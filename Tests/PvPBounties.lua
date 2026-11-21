-- Run: npm.cmd exec --yes --package=fengari-node-cli -- fengari Tests/PvPBounties.lua
local clock, timers = 1000, {}
time = function() return clock end
GetTime = time
GetUnitName = function() return 'Player Moon' end
UnitName = GetUnitName
UnitLevel = function() return 60 end
UnitExists = function() return false end
IsInInstance = function() return false, 'none' end
GetNumGuildMembers = function() return 2 end
GetGuildRosterInfo = function(i) return i == 1 and 'Player Moon' or 'Member Moon', 'Leader', 0 end
SlashCmdList = {}
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
CreateFrame = function()
    return { RegisterEvent = function() end, SetScript = function(self, event, callback) self[event] = callback end }
end
local function client()
    local gd = {}
    assert(loadfile('Core/Runtime.lua'))('GuildDB', gd)
    assert(loadfile('Features/PvP.lua'))('GuildDB', gd)
    assert(loadfile('Features/PvPBounties.lua'))('GuildDB', gd)
    gd.bucket, gd.guildName = {}, 'Test Guild'
    for key, factory in pairs(gd.bucketDefaults) do gd.bucket[key] = factory() end
    gd.bucket.pvpSeason = { name = 'Season 1', start = 900, ends = 2000 }
    function gd:RefreshUI() end
    return gd
end
local gd = client()
local function death(id, at, enemy, by)
    clock = at
    gd:RecordPvPBountyEvent('D', { id=id, ts=at, by=by or 'Member Moon', killer=enemy or 'Enemy Moon' }, true)
end
local function ownKill(at)
    clock = at
    for _, callback in ipairs(gd.eventHandlers.CHAT_MSG_COMBAT_HONOR_GAIN) do
        callback(nil, 'Enemy Moon dies, honorable kill (Estimated Honor Points: 10)')
    end
    local pending = timers; timers = {}
    for _, callback in ipairs(pending) do callback() end
end
local function score(client, name, allTime)
    local _, ranking = client:GetPvPLeaderboard(allTime)
    for _, row in ipairs(ranking) do if row.name == name then return row end end
end
death('d1', 1000)
death('d2', 1001)
assert(gd:GetPvPBounties()[1].status == 'WAIT' and gd:GetPvPBounties()[1].reward == 0)
death('d3', 1002)
assert(gd:GetPvPBounties()[1].reward == 3 and gd:GetPvPBounties()[1].status == 'OPEN', 'same member dying three times opens +3')
death('d4', 1003)
death('d5', 1004)
assert(gd:GetPvPBounties()[1].reward == 5)
for i=6,13 do death('d' .. i, 1000 + i) end
assert(gd:GetPvPBounties()[1].reward == 10, 'reward caps at +10 even above ten deaths')
ownKill(1020)
assert(score(gd, 'Player Moon', true).points == 11)
assert(score(gd, 'Player Moon', true).kills == 1 and score(gd, 'Player Moon', true).bountyPoints == 10)
gd.recordHandlers.P('group', 1021, 'Member Moon', 'Enemy Moon\n60\n1')
gd.recordHandlers.P('group', 1021, 'Member Moon', 'Enemy Moon\n60\n1')
assert(score(gd, 'Member Moon', true).points == 11, 'each credited member gets the full reward once')
gd.recordHandlers.P('repeat', 1022, 'Member Moon', 'Enemy Moon\n60\n1')
assert(score(gd, 'Member Moon', true).bountyPoints == 10, 'a second kill cannot double pay one member')
clock = 1031
gd.recordHandlers.P('late', 1031, 'Late Moon', 'Enemy Moon\n60\n1')
assert(score(gd, 'Late Moon', true).points == 1, 'credits outside the shared defeat window get no bonus')
assert(gd:GetPvPBounties()[1].status == 'PAID' and gd:GetPvPBounties()[1].deaths == 0)

-- Packets arriving in reverse order converge, including a previously offline peer.
local peer = client()
for _, provider in ipairs(gd.historyProviders) do provider.handler() end
for i=#gd.sendQueue,1,-1 do
    peer.eventFrame:OnEvent('CHAT_MSG_ADDON', peer.prefix, gd.sendQueue[i], 'GUILD', 'Player Moon')
end
for i=#gd.sendQueue,1,-1 do
    peer.eventFrame:OnEvent('CHAT_MSG_ADDON', peer.prefix, gd.sendQueue[i], 'GUILD', 'Player Moon')
end
assert(score(peer, 'Player Moon', true).points == 11)
assert(score(peer, 'Member Moon', true).bountyPoints == 10)
assert(score(peer, 'Late Moon', true).bountyPoints == nil)

-- New deaths build a fresh bounty, rather than reusing the original thirteen.
death('new1', 1990)
assert(gd:GetPvPBounties()[1].reward == 0 and gd:GetPvPBounties()[1].status == 'WAIT', 'a new counter cannot reuse the paid reward')
death('new2', 1991)
death('new3', 1992)
assert(gd:GetPvPBounties()[1].reward == 3)
ownKill(1999)
clock = 2001
gd.recordHandlers.P('after-cutoff', 2001, 'Member Moon', 'Enemy Moon\n60\n1')
assert(score(gd, 'Player Moon', true).bountyPoints == 13)
assert(score(gd, 'Member Moon', true).bountyPoints == 13)
assert(score(gd, 'Member Moon', false).bountyPoints == 10, 'season bonus uses each member kill timestamp')
assert(score(gd, 'Player Moon', true).kd == 2, 'bounty points never inflate K/D')

-- Event evidence and rewards survive the sixty-record feed limit and reload.
for i=1,65 do ownKill(2100 + i * 11) end
assert(#gd.bucket.pvpKills == 60)
local loaded = client(); loaded.bucket = gd.bucket
assert(score(loaded, 'Player Moon', true).bountyPoints == 13)
local fresh = client()
gd.sendQueue = {}
for _, provider in ipairs(gd.historyProviders) do provider.handler() end
for _, packet in ipairs(gd.sendQueue) do
    fresh.eventFrame:OnEvent('CHAT_MSG_ADDON', fresh.prefix, packet, 'GUILD', 'Player Moon')
end
assert(score(fresh, 'Player Moon', true).bountyPoints == 13, 'history sync preserves old awards after trimming')
assert(gd:DeletePvPSeason(900))
assert(score(gd, 'Player Moon', true).bountyPoints == 13, 'deleting a season preserves all-time bonuses')
local oldPackets = gd.sendQueue
assert(gd:WipePvPStats())
assert(next(gd.bucket.pvpBountyEvents) == nil and #gd:GetPvPBounties() == 0)
for _, packet in ipairs(oldPackets) do
    gd.eventFrame:OnEvent('CHAT_MSG_ADDON', gd.prefix, packet, 'GUILD', 'Player Moon')
end
assert(#gd:GetPvPBounties() == 0, 'old packets must not restore wiped bounties')
death('reset1', clock + 2)
death('reset2', clock + 2)
death('reset3', clock + 2)
assert(gd:GetPvPBounties()[1].reward == 3, 'fresh bounties work after a wipe')
print('PASS: +3/+5/+10 thresholds, same victim, full group bonuses, deduplication, late/reordered packets, seasons, K/D, history trimming, reload, sync and wipe')

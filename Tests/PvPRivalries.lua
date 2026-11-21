-- Run: npm.cmd exec --yes --package=fengari-node-cli -- fengari Tests/PvPRivalries.lua
local clock, player, timers = 1000, 'Player Moon', {}
time = function() return clock end
GetTime = time
GetUnitName = function() return player end
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
    gd.bucket, gd.guildName = {}, 'Test Guild'
    for key, factory in pairs(gd.bucketDefaults) do gd.bucket[key] = factory() end
    gd.bucket.pvpSeason = { name = 'Season 1', start = 900, ends = 2000 }
    function gd:RefreshUI() end
    return gd
end
local gd, peer = client(), client()
local function event(name, ...)
    for _, callback in ipairs(gd.eventHandlers[name] or {}) do callback(name, ...) end
end
local function kill(enemy)
    event('CHAT_MSG_COMBAT_HONOR_GAIN', enemy .. ' dies, honorable kill (Estimated Honor Points: 10)')
    local pending = timers; timers = {}
    for _, callback in ipairs(pending) do callback() end
    clock = clock + 1
end
local function transfer(source, target, history)
    local packets = history and source.historyQueue or source.sendQueue
    for _, packet in ipairs(packets) do
        target.eventFrame:OnEvent('CHAT_MSG_ADDON', target.prefix, packet, 'GUILD', player)
    end
end
-- Migration occurs before the next new kill, so it must count each event once.
gd.bucket.pvpKills = {{ id = 'old', ts = 950, by = player, victim = 'Enemy Moon', points = 1 }}
gd.bucket.pvpDeaths = {{ id = 'death', ts = 960, by = player, killer = 'Enemy Moon' }}
for _ = 1, 75 do kill('Enemy Moon') end
assert(#gd.bucket.pvpKills == 60, 'exercise actual history trimming')
local rivals = gd:GetPvPRivals(true)
assert(#rivals == 1 and rivals[1].kills == 76 and rivals[1].deaths == 1)
assert(rivals[1].kd == 76)
assert(gd:GetPvPRivals(false, 900)[1].kills == 76)
assert(gd:GetPvPLeaderboard(true).name == 'All-time')
transfer(gd, peer)
transfer(gd, peer)
assert(peer:GetPvPRivals(true)[1].kills == 76, 'replayed snapshots must not double counts')

-- A new client receives the cumulative totals from a relay, not only the feed.
gd.sendQueue = {}
for _, provider in ipairs(peer.historyProviders) do provider.handler() end
local newcomer = client()
transfer(peer, newcomer)
assert(newcomer:GetPvPRivals(true)[1].kills == 76, 'history relays must preserve trimmed encounters')

-- Name case coalesces; full realm identities remain separate.
kill('ENEMY MOON')
kill('Enemy Moon-OtherRealm')
kill('Other Enemy')
assert(#gd:GetPvPRivals(true) == 3)
assert(gd:GetPvPRivals(true)[1].kills == 77)
local last = clock - 1
gd.recordHandlers.PV('rival', clock, player, '0\n0\n0\n9\n' .. last .. '\nOther Enemy')
assert(gd:GetPvPRivals(true, nil, false, true)[1].name == 'Other Enemy', 'death sorting differs from kill sorting')
assert(gd:GetPvPRivals(true, nil, false, false)[1].name == 'Enemy Moon')
gd.recordHandlers.PV('rival', clock, 'Member Moon', '0\n0\n3\n4\n' .. last .. '\nEnemy Moon')
local board = gd:GetPvPRivals(true, nil, true, true)
assert(#board == 2 and board[1].name == 'Other Enemy', 'bounties exclude enemies with no guild kills')
assert(board[2].kills == 80 and board[2].deaths == 5, 'sum different members once per enemy')
assert(gd:GetPvPRivals(true)[1].kills == 77, 'personal results exclude other members')

-- An older client contributes recent events without cumulative snapshots.
gd.recordHandlers.X('legacy', clock, 'Member Moon', 'Legacy Enemy')
assert(#gd:GetPvPRivals(true, nil, true, true) == 3)
gd.bucket.pvpKills, gd.bucket.pvpDeaths = {}, {}
assert(gd:GetPvPRivals(true)[1].kills == 77, 'totals survive clearing recent history and reload')
local reloaded = client()
reloaded.bucket = gd.bucket
assert(reloaded:GetPvPRivals(true)[1].kills == 77)

-- Ended seasons stop gaining encounters while all-time continues.
clock = 2001
kill('Enemy Moon')
assert(gd:GetPvPRivals(false, 900)[1].kills == 77)
assert(gd:GetPvPRivals(true)[1].kills == 78)
assert(gd:DeletePvPSeason(900))
for _, row in pairs(gd.bucket.pvpRivalries) do assert(row.start ~= 900) end
gd.recordHandlers.PV('rival', clock, player, '0\n900\n99\n99\n1100\nEnemy Moon')
for _, row in pairs(gd.bucket.pvpRivalries) do assert(row.start ~= 900, 'deleted seasons reject stale snapshots') end
assert(gd:GetPvPRivals(true)[1].kills == 78, 'season deletion preserves all-time rivalries')
assert(gd:WipePvPStats())
assert(#gd:GetPvPRivals(true, nil, true, true) == 0)
gd.recordHandlers.PV('rival', clock, player, '0\n0\n999\n999\n1100\nEnemy Moon')
assert(next(gd.bucket.pvpRivalries) == nil, 'stale snapshots cannot resurrect wiped rivalries')
clock = clock + 2
kill('Fresh Enemy')
assert(gd:GetPvPRivals(true)[1].kills == 1, 'new encounters work after a reset')
print('PASS: rivalry migration, history cap, live/history sync, replay, identities, sorting, guild aggregation, seasons, reload, deletion and wipe')

-- Run: npm.cmd exec --yes --package=fengari-node-cli -- fengari Tests/PvPDeaths.lua
local clock, inside, dead = 1000, false, false
local ownGUID = 'Player-1-SELF'
local combatPayload
time = function() return clock end
GetTime = time
UnitGUID = function(unit) if unit == 'player' then return ownGUID end end
UnitIsDeadOrGhost = function() return dead end
GetUnitName = function() return 'Player Moon' end
UnitName = function() return 'Player' end
UnitExists = function() return false end
IsInInstance = function() return inside, inside and 'pvp' or 'none' end
GetGuildInfo = function() return 'Test Guild', 'Member', 3 end
CombatLogGetCurrentEventInfo = function() return table.unpack(combatPayload, 1, 15) end
C_Timer = {After = function() end}
SlashCmdList = {}
CreateFrame = function()
    return {
        RegisterEvent = function(self, event) self[event] = true end,
        IsEventRegistered = function(self, event) return self[event] == true end,
        SetScript = function(self, event, callback) self[event] = callback end,
    }
end
local function client()
    local gd = {}
    assert(loadfile('Core/Runtime.lua'))('GuildDB', gd)
    assert(loadfile('Features/PvP.lua'))('GuildDB', gd)
    assert(loadfile('Features/PvPBounties.lua'))('GuildDB', gd)
    gd.bucket = {}
    for key, factory in pairs(gd.bucketDefaults) do gd.bucket[key] = factory() end
    gd.bucket.pvpSeason = {name = 'Season 1', start = 900, ends = 2000}
    function gd:RefreshUI() end
    return gd
end
local GD, peer = client(), client()
local function event(name, ...)
    for _, callback in ipairs(GD.eventHandlers[name] or {}) do callback(name, ...) end
end
local function combat(kind, sourceGUID, sourceName, flags, destGUID)
    combatPayload = {clock, kind, false, sourceGUID, sourceName, flags or 0, 0,
        destGUID or ownGUID, 'Player Moon', 0, 0, 50, 0, 0, 50}
    event('COMBAT_LOG_EVENT_UNFILTERED')
end
local function revive()
    dead = false
    event('PLAYER_UNGHOST')
    clock = clock + 1
end
local function deathCount() return #GD.bucket.pvpDeaths end
assert(GD.eventRegistration.PLAYER_DEAD == 'registered')
assert(GD.eventRegistration.COMBAT_LOG_EVENT_UNFILTERED == 'registered')
combat('SWING_DAMAGE', 'Player-2-ENEMY', 'Enemy Moon')
dead = true
combat('UNIT_DIED')
event('PLAYER_DEAD')
assert(deathCount() == 1, 'combat log death and PLAYER_DEAD must count once')
assert(GD.bucket.pvpDeaths[1].killer == 'Enemy Moon')
assert(GD.bucket.pvpDeaths[1].by == 'Player Moon', 'use full character name')
assert(GD.bucket.pvpTotals['0|Player Moon'].deaths == 1, 'first death must not double count during migration')
assert(GD.bucket.pvpTotals['900|Player Moon'].deaths == 1, 'current season must include the death')
event('PLAYER_ALIVE') -- release to ghost
event('PLAYER_DEAD')
assert(deathCount() == 1, 'releasing must not count another death')
revive()
combat('SPELL_PERIODIC_DAMAGE', 'Player-2-ENEMY', 'Enemy Moon')
dead = true
event('PLAYER_DEAD')
assert(deathCount() == 2, 'death event must work without UNIT_DIED')
revive()
combat('SPELL_DAMAGE', 'Pet-2-ENEMY', 'Enemy Pet', 256)
dead = true
event('PLAYER_DEAD')
assert(deathCount() == 3, 'damage from player-controlled pets counts as PvP')
revive()
combat('SWING_DAMAGE', 'Creature-2-WOLF', 'Wolf')
event('PLAYER_DEAD')
assert(deathCount() == 3, 'PvE deaths must not count')
revive()
combat('ENVIRONMENTAL_DAMAGE', nil, nil)
event('PLAYER_DEAD')
assert(deathCount() == 3, 'environmental deaths without PvP damage must not count')
revive()
combat('SWING_DAMAGE', 'Player-2-ENEMY', 'Enemy Moon')
clock = clock + 31
event('PLAYER_DEAD')
assert(deathCount() == 3, 'old PvP damage must expire')
revive()
inside = true
combat('SWING_DAMAGE', 'Player-2-ENEMY', 'Enemy Moon')
event('PLAYER_DEAD')
assert(deathCount() == 3, 'instanced deaths must not count')
inside = false
revive()
combat('SWING_DAMAGE', 'Player-2-ENEMY', 'Enemy Moon', 0, 'Player-3-OTHER')
event('PLAYER_DEAD')
assert(deathCount() == 3, 'another player dying must not count as our death')
revive()
combat('SWING_DAMAGE', ownGUID, 'Player Moon')
event('PLAYER_DEAD')
assert(deathCount() == 3, 'self-inflicted damage is not PvP')
revive()
combat('SPELL_MISSED', 'Player-2-ENEMY', 'Enemy Moon')
event('PLAYER_DEAD')
assert(deathCount() == 3, 'missed attacks must not create damage evidence')
revive()
local combatAPI = CombatLogGetCurrentEventInfo
CombatLogGetCurrentEventInfo = function() error('protected combat log') end
event('COMBAT_LOG_EVENT_UNFILTERED')
CombatLogGetCurrentEventInfo = combatAPI
issecretvalue = function(value) return value == 'Player-2-ENEMY' end
combat('SWING_DAMAGE', 'Player-2-ENEMY', 'Enemy Moon')
issecretvalue = nil
event('PLAYER_DEAD')
assert(deathCount() == 3, 'protected values must be ignored safely')
revive()
combat('SWING_DAMAGE', 'Player-2-ENEMY', 'Enemy Moon')
event('PLAYER_ENTERING_WORLD')
event('PLAYER_DEAD')
assert(deathCount() == 3, 'zone changes must clear previous PvP combat')
revive()
clock = 2100
combat('SWING_DAMAGE', 'Player-2-ENEMY', 'Enemy Moon')
event('PLAYER_DEAD')
assert(deathCount() == 4)
assert(GD.bucket.pvpTotals['0|Player Moon'].deaths == 4)
assert(GD.bucket.pvpTotals['900|Player Moon'].deaths == 3, 'ended seasons must not gain deaths')

-- Exercise real chunked transport for both death records and cumulative totals.
local packets = GD.sendQueue
for _, packet in ipairs(packets) do
    peer.eventFrame:OnEvent('CHAT_MSG_ADDON', peer.prefix, packet, 'GUILD', 'Player Moon')
end
assert(#peer.bucket.pvpDeaths == 4, 'guild peers must receive death records')
assert(peer.bucket.pvpTotals['0|Player Moon'].deaths == 4, 'guild peers must receive death totals')
for _, packet in ipairs(packets) do
    peer.eventFrame:OnEvent('CHAT_MSG_ADDON', peer.prefix, packet, 'GUILD', 'Player Moon')
end
assert(#peer.bucket.pvpDeaths == 4, 'replayed history must not duplicate deaths')
GD.bucket.pvpTotals['0|Player Moon'].kills = 10
local function rivalDeaths(client, allTime)
    local total = 0
    for _, row in ipairs(client:GetPvPRivals(allTime)) do total = total + row.deaths end
    return total
end
assert(rivalDeaths(GD, true) == 4 and rivalDeaths(peer, true) == 4, 'actual PvP deaths must update and sync rivalries once per life')
assert(rivalDeaths(GD, false) == 3, 'rivalry deaths stop at the season cutoff')
local bountyDeaths = 0
for _, event in pairs(GD.bucket.pvpBountyEvents) do
    if event.kind == 'D' then bountyDeaths = bountyDeaths + 1 end
end
assert(bountyDeaths == 4, 'only eligible outdoor deaths must enter the bounty ledger, once per life')
local _, _, score = GD:GetPvPLeaderboard(true)
assert(score.kd == 2.5, 'K/D must use cumulative totals')
GD.bucket.pvpTotals['0|Player Moon'].deaths = 0
_, _, score = GD:GetPvPLeaderboard(true)
assert(score.kd == 10, 'zero deaths must not divide by zero')
GD.bucket.pvpTotals['0|Player Moon'].kills = 0
_, _, score = GD:GetPvPLeaderboard(true)
assert(score.kd == 0, 'zero kills/deaths must be zero')
print('PASS: PvP deaths, deduplication, pets, resurrection, PvE/instance exclusions, protected APIs, seasons, guild sync, and K/D ratios')

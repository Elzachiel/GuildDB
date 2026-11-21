-- Run: npm.cmd exec --yes --package=fengari-node-cli -- fengari Tests/PvPRepeatKills.lua
local GD = { bucket = {}, maxItems = 60 }
local events, timers = {}, {}
local clock, inside = 1000, false
function GD:RegisterBucket(key, factory) self.bucket[key] = factory() end
function GD:RegisterRecordHandler() end
function GD:RegisterHistoryProvider() end
function GD:RegisterCommand() end
function GD:RegisterTab() end
function GD:RegisterEventHandler(event, callback) events[event] = callback end
function GD:PlayerName() return 'Player Moon' end
function GD:SendRecord() end
function GD:NewRecord(record) record.by = self:PlayerName(); record.ts = clock; return record end
function GD:StoreRecord(key, record) table.insert(self.bucket[key], record) end
time = function() return clock end
GetTime = time
UnitLevel = function() return 60 end
UnitExists = function() return false end
IsInInstance = function() return inside, inside and 'pvp' or 'none' end
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
-- Existing capped history must have no effect after updating.
GDB = { pvpHistory = { ['playermoon|enemymoon'] = { 999, 999, 999, 999, 999 } } }
assert(loadfile('Features/PvP.lua'))('GuildDB', GD)
GD.bucket.pvpSeason = { start = 900, ends = 2000 }
local function resolve()
    local queued = timers
    timers = {}
    for _, callback in ipairs(queued) do callback() end
end
for index = 1, 12 do
    events.CHAT_MSG_COMBAT_HONOR_GAIN(nil, 'Enemy Moon dies, honorable kill (Estimated Honor Points: 10)')
    -- The matching counter event describes this same kill, not a second kill.
    events.PLAYER_PVP_KILLS_CHANGED(nil, 'player')
    resolve()
    assert(#GD.bucket.pvpKills == index, 'each repeat kill counts once, even within a minute or after five kills')
    clock = clock + 1
end
assert(GD.bucket.pvpTotals['0|Player Moon'].kills == 12)
assert(GD.bucket.pvpTotals['900|Player Moon'].kills == 12)
inside = true
events.CHAT_MSG_COMBAT_HONOR_GAIN(nil, 'Enemy Moon dies, honorable kill (Estimated Honor Points: 10)')
resolve()
assert(#GD.bucket.pvpKills == 12, 'instance exclusions remain')
print('PASS: 12 repeat kills in 12 seconds, old cap history ignored, honor/counter deduplication, all-time and season totals, instance exclusion')

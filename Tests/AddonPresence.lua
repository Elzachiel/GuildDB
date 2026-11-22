-- Run: npm.cmd exec --yes --package=fengari-node-cli -- fengari Tests/AddonPresence.lua
local clock, player, inGuild, guildName = 1000, 'Alt Moon', true, 'Test Guild'
local timers, sent, rosterRequests = {}, {}, 0
GetTime = function() return clock end
time = function() return clock end
GetUnitName = function() return player end
UnitName = function() return 'Alt' end
IsInGuild = function() return inGuild end
GetGuildInfo = function() return guildName end
UnitFactionGroup = function() return 'Alliance' end
GuildRoster = function() rosterRequests = rosterRequests + 1 end
SlashCmdList = {}
C_Timer = {After = function(delay, callback)
    timers[#timers + 1] = {at = clock + delay, callback = callback}
end}
SendAddonMessage = function(_, message) sent[#sent + 1] = message end
CreateFrame = function()
    return {
        RegisterEvent = function() end,
        SetScript = function(self, event, callback) self[event] = callback end,
    }
end
local function client()
    timers, sent = {}, {}
    local gd = {}
    assert(loadfile('Core/Runtime.lua'))('GuildDB', gd)
    gd.eventFrame:OnEvent('ADDON_LOADED', 'GuildDB')
    gd.syncCount = 0
    function gd:RequestSync() self.syncCount = self.syncCount + 1 end
    return gd
end
local function tick(gd, seconds)
    clock = clock + (seconds or 0)
    gd.eventFrame:OnUpdate(seconds or 0)
    local ready = timers
    timers = {}
    for _, timer in ipairs(ready) do
        if timer.at <= clock then timer.callback()
        else timers[#timers + 1] = timer end
    end
end
local function receive(gd, sender, payload)
    gd.eventFrame:OnEvent('CHAT_MSG_ADDON', gd.prefix, 'C|test|1|1|' .. payload, 'GUILD', sender)
end
local function heartbeat(message)
    return message and message:match('|H|' .. '([%w%.%-]+)$')
end
local function heartbeatCount()
    local count = 0
    for _, message in ipairs(sent) do if heartbeat(message) then count = count + 1 end end
    return count
end
local function settle(gd)
    tick(gd, 30)
    for _ = 1, 8 do tick(gd, 0.2) end
end

local gd = client()
gd.eventFrame:OnEvent('PLAYER_LOGIN')
assert(gd:GetAddonVersion('Alt Moon-Realm') == gd.version, 'recognize the current alt before a guild echo')
assert(gd:GetAddonVersion('Main Moon') == nil, 'do not attribute an alt installation to another character')
tick(gd)
assert(heartbeat(sent[1]) == gd.version, 'announce on login')
settle(gd) -- finish automatic startup discovery retries and drain identity packets
local announcements = heartbeatCount()
receive(gd, 'New Moon', 'H|0.2.13')
assert(gd:GetAddonVersion('New Moon') == '0.2.13', 'detect a newcomer immediately')
tick(gd, 3)
assert(heartbeatCount() == announcements + 1, 'announce back so a newcomer discovers us promptly')
announcements = heartbeatCount()
receive(gd, 'New Moon', 'H|0.2.13')
tick(gd, 3)
assert(heartbeatCount() == announcements, 'known peer heartbeats must not create a reply loop')
receive(gd, 'Other Alt', 'O|sync-id|0.2.12')
assert(gd:GetAddonVersion('Other Alt') == '0.2.12', 'sync offers also identify addon users')
tick(gd, 3)
assert(heartbeatCount() == announcements + 1, 'new sync responders also discover us')
gd:Enqueue('P|queued-record')
gd.nextPresence = 0
tick(gd, 2)
assert(heartbeat(sent[#sent]), 'presence must send ahead of queued records')
tick(gd, 151)
assert(gd:GetAddonVersion('New Moon') == nil, 'remote presence must still expire')
assert(gd:GetAddonVersion('Alt Moon') == gd.version, 'local installation never relies on an expiring echo')

-- Guild metadata can arrive after login with no follow-up guild event.
guildName = nil
gd = client()
gd.eventFrame:OnEvent('PLAYER_LOGIN')
assert(not gd.bucket, 'wait for guild metadata')
tick(gd, 12)
assert(gd.syncCount == 0)
guildName = 'Test Guild'
tick(gd, 2)
assert(gd.bucket and heartbeat(sent[1]), 'recover and announce when guild metadata becomes ready')
tick(gd, 10)
assert(gd.syncCount == 1, 'sync once after delayed guild initialization')
gd.eventFrame:OnEvent('GUILD_ROSTER_UPDATE')
tick(gd, 10)
assert(gd.syncCount == 1, 'routine roster events must not restart sync')

-- Joining a guild after login must initialize discovery and history too.
inGuild, guildName = false, nil
gd = client()
gd.eventFrame:OnEvent('PLAYER_LOGIN')
inGuild, guildName = true, 'New Guild'
gd.eventFrame:OnEvent('PLAYER_GUILD_UPDATE', 'player')
tick(gd)
assert(gd.bucket and heartbeat(sent[1]), 'announce immediately after joining')
inGuild, guildName = false, nil
gd.eventFrame:OnEvent('PLAYER_GUILD_UPDATE', 'player')
tick(gd, 10)
assert(gd.syncCount == 0, 'cancel delayed sync after leaving')
assert(gd:GetAddonVersion('Alt Moon') == nil, 'clear guild presence on departure')

-- An early guild packet can initialize the bucket before a roster event.
inGuild, guildName = true, nil
gd = client()
gd.eventFrame:OnEvent('PLAYER_LOGIN')
guildName = 'Test Guild'
receive(gd, 'Early Moon', 'H|0.2.13')
assert(gd:GetAddonVersion('Early Moon') == '0.2.13', 'keep the first packet when guild metadata becomes ready')
assert(rosterRequests > 0)
print('PASS: alt detection, peer discovery, delayed guild startup, guild joins, and heartbeat priority')

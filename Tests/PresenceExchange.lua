-- Run: npm.cmd exec --yes --package=fengari-node-cli -- fengari Tests/PresenceExchange.lua
-- Two real runtime instances exchange messages with shortened Forever senders.
local clock, active, network, clients = 1000, nil, {}, {}
SlashCmdList = {}
time = function() return math.floor(clock) end
GetTime = function() return clock end
GetUnitName = function() return active.shortNameOnly and active.name:match('^(%S+)') or active.name end
UnitName = function() return active.name:match('^(%S+)') end
IsInGuild = function() return active.inGuild end
GetGuildInfo = function() return active.inGuild and 'Test Guild' or nil end
UnitFactionGroup = function() return 'Alliance' end
GuildRoster = function() end
GetNumGuildMembers = function() return #clients end
GetGuildRosterInfo = function(index) return clients[index].name, 'Member', 3 end
C_Timer = {After = function(delay, callback)
    active.timers[#active.timers + 1] = {at = clock + delay, callback = callback}
end}
C_ChatInfo = {
    RegisterAddonMessagePrefix = function()
        if clock < active.readyAt then return false end
        active.registered = true
        return true
    end,
    InChatMessagingLockdown = function() return active.locked end,
    SendAddonMessage = function(prefix, message, channel)
        if active.failSend then return 11 end
        active.sent = active.sent + 1
        -- Reproduce a client silently dropping its startup messages.
        if clock < active.readyAt then return nil end
        network[#network + 1] = {prefix, message, channel, active.name:match('^(%S+)')}
        return nil
    end,
}
CreateFrame = function() return {
    RegisterEvent = function() end,
    SetScript = function(self, event, callback) self[event] = callback end,
} end
local function client(name, delay)
    local peer = {name = name, inGuild = true, readyAt = clock + (delay or 0), timers = {}, sent = 0}
    active = peer
    local gd = {}
    peer.gd = gd
    assert(loadfile('Core/Runtime.lua'))('GuildDB', gd)
    gd.eventFrame:OnEvent('ADDON_LOADED', 'GuildDB')
    function gd:RequestSync() end -- history is independent of presence discovery
    function gd:RefreshUI() end
    gd.frame = {Show = function() end}
    gd.eventFrame:OnEvent('PLAYER_LOGIN')
    clients[#clients + 1] = peer
    return peer
end
local function run(seconds)
    for _ = 1, math.ceil(seconds * 10) do
        clock = clock + 0.1
        for _, peer in ipairs(clients) do
            active = peer
            local pending = peer.timers
            peer.timers = {}
            for _, timer in ipairs(pending) do
                if timer.at <= clock then timer.callback()
                else peer.timers[#peer.timers + 1] = timer end
            end
            peer.gd.eventFrame:OnUpdate(0.1)
        end
        local messages = network
        network = {}
        for _, message in ipairs(messages) do
            for _, peer in ipairs(clients) do
                if peer.registered then
                    active = peer
                    peer.gd.eventFrame:OnEvent('CHAT_MSG_ADDON', table.unpack(message))
                end
            end
        end
    end
end
local observer = client('Observer Moon')
run(30)
local newcomer = client('Newcomer Star', 5)
newcomer.shortNameOnly = true
newcomer.gd.version = '0.2.16'
run(13)
assert(newcomer.registered, 'startup discovery must retry failed prefix registration without another world event')
active = observer
assert(observer.gd:GetAddonVersion('Newcomer Star') == newcomer.gd.version,
    'other members must detect the new character after silent startup drops and shortened senders')
active = newcomer
assert(newcomer.gd:GetAddonVersion('Observer Moon') == observer.gd.version, 'new characters must discover existing peers')
assert(newcomer.gd:GetAddonVersion('Newcomer Star') == newcomer.gd.version, 'resolve own full name even when unit getters shorten it')

-- An existing cache must still answer an explicit request after a peer reloads.
active = observer
observer.gd.addonPresence = {}
observer.gd:Open()
run(3)
active = observer
assert(observer.gd:GetAddonVersion('Newcomer Star') == newcomer.gd.version, 'opening the addon actively refreshes versions')
local before = #observer.gd.sendQueue
observer.gd:Open()
observer.gd:Open()
assert(#observer.gd.sendQueue == before, 'repeated window opens must coalesce requests')

active = newcomer
newcomer.gd.version = '0.2.17'
newcomer.gd:Open()
run(4)
active = observer
assert(observer.gd:GetAddonVersion('Newcomer Star') == '0.2.17', 'an updated peer must replace its previously reported version')

run(30)
local sentBefore = observer.sent + newcomer.sent
run(5)
assert(observer.sent + newcomer.sent == sentBefore, 'discovery replies must settle without ping-pong')

-- Transport failure retains the announcement for retry instead of losing it.
active = newcomer
newcomer.failSend = true
newcomer.gd:RequestPresence()
run(1)
assert(#newcomer.gd.sendQueue > 0 and not newcomer.gd.lastAddonSend.succeeded)
newcomer.failSend = false
run(6)
active = observer
assert(observer.gd:GetAddonVersion('Newcomer Star') == newcomer.gd.version)

-- Preserve legacy chunked and raw announcements without identifying an unrelated alt.
observer.gd.eventFrame:OnEvent('CHAT_MSG_ADDON', 'GDB', 'H|0.2.13', 'GUILD', 'Legacy Moon')
assert(observer.gd:GetAddonVersion('Legacy Moon') == '0.2.13')
observer.gd.eventFrame:OnEvent('CHAT_MSG_ADDON', 'GDB', 'C|legacy|1|1|H|0.2.14', 'GUILD', 'Legacy Moon')
assert(observer.gd:GetAddonVersion('Legacy Moon') == '0.2.14')
observer.gd.eventFrame:OnEvent('CHAT_MSG_ADDON', 'GDB', 'V|0.2.17|Unrelated Moon|0', 'GUILD', 'Someone')
assert(observer.gd:GetAddonVersion('Unrelated Moon') == nil, 'unrelated advertised names must not replace sender identity')

-- Joining after the addon has loaded follows the same automatic discovery path.
local joined = client('Joined Moon')
joined.inGuild = false
joined.gd.eventFrame:OnEvent('PLAYER_GUILD_UPDATE', 'player')
run(2)
active = joined
joined.inGuild = true
joined.gd.eventFrame:OnEvent('PLAYER_GUILD_UPDATE', 'player')
run(4)
active = observer
assert(observer.gd:GetAddonVersion('Joined Moon') == joined.gd.version, 'existing members must discover a new guild join automatically')

active = newcomer
newcomer.locked = true
local count = newcomer.sent
newcomer.gd:RequestPresence()
run(1)
assert(newcomer.sent == count and #newcomer.gd.sendQueue > 0, 'keep announcements queued during messaging lockdown')
newcomer.locked = false
run(4)
assert(newcomer.sent > count, 'send queued discovery after messaging unlocks')
print('PASS: real peer exchange, shortened names, silent startup drops, prefix retry, window discovery, legacy messages, and send retries')

-- Shared lifecycle, saved data, slash routing, and guild addon-message transport.
local ADDON, GD = ...
_G.GuildDB = GD

GD.version = "0.2.65"
-- New-member tracking begins with this release; keep this anchor on later bumps.
GD.recentJoinsVersion = "0.1.88"
GD.recentJoinsStart = 1795285809
GD.prefix = "GDB"
GD.maxItems = 60
GD.tabs = { "Home", "Roster" }
GD.activeTab = "Home"
GD.bucketDefaults = {}
GD.recordHandlers = {}
GD.recordLimits = {}
GD.historyProviders = {}
GD.eventHandlers = {}
GD.commands = {}
GD.fragments = {}
GD.sendQueue = {}
GD.liveQueue = {}
GD.historyQueue = {}
GD.nextSend = 0
GD.sendTokens = 8
GD.sendTokenAt = 0
GD.nextPresence = 0
GD.nextPresenceCleanup = 0
GD.addonPresence = {}
GD.syncRequests = {}
GD.syncOffers = {}
GD.syncServed = {}

local chatPrefix = "|cffb19cffGuildDB:|r "

function GD:PrintWelcome()
    if self.welcomeShown then return end
    self.welcomeShown = true
    print(chatPrefix .. "Ready. Type |cffffd100/gd|r to open. |cffaaaaaav" .. self.version .. "|r")
end

function GD:Encode(value)
    return (tostring(value or ""):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("\r", "%%0D"):gsub("\n", "%%0A"))
end

function GD:Decode(value)
    return (tostring(value or ""):gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

function GD:Enqueue(payload, lowPriority, urgent)
    local live = urgent and not lowPriority and payload:match("^DK[URJN]|")
    if live then
        self.liveQueue = self.liveQueue or {}
        -- Short live auction records need no fragment envelope. All clients
        -- already accept complete record payloads on the normal guild prefix.
        if #payload <= 255 then self.liveQueue[#self.liveQueue + 1] = payload; return end
    end
    local id = tostring(time()) .. tostring(math.random(1000, 999999))
    local size = 180
    local total = math.max(1, math.ceil(#payload / size))
    local queue = live and self.liveQueue or lowPriority and GD.historyQueue or GD.sendQueue
    for i = 1, total do
        local chunk = table.concat({ "C", id, i, total, payload:sub((i - 1) * size + 1, i * size) }, "|")
        if urgent and not live then table.insert(queue, i, chunk) else queue[#queue + 1] = chunk end
    end
end

function GD:SendRecord(kind, id, timestamp, author, content, urgent)
    self:Enqueue(table.concat({ kind, self:Encode(id), timestamp, self:Encode(author), self:Encode(content) }, "|"), self.historySyncing, urgent)
end

function GD:GetAddonSendQueue()
    local live = self.liveQueue and #self.liveQueue > 0
    return live and self.liveQueue or #self.sendQueue > 0 and self.sendQueue or self.historyQueue, live and 1 or 3
end

function GD:NewRecord(values)
    values.id = tostring(time()) .. "-" .. tostring(math.random(100000, 999999))
    values.ts = time()
    values.by = self:PlayerName()
    return values
end

-- WoW Forever character names can contain two parts. UnitName may only return
-- the first part, which cannot be matched reliably against guild roster names.
function GD:PlayerName()
    local fullName = GetUnitName and GetUnitName("player", false)
    if type(fullName) == "string" and fullName ~= "" then return fullName end
    return UnitName and UnitName("player") or "Guild member"
end

function GD:StoreRecord(bucketKey, record, kind, content)
    if not self.bucket then return end
    local list = self.bucket[bucketKey]
    for _, existing in ipairs(list) do
        if existing.id == record.id then return end
    end
    table.insert(list, 1, record)
    while #list > self.maxItems do table.remove(list) end
    if kind then self:SendRecord(kind, record.id, record.ts, record.by, content or "") end
    if self.RefreshUI then self:RefreshUI() end
end

function GD:RegisterBucket(key, defaultValue)
    self.bucketDefaults[key] = defaultValue
end

GD:RegisterBucket("addonUsers", function() return {} end)

function GD:RememberAddonVersion(name, version)
    if not self.bucket then return end
    self.bucket.addonUsers = self.bucket.addonUsers or {}
    local key = (tostring(name or ""):match("^([^-]+)") or ""):lower():gsub("[%s%-]", "")
    if key == "" then return end
    local record = self.bucket.addonUsers[key] or {}
    record.name, record.version, record.lastSeen = name, version, time()
    self.bucket.addonUsers[key] = record
end

function GD:RegisterRecordHandler(kind, handler, contentLimit)
    self.recordHandlers[kind] = handler
    self.recordLimits[kind] = contentLimit or 1200
end

function GD:RegisterHistoryProvider(handler, responderOnly)
    self.historyProviders[#self.historyProviders + 1] = {
        handler = handler,
        responderOnly = responderOnly ~= false,
    }
end

function GD:RegisterEventHandler(event, handler)
    self.eventHandlers[event] = self.eventHandlers[event] or {}
    self.eventHandlers[event][#self.eventHandlers[event] + 1] = handler
end

function GD:RegisterCommand(command, handler)
    self.commands[command] = handler
end

function GD:RegisterTab(name, renderer)
    self.views = self.views or {}
    local listed = false
    for _, tab in ipairs(self.tabs) do if tab == name then listed = true; break end end
    if not listed then self.tabs[#self.tabs + 1] = name end
    self.views[name] = renderer
end

function GD:Display(value)
    if value == "Windshaper Skyborne" then value = "Skyborne" end
    local displayed = tostring(value or ""):gsub("|", "||")
    return displayed
end

function GD:CanManage()
    if not self.guildName or not GetGuildInfo then return false end
    local _, _, rank = GetGuildInfo("player")
    return rank == 0 or rank == 1
end

local function peerNameKey(name)
    name = tostring(name or "")
    name = name:match("^([^-]+)") or name
    return name:lower():gsub("[%s%-]", "")
end

local registerPrefix

function GD:PresenceName()
    local name = self:PlayerName()
    if not GetNumGuildMembers or not GetGuildRosterInfo then return name end
    local wanted, candidate = peerNameKey(name), nil
    for index = 1, GetNumGuildMembers(true) do
        local rosterName = GetGuildRosterInfo(index)
        if rosterName then
            if peerNameKey(rosterName) == wanted then return rosterName end
            if peerNameKey(rosterName:match("^(%S+)")) == wanted then
                if candidate then return name end -- a shared first name is ambiguous
                candidate = rosterName
            end
        end
    end
    return candidate or name
end

function GD:GetLiveAddonVersion(name)
    if not name then return nil end
    local wanted = peerNameKey(name)
    if self.bucket and wanted == peerNameKey(self:PresenceName()) then return self.version end
    local now = GetTime and GetTime() or 0
    local latest
    for sender, status in pairs(self.addonPresence or {}) do
        if peerNameKey(sender) == wanted and now - (status.seen or 0) <= 150
            and (not latest or status.seen > latest.seen) then latest = status end
    end
    return latest and latest.version
end

function GD:GetAddonVersion(name)
    if not name then return nil end
    local live = self:GetLiveAddonVersion(name)
    if live then return live end
    local record = self.bucket and self.bucket.addonUsers and self.bucket.addonUsers[peerNameKey(name)]
    return record and record.version
end

function GD:RequestPresence()
    if not self.bucket then return false end
    local now = GetTime and GetTime() or 0
    if self.lastPresenceRequest and now - self.lastPresenceRequest < 3 then return false end
    if registerPrefix then registerPrefix() end
    self.lastPresenceRequest = now
    self.presenceRequestPending = true
    self.nextPresence = 0
    return true
end

local function cleanupPresence(now)
    if now < GD.nextPresenceCleanup then return end
    GD.nextPresenceCleanup = now + 30
    local changed = false
    for sender, status in pairs(GD.addonPresence) do
        if now - (status.seen or 0) > 150 then
            GD.addonPresence[sender] = nil
            changed = true
        end
    end
    if changed and GD.RefreshUI then GD:RefreshUI() end
end

local function guildKey(name, faction)
    return (name or ""):upper() .. "@" .. (faction or "Neutral")
end

local function ensureBucket()
    if not IsInGuild or not IsInGuild() then
        GD.guildName, GD.bucket = nil, nil
        GD.guildKey, GD.addonPresence, GD.guildSession = nil, {}, nil
        GD.lastPresenceRequest, GD.presenceRequestPending = nil, nil
        GD.roster = {}
        if GD.RefreshUI then GD:RefreshUI() end
        return false
    end
    local name = GetGuildInfo and GetGuildInfo("player")
    if not name or name == "" then return false end
    GD.guildName = name
    local faction = UnitFactionGroup and UnitFactionGroup("player") or "Neutral"
    local key = guildKey(name, faction)
    local changedGuild = GD.guildKey ~= key
    if changedGuild then GD.addonPresence = {} end
    GD.guildKey = key
    GDB.guilds[key] = GDB.guilds[key] or {}
    GD.bucket = GDB.guilds[key]
    for bucketKey, defaultValue in pairs(GD.bucketDefaults) do
        if type(GD.bucket[bucketKey]) ~= "table" then GD.bucket[bucketKey] = defaultValue() end
    end
    GD:RememberAddonVersion(GD:PresenceName(), GD.version)
    if changedGuild then
        GD.nextPresence = 0
        GD.lastPresenceRequest = nil
        GD:RequestPresence()
        local session = {}
        GD.guildSession = session
        -- Login and guild joins can silently drop the first guild packet.
        -- Retry discovery after the client has finished entering the world.
        for _, delay in ipairs({3, 10, 25}) do
            C_Timer.After(delay, function()
                if GD.bucket and GD.guildSession == session then GD:RequestPresence() end
            end)
        end
        C_Timer.After(10, function()
            if GD.bucket and GD.guildSession == session then GD:RequestSync() end
        end)
    end
    if GD.RefreshUI then GD:RefreshUI() end
    return true
end

local function sendRaw(message)
    local send
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        send = C_ChatInfo.SendAddonMessage
    elseif SendAddonMessage then
        send = SendAddonMessage
    end
    if not send then return false end
    local ok, result = pcall(send, GD.prefix, message, "GUILD")
    local body = message:match("^C|[^|]+|%d+|%d+|(.*)$") or message
    GD.lastAddonSend = {
        kind = body:match("^([^|]+)|") or body,
        result = result,
        succeeded = ok and (result == nil or result == true or result == 0),
        at = GetTime and GetTime() or 0,
        error = not ok and tostring(result) or nil,
    }
    GD.lastAddonSendByKind = GD.lastAddonSendByKind or {}
    GD.lastAddonSendByKind[GD.lastAddonSend.kind] = GD.lastAddonSend
    return ok and (result == nil or result == true or result == 0)
end

local function isChatMessagingLocked()
    if not (C_ChatInfo and C_ChatInfo.InChatMessagingLockdown) then return false end
    local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
    return ok and locked == true
end

registerPrefix = function()
    local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
    if not register then GD.prefixRegistration = "not required"; return end
    local ok, result = pcall(register, GD.prefix)
    GD.prefixRegistration = ok and result ~= false and "registered" or ("failed: " .. tostring(result))
end

local function requestGuildRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

local function parseRecord(payload, sender)
    local kind, id, timestamp, author, content = payload:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|(.*)$")
    if not kind or not id or not timestamp or not author then return end
    id, author, content = GD:Decode(id), GD:Decode(author), GD:Decode(content)
    timestamp = tonumber(timestamp)
    if not timestamp or #id > 100 or #author > 100 or #content > (GD.recordLimits[kind] or 1200) then return end
    local handler = GD.recordHandlers[kind]
    if handler then handler(id, timestamp, author, content, sender) end
end

local function sendHistory(requestId, requester)
    if not GD.bucket then return end
    local responder = GD.IsSyncResponder and GD:IsSyncResponder(requester)
    for _, provider in ipairs(GD.historyProviders) do
        if requestId or not provider.responderOnly or responder then
            GD.historySyncing = true
            local ok, err = pcall(provider.handler)
            GD.historySyncing = false
            if not ok then print("GuildDB sync error: " .. tostring(err)) end
        end
    end
    if requestId then GD:Enqueue("K|" .. requestId, true) end
end

local function after(seconds, callback)
    if C_Timer and C_Timer.After then C_Timer.After(seconds, callback) else callback() end
end

local function baseName(name)
    return (tostring(name or ""):match("^([^-]+)") or tostring(name or "")):lower():gsub("[%s%-]", "")
end

local function samePlayer(a, b)
    local left, right = baseName(a), baseName(b)
    return left ~= "" and left == right
end

local function localPlayerName()
    return GD:PlayerName()
end

local function newSyncId()
    return tostring(time()) .. "-" .. tostring(math.random(100000, 999999))
end

local function retrySync(request)
    if request.done or request.rounds >= 3 then return end
    request.rounds = request.rounds + 1
    local id = newSyncId()
    request.id, request.selected = id, nil
    GD.syncRequests[id] = request
    GD:Enqueue("Q|" .. id)
    after(8, function()
        if GD.syncRequests[id] ~= request or request.done then return end
        if request.selected then
            after(300, function()
                if GD.syncRequests[id] == request and not request.done then
                    GD.syncRequests[id] = nil
                    retrySync(request)
                end
            end)
        else
            GD.syncRequests[id] = nil
            retrySync(request)
        end
    end)
end

local function receiveSyncOffer(id, sender)
    local offer = GD.syncOffers[id]
    if offer then GD.syncOffers[id] = nil end -- first offer wins; others stand down
    local request = GD.syncRequests[id]
    if not request or request.done or request.selected then return end
    request.selected = sender
    GD:Enqueue("R|" .. id .. "|" .. GD:Encode(sender))
end

local function receiveSyncRequest(id, sender)
    if samePlayer(sender, localPlayerName()) or GD.syncOffers[id] then return end
    local offer = {}
    GD.syncOffers[id] = offer
    after(0.4 + math.random() * 2.5, function()
        if GD.syncOffers[id] ~= offer then return end
        GD.syncOffers[id] = nil
        GD:Enqueue("O|" .. id .. "|" .. GD.version)
    end)
end

local function receiveSyncGrant(id, target)
    if not samePlayer(target, localPlayerName()) or GD.syncServed[id] then return end
    GD.syncServed[id] = true
    sendHistory(id)
end

local function receiveSyncComplete(id, sender)
    local request = GD.syncRequests[id]
    if not request or request.done or not request.selected or not samePlayer(request.selected, sender) then return end
    request.done = true
    GD.syncRequests[id] = nil
end

local function recordPresence(sender, version, character)
    if not sender or #sender > 100 or not version or #version > 32 then return end
    -- Forever may supply only the first part of a two-part character name as
    -- the chat sender. New presence packets carry the complete character name.
    if character and #character > 0 and #character <= 100 then
        local full, source = peerNameKey(character), peerNameKey(sender)
        local first = peerNameKey(character:match("^(%S+)") or character)
        if full == source or first == source then sender = character end
    end
    local now = GetTime and GetTime() or 0
    local known = GD:GetLiveAddonVersion(sender)
    GD.addonPresence[sender] = { version = version, seen = now }
    GD:RememberAddonVersion(sender, version)
    GD.lastPresenceName = sender
    if not known and not samePlayer(sender, GD:PresenceName()) then
        if GD.RequestFeatureSettings then GD:RequestFeatureSettings() end
        -- A new login/join needs to discover existing peers too. Coalesce
        -- replies and jitter them so guild members do not all send at once.
        GD.nextPresence = math.min(GD.nextPresence, now + 0.2 + math.random() * 2)
    end
    if GD.RefreshUI then GD:RefreshUI() end
end

local function receivePayload(payload, sender)
    local version, character, request = payload:match("^V|([%w%.%-]+)|([^|]+)|([01])$")
    if version then
        character = GD:Decode(character)
        recordPresence(sender, version, character)
        if request == "1" and not samePlayer(character, GD:PresenceName()) then
            -- Replies use request=0, so discovery cannot create a reply loop.
            local now = GetTime and GetTime() or 0
            local replyAt = math.max(now + 0.2 + math.random() * 2, (GD.lastPresenceAnnouncement or 0) + 3)
            GD.nextPresence = math.min(GD.nextPresence, replyAt)
        end
        return
    end
    if payload == "Q" then
        -- Compatibility with clients that still use the original request packet.
        if not samePlayer(sender, localPlayerName()) then sendHistory(nil, sender) end
    else
        local requestId = payload:match("^Q|([^|]+)$")
        local offerId, offerVersion = payload:match("^O|([^|]+)|([%w%.%-]+)$")
        offerId = offerId or payload:match("^O|([^|]+)$")
        local grantId, target = payload:match("^R|([^|]+)|([^|]+)$")
        local completeId = payload:match("^K|([^|]+)$")
        if requestId then receiveSyncRequest(requestId, sender); return end
        if offerId then
            recordPresence(sender, offerVersion)
            receiveSyncOffer(offerId, sender)
            return
        end
        if grantId then receiveSyncGrant(grantId, GD:Decode(target)); return end
        if completeId then receiveSyncComplete(completeId, sender); return end
        local version = payload:match("^H|([%w%.%-]+)$")
        if version and #version <= 32 and sender and #sender <= 100 then
            recordPresence(sender, version)
        else
            if payload:match("^ML|") then
                GD.mapInboundPackets = (GD.mapInboundPackets or 0) + 1
                GD.mapLastInboundAt = GetTime and GetTime() or 0
                GD.mapLastInboundSender = sender
            end
            parseRecord(payload, sender)
        end
    end
end

local function receiveChunk(message, sender)
    local id, part, total, body = message:match("^C|([^|]+)|(%d+)|(%d+)|(.*)$")
    part, total = tonumber(part), tonumber(total)
    -- Long Guild Info text can expand to three times its size after encoding.
    if not id or not part or not total or total < 1 or total > 60 or part < 1 or part > total then return end
    local key = tostring(sender or "") .. ":" .. id
    local slot = GD.fragments[key]
    if not slot then slot = { total = total, parts = {}, count = 0 }; GD.fragments[key] = slot end
    if slot.total ~= total or slot.parts[part] then return end
    slot.parts[part], slot.count = body, slot.count + 1
    if slot.count == total then
        local pieces = {}
        for i = 1, total do if not slot.parts[i] then return end; pieces[i] = slot.parts[i] end
        GD.fragments[key] = nil
        receivePayload(table.concat(pieces), sender)
    end
end

function GD:RequestSync()
    if not self.bucket then return false, "Join a guild first." end
    if self.RequestFeatureSettings then self:RequestFeatureSettings(true) end
    retrySync({ rounds = 0, done = false })
    return true, "Requested an automatic sync from an online GuildDB peer."
end

function GD:Open()
    self:RequestPresence()
    if self.RequestFeatureSettings then self:RequestFeatureSettings(true) end
    if not self.frame and self.BuildUI then
        local ok, err = pcall(self.BuildUI)
        if not ok then
            print("GuildDB: Could not build the window: " .. tostring(err))
            return
        end
    end
    if self.frame then self.frame:Show(); self:RefreshUI() end
end

GD:RegisterCommand("presence", function()
    local last = GD.lastAddonSendByKind or {}
    local announcement = last.V or last.H
    print("GuildDB v" .. GD.version .. " presence: " .. tostring(GD.guildName or "no guild") ..
        "; prefix " .. tostring(GD.prefixRegistration or "not initialized") ..
        "; received " .. tostring(GD.presenceInboundPackets or 0) .. " guild packets.")
    print("GuildDB: Last announcement: " .. (announcement and
        (announcement.succeeded and "sent" or ("failed " .. tostring(announcement.error or announcement.result))) or "none") ..
        "; last sender: " .. tostring(GD.lastPresenceName or "none") ..
        "; messaging " .. (isChatMessagingLocked() and "locked" or "available") .. ".")
    GD:RequestPresence()
end)

GD:RegisterCommand("version", function()
    print(chatPrefix .. "Installed version: |cffffd100v" .. GD.version .. "|r")
end)

local function slashCommand(message)
    local command, rest = message:match("^(%S*)%s*(.-)$")
    command = (command or ""):lower()
    if command == "" or command == "open" then GD:Open(); return end
    if command == "sync" then
        local _, result = GD:RequestSync(); print("GuildDB: " .. result); return
    end
    local handler = GD.commands[command]
    if handler then handler(rest or "") else
        print("GuildDB commands: /gd version, /gd bankapi, /gd sync, /gd profile, /gd spec, /gd map, /gd looking, /gd craft, /gd poll, /gd pvp, /gd raid, /gd event, /gd rsvp, /gd post, /gd shout, /gd recruit, /gd testpopout")
    end
end

SLASH_GuildDB1 = "/gd"
SLASH_GuildDB2 = "/guilddb"
SlashCmdList.GuildDB = slashCommand

local frame = CreateFrame("Frame")
GD.eventFrame = frame
GD.eventRegistration = {}
for _, event in ipairs({ "ENCOUNTER_END", "BOSS_KILL", "LOOT_OPENED", "LOOT_CLOSED", "CHAT_MSG_LOOT" }) do
    local ok = pcall(frame.RegisterEvent, frame, event)
    GD.eventRegistration[event] = ok and "registered" or "unavailable"
end
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_GUILD_UPDATE", "PLAYER_REGEN_ENABLED", "GUILD_ROSTER_UPDATE", "GUILD_MOTD", "GUILD_EVENT_LOG_UPDATE", "CHAT_MSG_SYSTEM", "CHAT_MSG_WHISPER", "WHO_LIST_UPDATE", "UI_INFO_MESSAGE", "CHAT_MSG_ADDON", "CHAT_MSG_COMBAT_HONOR_GAIN", "PLAYER_PVP_KILLS_CHANGED", "PARTY_KILL", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "UNIT_FLAGS", "UNIT_HEALTH", "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD", "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "SKILL_LINES_CHANGED", "TRADE_SKILL_UPDATE", "PLAYER_LEVEL_UP", "WORLD_MAP_OPEN" }) do
    -- Some Forever builds omit optional retail/classic events. One unavailable
    -- event must not abort runtime setup and prevent /gd from opening.
    local ok = pcall(frame.RegisterEvent, frame, event)
    if ok and frame.IsEventRegistered then
        local checked, registered = pcall(frame.IsEventRegistered, frame, event)
        if checked then ok = registered end
    end
    GD.eventRegistration[event] = ok and "registered" or "unavailable"
end

frame:SetScript("OnUpdate", function(_, elapsed)
    local now = GetTime()
    -- Guild info can be unavailable during login, without another guild event.
    if GD.playerLoggedIn and not GD.bucket and now >= (GD.nextGuildCheck or 0) then
        GD.nextGuildCheck = now + 2
        if IsInGuild and IsInGuild() and ensureBucket() then requestGuildRoster() end
    end
    cleanupPresence(now)
    -- Guild addon messages share a per-prefix server allowance. Match GuildHQ's
    -- burst + steady refill pacing so a sync queue doesn't outrun that limit.
    if GD.sendTokenAt == 0 then GD.sendTokenAt = now end
    GD.sendTokens = math.min(8, GD.sendTokens + math.max(0, now - GD.sendTokenAt) * 0.9)
    GD.sendTokenAt = now
    if GD.bucket and now >= GD.nextPresence then
        GD.lastPresenceAnnouncement = now
        GD:Enqueue("V|" .. GD.version .. "|" .. GD:Encode(GD:PresenceName()) .. "|" ..
            (GD.presenceRequestPending and "1" or "0"), false, true)
        GD.presenceRequestPending = nil
        -- Preserve the original announcement for older clients.
        GD:Enqueue("H|" .. GD.version, false, true)
        GD.nextPresence = now + 60
    end
    local queue, minimumTokens = GD:GetAddonSendQueue()
    -- Some clients silently reject addon messages during combat/instance
    -- lockdown while returning nil (normally a successful send). Keep queued
    -- records until the API says messaging is available again.
    -- Preserve two tokens for player bid traffic instead of letting background
    -- history/presence consume the entire burst allowance.
    if #queue > 0 and GD.sendTokens >= minimumTokens and now >= GD.nextSend and not isChatMessagingLocked() then
        if sendRaw(queue[1]) then
            table.remove(queue, 1)
            GD.sendTokens = GD.sendTokens - 1
        else
            -- Keep the unsent frame queued and retry after a short pause.
            local sendResult = GD.lastAddonSend and GD.lastAddonSend.result
            GD.nextSend = now + (sendResult == 11 and 5 or 0.5)
        end
    end
    if GD.MapUpdate then GD:MapUpdate(now, elapsed) end
    if GD.RaidReminderUpdate then GD:RaidReminderUpdate(now) end
end)

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= ADDON then return end
        GDB = type(GDB) == "table" and GDB or {}
        GDB.guilds = type(GDB.guilds) == "table" and GDB.guilds or {}
        registerPrefix()
    elseif event == "PLAYER_LOGIN" then
        GD.playerLoggedIn = true
        GD:PrintWelcome()
        registerPrefix()
        ensureBucket()
        GD.nextPresence = 0
        if IsInGuild and IsInGuild() then requestGuildRoster() end
    elseif event == "PLAYER_GUILD_UPDATE" then
        if ensureBucket() then GD.nextPresence = 0; requestGuildRoster() end
    elseif event == "GUILD_ROSTER_UPDATE" then
        ensureBucket()
    elseif event == "PLAYER_ENTERING_WORLD" then
        registerPrefix()
        if ensureBucket() then GD:RequestPresence() end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix == GD.prefix and channel == "GUILD" and (GD.bucket or ensureBucket()) then
            GD.presenceInboundPackets = (GD.presenceInboundPackets or 0) + 1
            if message:match("^C|") then receiveChunk(message, sender)
            else receivePayload(message, sender) end
        end
    end
    for _, handler in ipairs(GD.eventHandlers[event] or {}) do handler(event, ...) end
end)

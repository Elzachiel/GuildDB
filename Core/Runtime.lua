-- Shared lifecycle, saved data, slash routing, and guild addon-message transport.
local ADDON, GH = ...
_G.GuildHall = GH

GH.version = "0.1.43"
GH.prefix = "GHALL"
GH.maxItems = 60
GH.tabs = { "Roster" }
GH.activeTab = "Roster"
GH.bucketDefaults = {}
GH.recordHandlers = {}
GH.historyProviders = {}
GH.eventHandlers = {}
GH.commands = {}
GH.fragments = {}
GH.sendQueue = {}
GH.nextSend = 0
GH.nextPresence = 0
GH.nextPresenceCleanup = 0
GH.addonPresence = {}

function GH:Encode(value)
    return (tostring(value or ""):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("\r", "%%0D"):gsub("\n", "%%0A"))
end

function GH:Decode(value)
    return (tostring(value or ""):gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

function GH:Enqueue(payload)
    local id = tostring(time()) .. tostring(math.random(1000, 999999))
    local size = 180
    local total = math.max(1, math.ceil(#payload / size))
    for i = 1, total do
        GH.sendQueue[#GH.sendQueue + 1] = table.concat({ "C", id, i, total, payload:sub((i - 1) * size + 1, i * size) }, "|")
    end
end

function GH:SendRecord(kind, id, timestamp, author, content)
    self:Enqueue(table.concat({ kind, self:Encode(id), timestamp, self:Encode(author), self:Encode(content) }, "|"))
end

function GH:NewRecord(values)
    values.id = tostring(time()) .. "-" .. tostring(math.random(100000, 999999))
    values.ts = time()
    values.by = UnitName and UnitName("player") or "Guild member"
    return values
end

function GH:StoreRecord(bucketKey, record, kind, content)
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

function GH:RegisterBucket(key, defaultValue)
    self.bucketDefaults[key] = defaultValue
end

function GH:RegisterRecordHandler(kind, handler)
    self.recordHandlers[kind] = handler
end

function GH:RegisterHistoryProvider(handler, responderOnly)
    self.historyProviders[#self.historyProviders + 1] = {
        handler = handler,
        responderOnly = responderOnly ~= false,
    }
end

function GH:RegisterEventHandler(event, handler)
    self.eventHandlers[event] = self.eventHandlers[event] or {}
    self.eventHandlers[event][#self.eventHandlers[event] + 1] = handler
end

function GH:RegisterCommand(command, handler)
    self.commands[command] = handler
end

function GH:RegisterTab(name, renderer)
    self.views = self.views or {}
    local listed = false
    for _, tab in ipairs(self.tabs) do if tab == name then listed = true; break end end
    if not listed then self.tabs[#self.tabs + 1] = name end
    self.views[name] = renderer
end

function GH:Display(value)
    return tostring(value or ""):gsub("|", "||")
end

function GH:CanManage()
    if not self.guildName or not GetGuildInfo then return false end
    local _, _, rank = GetGuildInfo("player")
    return rank == 0 or rank == 1
end

function GH:GetAddonVersion(name)
    if not name then return nil end
    local wanted = (name:match("^([^-]+)") or name):lower()
    local now = GetTime and GetTime() or 0
    for sender, status in pairs(self.addonPresence or {}) do
        local senderName = (sender:match("^([^-]+)") or sender):lower()
        if senderName == wanted and now - (status.seen or 0) <= 150 then return status.version end
    end
end

local function cleanupPresence(now)
    if now < GH.nextPresenceCleanup then return end
    GH.nextPresenceCleanup = now + 30
    local changed = false
    for sender, status in pairs(GH.addonPresence) do
        if now - (status.seen or 0) > 150 then
            GH.addonPresence[sender] = nil
            changed = true
        end
    end
    if changed and GH.RefreshUI then GH:RefreshUI() end
end

local function guildKey(name, faction)
    return (name or ""):upper() .. "@" .. (faction or "Neutral")
end

local function ensureBucket()
    if not IsInGuild or not IsInGuild() then
        GH.guildName, GH.bucket = nil, nil
        GH.guildKey, GH.addonPresence = nil, {}
        GH.roster = {}
        if GH.RefreshUI then GH:RefreshUI() end
        return false
    end
    local name = GetGuildInfo and GetGuildInfo("player")
    if not name or name == "" then return false end
    GH.guildName = name
    local faction = UnitFactionGroup and UnitFactionGroup("player") or "Neutral"
    local key = guildKey(name, faction)
    if GH.guildKey ~= key then GH.addonPresence = {} end
    GH.guildKey = key
    GuildHallDB.guilds[key] = GuildHallDB.guilds[key] or {}
    GH.bucket = GuildHallDB.guilds[key]
    for bucketKey, defaultValue in pairs(GH.bucketDefaults) do
        if type(GH.bucket[bucketKey]) ~= "table" then GH.bucket[bucketKey] = defaultValue() end
    end
    if GH.RefreshUI then GH:RefreshUI() end
    return true
end

local function sendRaw(message)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(GH.prefix, message, "GUILD")
    elseif SendAddonMessage then
        SendAddonMessage(GH.prefix, message, "GUILD")
    end
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
    id, author, content = GH:Decode(id), GH:Decode(author), GH:Decode(content)
    timestamp = tonumber(timestamp)
    if not timestamp or #id > 100 or #author > 100 or #content > 1200 then return end
    local handler = GH.recordHandlers[kind]
    if handler then handler(id, timestamp, author, content, sender) end
end

local function sendHistory()
    if not GH.bucket then return end
    local responder = GH.IsSyncResponder and GH:IsSyncResponder()
    for _, provider in ipairs(GH.historyProviders) do
        if not provider.responderOnly or responder then provider.handler() end
    end
end

local function receivePayload(payload, sender)
    if payload == "Q" then
        sendHistory()
    else
        local version = payload:match("^H|([%w%.%-]+)$")
        if version and #version <= 32 and sender and #sender <= 100 then
            GH.addonPresence[sender] = { version = version, seen = GetTime and GetTime() or 0 }
            if GH.RefreshUI then GH:RefreshUI() end
        else
            parseRecord(payload, sender)
        end
    end
end

local function receiveChunk(message, sender)
    local id, part, total, body = message:match("^C|([^|]+)|(%d+)|(%d+)|(.*)$")
    part, total = tonumber(part), tonumber(total)
    if not id or not part or not total or total < 1 or total > 20 or part > total then return end
    local key = tostring(sender or "") .. ":" .. id
    local slot = GH.fragments[key]
    if not slot then slot = { total = total, parts = {}, count = 0 }; GH.fragments[key] = slot end
    if slot.total ~= total or slot.parts[part] then return end
    slot.parts[part], slot.count = body, slot.count + 1
    if slot.count == total then
        local pieces = {}
        for i = 1, total do if not slot.parts[i] then return end; pieces[i] = slot.parts[i] end
        GH.fragments[key] = nil
        receivePayload(table.concat(pieces), sender)
    end
end

function GH:RequestSync()
    if not self.bucket then return false, "Join a guild first." end
    self:Enqueue("Q")
    return true, "Asked online guild members for recent posts."
end

function GH:Open()
    if not self.frame and self.BuildUI then
        local ok, err = pcall(self.BuildUI)
        if not ok then
            print("Guild Hall: Could not build the window: " .. tostring(err))
            return
        end
    end
    if self.frame then self.frame:Show(); self:RefreshUI() end
end

local function slashCommand(message)
    local command, rest = message:match("^(%S*)%s*(.-)$")
    command = (command or ""):lower()
    if command == "" or command == "open" then GH:Open(); return end
    if command == "sync" then
        local _, result = GH:RequestSync(); print("Guild Hall: " .. result); return
    end
    local handler = GH.commands[command]
    if handler then handler(rest or "") else
        print("Guild Hall commands: /gh sync, /gh profile, /gh guide, /gh looking, /gh craft, /gh poll, /gh pvp, /gh raid, /gh event, /gh rsvp, /gh post, /gh shout")
    end
end

SLASH_GUILDHALL1 = "/gh"
SLASH_GUILDHALL2 = "/guildhall"
SlashCmdList.GUILDHALL = slashCommand

local frame = CreateFrame("Frame")
GH.eventFrame = frame
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE", "CHAT_MSG_ADDON", "CHAT_MSG_COMBAT_HONOR_GAIN", "PARTY_KILL", "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "SKILL_LINES_CHANGED", "TRADE_SKILL_UPDATE", "PLAYER_LEVEL_UP" }) do
    -- Some Forever builds omit optional retail/classic events. One unavailable
    -- event must not abort runtime setup and prevent /gh from opening.
    pcall(frame.RegisterEvent, frame, event)
end

frame:SetScript("OnUpdate", function()
    local now = GetTime()
    cleanupPresence(now)
    if GH.bucket and now >= GH.nextPresence then
        GH:Enqueue("H|" .. GH.version)
        GH.nextPresence = now + 60
    end
    if #GH.sendQueue > 0 and now >= GH.nextSend then
        sendRaw(table.remove(GH.sendQueue, 1))
        GH.nextSend = now + 0.4
    end
end)

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= ADDON then return end
        GuildHallDB = type(GuildHallDB) == "table" and GuildHallDB or {}
        GuildHallDB.guilds = type(GuildHallDB.guilds) == "table" and GuildHallDB.guilds or {}
        local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
        if register then register(GH.prefix) end
    elseif event == "PLAYER_LOGIN" then
        ensureBucket()
        GH.nextPresence = 0
        if IsInGuild and IsInGuild() then requestGuildRoster() end
        C_Timer.After(10, function() if GH.bucket then GH:RequestSync() end end)
    elseif event == "PLAYER_GUILD_UPDATE" then
        if ensureBucket() then GH.nextPresence = 0; requestGuildRoster() end
    elseif event == "GUILD_ROSTER_UPDATE" then
        ensureBucket()
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix == GH.prefix and channel == "GUILD" and GH.bucket then receiveChunk(message, sender) end
    end
    for _, handler in ipairs(GH.eventHandlers[event] or {}) do handler(event, ...) end
end)

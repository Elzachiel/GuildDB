-- Guild announcements: officer-managed posts with create, edit, delete, and sync.
local _, GD = ...
GD:RegisterBucket("announcements", function() return {} end)
GD:RegisterBucket("announcementDeletes", function() return {} end)

local function clean(value, limit, singleLine)
    value = tostring(value or ""):gsub("|", " ")
    if singleLine then value = value:gsub("[\r\n]", " ") end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value:sub(1, limit)
end

local function encodePost(title, text)
    return title .. "\n" .. text
end

local function decodePost(content)
    local title, text = content:match("^(.-)\n(.*)$")
    if title then return title, text end
    return "", content -- Legacy announcement records contained message text only.
end

local function isOfficer(name)
    if not name or not GetNumGuildMembers or not GetGuildRosterInfo then return nil end
    local count = GetNumGuildMembers()
    if not count or count == 0 then return nil end
    local wanted = (name:match("^([^-]+)") or name):lower():gsub("[%s%-]", "")
    local prefixMatch
    for index = 1, GetNumGuildMembers() do
        local rosterName, _, rankIndex = GetGuildRosterInfo(index)
        if rosterName then
            local candidate = (rosterName:match("^([^-]+)") or rosterName):lower():gsub("[%s%-]", "")
            if candidate == wanted then return tonumber(rankIndex) ~= nil and tonumber(rankIndex) <= 1 end
            if #candidate > #wanted and candidate:sub(1, #wanted) == wanted then
                if prefixMatch then return false end
                prefixMatch = tonumber(rankIndex) ~= nil and tonumber(rankIndex) <= 1
            end
        end
    end
    return prefixMatch or false
end

local function deferUntilRoster(callback)
    GD.pendingAnnouncementChecks = GD.pendingAnnouncementChecks or {}
    GD.pendingAnnouncementChecks[#GD.pendingAnnouncementChecks + 1] = callback
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

local function deleteTimestamp(id)
    local value = (GD.bucket.announcementDeletes or {})[id]
    return type(value) == "table" and (tonumber(value.ts) or 0) or (tonumber(value) or 0)
end

local function findPost(id)
    for index, record in ipairs(GD.bucket.announcements or {}) do
        if record.id == id then return record, index end
    end
end

local function popAnnouncement(author, title, text)
    if not GD.ShowPopout then return end
    local summary = tostring(text or ""):gsub("%s+", " ")
    local displayTitle = title ~= "" and title or "New guild announcement"
    local message = tostring(author or "Guild officer")
    if summary ~= "" then message = message .. ": " .. summary end
    GD:ShowPopout("Guild announcement", displayTitle, message, "Interface/Icons/INV_Letter_15", function()
        GD.activeTab = "Announcements"
        GD:Open()
    end, 8)
end

local function storePost(id, ts, author, title, text)
    if #id > 100 or #author > 100 or #title > 120 or #text > 600 then return end
    local officer = isOfficer(author)
    if officer == nil then
        deferUntilRoster(function() storePost(id, ts, author, title, text) end)
        return "pending"
    end
    if not officer then return false end
    if deleteTimestamp(id) >= ts then return end
    local current, index = findPost(id)
    if current and (current.ts or 0) >= ts then return end
    local post = { id = id, ts = ts, by = author, title = title, text = text }
    if current then GD.bucket.announcements[index] = post else table.insert(GD.bucket.announcements, 1, post) end
    if GD.RefreshUI then GD:RefreshUI() end
end

function GD:PostAnnouncement(title, text)
    if not self:CanManage() then return false, "Only the guild leader or rank 1 can post announcements." end
    if text == nil then text, title = title, "" end -- Keep /gd post Message working.
    title = clean(title, 120, true)
    text = clean(text, 600, false)
    if title == "" and text == "" then return false, "Enter an announcement title or message." end
    local record = self:NewRecord({ title = title, text = text })
    self:StoreRecord("announcements", record)
    self:SendRecord("AN", record.id, record.ts, record.by, encodePost(title, text))
    self.shownAnnouncementPopups = self.shownAnnouncementPopups or {}
    self.shownAnnouncementPopups[record.id] = true
    popAnnouncement(record.by, title, text)
    return true, "Announcement saved and sent to online GuildDB users."
end

function GD:EditAnnouncement(id, title, text)
    if not self:CanManage() then return false, "Only the guild leader or rank 1 can edit announcements." end
    local record, index = findPost(id)
    if not record then return false, "That announcement is no longer available." end
    title, text = clean(title, 120, true), clean(text, 600, false)
    if title == "" and text == "" then return false, "Enter an announcement title or message." end
    record = { id = id, ts = math.max(time(), (record.ts or 0) + 1), by = self:PlayerName(), title = title, text = text }
    self.bucket.announcements[index] = record
    self:SendRecord("AE", id, record.ts, record.by, encodePost(title, text))
    if self.RefreshUI then self:RefreshUI() end
    return true, "Announcement updated and shared with online GuildDB users."
end

function GD:DeleteAnnouncement(id)
    if not self:CanManage() then return false, "Only the guild leader or rank 1 can remove announcements." end
    local _, index = findPost(id)
    if not index then return false, "That announcement is no longer available." end
    local player = self:PlayerName()
    local ts = math.max(time(), (self.bucket.announcements[index].ts or 0) + 1)
    table.remove(self.bucket.announcements, index)
    self.bucket.announcementDeletes = self.bucket.announcementDeletes or {}
    self.bucket.announcementDeletes[id] = { ts = ts, by = player }
    self:SendRecord("AD", id, ts, player, "")
    if self.RefreshUI then self:RefreshUI() end
    return true, "Announcement removed and synced with online GuildDB users."
end

GD:RegisterRecordHandler("A", function(id, ts, author, content)
    if #content <= 600 then storePost(id, ts, author, "", content) end
end)

GD:RegisterRecordHandler("AN", function(id, ts, author, content, sender)
    local title, text = decodePost(content)
    local result = storePost(id, ts, author, title, text)
    if result == false then return end
    if result == "pending" then
        deferUntilRoster(function()
            local senderName = tostring(sender or ""):match("^([^-]+)") or tostring(sender or "")
            local authorName = tostring(author or ""):match("^([^-]+)") or tostring(author or "")
            if senderName:lower():gsub("[%s%-]", "") ~= authorName:lower():gsub("[%s%-]", "") then return end
            if not isOfficer(author) or GD.shownAnnouncementPopups and GD.shownAnnouncementPopups[id] then return end
            GD.shownAnnouncementPopups = GD.shownAnnouncementPopups or {}
            GD.shownAnnouncementPopups[id] = true
            popAnnouncement(author, title, text)
        end)
        return
    end
    -- Live posts are sent by their author. History syncs are relayed by a
    -- different guild member, so they update the announcement list without
    -- replaying old popups.
    local senderName = tostring(sender or ""):match("^([^-]+)") or tostring(sender or "")
    local authorName = tostring(author or ""):match("^([^-]+)") or tostring(author or "")
    if senderName == "" or senderName:lower():gsub("[%s%-]", "") ~= authorName:lower():gsub("[%s%-]", "") then return end
    if #id > 100 or #author > 100 or #title > 120 or #text > 600 then return end
    GD.shownAnnouncementPopups = GD.shownAnnouncementPopups or {}
    if GD.shownAnnouncementPopups[id] then return end
    GD.shownAnnouncementPopups[id] = true
    popAnnouncement(author, title, text)
end)

GD:RegisterRecordHandler("AE", function(id, ts, author, content)
    local title, text = decodePost(content)
    storePost(id, ts, author, title, text)
end)

GD:RegisterRecordHandler("AD", function(id, ts, author)
    if #id > 100 or #author > 100 or not isOfficer(author) then return end
    GD.bucket.announcementDeletes = GD.bucket.announcementDeletes or {}
    local deletes = GD.bucket.announcementDeletes
    if deleteTimestamp(id) >= ts then return end
    deletes[id] = { ts = ts, by = author }
    local _, index = findPost(id)
    if index then table.remove(GD.bucket.announcements, index) end
    if GD.RefreshUI then GD:RefreshUI() end
end)

GD:RegisterEventHandler("GUILD_ROSTER_UPDATE", function()
    local pending = GD.pendingAnnouncementChecks
    if not pending or #pending == 0 then return end
    GD.pendingAnnouncementChecks = {}
    for _, callback in ipairs(pending) do callback() end
end)

-- Upgrade announcements made on WoW Forever builds where UnitName returned
-- only the first part of the author's two-part character name. These records
-- otherwise fail roster authorization or the live sender/author popup check.
GD:RegisterEventHandler("PLAYER_LOGIN", function()
    if not GD.bucket then return end
    local fullName = GD:PlayerName()
    local shortName = UnitName and UnitName("player")
    if not fullName or fullName == "" or not shortName or shortName == fullName then return end
    for _, record in ipairs(GD.bucket.announcements or {}) do
        if record.by == shortName then
            record.by = fullName
            record.ts = math.max(time(), (record.ts or 0) + 1)
            GD:SendRecord("AN", record.id, record.ts, record.by, encodePost(record.title or "", record.text or ""))
        end
    end
end)

GD:RegisterHistoryProvider(function()
    for _, record in ipairs(GD.bucket.announcements or {}) do
        GD:SendRecord("AN", record.id, record.ts or time(), record.by, encodePost(record.title or "", record.text or ""))
    end
    for id, info in pairs(GD.bucket.announcementDeletes or {}) do
        local ts = type(info) == "table" and info.ts or tonumber(info)
        local author = type(info) == "table" and info.by or nil
        if ts and author then GD:SendRecord("AD", id, ts, author, "") end
    end
end, false)

GD:RegisterCommand("post", function(text)
    local _, result = GD:PostAnnouncement(text)
    print("GuildDB: " .. result)
end)

GD:RegisterTab("Announcements", function()
    if not GD.bucket then return "Join a guild to see announcements." end
    local lines = {}
    for _, record in ipairs(GD.bucket.announcements or {}) do
        local title = record.title and record.title ~= "" and (record.title .. "\n") or ""
        lines[#lines + 1] = ("%s · %s\n%s%s"):format(date("%b %d, %I:%M %p", record.ts), GD:Display(record.by), title, GD:Display(record.text))
    end
    return #lines > 0 and table.concat(lines, "\n\n") or "No announcements yet. Officers can post with /gd post Message text."
end)

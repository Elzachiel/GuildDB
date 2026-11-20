-- Guild announcements: officer-managed posts with create, edit, delete, and sync.
local _, GH = ...
GH:RegisterBucket("announcements", function() return {} end)
GH:RegisterBucket("announcementDeletes", function() return {} end)

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
    if not name or not GetNumGuildMembers or not GetGuildRosterInfo then return false end
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

local function deleteTimestamp(id)
    local value = (GH.bucket.announcementDeletes or {})[id]
    return type(value) == "table" and (tonumber(value.ts) or 0) or (tonumber(value) or 0)
end

local function findPost(id)
    for index, record in ipairs(GH.bucket.announcements or {}) do
        if record.id == id then return record, index end
    end
end

local function popAnnouncement(author, title, text)
    if not GH.ShowPopout then return end
    local summary = tostring(text or ""):gsub("%s+", " ")
    local displayTitle = title ~= "" and title or "New guild announcement"
    local message = tostring(author or "Guild officer")
    if summary ~= "" then message = message .. ": " .. summary end
    GH:ShowPopout("Guild announcement", displayTitle, message, "Interface/Icons/INV_Letter_15", function()
        GH.activeTab = "Announcements"
        GH:Open()
    end, 8)
end

local function storePost(id, ts, author, title, text)
    if #id > 100 or #author > 100 or #title > 120 or #text > 600 then return end
    if not isOfficer(author) then return end
    if deleteTimestamp(id) >= ts then return end
    local current, index = findPost(id)
    if current and (current.ts or 0) >= ts then return end
    local post = { id = id, ts = ts, by = author, title = title, text = text }
    if current then GH.bucket.announcements[index] = post else table.insert(GH.bucket.announcements, 1, post) end
    if GH.RefreshUI then GH:RefreshUI() end
end

function GH:PostAnnouncement(title, text)
    if not self:CanManage() then return false, "Only the guild leader or rank 1 can post announcements." end
    if text == nil then text, title = title, "" end -- Keep /gh post Message working.
    title = clean(title, 120, true)
    text = clean(text, 600, false)
    if title == "" and text == "" then return false, "Enter an announcement title or message." end
    local record = self:NewRecord({ title = title, text = text })
    self:StoreRecord("announcements", record)
    self:SendRecord("AN", record.id, record.ts, record.by, encodePost(title, text))
    self:SendRecord("AP", record.id, record.ts, record.by, encodePost(title, text))
    self.shownAnnouncementPopups = self.shownAnnouncementPopups or {}
    self.shownAnnouncementPopups[record.id] = true
    popAnnouncement(record.by, title, text)
    return true, "Announcement saved and sent to online Guild Hall users."
end

function GH:EditAnnouncement(id, title, text)
    if not self:CanManage() then return false, "Only the guild leader or rank 1 can edit announcements." end
    local record, index = findPost(id)
    if not record then return false, "That announcement is no longer available." end
    title, text = clean(title, 120, true), clean(text, 600, false)
    if title == "" and text == "" then return false, "Enter an announcement title or message." end
    record = { id = id, ts = math.max(time(), (record.ts or 0) + 1), by = UnitName and UnitName("player") or "Guild officer", title = title, text = text }
    self.bucket.announcements[index] = record
    self:SendRecord("AE", id, record.ts, record.by, encodePost(title, text))
    if self.RefreshUI then self:RefreshUI() end
    return true, "Announcement updated and shared with online Guild Hall users."
end

function GH:DeleteAnnouncement(id)
    if not self:CanManage() then return false, "Only the guild leader or rank 1 can remove announcements." end
    local _, index = findPost(id)
    if not index then return false, "That announcement is no longer available." end
    local player = UnitName and UnitName("player") or "Guild officer"
    local ts = math.max(time(), (self.bucket.announcements[index].ts or 0) + 1)
    table.remove(self.bucket.announcements, index)
    self.bucket.announcementDeletes = self.bucket.announcementDeletes or {}
    self.bucket.announcementDeletes[id] = { ts = ts, by = player }
    self:SendRecord("AD", id, ts, player, "")
    if self.RefreshUI then self:RefreshUI() end
    return true, "Announcement removed and synced with online Guild Hall users."
end

GH:RegisterRecordHandler("A", function(id, ts, author, content)
    if #content <= 600 then storePost(id, ts, author, "", content) end
end)

GH:RegisterRecordHandler("AN", function(id, ts, author, content)
    local title, text = decodePost(content)
    storePost(id, ts, author, title, text)
end)

GH:RegisterRecordHandler("AP", function(id, ts, author, content, sender)
    if #id > 100 or #author > 100 or #content > 721 then return end
    GH.shownAnnouncementPopups = GH.shownAnnouncementPopups or {}
    if GH.shownAnnouncementPopups[id] then return end
    local senderName = tostring(sender or ""):match("^([^-]+)") or tostring(sender or "")
    local authorName = tostring(author or ""):match("^([^-]+)") or tostring(author or "")
    if senderName:lower():gsub("[%s%-]", "") ~= authorName:lower():gsub("[%s%-]", "") or not isOfficer(author) then return end
    local title, text = decodePost(content)
    if #title > 120 or #text > 600 then return end
    GH.shownAnnouncementPopups[id] = true
    popAnnouncement(author, title, text)
end)

GH:RegisterRecordHandler("AE", function(id, ts, author, content)
    local title, text = decodePost(content)
    storePost(id, ts, author, title, text)
end)

GH:RegisterRecordHandler("AD", function(id, ts, author)
    if #id > 100 or #author > 100 or not isOfficer(author) then return end
    GH.bucket.announcementDeletes = GH.bucket.announcementDeletes or {}
    local deletes = GH.bucket.announcementDeletes
    if deleteTimestamp(id) >= ts then return end
    deletes[id] = { ts = ts, by = author }
    local _, index = findPost(id)
    if index then table.remove(GH.bucket.announcements, index) end
    if GH.RefreshUI then GH:RefreshUI() end
end)

GH:RegisterHistoryProvider(function()
    for _, record in ipairs(GH.bucket.announcements or {}) do
        GH:SendRecord("AN", record.id, record.ts or time(), record.by, encodePost(record.title or "", record.text or ""))
    end
    for id, info in pairs(GH.bucket.announcementDeletes or {}) do
        local ts = type(info) == "table" and info.ts or tonumber(info)
        local author = type(info) == "table" and info.by or nil
        if ts and author then GH:SendRecord("AD", id, ts, author, "") end
    end
end, false)

GH:RegisterCommand("post", function(text)
    local _, result = GH:PostAnnouncement(text)
    print("Guild Hall: " .. result)
end)

GH:RegisterTab("Announcements", function()
    if not GH.bucket then return "Join a guild to see announcements." end
    local lines = {}
    for _, record in ipairs(GH.bucket.announcements or {}) do
        local title = record.title and record.title ~= "" and (record.title .. "\n") or ""
        lines[#lines + 1] = ("%s · %s\n%s%s"):format(date("%b %d, %I:%M %p", record.ts), GH:Display(record.by), title, GH:Display(record.text))
    end
    return #lines > 0 and table.concat(lines, "\n\n") or "No announcements yet. Officers can post with /gh post Message text."
end)

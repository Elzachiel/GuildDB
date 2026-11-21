-- Home dashboard: officer MOTD access and recently joined guild members.
local _, GD = ...
GD:RegisterBucket("homeMOTD", function() return {} end)
GD:RegisterBucket("homeMembers", function() return {} end)

local function key(name)
    return (tostring(name or ""):match("^([^-]+)") or ""):lower():gsub("%s", "")
end

local function rankOf(name)
    if not GetNumGuildMembers or not GetGuildRosterInfo then return end
    for i = 1, GetNumGuildMembers() do
        local member, _, rank = GetGuildRosterInfo(i)
        if member and key(member) == key(name) then return tonumber(rank) end
    end
end

local function allowed(name)
    local rank = rankOf(name)
    if rank == nil then return false end
    return rank <= 1
end

local function newer(current, ts, author)
    return ts > (current.ts or 0) or (ts == current.ts and author > (current.by or ""))
end

local function refresh()
    if GD.RefreshUI then GD:RefreshUI() end
end

local pending = {}
local function rosterReady(kind, id, ts, author, content)
    if GetNumGuildMembers and GetNumGuildMembers(true) > 0 then return true end
    if #pending < 60 then
        pending[#pending + 1] = { kind = kind, id = id, ts = ts, author = author, content = content, bucket = GD.bucket }
    end
    return false
end

function GD:CanEditHomeMOTD()
    if not self.bucket then return false end
    local rank
    if GetGuildInfo then local _, _, value = GetGuildInfo("player"); rank = value end
    if rank == nil then return allowed(self:PlayerName()) end
    return rank <= 1
end

-- Current clients expose GetMOTD in C_GuildInfo; the legacy global can be
-- absent or retain a compatibility cache. Use the same API family as the writer.
local function readGuildMOTD()
    local modern = C_GuildInfo and C_GuildInfo.GetMOTD
    local getters = {}
    if type(modern) == "function" then getters[#getters + 1] = modern end
    if type(GetGuildRosterMOTD) == "function" then getters[#getters + 1] = GetGuildRosterMOTD end
    for _, getter in ipairs(getters) do
        if type(getter) == "function" then
            local ok, text = pcall(getter)
            if ok and not (issecretvalue and issecretvalue(text)) and type(text) == "string" then return text end
        end
    end
end

-- Native MOTD writes are asynchronous. A successful Lua call alone does not
-- mean the server accepted the change, and the roster getter may lag the event.
local motdUpdate
local motdReadback
local function normalizeMOTD(text)
    return tostring(text or ""):gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function finishMOTD(update, eventText)
    if motdUpdate ~= update or GD.bucket ~= update.bucket then return end
    local current = update.bucket.homeMOTD
    local record = { text = update.text, ts = math.max(time(), (current.ts or 0) + 1), by = update.by }
    update.bucket.homeMOTD = record
    motdUpdate = nil
    if eventText then
        motdReadback = { bucket = update.bucket, text = eventText,
            previous = readGuildMOTD() }
    end
    GD:SendRecord("HM", "motd", record.ts, record.by, record.text)
    refresh()
end

local function checkMOTD()
    local update = motdUpdate
    if not update or GD.bucket ~= update.bucket then return end
    local native = readGuildMOTD()
    if type(native) == "string" and normalizeMOTD(native) == update.text then
        finishMOTD(update)
    end
end

local function requestMOTDRefresh()
    local request = C_GuildInfo and C_GuildInfo.GuildRoster or GuildRoster
    if type(request) == "function" then pcall(request) end
end

local function tryMOTDSetter(update)
    while update.index < #update.setters do
        update.index = update.index + 1
        local ok, result = pcall(update.setters[update.index], update.text)
        if ok and result ~= false then
            checkMOTD()
            requestMOTDRefresh()
            return true
        end
    end
    return false
end

function GD:SetHomeMOTD(text, secureClick)
    if not self:CanEditHomeMOTD() then return false, "Your guild rank cannot edit the MOTD." end
    text = normalizeMOTD(tostring(text or ""):gsub("|", " "))
    if #text > 255 then return false, "The guild MOTD must be 255 bytes or fewer." end
    local rank
    if GetGuildInfo then local _, _, value = GetGuildInfo("player"); rank = value end
    -- Some clients report the rank permission flag incorrectly for the GM.
    if rank ~= 0 and CanEditMOTD and not CanEditMOTD() then
        return false, "Your guild rank needs Edit MOTD permission in the game's guild controls."
    end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return false, "The game has locked guild messaging. Try editing the MOTD outside combat or the instance."
    end
    local setters = {}
    local modern = C_GuildInfo and C_GuildInfo.SetMOTD
    if type(modern) == "function" then setters[#setters + 1] = modern end
    if type(GuildSetMOTD) == "function" and GuildSetMOTD ~= modern then setters[#setters + 1] = GuildSetMOTD end
    if #setters == 0 and not secureClick then return false, "This client does not provide the guild MOTD API." end
    local update = { bucket = self.bucket, by = self:PlayerName(), text = text, setters = setters, index = 0 }
    motdUpdate = update
    if not secureClick and not tryMOTDSetter(update) then
        if motdUpdate == update then motdUpdate = nil end
        return false, "The game could not submit the guild MOTD update."
    end
    if C_Timer and C_Timer.After then
        if secureClick then C_Timer.After(0.2, function()
            if motdUpdate == update and GD.bucket == update.bucket then checkMOTD(); requestMOTDRefresh() end
        end) end
        C_Timer.After(3, function()
            if motdUpdate ~= update or GD.bucket ~= update.bucket then return end
            checkMOTD()
            if motdUpdate ~= update then return end
            -- Compatibility APIs can silently do nothing on some clients.
            if not secureClick then tryMOTDSetter(update) end
            requestMOTDRefresh()
        end)
        C_Timer.After(12, function()
            if motdUpdate ~= update or GD.bucket ~= update.bucket then return end
            checkMOTD()
            if motdUpdate ~= update then return end
            motdUpdate = nil
            print("GuildDB: The game has not confirmed the MOTD update. Check the guild window and try again. The previous saved MOTD was kept.")
            refresh()
        end)
    end
    return true, "Guild MOTD update requested."
end

function GD:HomeMOTDMacro(text)
    if not self:CanEditHomeMOTD() then return end
    text = normalizeMOTD(tostring(text or ""):gsub("[|%z]", " "))
    if #text > 255 then return end
    local command = SLASH_GUILD_MOTD1 or "/gmotd"
    return "/stopmacro [combat]\n" .. command .. " " .. text
end

GD:RegisterRecordHandler("HM", function(id, ts, author, content)
    if not GD.bucket or id ~= "motd" or #content > 600 then return end
    if not rosterReady("HM", id, ts, author, content) or not allowed(author) then return end
    if not newer(GD.bucket.homeMOTD, ts, author) then return end
    GD.bucket.homeMOTD = { text = content, ts = ts, by = author }
    refresh()
end)

GD:RegisterHistoryProvider(function()
    if not GD.bucket then return end
    local motd = GD.bucket.homeMOTD
    if motd.ts then GD:SendRecord("HM", "motd", motd.ts, motd.by, motd.text or "") end
end, false)

local function joinTracking()
    if not GD.bucket then return end
    local db = GD.bucket.homeMembers
    if db.trackingVersion ~= GD.recentJoinsVersion then
        db.trackingVersion = GD.recentJoinsVersion
        -- First scan of this release is a baseline, not a wave of new joins.
        db.members, db.initialized = {}, false
    end
    db.trackingSince = GD.recentJoinsStart
    db.clearedAt, db.clearedBy, db.ignoredLog = nil, nil, nil
    db.members, db.recent = db.members or {}, db.recent or {}
    for id, record in pairs(db.recent) do
        if (record.ts or 0) < db.trackingSince then db.recent[id] = nil end
    end
    return db
end

local function memberDetails(name)
    local wanted = key(name)
    for _, member in ipairs(GD.roster or {}) do
        if key(member.name) == wanted then return member.level, member.classFile end
    end
    if GetNumGuildMembers and GetGuildRosterInfo then
        for index = 1, GetNumGuildMembers(true) do
            local member, _, _, level, _, _, _, _, _, _, classFile = GetGuildRosterInfo(index)
            if member and key(member) == wanted then return level, classFile end
        end
    end
end

function GD:RecordHomeJoin(name, timestamp, source)
    if not self.bucket or type(name) ~= "string" or name == "" then return end
    local db = joinTracking()
    local id = key(name)
    if id == "" then return end
    local previous = db.recent[id]
    timestamp = tonumber(timestamp) or time()
    if timestamp < db.trackingSince then return end
    if time() - timestamp > 30 * 86400 then return end
    -- Re-reading the log must not reset join times on every refresh.
    if not previous or not previous.joined or (source == "system") then
        db.recent[id] = { name = name, ts = timestamp, joined = true, source = source }
    end
    local record = db.recent[id]
    if record then
        local level, classFile = memberDetails(name)
        record.level, record.classFile = level or record.level, classFile or record.classFile
    end
    db.members[id] = true
end

function GD:ReadHomeGuildLog()
    if not self.bucket or type(GetNumGuildEvents) ~= "function" or type(GetGuildEventInfo) ~= "function" then return end
    local ok, count = pcall(GetNumGuildEvents)
    if not ok or type(count) ~= "number" then return end
    for index = 1, count do
        local got, kind, name, _, _, years, months, days, hours = pcall(GetGuildEventInfo, index)
        if got and kind == "join" and not (issecretvalue and issecretvalue(name)) then
            local age = (tonumber(years) or 0) * 365 * 86400 + (tonumber(months) or 0) * 30 * 86400
                + (tonumber(days) or 0) * 86400 + (tonumber(hours) or 0) * 3600
            -- The guild log rounds age down to whole hours. Exclude records
            -- whose possible join interval crosses the release boundary.
            if time() - age - 3599 >= GD.recentJoinsStart then
                self:RecordHomeJoin(name, time() - age, "log")
            end
        end
    end
end

local logRequestedAt, logBucket
function GD:RequestHomeGuildLog()
    if not self.bucket or type(QueryGuildEventLog) ~= "function" then return end
    local now = time()
    if logBucket == self.bucket and logRequestedAt and now - logRequestedAt < 60 then return end
    logRequestedAt, logBucket = now, self.bucket
    pcall(QueryGuildEventLog)
end

local function escapePattern(text)
    return (text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

local function handleGuildJoin(message)
    if not GD.bucket or (issecretvalue and issecretvalue(message)) or type(message) ~= "string" then return end
    local formatText = ERR_GUILD_JOIN_S
    if type(formatText) ~= "string" then return end
    local start, finish = formatText:find("%s", 1, true)
    if not start then return end
    local pattern = "^" .. escapePattern(formatText:sub(1, start - 1)) .. "(.-)" .. escapePattern(formatText:sub(finish + 1)) .. "$"
    local name = message:match(pattern)
    if not name then return end
    name = name:match("|h%[(.-)%]|h") or name
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    GD:RecordHomeJoin(name, time(), "system")
    refresh()
end
GD:RegisterEventHandler("CHAT_MSG_SYSTEM", function(_, message) handleGuildJoin(message) end)
GD:RegisterEventHandler("UI_INFO_MESSAGE", function(_, _, message) handleGuildJoin(message) end)
GD:RegisterEventHandler("GUILD_EVENT_LOG_UPDATE", function()
    GD:ReadHomeGuildLog()
    refresh()
end)
GD:RegisterEventHandler("PLAYER_LOGIN", function() GD:RequestHomeGuildLog() end)
GD:RegisterEventHandler("PLAYER_GUILD_UPDATE", function() GD:RequestHomeGuildLog() end)

function GD:TrackHomeMembers()
    if not self.bucket or not GetNumGuildMembers or not GetGuildRosterInfo then return end
    local count = GetNumGuildMembers(true)
    if not count or count == 0 then return end
    local db, names = joinTracking(), {}
    -- Baseline only a complete roster, including offline members.
    for i = 1, count do
        local name = GetGuildRosterInfo(i)
        if not name then return end
        names[key(name)] = name
    end
    db.members, db.recent = db.members or {}, db.recent or {}
    local now = time()
    for id, name in pairs(names) do
        if db.initialized and not db.members[id] then db.recent[id] = { name = name, ts = now } end
    end
    for id in pairs(names) do db.members[id] = true end
    db.initialized = true
    for id, record in pairs(db.recent) do
        if now - (record.ts or 0) > 30 * 86400 then db.recent[id] = nil end
    end
end

GD:RegisterEventHandler("GUILD_ROSTER_UPDATE", function()
    if GetNumGuildMembers and GetNumGuildMembers(true) > 0 then
        local records = pending
        pending = {}
        for _, record in ipairs(records) do
            if GD.bucket == record.bucket then
                GD.recordHandlers[record.kind](record.id, record.ts, record.author, record.content)
            end
        end
    end
    GD:TrackHomeMembers()
    GD:RequestHomeGuildLog()
    checkMOTD()
    refresh()
end)
GD:RegisterEventHandler("GUILD_MOTD", function(_, text)
    if issecretvalue and issecretvalue(text) then return end
    if type(text) == "string" and GD.bucket then
        motdReadback = { bucket = GD.bucket, text = text,
            previous = readGuildMOTD() }
        if motdUpdate and motdUpdate.bucket == GD.bucket and normalizeMOTD(text) == motdUpdate.text then
            finishMOTD(motdUpdate, text)
        end
    end
    checkMOTD()
    refresh()
end)

local function label(parent, text, font)
    local item = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    item:SetJustifyH("LEFT")
    item:SetJustifyV("TOP")
    item:SetWordWrap(true)
    item:SetText(text)
    return item
end

local function button(parent, text, width, click)
    local item = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    GD:StyleButton(item)
    item:SetSize(width, 24)
    item:SetText(text)
    item:SetScript("OnClick", click)
    return item
end

local function box(parent, title)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    panel:SetBackdropColor(0.045, 0.06, 0.08, 1)
    panel:SetBackdropBorderColor(0.16, 0.25, 0.34, 1)
    panel.title = label(panel, title, "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 14, -14)
    panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scroll:SetPoint("TOPLEFT", 12, -48)
    panel.scroll:SetPoint("BOTTOMRIGHT", -30, 12)
    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetSize(100, 100)
    panel.scroll:SetScrollChild(panel.content)
    panel.scroll:SetScript("OnSizeChanged", function(_, width) panel.content:SetWidth(math.max(80, width)) end)
    return panel
end

local function announcementForm(post)
    GD.ShowInputForm(post and "Edit announcement" or "Post an announcement", {
        { label = "Title", value = post and post.title or "", max = 120 },
        { label = "Message", value = post and post.text or "", max = 600, multiline = true },
    }, function(values)
        if post then return GD:EditAnnouncement(post.id, values[1], values[2]) end
        return GD:PostAnnouncement(values[1], values[2])
    end)
end

function GD:GetHomeMOTD()
    local native = readGuildMOTD()
    if motdReadback and motdReadback.bucket == self.bucket then
        if native == motdReadback.previous then return motdReadback.text end
        motdReadback = nil
    end
    if type(native) == "string" then return native end
    return self.bucket and self.bucket.homeMOTD.text or ""
end

local function buildHome(frame)
    local home = CreateFrame("Frame", nil, frame.detailPanel)
    home:SetAllPoints()
    home.motd = box(home, "Message of the day")
    home.motd:SetPoint("TOPLEFT", 10, -10)
    home.motd:SetPoint("TOPRIGHT", -10, -10)
    home.motd:SetHeight(170)
    home.posts = box(home, "Announcements")
    home.posts:SetPoint("TOPLEFT", home.motd, "BOTTOMLEFT", 0, -12)
    home.posts:SetPoint("BOTTOMLEFT", 10, 12)
    home.joins = box(home, "Recently joined")
    home.joins:SetPoint("TOPRIGHT", home.motd, "BOTTOMRIGHT", 0, -12)
    home.joins:SetPoint("BOTTOMRIGHT", -10, 12)
    home:SetScript("OnSizeChanged", function(_, width)
        home.posts:SetWidth(math.max(180, (width - 32) / 2))
        home.joins:SetWidth(math.max(180, (width - 32) / 2))
    end)
    home.edit = button(home.motd, "Edit", 56, function()
        if InCombatLockdown and InCombatLockdown() then print("GuildDB: Wait until combat ends to edit the guild MOTD."); return end
        GD.ShowInputForm("Edit Home MOTD", {
            { label = "Message", value = GD:GetHomeMOTD(), max = 255, multiline = true },
        }, function(values) return GD:SetHomeMOTD(values[1], true) end, "Save", nil,
            function(values) return GD:HomeMOTDMacro(values[1]) end)
    end)
    home.edit:SetPoint("TOPRIGHT", -12, -10)
    home.newPost = button(home.posts, "New post", 86, function() announcementForm() end)
    home.newPost:SetPoint("TOPRIGHT", -12, -10)
    home.motdText = label(home.motd.content, "")
    home.motdText:SetPoint("TOPLEFT", 2, -2)
    home.motdText:SetPoint("TOPRIGHT", -2, -2)
    home.joinText = label(home.joins.content, "")
    home.joinText:SetPoint("TOPLEFT", 2, -2)
    home.joinText:SetPoint("TOPRIGHT", -2, -2)
    home.rows = {}
    frame.home = home
    return home
end

function GD:RefreshHomeAppearance()
    local home = self.frame and self.frame.home
    if not home or not self.GetAppearanceColors then return end
    local colors = self:GetAppearanceColors()
    for _, panel in ipairs({ home.motd, home.posts, home.joins }) do
        panel:SetBackdropColor(colors.alternate[1], colors.alternate[2], colors.alternate[3], colors.alternate[4] or 1)
        panel:SetBackdropBorderColor(colors.accent[1] * 0.5, colors.accent[2] * 0.5, colors.accent[3] * 0.5, 1)
        panel.title:SetTextColor(colors.accent[1], colors.accent[2], colors.accent[3])
    end
    for _, text in ipairs({ home.motdText, home.joinText }) do
        text:SetTextColor(colors.text[1], colors.text[2], colors.text[3])
    end
    if home.empty then home.empty:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3]) end
    self:StyleButton(home.edit)
    self:StyleButton(home.newPost, "primary")
    for _, row in ipairs(home.rows) do
        row.title:SetTextColor(colors.accent[1], colors.accent[2], colors.accent[3])
        row.body:SetTextColor(colors.text[1], colors.text[2], colors.text[3])
        self:StyleButton(row.edit)
        self:StyleButton(row.delete)
    end
end

function GD:RefreshHome()
    local frame = self.frame
    local home = frame.home or buildHome(frame)
    joinTracking()
    self:ReadHomeGuildLog()
    self:RequestHomeGuildLog()
    frame.detailScroll:Hide()
    frame.detailTitle:Hide()
    frame.detailMeta:Hide()
    frame.detailRule:Hide()
    frame.footer:Hide()
    home:Show()
    home.posts:SetWidth(math.max(180, (frame.detailPanel:GetWidth() - 32) / 2))
    home.joins:SetWidth(home.posts:GetWidth())
    home.edit:SetShown(self:CanEditHomeMOTD())
    home.newPost:SetShown(self.bucket ~= nil and self:CanManage())
    local text = self.bucket and self:GetHomeMOTD() or ""
    home.motdText:SetText(self:Display(text ~= "" and text or (self.bucket and "No message of the day set." or "Join a guild to view your Home page.")))
    home.motd.content:SetHeight(math.max(70, home.motdText:GetStringHeight() + 12))
    local recent = {}
    for _, record in pairs(self.bucket and self.bucket.homeMembers.recent or {}) do recent[#recent + 1] = record end
    table.sort(recent, function(a, b) if a.ts ~= b.ts then return a.ts > b.ts end return a.name < b.name end)
    local lines = {}
    for i = 1, math.min(20, #recent) do
        local member = recent[i]
        local level, classFile = memberDetails(member.name)
        member.level, member.classFile = level or member.level, classFile or member.classFile
        local name = self:Display(member.name)
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.classFile]
        if color then
            name = ("|cff%02x%02x%02x%s|r"):format(math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5), math.floor(color.b * 255 + 0.5), name)
        end
        local levelText = tonumber(member.level) and tonumber(member.level) > 0 and ("Level " .. member.level) or "Level unknown"
        lines[#lines + 1] = name .. " - " .. levelText .. (member.joined and "\nJoined " or "\nFirst seen ") .. date("%b %d, %I:%M %p", member.ts)
    end
    home.joinText:SetText(#lines > 0 and table.concat(lines, "\n\n") or "No recent joins yet.")
    home.joins.content:SetHeight(math.max(100, home.joinText:GetStringHeight() + 12))
    local posts = {}
    for _, post in ipairs(self.bucket and self.bucket.announcements or {}) do posts[#posts + 1] = post end
    table.sort(posts, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    local y = 0
    for index, post in ipairs(posts) do
        local row = home.rows[index]
        if not row then
            row = CreateFrame("Frame", nil, home.posts.content)
            row.title = label(row, "")
            row.title:SetPoint("TOPLEFT", 2, -6)
            row.title:SetPoint("TOPRIGHT", -2, -6)
            row.body = label(row, "", "GameFontHighlightSmall")
            row.body:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -8)
            row.body:SetPoint("RIGHT", -2, 0)
            row.edit = button(row, "Edit", 52, function() announcementForm(row.post) end)
            row.edit:SetPoint("BOTTOMLEFT", 2, 4)
            row.delete = button(row, "Delete", 60, function()
                local _, message = GD:DeleteAnnouncement(row.post.id)
                print("GuildDB: " .. tostring(message))
            end)
            row.delete:SetPoint("LEFT", row.edit, "RIGHT", 6, 0)
            home.rows[index] = row
        end
        row.post = post
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", home.posts.content, "RIGHT", 0, 0)
        row.title:SetText(self:Display(post.title and post.title ~= "" and post.title or "Announcement"))
        row.body:SetText(self:Display(post.text) .. "\n\n" .. self:Display(post.by) .. " - " .. date("%b %d", post.ts or time()))
        local manage = self:CanManage()
        row.edit:SetShown(manage)
        row.delete:SetShown(manage)
        row:SetHeight(row.title:GetStringHeight() + row.body:GetStringHeight() + (manage and 54 or 24))
        row:Show()
        y = y + row:GetHeight() + 12
    end
    for index = #posts + 1, #home.rows do home.rows[index]:Hide() end
    if not home.empty then
        home.empty = label(home.posts.content, "No announcements yet.", "GameFontHighlightSmall")
        home.empty:SetPoint("TOPLEFT", 2, -6)
    end
    home.empty:SetShown(#posts == 0)
    home.posts.content:SetHeight(math.max(100, y))
    self:RefreshHomeAppearance()
end

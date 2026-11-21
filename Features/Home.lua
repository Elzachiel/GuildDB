-- Home dashboard: guild-rank MOTD permissions and locally observed new members.
local _, GD = ...
GD:RegisterBucket("homeMOTD", function() return {} end)
GD:RegisterBucket("homeRoles", function() return {} end)
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
    -- Officers always retain access so a rank selection cannot lock them out.
    return rank <= 1 or (GD.bucket and GD.bucket.homeRoles.ranks or {})[rank] == true
end

local function newer(current, ts, author)
    return ts > (current.ts or 0) or (ts == current.ts and author > (current.by or ""))
end

local function refresh()
    if GD.RefreshUI then GD:RefreshUI() end
end

local function encodeRoles(ranks)
    local result = {}
    for rank = 0, 9 do if ranks[rank] then result[#result + 1] = tostring(rank) end end
    return table.concat(result, ",")
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
    return self.bucket and (self:CanManage() or allowed(self:PlayerName())) or false
end

function GD:SetHomeMOTD(text)
    if not self:CanEditHomeMOTD() then return false, "Your guild rank cannot edit the MOTD." end
    text = tostring(text or ""):gsub("|", " "):sub(1, 600)
    local current = self.bucket.homeMOTD
    local record = { text = text, ts = math.max(time(), (current.ts or 0) + 1), by = self:PlayerName() }
    self.bucket.homeMOTD = record
    self:SendRecord("HM", "motd", record.ts, record.by, text)
    refresh()
    return true, "Home MOTD saved and shared."
end

function GD:SetHomeRoles(ranks)
    if not self.bucket or not self:CanManage() then return false, "Only officers can choose MOTD editor ranks." end
    local selected = {}
    for rank = 0, 9 do if ranks[rank] then selected[rank] = true end end
    local record = { ranks = selected, ts = math.max(time(), (self.bucket.homeRoles.ts or 0) + 1), by = self:PlayerName() }
    self.bucket.homeRoles = record
    self:SendRecord("HR", "roles", record.ts, record.by, encodeRoles(selected))
    refresh()
    return true, "MOTD editor ranks saved and shared."
end

GD:RegisterRecordHandler("HR", function(id, ts, author, content)
    if not GD.bucket or id ~= "roles" or #content > 40 then return end
    if not rosterReady("HR", id, ts, author, content) then return end
    local rank = rankOf(author)
    if not rank or rank > 1 or not newer(GD.bucket.homeRoles, ts, author) then return end
    local ranks = {}
    if content ~= "" then
        for value in (content .. ","):gmatch("(.-),") do
            if not value:match("^[0-9]$") then return end
            ranks[tonumber(value)] = true
        end
    end
    GD.bucket.homeRoles = { ranks = ranks, ts = ts, by = author }
    refresh()
end)

GD:RegisterRecordHandler("HM", function(id, ts, author, content)
    if not GD.bucket or id ~= "motd" or #content > 600 then return end
    if not rosterReady("HM", id, ts, author, content) or not allowed(author) then return end
    if not newer(GD.bucket.homeMOTD, ts, author) then return end
    GD.bucket.homeMOTD = { text = content, ts = ts, by = author }
    refresh()
end)

GD:RegisterHistoryProvider(function()
    if not GD.bucket then return end
    -- Permissions must arrive before the MOTD from a delegated guild rank.
    local roles, motd = GD.bucket.homeRoles, GD.bucket.homeMOTD
    if roles.ts then GD:SendRecord("HR", "roles", roles.ts, roles.by, encodeRoles(roles.ranks or {})) end
    if motd.ts then GD:SendRecord("HM", "motd", motd.ts, motd.by, motd.text or "") end
end, false)

function GD:TrackHomeMembers()
    if not self.bucket or not GetNumGuildMembers or not GetGuildRosterInfo then return end
    local count = GetNumGuildMembers(true)
    if not count or count == 0 then return end
    local db, names = self.bucket.homeMembers, {}
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
    refresh()
end)
GD:RegisterEventHandler("GUILD_MOTD", refresh)

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
        GD.ShowInputForm("Edit Home MOTD", {
            { label = "Message", value = GD.bucket.homeMOTD.text or "", max = 600, multiline = true },
        }, function(values) return GD:SetHomeMOTD(values[1]) end)
    end)
    home.edit:SetPoint("TOPRIGHT", -12, -10)
    home.roles = button(home.motd, "Editor ranks", 100, function()
        local fields, ranks = {}, {}
        local count = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
        if count == 0 then print("GuildDB: Guild ranks are still loading."); return end
        for index = 1, math.min(count, 10) do
            local rank = index - 1
            if rank > 1 then
                fields[#fields + 1] = { label = GuildControlGetRankName(index) or ("Rank " .. rank),
                    value = (GD.bucket.homeRoles.ranks or {})[rank] and "Allowed" or "Not allowed",
                    options = { "Allowed", "Not allowed" } }
                ranks[#ranks + 1] = rank
            end
        end
        if #fields == 0 then return end
        GD.ShowInputForm("MOTD editors (officers always allowed)", fields, function(values)
            local selected = {}
            for i, rank in ipairs(ranks) do selected[rank] = values[i] == "Allowed" end
            return GD:SetHomeRoles(selected)
        end)
    end)
    home.roles:SetPoint("RIGHT", home.edit, "LEFT", -8, 0)
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

function GD:RefreshHome()
    local frame = self.frame
    local home = frame.home or buildHome(frame)
    frame.detailScroll:Hide()
    frame.detailTitle:Hide()
    frame.detailMeta:Hide()
    frame.detailRule:Hide()
    frame.footer:Hide()
    home:Show()
    home.posts:SetWidth(math.max(180, (frame.detailPanel:GetWidth() - 32) / 2))
    home.joins:SetWidth(home.posts:GetWidth())
    home.edit:SetShown(self:CanEditHomeMOTD())
    home.roles:SetShown(self.bucket ~= nil and self:CanManage())
    home.newPost:SetShown(self.bucket ~= nil and self:CanManage())
    local motd = self.bucket and self.bucket.homeMOTD or {}
    local text = motd.text
    if text == nil then text = GetGuildRosterMOTD and GetGuildRosterMOTD() or "" end
    text = text or ""
    home.motdText:SetText(self:Display(text ~= "" and text or (self.bucket and "No message of the day set." or "Join a guild to view your Home page.")))
    home.motd.content:SetHeight(math.max(70, home.motdText:GetStringHeight() + 12))
    local recent = {}
    for _, record in pairs(self.bucket and self.bucket.homeMembers.recent or {}) do recent[#recent + 1] = record end
    table.sort(recent, function(a, b) if a.ts ~= b.ts then return a.ts > b.ts end return a.name < b.name end)
    local lines = {}
    for i = 1, math.min(20, #recent) do
        local member = recent[i]
        lines[#lines + 1] = self:Display(member.name) .. "\nFirst seen " .. date("%b %d, %I:%M %p", member.ts)
    end
    home.joinText:SetText(#lines > 0 and table.concat(lines, "\n\n") or "No new members observed yet.\n\nNew members appear here after the initial guild roster scan.")
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
end

-- Bounded guild history for reported level-ups and profession milestones.
local _, GD = ...
local LIMIT, RETENTION, HISTORY_LIMIT = 200, 30 * 86400, 50
GD:RegisterBucket("activity", function() return {} end)
GD:RegisterTab("Guild Achievements", function() return "" end)

local function nameKey(name) return tostring(name or ""):lower():gsub("%s", "") end
local function trim()
    if not GD.bucket then return {} end
    local records = GD.bucket.activity or {}
    GD.bucket.activity = records
    for i = #records, 1, -1 do
        if type(records[i]) ~= "table" or (tonumber(records[i].ts) or 0) < time() - RETENTION then table.remove(records, i) end
    end
    table.sort(records, function(a, b)
        if a.ts ~= b.ts then return a.ts > b.ts end
        return tostring(a.id) < tostring(b.id)
    end)
    while #records > LIMIT do table.remove(records) end
    return records
end
local function payload(record)
    return table.concat({ record.kind, record.value, record.profession or "" }, "\n")
end

function GD:RecordGuildActivity(id, ts, author, kind, value, profession, broadcast)
    if not self.bucket or type(id) ~= "string" or #id == 0 or #id > 100 then return false end
    if type(author) ~= "string" or author == "" or #author > 100 or author:find("[%c|]") then return false end
    ts, value = tonumber(ts), tonumber(value)
    if not ts or ts < time() - RETENTION or ts > time() + 60 or not value or value ~= math.floor(value) then return false end
    profession = profession or ""
    if type(profession) ~= "string" or #profession > 60 or profession:find("[%c|]") then return false end
    if kind == "L" then
        if value < 10 or value > 60 or value % 10 ~= 0 or profession ~= "" then return false end
    elseif kind == "P" then
        if profession == "" or (value ~= 150 and value ~= 225 and value ~= 300) then return false end
    else return false end
    local records = trim()
    for _, record in ipairs(records) do
        if record.id == id or (nameKey(record.by) == nameKey(author) and record.kind == kind
            and record.value == value and record.profession == profession) then return false end
    end
    local record = { id = id, ts = ts, by = author, kind = kind, value = value, profession = profession }
    records[#records + 1] = record
    self:RecordGuildAchievement(id, ts, author, kind, value, profession)
    trim()
    if broadcast then self:SendRecord("AV", id, ts, author, payload(record)) end
    if self.RefreshUI and self.activeTab == "Guild Achievements" then self:RefreshUI() end
    return true
end

function GD:PostGuildActivity(kind, value, profession)
    if not self.bucket then return false end
    local record = self:NewRecord({})
    return self:RecordGuildActivity(record.id, record.ts, record.by, kind, value, profession, true)
end

GD:RegisterRecordHandler("AV", function(id, ts, author, content)
    local kind, value, profession = content:match("^([LP])\n(%d+)\n([^\n]*)$")
    if kind then GD:RecordGuildActivity(id, ts, author, kind, value, profession) end
end, 100)

GD:RegisterHistoryProvider(function()
    local records = trim()
    -- Catch up on recent activity without filling sync queues with the entire archive.
    for i = math.min(#records, HISTORY_LIMIT), 1, -1 do
        local record = records[i]
        GD:SendRecord("AV", record.id, record.ts, record.by, payload(record))
    end
end)

function GD:GetGuildActivity(filter)
    local result = {}
    for _, record in ipairs(trim()) do
        if (record.kind ~= "L" or record.value % 10 == 0)
            and (not filter or filter == "All" or filter == record.kind) then result[#result + 1] = record end
    end
    return result
end

local function text(parent, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetJustifyH("LEFT")
    return label
end
local function build(frame)
    local panel = CreateFrame("Frame", nil, frame.detailPanel)
    panel:SetAllPoints()
    panel.filter, panel.rows, panel.filters = "All", {}, {}
    panel.view, panel.activityFilter, panel.views = "Achievements", "All", {}
    panel.title = text(panel, "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 16, -16)
    panel.title:SetText("Guild Achievements")
    panel.summary = text(panel)
    panel.summary:SetPoint("TOPLEFT", 16, -42)
    for index, view in ipairs({ "Achievements", "Recent Activity", "Shoutouts" }) do
        local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetPoint("TOPLEFT", 16 + (index - 1) * 150, -66)
        button:SetSize(140, 26)
        button:SetText(view)
        button:SetScript("OnClick", function()
            panel.view = view
            panel.scroll:SetVerticalScroll(0)
            GD:RefreshUI()
        end)
        button.view = view
        panel.views[#panel.views + 1] = button
    end
    for index, option in ipairs({ { "All awards", "All" }, { "Levels", "L" }, { "Professions", "P" }, { "Raid clears", "R" } }) do
        local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetPoint("TOPLEFT", 16 + (index - 1) * 118, -102)
        button:SetSize(108, 26)
        button:SetText(option[1])
        button.filter = option[2]
        button:SetScript("OnClick", function(self)
            if panel.view == "Achievements" then panel.filter = self.filter
            else panel.activityFilter = self.filter end
            panel.scroll:SetVerticalScroll(0)
            GD:RefreshUI()
        end)
        panel.filters[#panel.filters + 1] = button
    end
    panel.recordClear = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.recordClear:SetSize(130, 26)
    panel.recordClear:SetPoint("TOPRIGHT", -16, -12)
    panel.recordClear:SetText("Record raid clear")
    panel.recordClear:SetScript("OnClick", function()
        GD.ShowInputForm("Record guild raid clear", {
            { label = "Raid or boss cleared", value = "", max = 100 },
            { label = "Details (team, difficulty, etc.)", value = "", max = 250 },
        }, function(values) return GD:PostRaidAchievement(values[1], values[2]) end, "Record")
    end)
    panel.postShoutout = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.postShoutout:SetSize(130, 26)
    panel.postShoutout:SetPoint("TOPRIGHT", -16, -12)
    panel.postShoutout:SetText("Give a shoutout")
    panel.postShoutout:SetScript("OnClick", function()
        GD.ShowInputForm("Give a guild shoutout", {
            { label = "Guild member", value = "", max = 80 },
            { label = "Your message", value = "", max = 250, multiline = true },
        }, function(values) return GD:PostShoutout(values[1], values[2]) end, "Post")
    end)
    panel.clearAwards = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.clearAwards:SetSize(114, 26)
    panel.clearAwards:SetPoint("RIGHT", panel.recordClear, "LEFT", -8, 0)
    panel.clearAwards:SetText("Clear category")
    panel.clearAwards:SetScript("OnClick", function()
        if not GD:CanDeleteGuildAchievements() then return end
        local records = GD:GetGuildAchievements(panel.filter)
        local ids = {}
        for _, record in ipairs(records) do ids[#ids + 1] = record.id end
        local category = panel.filter == "R" and "raid clears" or panel.filter == "L" and "level awards"
            or panel.filter == "P" and "profession awards" or "achievements"
        GD:ConfirmAction("Clear " .. category .. "?", "Remove all " .. #ids .. " currently listed " .. category .. " for the guild? This cannot be undone. Recent activity is kept.", function()
            for _, id in ipairs(ids) do
                local ok, message = GD:DeleteGuildAchievement(id, true)
                if not ok then GD:RefreshUI(); return false, message end
            end
            GD:RefreshUI()
            return true, "Category cleared."
        end, "Clear")
    end)
    panel.scroll = CreateFrame("ScrollFrame", nil, panel)
    panel.scroll:SetPoint("TOPLEFT", 16, -142)
    panel.scroll:SetPoint("BOTTOMRIGHT", -30, 44)
    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetSize(100, 100)
    panel.scroll:SetScrollChild(panel.content)
    panel.empty = text(panel.content, "GameFontNormal")
    panel.empty:SetPoint("TOPLEFT", 14, -28)
    panel.empty:SetPoint("TOPRIGHT", -14, -28)
    panel.empty:SetText("No achievements in this category yet. Milestones and officer-recorded raid clears will appear here.")
    panel.achievementHeading = text(panel.content, "GameFontNormal")
    panel.achievementHeading:SetPoint("TOPLEFT", 0, -4)
    panel.achievementHeading:SetText("Achievements")
    panel.note = text(panel)
    panel.note:SetPoint("BOTTOMLEFT", 16, 12)
    panel.note:SetPoint("BOTTOMRIGHT", -16, 12)
    panel.note:SetText("Awards: latest 500, no expiry. Activity: latest 200, up to 30 days. Tracking starts with reported events.")
    panel.scroll:SetScript("OnSizeChanged", function(_, width) panel.content:SetWidth(math.max(1, width)) end)
    frame.activity = panel
    return panel
end

function GD:RefreshActivity()
    if not self.frame then return end
    local frame = self.frame
    local panel = frame.activity or build(frame)
    for _, key in ipairs({ "detailScroll", "detailTitle", "detailMeta", "detailRule", "detailBody", "footer" }) do frame[key]:Hide() end
    panel:Show()
    local colors = self:GetAppearanceColors()
    panel.title:SetTextColor(unpack(colors.accent))
    panel.summary:SetTextColor(unpack(colors.muted))
    panel.note:SetTextColor(unpack(colors.muted))
    panel.empty:SetTextColor(unpack(colors.text))
    panel.achievementHeading:SetTextColor(unpack(colors.accent))
    local isAchievements = panel.view == "Achievements"
    local isShoutouts = panel.view == "Shoutouts"
    local activeFilter = isAchievements and panel.filter or panel.activityFilter
    panel.recordClear:SetShown(isAchievements and self.bucket ~= nil and self:CanManage())
    self:StyleButton(panel.recordClear, "primary")
    panel.postShoutout:SetShown(isShoutouts and self.bucket ~= nil)
    self:StyleButton(panel.postShoutout, "primary")
    panel.clearAwards:SetShown(isAchievements and self:CanDeleteGuildAchievements())
    self:StyleButton(panel.clearAwards)
    for _, button in ipairs(panel.views) do self:StyleButton(button, button.view == panel.view and "primary" or nil) end
    for _, button in ipairs(panel.filters) do
        button:SetShown(not isShoutouts and (isAchievements or button.filter ~= "R"))
        if button.filter == "All" then button:SetText(isAchievements and "All awards" or "All activity") end
        self:StyleButton(button, button.filter == activeFilter and "primary" or nil)
    end
    panel.content:SetWidth(math.max(1, panel.scroll:GetWidth()))
    self:ImportActivityAchievements()
    local achievements = self:GetGuildAchievements(panel.filter)
    panel.clearAwards:SetEnabled(#achievements > 0)
    local records = {}
    local visible = isAchievements and achievements or isShoutouts and self:GetGuildShoutouts() or self:GetGuildActivity(activeFilter)
    for _, record in ipairs(visible) do records[#records + 1] = { record = record, award = isAchievements, shoutout = isShoutouts } end
    panel.summary:SetText(isShoutouts and (#records .. " shoutouts | Celebrate your guildmates with kudos")
        or isAchievements and (#records .. " awards | Level milestones, professions and recorded raid clears")
        or (#records .. " reports | Every 10 levels and profession milestones | Newest first"))
    panel.note:SetText(isShoutouts and "Choose Cheers, Thanks, or Epic. Click your selected reaction again to remove it."
        or isAchievements and "Give Cheers, Thanks, or Epic. One reaction per member; click again to remove it."
        or "Activity: latest 200 reports, up to 30 days. Popup preferences do not disable tracking.")
    panel.achievementHeading:SetText(panel.view)
    panel.empty:SetText(isShoutouts and "No shoutouts yet. Thank a guildmate using Give a shoutout."
        or isAchievements and "No achievements in this category yet. Milestones and officer-recorded raid clears will appear here."
        or "No recent activity in this category. New level and profession milestones will appear here.")
    panel.empty:SetShown(#records == 0)
    local y = 28
    for index, item in ipairs(records) do
        local record = item.record
        local row = panel.rows[index]
        if not row then
            row = CreateFrame("Frame", nil, panel.content, "BackdropTemplate")
            row:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
            row:SetHeight(72)
            row.accent = row:CreateTexture(nil, "ARTWORK")
            row.accent:SetPoint("TOPLEFT", 1, -1)
            row.accent:SetPoint("BOTTOMLEFT", 1, 1)
            row.accent:SetWidth(4)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(36, 36)
            row.icon:SetPoint("LEFT", 14, 0)
            row.title = text(row, "GameFontNormal")
            row.title:SetPoint("TOPLEFT", 64, -12)
            row.title:SetPoint("TOPRIGHT", -14, -12)
            row.title:SetWordWrap(false)
            row.detail = text(row)
            row.detail:SetPoint("TOPLEFT", 64, -34)
            row.detail:SetPoint("TOPRIGHT", -14, -34)
            row.detail:SetWordWrap(false)
            row.delete = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.delete:SetSize(66, 24)
            row.delete:SetPoint("TOPRIGHT", -10, -10)
            row.delete:SetText("Delete")
            row:EnableMouseWheel(true)
            row:SetScript("OnMouseWheel", function(_, delta) panel.scroll:GetScript("OnMouseWheel")(panel.scroll, delta) end)
            panel.rows[index] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", 0, -y)
        local accent = colors.accent
        if item.shoutout then
            accent = { 0.30, 0.82, 0.65 }
        elseif record.kind == "R" then
            accent = { 1, 0.78, 0.25 }
        elseif record.kind == "L" then
            local _, token = self:GetRaidPlayerClass(record.by)
            local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token or ""]
            if classColor then accent = { classColor.r, classColor.g, classColor.b } end
        end
        local tint = 0.08
        row:SetBackdropColor(colors.alternate[1] * (1 - tint) + accent[1] * tint,
            colors.alternate[2] * (1 - tint) + accent[2] * tint,
            colors.alternate[3] * (1 - tint) + accent[3] * tint, colors.alternate[4] or 1)
        local borderStrength = 0.75
        row:SetBackdropBorderColor(accent[1] * borderStrength, accent[2] * borderStrength, accent[3] * borderStrength, 1)
        row.accent:SetColorTexture(accent[1], accent[2], accent[3], 1)
        row.accent:Show()
        row.title:SetTextColor(unpack(accent))
        row.detail:SetTextColor(unpack(colors.muted))
        local canDelete = item.award and self:CanDeleteGuildAchievements()
        row.delete:SetShown(canDelete == true)
        self:StyleButton(row.delete)
        row.title:ClearAllPoints()
        row.title:SetPoint("TOPLEFT", 64, -12)
        row.title:SetPoint("TOPRIGHT", canDelete and -86 or -14, -12)
        local recordId = record.id
        row.delete:SetScript("OnClick", function()
            local label = record.kind == "R" and record.title or (record.by .. " - " .. tostring(record.value) .. " " .. (record.profession or ""))
            GD:ConfirmAction("Delete achievement?", "Remove this achievement for the guild: " .. GD:Display(label),
                function() return GD:DeleteGuildAchievement(recordId) end, "Delete")
        end)
        local title, detail, icon
        if item.shoutout then
            title = "Shoutout to " .. record.target
            detail = "From " .. record.by .. " - " .. record.text
            icon = "Interface/Icons/Spell_Holy_BlessingOfStrength"
        elseif record.kind == "R" then
            title = "Raid cleared: " .. record.title
            detail = "Recorded by " .. record.by .. (record.details ~= "" and (" - " .. record.details) or "")
            icon = "Interface/Icons/INV_Misc_GroupLooking"
        elseif record.kind == "L" then
            title = record.by .. " reached level " .. record.value .. "!"
            detail = item.award and (record.value == 60 and "Level 60 achieved" or "Level milestone") or "Level-up"
            icon = "Interface/Icons/Achievement_Level_" .. record.value
        else
            title = record.by .. " reached " .. record.value .. " in " .. record.profession .. "!"
            detail = record.value == 300 and "Profession mastered" or "Profession milestone"
            icon = self:GetProfessionIcon(record.profession)
        end
        row.title:SetText(self:Display(title))
        row.detail:SetText(date("%b %d, %Y  %I:%M %p", record.ts) .. "  |  " .. self:Display(detail))
        row.icon:SetTexture(icon)
        local hasKudos = item.award or item.shoutout
        local height = 72
        row.detail:SetWordWrap(item.shoutout == true)
        if item.shoutout then height = math.max(104, 34 + row.detail:GetStringHeight() + 44)
        elseif hasKudos then height = 104 end
        row:SetHeight(height)
        if hasKudos then self:RefreshKudosButtons(row, item.shoutout and "S" or "A", record)
        else for _, button in ipairs(row.kudosButtons or {}) do button:Hide() end end
        row:Show()
        y = y + height + 10
    end
    for i = #records + 1, #panel.rows do panel.rows[i]:Hide() end
    panel.content:SetHeight(math.max(panel.scroll:GetHeight(), y))
    self:StyleScrollFrame(panel.scroll)
end

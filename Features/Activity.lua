-- Bounded guild history for reported level-ups and profession milestones.
local _, GD = ...
local LIMIT, RETENTION, HISTORY_LIMIT = 200, 30 * 86400, 50
GD:RegisterBucket("activity", function() return {} end)
GD:RegisterTab("Activity", function() return "" end)

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
        if value < 2 or value > 60 or profession ~= "" then return false end
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
    trim()
    if broadcast then self:SendRecord("AV", id, ts, author, payload(record)) end
    if self.RefreshUI and self.activeTab == "Activity" then self:RefreshUI() end
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
        if not filter or filter == "All" or filter == record.kind then result[#result + 1] = record end
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
    panel.title = text(panel, "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 16, -16)
    panel.title:SetText("Guild Activity")
    panel.summary = text(panel)
    panel.summary:SetPoint("TOPLEFT", 16, -42)
    for index, option in ipairs({ { "All activity", "All" }, { "Level-ups", "L" }, { "Professions", "P" } }) do
        local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetPoint("TOPLEFT", 16 + (index - 1) * 126, -66)
        button:SetSize(116, 26)
        button:SetText(option[1])
        button.filter = option[2]
        button:SetScript("OnClick", function(self)
            panel.filter = self.filter
            panel.scroll:SetVerticalScroll(0)
            GD:RefreshUI()
        end)
        panel.filters[#panel.filters + 1] = button
    end
    panel.scroll = CreateFrame("ScrollFrame", nil, panel)
    panel.scroll:SetPoint("TOPLEFT", 16, -106)
    panel.scroll:SetPoint("BOTTOMRIGHT", -30, 44)
    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetSize(100, 100)
    panel.scroll:SetScrollChild(panel.content)
    panel.empty = text(panel.content, "GameFontNormal")
    panel.empty:SetPoint("TOPLEFT", 14, -16)
    panel.empty:SetPoint("TOPRIGHT", -14, -16)
    panel.empty:SetText("No activity yet. New level-ups and profession milestones from GuildDB members will appear here.")
    panel.note = text(panel)
    panel.note:SetPoint("BOTTOMLEFT", 16, 12)
    panel.note:SetPoint("BOTTOMRIGHT", -16, 12)
    panel.note:SetText("Reports from GuildDB members. Keeps the latest 200 entries for up to 30 days.")
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
    for _, button in ipairs(panel.filters) do self:StyleButton(button, button.filter == panel.filter and "primary" or nil) end
    panel.content:SetWidth(math.max(1, panel.scroll:GetWidth()))
    local records = self:GetGuildActivity(panel.filter)
    panel.summary:SetText(#records .. " entries | Level-ups and profession milestones | Newest first")
    panel.empty:SetShown(#records == 0)
    for index, record in ipairs(records) do
        local row = panel.rows[index]
        if not row then
            row = CreateFrame("Frame", nil, panel.content, "BackdropTemplate")
            row:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
            row:SetPoint("TOPLEFT", 0, -(index - 1) * 82)
            row:SetPoint("TOPRIGHT", 0, -(index - 1) * 82)
            row:SetHeight(72)
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
            row:EnableMouseWheel(true)
            row:SetScript("OnMouseWheel", function(_, delta) panel.scroll:GetScript("OnMouseWheel")(panel.scroll, delta) end)
            panel.rows[index] = row
        end
        row:SetBackdropColor(unpack(colors.alternate))
        row:SetBackdropBorderColor(colors.accent[1] * 0.5, colors.accent[2] * 0.5, colors.accent[3] * 0.5, 1)
        row.title:SetTextColor(unpack(colors.text))
        row.detail:SetTextColor(unpack(colors.muted))
        local description = record.kind == "L" and (" reached level " .. record.value .. "!")
            or (" reached " .. record.value .. " in " .. record.profession .. "!")
        row.title:SetText(self:Display(record.by .. description))
        row.detail:SetText(date("%b %d, %Y  %H:%M", record.ts) .. "  |  " .. (record.kind == "L" and "Level-up" or "Profession milestone"))
        row.icon:SetTexture(record.kind == "L" and "Interface/Icons/INV_Misc_Book_11" or "Interface/Icons/Trade_BlackSmithing")
        row:Show()
    end
    for i = #records + 1, #panel.rows do panel.rows[i]:Hide() end
    panel.content:SetHeight(math.max(panel.scroll:GetHeight(), #records * 82))
    self:StyleScrollFrame(panel.scroll)
end

-- Current guild makeup, derived from the complete roster and shared profiles.
local _, GD = ...
GD:RegisterTab("Analytics", function() return "" end)

local function field(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value ~= "" then return value end
end

local function add(chart, label, color, order)
    label = label or "Unknown"
    local row = chart.counts[label]
    if not row then
        row = { label = label, count = 0, color = color, order = order }
        chart.counts[label] = row
        chart.rows[#chart.rows + 1] = row
    end
    row.count = row.count + 1
end

function GD:GetAnalyticsData(onlineOnly)
    local data = { total = 0, online = 0, included = 0, charts = {} }
    local definitions = {
        { "Classes", "CURRENT GUILD ROSTER" }, { "Races", "FROM SHARED PROFILES" },
        { "Specs", "FROM SHARED PROFILES" }, { "Roles", "FROM SHARED PROFILES" },
        { "Levels", "CURRENT GUILD ROSTER" },
    }
    for i, definition in ipairs(definitions) do
        data.charts[i] = { title = definition[1], source = definition[2], counts = {}, rows = {} }
    end
    for _, member in ipairs(self.guildName and self.roster or {}) do
        data.total = data.total + 1
        if member.online then data.online = data.online + 1 end
        if not onlineOnly or member.online then
            data.included = data.included + 1
            local profile = self:GetProfile(member.name) or {}
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.classFile]
            local class = field(member.class) or field(member.classFile)
            add(data.charts[1], class, color)
            add(data.charts[2], field(profile.race))
            local spec = field(profile.spec)
            add(data.charts[3], spec and (spec .. (class and (" - " .. class) or "")), spec and color)
            local role = field(profile.role)
            local normalized = role and role:lower()
            if normalized == "tank" then role = "Tank"
            elseif normalized == "healer" or normalized == "heal" then role = "Healer"
            elseif normalized == "dps" or normalized == "damage" then role = "DPS" end
            local roleColors = { Tank = { r = 0.35, g = 0.55, b = 0.95 }, Healer = { r = 0.25, g = 0.80, b = 0.55 }, DPS = { r = 0.95, g = 0.38, b = 0.45 } }
            add(data.charts[4], role, roleColors[role])
            local level = tonumber(member.level)
            local band, order = "Unknown", 999
            if level and level > 0 then
                local start = math.floor((level - 1) / 10) * 10 + 1
                band, order = start .. " - " .. (start + 9), -start
            end
            add(data.charts[5], band, nil, order)
        end
    end
    for _, chart in ipairs(data.charts) do
        table.sort(chart.rows, function(a, b)
            if chart.title == "Levels" then
                if (a.order or 999) ~= (b.order or 999) then return (a.order or 999) < (b.order or 999) end
            elseif a.count ~= b.count then return a.count > b.count end
            return a.label < b.label
        end)
    end
    return data
end

local function label(parent, font)
    local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    return text
end

local function build(frame)
    local panel = CreateFrame("Frame", nil, frame.detailPanel)
    panel:SetAllPoints()
    panel.title = label(panel, "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 16, -16)
    panel.title:SetText("Guild makeup")
    panel.summary = label(panel)
    panel.summary:SetPoint("TOPLEFT", 16, -42)
    panel.filter = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.filter:SetSize(130, 26)
    panel.filter:SetPoint("TOPRIGHT", -16, -12)
    panel.filter:SetScript("OnClick", function()
        panel.onlineOnly = not panel.onlineOnly
        GD:RefreshUI()
    end)
    panel.scroll = CreateFrame("ScrollFrame", nil, panel)
    panel.scroll:SetPoint("TOPLEFT", 14, -68)
    panel.scroll:SetPoint("BOTTOMRIGHT", -14, 34)
    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.scroll:SetScrollChild(panel.content)
    panel.scroll:EnableMouseWheel(true)
    panel.scroll:SetScript("OnMouseWheel", function(scroll, delta)
        local maximum = math.max(0, panel.content:GetHeight() - scroll:GetHeight())
        scroll:SetVerticalScroll(math.max(0, math.min(maximum, scroll:GetVerticalScroll() - delta * 48)))
    end)
    panel.note = label(panel)
    panel.note:SetPoint("BOTTOMLEFT", 16, 12)
    panel.note:SetText("Unknown = data unavailable. Counts are characters, including alts.")
    panel.cards = {}
    for i = 1, 5 do
        local card = CreateFrame("Frame", nil, panel.content, "BackdropTemplate")
        card:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
        card.title = label(card, "GameFontNormal")
        card.title:SetPoint("TOPLEFT", 12, -12)
        card.source = label(card)
        card.source:SetPoint("TOPLEFT", 12, -32)
        card.rows = {}
        card.empty = label(card)
        card.empty:SetPoint("TOPLEFT", 12, -60)
        card.empty:SetText("No members to display.")
        panel.cards[i] = card
    end
    panel:SetScript("OnSizeChanged", function()
        if panel:IsShown() and GD.activeTab == "Analytics" then GD:RefreshAnalytics() end
    end)
    frame.analytics = panel
    return panel
end

function GD:RefreshAnalytics()
    local frame = self.frame
    local panel = frame.analytics or build(frame)
    for _, key in ipairs({ "detailScroll", "detailTitle", "detailMeta", "detailRule", "footer" }) do frame[key]:Hide() end
    panel:Show()
    local colors = self:GetAppearanceColors()
    local accent, muted = colors.accent, colors.muted
    self:StyleButton(panel.filter)
    panel.filter:SetText(panel.onlineOnly and "Online only" or "All members")
    panel.title:SetTextColor(unpack(accent))
    panel.note:SetTextColor(unpack(muted))
    local data = self:GetAnalyticsData(panel.onlineOnly)
    panel.summary:SetText(not self.guildName and "Join a guild to view analytics." or
        (data.total == 0 and "Waiting for the guild roster..." or
        (data.total .. " members   /   " .. data.online .. " online   /   " .. data.included .. " shown")))
    panel.summary:SetTextColor(unpack(colors.text))
    local width = math.max(620, panel.scroll:GetWidth())
    panel.content:SetWidth(width)
    panel.note:SetWidth(math.max(100, panel:GetWidth() - 32))
    local topHeight, bottomHeight = 220, 170
    for i, chart in ipairs(data.charts) do
        if i <= 3 then topHeight = math.max(topHeight, 62 + #chart.rows * 22)
        else bottomHeight = math.max(bottomHeight, 62 + #chart.rows * 22) end
    end
    for i, chart in ipairs(data.charts) do
        local card = panel.cards[i]
        local columns, column = i <= 3 and 3 or 2, i <= 3 and i - 1 or i - 4
        local cardWidth = (width - (columns - 1) * 10) / columns
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", column * (cardWidth + 10), i <= 3 and 0 or -topHeight - 10)
        card:SetSize(cardWidth, i <= 3 and topHeight or bottomHeight)
        card:SetBackdropColor(unpack(colors.alternate))
        card:SetBackdropBorderColor(accent[1] * 0.4, accent[2] * 0.4, accent[3] * 0.4, 1)
        card.title:SetText(chart.title)
        card.title:SetTextColor(unpack(accent))
        card.source:SetText(chart.source)
        card.source:SetTextColor(unpack(muted))
        card.source:SetWidth(cardWidth - 24)
        card.source:SetWordWrap(false)
        card.empty:SetShown(#chart.rows == 0)
        local maximum = 1
        for _, item in ipairs(chart.rows) do maximum = math.max(maximum, item.count) end
        for index, item in ipairs(chart.rows) do
            local row = card.rows[index]
            if not row then
                row = CreateFrame("Frame", nil, card)
                row.name = label(row)
                row.track = row:CreateTexture(nil, "BACKGROUND")
                row.bar = row:CreateTexture(nil, "ARTWORK")
                row.count = label(row)
                row:EnableMouse(true)
                row:SetScript("OnEnter", function(widget)
                    GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
                    GameTooltip:SetText(widget.tooltip)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                card.rows[index] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 12, -54 - (index - 1) * 22)
            row:SetSize(cardWidth - 24, 20)
            local barWidth = math.max(20, (cardWidth - 24) * 0.34)
            row.name:SetPoint("LEFT")
            row.name:SetWidth(cardWidth - 24 - barWidth - 34)
            row.name:SetWordWrap(false)
            row.name:SetText(self:Display(item.label))
            local color = item.color or (item.label == "Unknown" or item.label == "Not set") and
                { r = muted[1], g = muted[2], b = muted[3] } or { r = accent[1], g = accent[2], b = accent[3] }
            row.name:SetTextColor(color.r, color.g, color.b)
            row.count:SetPoint("RIGHT")
            row.count:SetWidth(28)
            row.count:SetJustifyH("RIGHT")
            row.count:SetText(item.count)
            row.count:SetTextColor(unpack(colors.text))
            row.track:SetPoint("RIGHT", -32, 0)
            row.track:SetSize(barWidth, 7)
            row.track:SetColorTexture(muted[1], muted[2], muted[3], 0.18)
            row.bar:SetPoint("LEFT", row.track, "LEFT")
            row.bar:SetSize(math.max(1, barWidth * item.count / maximum), 7)
            row.bar:SetColorTexture(color.r, color.g, color.b, 1)
            row.tooltip = self:Display(item.label) .. ": " .. item.count .. " / " .. data.included ..
                string.format(" (%.1f%%)", data.included > 0 and item.count * 100 / data.included or 0)
            row:Show()
        end
        for index = #chart.rows + 1, #card.rows do card.rows[index]:Hide() end
    end
    panel.content:SetHeight(topHeight + bottomHeight + 10)
    local maximumScroll = math.max(0, panel.content:GetHeight() - panel.scroll:GetHeight())
    panel.scroll:SetVerticalScroll(math.min(panel.scroll:GetVerticalScroll(), maximumScroll))
end

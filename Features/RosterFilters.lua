-- Session-local roster filters; profile data may be unknown for non-addon users.
local _, GD = ...
local professions = {"Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring"}
local function lower(value) return tostring(value or ""):lower():match("^%s*(.-)%s*$") end

function GD:RosterMemberMatchesFilters(member, profile, filters)
    filters, profile = filters or {}, profile or {}
    if filters.class and filters.class ~= "" and lower(member.classFile or member.class) ~= lower(filters.class) then return false end
    local role = lower(profile.role)
    if role == "damage" or role == "damage dealer" then role = "dps" end
    if role ~= "tank" and role ~= "healer" and role ~= "dps" then role = "unknown" end
    if filters.role and filters.role ~= "" and role ~= lower(filters.role) then return false end
    local minimum, maximum, level = tonumber(filters.minimum), tonumber(filters.maximum), tonumber(member.level)
    if minimum and (not level or level < minimum) then return false end
    if maximum and (not level or level > maximum) then return false end
    if filters.profession and filters.profession ~= "" then
        local found = false
        for entry in tostring(profile.professions or ""):gmatch("[^,;\n]+") do
            local name = lower(entry):gsub("%s+%d+.*$", "")
            if name == lower(filters.profession) then found = true; break end
        end
        if not found then return false end
    end
    return true
end

local function classChoices()
    local result, seen = {{value = "", label = "All classes"}}, {}
    for _, member in ipairs(GD.roster or {}) do
        local key = member.classFile or member.class
        if key and not seen[key] then
            seen[key] = true
            result[#result + 1] = {value = key, label = member.class or key}
        end
    end
    table.sort(result, function(a, b) if a.value == "" then return b.value ~= "" end; if b.value == "" then return false end; return a.label < b.label end)
    return result
end

local function choicesFor(key)
    if key == "class" then return classChoices() end
    local result = {{value = "", label = key == "role" and "All roles" or "All professions"}}
    for _, value in ipairs(key == "role" and {"Tank", "Healer", "DPS", "Unknown"} or professions) do
        result[#result + 1] = {value = value, label = value}
    end
    return result
end

local function build(frame)
    local bar = CreateFrame("Frame", nil, frame.listPanel)
    bar:SetPoint("TOPLEFT", 10, -39)
    bar:SetPoint("TOPRIGHT", -10, -39)
    bar:SetHeight(76)
    frame.rosterFilterBar = bar
    bar.fields, bar.labels = {}, {}
    local toggle = CreateFrame("Button", nil, frame.listPanel, "UIPanelButtonTemplate")
    frame.rosterFilterToggle = toggle
    toggle:SetSize(112, 26)
    toggle:SetPoint("TOPRIGHT", -10, -10)
    toggle:SetScript("OnClick", function()
        frame.rosterFiltersExpanded = not frame.rosterFiltersExpanded
        GD:RefreshUI()
    end)
    local menu = CreateFrame("Frame", "GuildDBRosterFilterMenu", UIParent, "BackdropTemplate")
    bar.menu = menu
    menu:SetFrameStrata("TOOLTIP")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1})
    menu.rows = {}
    menu:Hide()
    UISpecialFrames = UISpecialFrames or {}
    table.insert(UISpecialFrames, "GuildDBRosterFilterMenu")
    frame:HookScript("OnHide", function() menu:Hide() end)
    local function openMenu(control, key)
        if menu:IsShown() and menu.owner == control then menu:Hide(); return end
        menu.owner = control
        local options = choicesFor(key)
        menu:SetSize(math.max(150, control:GetWidth()), #options * 24 + 8)
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", control, "BOTTOMLEFT", 0, -3)
        GD:StyleSurface(menu)
        for index, option in ipairs(options) do
            local row = menu.rows[index]
            if not row then row = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate"); menu.rows[index] = row end
            local selectedOption = option
            row:SetSize(menu:GetWidth() - 8, 22)
            row:SetPoint("TOPLEFT", 4, -4 - (index - 1) * 24)
            if not row:GetFontString() then row:SetFontString(row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")) end
            row:SetText(option.label)
            GD:StyleButton(row, (GD.rosterFilters or {})[key] == option.value and "primary" or nil)
            row:SetScript("OnClick", function()
                GD.rosterFilters = GD.rosterFilters or {}
                GD.rosterFilters[key] = selectedOption.value
                menu:Hide()
                GD:RefreshUI()
            end)
            row:Show()
        end
        for i = #options + 1, #menu.rows do menu.rows[i]:Hide() end
        menu:Show()
    end
    for _, definition in ipairs({{"class", "Class"}, {"role", "Role"}, {"level", "Level range"}, {"profession", "Profession"}}) do
        local key = definition[1]
        local title = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        title:SetText(definition[2])
        bar.labels[key] = title
        if key ~= "level" then
            local control = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
            control:SetScript("OnClick", function() openMenu(control, key) end)
            bar.fields[key] = control
        end
    end
    for _, key in ipairs({"minimum", "maximum"}) do
        local input = CreateFrame("EditBox", nil, bar, "BackdropTemplate")
        GD:StyleEditBox(input)
        input:SetAutoFocus(false)
        input:SetNumeric(true)
        input:SetMaxLetters(2)
        input:SetJustifyH("CENTER")
        input:EnableMouse(true)
        input:SetScript("OnEscapePressed", function(control) control:ClearFocus(); GD:CloseWindowsOnEscape() end)
        input:SetScript("OnEnterPressed", function(control) control:ClearFocus() end)
        input:SetScript("OnHide", function(control) control:ClearFocus() end)
        input:SetScript("OnTextChanged", function(control)
            if bar.loading then return end
            GD.rosterFilters = GD.rosterFilters or {}
            GD.rosterFilters[key] = control:GetText()
            GD:RefreshUI()
        end)
        bar.fields[key] = input
    end
    bar.rangeHint = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    bar.rangeHint:SetText("Min     Max")
    bar.summary = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    bar.summary:SetPoint("TOPLEFT", 0, -56)
    bar.clear = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    bar.clear:SetHeight(24)
    bar.clear:SetPoint("TOPLEFT", bar.fields.profession, "BOTTOMLEFT", 0, -6)
    bar.clear:SetPoint("TOPRIGHT", bar.fields.profession, "BOTTOMRIGHT", 0, -6)
    bar.clear:SetText("Clear filters")
    bar.clear:SetScript("OnClick", function()
        GD.rosterFilters = {}
        bar.loading = true
        for _, key in ipairs({"minimum", "maximum"}) do bar.fields[key]:SetText(""); bar.fields[key]:ClearFocus() end
        bar.loading = false
        menu:Hide()
        GD:RefreshUI()
    end)
    return bar
end

function GD:RefreshRosterFilters(visible, count)
    local frame = self.frame
    if not frame then return end
    if not visible then
        if frame.rosterFilterBar then frame.rosterFilterBar:Hide(); frame.rosterFilterBar.menu:Hide() end
        if frame.rosterFilterToggle then frame.rosterFilterToggle:Hide() end
        return
    end
    local bar = frame.rosterFilterBar or build(frame)
    local colors, filters = self:GetAppearanceColors(), self.rosterFilters or {}
    local active = 0
    for _, key in ipairs({"class", "role", "minimum", "maximum", "profession"}) do
        if filters[key] and filters[key] ~= "" then active = active + 1 end
    end
    frame.rosterFilterToggle:SetText(active > 0 and ("Filters (%d)"):format(active) or "Filters")
    self:StyleButton(frame.rosterFilterToggle, (frame.rosterFiltersExpanded or active > 0) and "primary" or nil)
    frame.rosterFilterToggle:Show()
    if not frame.rosterFiltersExpanded then
        bar:Hide()
        bar.menu:Hide()
        return
    end
    local usable, x = math.max(380, frame.listPanel:GetWidth() - 20) - 24, 0
    local levelWidth = 74
    local fractions = {class = 0.32, role = 0.25, profession = 0.43}
    for _, key in ipairs({"class", "role", "level", "profession"}) do
        local width = key == "level" and levelWidth or math.floor((usable - levelWidth) * fractions[key])
        bar.labels[key]:SetPoint("TOPLEFT", x, 0)
        bar.labels[key]:SetTextColor(unpack(colors.muted))
        if key == "level" then
            for index, name in ipairs({"minimum", "maximum"}) do
                local input = bar.fields[name]
                input:SetSize(34, 26)
                input:SetPoint("TOPLEFT", x + (index - 1) * 40, -17)
            end
            bar.rangeHint:SetPoint("TOPLEFT", x, -44)
        else
            local control, selected = bar.fields[key], nil
            for _, option in ipairs(choicesFor(key)) do if option.value == (filters[key] or "") then selected = option.label; break end end
            control:SetSize(width, 26)
            control:SetPoint("TOPLEFT", x, -17)
            control:SetText((selected or filters[key] or "All") .. "  v")
            self:StyleButton(control, filters[key] and filters[key] ~= "" and "primary" or nil)
        end
        x = x + width + 8
    end
    self:StyleButton(bar.clear)
    bar.summary:SetText(("Showing %d of %d members"):format(count or 0, #(self.roster or {})))
    bar:Show()
end

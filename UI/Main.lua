-- Dark guild workspace with a compact navigation rail and single content pane. - TEST
local _, GH = ...

local GOLD = { 0.20, 0.62, 0.98 }
local MUTED_GOLD = { 0.48, 0.60, 0.70 }
local CREAM = { 0.84, 0.89, 0.94 }
local PANEL = { 0.045, 0.055, 0.072, 0.99 }
local PANEL_ALT = { 0.075, 0.09, 0.115, 0.99 }

local function rosterText()
    if not GH.guildName then return "Join a guild to view its roster and Guild Hall." end
    if not GH.roster or #GH.roster == 0 then return "Loading the guild roster..." end
    local lines = {}
    for _, member in ipairs(GH.roster) do
        lines[#lines + 1] = member.name .. "  ·  " .. member.rank
    end
    return #lines > 0 and table.concat(lines, "\n") or "No guild members found."
end
GH:RegisterTab("Roster", rosterText)

local function setTextColor(font, color)
    font:SetTextColor(color[1], color[2], color[3])
end

function GH:StyleButton(button, variant)
    if not button then return end
    local primary = variant == "primary"
    local normalColor = primary and { 0.10, 0.32, 0.50 } or { 0.075, 0.09, 0.12 }
    local pressedColor = primary and { 0.07, 0.23, 0.37 } or { 0.045, 0.06, 0.085 }
    local borderColor = primary and { 0.20, 0.55, 0.84 } or { 0.16, 0.25, 0.34 }

    button:SetNormalTexture("Interface/Buttons/WHITE8X8")
    button:SetPushedTexture("Interface/Buttons/WHITE8X8")
    button:SetHighlightTexture("Interface/Buttons/WHITE8X8")
    button:SetDisabledTexture("Interface/Buttons/WHITE8X8")
    local normal = button:GetNormalTexture()
    local pushed = button:GetPushedTexture()
    local highlight = button:GetHighlightTexture()
    local disabled = button:GetDisabledTexture()
    if normal then normal:SetAllPoints(button); normal:SetVertexColor(normalColor[1], normalColor[2], normalColor[3], 1) end
    if pushed then pushed:SetAllPoints(button); pushed:SetVertexColor(pressedColor[1], pressedColor[2], pressedColor[3], 1) end
    if highlight then highlight:SetAllPoints(button); highlight:SetVertexColor(0.22, 0.52, 0.78, 0.20) end
    if disabled then disabled:SetAllPoints(button); disabled:SetVertexColor(0.08, 0.09, 0.11, 0.65) end

    if not button.guildHallBorder then
        local edges = {}
        for index = 1, 4 do
            edges[index] = button:CreateTexture(nil, "OVERLAY")
            edges[index]:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], 1)
        end
        edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
        edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
        edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
        edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
        button.guildHallBorder = edges
    else
        for _, edge in ipairs(button.guildHallBorder) do edge:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], 1) end
    end
    local text = button:GetFontString()
    if text then
        text:SetFontObject("GameFontNormalSmall")
        text:SetTextColor(primary and 0.92 or CREAM[1], primary and 0.97 or CREAM[2], primary and 1 or CREAM[3])
    end
end

local function guildAbbreviation(name)
    local words = {}
    for word in tostring(name or "Guild"):gmatch("%S+") do words[#words + 1] = word end
    local abbreviation = ""
    for i = 1, math.min(3, #words) do abbreviation = abbreviation .. words[i]:sub(1, 1):upper() end
    if #abbreviation < 2 and words[1] then abbreviation = words[1]:sub(1, 3):upper() end
    return abbreviation ~= "" and abbreviation or "GH"
end

local function splitSections(text)
    local sections, current = {}, {}
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        if line == "" then
            if #current > 0 then sections[#sections + 1] = table.concat(current, "\n"); current = {} end
        else
            current[#current + 1] = line
        end
    end
    if #current > 0 then sections[#sections + 1] = table.concat(current, "\n") end
    if #sections == 0 then sections[1] = "No information to display." end
    return sections
end

local dialogCounter = 0
local function showInputForm(title, fields, onAccept)
    dialogCounter = dialogCounter + 1
    local name = "GuildHallActionDialog" .. dialogCounter
    local dialog = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    local contentHeight = 0
    for _, field in ipairs(fields) do contentHeight = contentHeight + (field.multiline and 116 or 56) end
    dialog:SetSize(410, 96 + contentHeight)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetFrameLevel(100)
    dialog:EnableMouse(true)
    dialog:SetClampedToScreen(true)
    dialog:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    dialog:SetBackdropColor(0.025, 0.032, 0.043, 0.98)
    dialog:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
    dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    dialog.title:SetPoint("TOPLEFT", 18, -14)
    dialog.title:SetText(title)
    setTextColor(dialog.title, GOLD)
    dialog.inputs = {}
    dialog.dropdowns = {}
    local offset = 42
    for i, field in ipairs(fields) do
        local label = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", 18, -offset)
        label:SetText(field.label)
        setTextColor(label, CREAM)
        local height = field.multiline and 84 or 24
        local input
        if field.options then
            input = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
            GH:StyleButton(input)
            input:SetSize(370, 24)
            input:SetPoint("TOPLEFT", 20, -offset - 16)
            input.selectedValue = field.value or field.options[1]
            input:SetText(input.selectedValue or "Select...")
            -- Keep dropdown menus on UIParent so they render and receive clicks
            -- above the modal and its sibling edit boxes in the older client UI.
            local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            popup:SetSize(370, #field.options * 24 + 8)
            popup:SetFrameStrata("TOOLTIP")
            popup:SetFrameLevel(dialog:GetFrameLevel() + 10)
            popup:SetClampedToScreen(true)
            popup:EnableMouse(true)
            popup:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            popup:SetBackdropColor(0.025, 0.032, 0.043, 1)
            popup:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
            popup:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -2)
            popup:Hide()
            input.popup = popup
            dialog.dropdowns[#dialog.dropdowns + 1] = input
            local dropdownInput, dropdownPopup = input, popup
            for optionIndex, option in ipairs(field.options) do
                local chosenOption = option
                local optionButton = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
                GH:StyleButton(optionButton)
                optionButton:SetSize(356, 22)
                optionButton:SetPoint("TOPLEFT", 5, -4 - (optionIndex - 1) * 24)
                optionButton:SetText(chosenOption)
                optionButton:SetScript("OnClick", function()
                    dropdownInput.selectedValue = chosenOption
                    dropdownInput:SetText(chosenOption)
                    dropdownPopup:Hide()
                end)
            end
            input:SetScript("OnClick", function(self)
                local wasShown = dropdownPopup:IsShown()
                for _, dropdown in ipairs(dialog.dropdowns) do dropdown.popup:Hide() end
                dropdownPopup:SetShown(not wasShown)
            end)
        else
            input = CreateFrame("EditBox", nil, dialog, field.multiline and "BackdropTemplate" or "InputBoxTemplate")
            input:SetSize(370, height)
            input:SetPoint("TOPLEFT", 20, -offset - 16)
        end
        if field.multiline then
            input:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
            input:SetBackdropColor(0.04, 0.05, 0.065, 1)
            input:SetFontObject("GameFontHighlight")
            input:SetTextInsets(8, 8, 6, 6)
            input:SetMultiLine(true)
            input:SetJustifyH("LEFT")
            input:SetJustifyV("TOP")
        end
        if not field.options then
            input:SetAutoFocus(false)
            input:SetMaxLetters(field.max or 200)
            input:SetText(field.value or "")
            if field.readOnly then
                input:SetEnabled(false)
                input:SetTextColor(MUTED_GOLD[1], MUTED_GOLD[2], MUTED_GOLD[3])
            end
        end
        dialog.inputs[i] = input
        offset = offset + (field.multiline and 116 or 56)
    end
    local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() dialog:Hide() end)
    local cancel = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    GH:StyleButton(cancel)
    cancel:SetSize(92, 26)
    cancel:SetPoint("BOTTOMRIGHT", -120, 14)
    cancel:SetText("Cancel")
    cancel:SetScript("OnClick", function() dialog:Hide() end)
    local accept = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    GH:StyleButton(accept, "primary")
    accept:SetSize(92, 26)
    accept:SetPoint("LEFT", cancel, "RIGHT", 8, 0)
    accept:SetText("Save")
    accept:SetScript("OnClick", function()
        local values = {}
        for i, input in ipairs(dialog.inputs) do values[i] = input.selectedValue or input:GetText() end
        local ok, result = onAccept(values)
        if ok then dialog:Hide() end
        if result then print("Guild Hall: " .. result) end
    end)
    UISpecialFrames = UISpecialFrames or {}
    table.insert(UISpecialFrames, 1, name)
    dialog:SetScript("OnHide", function()
        for i = #UISpecialFrames, 1, -1 do if UISpecialFrames[i] == name then table.remove(UISpecialFrames, i) end end
    end)
    dialog:Show()
    dialog.inputs[1]:SetFocus()
end

local function openProfileEditor()
    local player = UnitName and UnitName("player") or ""
    GH:RefreshPlayerProfessions()
    local profile = GH:GetProfile(player) or {}
    local firstName, lastName = GH:GetPlayerNameParts()
    local playerRace = UnitRace and UnitRace("player") or ""
    local timezoneAliases = { ET = "Eastern Time (ET)", CT = "Central Time (CT)", MT = "Mountain Time (MT)", PT = "Pacific Time (PT)", UTC = "UTC" }
    local roleValue = profile.role and profile.role ~= "" and profile.role or "Flex"
    local timezoneValue = timezoneAliases[profile.timezone or ""] or (profile.timezone and profile.timezone ~= "" and profile.timezone) or "Eastern Time (ET)"
    showInputForm("Edit your member profile", {
        { label = "First name", value = firstName, max = 60, readOnly = true },
        { label = "Last name", value = lastName, max = 60, readOnly = true },
        { label = "Main role", value = roleValue, options = { "Tank", "DPS", "Healer", "Flex" } },
        { label = "Spec / playstyle", value = profile.spec or "", max = 80 },
        { label = "Time zone", value = timezoneValue, options = { "Eastern Time (ET)", "Central Time (CT)", "Mountain Time (MT)", "Pacific Time (PT)", "Alaska Time (AKT)", "Hawaii Time (HT)", "UTC", "UK Time (GMT/BST)", "Central European Time (CET/CEST)", "Eastern European Time (EET/EEST)", "India Standard Time (IST)", "Japan Standard Time (JST)", "Australian Eastern Time (AET)", "New Zealand Time (NZT)" } },
        { label = "Alts", value = profile.alts or "", max = 200 },
        { label = "Race", value = playerRace or profile.race or "", max = 60, readOnly = true },
        { label = "Professions", value = profile.professions or "Detected automatically from your Skills tab", max = 250, readOnly = true },
    }, function(values)
        return GH:SetProfile(values[1], values[2], values[3], values[4], values[5], values[6], profile.professions, values[7])
    end)
end

local function enableWheel(scroll, child)
    local function move(_, delta)
        local maximum = scroll:GetVerticalScrollRange() or 0
        local position = scroll:GetVerticalScroll() - delta * 48
        scroll:SetVerticalScroll(math.min(maximum, math.max(0, position)))
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", move)
    child:EnableMouseWheel(true)
    child:SetScript("OnMouseWheel", move)
end

local function build()
    if GH.frame then return end
    local frame = CreateFrame("Frame", "GuildHallMainFrame", UIParent)
    UISpecialFrames = UISpecialFrames or {}
    local escapeRegistered = false
    for _, frameName in ipairs(UISpecialFrames) do
        if frameName == "GuildHallMainFrame" then escapeRegistered = true; break end
    end
    if not escapeRegistered then table.insert(UISpecialFrames, "GuildHallMainFrame") end
    frame:SetSize(1080, 680)
    frame:SetScale(GH.GetSetting and GH:GetSetting("scale") or 1)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    frame.background = frame:CreateTexture(nil, "BACKGROUND")
    frame.background:SetAllPoints()
    frame.background:SetColorTexture(0.025, 0.032, 0.043, 0.99)
    GH.frame = frame

    frame.header = CreateFrame("Frame", nil, frame)
    frame.header:SetPoint("TOPLEFT", 1, -1)
    frame.header:SetPoint("TOPRIGHT", -1, -1)
    frame.header:SetHeight(70)
    frame.header:EnableMouse(true)
    frame.header:RegisterForDrag("LeftButton")
    frame.header:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame.header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    frame.headerBg = frame.header:CreateTexture(nil, "BACKGROUND")
    frame.headerBg:SetAllPoints()
    frame.headerBg:SetColorTexture(0.035, 0.052, 0.068, 1)
    frame.logoMark = frame.header:CreateTexture(nil, "ARTWORK")
    frame.logoMark:SetPoint("LEFT", 16, 0)
    frame.logoMark:SetSize(40, 40)
    frame.logoMark:SetColorTexture(0.12, 0.42, 0.68, 1)
    frame.logoAbbreviation = frame.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.logoAbbreviation:SetPoint("CENTER", frame.logoMark, "CENTER")
    frame.logoAbbreviation:SetWidth(38)
    frame.logoAbbreviation:SetJustifyH("CENTER")
    frame.logoAbbreviation:SetTextColor(0.92, 0.96, 1)
    frame.logoText = frame.header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.logoText:SetPoint("LEFT", frame.logoMark, "RIGHT", 10, 5)
    frame.logoText:SetText((GH.guildName or "Guild") .. " Hall")
    setTextColor(frame.logoText, CREAM)
    frame.version = frame.header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.version:SetPoint("TOPLEFT", frame.logoText, "BOTTOMLEFT", 0, -1)
    frame.version:SetText("HQ  ·  Guild Hall")
    frame.headerStatus = frame.header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.headerStatus:SetPoint("RIGHT", -156, 0)
    frame.headerStatus:SetJustifyH("RIGHT")
    frame.close = CreateFrame("Button", nil, frame.header, "UIPanelCloseButton")
    frame.close:SetPoint("RIGHT", -4, 0)
    frame.close:SetScript("OnClick", function() frame:Hide() end)
    frame.sync = CreateFrame("Button", nil, frame.header, "UIPanelButtonTemplate")
    GH:StyleButton(frame.sync, "primary")
    frame.sync:SetSize(104, 24)
    frame.sync:SetPoint("RIGHT", frame.close, "LEFT", -8, 0)
    frame.sync:SetText("Sync guild")
    frame.sync:RegisterForClicks("LeftButtonUp")
    frame.sync:SetScript("OnClick", function()
        local _, message = GH:RequestSync()
        print("Guild Hall: " .. tostring(message))
    end)

    frame.sidebar = CreateFrame("Frame", nil, frame)
    frame.sidebar:SetPoint("TOPLEFT", 1, -71)
    frame.sidebar:SetPoint("BOTTOMLEFT", 1, 1)
    frame.sidebar:SetWidth(198)
    frame.sidebar.bg = frame.sidebar:CreateTexture(nil, "BACKGROUND")
    frame.sidebar.bg:SetAllPoints()
    frame.sidebar.bg:SetColorTexture(0.035, 0.045, 0.06, 1)
    frame.tabButtons = {}
    frame.navTitle = frame.sidebar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.navTitle:SetPoint("TOPLEFT", 16, -16)
    frame.navTitle:SetText("N A V I G A T I O N")
    setTextColor(frame.navTitle, MUTED_GOLD)

    frame.listPanel = CreateFrame("Frame", nil, frame)
    frame.listPanel:SetPoint("TOPLEFT", 208, -88)
    frame.listPanel:SetPoint("BOTTOMLEFT", 208, 16)
    frame.listPanel:SetWidth(250)
    frame.listPanel.bg = frame.listPanel:CreateTexture(nil, "BACKGROUND")
    frame.listPanel.bg:SetAllPoints()
    frame.listPanel.bg:SetColorTexture(PANEL[1], PANEL[2], PANEL[3], PANEL[4])
    frame.listPanel:Hide()
    frame.listHeader = frame.listPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.listHeader:SetPoint("TOPLEFT", 14, -14)
    frame.listHeader:SetText("GUILD POSTS")
    setTextColor(frame.listHeader, MUTED_GOLD)
    frame.listRule = frame.listPanel:CreateTexture(nil, "ARTWORK")
    frame.listRule:SetPoint("TOPLEFT", 12, -40)
    frame.listRule:SetPoint("TOPRIGHT", -12, -40)
    frame.listRule:SetHeight(1)
    frame.listRule:SetColorTexture(0.12, 0.25, 0.37, 0.9)
    frame.rosterSearch = CreateFrame("EditBox", nil, frame.listPanel, "BackdropTemplate")
    frame.rosterSearch:SetSize(136, 26)
    frame.rosterSearch:SetPoint("TOPLEFT", 12, -10)
    frame.rosterSearch:SetAutoFocus(false)
    frame.rosterSearch:SetMaxLetters(80)
    frame.rosterSearch:SetFontObject("GameFontHighlightSmall")
    frame.rosterSearch:SetTextInsets(8, 8, 0, 0)
    frame.rosterSearch:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
    frame.rosterSearch:SetBackdropColor(0.075, 0.09, 0.12, 1)
    frame.rosterSearch.border = {}
    for index = 1, 4 do
        frame.rosterSearch.border[index] = frame.rosterSearch:CreateTexture(nil, "OVERLAY")
        frame.rosterSearch.border[index]:SetColorTexture(0.16, 0.25, 0.34, 1)
    end
    frame.rosterSearch.border[1]:SetPoint("TOPLEFT"); frame.rosterSearch.border[1]:SetPoint("TOPRIGHT"); frame.rosterSearch.border[1]:SetHeight(1)
    frame.rosterSearch.border[2]:SetPoint("BOTTOMLEFT"); frame.rosterSearch.border[2]:SetPoint("BOTTOMRIGHT"); frame.rosterSearch.border[2]:SetHeight(1)
    frame.rosterSearch.border[3]:SetPoint("TOPLEFT"); frame.rosterSearch.border[3]:SetPoint("BOTTOMLEFT"); frame.rosterSearch.border[3]:SetWidth(1)
    frame.rosterSearch.border[4]:SetPoint("TOPRIGHT"); frame.rosterSearch.border[4]:SetPoint("BOTTOMRIGHT"); frame.rosterSearch.border[4]:SetWidth(1)
    frame.rosterSearch:SetText("Search...")
    frame.rosterSearch:SetTextColor(MUTED_GOLD[1], MUTED_GOLD[2], MUTED_GOLD[3])
    frame.rosterSearch:SetScript("OnEditFocusGained", function(self)
        if self:GetText() == "Search..." then self:SetText(""); self:SetTextColor(CREAM[1], CREAM[2], CREAM[3]) end
        for _, edge in ipairs(self.border) do edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1) end
    end)
    frame.rosterSearch:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then self:SetText("Search..."); self:SetTextColor(MUTED_GOLD[1], MUTED_GOLD[2], MUTED_GOLD[3]) end
        for _, edge in ipairs(self.border) do edge:SetColorTexture(0.16, 0.25, 0.34, 1) end
    end)
    frame.rosterSearch:SetScript("OnTextChanged", function(self)
        if self:HasFocus() then GH:RefreshUI() end
    end)
    frame.rosterOnlineOnly = true
    if GH.GetSetting then frame.rosterOnlineOnly = GH:GetSetting("onlineOnly") ~= false end
    frame.rosterOnlineCheck = CreateFrame("Button", nil, frame.listPanel)
    frame.rosterOnlineCheck:SetSize(22, 22)
    frame.rosterOnlineCheck:SetPoint("LEFT", frame.rosterSearch, "RIGHT", 8, 0)
    frame.rosterOnlineCheck:SetNormalTexture("Interface/Buttons/WHITE8X8")
    frame.rosterOnlineCheck:SetPushedTexture("Interface/Buttons/WHITE8X8")
    frame.rosterOnlineCheck:SetHighlightTexture("Interface/Buttons/WHITE8X8")
    frame.rosterOnlineCheck:GetNormalTexture():SetAllPoints(frame.rosterOnlineCheck)
    frame.rosterOnlineCheck:GetNormalTexture():SetVertexColor(0.075, 0.09, 0.12, 1)
    frame.rosterOnlineCheck:GetPushedTexture():SetAllPoints(frame.rosterOnlineCheck)
    frame.rosterOnlineCheck:GetPushedTexture():SetVertexColor(0.045, 0.06, 0.085, 1)
    frame.rosterOnlineCheck:GetHighlightTexture():SetAllPoints(frame.rosterOnlineCheck)
    frame.rosterOnlineCheck:GetHighlightTexture():SetVertexColor(0.22, 0.52, 0.78, 0.20)
    frame.rosterOnlineCheck.border = {}
    for index = 1, 4 do
        frame.rosterOnlineCheck.border[index] = frame.rosterOnlineCheck:CreateTexture(nil, "OVERLAY")
        frame.rosterOnlineCheck.border[index]:SetColorTexture(0.16, 0.25, 0.34, 1)
    end
    frame.rosterOnlineCheck.border[1]:SetPoint("TOPLEFT"); frame.rosterOnlineCheck.border[1]:SetPoint("TOPRIGHT"); frame.rosterOnlineCheck.border[1]:SetHeight(1)
    frame.rosterOnlineCheck.border[2]:SetPoint("BOTTOMLEFT"); frame.rosterOnlineCheck.border[2]:SetPoint("BOTTOMRIGHT"); frame.rosterOnlineCheck.border[2]:SetHeight(1)
    frame.rosterOnlineCheck.border[3]:SetPoint("TOPLEFT"); frame.rosterOnlineCheck.border[3]:SetPoint("BOTTOMLEFT"); frame.rosterOnlineCheck.border[3]:SetWidth(1)
    frame.rosterOnlineCheck.border[4]:SetPoint("TOPRIGHT"); frame.rosterOnlineCheck.border[4]:SetPoint("BOTTOMRIGHT"); frame.rosterOnlineCheck.border[4]:SetWidth(1)
    frame.rosterOnlineCheck.mark = frame.rosterOnlineCheck:CreateTexture(nil, "OVERLAY")
    frame.rosterOnlineCheck.mark:SetTexture("Interface/Buttons/UI-CheckBox-Check")
    frame.rosterOnlineCheck.mark:SetSize(17, 17)
    frame.rosterOnlineCheck.mark:SetPoint("CENTER")
    frame.rosterOnlineCheck.mark:SetVertexColor(0.25, 0.68, 1, 1)
    frame.rosterOnlineCheck.mark:SetShown(frame.rosterOnlineOnly)
    frame.rosterOnlineCheck.label = frame.rosterOnlineCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.rosterOnlineCheck.label:SetPoint("LEFT", frame.rosterOnlineCheck, "RIGHT", 4, 0)
    frame.rosterOnlineCheck.label:SetText("Online")
    frame.rosterOnlineCheck.label:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
    frame.rosterOnlineCheck:SetScript("OnClick", function(self)
        frame.rosterOnlineOnly = not frame.rosterOnlineOnly
        self.mark:SetShown(frame.rosterOnlineOnly)
        if GH.SetSetting then GH:SetSetting("onlineOnly", frame.rosterOnlineOnly) else GH:RefreshUI() end
    end)
    frame.rosterHeaders = {}
    for _, column in ipairs({ { "NAME", "name", 10, 130 }, { "GUILD", "guild", 145, 38 }, { "LVL", "level", 185, 28 }, { "RANK", "rank", 218, 82 }, { "ZONE", "zone", 304, 120 }, { "ROLE", "role", 428, 58 }, { "HQ", "hq", 490, 55 } }) do
        local header = CreateFrame("Button", nil, frame.listPanel)
        header:SetSize(column[4], 20)
        header:SetPoint("TOPLEFT", column[3], -44)
        header.sortKey = column[2]
        header.title = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        header.title:SetAllPoints()
        header.title:SetJustifyH("LEFT")
        header.title:SetText(column[1])
        header.title:SetTextColor(MUTED_GOLD[1], MUTED_GOLD[2], MUTED_GOLD[3])
        header:SetScript("OnEnter", function(self) self.title:SetTextColor(CREAM[1], CREAM[2], CREAM[3]) end)
        header:SetScript("OnLeave", function() GH:RefreshUI() end)
        header:SetScript("OnClick", function(self)
            if GH.rosterSortField == self.sortKey then
                GH.rosterSortAscending = not GH.rosterSortAscending
            else
                GH.rosterSortField = self.sortKey
                GH.rosterSortAscending = true
            end
            GH:RefreshUI()
        end)
        frame.rosterHeaders[#frame.rosterHeaders + 1] = header
    end
    frame.rosterHeaderRule = frame.listPanel:CreateTexture(nil, "ARTWORK")
    frame.rosterHeaderRule:SetPoint("TOPLEFT", 8, -63)
    frame.rosterHeaderRule:SetPoint("TOPRIGHT", -8, -63)
    frame.rosterHeaderRule:SetHeight(1)
    frame.rosterHeaderRule:SetColorTexture(0.17, 0.21, 0.28, 0.9)
    frame.rosterEmpty = frame.listPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.rosterEmpty:SetPoint("TOPLEFT", 14, -82)
    frame.rosterEmpty:SetText("No members match these filters.")
    frame.rosterEmpty:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
    frame.rosterEmpty:Hide()
    frame.listRows = {}
    frame.listScroll = CreateFrame("ScrollFrame", nil, frame.listPanel)
    frame.listScroll:SetPoint("TOPLEFT", 8, -48)
    frame.listScroll:SetPoint("BOTTOMRIGHT", -14, 8)
    frame.listChild = CreateFrame("Frame", nil, frame.listScroll)
    frame.listChild:SetWidth(220)
    frame.listChild:SetHeight(300)
    frame.listScroll:SetScrollChild(frame.listChild)
    enableWheel(frame.listScroll, frame.listChild)

    frame.detailPanel = CreateFrame("Frame", nil, frame)
    frame.detailPanel:SetPoint("TOPLEFT", 216, -88)
    frame.detailPanel:SetPoint("BOTTOMRIGHT", -14, 16)
    frame.detailPanel.bg = frame.detailPanel:CreateTexture(nil, "BACKGROUND")
    frame.detailPanel.bg:SetAllPoints()
    frame.detailPanel.bg:SetColorTexture(PANEL[1], PANEL[2], PANEL[3], PANEL[4])
    frame.detailPanel.topAccent = frame.detailPanel:CreateTexture(nil, "ARTWORK")
    frame.detailPanel.topAccent:SetPoint("TOPLEFT", 1, -1)
    frame.detailPanel.topAccent:SetPoint("TOPRIGHT", -1, -1)
    frame.detailPanel.topAccent:SetHeight(3)
    frame.detailPanel.topAccent:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    frame.detailTitle = frame.detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.detailTitle:SetPoint("TOPLEFT", 18, -14)
    frame.detailTitle:SetWidth(560)
    frame.detailTitle:SetJustifyH("LEFT")
    setTextColor(frame.detailTitle, GOLD)
    frame.detailMeta = frame.detailPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.detailMeta:SetPoint("TOPLEFT", frame.detailTitle, "BOTTOMLEFT", 0, -5)
    frame.detailMeta:SetText("Guild Hall  ·  Shared with your guild")
    frame.detailRule = frame.detailPanel:CreateTexture(nil, "ARTWORK")
    frame.detailRule:SetPoint("TOPLEFT", 14, -58)
    frame.detailRule:SetPoint("TOPRIGHT", -14, -58)
    frame.detailRule:SetHeight(1)
    frame.detailRule:SetColorTexture(0.17, 0.21, 0.28, 0.9)
    frame.detailBody = frame.detailPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.detailBody:SetPoint("TOPLEFT", 18, -72)
    frame.detailBody:SetPoint("TOPRIGHT", -18, -72)
    frame.detailBody:SetJustifyH("LEFT")
    frame.detailBody:SetJustifyV("TOP")
    frame.detailBody:SetWordWrap(true)
    frame.detailBody:SetSpacing(5)
    frame.detailBody:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
    frame.detailScroll = CreateFrame("ScrollFrame", nil, frame.detailPanel)
    frame.detailScroll:SetPoint("TOPLEFT", 10, -66)
    frame.detailScroll:SetPoint("BOTTOMRIGHT", -28, 54)
    frame.detailChild = CreateFrame("Frame", nil, frame.detailScroll)
    frame.detailChild:SetHeight(400)
    frame.detailScroll:SetScrollChild(frame.detailChild)
    enableWheel(frame.detailScroll, frame.detailChild)
    frame.detailBody:ClearAllPoints()
    frame.detailBody:SetParent(frame.detailChild)
    frame.detailBody:SetPoint("TOPLEFT", 4, -6)
    frame.detailScroll:SetScript("OnSizeChanged", function(self, width)
        frame.detailChild:SetWidth(math.max(100, width - 4))
        frame.detailBody:SetWidth(math.max(80, width - 24))
    end)
    frame.pvpTitleSeason = frame.detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.pvpTitleSeason:SetPoint("LEFT", frame.detailTitle, "RIGHT", 14, -1)
    frame.pvpTitleSeason:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    frame.pvpSummary = frame.detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.pvpSummary:SetPoint("TOPLEFT", 18, -62)
    frame.pvpInfo = frame.detailPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.pvpInfo:SetPoint("TOPLEFT", 18, -86)
    frame.pvpTableRule = frame.detailPanel:CreateTexture(nil, "ARTWORK")
    frame.pvpTableRule:SetPoint("TOPLEFT", 14, -132)
    frame.pvpTableRule:SetPoint("TOPRIGHT", -14, -132)
    frame.pvpTableRule:SetHeight(1)
    frame.pvpTableRule:SetColorTexture(0.12, 0.25, 0.37, 0.9)
    frame.pvpHeaders = {}
    local function addPvpHeader(text, x, width, justify)
        local header = frame.detailPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        header:SetPoint("TOPLEFT", x, -113)
        header:SetWidth(width)
        header:SetJustifyH(justify or "LEFT")
        header:SetText(text)
        header:SetTextColor(MUTED_GOLD[1], MUTED_GOLD[2], MUTED_GOLD[3])
        frame.pvpHeaders[#frame.pvpHeaders + 1] = header
    end
    addPvpHeader("#", 12, 28)
    addPvpHeader("PLAYER", 48, 170)
    addPvpHeader("POINTS", 235, 58, "RIGHT")
    addPvpHeader("KILLS", 320, 50, "RIGHT")
    addPvpHeader("RECENT 1-5 PT KILLS", 390, 142)
    addPvpHeader("LAST KILL", 550, 220)
    frame.pvpRows = {}
    frame.pvpEmpty = frame.detailChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.pvpEmpty:SetPoint("TOPLEFT", 12, -14)
    frame.pvpEmpty:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
    frame.pvpMyButton = CreateFrame("Button", nil, frame.detailPanel, "UIPanelButtonTemplate")
    GH:StyleButton(frame.pvpMyButton)
    frame.pvpMyButton:SetSize(98, 26)
    frame.pvpMyButton:SetPoint("TOPRIGHT", -282, -12)
    frame.pvpMyButton:SetScript("OnClick", function()
        frame.pvpMyOnly = not frame.pvpMyOnly
        GH:RefreshUI()
    end)
    frame.pvpSeasonButton = CreateFrame("Button", nil, frame.detailPanel, "UIPanelButtonTemplate")
    GH:StyleButton(frame.pvpSeasonButton, "primary")
    frame.pvpSeasonButton:SetSize(112, 26)
    frame.pvpSeasonButton:SetPoint("LEFT", frame.pvpMyButton, "RIGHT", 8, 0)
    frame.pvpSeasonButton:SetText("New season")
    frame.pvpSeasonButton:SetScript("OnClick", function()
        if not GH:CanManage() then return end
        local currentName = GH.bucket and GH.bucket.pvpSeason and GH.bucket.pvpSeason.name or ""
        local currentNumber = tonumber(currentName:match("(%d+)$")) or 0
        showInputForm("Start a PvP season", {
            { label = "Season name", value = "Season " .. tostring(currentNumber + 1), max = 80 },
        }, function(values) return GH:StartPvPSeason(values[1]) end)
    end)
    frame.pvpScopeButton = CreateFrame("Button", nil, frame.detailPanel, "UIPanelButtonTemplate")
    GH:StyleButton(frame.pvpScopeButton)
    frame.pvpScopeButton:SetSize(116, 26)
    frame.pvpScopeButton:SetPoint("LEFT", frame.pvpSeasonButton, "RIGHT", 8, 0)
    frame.pvpScopeButton:SetScript("OnClick", function()
        frame.pvpAllTime = not frame.pvpAllTime
        GH:RefreshUI()
    end)
    frame.eventCreateButton = CreateFrame("Button", nil, frame.detailPanel, "UIPanelButtonTemplate")
    GH:StyleButton(frame.eventCreateButton, "primary")
    frame.eventCreateButton:SetSize(112, 26)
    frame.eventCreateButton:SetPoint("TOPRIGHT", -18, -12)
    frame.eventCreateButton:SetText("New event")
    frame.eventCreateButton:SetScript("OnClick", function()
        local tomorrow = time() + 86400
        showInputForm("Schedule a raid or event", {
            { label = "Title", value = "Guild event", max = 100 },
            { label = "Date (YYYY-MM-DD)", value = date("%Y-%m-%d", tomorrow), max = 10 },
            { label = "Start time, local (HH:MM, 24-hour)", value = "20:00", max = 5 },
            { label = "Details", value = "", max = 300, multiline = true },
        }, function(values)
            local eventType = frame.eventCreateType or "event"
            return GH:PostEventFields(values[2], values[3], values[1], values[4], eventType)
        end)
    end)
    frame.eventCreateTypeButton = CreateFrame("Button", nil, frame.detailPanel, "UIPanelButtonTemplate")
    GH:StyleButton(frame.eventCreateTypeButton)
    frame.eventCreateTypeButton:SetSize(82, 26)
    frame.eventCreateTypeButton:SetPoint("RIGHT", frame.eventCreateButton, "LEFT", -8, 0)
    frame.eventCreateTypeButton:SetText("Event")
    frame.eventCreateTypeButton:SetScript("OnClick", function()
        frame.eventCreateType = frame.eventCreateType == "raid" and "event" or "raid"
        frame.eventCreateTypeButton:SetText(frame.eventCreateType == "raid" and "Raid" or "Event")
    end)
    -- Parent the primary action to the main window rather than the detail panel.
    -- The detail scroll frame can otherwise sit above this button in older clients.
    frame.contentActionButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    GH:StyleButton(frame.contentActionButton, "primary")
    frame.contentActionButton:SetSize(130, 26)
    frame.contentActionButton:RegisterForClicks("LeftButtonUp")
    frame.contentActionButton:SetFrameStrata("DIALOG")
    frame.contentActionButton:SetFrameLevel(frame:GetFrameLevel() + 50)
    frame.contentActionButton:SetPoint("TOPRIGHT", frame.detailPanel, "TOPRIGHT", -18, -12)
    frame.contentActionButton:SetScript("OnClick", function()
        local tab = frame.activeTab
        if tab == "Announcements" then
            showInputForm("Post an announcement", {
                { label = "Title", value = "", max = 120 },
                { label = "Message", value = "", max = 600, multiline = true },
            }, function(values) return GH:PostAnnouncement(values[1], values[2]) end)
        elseif tab == "Guide" then
            local guide = GH.bucket and GH.bucket.guide or {}
            showInputForm("Edit guild guide", {
                { label = "Guild rules", value = guide.rules or "", max = 700, multiline = true },
                { label = "Loot rules", value = guide.loot or "", max = 700, multiline = true },
            }, function(values) return GH:SetGuide(values[1], values[2]) end)
        elseif tab == "Shoutouts" then
            showInputForm("Give a guild shoutout", {
                { label = "Member name", value = "", max = 80 },
                { label = "Message", value = "", max = 250, multiline = true },
            }, function(values) return GH:PostShoutout(values[1], values[2]) end)
        elseif tab == "Looking For" then
            showInputForm("Post a group request", {
                { label = "Role", value = "DPS", max = 60 },
                { label = "Activity", value = "", max = 100 },
                { label = "Details", value = "", max = 250, multiline = true },
            }, function(values) return GH:PostLookingRequest(values[1], values[2], values[3]) end)
        elseif tab == "Crafting" then
            showInputForm("Request a craft", {
                { label = "Item or recipe", value = "", max = 100 },
                { label = "Details", value = "", max = 300, multiline = true },
            }, function(values) return GH:PostCraftingRequest(values[1], values[2]) end)
        elseif tab == "Polls" then
            showInputForm("Create a guild poll", {
                { label = "Question", value = "", max = 120 },
                { label = "Option 1", value = "", max = 60 },
                { label = "Option 2", value = "", max = 60 },
                { label = "Option 3 (optional)", value = "", max = 60 },
                { label = "Option 4 (optional)", value = "", max = 60 },
            }, function(values)
                local options = {}
                for i = 2, 5 do if values[i] and values[i]:match("%S") then options[#options + 1] = values[i] end end
                return GH:CreatePoll(values[1], options)
            end)
        end
    end)
    -- Use a full-window parent so the button remains inside its parent's hit area.
    -- Parenting it to the short header let it draw at the bottom but blocked clicks.
    frame.actionLayer = CreateFrame("Frame", nil, frame)
    frame.actionLayer:SetAllPoints(frame)
    frame.actionLayer:EnableMouse(false)
    frame.actionLayer:SetFrameLevel(frame:GetFrameLevel() + 30)
    frame.profileEditButton = CreateFrame("Button", nil, frame.actionLayer, "UIPanelButtonTemplate")
    GH:StyleButton(frame.profileEditButton, "primary")
    frame.profileEditButton:SetSize(242, 28)
    frame.profileEditButton:SetPoint("BOTTOMLEFT", frame.detailPanel, "BOTTOMLEFT", 14, 12)
    frame.profileEditButton:SetFrameStrata("DIALOG")
    frame.profileEditButton:SetFrameLevel(frame.actionLayer:GetFrameLevel() + 1)
    frame.profileEditButton:RegisterForClicks("LeftButtonUp")
    frame.profileEditButton:SetText("Edit my profile")
    frame.profileEditButton:SetScript("OnClick", function()
        local ok, err = pcall(openProfileEditor)
        if not ok then
            print("Guild Hall: Profile editor error: " .. tostring(err))
        else
            print("Guild Hall: Profile editor opened.")
        end
    end)
    frame.rosterInviteButton = CreateFrame("Button", nil, frame.actionLayer, "UIPanelButtonTemplate")
    GH:StyleButton(frame.rosterInviteButton)
    frame.rosterInviteButton:SetSize(242, 28)
    frame.rosterInviteButton:SetPoint("BOTTOMLEFT", frame.profileEditButton, "TOPLEFT", 0, 8)
    frame.rosterInviteButton:SetFrameLevel(frame.actionLayer:GetFrameLevel() + 1)
    frame.rosterInviteButton:RegisterForClicks("LeftButtonUp")
    frame.rosterInviteButton:SetText("Invite to group")
    frame.rosterInviteButton:SetScript("OnClick", function()
        local name = GH.selectedRosterName
        if not name then
            print("Guild Hall: Select a roster member first.")
            return
        end

        -- WoW Forever exposes party invites through the C_PartyInfo namespace.
        -- Keep legacy aliases for other Classic-compatible clients.
        local invite = InviteByName or InviteUnit
        local partyInfo = C_PartyInfo
        if not invite and type(partyInfo) == "table" and type(partyInfo.InviteUnit) == "function" then
            invite = partyInfo.InviteUnit
        end
        if not invite then
            print("Guild Hall: This client does not expose a group invite function.")
            return
        end

        local ok, err = pcall(invite, name)
        if not ok then print("Guild Hall: Could not invite " .. GH:Display(name) .. ": " .. tostring(err)) end
    end)
    frame.craftSearchButton = CreateFrame("Button", nil, frame.detailPanel, "UIPanelButtonTemplate")
    GH:StyleButton(frame.craftSearchButton, "primary")
    frame.craftSearchButton:SetSize(112, 26)
    frame.craftSearchButton:SetPoint("RIGHT", frame.contentActionButton, "LEFT", -8, 0)
    frame.craftSearchButton:SetText("Find crafter")
    frame.craftSearchButton:SetScript("OnClick", function()
        showInputForm("Find an online crafter", {
            { label = "Profession or recipe", value = "", max = 80 },
        }, function(values)
            local matches = GH:FindGuildCrafters(values[1])
            print(#matches > 0 and ("Guild Hall crafters: " .. table.concat(matches, "; ")) or "Guild Hall: No online member lists that profession or recipe in their profile.")
            return true
        end)
    end)
    frame.eventRows = {}
    frame.actionRows = {}
    frame.eventEmpty = frame.detailChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.eventEmpty:SetPoint("TOPLEFT", 12, -14)
    frame.eventEmpty:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
    frame.listScroll:SetScript("OnSizeChanged", function(self, width)
        frame.listChild:SetWidth(math.max(100, width - 4))
    end)

    frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.footer:SetPoint("BOTTOMLEFT", frame.detailPanel, "BOTTOMLEFT", 14, 10)
    frame.footer:SetText("/gh for commands")
end
GH.BuildUI = build

local function makeTabButton(parent, tab, index)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(178, 38)
    button:SetPoint("TOPLEFT", 9, -48 - (index - 1) * 40)
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    button.bg:SetColorTexture(0.045, 0.055, 0.072, 0.97)
    button.accent = button:CreateTexture(nil, "ARTWORK")
    button.accent:SetPoint("TOPLEFT")
    button.accent:SetPoint("BOTTOMLEFT")
    button.accent:SetWidth(3)
    button.accent:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    button.accent:Hide()
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.label:SetPoint("LEFT", 14, 0)
    button.label:SetWidth(155)
    button.label:SetJustifyH("LEFT")
    button.label:SetText(tab)
    button:SetScript("OnEnter", function(self)
        if GH.activeTab ~= tab then self.bg:SetColorTexture(0.08, 0.15, 0.22, 1) end
    end)
    button:SetScript("OnLeave", function() GH:RefreshUI() end)
    button:SetScript("OnClick", function()
        if tab == "Profiles" then GH.profileTarget = nil end
        if tab == "Roster" then
            GH.profileTarget = nil
            GH.selectedRosterName = nil
            GH.selectedSection = 1
        end
        GH.activeTab = tab
        GH.selectedSection = nil
        GH:RefreshUI()
    end)
    return button
end

function GH:RefreshUI()
    if not self.frame then return end
    local frame = self.frame
    local active = self.activeTab or "Roster"
    if active == "Profiles" then
        self.selectedRosterName = self.profileTarget or self.selectedRosterName
        active, self.activeTab = "Roster", "Roster"
    end
    frame.activeTab = active
    if active ~= "Settings" and self.GetSetting and not self:GetSetting("feature:" .. active) then
        active = "Settings"
        self.activeTab = active
    end
    local renderer = self.views and self.views[active] or rosterText
    local text = renderer() or ""
    local rosterDisplay = {}
    if active == "Roster" then
        local query = frame.rosterSearch and frame.rosterSearch:GetText() or ""
        if query == "Search..." then query = "" end
        query = query:lower()
        for _, member in ipairs(self.roster or {}) do
            local profile = self:GetProfile(member.name)
            profile = profile or {}
            local haystack = table.concat({ member.name or "", member.rank or "", member.class or "", member.zone or "", profile.role or "", profile.professions or "" }, " "):lower()
            if (not frame.rosterOnlineOnly or member.online) and (query == "" or haystack:find(query, 1, true)) then
                rosterDisplay[#rosterDisplay + 1] = member
            end
        end
        local sortField = self.rosterSortField or "name"
        local ascending = self.rosterSortAscending ~= false
        local function profileFor(member)
            return self:GetProfile(member.name)
        end
        table.sort(rosterDisplay, function(a, b)
            local av, bv
            if sortField == "name" then
                av, bv = (a.name or ""):lower(), (b.name or ""):lower()
            elseif sortField == "guild" then
                av, bv = (self.guildName or ""):lower(), (self.guildName or ""):lower()
            elseif sortField == "level" then
                av, bv = tonumber(a.level) or -1, tonumber(b.level) or -1
            elseif sortField == "rank" then
                av, bv = tonumber(a.rankIndex) or 999, tonumber(b.rankIndex) or 999
            elseif sortField == "zone" then
                av, bv = (a.zone or ""):lower(), (b.zone or ""):lower()
            elseif sortField == "role" then
                local ap, bp = profileFor(a), profileFor(b)
                av, bv = (ap and ap.role or ""):lower(), (bp and bp.role or ""):lower()
            else
                av, bv = (self:GetAddonVersion(a.name) or ""):lower(), (self:GetAddonVersion(b.name) or ""):lower()
            end
            if av == bv then return (a.name or ""):lower() < (b.name or ""):lower() end
            return ascending and av < bv or (not ascending and av > bv)
        end)
        frame.rosterDisplay = rosterDisplay
        text = ""
        for _, member in ipairs(rosterDisplay) do text = text .. member.name .. "\n" end
    end
    local sections = splitSections(text)
    if active == "Roster" and #rosterDisplay == 0 then sections = {} end
    if active == "Events" and #sections > 1 then
        table.remove(sections, 1)
    end
    if active == "Roster" or active == "PvP" or (active == "Profiles" and not self.profileTarget) then
        local rows = {}
        local skipIntro = active == "Profiles" and #sections > 1
        for sectionIndex, section in ipairs(sections) do
            if not (skipIntro and sectionIndex == 1) then
                for line in (section .. "\n"):gmatch("(.-)\n") do
                    if line ~= "" then rows[#rows + 1] = line end
                end
            end
        end
        if #rows > 0 then sections = rows end
    end
    self.currentSections = sections
    local online, usingAddon = 0, 0
    for _, member in ipairs(self.roster or {}) do
        if member.online then online = online + 1 end
        if self:GetAddonVersion(member.name) then usingAddon = usingAddon + 1 end
    end
    local addonSummary = "    " .. usingAddon .. " using addon"
    frame.headerStatus:SetText((self.guildName and "|cff55cf9bGUILD CONNECTED|r    " or "|cffff6666NO GUILD|r    ") .. online .. " online" .. addonSummary)
    frame.logoText:SetText((self.guildName or "Guild") .. " Hall")
    frame.logoAbbreviation:SetText(guildAbbreviation(self.guildName or "Guild"))
    frame.listHeader:SetText(active:upper())
    frame.sync:SetShown(active ~= "Settings" and active ~= "Roster")
    if active == "Roster" then
        frame.listPanel:Show()
        frame.listPanel:ClearAllPoints()
        frame.listPanel:SetPoint("TOPLEFT", 208, -88)
        frame.listPanel:SetPoint("BOTTOMLEFT", 208, 16)
        frame.listPanel:SetWidth(math.max(420, frame:GetWidth() - 208 - 14 - 270 - 12))
        frame.listHeader:Hide()
        frame.listRule:Hide()
        frame.rosterSearch:Show()
        frame.rosterOnlineCheck:Show()
        frame.rosterHeaderRule:Show()
        for _, header in ipairs(frame.rosterHeaders) do
            local arrow = header.sortKey == (self.rosterSortField or "name") and (self.rosterSortAscending == false and " v" or " ^") or ""
            header.title:SetText(header.title:GetText():gsub(" [%^v]$", "") .. arrow)
            header:Show()
        end
        frame.listScroll:ClearAllPoints()
        frame.listScroll:SetPoint("TOPLEFT", 8, -68)
        frame.listScroll:SetPoint("BOTTOMRIGHT", -8, 8)
        frame.rosterEmpty:SetShown(#rosterDisplay == 0)
        frame.detailPanel:ClearAllPoints()
        frame.detailPanel:SetPoint("TOPRIGHT", -14, -88)
        frame.detailPanel:SetPoint("BOTTOMRIGHT", -14, 16)
        frame.detailPanel:SetWidth(270)
    else
        frame.listPanel:Hide()
        frame.listHeader:Show()
        frame.listRule:Show()
        frame.rosterSearch:Hide()
        frame.rosterOnlineCheck:Hide()
        frame.rosterHeaderRule:Hide()
        for _, header in ipairs(frame.rosterHeaders) do header:Hide() end
        frame.rosterEmpty:Hide()
        frame.listScroll:ClearAllPoints()
        frame.listScroll:SetPoint("TOPLEFT", 8, -48)
        frame.listScroll:SetPoint("BOTTOMRIGHT", -14, 8)
        frame.detailPanel:ClearAllPoints()
        frame.detailPanel:SetPoint("TOPLEFT", 216, -88)
        frame.detailPanel:SetPoint("BOTTOMRIGHT", -14, 16)
        frame.detailPanel:SetWidth(math.max(100, frame:GetWidth() - 230))
    end

    local navIndex = 0
    for _, tab in ipairs(self.tabs) do
        if not frame.tabButtons[tab] then frame.tabButtons[tab] = makeTabButton(frame.sidebar, tab, 1) end
        local button = frame.tabButtons[tab]
            local visible = tab ~= "Profiles" and (tab == "Settings" or not self.GetSetting or self:GetSetting("feature:" .. tab))
        button:SetShown(visible)
        if visible then
            navIndex = navIndex + 1
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", 9, -48 - (navIndex - 1) * 40)
        end
        local selected = tab == active
        button.accent:SetShown(selected)
        button.bg:SetColorTexture(selected and 0.08 or 0.045, selected and 0.16 or 0.055, selected and 0.23 or 0.072, 1)
        setTextColor(button.label, selected and CREAM or MUTED_GOLD)
    end

    local selected = #sections > 0 and math.min(math.max(self.selectedSection or 1, 1), #sections) or 0
    if selected > 0 then self.selectedSection = selected end
    for index, section in ipairs(sections) do
        local row = frame.listRows[index]
        if not row then
            row = CreateFrame("Button", nil, frame.listChild)
            row:SetSize(210, 72)
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            row.selectedMarker = row:CreateTexture(nil, "OVERLAY")
            row.selectedMarker:SetPoint("TOPLEFT", 0, -1)
            row.selectedMarker:SetPoint("BOTTOMLEFT", 0, 1)
            row.selectedMarker:SetWidth(3)
            row.selectedMarker:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
            row.selectedMarker:Hide()
            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.label:SetPoint("TOPLEFT", 10, -7)
            row.label:SetWidth(190)
            row.label:SetJustifyH("LEFT")
            row.label:SetWordWrap(false)
            row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.meta:SetPoint("BOTTOMLEFT", 10, 7)
            row.meta:SetHeight(40)
            row.meta:SetJustifyV("BOTTOM")
            row.meta:SetWordWrap(true)
            row.columns = {}
            for columnIndex, spec in ipairs({ { 10, 128, "LEFT" }, { 145, 36, "LEFT" }, { 185, 27, "LEFT" }, { 218, 82, "LEFT" }, { 304, 120, "LEFT" }, { 428, 58, "LEFT" }, { 490, 55, "LEFT" } }) do
                local cell = row:CreateFontString(nil, "OVERLAY", columnIndex == 1 and "GameFontNormal" or "GameFontNormalSmall")
                cell:SetPoint("LEFT", spec[1], 0)
                cell:SetWidth(spec[2])
                cell:SetJustifyH(spec[3])
                cell:SetWordWrap(false)
                row.columns[columnIndex] = cell
            end
            row:SetScript("OnClick", function(self)
                GH.selectedSection = self.sectionIndex
                GH.selectedRosterName = self.rosterName
                GH:RefreshUI()
            end)
            row:EnableMouseWheel(true)
            row:SetScript("OnMouseWheel", function(_, delta)
                frame.listScroll:GetScript("OnMouseWheel")(frame.listScroll, delta)
            end)
            frame.listRows[index] = row
        end
        row.sectionIndex = index
        local rowHeight = active == "Roster" and 34 or 72
        row:SetSize(math.max(180, frame.listChild:GetWidth() - 10), rowHeight)
        row:SetPoint("TOPLEFT", 4, -4 - (index - 1) * (rowHeight + (active == "Roster" and 1 or 0)))
        local title = section:match("([^\n]+)") or section
        if #title > 36 then title = title:sub(1, 33) .. "…" end
        row.label:SetText(title)
        row.rosterName = active == "Roster" and frame.rosterDisplay and frame.rosterDisplay[index] and frame.rosterDisplay[index].name or nil
        if active == "Roster" then
            local profile = row.rosterName and self:GetProfile(row.rosterName)
            local summary = profile and table.concat({ profile.role or "", profile.spec or "" }, " · "):gsub("^ · ", ""):gsub(" · $", "")
            local version = row.rosterName and self:GetAddonVersion(row.rosterName)
            local addonStatus = version and ("Guild Hall v" .. version) or "No addon detected"
            local profileStatus = summary and summary ~= "" and summary or (profile and "Profile available" or "No profile yet")
            local rowMember = frame.rosterDisplay[index]
            local characterInfo = table.concat({
                rowMember and rowMember.level and ("Level " .. rowMember.level) or "",
                profile and profile.race or "Race not listed",
                rowMember and rowMember.class or "",
            }, "  · ")
            local professions = profile and profile.professions or ""
            if #professions > 38 then professions = professions:sub(1, 35) .. "..." end
            local professionInfo = professions ~= "" and ("Professions: " .. professions) or "Professions not listed"
            local statusLine = addonStatus ~= "" and (addonStatus .. "  -  " .. profileStatus) or profileStatus
            row.meta:SetText(statusLine .. "\n" .. characterInfo .. "\n" .. professionInfo)
            row.meta:Show()
            row.label:ClearAllPoints()
            row.label:SetPoint("TOPLEFT", 10, -7)
        else
            for _, cell in ipairs(row.columns) do cell:Hide() end
            row.meta:Hide()
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", 10, 0)
        end
        if active == "Roster" then
            local member = frame.rosterDisplay[index]
            local profile = self:GetProfile(member.name)
            profile = profile or {}
            local version = self:GetAddonVersion(member.name)
            local guildShort = (self.guildName or "-"):gsub("(%S)%S*", "%1"):upper():sub(1, 3)
            row.columns[1]:SetText(self:Display(member.name))
            local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.classFile]
            if classColor then row.columns[1]:SetTextColor(classColor.r, classColor.g, classColor.b)
            else row.columns[1]:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
            row.columns[2]:SetText(guildShort:sub(1, 7))
            row.columns[3]:SetText(tostring(member.level or "-"))
            row.columns[4]:SetText(self:Display(member.rank or "Member"))
            row.columns[5]:SetText(self:Display(member.zone or "-"))
            row.columns[6]:SetText(self:Display(profile.role or "-"))
            row.columns[7]:SetText(version or "-")
            for _, cell in ipairs(row.columns) do cell:Show() end
            row.label:Hide()
            row.meta:Hide()
            if index == selected then
                row.bg:SetColorTexture(0.08, 0.16, 0.23, 1)
            else
                row.bg:SetColorTexture(index % 2 == 1 and PANEL_ALT[1] or PANEL[1], index % 2 == 1 and PANEL_ALT[2] or PANEL[2], index % 2 == 1 and PANEL_ALT[3] or PANEL[3], 1)
            end
        end
        row.label:SetWidth(math.max(100, row:GetWidth() - 20))
        row.meta:SetWidth(math.max(100, row:GetWidth() - 20))
        row.selectedMarker:SetShown(active == "Roster" and index == selected)
        if active ~= "Roster" then row.bg:SetColorTexture(index == (self.selectedSection or 1) and 0.08 or 0.055, index == (self.selectedSection or 1) and 0.16 or 0.068, index == (self.selectedSection or 1) and 0.23 or 0.085, 1) end
        row:Show()
    end
    for index = #sections + 1, #frame.listRows do frame.listRows[index]:Hide() end
    frame.listChild:SetHeight(math.max(280, #sections * (active == "Roster" and 35 or 72) + 8))

    local detail = table.concat(sections, "\n\n")
    local isPvP = active == "PvP"
    local isEvents = active == "Events"
    local isActionList = active == "Looking For" or active == "Crafting" or active == "Polls" or active == "Announcements"
    frame.sync:SetShown(active ~= "Settings" and not isPvP)
    frame.detailRule:SetShown(not isPvP and not isEvents and not isActionList)
    frame.detailMeta:SetShown(not isPvP and not isActionList)
    frame.detailScroll:ClearAllPoints()
    if isPvP then
        frame.detailScroll:SetPoint("TOPLEFT", 10, -144)
        frame.detailScroll:SetPoint("BOTTOMRIGHT", -10, 12)
    else
        frame.detailScroll:SetPoint("TOPLEFT", 10, -66)
        frame.detailScroll:SetPoint("BOTTOMRIGHT", -28, 54)
    end
    for _, element in ipairs({ frame.pvpTitleSeason, frame.pvpSummary, frame.pvpInfo, frame.pvpTableRule, frame.pvpMyButton, frame.pvpSeasonButton, frame.pvpScopeButton }) do
        element:SetShown(isPvP)
    end
    frame.eventCreateButton:SetShown(isEvents and self:CanManage())
    frame.eventCreateTypeButton:SetShown(isEvents and self:CanManage())
    local actionVisible = active == "Profiles" or active == "Shoutouts" or active == "Looking For" or active == "Crafting" or (active == "Polls" and self:CanManage()) or ((active == "Announcements" or active == "Guide") and self:CanManage())
    frame.contentActionButton:SetShown(actionVisible)
    frame.contentActionButton:EnableMouse(true)
    frame.contentActionButton:ClearAllPoints()
    frame.contentActionButton:SetSize(130, 26)
    frame.contentActionButton:SetPoint("TOPRIGHT", frame.detailPanel, "TOPRIGHT", -18, -12)
    frame.profileEditButton:SetShown(active == "Roster")
    frame.rosterInviteButton:SetShown(active == "Roster" and self.selectedRosterName ~= nil)
    frame.craftSearchButton:SetShown(active == "Crafting")
    if active == "Announcements" then
        frame.contentActionButton:SetText("New post")
    elseif active == "Profiles" then
        frame.contentActionButton:SetText("Edit my profile")
    elseif active == "Guide" then
        frame.contentActionButton:SetText("Edit guide")
    elseif active == "Shoutouts" then
        frame.contentActionButton:SetText("Give shoutout")
    elseif active == "Looking For" then
        frame.contentActionButton:SetText("New request")
    elseif active == "Crafting" then
        frame.contentActionButton:SetText("Request a craft")
    elseif active == "Polls" then
        frame.contentActionButton:SetText("New poll")
    end
    for _, header in ipairs(frame.pvpHeaders) do header:SetShown(isPvP) end
    if not isPvP then
        frame.pvpEmpty:Hide()
        for _, row in ipairs(frame.pvpRows) do row:Hide() end
    end
    if not isEvents then
        frame.eventEmpty:Hide()
        for _, row in ipairs(frame.eventRows) do row:Hide() end
    end
    for _, row in ipairs(frame.actionRows) do row:Hide() end
    if frame.actionEmpty then frame.actionEmpty:Hide() end
    frame.detailChild:SetWidth(math.max(100, frame.detailScroll:GetWidth() - 4))
    frame.detailBody:SetWidth(math.max(80, frame.detailScroll:GetWidth() - 28))
    frame.detailTitle:SetWidth(active == "Roster" and 100 or math.max(120, frame.detailPanel:GetWidth() - 36))
    frame.detailMeta:SetWidth(math.max(100, frame.detailPanel:GetWidth() - 36))
    frame.listChild:SetWidth(math.max(100, frame.listScroll:GetWidth() - 4))
    if active == "Settings" then
        self:HideSettingsControls()
        frame.detailBody:Hide()
        frame.detailMeta:SetText("Personal preferences and officer controls")
        frame.detailTitle:SetText("Settings")
        self:ShowSettingsControls(frame.detailChild)
        frame.detailChild:SetHeight(440)
    elseif active == "Roster" then
        self:HideSettingsControls()
        frame.detailBody:Show()
        local name = self.selectedRosterName
        local member
        for _, candidate in ipairs(frame.rosterDisplay or self.roster or {}) do
            if candidate.name == name then member = candidate; break end
            if name then
                local selectedBase = (name:match("^([^-]+)") or name):lower()
                local candidateBase = ((candidate.name or ""):match("^([^-]+)") or candidate.name or ""):lower()
                if selectedBase == candidateBase then
                    member, name = candidate, candidate.name
                    self.selectedRosterName = name
                    break
                end
            end
        end
        if not member and not name then
            member = frame.rosterDisplay and frame.rosterDisplay[selected]
            name = member and member.name
            self.selectedRosterName = name
        end
        local profile = self:GetProfile(name)
        local function value(field)
            return self:Display(profile and profile[field] ~= "" and profile[field] or "Not set")
        end
        local version = name and self:GetAddonVersion(name)
        local levelText = member and member.level and ("Level " .. member.level) or "Level unknown"
        local classText = member and member.class or "Class unknown"
        frame.detailMeta:SetText(levelText .. "  -  " .. value("race") .. "  -  " .. self:Display(classText) .. "  -  " .. (member and self:Display(member.rank) or "Guild member"))
        frame.detailTitle:SetText(self:Display(name or "Roster"))
        local guild = self:Display(self.guildName or "No guild")
        local status = member and (member.online and "Online" or "Offline") or "Unavailable"
        local zone = member and member.zone and member.zone ~= "" and self:Display(member.zone) or "Unknown"
        local profileName = profile and table.concat({ profile.firstName or "", profile.lastName or "" }, " "):gsub("^%s+", ""):gsub("%s+$", "") or ""
        if profileName == "" then profileName = "Not set" end
        local addonLine = "Guild Hall  " .. (version and ("v" .. version) or "Not detected") .. "\n\n"
        frame.detailBody:SetText(addonLine .. "Guild: " .. guild .. "\n\nName: " .. self:Display(profileName) .. "\n\nStatus: " .. status .. "  -  " .. zone .. "\n\nRole: " .. value("role") .. "\n\nProfessions: " .. value("professions") .. "\n\nSpecialization: " .. value("spec") .. "\n\nTime zone: " .. value("timezone") .. "\n\nAlts: " .. value("alts"))
    elseif active == "PvP" then
        self:HideSettingsControls()
        frame.detailBody:Hide()
        frame.detailTitle:SetWidth(math.min(390, math.max(250, frame.detailPanel:GetWidth() - 500)))
        frame.detailTitle:SetText("PVP LEADERBOARD")
        local season, ranking, ownScore, ownRank = self:GetPvPLeaderboard(frame.pvpAllTime)
        frame.pvpTitleSeason:SetText((season.name or "Season 1"))
        frame.pvpMyButton:SetText(frame.pvpMyOnly and "Guild board" or "My stats")
        frame.pvpSeasonButton:SetShown(self:CanManage())
        frame.pvpScopeButton:SetText(frame.pvpAllTime and "Season board" or "All-time")
        local playerName = UnitName and UnitName("player") or "You"
        frame.pvpSummary:SetText(ownScore and ("You: |cffffcc33%d pts|r  -  %d kills  -  #%d"):format(ownScore.points, ownScore.kills, ownRank) or (playerName .. ": no PvP points yet"))
        frame.pvpInfo:SetText("Outdoor PvP  |  Points by level: 1 (1-19), 2 (20-29), 3 (30-39), 4 (40-49), 5 (50-60)  |  Same player: once per 5 min, 5 per day")
        if frame.pvpMyOnly then
            local own = ownScore
            ranking = own and { own } or {}
        end
        local function leaderboardName(characterName)
            local profile = self:GetProfile(characterName)
            if profile then
                local firstName = (profile.firstName or ""):gsub("^%s+", ""):gsub("%s+$", "")
                local lastName = (profile.lastName or ""):gsub("^%s+", ""):gsub("%s+$", "")
                local displayName = (firstName .. " " .. lastName):gsub("^%s+", ""):gsub("%s+$", "")
                if displayName ~= "" then return displayName end
            end
            return characterName
        end
        for i, score in ipairs(ranking) do
            local row = frame.pvpRows[i]
            if not row then
                row = CreateFrame("Button", nil, frame.detailChild)
                row:SetHeight(34)
                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.player = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.points = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.kills = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.bands = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.last = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                for _, spec in ipairs({ { row.rank, 12, 28, "LEFT" }, { row.player, 48, 170, "LEFT" }, { row.points, 235, 58, "RIGHT" }, { row.kills, 320, 50, "RIGHT" }, { row.bands, 390, 142, "LEFT" }, { row.last, 550, 220, "LEFT" } }) do
                    spec[1]:SetPoint("LEFT", spec[2], 0)
                    spec[1]:SetWidth(spec[3])
                    spec[1]:SetJustifyH(spec[4])
                end
                frame.pvpRows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 36)
            row:SetPoint("RIGHT", frame.detailChild, "RIGHT", -4, 0)
            local band = score.recentPoints or {}
            row.rank:SetText(tostring(i))
            row.player:SetText(self:Display(leaderboardName(score.name)))
            row.player:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
            row.points:SetText(tostring(score.points or 0))
            row.points:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
            row.kills:SetText(tostring(score.kills or 0))
            row.bands:SetText(('%d  -  %d  -  %d  -  %d  -  %d'):format(band[1] or 0, band[2] or 0, band[3] or 0, band[4] or 0, band[5] or 0))
            local last = score.lastKill
            local lastText = "-"
            if last then
                local age = math.max(0, time() - (last.ts or time()))
                local ageText = age < 3600 and (math.floor(age / 60) .. "m") or age < 86400 and (math.floor(age / 3600) .. "h") or (math.floor(age / 86400) .. "d")
                lastText = self:Display(last.victim or "Unknown") .. " (" .. tostring(last.victimLevel or "?") .. ")  " .. ageText .. " ago"
            end
            row.last:SetText(lastText)
            row.last:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
            row.bg:SetColorTexture(i % 2 == 1 and PANEL_ALT[1] or PANEL[1], i % 2 == 1 and PANEL_ALT[2] or PANEL[2], i % 2 == 1 and PANEL_ALT[3] or PANEL[3], 1)
            row:Show()
        end
        for i = #ranking + 1, #frame.pvpRows do frame.pvpRows[i]:Hide() end
        if #ranking == 0 then
            frame.pvpEmpty:SetText(self.guildName and "No outdoor PvP kills recorded this season yet." or "Join a guild to see the PvP leaderboard.")
            frame.pvpEmpty:Show()
        else
            frame.pvpEmpty:Hide()
        end
        frame.detailChild:SetHeight(math.max(frame.detailScroll:GetHeight(), #ranking * 36 + 12))
    elseif active == "Events" then
        self:HideSettingsControls()
        frame.detailBody:Hide()
        frame.detailTitle:SetWidth(math.min(420, frame.detailPanel:GetWidth() - 250))
        frame.detailTitle:SetText("RAIDS & EVENTS")
        frame.detailMeta:SetText("Upcoming guild calendar  -  RSVP right on each event")
        local events = self.GetUpcomingEvents and self:GetUpcomingEvents() or {}
        local player = UnitName and UnitName("player") or ""
        for i, event in ipairs(events) do
            local row = frame.eventRows[i]
            if not row then
                row = CreateFrame("Frame", nil, frame.detailChild)
                row:SetHeight(78)
                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.title:SetPoint("TOPLEFT", 12, -9)
                row.title:SetWidth(360)
                row.title:SetJustifyH("LEFT")
                row.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
                row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                row.info:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
                row.info:SetWidth(360)
                row.details = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.details:SetPoint("TOPLEFT", row.info, "BOTTOMLEFT", 0, -4)
                row.details:SetWidth(360)
                row.counts = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.counts:SetPoint("TOPLEFT", 400, -12)
                row.counts:SetWidth(190)
                row.counts:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
                row.rsvpButtons = {}
                for buttonIndex, state in ipairs({ { "Going", "going" }, { "Maybe", "tentative" }, { "Absent", "absent" } }) do
                    local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    GH:StyleButton(button, "primary")
                    button:SetSize(72, 22)
                    button:SetPoint("BOTTOMRIGHT", -8 - (3 - buttonIndex) * 78, 9)
                    button:SetText(state[1])
                    button.status = state[2]
                    button:SetScript("OnClick", function(self)
                        local _, result = GH:SetRSVPForEvent(self.eventId, self.status)
                        if result then print("Guild Hall: " .. result) end
                    end)
                    row.rsvpButtons[buttonIndex] = button
                end
                frame.eventRows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 88)
            row:SetPoint("RIGHT", frame.detailChild, "RIGHT", -4, 0)
            row.title:SetText((event.eventType == "raid" and "RAID  -  " or "EVENT  -  ") .. self:Display(event.title))
            row.info:SetText(date("%a, %b %d  -  %I:%M %p", event.at) .. "  -  Posted by " .. self:Display(event.by))
            row.details:SetText(self:Display(event.details or ""))
            local counts = { going = 0, tentative = 0, absent = 0 }
            for _, response in pairs(event.rsvps or {}) do
                local status = type(response) == "table" and response.status or response
                if counts[status] ~= nil then counts[status] = counts[status] + 1 end
            end
            local mine = event.rsvps and event.rsvps[player]
            if type(mine) == "table" then mine = mine.status end
            row.counts:SetText(("Going %d  -  Maybe %d  -  Absent %d\nYour RSVP: %s"):format(counts.going, counts.tentative, counts.absent, mine or "Not set"))
            row.bg:SetColorTexture(i % 2 == 1 and PANEL_ALT[1] or PANEL[1], i % 2 == 1 and PANEL_ALT[2] or PANEL[2], i % 2 == 1 and PANEL_ALT[3] or PANEL[3], 1)
            for _, button in ipairs(row.rsvpButtons) do button.eventId = event.id end
            row:Show()
        end
        for i = #events + 1, #frame.eventRows do frame.eventRows[i]:Hide() end
        if #events == 0 then
            frame.eventEmpty:SetText(self.guildName and "No upcoming raids or events are scheduled." or "Join a guild to view its calendar.")
            frame.eventEmpty:Show()
        else
            frame.eventEmpty:Hide()
        end
        frame.detailChild:SetHeight(math.max(frame.detailScroll:GetHeight(), #events * 88 + 12))
    elseif isActionList then
        self:HideSettingsControls()
        frame.detailBody:Hide()
        frame.detailTitle:SetText(active:upper())
        local entries, y = {}, 4
        local function addActionRow(title, subtitle, actions, body)
            local index = #frame.actionRows + 1
            local row = frame.actionRows[index]
            if not row then
                row = CreateFrame("Frame", nil, frame.detailChild)
                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.title:SetPoint("TOPLEFT", 10, -8)
                row.title:SetWidth(520)
                row.title:SetJustifyH("LEFT")
                row.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
                row.subtitle = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.subtitle:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -5)
                row.subtitle:SetWidth(520)
                row.subtitle:SetJustifyH("LEFT")
                row.body = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.body:SetPoint("TOPLEFT", row.subtitle, "BOTTOMLEFT", 0, -5)
                row.body:SetJustifyH("LEFT")
                row.body:SetJustifyV("TOP")
                row.body:SetWordWrap(true)
                row.body:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
                row.buttons = {}
                frame.actionRows[index] = row
            end
            local actionCount = #(actions or {})
            local textWidth = math.max(180, frame.detailChild:GetWidth() - actionCount * 82 - 28)
            local bodyWidth = math.max(180, frame.detailChild:GetWidth() - 28)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 4, -y)
            row:SetPoint("RIGHT", frame.detailChild, "RIGHT", -4, 0)
            row.title:SetText(title)
            row.title:SetWidth(textWidth)
            row.subtitle:SetText(subtitle or "")
            row.subtitle:SetWidth(textWidth)
            if body and body ~= "" then
                row.body:SetText(body)
                row.body:SetWidth(bodyWidth)
                row.body:Show()
                local lineCount = 1
                for _ in body:gmatch("\n") do lineCount = lineCount + 1 end
                lineCount = lineCount + math.floor(#body / math.max(1, math.floor(bodyWidth / 7)))
                row:SetHeight(math.max(76, 69 + lineCount * 14))
            else
                row.body:SetText("")
                row.body:Hide()
                row:SetHeight(68)
            end
            row.bg:SetColorTexture(index % 2 == 1 and PANEL_ALT[1] or PANEL[1], index % 2 == 1 and PANEL_ALT[2] or PANEL[2], index % 2 == 1 and PANEL_ALT[3] or PANEL[3], 1)
            for buttonIndex, action in ipairs(actions or {}) do
                local button = row.buttons[buttonIndex]
                if not button then
                    button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    GH:StyleButton(button, "primary")
                    button:SetSize(76, 22)
                    row.buttons[buttonIndex] = button
                end
                button:SetText(action.label)
                GH:StyleButton(button, action.label == "Delete" and "secondary" or "primary")
                button:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8 - (buttonIndex - 1) * 82, -8)
                button:SetScript("OnClick", action.click)
                button:Show()
            end
            for i = #(actions or {}) + 1, #row.buttons do row.buttons[i]:Hide() end
            row:Show()
            y = y + row:GetHeight() + 8
        end
        if active == "Announcements" then
            entries = self.bucket and self.bucket.announcements or {}
            for _, post in ipairs(entries) do
                local postId, postTitle, postText = post.id, post.title or "", post.text or ""
                local actions = {}
                if self:CanManage() then
                    actions[#actions + 1] = { label = "Edit", click = function()
                        showInputForm("Edit announcement", {
                            { label = "Title", value = postTitle, max = 120 },
                            { label = "Message", value = postText, max = 600, multiline = true },
                        }, function(values) return self:EditAnnouncement(postId, values[1], values[2]) end)
                    end }
                    actions[#actions + 1] = { label = "Delete", click = function()
                        local _, message = self:DeleteAnnouncement(postId)
                        print("Guild Hall: " .. tostring(message))
                    end }
                end
                local title = postTitle ~= "" and postTitle or "Announcement"
                local meta = "By " .. self:Display(post.by or "Guild member") .. "  ·  " .. date("%b %d, %I:%M %p", post.ts or time())
                addActionRow(self:Display(title), meta, actions, self:Display(postText))
            end
        elseif active == "Looking For" then
            entries = self.GetActiveLookingRequests and self:GetActiveLookingRequests() or {}
            for _, entry in ipairs(entries) do
                local requestId = entry.id
                local canClose = self:CanManage() or entry.by:lower() == ((UnitName and UnitName("player")) or ""):lower()
                local actions = {}
                if canClose then actions[1] = { label = "Close", click = function() self:CloseLookingRequest(requestId) end } end
                addActionRow(self:Display(entry.role) .. "  -  " .. self:Display(entry.activity), "By " .. self:Display(entry.by) .. "  -  " .. tostring(math.max(1, math.ceil((entry.expires - time()) / 60))) .. " min left  -  " .. self:Display(entry.details), actions)
            end
        elseif active == "Crafting" then
            entries = self.GetActiveCraftingRequests and self:GetActiveCraftingRequests() or {}
            local player = UnitName and UnitName("player") or ""
            for _, entry in ipairs(entries) do
                local requestId = entry.id
                local actions = {}
                if entry.status == "pending" then actions[#actions + 1] = { label = "Claim", click = function() self:ChangeCraftingRequest(requestId, false) end } end
                if entry.status == "claimed" and (entry.crafter:lower() == player:lower() or entry.by:lower() == player:lower() or self:CanManage()) then actions[#actions + 1] = { label = "Complete", click = function() self:ChangeCraftingRequest(requestId, true) end } end
                addActionRow(self:Display(entry.item) .. "  -  " .. entry.status:upper(), "By " .. self:Display(entry.by) .. (entry.crafter ~= "" and ("  -  Claimed by " .. self:Display(entry.crafter)) or "") .. "  -  " .. self:Display(entry.details), actions)
            end
        else
            entries = self.bucket and self.bucket.polls or {}
            for _, poll in ipairs(entries) do
                local pollId = poll.id
                local actions = {}
                if not poll.closed then
                    for optionIndex, option in ipairs(poll.options) do
                        if #actions >= 3 then break end
                        local choice = optionIndex
                        actions[#actions + 1] = { label = "Vote " .. choice, click = function() self:VotePoll(pollId, choice) end }
                    end
                    if self:CanManage() then actions[#actions + 1] = { label = "Close", click = function() self:ClosePoll(pollId) end } end
                end
                local counts = {}
                for i = 1, #poll.options do counts[i] = 0 end
                for _, vote in pairs(poll.votes or {}) do local choice = type(vote) == "table" and vote.choice or vote; if counts[choice] then counts[choice] = counts[choice] + 1 end end
                local summary = {}
                for i, option in ipairs(poll.options) do summary[#summary + 1] = self:Display(option) .. ": " .. counts[i] end
                addActionRow((poll.closed and "CLOSED  -  " or "") .. self:Display(poll.question), table.concat(summary, "  |  "), actions)
            end
        end
        if #entries == 0 then
            frame.actionEmpty = frame.actionEmpty or frame.detailChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            frame.actionEmpty:SetPoint("TOPLEFT", 12, -14)
            local emptyText = active == "Polls" and "No polls have been created." or (active == "Announcements" and "No announcements yet. Officers can create the first post." or "No active posts.")
            frame.actionEmpty:SetText(emptyText)
            frame.actionEmpty:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
            frame.actionEmpty:Show()
        elseif frame.actionEmpty then frame.actionEmpty:Hide() end
        frame.detailChild:SetHeight(math.max(frame.detailScroll:GetHeight(), y + 8))
    else
        self:HideSettingsControls()
        frame.detailBody:Show()
        frame.detailMeta:SetText(self.guildName and "Guild Hall workspace" or "Guild Hall workspace - Join a guild to sync")
        frame.detailTitle:SetText(active)
        frame.detailBody:SetText(detail)
    end
    if active ~= "Settings" and active ~= "PvP" and active ~= "Events" and not isActionList then frame.detailChild:SetHeight(math.max(400, frame.detailBody:GetStringHeight() + 20)) end
end

local function rebuildRoster()
    if not GH.guildName or not GetNumGuildMembers or not GetGuildRosterInfo then return end
    local roster = {}
    for i = 1, GetNumGuildMembers() do
        local name, rankName, rankIndex, level, className, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name then
            roster[#roster + 1] = { name = name, rank = rankName or "Member", rankIndex = rankIndex or 99, level = level, class = className, classFile = classFile, zone = zone, online = not not online }
        end
    end
    table.sort(roster, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.name:lower() < b.name:lower()
    end)
    GH.roster = roster
    GH:RefreshUI()
end
GH.RebuildRoster = rebuildRoster
GH:RegisterEventHandler("PLAYER_LOGIN", function() build(); rebuildRoster() end)
GH:RegisterEventHandler("GUILD_ROSTER_UPDATE", function() build(); rebuildRoster() end)
GH:RegisterEventHandler("PLAYER_GUILD_UPDATE", function() build(); rebuildRoster() end)

function GH:IsSyncResponder()
    if not self.roster or #self.roster == 0 then return false end
    local candidates = {}
    for _, member in ipairs(self.roster) do
        if member.online and member.rankIndex <= 1 then candidates[#candidates + 1] = member end
    end
    table.sort(candidates, function(a, b)
        if a.rankIndex ~= b.rankIndex then return a.rankIndex < b.rankIndex end
        return a.name:lower() < b.name:lower()
    end)
    if not candidates[1] then return false end
    local playerNames = {}
    if UnitName then playerNames[#playerNames + 1] = (UnitName("player") or ""):match("^([^-]+)") end
    if GetUnitName then playerNames[#playerNames + 1] = (GetUnitName("player", false) or ""):match("^([^-]+)") end
    for _, name in ipairs(playerNames) do
        if name and candidates[1].name:lower() == name:lower() then return true end
    end
    return false
end

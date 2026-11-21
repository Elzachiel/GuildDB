-- Dark guild workspace with a compact navigation rail and single content pane. - TEST
local _, GH = ...

local GOLD = { 0.20, 0.62, 0.98 }
local MUTED_GOLD = { 0.48, 0.60, 0.70 }
local CREAM = { 0.84, 0.89, 0.94 }
local PANEL = { 0.045, 0.055, 0.072, 0.99 }
local PANEL_ALT = { 0.075, 0.09, 0.115, 0.99 }

local pvpColumnWidths = { 0.06, 0.28, 0.13, 0.13, 0.40 }
local function layoutPvPColumn(text, index, parent, width, inset, header)
    local offset = 0
    for column = 1, index - 1 do offset = offset + pvpColumnWidths[column] * width end
    text:ClearAllPoints()
    if header then text:SetPoint("TOPLEFT", parent, "TOPLEFT", inset + offset, -153)
    else text:SetPoint("LEFT", parent, "LEFT", offset, 0) end
    text:SetWidth(math.max(1, pvpColumnWidths[index] * width - 8))
    text:SetJustifyH("CENTER")
end

local function rosterText()
    if not GH.guildName then return "Join a guild to view its roster and GuildDB." end
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

local function styleRaidButton(button, width, variant)
    if not button:GetFontString() then
        button:SetFontString(button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    end
    GH:StyleButton(button, variant)
    button:SetSize(width, 28)
    button:SetNormalFontObject("GameFontHighlightSmall")
    button:SetHighlightFontObject("GameFontHighlightSmall")
    button:SetDisabledFontObject("GameFontDisableSmall")
    button:SetPushedTextOffset(0, -1)
    local text = button:GetFontString()
    if text then
        text:ClearAllPoints()
        text:SetPoint("CENTER", 0, 0)
        text:SetWidth(width - 16)
        text:SetHeight(18)
        text:SetJustifyH("CENTER")
        text:SetWordWrap(false)
        if variant == "danger" then text:SetTextColor(0.90, 0.64, 0.64) end
    end
end

local function styleRaidInviteCheck(button)
    -- Match the plain button, border, and blue check used in Settings.
    GH:StyleButton(button)
    button:SetSize(22, 22)
    button.mark = button:CreateTexture(nil, "OVERLAY")
    button.mark:SetTexture("Interface/Buttons/UI-CheckBox-Check")
    button.mark:SetSize(17, 17)
    button.mark:SetPoint("CENTER")
    button.mark:SetVertexColor(0.25, 0.68, 1, 1)
end

function GH:StyleEditBox(editBox, multiline)
    if not editBox then return end
    editBox:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
    editBox:SetBackdropColor(PANEL_ALT[1], PANEL_ALT[2], PANEL_ALT[3], 1)
    editBox:SetFontObject(multiline and "GameFontHighlight" or "GameFontHighlightSmall")
    editBox:SetTextInsets(8, 8, multiline and 6 or 0, multiline and 6 or 0)
    editBox:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
    editBox.guildHallBorder = editBox.guildHallBorder or {}
    for index = 1, 4 do
        local edge = editBox.guildHallBorder[index]
        if not edge then
            edge = editBox:CreateTexture(nil, "OVERLAY")
            editBox.guildHallBorder[index] = edge
        end
        edge:SetColorTexture(0.16, 0.25, 0.34, 1)
    end
    local border = editBox.guildHallBorder
    border[1]:SetPoint("TOPLEFT"); border[1]:SetPoint("TOPRIGHT"); border[1]:SetHeight(1)
    border[2]:SetPoint("BOTTOMLEFT"); border[2]:SetPoint("BOTTOMRIGHT"); border[2]:SetHeight(1)
    border[3]:SetPoint("TOPLEFT"); border[3]:SetPoint("BOTTOMLEFT"); border[3]:SetWidth(1)
    border[4]:SetPoint("TOPRIGHT"); border[4]:SetPoint("BOTTOMRIGHT"); border[4]:SetWidth(1)
    function editBox:SetGuildHallFocusState(focused)
        local color = focused and GOLD or { 0.16, 0.25, 0.34 }
        for _, edge in ipairs(self.guildHallBorder) do edge:SetColorTexture(color[1], color[2], color[3], 1) end
    end
    editBox:HookScript("OnEditFocusGained", function(self) self:SetGuildHallFocusState(true) end)
    editBox:HookScript("OnEditFocusLost", function(self) self:SetGuildHallFocusState(false) end)
    if multiline then
        editBox:SetMultiLine(true)
        editBox:SetJustifyH("LEFT")
        editBox:SetJustifyV("TOP")
    end
end

local function guildAbbreviation(name)
    local words = {}
    for word in tostring(name or "Guild"):gmatch("%S+") do words[#words + 1] = word end
    local abbreviation = ""
    for i = 1, math.min(3, #words) do abbreviation = abbreviation .. words[i]:sub(1, 1):upper() end
    if #abbreviation < 2 and words[1] then abbreviation = words[1]:sub(1, 3):upper() end
    return abbreviation ~= "" and abbreviation or "GDB"
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

local raidStartTimes = {}
for minutes = 0, 1439, 30 do
    local hour = math.floor(minutes / 60)
    raidStartTimes[#raidStartTimes + 1] = ("%d:%02d %s"):format((hour % 12 == 0) and 12 or hour % 12, minutes % 60, hour < 12 and "AM" or "PM")
end

local function createRaidDatePicker(dialog, field, offset)
    local input = CreateFrame("Button", nil, dialog)
    styleRaidButton(input, 370)
    input:SetPoint("TOPLEFT", 20, -offset - 16)
    input.selectedValue = field.value or date("%d-%m-%Y")
    input:SetText(input.selectedValue)
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetSize(294, 286)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetFrameLevel(dialog:GetFrameLevel() + 10)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 12 })
    popup:SetBackdropColor(0.025, 0.032, 0.043, 1)
    popup:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
    popup:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -4)
    popup:Hide()
    input.popup = popup
    dialog.dropdowns[#dialog.dropdowns + 1] = input
    local heading = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("TOP", 0, -16)
    local day, month, year = input.selectedValue:match("^(%d%d)%-(%d%d)%-(%d%d%d%d)$")
    local current = date("*t")
    month, year = tonumber(month) or current.month, tonumber(year) or current.year
    local cells = {}
    local function render()
        local first = date("*t", time({ year = year, month = month, day = 1, hour = 12 }))
        local last = date("*t", time({ year = year, month = month + 1, day = 0, hour = 12 })).day
        heading:SetText(date("%B %Y", time({ year = year, month = month, day = 1, hour = 12 })))
        for index, cell in ipairs(cells) do
            local number = index - first.wday + 1
            cell:SetShown(number >= 1 and number <= last)
            if number >= 1 and number <= last then
                local value = ("%02d-%02d-%04d"):format(number, month, year)
                cell.value = value
                styleRaidButton(cell, 34, value == input.selectedValue and "primary" or "secondary")
                cell:SetText(number)
            end
        end
    end
    for index, label in ipairs({ "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" }) do
        local text = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        text:SetPoint("TOPLEFT", 15 + (index - 1) * 38, -48)
        text:SetWidth(34)
        text:SetText(label)
    end
    for index = 1, 42 do
        local cell = CreateFrame("Button", nil, popup)
        cell:SetPoint("TOPLEFT", 15 + ((index - 1) % 7) * 38, -68 - math.floor((index - 1) / 7) * 34)
        cell:SetScript("OnClick", function(button)
            input.selectedValue = button.value
            input:SetText(button.value)
            popup:Hide()
        end)
        cells[index] = cell
    end
    for _, direction in ipairs({ -1, 1 }) do
        local delta = direction
        local button = CreateFrame("Button", nil, popup)
        styleRaidButton(button, 30)
        button:SetPoint(delta < 0 and "TOPLEFT" or "TOPRIGHT", delta < 0 and 12 or -12, -10)
        button:SetText(delta < 0 and "<" or ">")
        button:SetScript("OnClick", function()
            local nextMonth = date("*t", time({ year = year, month = month + delta, day = 1, hour = 12 }))
            month, year = nextMonth.month, nextMonth.year
            render()
        end)
    end
    input:SetScript("OnClick", function()
        local shown = popup:IsShown()
        for _, dropdown in ipairs(dialog.dropdowns) do dropdown.popup:Hide() end
        if not shown then render(); popup:Show() end
    end)
    return input
end

local dialogCounter = 0
local function showInputForm(title, fields, onAccept, acceptLabel, hideClose)
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
        if field.calendar then
            input = createRaidDatePicker(dialog, field, offset)
        elseif field.options then
            input = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
            GH:StyleButton(input)
            input:SetSize(370, 24)
            input:SetPoint("TOPLEFT", 20, -offset - 16)
            input.selectedValue = field.value or field.options[1]
            input:SetText(input.selectedValue or "Select...")
            -- Keep dropdown menus on UIParent so they render and receive clicks
            -- above the modal and its sibling edit boxes in the older client UI.
            local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            popup:SetSize(370, math.min(#field.options, 8) * 24 + 8)
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
            local listScroll = CreateFrame("ScrollFrame", nil, popup)
            listScroll:SetPoint("TOPLEFT", 4, -4)
            listScroll:SetPoint("BOTTOMRIGHT", -4, 4)
            local listContent = CreateFrame("Frame", nil, listScroll)
            listContent:SetSize(356, #field.options * 24)
            listScroll:SetScrollChild(listContent)
            listScroll:EnableMouseWheel(true)
            local maxScroll = math.max(0, (#field.options - 8) * 24)
            listScroll:SetScript("OnMouseWheel", function(self, delta)
                self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 72)))
            end)
            for optionIndex, option in ipairs(field.options) do
                local chosenOption = option
                local optionButton = CreateFrame("Button", nil, listContent)
                styleRaidButton(optionButton, 356)
                optionButton:SetSize(356, 22)
                optionButton:SetPoint("TOPLEFT", 1, -(optionIndex - 1) * 24)
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
                local selectedIndex = 1
                for index, value in ipairs(field.options) do if value == dropdownInput.selectedValue then selectedIndex = index; break end end
                listScroll:SetVerticalScroll(math.min(maxScroll, math.max(0, (selectedIndex - 3) * 24)))
                dropdownPopup:SetShown(not wasShown)
            end)
        else
            input = CreateFrame("EditBox", nil, dialog, "BackdropTemplate")
            input:SetSize(370, height)
            input:SetPoint("TOPLEFT", 20, -offset - 16)
            GH:StyleEditBox(input, field.multiline)
        end
        if not field.options and not field.calendar then
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
    if not hideClose then
        local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() dialog:Hide() end)
    end
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
    accept:SetText(acceptLabel or "Save")
    accept:SetScript("OnClick", function()
        local values = {}
        for i, input in ipairs(dialog.inputs) do values[i] = input.selectedValue or input:GetText() end
        local ok, result = onAccept(values)
        if ok then dialog:Hide() end
        if result then print("GuildDB: " .. result) end
    end)
    UISpecialFrames = UISpecialFrames or {}
    table.insert(UISpecialFrames, 1, name)
    dialog:SetScript("OnHide", function()
        for _, dropdown in ipairs(dialog.dropdowns) do dropdown.popup:Hide() end
        for i = #UISpecialFrames, 1, -1 do if UISpecialFrames[i] == name then table.remove(UISpecialFrames, i) end end
    end)
    dialog:Show()
    for index, input in ipairs(dialog.inputs) do
        if not fields[index].readOnly and not fields[index].options and not fields[index].calendar then
            input:SetFocus()
            break
        end
    end
end

local function calendarSettingsFromForm(values, offset)
    local inviteChoice = values[offset + 2]
    return {
        category = values[offset],
        locked = values[offset + 1] == "Locked",
        inviteMode = inviteChoice == "Selected players" and "selected"
            or inviteChoice == "Mass invite guild" and "guild" or "none",
        inviteNames = values[offset + 3] or "",
    }
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
    frame.logoMark:SetSize(54, 54)
    frame.logoMark:SetTexCoord(0, 1, 0, 1)
    frame.logoMark:SetBlendMode("ADD")
    frame.logoAbbreviation = frame.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.logoAbbreviation:SetPoint("CENTER", frame.logoMark, "CENTER")
    frame.logoAbbreviation:SetWidth(38)
    frame.logoAbbreviation:SetJustifyH("CENTER")
    frame.logoAbbreviation:SetTextColor(0.92, 0.96, 1)
    frame.logoAbbreviation:Hide()
    frame.logoText = frame.header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.logoText:SetPoint("LEFT", frame.logoMark, "RIGHT", 10, 5)
    frame.logoText:SetText("GuildDB")
    setTextColor(frame.logoText, CREAM)
    frame.version = frame.header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.version:SetPoint("TOPLEFT", frame.logoText, "BOTTOMLEFT", 0, -1)
    frame.version:SetText("GuildDB - v" .. tostring(GH.version))
    frame.headerStatus = frame.header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.headerStatus:SetJustifyH("RIGHT")
    frame.close = CreateFrame("Button", nil, frame.header)
    frame.close:SetSize(30, 30)
    frame.close:SetPoint("RIGHT", -12, 0)
    frame.close:SetText("X")
    GH:StyleButton(frame.close)
    frame.close:GetFontString():SetFontObject("GameFontNormalLarge")
    frame.close:GetFontString():SetTextColor(0.92, 0.96, 1)
    frame.close:GetFontString():ClearAllPoints()
    frame.close:GetFontString():SetPoint("CENTER", frame.close, "CENTER", 0, 0)
    frame.close:SetScript("OnClick", function() frame:Hide() end)
    frame.headerStatus:SetPoint("RIGHT", frame.close, "LEFT", -10, 0)
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
    GH:StyleEditBox(frame.rosterSearch)
    frame.rosterSearch:SetText("Search...")
    frame.rosterSearch:SetTextColor(MUTED_GOLD[1], MUTED_GOLD[2], MUTED_GOLD[3])
    frame.rosterSearch:SetScript("OnEditFocusGained", function(self)
        if self:GetText() == "Search..." then self:SetText(""); self:SetTextColor(CREAM[1], CREAM[2], CREAM[3]) end
        self:SetGuildHallFocusState(true)
    end)
    frame.rosterSearch:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then self:SetText("Search..."); self:SetTextColor(MUTED_GOLD[1], MUTED_GOLD[2], MUTED_GOLD[3]) end
        self:SetGuildHallFocusState(false)
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
    for _, column in ipairs({ { "NAME", "name", 10, 130 }, { "LEVEL", "level", 145, 60 }, { "RANK", "rank", 215, 82 }, { "ZONE", "zone", 300, 120 }, { "ROLE", "role", 425, 58 }, { "GDB", "hq", 490, 55 } }) do
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
    frame.detailMeta:SetText("GuildDB  ·  Shared with your guild")
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
    frame.pvpTitleSeason:SetPoint("TOPLEFT", frame.detailPanel, "TOPLEFT", 18, -40)
    frame.pvpTitleSeason:SetPoint("TOPRIGHT", frame.detailPanel, "TOPRIGHT", -18, -40)
    frame.pvpTitleSeason:SetJustifyH("LEFT")
    frame.pvpTitleSeason:SetHeight(38)
    frame.pvpTitleSeason:SetWordWrap(true)
    frame.pvpTitleSeason:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    frame.pvpSummary = frame.detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.pvpSummary:SetPoint("TOPLEFT", 18, -82)
    frame.pvpInfo = frame.detailPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.pvpInfo:SetPoint("TOPLEFT", 18, -106)
    frame.pvpInfo:SetPoint("TOPRIGHT", -18, -106)
    frame.pvpInfo:SetHeight(34)
    frame.pvpInfo:SetWordWrap(true)
    frame.pvpInfo:SetJustifyH("LEFT")
    frame.pvpTableRule = frame.detailPanel:CreateTexture(nil, "ARTWORK")
    frame.pvpTableRule:SetPoint("TOPLEFT", 14, -172)
    frame.pvpTableRule:SetPoint("TOPRIGHT", -14, -172)
    frame.pvpTableRule:SetHeight(1)
    frame.pvpTableRule:SetColorTexture(0.12, 0.25, 0.37, 0.9)
    frame.pvpHeaders = {}
    local function addPvpHeader(text, x, width, justify)
        local header = frame.detailPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        header:SetPoint("TOPLEFT", x, -153)
        header:SetWidth(width)
        header:SetJustifyH(justify or "LEFT")
        header:SetText(text)
        header:SetTextColor(MUTED_GOLD[1], MUTED_GOLD[2], MUTED_GOLD[3])
        frame.pvpHeaders[#frame.pvpHeaders + 1] = header
    end
    addPvpHeader("#", 12, 28)
    addPvpHeader("PLAYER", 48, 170)
    addPvpHeader("KILLS", 260, 90, "CENTER")
    addPvpHeader("DEATHS", 370, 90, "CENTER")
    addPvpHeader("LAST KILL", 490, 280)
    frame.pvpRows = {}
    frame.detailPanel:HookScript("OnSizeChanged", function(panel)
        local width = math.max(1, panel:GetWidth() - 28)
        for index, header in ipairs(frame.pvpHeaders) do
            layoutPvPColumn(header, index, panel, width, 14, true)
        end
        for _, row in ipairs(frame.pvpRows) do
            for index, text in ipairs({ row.rank, row.player, row.points, row.kills, row.last }) do
                layoutPvPColumn(text, index, row, width, 0, false)
            end
        end
    end)
    frame.pvpEmpty = frame.detailChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.pvpEmpty:SetPoint("TOPLEFT", 12, -14)
    frame.pvpEmpty:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
    frame.pvpMyButton = CreateFrame("Button", nil, frame.detailPanel, "UIPanelButtonTemplate")
    GH:StyleButton(frame.pvpMyButton)
    frame.pvpMyButton:SetSize(98, 26)
    frame.pvpMyButton:SetPoint("TOPRIGHT", -142, -12)
    frame.pvpMyButton:SetScript("OnClick", function()
        frame.pvpMyOnly = not frame.pvpMyOnly
        GH:RefreshUI()
    end)
    frame.pvpSeasonButton = CreateFrame("Button", nil, frame.detailPanel, "UIPanelButtonTemplate")
    GH:StyleButton(frame.pvpSeasonButton, "primary")
    frame.pvpSeasonButton:SetSize(112, 26)
    frame.pvpSeasonButton:SetPoint("BOTTOMLEFT", 18, 12)
    frame.pvpSeasonButton:SetText("New Season")
    frame.pvpSeasonButton:SetScript("OnClick", function()
        if not GH:CanManagePvPSeason() then return end
        local currentName = GH.bucket and GH.bucket.pvpSeason and GH.bucket.pvpSeason.name or ""
        local currentNumber = tonumber(currentName:match("(%d+)$")) or 0
        showInputForm("Start a PvP season", {
            { label = "Season name", value = "Season " .. tostring(currentNumber + 1), max = 80 },
            { label = "End date (includes this day)", value = date("%d-%m-%Y", time() + 30 * 86400), calendar = true },
        }, function(values)
            local ok, result = GH:StartPvPSeason(values[1], values[2])
            if ok then
                frame.pvpSelectedStart = nil; frame.pvpAllTime = false
                GH:RefreshUI()
            end
            return ok, result
        end, "Start", true)
    end)
    frame.pvpDeleteButton = CreateFrame("Button", nil, frame.detailPanel, "UIPanelButtonTemplate")
    GH:StyleButton(frame.pvpDeleteButton)
    frame.pvpDeleteButton:SetSize(116, 26)
    frame.pvpDeleteButton:SetPoint("LEFT", frame.pvpSeasonButton, "RIGHT", 8, 0)
    frame.pvpDeleteButton:SetText("Delete Season")
    frame.pvpDeleteButton:SetScript("OnClick", function()
        if not GH:CanManagePvPSeason() then return end
        local options, starts, selectedLabel = {}, {}, nil
        local selected = GH:GetPvPLeaderboard(frame.pvpAllTime, frame.pvpSelectedStart)
        for _, season in ipairs(GH:GetPvPSeasons()) do
            if season.start > 0 then
                local label = season.name .. " (" .. date("%d-%m-%Y %H:%M:%S", season.start) .. ")"
                options[#options + 1], starts[label] = label, season.start
                if season.start == selected.start then selectedLabel = label end
            end
        end
        if #options == 0 then return end
        showInputForm("Delete Season", {
            { label = "Season to permanently delete", value = selectedLabel or options[1], options = options },
            { label = "All-time stats will be kept.", value = "This removes the season and its leaderboard.", readOnly = true },
        }, function(values)
            local ok, result = GH:DeletePvPSeason(starts[values[1]])
            if ok then
                frame.pvpSelectedStart, frame.pvpAllTime = 0, true
                GH:RefreshUI()
            end
            return ok, result
        end, "Delete", true)
    end)
    frame.pvpWipeButton = CreateFrame("Button", nil, frame.detailPanel, "UIPanelButtonTemplate")
    GH:StyleButton(frame.pvpWipeButton)
    frame.pvpWipeButton:SetSize(120, 26)
    frame.pvpWipeButton:SetPoint("LEFT", frame.pvpDeleteButton, "RIGHT", 8, 0)
    frame.pvpWipeButton:SetText("Wipe All Stats")
    frame.pvpWipeButton:SetScript("OnClick", function()
        if not GH:CanManagePvPSeason() then return end
        showInputForm("Wipe All PvP Stats?", {
            { label = "Permanently erases PvP stats for the whole guild.", value = "All-time totals, kills, deaths, history and every season will be erased. You can then start a new Season 1.", multiline = true, readOnly = true },
        }, function()
            local ok, result = GH:WipePvPStats()
            if ok then
                frame.pvpSelectedStart, frame.pvpAllTime = nil, false
                GH:RefreshUI()
            end
            return ok, result
        end, "Wipe All", true)
    end)
    frame.pvpScopeButton = CreateFrame("Button", nil, frame.detailPanel, "UIPanelButtonTemplate")
    GH:StyleButton(frame.pvpScopeButton)
    frame.pvpScopeButton:SetSize(116, 26)
    frame.pvpScopeButton:SetPoint("TOPRIGHT", -18, -12)
    local seasonMenu = CreateFrame("ScrollFrame", nil, UIParent, "UIPanelScrollFrameTemplate,BackdropTemplate")
    seasonMenu:SetSize(280, 220)
    seasonMenu:SetPoint("TOPRIGHT", frame.pvpScopeButton, "BOTTOMRIGHT", -24, -4)
    seasonMenu:SetFrameStrata("TOOLTIP")
    seasonMenu:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
    seasonMenu:SetBackdropColor(0.025, 0.032, 0.043, 1)
    local seasonOptions = CreateFrame("Frame", nil, seasonMenu)
    seasonOptions:SetSize(280, 220)
    seasonMenu:SetScrollChild(seasonOptions)
    seasonMenu.buttons = {}
    seasonMenu:Hide()
    frame:HookScript("OnHide", function() seasonMenu:Hide() end)
    frame.pvpScopeButton:HookScript("OnHide", function() seasonMenu:Hide() end)
    frame.pvpScopeButton:SetScript("OnClick", function()
        if seasonMenu:IsShown() then seasonMenu:Hide(); return end
        local choices = GH:GetPvPSeasons()
        choices[#choices + 1] = { name = "Tracking details", tracking = true }
        for index, choice in ipairs(choices) do
            local option = seasonMenu.buttons[index]
            if not option then
                option = CreateFrame("Button", nil, seasonOptions, "UIPanelButtonTemplate")
                GH:StyleButton(option)
                option:SetSize(276, 28)
                option:SetPoint("TOPLEFT", 2, -(index - 1) * 30)
                seasonMenu.buttons[index] = option
            end
            option:SetText(choice.name)
            local start = choice.start
            local tracking = choice.tracking
            option:SetScript("OnClick", function()
                if tracking then
                    seasonMenu:Hide()
                    showInputForm("PvP tracking details", {
                        { label = "Last tracking result", value = (GH.pvpTrackingStatus or "No honor or kill-credit event received this session.") .. "\n\nLast honor message:\n" .. (GH.pvpLastHonorMessage or "None received"), multiline = true, readOnly = true, max = 1000 },
                        { label = "Client event support", value = "Honor: " .. ((GH.eventRegistration or {}).CHAT_MSG_COMBAT_HONOR_GAIN or "unknown") .. "\nKill credit: " .. ((GH.eventRegistration or {}).PLAYER_PVP_KILLS_CHANGED or "unknown"), multiline = true, readOnly = true, max = 300 },
                    }, function() return true end, "Done", true)
                    return
                end
                frame.pvpSelectedStart = start
                frame.pvpAllTime = start == 0
                seasonMenu:Hide()
                GH:RefreshUI()
            end)
            option:Show()
        end
        for index = #choices + 1, #seasonMenu.buttons do seasonMenu.buttons[index]:Hide() end
        seasonOptions:SetHeight(math.max(30, #choices * 30))
        seasonMenu:SetHeight(math.min(220, #choices * 30))
        seasonMenu:SetVerticalScroll(0)
        seasonMenu:Show()
    end)
    frame.eventCreateButton = CreateFrame("Button", nil, frame.detailPanel)
    styleRaidButton(frame.eventCreateButton, 128, "primary")
    frame.eventCreateButton:SetPoint("TOPRIGHT", -18, -12)
    frame.eventCreateButton:SetText("Create raid")
    frame.eventCreateButton:SetScript("OnClick", function()
        local tomorrow = time() + 86400
        showInputForm("Create guild raid", {
            { label = "Raid title", value = "Guild raid", max = 100 },
            { label = "Raid date (your local calendar)", value = date("%d-%m-%Y", tomorrow), calendar = true },
            { label = "Start time (your local time)", value = "8:00 PM", options = raidStartTimes },
            { label = "Raid size target", value = "40", options = { "10", "20", "25", "40" } },
            { label = "Sign-ups", value = "Open", options = { "Open", "Locked" } },
            { label = "Details", value = "", max = 300, multiline = true },
            { label = "Guild calendar", value = "Create guild calendar event", options = { "Create guild calendar event", "GuildDB only" } },
        }, function(values)
            local settings = { category = "Raid", raidSize = tonumber(values[4]), locked = values[5] == "Locked" }
            local ok, result, eventId = GH:PostEventFields(values[2], values[3], values[1], values[6], "raid", settings)
            if not ok then return false, result end
            if values[7] == "Create guild calendar event" then
                local exported, message = GH:AddEventToGameCalendar(eventId)
                result = result .. " " .. (exported and message or ("Calendar copy could not be created: " .. message .. " Use Create calendar on the raid to retry."))
            end
            return true, result
        end, "Create raid")
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
            }, function(values) return GH:PostAnnouncement(values[1], values[2]) end, "Post")
        elseif tab == "Guide" then
            local guide = GH.bucket and GH.bucket.guide or {}
            showInputForm("Edit guild guide", {
                { label = "Guild rules", value = guide.rules or "", max = 700, multiline = true },
                { label = "Loot rules", value = guide.loot or "", max = 700, multiline = true },
            }, function(values) return GH:SetGuide(values[1], values[2]) end)
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
            print("GuildDB: Profile editor error: " .. tostring(err))
        else
            print("GuildDB: Profile editor opened.")
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
            print("GuildDB: Select a roster member first.")
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
            print("GuildDB: This client does not expose a group invite function.")
            return
        end

        local ok, err = pcall(invite, name)
        if not ok then print("GuildDB: Could not invite " .. GH:Display(name) .. ": " .. tostring(err)) end
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
            print(#matches > 0 and ("GuildDB crafters: " .. table.concat(matches, "; ")) or "GuildDB: No online member lists that profession or recipe in their profile.")
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
    frame.footer:SetText("/gd for commands")
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
    button.label:SetText(tab == "Events" and "Raid Info" or tab)
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
    local faction = UnitFactionGroup and UnitFactionGroup("player") or nil
    local emblem = faction == "Horde" and "HordeEmblem.png" or "AllianceEmblem.png"
    frame.logoMark:SetTexture("Interface\\AddOns\\GuildHall\\Assets\\" .. emblem)
    frame.logoText:SetText("GuildDB")
    frame.logoAbbreviation:SetText(guildAbbreviation(self.guildName or "Guild"))
    frame.listHeader:SetText(active:upper())
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
            for columnIndex, spec in ipairs({ { 10, 128, "LEFT" }, { 145, 60, "LEFT" }, { 215, 82, "LEFT" }, { 300, 120, "LEFT" }, { 425, 58, "LEFT" }, { 490, 55, "LEFT" } }) do
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
            local addonStatus = version and ("GuildDB v" .. version) or "No addon detected"
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
            row.columns[1]:SetText(self:Display(member.name))
            local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.classFile]
            if classColor then row.columns[1]:SetTextColor(classColor.r, classColor.g, classColor.b)
            else row.columns[1]:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
            row.columns[2]:SetText(tostring(member.level or "-"))
            row.columns[3]:SetText(self:Display(member.rank or "Member"))
            row.columns[4]:SetText(self:Display(member.zone or "-"))
            row.columns[5]:SetText(self:Display(profile.role or "-"))
            row.columns[6]:SetText(version or "-")
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
    frame.detailRule:SetShown(not isPvP and not isEvents and not isActionList)
    frame.detailMeta:SetShown(not isPvP and not isActionList)
    frame.detailScroll:ClearAllPoints()
    if isPvP then
        frame.detailScroll:SetPoint("TOPLEFT", 10, -184)
        frame.detailScroll:SetPoint("BOTTOMRIGHT", -10, self:CanManagePvPSeason() and 54 or 12)
    else
        frame.detailScroll:SetPoint("TOPLEFT", 10, -66)
        frame.detailScroll:SetPoint("BOTTOMRIGHT", -28, 54)
    end
    for _, element in ipairs({ frame.pvpTitleSeason, frame.pvpSummary, frame.pvpInfo, frame.pvpTableRule, frame.pvpMyButton, frame.pvpSeasonButton, frame.pvpDeleteButton, frame.pvpWipeButton, frame.pvpScopeButton }) do
        element:SetShown(isPvP)
    end
    frame.eventCreateButton:SetShown(isEvents and self:CanManage())
    frame.eventCreateTypeButton:Hide()
    local actionVisible = active == "Profiles" or active == "Looking For" or active == "Crafting" or (active == "Polls" and self:CanManage()) or ((active == "Announcements" or active == "Guide") and self:CanManage())
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
        local status = member and (member.online and "Online" or "Offline") or "Unavailable"
        local zone = member and member.zone and member.zone ~= "" and self:Display(member.zone) or "Unknown"
        local profileName = profile and table.concat({ profile.firstName or "", profile.lastName or "" }, " "):gsub("^%s+", ""):gsub("%s+$", "") or ""
        if profileName == "" then profileName = "Not set" end
        local addonLine = "GuildDB  " .. (version and ("v" .. version) or "Not detected") .. "\n\n"
        frame.detailBody:SetText(addonLine .. "Name: " .. self:Display(profileName) .. "\n\nStatus: " .. status .. "  -  " .. zone .. "\n\nRole: " .. value("role") .. "\n\nProfessions: " .. value("professions") .. "\n\nSpecialization: " .. value("spec") .. "\n\nTime zone: " .. value("timezone") .. "\n\nAlts: " .. value("alts"))
    elseif active == "PvP" then
        self:HideSettingsControls()
        frame.detailBody:Hide()
        frame.detailTitle:SetWidth(math.min(390, math.max(250, frame.detailPanel:GetWidth() - 500)))
        frame.detailTitle:SetText("PVP LEADERBOARD")
        local season, ranking, ownScore, ownRank = self:GetPvPLeaderboard(frame.pvpAllTime, frame.pvpSelectedStart)
        local deadline = season.ends and season.ends > 0 and season.ends
        local seasonStatus = ""
        if deadline then
            local daysLeft = math.ceil((deadline - time()) / 86400)
            seasonStatus = daysLeft > 0 and (" - Ends in " .. daysLeft .. (daysLeft == 1 and " day" or " days")) or " - Ended"
        end
        frame.pvpTitleSeason:SetText((season.name or "Season 1") .. seasonStatus)
        if not frame.pvpCountdownTicker and C_Timer.NewTicker then
            frame.pvpCountdownTicker = C_Timer.NewTicker(60, function()
                if frame:IsShown() and GH.activeTab == "PvP" then GH:RefreshUI() end
            end)
        end
        frame.pvpMyButton:SetText(frame.pvpMyOnly and "Guild board" or "My stats")
        frame.pvpSeasonButton:SetShown(self:CanManagePvPSeason())
        frame.pvpDeleteButton:SetShown(self:CanManagePvPSeason())
        frame.pvpDeleteButton:SetEnabled(#self:GetPvPSeasons() > 1)
        frame.pvpWipeButton:SetShown(self:CanManagePvPSeason())
        frame.pvpScopeButton:SetText("Seasons  v")
        local playerName = UnitName and UnitName("player") or "You"
        frame.pvpSummary:SetText(ownScore and ("You: |cffffcc33%d kills|r  -  #%d"):format(ownScore.kills, ownRank) or (playerName .. ": no PvP kills yet"))
        frame.pvpInfo:SetText("Top 10 by honorable kills  |  Open world only  |  1 kill per game-credited honorable kill  |  Same player: once per 5 min, 5 per day")
        if frame.pvpMyOnly then
            local own = ownScore
            ranking = own and { own } or {}
        else
            while #ranking > 10 do table.remove(ranking) end
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
        local classByName = {}
        local function characterKey(name)
            return (tostring(name or ""):match("^([^-]+)") or ""):lower():gsub("%s", "")
        end
        if GetNumGuildMembers and GetGuildRosterInfo then
            for index = 1, GetNumGuildMembers() do
                local name, _, _, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(index)
                if name and classFile then classByName[characterKey(name)] = classFile end
            end
        end
        local boardWidth = math.max(1, frame.detailPanel:GetWidth() - 28)
        for index, header in ipairs(frame.pvpHeaders) do
            layoutPvPColumn(header, index, frame.detailPanel, boardWidth, 14, true)
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
                row.last = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                frame.pvpRows[i] = row
            end
            for index, text in ipairs({ row.rank, row.player, row.points, row.kills, row.last }) do
                layoutPvPColumn(text, index, row, boardWidth, 0, false)
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 36)
            row:SetPoint("RIGHT", frame.detailChild, "RIGHT", -4, 0)
            row.rank:SetText(tostring(i))
            row.player:SetText(self:Display(leaderboardName(score.name)))
            local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classByName[characterKey(score.name)]]
            if classColor then row.player:SetTextColor(classColor.r, classColor.g, classColor.b)
            else row.player:SetTextColor(CREAM[1], CREAM[2], CREAM[3]) end
            row.points:SetText(tostring(score.points or 0))
            row.points:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
            row.kills:SetText(tostring(score.deaths or 0))
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
        frame.detailTitle:SetText("RAID SIGNUPS")
        frame.detailMeta:SetText("Choose your attendance, spec and role. The GM checks attending players for invites.")
        local events = self.GetUpcomingEvents and self:GetUpcomingEvents() or {}
        local player = self:PlayerName()
        local eventY = 4
        for i, event in ipairs(events) do
            local row = frame.eventRows[i]
            if not row then
                row = CreateFrame("Frame", nil, frame.detailChild)
                row:SetHeight(190)
                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                row.title:SetPoint("TOPLEFT", 16, -16)
                row.title:SetWidth(360)
                row.title:SetJustifyH("LEFT")
                row.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
                row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                row.info:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
                row.info:SetWidth(360)
                row.info:SetHeight(28)
                row.details = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.details:SetPoint("TOPLEFT", row.info, "BOTTOMLEFT", 0, -4)
                row.details:SetWidth(360)
                row.details:SetHeight(32)
                row.accent = row:CreateTexture(nil, "ARTWORK")
                row.accent:SetPoint("TOPLEFT", 0, 0)
                row.accent:SetPoint("TOPRIGHT", 0, 0)
                row.accent:SetHeight(2)
                row.accent:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.7)
                row.state = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.state:SetPoint("TOPRIGHT", -16, -18)
                row.state:SetJustifyH("RIGHT")
                row.statCards = {}
                for index, label in ipairs({ "GOING", "TANKS", "HEALERS", "DPS", "MAYBE", "ABSENT", "INVITES" }) do
                    local stat = CreateFrame("Frame", nil, row)
                    stat.bg = stat:CreateTexture(nil, "BACKGROUND")
                    stat.bg:SetAllPoints()
                    stat.bg:SetColorTexture(0.035, 0.045, 0.062, 0.95)
                    stat.value = stat:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                    stat.value:SetPoint("TOP", 0, -8)
                    stat.label = stat:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                    stat.label:SetPoint("BOTTOM", 0, 7)
                    stat.label:SetText(label)
                    row.statCards[index] = stat
                end
                row.personalStatus = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.personalStatus:SetPoint("TOPLEFT", 16, -166)
                row.personalStatus:SetJustifyH("LEFT")
                row.rosterRule = row:CreateTexture(nil, "ARTWORK")
                row.rosterRule:SetPoint("TOPLEFT", 14, -250)
                row.rosterRule:SetPoint("TOPRIGHT", -14, -250)
                row.rosterRule:SetHeight(1)
                row.rosterRule:SetColorTexture(0.16, 0.23, 0.31, 1)
                row.emptyRoster = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.emptyRoster:SetPoint("TOPLEFT", 18, -272)
                row.emptyRoster:SetText("No signups yet. Be the first to join this raid.")
                row.rosterHeaders = {}
                for column, label in ipairs({ "PLAYER", "CLASS", "SPEC", "ROLE", "ATTENDANCE" }) do
                    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    text:SetText(label)
                    text:SetJustifyH("LEFT")
                    row.rosterHeaders[column] = text
                end
                row.inviteHeader = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                row.inviteHeader:SetPoint("TOPLEFT", 16, -232)
                row.inviteHeader:SetText("RAID ROSTER  |  Checked = selected for invite")
                row.classRows = {}
                row.classTitle = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.classTitle:SetJustifyH("LEFT")
                row.classTitle:SetText("CLASS COMPOSITION  |  Signed up / Invited")
                row.inviteButton = CreateFrame("Button", nil, row)
                styleRaidButton(row.inviteButton, 136, "primary")
                row.inviteButton:SetPoint("TOPRIGHT", -16, -216)
                row.inviteButton:SetText("Invite selected")
                row.inviteButton:SetScript("OnClick", function(button)
                    local _, result = GH:InviteRaidSelections(button.eventId)
                    if result then print("GuildDB: " .. result) end
                end)
                row.signupRows = {}
                row.rsvpButtons = {}
                row.calendarButton = CreateFrame("Button", nil, row)
                styleRaidButton(row.calendarButton, 128, "secondary")
                row.calendarButton:SetPoint("TOPLEFT", 16, -184)
                row.calendarButton:SetScript("OnClick", function(self)
                    local _, result = GH:AddEventToGameCalendar(self.eventId)
                    if result then print("GuildDB: " .. result) end
                end)
                row.editButton = CreateFrame("Button", nil, row)
                styleRaidButton(row.editButton, 88, "secondary")
                row.editButton:SetPoint("LEFT", row.calendarButton, "RIGHT", 8, 0)
                row.editButton:SetText("Edit")
                row.editButton:SetScript("OnClick", function(self)
                    local event
                    for _, candidate in ipairs(GH.bucket and GH.bucket.events or {}) do
                        if candidate.id == self.eventId then event = candidate; break end
                    end
                    if not event then return end
                    local settings = event.calendarSettings or {}
                    local category = settings.category or (event.eventType == "raid" and "Raid" or "Other")
                    local inviteMode = settings.inviteMode == "selected" and "Selected players"
                        or settings.inviteMode == "guild" and "Mass invite guild" or "No invites"
                    showInputForm("Edit guild event", {
                        { label = "Title", value = event.title or "", max = 100 },
                        { label = "Raid date (your local calendar)", value = date("%d-%m-%Y", event.at), calendar = true },
                        { label = "Start time (your local time)", value = date("%I:%M %p", event.at):gsub("^0", ""), options = raidStartTimes },
                        { label = "Calendar category", value = category, options = { "Raid", "Dungeon", "PvP", "Meeting", "Other" } },
                        { label = "Sign-ups", value = settings.locked and "Locked" or "Open", options = { "Open", "Locked" } },
                        { label = "Invitations", value = inviteMode, options = { "No invites", "Selected players", "Mass invite guild" } },
                        { label = "Players to invite (comma separated)", value = settings.inviteNames or "", max = 200 },
                        { label = "Details", value = event.details or "", max = 300, multiline = true },
                        { label = "Raid size target", value = tostring(settings.raidSize or 40), options = { "10", "20", "25", "40" } },
                    }, function(values)
                        local at, reason = GH:ParseEventTimeFields(values[2], values[3])
                        if not at then return false, reason end
                        local updatedSettings = calendarSettingsFromForm(values, 4)
                        updatedSettings.raidSize = tonumber(values[9])
                        return GH:EditEvent(self.eventId, at, values[1], values[8], updatedSettings)
                    end)
                end)
                row.deleteButton = CreateFrame("Button", nil, row)
                styleRaidButton(row.deleteButton, 88, "danger")
                row.deleteButton:SetPoint("LEFT", row.editButton, "RIGHT", 8, 0)
                row.deleteButton:SetText("Delete raid")
                row.deleteButton:SetScript("OnClick", function(self)
                    showInputForm("Remove guild event", {
                        { label = "Type REMOVE to confirm", value = "", max = 12 },
                    }, function(values)
                        if tostring(values[1] or ""):upper() ~= "REMOVE" then
                            return false, "Type REMOVE to confirm event removal."
                        end
                        return GH:DeleteEvent(self.eventId)
                    end)
                end)
                row.withdrawButton = CreateFrame("Button", nil, row)
                styleRaidButton(row.withdrawButton, 112, "danger")
                row.withdrawButton:SetPoint("TOPRIGHT", -16, -184)
                row.withdrawButton:SetText("Withdraw")
                row.withdrawButton:SetScript("OnClick", function(button)
                    local _, result = GH:RemoveRaidSignup(button.eventId)
                    if result then print("GuildDB: " .. result) end
                end)
                for buttonIndex, state in ipairs({ { "Sign up / Change", "going" } }) do
                    local button = CreateFrame("Button", nil, row)
                    styleRaidButton(button, 128, "primary")
                    button:SetPoint("TOPRIGHT", -136, -184)
                    button:SetText(state[1])
                    button.status = state[2]
                    button:SetScript("OnClick", function(self)
                        local eventId = self.eventId
                        local profile = GH.GetProfile and GH:GetProfile(player) or {}
                        local current
                        for _, candidate in ipairs(GH.bucket and GH.bucket.events or {}) do
                            if candidate.id == eventId then current = candidate.rsvps and candidate.rsvps[player]; break end
                        end
                        current = type(current) == "table" and current or {}
                        local className = GH:GetRaidPlayerClass(player)
                        local attendance = current.status == "tentative" and "Maybe" or current.status == "absent" and "Absent" or "Going"
                        showInputForm("Your raid signup", {
                            { label = "Attendance", value = attendance, options = { "Going", "Maybe", "Absent" } },
                            { label = "Class (detected automatically)", value = className, readOnly = true },
                            { label = "Spec (e.g. Holy, Protection, Fury)", value = current.spec or (profile and profile.spec) or "", max = 60 },
                            { label = "Role", value = current.role or "DPS", options = { "Tank", "Healer", "DPS" } },
                            { label = "Note (availability, late arrival, etc.)", value = current.note or "", max = 100 },
                        }, function(values)
                            local attendanceStatus = values[1] == "Going" and "going" or values[1] == "Maybe" and "tentative" or "absent"
                            return GH:SetRSVPForEvent(eventId, attendanceStatus, values[4], values[5], values[3])
                        end, "Save signup")
                    end)
                    row.rsvpButtons[buttonIndex] = button
                end
                frame.eventRows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 4, -eventY)
            row:SetPoint("RIGHT", frame.detailChild, "RIGHT", -4, 0)
            row.title:SetText(self:Display(event.title))
            row.title:SetWidth(math.max(180, frame.detailChild:GetWidth() - 200))
            local calendarSettings = event.calendarSettings or {}
            local category = calendarSettings.category or (event.eventType == "raid" and "Raid" or "Other")
            row.info:SetWidth(math.max(180, frame.detailChild:GetWidth() - 48))
            row.info:SetHeight(16)
            row.info:SetText(date("%a, %d %b %Y  |  %I:%M %p", event.at) .. " local  |  " .. category .. "  |  Led by " .. self:Display(event.by))
            row.state:SetText(calendarSettings.locked and "SIGNUPS LOCKED" or "SIGNUPS OPEN")
            if calendarSettings.locked then row.state:SetTextColor(0.92, 0.65, 0.28)
            else row.state:SetTextColor(0.35, 0.85, 0.58) end
            row.details:SetWidth(math.max(180, frame.detailChild:GetWidth() - 48))
            row.details:SetHeight(42)
            row.details:SetText(self:Display(event.details ~= "" and event.details or "No additional raid notes."))
            row.calendarButton.eventId = event.id
            row.calendarButton:SetShown(not event.preview and event.by == player)
            row.editButton.eventId = event.id
            row.deleteButton.eventId = event.id
            local canManageEvent = not event.preview and self:CanManage()
            row.editButton:SetShown(canManageEvent)
            row.deleteButton:SetShown(canManageEvent)
            local actionX = event.by == player and 152 or 16
            row.editButton:ClearAllPoints()
            row.editButton:SetPoint("TOPLEFT", row, "TOPLEFT", actionX, -184)
            local calendarExports = GuildHallDB and GuildHallDB.calendarExports
            if calendarExports and calendarExports[event.id] then
                row.calendarButton:SetText("Calendar added")
                row.calendarButton:Disable()
            else
                row.calendarButton:SetText("Create calendar")
                row.calendarButton:SetEnabled(event.by == player)
            end
            local counts = self:GetRaidSignupSummary(event)
            row.inviteButton.eventId = event.id
            row.inviteButton:SetShown(not event.preview and self:IsRaidGM())
            row.inviteButton:SetEnabled(counts.selected > 0)
            local mine = event.rsvps and event.rsvps[player]
            local myStatus = type(mine) == "table" and mine.status or mine
            local totals = { counts.going, counts.Tank, counts.Healer, counts.DPS, counts.tentative, counts.absent, counts.selected .. "/" .. (calendarSettings.raidSize or 40) }
            local statColors = { {0.35, 0.85, 0.58}, {0.45, 0.70, 1}, {0.35, 0.85, 0.65}, {1, 0.65, 0.38}, {1, 0.78, 0.35}, {0.85, 0.48, 0.48}, GOLD }
            local statWidth = (math.max(350, frame.detailChild:GetWidth() - 40) - 36) / 7
            for index, stat in ipairs(row.statCards) do
                stat:ClearAllPoints()
                stat:SetPoint("TOPLEFT", 16 + (index - 1) * (statWidth + 6), -100)
                stat:SetSize(statWidth, 54)
                stat.value:SetText(totals[index])
                stat.value:SetTextColor(unpack(statColors[index]))
            end
            local statusLabel = myStatus == "going" and "Going" or myStatus == "tentative" and "Maybe" or myStatus == "absent" and "Absent" or "Not signed up"
            row.personalStatus:SetWidth(math.max(180, frame.detailChild:GetWidth() - 48))
            row.personalStatus:SetText("Your signup: " .. statusLabel .. (counts.unassigned > 0 and ("  |  " .. counts.unassigned .. " attending without a role") or ""))
            row.withdrawButton.eventId = event.id
            row.withdrawButton:SetShown(not event.preview and mine ~= nil)
            local widths = { 0.24, 0.18, 0.25, 0.14, 0.19 }
            local available, headerX = math.max(300, frame.detailChild:GetWidth() - 140), 44
            for column, text in ipairs(row.rosterHeaders) do
                text:ClearAllPoints()
                text:SetPoint("TOPLEFT", row, "TOPLEFT", headerX, -259)
                text:SetWidth(available * widths[column] - 6)
                headerX = headerX + available * widths[column]
            end
            local names = {}
            for name in pairs(event.rsvps or {}) do names[#names + 1] = name end
            local function sortRank(name)
                local response = event.rsvps[name]
                response = type(response) == "table" and response or { status = response }
                if response.status == "absent" then return 6 end
                if response.status == "tentative" then return 5 end
                local selected = event.selections and event.selections[name]
                if selected and selected.selected then return 0 end
                return response.role == "Tank" and 1 or response.role == "Healer" and 2 or response.role == "DPS" and 3 or 4
            end
            table.sort(names, function(left, right)
                local a, b = sortRank(left), sortRank(right)
                if a ~= b then return a < b end
                return left:lower() < right:lower()
            end)
            row.emptyRoster:SetShown(#names == 0)

            for index, name in ipairs(names) do
                local response = event.rsvps[name]
                response = type(response) == "table" and response or { status = response }

                local selection = event.selections and event.selections[name]

                local signup = row.signupRows[index]
                if not signup then
                    signup = CreateFrame("Button", nil, row)
                    signup:SetSize(24, 24)
                    styleRaidInviteCheck(signup)
                    signup.band = signup:CreateTexture(nil, "BACKGROUND")
                    signup.band:SetPoint("TOPLEFT", -4, 5)
                    signup.band:SetHeight(42)
                    signup.columns = {}
                    for column = 1, 5 do
                        local text = signup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        text:SetJustifyH("LEFT")
                        text:SetHeight(18)
                        signup.columns[column] = text
                    end
                    signup.note = signup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                    signup.note:SetPoint("TOPLEFT", signup, "TOPRIGHT", 6, -21)
                    signup.note:SetJustifyH("LEFT")
                    signup.note:SetHeight(16)
                    signup.remove = CreateFrame("Button", nil, row)
                    styleRaidButton(signup.remove, 72, "danger")
                    signup.remove:SetText("Remove")
                    signup.remove:SetScript("OnClick", function(button)
                        local eventId, target = button.eventId, button.player
                        showInputForm("Remove raid signup", {
                            { label = "Player", value = target, readOnly = true },
                        }, function() return GH:RemoveRaidSignup(eventId, target) end, "Remove")
                    end)
                    signup:SetScript("OnClick", function(button)
                        local _, result = GH:SetRaidSelection(button.eventId, button.player, not button.selected)
                        if result then print("GuildDB: " .. result) end
                    end)
                    row.signupRows[index] = signup
                end
                signup:SetPoint("TOPLEFT", 14, -282 - (index - 1) * 44)
                signup.band:ClearAllPoints()
                signup.band:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -277 - (index - 1) * 44)
                signup.band:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -277 - (index - 1) * 44)
                signup.band:SetHeight(44)
                signup.band:SetColorTexture(index % 2 == 1 and 0.075 or 0.05, index % 2 == 1 and 0.095 or 0.065, index % 2 == 1 and 0.125 or 0.09, 1)
                signup.eventId, signup.player = event.id, name
                signup.selected = response.status == "going" and selection and selection.selected or false
                signup.mark:SetShown(signup.selected)
                signup:SetEnabled(not event.preview and GH:IsRaidGM() and response.status == "going")
                local className, classFile = GH:GetRaidPlayerClass(name)
                local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                local values = { GH:Display(name), GH:Display(className), GH:Display(response.spec ~= "" and response.spec or "Not set"), response.role or "Not set", response.status == "going" and "Going" or response.status == "tentative" and "Maybe" or "Absent" }
                local widths = { 0.24, 0.18, 0.25, 0.14, 0.19 }
                local available, x = math.max(300, frame.detailChild:GetWidth() - 140), 8
                for column, text in ipairs(signup.columns) do
                    text:ClearAllPoints()
                    text:SetPoint("TOPLEFT", signup, "TOPRIGHT", x, -3)
                    text:SetWidth(available * widths[column] - 6)
                    text:SetText(values[column])
                    text:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
                    if column <= 2 and color then text:SetTextColor(color.r, color.g, color.b) end
                    if column == 5 then
                        if response.status == "going" then text:SetTextColor(0.35, 0.85, 0.58)
                        elseif response.status == "tentative" then text:SetTextColor(1, 0.78, 0.35)
                        else text:SetTextColor(0.85, 0.48, 0.48) end
                    end
                    x = x + available * widths[column]
                end
                signup.note:SetWidth(available)
                signup.note:SetText(GH:Display(response.note or ""))
                signup.tooltipText = GH:Display(className) .. " - " .. GH:Display(response.spec or "Spec not set") .. "\n" .. (response.role or "Role not set") .. " - " .. values[5] .. ((response.note or "") ~= "" and ("\n" .. GH:Display(response.note)) or "")
                if response.status == "going" and selection and selection.selected then signup.band:SetColorTexture(0.07, 0.16, 0.22, 1) end
                signup.remove:SetPoint("TOPRIGHT", row, "TOPRIGHT", -16, -281 - (index - 1) * 44)
                signup.remove.eventId, signup.remove.player = event.id, name
                signup.remove:SetShown(not event.preview and (GH:IsRaidGM() or name == player))
                signup:Show()
            end
            for index = #names + 1, #row.signupRows do row.signupRows[index]:Hide(); row.signupRows[index].remove:Hide() end
            local rowHeight = 298 + math.max(1, #names) * 44
            local classes, classOrder = {}, {}
            local defaults = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
            for token, label in pairs(defaults) do
                classes[token] = { label = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or label, going = 0, selected = 0, maybe = 0 }
            end
            for name, response in pairs(event.rsvps or {}) do
                local status = type(response) == "table" and response.status or response
                if status == "going" or status == "tentative" then
                    local label, token = self:GetRaidPlayerClass(name)
                    token = token or "UNKNOWN"
                    classes[token] = classes[token] or { label = label, going = 0, selected = 0, maybe = 0 }
                    local entry = classes[token]
                    if status == "going" then
                        entry.going = entry.going + 1
                        local selected = event.selections and event.selections[name]
                        if selected and selected.selected then entry.selected = entry.selected + 1 end
                    else entry.maybe = entry.maybe + 1 end
                end
            end
            for token in pairs(classes) do classOrder[#classOrder + 1] = token end
            table.sort(classOrder, function(a, b) return classes[a].label < classes[b].label end)
            row.classTitle:ClearAllPoints()
            row.classTitle:SetPoint("TOPLEFT", 16, -rowHeight)
            local columns = frame.detailChild:GetWidth() >= 680 and 3 or 2
            local classWidth = (frame.detailChild:GetWidth() - 40) / columns
            for index, token in ipairs(classOrder) do
                local entry = classes[token]
                local text = row.classRows[index]
                if not text then
                    text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    text:SetJustifyH("LEFT")
                    row.classRows[index] = text
                end
                text:ClearAllPoints()
                text:SetPoint("TOPLEFT", 16 + ((index - 1) % columns) * classWidth, -rowHeight - 26 - math.floor((index - 1) / columns) * 42)
                text:SetWidth(classWidth - 12)
                text:SetHeight(36)
                text:SetText(entry.label .. "  " .. entry.going .. " / " .. entry.selected .. (entry.maybe > 0 and ("  (" .. entry.maybe .. " maybe)") or ""))
                local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
                text:SetTextColor(color and color.r or CREAM[1], color and color.g or CREAM[2], color and color.b or CREAM[3])
                text:Show()
            end
            for index = #classOrder + 1, #row.classRows do row.classRows[index]:Hide() end
            rowHeight = rowHeight + 36 + math.ceil(#classOrder / columns) * 42
            row:SetHeight(rowHeight)
            eventY = eventY + rowHeight + 20
            row.bg:SetColorTexture(i % 2 == 1 and PANEL_ALT[1] or PANEL[1], i % 2 == 1 and PANEL_ALT[2] or PANEL[2], i % 2 == 1 and PANEL_ALT[3] or PANEL[3], 1)
            for _, button in ipairs(row.rsvpButtons) do
                button.eventId = event.id
                button:SetText(mine and "Edit my signup" or "Sign up")
                button:ClearAllPoints()
                button:SetPoint("TOPRIGHT", mine and -136 or -16, -184)
                if event.preview or (calendarSettings.locked and not mine) then button:Disable() else button:Enable() end
            end
            row:Show()
        end
        for i = #events + 1, #frame.eventRows do frame.eventRows[i]:Hide() end
        if #events == 0 then
            frame.eventEmpty:SetText(self.guildName and "No upcoming raids or events are scheduled." or "Join a guild to view its calendar.")
            frame.eventEmpty:Show()
        else
            frame.eventEmpty:Hide()
        end
        frame.detailChild:SetHeight(math.max(frame.detailScroll:GetHeight(), eventY + 12))
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
                        print("GuildDB: " .. tostring(message))
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
        frame.detailMeta:SetText(self.guildName and "GuildDB workspace" or "GuildDB workspace - Join a guild to sync")
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

function GH:IsSyncResponder(requester)
    if not self.roster or #self.roster == 0 then return false end
    local function syncNameKey(name)
        name = tostring(name or "")
        return (name:match("^([^-]+)") or name):lower():gsub("[%s%-]", "")
    end
    local excluded = syncNameKey(requester)
    local candidates = {}
    for _, member in ipairs(self.roster) do
        -- Sync can only be served by a client that is actually running
        -- GuildDB. Limiting this to officers meant no one answered when the
        -- online leader/rank-1 member did not have the addon installed.
        local candidateName = syncNameKey(member.name)
        if member.online and candidateName ~= excluded and self:GetAddonVersion(member.name) then candidates[#candidates + 1] = member end
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
        if name and syncNameKey(candidates[1].name) == syncNameKey(name) then return true end
    end
    return false
end

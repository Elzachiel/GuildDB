-- Member actions capture the full name when the menu opens, even if rows reorder.
local _, GD = ...

function GD:InviteRosterMember(name)
    if not name then print("GuildDB: Select a roster member first."); return end
    local invite = InviteByName or InviteUnit
    if not invite and type(C_PartyInfo) == "table" then invite = C_PartyInfo.InviteUnit end
    if type(invite) ~= "function" then
        print("GuildDB: This client does not expose a group invite function.")
        return
    end
    local ok, err = pcall(invite, name)
    if not ok then print("GuildDB: Could not invite " .. self:Display(name) .. ": " .. tostring(err)) end
end

function GD:HideRosterActions()
    if self.rosterActionsMenu then self.rosterActionsMenu:Hide() end
end

function GD:ShowRosterActions(row, name)
    if not name or self.activeTab ~= "Roster" then return end
    local menu = self.rosterActionsMenu
    if not menu then
        menu = CreateFrame("Frame", "GuildDBRosterActionsMenu", UIParent, "BackdropTemplate")
        self.rosterActionsMenu = menu
        menu:SetSize(210, 148)
        menu:SetFrameStrata("TOOLTIP")
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        menu:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
        menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        menu.title:SetPoint("TOPLEFT", 10, -10)
        menu.title:SetWidth(190)
        menu.title:SetWordWrap(false)
        menu.title:SetJustifyH("LEFT")
        menu.buttons = {}
        for index, label in ipairs({ "Whisper", "Invite to group", "View profile", "Copy character name" }) do
            local button = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
            button:SetSize(194, 24)
            button:SetPoint("TOPLEFT", 8, -30 - (index - 1) * 28)
            button:SetText(label)
            menu.buttons[index] = button
        end
        menu:SetScript("OnUpdate", function()
            if not menu.owner:IsShown() or menu.owner.rosterName ~= menu.memberName
                or GD.activeTab ~= "Roster" then menu:Hide(); return end
            if IsMouseButtonDown and MouseIsOver
                and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
                and not MouseIsOver(menu) and not MouseIsOver(menu.owner) then menu:Hide() end
        end)
        UISpecialFrames = UISpecialFrames or {}
        table.insert(UISpecialFrames, "GuildDBRosterActionsMenu")
        self.frame:HookScript("OnHide", function() menu:Hide() end)
        self.frame.listScroll:HookScript("OnVerticalScroll", function() menu:Hide() end)
    end
    menu.owner, menu.memberName = row, name
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 12, -2)
    menu.title:SetText(self:Display(name))
    local colors = self:GetAppearanceColors()
    menu.title:SetTextColor(unpack(colors.accent))
    self:StyleSurface(menu)
    for _, button in ipairs(menu.buttons) do self:StyleButton(button) end
    menu.buttons[1]:SetScript("OnClick", function()
        menu:Hide()
        if ChatFrame_SendTell then ChatFrame_SendTell(name)
        else print("GuildDB: This client does not expose a whisper chat function.") end
    end)
    menu.buttons[2]:SetScript("OnClick", function()
        menu:Hide()
        GD:InviteRosterMember(name)
    end)
    menu.buttons[3]:SetScript("OnClick", function()
        menu:Hide()
        GD.profileTarget, GD.selectedRosterName, GD.activeTab = name, name, "Roster"
        GD:RefreshUI()
    end)
    menu.buttons[4]:SetScript("OnClick", function()
        menu:Hide()
        GD:ShowCopyCharacterName(name)
    end)
    menu:Show()
end

function GD:ShowCopyCharacterName(name)
    local dialog = self.copyCharacterDialog
    if not dialog then
        dialog = CreateFrame("Frame", "GuildDBCopyCharacterDialog", UIParent, "BackdropTemplate")
        self.copyCharacterDialog = dialog
        dialog:SetSize(420, 150)
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetClampedToScreen(true)
        dialog:EnableMouse(true)
        dialog:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 16 })
        dialog.label = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dialog.label:SetPoint("TOPLEFT", 20, -20)
        dialog.label:SetText("Copy character name - press Ctrl+C")
        dialog.input = CreateFrame("EditBox", nil, dialog, "BackdropTemplate")
        dialog.input:SetSize(380, 28)
        dialog.input:SetPoint("TOPLEFT", 20, -52)
        dialog.input:SetAutoFocus(false)
        dialog.input:SetMaxLetters(200)
        dialog.input:SetScript("OnEscapePressed", function() dialog:Hide() end)
        dialog.input:SetScript("OnEnterPressed", function() dialog:Hide() end)
        dialog.input:SetScript("OnEditFocusGained", function(input) input:HighlightText() end)
        dialog.input:SetScript("OnMouseUp", function(input) input:SetFocus(); input:HighlightText() end)
        dialog.input:SetScript("OnTextChanged", function(input)
            if input:GetText() ~= dialog.memberName then input:SetText(dialog.memberName or ""); input:HighlightText() end
        end)
        dialog.close = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        dialog.close:SetSize(90, 26)
        dialog.close:SetPoint("BOTTOMRIGHT", -20, 18)
        dialog.close:SetText("Close")
        dialog.close:SetScript("OnClick", function() dialog:Hide() end)
        dialog:SetScript("OnHide", function() dialog.input:ClearFocus() end)
        UISpecialFrames = UISpecialFrames or {}
        table.insert(UISpecialFrames, "GuildDBCopyCharacterDialog")
    end
    self:StyleSurface(dialog, "window")
    self:StyleEditBox(dialog.input)
    self:StyleButton(dialog.close, "primary")
    dialog.memberName = name
    dialog.input:SetText(name)
    dialog:Show()
    dialog.input:SetFocus()
    dialog.input:HighlightText()
end

-- Dark guild workspace with a compact navigation rail and single content pane. - TEST
local _, GD = ...

local GOLD = { 0.20, 0.62, 0.98 }
local ACCENTS = {
    { 0.20, 0.62, 0.98 }, -- blue
    { 0.72, 0.42, 0.95 }, -- violet
    { 0.20, 0.78, 0.58 }, -- teal
    { 0.95, 0.48, 0.32 }, -- coral
    { 0.95, 0.72, 0.25 }, -- amber
    { 0.94, 0.38, 0.52 }, -- rose
}
local CLASS_COLOR_FALLBACKS = {
    WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 },
    HUNTER = { 0.67, 0.83, 0.45 }, ROGUE = { 1.00, 0.96, 0.41 },
    PRIEST = { 1.00, 1.00, 1.00 }, DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    SHAMAN = { 0.00, 0.44, 0.87 }, MAGE = { 0.25, 0.78, 0.92 },
    WARLOCK = { 0.53, 0.53, 0.93 }, MONK = { 0.00, 1.00, 0.60 },
    DRUID = { 1.00, 0.49, 0.04 }, DEMONHUNTER = { 0.64, 0.19, 0.79 },
    EVOKER = { 0.20, 0.57, 0.50 },
}
local function classAccent()
    local class
    if UnitClass then local _, token = UnitClass("player"); class = token end
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then return { color.r, color.g, color.b } end
    return CLASS_COLOR_FALLBACKS[class] or ACCENTS[1]
end
local function updateAccent()
    local index = GD.GetSetting and tonumber(GD:GetSetting("accentColor")) or 1
    local color = index == 1 and classAccent() or ACCENTS[index - 1]
    color = color or ACCENTS[1]
    GOLD[1], GOLD[2], GOLD[3] = color[1], color[2], color[3]
end
GD.GetAccentChoices = function()
    local choices = { classAccent() }
    for _, color in ipairs(ACCENTS) do choices[#choices + 1] = color end
    return choices
end
local function applyAccent(frame)
    if not frame then return end
    local r, g, b = GOLD[1], GOLD[2], GOLD[3]
    if frame.detailPanel and frame.detailPanel.topAccent then
        frame.detailPanel.topAccent:SetColorTexture(r, g, b, 1)
        frame.detailTitle:SetTextColor(r, g, b)
    end
    for _, button in pairs(frame.tabButtons or {}) do
        if button.accent then button.accent:SetColorTexture(r, g, b, 1) end
    end
    for _, row in ipairs(frame.listRows or {}) do
        if row.selectedMarker then row.selectedMarker:SetColorTexture(r, g, b, 1) end
    end
    if frame.pvpTitleSeason then frame.pvpTitleSeason:SetTextColor(r, g, b) end
    for _, key in ipairs({ "pvpMyButton", "pvpSeasonButton", "pvpDeleteButton", "pvpWipeButton", "pvpScopeButton", "contentActionButton", "profileEditButton", "rosterInviteButton", "rosterRankDropdown", "eventCreateButton", "eventCreateTypeButton" }) do
        local button = frame[key]
        local combatRankControl = key == "rosterRankDropdown" and InCombatLockdown and InCombatLockdown()
        if not combatRankControl and button and button.GetObjectType and button:GetObjectType() == "Button" then
            local primary = key == "pvpSeasonButton" or key == "contentActionButton" or key == "profileEditButton"
            GD:StyleButton(button, primary and "primary" or nil)
        end
    end
    for _, row in ipairs(frame.actionRows or {}) do
        for _, button in ipairs(row.buttons or {}) do GD:StyleButton(button, "primary") end
    end
    if GD.RefreshSettingsAppearance then GD:RefreshSettingsAppearance() end
end
local MUTED_GOLD = { 0.48, 0.60, 0.70 }
local CREAM = { 0.84, 0.89, 0.94 }
local PANEL = { 0.045, 0.055, 0.072, 0.99 }
local PANEL_ALT = { 0.075, 0.09, 0.115, 0.99 }
local FRAME_BG = { 0.025, 0.032, 0.043, 0.99 }
local HEADER_BG = { 0.035, 0.052, 0.068, 1 }
local SIDEBAR_BG = { 0.035, 0.045, 0.06, 1 }
local THEMES = {
    { name = "Midnight", frame = { 0.025, 0.032, 0.043, 0.99 }, header = { 0.035, 0.052, 0.068, 1 }, sidebar = { 0.035, 0.045, 0.06, 1 }, panel = { 0.045, 0.055, 0.072, 0.99 }, alternate = { 0.075, 0.09, 0.115, 0.99 } },
    { name = "Slate", frame = { 0.022, 0.03, 0.043, 0.99 }, header = { 0.035, 0.05, 0.07, 1 }, sidebar = { 0.03, 0.042, 0.06, 1 }, panel = { 0.045, 0.062, 0.085, 0.99 }, alternate = { 0.07, 0.09, 0.12, 0.99 } },
    { name = "Forest", frame = { 0.018, 0.032, 0.026, 0.99 }, header = { 0.026, 0.052, 0.04, 1 }, sidebar = { 0.023, 0.043, 0.034, 1 }, panel = { 0.036, 0.062, 0.048, 0.99 }, alternate = { 0.06, 0.09, 0.068, 0.99 } },
    { name = "Ember", frame = { 0.036, 0.022, 0.026, 0.99 }, header = { 0.06, 0.032, 0.04, 1 }, sidebar = { 0.046, 0.027, 0.034, 1 }, panel = { 0.065, 0.038, 0.045, 0.99 }, alternate = { 0.095, 0.055, 0.06, 0.99 } },
}
local function copyColor(target, source)
    for index = 1, #source do target[index] = source[index] end
end
local function updateTheme()
    local index = GD.GetSetting and tonumber(GD:GetSetting("uiTheme")) or 1
    local theme = THEMES[index] or THEMES[1]
    copyColor(FRAME_BG, theme.frame)
    copyColor(HEADER_BG, theme.header)
    copyColor(SIDEBAR_BG, theme.sidebar)
    copyColor(PANEL, theme.panel)
    copyColor(PANEL_ALT, theme.alternate)
end
GD.GetThemeChoices = function() return THEMES end
updateTheme()
-- Feature panels use this palette instead of keeping their own fixed colors.
function GD:GetAppearanceColors()
    updateTheme()
    updateAccent()
    return { panel = PANEL, alternate = PANEL_ALT, window = FRAME_BG,
        accent = GOLD, text = CREAM, muted = MUTED_GOLD }
end
local themedSurfaces = setmetatable({}, { __mode = "k" })
local themedScrollFrames = setmetatable({}, { __mode = "k" })
local themedCloseButtons = setmetatable({}, { __mode = "k" })
function GD:StyleSurface(surface, kind)
    themedSurfaces[surface] = kind or "panel"
    local colors = self:GetAppearanceColors()
    local background = kind == "window" and colors.window or colors.alternate
    surface:SetBackdropColor(background[1], background[2], background[3], background[4] or 1)
    surface:SetBackdropBorderColor(colors.accent[1], colors.accent[2], colors.accent[3], 0.9)
end

-- One compact scrollbar for every workspace, including native-template scroll frames.
function GD:StyleScrollFrame(scroll)
    if not scroll then return end
    themedScrollFrames[scroll] = true
    local bar = scroll.GuildDBScrollBar
    if not bar then
        bar = CreateFrame("Slider", nil, scroll)
        scroll.GuildDBScrollBar = bar
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, -2)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 2)
        bar:SetWidth(8)
        bar:EnableMouse(true)
        bar:SetOrientation("VERTICAL")
        bar:SetValueStep(1)
        bar:SetThumbTexture("Interface/Buttons/WHITE8X8")
        bar.track = bar:CreateTexture(nil, "BACKGROUND")
        bar.track:SetAllPoints()
        local function sync()
            if bar.syncing then return end
            bar.syncing = true
            local child = scroll:GetScrollChild()
            local viewport = math.max(1, scroll:GetHeight())
            local height = child and child:GetHeight() or viewport
            local maximum = math.max(0, height - viewport)
            local position = math.max(0, math.min(maximum, scroll:GetVerticalScroll()))
            bar:SetMinMaxValues(0, math.max(1, maximum))
            bar:SetValue(position)
            local trackHeight = math.max(1, bar:GetHeight())
            bar:GetThumbTexture():SetSize(8, math.min(trackHeight, math.max(24, trackHeight * viewport / math.max(viewport, height))))
            bar:SetShown(maximum > 0)
            if scroll.ScrollBar then scroll.ScrollBar:Hide() end
            if position ~= scroll:GetVerticalScroll() then scroll:SetVerticalScroll(position) end
            bar.syncing = false
        end
        bar:SetScript("OnValueChanged", function(_, value)
            if not bar.syncing then scroll:SetVerticalScroll(value) end
        end)
        local function wheel(_, delta)
            local child = scroll:GetScrollChild()
            local maximum = math.max(0, (child and child:GetHeight() or 0) - scroll:GetHeight())
            scroll:SetVerticalScroll(math.max(0, math.min(maximum, scroll:GetVerticalScroll() - delta * 40)))
        end
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", wheel)
        bar:EnableMouseWheel(true)
        bar:SetScript("OnMouseWheel", wheel)
        for _, event in ipairs({ "OnScrollRangeChanged", "OnVerticalScroll", "OnSizeChanged", "OnShow" }) do scroll:HookScript(event, sync) end
        if scroll.ScrollBar then
            scroll.ScrollBar:Hide()
            scroll.ScrollBar:HookScript("OnShow", function(native) native:Hide() end)
        end
        bar.sync = sync
    end
    local colors = self:GetAppearanceColors()
    bar.track:SetColorTexture(colors.muted[1], colors.muted[2], colors.muted[3], 0.16)
    bar:GetThumbTexture():SetVertexColor(colors.accent[1], colors.accent[2], colors.accent[3], 0.85)
    bar.sync()
end

local function applyTheme(frame)
    if not frame then return end
    if frame.background then frame.background:SetColorTexture(FRAME_BG[1], FRAME_BG[2], FRAME_BG[3], FRAME_BG[4]) end
    if frame.headerBg then frame.headerBg:SetColorTexture(HEADER_BG[1], HEADER_BG[2], HEADER_BG[3], HEADER_BG[4]) end
    if frame.sidebar and frame.sidebar.bg then frame.sidebar.bg:SetColorTexture(SIDEBAR_BG[1], SIDEBAR_BG[2], SIDEBAR_BG[3], SIDEBAR_BG[4]) end
    if frame.listPanel and frame.listPanel.bg then frame.listPanel.bg:SetColorTexture(PANEL[1], PANEL[2], PANEL[3], PANEL[4]) end
    if frame.detailPanel and frame.detailPanel.bg then frame.detailPanel.bg:SetColorTexture(PANEL[1], PANEL[2], PANEL[3], PANEL[4]) end
    if frame.rosterSearch then frame.rosterSearch:SetBackdropColor(PANEL_ALT[1], PANEL_ALT[2], PANEL_ALT[3], 1) end
    for surface, kind in pairs(themedSurfaces) do GD:StyleSurface(surface, kind) end
    for scroll in pairs(themedScrollFrames) do GD:StyleScrollFrame(scroll) end
    for button in pairs(themedCloseButtons) do GD:StyleCloseButton(button) end
    if frame.recruitment and GD.RefreshRecruitmentAppearance then GD:RefreshRecruitmentAppearance() end
    if GD.RefreshRecruitPopoutAppearance then GD:RefreshRecruitPopoutAppearance() end
    if frame.home and GD.RefreshHomeAppearance then GD:RefreshHomeAppearance() end
    if frame.guildInfo and GD.RefreshGuildInfoAppearance then GD:RefreshGuildInfoAppearance() end
    if frame.close then GD:StyleCloseButton(frame.close) end
    if frame.rosterOnlineCheck then GD:StyleButton(frame.rosterOnlineCheck) end
end

local pvpColumnWidths = { 0.06, 0.25, 0.10, 0.10, 0.10, 0.39 }
local pvpScoreColumnWidths = { 0.045, 0.205, 0.11, 0.09, 0.08, 0.08, 0.08, 0.31 }
local function layoutPvPColumn(text, index, parent, width, inset, header, rivals)
    local widths = rivals and pvpColumnWidths or pvpScoreColumnWidths
    local offset = 0
    for column = 1, index - 1 do offset = offset + widths[column] * width end
    text:ClearAllPoints()
    if header then text:SetPoint("TOPLEFT", parent, "TOPLEFT", inset + offset, -187)
    else text:SetPoint("LEFT", parent, "LEFT", offset, 0) end
    text:SetWidth(math.max(1, widths[index] * width - 8))
    text:SetJustifyH("CENTER")
end

local function layoutPvPRow(row, width, rivals)
    row.killCount:SetShown(not rivals)
    row.pvpRank:SetShown(not rivals)
    local columns = rivals and { row.rank, row.player, row.points, row.kills, row.kd, row.last }
        or { row.rank, row.player, row.pvpRank, row.points, row.killCount, row.kills, row.kd, row.last }
    for index, text in ipairs(columns) do layoutPvPColumn(text, index, row, width, 0, false, rivals) end
end

local function rosterText()
    if not GD.guildName then return "Join a guild to view its roster and GuildDB." end
    if not GD.roster or #GD.roster == 0 then return "Loading the guild roster..." end
    local lines = {}
    for _, member in ipairs(GD.roster) do
        lines[#lines + 1] = member.name .. "  ·  " .. member.rank
    end
    return #lines > 0 and table.concat(lines, "\n") or "No guild members found."
end
GD:RegisterTab("Roster", rosterText)

local function rosterRank(name)
    if not name or not GetNumGuildMembers or not GetGuildRosterInfo then return end
    for index = 1, GetNumGuildMembers() do
        local memberName, _, rank = GetGuildRosterInfo(index)
        if memberName == name then return rank end
    end
end

function GD:GetRosterRankChoices(name)
    local choices = {}
    if not self.guildName or not GetGuildInfo or not GuildControlGetNumRanks then return choices end
    local _, _, ownRank = GetGuildInfo("player")
    local current = rosterRank(name)
    if type(ownRank) ~= "number" or type(current) ~= "number" or current <= ownRank then return choices end
    local canPromote = ownRank == 0 or (CanGuildPromote and CanGuildPromote())
    local canDemote = ownRank == 0 or (CanGuildDemote and CanGuildDemote())
    for rank = ownRank + 1, GuildControlGetNumRanks() - 1 do
        if (rank < current and canPromote) or (rank > current and canDemote) then
            choices[#choices + 1] = { rank = rank, label = GuildControlGetRankName and GuildControlGetRankName(rank + 1) or ("Rank " .. rank) }
        end
    end
    return choices
end

function GD:RosterRankMacro(name, rank)
    if self.pendingRosterRank or (InCombatLockdown and InCombatLockdown()) then return end
    if type(name) ~= "string" or name:find("%c") or name:find("/", 1, true) or name:find("|", 1, true) then return end
    for _, choice in ipairs(self:GetRosterRankChoices(name)) do
        if choice.rank == rank then
            local current = rosterRank(name)
            local command
            if rank < current then command = (SLASH_GUILD_PROMOTE1 or "/gpromote") .. " "
            else command = (SLASH_GUILD_DEMOTE1 or "/gdemote") .. " " end
            local macro = "/stopmacro [combat]\n" .. command .. name .. "\n"
            if #macro <= 1023 then return macro end
        end
    end
end

local function requestRankRoster()
    local request = C_GuildInfo and C_GuildInfo.GuildRoster or GuildRoster
    if request then pcall(request) end
end

function GD:TrackRosterRankChange(name, rank, before)
    if type(before) ~= "number" then return end
    local update = { name = name, rank = rank, before = before,
        expected = before + (rank < before and -1 or 1), guild = self.guildName }
    self.rosterRankTarget = { name = name, rank = rank, guild = self.guildName }
    self.pendingRosterRank = update
    requestRankRoster()
    if C_Timer and C_Timer.After then
        -- Refresh native data after the command has reached the server, rather
        -- than relying on the pre-command roster cache or one unsolicited event.
        for _, delay in ipairs({ 0.75, 2, 4, 7 }) do
            C_Timer.After(delay, function()
                if GD.pendingRosterRank ~= update then return end
                requestRankRoster()
                if GD.RebuildRoster then GD:RebuildRoster() end
            end)
        end
        C_Timer.After(10, function()
            if GD.pendingRosterRank ~= update then return end
            if GD.RebuildRoster then GD:RebuildRoster() end
            if GD.pendingRosterRank ~= update then return end
            GD.pendingRosterRank, GD.rosterRankTarget = nil, nil
            print("GuildDB: The game did not confirm the rank change for " .. GD:Display(name) .. ".")
            GD:RefreshUI()
        end)
    end
    self:RefreshUI()
end

function GD:ConfirmRosterRankChange()
    local update = self.pendingRosterRank
    if not update then return end
    if self.guildName ~= update.guild then self.pendingRosterRank, self.rosterRankTarget = nil, nil; return end
    local current = rosterRank(update.name)
    if current == update.before then return end
    self.pendingRosterRank = nil
    if current == update.rank then
        self.rosterRankTarget = nil
        print("GuildDB: Guild rank updated for " .. self:Display(update.name) .. ".")
    elseif current ~= update.expected then
        self.rosterRankTarget = nil
        print("GuildDB: The member's rank changed unexpectedly. Select the desired rank again.")
    elseif self.rosterRankTarget then
        local label = GuildControlGetRankName and GuildControlGetRankName(update.rank + 1) or "selected rank"
        print("GuildDB: Rank updated one step. Click Continue to " .. self:Display(label) .. " to finish.")
    end
end
local function rosterRankMenuContext(name, choices)
    local context = { GD.guildName or "", name or "", tostring(rosterRank(name)) }
    for _, choice in ipairs(choices) do context[#context + 1] = tostring(choice.rank) .. ":" .. choice.label end
    return table.concat(context, "\n")
end

function GD:RefreshRosterRankControls(name)
    if InCombatLockdown and InCombatLockdown() then
        if self.activeTab == "Roster" then
            self.frame.detailScroll:SetPoint("BOTTOMRIGHT", -28, name and 90 or 54)
        end
        return
    end
    local frame = self.frame
    local dropdown = frame.rosterRankDropdown
    local choices = self.activeTab == "Roster" and self:GetRosterRankChoices(name) or {}
    local pending = self.pendingRosterRank
    local target = self.rosterRankTarget
    if target and (target.name ~= name or target.guild ~= self.guildName or self.activeTab ~= "Roster") then
        self.rosterRankTarget, target = nil, nil
    end
    local continuation = target and not pending and self:RosterRankMacro(name, target.rank)
    if target and not pending and not continuation then self.rosterRankTarget, target = nil, nil end
    local visible = self.activeTab == "Roster" and (#choices > 0 or (pending and pending.name == name))
    if not visible or pending or dropdown.popup.rankContext ~= rosterRankMenuContext(name, choices) then dropdown.popup:Hide() end
    local targetLabel = target and GuildControlGetRankName and GuildControlGetRankName(target.rank + 1)
    dropdown:SetText(pending and "Updating rank..." or (continuation and ("Continue to " .. self:Display(targetLabel or "selected rank"))) or "Set Guild Rank  v")
    dropdown:SetAttribute("type", continuation and "macro" or nil)
    dropdown:SetAttribute("macrotext", continuation)
    dropdown.rankName, dropdown.rankValue, dropdown.rankMacro, dropdown.rankFrom = name, target and target.rank, continuation, rosterRank(name)
    dropdown:SetShown(not not visible)
    dropdown:SetEnabled(not pending)
    if self.activeTab == "Roster" then
        frame.detailScroll:SetPoint("BOTTOMRIGHT", -28, visible and 126 or (name and 90 or 54))
    end
    self:PositionRankLayer()
end

function GD:PositionRankLayer()
    if InCombatLockdown and InCombatLockdown() then return end
    local frame = self.frame
    local layer = frame and frame.rankLayer
    if not layer then return end
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not left or not bottom then return end
    -- Copy geometry instead of anchoring secure controls to the main window:
    -- protected anchor targets inherit combat restrictions just like parents.
    layer:SetScale(frame:GetEffectiveScale() / UIParent:GetEffectiveScale())
    layer:ClearAllPoints()
    layer:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    layer:SetSize(frame:GetWidth(), frame:GetHeight())
    local invite = frame.rosterInviteButton
    local inviteLeft, inviteTop = invite:GetLeft(), invite:GetTop()
    if inviteLeft and inviteTop then
        frame.rosterRankDropdown:ClearAllPoints()
        frame.rosterRankDropdown:SetPoint("BOTTOMLEFT", layer, "BOTTOMLEFT", inviteLeft - left, inviteTop - bottom + 8)
    end
end
local function setTextColor(font, color)
    font:SetTextColor(color[1], color[2], color[3])
end

function GD:StyleButton(button, variant)
    if not button then return end
    local primary = variant == "primary"
    local normalColor = primary and { GOLD[1] * 0.42, GOLD[2] * 0.42, GOLD[3] * 0.42 } or { PANEL_ALT[1], PANEL_ALT[2], PANEL_ALT[3] }
    local pressedColor = primary and { GOLD[1] * 0.30, GOLD[2] * 0.30, GOLD[3] * 0.30 } or { PANEL[1], PANEL[2], PANEL[3] }
    local borderColor = primary and GOLD or { 0.16, 0.25, 0.34 }

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
    if highlight then highlight:SetAllPoints(button); highlight:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.20) end
    if disabled then disabled:SetAllPoints(button); disabled:SetVertexColor(0.08, 0.09, 0.11, 0.65) end

    if not button.GuildDBBorder then
        local edges = {}
        for index = 1, 4 do
            edges[index] = button:CreateTexture(nil, "OVERLAY")
            edges[index]:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], 1)
        end
        edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
        edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
        edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
        edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
        button.GuildDBBorder = edges
    else
        for _, edge in ipairs(button.GuildDBBorder) do edge:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], 1) end
    end
    -- Let the button switch fonts with its native hover state. Changing only
    -- the FontString leaves the template's larger normal font active on leave
    -- until the next appearance refresh.
    button:SetNormalFontObject("GameFontNormalSmall")
    button:SetHighlightFontObject("GameFontHighlight")
    button:SetDisabledFontObject("GameFontDisableSmall")
    local text = button:GetFontString()
    if text then
        text:SetTextColor(primary and 0.92 or CREAM[1], primary and 0.97 or CREAM[2], primary and 1 or CREAM[3])
    end
end

function GD:StyleCloseButton(button)
    if not button then return end
    themedCloseButtons[button] = true
    button:SetSize(30, 30)
    if not button:GetFontString() then
        button:SetFontString(button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"))
    end
    button:SetText("X")
    self:StyleButton(button)
    button:SetNormalFontObject("GameFontNormalLarge")
    button:SetHighlightFontObject("GameFontNormalLarge")
    local text = button:GetFontString()
    text:SetFontObject("GameFontNormalLarge")
    text:ClearAllPoints()
    text:SetPoint("CENTER", button, "CENTER", 0, 0)
end

local function styleRaidButton(button, width, variant)
    if not button:GetFontString() then
        button:SetFontString(button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    end
    GD:StyleButton(button, variant)
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
    GD:StyleButton(button)
    button:SetSize(22, 22)
    button.mark = button:CreateTexture(nil, "OVERLAY")
    button.mark:SetTexture("Interface/Buttons/UI-CheckBox-Check")
    button.mark:SetSize(17, 17)
    button.mark:SetPoint("CENTER")
    button.mark:SetVertexColor(0.25, 0.68, 1, 1)
end

-- Match the compact checkbox used by Settings and the roster's Online filter.
function GD:StyleCheckbox(button)
    button:SetSize(22, 22)
    button:SetNormalTexture("Interface/Buttons/WHITE8X8")
    button:SetPushedTexture("Interface/Buttons/WHITE8X8")
    button:SetHighlightTexture("Interface/Buttons/WHITE8X8")
    button:SetDisabledTexture("Interface/Buttons/WHITE8X8")
    button:GetNormalTexture():SetAllPoints(button)
    button:GetNormalTexture():SetVertexColor(0.075, 0.09, 0.12, 1)
    button:GetPushedTexture():SetAllPoints(button)
    button:GetPushedTexture():SetVertexColor(0.045, 0.06, 0.085, 1)
    button:GetHighlightTexture():SetAllPoints(button)
    button:GetHighlightTexture():SetVertexColor(0.22, 0.52, 0.78, 0.20)
    button:GetDisabledTexture():SetAllPoints(button)
    button:GetDisabledTexture():SetVertexColor(0.08, 0.09, 0.11, 0.65)
    button.border = button.border or {}
    for index = 1, 4 do
        button.border[index] = button.border[index] or button:CreateTexture(nil, "OVERLAY")
        button.border[index]:SetColorTexture(0.16, 0.25, 0.34, 1)
    end
    button.border[1]:SetPoint("TOPLEFT"); button.border[1]:SetPoint("TOPRIGHT"); button.border[1]:SetHeight(1)
    button.border[2]:SetPoint("BOTTOMLEFT"); button.border[2]:SetPoint("BOTTOMRIGHT"); button.border[2]:SetHeight(1)
    button.border[3]:SetPoint("TOPLEFT"); button.border[3]:SetPoint("BOTTOMLEFT"); button.border[3]:SetWidth(1)
    button.border[4]:SetPoint("TOPRIGHT"); button.border[4]:SetPoint("BOTTOMRIGHT"); button.border[4]:SetWidth(1)
    button.mark = button.mark or button:CreateTexture(nil, "OVERLAY")
    button.mark:SetTexture("Interface/Buttons/UI-CheckBox-Check")
    button.mark:SetSize(17, 17)
    button.mark:SetPoint("CENTER")
    button.mark:SetVertexColor(0.25, 0.68, 1, 1)
    button:SetCheckedTexture(button.mark)
end

function GD:StyleEditBox(editBox, multiline)
    if not editBox then return end
    editBox:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
    editBox:SetBackdropColor(PANEL_ALT[1], PANEL_ALT[2], PANEL_ALT[3], 1)
    editBox:SetFontObject(multiline and "GameFontHighlight" or "GameFontHighlightSmall")
    editBox:SetTextInsets(8, 8, multiline and 6 or 0, multiline and 6 or 0)
    editBox:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
    editBox.GuildDBBorder = editBox.GuildDBBorder or {}
    for index = 1, 4 do
        local edge = editBox.GuildDBBorder[index]
        if not edge then
            edge = editBox:CreateTexture(nil, "OVERLAY")
            editBox.GuildDBBorder[index] = edge
        end
        edge:SetColorTexture(0.16, 0.25, 0.34, 1)
    end
    local border = editBox.GuildDBBorder
    border[1]:SetPoint("TOPLEFT"); border[1]:SetPoint("TOPRIGHT"); border[1]:SetHeight(1)
    border[2]:SetPoint("BOTTOMLEFT"); border[2]:SetPoint("BOTTOMRIGHT"); border[2]:SetHeight(1)
    border[3]:SetPoint("TOPLEFT"); border[3]:SetPoint("BOTTOMLEFT"); border[3]:SetWidth(1)
    border[4]:SetPoint("TOPRIGHT"); border[4]:SetPoint("BOTTOMRIGHT"); border[4]:SetWidth(1)
    function editBox:SetGuildDBFocusState(focused)
        local color = focused and GOLD or { 0.16, 0.25, 0.34 }
        for _, edge in ipairs(self.GuildDBBorder) do edge:SetColorTexture(color[1], color[2], color[3], 1) end
    end
    editBox:HookScript("OnEditFocusGained", function(self) self:SetGuildDBFocusState(true) end)
    editBox:HookScript("OnEditFocusLost", function(self) self:SetGuildDBFocusState(false) end)
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
    GD:StyleSurface(popup)
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
local function showInputForm(title, fields, onAccept, acceptLabel, hideClose, secureAction)
    dialogCounter = dialogCounter + 1
    local name = "GuildDBActionDialog" .. dialogCounter
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
    GD:StyleSurface(dialog, "window")
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
        if field.checkbox then
            input = CreateFrame("CheckButton", nil, dialog)
            GD:StyleCheckbox(input)
            input:SetPoint("TOPLEFT", 18, -offset - 12)
            input:SetChecked(field.value == true)
            label:ClearAllPoints()
            label:SetPoint("LEFT", input, "RIGHT", 4, 0)
            label:SetFontObject("GameFontNormal")
        elseif field.weekdays then
            input = CreateFrame("Frame", nil, dialog)
            input.selectedValue = {}
            input:SetSize(370, 24)
            input:SetPoint("TOPLEFT", 20, -offset - 16)
            local selected = {}
            for _, day in ipairs(field.value or {}) do selected[day] = true end
            local function updateDays()
                input.selectedValue = {}
                for day = 1, 7 do if selected[day] then table.insert(input.selectedValue, day) end end
            end
            for day, label in ipairs({"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}) do
                local weekday = day
                local button = CreateFrame("Button", nil, input, "UIPanelButtonTemplate")
                button:SetSize(48, 24)
                button:SetPoint("TOPLEFT", (day - 1) * 53, 0)
                button:SetText(label)
                GD:StyleButton(button, selected[day] and "primary" or nil)
                button:SetScript("OnClick", function()
                    selected[weekday] = not selected[weekday]
                    GD:StyleButton(button, selected[weekday] and "primary" or nil)
                    updateDays()
                end)
            end
            updateDays()
        elseif field.calendar then
            input = createRaidDatePicker(dialog, field, offset)
        elseif field.options then
            input = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
            GD:StyleButton(input)
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
            GD:StyleSurface(popup)
            popup:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
            popup:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -2)
            popup:Hide()
            input.popup = popup
            dialog.dropdowns[#dialog.dropdowns + 1] = input
            local dropdownInput, dropdownPopup = input, popup
            local listScroll = CreateFrame("ScrollFrame", nil, popup)
            listScroll:SetPoint("TOPLEFT", 4, -4)
            listScroll:SetPoint("BOTTOMRIGHT", -18, 4)
            local listContent = CreateFrame("Frame", nil, listScroll)
            listContent:SetSize(342, #field.options * 24)
            listScroll:SetScrollChild(listContent)
            GD:StyleScrollFrame(listScroll)
            local maxScroll = math.max(0, (#field.options - 8) * 24)
            for optionIndex, option in ipairs(field.options) do
                local chosenOption = option
                local optionButton = CreateFrame("Button", nil, listContent)
                styleRaidButton(optionButton, 342)
                optionButton:SetSize(342, 22)
                optionButton:EnableMouseWheel(true)
                optionButton:SetScript("OnMouseWheel", function(_, delta) listScroll:GetScript("OnMouseWheel")(listScroll, delta) end)
                optionButton:SetPoint("TOPLEFT", 1, -(optionIndex - 1) * 24)
                optionButton:SetText(chosenOption)
                optionButton:SetScript("OnClick", function()
                    dropdownInput.selectedValue = chosenOption
                    dropdownInput:SetText(chosenOption)
                    dropdownPopup:Hide()
                    if field.onChange then field.onChange(chosenOption) end
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
            GD:StyleEditBox(input, field.multiline)
        end
        if not field.options and not field.calendar and not field.weekdays and not field.checkbox then
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
        local close = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        GD:StyleCloseButton(close)
        close:SetPoint("TOPRIGHT", -12, -10)
        close:SetScript("OnClick", function() dialog:Hide() end)
    end
    local cancel = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    GD:StyleButton(cancel)
    cancel:SetSize(92, 26)
    cancel:SetPoint("BOTTOMRIGHT", -120, 14)
    cancel:SetText("Cancel")
    cancel:SetScript("OnClick", function() dialog:Hide() end)
    local accept = CreateFrame("Button", nil, dialog, secureAction and "UIPanelButtonTemplate,SecureActionButtonTemplate" or "UIPanelButtonTemplate")
    GD:StyleButton(accept, "primary")
    accept:SetSize(92, 26)
    accept:SetPoint("LEFT", cancel, "RIGHT", 8, 0)
    accept:SetText(acceptLabel or "Save")
    local function valuesFromForm()
        local values = {}
        for i, input in ipairs(dialog.inputs) do
            if fields[i].checkbox then values[i] = input:GetChecked() == true
            else values[i] = input.selectedValue or input:GetText() end
        end
        return values
    end
    if secureAction then
        -- Keep the template's secure OnClick handler. Arm the command as the
        -- user types, before the hardware click, rather than calling it in Lua.
        accept:RegisterForClicks("LeftButtonUp")
        accept:SetAttribute("useOnKeyDown", false)
        local function arm()
            if InCombatLockdown and InCombatLockdown() then return end
            local command = secureAction(valuesFromForm())
            accept:SetAttribute("type", command and "macro" or nil)
            accept:SetAttribute("macrotext", command)
        end
        for _, input in ipairs(dialog.inputs) do input:HookScript("OnTextChanged", arm) end
        arm()
        local accepted
        accept:HookScript("PreClick", function()
            accepted = false
            if InCombatLockdown and InCombatLockdown() then
                print("GuildDB: Wait until combat ends to save the guild MOTD.")
                return
            end
            local ok, result = onAccept(valuesFromForm())
            accepted = ok
            if not ok then accept:SetAttribute("type", nil) end
            if result then print("GuildDB: " .. result) end
        end)
        accept:HookScript("PostClick", function()
            if accepted then dialog:Hide() else arm() end
        end)
    else
        accept:SetScript("OnClick", function()
            local ok, result = onAccept(valuesFromForm())
            if ok then dialog:Hide() end
            if result then print("GuildDB: " .. result) end
        end)
    end
    UISpecialFrames = UISpecialFrames or {}
    table.insert(UISpecialFrames, 1, name)
    dialog:SetScript("OnHide", function()
        for _, dropdown in ipairs(dialog.dropdowns) do dropdown.popup:Hide() end
        for i = #UISpecialFrames, 1, -1 do if UISpecialFrames[i] == name then table.remove(UISpecialFrames, i) end end
    end)
    dialog:Show()
    for index, input in ipairs(dialog.inputs) do
        if not fields[index].readOnly and not fields[index].options and not fields[index].calendar and not fields[index].weekdays and not fields[index].checkbox then
            input:SetFocus()
            break
        end
    end
end

GD.ShowInputForm = showInputForm

function GD:ConfirmAction(title, message, onAccept, acceptLabel, requiredText)
    local fields = {
        { label = "Please confirm", value = message, multiline = true, readOnly = true },
    }
    if requiredText then
        fields[#fields + 1] = { label = "Type " .. requiredText .. " to confirm", value = "", max = 20 }
    end
    return self.ShowInputForm(title, fields, function(values)
        if requiredText and tostring(values[2] or ""):match("^%s*(.-)%s*$") ~= requiredText then
            return false, "Type " .. requiredText .. " to confirm."
        end
        return onAccept()
    end, acceptLabel or "Confirm")
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
    local player = GD:PlayerName()
    GD:RefreshPlayerProfessions()
    GD:RefreshPlayerSpec()
    local profile = GD:GetProfile(player) or {}
    local specOptions, detectedSpec = GD:GetPlayerSpecOptions()
    local specValue = detectedSpec or specOptions[1]
    for _, option in ipairs(specOptions) do if option == profile.spec then specValue = option; break end end
    local firstName, lastName = GD:GetPlayerNameParts()
    local playerRace = UnitRace and UnitRace("player") or ""
    local timezoneAliases = { ET = "Eastern Time (ET)", CT = "Central Time (CT)", MT = "Mountain Time (MT)", PT = "Pacific Time (PT)", UTC = "UTC" }
    local roleValue = profile.role and profile.role ~= "" and profile.role or "Flex"
    local timezoneValue = timezoneAliases[profile.timezone or ""] or (profile.timezone and profile.timezone ~= "" and profile.timezone) or "Eastern Time (ET)"
    local function saveChoice(key, value)
        local current = GD:GetProfile(player) or {}
        local role = key == "role" and value or current.role
        local timezone = key == "timezone" and value or current.timezone
        local spec = key == "spec" and value or current.spec
        if key == "spec" then GD:SetPlayerSpecChoice(value) end
        GD:SetProfile(nil, nil, role, spec, timezone, current.alts, current.professions, current.race)
    end
    showInputForm("Edit your member profile", {
        { label = "First name", value = firstName, max = 60, readOnly = true },
        { label = "Last name", value = lastName, max = 60, readOnly = true },
        { label = "Main role", value = roleValue, onChange = function(value) saveChoice("role", value) end, options = { "Tank", "DPS", "Healer", "Flex" } },
        { label = "Spec (detected from your talents; choose to override)", value = specValue, options = specOptions, onChange = function(value) saveChoice("spec", value) end },
        { label = "Time zone", value = timezoneValue, onChange = function(value) saveChoice("timezone", value) end, options = { "Eastern Time (ET)", "Central Time (CT)", "Mountain Time (MT)", "Pacific Time (PT)", "Alaska Time (AKT)", "Hawaii Time (HT)", "UTC", "UK Time (GMT/BST)", "Central European Time (CET/CEST)", "Eastern European Time (EET/EEST)", "India Standard Time (IST)", "Japan Standard Time (JST)", "Australian Eastern Time (AET)", "New Zealand Time (NZT)" } },
        { label = "Alts", value = profile.alts or "", max = 200 },
        { label = "Race", value = playerRace or profile.race or "", max = 60, readOnly = true },
        { label = "Professions", value = GD:FormatProfileProfessions(profile.professions), max = 250, readOnly = true },
    }, function(values)
        return GD:SetProfile(values[1], values[2], values[3], values[4], values[5], values[6], profile.professions, values[7])
    end)
end

local function enableWheel(scroll, child)
    GD:StyleScrollFrame(scroll)
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
    if GD.frame then return end
    updateTheme()
    local frame = CreateFrame("Frame", "GuildDBMainFrame", UIParent)
    UISpecialFrames = UISpecialFrames or {}
    local escapeRegistered = false
    for _, frameName in ipairs(UISpecialFrames) do
        if frameName == "GuildDBMainFrame" then escapeRegistered = true; break end
    end
    if not escapeRegistered then table.insert(UISpecialFrames, "GuildDBMainFrame") end
    frame:SetSize(1080, 680)
    frame:SetScale(GD.GetSetting and GD:GetSetting("scale") or 1)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    frame.background = frame:CreateTexture(nil, "BACKGROUND")
    frame.background:SetAllPoints()
    frame.background:SetColorTexture(FRAME_BG[1], FRAME_BG[2], FRAME_BG[3], FRAME_BG[4])
    GD.frame = frame

    frame.header = CreateFrame("Frame", nil, frame)
    frame.header:SetPoint("TOPLEFT", 1, -1)
    frame.header:SetPoint("TOPRIGHT", -1, -1)
    frame.header:SetHeight(70)
    frame.header:EnableMouse(true)
    frame.header:RegisterForDrag("LeftButton")
    frame.header:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame.header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        GD:PositionRankLayer()
    end)
    frame.headerBg = frame.header:CreateTexture(nil, "BACKGROUND")
    frame.headerBg:SetAllPoints()
    frame.headerBg:SetColorTexture(HEADER_BG[1], HEADER_BG[2], HEADER_BG[3], HEADER_BG[4])
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
    frame.version:SetText("GuildDB - v" .. tostring(GD.version))
    frame.headerStatus = frame.header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.headerStatus:SetJustifyH("RIGHT")
    frame.close = CreateFrame("Button", nil, frame.header)
    frame.close:SetPoint("RIGHT", -12, 0)
    GD:StyleCloseButton(frame.close)
    frame.close:SetScript("OnClick", function() frame:Hide() end)
    frame.discordButton = CreateFrame("Button", nil, frame.header, "UIPanelButtonTemplate")
    frame.discordButton:SetSize(164, 30)
    frame.discordButton:SetPoint("RIGHT", frame.close, "LEFT", -12, 0)
    frame.discordButton:SetText("Discord Not Set")
    frame.discordButton:SetScript("OnClick", function() GD:ShowGuildDiscordInvite() end)
    frame:HookScript("OnHide", function()
        if GD.discordInviteDialog then GD.discordInviteDialog:Hide() end
    end)
    frame.headerStatus:SetPoint("RIGHT", frame.discordButton, "LEFT", -12, 0)
    frame.sidebar = CreateFrame("Frame", nil, frame)
    frame.sidebar:SetPoint("TOPLEFT", 1, -71)
    frame.sidebar:SetPoint("BOTTOMLEFT", 1, 1)
    frame.sidebar:SetWidth(198)
    frame.sidebar.bg = frame.sidebar:CreateTexture(nil, "BACKGROUND")
    frame.sidebar.bg:SetAllPoints()
    frame.sidebar.bg:SetColorTexture(SIDEBAR_BG[1], SIDEBAR_BG[2], SIDEBAR_BG[3], SIDEBAR_BG[4])
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
    GD:StyleEditBox(frame.rosterSearch)
    frame.rosterSearch:SetText("Search...")
    frame.rosterSearch:SetTextColor(MUTED_GOLD[1], MUTED_GOLD[2], MUTED_GOLD[3])
    frame.rosterSearch:SetScript("OnEditFocusGained", function(self)
        if self:GetText() == "Search..." then self:SetText(""); self:SetTextColor(CREAM[1], CREAM[2], CREAM[3]) end
        self:SetGuildDBFocusState(true)
    end)
    frame.rosterSearch:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then self:SetText("Search..."); self:SetTextColor(MUTED_GOLD[1], MUTED_GOLD[2], MUTED_GOLD[3]) end
        self:SetGuildDBFocusState(false)
    end)
    frame.rosterSearch:SetScript("OnTextChanged", function(self)
        if self:HasFocus() then GD:RefreshUI() end
    end)
    frame.rosterOnlineOnly = true
    if GD.GetSetting then frame.rosterOnlineOnly = GD:GetSetting("onlineOnly") ~= false end
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
        if GD.SetSetting then GD:SetSetting("onlineOnly", frame.rosterOnlineOnly) else GD:RefreshUI() end
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
        header:SetScript("OnLeave", function() GD:RefreshUI() end)
        header:SetScript("OnClick", function(self)
            if GD.rosterSortField == self.sortKey then
                GD.rosterSortAscending = not GD.rosterSortAscending
            else
                GD.rosterSortField = self.sortKey
                GD.rosterSortAscending = true
            end
            GD:RefreshUI()
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
        if frame.rosterProfessionPanel and frame.rosterProfessionPanel:IsShown() then GD:LayoutRosterProfessions(frame) end
        if GD.activeTab == "Polls" and GD.RefreshPollCards and frame.pollCards then GD:RefreshPollCards(frame) end
    end)
    frame.pvpTitleSeason = frame.detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.pvpTitleSeason:SetPoint("TOPLEFT", frame.detailPanel, "TOPLEFT", 18, -40)
    frame.pvpTitleSeason:SetPoint("TOPRIGHT", frame.detailPanel, "TOPRIGHT", -18, -40)
    frame.pvpTitleSeason:SetJustifyH("LEFT")
    frame.pvpTitleSeason:SetHeight(38)
    frame.pvpTitleSeason:SetWordWrap(true)
    frame.pvpTitleSeason:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    frame.pvpSummary = frame.detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.pvpSummary:SetPoint("TOPLEFT", 18, -116)
    frame.pvpInfo = frame.detailPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.pvpInfo:SetPoint("TOPLEFT", 18, -140)
    frame.pvpInfo:SetPoint("TOPRIGHT", -18, -140)
    frame.pvpInfo:SetHeight(34)
    frame.pvpInfo:SetWordWrap(true)
    frame.pvpInfo:SetJustifyH("LEFT")
    frame.pvpTableRule = frame.detailPanel:CreateTexture(nil, "ARTWORK")
    frame.pvpTableRule:SetPoint("TOPLEFT", 14, -206)
    frame.pvpTableRule:SetPoint("TOPRIGHT", -14, -206)
    frame.pvpTableRule:SetHeight(1)
    frame.pvpTableRule:SetColorTexture(0.12, 0.25, 0.37, 0.9)
    frame.pvpHeaders = {}
    local function addPvpHeader(text, x, width, justify)
        local header = frame.detailPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        header:SetPoint("TOPLEFT", x, -187)
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
    addPvpHeader("K/D", 440, 70, "CENTER")
    addPvpHeader("LAST KILL", 490, 280)
    addPvpHeader("", 0, 1)
    addPvpHeader("", 0, 1)
    frame.pvpRows = {}
    frame.pvpViewButtons = {}
    for index, view in ipairs({ "Leaderboard", "Bounty Board", "Nemesis" }) do
        local button = CreateFrame("Button", nil, frame.detailPanel, "UIPanelButtonTemplate")
        GD:StyleButton(button)
        button:SetSize(112, 26)
        button:SetPoint("TOPLEFT", 18 + (index - 1) * 120, -80)
        button:SetText(view)
        button:SetScript("OnClick", function()
            frame.pvpView = view
            frame.detailScroll:SetVerticalScroll(0)
            GD:RefreshUI()
        end)
        frame.pvpViewButtons[index] = button
    end
    frame.pvpRivalSort = CreateFrame("Button", nil, frame.detailPanel, "UIPanelButtonTemplate")
    GD:StyleButton(frame.pvpRivalSort)
    frame.pvpRivalSort:SetSize(132, 26)
    frame.pvpRivalSort:SetPoint("TOPRIGHT", -18, -80)
    frame.pvpRivalSort:SetScript("OnClick", function()
        frame.pvpRivalDeaths = not frame.pvpRivalDeaths
        frame.detailScroll:SetVerticalScroll(0)
        GD:RefreshUI()
    end)
    frame.detailPanel:HookScript("OnSizeChanged", function(panel)
        local width = math.max(1, panel:GetWidth() - 28)
        local rivals = frame.pvpView and frame.pvpView ~= "Leaderboard"
        for index, header in ipairs(frame.pvpHeaders) do
            if index <= (rivals and 6 or 7) then layoutPvPColumn(header, index, panel, width, 14, true, rivals) end
        end
        for _, row in ipairs(frame.pvpRows) do
            layoutPvPRow(row, width, rivals)
        end
    end)
    frame.pvpEmpty = frame.detailChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.pvpEmpty:SetPoint("TOPLEFT", 12, -14)
    frame.pvpEmpty:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
    frame.pvpMyButton = CreateFrame("Button", nil, frame.detailPanel, "UIPanelButtonTemplate")
    GD:StyleButton(frame.pvpMyButton)
    frame.pvpMyButton:SetSize(98, 26)
    frame.pvpMyButton:SetPoint("TOPRIGHT", -142, -12)
    frame.pvpMyButton:SetScript("OnClick", function()
        frame.pvpMyOnly = not frame.pvpMyOnly
        GD:RefreshUI()
    end)
    frame.pvpSeasonButton = CreateFrame("Button", nil, frame.detailPanel, "UIPanelButtonTemplate")
    GD:StyleButton(frame.pvpSeasonButton, "primary")
    frame.pvpSeasonButton:SetSize(112, 26)
    frame.pvpSeasonButton:SetPoint("BOTTOMLEFT", 18, 12)
    frame.pvpSeasonButton:SetText("New Season")
    frame.pvpSeasonButton:SetScript("OnClick", function()
        if not GD:CanManagePvPSeason() then return end
        local currentName = GD.bucket and GD.bucket.pvpSeason and GD.bucket.pvpSeason.name or ""
        local currentNumber = tonumber(currentName:match("(%d+)$")) or 0
        showInputForm("Start a PvP season", {
            { label = "Season name", value = "Season " .. tostring(currentNumber + 1), max = 80 },
            { label = "End date (includes this day)", value = date("%d-%m-%Y", time() + 30 * 86400), calendar = true },
        }, function(values)
            local ok, result = GD:StartPvPSeason(values[1], values[2])
            if ok then
                frame.pvpSelectedStart = nil; frame.pvpAllTime = false
                GD:RefreshUI()
            end
            return ok, result
        end, "Start", true)
    end)
    frame.pvpDeleteButton = CreateFrame("Button", nil, frame.detailPanel, "UIPanelButtonTemplate")
    GD:StyleButton(frame.pvpDeleteButton)
    frame.pvpDeleteButton:SetSize(116, 26)
    frame.pvpDeleteButton:SetPoint("LEFT", frame.pvpSeasonButton, "RIGHT", 8, 0)
    frame.pvpDeleteButton:SetText("Delete Season")
    frame.pvpDeleteButton:SetScript("OnClick", function()
        if not GD:CanManagePvPSeason() then return end
        local options, starts, selectedLabel = {}, {}, nil
        local selected = GD:GetPvPLeaderboard(frame.pvpAllTime, frame.pvpSelectedStart)
        for _, season in ipairs(GD:GetPvPSeasons()) do
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
            local ok, result = GD:DeletePvPSeason(starts[values[1]])
            if ok then
                frame.pvpSelectedStart, frame.pvpAllTime = 0, true
                GD:RefreshUI()
            end
            return ok, result
        end, "Delete", true)
    end)
    frame.pvpWipeButton = CreateFrame("Button", nil, frame.detailPanel, "UIPanelButtonTemplate")
    GD:StyleButton(frame.pvpWipeButton)
    frame.pvpWipeButton:SetSize(120, 26)
    frame.pvpWipeButton:SetPoint("LEFT", frame.pvpDeleteButton, "RIGHT", 8, 0)
    frame.pvpWipeButton:SetText("Wipe All Stats")
    frame.pvpWipeButton:SetScript("OnClick", function()
        if not GD:CanManagePvPSeason() then return end
        GD:ConfirmAction("Wipe All PvP Stats?", "Permanently erase PvP stats for the whole guild: all-time totals, kills, deaths, history, bounties, rivalries and every season. This cannot be undone.", function()
            local ok, result = GD:WipePvPStats()
            if ok then
                frame.pvpSelectedStart, frame.pvpAllTime = nil, false
                GD:RefreshUI()
            end
            return ok, result
        end, "Wipe All", "WIPE")
    end)
    frame.pvpScopeButton = CreateFrame("Button", nil, frame.detailPanel, "UIPanelButtonTemplate")
    GD:StyleButton(frame.pvpScopeButton)
    frame.pvpScopeButton:SetSize(116, 26)
    frame.pvpScopeButton:SetPoint("TOPRIGHT", -18, -12)
    local seasonMenu = CreateFrame("ScrollFrame", nil, UIParent, "UIPanelScrollFrameTemplate,BackdropTemplate")
    seasonMenu:SetSize(280, 220)
    seasonMenu:SetPoint("TOPRIGHT", frame.pvpScopeButton, "BOTTOMRIGHT", -24, -4)
    seasonMenu:SetFrameStrata("TOOLTIP")
    seasonMenu:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
    GD:StyleSurface(seasonMenu)
    local seasonOptions = CreateFrame("Frame", nil, seasonMenu)
    seasonOptions:SetSize(280, 220)
    seasonMenu:SetScrollChild(seasonOptions)
    GD:StyleScrollFrame(seasonMenu)
    seasonMenu.buttons = {}
    seasonMenu:Hide()
    frame:HookScript("OnHide", function() seasonMenu:Hide() end)
    frame.pvpScopeButton:HookScript("OnHide", function() seasonMenu:Hide() end)
    frame.pvpScopeButton:SetScript("OnClick", function()
        if seasonMenu:IsShown() then seasonMenu:Hide(); return end
        local choices = GD:GetPvPSeasons()
        choices[#choices + 1] = { name = "Tracking details", tracking = true }
        for index, choice in ipairs(choices) do
            local option = seasonMenu.buttons[index]
            if not option then
                option = CreateFrame("Button", nil, seasonOptions, "UIPanelButtonTemplate")
                GD:StyleButton(option)
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
                        { label = "Last tracking result", value = (GD.pvpTrackingStatus or "No honor or kill-credit event received this session.") .. "\n\nLast honor message:\n" .. (GD.pvpLastHonorMessage or "None received"), multiline = true, readOnly = true, max = 1000 },
                        { label = "Client event support", value = "Honor: " .. ((GD.eventRegistration or {}).CHAT_MSG_COMBAT_HONOR_GAIN or "unknown") .. "\nKill credit: " .. ((GD.eventRegistration or {}).PLAYER_PVP_KILLS_CHANGED or "unknown"), multiline = true, readOnly = true, max = 300 },
                    }, function() return true end, "Done", true)
                    return
                end
                frame.pvpSelectedStart = start
                frame.pvpAllTime = start == 0
                seasonMenu:Hide()
                GD:RefreshUI()
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
            { label = "Repeat", value = "Once", options = { "Once", "Weekly for 4 weeks" } },
            { label = "Announce sign-ups to online GuildDB users", value = false, checkbox = true },
        }, function(values)
            local settings = { category = "Raid", raidSize = tonumber(values[4]), locked = values[5] == "Locked", announce = values[9] == true }
            if values[8] == "Weekly for 4 weeks" then
                local at, reason = GD:ParseEventTimeFields(values[2], values[3])
                if not at then return false, reason end
                showInputForm("Recurring raids - 4 weeks", {
                    {label = "Repeat on these days", weekdays = true, value = {date("*t", at).wday}},
                    {label = "Four-week schedule ends on (inclusive)", readOnly = true, value = GD:GetRaidRepeatUntil(at)},
                    {label = "Calendar copies", value = "Use Create calendar on each raid", readOnly = true},
                }, function(repeatValues)
                    return GD:PostRecurringRaid(at, values[1], values[6], settings, repeatValues[1], repeatValues[2])
                end, "Create series")
                return true
            end
            local ok, result, eventId = GD:PostEventFields(values[2], values[3], values[1], values[6], "raid", settings)
            if not ok then return false, result end
            if values[7] == "Create guild calendar event" then
                local exported, message = GD:AddEventToGameCalendar(eventId)
                result = result .. " " .. (exported and message or ("Calendar copy could not be created: " .. message .. " Use Create calendar on the raid to retry."))
            end
            return true, result
        end, "Create raid")
    end)
    frame.eventCreateTypeButton = CreateFrame("Button", nil, frame.detailPanel, "UIPanelButtonTemplate")
    GD:StyleButton(frame.eventCreateTypeButton)
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
    GD:StyleButton(frame.contentActionButton, "primary")
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
            }, function(values) return GD:PostAnnouncement(values[1], values[2]) end, "Post")
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
                return GD:CreatePoll(values[1], options)
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
    GD:StyleButton(frame.profileEditButton, "primary")
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
    GD:StyleButton(frame.rosterInviteButton)
    frame.rosterInviteButton:SetSize(242, 28)
    frame.rosterInviteButton:SetPoint("BOTTOMLEFT", frame.profileEditButton, "TOPLEFT", 0, 8)
    frame.rosterInviteButton:SetFrameLevel(frame.actionLayer:GetFrameLevel() + 1)
    frame.rosterInviteButton:RegisterForClicks("LeftButtonUp")
    frame.rosterInviteButton:SetText("Invite to group")
    frame.rosterInviteButton:SetScript("OnClick", function()
        GD:InviteRosterMember(GD.selectedRosterName)
    end)
    -- Secure descendants make every parent protected, which prevents /gd from
    -- showing the main window in combat. Keep rank actions in a separate root.
    local rankLayer = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    frame.rankLayer = rankLayer
    rankLayer:SetFrameStrata("DIALOG")
    rankLayer:SetFrameLevel(frame.actionLayer:GetFrameLevel() + 1)
    rankLayer:EnableMouse(false)
    rankLayer:SetAttribute("_onstate-combat", "if newstate == '1' then self:Hide() end")
    RegisterStateDriver(rankLayer, "combat", "[combat] 1; 0")
    rankLayer:SetShown(frame:IsShown() and GD.activeTab == "Roster")
    frame:HookScript("OnShow", function()
        if not (InCombatLockdown and InCombatLockdown()) then
            GD:PositionRankLayer()
            rankLayer:SetShown(GD.activeTab == "Roster")
        end
    end)
    frame:HookScript("OnHide", function()
        if not (InCombatLockdown and InCombatLockdown()) then rankLayer:Hide() end
    end)
    local dropdown = CreateFrame("Button", nil, rankLayer, "UIPanelButtonTemplate,SecureActionButtonTemplate")
    frame.rosterRankDropdown = dropdown
    GD:StyleButton(dropdown)
    dropdown:SetSize(242, 28)
    dropdown:RegisterForClicks("LeftButtonUp")
    dropdown:SetAttribute("useOnKeyDown", false)
    dropdown:SetPoint("BOTTOMRIGHT", rankLayer, "BOTTOMRIGHT", -28, 100)
    dropdown:Hide()
    local popup = CreateFrame("Frame", nil, rankLayer, "BackdropTemplate")
    dropdown.popup = popup
    popup:SetSize(242, 40)
    popup:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 4)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(frame.actionLayer:GetFrameLevel() + 5)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 12 })
    GD:StyleSurface(popup)
    popup:Hide()
    popup.rows = {}
    dropdown:SetScript("OnHide", function()
        if not (InCombatLockdown and InCombatLockdown()) then popup:Hide() end
    end)
    frame:HookScript("OnHide", function()
        if not (InCombatLockdown and InCombatLockdown()) then popup:Hide() end
    end)
    local function openRankMenu()
        if popup:IsShown() then popup:Hide(); return end
        if InCombatLockdown and InCombatLockdown() then return end
        local choices = GD:GetRosterRankChoices(GD.selectedRosterName)
        popup.rankContext = rosterRankMenuContext(GD.selectedRosterName, choices)
        for _, row in ipairs(popup.rows) do row:Hide() end
        for index, choice in ipairs(choices) do
            local row = popup.rows[index]
            if not row then
                row = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate,SecureActionButtonTemplate")
                row:SetSize(226, 26)
                row:SetPoint("TOPLEFT", 8, -8 - (index - 1) * 28)
                row:RegisterForClicks("LeftButtonUp")
                row:SetAttribute("useOnKeyDown", false)
                row:HookScript("PreClick", function(self)
                    self.rankSubmitted = false
                    if InCombatLockdown and InCombatLockdown() then return end
                    local macro = GD.selectedRosterName == self.rankName and GD:RosterRankMacro(self.rankName, self.rankValue)
                    if not macro or macro ~= self.rankMacro or rosterRank(self.rankName) ~= self.rankFrom then
                        self:SetAttribute("type", nil)
                        print("GuildDB: The roster changed. Open Set Guild Rank again.")
                        return
                    end
                    self.rankSubmitted = true
                end)
                row:HookScript("PostClick", function(self)
                    popup:Hide()
                    if self.rankSubmitted then GD:TrackRosterRankChange(self.rankName, self.rankValue, self.rankFrom) end
                end)
                GD:StyleButton(row)
                popup.rows[index] = row
            end
            local name, rank = GD.selectedRosterName, choice.rank
            local macro = GD:RosterRankMacro(name, rank)
            row:SetText(GD:Display(choice.label))
            row:SetAttribute("type", macro and "macro" or nil)
            row:SetAttribute("macrotext", macro)
            row.rankName, row.rankValue, row.rankMacro, row.rankFrom = name, rank, macro, rosterRank(name)
            row:SetEnabled(macro ~= nil)
            row:Show()
        end
        popup:SetHeight(#choices * 28 + 16)
        popup:SetShown(#choices > 0)
    end
    dropdown:HookScript("PreClick", function(self)
        self.rankSubmitted = false
        if InCombatLockdown and InCombatLockdown() then return end
        if not GD.rosterRankTarget then openRankMenu(); return end
        local macro = GD.selectedRosterName == self.rankName and GD:RosterRankMacro(self.rankName, self.rankValue)
        if not macro or macro ~= self.rankMacro or rosterRank(self.rankName) ~= self.rankFrom then
            self:SetAttribute("type", nil)
            GD.rosterRankTarget = nil
            GD:RefreshUI()
            return
        end
        self.rankSubmitted = true
    end)
    dropdown:HookScript("PostClick", function(self)
        if self.rankSubmitted then GD:TrackRosterRankChange(self.rankName, self.rankValue, self.rankFrom) end
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
    GD:PositionRankLayer()
end
GD.BuildUI = build

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
    button.unread = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.unread:SetPoint("RIGHT", -10, 0)
    button.unread:SetText("NEW")
    button.unread:SetTextColor(1, 0.82, 0.25)
    button.unread:Hide()
    button:SetScript("OnEnter", function(self)
        if GD.activeTab ~= tab then self.bg:SetColorTexture(PANEL_ALT[1], PANEL_ALT[2], PANEL_ALT[3], 1) end
    end)
    button:SetScript("OnLeave", function() GD:RefreshUI() end)
    button:SetScript("OnClick", function()
        if tab == "Profiles" then GD.profileTarget = nil end
        if tab == "Roster" then
            GD.profileTarget = nil
            GD.selectedRosterName = nil
            GD.selectedSection = 1
        end
        GD.activeTab = tab
        GD.selectedSection = nil
        GD:RefreshUI()
    end)
    return button
end

function GD:LayoutRosterProfessions(frame)
    local panel = frame.rosterProfessionPanel
    local width = math.max(80, frame.detailBody:GetWidth())
    panel:SetWidth(width)
    for _, row in ipairs(panel.rows) do
        row:SetWidth(width)
        row.name:SetWidth(math.max(20, width - 78))
        row.track:SetSize(width, 7)
        row.bar:SetSize(math.max(1, width * math.min(300, math.max(0, row.rank)) / 300), 7)
    end
    frame.rosterProfileFooter:SetWidth(width)
    frame.detailChild:SetHeight(math.max(400, frame.detailBody:GetStringHeight() + panel.contentHeight + frame.rosterProfileFooter:GetStringHeight() + 60))
end

function GD:ShowRosterProfessions(frame, value, footer)
    local panel = frame.rosterProfessionPanel
    if not panel then
        panel = CreateFrame("Frame", nil, frame.detailChild)
        panel:SetPoint("TOPLEFT", frame.detailBody, "BOTTOMLEFT", 0, -12)
        panel.rows = {}
        panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        panel.empty:SetPoint("TOPLEFT")
        panel.empty:SetText("Not set")
        frame.rosterProfessionPanel = panel
        frame.rosterProfileFooter = frame.detailChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.rosterProfileFooter:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -18)
        frame.rosterProfileFooter:SetJustifyH("LEFT")
        frame.rosterProfileFooter:SetWordWrap(true)
        frame.rosterProfileFooter:SetSpacing(5)
    end
    local professions = self:GetProfileProfessionList(value)
    panel.empty:SetShown(#professions == 0)
    panel.empty:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
    for index, profession in ipairs(professions) do
        local row = panel.rows[index]
        if not row then
            row = CreateFrame("Frame", nil, panel)
            row:SetPoint("TOPLEFT", 0, -(index - 1) * 44)
            row:SetHeight(36)
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.name:SetPoint("TOPLEFT")
            row.name:SetJustifyH("LEFT")
            row.name:SetWordWrap(false)
            row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.count:SetPoint("TOPRIGHT")
            row.track = row:CreateTexture(nil, "BACKGROUND")
            row.track:SetPoint("TOPLEFT", 0, -22)
            row.bar = row:CreateTexture(nil, "ARTWORK")
            row.bar:SetPoint("LEFT", row.track, "LEFT")
            panel.rows[index] = row
        end
        local color = profession.color
        local r, g, b = tonumber(color:sub(1, 2), 16) / 255, tonumber(color:sub(3, 4), 16) / 255, tonumber(color:sub(5, 6), 16) / 255
        row.rank = profession.rank
        row.name:SetText(profession.name)
        row.name:SetTextColor(r, g, b)
        row.count:SetText(profession.rank .. " / 300")
        row.count:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
        row.track:SetColorTexture(r, g, b, 0.18)
        row.bar:SetColorTexture(r, g, b, 1)
        row:Show()
    end
    for index = #professions + 1, #panel.rows do panel.rows[index]:Hide() end
    panel.contentHeight = math.max(20, #professions * 44 - 8)
    panel:SetHeight(panel.contentHeight)
    frame.rosterProfileFooter:SetText(footer)
    frame.rosterProfileFooter:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
    panel:Show()
    frame.rosterProfileFooter:Show()
    self:LayoutRosterProfessions(frame)
end

function GD:RefreshUI()
    if not self.frame then return end
    -- Ordinary views remain interactive in combat. Only the separate protected
    -- rank layer must wait for PLAYER_REGEN_ENABLED.
    local inCombat = InCombatLockdown and InCombatLockdown()
    updateTheme()
    updateAccent()
    local frame = self.frame
    if frame.rosterProfessionPanel then frame.rosterProfessionPanel:Hide(); frame.rosterProfileFooter:Hide() end
    applyTheme(frame)
    applyAccent(frame)
    if self.RefreshDiscordInviteButton then self:RefreshDiscordInviteButton() end
    local active = self.activeTab or "Home"
    if active == "Recruitment" and not self:CanManage() then
        active, self.activeTab = "Home", "Home"
    end
    if active == "Profiles" then
        self.selectedRosterName = self.profileTarget or self.selectedRosterName
        active, self.activeTab = "Roster", "Roster"
    end
    if active ~= "Roster" then self:HideRosterActions() end
    frame.activeTab = active
    if active ~= "Settings" and self.GetSetting and not self:GetSetting("feature:" .. active) then
        active = "Settings"
        self.activeTab = active
    end
    -- These full-window overlays belong to roster controls. Keeping them above
    -- other pages can obstruct native EditBox hit testing on Forever clients.
    if frame.actionLayer then frame.actionLayer:SetShown(active == "Roster") end
    if frame.rankLayer and not inCombat then
        frame.rankLayer:SetShown(frame:IsShown() and active == "Roster")
    end
    if self.UpdateUnreadState then self:UpdateUnreadState(active) end
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
            if (not frame.rosterOnlineOnly or member.online) and (query == "" or haystack:find(query, 1, true))
                and (not self.RosterMemberMatchesFilters or self:RosterMemberMatchesFilters(member, profile, self.rosterFilters)) then
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
        if self.selectedRosterName then
            local found = false
            for _, member in ipairs(rosterDisplay) do if member.name == self.selectedRosterName then found = true; break end end
            if not found then self.selectedRosterName = nil; self.selectedSection = nil end
        end
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
    local addonSummary = "    " .. usingAddon .. " known addon users"
    frame.headerStatus:SetText((self.guildName and "|cff55cf9bGUILD CONNECTED|r    " or "|cffff6666NO GUILD|r    ") .. online .. " online" .. addonSummary)
    self:RefreshGuildEmblem()
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
        if self.RefreshRosterFilters then self:RefreshRosterFilters(true, #rosterDisplay) end
        local filtersExpanded = self.RefreshRosterFilters and frame.rosterFiltersExpanded
        for _, header in ipairs(frame.rosterHeaders) do
            if self.RefreshRosterFilters then
                header:ClearAllPoints()
                local offsets = {name = 10, level = 145, rank = 215, zone = 300, role = 425, hq = 490}
                header:SetPoint("TOPLEFT", offsets[header.sortKey], filtersExpanded and -120 or -44)
            end
            local arrow = header.sortKey == (self.rosterSortField or "name") and (self.rosterSortAscending == false and " v" or " ^") or ""
            header.title:SetText(header.title:GetText():gsub(" [%^v]$", "") .. arrow)
            header:Show()
        end
        frame.listScroll:ClearAllPoints()
        frame.listScroll:SetPoint("TOPLEFT", 8, filtersExpanded and -144 or -68)
        if self.RefreshRosterFilters then
            frame.rosterHeaderRule:ClearAllPoints()
            frame.rosterHeaderRule:SetPoint("TOPLEFT", 8, filtersExpanded and -139 or -63)
            frame.rosterHeaderRule:SetPoint("TOPRIGHT", -8, filtersExpanded and -139 or -63)
            frame.rosterEmpty:ClearAllPoints()
            frame.rosterEmpty:SetPoint("TOPLEFT", 14, filtersExpanded and -158 or -82)
        end
        frame.listScroll:SetPoint("BOTTOMRIGHT", -8, 8)
        frame.rosterEmpty:SetShown(#rosterDisplay == 0)
        frame.detailPanel:ClearAllPoints()
        frame.detailPanel:SetPoint("TOPRIGHT", -14, -88)
        frame.detailPanel:SetPoint("BOTTOMRIGHT", -14, 16)
        frame.detailPanel:SetWidth(270)
    else
        frame.listPanel:Hide()
        if self.RefreshRosterFilters then self:RefreshRosterFilters(false) end
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
        local visible = tab ~= "Profiles" and (tab ~= "Recruitment" or self:CanManage())
            and (tab == "Settings" or not self.GetSetting or self:GetSetting("feature:" .. tab))
        button:SetShown(visible)
        if visible then
            navIndex = navIndex + 1
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", 9, -48 - (navIndex - 1) * 40)
        end
        local selected = tab == active
        local unread = self.GetTabUnreadCount and self:GetTabUnreadCount(tab) > 0
        button.unread:SetShown(unread == true)
        button.label:SetWidth(unread and 115 or 155)
        button.accent:SetShown(selected)
        button.bg:SetColorTexture(selected and PANEL_ALT[1] or PANEL[1], selected and PANEL_ALT[2] or PANEL[2], selected and PANEL_ALT[3] or PANEL[3], 1)
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
                cell:SetNonSpaceWrap(false)
                row.columns[columnIndex] = cell
            end
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnClick", function(self, mouseButton)
                local memberName = self.rosterName
                GD:HideRosterActions()
                GD.selectedSection = self.sectionIndex
                GD.selectedRosterName = memberName
                GD:RefreshUI()
                if mouseButton == "RightButton" and memberName then GD:ShowRosterActions(self, memberName) end
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
            local live = self.GetLiveAddonVersion and self:GetLiveAddonVersion(row.rosterName)
            local addonStatus = version and ("GuildDB v" .. version .. (live and "" or " (last known)")) or "Not yet detected"
            local profileStatus = summary and summary ~= "" and summary or (profile and "Profile available" or "No profile yet")
            local rowMember = frame.rosterDisplay[index]
            local characterInfo = table.concat({
                rowMember and rowMember.level and ("Level " .. rowMember.level) or "",
                profile and profile.race or "Race not listed",
                rowMember and rowMember.class or "",
            }, "  · ")
            local professions = self:FormatProfileProfessions(profile and profile.professions)
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
            row.columns[6]:SetText(version or "X")
            for _, cell in ipairs(row.columns) do cell:Show() end
            row.label:Hide()
            row.meta:Hide()
            if index == selected then
                row.bg:SetColorTexture(PANEL_ALT[1], PANEL_ALT[2], PANEL_ALT[3], 1)
            else
                row.bg:SetColorTexture(index % 2 == 1 and PANEL_ALT[1] or PANEL[1], index % 2 == 1 and PANEL_ALT[2] or PANEL[2], index % 2 == 1 and PANEL_ALT[3] or PANEL[3], 1)
            end
        end
        row.label:SetWidth(math.max(100, row:GetWidth() - 20))
        row.meta:SetWidth(math.max(100, row:GetWidth() - 20))
        row.selectedMarker:SetShown(active == "Roster" and index == selected)
        if active ~= "Roster" then
            local selectedRow = index == (self.selectedSection or 1)
            local color = selectedRow and PANEL_ALT or PANEL
            row.bg:SetColorTexture(color[1], color[2], color[3], 1)
        end
        row:Show()
    end
    for index = #sections + 1, #frame.listRows do frame.listRows[index]:Hide() end
    frame.listChild:SetHeight(math.max(280, #sections * (active == "Roster" and 35 or 72) + 8))

    local detail = table.concat(sections, "\n\n")
    local isPvP = active == "PvP"
    local isEvents = active == "Events"
    frame.detailScroll:Show()
    frame.detailTitle:Show()
    frame.footer:Show()
    if frame.home then frame.home:Hide() end
    if frame.requests then frame.requests:Hide() end
    if frame.guildInfo and active ~= "Guild Info" then frame.guildInfo:Hide() end
    if frame.analytics then frame.analytics:Hide() end
    if frame.activity and active ~= "Guild Achievements" then frame.activity:Hide() end
    if frame.recruitment and active ~= "Recruitment" then frame.recruitment:Hide() end
    local isActionList = active == "Polls" or active == "Announcements"
    frame.detailRule:SetShown(not isPvP and not isEvents and not isActionList)
    frame.detailMeta:SetShown(not isPvP and not isActionList)
    frame.detailScroll:ClearAllPoints()
    if isPvP then
        frame.detailScroll:SetPoint("TOPLEFT", 10, -218)
        frame.detailScroll:SetPoint("BOTTOMRIGHT", -10, self:CanManagePvPSeason() and 54 or 12)
    else
        frame.detailScroll:SetPoint("TOPLEFT", 10, -66)
        frame.detailScroll:SetPoint("BOTTOMRIGHT", -28, 54)
    end
    for _, element in ipairs({ frame.pvpTitleSeason, frame.pvpSummary, frame.pvpInfo, frame.pvpTableRule, frame.pvpMyButton, frame.pvpSeasonButton, frame.pvpDeleteButton, frame.pvpWipeButton, frame.pvpScopeButton }) do
        element:SetShown(isPvP)
    end
    for _, button in ipairs(frame.pvpViewButtons) do button:SetShown(isPvP) end
    frame.pvpRivalSort:SetShown(isPvP and frame.pvpView == "Nemesis")
    frame.eventCreateButton:SetShown(isEvents and self:CanManage())
    frame.eventCreateTypeButton:Hide()
    local actionVisible = active == "Profiles" or (active == "Polls" and self:CanManage()) or (active == "Announcements" and self:CanManage())
    frame.contentActionButton:SetShown(actionVisible)
    frame.contentActionButton:EnableMouse(true)
    frame.contentActionButton:ClearAllPoints()
    frame.contentActionButton:SetSize(130, 26)
    frame.contentActionButton:SetPoint("TOPRIGHT", frame.detailPanel, "TOPRIGHT", -18, -12)
    frame.profileEditButton:SetShown(active == "Roster")
    frame.rosterInviteButton:SetShown(active == "Roster" and self.selectedRosterName ~= nil)
    if active ~= "Roster" then self:RefreshRosterRankControls(nil) end
    if active == "Announcements" then
        frame.contentActionButton:SetText("New post")
    elseif active == "Profiles" then
        frame.contentActionButton:SetText("Edit my profile")
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
    for _, card in ipairs(frame.pollCards or {}) do card:Hide() end
    if frame.pollEmpty then frame.pollEmpty:Hide() end
    if frame.actionEmpty then frame.actionEmpty:Hide() end
    frame.detailChild:SetWidth(math.max(100, frame.detailScroll:GetWidth() - 4))
    frame.detailBody:SetWidth(math.max(80, frame.detailScroll:GetWidth() - 28))
    frame.detailTitle:SetWidth(math.max(120, frame.detailPanel:GetWidth() - 36))
    frame.detailTitle:SetWordWrap(active ~= "Roster")
    frame.detailTitle:SetNonSpaceWrap(active ~= "Roster")
    frame.detailMeta:SetWidth(math.max(100, frame.detailPanel:GetWidth() - 36))
    frame.listChild:SetWidth(math.max(100, frame.listScroll:GetWidth() - 4))
    if active == "Settings" then
        -- Hiding a pressed button cancels its pending mouse-up click. Settings
        -- stays visible while background roster/presence updates refresh it.
        frame.detailBody:Hide()
        frame.detailMeta:SetText("Personal preferences and officer controls")
        frame.detailTitle:SetText("Settings")
        self:ShowSettingsControls(frame.detailChild)
        frame.detailChild:SetHeight(480)
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
        frame.rosterInviteButton:SetShown(name ~= nil)
        self:RefreshRosterRankControls(name)
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
        local live = self.GetLiveAddonVersion and self:GetLiveAddonVersion(name)
        local addonLine = "GuildDB  " .. (version and ("v" .. version .. (live and "" or " (last known)")) or "Not yet detected") .. "\n\n"
        frame.detailBody:SetText(addonLine .. "Status: " .. status .. "  -  " .. zone .. "\n\nRole: " .. value("role") .. "\n\nProfessions:")
        self:ShowRosterProfessions(frame, profile and profile.professions, "Specialization: " .. value("spec") .. "\n\nTime zone: " .. value("timezone") .. "\n\nAlts: " .. value("alts"))
    elseif active == "PvP" then
        self:HideSettingsControls()
        frame.detailBody:Hide()
        local view = frame.pvpView or "Leaderboard"
        local isRivals, isBounty = view ~= "Leaderboard", view == "Bounty Board"
        for index, button in ipairs(frame.pvpViewButtons) do
            local selectedView = ({ "Leaderboard", "Bounty Board", "Nemesis" })[index] == view
            self:StyleButton(button, selectedView and "primary" or nil)
        end
        frame.pvpMyButton:SetShown(not isRivals)
        frame.pvpRivalSort:SetText(frame.pvpRivalDeaths and "Killed me most" or "Most killed")
        frame.detailTitle:SetWidth(math.min(390, math.max(250, frame.detailPanel:GetWidth() - 500)))
        frame.detailTitle:SetText(isBounty and "BOUNTY BOARD" or isRivals and "NEMESIS" or "PVP LEADERBOARD")
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
                if frame:IsShown() and GD.activeTab == "PvP" then GD:RefreshUI() end
            end)
        end
        frame.pvpMyButton:SetText(frame.pvpMyOnly and "Guild board" or "My stats")
        frame.pvpSeasonButton:SetShown(self:CanManagePvPSeason())
        frame.pvpDeleteButton:SetShown(self:CanManagePvPSeason())
        frame.pvpDeleteButton:SetEnabled(#self:GetPvPSeasons() > 1)
        frame.pvpWipeButton:SetShown(self:CanManagePvPSeason())
        frame.pvpScopeButton:SetText("Seasons  v")
        local playerName = UnitName and UnitName("player") or "You"
        frame.pvpSummary:SetText(ownScore and ("You: |cffffcc33%d points|r (%d bounty) / %d kills / %d deaths / %.2f K/D - #%d"):format(ownScore.points, ownScore.bountyPoints or 0, ownScore.kills, ownScore.deaths, ownScore.kd, ownRank) or (playerName .. ": no PvP stats yet"))
        frame.pvpInfo:SetText("Ranked by total points  |  Points = kills + bounty bonus  |  Open world only  |  K/D uses kills and deaths")
        if isBounty then
            ranking = self:GetPvPBounties()
            frame.pvpScopeButton:Hide()
            frame.pvpTitleSeason:SetText("Guild-wide bounties - points count in the season when claimed")
            frame.pvpSummary:SetText("3 guild deaths opens +3 points; each further death adds +1, up to +10")
            frame.pvpInfo:SetText("Repeat victims count  |  Every credited member earns the full bonus once  |  Counter restarts after a claim")
        elseif isRivals then
            ranking = self:GetPvPRivals(frame.pvpAllTime, frame.pvpSelectedStart, false, frame.pvpRivalDeaths)
            frame.pvpSummary:SetText("Your rivalries: enemies you defeat and enemies who kill you")
            frame.pvpInfo:SetText("Kills: you defeated them  |  Deaths: they killed you  |  Use Seasons to change the period")
        elseif frame.pvpMyOnly then
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
        local labels = isBounty and { "#", "ENEMY", "DEATHS", "BONUS", "STATUS", "LAST ENCOUNTER" }
            or isRivals and { "#", "ENEMY", "KILLS", "DEATHS", "K/D", "LAST ENCOUNTER" }
            or { "#", "PLAYER", "RANK", "POINTS", "KILLS", "DEATHS", "K/D", "LAST KILL" }
        for index, header in ipairs(frame.pvpHeaders) do
            header:SetShown(labels[index] ~= nil)
            if labels[index] then
                header:SetText(labels[index])
                layoutPvPColumn(header, index, frame.detailPanel, boardWidth, 14, true, isRivals)
            end
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
                row.pvpRank = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.points = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.killCount = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.kills = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.kd = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.last = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                frame.pvpRows[i] = row
            end
            layoutPvPRow(row, boardWidth, isRivals)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 36)
            row:SetPoint("RIGHT", frame.detailChild, "RIGHT", -4, 0)
            row.rank:SetText(tostring(i))
            row.player:SetText(self:Display(isRivals and score.name or leaderboardName(score.name)))
            row.pvpRank:SetText(not isRivals and (season.start or 0) > 0 and self:GetPvPRank(score.kills or 0) or "—")
            row.pvpRank:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
            local classColor = not isRivals and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classByName[characterKey(score.name)]]
            if classColor then row.player:SetTextColor(classColor.r, classColor.g, classColor.b)
            else row.player:SetTextColor(CREAM[1], CREAM[2], CREAM[3]) end
            row.points:SetText(tostring(isBounty and score.deaths or isRivals and score.kills or score.points or 0))
            row.points:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
            row.killCount:SetText(tostring(score.kills or 0))
            row.kills:SetText(isBounty and (score.reward > 0 and ("+" .. score.reward) or "-") or tostring(score.deaths or 0))
            row.kd:SetText(isBounty and score.status or ("%.2f"):format(score.kd))
            local last = score.lastKill
            local lastText = "-"
            if last or isRivals and score.last > 0 then
                local age = math.max(0, time() - (isRivals and score.last or last.ts or time()))
                local ageText = age < 3600 and (math.floor(age / 60) .. "m") or age < 86400 and (math.floor(age / 3600) .. "h") or (math.floor(age / 86400) .. "d")
                lastText = isRivals and (ageText .. " ago") or (self:Display(last.victim or "Unknown") .. " (" .. tostring(last.victimLevel or "?") .. ")  " .. ageText .. " ago")
            end
            row.last:SetText(lastText)
            row.last:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
            row.bg:SetColorTexture(i % 2 == 1 and PANEL_ALT[1] or PANEL[1], i % 2 == 1 and PANEL_ALT[2] or PANEL[2], i % 2 == 1 and PANEL_ALT[3] or PANEL[3], 1)
            row:Show()
        end
        for i = #ranking + 1, #frame.pvpRows do frame.pvpRows[i]:Hide() end
        if #ranking == 0 then
            frame.pvpEmpty:SetText(not self.guildName and "Join a guild to see PvP stats." or isBounty and "No bounty activity yet. Three guild deaths to the same enemy opens a bounty." or isRivals and "No personal rivalries recorded in this period yet." or "No outdoor PvP kills recorded this season yet.")
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
                row.info = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
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
                    local _, result = GD:InviteRaidSelections(button.eventId)
                    if result then print("GuildDB: " .. result) end
                end)
                row.announceButton = CreateFrame("Button", nil, row)
                styleRaidButton(row.announceButton, 168, "secondary")
                row.announceButton:SetPoint("RIGHT", row.inviteButton, "LEFT", -8, 0)
                row.announceButton:SetText("Announce sign-ups")
                row.announceButton:SetScript("OnClick", function(button)
                    local _, result = GD:AnnounceRaidSignups(button.eventId)
                    if result then print("GuildDB: " .. result) end
                end)
                row.signupRows = {}
                row.rsvpButtons = {}
                row.calendarButton = CreateFrame("Button", nil, row)
                styleRaidButton(row.calendarButton, 128, "secondary")
                row.calendarButton:SetPoint("TOPLEFT", 16, -184)
                row.calendarButton:SetScript("OnClick", function(self)
                    local _, result = GD:AddEventToGameCalendar(self.eventId)
                    if result then print("GuildDB: " .. result) end
                end)
                row.editButton = CreateFrame("Button", nil, row)
                styleRaidButton(row.editButton, 88, "secondary")
                row.editButton:SetPoint("LEFT", row.calendarButton, "RIGHT", 8, 0)
                row.editButton:SetText("Edit")
                row.editButton:SetScript("OnClick", function(self)
                    local event
                    for _, candidate in ipairs(GD.bucket and GD.bucket.events or {}) do
                        if candidate.id == self.eventId then event = candidate; break end
                    end
                    if not event then return end
                    local settings = event.calendarSettings or {}
                    local category = settings.category or (event.eventType == "raid" and "Raid" or "Other")
                    local inviteMode = settings.inviteMode == "selected" and "Selected players"
                        or settings.inviteMode == "guild" and "Mass invite guild" or "No invites"
                    local fields = {
                        { label = "Title", value = event.title or "", max = 100 },
                        { label = "Raid date (your local calendar)", value = date("%d-%m-%Y", event.at), calendar = true },
                        { label = "Start time (your local time)", value = date("%I:%M %p", event.at):gsub("^0", ""), options = raidStartTimes },
                        { label = "Calendar category", value = category, options = { "Raid", "Dungeon", "PvP", "Meeting", "Other" } },
                        { label = "Sign-ups", value = settings.locked and "Locked" or "Open", options = { "Open", "Locked" } },
                        { label = "Invitations", value = inviteMode, options = { "No invites", "Selected players", "Mass invite guild" } },
                        { label = "Players to invite (comma separated)", value = settings.inviteNames or "", max = 200 },
                        { label = "Details", value = event.details or "", max = 300, multiline = true },
                        { label = "Raid size target", value = tostring(settings.raidSize or 40), options = { "10", "20", "25", "40" } },
                    }
                    if settings.seriesId then fields[#fields + 1] = {
                        label = "Apply changes to (date changes shift the series)", value = "This raid only",
                        options = {"This raid only", "All upcoming in series"},
                    } end
                    showInputForm("Edit guild event", fields, function(values)
                        local at, reason = GD:ParseEventTimeFields(values[2], values[3])
                        if not at then return false, reason end
                        local updatedSettings = calendarSettingsFromForm(values, 4)
                        updatedSettings.raidSize = tonumber(values[9])
                        if values[10] == "All upcoming in series" then
                            return GD:EditRaidSeries(self.eventId, at, values[1], values[8], updatedSettings)
                        end
                        return GD:EditEvent(self.eventId, at, values[1], values[8], updatedSettings)
                    end)
                end)
                row.deleteButton = CreateFrame("Button", nil, row)
                styleRaidButton(row.deleteButton, 88, "danger")
                row.deleteButton:SetPoint("LEFT", row.editButton, "RIGHT", 8, 0)
                row.deleteButton:SetText("Delete raid")
                row.deleteButton:SetScript("OnClick", function(self)
                    local event
                    for _, candidate in ipairs(GD.bucket and GD.bucket.events or {}) do
                        if candidate.id == self.eventId then event = candidate; break end
                    end
                    if not event then return end
                    local fields = {
                        { label = "Type REMOVE to confirm", value = "", max = 12 },
                    }
                    if event.calendarSettings and event.calendarSettings.seriesId then fields[#fields + 1] = {
                        label = "Remove", value = "This raid only", options = {"This raid only", "All upcoming in series"},
                    } end
                    showInputForm("Remove guild event", fields, function(values)
                        if tostring(values[1] or ""):upper() ~= "REMOVE" then
                            return false, "Type REMOVE to confirm event removal."
                        end
                        if values[2] == "All upcoming in series" then return GD:DeleteRaidSeries(self.eventId) end
                        return GD:DeleteEvent(self.eventId)
                    end)
                end)
                row.withdrawButton = CreateFrame("Button", nil, row)
                styleRaidButton(row.withdrawButton, 112, "danger")
                row.withdrawButton:SetPoint("TOPRIGHT", -16, -184)
                row.withdrawButton:SetText("Withdraw")
                row.withdrawButton:SetScript("OnClick", function(button)
                    local _, result = GD:RemoveRaidSignup(button.eventId)
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
                        local profile = GD.GetProfile and GD:GetProfile(player) or {}
                        local current
                        for _, candidate in ipairs(GD.bucket and GD.bucket.events or {}) do
                            if candidate.id == eventId then current = candidate.rsvps and candidate.rsvps[player]; break end
                        end
                        current = type(current) == "table" and current or { status = current }
                        local defaultRole, defaultSpec = GD:GetRaidSignupDefaults(current, profile)
                        local className = GD:GetRaidPlayerClass(player)
                        local attendance = current.status == "tentative" and "Maybe" or current.status == "absent" and "Absent" or "Going"
                        showInputForm("Your raid signup", {
                            { label = "Attendance", value = attendance, options = { "Going", "Maybe", "Absent" } },
                            { label = "Class (detected automatically)", value = className, readOnly = true },
                            { label = "Spec (e.g. Holy, Protection, Fury)", value = defaultSpec, max = 60 },
                            { label = "Role", value = defaultRole, options = { "Tank", "Healer", "DPS" } },
                            { label = "Note (availability, late arrival, etc.)", value = current.note or "", max = 100 },
                        }, function(values)
                            local attendanceStatus = values[1] == "Going" and "going" or values[1] == "Maybe" and "tentative" or "absent"
                            return GD:SetRSVPForEvent(eventId, attendanceStatus, values[4], values[5], values[3])
                        end, "Save signup")
                    end)
                    row.rsvpButtons[buttonIndex] = button
                end
                frame.eventRows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 4, -eventY)
            row:SetPoint("RIGHT", frame.detailChild, "RIGHT", -4, 0)
            row.title:SetText(self:Display(event.title) .. ((event.calendarSettings or {}).seriesId and " |cff8ba7bf[Weekly]|r" or ""))
            row.title:SetWidth(math.max(180, frame.detailChild:GetWidth() - 200))
            local calendarSettings = event.calendarSettings or {}
            local category = calendarSettings.category or (event.eventType == "raid" and "Raid" or "Other")
            row.info:SetWidth(math.max(180, frame.detailChild:GetWidth() - 48))
            row.info:SetHeight(22)
            row.info:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
            row.info:SetText(date("%A, %d %b %Y  |  %I:%M %p", event.at) .. " local")
            row.state:SetText(calendarSettings.locked and "SIGNUPS LOCKED" or "SIGNUPS OPEN")
            if calendarSettings.locked then row.state:SetTextColor(0.92, 0.65, 0.28)
            else row.state:SetTextColor(0.35, 0.85, 0.58) end
            row.details:SetWidth(math.max(180, frame.detailChild:GetWidth() - 48))
            row.details:SetHeight(30)
            row.details:SetText(category .. "  |  Led by " .. self:Display(event.by) .. "\n" .. self:Display(event.details ~= "" and event.details or "No additional raid notes."))
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
            local calendarExports = GDB and GDB.calendarExports
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
            row.announceButton.eventId = event.id
            row.announceButton:SetShown(canManageEvent and event.eventType == "raid")
            row.announceButton:SetEnabled(not calendarSettings.locked and event.at >= time())
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
            local needsSignup = self:NeedsRaidSignup(event)
            row.personalStatus:SetWidth(math.max(180, frame.detailChild:GetWidth() - 48))
            local signupText = needsSignup and (calendarSettings.locked and "SIGNUP MISSING - signups are locked; contact an officer" or "SIGNUP NEEDED - choose Going, Maybe, or Absent")
                or ("Your signup: " .. statusLabel)
            row.personalStatus:SetText(signupText .. (counts.unassigned > 0 and ("  |  " .. counts.unassigned .. " attending without a role") or ""))
            if needsSignup then row.personalStatus:SetTextColor(1, 0.78, 0.35)
            else row.personalStatus:SetTextColor(CREAM[1], CREAM[2], CREAM[3]) end
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
                        }, function() return GD:RemoveRaidSignup(eventId, target) end, "Remove")
                    end)
                    signup:SetScript("OnClick", function(button)
                        local _, result = GD:SetRaidSelection(button.eventId, button.player, not button.selected)
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
                signup:SetEnabled(not event.preview and GD:IsRaidGM() and response.status == "going")
                local className, classFile = GD:GetRaidPlayerClass(name)
                local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                local values = { GD:Display(name), GD:Display(className), GD:Display(response.spec ~= "" and response.spec or "Not set"), response.role or "Not set", response.status == "going" and "Going" or response.status == "tentative" and "Maybe" or "Absent" }
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
                signup.note:SetText(GD:Display(response.note or ""))
                signup.tooltipText = GD:Display(className) .. " - " .. GD:Display(response.spec or "Spec not set") .. "\n" .. (response.role or "Role not set") .. " - " .. values[5] .. ((response.note or "") ~= "" and ("\n" .. GD:Display(response.note)) or "")
                if response.status == "going" and selection and selection.selected then signup.band:SetColorTexture(0.07, 0.16, 0.22, 1) end
                signup.remove:SetPoint("TOPRIGHT", row, "TOPRIGHT", -16, -281 - (index - 1) * 44)
                signup.remove.eventId, signup.remove.player = event.id, name
                signup.remove:SetShown(not event.preview and (GD:IsRaidGM() or name == player))
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
    elseif active == "Polls" and self.RefreshPollCards then
        self:HideSettingsControls()
        frame.detailBody:Hide()
        frame.detailTitle:SetText("POLLS")
        self:RefreshPollCards(frame)
    elseif active == "Requests" then
        self:HideSettingsControls()
        frame.detailBody:Hide()
        frame.detailScroll:Hide()
        frame.detailTitle:SetText("REQUESTS")
        frame.detailMeta:Hide()
        frame.detailRule:Hide()
        self:RefreshRequests(frame, showInputForm)
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
                    GD:StyleButton(button, "primary")
                    button:SetSize(76, 22)
                    row.buttons[buttonIndex] = button
                end
                button:SetText(action.label)
                GD:StyleButton(button, action.label == "Delete" and "secondary" or "primary")
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
                        self:ConfirmAction("Delete announcement?", "Permanently delete this guild announcement: " .. self:Display(postTitle),
                            function() return self:DeleteAnnouncement(postId) end, "Delete")
                    end }
                end
                local title = postTitle ~= "" and postTitle or "Announcement"
                local meta = "By " .. self:Display(post.by or "Guild member") .. "  ·  " .. date("%b %d, %I:%M %p", post.ts or time())
                addActionRow(self:Display(title), meta, actions, self:Display(postText))
            end
        end
        if #entries == 0 then
            frame.actionEmpty = frame.actionEmpty or frame.detailChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            frame.actionEmpty:SetPoint("TOPLEFT", 12, -14)
            local emptyText = active == "Announcements" and "No announcements yet. Officers can create the first post." or "No active posts."
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
    if active ~= "Roster" and active ~= "Settings" and active ~= "PvP" and active ~= "Events" and not isActionList then frame.detailChild:SetHeight(math.max(400, frame.detailBody:GetStringHeight() + 20)) end
    if active == "Home" and self.RefreshHome then self:RefreshHome() end
    if active == "Guild Info" and self.RefreshGuildInfo then self:RefreshGuildInfo() end
    if active == "Analytics" and self.RefreshAnalytics then self:RefreshAnalytics() end
    if active == "Guild Achievements" and self.RefreshActivity then self:RefreshActivity() end
    if active == "Recruitment" and self.RefreshRecruitment then self:RefreshRecruitment() end
end

local function rebuildRoster()
    GD:ConfirmRosterRankChange()

    if not GD.guildName or not GetNumGuildMembers or not GetGuildRosterInfo then return end
    local roster = {}
    for i = 1, GetNumGuildMembers(true) do
        local name, rankName, rankIndex, level, className, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name then
            roster[#roster + 1] = { name = name, rank = rankName or "Member", rankIndex = rankIndex or 99, level = level, class = className, classFile = classFile, zone = zone, online = not not online }
        end
    end
    table.sort(roster, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.name:lower() < b.name:lower()
    end)
    GD.roster = roster
    GD:RefreshUI()
end
GD.RebuildRoster = rebuildRoster
GD:RegisterEventHandler("PLAYER_LOGIN", function() build(); rebuildRoster() end)
GD:RegisterEventHandler("GUILD_ROSTER_UPDATE", function(_, canRequest)
    if canRequest then requestRankRoster() end
    build(); rebuildRoster()
end)
GD:RegisterEventHandler("PLAYER_GUILD_UPDATE", function() build(); rebuildRoster() end)
GD:RegisterEventHandler("PLAYER_REGEN_ENABLED", function() GD:RefreshUI() end)

function GD:IsSyncResponder(requester)
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
        if member.online and candidateName ~= excluded and self:GetLiveAddonVersion(member.name) then candidates[#candidates + 1] = member end
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

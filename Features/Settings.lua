-- Personal preferences plus per-guild, officer-managed feature visibility.
local _, GD = ...

local defaults = { onlineOnly = true, scale = 1, popups = true, raidReminders = true, levelGuildChat = false, shareMapLocation = false, accentColor = 1, uiTheme = 1, showMinimapButton = true, minimapAngle = 225, dkpAuctionWidth = 520, dkpAuctionHeight = 610, dkpOutbidSound = false, dkpOutbidFlash = false }

function GD:ResetAppearance()
    self:SetSetting("accentColor", defaults.accentColor)
    self:SetSetting("uiTheme", defaults.uiTheme)
    return true, "Appearance reset to class color and Midnight."
end

local function settings()
    if type(GDB) ~= "table" then GDB = {} end
    if type(GDB.settings) ~= "table" then GDB.settings = {} end
    for key, value in pairs(defaults) do
        if GDB.settings[key] == nil then GDB.settings[key] = value end
    end
    if type(GDB.settings.features) ~= "table" then GDB.settings.features = {} end
    return GDB.settings
end

function GD:HasGuildFeatureSettings()
    local config = self.bucket and self.bucket.guildSettings
    return config ~= nil and type(config.features) == "table" and next(config.features) ~= nil
        and type(config.ts) == "number" and config.ts > 0
end

function GD:GetSetting(key)
    if key == "feature:DKP" then return self:IsDKPEnabled() end
    local db = settings()
    if key:sub(1, 8) == "feature:" then
        local tab = key:sub(9)
        local guildSettings = self.bucket and self.bucket.guildSettings
        if tab == "Guild Achievements" and guildSettings and guildSettings.features
            and guildSettings.features["Guild Achievements"] == nil and guildSettings.features.Activity ~= nil then
            return guildSettings.features.Activity ~= false
        end
        if tab == "Requests" and guildSettings and guildSettings.features
            and guildSettings.features.Requests == nil
            and (guildSettings.features["Looking For"] ~= nil or guildSettings.features.Crafting ~= nil) then
            return guildSettings.features["Looking For"] ~= false or guildSettings.features.Crafting ~= false
        end
        if tab == "Home" and guildSettings and guildSettings.features
            and guildSettings.features.Home == nil and guildSettings.features.Announcements ~= nil then
            return guildSettings.features.Announcements ~= false
        end
        if guildSettings and guildSettings.features and guildSettings.features[tab] ~= nil then
            return guildSettings.features[tab] ~= false
        end
        -- A new member must not briefly enable every optional workspace while
        -- waiting for the guild's first snapshot. Officers can still configure it.
        if self.guildName and not self:HasGuildFeatureSettings() and not self:CanManage() then
            return tab == "Home" or tab == "Roster" or tab == "Settings"
        end
        return true
    end
    return db[key]
end

function GD:SetSetting(key, value)
    if key == "feature:DKP" then return self:SetDKPEnabled(value) end
    local db = settings()
    if key:sub(1, 8) == "feature:" then
        if not self:CanManage() or not self.bucket then return end
        local config = self.bucket.guildSettings or { features = {} }
        config.features = config.features or {}
        -- Rapid toggles must still supersede the previous snapshot.
        config.ts = math.max(time(), (tonumber(config.ts) or 0) + 1)
        config.by = self:PlayerName()
        for _, tab in ipairs(self.tabs or {}) do
            if tab ~= "Settings" then config.features[tab] = self:GetSetting("feature:" .. tab) end
        end
        config.features[key:sub(9)] = not not value
        self.bucket.guildSettings = config
        local lines = {}
        for _, tab in ipairs(self.tabs or {}) do
            if tab ~= "Settings" then
                lines[#lines + 1] = tab .. "\t" .. (config.features[tab] and "1" or "0")
            end
        end
        self:SendRecord("F", "features", config.ts, config.by, table.concat(lines, "\n"))
        if not value and self.activeTab == key:sub(9) then
            self.activeTab = "Settings"
            for _, tab in ipairs(self.tabs or {}) do
                if tab ~= key:sub(9) and tab ~= "Settings" and self:GetSetting("feature:" .. tab) then
                    self.activeTab = tab
                    break
                end
            end
        end
    elseif defaults[key] ~= nil then
        if key == "accentColor" then
            value = math.max(1, math.min(7, math.floor(tonumber(value) or 1)))
        elseif key == "uiTheme" then
            value = math.max(1, math.min(4, math.floor(tonumber(value) or 1)))
        elseif key == "dkpAuctionWidth" then
            value = math.max(500, math.min(800, math.floor(tonumber(value) or 520)))
        elseif key == "dkpAuctionHeight" then
            value = math.max(540, math.min(900, math.floor(tonumber(value) or 610)))
        elseif key == "minimapAngle" then
            value = (tonumber(value) or 225) % 360
            if type(GDB.minimap) == "table" then GDB.minimap.minimapPos = value end
        end
        db[key] = value
    else
        return
    end
    if key == "scale" and self.frame then self.frame:SetScale(value) end
    if key == "onlineOnly" then
        if self.frame and self.frame.rosterOnlineCheck then
            self.frame.rosterOnlineOnly = value ~= false
            self.frame.rosterOnlineCheck.mark:SetShown(self.frame.rosterOnlineOnly)
        end
        if self.RebuildRoster then self:RebuildRoster() end
    end
    if (key == "showMinimapButton" or key == "minimapAngle") and self.RefreshMinimapButton then
        self:RefreshMinimapButton()
    end
    if self.RefreshUI then self:RefreshUI() end
end

local function normalizeName(name)
    return tostring(name or ""):lower():gsub("[%s%-]", "")
end

local function guildRank(name)
    if not name or not GetNumGuildMembers or not GetGuildRosterInfo then return nil end
    local wanted, short, fallback, matches = normalizeName(name), tostring(name):match("^([^%s%-]+)$"), nil, 0
    for index = 1, GetNumGuildMembers(true) do
        local rosterName, _, rankIndex = GetGuildRosterInfo(index)
        if rosterName then
            if normalizeName(rosterName) == wanted then return tonumber(rankIndex) end
            -- Forever can shorten a chat sender to their first name. Only use
            -- that fallback when exactly one roster member has that first name.
            local first = rosterName:match("^([^%s%-]+)")
            if short and first and first:lower() == short:lower() then
                fallback, matches = tonumber(rankIndex), matches + 1
            end
        end
    end
    if matches == 1 then return fallback end
end

local pendingFeatures = {}
local nextFeatureRoster = 0
local function deferFeatures(id, ts, author, content, sender)
    if #pendingFeatures >= 60 then return end
    pendingFeatures[#pendingFeatures + 1] = {
        id = id, ts = ts, author = author, content = content,
        sender = sender, bucket = GD.bucket,
    }
    if time() >= nextFeatureRoster then
        nextFeatureRoster = time() + 10
        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
        elseif GuildRoster then GuildRoster() end
    end
end
local function receiveFeatures(id, ts, author, content, sender)
    if id ~= "features" or not GD.bucket or #content > 1000 or ts <= 0 or ts > time() + 60 then return end
    -- A fresh login can receive history before guild ranks are available.
    if not GetNumGuildMembers or GetNumGuildMembers(true) == 0 then
        deferFeatures(id, ts, author, content, sender)
        return
    end
    -- History may come from any guild peer, including when the officer is offline.
    -- Keep the original officer attribution when relaying the saved snapshot.
    local authorRank = guildRank(author)
    if authorRank and authorRank > 1 then return end
    if guildRank(sender) == nil or authorRank == nil then
        deferFeatures(id, ts, author, content, sender)
        return
    end
    local features, found = {}, false
    for line in (content .. "\n"):gmatch("(.-)\n") do
        local tab, enabled = line:match("^(.-)\t([01])$")
        if not tab or tab == "" or #tab > 80 or tab:find("[%c]") then return end
        features[tab] = enabled == "1"
        found = true
    end
    if not found then return end
    local current = GD.bucket.guildSettings or {}
    if (current.ts or 0) > ts or ((current.ts or 0) == ts and tostring(current.by or "") > author) then return end
    local config = GD.bucket.guildSettings or {}
    config.features, config.ts, config.by = features, ts, author
    GD.bucket.guildSettings = config
    if GD.RefreshUI then GD:RefreshUI() end
end
GD:RegisterRecordHandler("F", receiveFeatures)

GD:RegisterEventHandler("GUILD_ROSTER_UPDATE", function()
    if not GetNumGuildMembers or GetNumGuildMembers(true) == 0 then return end
    local records = pendingFeatures
    pendingFeatures = {}
    for _, record in ipairs(records) do
        if GD.bucket == record.bucket then
            receiveFeatures(record.id, record.ts, record.author, record.content, record.sender)
        end
    end
    if not GD:HasGuildFeatureSettings() then GD:RequestFeatureSettings() end
end)

local function sendFeatures()
    local config = GD.bucket and GD.bucket.guildSettings
    if not GD:HasGuildFeatureSettings() then
        local rank
        if GetGuildInfo then local _, _, value = GetGuildInfo("player"); rank = value end
        if not GD.bucket or rank ~= 0 then return end
        config = config or {}
        config.features = config.features or {}
        for _, tab in ipairs(GD.tabs or {}) do
            if tab ~= "Settings" then config.features[tab] = GD:GetSetting("feature:" .. tab) end
        end
        -- A GM with no saved selection can share defaults, but that snapshot
        -- must never outrank an actual saved choice relayed by another peer.
        config.ts, config.by = 1, GD:PlayerName()
        GD.bucket.guildSettings = config
    end
    local lines = {}
    -- Relay only saved values: newer/renamed tabs must retain their defaults.
    for tab, enabled in pairs(config.features) do
        lines[#lines + 1] = tab .. "\t" .. (enabled and "1" or "0")
    end
    table.sort(lines)
    GD:SendRecord("F", "features", config.ts, config.by or "Guild officer", table.concat(lines, "\n"))
end
GD:RegisterHistoryProvider(sendFeatures)

local featureRequestBucket, lastFeatureRequest, lastFeatureReply = nil, 0, 0
local pendingFeatureReply
local immediateFeatureRequest = false
function GD:RequestFeatureSettings(immediate)
    if not self.bucket then return false end
    if self.RequestDKPSettings then self:RequestDKPSettings(immediate) end
    if featureRequestBucket ~= self.bucket then
        featureRequestBucket, lastFeatureRequest, lastFeatureReply = self.bucket, 0, 0
        immediateFeatureRequest = false
    end
    -- Opening the window/manual re-sync should retry promptly even when a
    -- login request was just dropped, while repeated clicks stay throttled.
    local firstImmediate = immediate and not immediateFeatureRequest
    if not firstImmediate and time() - lastFeatureRequest < (immediate and 2 or 10) then return false end
    if immediate then immediateFeatureRequest = true end
    lastFeatureRequest = time()
    self:SendRecord("FQ", "features", time(), self:PlayerName(), "")
    return true
end

GD:RegisterRecordHandler("FQ", function(id, ts, author, content, sender)
    if id ~= "features" or not GD.bucket or content ~= "" or guildRank(sender) == nil then return end
    if normalizeName(author) == normalizeName(GD:PlayerName()) then return end
    local remaining = lastFeatureReply + 5 - time()
    if remaining > 0 then
        if pendingFeatureReply or not C_Timer or not C_Timer.After then return end
        local token, bucket = {}, GD.bucket
        pendingFeatureReply = token
        C_Timer.After(remaining, function()
            if pendingFeatureReply ~= token then return end
            pendingFeatureReply = nil
            if GD.bucket ~= bucket then return end
            lastFeatureReply = time()
            sendFeatures()
        end)
        return
    end
    pendingFeatureReply = nil
    lastFeatureReply = time()
    -- Any peer with an officer-authored snapshot can answer, even if the GM is
    -- offline. This uses the live queue instead of waiting behind full history.
    sendFeatures()
end)

local featureSession
local function startFeatureSync()
    if not GD.bucket then featureSession = nil; return end
    if featureSession == GD.bucket then return end
    local bucket = GD.bucket
    featureSession = bucket
    GD:RequestFeatureSettings()
    if C_Timer and C_Timer.After then
        for _, delay in ipairs({ 3, 12, 30, 60 }) do
            C_Timer.After(delay, function()
                if GD.bucket == bucket and featureSession == bucket then GD:RequestFeatureSettings() end
            end)
        end
    end
end
GD:RegisterEventHandler("PLAYER_LOGIN", startFeatureSync)
GD:RegisterEventHandler("PLAYER_GUILD_UPDATE", startFeatureSync)
GD:RegisterEventHandler("PLAYER_ENTERING_WORLD", startFeatureSync)

local function label(parent, text, x, y, font, list)
    local item = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    item:SetPoint("TOPLEFT", x, y)
    item:SetText(text)
    list[#list + 1] = item
    return item
end

local function check(parent, text, key, x, y, list, officerOnly)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(22, 22)
    button:SetPoint("TOPLEFT", x, y)
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
    button.border = {}
    for index = 1, 4 do
        button.border[index] = button:CreateTexture(nil, "OVERLAY")
        button.border[index]:SetColorTexture(0.16, 0.25, 0.34, 1)
    end
    button.border[1]:SetPoint("TOPLEFT"); button.border[1]:SetPoint("TOPRIGHT"); button.border[1]:SetHeight(1)
    button.border[2]:SetPoint("BOTTOMLEFT"); button.border[2]:SetPoint("BOTTOMRIGHT"); button.border[2]:SetHeight(1)
    button.border[3]:SetPoint("TOPLEFT"); button.border[3]:SetPoint("BOTTOMLEFT"); button.border[3]:SetWidth(1)
    button.border[4]:SetPoint("TOPRIGHT"); button.border[4]:SetPoint("BOTTOMRIGHT"); button.border[4]:SetWidth(1)
    button.mark = button:CreateTexture(nil, "OVERLAY")
    button.mark:SetTexture("Interface/Buttons/UI-CheckBox-Check")
    button.mark:SetSize(17, 17)
    button.mark:SetPoint("CENTER")
    button.mark:SetVertexColor(0.25, 0.68, 1, 1)
    button.text = label(parent, text, x + 26, y - 2, "GameFontNormal", list)
    list[#list + 1] = button
    local function update()
        local enabled = GD:GetSetting(key)
        button.mark:SetShown(enabled)
        button:GetNormalTexture():SetVertexColor(0.075, 0.09, 0.12, 1)
        for _, edge in ipairs(button.border) do edge:SetColorTexture(0.16, 0.25, 0.34, 1) end
        local permitted = not officerOnly or GD:CanManage()
        if key == "feature:DKP" then permitted = GD:CanConfigureDKP() end
        button:SetEnabled(permitted)
        button.text:SetTextColor(permitted and 0.88 or 0.38, permitted and 0.84 or 0.40, permitted and 0.73 or 0.45)
    end
    button:SetScript("OnClick", function()
        if key == "feature:DKP" and GD:IsDKPEnabled() then
            local bucket = GD.bucket
            GD:ConfirmAction("Disable guild DKP?", "Hide DKP for this guild. Saved balances and history will be kept.", function()
                if GD.bucket ~= bucket then return false, "Your guild changed. Open Guild Settings again." end
                return GD:SetDKPEnabled(false)
            end, "Disable")
            return
        end
        GD:SetSetting(key, not GD:GetSetting(key))
        update()
    end)
    button.update = update
    return button
end

local function makeButton(parent, text, width, x, y, callback, list)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button.GuildDBPrimary = text == "Re-sync now"
    if GD.StyleButton then GD:StyleButton(button, button.GuildDBPrimary and "primary" or nil) end
    button:SetSize(width, 26)
    button:SetPoint("TOPLEFT", x, y)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    list[#list + 1] = button
    return button
end

local function build(parent)
    local list = {}
    GD.settingsControls = list
    local personalPanel = CreateFrame("Frame", nil, parent)
    personalPanel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -40)
    personalPanel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    list[#list + 1] = personalPanel
    local appearancePanel = CreateFrame("Frame", nil, parent)
    appearancePanel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -40)
    appearancePanel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    appearancePanel:Hide()
    list[#list + 1] = appearancePanel
    local officerPanel = CreateFrame("Frame", nil, parent)
    officerPanel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -40)
    officerPanel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    officerPanel:Hide()
    list[#list + 1] = officerPanel
    local pvpPanel = CreateFrame("Frame", nil, parent)
    pvpPanel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -40)
    pvpPanel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    pvpPanel:Hide()
    list[#list + 1] = pvpPanel
    local gmPanel = CreateFrame("Frame", nil, parent)
    gmPanel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -40)
    gmPanel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    gmPanel:Hide()
    list[#list + 1] = gmPanel
    GD.settingsPanels = { personalPanel, appearancePanel, officerPanel, pvpPanel, gmPanel }

    local appearanceTab
    local officerTab
    local pvpTab
    local personalTab
    local gmTab
    local function selectSettingsSection(section)
        local canManage = GD:CanManage()
        if (section == "officer" or section == "pvp") and not canManage then section = "personal" end
        local canManageInvite = GD.CanManageGuildInvite and GD:CanManageGuildInvite()
        if section == "gm" and not canManageInvite then section = "personal" end
        GD.settingsSection = section
        personalPanel:SetShown(section == "personal")
        appearancePanel:SetShown(section == "appearance")
        officerPanel:SetShown(section == "officer")
        pvpPanel:SetShown(section == "pvp")
        gmPanel:SetShown(section == "gm")
        officerTab:SetShown(canManage)
        pvpTab:SetShown(canManage)
        gmTab:SetShown(canManageInvite == true)
        GD:StyleButton(personalTab, section == "personal" and "primary" or nil)
        GD:StyleButton(appearanceTab, section == "appearance" and "primary" or nil)
        GD:StyleButton(officerTab, section == "officer" and "primary" or nil)
        GD:StyleButton(pvpTab, section == "pvp" and "primary" or nil)
        GD:StyleButton(gmTab, section == "gm" and "primary" or nil)
    end
    personalTab = makeButton(parent, "Personal", 88, 12, -8, function()
        selectSettingsSection("personal")
    end, list)
    personalTab.GuildDBSettingsTab = true
    appearanceTab = makeButton(parent, "Appearance", 98, 108, -8, function()
        selectSettingsSection("appearance")
    end, list)
    appearanceTab.GuildDBSettingsTab = true
    officerTab = makeButton(parent, "Officer", 82, 214, -8, function()
        selectSettingsSection("officer")
    end, list)
    officerTab.GuildDBSettingsTab = true
    pvpTab = makeButton(parent, "PvP", 64, 302, -8, function()
        selectSettingsSection("pvp")
    end, list)
    pvpTab.GuildDBSettingsTab = true
    gmTab = makeButton(parent, "GM", 64, 374, -8, function()
        selectSettingsSection("gm")
    end, list)
    gmTab.GuildDBSettingsTab = true
    GD.RefreshSettingsSection = function()
        selectSettingsSection(GD.settingsSection or "personal")
    end
    selectSettingsSection(GD.settingsSection or "personal")

    label(personalPanel, "Personal", 12, -10, "GameFontNormalLarge", list)
    check(personalPanel, "Show online members only", "onlineOnly", 12, -42, list)
    check(personalPanel, "Show GuildDB popups", "popups", 12, -72, list)
    check(personalPanel, "Guild chat ding for level milestones", "levelGuildChat", 12, -102, list)
    check(personalPanel, "Share my location with GuildDB members", "shareMapLocation", 12, -132, list)
    check(personalPanel, "Show minimap button", "showMinimapButton", 12, -162, list)
    check(personalPanel, "15-minute raid/event reminders (Going or Maybe)", "raidReminders", 12, -192, list)
    label(personalPanel, "Window scale", 12, -238, "GameFontNormal", list)
    local scaleText = label(personalPanel, "", 105, -238, "GameFontHighlight", list)
    local function updateScale()
        scaleText:SetText(("%d%%"):format(math.floor((GD:GetSetting("scale") or 1) * 100 + 0.5)))
    end
    local scaleDown = makeButton(personalPanel, "-", 32, 160, -230, function()
        GD:SetSetting("scale", math.max(0.8, math.floor(((GD:GetSetting("scale") or 1) - 0.1) * 10 + 0.5) / 10))
        updateScale()
    end, list)
    local scaleUp = makeButton(personalPanel, "+", 32, 200, -230, function()
        GD:SetSetting("scale", math.min(1.2, math.floor(((GD:GetSetting("scale") or 1) + 0.1) * 10 + 0.5) / 10))
        updateScale()
    end, list)
    scaleDown:GetFontString():SetFontObject("GameFontNormalLarge")
    scaleUp:GetFontString():SetFontObject("GameFontNormalLarge")
    updateScale()

    local openAppearanceMenu
    label(appearancePanel, "Accent color", 12, -14, "GameFontNormal", list)
    local choices = GD.GetAccentChoices and GD:GetAccentChoices() or {}
    local accentText
    accentText = makeButton(appearancePanel, "", 200, 12, -38, function()
        openAppearanceMenu(accentText, "accentColor")
    end, list)
    local accentSwatch = appearancePanel:CreateTexture(nil, "ARTWORK")
    accentSwatch:SetSize(18, 18)
    accentSwatch:SetPoint("LEFT", accentText, "RIGHT", 10, 0)
    list[#list + 1] = accentSwatch
    local function updateAccent()
        local index = GD:GetSetting("accentColor") or 1
        local color = choices[index] or choices[1] or { 0.20, 0.62, 0.98 }
        local names = { "Class color", "Blue", "Violet", "Teal", "Coral", "Amber", "Rose" }
        local className
        if UnitClass then local name = UnitClass("player"); className = name end
        accentText:SetText((index == 1 and ("Class color (" .. (className or "Class") .. ")") or names[index] or names[1]) .. "  v")
        accentSwatch:SetColorTexture(color[1], color[2], color[3], 1)
    end
    label(appearancePanel, "Theme", 280, -14, "GameFontNormal", list)
    local themeChoices = GD.GetThemeChoices and GD:GetThemeChoices() or {}
    local themeText
    themeText = makeButton(appearancePanel, "", 200, 280, -38, function()
        openAppearanceMenu(themeText, "uiTheme")
    end, list)
    local themeSwatch = appearancePanel:CreateTexture(nil, "ARTWORK")
    themeSwatch:SetSize(30, 18)
    themeSwatch:SetPoint("LEFT", themeText, "RIGHT", 10, 0)
    list[#list + 1] = themeSwatch
    local function updateTheme()
        local index = GD:GetSetting("uiTheme") or 1
        local theme = themeChoices[index] or themeChoices[1]
        themeText:SetText((theme and theme.name or "Midnight") .. "  v")
        if theme then themeSwatch:SetColorTexture(theme.panel[1], theme.panel[2], theme.panel[3], 1) end
    end
    GD.RefreshSettingsAppearance = function()
        updateAccent()
        updateTheme()
        GD:StyleButton(personalTab, GD.settingsSection == "personal" and "primary" or nil)
        GD:StyleButton(appearanceTab, GD.settingsSection == "appearance" and "primary" or nil)
        GD:StyleButton(officerTab, GD.settingsSection == "officer" and "primary" or nil)
        GD:StyleButton(pvpTab, GD.settingsSection == "pvp" and "primary" or nil)
        GD:StyleButton(gmTab, GD.settingsSection == "gm" and "primary" or nil)
        for _, item in ipairs(list) do
            if item.mark and item.mark.SetVertexColor then
                local color = choices[GD:GetSetting("accentColor") or 1] or choices[1]
                item.mark:SetVertexColor(color[1], color[2], color[3], 1)
            end
            if item.GetObjectType and item:GetObjectType() == "Button" and not item.GuildDBSettingsTab and GD.StyleButton then
                GD:StyleButton(item, (item.GuildDBPrimary or item.GuildDBAccent) and "primary" or nil)
            end
        end
    end
    local menu = CreateFrame("Frame", "GuildDBAppearanceMenu", UIParent, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    menu.rows = {}
    menu:Hide()
    UISpecialFrames = UISpecialFrames or {}
    table.insert(UISpecialFrames, "GuildDBAppearanceMenu")
    appearancePanel:HookScript("OnHide", function() menu:Hide() end)
    menu:SetScript("OnUpdate", function()
        if IsMouseButtonDown and MouseIsOver and IsMouseButtonDown("LeftButton")
            and not MouseIsOver(menu) and not MouseIsOver(menu.owner) then menu:Hide() end
    end)
    openAppearanceMenu = function(control, key)
        if menu:IsShown() and menu.owner == control then menu:Hide(); return end
        menu.owner = control
        local accent = key == "accentColor"
        local options = accent and choices or themeChoices
        local names = { "Class color", "Blue", "Violet", "Teal", "Coral", "Amber", "Rose" }
        menu:SetSize(control:GetWidth(), #options * 28 + 8)
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", control, "BOTTOMLEFT", 0, -3)
        GD:StyleSurface(menu)
        for index, option in ipairs(options) do
            local row = menu.rows[index]
            if not row then
                row = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
                row.swatch = row:CreateTexture(nil, "OVERLAY")
                row.swatch:SetSize(14, 14)
                row.swatch:SetPoint("LEFT", 8, 0)
                menu.rows[index] = row
            end
            local selectedIndex = index
            row:SetSize(menu:GetWidth() - 8, 26)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 4, -4 - (index - 1) * 28)
            row:SetText(accent and names[index] or option.name)
            local color = accent and option or option.panel
            row.swatch:SetColorTexture(color[1], color[2], color[3], 1)
            GD:StyleButton(row, GD:GetSetting(key) == index and "primary" or nil)
            row:SetScript("OnClick", function()
                menu:Hide()
                GD:SetSetting(key, selectedIndex)
                updateAccent()
                updateTheme()
            end)
            row:Show()
        end
        for index = #options + 1, #menu.rows do menu.rows[index]:Hide() end
        menu:Show()
    end
    updateAccent()
    updateTheme()
    makeButton(appearancePanel, "Reset Appearance", 156, 12, -92, function()
        menu:Hide()
        GD:ResetAppearance()
    end, list)
    label(personalPanel, "Data", 12, -280, "GameFontNormalLarge", list)
    makeButton(personalPanel, "Re-sync now", 120, 12, -310, function()
        local _, message = GD:RequestSync()
        print("GuildDB: " .. tostring(message))
    end, list)
    local records = 0
    for key, bucket in pairs(GD.bucket or {}) do
        if key ~= "pvpSeason" and key ~= "guildSettings" and type(bucket) == "table" then
            for _ in pairs(bucket) do records = records + 1 end
        end
    end
    label(personalPanel, ("Stored records: %d"):format(records), 12, -350, "GameFontDisableSmall", list)
    local featureStatus = label(personalPanel, "", 12, -372, "GameFontDisableSmall", list)
    featureStatus.update = function()
        featureStatus:SetText(not GD.guildName and "Guild tabs: join a guild to sync." or
            (GD:HasGuildFeatureSettings() and "Guild tabs: saved guild settings loaded." or "Guild tabs: waiting for guild settings..."))
    end

    label(officerPanel, "Officer settings", 12, -10, "GameFontNormalLarge", list)
    label(officerPanel, "Feature switches (guild-wide; GM or rank 1)", 12, -38, "GameFontDisableSmall", list)
    local tabs = {}
    for _, tab in ipairs(GD.tabs or {}) do
        if tab ~= "Settings" and tab ~= "Profiles" then tabs[#tabs + 1] = tab end
    end
    local split = math.ceil(#tabs / 2)
    for index, tab in ipairs(tabs) do
        local column = index > split and 1 or 0
        local row = index > split and index - split or index
        check(officerPanel, tab == "Events" and "Raid Info" or tab == "DKP" and "DKP (testing)" or tab, "feature:" .. tab, 12 + column * 180, -70 - (row - 1) * 30, list, true)
    end
    label(officerPanel, GD:CanManage() and "Online users update now; offline users on next sync." or "Only the guild leader or rank 1 can change these switches.", 12, -70 - (split + 1) * 30, "GameFontDisableSmall", list)

    label(gmPanel, "Guild Discord invite", 12, -10, "GameFontNormalLarge", list)
    local inviteHelp = label(gmPanel, "Paste your Discord server invite below. Members can copy it using Join Guild Discord in the header.", 12, -42, "GameFontHighlight", list)
    inviteHelp:SetWidth(400)
    local inviteInput = CreateFrame("EditBox", nil, gmPanel, "BackdropTemplate")
    inviteInput:SetSize(400, 28)
    inviteInput:SetPoint("TOPLEFT", 12, -90)
    inviteInput:SetAutoFocus(false)
    inviteInput:SetMaxLetters(200)
    GD:StyleEditBox(inviteInput)
    local inviteDirty, loadingInvite, inviteBucket = false, false, GD.bucket
    inviteInput:SetScript("OnTextChanged", function() if not loadingInvite then inviteDirty = true end end)
    inviteInput:SetScript("OnEscapePressed", function(input) input:ClearFocus(); GD:CloseWindowsOnEscape() end)
    list[#list + 1] = inviteInput
    local inviteStatus = label(gmPanel, "Only the guild master can change this link. Leave blank and save to remove it.", 12, -172, "GameFontDisableSmall", list)
    inviteStatus:SetWidth(400)
    local saveInvite = makeButton(gmPanel, "Save Discord invite", 160, 12, -132, function()
        if inviteBucket ~= GD.bucket then return end
        local ok, message = GD:SetGuildDiscordInvite(inviteInput:GetText())
        if ok then
            inviteDirty, loadingInvite = false, true
            inviteInput:SetText(GD:GetGuildDiscordInvite())
            loadingInvite = false
            inviteInput:ClearFocus()
        end
        inviteStatus:SetText(message or "")
    end, list)
    gmPanel.update = function()
        if inviteBucket ~= GD.bucket then inviteDirty = false; inviteBucket = GD.bucket end
        if not inviteDirty then
            loadingInvite = true
            inviteInput:SetText(GD.GetGuildDiscordInvite and GD:GetGuildDiscordInvite() or "")
            loadingInvite = false
        end
        local permitted = GD.CanManageGuildInvite and GD:CanManageGuildInvite()
        inviteInput:SetEnabled(permitted == true)
        saveInvite:SetEnabled(permitted == true)
    end

    label(pvpPanel, "PvP seasonal ranks", 12, -10, "GameFontNormalLarge", list)
    label(pvpPanel, "Rank uses seasonal kills; points stay separate. Rank is not shown in All-time view.", 12, -38, "GameFontDisableSmall", list)
    label(pvpPanel, "Tier", 18, -76, "GameFontNormal", list)
    label(pvpPanel, "Minimum seasonal kills", 150, -76, "GameFontNormal", list)
    local tierNames = { "Silver", "Gold", "Platinum", "Elite" }
    local rankInputs = {}
    local loadingRankInputs = false
    local rankInputsDirty = false
    for index, tier in ipairs(tierNames) do
        local y = -106 - (index - 1) * 32
        label(pvpPanel, tier, 18, y, "GameFontHighlight", list)
        local input = CreateFrame("EditBox", nil, pvpPanel, "BackdropTemplate")
        input:SetSize(80, 24)
        input:SetPoint("TOPLEFT", 150, y + 5)
        input:SetAutoFocus(false)
        input:SetNumeric(true)
        input:SetMaxLetters(7)
        input:SetJustifyH("CENTER")
        if GD.StyleEditBox then GD:StyleEditBox(input) end
        input:SetScript("OnMouseDown", function(self) self:SetFocus() end)
        input:SetScript("OnTextChanged", function()
            if not loadingRankInputs then rankInputsDirty = true end
        end)
        list[#list + 1] = input
        rankInputs[index] = input
    end
    local rankStatus = label(pvpPanel, "", 188, -258, "GameFontDisableSmall", list)
    local function savePvpRankThresholds()
        local values = {}
        for index, input in ipairs(rankInputs) do values[index] = tonumber(input:GetText()) end
        local ok, message = GD:SetPvPRankThresholds(values)
        print("GuildDB: " .. tostring(message))
        if ok then
            local thresholds = GD:GetPvPRankThresholds()
            loadingRankInputs = true
            for index, input in ipairs(rankInputs) do input:SetText(tostring(thresholds[index])) end
            loadingRankInputs = false
            rankInputsDirty = false
        end
        rankStatus:SetText(message or "")
        return ok
    end
    local savePvpRanks = makeButton(pvpPanel, "Save rank thresholds", 156, 18, -250, savePvpRankThresholds, list)
    local rankPermission = label(pvpPanel, "Only the guild leader or rank 1 can edit these guild-wide thresholds.", 18, -286, "GameFontDisableSmall", list)
    local function updatePvpRanks()
        if not rankInputsDirty then
            local thresholds = GD:GetPvPRankThresholds()
            loadingRankInputs = true
            for index, input in ipairs(rankInputs) do input:SetText(tostring(thresholds[index])) end
            loadingRankInputs = false
        end
        local permitted = GD:CanManage()
        for _, input in ipairs(rankInputs) do input:SetEnabled(permitted) end
        savePvpRanks:SetShown(permitted)
        rankPermission:SetShown(not permitted)
    end
    pvpPanel.update = updatePvpRanks

    makeButton(personalPanel, "Reset personal settings", 172, 12, -390, function()
        GD:ConfirmAction("Reset personal settings?", "Restore all your personal preferences, including appearance, scale, popups, minimap and location sharing, to their defaults.", function()
            for key, value in pairs(defaults) do GD:SetSetting(key, value) end
            updateScale()
            updateAccent()
            updateTheme()
            GD:RefreshUI()
            return true, "Personal settings reset."
        end, "Reset")
    end, list)
    for _, item in ipairs(list) do
        if item.update then item.update() end
    end
end

function GD:ShowSettingsControls(parent)
    if not self.settingsControls then build(parent) end
    for _, item in ipairs(self.settingsControls) do
        item:Show()
        if item.update then item.update() end
    end
    if self.RefreshSettingsSection then self.RefreshSettingsSection() end
end

function GD:HideSettingsControls()
    for _, item in ipairs(self.settingsControls or {}) do item:Hide() end
end

GD:RegisterTab("Settings", function()
    return "Personal preferences and officer feature visibility."
end)

-- Personal preferences plus per-guild, officer-managed feature visibility.
local _, GD = ...

local defaults = { onlineOnly = true, scale = 1, popups = true, levelGuildChat = false, shareMapLocation = false, accentColor = 1 }

local function settings()
    if type(GDB) ~= "table" then GDB = {} end
    if type(GDB.settings) ~= "table" then GDB.settings = {} end
    for key, value in pairs(defaults) do
        if GDB.settings[key] == nil then GDB.settings[key] = value end
    end
    if type(GDB.settings.features) ~= "table" then GDB.settings.features = {} end
    return GDB.settings
end

function GD:GetSetting(key)
    local db = settings()
    if key:sub(1, 8) == "feature:" then
        local tab = key:sub(9)
        local guildSettings = self.bucket and self.bucket.guildSettings
        if tab == "Home" and guildSettings and guildSettings.features
            and guildSettings.features.Home == nil and guildSettings.features.Announcements ~= nil then
            return guildSettings.features.Announcements ~= false
        end
        if guildSettings and guildSettings.features and guildSettings.features[tab] ~= nil then
            return guildSettings.features[tab] ~= false
        end
        return true
    end
    return db[key]
end

function GD:SetSetting(key, value)
    local db = settings()
    if key:sub(1, 8) == "feature:" then
        if not self:CanManage() or not self.bucket then return end
        local config = self.bucket.guildSettings or { features = {} }
        config.features = config.features or {}
        config.ts = time()
        config.by = UnitName and UnitName("player") or "Guild officer"
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
    if self.RefreshUI then self:RefreshUI() end
end

local function normalizeName(name)
    return tostring(name or ""):lower():gsub("[%s%-]", "")
end

local function sameGuildName(left, right)
    if normalizeName(left) == normalizeName(right) then return true end
    local leftFirst = tostring(left or ""):match("^([^%s%-]+)")
    local rightFirst = tostring(right or ""):match("^([^%s%-]+)")
    return leftFirst and rightFirst and leftFirst:lower() == rightFirst:lower() or false
end

local function isGuildOfficer(name)
    if not name or not GetNumGuildMembers or not GetGuildRosterInfo then return false end
    for index = 1, GetNumGuildMembers() do
        local rosterName, _, rankIndex = GetGuildRosterInfo(index)
        if rosterName and sameGuildName(rosterName, name) then
            return tonumber(rankIndex) ~= nil and tonumber(rankIndex) <= 1
        end
    end
    return false
end

GD:RegisterRecordHandler("F", function(id, ts, author, content, sender)
    if id ~= "features" or not GD.bucket or not isGuildOfficer(sender) or not isGuildOfficer(author) then return end
    if #content > 1000 then return end
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
    GD.bucket.guildSettings = { features = features, ts = ts, by = author }
    if GD.RefreshUI then GD:RefreshUI() end
end)

GD:RegisterHistoryProvider(function()
    if not GD:CanManage() then return end
    local config = GD.bucket and GD.bucket.guildSettings
    if not config or not config.features or not config.ts or config.ts <= 0 then return end
    local lines = {}
    for _, tab in ipairs(GD.tabs or {}) do
        if tab ~= "Settings" then
            lines[#lines + 1] = tab .. "\t" .. (config.features[tab] and "1" or "0")
        end
    end
    GD:SendRecord("F", "features", config.ts, config.by or "Guild officer", table.concat(lines, "\n"))
end, false)

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
        button:SetEnabled(permitted)
        button.text:SetTextColor(permitted and 0.88 or 0.38, permitted and 0.84 or 0.40, permitted and 0.73 or 0.45)
    end
    button:SetScript("OnClick", function()
        GD:SetSetting(key, not GD:GetSetting(key))
        update()
    end)
    button.update = update
    return button
end

local function makeButton(parent, text, width, x, y, callback, list)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    if GD.StyleButton then GD:StyleButton(button, text == "Re-sync now" and "primary" or nil) end
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
    label(parent, "Personal", 12, -10, "GameFontNormalLarge", list)
    check(parent, "Show online members only", "onlineOnly", 12, -42, list)
    check(parent, "Show GuildDB popups", "popups", 12, -72, list)
    check(parent, "Guild chat ding for level milestones", "levelGuildChat", 12, -102, list)
    check(parent, "Share my location with GuildDB members", "shareMapLocation", 12, -132, list)
    label(parent, "Window scale", 12, -178, "GameFontNormal", list)
    local scaleText = label(parent, "", 105, -178, "GameFontHighlight", list)
    local function updateScale()
        scaleText:SetText(("%d%%"):format(math.floor((GD:GetSetting("scale") or 1) * 100 + 0.5)))
    end
    local scaleDown = makeButton(parent, "-", 32, 160, -170, function()
        GD:SetSetting("scale", math.max(0.8, math.floor(((GD:GetSetting("scale") or 1) - 0.1) * 10 + 0.5) / 10))
        updateScale()
    end, list)
    local scaleUp = makeButton(parent, "+", 32, 200, -170, function()
        GD:SetSetting("scale", math.min(1.2, math.floor(((GD:GetSetting("scale") or 1) + 0.1) * 10 + 0.5) / 10))
        updateScale()
    end, list)
    scaleDown:GetFontString():SetFontObject("GameFontNormalLarge")
    scaleUp:GetFontString():SetFontObject("GameFontNormalLarge")
    updateScale()

    label(parent, "Appearance", 12, -218, "GameFontNormalLarge", list)
    label(parent, "Accent color", 12, -248, "GameFontNormal", list)
    local choices = GD.GetAccentChoices and GD:GetAccentChoices() or {}
    local accentText = label(parent, "", 112, -248, "GameFontHighlight", list)
    local accentSwatch = parent:CreateTexture(nil, "ARTWORK")
    accentSwatch:SetSize(18, 18)
    accentSwatch:SetPoint("TOPLEFT", 282, -244)
    list[#list + 1] = accentSwatch
    local function updateAccent()
        local index = GD:GetSetting("accentColor") or 1
        local color = choices[index] or choices[1] or { 0.20, 0.62, 0.98 }
        local names = { "Class color", "Blue", "Violet", "Teal", "Coral", "Amber", "Rose" }
        local className
        if UnitClass then local name = UnitClass("player"); className = name end
        accentText:SetText(index == 1 and ("Class color (" .. (className or "Unknown") .. ")") or names[index] or names[1])
        accentSwatch:SetColorTexture(color[1], color[2], color[3], 1)
    end
    GD.RefreshSettingsAppearance = function()
        updateAccent()
        for _, item in ipairs(list) do
            if item.mark and item.mark.SetVertexColor then
                local color = choices[GD:GetSetting("accentColor") or 1] or choices[1]
                item.mark:SetVertexColor(color[1], color[2], color[3], 1)
            end
            if item.GuildDBAccent and GD.StyleButton then GD:StyleButton(item, "primary") end
        end
    end
    local accentPrevious = makeButton(parent, "<", 28, 220, -240, function()
        GD:SetSetting("accentColor", ((GD:GetSetting("accentColor") or 1) - 2) % #choices + 1)
        updateAccent()
    end, list)
    local accentNext = makeButton(parent, ">", 28, 244, -240, function()
        GD:SetSetting("accentColor", (GD:GetSetting("accentColor") or 1) % #choices + 1)
        updateAccent()
    end, list)
    accentPrevious.GuildDBAccent, accentNext.GuildDBAccent = true, true
    updateAccent()

    label(parent, "Data", 12, -290, "GameFontNormalLarge", list)
    makeButton(parent, "Re-sync now", 120, 12, -320, function()
        local _, message = GD:RequestSync()
        print("GuildDB: " .. tostring(message))
    end, list)
    local records = 0
    for key, bucket in pairs(GD.bucket or {}) do
        if key ~= "pvpSeason" and key ~= "guildSettings" and type(bucket) == "table" then
            for _ in pairs(bucket) do records = records + 1 end
        end
    end
    label(parent, ("Stored records: %d"):format(records), 12, -360, "GameFontDisableSmall", list)

    label(parent, "GM Settings", 350, -10, "GameFontNormalLarge", list)
    label(parent, "Feature switches (guild-wide; GM or rank 1)", 350, -38, "GameFontDisableSmall", list)
    local tabs = {}
    for _, tab in ipairs(GD.tabs or {}) do
        if tab ~= "Settings" then tabs[#tabs + 1] = tab end
    end
    local split = math.ceil(#tabs / 2)
    for index, tab in ipairs(tabs) do
        local column = index > split and 1 or 0
        local row = index > split and index - split or index
        check(parent, tab == "Events" and "Raid Info" or tab, "feature:" .. tab, 350 + column * 155, -70 - (row - 1) * 30, list, true)
    end
    label(parent, GD:CanManage() and "Online users update now; offline users on next sync." or "Only the guild leader or rank 1 can change these switches.", 350, -70 - (split + 1) * 30, "GameFontDisableSmall", list)
    local motdRanks = makeButton(parent, "MOTD editor ranks", 160, 350, -108 - (split + 1) * 30, function()
        GD:OpenHomeRoleSettings()
    end, list)
    motdRanks.update = function()
        motdRanks:SetEnabled(GD.bucket ~= nil and GD:CanManage())
    end

    makeButton(parent, "Reset personal settings", 172, 12, -400, function()
        for key, value in pairs(defaults) do GD:SetSetting(key, value) end
        updateScale()
        updateAccent()
        GD:RefreshUI()
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
end

function GD:HideSettingsControls()
    for _, item in ipairs(self.settingsControls or {}) do item:Hide() end
end

GD:RegisterTab("Settings", function()
    return "Personal preferences and officer feature visibility."
end)

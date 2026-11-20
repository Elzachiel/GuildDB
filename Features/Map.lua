-- Guild-wide, opt-in location sharing and World Map pins.
local _, GH = ...

local REPORT_TTL = 45
local SEND_INTERVAL = 15
local lastSent = 0
local elapsedSincePrune = 0
local lastLocalStatus = "Waiting for a map position"
local lastLocalPosition
GH.mapReports = GH.mapReports or {}

local function unitLocation()
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then return end
    if IsInInstance then
        local inside = IsInInstance()
        if inside then return end
    end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    if not position then return end
    local x, y
    if position.GetXY then x, y = position:GetXY() else x, y = position.x, position.y end
    if not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return end
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    local zone = info and info.name or (GetZoneText and GetZoneText()) or "Unknown zone"
    return mapID, x, y, zone
end

local function refreshMapPins()
    if GH.mapDataProvider and WorldMapFrame and WorldMapFrame:IsShown() then
        GH.mapDataProvider:RefreshAllData()
    end
end

local function updateUI()
    if GH.RefreshUI then GH:RefreshUI() end
    refreshMapPins()
end

GH:RegisterRecordHandler("ML", function(id, timestamp, author, content, sender)
    local function reject(reason)
        GH.mapRejectReason = reason
    end
    if not GH.bucket or not sender then reject("no guild bucket or sender"); return end
    local mapID, x, y, zone = content:match("^(%d+)|([%d%.]+)|([%d%.]+)|(.*)$")
    mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
    if not mapID or not x or not y or not zone then reject("malformed location payload"); return end
    if x < 0 or x > 1 or y < 0 or y > 1 or #zone > 80 then reject("coordinates or zone out of range"); return end
    local senderName = (sender:match("^([^-]+)") or sender):lower()
    local authorName = (author:match("^([^-]+)") or author):lower()
    if senderName ~= authorName then reject("sender name did not match payload author"); return end
    GH.mapValidReports = (GH.mapValidReports or 0) + 1
    GH.mapRejectReason = nil
    GH.mapReports[senderName] = {
        name = sender, mapID = mapID, x = x, y = y, zone = zone,
        seen = GetTime and GetTime() or 0,
    }
    updateUI()
end)

local function sendLocation()
    if not GH.bucket or not GH:GetSetting("shareMapLocation") then return end
    local mapID, x, y, zone = unitLocation()
    if not mapID then
        lastLocalStatus = IsInInstance and IsInInstance() and "Location sharing pauses in instances" or "The client did not return a map position"
        return
    end
    lastLocalStatus = "Position available"
    lastLocalPosition = { mapID = mapID, x = x, y = y, zone = zone }
    local author = UnitName and UnitName("player") or ""
    if author == "" then return end
    local payload = table.concat({
        "ML", "loc", time(), GH:Encode(author),
        table.concat({ mapID, ("%.4f"):format(x), ("%.4f"):format(y), GH:Encode(zone) }, "|"),
    }, "|")
    GH:Enqueue(payload)
    lastSent = GetTime and GetTime() or 0
    if GH.activeTab == "Map" and GH.RefreshUI then GH:RefreshUI() end
end

function GH:MapUpdate(now, elapsed)
    if not now then return end
    if self.bucket and self:GetSetting("shareMapLocation") and now - lastSent >= SEND_INTERVAL then
        sendLocation()
    end
    elapsedSincePrune = elapsedSincePrune + (tonumber(elapsed) or 0)
    if elapsedSincePrune < 2 then return end
    elapsedSincePrune = 0
    local changed = false
    for name, report in pairs(self.mapReports) do
        if now - (report.seen or 0) > REPORT_TTL then
            self.mapReports[name] = nil
            changed = true
        end
    end
    if changed then updateUI() end
end

function GH:GetMapReports()
    local reports = {}
    local now = GetTime and GetTime() or 0
    for _, report in pairs(self.mapReports or {}) do
        if now - (report.seen or 0) <= REPORT_TTL then reports[#reports + 1] = report end
    end
    table.sort(reports, function(a, b) return a.name:lower() < b.name:lower() end)
    return reports
end

local function setWaypoint(report)
    if not report or not UiMapPoint or not UiMapPoint.CreateFromCoordinates or not C_Map or not C_Map.SetUserWaypoint then
        print("Guild Hall: Waypoints are unavailable in this client.")
        return
    end
    local point = UiMapPoint.CreateFromCoordinates(report.mapID, report.x, report.y)
    if C_Map.SetUserWaypoint(point) then
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        if C_Map.OpenWorldMap then C_Map.OpenWorldMap(report.mapID) end
        print(("Guild Hall: Waypoint set to %s in %s."):format(report.name, report.zone))
    else
        print("Guild Hall: The client could not set that waypoint.")
    end
end

GH:RegisterCommand("map", function(rest)
    local action, target = (rest or ""):match("^(%S+)%s*(.-)$")
    action = (action or ""):lower()
    if action == "waypoint" and target ~= "" then
        local wanted = target:lower()
        for _, report in ipairs(GH:GetMapReports()) do
            local shortName = (report.name:match("^([^-]+)") or report.name):lower()
            if shortName == wanted then setWaypoint(report); return end
        end
        print("Guild Hall: No fresh location report found for " .. target .. ".")
    elseif action == "clear" then
        if C_Map and C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
    else
        print("Guild Hall: use /gh map waypoint CharacterName or /gh map clear.")
    end
end)

local function mapTabText()
    if not GH.guildName then return "Join a guild to share and view member locations." end
    local reports = GH:GetMapReports()
    local sharing = GH:GetSetting("shareMapLocation") and "On" or "Off"
    local positionText = lastLocalPosition
        and ("%s (%.1f, %.1f)"):format(lastLocalPosition.zone, lastLocalPosition.x * 100, lastLocalPosition.y * 100)
        or lastLocalStatus
    local lastSend = GH.lastAddonSendByKind and GH.lastAddonSendByKind.ML
    local sendText = "No outbound addon message recorded yet"
    if lastSend then
        local age = math.max(0, math.floor((GetTime and GetTime() or 0) - (lastSend.at or 0)))
        sendText = ("Last %s message: %s, result %s, %ds ago"):format(
            tostring(lastSend.kind), lastSend.succeeded and "accepted" or "failed",
            tostring(lastSend.error or lastSend.result or "unknown"), age)
    end
    local inboundAge = GH.mapLastInboundAt and math.max(0, math.floor((GetTime and GetTime() or 0) - GH.mapLastInboundAt))
    local inboundText = ("Location packets received: %d; valid reports: %d"):format(
        GH.mapInboundPackets or 0, GH.mapValidReports or 0)
    if inboundAge then
        inboundText = inboundText .. ("; last from %s, %ds ago"):format(tostring(GH.mapLastInboundSender or "unknown"), inboundAge)
    end
    if GH.mapRejectReason then inboundText = inboundText .. "; last rejected: " .. GH.mapRejectReason end
    if #reports == 0 then
        return table.concat({
            "Guild member map", "",
            "No fresh reports from other GuildHall users.",
            "Your sharing: " .. sharing .. "  ·  Your position: " .. positionText,
            sendText,
            inboundText,
            "Reports expire after 45 seconds and pause in instances.",
        }, "\n\n")
    end
    local lines = { "Guild member locations (reports expire after 45 seconds):", "" }
    for _, report in ipairs(reports) do
        local age = math.max(0, math.floor((GetTime and GetTime() or 0) - report.seen))
        lines[#lines + 1] = ("%s  ·  %s  ·  %.1f, %.1f  ·  %ds old"):format(
            report.name, report.zone, report.x * 100, report.y * 100, age)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Your sharing: " .. sharing .. "  ·  Your position: " .. positionText
    lines[#lines + 1] = sendText
    lines[#lines + 1] = inboundText
    lines[#lines + 1] = "Set a navigation waypoint: /gh map waypoint CharacterName"
    return table.concat(lines, "\n")
end
GH:RegisterTab("Map", mapTabText)

GuildHallMapPinMixin = {}

local function attachMapProvider()
    if not (MapCanvasDataProviderMixin and MapCanvasPinMixin and CreateFromMixins and WorldMapFrame and WorldMapFrame.AddDataProvider) then return end
    if GH.mapDataProvider then return end
    GuildHallMapPinMixin = CreateFromMixins(MapCanvasPinMixin)
    GuildHallMapPinMixin.OnLoad = function(self)
        self:SetSize(22, 22)
        self.dot = self:CreateTexture(nil, "ARTWORK")
        self.dot:SetAllPoints()
        self.dot:SetTexture("Interface/TargetingFrame/UI-RaidTargetingIcon_1")
        self.text = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        self.text:SetPoint("BOTTOM", self, "TOP", 0, 2)
        self.text:SetTextColor(1, 1, 1)
        self:EnableMouse(true)
        self:SetScript("OnEnter", function(pin)
            GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
            GameTooltip:SetText(pin.memberName or "Guild member")
            GameTooltip:AddLine(pin.zone or "", 0.8, 0.85, 0.9)
            GameTooltip:AddLine(("%.1f, %.1f"):format((pin.x or 0) * 100, (pin.y or 0) * 100), 0.6, 0.8, 1)
            GameTooltip:AddLine("Click to set waypoint", 0.6, 0.8, 1)
            GameTooltip:Show()
        end)
        self:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self:SetScript("OnMouseUp", function(pin, button)
            if button == "LeftButton" then setWaypoint(pin.report) end
        end)
    end
    GuildHallMapPinMixin.OnAcquired = function(self, report)
        self.report = report
        self.memberName, self.zone = report.name, report.zone
        self.x, self.y = report.x, report.y
        self.text:SetText((report.name:match("^([^-]+)") or report.name):sub(1, 12))
        self:SetPosition(report.x, report.y)
    end
    GH.mapDataProvider = CreateFromMixins(MapCanvasDataProviderMixin)
    function GH.mapDataProvider:RefreshAllData()
        self:RemoveAllData()
        local map = self:GetMap()
        if not map or not map.GetMapID then return end
        local mapID = map:GetMapID()
        for _, report in ipairs(GH:GetMapReports()) do
            if report.mapID == mapID then map:AcquirePin("GuildHallMapPinTemplate", report) end
        end
    end
    WorldMapFrame:AddDataProvider(GH.mapDataProvider)
end

GH:RegisterEventHandler("ADDON_LOADED", attachMapProvider)
GH:RegisterEventHandler("PLAYER_LOGIN", attachMapProvider)
GH:RegisterEventHandler("WORLD_MAP_OPEN", attachMapProvider)
if C_Timer and C_Timer.After then C_Timer.After(2, attachMapProvider) end


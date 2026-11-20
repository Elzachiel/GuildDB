-- Guild-wide, opt-in location sharing and World Map pins.
local _, GH = ...

local REPORT_TTL = 45
local SEND_INTERVAL = 4
local lastSent = 0
local elapsedSincePrune = 0
local lastLocalStatus = "Waiting for a map position"
local lastLocalPosition
GH.mapReports = GH.mapReports or {}

local function normalizeMemberKey(name)
    local value = tostring(name or "")
    value = value:match("^([^%-]+)") or value
    return value:lower():gsub("[%s%-]", "")
end

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
    local mapID, x, y, location = content:match("^(%d+)|([%d%.]+)|([%d%.]+)|(.*)$")
    local zone, class
    if location then zone, class = location:match("^(.-)|([A-Z]+)$") end
    if not zone then zone, class = location, nil end -- Older GuildHall clients omit class.
    mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
    if not mapID or not x or not y or not zone then reject("malformed location payload"); return end
    if x < 0 or x > 1 or y < 0 or y > 1 or #zone > 80 then reject("coordinates or zone out of range"); return end
    local senderName = normalizeMemberKey(sender)
    -- CHAT_MSG_ADDON supplies the authenticated sender for the guild channel.
    -- Payload authors can use another name form (including two-part names),
    -- so don't discard a valid guild report when those strings differ.
    GH.mapValidReports = (GH.mapValidReports or 0) + 1
    GH.mapRejectReason = nil
    GH.mapReports[senderName] = {
        name = sender, author = author, mapID = mapID, x = x, y = y, zone = zone, class = class,
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
        table.concat({ mapID, ("%.4f"):format(x), ("%.4f"):format(y), GH:Encode(zone), select(2, UnitClass("player")) or "UNKNOWN" }, "|"),
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

GH:RegisterCommand("map", function(rest)
    local action = (rest or ""):match("^(%S+)")
    action = (action or ""):lower()
    if action == "clear" then
        if C_Map and C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
    else
        print("Guild Hall: Guild member locations are shown as live map pins. Use /gh map clear to remove an old WoW waypoint.")
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
            "GuildHall pins update about every 4 seconds, expire after 45 seconds, and pause in instances.",
        }, "\n\n")
    end
    local lines = { "Guild member locations (live pins; reports expire after 45 seconds):", "" }
    for _, report in ipairs(reports) do
        local age = math.max(0, math.floor((GetTime and GetTime() or 0) - report.seen))
        lines[#lines + 1] = ("%s  ·  %s  ·  %.1f, %.1f  ·  %ds old"):format(
            report.name, report.zone, report.x * 100, report.y * 100, age)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Your sharing: " .. sharing .. "  ·  Your position: " .. positionText
    lines[#lines + 1] = sendText
    lines[#lines + 1] = inboundText
    lines[#lines + 1] = "Pins update about every 4 seconds and can appear on zone and continent maps."
    return table.concat(lines, "\n")
end
GH:RegisterTab("Map", mapTabText)

GuildHallMapPinMixin = {}

-- Convert a point between map levels using the map hierarchy. GetMapPosFromWorldPos
-- is inconsistent for some legacy/continent maps, while map rectangles are available
-- for both the source and the map currently shown by the canvas.
local function mapAncestors(mapID)
    local chain, seen = {}, {}
    while mapID and not seen[mapID] do
        chain[#chain + 1] = mapID
        seen[mapID] = true
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        mapID = info and info.parentMapID
    end
    return chain
end

local function mapRect(childID, parentID)
    if not C_Map or not C_Map.GetMapRectOnMap then return end
    local left, right, top, bottom = C_Map.GetMapRectOnMap(childID, parentID)
    if left == nil or right == nil or top == nil or bottom == nil then return end
    return left, right, top, bottom
end

local function convertMapPosition(sourceID, x, y, targetID)
    if sourceID == targetID then return x, y end
    -- Use Blizzard's world-coordinate conversion first. It handles zone maps whose
    -- map hierarchy rectangles are incomplete (common on older continent maps).
    if C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos then
        local sourcePosition = CreateVector2D and CreateVector2D(x, y) or { x = x, y = y }
        local continentID, worldPosition = C_Map.GetWorldPosFromMapPos(sourceID, sourcePosition)
        if continentID and worldPosition then
            local convertedID, mapPosition = C_Map.GetMapPosFromWorldPos(continentID, worldPosition, targetID)
            if mapPosition and (convertedID == targetID or convertedID == nil) then
                local mapX, mapY
                if mapPosition.GetXY then mapX, mapY = mapPosition:GetXY()
                else mapX, mapY = mapPosition.x, mapPosition.y end
                if mapX and mapY and mapX >= 0 and mapX <= 1 and mapY >= 0 and mapY <= 1 then
                    return mapX, mapY
                end
            end
        end
    end
    local sourceChain, targetChain = mapAncestors(sourceID), mapAncestors(targetID)
    local targetSet = {}
    for _, id in ipairs(targetChain) do targetSet[id] = true end
    local common
    for _, id in ipairs(sourceChain) do
        if targetSet[id] then common = id; break end
    end
    if not common then return end

    local mapID = sourceID
    while mapID ~= common do
        local info = C_Map.GetMapInfo(mapID)
        local parentID = info and info.parentMapID
        local left, right, top, bottom = mapRect(mapID, parentID)
        if not left or not parentID then return end
        x, y = left + (right - left) * x, top + (bottom - top) * y
        mapID = parentID
    end

    local targetPath = {}
    mapID = targetID
    while mapID ~= common do
        targetPath[#targetPath + 1] = mapID
        local info = C_Map.GetMapInfo(mapID)
        mapID = info and info.parentMapID
        if not mapID then return end
    end
    for i = #targetPath, 1, -1 do
        local childID = targetPath[i]
        local left, right, top, bottom = mapRect(childID, C_Map.GetMapInfo(childID).parentMapID)
        if not left or right == left or bottom == top then return end
        x, y = (x - left) / (right - left), (y - top) / (bottom - top)
    end
    if x < 0 or x > 1 or y < 0 or y > 1 then return end
    return x, y
end

local function attachMapProvider()
    if not (MapCanvasDataProviderMixin and MapCanvasPinMixin and CreateFromMixins and WorldMapFrame and WorldMapFrame.AddDataProvider) then return end
    if GH.mapDataProvider then return end
    GuildHallMapPinMixin = CreateFromMixins(MapCanvasPinMixin)
    GuildHallMapPinMixin.OnLoad = function(self)
        self:SetSize(20, 20)
        local function createDot(size, layer)
            local texture = self:CreateTexture(nil, layer)
            texture:SetSize(size, size)
            texture:SetPoint("CENTER")
            texture:SetTexture("Interface\\COMMON\\Indicator-Gray")
            return texture
        end
        self.outline = createDot(16, "ARTWORK")
        self.outline:SetVertexColor(0, 0, 0, 1)
        self.dot = createDot(11, "OVERLAY")
        self.text = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        self.text:SetPoint("BOTTOM", self, "TOP", 0, 3)
        self.text:SetTextColor(1, 1, 1, 1)
        self.text:SetShadowColor(0, 0, 0, 1)
        self.text:SetShadowOffset(1, -1)
        self:EnableMouse(true)
        self:SetScript("OnEnter", function(pin)
            GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
            GameTooltip:SetText(pin.memberName or "Guild member")
            GameTooltip:AddLine(pin.zone or "", 0.8, 0.85, 0.9)
            GameTooltip:AddLine(("%.1f, %.1f"):format((pin.x or 0) * 100, (pin.y or 0) * 100), 0.6, 0.8, 1)
            GameTooltip:AddLine("Live GuildHall location pin", 0.6, 0.8, 1)
            GameTooltip:Show()
        end)
        self:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    GuildHallMapPinMixin.OnAcquired = function(self, report)
        self.report = report
        self.memberName, self.zone = report.name, report.zone
        self.x, self.y = report.x, report.y
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[report.class or ""]
        if color then self.dot:SetVertexColor(color.r, color.g, color.b, 1)
        else self.dot:SetVertexColor(0.8, 0.8, 0.8, 1) end
        self.text:SetText((report.name:match("^([^-]+)") or report.name):sub(1, 12))
        self:SetPosition(report.x, report.y)
    end
    GH.mapDataProvider = CreateFromMixins(MapCanvasDataProviderMixin)
    function GH.mapDataProvider:RemoveAllData()
        local map = self:GetMap()
        if map and map.RemoveAllPinsByTemplate then
            map:RemoveAllPinsByTemplate("GuildHallMapPinTemplate")
        end
    end
    function GH.mapDataProvider:OnMapChanged()
        self:RefreshAllData()
        -- The map canvas changes its map ID before the map art/coordinate data
        -- finishes loading. Refresh once more on the next frame for legacy clients.
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if GH.mapDataProvider == self and self:GetMap() == WorldMapFrame then
                    self:RefreshAllData()
                end
            end)
        end
    end
    function GH.mapDataProvider:RefreshAllData()
        self:RemoveAllData()
        local map = self:GetMap()
        if not map or not map.GetMapID then return end
        local mapID = map:GetMapID()
        for _, report in ipairs(GH:GetMapReports()) do
            local x, y
            if C_Map and C_Map.GetMapInfo and C_Map.GetMapRectOnMap then
                x, y = convertMapPosition(report.mapID, report.x, report.y, mapID)
            end
            if x and y then
                local pinReport = { name = report.name, zone = report.zone, class = report.class, mapID = mapID, x = x, y = y, seen = report.seen }
                map:AcquirePin("GuildHallMapPinTemplate", pinReport)
            end
        end
    end
    WorldMapFrame:AddDataProvider(GH.mapDataProvider)
end

GH:RegisterEventHandler("ADDON_LOADED", attachMapProvider)
GH:RegisterEventHandler("PLAYER_LOGIN", attachMapProvider)
GH:RegisterEventHandler("WORLD_MAP_OPEN", attachMapProvider)
if C_Timer and C_Timer.After then C_Timer.After(2, attachMapProvider) end


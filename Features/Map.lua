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
    if GH.RefreshMapPins and WorldMapFrame and WorldMapFrame:IsShown() then
        GH:RefreshMapPins()
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

local mapMemberIcons = {}

local function isInLocalGroup(memberName)
    local wanted = normalizeMemberKey(memberName)
    if wanted == "" or not UnitExists or not UnitName then return false end

    -- Prefer raid unit tokens when in a raid; otherwise inspect the four
    -- non-player party slots. These members already have Blizzard map markers.
    local inRaid = IsInRaid and IsInRaid()
    local prefix, limit = inRaid and "raid" or "party", inRaid and 40 or 4
    for index = 1, limit do
        local unit = prefix .. index
        if UnitExists(unit) then
            local name = UnitName(unit)
            if name and normalizeMemberKey(name) == wanted then return true end
        end
    end
    return false
end

local function getMapLibraries()
    if not LibStub then return end
    return LibStub("HereBeDragons-2.0", true), LibStub("HereBeDragons-Pins-2.0", true)
end

local function createMemberIcon()
    local icon = CreateFrame("Frame", nil, UIParent)
    icon:SetSize(14, 14)
    icon.dotOutline = icon:CreateTexture(nil, "ARTWORK")
    icon.dotOutline:SetSize(11, 11)
    icon.dotOutline:SetPoint("CENTER")
    icon.dotOutline:SetTexture("Interface\\AddOns\\GuildHall\\Assets\\MapDot")
    icon.dotOutline:SetVertexColor(0, 0, 0, 1)
    icon.dot = icon:CreateTexture(nil, "OVERLAY")
    icon.dot:SetSize(8, 8)
    icon.dot:SetPoint("CENTER")
    icon.dot:SetTexture("Interface\\AddOns\\GuildHall\\Assets\\MapDot")
    icon.label = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    icon.label:SetPoint("BOTTOM", icon, "TOP", 0, 3)
    icon.label:SetTextColor(1, 1, 1, 1)
    icon.label:SetShadowColor(0, 0, 0, 1)
    icon.label:SetShadowOffset(1, -1)
    icon:EnableMouse(true)
    icon:SetScript("OnEnter", function(frame)
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        GameTooltip:SetText(frame.memberName or "Guild member")
        GameTooltip:AddLine(frame.zone or "", 0.8, 0.85, 0.9)
        GameTooltip:AddLine(("%.1f, %.1f"):format((frame.x or 0) * 100, (frame.y or 0) * 100), 0.6, 0.8, 1)
        GameTooltip:AddLine("Live GuildHall location pin", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return icon
end

function GH:RefreshMapPins()
    local HBD, HBDPins = getMapLibraries()
    if not (HBD and HBDPins and WorldMapFrame) then return end

    HBDPins:RemoveAllWorldMapIcons(self)
    local activeIcons = {}
    for _, report in ipairs(self:GetMapReports()) do
        local key = normalizeMemberKey(report.name)
        if not isInLocalGroup(report.name) then
            local icon = mapMemberIcons[key] or createMemberIcon()
            mapMemberIcons[key] = icon
            icon.memberName, icon.zone = report.name, report.zone
            icon.x, icon.y = report.x, report.y
            icon.label:SetText((report.name:match("^([^-]+)") or report.name):sub(1, 12))
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[report.class or ""]
            if color then icon.dot:SetVertexColor(color.r, color.g, color.b, 1)
            else icon.dot:SetVertexColor(0.8, 0.8, 0.8, 1) end
            icon:Show()

            local added = HBDPins:AddWorldMapIconMap(
                self, icon, report.mapID, report.x, report.y, HBD_PINS_WORLDMAP_SHOW_WORLD
            )
            if added then activeIcons[key] = true else icon:Hide() end
        end
    end
    for key, icon in pairs(mapMemberIcons) do
        if not activeIcons[key] then icon:Hide() end
    end
end

GH:RegisterEventHandler("WORLD_MAP_OPEN", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, refreshMapPins)
    else
        refreshMapPins()
    end
end)

GH:RegisterEventHandler("GROUP_ROSTER_UPDATE", refreshMapPins)


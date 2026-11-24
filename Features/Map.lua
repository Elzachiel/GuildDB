-- Guild-wide, opt-in location sharing and World Map pins.
local _, GD = ...

local REPORT_TTL = 45
local SEND_INTERVAL = 4
local lastSent = 0
local elapsedSincePrune = 0
GD.mapReports = GD.mapReports or {}

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
    if GD.RefreshMapPins and WorldMapFrame and WorldMapFrame:IsShown() then
        GD:RefreshMapPins()
    end
end

GD:RegisterRecordHandler("ML", function(id, timestamp, author, content, sender)
    local function reject(reason)
        GD.mapRejectReason = reason
    end
    if not GD.bucket or not sender then reject("no guild bucket or sender"); return end
    local mapID, x, y, location = content:match("^(%d+)|([%d%.]+)|([%d%.]+)|(.*)$")
    local zone, class
    if location then zone, class = location:match("^(.-)|([A-Z]+)$") end
    if not zone then zone, class = location, nil end -- Older GuildDB clients omit class.
    mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
    if not mapID or not x or not y or not zone then reject("malformed location payload"); return end
    if x < 0 or x > 1 or y < 0 or y > 1 or #zone > 80 then reject("coordinates or zone out of range"); return end
    local senderName = normalizeMemberKey(sender)
    -- CHAT_MSG_ADDON supplies the authenticated sender for the guild channel.
    -- Payload authors can use another name form (including two-part names),
    -- so don't discard a valid guild report when those strings differ.
    GD.mapValidReports = (GD.mapValidReports or 0) + 1
    GD.mapRejectReason = nil
    GD.mapReports[senderName] = {
        name = sender, author = author, mapID = mapID, x = x, y = y, zone = zone, class = class,
        seen = GetTime and GetTime() or 0,
    }
    refreshMapPins()
end)

local function sendLocation()
    if not GD.bucket or not GD:GetSetting("shareMapLocation") then return end
    local mapID, x, y, zone = unitLocation()
    if not mapID then return end
    local author = UnitName and UnitName("player") or ""
    if author == "" then return end
    local payload = table.concat({
        "ML", "loc", time(), GD:Encode(author),
        table.concat({ mapID, ("%.4f"):format(x), ("%.4f"):format(y), GD:Encode(zone), select(2, UnitClass("player")) or "UNKNOWN" }, "|"),
    }, "|")
    GD:Enqueue(payload)
    lastSent = GetTime and GetTime() or 0
end

function GD:MapUpdate(now, elapsed)
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
    if changed then refreshMapPins() end
end

function GD:GetMapReports()
    local reports = {}
    local now = GetTime and GetTime() or 0
    for _, report in pairs(self.mapReports or {}) do
        if now - (report.seen or 0) <= REPORT_TTL then reports[#reports + 1] = report end
    end
    table.sort(reports, function(a, b) return a.name:lower() < b.name:lower() end)
    return reports
end

GD:RegisterCommand("map", function(rest)
    local action = (rest or ""):match("^(%S+)")
    action = (action or ""):lower()
    if action == "clear" then
        if C_Map and C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
    else
        print("GuildDB: Guild member locations are shown as live map pins. Use /gd map clear to remove an old WoW waypoint.")
    end
end)

local mapMemberIcons = {}

local function isInLocalGroup(memberName, payloadAuthor)
    local wanted = {
        [normalizeMemberKey(memberName)] = true,
        [normalizeMemberKey(payloadAuthor)] = true,
    }
    wanted[""] = nil
    if not next(wanted) or not UnitExists then return false end

    local playerName = UnitName and UnitName("player")
    if playerName and wanted[normalizeMemberKey(playerName)] then return true end

    -- Prefer raid unit tokens when in a raid; otherwise inspect the four
    -- non-player party slots. These members already have Blizzard map markers.
    local inRaid = IsInRaid and IsInRaid()
    local prefix, limit = inRaid and "raid" or "party", inRaid and 40 or 4
    for index = 1, limit do
        local unit = prefix .. index
        if UnitExists(unit) then
            local name, realm
            if UnitFullName then
                name, realm = UnitFullName(unit)
            elseif UnitName then
                name, realm = UnitName(unit)
            end
            if name and wanted[normalizeMemberKey(name)] then return true end
            if name and realm and wanted[normalizeMemberKey(name .. "-" .. realm)] then return true end
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
    icon.dotOutline:SetTexture("Interface\\AddOns\\GuildDB\\Assets\\MapDot")
    icon.dotOutline:SetVertexColor(0, 0, 0, 1)
    icon.dot = icon:CreateTexture(nil, "OVERLAY")
    icon.dot:SetSize(8, 8)
    icon.dot:SetPoint("CENTER")
    icon.dot:SetTexture("Interface\\AddOns\\GuildDB\\Assets\\MapDot")
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
        GameTooltip:AddLine("Live GuildDB location pin", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return icon
end

function GD:RefreshMapPins()
    local HBD, HBDPins = getMapLibraries()
    if not (HBD and HBDPins and WorldMapFrame) then return end

    HBDPins:RemoveAllWorldMapIcons(self)
    local activeIcons = {}
    for _, report in ipairs(self:GetMapReports()) do
        local key = normalizeMemberKey(report.name)
        -- The authenticated addon sender and payload author can differ in
        -- name/realm formatting. Match either against the local group roster.
        if not isInLocalGroup(report.name, report.author) then
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

GD:RegisterEventHandler("WORLD_MAP_OPEN", function()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, refreshMapPins)
    else
        refreshMapPins()
    end
end)

GD:RegisterEventHandler("GROUP_ROSTER_UPDATE", refreshMapPins)


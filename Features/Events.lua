-- Guild events, raid scheduling, attendee RSVPs, display, and sync.
local _, GD = ...
GD:RegisterBucket("events", function() return {} end)
GD:RegisterBucket("eventDeletes", function() return {} end)
local syncGameCalendarRSVP
local EVENT_SETTINGS_MARKER = "\n\n[GuildDB calendar settings]\n"
local CALENDAR_TYPES = { Raid = 0, Dungeon = 1, PvP = 2, Meeting = 3, Other = 4 }

local function parseEventTime(value)
    local y, month, day, hour, minute = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)%s+(%d%d):(%d%d)$")
    y, month, day, hour, minute = tonumber(y), tonumber(month), tonumber(day), tonumber(hour), tonumber(minute)
    if not y or month < 1 or month > 12 or day < 1 or day > 31 or hour > 23 or minute > 59 then return end
    local stamp = time({ year = y, month = month, day = day, hour = hour, min = minute, sec = 0 })
    local actual = date("*t", stamp)
    if actual.year ~= y or actual.month ~= month or actual.day ~= day or actual.hour ~= hour or actual.min ~= minute then return end
    return stamp
end

local function encodeEvent(record)
    local settings = record.calendarSettings or {}
    local details = tostring(record.details or ""):gsub("%[GuildDB calendar settings%]", "[GuildDB settings]")
    local metadata = table.concat({
        settings.category or (record.eventType == "raid" and "Raid" or "Other"),
        settings.locked and "1" or "0",
        settings.inviteMode or "none",
        settings.inviteNames or "",
        tostring(settings.raidSize or 40),
    }, "\n")
    return table.concat({ record.at, record.title, details .. EVENT_SETTINGS_MARKER .. metadata }, "\n")
end

local function findEvent(id)
    for index, event in ipairs((GD.bucket and GD.bucket.events) or {}) do
        if event.id == id then return event, index end
    end
end

local function eventDeleteTimestamp(id)
    local value = (GD.bucket.eventDeletes or {})[id]
    return type(value) == "table" and (tonumber(value.ts) or 0) or (tonumber(value) or 0)
end

local function isOfficer(name)
    if not name or not GetNumGuildMembers or not GetGuildRosterInfo then return false end
    local wanted = (name:match("^([^-]+)") or name):lower()
    for index = 1, GetNumGuildMembers() do
        local rosterName, _, rankIndex = GetGuildRosterInfo(index)
        if rosterName and (rosterName:match("^([^-]+)") or rosterName):lower() == wanted then
            return tonumber(rankIndex) ~= nil and tonumber(rankIndex) <= 1
        end
    end
    return false
end

local function samePlayerName(left, right)
    local function key(name)
        name = tostring(name or ""):match("^([^-]+)") or tostring(name or "")
        return name:lower():gsub("[%s%-]", "")
    end
    return key(left) ~= "" and key(left) == key(right)
end

local function showEventPopout(event)
    if not GD.ShowPopout then return end
    local eventType = event.eventType == "raid" and "raid" or "event"
    local when = date("%a %d %b %Y, %I:%M %p", event.at)
    local message = (event.by or "A guild officer") .. " scheduled " .. when
    if event.details and event.details ~= "" then message = message .. "\n" .. event.details end
    GD:ShowPopout(eventType == "raid" and "New guild raid" or "New guild event", event.title, message,
        eventType == "raid" and "Interface/Icons/INV_Misc_GroupLooking" or "Interface/Icons/INV_Misc_Note_01",
        function() GD.activeTab = "Events"; GD:Open() end, 8)
end

local function storeEvent(id, ts, author, content, eventType, sender)
    if #id > 100 or #author > 100 or #content > 900 then return end
    if not isOfficer(author) or eventDeleteTimestamp(id) >= ts then return end
    local at, title, remainder = content:match("^(.-)\n(.-)\n(.*)$")
    at = tonumber(at)
    if not at or not title then return end
    local details, metadata = remainder:match("^(.*)\n\n%[GuildDB calendar settings%]\n(.*)$")
    local settings = {}
    if metadata then
        local category, locked, inviteMode, inviteNames, raidSize = metadata:match("^(.-)\n(.-)\n(.-)\n(.-)\n(%d+)$")
        if not category then category, locked, inviteMode, inviteNames = metadata:match("^(.-)\n(.-)\n(.-)\n(.*)$") end
        if category then
            settings.category = CALENDAR_TYPES[category] and category or (eventType == "raid" and "Raid" or "Other")
            settings.locked = locked == "1"
            settings.inviteMode = (inviteMode == "selected" or inviteMode == "guild") and inviteMode or "none"
            settings.inviteNames = (inviteNames or ""):sub(1, 200)
            settings.raidSize = math.max(1, math.min(40, tonumber(raidSize) or 40))
        end
    else
        details = remainder
    end
    if not details or #title > 100 or #details > 300 then return end
    local current, index = findEvent(id)
    if current and (current.ts or 0) >= ts then return end
    local isNew = current == nil
    local event = { id = id, ts = ts, by = author, at = at, title = title, details = details,
        eventType = eventType, calendarSettings = settings, rsvps = current and current.rsvps or {}, selections = current and current.selections or {}, signupDeletes = current and current.signupDeletes or {} }
    if current then GD.bucket.events[index] = event else table.insert(GD.bucket.events, 1, event) end
    if GD.RefreshUI then GD:RefreshUI() end
    if isNew and sender and samePlayerName(sender, author) then showEventPopout(event) end
end

local function normalizeCalendarSettings(settings, eventType)
    settings = type(settings) == "table" and settings or {}
    local category = CALENDAR_TYPES[settings.category] and settings.category or (eventType == "raid" and "Raid" or "Other")
    local inviteMode = "none"
    if settings.inviteMode == "selected" or settings.inviteMode == "guild" then inviteMode = settings.inviteMode end
    return {
        category = category,
        locked = settings.locked == true,
        inviteMode = inviteMode,
        inviteNames = tostring(settings.inviteNames or ""):gsub("[\r\n]", ","):sub(1, 200),
        raidSize = math.max(1, math.min(40, math.floor(tonumber(settings.raidSize) or 40))),
    }
end

local function parseInviteNames(value)
    local names, seen = {}, {}
    for name in tostring(value or ""):gmatch("[^,]+") do
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        local key = name:lower()
        if name ~= "" and not seen[key] and #names < 25 then
            seen[key] = true
            names[#names + 1] = name
        end
    end
    return names
end

local function inviteCalendarGuests(calendar, settings, priorSettings)
    local warnings = {}
    priorSettings = priorSettings or {}
    local priorSelected = parseInviteNames(priorSettings.inviteNames)
    local selected = {}
    if settings.inviteMode == "selected" then
        for _, name in ipairs(parseInviteNames(settings.inviteNames)) do selected[name:lower()] = true end
    end
    if priorSettings.inviteMode == "selected" and #priorSelected > 0 then
        if type(calendar.GetNumInvites) == "function" and type(calendar.EventGetInvite) == "function"
            and type(calendar.EventRemoveInvite) == "function" then
            for index = calendar.GetNumInvites(), 1, -1 do
                local invite = calendar.EventGetInvite(index)
                local name = invite and invite.name
                if name and not selected[name:lower()] then
                    local wasManaged = false
                    for _, previousName in ipairs(priorSelected) do
                        if previousName:lower() == name:lower() then wasManaged = true; break end
                    end
                    if wasManaged then
                        local ok, err = pcall(calendar.EventRemoveInvite, index)
                        if not ok then warnings[#warnings + 1] = "Could not remove invite for " .. name .. ": " .. tostring(err) end
                    end
                end
            end
        else
            warnings[#warnings + 1] = "This client cannot remove previously selected player invites."
        end
    elseif priorSettings.inviteMode == "guild" and settings.inviteMode ~= "guild" then
        warnings[#warnings + 1] = "Previously sent mass guild invites remain on the in-game calendar."
    end
    if settings.inviteMode == "guild" and priorSettings.inviteMode ~= "guild" then
        if type(calendar.MassInviteGuild) == "function" then
            local ok, err = pcall(calendar.MassInviteGuild, 1, 100, 99)
            if not ok then warnings[#warnings + 1] = "Mass invite failed: " .. tostring(err) end
        else
            warnings[#warnings + 1] = "Mass guild invite is unavailable in this client."
        end
    elseif settings.inviteMode == "selected" then
        local prior = {}
        for _, name in ipairs(priorSelected) do prior[name:lower()] = true end
        for _, name in ipairs(parseInviteNames(settings.inviteNames)) do
            if not prior[name:lower()] then
                if type(calendar.EventInvite) == "function" then
                    local ok, err = pcall(calendar.EventInvite, name)
                    if not ok then warnings[#warnings + 1] = "Invite failed for " .. name .. ": " .. tostring(err) end
                else
                    warnings[#warnings + 1] = "Named invites are unavailable in this client."
                    break
                end
            end
        end
    end
    return warnings
end

function GD:PostEvent(at, title, details, eventType, calendarSettings)
    if not self:CanManage() then return false, "Only the guild leader or rank 1 can post events." end
    if not at or not title or title == "" then return false, "Enter a valid date, time, and event title." end
    eventType = eventType == "raid" and "raid" or "event"
    local settings = normalizeCalendarSettings(calendarSettings, eventType)
    eventType = settings.category == "Raid" and "raid" or "event"
    local record = self:NewRecord({ at = at, title = title:sub(1, 100), details = (details or ""):sub(1, 300), eventType = eventType, calendarSettings = settings, rsvps = {} })
    local kind = eventType == "raid" and "D" or "E"
    self:StoreRecord("events", record, kind, encodeEvent(record))
    showEventPopout(record)
    return true, (eventType == "raid" and "Raid" or "Event") .. " saved and sent to online GuildDB users.", record.id
end

local function onEventRecord(kind, id, ts, author, content, sender)
    storeEvent(id, ts, author, content, kind == "D" and "raid" or "event", sender)
end
GD:RegisterRecordHandler("E", function(...) onEventRecord("E", ...) end)
GD:RegisterRecordHandler("D", function(...) onEventRecord("D", ...) end)

GD:RegisterRecordHandler("EVX", function(id, ts, author)
    if #id > 100 or #author > 100 or not isOfficer(author) or eventDeleteTimestamp(id) >= ts then return end
    GD.bucket.eventDeletes = GD.bucket.eventDeletes or {}
    GD.bucket.eventDeletes[id] = { ts = ts, by = author }
    local _, index = findEvent(id)
    if index then table.remove(GD.bucket.events, index) end
    if GD.RefreshUI then GD:RefreshUI() end
end)

function GD:EditEvent(eventId, at, title, details, calendarSettings)
    if not self:CanManage() then return false, "Only the guild leader or rank 1 can edit events." end
    local event = findEvent(eventId)
    if not event then return false, "That event is no longer available." end
    if not at or not title or title == "" then return false, "Enter a valid date, time, and event title." end

    local player = self:PlayerName()
    local settings = normalizeCalendarSettings(calendarSettings or event.calendarSettings, event.eventType)
    local calendarUpdated, calendarMessage = self:UpdateGameCalendarEvent(event, at, title, details, settings)

    local updated = { id = event.id, ts = math.max(time(), (event.ts or 0) + 1), by = player,
        at = at, title = title:sub(1, 100), details = (details or ""):sub(1, 300),
        eventType = settings.category == "Raid" and "raid" or "event",
        calendarSettings = settings, rsvps = event.rsvps or {}, selections = event.selections or {}, signupDeletes = event.signupDeletes or {} }
    local _, index = findEvent(eventId)
    self.bucket.events[index] = updated
    self:SendRecord(updated.eventType == "raid" and "D" or "E", updated.id, updated.ts, updated.by, encodeEvent(updated))
    if self.RefreshUI then self:RefreshUI() end
    local result = "Event updated and shared with online GuildDB users."
    if calendarUpdated then
        result = result .. " The in-game guild-calendar entry was updated."
        if calendarMessage then result = result .. " " .. calendarMessage end
    elseif calendarMessage and calendarMessage ~= "No matching native guild-calendar entry was found." then
        result = result .. " Calendar copy unchanged: " .. calendarMessage
    end
    return true, result
end

function GD:DeleteEvent(eventId)
    if not self:CanManage() then return false, "Only the guild leader or rank 1 can remove events." end
    local event, index = findEvent(eventId)
    if not event then return false, "That event is no longer available." end
    local player = self:PlayerName()
    local removedCalendarEntry, calendarMessage = self:RemoveGameCalendarEvent(event)
    if removedCalendarEntry and GDB and GDB.calendarExports then
        GDB.calendarExports[eventId] = nil
    end
    local ts = math.max(time(), (event.ts or 0) + 1)
    table.remove(self.bucket.events, index)
    self.bucket.eventDeletes = self.bucket.eventDeletes or {}
    self.bucket.eventDeletes[eventId] = { ts = ts, by = player }
    self:SendRecord("EVX", eventId, ts, player, "")
    if self.RefreshUI then self:RefreshUI() end
    local result = "Event removed from GuildDB and synced with online GuildDB users."
    if removedCalendarEntry then result = result .. " The in-game guild-calendar entry was removed."
    elseif calendarMessage and calendarMessage ~= "No matching native guild-calendar entry was found." then
        result = result .. " Calendar copy unchanged: " .. calendarMessage
    end
    return true, result
end

GD:RegisterRecordHandler("R", function(id, ts, author, content)
    local status, role, spec, note = content:match("^(.-)\n(.-)\n(.-)\n(.*)$")
    if not status then status, role, note = content:match("^(.-)\n(.-)\n(.*)$") end
    status = (status or content):lower()
    if role and role ~= "Tank" and role ~= "Healer" and role ~= "DPS" then return end
    if note and #note > 100 then return end
    if spec and #spec > 60 then return end
    if status ~= "going" and status ~= "tentative" and status ~= "absent" then return end
    for _, event in ipairs(GD.bucket.events or {}) do
        if event.id == id then
            event.rsvps = event.rsvps or {}
            local previous = event.rsvps[author]
            local deleted = event.signupDeletes and event.signupDeletes[author]
            if deleted and deleted.ts >= ts then return end
            if previous and type(previous) == "table" and previous.ts >= ts then return end
            event.rsvps[author] = { status = status, ts = ts, role = role, spec = spec, note = note }
            if GD.RefreshUI then GD:RefreshUI() end
            return
        end
    end
end)

local function sendRSVP(eventId, player, response)
    local status = type(response) == "table" and response.status or response
    local ts = type(response) == "table" and response.ts or time()
    local content = status
    if type(response) == "table" and response.role then
        content = table.concat({ status, response.role, response.spec or "", response.note or "" }, "\n")
    end
    GD:SendRecord("R", eventId, ts, player, content)
end

function GD:IsRaidGM(name)
    local wanted = name or self:PlayerName()
    for index = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
        local member, _, rank = GetGuildRosterInfo(index)
        if samePlayerName(member, wanted) then return rank == 0 end
    end
    return false
end

-- Class comes from the live guild roster, including offline members.
function GD:GetRaidPlayerClass(name)
    local previewClass = self.raidPreviewEvent and self.raidPreviewEvent.classes[name]
    if previewClass then return previewClass[1], previewClass[2] end
    if samePlayerName(name, self:PlayerName()) and UnitClass then
        local label, token = UnitClass("player")
        if token then return label, token end
    end
    for index = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
        local member, _, _, _, label, _, _, _, _, _, token = GetGuildRosterInfo(index)
        if samePlayerName(member, name) then return label, token end
    end
    return "Unknown", nil
end

function GD:GetRaidSignupSummary(event)
    local summary = { going = 0, tentative = 0, absent = 0, Tank = 0, Healer = 0, DPS = 0, unassigned = 0, selected = 0 }
    for name, response in pairs(event.rsvps or {}) do
        local status = type(response) == "table" and response.status or response
        if summary[status] ~= nil then summary[status] = summary[status] + 1 end
        if status == "going" then
            local role = type(response) == "table" and response.role
            if role == "Tank" or role == "Healer" or role == "DPS" then summary[role] = summary[role] + 1
            else summary.unassigned = summary.unassigned + 1 end
        end
        local selection = event.selections and event.selections[name]
        if status == "going" and selection and selection.selected then summary.selected = summary.selected + 1 end
    end
    return summary
end

local function removeSignup(event, player, ts, author)
    event.signupDeletes = event.signupDeletes or {}
    local prior = event.signupDeletes[player]
    local response = event.rsvps and event.rsvps[player]
    if prior and prior.ts >= ts then return false end
    if type(response) == "table" and (response.ts or 0) >= ts then return false end
    event.signupDeletes[player] = { ts = ts, by = author }
    if event.rsvps then event.rsvps[player] = nil end
    if event.selections then event.selections[player] = nil end
    return true
end

GD:RegisterRecordHandler("RX", function(id, ts, author, player)
    if #player > 100 or player == "" then return end
    if not samePlayerName(player, author) and not GD:IsRaidGM(author) then return end
    local event = findEvent(id)
    if event and removeSignup(event, player, ts, author) and GD.RefreshUI then GD:RefreshUI() end
end)

function GD:RemoveRaidSignup(eventId, player)
    local event = self.bucket and findEvent(eventId)
    if not event then return false, "That raid is no longer available." end
    player = player or self:PlayerName()
    local author = self:PlayerName()
    if not samePlayerName(player, author) and not self:IsRaidGM() then return false, "Only the GM can remove another player's signup." end
    local response = event.rsvps and event.rsvps[player]
    if not response then return false, "That player is not signed up." end
    local prior = event.signupDeletes and event.signupDeletes[player]
    local selection = event.selections and event.selections[player]
    local ts = math.max(time(), type(response) == "table" and (response.ts or 0) + 1 or 0, prior and prior.ts + 1 or 0, selection and selection.ts + 1 or 0)
    removeSignup(event, player, ts, author)
    self:SendRecord("RX", eventId, ts, author, player)
    if samePlayerName(player, author) and syncGameCalendarRSVP then syncGameCalendarRSVP(event, "absent") end
    if self.RefreshUI then self:RefreshUI() end
    return true, "Signup removed for " .. player .. "."
end

GD:RegisterRecordHandler("RI", function(id, ts, author, content)
    if not GD:IsRaidGM(author) then return end
    local player, selected = content:match("^([^\n]+)\n([01])$")
    if not player or #player > 100 then return end
    local event = findEvent(id)
    if not event then return end
    local deleted = event.signupDeletes and event.signupDeletes[player]
    if deleted and deleted.ts >= ts then return end
    event.selections = event.selections or {}
    local prior = event.selections[player]
    if prior and prior.ts >= ts then return end
    event.selections[player] = { selected = selected == "1", ts = ts, by = author }
    if GD.RefreshUI then GD:RefreshUI() end
end)

function GD:SetRaidSelection(eventId, player, selected)
    if not self:IsRaidGM() then return false, "Only the GM can select the invite roster." end
    local event = findEvent(eventId)
    if not event or not event.rsvps or not event.rsvps[player] then return false, "That signup is no longer available." end
    event.selections = event.selections or {}
    local prior = event.selections[player]
    local ts = math.max(time(), prior and prior.ts + 1 or 0)
    local response = event.rsvps[player]
    if selected and (type(response) == "table" and response.status or response) ~= "going" then return false, "Only attending players can be selected for invites." end
    local deleted = event.signupDeletes and event.signupDeletes[player]
    ts = math.max(ts, deleted and deleted.ts + 1 or 0)
    event.selections[player] = { selected = selected == true, ts = ts, by = self:PlayerName() }
    self:SendRecord("RI", eventId, ts, self:PlayerName(), player .. "\n" .. (selected and "1" or "0"))
    if self.RefreshUI then self:RefreshUI() end
    return true, "Invite roster updated."
end

-- Invites run directly from the GM's click so the client can enforce permissions.
function GD:InviteRaidSelections(eventId)
    if not self:IsRaidGM() then return false, "Only the GM can invite the selected raid roster." end
    local event = self.bucket and findEvent(eventId)
    if not event then return false, "That raid is no longer available." end
    if InCombatLockdown and InCombatLockdown() then return false, "Leave combat before inviting the raid roster." end
    local partyInfo = C_PartyInfo or {}
    local invite = InviteByName or InviteUnit or partyInfo.InviteUnit
    if type(invite) ~= "function" then return false, "This client does not expose a group invite function." end
    local inRaid = IsInRaid and IsInRaid()
    local grouped = inRaid or (IsInGroup and IsInGroup()) or (GetNumGroupMembers and GetNumGroupMembers() > 0)
    if grouped and not ((UnitIsGroupLeader and UnitIsGroupLeader("player")) or (inRaid and UnitIsGroupAssistant and UnitIsGroupAssistant("player"))) then
        return false, "You must be group leader or raid assistant to invite players."
    end
    if grouped and not inRaid then
        local convert = ConvertToRaid or partyInfo.ConvertToRaid
        if type(convert) ~= "function" then return false, "Convert your party to a raid before inviting the roster." end
        local ok, reason = pcall(convert)
        if not ok then return false, "Could not convert the party to a raid: " .. tostring(reason) end
        if not (IsInRaid and IsInRaid()) then return true, "Raid conversion requested. Click Invite selected again once the group becomes a raid." end
        inRaid = true
    end
    local online = {}
    for index = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
        local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(index)
        if name and isOnline then online[name:lower()] = name end
    end
    self.pendingRaidInvites = self.pendingRaidInvites or {}
    local pending = self.pendingRaidInvites
    local now = time()
    for name, at in pairs(pending) do if now - at >= 60 then pending[name] = nil end end
    local candidates, offline, already, waiting = {}, 0, 0, 0
    for name, selection in pairs(event.selections or {}) do
        local response = event.rsvps and event.rsvps[name]
        local status = type(response) == "table" and response.status or response
        if selection.selected and status == "going" then
            if samePlayerName(name, self:PlayerName()) or (UnitInRaid and UnitInRaid(name)) or (UnitInParty and UnitInParty(name)) then
                already = already + 1
                pending[name] = nil
            elseif pending[name] then waiting = waiting + 1
            else
                local target = online[name:lower()]
                if not target then
                    for _, member in pairs(online) do if samePlayerName(member, name) then target = member; break end end
                end
                if target then candidates[#candidates + 1] = { name = name, target = target }
                else offline = offline + 1 end
            end
        end
    end
    table.sort(candidates, function(a, b) return a.name < b.name end)
    if not inRaid then
        for _ in pairs(pending) do return false, "Waiting for an invited player to join. Then click Invite selected again to form the raid." end
    end
    local capacity = math.max(0, 40 - (GetNumGroupMembers and GetNumGroupMembers() or 1))
    if not inRaid then capacity = 1 end
    local sent, failed = 0, 0
    for _, candidate in ipairs(candidates) do
        if sent >= capacity then break end
        local ok = pcall(invite, candidate.target)
        if ok then sent = sent + 1; pending[candidate.name] = now else failed = failed + 1 end
    end
    local message = ("Invite requests: %d. Already grouped: %d. Offline: %d. Pending: %d. Failed: %d."):format(sent, already, offline, waiting, failed)
    if sent > 0 and not inRaid then message = message .. " Once that player joins, click Invite selected again to convert to a raid and invite the remaining players." end
    return sent > 0, message
end

GD:RegisterHistoryProvider(function()
    local events = GD.bucket.events or {}
    for i = math.min(#events, 12), 1, -1 do
        local event = events[i]
        GD:SendRecord(event.eventType == "raid" and "D" or "E", event.id, event.ts, event.by, encodeEvent(event))
        for player, removal in pairs(event.signupDeletes or {}) do
            GD:SendRecord("RX", event.id, removal.ts, removal.by, player)
        end
        for player, response in pairs(event.rsvps or {}) do sendRSVP(event.id, player, response) end
        for player, selection in pairs(event.selections or {}) do
            GD:SendRecord("RI", event.id, selection.ts, selection.by, player .. "\n" .. (selection.selected and "1" or "0"))
        end
    end
    for id, info in pairs(GD.bucket.eventDeletes or {}) do
        local ts = type(info) == "table" and info.ts or tonumber(info)
        local author = type(info) == "table" and info.by or nil
        if ts and author then GD:SendRecord("EVX", id, ts, author, "") end
    end
end)

local function upcomingEvents()
    local events = {}
    for _, event in ipairs((GD.bucket and GD.bucket.events) or {}) do
        if event.at + 6 * 3600 >= time() then events[#events + 1] = event end
    end
    if GD.raidPreviewEvent then events[#events + 1] = GD.raidPreviewEvent end
    table.sort(events, function(a, b)
        if a.preview ~= b.preview then return a.preview == true end
        return a.at < b.at
    end)
    return events
end
GD.GetUpcomingEvents = upcomingEvents

function GD:ParseEventTimeFields(dateText, timeText)
    local day, month, year = tostring(dateText or ""):match("^%s*(%d%d)[%-%/](%d%d)[%-%/](%d%d%d%d)%s*$")
    local hour, minute, period = tostring(timeText or ""):upper():match("^%s*(%d%d?):(%d%d)%s*([AP]M)%s*$")
    hour, minute = tonumber(hour), tonumber(minute)
    if not year then return nil, "Enter the date as DD-MM-YYYY (for example, 21-11-2026)." end
    if not hour or hour < 1 or hour > 12 or minute > 59 then
        return nil, "Enter the start time with AM or PM (for example, 8:00 PM)."
    end
    hour = hour % 12 + (period == "PM" and 12 or 0)
    local stamp = parseEventTime(("%s-%s-%s %02d:%02d"):format(year, month, day, hour, minute))
    if not stamp then return nil, "Enter a valid calendar date and local start time." end
    return stamp
end

function GD:PostEventFields(dateText, timeText, title, details, eventType, calendarSettings)
    local at, reason = self:ParseEventTimeFields(dateText, timeText)
    if not at then return false, reason end
    return self:PostEvent(at, title, details, eventType, calendarSettings)
end

function GD:SetRSVPForEvent(eventId, status, role, note, spec)
    if not self.bucket then return false, "Join a guild first." end
    status = tostring(status or ""):lower()
    if status ~= "going" and status ~= "tentative" and status ~= "absent" then return false, "Choose going, tentative, or absent." end
    local event
    for _, candidate in ipairs(upcomingEvents()) do
        if candidate.id == eventId then event = candidate; break end
    end
    if not event then return false, "That event is no longer upcoming." end
    if event.preview then return false, "This is a local preview. Use /gd testraid40 clear to remove it." end
    if event.calendarSettings and event.calendarSettings.locked and not (event.rsvps and event.rsvps[self:PlayerName()]) then return false, "Sign-ups are locked for this event." end
    event.rsvps = event.rsvps or {}
    local player, ts = self:PlayerName(), time()
    local previous = event.rsvps[player]
    role = role or (type(previous) == "table" and previous.role) or "DPS"
    if role ~= "Tank" and role ~= "Healer" and role ~= "DPS" then return false, "Choose Tank, Healer, or DPS." end
    note = tostring(note or (type(previous) == "table" and previous.note) or ""):gsub("[\r\n]", " "):sub(1, 100)
    local deleted = event.signupDeletes and event.signupDeletes[player]
    ts = math.max(ts, type(previous) == "table" and (previous.ts or 0) + 1 or 0, deleted and deleted.ts + 1 or 0)
    spec = tostring(spec or (type(previous) == "table" and previous.spec) or ""):gsub("[\r\n]", " "):sub(1, 60)
    event.rsvps[player] = { status = status, ts = ts, role = role, spec = spec, note = note }
    sendRSVP(event.id, player, event.rsvps[player])
    local calendarSynced = syncGameCalendarRSVP and syncGameCalendarRSVP(event, status)
    if self.RefreshUI then self:RefreshUI() end
    local result = "RSVP saved as " .. status .. " for " .. event.title .. "."
    if calendarSynced then result = result .. " Your in-game guild-calendar signup was updated."
    else result = result .. " No matching native calendar entry was found, so this RSVP is in GuildDB only." end
    return true, result
end

function GD:SetRSVP(eventNumber, status)
    if not self.bucket then return false, "Join a guild first." end
    status = tostring(status or ""):lower()
    if status ~= "going" and status ~= "tentative" and status ~= "absent" then return false, "Choose going, tentative, or absent." end
    local event = upcomingEvents()[tonumber(eventNumber) or 0]
    if not event then return false, "No upcoming event has that number." end
    return self:SetRSVPForEvent(event.id, status)
end

function GD:AddEventToGameCalendar(eventId)
    local event
    for _, candidate in ipairs((self.bucket and self.bucket.events) or {}) do
        if candidate.id == eventId then event = candidate; break end
    end
    if not event then return false, "That GuildDB event could not be found." end

    local playerName = self:PlayerName()
    local eventOwner = tostring(event.by or ""):match("^([^-]+)") or tostring(event.by or "")
    playerName = tostring(playerName):match("^([^-]+)") or tostring(playerName)
    if playerName:lower() ~= eventOwner:lower() then
        return false, "Only the event creator can add it to the guild calendar, to prevent duplicate entries."
    end

    GDB = type(GDB) == "table" and GDB or {}
    GDB.calendarExports = type(GDB.calendarExports) == "table" and GDB.calendarExports or {}
    if GDB.calendarExports[eventId] then
        return false, "This event was already added to your in-game calendar on this character."
    end

    local calendar = C_Calendar
    if not calendar or type(calendar.CreateGuildSignUpEvent) ~= "function"
        or type(calendar.EventSetTitle) ~= "function" or type(calendar.EventSetDate) ~= "function"
        or type(calendar.EventSetTime) ~= "function" or type(calendar.AddEvent) ~= "function" then
        return false, "Your game client does not provide guild calendar event creation."
    end
    if type(C_DateAndTime) ~= "table" or type(C_DateAndTime.GetCalendarTimeFromEpoch) ~= "function" then
        return false, "Your game client does not provide calendar date conversion."
    end

    -- Calendar writes are protected by the game and must happen directly from
    -- a user click. Convert the shared Unix timestamp to the client's calendar
    -- date, then create a native guild sign-up event that guildmates can see.
    local settings = normalizeCalendarSettings(event.calendarSettings, event.eventType)
    if settings.inviteMode == "selected" and #parseInviteNames(settings.inviteNames) == 0 then
        return false, "Enter at least one player name or choose a different invitation option."
    end
    local inviteWarnings = {}
    local ok, err = pcall(function()
        local calendarTime = C_DateAndTime.GetCalendarTimeFromEpoch(event.at * 1000000)
        if type(calendarTime) ~= "table" or not calendarTime.year or not calendarTime.month
            or not calendarTime.monthDay or calendarTime.hour == nil or calendarTime.minute == nil then
            error("The event date could not be converted.")
        end
        calendar.CreateGuildSignUpEvent()
        calendar.EventSetTitle((event.title or "Guild event"):sub(1, 64))
        if type(calendar.EventSetType) == "function" then
            calendar.EventSetType(CALENDAR_TYPES[settings.category] or CALENDAR_TYPES.Other)
        end
        calendar.EventSetDate(calendarTime.month, calendarTime.monthDay, calendarTime.year)
        calendar.EventSetTime(calendarTime.hour, calendarTime.minute)
        if type(calendar.EventSetDescription) == "function" then
            calendar.EventSetDescription((event.details or ""):sub(1, 255))
        end
        for _, warning in ipairs(inviteCalendarGuests(calendar, settings)) do
            inviteWarnings[#inviteWarnings + 1] = warning
        end
        if settings.locked then
            if type(calendar.EventSetLocked) == "function" then calendar.EventSetLocked()
            else inviteWarnings[#inviteWarnings + 1] = "Locking sign-ups is unavailable in this client." end
        end
        calendar.AddEvent()
    end)
    if not ok then return false, "Could not add the calendar event: " .. tostring(err) end

    GDB.calendarExports[eventId] = time()
    if self.RefreshUI then self:RefreshUI() end
    local message = "Guild sign-up event added to the in-game calendar."
    if #inviteWarnings > 0 then message = message .. " " .. table.concat(inviteWarnings, " ") end
    return true, message
end

local function findGameCalendarEvent(event)
    local calendar = C_Calendar
    if not calendar or type(calendar.GetNumGuildEvents) ~= "function"
        or type(calendar.GetGuildEventInfo) ~= "function" or type(calendar.GetEventIndexInfo) ~= "function"
        or type(calendar.OpenEvent) ~= "function" then return nil, "Guild calendar lookup is unavailable." end
    local target = C_DateAndTime and C_DateAndTime.GetCalendarTimeFromEpoch
        and C_DateAndTime.GetCalendarTimeFromEpoch(event.at * 1000000)
    if not target then return nil, "Could not convert the event date for the game calendar." end

    local matches = {}
    for index = 1, (calendar.GetNumGuildEvents() or 0) do
        local info = calendar.GetGuildEventInfo(index)
        if info and info.calendarType == "GUILD_EVENT" and info.title == (event.title or ""):sub(1, 64)
            and info.year == target.year and info.month == target.month and info.monthDay == target.monthDay
            and info.hour == target.hour and info.minute == target.minute then
            local eventIndex = info.eventID and calendar.GetEventIndexInfo(info.eventID)
            if eventIndex then matches[#matches + 1] = { info = info, index = eventIndex } end
        end
    end
    if #matches == 0 then return nil, "No matching native guild-calendar entry was found." end
    if #matches > 1 then return nil, "More than one calendar entry matches; refusing to change an ambiguous entry." end
    local match = matches[1]
    if not calendar.OpenEvent(match.index.offsetMonths, match.index.monthDay, match.index.eventIndex) then
        return nil, "The native calendar entry could not be opened. Try again after the calendar finishes loading."
    end
    return match.info, nil, target, match.index
end

function GD:UpdateGameCalendarEvent(oldEvent, at, title, details, settings)
    local calendar = C_Calendar
    if not calendar or type(calendar.UpdateEvent) ~= "function" then
        return false, "Your game client does not provide calendar event editing."
    end
    local selected, reason = findGameCalendarEvent(oldEvent)
    if not selected then return false, reason end
    if type(calendar.EventCanEdit) == "function" and not calendar.EventCanEdit() then
        return false, "The game calendar does not grant this officer permission to edit that entry."
    end
    local target = C_DateAndTime.GetCalendarTimeFromEpoch(at * 1000000)
    settings = normalizeCalendarSettings(settings or oldEvent.calendarSettings, oldEvent.eventType)
    if settings.inviteMode == "selected" and #parseInviteNames(settings.inviteNames) == 0 then
        return false, "Enter at least one player name or choose a different invitation option."
    end
    local inviteWarnings = {}
    local ok, err = pcall(function()
        calendar.EventSetTitle((title or "Guild event"):sub(1, 64))
        if type(calendar.EventSetType) == "function" then
            calendar.EventSetType(CALENDAR_TYPES[settings.category] or CALENDAR_TYPES.Other)
        end
        calendar.EventSetDate(target.month, target.monthDay, target.year)
        calendar.EventSetTime(target.hour, target.minute)
        if calendar.EventSetDescription then calendar.EventSetDescription((details or ""):sub(1, 255)) end
        local currentInfo = type(calendar.GetEventInfo) == "function" and calendar.GetEventInfo() or nil
        for _, warning in ipairs(inviteCalendarGuests(calendar, settings, oldEvent.calendarSettings)) do
            inviteWarnings[#inviteWarnings + 1] = warning
        end
        if settings.locked and not (currentInfo and currentInfo.isLocked) then
            if type(calendar.EventSetLocked) == "function" then calendar.EventSetLocked()
            else inviteWarnings[#inviteWarnings + 1] = "Locking sign-ups is unavailable in this client." end
        elseif not settings.locked and currentInfo and currentInfo.isLocked then
            if type(calendar.EventClearLocked) == "function" then calendar.EventClearLocked()
            else inviteWarnings[#inviteWarnings + 1] = "Unlocking sign-ups is unavailable in this client." end
        end
        calendar.UpdateEvent()
    end)
    if not ok then return false, "Could not update the in-game calendar entry: " .. tostring(err) end
    return true, #inviteWarnings > 0 and table.concat(inviteWarnings, " ") or nil
end

function GD:RemoveGameCalendarEvent(event)
    local calendar = C_Calendar
    if not calendar or (type(calendar.RemoveEvent) ~= "function" and type(calendar.ContextMenuEventRemove) ~= "function") then
        return false, "Your game client does not provide calendar event removal."
    end
    local selected, reason, _, eventIndex = findGameCalendarEvent(event)
    if not selected then return false, reason end
    local ok, err
    if eventIndex and type(calendar.ContextMenuSelectEvent) == "function"
        and type(calendar.ContextMenuEventRemove) == "function" then
        local canRemove = type(calendar.ContextMenuEventCanRemove) ~= "function"
            or calendar.ContextMenuEventCanRemove(eventIndex.offsetMonths, eventIndex.monthDay, eventIndex.eventIndex)
        if not canRemove then return false, "The game calendar does not grant this officer permission to remove that entry." end
        ok, err = pcall(function()
            calendar.ContextMenuSelectEvent(eventIndex.offsetMonths, eventIndex.monthDay, eventIndex.eventIndex)
            calendar.ContextMenuEventRemove()
        end)
    else
        if type(calendar.RemoveEvent) ~= "function" then
            return false, "Your game client does not expose a usable calendar removal action."
        end
        if type(calendar.EventCanEdit) == "function" and not calendar.EventCanEdit() then
            return false, "The game calendar does not grant this officer permission to remove that entry."
        end
        ok, err = pcall(calendar.RemoveEvent)
    end
    if not ok then return false, "Could not remove the in-game calendar entry: " .. tostring(err) end
    return true
end

syncGameCalendarRSVP = function(event, status)
    local calendar = C_Calendar
    if not calendar then return false end
    local selected = findGameCalendarEvent(event)
    if not selected then return false end
    local action = status == "going" and calendar.EventSignUp
        or status == "tentative" and calendar.EventTentative
        or calendar.EventDecline
    if type(action) ~= "function" then return false end
    local ok = pcall(action)
    return ok
end

local function createCommand(rest, eventType)
    local dateText, title, details = rest:match("^(%d%d%d%d%-%d%d%-%d%d%s+%d%d:%d%d)%s*|%s*([^|]-)%s*|%s*(.*)$")
    local ok, result = GD:PostEvent(parseEventTime(dateText or ""), title, details, eventType)
    print("GuildDB: " .. result)
end

GD:RegisterCommand("event", function(rest) createCommand(rest, "event") end)
GD:RegisterCommand("raid", function(rest) createCommand(rest, "raid") end)
GD:RegisterCommand("rsvp", function(rest)
    local number, status = rest:match("^(%d+)%s+(%S+)$")
    local _, result = GD:SetRSVP(number, status)
    print("GuildDB: " .. result)
end)

GD:RegisterTab("Events", function()
    if not GD.bucket then return "Join a guild to see upcoming raids and events." end
    local upcoming = upcomingEvents()
    if #upcoming == 0 then return "No upcoming raids or events. Officers can schedule one with /gd raid or /gd event." end
    local player = UnitName and UnitName("player") or ""
    local lines = { "Upcoming raids and events", "RSVP with /gd rsvp # going, /gd rsvp # tentative, or /gd rsvp # absent.", "" }
    for index, event in ipairs(upcoming) do
        local counts = { going = 0, tentative = 0, absent = 0 }
        for _, response in pairs(event.rsvps or {}) do
            local status = type(response) == "table" and response.status or response
            if counts[status] then counts[status] = counts[status] + 1 end
        end
        local mine = event.rsvps and event.rsvps[player]
        if type(mine) == "table" then mine = mine.status end
        lines[#lines + 1] = ("%d. [%s] %s — %s"):format(index, event.eventType == "raid" and "RAID" or "EVENT", date("%a %d %b %Y, %I:%M %p", event.at), GD:Display(event.title))
        if event.details and event.details ~= "" then lines[#lines + 1] = GD:Display(event.details) end
        lines[#lines + 1] = ("Going: %d · Tentative: %d · Absent: %d · Your RSVP: %s"):format(counts.going, counts.tentative, counts.absent, mine or "Not set")
        lines[#lines + 1] = "Posted by " .. GD:Display(event.by)
        lines[#lines + 1] = ""
    end
    return table.concat(lines, "\n")
end)

-- Temporary local data for checking a full raid layout; never enters synced buckets.
GD:RegisterCommand("testraid40", function(rest)
    if tostring(rest or ""):lower():match("^%s*clear%s*$") then
        GD.raidPreviewEvent = nil
        if GD.RefreshUI then GD:RefreshUI() end
        print("GuildDB: 40-player preview removed.")
        return
    end
    local templates = {
        { "Warrior", "WARRIOR", "Protection", "Tank" },
        { "Paladin", "PALADIN", "Holy", "Healer" },
        { "Hunter", "HUNTER", "Marksmanship", "DPS" },
        { "Rogue", "ROGUE", "Combat", "DPS" },
        { "Priest", "PRIEST", "Holy", "Healer" },
        { "Shaman", "SHAMAN", "Restoration", "Healer" },
        { "Mage", "MAGE", "Frost", "DPS" },
        { "Warlock", "WARLOCK", "Affliction", "DPS" },
        { "Druid", "DRUID", "Feral", "Tank" },
        { "Warrior", "WARRIOR", "Fury", "DPS" },
    }
    local names = { "Aldren", "Bellara", "Caelthorn", "Duskblade", "Elowyn", "Frostmane", "Grimholt", "Hearthwick", "Ironbark", "Jorund", "Kaelara", "Luneth", "Mordain", "Nyssara", "Oakwarden", "Pyrestorm", "Quillshade", "Ravencrest", "Silverbrook", "Thornvale", "Umbralis", "Valewind", "Wildsong", "Xandriel", "Yarrow", "Zephyra", "Ashforge", "Brightwater", "Cinderveil", "Dawnwhisper", "Emberfall", "Flintguard", "Galestrider", "Hollowshade", "Ivorymoon", "Jadebranch", "Kestrelwind", "Lightwarden", "Moonbrook", "Nightwillow" }
    local event = { id = "local-raid-preview", preview = true, at = time() + 86400,
        title = "40-player layout test (local preview)", by = "GuildDB preview",
        details = "Temporary test roster: 40 signups, 34 Going, 4 Maybe, 2 Absent. Blue checks show 25 selected invites. Clear with /gd testraid40 clear.",
        calendarSettings = { category = "Raid", raidSize = 40, locked = true }, rsvps = {}, selections = {}, classes = {} }
    for index, baseName in ipairs(names) do
        local template = templates[(index - 1) % #templates + 1]
        local name = "Test " .. baseName
        event.classes[name] = { template[1], template[2] }
        event.rsvps[name] = { status = index <= 34 and "going" or index <= 38 and "tentative" or "absent",
            role = template[4], spec = template[3], ts = time(), note = index % 7 == 0 and "May arrive 10 minutes late" or "" }
        if index <= 25 then event.selections[name] = { selected = true, ts = time(), by = "GuildDB preview" } end
    end
    GD.raidPreviewEvent = event
    GD.activeTab = "Events"
    if GD.Open then GD:Open() end
    print("GuildDB: Showing 40 test signups locally. Remove with /gd testraid40 clear or /reload.")
end)

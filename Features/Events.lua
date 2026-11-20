-- Guild events, raid scheduling, attendee RSVPs, display, and sync.
local _, GH = ...
GH:RegisterBucket("events", function() return {} end)
GH:RegisterBucket("eventDeletes", function() return {} end)
local syncGameCalendarRSVP
local EVENT_SETTINGS_MARKER = "\n\n[GuildHall calendar settings]\n"
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
    local details = tostring(record.details or ""):gsub("%[GuildHall calendar settings%]", "[GuildHall settings]")
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
    for index, event in ipairs((GH.bucket and GH.bucket.events) or {}) do
        if event.id == id then return event, index end
    end
end

local function eventDeleteTimestamp(id)
    local value = (GH.bucket.eventDeletes or {})[id]
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
    if not GH.ShowPopout then return end
    local eventType = event.eventType == "raid" and "raid" or "event"
    local when = date("%a %b %d, %I:%M %p", event.at)
    local message = (event.by or "A guild officer") .. " scheduled " .. when
    if event.details and event.details ~= "" then message = message .. "\n" .. event.details end
    GH:ShowPopout(eventType == "raid" and "New guild raid" or "New guild event", event.title, message,
        eventType == "raid" and "Interface/Icons/INV_Misc_GroupLooking" or "Interface/Icons/INV_Misc_Note_01",
        function() GH.activeTab = "Events"; GH:Open() end, 8)
end

local function storeEvent(id, ts, author, content, eventType, sender)
    if #id > 100 or #author > 100 or #content > 900 then return end
    if not isOfficer(author) or eventDeleteTimestamp(id) >= ts then return end
    local at, title, remainder = content:match("^(.-)\n(.-)\n(.*)$")
    at = tonumber(at)
    if not at or not title then return end
    local details, metadata = remainder:match("^(.*)\n\n%[GuildHall calendar settings%]\n(.*)$")
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
    if current then GH.bucket.events[index] = event else table.insert(GH.bucket.events, 1, event) end
    if GH.RefreshUI then GH:RefreshUI() end
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

function GH:PostEvent(at, title, details, eventType, calendarSettings)
    if not self:CanManage() then return false, "Only the guild leader or rank 1 can post events." end
    if not at or not title or title == "" then return false, "Enter a valid date, time, and event title." end
    eventType = eventType == "raid" and "raid" or "event"
    local settings = normalizeCalendarSettings(calendarSettings, eventType)
    eventType = settings.category == "Raid" and "raid" or "event"
    local record = self:NewRecord({ at = at, title = title:sub(1, 100), details = (details or ""):sub(1, 300), eventType = eventType, calendarSettings = settings, rsvps = {} })
    local kind = eventType == "raid" and "D" or "E"
    self:StoreRecord("events", record, kind, encodeEvent(record))
    showEventPopout(record)
    return true, (eventType == "raid" and "Raid" or "Event") .. " saved and sent to online Guild Hall users.", record.id
end

local function onEventRecord(kind, id, ts, author, content, sender)
    storeEvent(id, ts, author, content, kind == "D" and "raid" or "event", sender)
end
GH:RegisterRecordHandler("E", function(...) onEventRecord("E", ...) end)
GH:RegisterRecordHandler("D", function(...) onEventRecord("D", ...) end)

GH:RegisterRecordHandler("EVX", function(id, ts, author)
    if #id > 100 or #author > 100 or not isOfficer(author) or eventDeleteTimestamp(id) >= ts then return end
    GH.bucket.eventDeletes = GH.bucket.eventDeletes or {}
    GH.bucket.eventDeletes[id] = { ts = ts, by = author }
    local _, index = findEvent(id)
    if index then table.remove(GH.bucket.events, index) end
    if GH.RefreshUI then GH:RefreshUI() end
end)

function GH:EditEvent(eventId, at, title, details, calendarSettings)
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
    local result = "Event updated and shared with online Guild Hall users."
    if calendarUpdated then
        result = result .. " The in-game guild-calendar entry was updated."
        if calendarMessage then result = result .. " " .. calendarMessage end
    elseif calendarMessage and calendarMessage ~= "No matching native guild-calendar entry was found." then
        result = result .. " Calendar copy unchanged: " .. calendarMessage
    end
    return true, result
end

function GH:DeleteEvent(eventId)
    if not self:CanManage() then return false, "Only the guild leader or rank 1 can remove events." end
    local event, index = findEvent(eventId)
    if not event then return false, "That event is no longer available." end
    local player = self:PlayerName()
    local removedCalendarEntry, calendarMessage = self:RemoveGameCalendarEvent(event)
    if removedCalendarEntry and GuildHallDB and GuildHallDB.calendarExports then
        GuildHallDB.calendarExports[eventId] = nil
    end
    local ts = math.max(time(), (event.ts or 0) + 1)
    table.remove(self.bucket.events, index)
    self.bucket.eventDeletes = self.bucket.eventDeletes or {}
    self.bucket.eventDeletes[eventId] = { ts = ts, by = player }
    self:SendRecord("EVX", eventId, ts, player, "")
    if self.RefreshUI then self:RefreshUI() end
    local result = "Event removed from Guild Hall and synced with online Guild Hall users."
    if removedCalendarEntry then result = result .. " The in-game guild-calendar entry was removed."
    elseif calendarMessage and calendarMessage ~= "No matching native guild-calendar entry was found." then
        result = result .. " Calendar copy unchanged: " .. calendarMessage
    end
    return true, result
end

GH:RegisterRecordHandler("R", function(id, ts, author, content)
    local status, role, spec, note = content:match("^(.-)\n(.-)\n(.-)\n(.*)$")
    if not status then status, role, note = content:match("^(.-)\n(.-)\n(.*)$") end
    status = (status or content):lower()
    if role and role ~= "Tank" and role ~= "Healer" and role ~= "DPS" then return end
    if note and #note > 100 then return end
    if spec and #spec > 60 then return end
    if status ~= "going" and status ~= "tentative" and status ~= "absent" then return end
    for _, event in ipairs(GH.bucket.events or {}) do
        if event.id == id then
            event.rsvps = event.rsvps or {}
            local previous = event.rsvps[author]
            local deleted = event.signupDeletes and event.signupDeletes[author]
            if deleted and deleted.ts >= ts then return end
            if previous and type(previous) == "table" and previous.ts >= ts then return end
            event.rsvps[author] = { status = status, ts = ts, role = role, spec = spec, note = note }
            if GH.RefreshUI then GH:RefreshUI() end
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
    GH:SendRecord("R", eventId, ts, player, content)
end

function GH:IsRaidGM(name)
    local wanted = name or self:PlayerName()
    for index = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
        local member, _, rank = GetGuildRosterInfo(index)
        if samePlayerName(member, wanted) then return rank == 0 end
    end
    return false
end

-- Class comes from the live guild roster, including offline members.
function GH:GetRaidPlayerClass(name)
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

function GH:GetRaidSignupSummary(event)
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

GH:RegisterRecordHandler("RX", function(id, ts, author, player)
    if #player > 100 or player == "" then return end
    if not samePlayerName(player, author) and not GH:IsRaidGM(author) then return end
    local event = findEvent(id)
    if event and removeSignup(event, player, ts, author) and GH.RefreshUI then GH:RefreshUI() end
end)

function GH:RemoveRaidSignup(eventId, player)
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

GH:RegisterRecordHandler("RI", function(id, ts, author, content)
    if not GH:IsRaidGM(author) then return end
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
    if GH.RefreshUI then GH:RefreshUI() end
end)

function GH:SetRaidSelection(eventId, player, selected)
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

GH:RegisterHistoryProvider(function()
    local events = GH.bucket.events or {}
    for i = math.min(#events, 12), 1, -1 do
        local event = events[i]
        GH:SendRecord(event.eventType == "raid" and "D" or "E", event.id, event.ts, event.by, encodeEvent(event))
        for player, removal in pairs(event.signupDeletes or {}) do
            GH:SendRecord("RX", event.id, removal.ts, removal.by, player)
        end
        for player, response in pairs(event.rsvps or {}) do sendRSVP(event.id, player, response) end
        for player, selection in pairs(event.selections or {}) do
            GH:SendRecord("RI", event.id, selection.ts, selection.by, player .. "\n" .. (selection.selected and "1" or "0"))
        end
    end
    for id, info in pairs(GH.bucket.eventDeletes or {}) do
        local ts = type(info) == "table" and info.ts or tonumber(info)
        local author = type(info) == "table" and info.by or nil
        if ts and author then GH:SendRecord("EVX", id, ts, author, "") end
    end
end)

local function upcomingEvents()
    local events = {}
    for _, event in ipairs((GH.bucket and GH.bucket.events) or {}) do
        if event.at >= time() then events[#events + 1] = event end
    end
    table.sort(events, function(a, b) return a.at < b.at end)
    return events
end
GH.GetUpcomingEvents = upcomingEvents

function GH:PostEventFields(dateText, timeText, title, details, eventType, calendarSettings)
    local at = parseEventTime(tostring(dateText or "") .. " " .. tostring(timeText or ""))
    return self:PostEvent(at, title, details, eventType, calendarSettings)
end

function GH:ParseEventTimeFields(dateText, timeText)
    return parseEventTime(tostring(dateText or "") .. " " .. tostring(timeText or ""))
end

function GH:SetRSVPForEvent(eventId, status, role, note, spec)
    if not self.bucket then return false, "Join a guild first." end
    status = tostring(status or ""):lower()
    if status ~= "going" and status ~= "tentative" and status ~= "absent" then return false, "Choose going, tentative, or absent." end
    local event
    for _, candidate in ipairs(upcomingEvents()) do
        if candidate.id == eventId then event = candidate; break end
    end
    if not event then return false, "That event is no longer upcoming." end
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
    else result = result .. " No matching native calendar entry was found, so this RSVP is in Guild Hall only." end
    return true, result
end

function GH:SetRSVP(eventNumber, status)
    if not self.bucket then return false, "Join a guild first." end
    status = tostring(status or ""):lower()
    if status ~= "going" and status ~= "tentative" and status ~= "absent" then return false, "Choose going, tentative, or absent." end
    local event = upcomingEvents()[tonumber(eventNumber) or 0]
    if not event then return false, "No upcoming event has that number." end
    return self:SetRSVPForEvent(event.id, status)
end

function GH:AddEventToGameCalendar(eventId)
    local event
    for _, candidate in ipairs((self.bucket and self.bucket.events) or {}) do
        if candidate.id == eventId then event = candidate; break end
    end
    if not event then return false, "That Guild Hall event could not be found." end

    local playerName = self:PlayerName()
    local eventOwner = tostring(event.by or ""):match("^([^-]+)") or tostring(event.by or "")
    playerName = tostring(playerName):match("^([^-]+)") or tostring(playerName)
    if playerName:lower() ~= eventOwner:lower() then
        return false, "Only the event creator can add it to the guild calendar, to prevent duplicate entries."
    end

    GuildHallDB = type(GuildHallDB) == "table" and GuildHallDB or {}
    GuildHallDB.calendarExports = type(GuildHallDB.calendarExports) == "table" and GuildHallDB.calendarExports or {}
    if GuildHallDB.calendarExports[eventId] then
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

    GuildHallDB.calendarExports[eventId] = time()
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

function GH:UpdateGameCalendarEvent(oldEvent, at, title, details, settings)
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

function GH:RemoveGameCalendarEvent(event)
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
    local ok, result = GH:PostEvent(parseEventTime(dateText or ""), title, details, eventType)
    print("Guild Hall: " .. result)
end

GH:RegisterCommand("event", function(rest) createCommand(rest, "event") end)
GH:RegisterCommand("raid", function(rest) createCommand(rest, "raid") end)
GH:RegisterCommand("rsvp", function(rest)
    local number, status = rest:match("^(%d+)%s+(%S+)$")
    local _, result = GH:SetRSVP(number, status)
    print("Guild Hall: " .. result)
end)

GH:RegisterTab("Events", function()
    if not GH.bucket then return "Join a guild to see upcoming raids and events." end
    local upcoming = upcomingEvents()
    if #upcoming == 0 then return "No upcoming raids or events. Officers can schedule one with /gh raid or /gh event." end
    local player = UnitName and UnitName("player") or ""
    local lines = { "Upcoming raids and events", "RSVP with /gh rsvp # going, /gh rsvp # tentative, or /gh rsvp # absent.", "" }
    for index, event in ipairs(upcoming) do
        local counts = { going = 0, tentative = 0, absent = 0 }
        for _, response in pairs(event.rsvps or {}) do
            local status = type(response) == "table" and response.status or response
            if counts[status] then counts[status] = counts[status] + 1 end
        end
        local mine = event.rsvps and event.rsvps[player]
        if type(mine) == "table" then mine = mine.status end
        lines[#lines + 1] = ("%d. [%s] %s — %s"):format(index, event.eventType == "raid" and "RAID" or "EVENT", date("%a %b %d, %I:%M %p", event.at), GH:Display(event.title))
        if event.details and event.details ~= "" then lines[#lines + 1] = GH:Display(event.details) end
        lines[#lines + 1] = ("Going: %d · Tentative: %d · Absent: %d · Your RSVP: %s"):format(counts.going, counts.tentative, counts.absent, mine or "Not set")
        lines[#lines + 1] = "Posted by " .. GH:Display(event.by)
        lines[#lines + 1] = ""
    end
    return table.concat(lines, "\n")
end)

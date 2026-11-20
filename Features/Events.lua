-- Guild events, raid scheduling, attendee RSVPs, display, and sync.
local _, GH = ...
GH:RegisterBucket("events", function() return {} end)

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
    return table.concat({ record.at, record.title, record.details or "" }, "\n")
end

function GH:PostEvent(at, title, details, eventType)
    if not self:CanManage() then return false, "Only the guild leader or rank 1 can post events." end
    if not at or not title or title == "" then return false, "Enter a valid date, time, and event title." end
    eventType = eventType == "raid" and "raid" or "event"
    local record = self:NewRecord({ at = at, title = title:sub(1, 100), details = (details or ""):sub(1, 300), eventType = eventType, rsvps = {} })
    local kind = eventType == "raid" and "D" or "E"
    self:StoreRecord("events", record, kind, encodeEvent(record))
    return true, (eventType == "raid" and "Raid" or "Event") .. " saved and sent to online Guild Hall users."
end

local function onEventRecord(kind, id, ts, author, content)
    local at, title, details = content:match("^(.-)\n(.-)\n(.*)$")
    at = tonumber(at)
    if not at or not title or #title > 100 or #details > 300 then return end
    GH:StoreRecord("events", { id = id, ts = ts, by = author, at = at, title = title, details = details, eventType = kind == "D" and "raid" or "event", rsvps = {} })
end
GH:RegisterRecordHandler("E", function(...) onEventRecord("E", ...) end)
GH:RegisterRecordHandler("D", function(...) onEventRecord("D", ...) end)

GH:RegisterRecordHandler("R", function(id, ts, author, content)
    local status = content:lower()
    if status ~= "going" and status ~= "tentative" and status ~= "absent" then return end
    for _, event in ipairs(GH.bucket.events or {}) do
        if event.id == id then
            event.rsvps = event.rsvps or {}
            local previous = event.rsvps[author]
            if previous and type(previous) == "table" and previous.ts > ts then return end
            event.rsvps[author] = { status = status, ts = ts }
            if GH.RefreshUI then GH:RefreshUI() end
            return
        end
    end
end)

local function sendRSVP(eventId, player, response)
    local status = type(response) == "table" and response.status or response
    local ts = type(response) == "table" and response.ts or time()
    GH:SendRecord("R", eventId, ts, player, status)
end

GH:RegisterHistoryProvider(function()
    local events = GH.bucket.events or {}
    for i = math.min(#events, 12), 1, -1 do
        local event = events[i]
        GH:SendRecord(event.eventType == "raid" and "D" or "E", event.id, event.ts, event.by, encodeEvent(event))
        for player, response in pairs(event.rsvps or {}) do sendRSVP(event.id, player, response) end
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

function GH:PostEventFields(dateText, timeText, title, details, eventType)
    local at = parseEventTime(tostring(dateText or "") .. " " .. tostring(timeText or ""))
    return self:PostEvent(at, title, details, eventType)
end

function GH:SetRSVPForEvent(eventId, status)
    if not self.bucket then return false, "Join a guild first." end
    status = tostring(status or ""):lower()
    if status ~= "going" and status ~= "tentative" and status ~= "absent" then return false, "Choose going, tentative, or absent." end
    local event
    for _, candidate in ipairs(upcomingEvents()) do
        if candidate.id == eventId then event = candidate; break end
    end
    if not event then return false, "That event is no longer upcoming." end
    event.rsvps = event.rsvps or {}
    local player, ts = UnitName and UnitName("player") or "Guild member", time()
    event.rsvps[player] = { status = status, ts = ts }
    sendRSVP(event.id, player, event.rsvps[player])
    if self.RefreshUI then self:RefreshUI() end
    return true, "RSVP saved as " .. status .. " for " .. event.title .. "."
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

    local playerName = UnitName and UnitName("player") or ""
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
    local ok, err = pcall(function()
        local calendarTime = C_DateAndTime.GetCalendarTimeFromEpoch(event.at * 1000000)
        if type(calendarTime) ~= "table" or not calendarTime.year or not calendarTime.month
            or not calendarTime.monthDay or calendarTime.hour == nil or calendarTime.minute == nil then
            error("The event date could not be converted.")
        end
        calendar.CreateGuildSignUpEvent()
        calendar.EventSetTitle((event.title or "Guild event"):sub(1, 64))
        calendar.EventSetDate(calendarTime.month, calendarTime.monthDay, calendarTime.year)
        calendar.EventSetTime(calendarTime.hour, calendarTime.minute)
        if type(calendar.EventSetDescription) == "function" then
            calendar.EventSetDescription((event.details or ""):sub(1, 255))
        end
        calendar.AddEvent()
    end)
    if not ok then return false, "Could not add the calendar event: " .. tostring(err) end

    GuildHallDB.calendarExports[eventId] = time()
    if self.RefreshUI then self:RefreshUI() end
    return true, "Guild sign-up event added to the in-game calendar."
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

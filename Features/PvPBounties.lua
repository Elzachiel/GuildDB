-- Automatic revenge bounties. Replaying immutable combat records makes awards
-- independent of which guild peer receives kill/death packets first.
local _, GD = ...
GD:RegisterBucket("pvpBountyEvents", function() return {} end)
local CREDIT_WINDOW = 10

local function nameKey(name)
    return tostring(name or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function resetTime()
    return (GD.bucket.pvpReset or {}).ts or 0
end

function GD:RecordPvPBountyEvent(kind, record, broadcast)
    if not self.bucket then return end
    local enemy = kind == "D" and record.killer or record.victim
    if (kind ~= "D" and kind ~= "K") or type(enemy) ~= "string" or nameKey(enemy) == ""
        or #enemy > 100 or type(record.id) ~= "string" or #record.id > 100
        or type(record.by) ~= "string" or nameKey(record.by) == "" or #record.by > 100
        or type(record.ts) ~= "number" or record.ts <= resetTime() or record.ts > time() + 60 then return end
    local events = self.bucket.pvpBountyEvents
    local key = kind .. "\n" .. nameKey(record.by) .. "\n" .. record.id
    if events[key] then return end
    events[key] = { id = record.id, key = key, kind = kind, enemy = enemy, by = record.by, ts = record.ts }
    self.pvpBountyCache = nil
    if broadcast then
        self:SendRecord("PB", record.id, record.ts, record.by, table.concat({ resetTime(), kind, enemy }, "\n"))
    end
    if kind == "K" and C_Timer and C_Timer.After then
        local bucket = self.bucket
        C_Timer.After(CREDIT_WINDOW + 1, function()
            if GD.bucket == bucket and GD.activeTab == "PvP" and GD.RefreshUI then GD:RefreshUI() end
        end)
    end
end

GD:RegisterRecordHandler("PB", function(id, ts, author, content)
    local reset, kind, enemy = content:match("^(%d+)\n([DK])\n([^\n]+)$")
    if tonumber(reset) ~= resetTime() then return end
    GD:RecordPvPBountyEvent(kind, { id = id, ts = ts, by = author, killer = enemy, victim = enemy })
    if GD.RefreshUI then GD:RefreshUI() end
end)

local function state()
    -- Import retained records from older clients too. Counters alone do not
    -- contain enough chronology to determine whether a bounty was claimed.
    for _, record in ipairs(GD.bucket.pvpDeaths or {}) do GD:RecordPvPBountyEvent("D", record) end
    for _, record in ipairs(GD.bucket.pvpKills or {}) do GD:RecordPvPBountyEvent("K", record) end
    local events = GD.bucket.pvpBountyEvents
    local cache = GD.pvpBountyCache
    if cache and cache.events == events then return cache end
    local ordered = {}
    for _, event in pairs(events) do ordered[#ordered + 1] = event end
    table.sort(ordered, function(a, b)
        if a.ts ~= b.ts then return a.ts < b.ts end
        -- Timestamps have one-second precision: damage/death evidence is
        -- applied before kill credits within that second on every client.
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.key < b.key
    end)
    cache = { events = events, enemies = {}, awards = {} }
    for _, event in ipairs(ordered) do
        local key = nameKey(event.enemy)
        local enemy = cache.enemies[key] or { name = event.enemy, deaths = 0, last = 0 }
        cache.enemies[key] = enemy
        enemy.last = math.max(enemy.last, event.ts)
        if event.kind == "D" then
            enemy.deaths = enemy.deaths + 1
        else
            local claim = enemy.claim
            if not claim or event.ts > claim.ts + CREDIT_WINDOW then
                claim = nil
                if enemy.deaths >= 3 then
                    claim = { ts = event.ts, reward = math.min(10, enemy.deaths), members = {} }
                    enemy.claim, enemy.deaths = claim, 0
                    cache.awards[#cache.awards + 1] = claim
                end
            end
            if claim and not claim.members[nameKey(event.by)] then
                claim.members[nameKey(event.by)] = { name = event.by, ts = event.ts }
            end
        end
    end
    GD.pvpBountyCache = cache
    return cache
end

function GD:GetPvPBountyPoints(start, finish)
    local points = {}
    if not self.bucket then return points end
    for _, award in ipairs(state().awards) do
        for key, member in pairs(award.members) do
            if member.ts >= start and member.ts < finish then
                local row = points[key] or { name = member.name, points = 0 }
                row.points = row.points + award.reward
                points[key] = row
            end
        end
    end
    return points
end

function GD:GetPvPBounties()
    local rows = {}
    if not self.bucket then return rows end
    for _, enemy in pairs(state().enemies) do
        -- Enemies with only our kills and no bounty activity need no target row.
        if enemy.deaths > 0 or enemy.claim then
            local claiming = enemy.claim and time() <= enemy.claim.ts + CREDIT_WINDOW
            local open = enemy.deaths >= 3 and not claiming
            local reward = open and math.min(10, enemy.deaths)
                or (claiming or enemy.deaths == 0) and enemy.claim and enemy.claim.reward or 0
            rows[#rows + 1] = { name = enemy.name, deaths = enemy.deaths, reward = reward,
                status = open and "OPEN" or claiming and "CLAIM" or enemy.deaths > 0 and "WAIT" or "PAID",
                last = enemy.last }
        end
    end
    table.sort(rows, function(a, b)
        local order = { OPEN = 4, CLAIM = 3, WAIT = 2, PAID = 1 }
        if order[a.status] ~= order[b.status] then return order[a.status] > order[b.status] end
        if a.reward ~= b.reward then return a.reward > b.reward end
        if a.deaths ~= b.deaths then return a.deaths > b.deaths end
        return a.name:lower() < b.name:lower()
    end)
    return rows
end

GD:RegisterHistoryProvider(function()
    state()
    for _, event in pairs(GD.bucket.pvpBountyEvents) do
        GD:SendRecord("PB", event.id, event.ts, event.by, table.concat({ resetTime(), event.kind, event.enemy }, "\n"))
    end
end)

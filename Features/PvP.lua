-- Outdoor player-versus-player kill tracking and leaderboard.
local _, GH = ...
GH:RegisterBucket("pvpKills", function() return {} end)
GH:RegisterBucket("pvpDeaths", function() return {} end)
GH:RegisterBucket("pvpTotals", function() return {} end)
GH:RegisterBucket("pvpSeason", function() return { name = "All-time", start = 0, ts = 0 } end)
GH:RegisterBucket("pvpReset", function() return { ts = 0 } end)
GH:RegisterBucket("pvpSeasons", function() return {} end)
GH:RegisterBucket("pvpSeasonDeletes", function() return {} end)
local seenPlayers = {}
local honorCredits = {}
local creditScheduled = false
local lastTarget
local captureVisiblePlayers
local unmatchedCredit
local retryGroupCredit
local groupEvidence = {}

-- Combat unit APIs may return protected values on this client. Never let a
-- failed optional unit read prevent an honor reward from being processed.
local function readable(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function unitValue(api, unit)
    if not api then return nil end
    local ok, value = pcall(api, unit)
    if ok then return readable(value) end
end

local function refreshVisiblePlayers()
    if captureVisiblePlayers then pcall(captureVisiblePlayers) end
end

local function trackingNote(message)
    GH.pvpTrackingStatus = message
end

local function totalsKey(start, player)
    return tostring(start) .. "|" .. player
end

local function playerName()
    return GH.PlayerName and GH:PlayerName() or (UnitName and UnitName("player") or "Guild member")
end

local function resetTime()
    return (GH.bucket.pvpReset or {}).ts or 0
end

local function guildLeader(name)
    if not GetNumGuildMembers or not GetGuildRosterInfo then return false end
    local wanted = (tostring(name or ""):match("^([^-]+)") or ""):lower()
    for index = 1, GetNumGuildMembers() do
        local member, _, rank = GetGuildRosterInfo(index)
        if member and (member:match("^([^-]+)") or member):lower() == wanted then
            return tonumber(rank) == 0
        end
    end
    return false
end

function GH:CanManagePvPSeason()
    return self.bucket ~= nil and guildLeader(playerName())
end

local function deleteSeason(start, stamp, author)
    local key = tostring(start)
    local previous = GH.bucket.pvpSeasonDeletes[key]
    if previous and previous.ts >= stamp then return end
    GH.bucket.pvpSeasonDeletes[key] = { ts = stamp, by = author }
    GH.bucket.pvpSeasons[key] = nil
    for id, totals in pairs(GH.bucket.pvpTotals) do
        if totals.start == start then GH.bucket.pvpTotals[id] = nil end
    end
    if GH.bucket.pvpSeason.start == start then
        GH.bucket.pvpSeason = { name = "All-time", start = 0, ts = stamp, by = author }
    end
    if GH.RefreshUI then GH:RefreshUI() end
end

function GH:DeletePvPSeason(start)
    if not self:CanManagePvPSeason() then return false, "Only the guild master can delete seasons." end
    start = tonumber(start)
    if not start or start <= 0 then return false, "Select a season first. All-time cannot be deleted here." end
    deleteSeason(start, time(), playerName())
    self:SendRecord("PD", tostring(start), time(), playerName(), "")
    return true, "Season deleted. All-time stats were kept."
end

GH:RegisterRecordHandler("PD", function(id, ts, author)
    local start = tonumber(id)
    if not start or start <= 0 or not guildLeader(author) or ts <= resetTime() or ts > time() + 60 then return end
    deleteSeason(start, ts, author)
end)

local function applyReset(stamp, author)
    if stamp <= resetTime() then return end
    GH.bucket.pvpReset = { ts = stamp, by = author }
    GH.bucket.pvpSeasonDeletes = {}
    GH.bucket.pvpKills, GH.bucket.pvpDeaths, GH.bucket.pvpTotals, GH.bucket.pvpSeasons = {}, {}, {}, {}
    GH.bucket.pvpSeason = { name = "All-time", start = 0, ts = stamp, by = author }
    honorCredits, seenPlayers = {}, {}
    unmatchedCredit, lastTarget, groupEvidence = nil, nil, {}
    if GuildHallDB then GuildHallDB.pvpHistory = {} end
    if GH.RefreshUI then GH:RefreshUI() end
end

GH:RegisterRecordHandler("PR", function(id, ts, author)
    if id ~= "wipe" or not guildLeader(author) or ts > time() + 60 then return end
    applyReset(ts, author)
end)

function GH:WipePvPStats()
    if not self.bucket then return false, "Join a guild first." end
    if not guildLeader(playerName()) then return false, "Only the guild master can wipe PvP stats." end
    local stamp = math.max(time(), resetTime() + 1)
    applyReset(stamp, playerName())
    self:SendRecord("PR", "wipe", stamp, playerName(), "")
    return true, "All guild PvP stats and seasons reset. Updated members receive the reset through guild sync."
end

local function isOpenWorld()
    if IsInInstance then
        local ok, inside, kind = pcall(IsInInstance)
        if ok and readable(inside) then return false end
        kind = ok and readable(kind) or nil
        if type(kind) == "string" and kind ~= "" and kind ~= "none" then return false end
    end
    for _, name in ipairs({ "IsBattleground", "IsArena" }) do
        local check = C_PvP and C_PvP[name]
        if check then
            local ok, active = pcall(check)
            if ok and readable(active) then return false end
        end
    end
    return true
end

local function sendTotals(start, player, totals)
    totals.id = "totals:" .. totalsKey(start, player)
    totals.ts = time()
    totals.by = player
    GH:SendRecord("Z", totals.id, totals.ts, player,
        table.concat({ start, totals.kills or 0, totals.kills or 0, totals.deaths or 0, resetTime() }, "\n"))
end

local function addLocalStat(field, points)
    if not GH.bucket then return end
    local player = playerName()
    local season = GH.bucket.pvpSeason or { start = 0 }
    local starts = { 0 }
    if (season.start or 0) > 0 and (not season.ends or season.ends == 0 or time() < season.ends) then
        starts[#starts + 1] = season.start
    end
    for _, start in ipairs(starts) do
        local key = totalsKey(start, player)
        local totals = GH.bucket.pvpTotals[key]
        if not totals then
            totals = { start = start, by = player, kills = 0, points = 0, deaths = 0 }
            for _, kill in ipairs(GH.bucket.pvpKills or {}) do
                if kill.by == player and kill.ts >= start then
                    totals.kills = totals.kills + 1
                    totals.points = totals.points + (tonumber(kill.points) or 1)
                end
            end
            for _, death in ipairs(GH.bucket.pvpDeaths or {}) do
                if death.by == player and death.ts >= start then totals.deaths = totals.deaths + 1 end
            end
        end
        totals[field] = (totals[field] or 0) + 1
        totals.points = totals.kills or 0
        GH.bucket.pvpTotals[key] = totals
        sendTotals(start, player, totals)
    end
end

local function encodeKill(record)
    return table.concat({ record.victim, record.victimLevel or 0, record.points or 1 }, "\n")
end

local function normalizedName(name)
    local baseName = tostring(name or ""):match("^([^-]+)") or tostring(name or "")
    return baseName:lower():gsub("%s", "")
end

local function historyFor(victim)
    if type(GuildHallDB) ~= "table" then GuildHallDB = {} end
    if type(GuildHallDB.pvpHistory) ~= "table" then GuildHallDB.pvpHistory = {} end
    local now = time()
    if now - (GuildHallDB.pvpHistoryPruned or 0) > 3600 then
        for key, stamps in pairs(GuildHallDB.pvpHistory) do
            local fresh = {}
            if type(stamps) == "table" then
                for _, stamp in ipairs(stamps) do
                    if type(stamp) == "number" and now - stamp < 86400 then fresh[#fresh + 1] = stamp end
                end
            end
            GuildHallDB.pvpHistory[key] = #fresh > 0 and fresh or nil
        end
        GuildHallDB.pvpHistoryPruned = now
    end
    local player = playerName()
    local key = normalizedName(player) .. "|" .. normalizedName(victim)
    local history = GuildHallDB.pvpHistory[key]
    if type(history) ~= "table" then history = {}; GuildHallDB.pvpHistory[key] = history end
    local fresh = {}
    for _, stamp in ipairs(history) do
        if type(stamp) == "number" and now - stamp < 86400 then fresh[#fresh + 1] = stamp end
    end
    GuildHallDB.pvpHistory[key] = fresh
    return fresh, now
end

local function recordKill(victim, victimLevel, outdoors)
    if not GH.bucket then trackingNote("No guild data available"); return end
    if not outdoors then trackingNote("Reward ignored: instanced area"); return end
    if not victim or victim == "" then trackingNote("Reward received without an identified enemy"); return end
    local history, now = historyFor(victim)
    if #history > 0 and now - history[#history] < 300 then trackingNote("Repeat victim: five-minute limit"); return end
    if #history >= 5 then trackingNote("Repeat victim: daily limit"); return end
    history[#history + 1] = now
    local level = tonumber(victimLevel) or 0
    local ownLevel = tonumber(unitValue(UnitLevel, "player")) or 60
    if level == -1 then level = math.min(60, ownLevel + 10)
    elseif level <= 0 then level = ownLevel end
    local record = GH:NewRecord({ victim = victim, victimLevel = level, points = 1 })
    record.id = tostring(time()) .. "-pvp-" .. tostring(math.random(100000, 999999))
    addLocalStat("kills", record.points)
    trackingNote("Recorded " .. victim .. ": +" .. record.points .. " points")
    if GH.ShowPvPPopup then
        local player = playerName()
        local seasonStart = (GH.bucket.pvpSeason or {}).start or 0
        local totals = GH.bucket.pvpTotals[totalsKey(seasonStart, player)]
        GH:ShowPvPPopup(record.points, victim, level, totals and totals.kills or 1)
    end
    GH:StoreRecord("pvpKills", record, "P", encodeKill(record))
    return true
end

GH:RegisterRecordHandler("P", function(id, ts, author, content, sender)
    if ts <= resetTime() then return end
    local victim, level, points = content:match("^(.-)\n(%d+)\n(%d+)$")
    level, points = tonumber(level), tonumber(points)
    if not victim or victim == "" or #victim > 100 or not level or level > 100 or not points or points < 1 or points > 5 then return end
    GH:StoreRecord("pvpKills", { id = id, ts = ts, by = author, victim = victim, victimLevel = level, points = points })
    if retryGroupCredit then retryGroupCredit(ts, author, sender, victim, level) end
end)

GH:RegisterRecordHandler("X", function(id, ts, author, content)
    if ts <= resetTime() then return end
    local killer = content:gsub("^%s+", ""):gsub("%s+$", "")
    if killer == "" or #killer > 100 then return end
    GH:StoreRecord("pvpDeaths", { id = id, ts = ts, by = author, killer = killer })
end)

GH:RegisterRecordHandler("Y", function(id, ts, author, content)
    if ts <= resetTime() then return end
    if not guildLeader(author) then return end
    local name, start, ends = content:match("^(.-)\n(%d+)\n(%d+)$")
    if not name then name, start = content:match("^(.-)\n(%d+)$") end
    start = tonumber(start)
    if start and GH.bucket.pvpSeasonDeletes[tostring(start)] then return end
    ends = tonumber(ends) or 0
    if not name or name == "" or #name > 80 or not start then return end
    if id ~= "season" and id ~= "season:" .. tostring(start) then return end
    if ends ~= 0 and ends <= start then return end
    local current = GH.bucket.pvpSeason or {}
    local saved = GH.bucket.pvpSeasons[tostring(start)]
    local incoming = { name = name, start = start, ends = ends, ts = ts, by = author }
    if not saved or (saved.ts or 0) <= ts then GH.bucket.pvpSeasons[tostring(start)] = incoming end
    if id == "season" and (current.ts or 0) <= ts then
        if (current.start or 0) > 0 then
            local previous = GH.bucket.pvpSeasons[tostring(current.start)]
            if not previous or (previous.ts or 0) < (current.ts or 0) then
                GH.bucket.pvpSeasons[tostring(current.start)] = current
            end
        end
        GH.bucket.pvpSeason = incoming
        GH.bucket.pvpSeasons[tostring(start)] = incoming
    end
    if GH.RefreshUI then GH:RefreshUI() end
end)

GH:RegisterRecordHandler("Z", function(id, ts, author, content)
    local body, epoch = content:match("^(.*)\n(%d+)$")
    if body and select(2, content:gsub("\n", "")) == 4 then
        if tonumber(epoch) ~= resetTime() then return end
        content = body
    elseif resetTime() > 0 then return end
    local start, kills, points, deaths = content:match("^(%d+)\n(%d+)\n(%d+)\n(%d+)$")
    start, kills, points, deaths = tonumber(start), tonumber(kills), tonumber(points), tonumber(deaths)
    if start and GH.bucket.pvpSeasonDeletes[tostring(start)] then return end
    if not start or not kills or not points or not deaths or #author > 100 then return end
    local key = totalsKey(start, author)
    local current = GH.bucket.pvpTotals[key]
    if not current or kills > (current.kills or 0) or points > (current.points or 0) or deaths > (current.deaths or 0) then
        GH.bucket.pvpTotals[key] = { start = start, by = author, kills = math.max(kills, current and current.kills or 0), points = math.max(points, current and current.points or 0), deaths = math.max(deaths, current and current.deaths or 0), ts = ts }
        if GH.RefreshUI then GH:RefreshUI() end
    end
end)

local honorPatterns
local function buildHonorPatterns()
    honorPatterns = {}
    local function add(formatString)
        if type(formatString) ~= "string" or formatString == "" then return end
        local pattern = formatString:gsub("%%%d%$", "%%")
        pattern = pattern:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
        local first = true
        pattern = pattern:gsub("%%([sd])", function(kind)
            if kind == "d" then return "%d+" end
            if first then first = false; return "(.-)" end
            return ".-"
        end)
        honorPatterns[#honorPatterns + 1] = "^" .. pattern .. "$"
    end
    add(COMBATLOG_HONORGAIN)
    add(COMBATLOG_HONORGAIN_NO_RANK)
    add(COMBATLOG_HONORGAIN_EXHAUSTION1)
    add("%s dies, honorable kill Rank: %s (Estimated Honor Points: %d)")
    add("%s dies, honorable kill (Estimated Honor Points: %d)")
    honorPatterns[#honorPatterns + 1] = "^(.-) dies, honorable kill"
end

local function victimFromHonorMessage(message)
    if type(message) ~= "string" then return end
    message = message:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    message = message:gsub("|H.-|h(.-)|h", "%1"):gsub("^%s+", ""):gsub("%s+$", "")
    if not honorPatterns then buildHonorPatterns() end
    for _, pattern in ipairs(honorPatterns) do
        local name = message:match(pattern)
        if name and name ~= "" then return name end
    end
    -- Some clients change capitalization or punctuation in the English text.
    local at = message:lower():find(" dies", 1, true)
    if at and message:lower():find("honorable kill", at, true) then
        return message:sub(1, at - 1)
    end
end

local function levelForVictim(name)
    local wanted = normalizedName(name)
    local first = (tostring(name):match("^([^-]+)") or tostring(name)):lower()
    local found
    for _, seen in pairs(seenPlayers) do
        local seenName = tostring(seen.name or "")
        if GetTime() - seen.seen <= 900 and (normalizedName(seenName) == wanted or seenName:lower() == first) then
            if found and found ~= seen then return 0 end
            found = seen
        end
    end
    return found and found.level or 0
end

-- Honor messages and counter updates describe the same reward. Resolve one
-- short batch together, retaining the location at the time of each signal.
local function resolveCredits()
    creditScheduled = false
    local batch = honorCredits
    honorCredits = {}
    local names, counters, outdoorCounter = 0, 0, false
    for _, reward in ipairs(batch) do
        if reward.victim then
            names = names + 1
            recordKill(reward.victim, levelForVictim(reward.victim), reward.outdoors)
        else
            counters = counters + 1
            outdoorCounter = outdoorCounter or reward.outdoors
        end
    end
    if counters <= names or not outdoorCounter then return end
    refreshVisiblePlayers()
    local candidate
    if lastTarget and GetTime() - lastTarget.targetAt <= 15 then
        local guid = unitValue(UnitGUID, "target")
        local dead = unitValue(UnitIsDeadOrGhost, "target")
        if dead or (guid and guid ~= lastTarget.guid) or unitValue(UnitExists, "target") == false then
            candidate = lastTarget
        end
    end
    if candidate then unmatchedCredit = nil; recordKill(candidate.name, candidate.level, true); return end
    for _, seen in pairs(seenPlayers) do
        if seen.diedAt and GetTime() - seen.diedAt <= 12 then
            -- Without a named message, multiple recent deaths are ambiguous.
            if candidate then trackingNote("Kill credit received: multiple enemy deaths, no named victim"); return end
            candidate = seen
        end
    end
    if not candidate and groupEvidence.expires and GetTime() <= groupEvidence.expires then
        candidate = groupEvidence
    end
    if candidate then
        recordKill(candidate.name, candidate.level, true)
        unmatchedCredit = nil
    else
        unmatchedCredit = { expires = GetTime() + 12 }
        trackingNote("Own kill credit received; waiting for enemy identification")
    end
end

-- A live report from someone currently in our group supplies a victim name,
-- never credit. Only consume it if this client already received its own reward.
retryGroupCredit = function(stamp, author, sender, victim, level)
    if not sender or normalizedName(sender) ~= normalizedName(author) then return end
    if math.abs(time() - stamp) > 12 or not isOpenWorld() then return end
    local grouped = false
    for _, prefix in ipairs({ "party", "raid" }) do
        local count = prefix == "party" and 4 or 40
        for index = 1, count do
            local name = unitValue(GetUnitName, prefix .. index)
            if name and normalizedName(name) == normalizedName(sender) then grouped = true; break end
        end
        if grouped then break end
    end
    if not grouped then return end
    groupEvidence = { name = victim, level = level, expires = GetTime() + 12 }
    if unmatchedCredit and GetTime() <= unmatchedCredit.expires then
        unmatchedCredit = nil
        recordKill(victim, level, true)
    end
end

local function queueCredit(victim)
    if not GH.bucket then return end
    honorCredits[#honorCredits + 1] = { victim = victim, outdoors = isOpenWorld() }
    if creditScheduled then return end
    creditScheduled = true
    C_Timer.After(0.8, resolveCredits)
end

GH:RegisterEventHandler("CHAT_MSG_COMBAT_HONOR_GAIN", function(_, message)
    message = readable(message)
    GH.pvpLastHonorMessage = type(message) == "string" and message or "Honor event had no readable text"
    refreshVisiblePlayers()
    local ok, victim = pcall(victimFromHonorMessage, message)
    if not ok then victim = nil end
    if victim then queueCredit(victim)
    else
        -- Generic honor can come from objectives and other rewards. Only a
        -- named honorable-kill message or the game's kill-credit event may
        -- authorize a kill; death observations only identify its victim.
        if not creditScheduled and not unmatchedCredit then
            trackingNote("Honor received; waiting for the game's honorable-kill credit")
        end
    end
end)
GH:RegisterEventHandler("PLAYER_PVP_KILLS_CHANGED", function(_, unit)
    unit = readable(unit)
    if type(unit) == "string" and unit ~= "player" then return end
    refreshVisiblePlayers()
    queueCredit(nil)
end)

GH:RegisterHistoryProvider(function()
    local reset = GH.bucket.pvpReset
    if reset and reset.ts > 0 then GH:SendRecord("PR", "wipe", reset.ts, reset.by, "") end
    for start, deleted in pairs(GH.bucket.pvpSeasonDeletes) do
        GH:SendRecord("PD", start, deleted.ts, deleted.by, "")
    end
    local list = GH.bucket.pvpKills or {}
    for i = math.min(#list, GH.maxItems), 1, -1 do
        local record = list[i]
        GH:SendRecord("P", record.id, record.ts, record.by, encodeKill(record))
    end
    local deaths = GH.bucket.pvpDeaths or {}
    for i = math.min(#deaths, GH.maxItems), 1, -1 do
        local death = deaths[i]
        GH:SendRecord("X", death.id, death.ts, death.by, death.killer)
    end
    local season = GH.bucket.pvpSeason or { name = "All-time", start = 0, ts = 0 }
    if season.ts and season.ts > 0 then GH:SendRecord("Y", "season", season.ts, season.by or "Guild officer", table.concat({ season.name, season.start, season.ends or 0 }, "\n")) end
    for _, archived in pairs(GH.bucket.pvpSeasons) do
        GH:SendRecord("Y", "season:" .. archived.start, archived.ts, archived.by,
            table.concat({ archived.name, archived.start, archived.ends or 0 }, "\n"))
    end
    for _, totals in pairs(GH.bucket.pvpTotals or {}) do
        sendTotals(totals.start or 0, totals.by, totals)
    end
end)

-- Cache visible player units so honor messages can include the victim level
-- when that player was recently visible.
local function capturePlayer(unit)
    if not unitValue(UnitExists, unit) or not unitValue(UnitIsPlayer, unit) then return end
    if UnitFactionGroup then
        local faction = unitValue(UnitFactionGroup, unit)
        if not faction or faction == "Neutral" or faction == unitValue(UnitFactionGroup, "player") then return end
    end
    local guid = unitValue(UnitGUID, unit)
    local name = unitValue(GetUnitName, unit) or unitValue(UnitName, unit)
    if type(guid) ~= "string" or type(name) ~= "string" or name == "" then return end
    local level = tonumber(unitValue(UnitLevel, unit)) or 0
    local seen = seenPlayers[guid] or {}
    seen.guid = guid
    seen.name, seen.level, seen.seen = name, level or 0, GetTime()
    local dead = unitValue(UnitIsDeadOrGhost, unit)
    if dead then
        if seen.alive and not seen.diedAt then seen.diedAt = seen.seen end
    elseif dead == false then
        seen.alive, seen.diedAt = true, nil
    end
    seenPlayers[guid] = seen
    if unit == "target" then seen.targetAt = seen.seen; lastTarget = seen end
end

captureVisiblePlayers = function()
    capturePlayer("target")
    capturePlayer("mouseover")
    capturePlayer("focus")
    for index = 1, 4 do capturePlayer("party" .. index .. "target") end
    if IsInRaid and IsInRaid() then
        for index = 1, 40 do capturePlayer("raid" .. index .. "target") end
    end
    if GetNumNameplates then
        for i = 1, GetNumNameplates() do capturePlayer("nameplate" .. i) end
    else
        for i = 1, 40 do capturePlayer("nameplate" .. i) end
    end
end

GH:RegisterEventHandler("PLAYER_TARGET_CHANGED", refreshVisiblePlayers)
GH:RegisterEventHandler("UPDATE_MOUSEOVER_UNIT", refreshVisiblePlayers)
GH:RegisterEventHandler("NAME_PLATE_UNIT_ADDED", function(_, unit) capturePlayer(unit) end)
GH:RegisterEventHandler("NAME_PLATE_UNIT_REMOVED", function(_, unit) capturePlayer(unit) end)
GH:RegisterEventHandler("UNIT_HEALTH", function(_, unit)
    if unit == "target" or unit == "focus" then capturePlayer(unit) end
end)
GH:RegisterEventHandler("UNIT_FLAGS", function(_, unit)
    if unit == "target" or unit == "focus" then capturePlayer(unit) end
end)
-- This event supplies death evidence only. Points still require the local
-- player's own honor/kill credit, so a group member's killing blow cannot
-- independently award points.
GH:RegisterEventHandler("PARTY_KILL", function(_, attacker, victim)
    victim = readable(victim)
    if type(victim) ~= "string" then return end
    local seen = seenPlayers[victim]
    if seen then seen.diedAt = GetTime() end
end)
GH:RegisterEventHandler("PLAYER_ENTERING_WORLD", function()
    seenPlayers, groupEvidence = {}, {}
    lastTarget, unmatchedCredit = nil, nil
end)
function GH:StartPvPSeason(name, endDate, restart)
    if not self:CanManagePvPSeason() then return false, "Only the guild master can start a PvP season." end
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or #name > 80 then return false, "Enter a season name (up to 80 characters)." end
    local ts = math.max(time(), resetTime() + 1, (self.bucket.pvpSeason.start or 0) + 1)
    local day, month, year = tostring(endDate or ""):match("^(%d%d)%-(%d%d)%-(%d%d%d%d)$")
    if not year then return false, "Enter an end date as DD-MM-YYYY (your local time)." end
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    if year < 1971 or year > 2099 or month < 1 or month > 12 or day < 1 or day > 31 then
        return false, "Enter a valid end date."
    end
    local midnight = time({ year = year, month = month, day = day, hour = 0, min = 0, sec = 0 })
    if not midnight or date("%d-%m-%Y", midnight) ~= endDate then return false, "Enter a valid end date." end
    local ends = time({ year = year, month = month, day = day + 1, hour = 0, min = 0, sec = 0 })
    if ends <= ts then return false, "The end date must be today or later." end
    if restart then
        name = "Season 1"
    end
    if ends <= ts then return false, "Choose a later end date." end
    local player = playerName()
    local previous = self.bucket.pvpSeason
    if previous and (previous.start or 0) > 0 then
        -- Starting a replacement season closes the previous scoring window.
        previous.ends = math.min(previous.ends and previous.ends > 0 and previous.ends or ts, ts)
        previous.ts, previous.by = ts, player
        self.bucket.pvpSeasons[tostring(previous.start)] = previous
        self:SendRecord("Y", "season:" .. previous.start, previous.ts, player,
            table.concat({ previous.name, previous.start, previous.ends }, "\n"))
    end
    self.bucket.pvpSeason = { name = name, start = ts, ends = ends, ts = ts, by = player }
    self.bucket.pvpSeasons[tostring(ts)] = self.bucket.pvpSeason
    self:SendRecord("Y", "season", ts, player, table.concat({ name, ts, ends }, "\n"))
    self:RefreshUI()
    return true, "PvP season started: " .. name
end

GH:RegisterCommand("pvp", function(rest)
    local action, name = rest:match("^(%S+)%s*(.*)$")
    if (action or ""):lower() == "wipe" then
        if not guildLeader(playerName()) then print("Guild Hall: Only the guild master can wipe PvP stats."); return end
        if name ~= "CONFIRM" then print("Guild Hall: This erases all guild PvP points, kills, deaths, history and seasons. Type /gh pvp wipe CONFIRM to proceed."); return end
        local _, result = GH:WipePvPStats()
        print("Guild Hall: " .. result)
        return
    end
    GH.activeTab = "PvP"
    GH:Open()
end)

function GH:GetPvPSeasons()
    local bucket = self.bucket or {}
    local choices, known = {}, {}
    for start in pairs(bucket.pvpSeasonDeletes or {}) do known[tonumber(start)] = true end
    local current = bucket.pvpSeason
    if current and (current.start or 0) > 0 and not known[current.start] then
        choices[#choices + 1], known[current.start] = current, true
    end
    for _, season in pairs(bucket.pvpSeasons or {}) do
        if not known[season.start] then choices[#choices + 1], known[season.start] = season, true end
    end
    for _, total in pairs(bucket.pvpTotals or {}) do
        local start = total.start or 0
        if start > 0 and not known[start] then
            choices[#choices + 1] = { start = start, name = "Season " .. date("%d-%m-%Y", start) }
            known[start] = true
        end
    end
    table.sort(choices, function(a, b) return a.start > b.start end)
    for index = 2, #choices do
        local older = choices[index]
        older = { name = older.name, start = older.start, ends = older.ends, ts = older.ts, by = older.by }
        older.ends = math.min(older.ends and older.ends > 0 and older.ends or math.huge, choices[index - 1].start)
        choices[index] = older
    end
    choices[#choices + 1] = { start = 0, name = "All-time" }
    return choices
end

function GH:GetPvPLeaderboard(allTime, selectedStart)
    local bucket = GH.bucket or {}
    local season = bucket.pvpSeason or { name = "All-time", start = 0 }
    if selectedStart ~= nil then
        allTime = false
        for _, choice in ipairs(self:GetPvPSeasons()) do
            if choice.start == selectedStart then season = choice; allTime = selectedStart == 0; break end
        end
    end
    local start = allTime and 0 or (season.start or 0)
    local finish = not allTime and season.ends and season.ends > 0 and season.ends or math.huge
    local scores, totalRows = {}, {}
    for _, total in pairs(bucket.pvpTotals or {}) do
        if (total.start or 0) == start then
            local score = scores[total.by] or { name = total.by, points = 0, kills = 0, deaths = 0, recentPoints = { 0, 0, 0, 0, 0 } }
            score.points = math.max(score.points, total.points or 0)
            score.kills = math.max(score.kills, total.kills or 0)
            score.deaths = math.max(score.deaths, total.deaths or 0)
            scores[total.by] = score
            totalRows[total.by] = true
        end
    end
    for _, kill in ipairs(bucket.pvpKills or {}) do
        if kill.ts >= start and kill.ts < finish then
            local score = scores[kill.by] or { name = kill.by, points = 0, kills = 0, deaths = 0, recentPoints = { 0, 0, 0, 0, 0 } }
            if not totalRows[kill.by] then
                score.points = score.points + (tonumber(kill.points) or 1)
                score.kills = score.kills + 1
            end
            local band = math.max(1, math.min(5, tonumber(kill.points) or 1))
            score.recentPoints[band] = score.recentPoints[band] + 1
            if not score.lastKill or kill.ts > score.lastKill.ts then score.lastKill = kill end
            scores[kill.by] = score
        end
    end
    for _, death in ipairs(bucket.pvpDeaths or {}) do
        if death.ts >= start and death.ts < finish then
            local score = scores[death.by] or { name = death.by, points = 0, kills = 0, deaths = 0, recentPoints = { 0, 0, 0, 0, 0 } }
            if not totalRows[death.by] then score.deaths = score.deaths + 1 end
            scores[death.by] = score
        end
    end
    local ranking = {}
    for _, score in pairs(scores) do score.points = score.kills; ranking[#ranking + 1] = score end
    table.sort(ranking, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        if a.kills ~= b.kills then return a.kills > b.kills end
        return a.name:lower() < b.name:lower()
    end)
    local ownName = playerName()
    local ownScore, ownRank
    for rank, score in ipairs(ranking) do
        if ownName and score.name:lower() == ownName:lower() then ownScore, ownRank = score, rank; break end
    end
    return season, ranking, ownScore, ownRank
end

GH:RegisterTab("PvP", function()
    if not GH.bucket then return "Join a guild to see the PvP leaderboard." end
    local kills = GH.bucket.pvpKills or {}
    local deaths = GH.bucket.pvpDeaths or {}
    if #kills == 0 and #deaths == 0 and not next(GH.bucket.pvpTotals or {}) then return "No outdoor PvP kills recorded yet. Defeat an enemy player in the open world to earn points." end
    local season = GH.bucket.pvpSeason or { name = "All-time", start = 0 }
    local scores, wanted = {}, {}
    local totalRows = {}
    for _, total in pairs(GH.bucket.pvpTotals or {}) do
        if (total.start or 0) == (season.start or 0) then
            local score = scores[total.by] or { name = total.by, points = 0, kills = 0, deaths = 0 }
            score.points = math.max(score.points, total.points or 0)
            score.kills = math.max(score.kills, total.kills or 0)
            score.deaths = math.max(score.deaths, total.deaths or 0)
            scores[total.by] = score
            totalRows[total.by] = true
        end
    end
    for _, kill in ipairs(kills) do
        if not totalRows[kill.by] and kill.ts >= (season.start or 0) and (not season.ends or season.ends == 0 or kill.ts < season.ends) then
            local score = scores[kill.by] or { name = kill.by, points = 0, kills = 0, deaths = 0 }
            score.points, score.kills = score.points + (tonumber(kill.points) or 1), score.kills + 1
            scores[kill.by] = score
        end
    end
    for _, death in ipairs(deaths) do
        if not totalRows[death.by] and death.ts >= (season.start or 0) and (not season.ends or season.ends == 0 or death.ts < season.ends) then
            local score = scores[death.by] or { name = death.by, points = 0, kills = 0, deaths = 0 }
            score.deaths = score.deaths + 1
            scores[death.by] = score
            wanted[death.killer] = (wanted[death.killer] or 0) + 1
        end
    end
    local ranking = {}
    for _, score in pairs(scores) do score.points = score.kills; ranking[#ranking + 1] = score end
    table.sort(ranking, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        if a.kills ~= b.kills then return a.kills > b.kills end
        return a.name:lower() < b.name:lower()
    end)
    local lines = { "PvP season: " .. GH:Display(season.name or "All-time"), "Ranked by kills since season start", "" }
    for rank, score in ipairs(ranking) do
        lines[#lines + 1] = ("%d. %s — %d points · %d kills / %d deaths"):format(rank, GH:Display(score.name), score.points, score.kills, score.deaths)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Recent kills:"
    local shown = 0
    for _, kill in ipairs(kills) do
        if kill.ts >= (season.start or 0) and (not season.ends or season.ends == 0 or kill.ts < season.ends) and shown < 10 then
            shown = shown + 1
            local level = kill.victimLevel and kill.victimLevel > 0 and (" (level " .. kill.victimLevel .. ")") or " (level unknown)"
            lines[#lines + 1] = ("%s defeated %s%s · +%d"):format(GH:Display(kill.by), GH:Display(kill.victim), level, kill.points or 1)
        end
    end
    local enemies = {}
    for name, deaths in pairs(wanted) do enemies[#enemies + 1] = { name = name, deaths = deaths } end
    table.sort(enemies, function(a, b) if a.deaths ~= b.deaths then return a.deaths > b.deaths end; return a.name:lower() < b.name:lower() end)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Most wanted (enemy players with most guild kills against us):"
    for i = 1, math.min(#enemies, 5) do lines[#lines + 1] = ("%d. %s · %d kill(s)"):format(i, GH:Display(enemies[i].name), enemies[i].deaths) end
    return table.concat(lines, "\n")
end)

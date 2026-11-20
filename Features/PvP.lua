-- Outdoor player-versus-player kill tracking and leaderboard.
local _, GH = ...
GH:RegisterBucket("pvpKills", function() return {} end)
GH:RegisterBucket("pvpDeaths", function() return {} end)
GH:RegisterBucket("pvpTotals", function() return {} end)
GH:RegisterBucket("pvpSeason", function() return { name = "All-time", start = 0, ts = 0 } end)
local seenPlayers = {}

local function totalsKey(start, player)
    return tostring(start) .. "|" .. player
end

local function sendTotals(start, player, totals)
    totals.id = "totals:" .. totalsKey(start, player)
    totals.ts = time()
    totals.by = player
    GH:SendRecord("Z", totals.id, totals.ts, player,
        table.concat({ start, totals.kills or 0, totals.points or 0, totals.deaths or 0 }, "\n"))
end

local function addLocalStat(field, points)
    if not GH.bucket then return end
    local player = UnitName and UnitName("player") or "Guild member"
    local season = GH.bucket.pvpSeason or { start = 0 }
    local starts = { 0 }
    if (season.start or 0) > 0 then starts[#starts + 1] = season.start end
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
        if field == "kills" then totals.points = (totals.points or 0) + (points or 1) end
        GH.bucket.pvpTotals[key] = totals
        sendTotals(start, player, totals)
    end
end

local function pointsForLevel(level)
    if level >= 50 then return 5 end
    if level >= 40 then return 4 end
    if level >= 30 then return 3 end
    if level >= 20 then return 2 end
    return 1
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
    local player = UnitName and UnitName("player") or "Guild member"
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

local function recordKill(victim, victimLevel)
    if not GH.bucket or not victim or victim == "" then return end
    local history, now = historyFor(victim)
    if #history > 0 and now - history[#history] < 300 then return end
    if #history >= 5 then return end
    history[#history + 1] = now
    local level = tonumber(victimLevel) or 0
    local record = GH:NewRecord({ victim = victim, victimLevel = level, points = pointsForLevel(level) })
    record.id = tostring(time()) .. "-pvp-" .. tostring(math.random(100000, 999999))
    addLocalStat("kills", record.points)
    GH:StoreRecord("pvpKills", record, "P", encodeKill(record))
end

GH:RegisterRecordHandler("P", function(id, ts, author, content)
    local victim, level, points = content:match("^(.-)\n(%d+)\n(%d+)$")
    level, points = tonumber(level), tonumber(points)
    if not victim or victim == "" or #victim > 100 or not level or level > 100 or not points or points < 1 or points > 5 then return end
    GH:StoreRecord("pvpKills", { id = id, ts = ts, by = author, victim = victim, victimLevel = level, points = points })
end)

GH:RegisterRecordHandler("X", function(id, ts, author, content)
    local killer = content:gsub("^%s+", ""):gsub("%s+$", "")
    if killer == "" or #killer > 100 then return end
    GH:StoreRecord("pvpDeaths", { id = id, ts = ts, by = author, killer = killer })
end)

GH:RegisterRecordHandler("Y", function(id, ts, author, content)
    local name, start = content:match("^(.-)\n(%d+)$")
    start = tonumber(start)
    if id ~= "season" or not name or name == "" or #name > 80 or not start then return end
    local current = GH.bucket.pvpSeason or {}
    if (current.ts or 0) > ts then return end
    GH.bucket.pvpSeason = { name = name, start = start, ts = ts, by = author }
    if GH.RefreshUI then GH:RefreshUI() end
end)

GH:RegisterRecordHandler("Z", function(id, ts, author, content)
    local start, kills, points, deaths = content:match("^(%d+)\n(%d+)\n(%d+)\n(%d+)$")
    start, kills, points, deaths = tonumber(start), tonumber(kills), tonumber(points), tonumber(deaths)
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
    if not honorPatterns then buildHonorPatterns() end
    for _, pattern in ipairs(honorPatterns) do
        local name = message:match(pattern)
        if name and name ~= "" then return name end
    end
end

local function levelForVictim(name)
    local wanted = normalizedName(name)
    local first = (tostring(name):match("^([^-]+)") or tostring(name)):lower()
    local found
    for _, seen in pairs(seenPlayers) do
        local seenName = tostring(seen.name or "")
        if normalizedName(seenName) == wanted or seenName:lower() == first then
            if found and found ~= seen then return 0 end
            found = seen
        end
    end
    return found and found.level or 0
end

GH:RegisterEventHandler("CHAT_MSG_COMBAT_HONOR_GAIN", function(_, message)
    local victim = victimFromHonorMessage(message)
    if victim then recordKill(victim, levelForVictim(victim)) end
end)

GH:RegisterHistoryProvider(function()
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
    if season.ts and season.ts > 0 then GH:SendRecord("Y", "season", season.ts, season.by or "Guild officer", season.name .. "\n" .. season.start) end
    local activeStart = (GH.bucket.pvpSeason or {}).start or 0
    for _, totals in pairs(GH.bucket.pvpTotals or {}) do
        if (totals.start or 0) == 0 or totals.start == activeStart then
            sendTotals(totals.start or 0, totals.by, totals)
        end
    end
end)

-- Forever blocks the combat log for addons. PARTY_KILL is the supported
-- killing-blow event, but supplies GUIDs only. Cache visible player units so
-- we can resolve the victim when that event arrives.
local function capturePlayer(unit)
    if not UnitExists or not UnitExists(unit) or not UnitIsPlayer or not UnitIsPlayer(unit) then return end
    local guid = UnitGUID and UnitGUID(unit)
    local name = UnitName and UnitName(unit)
    if type(guid) ~= "string" or type(name) ~= "string" or name == "" then return end
    local level = UnitLevel and tonumber(UnitLevel(unit)) or 0
    seenPlayers[guid] = { name = name, level = level or 0, seen = GetTime and GetTime() or 0 }
end

local function captureVisiblePlayers()
    capturePlayer("target")
    capturePlayer("mouseover")
    capturePlayer("focus")
    if GetNumNameplates then
        for i = 1, GetNumNameplates() do capturePlayer("nameplate" .. i) end
    else
        for i = 1, 40 do capturePlayer("nameplate" .. i) end
    end
end

GH:RegisterEventHandler("PLAYER_TARGET_CHANGED", captureVisiblePlayers)
GH:RegisterEventHandler("UPDATE_MOUSEOVER_UNIT", captureVisiblePlayers)
GH:RegisterEventHandler("NAME_PLATE_UNIT_ADDED", function(_, unit) capturePlayer(unit) end)
GH:RegisterEventHandler("PARTY_KILL", function(_, attackerGUID, victimGUID)
    if not GH.bucket or IsInInstance and IsInInstance() then return end
    captureVisiblePlayers()
    if type(attackerGUID) ~= "string" or type(victimGUID) ~= "string" then return end
    local playerGUID = UnitGUID and UnitGUID("player")
    local petGUID = UnitGUID and UnitGUID("pet")
    if attackerGUID ~= playerGUID and attackerGUID ~= petGUID then return end
    local victim = seenPlayers[victimGUID]
    if not victim then return end
    recordKill(victim.name, victim.level)
end)

function GH:StartPvPSeason(name)
    if not self:CanManage() then return false, "Only the guild leader or rank 1 can start a PvP season." end
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or #name > 80 then return false, "Enter a season name (up to 80 characters)." end
    local ts = time()
    local player = UnitName and UnitName("player") or "Guild officer"
    self.bucket.pvpSeason = { name = name, start = ts, ts = ts, by = player }
    self:SendRecord("Y", "season", ts, player, name .. "\n" .. ts)
    self:RefreshUI()
    return true, "PvP season started: " .. name
end

GH:RegisterCommand("pvp", function(rest)
    local action, name = rest:match("^(%S+)%s*(.*)$")
    if (action or ""):lower() ~= "season" then GH.activeTab = "PvP"; GH:Open(); return end
    local _, result = GH:StartPvPSeason(name)
    print("Guild Hall: " .. result)
end)

function GH:GetPvPLeaderboard(allTime)
    local bucket = GH.bucket or {}
    local season = bucket.pvpSeason or { name = "All-time", start = 0 }
    local start = allTime and 0 or (season.start or 0)
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
        if kill.ts >= start then
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
        if death.ts >= start then
            local score = scores[death.by] or { name = death.by, points = 0, kills = 0, deaths = 0, recentPoints = { 0, 0, 0, 0, 0 } }
            if not totalRows[death.by] then score.deaths = score.deaths + 1 end
            scores[death.by] = score
        end
    end
    local ranking = {}
    for _, score in pairs(scores) do ranking[#ranking + 1] = score end
    table.sort(ranking, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        if a.kills ~= b.kills then return a.kills > b.kills end
        return a.name:lower() < b.name:lower()
    end)
    local ownName = UnitName and UnitName("player")
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
        if not totalRows[kill.by] and kill.ts >= (season.start or 0) then
            local score = scores[kill.by] or { name = kill.by, points = 0, kills = 0, deaths = 0 }
            score.points, score.kills = score.points + (tonumber(kill.points) or 1), score.kills + 1
            scores[kill.by] = score
        end
    end
    for _, death in ipairs(deaths) do
        if not totalRows[death.by] and death.ts >= (season.start or 0) then
            local score = scores[death.by] or { name = death.by, points = 0, kills = 0, deaths = 0 }
            score.deaths = score.deaths + 1
            scores[death.by] = score
            wanted[death.killer] = (wanted[death.killer] or 0) + 1
        end
    end
    local ranking = {}
    for _, score in pairs(scores) do ranking[#ranking + 1] = score end
    table.sort(ranking, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        if a.kills ~= b.kills then return a.kills > b.kills end
        return a.name:lower() < b.name:lower()
    end)
    local lines = { "PvP season: " .. GH:Display(season.name or "All-time"), "Points, kills, and deaths since season start", "" }
    for rank, score in ipairs(ranking) do
        lines[#lines + 1] = ("%d. %s — %d points · %d kills / %d deaths"):format(rank, GH:Display(score.name), score.points, score.kills, score.deaths)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Recent kills:"
    local shown = 0
    for _, kill in ipairs(kills) do
        if kill.ts >= (season.start or 0) and shown < 10 then
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

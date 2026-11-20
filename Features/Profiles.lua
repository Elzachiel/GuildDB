-- Self-managed guild member profiles and profile directory.
local _, GH = ...
GH:RegisterBucket("profiles", function() return {} end)
GH.profileCache = GH.profileCache or {}

local function baseName(name)
    local value = tostring(name or "")
    value = value:match("^([^-]+)") or value
    return value:gsub("^%s+", ""):gsub("%s+$", ""):lower()
end

-- Forever roster names and UnitName() can differ in spacing/realm formatting.
-- Use a second, punctuation-insensitive key for matching profile identities.
local function nameKey(name)
    return baseName(name):gsub("[^%w]", "")
end

local function sameCharacter(a, b)
    return baseName(a) == baseName(b) or (nameKey(a) ~= "" and nameKey(a) == nameKey(b))
end

local function profileMatches(profile, name)
    if type(profile) ~= "table" then return false end
    local fullName = table.concat({ profile.firstName or "", profile.lastName or "" }, " ")
    return sameCharacter(profile.characterName, name) or sameCharacter(fullName, name)
end

local function currentRosterName()
    local playerName = UnitName and UnitName("player") or "Guild member"
    local saved = GH.playerProfile or (GuildHallDB and GuildHallDB.playerProfile)
    for _, member in ipairs(GH.roster or {}) do
        if sameCharacter(member.name, playerName) or profileMatches(saved, member.name) then
            return member.name
        end
    end
    -- Some Forever guild roster names include the player's surname while
    -- UnitName() returns only the character's first/name token. Use a unique
    -- roster prefix match when there is exactly one candidate.
    local key, candidate = nameKey(playerName), nil
    if key ~= "" then
        for _, member in ipairs(GH.roster or {}) do
            local memberKey = nameKey(member.name)
            if #memberKey > #key and memberKey:sub(1, #key) == key then
                if candidate then return playerName end
                candidate = member.name
            end
        end
    end
    return candidate or playerName
end

local function characterNameParts(name)
    local characterName = tostring(name or ""):match("^([^-]+)") or tostring(name or "")
    local firstName, lastName = characterName:match("^%s*(%S+)%s*(.-)%s*$")
    return firstName or "", lastName or ""
end

function GH:GetPlayerNameParts()
    return characterNameParts(currentRosterName())
end

function GH:GetProfile(name)
    if not name then return nil end
    local wanted = baseName(name)
    local wantedKey = nameKey(name)
    local localProfiles = GuildHallDB and GuildHallDB.localProfiles or {}
    local guildProfiles = self.bucket and self.bucket.profiles or {}
    local ownProfile = GuildHallDB and GuildHallDB.playerProfile
    local playerName = UnitName and UnitName("player") or ""
    local playerGUID = UnitGUID and UnitGUID("player")
    local isPlayer = wanted == baseName(playerName)
    if self.playerProfile and (isPlayer or profileMatches(self.playerProfile, name)) then
        self.profileCache[wanted] = self.playerProfile
        return self.playerProfile
    end
    if ownProfile and ((isPlayer and playerGUID and ownProfile.characterGUID == playerGUID)
        or profileMatches(ownProfile, name)) then
        self.profileCache[wanted] = ownProfile
        return ownProfile
    end
    if isPlayer and playerGUID and localProfiles[playerGUID] then
        self.profileCache[wanted] = localProfiles[playerGUID]
        return localProfiles[playerGUID]
    end
    if localProfiles[name] then self.profileCache[wanted] = localProfiles[name]; return localProfiles[name] end
    if localProfiles[wanted] then self.profileCache[wanted] = localProfiles[wanted]; return localProfiles[wanted] end
    if guildProfiles[wanted] then self.profileCache[wanted] = guildProfiles[wanted]; return guildProfiles[wanted] end
    if guildProfiles[name] then self.profileCache[wanted] = guildProfiles[name]; return guildProfiles[name] end
    for _, profiles in ipairs({ localProfiles, guildProfiles }) do
        for profileName, profile in pairs(profiles) do
            if sameCharacter(profileName, name) or profileMatches(profile, name) then
                self.profileCache[wanted] = profile
                self.profileCache[wantedKey] = profile
                return profile
            end
        end
    end
    return self.profileCache[wanted] or self.profileCache[wantedKey]
end

-- WoW Forever exposes the character's Skills tab through C_SkillInfo. Read
-- its primary and secondary profession groups and keep the result in profile
-- data so it is shared with guildmates who also run Guild Hall.
function GH:GetPlayerProfessions()
    local api = C_SkillInfo
    if type(api) ~= "table" or type(api.GetNumSkillLines) ~= "function" or type(api.GetSkillLineInfo) ~= "function" then
        return nil
    end
    local ok, count = pcall(api.GetNumSkillLines)
    if not ok or type(count) ~= "number" then return nil end
    local professions, seen, inProfessionGroup = {}, {}, false
    for index = 1, count do
        local lineOK, info = pcall(api.GetSkillLineInfo, index)
        if lineOK and type(info) == "table" then
            local name = info.name
            if info.isHeader then
                local header = type(name) == "string" and name:lower() or ""
                inProfessionGroup = header:find("profession", 1, true) ~= nil or header:find("secondary", 1, true) ~= nil
                    or info.skillID == 9 or info.skillID == 11
            elseif (inProfessionGroup or info.skillLineCategoryID == 9 or info.skillLineCategoryID == 11)
                and type(name) == "string" and name ~= "" and (tonumber(info.maxRank) or 0) > 1 then
                local rank = tonumber(info.rank) or 0
                local key = name:lower()
                if not seen[key] then
                    seen[key] = #professions + 1
                    professions[#professions + 1] = { name = name, rank = rank }
                elseif rank > professions[seen[key]].rank then
                    professions[seen[key]].rank = rank
                end
            end
        end
    end
    local display = {}
    for _, profession in ipairs(professions) do
        display[#display + 1] = profession.name .. " " .. profession.rank
    end
    return table.concat(display, ", "), professions
end

function GH:RefreshPlayerProfessions()
    if not self.bucket then return end
    local professions = self:GetPlayerProfessions()
    if professions == nil then return end
    local player = UnitName and UnitName("player") or "Guild member"
    local profile = self:GetProfile(player) or {}
    if professions == "" or profile.professions == professions then return end
    self:SetProfile(profile.firstName, profile.lastName, profile.role, profile.spec, profile.timezone, profile.alts, professions, profile.race)
end

local function cleanField(value, limit)
    value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return value:gsub("[\r\n|]", " "):sub(1, limit)
end

local function encodeProfile(profile)
    return table.concat({ profile.firstName or "", profile.lastName or "", profile.role or "", profile.spec or "", profile.timezone or "", profile.alts or "", profile.professions or "", profile.race or "" }, "\n")
end

GH:RegisterRecordHandler("PF", function(id, ts, author, content)
    local firstName, lastName, role, spec, timezone, alts, professions, race = content:match("^(.-)\n(.-)\n(.-)\n(.-)\n(.-)\n(.-)\n(.-)\n(.*)$")
    if not firstName then
        firstName, lastName, role, spec, timezone, alts, professions = content:match("^(.-)\n(.-)\n(.-)\n(.-)\n(.-)\n(.-)\n(.*)$")
        race = ""
    end
    if not firstName then
        role, spec, timezone, alts, professions = content:match("^(.-)\n(.-)\n(.-)\n(.-)\n(.*)$")
        firstName, lastName = "", ""
    end
    if not role then
        role, spec, timezone, alts = content:match("^(.-)\n(.-)\n(.-)\n(.*)$")
        professions = ""
    end
    if not role or id:lower() ~= author:lower() or #id > 80 or #firstName > 60 or #lastName > 60 or #role > 60 or #spec > 80 or #timezone > 60 or #alts > 200 or #professions > 250 or #race > 60 then return end
    local previous = GH.bucket.profiles[id]
    -- Ignore same-second echoes/duplicates too; they may carry an older copy
    -- of the profile and otherwise replace the just-saved local values.
    if previous and previous.ts and previous.ts >= ts then return end
    local profile = { firstName = firstName, lastName = lastName, role = role, spec = spec, timezone = timezone, alts = alts, professions = professions, race = race, ts = ts, by = author, characterName = id }
    GH.bucket.profiles[id] = profile
    GH.profileCache[baseName(id)] = profile
    if GH.RefreshUI then GH:RefreshUI() end
end)

GH:RegisterHistoryProvider(function()
    for player, profile in pairs(GH.bucket.profiles or {}) do
        GH:SendRecord("PF", player, profile.ts or time(), player, encodeProfile(profile))
    end
end, false)

function GH:SetProfile(firstName, lastName, role, spec, timezone, alts, professions, race)
    if not self.bucket then return false, "Join a guild first." end
    local player = currentRosterName()
    local playerBase = baseName(player)
    firstName, lastName = characterNameParts(player)
    local detectedRace = UnitRace and UnitRace("player") or nil
    if type(detectedRace) == "table" then detectedRace = detectedRace[1] end
    race = (type(detectedRace) == "string" and detectedRace ~= "" and detectedRace) or race
    local detectedProfessions = self:GetPlayerProfessions()
    if detectedProfessions ~= nil and detectedProfessions ~= "" then professions = detectedProfessions end
    local profile = {
        firstName = cleanField(firstName, 60), lastName = cleanField(lastName, 60),
        role = cleanField(role, 60), spec = cleanField(spec, 80),
        timezone = cleanField(timezone, 60), alts = cleanField(alts, 200), professions = cleanField(professions, 250), race = cleanField(race, 60),
        ts = time(), by = player,
        characterName = player,
        characterGUID = UnitGUID and UnitGUID("player") or nil,
    }
    self.bucket.profiles[player] = profile
    GuildHallDB = type(GuildHallDB) == "table" and GuildHallDB or {}
    GuildHallDB.localProfiles = type(GuildHallDB.localProfiles) == "table" and GuildHallDB.localProfiles or {}
    GuildHallDB.localProfiles[player] = profile
    GuildHallDB.localProfiles[playerBase] = profile
    if profile.characterGUID then GuildHallDB.localProfiles[profile.characterGUID] = profile end
    GuildHallDB.playerProfile = profile
    self.playerProfile = profile
    self.profileCache[playerBase] = profile
    self.profileCache[nameKey(player)] = profile
    self:SendRecord("PF", player, profile.ts, player, encodeProfile(profile))
    self.profileTarget, self.activeTab = player, "Roster"
    self.selectedRosterName = player
    if self.RefreshUI then self:RefreshUI() end
    return true, "Profile saved and shared with online Guild Hall users."
end

local professionScanPending = false
local function scheduleProfessionScan()
    if professionScanPending then return end
    professionScanPending = true
    local function scan()
        professionScanPending = false
        GH:RefreshPlayerProfessions()
    end
    if C_Timer and C_Timer.After then C_Timer.After(1, scan) else scan() end
end
GH:RegisterEventHandler("PLAYER_LOGIN", scheduleProfessionScan)
GH:RegisterEventHandler("SKILL_LINES_CHANGED", scheduleProfessionScan)
GH:RegisterEventHandler("TRADE_SKILL_UPDATE", scheduleProfessionScan)

GH:RegisterCommand("profile", function(rest)
    local action, profileRest = rest:match("^(%S+)%s*(.*)$")
    action = (action or ""):lower()
    if action == "set" then
        local firstName, lastName, role, spec, timezone, alts, professions, race = profileRest:match("^(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.*)$")
        if not firstName then
            firstName, lastName, role, spec, timezone, alts, professions = profileRest:match("^(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.*)$")
            race = ""
        end
        if not firstName then
            role, spec, timezone, alts, professions = profileRest:match("^(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.*)$")
            firstName, lastName = "", ""
        end
        if not role then role, spec, timezone, alts = profileRest:match("^(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.*)$") end
        local _, result = GH:SetProfile(firstName, lastName, role, spec, timezone, alts, professions, race)
        print("Guild Hall: " .. result)
        return
    end
    if action == "list" then
        GH.profileTarget, GH.activeTab = nil, "Roster"
        GH:Open()
        return
    end
    local target = action == "view" and profileRest or rest
    if target == "" then target = UnitName and UnitName("player") or "" end
    GH.profileTarget, GH.activeTab = target, "Roster"
    GH.selectedRosterName = target
    GH:Open()
end)

local function profileFor(name)
    return GH:GetProfile(name)
end

GH:RegisterTab("Profiles", function()
    if not GH.bucket then return "Join a guild to view member profiles." end
    local target = GH.profileTarget
    if target and target ~= "" then
        local profile = profileFor(target)
        if not profile then return ("No profile found for %s. Create one with /gh profile set First | Last | Role | Spec | Time zone | Alts | Professions | Race."):format(GH:Display(target)) end
        local function field(value) return GH:Display(value ~= "" and value or "Not set") end
        local displayName = ((profile.firstName or "") .. " " .. (profile.lastName or "")):gsub("^%s+", ""):gsub("%s+$", "")
        if displayName == "" then displayName = target end
        return ("%s\n\nCharacter: %s\nRace: %s\nRole: %s\nSpec: %s\nTime zone: %s\nAlts: %s\nProfessions / recipes: %s"):format(
            GH:Display(displayName), GH:Display(target), field(profile.race or ""), field(profile.role or ""), field(profile.spec or ""), field(profile.timezone or ""), field(profile.alts or ""), field(profile.professions or ""))
    end
    if not GH.roster or #GH.roster == 0 then return "Loading guild members..." end
    local lines = { "Member profiles", "Use /gh profile Name to view one. Set yours with /gh profile set First | Last | Role | Spec | Time zone | Alts | Professions | Race.", "" }
    for _, member in ipairs(GH.roster) do
        local profile = profileFor(member.name)
        local role, spec = profile and profile.role or "", profile and profile.spec or ""
        local summary = role ~= "" and spec ~= "" and (role .. " · " .. spec) or (role ~= "" and role or (spec ~= "" and spec or "Profile not set"))
        lines[#lines + 1] = GH:Display(member.name) .. " — " .. GH:Display(summary)
    end
    return table.concat(lines, "\n")
end)


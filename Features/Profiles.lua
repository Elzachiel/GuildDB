-- Self-managed guild member profiles and profile directory.
local _, GD = ...
GD:RegisterBucket("profiles", function() return {} end)
GD.profileCache = GD.profileCache or {}

local classSpecs = {
    WARRIOR = { "Arms", "Fury", "Protection" },
    PALADIN = { "Holy", "Protection", "Retribution" },
    HUNTER = { "Beast Mastery", "Marksmanship", "Survival" },
    ROGUE = { "Assassination", "Combat", "Subtlety" },
    PRIEST = { "Discipline", "Holy", "Shadow" },
    SHAMAN = { "Elemental", "Enhancement", "Restoration" },
    MAGE = { "Arcane", "Fire", "Frost" },
    WARLOCK = { "Affliction", "Demonology", "Destruction" },
    DRUID = { "Balance", "Feral Combat", "Restoration" },
}

-- Forever exposes talent points through specialization or trait-group APIs;
-- older clients expose talent tabs with either the three- or five-field layout.
function GD:GetPlayerSpecOptions()
    local class
    if UnitClass then local _, token = UnitClass("player"); class = token end
    local fallback = classSpecs[class] or {}
    local trees, zeroTrees = {}, nil
    local function addTree(index, name, points)
        if issecretvalue and (issecretvalue(name) or issecretvalue(points)) then return end
        -- Empty trees can have a name but no points field on this client.
        if points == nil then points = 0 end
        if type(name) == "string" and name ~= "" and type(points) == "number" and points >= 0 then
            trees[index] = { name = name, points = points }
        end
    end
    local function fillEmptyTrees()
        local spent = false
        for i = 1, 3 do if trees[i] and trees[i].points > 0 then spent = true end end
        if not spent then return end
        -- Trait currency replies may omit entire unspent groups. Once spent
        -- points are readable, fill the other known class trees with zeroes.
        for i = 1, 3 do if not trees[i] and fallback[i] then addTree(i, fallback[i], 0) end end
    end
    local function collect()
        local function completeWithPoints()
            fillEmptyTrees()
            return trees[1] and trees[2] and trees[3]
                and (trees[1].points + trees[2].points + trees[3].points) > 0
        end
        if GetTalentTabInfo then
            for i = 1, 3 do
                local ok, a, b, c, _, e = pcall(GetTalentTabInfo, i)
                if ok then
                    local name, points = type(a) == "number" and b or a, type(a) == "number" and e or c
                    addTree(i, name, points)
                end
            end
            if completeWithPoints() then return end
            if trees[1] and trees[2] and trees[3] then zeroTrees = trees end
            trees = {}
        end
        local api = C_SpecializationInfo
        if api and api.GetSpecializationInfo then
            for i = 1, 3 do
                local ok, _, name, _, _, _, _, points = pcall(api.GetSpecializationInfo, i)
                if not ok or type(name) ~= "string" then
                    ok, _, name, _, _, _, _, points = pcall(api.GetSpecializationInfo, { specializationIndex = i })
                end
                if ok then addTree(i, name, points) end
            end
            if completeWithPoints() then return end
            if trees[1] and trees[2] and trees[3] then zeroTrees = trees end
            trees = {}
        end
        local traits, talents = C_Traits, C_ClassTalents
        if not (traits and traits.GetConfigInfo
            and traits.GetGroupDisplayInfoByTreeID and traits.GetGroupCurrencyInfo) then return end
        local config = talents and talents.GetActiveConfigID and talents.GetActiveConfigID()
        if not config and api and api.GetActiveSpecGroup and api.GetCombatConfigIDForSpecGroup then
            local group = api.GetActiveSpecGroup()
            if group then config = api.GetCombatConfigIDForSpecGroup(group) end
        end
        local info = config and traits.GetConfigInfo(config)
        local tree = info and info.treeIDs and info.treeIDs[1]
        local displays = tree and traits.GetGroupDisplayInfoByTreeID(tree)
        if type(displays) ~= "table" or #displays ~= 3 then return end
        local sorted, ids, points = {}, {}, {}
        for i, display in ipairs(displays) do sorted[i] = display end
        table.sort(sorted, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
        for i, display in ipairs(sorted) do ids[i] = display.groupID end
        for _, group in ipairs(traits.GetGroupCurrencyInfo(config, ids) or {}) do
            local currency = group.currencyInfos and group.currencyInfos[1]
            if currency then points[group.traitNodeGroupID] = currency.spent end
        end
        for i, display in ipairs(sorted) do
            if type(points[display.groupID]) == "number" then
                addTree(i, display.displayName or fallback[i], points[display.groupID])
            end
        end
    end
    local ok = pcall(collect)
    if not ok then trees = {} end
    fillEmptyTrees()
    if not (trees[1] and trees[2] and trees[3]) and zeroTrees then trees = zeroTrees end
    local options, signature, best, winner, tied = {}, {}, 0, nil, false
    for i = 1, 3 do
        local tree = trees[i]
        local name = tree and tree.name or fallback[i]
        if name then options[#options + 1] = name end
        if tree then
            signature[#signature + 1] = tostring(tree.points)
            if tree.points > best then best, winner, tied = tree.points, name, false
            elseif tree.points == best and best > 0 then tied = true end
        end
    end
    -- Missing data, no spent points and tied builds must not invent a main spec.
    local complete = #signature == 3
    return options, complete and not tied and winner or nil,
        complete and ((class or "") .. ":" .. table.concat(signature, "/")) or nil,
        { trees = trees, status = not complete and "Talent data unavailable"
            or best == 0 and "No talent points spent" or tied and "Talent trees tied for most points" or "Detected" }
end

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
    local playerName = GD:PlayerName()
    local saved = GD.playerProfile or (GDB and GDB.playerProfile)
    for _, member in ipairs(GD.roster or {}) do
        if sameCharacter(member.name, playerName) or profileMatches(saved, member.name) then
            return member.name
        end
    end
    -- Some Forever guild roster names include the player's surname while
    -- UnitName() returns only the character's first/name token. Use a unique
    -- roster prefix match when there is exactly one candidate.
    local key, candidate = nameKey(playerName), nil
    if key ~= "" then
        for _, member in ipairs(GD.roster or {}) do
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

function GD:GetPlayerNameParts()
    return characterNameParts(currentRosterName())
end

function GD:SetPlayerSpecChoice(spec)
    local options, _, signature = self:GetPlayerSpecOptions()
    for _, option in ipairs(options) do
        if option == spec then
            GDB = GDB or {}
            GDB.specChoices = GDB.specChoices or {}
            GDB.specChoices[nameKey(currentRosterName())] = { spec = spec, build = signature }
            return true
        end
    end
    return false
end

function GD:RefreshPlayerSpec()
    if not self.bucket then return end
    local options, detected, signature = self:GetPlayerSpecOptions()
    local player = currentRosterName()
    local choice = GDB and GDB.specChoices and GDB.specChoices[nameKey(player)]
    local selected = detected
    if choice and choice.build == signature then
        for _, option in ipairs(options) do if choice.spec == option then selected = option; break end end
    end
    local profile = self:GetProfile(player) or {}
    if not selected or profile.spec == selected then return end
    self:SetProfile(nil, nil, profile.role, selected, profile.timezone, profile.alts, profile.professions, profile.race, true)
end

function GD:GetProfile(name)
    if not name then return nil end
    local wanted = baseName(name)
    local wantedKey = nameKey(name)
    local localProfiles = GDB and GDB.localProfiles or {}
    local guildProfiles = self.bucket and self.bucket.profiles or {}
    local ownProfile = GDB and GDB.playerProfile
    local playerName = self:PlayerName()
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

-- Only the two main professions and Cooking belong in member profiles.
local professionColors = {
    alchemy = "79d98b", blacksmithing = "929ba6", enchanting = "bd91ff",
    engineering = "f2c94c", herbalism = "65c96f", mining = "c9a66b",
    leatherworking = "d49364", skinning = "c9b18a", tailoring = "91b9ed",
    jewelcrafting = "64d9d0", inscription = "e6bb78", cooking = "f29d63",
}

function GD:GetProfileProfessionList(value)
    local result, seen, mainCount = {}, {}, 0
    local cooking
    for entry in tostring(value or ""):gmatch("[^,]+") do
        local name, rank = entry:match("^%s*(.-)%s+(%d+)%s*$")
        local key = name and name:lower()
        if professionColors[key] and not seen[key] and (key == "cooking" or mainCount < 2) then
            seen[key] = true
            if key ~= "cooking" then mainCount = mainCount + 1 end
            local profession = { name = name, rank = tonumber(rank), color = professionColors[key] }
            if key == "cooking" then cooking = profession
            else result[#result + 1] = profession end
        end
    end
    if cooking then result[#result + 1] = cooking end
    return result
end

function GD:FormatProfileProfessions(value)
    local lines = {}
    for _, profession in ipairs(self:GetProfileProfessionList(value)) do
        lines[#lines + 1] = profession.name .. " " .. profession.rank
    end
    return #lines > 0 and table.concat(lines, ", ") or "Not set"
end

-- WoW Forever exposes the character's Skills tab through C_SkillInfo.
function GD:GetPlayerProfessions()
    local api = C_SkillInfo or {}
    local professions, seen = {}, {}
    local function add(name, rank)
        if type(name) ~= "string" or name == "" then return end
        rank = tonumber(rank) or 0
        local key = name:lower()
        if not professionColors[key] then return end
        if not seen[key] then
            seen[key] = #professions + 1
            professions[#professions + 1] = { name = name, rank = rank }
        else
            professions[seen[key]].rank = math.max(professions[seen[key]].rank, rank)
        end
    end
    -- Read professions even when their Skills headers are collapsed.
    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local ok, a, b, c, d, e, f = pcall(GetProfessions)
        if ok then
            local indices = { a, b, c, d, e, f }
            for slot = 1, 6 do
                if indices[slot] then
                    local got, name, _, rank = pcall(GetProfessionInfo, indices[slot])
                    if got then add(name, rank) end
                end
            end
        end
    end
    local countSkills = api.GetNumSkillLines or GetNumSkillLines
    local skillInfo = api.GetSkillLineInfo or GetSkillLineInfo
    local count, inProfessionGroup = 0, false
    if type(countSkills) == "function" and type(skillInfo) == "function" then
        local ok, result = pcall(countSkills)
        if ok and type(result) == "number" then count = result end
    end
    for index = 1, count do
        local lineOK, info, isHeader, _, rank, _, _, maxRank = pcall(skillInfo, index)
        if lineOK and type(info) == "string" then
            info = { name = info, isHeader = isHeader, rank = rank, maxRank = maxRank }
        end
        if lineOK and type(info) == "table" then
            local name = info.name
            if info.isHeader then
                local header = type(name) == "string" and name:lower() or ""
                inProfessionGroup = header:find("profession", 1, true) ~= nil or header:find("secondary", 1, true) ~= nil
                    or info.skillID == 9 or info.skillID == 11
            elseif (inProfessionGroup or info.skillLineCategoryID == 9 or info.skillLineCategoryID == 11)
                and type(name) == "string" and name ~= "" and (tonumber(info.maxRank) or 0) > 1 then
                add(name, info.rank)
            end
        end
    end
    local display = {}
    for _, profession in ipairs(professions) do
        display[#display + 1] = profession.name .. " " .. profession.rank
    end
    local filtered = self:GetProfileProfessionList(table.concat(display, ", "))
    display = {}
    for _, profession in ipairs(filtered) do
        display[#display + 1] = profession.name .. " " .. profession.rank
    end
    return table.concat(display, ", "), filtered
end

function GD:RefreshPlayerProfessions()
    if not self.bucket then return end
    local professions = self:GetPlayerProfessions()
    local player = currentRosterName()
    local profile = self:GetProfile(player) or {}
    local firstName, lastName = self:GetPlayerNameParts()
    if profile.firstName == firstName and profile.lastName == lastName
        and (not professions or professions == "" or profile.professions == professions) then return end
    professions = professions and professions ~= "" and professions or profile.professions
    self:SetProfile(profile.firstName, profile.lastName, profile.role, profile.spec, profile.timezone, profile.alts, professions, profile.race, true)
end

local function cleanField(value, limit)
    value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return value:gsub("[\r\n|]", " "):sub(1, limit)
end

local function encodeProfile(profile)
    return table.concat({ profile.firstName or "", profile.lastName or "", profile.role or "", profile.spec or "", profile.timezone or "", profile.alts or "", profile.professions or "", profile.race or "" }, "\n")
end

GD:RegisterRecordHandler("PF", function(id, ts, author, content)
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
    firstName, lastName, race = firstName or "", lastName or "", race or ""
    if not role or id:lower() ~= author:lower() or #id > 80 or #firstName > 60 or #lastName > 60 or #role > 60 or #spec > 80 or #timezone > 60 or #alts > 200 or #professions > 250 or #race > 60 then return end
    local previous = GD.bucket.profiles[id]
    -- Ignore same-second echoes/duplicates too; they may carry an older copy
    -- of the profile and otherwise replace the just-saved local values.
    if previous and previous.ts and previous.ts >= ts then return end
    local profile = { firstName = firstName, lastName = lastName, role = role, spec = spec, timezone = timezone, alts = alts, professions = professions, race = race, ts = ts, by = author, characterName = id }
    GD.bucket.profiles[id] = profile
    GD.profileCache[baseName(id)] = profile
    if GD.RefreshUI then GD:RefreshUI() end
end)

GD:RegisterHistoryProvider(function()
    for player, profile in pairs(GD.bucket.profiles or {}) do
        GD:SendRecord("PF", player, profile.ts or time(), player, encodeProfile(profile))
    end
end, false)

function GD:SetProfile(firstName, lastName, role, spec, timezone, alts, professions, race, preserveView)
    if not self.bucket then return false, "Join a guild first." end
    local player = currentRosterName()
    local playerBase = baseName(player)
    firstName, lastName = characterNameParts(player)
    local detectedRace = UnitRace and UnitRace("player") or nil
    if type(detectedRace) == "table" then detectedRace = detectedRace[1] end
    race = (type(detectedRace) == "string" and detectedRace ~= "" and detectedRace) or race
    local detectedProfessions = self:GetPlayerProfessions()
    if detectedProfessions ~= nil and detectedProfessions ~= "" then professions = detectedProfessions end
    local previous = self:GetProfile(player)
    local profile = {
        firstName = cleanField(firstName, 60), lastName = cleanField(lastName, 60),
        role = cleanField(role, 60), spec = cleanField(spec, 80),
        timezone = cleanField(timezone, 60), alts = cleanField(alts, 200), professions = cleanField(professions, 250), race = cleanField(race, 60),
        -- Profession and talent scans can both update the profile in one second.
        ts = math.max(time(), (previous and previous.ts or 0) + 1), by = player,
        characterName = player,
        characterGUID = UnitGUID and UnitGUID("player") or nil,
    }
    self.bucket.profiles[player] = profile
    GDB = type(GDB) == "table" and GDB or {}
    GDB.localProfiles = type(GDB.localProfiles) == "table" and GDB.localProfiles or {}
    GDB.localProfiles[player] = profile
    GDB.localProfiles[playerBase] = profile
    if profile.characterGUID then GDB.localProfiles[profile.characterGUID] = profile end
    GDB.playerProfile = profile
    self.playerProfile = profile
    self.profileCache[playerBase] = profile
    self.profileCache[nameKey(player)] = profile
    self:SendRecord("PF", player, profile.ts, player, encodeProfile(profile))
    if not preserveView then
        self.profileTarget, self.activeTab = player, "Roster"
        self.selectedRosterName = player
    end
    if self.RefreshUI then self:RefreshUI() end
    return true, "Profile saved and shared with online GuildDB users."
end

local professionScanPending = false
local function scheduleProfessionScan()
    if professionScanPending then return end
    professionScanPending = true
    local function scan()
        professionScanPending = false
        GD:RefreshPlayerProfessions()
        GD:RefreshPlayerSpec()
    end
    if C_Timer and C_Timer.After then C_Timer.After(1, scan) else scan() end
end
GD:RegisterEventHandler("PLAYER_LOGIN", scheduleProfessionScan)
GD:RegisterEventHandler("GUILD_ROSTER_UPDATE", scheduleProfessionScan)
GD:RegisterEventHandler("PLAYER_GUILD_UPDATE", scheduleProfessionScan)
GD:RegisterEventHandler("SKILL_LINES_CHANGED", scheduleProfessionScan)
GD:RegisterEventHandler("TRADE_SKILL_UPDATE", scheduleProfessionScan)
GD:RegisterEventHandler("PLAYER_ENTERING_WORLD", scheduleProfessionScan)
GD:RegisterEventHandler("PLAYER_TALENT_UPDATE", scheduleProfessionScan)
GD:RegisterEventHandler("CHARACTER_POINTS_CHANGED", scheduleProfessionScan)
GD:RegisterEventHandler("ACTIVE_TALENT_GROUP_CHANGED", scheduleProfessionScan)
GD:RegisterEventHandler("TRAIT_CONFIG_UPDATED", scheduleProfessionScan)

GD:RegisterCommand("spec", function()
    local options, detected, signature, details = GD:GetPlayerSpecOptions()
    print("GuildDB: Detected main spec: " .. (detected or ("Unknown (" .. details.status .. ")")))
    for i, option in ipairs(options) do
        local tree = details.trees[i]
        print("GuildDB: " .. option .. ": " .. (tree and tostring(tree.points) or "unavailable") .. " talent points")
    end
    local player = currentRosterName()
    local profile = GD:GetProfile(player)
    local choice = GDB and GDB.specChoices and GDB.specChoices[nameKey(player)]
    local manual = choice and choice.build == signature and profile and profile.spec == choice.spec
    print("GuildDB: Saved profile spec: " .. (profile and profile.spec ~= "" and profile.spec or "Not set")
        .. (manual and " (manual override for this build)" or ""))
end)

GD:RegisterCommand("profile", function(rest)
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
        local _, result = GD:SetProfile(firstName, lastName, role, spec, timezone, alts, professions, race)
        print("GuildDB: " .. result)
        return
    end
    if action == "list" then
        GD.profileTarget, GD.activeTab = nil, "Roster"
        GD:Open()
        return
    end
    local target = action == "view" and profileRest or rest
    if target == "" then target = UnitName and UnitName("player") or "" end
    GD.profileTarget, GD.activeTab = target, "Roster"
    GD.selectedRosterName = target
    GD:Open()
end)

local function profileFor(name)
    return GD:GetProfile(name)
end

GD:RegisterTab("Profiles", function()
    if not GD.bucket then return "Join a guild to view member profiles." end
    local target = GD.profileTarget
    if target and target ~= "" then
        local profile = profileFor(target)
        if not profile then return ("No profile found for %s. Create one with /gd profile set First | Last | Role | Spec | Time zone | Alts | Professions | Race."):format(GD:Display(target)) end
        local function field(value) return GD:Display(value ~= "" and value or "Not set") end
        local displayName = ((profile.firstName or "") .. " " .. (profile.lastName or "")):gsub("^%s+", ""):gsub("%s+$", "")
        if displayName == "" then displayName = target end
        return ("%s\n\nCharacter: %s\nRace: %s\nRole: %s\nSpec: %s\nTime zone: %s\nAlts: %s\nProfessions / recipes: %s"):format(
            GD:Display(displayName), GD:Display(target), field(profile.race or ""), field(profile.role or ""), field(profile.spec or ""), field(profile.timezone or ""), field(profile.alts or ""), field(profile.professions or ""))
    end
    if not GD.roster or #GD.roster == 0 then return "Loading guild members..." end
    local lines = { "Member profiles", "Use /gd profile Name to view one. Set yours with /gd profile set First | Last | Role | Spec | Time zone | Alts | Professions | Race.", "" }
    for _, member in ipairs(GD.roster) do
        local profile = profileFor(member.name)
        local role, spec = profile and profile.role or "", profile and profile.spec or ""
        local summary = role ~= "" and spec ~= "" and (role .. " · " .. spec) or (role ~= "" and role or (spec ~= "" and spec or "Profile not set"))
        lines[#lines + 1] = GD:Display(member.name) .. " — " .. GD:Display(summary)
    end
    return table.concat(lines, "\n")
end)


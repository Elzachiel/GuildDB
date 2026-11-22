-- Run: npm.cmd exec --yes --package=fengari-node-cli -- fengari Tests/ProfileSpecs.lua
local GD = { bucket = {}, sent = {}, events = {}, activeTab = 'PvP', selectedRosterName = 'Other Member' }
function GD:RegisterBucket(key, factory) self.bucket[key] = factory() end
function GD:RegisterRecordHandler() end
function GD:RegisterHistoryProvider() end
GD.commands = {}
function GD:RegisterCommand(command, callback) self.commands[command] = callback end
function GD:RegisterTab() end
function GD:RegisterEventHandler(event, callback) self.events[event] = callback end
function GD:PlayerName() return 'Player Moon' end
function GD:SendRecord(...) self.sent[#self.sent + 1] = {...} end
function GD:RefreshUI() end
time = function() return 1000 end
GDB = {}
local class, points = 'MAGE', { 10, 31, 0 }
local names = { 'Arcane', 'Fire', 'Frost' }
UnitClass = function() return 'Mage', class end
GetTalentTabInfo = function(i) return names[i], 'icon', points[i] end
assert(loadfile('Features/Profiles.lua'))('GuildDB', GD)
local choices, detected = GD:GetPlayerSpecOptions()
assert(#choices == 3 and choices[1] == 'Arcane' and detected == 'Fire')
GD:RefreshPlayerSpec()
assert(GD:GetProfile('Player Moon').spec == 'Fire')
assert(GD.sent[#GD.sent][1] == 'PF' and GD.sent[#GD.sent][5]:find('\nFire\n', 1, true), 'detected spec must use normal profile sync')
assert(GD.activeTab == 'PvP' and GD.selectedRosterName == 'Other Member', 'automatic detection must preserve the current view')
local sent = #GD.sent
local firstStamp = GD.sent[#GD.sent][3]
GD:RefreshPlayerSpec()
assert(#GD.sent == sent, 'unchanged talents must not repeatedly send profiles')
assert(GD:SetPlayerSpecChoice('Frost'))
assert(not GD:SetPlayerSpecChoice('Protection'), 'another class spec cannot be selected')
GD:RefreshPlayerSpec()
assert(GD:GetProfile('Player Moon').spec == 'Frost', 'manual choice remains for the same build')
assert(GD.sent[#GD.sent][3] > firstStamp, 'same-second profile updates need distinct timestamps so peers accept the new spec')
points = { 0, 0, 41 }
GD:RefreshPlayerSpec()
assert(GD:GetProfile('Player Moon').spec == 'Frost')
points = { 41, 0, 0 }
GD:RefreshPlayerSpec()
assert(GD:GetProfile('Player Moon').spec == 'Arcane', 'a changed build resumes automatic detection')
points = { 20, 20, 0 }
choices, detected = GD:GetPlayerSpecOptions()
assert(detected == nil, 'ties cannot invent a main spec')
points = { 0, 0, 0 }
choices, detected = GD:GetPlayerSpecOptions()
assert(detected == nil, 'unspent builds cannot invent a main spec')
GD:RefreshPlayerSpec()
assert(GD:GetProfile('Player Moon').spec == 'Arcane', 'unknown data must retain the previous choice')
-- ID/name/description/icon/points layout.
points = { 0, 42, 0 }
GetTalentTabInfo = function(i) return 100 + i, names[i], 'description', 'icon', points[i] end
choices, detected = GD:GetPlayerSpecOptions()
assert(detected == 'Fire')
GetTalentTabInfo = function() error('unavailable API') end
choices, detected = GD:GetPlayerSpecOptions()
assert(#choices == 3 and detected == nil, 'API failures still allow a class dropdown')
-- Forever specialization data can use positional or table arguments.
C_SpecializationInfo = { GetSpecializationInfo = function(i)
    if type(i) ~= 'table' then error('table argument required') end
    local index = i.specializationIndex
    return index, names[index], '', 'icon', '', '', points[index]
end }
choices, detected = GD:GetPlayerSpecOptions()
assert(detected == 'Fire')
GetTalentTabInfo, C_SpecializationInfo = nil, nil
-- Forever trait groups are sorted by display order, not their return order.
C_ClassTalents = { GetActiveConfigID = function() return 1 end }
C_SpecializationInfo = { GetSpecializationInfo = function(i) return i, names[i], '', 'icon', '', '', 0 end }
C_Traits = {
    GetConfigInfo = function() return { treeIDs = { 10 } } end,
    GetGroupDisplayInfoByTreeID = function()
        return {{groupID=3,orderIndex=3,displayName='Frost'}, {groupID=1,orderIndex=1,displayName='Arcane'}, {groupID=2,orderIndex=2,displayName='Fire'}}
    end,
    GetGroupCurrencyInfo = function()
        return {{traitNodeGroupID=1,currencyInfos={{spent=0}}}, {traitNodeGroupID=2,currencyInfos={{spent=0}}}, {traitNodeGroupID=3,currencyInfos={{spent=41}}}}
    end,
}
choices, detected = GD:GetPlayerSpecOptions()
assert(choices[1] == 'Arcane' and choices[3] == 'Frost' and detected == 'Frost')
C_Traits, C_ClassTalents, C_SpecializationInfo = nil, nil, nil
class = 'WARRIOR'
choices, detected = GD:GetPlayerSpecOptions()
assert(#choices == 3 and choices[1] == 'Arms' and choices[2] == 'Fury' and choices[3] == 'Protection' and detected == nil)
class = 'DRUID'
choices = GD:GetPlayerSpecOptions()
assert(#choices == 3 and choices[2] == 'Feral Combat')
assert(GD.events.PLAYER_TALENT_UPDATE and GD.events.CHARACTER_POINTS_CHANGED and GD.events.TRAIT_CONFIG_UPDATED)
-- Coalesced talent notifications update/share once and do not switch tabs.
class, points = 'MAGE', { 0, 41, 0 }
GetTalentTabInfo = function(i) return names[i], 'icon', points[i] end
local queued = {}
C_Timer = { After = function(_, callback) queued[#queued + 1] = callback end }
GD.events.PLAYER_TALENT_UPDATE()
GD.events.TRAIT_CONFIG_UPDATED()
assert(#queued == 1)
queued[1]()
assert(GD:GetProfile('Player Moon').spec == 'Fire' and GD.activeTab == 'PvP')
print('PASS: class spec choices, main talent tree, ties/zero points, API layouts, Forever specs/traits, manual override, profile sync and talent updates')
local function diagnostic()
    local lines, savedPrint = {}, print
    print = function(message) lines[#lines + 1] = message end
    GD.commands.spec()
    print = savedPrint
    return table.concat(lines, '\n')
end
local sendsBefore = #GD.sent
local output = diagnostic()
assert(output:find('Detected main spec: Fire', 1, true) and output:find('Fire: 41 talent points', 1, true))
assert(output:find('Saved profile spec: Fire', 1, true) and #GD.sent == sendsBefore, 'diagnostic must not alter or sync the profile')
assert(GD:SetPlayerSpecChoice('Frost'))
GD:RefreshPlayerSpec()
assert(diagnostic():find('manual override for this build', 1, true))
points = {20,20,0}
assert(diagnostic():find('Talent trees tied for most points', 1, true))
points = {0,0,0}
assert(diagnostic():find('No talent points spent', 1, true))
GetTalentTabInfo = nil
assert(diagnostic():find('Talent data unavailable', 1, true))
print('PASS: /gd spec detection, per-tree points, saved spec, manual override, ties, unspent/unavailable data and read-only output')

-- Reported Warlock build: 16 Affliction / 31 Demonology / omitted Destruction.
class, names, points = 'WARLOCK', {'Affliction','Demonology','Destruction'}, {16,31}
GetTalentTabInfo = function(i) return names[i], 'icon', points[i] end
choices, detected = GD:GetPlayerSpecOptions()
assert(detected == 'Demonology', 'an empty third tree must not block main spec detection')
output = diagnostic()
assert(output:find('Detected main spec: Demonology', 1, true))
assert(output:find('Destruction: 0 talent points', 1, true) and not output:find('unavailable', 1, true))
GetTalentTabInfo = function(i) if i == 2 then return names[i], 'icon', 31 end end
choices, detected = GD:GetPlayerSpecOptions()
assert(detected == 'Demonology', 'omitted unspent legacy trees also count as zero')
GetTalentTabInfo = nil
C_ClassTalents = { GetActiveConfigID = function() return 1 end }
C_Traits = {
    GetConfigInfo = function() return {treeIDs={10}} end,
    GetGroupDisplayInfoByTreeID = function()
        return {{groupID=1,orderIndex=1,displayName='Affliction'}, {groupID=2,orderIndex=2,displayName='Demonology'}, {groupID=3,orderIndex=3,displayName='Destruction'}}
    end,
    GetGroupCurrencyInfo = function()
        return {{traitNodeGroupID=1,currencyInfos={{spent=16}}}, {traitNodeGroupID=2,currencyInfos={{spent=31}}}}
    end,
}
choices, detected = GD:GetPlayerSpecOptions()
assert(detected == 'Demonology')
assert(diagnostic():find('Destruction: 0 talent points', 1, true), 'omitted trait currency group must display zero')
GD:RefreshPlayerSpec()
assert(GD:GetProfile('Player Moon').spec == 'Demonology')
print('PASS: Warlock 16/31/0 detection and zero-point output for omitted legacy/trait trees')

-- Old peer profiles may still contain First Aid, Fishing, and other skills.
local profileSkills = 'Blacksmithing 19, Mining 8, First Aid 1, Cooking 1, Fishing 5, Defense 60, Alchemy 30'
local listed = GD:GetProfileProfessionList(profileSkills)
assert(#listed == 3 and listed[1].name == 'Blacksmithing' and listed[2].name == 'Mining' and listed[3].name == 'Cooking')
local formatted = GD:FormatProfileProfessions(profileSkills)
assert(formatted == 'Blacksmithing 19, Mining 8, Cooking 1')
assert(listed[1].color ~= listed[2].color and listed[2].color ~= listed[3].color, 'professions need distinct colors')
assert(not formatted:find('First Aid', 1, true) and not formatted:find('Fishing', 1, true))
assert(GD:FormatProfileProfessions('First Aid 20, Fishing 50') == 'Not set')
assert(GD:FormatProfileProfessions(nil) == 'Not set')

GetProfessions = function() return 1, 2, 3, 4, 5 end
local apiSkills = { {'Blacksmithing',19}, {'Mining',8}, {'First Aid',1}, {'Fishing',5}, {'Cooking',1} }
GetProfessionInfo = function(index) return apiSkills[index][1], 'icon', apiSkills[index][2] end
local detectedSkills = GD:GetPlayerProfessions()
assert(detectedSkills == 'Blacksmithing 19, Mining 8, Cooking 1', 'profession API must exclude secondary skills other than Cooking: ' .. detectedSkills)
GetProfessions, GetProfessionInfo = nil, nil
C_SkillInfo = {
    GetNumSkillLines = function() return 7 end,
    GetSkillLineInfo = function(index)
        if index == 1 then return {name='Professions', isHeader=true} end
        if index == 4 then return {name='Secondary Skills', isHeader=true} end
        local skill = apiSkills[index < 4 and index - 1 or index - 2]
        return {name=skill[1], rank=skill[2], maxRank=300}
    end,
}
assert(GD:GetPlayerProfessions() == detectedSkills, 'Skills tab scanning must apply the same filter')
print('PASS: profession colors, old profile filtering, two main professions plus Cooking, and both skill APIs')

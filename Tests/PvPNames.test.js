// Run with Node.js and the fengari/luaparse development dependencies.
const fs = require('fs'), path = require('path');
const dependency = name => require(process.env.GUILDDB_TEST_ROOT
    ? path.join(process.env.GUILDDB_TEST_ROOT, 'node_modules', name) : name);
const source = fs.readFileSync(path.join(__dirname, '../UI/Main.lua'), 'utf8');
dependency('luaparse').parse(source, { luaVersion: '5.1' });
const start = source.indexOf('local function pvpGuildRoster(');
const end = source.indexOf('local function rosterText()', start);
if (start < 0 || end < 0) throw new Error('PvP name helpers not found');
const call = source.match(/updatePvPNameStrike\(row, (not isRivals[^\n]+)\)/);
if (!call) throw new Error('PvP row rendering does not update the strike');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = dependency('fengari');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const test = `
${source.slice(start, end)}
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function characterKey(name) return tostring(name or ''):lower():gsub('%s', '') end
local roster, count = {}, 0
GetNumGuildMembers = function(includeOffline)
    check(includeOffline == true, 'membership must include offline members')
    return count
end
GetGuildRosterInfo = function(i)
    local member = roster[i]
    if member then return member.name, nil, nil, nil, nil, nil, nil, nil, member.online, nil, member.class end
end
local texture = { shown = false }
function texture:SetDrawLayer() end
function texture:SetPoint(point, target) self.target = target end
function texture:SetColorTexture(...) self.color = {...} end
function texture:SetSize(width, height) self.width, self.height = width, height end
function texture:SetShown(shown) self.shown = shown end
local row = { player = {}, allocations = 0 }
function row:CreateTexture() self.allocations = self.allocations + 1; return texture end
function row.player:GetTextColor() return 0.8, 0.9, 1 end
function row.player:GetStringWidth() return 120 end
function row.player:GetWidth() return 90 end
local cachedRoster = {}
local function render(name, rival, guild)
    local context = {roster=cachedRoster}
    function context:Display(value) return value == 'Windshaper Skyborne' and 'Skyborne' or value end
    local guildMembers, _, rosterComplete = pvpGuildRoster(characterKey, context)
    local score, isRivals, self = {name=name}, rival == true, {guildName=guild}
    updatePvPNameStrike(row, ${call[1]})
    return texture.shown
end
check(not render('Former Member', false, 'Guild'), 'empty roster must not mark departures')
roster = {
    {name='Online Member', online=true, class='MAGE'},
    {name='Offline Member', online=false, class='PRIEST'},
    {name='Realm Member-RealmA', online=false, class='ROGUE'},
    {name='No Class Yet', online=false},
}
count = 4
check(not render('Online Member', false, 'Guild'), 'current online member is unmarked')
check(not render('Offline Member', false, 'Guild'), 'offline member is unmarked')
check(not render('offline member', false, 'Guild'), 'name matching ignores case')
check(not render('Online', false, 'Guild'), 'shortened first-name PvP record matches current full roster name')
check(not render('Offline', false, 'Guild'), 'shortened offline-member name is unmarked')
check(not render('Online Member-RealmA', false, 'Guild'), 'realm-qualified report matches unqualified current roster name')
check(not render('No Class Yet', false, 'Guild'), 'membership does not require class data')
check(not render('Realm Member', false, 'Guild'), 'legacy realm-less records still match')
check(not render('Realm Member-RealmA', false, 'Guild'), 'exact realm matches')
check(render('Realm Member-RealmB', false, 'Guild'), 'different realms remain distinct')
check(render('Former Member', false, 'Guild'), 'former guild member gets a line')
check(texture.width == 90 and texture.height == 1, 'line fits visible name text')
check(texture.target == row.player and texture.color[1] == 0.8, 'line follows the name and its theme color')
check(not render('Enemy Player', true, 'Guild'), 'Nemesis and Bounty enemy rows clear the line')
check(not render('Former Member', false, nil), 'no guild does not mark everyone as departed')
roster[5] = {name='Former Member', online=false}; count = 5
check(not render('Former Member', false, 'Guild'), 'rejoining removes the line')
roster[5] = nil; count = 5
check(not render('Former Member', false, 'Guild'), 'partially loaded roster does not mark departures')
count = 4
check(render('Former Member', false, 'Guild'), 'complete refreshed roster recognizes departure')
check(not render('Online Member', false, 'Guild'), 'reused rows clear the previous name line')
cachedRoster = {{name='Offline Cached',classFile='MAGE'}}
check(not render('Offline Cached', false, 'Guild'), 'cached current member survives transient live roster omission')
check(not render('Offline', false, 'Guild'), 'abbreviated cached member is protected')
cachedRoster = {{name='Windshaper Skyborne'}}
check(not render('Skyborne', false, 'Guild'), 'known display-name alias remains a current member')
cachedRoster = {{name='Shortonly'}}
check(not render('Shortonly Fullname', false, 'Guild'), 'shortened roster entry protects the matching full PvP name')
check(not render('Shortonly Fullname-RealmA', false, 'Guild'), 'short roster entry does not falsely mark a qualified full name')
cachedRoster = {}
check(render('Offline Cached', false, 'Guild'), 'departure is marked after current-member cache updates')
check(row.allocations == 1, 'refreshes reuse one line texture per row')
GetNumGuildMembers = nil
check(not render('Former Member', false, 'Guild'), 'unavailable roster API leaves names unmarked')
print(checks .. ' PvP former-member name checks passed; Lua syntax valid.')
`;
if (lauxlib.luaL_dostring(L, to_luastring(test)) !== lua.LUA_OK) {
    throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
}

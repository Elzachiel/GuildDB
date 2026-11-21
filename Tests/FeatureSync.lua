-- Run: npm.cmd exec --yes --package=fengari-node-cli -- fengari Tests/FeatureSync.lua
local clock, player, rank = 1000, 'Leader Moon', 0
local roster = {
    {'Leader Moon', 'Leader', 0}, {'Member Moon', 'Member', 3},
    {'New Moon', 'Member', 3},
}
time = function() return clock end
GetTime = function() return clock end
GetNumGuildMembers = function() return #roster end
GetGuildRosterInfo = function(i) return table.unpack(roster[i]) end
GetGuildInfo = function() return 'Test Guild', 'Rank', rank end
GetUnitName = function() return player end
UnitName = function() return player:match('^(%S+)') end
SlashCmdList = {}
C_Timer = {After = function() end}
CreateFrame = function()
    return {
        RegisterEvent = function() end,
        SetScript = function(self, event, handler) self[event] = handler end,
    }
end
local function client()
    local gd = {}
    assert(loadfile('Core/Runtime.lua'))('GuildDB', gd)
    assert(loadfile('Features/Settings.lua'))('GuildDB', gd)
    gd.guildName, gd.bucket = 'Test Guild', {}
    gd.tabs = {'Home', 'Roster', 'PvP', 'Settings'}
    gd.refreshes = 0
    function gd:RefreshUI() self.refreshes = self.refreshes + 1 end
    return gd
end
local function receive(gd, sender, message)
    gd.eventFrame:OnEvent('CHAT_MSG_ADDON', gd.prefix, message, 'GUILD', sender)
end
local function transfer(source, target, sender, history)
    local queue = history and source.historyQueue or source.sendQueue
    for _, message in ipairs(queue) do receive(target, sender, message) end
    if history then source.historyQueue = {} else source.sendQueue = {} end
end
local leader, member, newcomer = client(), client(), client()
GDB = {}
leader:SetSetting('feature:PvP', false)
assert(leader.bucket.guildSettings.by == 'Leader Moon', 'save the full officer name')
transfer(leader, member, 'Leader Moon')
assert(not member:GetSetting('feature:PvP'), 'live disable must reach members')
assert(member.refreshes > 0, 'received switches must refresh sidebar visibility')

-- The elected history responder is a regular member; the officer is offline.
player, rank = 'Member Moon', 3
receive(member, 'New Moon', 'C|grant1|1|1|R|initial-sync|Member Moon')
assert(#member.historyQueue > 1, 'regular members must include feature settings in history')
transfer(member, newcomer, 'Member Moon', true)
assert(not newcomer:GetSetting('feature:PvP'), 'fresh installs must get disabled tabs from peers')
assert(newcomer.bucket.guildSettings.by == 'Leader Moon', 'relay must preserve officer attribution')
member:SetSetting('feature:PvP', true)
assert(not member:GetSetting('feature:PvP'), 'members cannot change guild switches')

-- Two changes in one second must have a strict order, even with stale history.
local oldConfig = member.bucket.guildSettings
player, rank = 'Leader Moon', 0
leader:SetSetting('feature:PvP', true)
transfer(leader, member, 'Leader Moon')
assert(member:GetSetting('feature:PvP'), 'live enable must reach members')
assert(member.bucket.guildSettings.ts > oldConfig.ts, 'rapid toggles need increasing revisions')
player, rank = 'Member Moon', 3
receive(member, 'New Moon', 'C|enable-sync|1|1|R|enable-sync|Member Moon')
transfer(member, newcomer, 'Member Moon', true)
assert(newcomer:GetSetting('feature:PvP'), 'returning members must sync the enabled value')
receive(member, 'New Moon', 'C|stale|1|1|F|features|' .. oldConfig.ts .. '|Leader Moon|PvP\t0')
assert(member:GetSetting('feature:PvP'), 'stale history must not undo a newer toggle')
receive(member, 'Member Moon', 'C|forged|1|1|F|features|2000|Member Moon|PvP\t0')
assert(member:GetSetting('feature:PvP'), 'member-authored switches must be rejected')
receive(member, 'Outsider', 'C|outsider|1|1|F|features|2000|Leader Moon|PvP\t0')
assert(member:GetSetting('feature:PvP'), 'non-guild senders must be rejected')

-- Preserve exact saved switches across different addon tab lists.
member.bucket.guildSettings = {ts = 3000, by = 'Leader Moon', features = {Announcements = false, FutureTab = false}}
player, rank = 'Member Moon', 3
receive(member, 'New Moon', 'C|grant2|1|1|R|next-sync|Member Moon')
transfer(member, newcomer, 'Member Moon', true)
assert(not newcomer:GetSetting('feature:Home'), 'legacy Home switch must survive relays')
assert(not newcomer:GetSetting('feature:FutureTab'), 'unknown saved tabs must survive relays')
assert(newcomer:GetSetting('feature:PvP'), 'unspecified tabs must keep their enabled default')
local loading = client()
local savedRoster = roster
roster = {}
receive(loading, 'Member Moon', 'C|early|1|1|F|features|4000|Leader Moon|PvP\t0')
assert(loading.bucket.guildSettings == nil, 'wait for ranks before accepting early history')
roster = savedRoster
loading.eventHandlers.GUILD_ROSTER_UPDATE[1]()
assert(not loading:GetSetting('feature:PvP'), 'apply early history once guild ranks load')
roster = {}
receive(loading, 'Member Moon', 'C|other-guild|1|1|F|features|4001|Leader Moon|PvP\t1')
loading.bucket = {}
roster = savedRoster
loading.eventHandlers.GUILD_ROSTER_UPDATE[1]()
assert(loading.bucket.guildSettings == nil, 'queued switches must not cross guild buckets')
print('PASS: feature switches sync live and through member history, preserve officer names and defaults, and reject stale/unauthorized updates')

-- Build the actual Settings controls and check access after rank changes.
local methods = {}
local function widget()
    return setmetatable({shown = true, scripts = {}}, {__index = function(_, key)
        return methods[key] or (key:match('^%u') and function() end or nil)
    end})
end
function methods:CreateFontString() return widget() end
function methods:CreateTexture() return widget() end
function methods:GetNormalTexture() return widget() end
function methods:GetPushedTexture() return widget() end
function methods:GetHighlightTexture() return widget() end
function methods:GetDisabledTexture() return widget() end
function methods:GetFontString() return widget() end
function methods:SetShown(value) self.shown = value end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetText(value) self.text = value end
function methods:SetScript(event, callback) self.scripts[event] = callback end
CreateFrame = function() return widget() end
local settingsUI = client()
function settingsUI:StyleButton() end
settingsUI.tabs = {'Home', 'Roster', 'Profiles', 'PvP', 'Settings'}
settingsUI.settingsSection = 'officer'
rank = 3
settingsUI:ShowSettingsControls(widget())
local officerTab
for _, control in ipairs(settingsUI.settingsControls) do
    assert(control.text ~= 'Profiles', 'Profiles must not appear in feature switches')
    if control.text == 'Officer' then officerTab = control end
end
assert(officerTab and not officerTab.shown, 'non-officers must not see the Officer tab')
assert(settingsUI.settingsSection == 'personal' and settingsUI.settingsPanels[1].shown)
assert(not settingsUI.settingsPanels[3].shown, 'non-officers must not see the Officer panel')
officerTab.scripts.OnClick()
assert(settingsUI.settingsSection == 'personal', 'Officer selection must also enforce rank')
rank = 1
settingsUI:ShowSettingsControls(widget())
assert(officerTab.shown, 'rank 1 must see the Officer tab')
officerTab.scripts.OnClick()
assert(settingsUI.settingsSection == 'officer' and settingsUI.settingsPanels[3].shown)
rank = 3
settingsUI:ShowSettingsControls(widget())
assert(not officerTab.shown and not settingsUI.settingsPanels[3].shown, 'demotion must hide Officer controls')
assert(settingsUI.settingsSection == 'personal', 'demotion must return to Personal')
rank = 0
settingsUI:ShowSettingsControls(widget())
assert(officerTab.shown, 'the guild leader must see the Officer tab')
print('PASS: Profiles omitted from switches; Officer tab/panel restricted to GM and rank 1, including rank changes')

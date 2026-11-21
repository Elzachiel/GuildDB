-- Run: npm.cmd exec --yes --package=fengari-node-cli -- fengari Tests/RosterRanks.lua
local GD = { guildName = 'Test Guild', activeTab = 'Roster' }
local events = {}
function GD:RegisterTab() end
function GD:RegisterEventHandler(event, callback) events[event] = callback end
function GD:Display(value) return tostring(value or '') end
assert(loadfile('UI/Main.lua'))('GuildDB', GD)
local ownRank, memberRank, combat = 0, 3, false
local promoteAllowed, demoteAllowed = true, true
GetGuildInfo = function() return 'Test Guild', 'Rank', ownRank end
GetNumGuildMembers = function() return 2 end
GetGuildRosterInfo = function(index)
    if index == 1 then return 'Player Moon', 'Rank', ownRank end
    return 'Member Moon', 'Rank', memberRank
end
GuildControlGetNumRanks = function() return 5 end
GuildControlGetRankName = function(index) return 'Rank ' .. index end
CanGuildPromote = function() return promoteAllowed end
CanGuildDemote = function() return demoteAllowed end
InCombatLockdown = function() return combat end
local choices = GD:GetRosterRankChoices('Member Moon')
assert(#choices == 3 and choices[1].rank == 1 and choices[3].rank == 4)
assert(#GD:GetRosterRankChoices('Player Moon') == 0)
assert(#GD:GetRosterRankChoices('Missing Moon') == 0)
ownRank = 1
choices = GD:GetRosterRankChoices('Member Moon')
assert(#choices == 2 and choices[1].rank == 2, 'cannot assign own rank')
promoteAllowed = false
assert(#GD:GetRosterRankChoices('Member Moon') == 1, 'demote permission remains independent')
demoteAllowed = false
assert(#GD:GetRosterRankChoices('Member Moon') == 0)
ownRank, promoteAllowed, demoteAllowed = 0, true, true
-- Restored in-addon dropdown: never load or open Blizzard's guild roster.
local function forbidden() error('must keep the rank selector inside GuildDB') end
C_AddOns = { LoadAddOn = forbidden }
ShowUIPanel = forbidden
local methods = {}
local function widget()
    return setmetatable({scripts={},hooks={},attributes={},shown=true}, {__index=function(_, key)
        return methods[key] or (key:match('^%u') and not key:match('^GuildDB') and function() end)
    end})
end
function methods:CreateFontString() return widget() end
function methods:CreateTexture() return widget() end
function methods:GetFontString() return widget() end
function methods:GetNormalTexture() return widget() end
methods.GetPushedTexture = methods.GetNormalTexture
methods.GetHighlightTexture = methods.GetNormalTexture
methods.GetDisabledTexture = methods.GetNormalTexture
function methods:GetFrameLevel() return 1 end
function methods:GetWidth() return 600 end
function methods:GetHeight() return 500 end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:HookScript(event, callback) self.hooks[event] = callback end
function methods:SetAttribute(key, value) self.attributes[key] = value end
function methods:SetText(text) self.text = text end
function methods:SetEnabled(value) self.enabled = value end
function methods:SetShown(value) self.shown = value end
function methods:IsShown() return self.shown end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
local serverRank, commandCount = 3, 0
local secureOnClick = function(self)
    if self.attributes.type ~= 'macro' then return end
    local macro = self.attributes.macrotext
    local _, promotes = macro:gsub('/gpromote ', '')
    local _, demotes = macro:gsub('/gdemote ', '')
    assert(promotes + demotes == 1, 'exactly one secure command per hardware click')
    serverRank = serverRank + (promotes == 1 and -1 or 1)
    commandCount = commandCount + 1
end
local function click(button)
    if button.hooks.PreClick then button.hooks.PreClick(button) end
    if button.scripts.OnClick then button.scripts.OnClick(button) end
    if button.hooks.PostClick then button.hooks.PostClick(button) end
end
CreateFrame = function(_, _, _, template)
    local frame = widget()
    if template and template:find('SecureActionButtonTemplate', 1, true) then frame.scripts.OnClick = secureOnClick end
    return frame
end
function GD:RefreshUI() end
GD:BuildUI()
GD.selectedRosterName = 'Member Moon'
GD:RefreshRosterRankControls(GD.selectedRosterName)
local dropdown = GD.frame.rosterRankDropdown
assert(dropdown.shown and dropdown.text == 'Set Guild Rank  v')
assert(GD.frame.rosterSetRankButton == nil, 'no separate apply button')
click(dropdown)
assert(dropdown.popup.shown and #dropdown.popup.rows == 3)
for index=1,10 do GD:RefreshRosterRankControls(GD.selectedRosterName) end
assert(dropdown.popup.shown, 'background refresh must preserve open dropdown')
local row = dropdown.popup.rows[1]
assert(row.scripts.OnClick == secureOnClick, 'preserve secure option handler')
assert(row.rankName == 'Member Moon' and row.rankValue == 1)
assert(row.attributes.type == 'macro' and row.attributes.macrotext:find('/gpromote Member Moon', 1, true))
row.hooks.PreClick(row)
assert(row.rankSubmitted)
assert(memberRank == 3, 'preparing an option must not claim a successful rank change')
GD.selectedRosterName = 'Player Moon'
GD:RefreshRosterRankControls(GD.selectedRosterName)
assert(not dropdown.shown and not dropdown.popup.shown)
row.hooks.PreClick(row)
assert(not row.rankSubmitted and row.attributes.type == nil, 'cancel stale member selection')
GD.activeTab = 'Home'
GD:RefreshRosterRankControls(nil)
assert(not dropdown.shown)
-- Reproduce Member -> Officer through Veteran, using server-confirmed steps.
local timers, requests = {}, 0
C_Timer = { After=function(delay, callback) timers[#timers+1]={delay,callback} end }
C_GuildInfo = { GuildRoster=function() requests=requests+1; memberRank=serverRank end }
local function poll()
    local scheduled = timers
    for _, timer in ipairs(scheduled) do if timer[1] == 0.75 then timer[2]() end end
end
function GD:RefreshUI() self:RefreshRosterRankControls(self.selectedRosterName) end
GD.activeTab, GD.selectedRosterName = 'Roster', 'Member Moon'
memberRank, serverRank = 3, 3
GD:RebuildRoster()
local function displayedRank()
    for _, member in ipairs(GD.roster) do if member.name == 'Member Moon' then return member.rankIndex end end
end
assert(displayedRank() == 3)
click(dropdown)
row = dropdown.popup.rows[1]
click(row)
assert(serverRank == 2 and GD.pendingRosterRank.expected == 2 and commandCount == 1)
assert(not GD:RosterRankMacro('Member Moon', 1), 'prevent another click until confirmed')
poll()
assert(displayedRank() == 2 and not GD.pendingRosterRank, 'refresh actual roster at intermediate rank')
assert(GD.rosterRankTarget.rank == 1 and dropdown.text == 'Continue to Rank 2')
click(dropdown)
assert(serverRank == 1 and commandCount == 2)
poll()
assert(displayedRank() == 1 and not GD.pendingRosterRank and not GD.rosterRankTarget)
assert(dropdown.text == 'Set Guild Rank  v', 'stop at chosen rank and return to dropdown')
-- Officer -> Veteran: one selection updates both the server and displayed rank.
click(dropdown)
row = dropdown.popup.rows[1] -- first demotable rank is Veteran (rank 2)
assert(row.rankValue == 2)
click(row)
poll()
assert(serverRank == 2 and displayedRank() == 2 and not GD.pendingRosterRank)
assert(commandCount == 3 and requests >= 6)
local priorRequests = requests
events.GUILD_ROSTER_UPDATE('GUILD_ROSTER_UPDATE', true)
assert(requests == priorRequests + 1, 'honor native request-roster flag')
-- Unchanged cache data keeps the operation pending until confirmation/timeout.
click(dropdown)
row = dropdown.popup.rows[1]
click(row)
local pending = GD.pendingRosterRank
memberRank = pending.before
GD:RebuildRoster()
assert(GD.pendingRosterRank == pending, 'unchanged cache is not confirmation')
local serverBeforeTimeout = serverRank
C_GuildInfo.GuildRoster = function() requests=requests+1 end
for _, timer in ipairs(timers) do if timer[1] == 10 then timer[2]() end end
assert(not GD.pendingRosterRank and not GD.rosterRankTarget, 'timeout clears continuation')
assert(serverRank == serverBeforeTimeout, 'timers must never issue more rank commands')
print('PASS: one command per click, Member -> Veteran -> Officer with confirmed continuation, Officer -> Veteran, refreshed roster ranks, no overshoot, stable dropdown and stale selection protection')

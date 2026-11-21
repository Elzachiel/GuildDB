-- Run: npm.cmd exec --yes --package=fengari-node-cli -- fengari Tests/RosterRanks.lua
unpack = unpack or table.unpack
local GD = { guildName = 'Test Guild', activeTab = 'Roster' }
local events = {}
function GD:RegisterTab() end
function GD:RegisterEventHandler(event, callback) events[event] = callback end
function GD:Display(value) return tostring(value or '') end
assert(loadfile('UI/Main.lua'))('GuildDB', GD)
local refreshUI = GD.RefreshUI
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
local createdFrames = {}
local function dependsOn(frame, target, visited)
    if frame == target then return true end
    if not frame or (visited and visited[frame]) then return false end
    visited = visited or {}
    visited[frame] = true
    if dependsOn(frame.parent, target, visited) then return true end
    for _, anchor in ipairs(frame.anchors or {}) do
        if dependsOn(anchor, target, visited) then return true end
    end
    return false
end
local function protected(frame)
    for _, candidate in ipairs(createdFrames) do
        if candidate.template and candidate.template:find('Secure', 1, true) and dependsOn(candidate, frame) then return true end
    end
    return false
end
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
function methods:GetObjectType() return 'Button' end
function methods:GetWidth() return 600 end
function methods:GetHeight() return 500 end
function methods:GetText() return self.text or '' end
function methods:GetStringHeight() return 20 end
function methods:GetVerticalScroll() return 0 end
function methods:GetEffectiveScale() return 1 end
function methods:GetLeft() return 100 end
function methods:GetBottom() return 50 end
function methods:GetTop() return 550 end
function methods:ClearAllPoints() self.anchors = {} end
function methods:SetAllPoints(relative) self.anchors = {relative or self.parent} end
function methods:SetPoint(_, relative)
    self.anchors = self.anchors or {}
    self.anchors[#self.anchors + 1] = type(relative) == 'table' and relative or self.parent
end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:HookScript(event, callback) self.hooks[event] = callback end
function methods:SetAttribute(key, value) self.attributes[key] = value end
function methods:SetText(text) self.text = text end
function methods:SetEnabled(value) self.enabled = value end
function methods:SetShown(value) self.shown = value end
function methods:IsShown() return self.shown end
function methods:Show()
    assert(not combat or not protected(self), 'combat cannot show a protected frame or its parent/anchor target')
    self.shown = true
end
function methods:Hide()
    assert(not combat or not protected(self), 'combat cannot hide a protected frame or its parent/anchor target')
    self.shown = false
end
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
UIParent = widget()
RegisterStateDriver = function(frame, state, condition)
    frame.stateDriver = { state = state, condition = condition }
end
CreateFrame = function(_, _, parent, template)
    local frame = widget()
    frame.parent, frame.template = parent, template
    createdFrames[#createdFrames + 1] = frame
    if template and template:find('SecureActionButtonTemplate', 1, true) then frame.scripts.OnClick = secureOnClick end
    return frame
end
function GD:RefreshUI() end
GD:BuildUI()
assert(not protected(GD.frame), 'main window must have no protected parent or anchor dependencies')
-- Reproduce both missed anchor paths from the previous fix, then restore them.
GD.frame.rankLayer:SetAllPoints(GD.frame)
assert(protected(GD.frame), 'test must detect indirect protection through anchors')
GD:PositionRankLayer()
GD.frame.rosterRankDropdown:SetPoint('BOTTOMLEFT', GD.frame.rosterInviteButton, 'TOPLEFT', 0, 8)
assert(protected(GD.frame), 'test must detect secure button anchors into the ordinary window')
GD:PositionRankLayer()
assert(not protected(GD.frame))
assert(GD.frame.rankLayer.parent == UIParent, 'protected rank layer must be outside the main window')
assert(GD.frame.rankLayer.stateDriver.condition == '[combat] 1; 0')
assert(GD.frame.rankLayer.attributes['_onstate-combat']:find('self:Hide()', 1, true))
for _, frame in ipairs(createdFrames) do
    if frame.template and frame.template:find('Secure', 1, true) then
        local parent = frame.parent
        while parent do
            assert(parent ~= GD.frame, 'secure controls must not protect the main window')
            parent = parent.parent
        end
    end
end
combat = true
GD.frame:Hide()
GD.frame.rankLayer.shown = false -- WoW executes the secure combat state snippet.
local popupHide = GD.frame.rosterRankDropdown.popup.Hide
GD.frame.rosterRankDropdown.popup.Hide = function() error('insecure protected hide during combat') end
GD.frame.rosterRankDropdown.scripts.OnHide()
GD.frame.rosterRankDropdown.popup.Hide = popupHide
GD.frame:Show()
GD.frame.hooks.OnShow()
assert(GD.frame.shown and not GD.frame.rankLayer.shown, 'window must open with rank actions hidden in combat')
GD.frame:Hide()
GD.frame.hooks.OnHide()
assert(not GD.frame.shown, 'window can close during combat')
combat = false
GD.frame:Show()
GD.frame.hooks.OnShow()
assert(GD.frame.rankLayer.shown, 'rank layer returns when opened outside combat')
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

-- Exercise the real refresh and tab click handlers during combat. The rank
-- layer is protected even while hidden, so reject all insecure mutations.
function methods:SetShown(value)
    assert(not combat or not protected(self), 'combat must not change protected visibility')
    self.shown = value
end
local styleButton = GD.StyleButton
function GD:StyleButton(button, variant)
    assert(not combat or not protected(button), 'combat must not restyle protected buttons')
    return styleButton(self, button, variant)
end
function GD:GetProfile() return nil end
function GD:CanManage() return true end
function GD:GetAddonVersion() return nil end
function GD:HideSettingsControls() end
local homeRefreshes = 0
function GD:RefreshHome() homeRefreshes = homeRefreshes + 1 end
assert(loadfile('Features/Analytics.lua'))('GuildDB', GD)
GD.tabs = {'Home', 'Roster', 'Analytics', 'Guide'}
GD.views = {
    Home=function() return '' end, Roster=function() return '' end,
    Analytics=function() return '' end, Guide=function() return 'Guild rules' end,
}
GD.RefreshUI = refreshUI
combat = true
GD.frame.rankLayer.shown = false
GD.activeTab = 'Home'
GD:RefreshUI()
assert(homeRefreshes == 1, 'Home must refresh in combat')
for _, tab in ipairs({'Analytics', 'Roster', 'Guide', 'Home', 'Analytics'}) do
    click(GD.frame.tabButtons[tab])
    assert(GD.activeTab == tab and GD.frame.activeTab == tab, 'tab click must render the selected view in combat')
    assert(not GD.frame.rankLayer.shown, 'protected controls must stay hidden')
    if tab == 'Analytics' then assert(GD.frame.analytics.shown)
    else assert(not GD.frame.analytics.shown) end
end
click(GD.frame.analytics.filter)
assert(GD.frame.analytics.onlineOnly, 'Analytics filtering must remain interactive during combat')
GD.frame:Hide()
GD.frame.hooks.OnHide()
GD.frame:Show()
GD.frame.hooks.OnShow()
GD:RefreshUI()
assert(GD.frame.shown and not GD.frame.rankLayer.shown)
combat = false
events.PLAYER_REGEN_ENABLED()
assert(GD.frame.rankLayer.shown, 'protected layer must return after combat')
print('PASS: real combat tab switching, view refresh, Analytics filtering, close/reopen and protected rank isolation')

-- Render and resize the PvP leaderboard with its K/D column.
function GD:CanManagePvPSeason() return false end
function GD:GetPvPSeasons() return {{name='All-time', start=0}} end
local pvpScore = {name='Member Moon', kills=10, points=10, deaths=4, kd=2.5}
function GD:GetPvPLeaderboard() return {name='All-time', start=0}, {pvpScore}, pvpScore, 1 end
GD.activeTab = 'PvP'
GD:RefreshUI()
assert(#GD.frame.pvpHeaders == 6 and GD.frame.pvpHeaders[5].text == 'K/D')
assert(GD.frame.pvpRows[1].kd.text == '2.50', 'leaderboard must display the computed ratio')
assert(GD.frame.pvpRows[1].kills.text == '4', 'deaths must remain visible beside K/D')
assert(GD.frame.pvpSummary.text:find('4 deaths', 1, true) and GD.frame.pvpSummary.text:find('2.50 K/D', 1, true))
GD.frame.detailPanel.hooks.OnSizeChanged(GD.frame.detailPanel)
pvpScore.deaths, pvpScore.kd = 5, 2
GD:RefreshUI()
assert(GD.frame.pvpRows[1].kd.text == '2.00', 'reused rows must refresh the ratio')
assert(not GD.frame.pvpInfo.text:find('5 per day', 1, true), 'remove obsolete kill caps from the UI')
print('PASS: PvP K/D column, personal summary, row reuse, and resize layout')

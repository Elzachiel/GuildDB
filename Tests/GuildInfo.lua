-- Run: npm.cmd exec --yes --package=fengari-node-cli -- fengari Tests/GuildInfo.lua
unpack = unpack or table.unpack
local clock, rank = 1000, 0
local roster = {{'Leader Moon', 'Leader', 0}, {'Member Moon', 'Member', 3}, {'Officer Moon', 'Officer', 1}}
time = function() return clock end
GetTime = function() return clock end
GetGuildInfo = function() return 'Test Guild', 'Rank', rank end
GetUnitName = function() return 'Leader Moon' end
GetNumGuildMembers = function() return #roster end
GetGuildRosterInfo = function(i) return unpack(roster[i]) end
SlashCmdList = {}
C_Timer = {After = function() end}
CreateFrame = function() return {
    RegisterEvent = function() end,
    SetScript = function(self, event, callback) self[event] = callback end,
} end
local function client()
    local gd = {}
    assert(loadfile('Core/Runtime.lua'))('GuildDB', gd)
    assert(loadfile('Features/GuildInfo.lua'))('GuildDB', gd)
    assert(loadfile('Features/Analytics.lua'))('GuildDB', gd)
    gd.eventFrame:OnEvent('ADDON_LOADED', 'GuildDB')
    gd.guildName, gd.bucket = 'Test Guild', {guildInfo = {}}
    function gd:RefreshUI() end
    return gd
end
local function receive(gd, sender, payload)
    gd.eventFrame:OnEvent('CHAT_MSG_ADDON', gd.prefix, 'C|test|1|1|' .. payload, 'GUILD', sender)
end
local function transfer(source, target, sender, history)
    for _, message in ipairs(history and source.historyQueue or source.sendQueue) do
        target.eventFrame:OnEvent('CHAT_MSG_ADDON', target.prefix, message, 'GUILD', sender)
    end
    if history then source.historyQueue = {} else source.sendQueue = {} end
end
local leader, member = client(), client()
assert(leader.tabs[#leader.tabs - 1] == 'Guild Info' and leader.tabs[#leader.tabs] == 'Analytics')
local text = 'Rules\n1. Be kind.\n2. Be on time.\n\nDiscord\nhttps://discord.gg/example\n\nRaid times\nTuesday 8 PM server time'
assert(leader:SetGuildInfoText(text))
transfer(leader, member, 'Leader Moon')
assert(member:GetGuildInfoText() == text, 'live sync preserves paragraphs and Discord URLs')
local previousRevision = leader.bucket.guildInfo.ts
assert(leader:SetGuildInfoText(text .. '\nBring consumables.'))
assert(leader.bucket.guildInfo.ts > previousRevision, 'rapid saves advance revisions')
transfer(leader, member, 'Leader Moon')
receive(member, 'Leader Moon', 'GI|info|1000|Leader Moon|stale')
assert(member:GetGuildInfoText():find('Bring consumables.', 1, true), 'ignore stale records')
receive(member, 'Member Moon', 'GI|info|2000|Member Moon|forged')
receive(member, 'Outsider', 'GI|info|2000|Leader Moon|forged')
assert(member:GetGuildInfoText() ~= 'forged', 'reject member authors and non-guild senders')
rank = 3
assert(not member:SetGuildInfoText('unauthorized'), 'members cannot edit locally')
rank = 0

-- Existing members can relay officer-authored info to a fresh installation.
local newcomer = client()
receive(member, 'Officer Moon', 'R|history|Leader Moon')
transfer(member, newcomer, 'Member Moon', true)
assert(newcomer:GetGuildInfoText() == member:GetGuildInfoText(), 'history relays retain officer attribution')

-- Worst-case escaped text must survive chunking and the larger record limit.
local longText = string.rep('%', 3000)
assert(leader:SetGuildInfoText(longText))
assert(#leader.sendQueue > 20 and #leader.sendQueue <= 60)
transfer(leader, member, 'Leader Moon')
assert(member:GetGuildInfoText() == longText, 'large Guild Info survives encoding and reassembly')
assert(not leader:SetGuildInfoText(longText .. '!'), 'reject oversized info without truncation')
local receivedOther = false
member:RegisterRecordHandler('TEST', function() receivedOther = true end)
member.eventFrame:OnEvent('CHAT_MSG_ADDON', member.prefix, 'C|limit|1|1|TEST|id|2000|Leader Moon|' .. string.rep('a', 1201), 'GUILD', 'Leader Moon')
assert(not receivedOther, 'other record types retain their existing size limit')
assert(leader:SetGuildInfoText(''))
transfer(leader, member, 'Leader Moon')
assert(member:GetGuildInfoText() == '', 'clearing info syncs too')

local savedRoster = roster
roster = {}
receive(newcomer, 'Member Moon', 'GI|info|3000|Leader Moon|Wait for ranks')
assert(newcomer:GetGuildInfoText() ~= 'Wait for ranks')
roster = savedRoster
newcomer.eventHandlers.GUILD_ROSTER_UPDATE[1]()
assert(newcomer:GetGuildInfoText() == 'Wait for ranks', 'apply early history once ranks load')
roster = {}
receive(newcomer, 'Member Moon', 'GI|info|3001|Leader Moon|Wrong guild')
newcomer.bucket = {guildInfo = {}}
roster = savedRoster
newcomer.eventHandlers.GUILD_ROSTER_UPDATE[1]()
assert(newcomer:GetGuildInfoText() == '', 'deferred records cannot cross guild buckets')

-- Exercise the actual full-page editor and its save/cancel/permission handling.
local methods = {}
local function widget()
    return setmetatable({shown = true, width = 800, height = 400, text = '', scripts = {}}, {__index = function(_, name)
        return methods[name] or (name:match('^%u') and function() end)
    end})
end
function methods:CreateFontString() return widget() end
function methods:CreateTexture() return widget() end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:GetWidth() return self.width end
function methods:SetHeight(h) self.height = h end
function methods:GetHeight() return self.height end
function methods:SetText(value)
    self.text = value
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
end
function methods:GetText() return self.text end
function methods:GetNumLines() local _, count = self.text:gsub('\n', '') return count + 1 end
function methods:GetStringHeight() return self:GetNumLines() * 20 end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value end
function methods:GetVerticalScroll() return rawget(self, 'scroll') or 0 end
function methods:SetVerticalScroll(value) self.scroll = value end
function methods:SetFocus() self.focused = true end
function methods:ClearFocus() self.focused = false end
CreateFrame = function() return widget() end
local ui = leader
ui.frame = {detailPanel = widget(), detailScroll = widget(), detailTitle = widget(), detailMeta = widget(), detailRule = widget(), footer = widget()}
function ui:StyleButton() end
function ui:StyleEditBox() end
function ui:GetAppearanceColors() return {alternate = {0, 0, 0, 1}, accent = {1, 1, 0}, text = {1, 1, 1}, muted = {.5, .5, .5}} end
function ui:RefreshUI() self:RefreshGuildInfo() end
ui:RefreshUI()
local panel = ui.frame.guildInfo
assert(panel.edit.shown and not panel.input.shown and not ui.frame.detailScroll.shown)
panel.edit.scripts.OnClick()
assert(panel.input.shown and panel.save.shown and panel.cancel.shown and not panel.text.shown)
panel.input:SetText(text)
ui:RefreshUI()
assert(panel.input:GetText() == text, 'background refreshes preserve unsaved edits')
panel.cancel.scripts.OnClick()
assert(ui:GetGuildInfoText() == '' and not panel.input.shown, 'Cancel discards changes')
panel.edit.scripts.OnClick()
panel.input:SetText(text)
panel.save.scripts.OnClick()
assert(ui:GetGuildInfoText() == text and panel.text.text == text and not panel.input.shown)
panel.edit.scripts.OnClick()
rank = 3
ui:RefreshUI()
assert(not panel.edit.shown and not panel.input.shown and panel.text.shown, 'demotion exits editing')
panel.edit.scripts.OnClick()
assert(not panel.input.shown, 'edit action enforces rank too')
rank = 0
panel.edit.scripts.OnClick()
panel.input:SetText('Draft for old guild')
ui.bucket = {guildInfo = {text = 'New guild info'}}
panel.save.scripts.OnClick()
assert(ui:GetGuildInfoText() == 'New guild info', 'old drafts cannot save into another guild')
ui:RefreshUI()
assert(not panel.input.shown and panel.text.text == 'New guild info')
ui.bucket = nil
ui:RefreshUI()
assert(not panel.edit.shown and panel.text.text:find('Join a guild', 1, true))
print('PASS: Guild Info tab order, officer edits, live/history sync, long text, permissions, revisions, and editor save/cancel')

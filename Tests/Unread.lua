-- Run: npm.cmd exec --yes --package=fengari-node-cli -- fengari Tests/Unread.lua
local clock, player, shown = 100000, 'Member Moon', false
time = function() return clock end
GetTime = time
GetUnitName = function() return player end
UnitName = GetUnitName
GetGuildInfo = function() return 'Test Guild', 'Officer', 1 end
GetNumGuildMembers = function() return 1 end
GetGuildRosterInfo = function() return 'Officer Moon', 'Officer', 1 end
SlashCmdList = {}
CreateFrame = function() return {RegisterEvent = function() end, SetScript = function() end} end

local function client(bucket)
    local gd = {}
    for _, path in ipairs({'Core/Runtime.lua', 'Features/Events.lua', 'Features/Polls.lua',
        'Features/GuildInfo.lua', 'Features/Unread.lua'}) do
        assert(loadfile(path))('GuildDB', gd)
    end
    gd.bucket, gd.guildName = bucket or {}, 'Test Guild'
    for key, factory in pairs(gd.bucketDefaults) do
        gd.bucket[key] = gd.bucket[key] or factory()
    end
    gd.frame = {IsShown = function() return shown end}
    function gd:RefreshUI() self:UpdateUnreadState(self.activeTab) end
    return gd
end

local gd = client()
for _, tab in ipairs({'Events', 'Guild Info', 'Polls', 'Roster'}) do
    assert(gd:GetTabUnreadCount(tab) == 0, 'empty sections have no badge')
end

-- Real feature handlers refresh while hidden; this must not consume receipts.
gd.activeTab = 'Guild Info'
gd.recordHandlers.GI('info', clock, 'Officer Moon', 'Read the rules', 'Officer Moon')
assert(gd:GetTabUnreadCount('Guild Info') == 1, 'hidden active tab stays unread')
shown = true
gd:RefreshUI()
assert(gd:GetTabUnreadCount('Guild Info') == 0, 'opening section clears badge')
gd.recordHandlers.GI('info', clock + 1, 'Officer Moon', 'Updated rules', 'Officer Moon')
assert(gd:GetTabUnreadCount('Guild Info') == 0, 'visible updates count as read')
gd.activeTab = 'Home'
gd.recordHandlers.GI('info', clock + 2, 'Officer Moon', '', 'Officer Moon')
assert(gd:GetTabUnreadCount('Guild Info') == 1, 'clearing page is an unread revision')
gd:UpdateUnreadState('Guild Info')
gd.recordHandlers.GI('info', clock + 2, 'Officer Moon', '', 'Officer Moon')
assert(gd:GetTabUnreadCount('Guild Info') == 0, 'duplicate history does not reopen badge')

gd.recordHandlers.D('raid', clock, 'Officer Moon', (clock + 100) .. '\nRaid night\nBring potions', 'Officer Moon')
assert(gd:GetTabUnreadCount('Events') == 1, 'new raid is unread')
gd:UpdateUnreadState('Events')
gd.bucket.events[1].rsvps[player] = {status = 'going', ts = clock + 1}
gd.bucket.events[1].selections = {[player] = {selected = true, ts = clock + 1}}
assert(gd:GetTabUnreadCount('Events') == 0, 'signups and selections do not trigger badges')
gd.recordHandlers.D('raid', clock + 1, 'Officer Moon', (clock + 200) .. '\nChanged raid\nNew time', 'Officer Moon')
assert(gd:GetTabUnreadCount('Events') == 1, 'raid edit is unread even in the same second')
gd.recordHandlers.D('raid', clock, 'Officer Moon', (clock + 100) .. '\nOld raid\nStale', 'Officer Moon')
assert(gd:GetTabUnreadCount('Events') == 1, 'stale sync does not replace latest revision')
clock = clock + 200 + 6 * 3600 + 1
assert(gd:GetTabUnreadCount('Events') == 0, 'events disappear when they leave Raid Info')
gd.raidPreviewEvent = {id = 'preview', preview = true, at = clock + 100}
assert(gd:GetTabUnreadCount('Events') == 0, 'local layout previews are excluded')

gd.recordHandlers.O('poll', clock, 'Officer Moon', 'Raid day?\nTuesday\nThursday')
assert(gd:GetTabUnreadCount('Polls') == 1, 'new poll is unread')
gd:UpdateUnreadState('Polls')
gd.recordHandlers.V('poll', clock + 1, player, '1')
assert(gd:GetTabUnreadCount('Polls') == 0, 'votes do not trigger badges')
gd.recordHandlers.OC('poll', clock + 2, 'Officer Moon')
assert(gd:GetTabUnreadCount('Polls') == 1, 'poll closure marks results unread')
gd:UpdateUnreadState('Polls')
gd.recordHandlers.O('poll', clock, 'Officer Moon', 'Raid day?\nTuesday\nThursday')
gd.recordHandlers.OC('poll', clock + 2, 'Officer Moon')
assert(gd:GetTabUnreadCount('Polls') == 0, 'history replay stays read')

local saved = gd.bucket
gd = client(saved)
assert(gd:GetTabUnreadCount('Polls') == 0, 'receipts survive reloading addon')
player = 'Alt Moon'
assert(gd:GetTabUnreadCount('Polls') == 1, 'alts have independent receipts')
gd:UpdateUnreadState('Polls')
player = 'Member Moon'
assert(gd:GetTabUnreadCount('Polls') == 0, 'alt visits preserve main receipts')
gd.bucket = {polls = saved.polls}
assert(gd:GetTabUnreadCount('Polls') == 1, 'guilds have independent receipts')
gd.bucket = saved
gd.recordHandlers.O('deleted', clock, 'Officer Moon', 'Delete me?\nYes\nNo')
assert(gd:GetTabUnreadCount('Polls') == 1)
gd.recordHandlers.OD('deleted', clock + 1, 'Officer Moon')
assert(gd:GetTabUnreadCount('Polls') == 0, 'deleted polls leave no badge')
gd.bucket = nil
assert(gd:GetTabUnreadCount('Polls') == 0, 'guildless characters have no badges')
gd:UpdateUnreadState('Polls')
assert(loadfile('UI/Main.lua'), 'UI changes compile')
print('PASS: unread revisions, visible/hidden sections, replay, expiry, votes, closure, deletion, reload, character and guild isolation')

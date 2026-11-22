-- Run: npm.cmd exec --yes --package=fengari-node-cli -- fengari Tests/Polls.lua
unpack = unpack or table.unpack
local rank, clock = 0, 1000
time = function() return clock end
GetGuildInfo = function() return 'Test Guild', 'Leader', rank end
UnitName = function() return 'Player Moon' end
GetUnitName = UnitName
SlashCmdList = {}
CreateFrame = function() return {RegisterEvent = function() end, SetScript = function() end} end
local GD = {}
assert(loadfile('Core/Runtime.lua'))('GuildDB', GD)
assert(loadfile('Features/Polls.lua'))('GuildDB', GD)
assert(loadfile('UI/Main.lua')) -- compile the integration into the main window
GD.bucket, GD.guildName = {polls = {}}, 'Test Guild'
function GD:RefreshUI() end
assert(GD:CreatePoll('Which raid night?', {'Tuesday', 'Wednesday', 'Thursday', 'Friday'}))
local poll = GD.bucket.polls[1]
poll.votes = {A = {choice = 1, ts = 900}, B = {choice = 1, ts = 900}, C = 2, Bad = {choice = 9, ts = 900}}
local counts, total = GD:GetPollResults(poll)
assert(total == 3 and counts[1] == 2 and counts[2] == 1 and counts[3] == 0 and counts[4] == 0)

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
function methods:SetText(text) self.text = text end
function methods:GetStringHeight() return math.max(14, math.ceil(#self.text / math.max(1, self.width / 7)) * 14) end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:ClearAllPoints() self.points = {} end
function methods:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = {...} end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value end
function methods:SetEnabled(value) self.enabled = value end
function methods:IsEnabled() return self.enabled end
function methods:IsMouseOver() return false end
function methods:SetColorTexture(...) self.color = {...} end
function methods:SetVertexColor(...) self.color = {...} end
function methods:GetVertexColor() return unpack(self.color) end
function methods:GetNormalTexture() return self.normalTexture end
function methods:GetPushedTexture() return self.pushedTexture end
function methods:GetHighlightTexture() return self.highlightTexture end
function methods:GetDisabledTexture() return self.disabledTexture end
function methods:GetFontString() return self.fontString end
CreateFrame = function() return widget() end
function GD:StyleButton(button, variant)
    button.styleVariant = variant
    button.normalTexture = rawget(button, 'normalTexture') or widget()
    button.pushedTexture = rawget(button, 'pushedTexture') or widget()
    button.highlightTexture = rawget(button, 'highlightTexture') or widget()
    button.disabledTexture = rawget(button, 'disabledTexture') or widget()
    button.fontString = rawget(button, 'fontString') or widget()
    button.GuildDBBorder = rawget(button, 'GuildDBBorder') or {widget(), widget(), widget(), widget()}
    button.normalTexture:SetVertexColor(variant == 'primary' and 0.42 or 0.08, 0.2, 0.3, 1)
    button.disabledTexture:SetVertexColor(0.08, 0.09, 0.11, 0.65)
end
function GD:GetAppearanceColors() return {alternate = {0, 0, 0, 1}, accent = {1, .8, .2}, muted = {.5, .5, .5}, text = {1, 1, 1}} end
local frame = {detailChild = widget(), detailScroll = widget()}
function GD:RefreshUI() self:RefreshPollCards(frame) end
GD:RefreshUI()
local card = frame.pollCards[1]
assert(#card.options == 4, 'render and allow voting for all four options')
assert(card.title.text == 'Which raid night?' and card.meta.text:find('3 votes', 1, true))
assert(card.options[1].count.text == '2 (67%)')
assert(card.options[2].count.text == '1 (33%)')
assert(not card.options[3].fill.shown and card.options[3].count.text == '0 (0%)')
assert(card.options[1].fill.height == card.options[1].track.height)
assert(math.abs(card.options[1].fill.width / card.options[1].track.width - 2 / 3) < 0.00001, 'horizontal length represents vote share')
assert(card.options[1].fill.width == card.options[2].fill.width * 2)
assert(card.options[2].points[1][3] < card.options[1].points[1][3], 'options stack vertically')
assert(card.options[1].vote.points[1][1] == 'BOTTOMLEFT', 'vote button sits beneath its horizontal bar')
assert(card.options[1].fill.points[1][3] > card.options[1].vote.points[1][3], 'bar sits above the vote button')
assert(card.options[1].fill.color[3] == 1 and card.options[2].fill.color[1] == 1, 'use vibrant distinct option colors')
assert(card.options[1].vote.styleVariant == 'secondary', 'unselected votes use normal addon buttons')
local firstWidth = card.options[1].track.width
frame.detailChild:SetWidth(600)
GD:RefreshUI()
assert(frame.pollCards[1] == card and card.options[1].track.width < firstWidth, 'reuse and resize the poll card')
card.options[4].vote.scripts.OnClick()
assert(poll.votes['Player Moon'].choice == 4 and card.options[4].label.text == 'Friday (your vote)')
assert(card.options[4].count.text == '1 (25%)')
assert(card.options[4].vote.text == 'Voted' and not card.options[4].vote.enabled)
assert(card.options[4].vote.styleVariant == 'primary', 'only the selected vote uses the lit addon style')
assert(card.options[4].vote.disabledTexture.color[1] == card.options[4].vote.normalTexture.color[1]
    and card.options[4].vote.disabledTexture.color[4] == 1, 'selected disabled vote retains the standard primary fill')
card.options[1].vote.scripts.OnClick()
counts, total = GD:GetPollResults(poll)
assert(total == 4 and counts[1] == 3 and counts[4] == 0, 'changing a vote moves the bar without adding a voter')
assert(not card.options[4].fill.shown and card.options[1].label.text:find('your vote', 1, true))
assert(card.options[4].vote.disabledTexture.color[4] == 0.65, 'changing votes restores the previous button styling')
assert(card.options[4].vote.styleVariant == 'secondary', 'a previous selection returns to the normal addon style')

rank = 3
GD:RefreshUI()
assert(not card.close.shown and card.options[2].vote.enabled, 'members can vote but cannot close a poll')
rank = 0
GD:RefreshUI()
assert(card.close.shown)
card.close.scripts.OnClick(card.close)
assert(poll.closed and card.meta.text:find('Closed', 1, true))
for _, option in ipairs(card.options) do assert(not option.vote.enabled) end
card.options[2].vote.scripts.OnClick()
assert(poll.votes['Player Moon'].choice == 1, 'closed poll results stay fixed')
assert(not card.close.shown)

clock = 1001
assert(GD:CreatePoll('A second poll', {'Yes', 'No'}))
assert(#frame.pollCards == 2 and frame.pollCards[1].title.text == 'A second poll')
local emptyCard = frame.pollCards[1]
assert(emptyCard.meta.text:find('0 votes', 1, true))
assert(not emptyCard.options[1].fill.shown and not emptyCard.options[3].shown)

-- Multiple open polls must have independent identities and card controls.
local second = GD.bucket.polls[1]
assert(GD:CreatePoll('A third poll', {'A', 'B'}))
local third = GD.bucket.polls[1]
assert(second.id ~= third.id)
frame.pollCards[2].close.scripts.OnClick(frame.pollCards[2].close)
assert(second.closed and not third.closed, 'closing one card must leave the other open poll untouched')
assert(frame.pollCards[1].options[1].vote.enabled, 'other poll voting remains available')
assert(frame.pollCards[2].delete.shown, 'closed polls can still be deleted')
rank = 3
GD:RefreshUI()
assert(not frame.pollCards[1].delete.shown and not GD:DeletePoll(third.id), 'members cannot delete polls')
rank = 1
GD:RefreshUI()
frame.pollCards[2].delete.scripts.OnClick(frame.pollCards[2].delete)
assert(#GD.bucket.polls == 2 and GD.bucket.polls[1] == third and not third.closed, 'deleting a closed poll preserves the others')
local savedThirdId = third.id
frame.pollCards[1].delete.scripts.OnClick(frame.pollCards[1].delete)
assert(#GD.bucket.polls == 1 and GD.bucket.pollDeletes[savedThirdId], 'rank 1 can delete an open poll')

-- Same-second/random creations must not share an ID.
rank = 0
local originalRandom = math.random
math.random = function() return 123456 end
assert(GD:CreatePoll('First rapid poll', {'Yes', 'No'}))
local rapid = GD.bucket.polls[1]
assert(GD:CreatePoll('Second rapid poll', {'Yes', 'No'}))
assert(GD.bucket.polls[1].id ~= rapid.id, 'rapid creations remain distinct even with identical random values')
math.random = originalRandom

-- Delayed history must not reopen closed polls or resurrect deleted ones.
GetNumGuildMembers = function() return 2 end
GetGuildRosterInfo = function(index)
    if index == 1 then return 'Player Moon', 'Leader', 0 end
    return 'Member Moon', 'Member', 3
end
GD.recordHandlers.OD('remote-delete', 2000, 'Member Moon')
assert(not GD.bucket.pollDeletes['remote-delete'], 'reject member-authored deletions')
GD.recordHandlers.OD('remote-delete', 2000, 'Player Moon')
GD.recordHandlers.O('remote-delete', 1999, 'Player Moon', 'Stale deleted poll\nYes\nNo')
assert(GD.bucket.polls[1].id ~= 'remote-delete', 'deletion received before poll history prevents resurrection')
GD.recordHandlers.OC('remote-close', 2000, 'Player Moon')
GD.recordHandlers.O('remote-close', 1999, 'Player Moon', 'Closed elsewhere\nYes\nNo')
assert(GD.bucket.polls[1].id == 'remote-close' and GD.bucket.polls[1].closed, 'close received before history stays closed')
GD.sendQueue = {}
for _, provider in ipairs(GD.historyProviders) do provider.handler() end
local peer = {}
assert(loadfile('Core/Runtime.lua'))('GuildDB', peer)
assert(loadfile('Features/Polls.lua'))('GuildDB', peer)
peer.bucket, peer.guildName = {polls = {}}, 'Test Guild'
for index = #GD.sendQueue, 1, -1 do
    local payload = GD.sendQueue[index]:match('^C|[^|]+|1|1|(.*)$')
    if payload then
        local kind, id, ts, author, content = payload:match('^([^|]+)|([^|]+)|([^|]+)|([^|]+)|(.*)$')
        if peer.recordHandlers[kind] then peer.recordHandlers[kind](peer:Decode(id), tonumber(ts), peer:Decode(author), peer:Decode(content)) end
    end
end
assert(peer.bucket.pollDeletes[savedThirdId], 'history sync shares poll deletions')
local remotelyClosed = false
for _, value in ipairs(peer.bucket.polls) do if value.id == 'remote-close' then remotelyClosed = value.closed end end
assert(remotelyClosed, 'reverse-order history keeps the intended poll closed')
GD.bucket.polls = {}
GD:RefreshUI()
assert(frame.pollEmpty.shown and not frame.pollCards[1].shown and not frame.pollCards[2].shown)
GD.bucket = nil
GD:RefreshUI()
assert(frame.pollEmpty.text:find('Join a guild', 1, true))
print('PASS: poll graphs, independent close/delete controls, unique rapid IDs, officer permissions, deletion sync, reordered history, vote changes and resizing')

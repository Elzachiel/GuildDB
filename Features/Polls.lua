-- Officer polls with one replaceable vote per guild member.
local _, GD = ...
GD:RegisterBucket("polls", function() return {} end)
GD:RegisterBucket("pollDeletes", function() return {} end)
GD:RegisterBucket("pollClosures", function() return {} end)
local pollSequence = 0

local function findPoll(id)
    if not GD.bucket or type(id) ~= "string" or id == "" then return end
    for index, poll in ipairs(GD.bucket.polls or {}) do if poll.id == id then return poll, index end end
end

local function openPolls()
    local result = {}
    for _, poll in ipairs((GD.bucket and GD.bucket.polls) or {}) do if not poll.closed then result[#result + 1] = poll end end
    return result
end
GD.GetOpenPolls = openPolls

function GD:GetPollResults(poll)
    local counts, total = {}, 0
    for index = 1, #poll.options do counts[index] = 0 end
    for _, vote in pairs(poll.votes or {}) do
        local choice = type(vote) == "table" and vote.choice or vote
        if counts[choice] then counts[choice], total = counts[choice] + 1, total + 1 end
    end
    return counts, total
end

-- One card per poll, with horizontal bars and Vote buttons below each bar.
function GD:RefreshPollCards(frame)
    frame.pollCards = frame.pollCards or {}
    local polls = self.bucket and self.bucket.polls or {}
    local colors = self:GetAppearanceColors()
    local width, y = math.max(180, frame.detailChild:GetWidth() - 8), 4
    local voter = UnitName and UnitName("player") or "Guild member"
    for index, poll in ipairs(polls) do
        local card = frame.pollCards[index]
        if not card then
            card = CreateFrame("Frame", nil, frame.detailChild, "BackdropTemplate")
            card:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1})
            card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            card.title:SetPoint("TOPLEFT", 12, -12)
            card.title:SetJustifyH("LEFT")
            card.title:SetWordWrap(true)
            card.meta = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            card.meta:SetJustifyH("LEFT")
            card.close = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
            card.close:SetPoint("TOPRIGHT", -12, -10)
            card.close:SetSize(68, 24)
            card.close:SetText("Close")
            card.delete = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
            card.delete:SetPoint("TOPRIGHT", -12, -10)
            card.delete:SetSize(68, 24)
            card.delete:SetText("Delete")
            card.options = {}
            frame.pollCards[index] = card
        end
        local pollId = poll.id
        local counts, total = self:GetPollResults(poll)
        local mine = poll.votes and poll.votes[voter]
        local selected = type(mine) == "table" and mine.choice or mine
        local canClose = not poll.closed and self:CanManage()
        local canDelete = self:CanManage()
        card.close.pollId, card.delete.pollId = pollId, pollId
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", 4, -y)
        card:SetWidth(width)
        card:SetBackdropColor(unpack(colors.alternate))
        card:SetBackdropBorderColor(colors.accent[1] * 0.4, colors.accent[2] * 0.4, colors.accent[3] * 0.4, 1)
        card.title:SetWidth(math.max(80, width - (canClose and 184 or canDelete and 106 or 24)))
        card.title:SetText(self:Display(poll.question))
        card.title:SetTextColor(unpack(colors.accent))
        local titleHeight = math.max(16, card.title:GetStringHeight())
        card.meta:ClearAllPoints()
        card.meta:SetPoint("TOPLEFT", 12, -20 - titleHeight)
        card.meta:SetWidth(width - 24)
        card.meta:SetText((poll.closed and "Closed" or "Open") .. "  -  " .. total ..
            (total == 1 and " vote" or " votes") .. (not poll.closed and "  -  Use Vote below an option" or ""))
        card.meta:SetTextColor(unpack(colors.muted))
        self:StyleButton(card.close)
        card.close:ClearAllPoints()
        card.close:SetPoint("TOPRIGHT", -88, -10)
        card.close:SetShown(canClose)
        card.close:SetScript("OnClick", function(button)
            local id = button.pollId
            self:ConfirmAction("Close poll?", "Stop accepting votes for: " .. self:Display(poll.question) .. "\nExisting results will be kept.",
                function() return self:ClosePoll(id) end, "Close poll")
        end)
        self:StyleButton(card.delete)
        card.delete:SetShown(canDelete)
        card.delete:SetScript("OnClick", function(button)
            local id = button.pollId
            self:ConfirmAction("Delete poll?", "Permanently delete this poll and all its votes: " .. self:Display(poll.question),
                function() return self:DeletePoll(id) end, "Delete")
        end)
        local offset = titleHeight + 44
        local barWidth = width - 24
        local palette = {{0.05, 0.75, 1}, {1, 0.18, 0.38}, {0.2, 1, 0.45}, {0.8, 0.25, 1}}
        for optionIndex, option in ipairs(poll.options) do
            local row = card.options[optionIndex]
            if not row then
                row = CreateFrame("Frame", nil, card)
                row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.label:SetJustifyH("LEFT")
                row.label:SetWordWrap(true)
                row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.count:SetJustifyH("RIGHT")
                row.track = row:CreateTexture(nil, "BACKGROUND")
                row.fill = row:CreateTexture(nil, "ARTWORK")
                -- Use only GuildDB's flat theme, without the game template's
                -- extra button artwork showing through in different states.
                row.vote = CreateFrame("Button", nil, row)
                local voteText = row.vote:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                voteText:SetPoint("CENTER")
                row.vote:SetFontString(voteText)
                row.vote:SetNormalFontObject("GameFontHighlightSmall")
                row.vote:SetHighlightFontObject("GameFontHighlightSmall")
                row.vote:SetPoint("BOTTOMLEFT", 0, 0)
                card.options[optionIndex] = row
            end
            local choice = optionIndex
            local fraction = total > 0 and counts[choice] / total or 0
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 12, -offset)
            row:SetWidth(barWidth)
            row.label:ClearAllPoints()
            row.label:SetPoint("TOPLEFT", 0, 0)
            row.label:SetWidth(math.max(60, barWidth - 116))
            row.label:SetText(self:Display(option) .. (selected == choice and " (your vote)" or ""))
            row.label:SetTextColor(unpack(selected == choice and colors.accent or colors.text))
            local labelHeight = math.max(14, row.label:GetStringHeight())
            row.count:ClearAllPoints()
            row.count:SetPoint("TOPRIGHT", 0, 0)
            row.count:SetWidth(108)
            row.count:SetText(counts[choice] .. (" (%d%%)"):format(math.floor(fraction * 100 + 0.5)))
            row.count:SetTextColor(unpack(colors.text))
            row:SetHeight(labelHeight + 60)
            row.track:ClearAllPoints()
            row.track:SetPoint("BOTTOMLEFT", 0, 34)
            row.track:SetSize(barWidth, 18)
            row.track:SetColorTexture(colors.muted[1], colors.muted[2], colors.muted[3], 0.15)
            row.fill:ClearAllPoints()
            row.fill:SetPoint("BOTTOMLEFT", 0, 34)
            row.fill:SetSize(math.max(1, barWidth * fraction), 18)
            local color = palette[choice]
            row.fill:SetColorTexture(color[1], color[2], color[3], 1)
            row.fill:SetShown(counts[choice] > 0)
            row.vote:SetSize(90, 24)
            row.vote:SetText(selected == choice and "Voted" or "Vote")
            row.vote:SetEnabled(not poll.closed and selected ~= choice)
            self:StyleButton(row.vote, selected == choice and "primary" or "secondary")
            row.vote:SetDisabledFontObject(selected == choice and "GameFontHighlightSmall" or "GameFontDisableSmall")
            if selected == choice then
                -- Keep the shared primary appearance while preventing repeat
                -- clicks; the default disabled texture otherwise darkens it.
                local normal, disabled = row.vote:GetNormalTexture(), row.vote:GetDisabledTexture()
                if normal and disabled then disabled:SetVertexColor(normal:GetVertexColor()) end
            end
            row.vote:SetScript("OnClick", function() self:VotePoll(pollId, choice) end)
            row:Show()
            offset = offset + row:GetHeight() + 12
        end
        for optionIndex = #poll.options + 1, #card.options do card.options[optionIndex]:Hide() end
        card:SetHeight(offset + 8)
        card:Show()
        y = y + card:GetHeight() + 12
    end
    for index = #polls + 1, #frame.pollCards do frame.pollCards[index]:Hide() end
    frame.pollEmpty = frame.pollEmpty or frame.detailChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.pollEmpty:SetPoint("TOPLEFT", 12, -14)
    frame.pollEmpty:SetText(self.bucket and "No polls have been created." or "Join a guild to see guild polls.")
    frame.pollEmpty:SetTextColor(unpack(colors.text))
    frame.pollEmpty:SetShown(#polls == 0)
    frame.detailChild:SetHeight(math.max(frame.detailScroll:GetHeight(), y + 8))
end

local function pollPayload(poll)
    return poll.question .. "\n" .. table.concat(poll.options, "\n")
end

local function closePoll(poll, closer, ts, send)
    poll.closed, poll.closedAt, poll.closedBy = true, ts, closer
    if send then GD:SendRecord("OC", poll.id, ts, closer, "closed") end
    if GD.RefreshUI then GD:RefreshUI() end
end

local function rememberClosure(id, ts, closer)
    GD.bucket.pollClosures = GD.bucket.pollClosures or {}
    local previous = GD.bucket.pollClosures[id]
    if not previous or previous.ts < ts then GD.bucket.pollClosures[id] = {ts = ts, by = closer} end
end

local function deletePoll(id, ts, author)
    if not GD.bucket or not id or id == "" then return end
    GD.bucket.pollDeletes = GD.bucket.pollDeletes or {}
    local previous = GD.bucket.pollDeletes[id]
    if not previous or previous.ts < ts then GD.bucket.pollDeletes[id] = {ts = ts, by = author} end
    local _, index = findPoll(id)
    if index then table.remove(GD.bucket.polls, index) end
    if GD.bucket.pollClosures then GD.bucket.pollClosures[id] = nil end
    if GD.RefreshUI then GD:RefreshUI() end
end

local pendingControls = {}
local function receiveControl(kind, id, ts, author)
    if not GD.bucket then return end
    if not GetNumGuildMembers or not GetGuildRosterInfo or GetNumGuildMembers(true) == 0 then
        if #pendingControls < 60 then pendingControls[#pendingControls + 1] = {
            kind = kind, id = id, ts = ts, author = author, bucket = GD.bucket,
        } end
        return
    end
    local function nameKey(name)
        return (tostring(name or ""):match("^([^-]+)") or ""):lower():gsub("%s", "")
    end
    local officer = false
    for index = 1, GetNumGuildMembers(true) do
        local name, _, rank = GetGuildRosterInfo(index)
        if nameKey(name) == nameKey(author) then officer = tonumber(rank) ~= nil and tonumber(rank) <= 1; break end
    end
    if not officer then return end
    if kind == "OD" then deletePoll(id, ts, author); return end
    if (GD.bucket.pollDeletes or {})[id] then return end
    rememberClosure(id, ts, author)
    local poll = findPoll(id)
    if poll and (not poll.closedAt or poll.closedAt < ts) then closePoll(poll, author, ts, false) end
end
GD:RegisterEventHandler("GUILD_ROSTER_UPDATE", function()
    if not GetNumGuildMembers or GetNumGuildMembers(true) == 0 then return end
    local controls = pendingControls
    pendingControls = {}
    for _, record in ipairs(controls) do
        if record.bucket == GD.bucket then receiveControl(record.kind, record.id, record.ts, record.author) end
    end
end)

function GD:CreatePoll(question, options)
    if not self:CanManage() then return false, "Only officers can create polls." end
    question = tostring(question or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cleanOptions = {}
    for _, option in ipairs(options or {}) do
        option = tostring(option or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if option ~= "" then cleanOptions[#cleanOptions + 1] = option:sub(1, 60) end
    end
    if question == "" or #question > 120 or #cleanOptions < 2 or #cleanOptions > 4 then
        return false, "Add a question and between 2 and 4 options."
    end
    local poll = self:NewRecord({ question = question, options = cleanOptions, votes = {}, closed = false })
    -- Include the author and a local sequence so rapid creations and separate
    -- officers cannot accidentally share a timestamp/random identifier.
    pollSequence = pollSequence + 1
    poll.id = poll.id .. "-" .. tostring(poll.by):gsub("[%c|]", ""):sub(1, 32) .. "-" .. pollSequence
    self:StoreRecord("polls", poll, "O", pollPayload(poll))
    return true, "Poll created."
end

function GD:VotePoll(id, choice)
    local poll, voter = findPoll(id), UnitName and UnitName("player") or "Guild member"
    choice = tonumber(choice)
    if not poll or poll.closed or not choice or not poll.options[choice] then return false, "That poll or option is unavailable." end
    local ts = time()
    poll.votes[voter] = { choice = choice, ts = ts }
    self:SendRecord("V", poll.id, ts, voter, choice)
    if self.RefreshUI then self:RefreshUI() end
    return true, "Vote recorded."
end

function GD:ClosePoll(id)
    if not self:CanManage() then return false, "Only officers can close polls." end
    local poll = findPoll(id)
    if not poll or poll.closed then return false, "That poll is already closed or unavailable." end
    local closer, ts = self:PlayerName(), math.max(time(), poll.ts or 0)
    rememberClosure(id, ts, closer)
    closePoll(poll, closer, ts, true)
    return true, "Poll closed."
end

function GD:DeletePoll(id)
    if not self:CanManage() then return false, "Only officers can delete polls." end
    local poll = findPoll(id)
    if not poll then return false, "That poll is unavailable." end
    local ts, author = math.max(time(), poll.ts or 0), self:PlayerName()
    deletePoll(id, ts, author)
    self:SendRecord("OD", id, ts, author, "deleted")
    return true, "Poll deleted and shared with the guild."
end

GD:RegisterRecordHandler("O", function(id, ts, author, content)
    if not GD.bucket or (GD.bucket.pollDeletes or {})[id] then return end
    local question, optionText = content:match("^(.-)\n(.*)$")
    if not question or #question > 120 then return end
    local options = {}
    for option in optionText:gmatch("([^\n]+)") do
        option = option:gsub("^%s+", ""):gsub("%s+$", "")
        if option ~= "" then options[#options + 1] = option end
    end
    if #options < 2 or #options > 4 then return end
    local existing = findPoll(id)
    if existing then return end
    local closure = (GD.bucket.pollClosures or {})[id]
    GD:StoreRecord("polls", { id = id, ts = ts, by = author, question = question, options = options, votes = {},
        closed = closure ~= nil, closedAt = closure and closure.ts, closedBy = closure and closure.by })
end)

GD:RegisterRecordHandler("V", function(id, ts, voter, content)
    local poll, choice = findPoll(id), tonumber(content)
    if not poll or not choice or not poll.options[choice] or (poll.closed and ts > (poll.closedAt or 0)) then return end
    local previous = poll.votes[voter]
    if previous and previous.ts >= ts then return end
    poll.votes[voter] = { choice = choice, ts = ts }
    if GD.RefreshUI then GD:RefreshUI() end
end)

GD:RegisterRecordHandler("OC", function(id, ts, closer)
    receiveControl("OC", id, ts, closer)
end)

GD:RegisterRecordHandler("OD", function(id, ts, author) receiveControl("OD", id, ts, author) end)

GD:RegisterHistoryProvider(function()
    local polls = GD.bucket.polls or {}
    for i = math.min(#polls, 20), 1, -1 do
        local poll = polls[i]
        GD:SendRecord("O", poll.id, poll.ts, poll.by, pollPayload(poll))
        for voter, vote in pairs(poll.votes or {}) do
            GD:SendRecord("V", poll.id, type(vote) == "table" and vote.ts or poll.ts, voter,
                type(vote) == "table" and vote.choice or vote)
        end
        if poll.closed then GD:SendRecord("OC", poll.id, poll.closedAt or poll.ts, poll.closedBy or poll.by, "closed") end
    end
    for id, record in pairs(GD.bucket.pollDeletes or {}) do GD:SendRecord("OD", id, record.ts, record.by, "deleted") end
    for id, record in pairs(GD.bucket.pollClosures or {}) do
        if not findPoll(id) then GD:SendRecord("OC", id, record.ts, record.by, "closed") end
    end
end)

local function selectOpen(number)
    return openPolls()[tonumber(number) or 0]
end

GD:RegisterCommand("poll", function(rest)
    local action, content = rest:match("^(%S+)%s*(.*)$")
    action = (action or ""):lower()
    if action == "create" then
        local question, optionText = content:match("^(.-)%s*|%s*(.*)$")
        local options = {}
        for option in (optionText or ""):gmatch("([^|]+)") do
            option = option:gsub("^%s+", ""):gsub("%s+$", "")
            if option ~= "" then options[#options + 1] = option:sub(1, 60) end
        end
        local _, result = GD:CreatePoll(question, options)
        print("GuildDB: " .. result)
    elseif action == "vote" then
        local number, choice = content:match("^(%d+)%s+(%d+)$")
        local poll = selectOpen(number)
        choice = tonumber(choice)
        if not poll or not choice or not poll.options[choice] then print("GuildDB: Choose an open poll number and a valid option number."); return end
        local _, result = GD:VotePoll(poll.id, choice)
        print("GuildDB: " .. result)
    elseif action == "close" then
        local poll = selectOpen(content)
        local _, result = GD:ClosePoll(poll and poll.id)
        print("GuildDB: " .. result)
    else
        GD.activeTab = "Polls"
        GD:Open()
    end
end)

GD:RegisterTab("Polls", function()
    if not GD.bucket then return "Join a guild to see guild polls." end
    local polls = GD.bucket.polls or {}
    if #polls == 0 then return "No polls yet. Officers can create one with /gd poll create Question | Option 1 | Option 2." end
    local lines = { "Polls · votes are not shown by member; results are public", "Use /gd poll vote # option# to vote.", "" }
    local openNumber = 0
    for _, poll in ipairs(polls) do
        if not poll.closed then openNumber = openNumber + 1 end
        local counts = {}
        for i = 1, #poll.options do counts[i] = 0 end
        for _, vote in pairs(poll.votes or {}) do
            local choice = type(vote) == "table" and vote.choice or vote
            if counts[choice] then counts[choice] = counts[choice] + 1 end
        end
        lines[#lines + 1] = ("%s%s · %s"):format(poll.closed and "[CLOSED] " or (openNumber .. ". "), GD:Display(poll.question), date("%b %d", poll.ts))
        for i, option in ipairs(poll.options) do lines[#lines + 1] = ("  %d. %s — %d"):format(i, GD:Display(option), counts[i]) end
        lines[#lines + 1] = ""
    end
    return table.concat(lines, "\n")
end)

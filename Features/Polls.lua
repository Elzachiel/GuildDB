-- Officer polls with one replaceable vote per guild member.
local _, GH = ...
GH:RegisterBucket("polls", function() return {} end)

local function findPoll(id)
    for _, poll in ipairs(GH.bucket.polls or {}) do if poll.id == id then return poll end end
end

local function openPolls()
    local result = {}
    for _, poll in ipairs((GH.bucket and GH.bucket.polls) or {}) do if not poll.closed then result[#result + 1] = poll end end
    return result
end
GH.GetOpenPolls = openPolls

local function pollPayload(poll)
    return poll.question .. "\n" .. table.concat(poll.options, "\n")
end

local function closePoll(poll, closer, ts, send)
    poll.closed, poll.closedAt, poll.closedBy = true, ts, closer
    if send then GH:SendRecord("OC", poll.id, ts, closer, "closed") end
    if GH.RefreshUI then GH:RefreshUI() end
end

function GH:CreatePoll(question, options)
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
    self:StoreRecord("polls", poll, "O", pollPayload(poll))
    return true, "Poll created."
end

function GH:VotePoll(id, choice)
    local poll, voter = findPoll(id), UnitName and UnitName("player") or "Guild member"
    choice = tonumber(choice)
    if not poll or poll.closed or not choice or not poll.options[choice] then return false, "That poll or option is unavailable." end
    local ts = time()
    poll.votes[voter] = { choice = choice, ts = ts }
    self:SendRecord("V", poll.id, ts, voter, choice)
    if self.RefreshUI then self:RefreshUI() end
    return true, "Vote recorded."
end

function GH:ClosePoll(id)
    if not self:CanManage() then return false, "Only officers can close polls." end
    local poll = findPoll(id)
    if not poll or poll.closed then return false, "That poll is already closed or unavailable." end
    closePoll(poll, UnitName and UnitName("player") or "Guild officer", time(), true)
    return true, "Poll closed."
end

GH:RegisterRecordHandler("O", function(id, ts, author, content)
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
    GH:StoreRecord("polls", { id = id, ts = ts, by = author, question = question, options = options, votes = {}, closed = false })
end)

GH:RegisterRecordHandler("V", function(id, ts, voter, content)
    local poll, choice = findPoll(id), tonumber(content)
    if not poll or not choice or not poll.options[choice] or (poll.closed and ts > (poll.closedAt or 0)) then return end
    local previous = poll.votes[voter]
    if previous and previous.ts >= ts then return end
    poll.votes[voter] = { choice = choice, ts = ts }
    if GH.RefreshUI then GH:RefreshUI() end
end)

GH:RegisterRecordHandler("OC", function(id, ts, closer) 
    local poll = findPoll(id)
    if poll and (not poll.closedAt or poll.closedAt < ts) then closePoll(poll, closer, ts, false) end
end)

GH:RegisterHistoryProvider(function()
    local polls = GH.bucket.polls or {}
    for i = math.min(#polls, 20), 1, -1 do
        local poll = polls[i]
        GH:SendRecord("O", poll.id, poll.ts, poll.by, pollPayload(poll))
        for voter, vote in pairs(poll.votes or {}) do GH:SendRecord("V", poll.id, vote.ts, voter, vote.choice) end
        if poll.closed then GH:SendRecord("OC", poll.id, poll.closedAt or poll.ts, poll.closedBy or poll.by, "closed") end
    end
end)

local function selectOpen(number)
    return openPolls()[tonumber(number) or 0]
end

GH:RegisterCommand("poll", function(rest)
    local action, content = rest:match("^(%S+)%s*(.*)$")
    action = (action or ""):lower()
    if action == "create" then
        local question, optionText = content:match("^(.-)%s*|%s*(.*)$")
        local options = {}
        for option in (optionText or ""):gmatch("([^|]+)") do
            option = option:gsub("^%s+", ""):gsub("%s+$", "")
            if option ~= "" then options[#options + 1] = option:sub(1, 60) end
        end
        local _, result = GH:CreatePoll(question, options)
        print("GuildDB: " .. result)
    elseif action == "vote" then
        local number, choice = content:match("^(%d+)%s+(%d+)$")
        local poll = selectOpen(number)
        choice = tonumber(choice)
        if not poll or not choice or not poll.options[choice] then print("GuildDB: Choose an open poll number and a valid option number."); return end
        local _, result = GH:VotePoll(poll.id, choice)
        print("GuildDB: " .. result)
    elseif action == "close" then
        local poll = selectOpen(content)
        local _, result = GH:ClosePoll(poll and poll.id)
        print("GuildDB: " .. result)
    else
        GH.activeTab = "Polls"
        GH:Open()
    end
end)

GH:RegisterTab("Polls", function()
    if not GH.bucket then return "Join a guild to see guild polls." end
    local polls = GH.bucket.polls or {}
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
        lines[#lines + 1] = ("%s%s · %s"):format(poll.closed and "[CLOSED] " or (openNumber .. ". "), GH:Display(poll.question), date("%b %d", poll.ts))
        for i, option in ipairs(poll.options) do lines[#lines + 1] = ("  %d. %s — %d"):format(i, GH:Display(option), counts[i]) end
        lines[#lines + 1] = ""
    end
    return table.concat(lines, "\n")
end)

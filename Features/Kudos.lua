-- One changeable reaction per character and post, shared through guild history.
local _, GD = ...
local choices = {
    { "cheers", "Cheers", "Interface/Icons/INV_Drink_03", { 1, 0.78, 0.25 } },
    { "thanks", "Thanks", "Interface/Icons/Spell_Holy_BlessingOfStrength", { 0.30, 0.82, 0.65 } },
    { "epic", "Epic", "Interface/Icons/INV_Misc_Gem_Diamond_02", { 0.72, 0.45, 1 } },
}
local valid = { cheers = true, thanks = true, epic = true, none = true }
GD:RegisterBucket("kudos", function() return {} end)

local function keyFor(category, record)
    if category == "S" then return "S:" .. record.id end
    if record.kind == "R" then return "A:R:" .. record.id end
    -- Milestone messages can have different IDs on older clients. Share reactions
    -- by milestone identity, rather than splitting counts across those aliases.
    local author, profession = record.by:lower(), (record.profession or ""):lower()
    return table.concat({ "A", record.kind, record.value, #author, author, #profession, profession }, ":")
end

local function deletionKeys()
    local result = {}
    for id in pairs((GD.bucket and GD.bucket.shoutoutDeletes) or {}) do result["S:" .. id] = true end
    for id, record in pairs((GD.bucket and GD.bucket.guildAchievementDeletes) or {}) do
        result[keyFor("A", { id = id, kind = record.kind, value = record.value,
            by = record.targetAuthor, profession = record.profession })] = true
    end
    return result
end

local function deleted(key)
    return deletionKeys()[key] == true
end

local function targets()
    local result = {}
    for _, record in ipairs(GD.bucket and GD.bucket.guildAchievements or {}) do result[keyFor("A", record)] = true end
    for _, record in ipairs(GD.bucket and GD.bucket.shoutouts or {}) do result[keyFor("S", record)] = true end
    return result
end

local function prune()
    local store = GD.bucket and GD.bucket.kudos
    if not store then return end
    local live, removed, remaining = targets(), deletionKeys(), {}
    for key, entry in pairs(store) do
        if removed[key] or (not live[key] and time() - (entry.seen or 0) > 600) then store[key] = nil
        else remaining[#remaining + 1] = { key = key, seen = entry.seen or 0, live = live[key] == true } end
    end
    table.sort(remaining, function(a, b)
        if a.live ~= b.live then return a.live end
        if a.seen ~= b.seen then return a.seen > b.seen end
        return a.key < b.key
    end)
    for index = 801, #remaining do store[remaining[index].key] = nil end
end

local function receive(key, ts, author, choice)
    if not GD.bucket or type(key) ~= "string" or #key > 250
        or not (key:match("^A:[LPR]:") or key:match("^S:")) or key:find("[%c]")
        or type(author) ~= "string" or author == "" or #author > 100 or author:find("[%c|]")
        or not valid[choice] or type(ts) ~= "number" or ts <= 0 or ts > time() + 60 or deleted(key) then return false end
    GD.bucket.kudos = GD.bucket.kudos or {}
    local store, voter = GD.bucket.kudos, author:lower()
    local entry = store[key] or { votes = {}, seen = time() }
    local previous = entry.votes[voter]
    if previous and (previous.ts > ts or (previous.ts == ts and previous.choice >= choice)) then return false end
    entry.votes[voter] = { ts = ts, by = author, choice = choice }
    entry.seen = time()
    store[key] = entry
    prune()
    return true
end

function GD:GetKudos(category, record)
    local counts, mine = { cheers = 0, thanks = 0, epic = 0 }, nil
    local key = keyFor(category, record)
    local entry = self.bucket and self.bucket.kudos and self.bucket.kudos[key]
    if entry and not deleted(key) then
        local player = self:PlayerName():lower()
        for voter, vote in pairs(entry.votes) do
            if counts[vote.choice] then counts[vote.choice] = counts[vote.choice] + 1 end
            if voter == player then mine = vote.choice end
        end
    end
    return counts, mine
end

function GD:ReactWithKudos(category, record, choice)
    if not self.bucket then return false, "Join a guild first." end
    if not valid[choice] or choice == "none" then return false, "Choose Cheers, Thanks, or Epic." end
    local key = keyFor(category, record)
    if not targets()[key] or deleted(key) then return false, "This post is no longer available." end
    local author = self:PlayerName()
    local entry = self.bucket.kudos and self.bucket.kudos[key]
    local previous = entry and entry.votes[author:lower()]
    local ts = math.max(time(), previous and previous.ts + 1 or 0)
    if ts > time() + 60 then return false, "Wait a moment before reacting again." end
    if previous and previous.choice == choice then choice = "none" end
    if not receive(key, ts, author, choice) then return false, "Could not save your reaction." end
    self:SendRecord("KU", "kudos", ts, author, key .. "\n" .. choice)
    if self.RefreshUI then self:RefreshUI() end
    return true
end

GD:RegisterRecordHandler("KU", function(_, ts, author, content)
    local key, choice = content:match("^([^\n]+)\n([a-z]+)$")
    if key and receive(key, ts, author, choice) and GD.RefreshUI then GD:RefreshUI() end
end, 270)
GD:RegisterHistoryProvider(function()
    if not GD.bucket then return end
    prune()
    local live = targets()
    for key, entry in pairs(GD.bucket.kudos or {}) do
        if live[key] then
            for _, vote in pairs(entry.votes) do
                GD:SendRecord("KU", "kudos", vote.ts, vote.by, key .. "\n" .. vote.choice)
            end
        end
    end
end)

function GD:RefreshKudosButtons(row, category, record)
    row.kudosButtons = row.kudosButtons or {}
    local counts, mine = self:GetKudos(category, record)
    local colors = self:GetAppearanceColors()
    for index, option in ipairs(choices) do
        local choice, label = option[1], option[2]
        local color, selected = option[4], mine == choice
        local button = row.kudosButtons[index]
        if not button then
            button = CreateFrame("Button", nil, row, "BackdropTemplate")
            button:SetSize(104, 26)
            button:SetPoint("BOTTOMLEFT", 64 + (index - 1) * 112, 10)
            button:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
            button.icon = button:CreateTexture(nil, "ARTWORK")
            button.icon:SetSize(18, 18)
            button.icon:SetPoint("LEFT", 7, 0)
            button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            button.label:SetPoint("LEFT", 31, 0)
            button.label:SetPoint("RIGHT", -5, 0)
            button.label:SetJustifyH("LEFT")
            button.label:SetWordWrap(false)
            button.selectedMark = button:CreateTexture(nil, "OVERLAY")
            button.selectedMark:SetPoint("BOTTOMLEFT", 1, 1)
            button.selectedMark:SetPoint("BOTTOMRIGHT", -1, 1)
            button.selectedMark:SetHeight(2)
            row.kudosButtons[index] = button
        end
        button.icon:SetTexture(option[3])
        button.label:SetText(label .. " " .. counts[choice])
        button.selectedMark:SetColorTexture(color[1], color[2], color[3], 1)
        button.selectedMark:SetShown(selected)
        local function style(hover)
            local tint = selected and 0.20 or hover and 0.12 or 0.03
            button:SetBackdropColor(colors.panel[1] * (1 - tint) + color[1] * tint,
                colors.panel[2] * (1 - tint) + color[2] * tint,
                colors.panel[3] * (1 - tint) + color[3] * tint, 1)
            local border = (selected or hover) and color or colors.muted
            button:SetBackdropBorderColor(border[1], border[2], border[3], (selected or hover) and 0.9 or 0.35)
            local textColor = (selected or hover) and colors.text or colors.muted
            button.label:SetTextColor(unpack(textColor))
            button.icon:SetDesaturated(not selected and not hover)
        end
        style(false)
        button:SetScript("OnEnter", function()
            style(true)
            GameTooltip:SetOwner(button, "ANCHOR_TOP")
            GameTooltip:SetText(label .. " - " .. counts[choice])
            GameTooltip:AddLine(selected and "Your reaction. Click to remove." or "Click to react. One choice per character.", 0.8, 0.85, 0.9)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() style(false); GameTooltip:Hide() end)
        button:SetScript("OnHide", function() if GameTooltip:IsOwned(button) then GameTooltip:Hide() end end)
        button:SetScript("OnClick", function()
            if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
            local ok, message = GD:ReactWithKudos(category, record, choice)
            if not ok and message then print("GuildDB: " .. message) end
        end)
        button:Show()
    end
end

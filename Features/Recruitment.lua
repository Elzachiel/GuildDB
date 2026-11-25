-- Officer-only recruiting. Private data stays local; never use guild history transport.
local _, GD = ...
GD:RegisterTab("Recruitment", function() return "" end)

local CONTACT_DELAY, PLAYER_DELAY, SKIP_DELAY, DAILY_LIMIT = 2, 86400, 3600, 50
local statuses = { "All", "New", "Contacted", "Replied", "Invited", "Skipped", "Do Not Contact" }
local function clean(value, limit)
    return tostring(value or ""):gsub("|", " "):gsub("[\r\n]", " "):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, limit)
end
local function key(name) return clean(name, 100):lower() end
local function contacted(record)
    return record.lastWhisper or record.lastInvite or record.status == "Contacted" or record.status == "Replied" or record.status == "Invited"
end
local function classColor(record, fallback)
    local class = record and record.class or ""
    local token = class:upper():gsub("%s", "")
    for file, name in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do if name == class then token = file; break end end
    for file, name in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do if name == class then token = file; break end end
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    return color and { color.r, color.g, color.b } or fallback
end
local function statusColor(record, fallback)
    if not record then return fallback end
    if record.status == "Do Not Contact" then return { 1, 0.35, 0.35 } end
    if record.status == "Replied" then return { 0.35, 0.85, 1 } end
    if contacted(record) then return { 0.35, 1, 0.55 } end
    return fallback
end
local function statusText(record)
    local status = record.status or "New"
    if contacted(record) then
        return "[" .. status:upper() .. "] " .. (record.lastInvite and "Invite sent" or "Whisper sent")
    end
    return "[" .. status:upper() .. "]"
end
local function allowed() return GD:CanManage() and GD.bucket ~= nil end
local function database()
    if not allowed() then return nil end
    -- Kept outside all registered buckets/providers: no broadcast to ordinary members.
    GD.bucket.recruitmentLocal = GD.bucket.recruitmentLocal or {}
    local owner = key(GD:PlayerName())
    local db = GD.bucket.recruitmentLocal[owner]
    if not db then
        db = { candidates = {}, message = "Hi {name}! {guild} is recruiting friendly players. Would you like to hear more?", ad = "{guild} is recruiting! Whisper me for details." }
        GD.bucket.recruitmentLocal[owner] = db
    end
    return db
end
local function refresh()
    if GD.frame and GD.frame:IsShown() and GD.activeTab == "Recruitment" then GD:RefreshUI() end
    if GD.recruitPopout and GD.recruitPopout:IsShown() then GD:RefreshRecruitPopout() end
end
local function searchFeedback(message)
    local panel = GD.recruitPopout
    if panel and panel:IsShown() then panel.feedback, panel.feedbackUntil = message, time() + 12 end
    local main = GD.frame and GD.frame.recruitment
    if main then main.status:SetText(message) end
end
local function candidate(name)
    local db = database()
    return db and db.candidates[key(name)], db
end
local function joined(name)
    local wanted = key(name)
    if wanted == key(GD:PlayerName()) then return true end
    for _, member in ipairs(GD.roster or {}) do
        if key(member.name) == wanted then return true end
    end
end
local function today(db)
    local day = date("%Y-%m-%d")
    if db.day ~= day then db.day, db.contacts = day, 0 end
    return db.contacts or 0
end
local function expand(text, name)
    return (text:gsub("{name}", function() return name or "" end):gsub("{guild}", function() return GD.guildName or "our guild" end))
end

local function searchContext(query)
    query = clean(query, 150)
    local minimum, maximum = query:match("^(%d+)%s*%-%s*(%d+)$")
    if query:match("^%d+$") then minimum, maximum = query, query end
    minimum, maximum = tonumber(minimum), tonumber(maximum)
    if minimum and (minimum < 1 or maximum < minimum) then return nil end
    return { guild = GD.guildKey, owner = key(GD:PlayerName()), query = query,
        minimum = minimum, maximum = maximum, ids = {}, state = "pending" }
end
local function currentSearch()
    local search = GD.recruitSearch
    if search and search.guild == GD.guildKey and search.owner == key(GD:PlayerName()) then return search end
end
local function matchesLevel(search, level)
    if not search.minimum then return true end
    level = tonumber(level)
    return level ~= nil and level >= search.minimum and level <= search.maximum
end

function GD:ShowRecruitSavedCandidates()
    if not allowed() then return false end
    self.recruitSearch = nil
    self.recruitSavedView = { guild = self.guildKey, owner = key(self:PlayerName()) }
    return true
end

function GD:GetRecruitCandidates(status, text, whoQuery)
    local db = database()
    if not db then return {}, 0, "Only the GM and rank 1 officers can recruit." end
    local search = currentSearch()
    local saved = self.recruitSavedView
    local showSaved = saved and saved.guild == self.guildKey and saved.owner == key(self:PlayerName())
    local draft = search and whoQuery ~= nil and clean(whoQuery, 150) ~= search.query
    local requested = whoQuery ~= nil and searchContext(whoQuery) or nil
    local records, total = {}, 0
    text = tostring(text or ""):lower()
    for id, record in pairs(db.candidates) do
        total = total + 1
        local haystack = table.concat({ record.name, record.class or "", record.note or "" }, " "):lower()
        local inSearch = (not search and showSaved) or (search and not draft and search.state == "complete" and search.ids[id] and matchesLevel(search, record.level))
        local contactView = status == "Contacted"
        local newView = status == "New"
        local inRange = not requested or not requested.minimum or matchesLevel(requested, record.level)
        local unguilded = record.guildKnown ~= false and (record.guild == nil or record.guild == "") and not joined(record.name)
        local isNew = record.status == "New" and not contacted(record) and not joined(record.name)
        local matchesStatus = (newView and isNew) or (contactView and contacted(record))
            or (not newView and not contactView and (not status or status == "All" or record.status == status))
        -- The New queue includes previously found, untouched candidates as well as
        -- fresh Who results. A pending/empty Who reply must not hide that queue.
        if unguilded and inRange and (newView or contactView or inSearch) and matchesStatus and haystack:find(text, 1, true) then
            records[#records + 1] = { id = id, record = record }
        end
    end
    table.sort(records, function(a, b) return a.id < b.id end)
    local empty = "No matching candidates."
    if not search and not showSaved then empty = "Run Search Who or choose Saved list."
    elseif draft then empty = "Click Search Who to run this filter."
    elseif search and search.state == "pending" then empty = "Waiting for Who results..."
    elseif search and search.state == "timeout" then empty = "No Who reply. Retry or import results."
    elseif search and search.state == "error" then empty = search.error or "Who results could not be imported."
    elseif search then empty = "No candidates match this search and status." end
    if status == "Contacted" then empty = "No contacted candidates yet. Whispers and invites appear here automatically." end
    if status == "New" and not draft and (showSaved or (search and search.state == "complete")) then
        empty = "No uncontacted, unguilded candidates match these levels. Use Search Who to refresh this range."
    end
    return records, total, empty
end

function GD:AddRecruitCandidate(name, class, level, zone)
    if not allowed() then return false, "Recruitment is available to the GM and rank 1 officers only." end
    name = clean(name, 100)
    if name == "" or name:find("[%c%d]") then return false, "Enter a character's full name." end
    if joined(name) then return false, "That character is already in your guild." end
    local db = database()
    local id = key(name)
    local record = db.candidates[id]
    if not record then
        local count = 0
        for _, existing in pairs(db.candidates) do
            if existing.status == "New" and not contacted(existing) then count = count + 1 end
        end
        if count >= 500 then return false, "New candidate queue is full (500). Contact or skip existing candidates first." end
        record = { name = name, status = "New", added = time() }
        db.candidates[id] = record
    end
    if class then record.class = clean(class, 40) end
    if level then record.level = tonumber(level) end
    if zone then record.zone = clean(zone, 80) end
    return true, "Candidate saved.", record
end

function GD:SetRecruitStatus(name, status)
    local record = candidate(name)
    if not record then return false, "Select a candidate first." end
    if status ~= "Skipped" and status ~= "Do Not Contact" and status ~= "New" then return false, "Invalid status." end
    -- Skip must never downgrade a permanent exclusion.
    if record.status == "Do Not Contact" and status ~= "New" then return false, "Use Restore to remove Do Not Contact." end
    record.status = status
    if status == "Skipped" then record.skipUntil = time() + SKIP_DELAY end
    if status == "New" then record.skipUntil = nil end
    refresh()
    return true, status == "New" and "Candidate restored; contact cooldowns still apply." or ("Marked " .. status .. ".")
end

function GD:SaveRecruitNote(name, note)
    local record = candidate(name)
    if not record then return false, "Select a candidate first." end
    record.note = clean(note, 300)
    return true, "Note saved locally."
end

function GD:SaveRecruitTemplates(message, ad)
    local db = database()
    if not db then return false, "Only the GM and rank 1 officers can recruit." end
    message, ad = clean(message, 255), clean(ad, 255)
    if message == "" or ad == "" then return false, "Both message templates are required." end
    db.message, db.ad = message, ad
    return true, "Templates saved locally."
end

function GD:GetRecruitContactBlock(name, action)
    local record, db = candidate(name)
    if not record then return "Select a candidate first." end
    if action ~= "whisper" and action ~= "invite" then return "Invalid contact action." end
    if record.guild and record.guild ~= "" then return "That character is already in a guild." end
    if record.guildKnown == false then return "Guild status is unavailable. Refresh Who results before contacting this candidate." end
    if record.status == "Do Not Contact" then return "Do Not Contact: restore this candidate before contacting them." end
    if joined(record.name) then return "That character is already in your guild." end
    if (record.skipUntil or 0) > time() then return "Skipped for another " .. math.ceil((record.skipUntil - time()) / 60) .. " minute(s)." end
    local wait = (db.lastContact or 0) + CONTACT_DELAY - time()
    if wait > 0 then return "Wait " .. wait .. " seconds before another contact." end
    local previous
    if action == "invite" then previous = record.lastInvite else previous = record.lastWhisper end
    wait = (previous or 0) + PLAYER_DELAY - time()
    if previous and wait > 0 then return "This action is on cooldown for " .. math.ceil(wait / 60) .. " minute(s)." end
    if today(db) >= DAILY_LIMIT then return "Daily limit reached (50 contact actions)." end
    if action == "invite" and (not CanGuildInvite or not CanGuildInvite()) then return "Your guild rank cannot invite members." end
end

function GD:ContactRecruit(name, action)
    local block = self:GetRecruitContactBlock(name, action)
    if block then return false, block end
    local record, db = candidate(name)
    local send, args
    if action == "whisper" then
        local text = expand(db.message, record.name)
        if #text > 255 then return false, "Expanded whisper exceeds 255 bytes; shorten the template." end
        send, args = SendChatMessage, { text, "WHISPER", nil, record.name }
    else
        send = C_GuildInfo and C_GuildInfo.Invite or GuildInvite
        args = { record.name }
    end
    if not send then return false, "This client does not provide that action." end
    local ok, result
    if action == "whisper" then ok, result = pcall(send, args[1], args[2], nil, args[4])
    else ok, result = pcall(send, args[1]) end
    if not ok or result == false then return false, "The client could not submit that contact. Check game permissions." end
    db.lastContact, db.contacts = time(), today(db) + 1
    if action == "invite" then record.lastInvite, record.status = time(), "Invited"
    else record.lastWhisper = time(); if record.status ~= "Replied" and record.status ~= "Invited" then record.status = "Contacted" end end
    refresh()
    return true, "Contact submitted. Delivery and invitations are subject to game permissions."
end

function GD:SearchRecruits(query)
    local db = database()
    if not db then return false, "Only the GM and rank 1 officers can recruit." end
    local send = C_FriendList and C_FriendList.SendWho or SendWho
    if not send then return false, "Who search is unavailable. Add candidates by name instead." end
    if self.recruitWhoPending then return false, "Wait for the current Who search to finish before searching again." end
    if (db.lastSearch or 0) + 10 > time() then return false, "Wait 10 seconds between Who searches." end
    local search = searchContext(query)
    if not search then return false, "Enter a level or an ascending range, such as 22 or 50-60." end
    local set = C_FriendList and C_FriendList.SetWhoToUi or SetWhoToUI
    if set then pcall(set, true) end
    -- Explicit equal bounds keep a single level exact on clients whose Who parser
    -- otherwise treats a bare number as the start of a broader range.
    local filter = search.minimum and (search.minimum .. "-" .. search.maximum) or search.query
    search.sentFilter = filter
    -- Some clients can dispatch cached Who results from inside SendWho itself.
    -- Own the request before sending so its reply cannot be missed.
    local previousSearch, previousSaved = self.recruitSearch, self.recruitSavedView
    local pending = { guild = self.guildKey, owner = key(self:PlayerName()), search = search }
    self.recruitSearch, self.recruitSavedView, self.recruitWhoPending = search, nil, pending
    local ok, result
    if C_FriendList and send == C_FriendList.SendWho then
        local origin = Enum and Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social or 1
        ok, result = pcall(send, filter, origin)
    else
        ok, result = pcall(send, filter)
    end
    if not ok or result == false then
        if self.recruitWhoPending == pending then
            self.recruitSearch, self.recruitSavedView, self.recruitWhoPending = previousSearch, previousSaved, nil
        end
        if set then pcall(set, false) end
        return false, "Who search could not start: " .. tostring(result) .. ". Use the game's Who window and Import Who."
    end
    db.lastSearch = time()
    if C_Timer and C_Timer.After then C_Timer.After(15, function()
        if GD.recruitWhoPending ~= pending then return end
        GD.recruitWhoPending = nil
        if set then pcall(set, false) end
        search.state = "timeout"
        searchFeedback("Who did not reply. Try again after a few seconds, or use the game's Who window and Import Who results.")
        refresh()
    end) end
    refresh()
    return true, search.message or ("Searching Who: " .. filter .. ". Waiting for the server's results...")
end

function GD:ImportRecruitWho(search)
    if not allowed() then return false, "Only the GM and rank 1 officers can recruit." end
    local count = C_FriendList and C_FriendList.GetNumWhoResults or GetNumWhoResults
    local info = C_FriendList and C_FriendList.GetWhoInfo or GetWhoInfo
    if not count or not info then return false, "Who results are unavailable. Add candidates by name instead." end
    local ok, total = pcall(count)
    if not ok or type(total) ~= "number" then return false, "Who results could not be read." end
    if not search then
        local panel = self.frame and self.frame.recruitment
        local previous = currentSearch()
        search = searchContext(panel and panel.query:GetText() or (previous and previous.query or ""))
    end
    if not search then return false, "Enter a level or an ascending range, such as 22 or 50-60." end
    if search.guild ~= self.guildKey or search.owner ~= key(self:PlayerName()) then return false, "That search belongs to another recruiter or guild." end
    search.ids = {}
    local added, new, unknown, rejected = 0, 0, 0, 0
    local rejection
    for index = 1, math.min(total, 100) do
        local readable, first, guild, level, _, class, zone = pcall(info, index)
        if readable then
            local name = first
            if type(first) == "table" then
                name, guild, level, class, zone = first.fullName, first.fullGuildName, first.level, first.filename or first.classStr, first.area
            end
            -- Update saved candidates too: a former recruit may have joined a guild.
            local existing = type(name) == "string" and database().candidates[key(name)]
            if existing then
                existing.guildKnown = type(guild) == "string"
                existing.guild = type(guild) == "string" and guild or nil
                if tonumber(level) then existing.level = tonumber(level) end
            end
            if type(guild) ~= "string" then unknown = unknown + 1 end
            -- Unknown guild information is not evidence that a player is unguilded.
            if type(name) == "string" and guild == "" and matchesLevel(search, level) then
                local saved, message, record = self:AddRecruitCandidate(name, class, level, zone)
                if saved then
                    record.guild, record.guildKnown = "", true
                    search.ids[key(name)] = true
                    added = added + 1
                    if record.status == "New" and not contacted(record) then new = new + 1 end
                else rejected, rejection = rejected + 1, message end
            end
        end
    end
    search.state = "complete"
    search.message = added .. " unguilded candidate(s), " .. new .. " uncontacted. Levels: " .. search.query .. "."
    if rejected > 0 then search.message = search.message .. " " .. rejected .. " not saved: " .. (rejection or "Unknown error.") end
    if unknown > 0 then search.message = search.message .. " Guild information unavailable for " .. unknown .. "." end
    if total == 0 then search.message = search.message .. " Try again after a few seconds, or import results from the game's Who window."
    elseif new == 0 and added > 0 then search.message = search.message .. " Check Contacted or All saved."
    elseif new > 0 then search.message = search.message .. " Select a name below." end
    self.recruitSearch = search
    self.recruitSavedView = nil
    searchFeedback(search.message)
    local panel = self.recruitPopout
    refresh()
    if panel and panel:IsShown() and panel.owner == tostring(self.guildKey) .. ":" .. key(self:PlayerName()) then
        local records = self:GetRecruitCandidates(panel.filter or "All", "", panel.query:GetText())
        if #records > 0 then panel.candidateMenu.offset = 0; panel.candidateMenu:Show(); refresh() end
    end
    return true, search.message
end

function GD:PostRecruitAd(channel)
    local db = database()
    if not db then return false, "Only the GM and rank 1 officers can recruit." end
    if (db.lastAd or 0) + 300 > time() then return false, "Wait " .. ((db.lastAd or 0) + 300 - time()) .. " seconds before another ad." end
    channel = tonumber(channel)
    if not channel or channel < 1 or channel ~= math.floor(channel) then return false, "Enter a joined chat channel number, such as 2." end
    local id = GetChannelName and GetChannelName(channel)
    if not id or id == 0 then return false, "You are not in that chat channel." end
    local text = expand(db.ad)
    if #text > 255 then return false, "Expanded ad exceeds 255 bytes; shorten the template." end
    if not SendChatMessage then return false, "Chat is unavailable." end
    local ok, result = pcall(SendChatMessage, text, "CHANNEL", nil, channel)
    if not ok or result == false then return false, "The client could not submit the ad." end
    db.lastAd = time()
    return true, "Ad submitted to channel " .. channel .. "."
end

GD:RegisterEventHandler("WHO_LIST_UPDATE", function()
    local pending = GD.recruitWhoPending
    if not pending then return end
    GD.recruitWhoPending = nil
    local set = C_FriendList and C_FriendList.SetWhoToUi or SetWhoToUI
    if set then pcall(set, false) end
    if pending.guild == GD.guildKey and pending.owner == key(GD:PlayerName()) and allowed()
        and GD.recruitSearch == pending.search then
        local ok, message = GD:ImportRecruitWho(pending.search)
        if not ok then
            pending.search.state, pending.search.error = "error", message
            searchFeedback(message)
            refresh()
        end
    end
end)
GD:RegisterEventHandler("CHAT_MSG_WHISPER", function(_, message, sender)
    local record = candidate(sender)
    if not record or (not record.lastWhisper and not record.lastInvite) or record.status == "Do Not Contact" then return end
    record.reply, record.repliedAt, record.status = clean(message, 300), time(), "Replied"
    refresh()
end)

local function label(parent, text, x, y, font)
    local widget = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    widget:SetPoint("TOPLEFT", x, y)
    widget:SetJustifyH("LEFT")
    widget:SetText(text)
    return widget
end
local function input(parent, x, y, width, limit)
    local widget = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    widget:SetPoint("TOPLEFT", x, y)
    widget:SetSize(width, 26)
    widget:SetAutoFocus(false)
    widget:SetMaxLetters(limit)
    GD:StyleEditBox(widget)
    widget:SetScript("OnEscapePressed", function(self) self:ClearFocus(); GD:CloseWindowsOnEscape() end)
    return widget
end
local function button(panel, text, x, y, width, callback, parent)
    local widget = CreateFrame("Button", nil, parent or panel.content, "UIPanelButtonTemplate")
    widget:SetPoint("TOPLEFT", x, y)
    widget:SetSize(width, 26)
    widget:SetText(text)
    widget:SetScript("OnClick", function()
        if not allowed() then refresh(); return end
        local _, message = callback()
        panel.status:SetText(message or "")
    end)
    panel.buttons[#panel.buttons + 1] = widget
    return widget
end

local function updateContacts(panel)
    local record = candidate(panel.selected)
    local whisper = GD:GetRecruitContactBlock(panel.selected, "whisper")
    local invite = GD:GetRecruitContactBlock(panel.selected, "invite")
    panel.whisper:SetEnabled(record ~= nil and whisper == nil)
    panel.invite:SetEnabled(record ~= nil and invite == nil)
    panel.skip:SetEnabled(record ~= nil and record.status ~= "Do Not Contact")
    panel.dnc:SetEnabled(record ~= nil and record.status ~= "Do Not Contact")
    panel.restore:SetEnabled(record ~= nil and record.status ~= "New")
    panel.saveNote:SetEnabled(record ~= nil)
    panel.contactInfo:SetText(record and GD:Display("Whisper: " .. (whisper or "Ready") .. "\nInvite: " .. (invite or "Ready")) or "")
end

local function build(frame)
    local panel = CreateFrame("Frame", nil, frame.detailPanel)
    panel:SetAllPoints()
    panel.buttons, panel.rows, panel.cards, panel.labels = {}, {}, {}, {}
    panel.filter, panel.page = "New", "Candidates"
    local function text(parent, value, x, y, kind, font)
        local widget = label(parent, value, x, y, font)
        panel.labels[#panel.labels + 1] = { widget = widget, kind = kind or "text" }
        return widget
    end
    local function card(parent, title, subtitle)
        local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        box:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
        text(box, title, 14, -12, "accent", "GameFontNormal")
        local hint = text(box, subtitle, 14, -33, "muted")
        hint:SetPoint("TOPRIGHT", -14, -33)
        hint:SetHeight(28)
        panel.cards[#panel.cards + 1] = box
        return box
    end
    panel.title = text(panel, "Recruitment", 16, -16, "accent", "GameFontNormalLarge")
    panel.summary = text(panel, "", 16, -42, "muted")
    panel.status = text(panel, "Choose a candidate to get started.", 16, -12, "muted")
    panel.status:ClearAllPoints()
    panel.status:SetPoint("BOTTOMLEFT", 16, 10)
    panel.status:SetPoint("BOTTOMRIGHT", -16, 10)
    panel.status:SetHeight(28)
    panel.scroll = CreateFrame("ScrollFrame", nil, panel)
    panel.scroll:SetPoint("TOPLEFT", 16, -108)
    panel.scroll:SetPoint("BOTTOMRIGHT", -30, 48)
    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetSize(740, 480)
    panel.scroll:SetScrollChild(panel.content)
    panel.candidatesPage = CreateFrame("Frame", nil, panel.content)
    panel.candidatesPage:SetAllPoints()
    panel.messagesPage = CreateFrame("Frame", nil, panel.content)
    panel.messagesPage:SetAllPoints()
    for index, page in ipairs({ "Candidates", "Messages" }) do
        local tab = button(panel, page, 16 + (index - 1) * 132, -68, 122, function()
            panel.page = page
            panel.scroll:SetVerticalScroll(0)
            refresh()
            return true, page == "Candidates" and "Select a candidate to review or contact." or "Save your templates before sending."
        end, panel)
        if page == "Candidates" then panel.candidatesTab = tab else panel.messagesTab = tab end
    end
    button(panel, "Pop out", 280, -68, 110, function() return GD:ShowRecruitPopout() end, panel)

    panel.findBox = card(panel.candidatesPage, "Find players", "Search Who for unguilded players, or add a full character name.")
    panel.findBox:SetPoint("TOPLEFT")
    panel.findBox:SetPoint("TOPRIGHT")
    panel.findBox:SetHeight(136)
    panel.query = input(panel.findBox, 14, -64, 240, 150)
    panel.query:SetText("1-60")
    panel.query:SetScript("OnTextChanged", function() refresh() end)
    button(panel, "Search Who", 264, -64, 106, function()
        local previous = panel.filter
        panel.filter = "New"
        local ok, message = GD:SearchRecruits(panel.query:GetText())
        if not ok then panel.filter = previous end
        refresh()
        return ok, message
    end, panel.findBox)
    button(panel, "Import results", 380, -64, 116, function() return GD:ImportRecruitWho() end, panel.findBox)
    panel.name = input(panel.findBox, 14, -96, 240, 100)
    panel.addName = button(panel, "Add name", 264, -96, 106, function()
        local ok, message, record = GD:AddRecruitCandidate(panel.name:GetText())
        if ok then GD:ShowRecruitSavedCandidates(); panel.selected = key(record.name); panel.name:SetText(""); panel.filter = "All"; refresh() end
        return ok, message
    end, panel.findBox)
    button(panel, "Saved list", 380, -96, 116, function()
        if GD.recruitWhoPending then return false, "Wait for the current Who search to finish." end
        GD:ShowRecruitSavedCandidates()
        refresh()
        return true, "Showing saved candidates. Contact history and exclusions are retained."
    end, panel.findBox)

    panel.listBox = card(panel.candidatesPage, "Candidates", "Search and select someone to review.")
    panel.listBox:SetPoint("TOPLEFT", 0, -150)
    panel.listBox:SetSize(310, 338)
    panel.filterButton = button(panel, "All  v", 14, -64, 128, function()
        if panel.filterMenu:IsShown() then panel.filterMenu:Hide()
        else GD:RefreshRecruitmentAppearance(); panel.filterMenu:Show() end
        return true, "Choose a candidate status."
    end, panel.listBox)
    -- Keep the menu outside the scroll child so the options cannot be clipped.
    panel.filterMenu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    panel.filterMenu:SetSize(184, #statuses * 28 + 8)
    panel.filterMenu:SetPoint("TOPLEFT", panel.filterButton, "BOTTOMLEFT", 0, -4)
    panel.filterMenu:SetFrameStrata("TOOLTIP")
    panel.filterMenu:SetClampedToScreen(true)
    panel.filterMenu:EnableMouse(true)
    panel.filterMenu:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    panel.filterMenu:Hide()
    panel.filterOptions = {}
    for index, status in ipairs(statuses) do
        panel.filterOptions[index] = button(panel, status, 4, -4 - (index - 1) * 28, 176, function()
            panel.filter = status
            panel.filterMenu:Hide()
            if panel.list then panel.list:SetVerticalScroll(0) end
            refresh()
            return true, "Showing " .. status .. "."
        end, panel.filterMenu)
    end
    panel.filterMenu:SetScript("OnUpdate", function(menu)
        if not allowed() or GD.activeTab ~= "Recruitment" or panel.page ~= "Candidates" then menu:Hide(); return end
        if IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
            and not menu:IsMouseOver() and not panel.filterButton:IsMouseOver() then menu:Hide() end
    end)
    local function closeFilter() panel.filterMenu:Hide() end
    panel:HookScript("OnHide", closeFilter)
    panel:HookScript("OnHide", function()
        local popout = GD.recruitPopout
        if popout and popout:IsShown() and popout.owner == tostring(GD.guildKey) .. ":" .. key(GD:PlayerName()) then return end
        -- Opening Recruitment is a fresh workspace; history is an explicit view.
        GD.recruitSearch, GD.recruitSavedView = nil, nil
        panel.selected = nil
    end)
    panel.candidatesPage:HookScript("OnHide", closeFilter)
    panel.scroll:HookScript("OnVerticalScroll", closeFilter)
    panel.search = input(panel.listBox, 152, -64, 144, 100)
    panel.search:SetScript("OnTextChanged", function() refresh() end)
    panel.list = CreateFrame("ScrollFrame", nil, panel.listBox)
    panel.list:SetPoint("TOPLEFT", 12, -102)
    panel.list:SetPoint("BOTTOMRIGHT", -26, 12)
    panel.listContent = CreateFrame("Frame", nil, panel.list)
    panel.listContent:SetSize(270, 220)
    panel.list:SetScrollChild(panel.listContent)
    panel.empty = text(panel.listContent, "No matching candidates.", 4, -8, "muted")

    panel.workBox = card(panel.candidatesPage, "Selected candidate", "Review replies, contact actions, and private notes.")
    panel.workBox:SetPoint("TOPLEFT", panel.listBox, "TOPRIGHT", 14, 0)
    panel.workBox:SetPoint("BOTTOMRIGHT", 0, 8)
    panel.selectedText = text(panel.workBox, "Select a candidate from the list.", 14, -64, "accent", "GameFontNormal")
    panel.selectedText:SetPoint("TOPRIGHT", -14, -64)
    panel.selectedText:SetHeight(20)
    panel.contactInfo = text(panel.workBox, "", 14, -90, "muted")
    panel.contactInfo:SetPoint("TOPRIGHT", -14, -90)
    panel.contactInfo:SetHeight(48)
    panel.whisper = button(panel, "Whisper", 14, -144, 112, function() return GD:ContactRecruit(panel.selected, "whisper") end, panel.workBox)
    panel.invite = button(panel, "Guild invite", 136, -144, 112, function() return GD:ContactRecruit(panel.selected, "invite") end, panel.workBox)
    panel.skip = button(panel, "Skip 1 hour", 14, -180, 104, function() return GD:SetRecruitStatus(panel.selected, "Skipped") end, panel.workBox)
    panel.dnc = button(panel, "Do Not Contact", 128, -180, 132, function() return GD:SetRecruitStatus(panel.selected, "Do Not Contact") end, panel.workBox)
    panel.restore = button(panel, "Restore", 270, -180, 82, function() return GD:SetRecruitStatus(panel.selected, "New") end, panel.workBox)
    panel.reply = text(panel.workBox, "", 14, -220)
    panel.reply:SetPoint("TOPRIGHT", -14, -220)
    panel.reply:SetHeight(36)
    text(panel.workBox, "PRIVATE NOTE", 14, -266, "muted")
    panel.note = input(panel.workBox, 14, -286, 240, 300)
    panel.note:SetPoint("TOPRIGHT", -110, -286)
    panel.saveNote = button(panel, "Save note", 0, -286, 86, function() return GD:SaveRecruitNote(panel.selected, panel.note:GetText()) end, panel.workBox)
    panel.saveNote:ClearAllPoints()
    panel.saveNote:SetPoint("TOPRIGHT", -14, -286)

    panel.whisperBox = card(panel.messagesPage, "Recruiting whisper", "Use {name} for the candidate and {guild} for your guild name.")
    panel.whisperBox:SetPoint("TOPLEFT")
    panel.whisperBox:SetPoint("TOPRIGHT")
    panel.whisperBox:SetHeight(124)
    panel.message = input(panel.whisperBox, 14, -70, 670, 255)
    panel.message:SetPoint("TOPRIGHT", -14, -70)
    panel.adBox = card(panel.messagesPage, "Guild advertisement", "Use {guild} for your guild name. Posting requires a click.")
    panel.adBox:SetPoint("TOPLEFT", 0, -138)
    panel.adBox:SetPoint("TOPRIGHT", 0, -138)
    panel.adBox:SetHeight(160)
    panel.ad = input(panel.adBox, 14, -64, 670, 255)
    panel.ad:SetPoint("TOPRIGHT", -14, -64)
    text(panel.adBox, "Channel #", 14, -110, "muted")
    panel.channel = input(panel.adBox, 90, -104, 52, 3)
    panel.channel:SetText("2")
    button(panel, "Post ad", 156, -104, 104, function() return GD:PostRecruitAd(panel.channel:GetText()) end, panel.adBox)
    panel.saveTemplates = button(panel, "Save templates", 0, -104, 140, function() return GD:SaveRecruitTemplates(panel.message:GetText(), panel.ad:GetText()) end, panel.adBox)
    panel.saveTemplates:ClearAllPoints()
    panel.saveTemplates:SetPoint("TOPRIGHT", -14, -104)
    panel.policyBox = card(panel.messagesPage, "Contact limits", "Exclusions and cooldowns survive reloads.")
    panel.policyBox:SetPoint("TOPLEFT", 0, -312)
    panel.policyBox:SetPoint("TOPRIGHT", 0, -312)
    panel.policyBox:SetHeight(158)
    panel.policy = text(panel.policyBox, "2 seconds between contacts; 24 hours per player per action; 50 actions/day.\nSkip: 1 hour. Do Not Contact: until explicitly restored. Ads: 5 minutes.\nAds, whispers and guild invites can be submitted during combat.\nSave templates before sending. Expanded messages must fit 255 bytes.", 14, -64, "muted")
    panel.policy:SetPoint("TOPRIGHT", -14, -64)
    panel.policy:SetHeight(82)
    panel:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed < 1 then return end
        self.elapsed = 0
        if not allowed() then GD:RefreshUI(); return end
        updateContacts(self)
    end)
    panel.scroll:HookScript("OnSizeChanged", function() GD:LayoutRecruitment() end)
    frame.recruitment = panel
    return panel
end

function GD:LayoutRecruitment()
    local panel = self.frame and self.frame.recruitment
    if not panel then return end
    local width = math.max(1, panel.scroll:GetWidth())
    panel.content:SetWidth(width)
    panel.content:SetHeight(panel.page == "Candidates" and 496 or 480)
    -- Keep the two workspaces distinct with equal gutters and a wider detail card.
    local listWidth = math.max(250, math.floor(width * 0.40))
    panel.listBox:SetWidth(listWidth)
    panel.search:SetWidth(math.max(72, listWidth - 166))
    panel.listContent:SetWidth(math.max(1, panel.list:GetWidth() - 2))
    self:StyleScrollFrame(panel.scroll)
    self:StyleScrollFrame(panel.list)
end

function GD:RefreshRecruitmentAppearance()
    local panel = self.frame and self.frame.recruitment
    if not panel then return end
    local colors = self:GetAppearanceColors()
    for _, box in ipairs(panel.cards) do
        box:SetBackdropColor(unpack(colors.alternate))
        box:SetBackdropBorderColor(colors.accent[1] * 0.5, colors.accent[2] * 0.5, colors.accent[3] * 0.5, 1)
    end
    for _, entry in ipairs(panel.labels) do entry.widget:SetTextColor(unpack(colors[entry.kind])) end
    for _, widget in ipairs(panel.buttons) do self:StyleButton(widget, widget == panel.saveTemplates and "primary" or nil) end
    self:StyleButton(panel.candidatesTab, panel.page == "Candidates" and "primary" or nil)
    self:StyleButton(panel.messagesTab, panel.page == "Messages" and "primary" or nil)
    self:StyleSurface(panel.filterMenu)
    for index, option in ipairs(panel.filterOptions) do
        self:StyleButton(option, statuses[index] == panel.filter and "primary" or nil)
    end
    for _, widget in ipairs({ panel.query, panel.name, panel.search, panel.note, panel.message, panel.ad, panel.channel }) do
        widget:SetBackdropColor(unpack(colors.panel))
        widget:SetTextColor(unpack(colors.text))
        widget:SetGuildDBFocusState(widget:HasFocus())
    end
    self:StyleScrollFrame(panel.scroll)
    self:StyleScrollFrame(panel.list)
end
function GD:RefreshRecruitment()
    if not allowed() then return end
    local frame, db = self.frame, database()
    local panel = frame.recruitment or build(frame)
    for _, name in ipairs({ "detailScroll", "detailTitle", "detailMeta", "detailRule", "footer", "detailBody" }) do frame[name]:Hide() end
    panel:Show()
    panel.candidatesPage:SetShown(panel.page == "Candidates")
    panel.messagesPage:SetShown(panel.page == "Messages")
    self:LayoutRecruitment()
    self:RefreshRecruitmentAppearance()
    local owner = self.guildKey .. ":" .. key(self:PlayerName())
    if panel.owner ~= owner then
        panel.owner, panel.selected, panel.loadedCandidate, panel.filter = owner, nil, nil, "New"
        panel.message:SetText(db.message)
        panel.ad:SetText(db.ad)
        panel.note:SetText("")
        panel.status:SetText("Each whisper, invite, and ad requires your click.")
    end
    local records, total, empty = self:GetRecruitCandidates(panel.filter, panel.search:GetText(), panel.query:GetText())
    if panel.selected then
        local visible = false
        for _, entry in ipairs(records) do if entry.id == panel.selected then visible = true; break end end
        if not visible then panel.selected = nil end
    end
    panel.summary:SetText(#records .. " shown / " .. total .. " saved | " .. today(db) .. "/" .. DAILY_LIMIT .. " contact actions today | GM / rank 1 only")
    panel.filterButton:SetText(panel.filter .. "  v")
    panel.empty:SetShown(#records == 0)
    panel.empty:SetText(empty)
    for index, entry in ipairs(records) do
        local row = panel.rows[index]
        if not row then
            row = CreateFrame("Button", nil, panel.listContent, "UIPanelButtonTemplate")
            row:SetHeight(48)
            row:SetPoint("TOPLEFT", 0, -(index - 1) * 52)
            row:SetPoint("TOPRIGHT", -2, -(index - 1) * 52)
            row.name = label(row, "", 10, -8, "GameFontNormal")
            row.name:SetPoint("TOPRIGHT", -10, -8)
            row.name:SetWordWrap(false)
            row.meta = label(row, "", 10, -28)
            row.meta:SetPoint("TOPRIGHT", -10, -28)
            row.meta:SetWordWrap(false)
            row:EnableMouseWheel(true)
            row:SetScript("OnMouseWheel", function(_, delta) panel.list:GetScript("OnMouseWheel")(panel.list, delta) end)
            row:SetScript("OnClick", function(widget)
                if not allowed() then return end
                panel.selected = widget.id
                refresh()
            end)
            panel.rows[index] = row
        end
        row.id = entry.id
        local record = entry.record
        row.name:SetText(self:Display(record.name))
        row.meta:SetText(self:Display(statusText(record) .. " - " .. (record.level or "?") .. " " .. (record.class or "")))
        local colors = self:GetAppearanceColors()
        row.name:SetTextColor(unpack(classColor(record, colors.text)))
        row.meta:SetTextColor(unpack(statusColor(record, colors.muted)))
        self:StyleButton(row, panel.selected == entry.id and "primary" or nil)
        row:Show()
    end
    for index = #records + 1, #panel.rows do panel.rows[index]:Hide() end
    panel.listContent:SetHeight(math.max(panel.list:GetHeight(), #records * 52))
    self:StyleScrollFrame(panel.list)
    local record = db.candidates[panel.selected or ""]
    if panel.loadedCandidate ~= panel.selected then
        panel.loadedCandidate = panel.selected
        panel.note:SetText(record and record.note or "")
    end
    panel.selectedText:SetText(record and self:Display(record.name .. " - " .. statusText(record)) or "Select a candidate above.")
    panel.selectedText:SetTextColor(unpack(classColor(record, self:GetAppearanceColors().text)))
    panel.reply:SetText(record and record.reply and ("Latest reply: " .. self:Display(record.reply)) or "Replies from contacted candidates appear here. Replies never trigger automatic invites.")
    updateContacts(panel)
end

local function popoutAllowed()
    return allowed() and (not GD.GetSetting or GD:GetSetting("feature:Recruitment"))
end

local function popoutOwner()
    return tostring(GD.guildKey) .. ":" .. key(GD:PlayerName())
end

function GD:StepRecruitPopout(delta)
    local panel = self.recruitPopout
    if not panel or not popoutAllowed() or panel.owner ~= popoutOwner() then return end
    local records = self:GetRecruitCandidates(panel.filter or "All", "", panel.query:GetText())
    if #records == 0 then panel.selected = nil; self:RefreshRecruitPopout(); return end
    local index = 1
    for i, entry in ipairs(records) do if entry.id == panel.selected then index = i; break end end
    panel.selected = records[(index - 1 + delta) % #records + 1].id
    self:RefreshRecruitPopout()
end

local function refreshPopoutChoices(panel, records)
    local menu = panel.candidateMenu
    if not menu:IsShown() then return end
    local colors = GD:GetAppearanceColors()
    local count = math.min(6, #records)
    menu.offset = math.max(0, math.min(menu.offset or 0, #records - count))
    menu:SetWidth(panel.candidateButton:GetWidth())
    menu:SetHeight(count * 40 + 28)
    GD:StyleSurface(menu)
    for i, row in ipairs(menu.rows) do
        local entry = records[i + menu.offset]
        row.id = entry and entry.id
        row:SetShown(entry ~= nil)
        if entry then
            GD:StyleButton(row, panel.selected == entry.id and "primary" or nil)
            row.name:SetText(GD:Display(entry.record.name .. " - " .. (entry.record.level or "?") .. " " .. (entry.record.class or "")))
            row.name:SetTextColor(unpack(classColor(entry.record, colors.text)))
            row.status:SetText(GD:Display(statusText(entry.record)))
            row.status:SetTextColor(unpack(statusColor(entry.record, colors.muted)))
        end
    end
    menu.hint:SetText((menu.offset + 1) .. "-" .. (menu.offset + count) .. " / " .. #records .. (#records > count and "  |  Scroll for more" or ""))
    menu.hint:SetTextColor(unpack(colors.muted))
    if #records == 0 then menu:Hide() end
end

local function layoutPopout(panel)
    local width, height = panel:GetSize()
    local compact = height < 480
    local function place(control, x, y, w)
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
        if w then control:SetWidth(w) end
    end
    panel.query:SetWidth(width - 144)
    place(panel.searchWho, width - 122, -60, 110)
    place(panel.viewButton, 12, -94, width - 136)
    place(panel.fullWindow, width - 116, -94, 104)
    panel.viewMenu:SetWidth(width - 136)
    panel.counter:SetWidth(width - 24)
    place(panel.counter, 12, compact and -126 or -132)
    for _, text in ipairs({ panel.meta, panel.preview, panel.reply }) do text:SetWidth(width - 24) end
    local shift = compact and 20 or 0
    place(panel.candidateButton, 12, compact and -144 or -158, width - 24)
    panel.candidateMenu:SetWidth(width - 24)
    place(panel.meta, 12, compact and -176 or -190)
    place(panel.previewLabel, 12, -216 + shift)
    local previewTop = 236 - shift
    local available = height - previewTop - 158
    local previewHeight = math.floor(available * 0.62)
    place(panel.preview, 12, -previewTop)
    panel.preview:SetHeight(previewHeight)
    place(panel.reply, 12, -(previewTop + previewHeight + 6))
    panel.reply:SetHeight(available - previewHeight - 6)
    local third = (width - 48) / 3
    for i, control in ipairs({ panel.whisper, panel.invite, panel.skip }) do
        place(control, 12 + (i - 1) * (third + 12), -(height - 148), third)
    end
    local half = (width - 36) / 2
    place(panel.dnc, 12, -(height - 114), half)
    place(panel.restore, 24 + half, -(height - 114), half)
    place(panel.status, 12, -(height - 72), width - 40)
end

local function savePopoutGeometry(panel)
    if not popoutAllowed() or panel.owner ~= popoutOwner() then return end
    local point, _, relativePoint, x, y = panel:GetPoint()
    local db = database()
    db.popoutPosition = { point = point, relativePoint = relativePoint, x = x, y = y }
    db.popoutSize = { width = panel:GetWidth(), height = panel:GetHeight() }
end

local function buildPopout()
    local panel = CreateFrame("Frame", "GuildDBRecruitPopout", UIParent, "BackdropTemplate")
    GD.recruitPopout = panel
    panel:SetSize(380, 510)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:SetResizable(true)
    if panel.SetResizeBounds then panel:SetResizeBounds(320, 440, 900, 1000)
    else
        panel:SetMinResize(320, 440)
        panel:SetMaxResize(900, 1000)
    end
    panel:EnableMouse(true)
    panel:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    panel:Hide()
    panel.buttons = {}
    local drag = CreateFrame("Frame", nil, panel)
    drag:SetPoint("TOPLEFT")
    drag:SetPoint("TOPRIGHT", -42, 0)
    drag:SetHeight(34)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() panel:StartMoving() end)
    drag:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
        savePopoutGeometry(panel)
    end)
    panel.title = label(drag, "Recruiting", 12, -12, "GameFontNormal")
    panel.close = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.close:SetPoint("TOPRIGHT", -6, -6)
    panel.close:SetScript("OnClick", function() panel:Hide() end)
    GD:StyleCloseButton(panel.close)
    panel.queryLabel = label(panel, "Who level or range", 12, -40)
    panel.query = input(panel, 12, -60, 236, 150)
    local function action(text, x, y, width, callback, parent)
        local control = CreateFrame("Button", nil, parent or panel, "UIPanelButtonTemplate")
        control:SetPoint("TOPLEFT", x, y)
        control:SetSize(width, 26)
        control:SetText(text)
        control:SetScript("OnClick", function()
            if not popoutAllowed() or panel.owner ~= popoutOwner() then panel:Hide(); return end
            local _, message = callback()
            panel.feedback = message
            panel.feedbackUntil = time() + 6
            GD:RefreshRecruitPopout()
        end)
        panel.buttons[#panel.buttons + 1] = control
        return control
    end
    panel.searchWho = action("Search Who", 258, -60, 110, function()
        panel.query:ClearFocus()
        panel.viewMenu:Hide()
        panel.candidateMenu:Hide()
        local previousFilter = panel.filter
        panel.filter = "New"
        local ok, message = GD:SearchRecruits(panel.query:GetText())
        if not ok then panel.filter = previousFilter end
        return ok, message
    end)
    panel.searchWho:SetScript("OnEnter", function(control)
        GameTooltip:SetOwner(control, "ANCHOR_TOPLEFT")
        GameTooltip:SetText("Find uncontacted players")
        GameTooltip:AddLine("Searches exactly the level or range you enter. Only unguilded candidates within those levels are shown; New excludes anyone already contacted.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    panel.searchWho:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.query:SetScript("OnEnterPressed", function() panel.searchWho:GetScript("OnClick")() end)
    panel.query:SetScript("OnTextChanged", function()
        panel.candidateMenu:Hide()
        GD:RefreshRecruitPopout()
    end)
    panel.viewButton = action("All saved  v", 12, -94, 244, function()
        panel.candidateMenu:Hide()
        if panel.viewMenu:IsShown() then panel.viewMenu:Hide() else panel.viewMenu:Show() end
        return true
    end)
    panel.viewMenu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    local views = panel.viewMenu
    views:SetPoint("TOPLEFT", panel.viewButton, "BOTTOMLEFT", 0, -4)
    views:SetHeight((#statuses + 1) * 28 + 8)
    views:SetFrameStrata("TOOLTIP")
    views:SetClampedToScreen(true)
    views:EnableMouse(true)
    views:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    views:Hide()
    panel.viewOptions = {}
    for i, status in ipairs(statuses) do
        local option = action(status == "All" and "All saved" or status, 4, -4 - (i - 1) * 28, 176, function()
            if GD.recruitWhoPending and status ~= "New" then return false, "Wait for the current Who search to finish." end
            panel.filter = status
            -- New filters the active Who results, including a search still in flight.
            -- Switching the source here discards the pending reply before import.
            if status ~= "New" or not currentSearch() then GD:ShowRecruitSavedCandidates() end
            panel.selected, panel.feedback = nil, nil
            views:Hide()
            return true
        end, views)
        option:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * 28)
        panel.viewOptions[i] = option
    end
    panel.importWho = action("Import Who results", 4, -4 - #statuses * 28, 176, function()
        if GD.recruitWhoPending then return false, "Wait for the current Who search to finish." end
        local search = searchContext(panel.query:GetText())
        if not search then return false, "Enter a level or ascending range." end
        panel.filter = "New"
        views:Hide()
        return GD:ImportRecruitWho(search)
    end, views)
    panel.importWho:SetPoint("TOPRIGHT", -4, -4 - #statuses * 28)
    views:SetScript("OnUpdate", function()
        if not panel:IsShown() or not popoutAllowed() or panel.owner ~= popoutOwner() then views:Hide(); return end
        if IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
            and not views:IsMouseOver() and not panel.viewButton:IsMouseOver() then views:Hide() end
    end)
    panel.fullWindow = action("Full UI", 212, -94, 156, function()
        GD.activeTab = "Recruitment"
        GD:Open()
        local main = GD.frame and GD.frame.recruitment
        if main then main.query:SetText(panel.query:GetText()); main.selected = panel.selected; main.filter = panel.filter or "All"; GD:RefreshUI() end
        panel:Hide()
        return true
    end)
    panel.counter = label(panel, "", 12, -136)
    panel.counter:SetWidth(262)
    panel.candidateButton = action("", 12, -158, 356, function()
        panel.viewMenu:Hide()
        local menu = panel.candidateMenu
        if menu:IsShown() then menu:Hide()
        else
            local records = GD:GetRecruitCandidates(panel.filter or "All", "", panel.query:GetText())
            menu.offset = 0
            for i, entry in ipairs(records) do
                if entry.id == panel.selected then menu.offset = math.max(0, i - 3); break end
            end
            menu:Show()
        end
        return true
    end)
    panel.name = panel.candidateButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.name:SetPoint("LEFT", 10, 0)
    panel.name:SetPoint("RIGHT", -26, 0)
    panel.name:SetJustifyH("LEFT")
    panel.name:SetWordWrap(false)
    panel.candidateArrow = panel.candidateButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.candidateArrow:SetPoint("RIGHT", -10, 0)
    panel.candidateArrow:SetText("v")
    panel.candidateMenu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    local menu = panel.candidateMenu
    menu:SetPoint("TOPLEFT", panel.candidateButton, "BOTTOMLEFT", 0, -4)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetClampedToScreen(true)
    menu:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    menu:EnableMouse(true)
    menu:EnableMouseWheel(true)
    menu:Hide()
    menu.rows = {}
    local function wheel(_, delta)
        menu.offset = (menu.offset or 0) - delta
        GD:RefreshRecruitPopout()
    end
    menu:SetScript("OnMouseWheel", wheel)
    for i = 1, 6 do
        local row = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
        row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 40)
        row:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * 40)
        row:SetHeight(38)
        row.name = label(row, "", 8, -5, "GameFontNormal")
        row.name:SetPoint("TOPRIGHT", -8, -5)
        row.name:SetWordWrap(false)
        row.status = label(row, "", 8, -22)
        row.status:SetPoint("TOPRIGHT", -8, -22)
        row.status:SetWordWrap(false)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", wheel)
        row:SetScript("OnClick", function(control)
            if not popoutAllowed() or panel.owner ~= popoutOwner() then panel:Hide(); return end
            local records = GD:GetRecruitCandidates(panel.filter or "All", "", panel.query:GetText())
            for _, entry in ipairs(records) do
                if entry.id == control.id then panel.selected = entry.id; panel.feedback = nil; break end
            end
            menu:Hide()
            GD:RefreshRecruitPopout()
        end)
        menu.rows[i] = row
    end
    menu.hint = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    menu.hint:SetPoint("BOTTOM", 0, 7)
    menu:SetScript("OnUpdate", function()
        if not panel:IsShown() or not popoutAllowed() or panel.owner ~= popoutOwner() then menu:Hide(); return end
        if IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
            and not menu:IsMouseOver() and not panel.candidateButton:IsMouseOver() then menu:Hide() end
    end)
    menu:SetScript("OnHide", function()
        for _, row in ipairs(menu.rows) do row.id = nil; row.name:SetText(""); row.status:SetText("") end
    end)
    panel.meta = label(panel, "", 12, -190)
    panel.meta:SetWidth(356)
    panel.meta:SetWordWrap(false)
    panel.previewLabel = label(panel, "Whisper preview", 12, -216, "GameFontNormal")
    panel.preview = label(panel, "", 12, -236)
    panel.preview:SetWidth(356)
    panel.preview:SetHeight(68)
    panel.preview:SetJustifyV("TOP")
    panel.preview:SetWordWrap(true)
    panel.reply = label(panel, "", 12, -310)
    panel.reply:SetWidth(356)
    panel.reply:SetHeight(42)
    panel.reply:SetJustifyV("TOP")
    panel.reply:SetWordWrap(true)
    panel.whisper = action("Whisper", 12, -362, 110, function() return GD:ContactRecruit(panel.selected, "whisper") end)
    panel.invite = action("Guild invite", 134, -362, 112, function() return GD:ContactRecruit(panel.selected, "invite") end)
    panel.skip = action("Skip / Next", 258, -362, 110, function()
        local ok, message = GD:SetRecruitStatus(panel.selected, "Skipped")
        if ok then GD:StepRecruitPopout(1) end
        return ok, message
    end)
    panel.dnc = action("Do Not Contact", 12, -396, 174, function() return GD:SetRecruitStatus(panel.selected, "Do Not Contact") end)
    panel.restore = action("Restore", 198, -396, 170, function() return GD:SetRecruitStatus(panel.selected, "New") end)
    panel.status = label(panel, "", 12, -438)
    panel.status:SetWidth(356)
    panel.status:SetHeight(58)
    panel.status:SetJustifyV("TOP")
    panel.status:SetWordWrap(true)
    panel.resize = CreateFrame("Button", nil, panel)
    panel.resize:SetSize(20, 20)
    panel.resize:SetPoint("BOTTOMRIGHT", -2, 2)
    panel.resize:EnableMouse(true)
    panel.resize.grip = panel.resize:CreateTexture(nil, "ARTWORK")
    panel.resize.grip:SetAllPoints()
    panel.resize.grip:SetTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
    panel.resize:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then panel.resizing = true; panel:StartSizing("BOTTOMRIGHT") end
    end)
    panel.resize:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            panel:StopMovingOrSizing()
            panel.resizing = nil
            savePopoutGeometry(panel)
        end
    end)
    panel.resize:SetScript("OnEnter", function(control)
        GameTooltip:SetOwner(control, "ANCHOR_TOPLEFT")
        GameTooltip:SetText("Drag to resize")
        GameTooltip:Show()
    end)
    panel.resize:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel:SetScript("OnSizeChanged", function() layoutPopout(panel) end)
    layoutPopout(panel)
    panel:SetScript("OnUpdate", function(_, elapsed)
        panel.elapsed = (panel.elapsed or 0) + elapsed
        if panel.elapsed >= 1 then panel.elapsed = 0; GD:RefreshRecruitPopout() end
    end)
    panel:SetScript("OnHide", function()
        panel.viewMenu:Hide()
        panel.candidateMenu:Hide()
        panel:StopMovingOrSizing()
        if panel.resizing then savePopoutGeometry(panel); panel.resizing = nil end
        GameTooltip:Hide()
        panel.query:ClearFocus()
        local mainShown = GD.frame and GD.frame:IsShown() and GD.activeTab == "Recruitment"
        if not mainShown then GD.recruitSearch, GD.recruitSavedView = nil, nil end
    end)
    UISpecialFrames = UISpecialFrames or {}
    table.insert(UISpecialFrames, "GuildDBRecruitPopout")
    return panel
end

function GD:RefreshRecruitPopoutAppearance()
    local panel = self.recruitPopout
    if not panel then return end
    local colors = self:GetAppearanceColors()
    self:StyleSurface(panel, "window")
    self:StyleCloseButton(panel.close)
    for _, control in ipairs(panel.buttons) do self:StyleButton(control, control == panel.whisper and "primary" or nil) end
    self:StyleSurface(panel.viewMenu)
    for i, option in ipairs(panel.viewOptions) do self:StyleButton(option, statuses[i] == (panel.filter or "All") and "primary" or nil) end
    panel.title:SetTextColor(unpack(colors.accent))
    panel.candidateArrow:SetTextColor(unpack(colors.accent))
    panel.previewLabel:SetTextColor(unpack(colors.accent))
    panel.queryLabel:SetTextColor(unpack(colors.muted))
    panel.resize.grip:SetVertexColor(unpack(colors.accent))
    local record = candidate(panel.selected)
    panel.name:SetTextColor(unpack(classColor(record, colors.text)))
    for _, text in ipairs({ panel.counter, panel.meta, panel.preview, panel.reply, panel.status }) do text:SetTextColor(unpack(colors.muted)) end
    panel.meta:SetTextColor(unpack(statusColor(record, colors.muted)))
    panel.query:SetBackdropColor(unpack(colors.panel))
    panel.query:SetTextColor(unpack(colors.text))
    panel.query:SetGuildDBFocusState(panel.query:HasFocus())
    if panel.candidateMenu:IsShown() then
        local records = self:GetRecruitCandidates(panel.filter or "All", "", panel.query:GetText())
        refreshPopoutChoices(panel, records)
    end
end

function GD:RefreshRecruitPopout()
    local panel = self.recruitPopout
    if not panel or not panel:IsShown() then return end
    if not popoutAllowed() or panel.owner ~= popoutOwner() then panel:Hide(); return end
    local db = database()
    local records, _, empty = self:GetRecruitCandidates(panel.filter or "All", "", panel.query:GetText())
    local index
    for i, entry in ipairs(records) do if entry.id == panel.selected then index = i; break end end
    if not index then index = #records > 0 and 1 or nil; panel.selected = index and records[index].id end
    local record = index and records[index].record
    self:RefreshRecruitPopoutAppearance()
    panel.counter:SetText((index or 0) .. " / " .. #records .. (panel.filter == "Contacted" and " contacts" or "") .. " | " .. today(db) .. "/" .. DAILY_LIMIT .. " today")
    panel.viewButton:SetText(((panel.filter or "All") == "All" and "All saved" or panel.filter) .. "  v")
    local search = currentSearch()
    panel.name:SetText(record and self:Display(record.name)
        or (self.recruitWhoPending and "Waiting for Who results..."
        or (search and search.state == "complete" and "No matching candidates" or "Choose Search Who to find players")))
    panel.meta:SetText(record and self:Display(statusText(record) .. " - " .. (record.level or "?") .. " " .. (record.class or "")) or empty)
    panel.preview:SetText(self:Display(expand(db.message, record and record.name or "{name}")))
    panel.reply:SetText(record and record.reply and self:Display("Reply: " .. record.reply) or "Replies from contacted candidates appear here.")
    local whisper = self:GetRecruitContactBlock(panel.selected, "whisper")
    local invite = self:GetRecruitContactBlock(panel.selected, "invite")
    panel.whisper:SetEnabled(record ~= nil and whisper == nil)
    panel.invite:SetEnabled(record ~= nil and invite == nil)
    panel.skip:SetEnabled(record ~= nil and record.status ~= "Do Not Contact")
    panel.dnc:SetEnabled(record ~= nil and record.status ~= "Do Not Contact")
    panel.restore:SetEnabled(record ~= nil and record.status ~= "New")
    panel.candidateButton:SetEnabled(#records > 0)
    panel.searchWho:SetEnabled(self.recruitWhoPending == nil)
    panel.searchWho:SetText(self.recruitWhoPending and "Searching..." or "Search Who")
    panel.status:SetText((panel.feedback and (panel.feedbackUntil or 0) > time()) and panel.feedback
        or (record and ("Whisper: " .. (whisper or "Ready") .. "\nInvite: " .. (invite or "Ready"))
        or (search and search.state == "complete" and search.message) or empty))
end

function GD:ShowRecruitPopout()
    if not popoutAllowed() then return false, "Recruitment is available to enabled GM/rank 1 recruiters only." end
    local panel = self.recruitPopout or buildPopout()
    local owner, db = popoutOwner(), database()
    if panel.owner ~= owner then panel.selected, panel.feedback, panel.filter = nil, nil, "New" end
    panel.owner = owner
    local main = self.frame and self.frame.recruitment
    local search = currentSearch()
    panel.query:SetText(search and search.query or (main and main.owner == owner and main.query:GetText()) or "50-60")
    if main and main.owner == owner then panel.selected = main.selected end
    if not search then self:ShowRecruitSavedCandidates() end
    local size = db.popoutSize
    panel:SetSize(math.max(320, math.min(900, tonumber(size and size.width) or 380)),
        math.max(440, math.min(1000, tonumber(size and size.height) or 510)))
    local position = db.popoutPosition
    panel:ClearAllPoints()
    if position then panel:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
    else panel:SetPoint("CENTER") end
    panel:Show()
    self:RefreshRecruitPopout()
    if self.frame then self.frame:Hide() end
    return true, "Compact recruiting opened. Drag its title to move it or its bottom-right corner to resize."
end

GD:RegisterCommand("recruit", function(rest)
    if not allowed() then print("GuildDB: Recruitment is available to the GM and rank 1 officers only."); return end
    if GD.GetSetting and not GD:GetSetting("feature:Recruitment") then print("GuildDB: Recruitment is disabled in officer settings."); return end
    if clean(rest, 30):lower() == "popout" then GD:ShowRecruitPopout(); return end
    GD.activeTab = "Recruitment"
    GD:Open()
end)

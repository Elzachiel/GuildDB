-- Officer-managed DKP activation, awards, deductions, standings and history.
local _, GD = ...
function GD:GetDKPTime()
    local stamp = GetServerTime and GetServerTime()
    if type(stamp) == "number" and stamp == stamp and stamp > 0 then return math.floor(stamp) end
    return time()
end
function GD:GetDKPItemInfo(value)
    local query = C_Item and C_Item.GetItemInfo or GetItemInfo
    if query then return query(value) end
end
function GD:GetDKPItemInfoInstant(value)
    local query = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if query then return query(value) end
end
function GD:IsDKPSoloTesting()
    return self.dkpSolo ~= nil and self.dkpSolo.guildBucket == self.bucket
end
function GD:GetDKPBucket()
    return self:IsDKPSoloTesting() and self.dkpSolo.data or self.bucket
end
function GD:SendDKPRecord(...)
    if not self:IsDKPSoloTesting() then return self:SendRecord(...) end
end
function GD:RegisterDKPRecordHandler(kind, callback, limit)
    self:RegisterRecordHandler(kind, function(...)
        if not self:IsDKPSoloTesting() then return callback(...) end
        local incoming = self.dkpSolo.incoming
        incoming[#incoming + 1] = { callback = callback, args = { ... } }
    end, limit)
end

function GD:ToggleDKPSoloTest()
    if self:IsDKPSoloTesting() then
        local incoming = self.dkpSolo.incoming
        self.dkpSolo = nil
        for _, record in ipairs(incoming) do record.callback(unpack(record.args)) end
        if self.RequestDKPSettings then self:RequestDKPSettings() end
        if self.RequestDKPAwards then self:RequestDKPAwards() end
    else
        if not self:CanConfigureDKP() then return false, "Only the GM or rank 1 officers can use Solo Test." end
        local member = self:GetDKPGuildMember(self:PlayerName())
        if not member then return false, "Wait for your guild roster to load, then try Solo Test again." end
        local prices = {}
        for item, record in pairs(self.bucket.dkpStartingBids or {}) do
            prices[item] = {}; for k, v in pairs(record) do prices[item][k] = v end
        end
        self.dkpSolo = { guildBucket = self.bucket, incoming = {}, data = { dkpConfig = { enabled = true },
            dkpBalances = {}, dkpAwards = {}, dkpStartingBids = prices, dkpSystems = {}, dkpAccounts = {} } }
        self.dkpLastBidRequest, self.dkpBidStatus = nil, nil
        self:GrantDKPStartingBalance({ member })
        self.activeTab = "DKP"
    end
    if self.RefreshUI then self:RefreshUI() end
    if self.RefreshDKPAuctionPopup then self:RefreshDKPAuctionPopup() end
    return true, self:IsDKPSoloTesting() and "SOLO TEST enabled: 1,000 temporary DKP. No raid or level requirement; nothing syncs to the guild. /gd dkptest exits."
        or "Solo Test ended. Temporary data discarded; guild DKP restored."
end
GD:RegisterCommand("dkptest", function() local _, message = GD:ToggleDKPSoloTest(); if message then print("GuildDB: " .. message) end end)

GD:RegisterBucket("dkpConfig", function() return {} end)
GD:RegisterBucket("dkpBalances", function() return {} end)
GD:RegisterBucket("dkpAwards", function() return {} end)
GD:RegisterBucket("dkpStartingBids", function() return {} end)

local function nameKey(name)
    return tostring(name or ""):lower():match("^%s*(.-)%s*$")
end

local STARTING_DKP, STARTING_REASON = 1000, "One-time starting balance"
local gearPrices = {
    { label = "Neck / rings", amount = 100 },
    { label = "Cloak / wrists / waist / feet / wand / thrown", amount = 150 },
    { label = "Head / chest / shoulders / legs / hands", amount = 200 },
    { label = "One-hand weapons / shields / off-hands", amount = 250 },
    { label = "Two-hand / ranged weapons", amount = 350 },
    { label = "Trinkets", amount = 300 },
}
local gearSlots = {
    INVTYPE_NECK = 1, INVTYPE_FINGER = 1,
    INVTYPE_CLOAK = 2, INVTYPE_WRIST = 2, INVTYPE_WAIST = 2, INVTYPE_FEET = 2, INVTYPE_THROWN = 2,
    INVTYPE_HEAD = 3, INVTYPE_CHEST = 3, INVTYPE_ROBE = 3, INVTYPE_SHOULDER = 3, INVTYPE_LEGS = 3, INVTYPE_HAND = 3,
    INVTYPE_WEAPON = 4, INVTYPE_WEAPONMAINHAND = 4, INVTYPE_WEAPONOFFHAND = 4, INVTYPE_SHIELD = 4, INVTYPE_HOLDABLE = 4,
    INVTYPE_2HWEAPON = 5, INVTYPE_RANGED = 5, INVTYPE_RANGEDRIGHT = 5, INVTYPE_TRINKET = 6,
}
local raidRewards = {
    { label = "Boss kill - 20 DKP", amount = 20, reason = "Boss kill", event = "boss" },
    { label = "Guild-first boss kill - 30 DKP total", amount = 30, reason = "Guild-first boss kill (20 + 10 bonus)", event = "boss" },
    { label = "On time and ready - 10 DKP", amount = 10, reason = "On time and ready", event = "ontime" },
    { label = "Stayed until raid end - 10 DKP", amount = 10, reason = "Stayed until scheduled raid end", event = "finish" },
}

function GD:GetDKPRewardValues()
    return { starting = STARTING_DKP, boss = 20, firstKillBonus = 10, onTime = 10, raidEnd = 10 }
end

function GD:ShowDKPRules()
    if not self:IsDKPEnabled() then return end
    local fields = {}
    for _, rule in ipairs(gearPrices) do
        fields[#fields + 1] = { label = rule.label, value = rule.amount .. " DKP", readOnly = true }
    end
    fields[#fields + 1] = { label = "Raid rewards (officer-reviewed awards)", value = "Starting grant: 1,000 DKP once per character\nBoss kill: 20 DKP; guild-first kill: 30 total\nOn time: 10 DKP; stayed until end: 10 DKP", multiline = true, readOnly = true, max = 500 }
    self.ShowInputForm("Guild DKP Prices and Rewards", fields, function() return true end, "Close")
end

local function rosterMember(name)
    if type(name) ~= "string" or name == "" or not GetNumGuildMembers or not GetGuildRosterInfo then return end
    local wanted, short = nameKey(name), name:match("^([^%s%-]+)$")
    local fallback, matches = nil, 0
    for i = 1, GetNumGuildMembers(true) do
        local member, _, rank = GetGuildRosterInfo(i)
        if member then
            if nameKey(member) == wanted then return member, tonumber(rank) end
            local base = member:match("^([^%-]+)")
            if not name:find("-", 1, true) and (nameKey(base) == wanted
                or (short and nameKey(member:match("^([^%s%-]+)")) == wanted)) then
                fallback, matches = { member, tonumber(rank) }, matches + 1
            end
        end
    end
    if matches == 1 then return unpack(fallback) end
end

function GD:GetDKPGuildMember(name)
    return rosterMember(name)
end

local classRoster, classBucket, classCount
function GD:GetDKPClassColor(name)
    local count = GetNumGuildMembers(true)
    if not classRoster or classBucket ~= self:GetDKPBucket() or classCount ~= count then
        classRoster, classBucket, classCount = {}, self:GetDKPBucket(), count
        for index = 1, count do
            local member, _, _, _, localized, _, _, _, _, _, classFile = GetGuildRosterInfo(index)
            if not classFile and localized then
                for token, label in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do if label == localized then classFile = token; break end end
                if not classFile then for token, label in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do if label == localized then classFile = token; break end end end
                classFile = classFile or localized:upper()
            end
            if member then classRoster[nameKey(member)] = classFile end
        end
    end
    local canonical = classRoster[nameKey(name)] and name or self:GetDKPGuildMember(name)
    local token = canonical and classRoster[nameKey(canonical)]
    return token and ((CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[token]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token])) or nil
end
function GD:DKPCharacterText(name)
    local value, color = self:Display(name), self:GetDKPClassColor(name)
    if not color then return value end
    local function byte(n) return math.floor(math.max(0, math.min(1, n)) * 255 + .5) end
    return string.format("|cff%02x%02x%02x%s|r", byte(color.r), byte(color.g), byte(color.b), value)
end
GD:RegisterEventHandler("GUILD_ROSTER_UPDATE", function() classRoster = nil end)

function GD:CanConfigureDKP()
    return self:GetDKPBucket() ~= nil and self:CanManage()
end

function GD:IsDKPEnabled()
    return self.guildName ~= nil and self:GetDKPBucket() ~= nil and self:GetDKPBucket().dkpConfig ~= nil
        and self:GetDKPBucket().dkpConfig.enabled == true
end

local function refresh()
    if GD.dkpImporting then return end
    if not GD:IsDKPEnabled() and GD.activeTab == "DKP" then GD.activeTab = "Home" end
    if GD.RefreshUI then GD:RefreshUI() end
end

function GD:SetDKPEnabled(enabled)
    if not self:CanConfigureDKP() then return false, "Only the GM or rank 1 officers can enable or disable DKP during testing." end
    if type(enabled) ~= "boolean" then return false, "Choose whether DKP is enabled or disabled." end
    local previous = self:GetDKPBucket().dkpConfig or {}
    local record = { enabled = enabled, ts = math.max(GD:GetDKPTime(), (tonumber(previous.ts) or 0) + 1), by = self:PlayerName() }
    self:GetDKPBucket().dkpConfig = record
    self:SendDKPRecord("DKE", "enabled", record.ts, record.by, enabled and "1" or "0")
    if enabled and self.RequestDKPAwards then self:RequestDKPAwards() end
    refresh()
    return true, enabled and "DKP enabled for this guild." or "DKP disabled. Saved DKP data has been preserved."
end

-- Only GM/officer senders can publish or relay DKP settings during testing.
-- Relays keep the original version so a stale officer cannot overwrite it.
local pending = {}
local function receive(id, ts, author, content, sender)
    if not GD:GetDKPBucket() or id ~= "enabled" or (content ~= "0" and content ~= "1")
        or type(ts) ~= "number" or ts ~= ts or ts <= 0 or ts ~= math.floor(ts) or ts > GD:GetDKPTime() + 60 then return end
    local authorName, authorRank = rosterMember(author)
    local senderName, senderRank = rosterMember(sender)
    if (authorRank and authorRank > 1) or (senderRank and senderRank > 1) then return end
    if not authorName or not senderName then
        if #pending < 30 then pending[#pending + 1] = {
            id = id, ts = ts, author = author, content = content, sender = sender, bucket = GD:GetDKPBucket(),
        } end
        return
    end
    if not authorRank or not senderRank or authorRank > 1 or senderRank > 1 then return end
    local current = GD:GetDKPBucket().dkpConfig or {}
    local currentAuthor = rosterMember(current.by) or current.by
    if ts < (tonumber(current.ts) or 0) or (ts == (tonumber(current.ts) or 0)
        and nameKey(authorName) <= nameKey(currentAuthor)) then return end
    GD:GetDKPBucket().dkpConfig = { enabled = content == "1", ts = ts, by = authorName }
    if content == "1" and GD.RequestDKPAwards then GD:RequestDKPAwards() end
    refresh()
end
GD:RegisterDKPRecordHandler("DKE", receive, 1)

local function sendConfig()
    if not GD:CanConfigureDKP() then return end
    local record = GD:GetDKPBucket().dkpConfig or {}
    -- A newly installed officer client must request the guild's saved choice,
    -- never publish its default-off state over an existing enabled setting.
    if not record.ts then return end
    GD:SendDKPRecord("DKE", "enabled", record.ts, record.by, record.enabled and "1" or "0")
end
GD:RegisterHistoryProvider(sendConfig, false)

local requestBucket, lastRequest, replyBucket, lastReply
function GD:RequestDKPSettings(immediate)
    if not self.guildName or not self:GetDKPBucket() then return false end
    if requestBucket ~= self:GetDKPBucket() then requestBucket, lastRequest = self:GetDKPBucket(), nil end
    if lastRequest and GD:GetDKPTime() - lastRequest < (immediate and 2 or 10) then return false end
    lastRequest = GD:GetDKPTime()
    if self:IsDKPEnabled() and self.RequestDKPAwards then self:RequestDKPAwards() end
    if self:CanConfigureDKP() and self:GetDKPBucket().dkpConfig and self:GetDKPBucket().dkpConfig.ts then sendConfig()
    else self:SendDKPRecord("DKQ", "enabled", GD:GetDKPTime(), self:PlayerName(), "") end
    return true
end
GD:RegisterDKPRecordHandler("DKQ", function(id, ts, author, content, sender)
    if id ~= "enabled" or content ~= "" or not GD:CanConfigureDKP() then return end
    local member = rosterMember(sender)
    if not member then return end
    if replyBucket ~= GD:GetDKPBucket() then replyBucket, lastReply = GD:GetDKPBucket(), nil end
    if lastReply and GD:GetDKPTime() - lastReply < 2 then return end
    lastReply = GD:GetDKPTime()
    sendConfig()
end, 1)

local sessionBucket
local function startSync()
    if not GD:GetDKPBucket() then sessionBucket = nil; pending = {}; return end
    if sessionBucket == GD:GetDKPBucket() then return end
    sessionBucket, pending = GD:GetDKPBucket(), {}
    local bucket = GD:GetDKPBucket()
    GD:RequestDKPSettings()
    if C_Timer and C_Timer.After then
        for _, delay in ipairs({ 3, 12, 30, 60 }) do
            C_Timer.After(delay, function()
                if GD:GetDKPBucket() == bucket and sessionBucket == bucket then GD:RequestDKPSettings() end
            end)
        end
    end
end
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_GUILD_UPDATE", "PLAYER_ENTERING_WORLD" }) do
    GD:RegisterEventHandler(event, startSync)
end
GD:RegisterEventHandler("GUILD_ROSTER_UPDATE", function()
    local records = pending
    pending = {}
    for _, record in ipairs(records) do
        if record.bucket == GD:GetDKPBucket() then receive(record.id, record.ts, record.author, record.content, record.sender) end
    end
    local config = GD:GetDKPBucket() and GD:GetDKPBucket().dkpConfig
    if GD:GetDKPBucket() and (not config or not config.ts) then GD:RequestDKPSettings() end
end)

local function rawBalance(name)
    local balances = GD:GetDKPBucket() and GD:GetDKPBucket().dkpBalances or {}
    local value = balances[nameKey(name)]
    if type(value) ~= "number" or value ~= value or math.abs(value) > 9007199254740991 or value ~= math.floor(value) then return 0 end
    return value
end

local function balanceFor(name)
    return rawBalance(GD:GetDKPGuildMember(name) or name)
end

local function awardContent(record)
    return table.concat({ record.member, tostring(math.abs(record.amount)), record.reason }, "\n")
end

local function validReason(reason)
    return type(reason) == "string" and #reason <= 160 and not reason:find("%c") and reason:find("%S") ~= nil
end

local function applyAward(record, quiet)
    local awards = GD:GetDKPBucket().dkpAwards or {}
    if awards[record.id] then
        -- Concurrent starting grants share one ID and amount. Resolve their
        -- history metadata consistently without ever crediting the grant twice.
        local previous = awards[record.id]
        if record.id:sub(1, 10) == "dkp:start:" and (record.ts < previous.ts
            or (record.ts == previous.ts and nameKey(record.by) < nameKey(previous.by))) then
            awards[record.id] = record
            if not quiet then refresh() end
        end
        return false
    end
    local balance = balanceFor(record.member)
    if math.abs(balance + record.amount) > 9007199254740991 then return false end
    -- Signed adjustments commute, even when officers act concurrently or history
    -- arrives out of order. Keep negative balances rather than clamping away debt.
    GD:GetDKPBucket().dkpAwards = awards
    GD:GetDKPBucket().dkpBalances = GD:GetDKPBucket().dkpBalances or {}
    awards[record.id] = record
    GD:GetDKPBucket().dkpBalances[nameKey(record.member)] = rawBalance(record.member) + record.amount
    if GD.OnDKPLedgerChanged then GD:OnDKPLedgerChanged() end
    if not quiet then refresh() end
    return true
end

function GD:ApplyDKPSystemTransaction(record, quiet)
    record.system = true
    return applyAward(record, quiet)
end

function GD:UpdateDKPDerivedTransaction(record)
    local previous = (self:GetDKPBucket().dkpAwards or {})[record.id]
    if previous and not previous.system then return false end
    local oldAmount = previous and previous.amount or 0
    if previous and oldAmount == record.amount then return false end
    self:GetDKPBucket().dkpAwards[record.id] = record
    record.system = true
    self:GetDKPBucket().dkpBalances[nameKey(record.member)] = rawBalance(record.member) + record.amount - oldAmount
    return true
end

function GD:ValidateDKPAward(member, amount, reason, deduction)
    if not self:IsDKPEnabled() then return false, "Enable DKP for this guild first." end
    if not self:CanConfigureDKP() then return false, "Only the GM or rank 1 officers can adjust DKP." end
    local canonical = rosterMember(member)
    if not canonical then return false, "Select a current guild member. Refresh the guild roster if necessary." end
    amount = tonumber(amount)
    if not amount or amount ~= math.floor(amount) or amount < 1 or amount > 1000000 then
        return false, "Enter a whole-number amount from 1 to 1,000,000 DKP."
    end
    if not validReason(reason) then return false, "Enter a reason of 1-160 characters on one line." end
    return true, canonical, deduction and -amount or amount, reason:match("^%s*(.-)%s*$")
end

local function adjustDKP(self, member, amount, reason, deduction)
    local ok, canonical, points, note = self:ValidateDKPAward(member, amount, reason, deduction)
    if not ok then return false, canonical end
    local author = rosterMember(self:PlayerName()) or self:PlayerName()
    local sequence = (tonumber(self:GetDKPBucket().dkpAwardSequence) or 0) + 1
    local id = "dkp:" .. nameKey(author):gsub("[^%w]", ""):sub(1, 40) .. ":" .. GD:GetDKPTime() .. ":" .. sequence .. ":" .. math.random(100000, 999999)
    if (self:GetDKPBucket().dkpAwards or {})[id] then return false, "Award ID already exists. Try again." end
    local record = { id = id, ts = GD:GetDKPTime(), by = author, member = canonical, amount = points, reason = note }
    if not applyAward(record) then return false, "The award could not be applied." end
    self:GetDKPBucket().dkpAwardSequence = sequence
    self:SendDKPRecord(deduction and "DKD" or "DKA", id, record.ts, author, awardContent(record))
    return true, math.abs(points) .. (deduction and " DKP taken from " or " DKP awarded to ") .. self:Display(canonical) .. ".", id
end

function GD:AwardDKP(member, amount, reason)
    return adjustDKP(self, member, amount, reason, false)
end

function GD:DeductDKP(member, amount, reason)
    return adjustDKP(self, member, amount, reason, true)
end

local function startingID(member)
    return "dkp:start:" .. nameKey(member)
end

function GD:HasDKPStartingGrant(member)
    local canonical = rosterMember(member)
    if not canonical then return false end
    local account = nameKey(self.GetDKPAccount and self:GetDKPAccount(canonical) or canonical)
    for id, record in pairs(self:GetDKPBucket() and self:GetDKPBucket().dkpAwards or {}) do
        if id:sub(1, 10) == "dkp:start:" and nameKey(self.GetDKPAccount and self:GetDKPAccount(record.member) or record.member) == account then return true end
    end
    return false
end

function GD:GrantDKPStartingBalance(members)
    if not self:IsDKPEnabled() or not self:CanConfigureDKP() then return false, "Only the GM or rank 1 officers can grant starting DKP while DKP is enabled." end
    if type(members) ~= "table" or #members == 0 then return false, "Select at least one guild member." end
    local records, seen, skipped = {}, {}, 0
    local author, ts = rosterMember(self:PlayerName()) or self:PlayerName(), GD:GetDKPTime()
    for _, member in ipairs(members) do
        local ok, canonical = self:ValidateDKPAward(member, STARTING_DKP, STARTING_REASON)
        if not ok then return false, canonical end
        canonical = self.GetDKPAccount and self:GetDKPAccount(canonical) or canonical
        local id = startingID(canonical)
        if #id > 100 then return false, "A selected member's name is too long for a starting grant." end
        if not seen[id] then
            seen[id] = true
            if self:HasDKPStartingGrant(canonical) then skipped = skipped + 1
            else
                if balanceFor(canonical) + STARTING_DKP > 9007199254740991 then return false, "A selected member's DKP balance is too large." end
                records[#records + 1] = { id = id, member = canonical, ts = ts, by = author, amount = STARTING_DKP, reason = STARTING_REASON }
            end
        end
    end
    if #records == 0 then return false, "All selected members already received their starting grant." end
    for _, record in ipairs(records) do applyAward(record, true) end
    for _, record in ipairs(records) do self:SendDKPRecord("DKA", record.id, record.ts, record.by, awardContent(record)) end
    refresh()
    return true, "Granted 1,000 starting DKP to " .. #records .. " members. Already granted: " .. skipped .. "."
end

function GD:ShowDKPStartingGrantForm()
    if not self:IsDKPEnabled() or not self:CanConfigureDKP() then return end
    local bucket, members = self:GetDKPBucket(), {}
    for _, row in ipairs(self:GetDKPStandings()) do
        if not self:HasDKPStartingGrant(row.name) then members[#members + 1] = row.name end
    end
    table.sort(members, function(a, b) return nameKey(a) < nameKey(b) end)
    if #members == 0 then print("GuildDB: No eligible guild members. Refresh the guild roster if necessary."); return end
    self.ShowInputForm("Starting DKP", {
        { label = "Grant", value = "1,000 DKP once per selected character; existing points are kept.", readOnly = true, max = 100 },
        { label = "Select raiders to receive starting DKP (exclude their alts)", checklist = members, value = {} },
    }, function(values)
        if self:GetDKPBucket() ~= bucket then return false, "Your guild changed. Reopen Starting DKP." end
        if not self:IsDKPEnabled() or not self:CanConfigureDKP() then return false, "DKP access changed. Reopen Starting DKP." end
        local selected, seen = {}, {}
        for _, name in ipairs(values[2] or {}) do
            local canonical = rosterMember(name)
            if not canonical then return false, "A selected member left the guild. Reopen Starting DKP." end
            if not seen[nameKey(canonical)] then
                selected[#selected + 1] = canonical
                seen[nameKey(canonical)] = true
            end
        end
        if #selected == 0 then return false, "Select at least one raider." end
        local used = false
        self.ShowInputForm("Confirm Starting DKP", {
            { label = "Starting grant", value = "Add 1,000 DKP to each selected character. Already-granted members are skipped. This does not reset balances.", multiline = true, readOnly = true, max = 300 },
            { label = "Recipients", checklist = selected, value = selected, readOnly = true },
        }, function()
            if used then return false, "This starting grant has already been applied." end
            if self:GetDKPBucket() ~= bucket then return false, "Your guild changed. Reopen Starting DKP." end
            local success, message = self:GrantDKPStartingBalance(selected)
            if success then used = true end
            return success, message
        end, "Grant DKP")
        return true
    end, "Review")
end

local function bidItem(value)
    if type(value) ~= "string" or #value > 500 or value:find("%c") then return end
    value = value:match("^%s*(.-)%s*$")
    local link = value:gsub("^|cn[^:]+:", ""):gsub("^|c%x%x%x%x%x%x%x%x", ""):gsub("|r$", "")
    local id, label = link:match("^|Hitem:(%d+)[^|]*|h%[([^|]+)%]|h$")
    id = tonumber(id or value:match("^item:(%d+):") or value:match("^item:(%d+)$") or value:match("^(%d+)$"))
    if not id or id < 1 or id > 2147483647 then return end
    if label then
        GD.dkpItemLinks = GD.dkpItemLinks or {}
        GD.dkpItemLinks[tostring(id)] = { link = value, name = label }
    end
    local cached = GD:GetDKPItemInfo(id)
    if not cached and label then cached = GD:GetDKPItemInfo(value) end
    label = cached or label or ("Item " .. id)
    label = label:gsub("[%c|]", ""):sub(1, 100)
    if label == "" then label = "Item " .. id end
    return tostring(id), label
end

function GD:GetDKPItemIdentity(value)
    return bidItem(tostring(value or ""))
end

function GD:GetDKPStartingBid(item)
    local id = bidItem(tostring(item or ""))
    local record = self:GetDKPBucket() and self:GetDKPBucket().dkpStartingBids and self:GetDKPBucket().dkpStartingBids[id]
    if record then return record.amount, record, "item" end
    if not id then return end
    local equipLoc, classID, subClassID
    do
        local name, _, _, _, _, _, _, _, slot, _, _, class, subclass = self:GetDKPItemInfo(tonumber(id))
        if name then equipLoc, classID, subClassID = slot, class, subclass end
    end
    if not equipLoc then
        local _, _, _, slot, _, class, subclass = self:GetDKPItemInfoInstant(tonumber(id))
        equipLoc, classID, subClassID = slot, class, subclass
    end
    local category = gearSlots[equipLoc]
    -- Wands share a ranged inventory slot with guns/crossbows. Classify by
    -- numeric weapon subclass so this works with localized item names too.
    if classID == 2 and subClassID == 19 then category = 2 end
    local rule = category and gearPrices[category]
    if rule then return rule.amount, { amount = rule.amount, label = rule.label }, "category" end
end

function GD:ShowDKPPriceLookup()
    if not self:IsDKPEnabled() then return end
    local bucket = self:GetDKPBucket()
    self.ShowInputForm("Check Item DKP Price", {
        { label = "Item link or numeric item ID", value = "", max = 500, itemLink = true },
    }, function(values)
        if self:GetDKPBucket() ~= bucket or not self:IsDKPEnabled() then return false, "Reopen the price lookup for your current guild." end
        local id, label = bidItem(values[1])
        if not id then return false, "Paste an item link or enter its numeric item ID." end
        local amount, rule, source = self:GetDKPStartingBid(values[1])
        if not amount then return false, "No equipment price found. If the item is not cached, try again after its tooltip loads." end
        self.ShowInputForm("Item DKP Price", {
            { label = label .. " (" .. id .. ")", value = amount .. " DKP", readOnly = true },
            { label = "Price source", value = source == "item" and "Saved item override" or rule.label, readOnly = true, max = 200 },
        }, function() return true end, "Close")
        return true
    end, "Check")
end

function GD:SetDKPStartingBid(item, amount)
    if not self:IsDKPEnabled() then return false, "Enable DKP for this guild first." end
    if not self:CanConfigureDKP() then return false, "Only the GM or rank 1 officers can set starting bids." end
    local id, label = bidItem(item)
    if not id then return false, "Paste an item link or enter its numeric item ID." end
    amount = tonumber(amount)
    if not amount or amount ~= math.floor(amount) or amount < 1 or amount > 1000000 then
        return false, "Enter a whole-number starting bid from 1 to 1,000,000 DKP."
    end
    local bids = self:GetDKPBucket().dkpStartingBids
    local previous = bids[id]
    if previous and label == "Item " .. id then label = previous.label end
    local record = { amount = amount, label = label, ts = math.max(GD:GetDKPTime(), previous and previous.ts + 1 or 0), by = self:PlayerName() }
    bids[id] = record
    self:SendDKPRecord("DKB", id, record.ts, record.by, amount .. "\n" .. label)
    return true, label .. " starting bid saved: " .. amount .. " DKP."
end

function GD:ShowDKPStartingBidForm(item)
    if not self:IsDKPEnabled() or not self:CanConfigureDKP() then return end
    local bucket = self:GetDKPBucket()
    local amount = self:GetDKPStartingBid(item)
    local id = bidItem(tostring(item or ""))
    local record = self:GetDKPBucket().dkpStartingBids[id]
    self.ShowInputForm("Item Starting Bid", {
        { label = record and (record.label .. " - item ID " .. item) or "Item link or numeric item ID", value = item or "", max = 500, readOnly = record ~= nil, itemLink = true },
        { label = "Starting bid (DKP)", value = tostring(amount or 10), max = 7 },
    }, function(values)
        if self:GetDKPBucket() ~= bucket then return false, "Your guild changed. Reopen Starting Bids." end
        return self:SetDKPStartingBid(values[1], values[2])
    end, "Save Bid")
end

function GD:ShowDKPStartingBids()
    if not self:IsDKPEnabled() then return end
    local bucket, options, items = self:GetDKPBucket(), { "Guild gear prices and rewards", "Look up an item price" }, {}
    if self:CanConfigureDKP() then options[#options + 1] = "New item..." end
    for id, record in pairs(bucket.dkpStartingBids) do
        items[#items + 1] = { id = id, label = record.label .. " (" .. id .. ") - " .. record.amount .. " DKP" }
    end
    table.sort(items, function(a, b) return a.label < b.label end)
    local ids = {}
    if self:CanConfigureDKP() then
        for _, item in ipairs(items) do options[#options + 1] = item.label; ids[item.label] = item.id end
    end
    self.ShowInputForm("Starting Bids", {
        { label = "Guild prices, rewards and item overrides", options = options, value = options[1] },
    }, function(values)
        if self:GetDKPBucket() ~= bucket then return false, "Your guild changed. Reopen Starting Bids." end
        if not self:IsDKPEnabled() then return false, "DKP access changed. Reopen Starting Bids." end
        if values[1] == options[1] then self:ShowDKPRules()
        elseif values[1] == options[2] then self:ShowDKPPriceLookup()
        elseif self:CanConfigureDKP() then self:ShowDKPStartingBidForm(ids[values[1]])
        else return false, "Only the GM or rank 1 officers can edit starting bids." end
        return true
    end, "Open")
end

local pendingBids = {}
local function receiveBid(id, ts, author, content, sender)
    if not GD:GetDKPBucket() or type(id) ~= "string" or not id:match("^%d+$") or #id > 10
        or not tonumber(id) or tonumber(id) < 1 or tonumber(id) > 2147483647 or tostring(tonumber(id)) ~= id
        or type(ts) ~= "number" or ts <= 0 or ts ~= math.floor(ts) or ts > GD:GetDKPTime() + 60
        or type(author) ~= "string" or author == "" or #author > 100 or author:find("%c")
        or type(content) ~= "string" or #content > 120 then return end
    local amount, label = content:match("^(%d+)\n([^\n]+)$")
    amount = tonumber(amount)
    if not amount or amount < 1 or amount > 1000000 or #label > 100 or label:find("[%c|]") then return end
    local _, rank = rosterMember(sender)
    if rank == nil then
        if #pendingBids < 50 then pendingBids[#pendingBids + 1] = { id = id, ts = ts, author = author, content = content, sender = sender, bucket = GD:GetDKPBucket() } end
        return
    end
    if rank > 1 then return end
    local bids = GD:GetDKPBucket().dkpStartingBids
    local current = bids[id]
    if current and (ts < current.ts or (ts == current.ts and nameKey(author) <= nameKey(current.by))) then return end
    bids[id] = { amount = amount, label = label, ts = ts, by = author }
end
GD:RegisterDKPRecordHandler("DKB", receiveBid, 120)
GD:RegisterEventHandler("GUILD_ROSTER_UPDATE", function()
    local records = pendingBids
    pendingBids = {}
    for _, record in ipairs(records) do
        if record.bucket == GD:GetDKPBucket() then receiveBid(record.id, record.ts, record.author, record.content, record.sender) end
    end
end)

function GD:GetDKPRaidMembers(allowParty)
    local members, seen = {}, {}
    if self:IsDKPSoloTesting() then
        local member = self:GetDKPGuildMember(self:PlayerName())
        return member and { member } or members
    end
    if not self:IsDKPEnabled() then return members end
    if not IsInRaid or not IsInRaid() then
        -- Recording and auction tests opt into party support; ordinary manual
        -- raid awards still use the raid-only path by default.
        if not allowParty or not IsInGroup or not IsInGroup() then return members end
        local count = math.min(4, GetNumSubgroupMembers and GetNumSubgroupMembers()
            or math.max(0, (GetNumGroupMembers and GetNumGroupMembers() or 1) - 1))
        for index = 0, count do
            local unit = index == 0 and "player" or "party" .. index
            local name = index == 0 and self:PlayerName() or GetUnitName and GetUnitName(unit, true)
            if not name and UnitName then
                local base, realm = UnitName(unit)
                name = base and (realm and realm ~= "" and base .. "-" .. realm or base)
            end
            local connected = not UnitIsConnected or UnitIsConnected(unit)
            local canonical = rosterMember(name)
            if canonical and connected and connected ~= 0 and not seen[nameKey(canonical)] then
                seen[nameKey(canonical)] = true; members[#members + 1] = canonical
            end
        end
        table.sort(members, function(a,b) return nameKey(a) < nameKey(b) end)
        return members
    end
    if not GetRaidRosterInfo then return members end
    for index = 1, math.min(40, GetNumGroupMembers and GetNumGroupMembers() or 40) do
        local name = GetRaidRosterInfo(index)
        local canonical = rosterMember(name)
        if canonical and not seen[nameKey(canonical)] then
            seen[nameKey(canonical)] = true
            members[#members + 1] = canonical
        end
    end
    table.sort(members, function(a, b) return nameKey(a) < nameKey(b) end)
    return members
end

function GD:ValidateDKPRaidAward(members, amount, reason)
    if not self:IsDKPEnabled() then return false, "Enable DKP for this guild first." end
    if not self:CanConfigureDKP() then return false, "Only the GM or rank 1 officers can award raid DKP." end
    if type(members) ~= "table" or #members < 1 or #members > 40 then return false, "Select at least one raid member." end
    local current, selected, seen = {}, {}, {}
    for _, name in ipairs(self:GetDKPRaidMembers()) do current[nameKey(name)] = true end
    local points, note
    for _, name in ipairs(members) do
        local ok, canonical, value, text = self:ValidateDKPAward(name, amount, reason)
        if not ok then return false, canonical end
        if not current[nameKey(canonical)] then return false, "A selected member left the raid. Reopen Award Raid to refresh the list." end
        if seen[nameKey(canonical)] then return false, "A raid member was selected more than once." end
        if math.abs(balanceFor(canonical) + value) > 9007199254740991 then return false, "A selected member's DKP balance is too large." end
        seen[nameKey(canonical)] = true
        selected[#selected + 1] = canonical
        points, note = value, text
    end
    return true, selected, points, note
end

function GD:AwardRaidDKP(members, amount, reason)
    local ok, selected, points, note = self:ValidateDKPRaidAward(members, amount, reason)
    if not ok then return false, selected end
    -- Prepare every entry before changing balances, so validation or an ID
    -- collision cannot leave only part of the selected raid awarded.
    local records, ids = {}, {}
    local author = rosterMember(self:PlayerName()) or self:PlayerName()
    local sequence, ts = tonumber(self:GetDKPBucket().dkpAwardSequence) or 0, GD:GetDKPTime()
    for _, member in ipairs(selected) do
        sequence = sequence + 1
        local id = "dkp:" .. nameKey(author):gsub("[^%w]", ""):sub(1, 40) .. ":" .. ts .. ":" .. sequence .. ":" .. math.random(100000, 999999)
        if ids[id] or (self:GetDKPBucket().dkpAwards or {})[id] then return false, "Award ID already exists. Try again." end
        ids[id] = true
        records[#records + 1] = { id = id, ts = ts, by = author, member = member, amount = points, reason = note }
    end
    for _, record in ipairs(records) do applyAward(record, true) end
    self:GetDKPBucket().dkpAwardSequence = sequence
    for _, record in ipairs(records) do self:SendDKPRecord("DKA", record.id, record.ts, record.by, awardContent(record)) end
    refresh()
    return true, points .. " DKP awarded to " .. #records .. " raid members."
end

function GD:ShowDKPRaidRewardPicker()
    if not self:IsDKPEnabled() or not self:CanConfigureDKP() then return end
    local bucket, options, presets = self:GetDKPBucket(), {}, {}
    for _, reward in ipairs(raidRewards) do
        options[#options + 1] = reward.label
        presets[reward.label] = reward
    end
    options[#options + 1] = "Starting balance - 1,000 DKP once"
    options[#options + 1] = "Custom raid award"
    self.ShowInputForm("DKP Awards", {
        { label = "Choose an award", options = options, value = options[1] },
    }, function(values)
        if self:GetDKPBucket() ~= bucket then return false, "Your guild changed. Reopen DKP Awards." end
        if not self:IsDKPEnabled() or not self:CanConfigureDKP() then return false, "DKP access changed. Reopen DKP Awards." end
        if values[1] == "Starting balance - 1,000 DKP once" then self:ShowDKPStartingGrantForm()
        else
            if presets[values[1]] and self.GetDKPActiveRaid and self:GetDKPActiveRaid() then
                return self:ShowDKPRecordedReward(presets[values[1]])
            end
            self:ShowDKPRaidAwardForm(presets[values[1]])
        end
        return true
    end, "Open")
end

function GD:ShowDKPRaidAwardForm(preset)
    if not self:IsDKPEnabled() or not self:CanConfigureDKP() then return end
    local bucket, members = self:GetDKPBucket(), self:GetDKPRaidMembers()
    if #members == 0 then
        print("GuildDB: Join a raid with guild members first. Refresh the guild roster if necessary.")
        return
    end
    self.ShowInputForm("Award Raid DKP", {
        { label = "DKP per selected member", value = tostring(preset and preset.amount or 10), max = 7 },
        { label = "Reason (add the boss or raid name)", value = preset and preset.reason or "", max = 160 },
        { label = "Guild members in this raid (uncheck to exclude)", checklist = members, value = members },
    }, function(values)
        if self:GetDKPBucket() ~= bucket then return false, "Your guild changed. Reopen Award Raid." end
        local ok, selected, points, note = self:ValidateDKPRaidAward(values[3], values[1], values[2])
        if not ok then return false, selected end
        local used = false
        self.ShowInputForm("Confirm Raid DKP", {
            { label = "Award summary", value = points .. " DKP each to " .. #selected .. " members (" .. points * #selected .. " total).\nReason: " .. self:Display(note), multiline = true, readOnly = true, max = 500 },
            { label = "Confirmed recipients", checklist = selected, value = selected, readOnly = true },
        }, function()
            if used then return false, "This raid award has already been applied." end
            if self:GetDKPBucket() ~= bucket then return false, "Your guild changed. Reopen Award Raid." end
            local success, message = self:AwardRaidDKP(selected, points, note)
            if success then used = true end
            return success, message
        end, "Award Raid")
        return true
    end, "Review")
end

local pendingAwards = {}
local function receiveAward(id, ts, author, content, sender, deduction)
    if not GD:GetDKPBucket() or type(id) ~= "string" or id == "" or #id > 100 or id:find("%c")
        or type(ts) ~= "number" or ts <= 0 or ts ~= math.floor(ts) or ts > GD:GetDKPTime() + 60
        or type(author) ~= "string" or author == "" or #author > 100 or author:find("%c")
        or type(content) ~= "string" or #content > 300 then return end
    local member, amount, reason = content:match("^([^\n]+)\n(%d+)\n([^\n]+)$")
    amount = tonumber(amount)
    if not member or #member > 100 or member:find("%c") or not amount or amount < 1 or amount > 1000000 or not validReason(reason) then return end
    if id:sub(1, 10) == "dkp:start:" and (deduction or amount ~= STARTING_DKP
        or reason ~= STARTING_REASON or id ~= startingID(member)) then return end
    local _, rank = rosterMember(sender)
    if rank == nil then
        if #pendingAwards < 200 then pendingAwards[#pendingAwards + 1] = {
            id = id, ts = ts, author = author, content = content, sender = sender, bucket = GD:GetDKPBucket(), deduction = deduction,
        } end
        return
    end
    -- Only currently authorized officers may send/attest award history. A member
    -- cannot obtain write access by placing an officer's name in the payload.
    if rank > 1 then return end
    applyAward({ id = id, ts = ts, by = author, member = member, amount = deduction and -amount or amount, reason = reason })
end
GD:RegisterDKPRecordHandler("DKA", receiveAward, 300)
GD:RegisterDKPRecordHandler("DKD", function(id, ts, author, content, sender)
    receiveAward(id, ts, author, content, sender, true)
end, 300)
GD:RegisterEventHandler("GUILD_ROSTER_UPDATE", function()
    local records = pendingAwards
    pendingAwards = {}
    for _, record in ipairs(records) do
        if record.bucket == GD:GetDKPBucket() then receiveAward(record.id, record.ts, record.author, record.content, record.sender, record.deduction) end
    end
end)

local function sendAwards()
    if not GD:CanConfigureDKP() then return end
    for _, record in pairs(GD:GetDKPBucket().dkpAwards or {}) do
        if not record.system then GD:SendDKPRecord(record.amount < 0 and "DKD" or "DKA", record.id, record.ts, record.by, awardContent(record)) end
    end
    for id, record in pairs(GD:GetDKPBucket().dkpStartingBids or {}) do
        GD:SendDKPRecord("DKB", id, record.ts, record.by, record.amount .. "\n" .. record.label)
    end
end
GD:RegisterHistoryProvider(sendAwards, false)
local awardRequestBucket, lastAwardRequest, awardReplyBucket, lastAwardReply
function GD:RequestDKPAwards()
    if not self:GetDKPBucket() then return false end
    if awardRequestBucket ~= self:GetDKPBucket() then awardRequestBucket, lastAwardRequest = self:GetDKPBucket(), nil end
    if lastAwardRequest and GD:GetDKPTime() - lastAwardRequest < 10 then return false end
    lastAwardRequest = GD:GetDKPTime()
    self:SendDKPRecord("DKAQ", "awards", GD:GetDKPTime(), self:PlayerName(), "")
    return true
end
GD:RegisterDKPRecordHandler("DKAQ", function(id, ts, author, content, sender)
    if id ~= "awards" or content ~= "" or not GD:CanConfigureDKP() or not rosterMember(sender) then return end
    if awardReplyBucket ~= GD:GetDKPBucket() then awardReplyBucket, lastAwardReply = GD:GetDKPBucket(), nil end
    if lastAwardReply and GD:GetDKPTime() - lastAwardReply < 5 then return end
    lastAwardReply = GD:GetDKPTime()
    sendAwards()
    if GD.SendDKPSystemsHistory then GD:SendDKPSystemsHistory() end
end, 1)

function GD:GetDKPAwardHistory(query, category)
    if not self:IsDKPEnabled() then return {} end
    query = nameKey(query)
    local rows = {}
    for _, record in pairs(self:GetDKPBucket().dkpAwards or {}) do
        local source = record.reverses and self:GetDKPBucket().dkpAwards[record.reverses]
        local matches = not category or category == "All"
            or category == "Earned" and record.amount > 0 and not record.reverses
            or category == "Spent" and record.amount < 0 and not record.reverses
            or category == "Loot" and (record.loot or source and source.loot)
            or category == "Corrections" and (record.reverses or record.amount < 0 and not record.loot)
        if matches and record.amount ~= 0 and (query == "" or nameKey(record.member .. " " .. record.by .. " " .. record.reason):find(query, 1, true)) then rows[#rows + 1] = record end
    end
    table.sort(rows, function(a, b) if a.ts ~= b.ts then return a.ts > b.ts end; return a.id > b.id end)
    return rows
end

function GD:ShowDKPAwardForm(member, deduction)
    if not self:IsDKPEnabled() or not self:CanConfigureDKP() then return end
    local bucket, canonical = self:GetDKPBucket(), rosterMember(member)
    if not canonical then return end
    self.ShowInputForm(deduction and "Take DKP" or "Award DKP", {
        { label = "Guild member", value = canonical, readOnly = true, max = 100 },
        { label = "Amount (whole number)", value = "10", max = 7 },
        { label = "Reason", value = "", max = 160 },
    }, function(values)
        if self:GetDKPBucket() ~= bucket then return false, "Your guild changed. Open the award form again." end
        local ok, name, points, note = self:ValidateDKPAward(canonical, values[2], values[3], deduction)
        if not ok then return false, name end
        local used = false
        local resulting = balanceFor(name) + points
        local summary = (deduction and "Take " or "Award ") .. math.abs(points) .. (deduction and " DKP from " or " DKP to ") .. self:Display(name)
            .. "?\nReason: " .. self:Display(note) .. "\nCurrent balance: " .. balanceFor(name) .. " DKP\nBalance after adjustment: " .. resulting .. " DKP"
        if resulting < 0 then summary = summary .. "\nThis leaves a negative DKP balance." end
        self:ConfirmAction(deduction and "Confirm DKP deduction" or "Confirm DKP award", summary, function()
            if used then return false, "This award has already been applied." end
            if self:GetDKPBucket() ~= bucket then return false, "Your guild changed. Open the award form again." end
            local success, message
            if deduction then success, message = self:DeductDKP(name, math.abs(points), note)
            else success, message = self:AwardDKP(name, points, note) end
            if success then used = true end
            return success, message
        end, deduction and "Take DKP" or "Award")
        return true
    end, "Review")
end

function GD:GetDKPBalance(name)
    if not self:IsDKPEnabled() then return 0 end
    local member = rosterMember(name)
    return member and balanceFor(member) or 0
end

function GD:GetDKPStandings(query)
    if not self:IsDKPEnabled() then return {}, 0 end
    query = nameKey(query)
    local rows, total = {}, 0
    if not GetNumGuildMembers or not GetGuildRosterInfo then return rows, total end
    for index = 1, GetNumGuildMembers(true) do
        local name, _, _, level, class, _, _, _, online, _, classFile = GetGuildRosterInfo(index)
        local solo = self:IsDKPSoloTesting()
        if name and ((not solo and tonumber(level) == 60) or (solo and nameKey(name) == nameKey(self:GetDKPGuildMember(self:PlayerName())))) then
            total = total + 1
            if query == "" or (nameKey(name) .. " " .. nameKey(class)):find(query, 1, true) then
                rows[#rows + 1] = { name = name, class = class or "Unknown", classFile = classFile,
                    balance = balanceFor(name), online = not not online }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.balance ~= b.balance then return a.balance > b.balance end
        return nameKey(a.name) < nameKey(b.name)
    end)
    return rows, total
end

local function text(parent, font, x, y)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetPoint("TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    return label
end

local function buildStandings(frame)
    local panel = CreateFrame("Frame", nil, frame.detailPanel)
    panel:SetAllPoints()
    panel.rows = {}
    panel.title = text(panel, "GameFontNormalLarge", 16, -16)
    panel.title:SetText("DKP Standings")
    panel.history = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.history:SetSize(100, 26)
    panel.history:SetPoint("TOPRIGHT", -16, -12)
    panel.history:SetText("History")
    panel.startingBids = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.startingBids:SetSize(110, 26)
    panel.startingBids:SetPoint("TOPRIGHT", -124, -12)
    panel.startingBids:SetText("Prices / Rules")
    panel.startingBids:SetScript("OnClick", function() GD:ShowDKPStartingBids() end)
    panel.history:SetScript("OnClick", function()
        panel.section = nil
        panel.historyMode = not panel.historyMode
        panel.search:SetText("")
        panel.scroll:SetVerticalScroll(0)
        GD:RefreshDKP()
    end)
    panel.summary = text(panel, "GameFontNormal", 16, -46)
    panel.syncStatus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.syncStatus:SetSize(100, 26); panel.syncStatus:SetPoint("TOPRIGHT", -16, -42); panel.syncStatus:SetText("Sync Status")
    panel.syncStatus:SetScript("OnClick", function() GD:ShowDKPSyncStatus() end)
    panel.historyFilter = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.historyFilter:SetSize(124, 26); panel.historyFilter:SetPoint("TOPLEFT", 16, -160)
    panel.historyFilter:SetScript("OnClick", function()
        local bucket = GD:GetDKPBucket()
        GD.ShowInputForm("History Filter", {{label = "Show adjustments", options = {"All", "Earned", "Spent", "Loot", "Corrections"}, value = panel.historyCategory or "All"}}, function(values)
            if GD:GetDKPBucket() ~= bucket then return false, "Your guild changed. Reopen history." end
            local valid = {All=true, Earned=true, Spent=true, Loot=true, Corrections=true}
            if not valid[values[1]] then return false, "Choose a history filter." end
            panel.historyCategory = values[1]; panel.scroll:SetVerticalScroll(0); GD:RefreshDKP(); return true
        end, "Apply")
    end)
    panel.raidAward = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.raidAward:SetSize(100, 26)
    panel.raidAward:SetPoint("TOPRIGHT", -16, -42)
    panel.raidAward:SetText("Award Raid")
    panel.raidAward:SetScript("OnClick", function() GD:ShowDKPRaidRewardPicker() end)
    panel.searchLabel = text(panel, "GameFontHighlightSmall", 16, -76)
    panel.searchLabel:SetText("Search name or class")
    panel.search = CreateFrame("EditBox", nil, panel, "BackdropTemplate")
    panel.search:SetPoint("TOPLEFT", 16, -94)
    panel.search:SetPoint("TOPRIGHT", -52, -94)
    panel.search:SetHeight(26)
    panel.search:SetAutoFocus(false)
    panel.search:SetMaxLetters(100)
    GD:StyleEditBox(panel.search)
    panel.clearSearch = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.clearSearch:SetSize(28, 26); panel.clearSearch:SetPoint("TOPRIGHT", -16, -93); panel.clearSearch:SetText("X")
    panel.clearSearch:SetScript("OnClick", function() panel.search:SetText(""); panel.search:ClearFocus(); GD:RefreshDKP() end)
    panel.search:SetScript("OnEscapePressed", function(input) input:ClearFocus(); frame:Hide(); if GD.CloseWindowsOnEscape then GD:CloseWindowsOnEscape() end end)
    panel.search:SetScript("OnTextChanged", function()
        panel.scroll:SetVerticalScroll(0)
        if panel.workspace then panel.workspace.scroll:SetVerticalScroll(0) end
        GD:RefreshDKP()
    end)
    panel.nameHeader = text(panel, "GameFontNormal", 24, -170)
    panel.nameHeader:SetText("Guild member")
    panel.pointsHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.pointsHeader:SetPoint("TOPRIGHT", -32, -170)
    panel.pointsHeader:SetText("DKP")
    panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scroll:SetPoint("TOPLEFT", 16, -192)
    panel.scroll:SetPoint("BOTTOMRIGHT", -32, 42)
    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetSize(400, 100)
    panel.scroll:SetScrollChild(panel.content)
    panel.empty = text(panel.content, "GameFontHighlight", 8, -12)
    panel.footer = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.footer:SetPoint("BOTTOMLEFT", 16, 16)
    panel.footer:SetText("Officers can award or take DKP. History records every adjustment.")
    panel:HookScript("OnHide", function() panel.search:ClearFocus(); GameTooltip:Hide() end)
    panel.scroll:HookScript("OnSizeChanged", function() if panel:IsShown() then GD:RefreshDKP() end end)
    frame.dkp = panel
    return panel
end

function GD:RefreshDKP()
    local frame = self.frame
    if not frame then return end
    if not self:IsDKPEnabled() or self.activeTab ~= "DKP" then
        if frame.dkp then frame.dkp:Hide() end
        return
    end
    local panel = frame.dkp or buildStandings(frame)
    panel:Show()
    for _, key in ipairs({ "detailScroll", "detailTitle", "detailMeta", "detailRule", "detailBody", "footer" }) do frame[key]:Hide() end
    if panel.bucket ~= self:GetDKPBucket() then
        panel.bucket = self:GetDKPBucket()
        panel.historyMode = false
        panel.historyCategory = "All"
        panel.section = nil
        panel.search:SetText("")
        panel.scroll:SetVerticalScroll(0)
    end
    local rows, total
    if panel.historyMode then rows = self:GetDKPAwardHistory(panel.search:GetText(), panel.historyCategory); total = #self:GetDKPAwardHistory(nil, panel.historyCategory)
    else rows, total = self:GetDKPStandings(panel.search:GetText()) end
    local canAward = self:CanConfigureDKP() and not panel.historyMode and (not panel.section or panel.section == "Raids")
    local colors = self:GetAppearanceColors()
    local width = math.max(100, panel.scroll:GetWidth())
    panel.content:SetWidth(width)
    local rowHeight = panel.historyMode and 68 or 48
    panel.content:SetHeight(math.max(panel.scroll:GetHeight(), #rows * rowHeight))
    panel.title:SetText((self:IsDKPSoloTesting() and "SOLO TEST - " or "") .. (panel.historyMode and "DKP History" or "DKP Standings"))
    panel.title:SetWidth(math.max(100, frame.detailPanel:GetWidth() - 258))
    panel.startingBids:Show()
    self:StyleButton(panel.startingBids)
    panel.history:SetText(panel.historyMode and "Standings" or "History")
    self:StyleButton(panel.history, panel.historyMode and "primary" or nil)
    panel.searchLabel:SetText(panel.historyMode and "Search member, officer or reason" or "Search name or class")
    panel.historyFilter:SetShown(panel.historyMode and not panel.section)
    panel.historyFilter:SetText(panel.historyCategory or "All"); self:StyleButton(panel.historyFilter)
    panel.nameHeader:ClearAllPoints(); panel.nameHeader:SetPoint("TOPLEFT", panel.historyMode and 152 or 24, -170)
    panel.nameHeader:SetText(panel.historyMode and "Adjustment details" or "Guild member")
    panel.summary:SetText(#rows .. " / " .. total .. (panel.historyMode and " adjustments" or " members") .. "  |  Your DKP: " .. self:GetDKPBalance(self:PlayerName()))
    local showSync = self:CanConfigureDKP() and panel.section == "Officer"
    panel.syncStatus:SetShown(showSync); self:StyleButton(panel.syncStatus)
    panel.summary:SetWidth(math.max(100, frame.detailPanel:GetWidth() - ((canAward or showSync) and 140 or 32)))
    panel.raidAward:SetShown(canAward)
    self:StyleButton(panel.raidAward)
    panel.title:SetTextColor(unpack(colors.accent))
    panel.summary:SetTextColor(unpack(colors.text))
    for _, label in ipairs({ panel.searchLabel, panel.nameHeader, panel.pointsHeader, panel.empty, panel.footer }) do label:SetTextColor(unpack(colors.muted)) end
    panel.footer:SetWidth(math.max(100, frame.detailPanel:GetWidth() - 32))
    panel.search:SetBackdropColor(unpack(colors.panel))
    panel.search:SetTextColor(unpack(colors.text))
    panel.search:SetGuildDBFocusState(panel.search:HasFocus())
    panel.clearSearch:SetShown(panel.search:GetText() ~= ""); self:StyleButton(panel.clearSearch)
    if self.RefreshDKPWorkspace and self:RefreshDKPWorkspace(panel) then return end
    panel.footer:SetText(self:IsDKPSoloTesting() and "SOLO TEST: temporary data, no guild sync. /gd dkptest exits." or "Officers can award or take DKP. History records every adjustment.")
    for index, member in ipairs(rows) do
        local row = panel.rows[index]
        if not row then
            row = CreateFrame("Frame", nil, panel.content)
            row:SetHeight(44)
            row:SetPoint("TOPLEFT", 0, -(index - 1) * 48)
            row:SetPoint("TOPRIGHT", 0, -(index - 1) * 48)
            row.background = row:CreateTexture(nil, "BACKGROUND")
            row.background:SetAllPoints()
            row.name = text(row, "GameFontNormal", 10, -6)
            row.meta = text(row, "GameFontHighlightSmall", 10, -25)
            row.points = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            row.points:SetPoint("RIGHT", -12, 0)
            row.award = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.award:SetSize(66, 26)
            row.award:SetPoint("RIGHT", -82, 0)
            row.award:SetText("Award")
            row.award:SetScript("OnClick", function() GD:ShowDKPAwardForm(row.member) end)
            row.deduct = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.deduct:SetSize(70, 26)
            row.deduct:SetPoint("RIGHT", -8, 0)
            row.deduct:SetText("Take DKP")
            row.deduct:SetScript("OnClick", function() GD:ShowDKPAwardForm(row.member, true) end)
            row:EnableMouse(true)
            row:SetScript("OnEnter", function()
                GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
                if not row.record then
                    if not row.member then return end
                    GameTooltip:SetText(GD:Display(row.member))
                    if GD.GetDKPAccount then GameTooltip:AddLine("DKP account: " .. GD:Display(GD:GetDKPAccount(row.member)), 1, 1, 1, true) end
                    GameTooltip:AddLine("Balance: " .. GD:GetDKPBalance(row.member) .. " DKP", 1, 1, 1, true)
                    GameTooltip:Show(); return
                end
                GameTooltip:SetText(GD:Display(row.record.member) .. " " .. (row.record.amount > 0 and "+" or "") .. row.record.amount .. " DKP")
                GameTooltip:AddLine("By " .. GD:Display(row.record.by) .. " - " .. date("%b %d, %Y %I:%M %p", row.record.ts), 1, 1, 1, true)
                GameTooltip:AddLine(GD:Display(row.record.reason), 1, 1, 1, true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            panel.rows[index] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
        row:SetPoint("TOPRIGHT", 0, -(index - 1) * rowHeight)
        row:SetHeight(rowHeight - 4)
        row.member, row.record = member.name, panel.historyMode and member or nil
        local color = self:GetDKPClassColor(panel.historyMode and member.member or member.name)
        row.background:SetColorTexture(unpack(index % 2 == 0 and colors.panel or colors.alternate))
        row.name:SetWidth(math.max(1, width - (canAward and 254 or 110)))
        row.name:SetWordWrap(false)
        row.meta:SetWidth(math.max(1, width - (canAward and 254 or 110)))
        row.meta:SetWordWrap(panel.historyMode == true)
        row.meta:SetHeight(panel.historyMode and 34 or 14)
        row.name:SetText(self:Display(panel.historyMode and member.member or member.name))
        row.name:SetTextColor(color and color.r or colors.text[1], color and color.g or colors.text[2], color and color.b or colors.text[3])
        row.meta:SetText(panel.historyMode and ("By " .. self:DKPCharacterText(member.by) .. " - " .. date("%b %d, %I:%M %p", member.ts) .. "\n" .. self:Display(member.reason))
            or (self:Display(member.class) .. (member.online and " - Online" or " - Offline")))
        row.meta:SetTextColor(unpack(colors.muted))
        row.points:ClearAllPoints()
        row.points:SetPoint("RIGHT", canAward and -164 or -12, 0)
        row.points:SetText(panel.historyMode and ((member.amount > 0 and "+" or "") .. member.amount) or tostring(member.balance))
        if (panel.historyMode and member.amount or member.balance) < 0 then row.points:SetTextColor(1, 0.35, 0.35)
        else row.points:SetTextColor(unpack(colors.accent)) end
        row.award:SetShown(canAward)
        row.deduct:SetShown(canAward)
        self:StyleButton(row.award)
        self:StyleButton(row.deduct)
        row:Show()
    end
    for index = #rows + 1, #panel.rows do panel.rows[index]:Hide() end
    panel.empty:SetShown(#rows == 0)
    panel.empty:SetText(panel.historyMode and (total == 0 and "No DKP adjustments yet." or "No adjustments match your search.")
        or (total == 0 and "Waiting for the guild roster..." or "No guild members match your search."))
    panel.empty:SetWidth(math.max(1, width - 16))
    self:StyleScrollFrame(panel.scroll)
end

GD:RegisterTab("DKP", function() return GD:IsDKPEnabled() and "Standings\nGuild members and current DKP balances." or "" end)

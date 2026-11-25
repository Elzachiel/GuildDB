-- Guild DKP operations. Saved records are replayable; live bids belong to the
-- officer hosting the auction. Optional Master Loot delivery is handled separately.
local _, GD = ...
GD:RegisterBucket("dkpSystems", function() return {} end)
GD:RegisterBucket("dkpAccounts", function() return {} end)

local function key(value) return tostring(value or ""):lower():match("^%s*(.-)%s*$") end
local function clean(value, limit) return type(value) == "string" and #value <= limit and not value:find("%c") end
local function integer(value, low, high)
    local n = tonumber(value)
    return n and n == math.floor(n) and n >= low and n <= high and n or nil
end
local function pack(values)
    local result = {}
    for i, value in ipairs(values) do result[i] = GD:Encode(value) end
    return table.concat(result, "|")
end
local function split(value)
    local result = {}
    for part in (value .. "|"):gmatch("(.-)|") do result[#result + 1] = GD:Decode(part) end
    return result
end
local function names(value)
    local result, seen = {}, {}
    if value == "" then return result end
    for _, name in ipairs(split(value)) do
        if not clean(name, 100) or name == "" or seen[key(name)] then return end
        seen[key(name)] = true; result[#result + 1] = name
    end
    if #result > 40 then return end
    return result
end
local function own() return GD:GetDKPGuildMember(GD:PlayerName()) or GD:PlayerName() end
local function allowed() return GD:IsDKPEnabled() and GD:CanConfigureDKP() end
local function notify()
    if GD.dkpImporting then return end
    if GD.RefreshUI then GD:RefreshUI() end
    if GD.RefreshDKPAuctionPopup then GD:RefreshDKPAuctionPopup() end
end
local function id(prefix)
    GD:GetDKPBucket().dkpSystemSequence = (tonumber(GD:GetDKPBucket().dkpSystemSequence) or 0) + 1
    return prefix .. ":" .. key(own()):gsub("[^%w]", ""):sub(1, 12) .. ":" .. GD:GetDKPTime() .. ":" .. GD:GetDKPBucket().dkpSystemSequence .. ":" .. math.random(10000, 99999)
end
local function records(kind)
    local result = {}
    for _, r in pairs(GD:GetDKPBucket() and GD:GetDKPBucket().dkpSystems or {}) do if r.kind == kind then result[#result + 1] = r end end
    table.sort(result, function(a, b) if a.ts ~= b.ts then return a.ts > b.ts end; return a.id > b.id end)
    return result
end
local function get(kind, recordID) return GD:GetDKPBucket() and GD:GetDKPBucket().dkpSystems[kind .. ":" .. recordID] end

local identityCache, identityBucket, identitySize
local function identity(name)
    local size = GetNumGuildMembers(true)
    if not identityCache or identityBucket ~= GD:GetDKPBucket() or identitySize ~= size then
        identityCache, identityBucket, identitySize = {}, GD:GetDKPBucket(), size
        local function alias(value, canonical)
            value = key(value)
            if identityCache[value] and identityCache[value] ~= canonical then identityCache[value] = false
            elseif identityCache[value] == nil then identityCache[value] = canonical end
        end
        for i = 1, size do
            local canonical = GetGuildRosterInfo(i)
            if canonical then
                alias(canonical, canonical); alias(canonical:match("^([^%-]+)"), canonical)
                alias(canonical:match("^([^%s%-]+)"), canonical)
            end
        end
    end
    return identityCache[key(name)] or name
end

function GD:GetDKPAccount(name)
    -- Legacy DKM records remain available for backup/history compatibility,
    -- but never merge character funds, eligibility or starting grants.
    return identity(name)
end

function GD:IsDKPEligible(name)
    local canonical = self:GetDKPGuildMember(name)
    if not canonical then return false end
    if self:IsDKPSoloTesting() then return key(canonical) == key(own()), canonical end
    for i = 1, GetNumGuildMembers(true) do
        local member, _, _, level = GetGuildRosterInfo(i)
        if key(member) == key(canonical) then return tonumber(level) == 60, canonical end
    end
    return false
end

function GD:GetDKPParticipants(includeAllLevels)
    local result, seen, offline = {}, {}, {}
    if IsInRaid and IsInRaid() and GetRaidRosterInfo then
        for i = 1, math.min(40, GetNumGroupMembers and GetNumGroupMembers() or 40) do
            local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
            if name and (online == false or online == 0) then offline[key(self:GetDKPGuildMember(name) or name)] = true end
        end
    end
    for _, name in ipairs(self:GetDKPRaidMembers(includeAllLevels)) do
        local eligible, canonical = self:IsDKPEligible(name)
        if includeAllLevels then canonical = self:GetDKPGuildMember(name); eligible = canonical ~= nil end
        local account = key(self:GetDKPAccount(name))
        if eligible and not offline[key(canonical)] and not seen[account] then seen[account] = true; result[#result + 1] = canonical end
    end
    table.sort(result, function(a, b) return key(a) < key(b) end)
    return result
end

local schemas = {}
schemas.DKU = function(f)
    -- revision, owner, item, label, minimum, increment, end, status, bids,
    -- winner, cost, spec, eligible characters, opened time
    if #f ~= 14 or not integer(f[1], 1, 1000000) or not clean(f[2], 100) or f[2] == ""
        or not integer(f[3], 1, 2147483647) or not clean(f[4], 100) or not integer(f[5], 1, 1000000)
        or not integer(f[6], 1, 1000000) or not integer(f[7], 1, 9007199254740991)
        or not ({ OPEN = true, REVIEW = true, AWARDED = true, CANCELLED = true })[f[8]]
        or not clean(f[10], 100) or not integer(f[11], 0, 1000000)
        or not ({ MS = true, OS = true, [""] = true })[f[12]] or not names(f[13]) or not integer(f[14], 1, 9007199254740991) then return end
    local candidates, seen = {}, {}
    if f[9] ~= "" then
        for _, encoded in ipairs(split(f[9])) do
            local bid = split(encoded)
            if #bid ~= 4 or not clean(bid[1], 100) or bid[1] == "" or seen[key(bid[1])]
                or not integer(bid[2], 1, 1000000) or not ({ MS = true, OS = true })[bid[3]] or not integer(bid[4], 1, 1000000) then return end
            seen[key(bid[1])] = true
            candidates[#candidates + 1] = { member = bid[1], amount = tonumber(bid[2]), spec = bid[3], order = tonumber(bid[4]) }
        end
    end
    if #candidates > 40 or (f[8] == "AWARDED" and (f[10] == "" or tonumber(f[11]) < tonumber(f[5]) or f[12] == "")) then return end
    return { revision = tonumber(f[1]), owner = f[2], item = f[3], label = f[4], minimum = tonumber(f[5]), increment = tonumber(f[6]), ends = tonumber(f[7]), status = f[8], bids = candidates,
        winner = f[10], cost = tonumber(f[11]), spec = f[12], participants = names(f[13]), opened = tonumber(f[14]) }
end
schemas.DKS = function(f)
    if #f ~= 7 or not integer(f[1], 1, 1000000) or not clean(f[2], 100) or f[2] == "" or not clean(f[3], 100) or f[3] == ""
        or not integer(f[4], 1, 9007199254740991) or not integer(f[5], 0, 9007199254740991) or not clean(f[6], 100) or not names(f[7]) then return end
    return { revision = tonumber(f[1]), owner = f[2], label = f[3], started = tonumber(f[4]), ended = tonumber(f[5]), zone = f[6], participants = names(f[7]) }
end
schemas.DKJ = function(f)
    if #f ~= 8 or not clean(f[1], 80) or not integer(f[2], 2, 1000000) or not clean(f[3], 100) or f[3] == ""
        or not integer(f[4], 0, 1000000) or not ({ MS = true, OS = true })[f[5]]
        or not integer(f[6], 1, 1000000) or not integer(f[7], 1, 9007199254740991) or (f[8] ~= "0" and f[8] ~= "1") then return end
    return { auction = f[1], revision = tonumber(f[2]), member = f[3], amount = tonumber(f[4]), spec = f[5], order = tonumber(f[6]), ends = tonumber(f[7]), withdraw = f[8] == "1" }
end
schemas.DKV = function(f)
    if #f ~= 5 or not clean(f[1], 80) or f[1] == "" or not ({ boss = true, ontime = true, finish = true })[f[2]]
        or not clean(f[3], 160) or f[3] == "" or not clean(f[4], 100) or not names(f[5]) or #names(f[5]) == 0 then return end
    return { raid = f[1], event = f[2], label = f[3], boss = f[4], participants = names(f[5]) }
end
schemas.DKL = function(f)
    if #f ~= 5 or not clean(f[1], 100) or f[1] == "" or not integer(f[2], 1, 2147483647)
        or not clean(f[3], 100) or not integer(f[4], 1, 1000000) or not ({ MS = true, OS = true })[f[5]] then return end
    return { member = f[1], item = f[2], label = f[3], cost = tonumber(f[4]), spec = f[5] }
end
schemas.DKX = function(f)
    if #f ~= 2 or not clean(f[1], 96) or f[1] == "" or not clean(f[2], 160) or not f[2]:find("%S") then return end
    return { target = f[1], label = f[2] }
end
schemas.DKM = function(f)
    if #f ~= 1 or not clean(f[1], 100) or f[1] == "" then return end
    return { main = f[1] }
end
schemas.DKZ = function(f)
    if #f ~= 2 or (f[1] ~= "auction" and f[1] ~= "raid") or not clean(f[2], 160) or not f[2]:find("%S") then return end
    return { scope = f[1], label = f[2] }
end
schemas.DKT = function(f)
    if #f ~= 2 or not clean(f[1], 80) or f[1] == "" or not clean(f[2], 96) or f[2] == "" then return end
    return { raid = f[1], loot = f[2] }
end
schemas.DKY = function(f)
    if #f ~= 2 or not clean(f[1], 96) or f[1] == "" or (f[2] ~= "0" and f[2] ~= "1") then return end
    return { loot = f[1], delivered = f[2] == "1" }
end

local rebuilding = false
local function transaction(r, transactionID, member, amount, reason, extra)
    local value = { id = transactionID, ts = r.ts, by = r.by, member = member, amount = amount, reason = reason, system = true }
    for k, v in pairs(extra or {}) do value[k] = v end
    GD:ApplyDKPSystemTransaction(value, true)
end

local function rebuild()
    if rebuilding or not GD:GetDKPBucket() then return end
    rebuilding = true
    -- Small accepted-bid deltas avoid rebroadcasting a 40-player snapshot for
    -- every bid. Replay in revision order, including out-of-order delivery.
    local deltas = records("DKJ")
    table.sort(deltas, function(a, b) return a.data.revision < b.data.revision end)
    for _, auction in ipairs(records("DKU")) do
        auction.data = schemas.DKU(split(auction.content))
        for _, delta in ipairs(deltas) do
            local a, d = auction.data, delta.data
            if d.auction == auction.id and key(delta.by) == key(a.owner) and d.revision > a.revision and (a.status == "OPEN" or a.status == "REVIEW") then
                local bids = {}
                for _, bid in ipairs(a.bids) do if key(GD:GetDKPAccount(bid.member)) ~= key(GD:GetDKPAccount(d.member)) then bids[#bids + 1] = bid end end
                if not d.withdraw then bids[#bids + 1] = { member = d.member, amount = d.amount, spec = d.spec, order = d.order } end
                a.bids, a.revision, a.ends = bids, d.revision, d.ends
            end
        end
    end
    local first = {}
    for _, r in ipairs(records("DKV")) do
        local raid = get("DKS", r.data.raid)
        if raid and key(raid.data.owner) == key(r.by) then
            local e = r.data
            local amount = e.event == "boss" and 20 or 10
            for index, member in ipairs(e.participants) do transaction(r, "event:" .. r.id .. ":" .. index, member, amount, e.label, { raid = e.raid }) end
            if e.event == "boss" then
                local boss = key(raid.data.zone .. ":" .. e.boss)
                local previous = first[boss]
                if not previous or r.ts < previous.ts or (r.ts == previous.ts and r.id < previous.id) then first[boss] = r end
            end
        end
    end
    for _, r in ipairs(records("DKV")) do
        local raid, e = get("DKS", r.data.raid), r.data
        if raid and e.event == "boss" and key(raid.data.owner) == key(r.by) then
            local isFirst = first[key(raid.data.zone .. ":" .. e.boss)] == r
            for index, member in ipairs(e.participants) do
                GD:UpdateDKPDerivedTransaction({ id = "first:" .. r.id .. ":" .. index, ts = r.ts, by = r.by, member = member, amount = isFirst and 10 or 0,
                    reason = "Guild-first bonus: " .. e.label, raid = e.raid, system = true })
            end
        end
    end
    for _, r in ipairs(records("DKU")) do
        local a = r.data
        if a.status == "AWARDED" then
            local cancelled = get("DKZ", r.id)
            GD:UpdateDKPDerivedTransaction({ id = "loot:" .. r.id, ts = r.ts, by = r.by, member = a.winner,
                amount = cancelled and cancelled.ts <= r.ts and 0 or -a.cost, reason = "Loot: " .. a.label,
                item = a.item, label = a.label, spec = a.spec, auction = r.id, loot = true, system = true })
        end
    end
    for _, r in ipairs(records("DKL")) do
        local a = r.data
        transaction(r, "loot:" .. r.id, a.member, -a.cost, "Loot: " .. a.label, { item = a.item, label = a.label, spec = a.spec, loot = true })
    end
    for _, r in ipairs(records("DKX")) do
        local source = GD:GetDKPBucket().dkpAwards[r.data.target]
        if source and not source.reverses then
            GD:UpdateDKPDerivedTransaction({ id = "rev:" .. source.id, ts = r.ts, by = r.by, member = source.member, amount = -source.amount,
                reason = "Reversal: " .. r.data.label, reverses = source.id, system = true })
        end
    end
    rebuilding = false
end
function GD:OnDKPLedgerChanged() rebuild() end

local pending = {}
local function validate(kind, recordID, ts, author, content)
    if not schemas[kind] or not clean(recordID, 100) or recordID == "" or not integer(ts, 1, GD:GetDKPTime() + 120)
        or not clean(author, 100) or author == "" or type(content) ~= "string" or #content > 6500 then return end
    local data = schemas[kind](split(content))
    if not data then return end
    if (kind == "DKU" or kind == "DKS") and key(data.owner) ~= key(author) then return end
    if kind == "DKX" and recordID ~= data.target then return end
    if (kind == "DKT" or kind == "DKY") and recordID ~= data.loot then return end
    if kind == "DKJ" and recordID ~= data.auction .. ":" .. data.revision then return end
    if kind == "DKM" and recordID ~= key(recordID) then return end
    return { kind = kind, id = recordID, ts = ts, by = author, content = content, data = data }
end
local function receive(kind, recordID, ts, author, content, sender)
    if not GD:GetDKPBucket() then return end
    local r = validate(kind, recordID, ts, author, content)
    if not r then return end
    local _, rank = GD:GetDKPGuildMember(sender)
    if rank == nil then
        if #pending < 300 then pending[#pending + 1] = { kind, recordID, ts, author, content, sender, bucket = GD:GetDKPBucket() } end
        return
    end
    if rank > 1 then return end
    local storageKey, previous = kind .. ":" .. recordID, get(kind, recordID)
    if previous then
        if kind == "DKU" or kind == "DKS" then
            if key(previous.by) ~= key(author) or r.data.revision <= previous.data.revision then return end
            if kind == "DKU" and (previous.data.status == "AWARDED" or previous.data.status == "CANCELLED") then return end
            if kind == "DKS" and previous.data.ended > 0 then return end
        elseif kind == "DKM" or kind == "DKY" then
            if ts < previous.ts or (ts == previous.ts and key(author) <= key(previous.by)) then return end
        elseif kind == "DKZ" then
            if ts > previous.ts or (ts == previous.ts and key(author) >= key(previous.by)) then return end
        else return end
    end
    GD:GetDKPBucket().dkpSystems[storageKey] = r
    if kind == "DKM" then GD:GetDKPBucket().dkpAccounts[recordID] = { main = r.data.main, ts = ts, by = author } end
    rebuild()
    if kind == "DKJ" and not GD.dkpImporting then
        local auction = GD:GetDKPAuction(r.data.auction)
        if auction and GD:GetDKPActiveAuction() == auction and key(r.by) == key(auction.data.owner) and key(r.data.member) == key(own()) then
            GD.dkpBidStatus = r.data.withdraw and "Bid withdrawn." or "Bid accepted."
        end
    end
    if kind == "DKU" and GD.ObserveDKPMasterLoot then
        local ok = pcall(GD.ObserveDKPMasterLoot, GD, r)
        if not ok then print("GuildDB: Automatic Master Loot is unavailable for this item. DKP is recorded; distribute it manually and mark delivery in Loot.") end
    end
    notify()
end
for kind in pairs(schemas) do
    local wire = kind
    GD:RegisterDKPRecordHandler(wire, function(...) receive(wire, ...) end, 6500)
end
local function publish(kind, recordID, fields)
    local previous = get(kind, recordID)
    local ts = math.max(GD:GetDKPTime(), previous and previous.ts + 1 or 0)
    local content, author = pack(fields), own()
    if not validate(kind, recordID, ts, author, content) then return false, "The DKP record is invalid or too large." end
    receive(kind, recordID, ts, author, content, author)
    GD:SendDKPRecord(kind, recordID, ts, author, content, kind == "DKJ" or kind == "DKU")
    return true
end

function GD:GetDKPSystemRecords(kind) return records(kind) end
function GD:GetDKPAuction(recordID) return get("DKU", recordID) end
function GD:GetDKPAuctionStatus(r)
    local cancelled = r and get("DKZ", r.id)
    if cancelled and (r.data.status ~= "AWARDED" or cancelled.ts <= r.ts) then return "CANCELLED" end
    return r and r.data.status
end
function GD:GetDKPActiveAuction()
    local result
    for _, r in ipairs(records("DKU")) do
        local status = self:GetDKPAuctionStatus(r)
        if status == "OPEN" or status == "REVIEW" then
            if not result or r.data.opened < result.data.opened or (r.data.opened == result.data.opened and r.id < result.id) then result = r end
        end
    end
    return result
end
function GD:GetDKPAuctionLeader(r)
    if not r then return end
    local bids = {}
    for _, bid in ipairs(r.data.bids) do bids[#bids + 1] = bid end
    table.sort(bids, function(a, b)
        if a.spec ~= b.spec then return a.spec == "MS" end
        if a.amount ~= b.amount then return a.amount > b.amount end
        if a.order ~= b.order then return a.order < b.order end
        return key(a.member) < key(b.member)
    end)
    return bids[1], bids
end
function GD:GetDKPNextBid(auctionID, spec)
    local r = self:GetDKPAuction(auctionID)
    if not r or (spec ~= "MS" and spec ~= "OS") then return end
    local amount = r.data.minimum
    for _, bid in ipairs(r.data.bids) do
        if bid.spec == spec then amount = math.max(amount, bid.amount + r.data.increment) end
    end
    return amount
end
function GD:GetDKPAvailable(name, exceptAuction)
    local available, account = self:GetDKPBalance(name), key(self:GetDKPAccount(name))
    for _, r in ipairs(records("DKU")) do
        local status = self:GetDKPAuctionStatus(r)
        if r.id ~= exceptAuction and (status == "OPEN" or status == "REVIEW") then
            local bid = self:GetDKPAuctionLeader(r)
            if bid and key(self:GetDKPAccount(bid.member)) == account then available = available - bid.amount end
        end
    end
    return math.max(0, available)
end
local function auctionFields(a)
    local bids = {}
    for _, bid in ipairs(a.bids) do bids[#bids + 1] = pack({ bid.member, bid.amount, bid.spec, bid.order }) end
    return { a.revision, a.owner, a.item, a.label, a.minimum, a.increment, a.ends, a.status, pack(bids), a.winner, a.cost, a.spec, pack(a.participants), a.opened }
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for k, v in pairs(value) do result[k] = copy(v) end; return result
end
local function changeAuction(r, callback)
    if not allowed() or key(r.data.owner) ~= key(own()) then return false, "Only the auction's hosting officer can change it." end
    if get("DKZ", r.id) then return false, "This auction was stopped by an officer." end
    if r.data.status == "AWARDED" or r.data.status == "CANCELLED" then return false, "This auction has already finished." end
    local a = copy(r.data); a.revision = a.revision + 1
    local ok, message = callback(a)
    if not ok then return false, message end
    return publish("DKU", r.id, auctionFields(a))
end

function GD:StartDKPAuction(item, minimum, increment, duration)
    if not allowed() then return false, "Only the GM or rank 1 officers can start auctions." end
    self:ResolveExpiredDKPAuctions()
    if self:GetDKPActiveAuction() then return false, "Finish or cancel the current guild auction first." end
    local itemID, label = self:GetDKPItemIdentity(item)
    if not itemID then return false, "Enter an item link or numeric item ID." end
    minimum = integer(minimum, 1, 1000000); increment = integer(increment, 1, 1000000); duration = integer(duration, 10, 300)
    if not minimum or not increment or not duration then return false, "Use whole numbers: minimum/increment 1-1,000,000; duration 10-300 seconds." end
    local participants = self:GetDKPParticipants(true)
    if #participants == 0 then return false, "Join a raid or party with eligible guild members before starting an auction." end
    local auctionID = id("auction")
    local success, message = publish("DKU", auctionID, { 1, own(), itemID, label, minimum, increment, GD:GetDKPTime() + duration, "OPEN", "", "", 0, "", pack(participants), GD:GetDKPTime() })
    return success, message or "Auction opened. Players in this raid can bid.", auctionID
end
function GD:CanBidDKPAuction(r, name)
    if not self:IsDKPEnabled() or not r or get("DKZ", r.id) then return false, "This auction is unavailable." end
    local canonical, rank = self:GetDKPGuildMember(name)
    if not canonical then return false, "Only current guild members can bid." end
    local host = key(canonical) == key(r.data.owner) and rank and rank <= 1
    local inRaid = false
    for _, member in ipairs(self:GetDKPRaidMembers(true)) do
        if key(member) == key(canonical) then inRaid = true end
    end
    if not inRaid then return false, "Join the auction's raid or party to bid." end
    if host then return true end
    for _, member in ipairs(r.data.participants) do if key(member) == key(canonical) then return true end end
    return false, "You were not in the group when this auction started. Ask the host to restart it."
end
function GD:AcceptDKPBid(auctionID, member, amount, spec, withdraw)
    local r = self:GetDKPAuction(auctionID)
    if not r then return false, "Auction not found." end
    if self:GetDKPActiveAuction() ~= r then return false, "Another auction is being resolved first." end
    if r.data.status ~= "OPEN" or GD:GetDKPTime() >= r.data.ends then return false, "Bidding has closed." end
    local eligible, eligibilityReason = self:CanBidDKPAuction(r, member)
    if not eligible then return false, eligibilityReason end
    local canonical, account = self:GetDKPGuildMember(member), key(self:GetDKPAccount(member))
    if not withdraw then
        amount = integer(amount, r.data.minimum, 1000000)
        if not amount or (spec ~= "MS" and spec ~= "OS") then return false, "Enter a whole-number bid at or above the minimum and choose MS or OS." end
        if amount > self:GetDKPAvailable(canonical, auctionID) then return false, "Your bid exceeds your available DKP." end
        local nextBid = self:GetDKPNextBid(auctionID, spec)
        if amount < nextBid then return false, "The next " .. spec .. " bid must be at least " .. nextBid .. " DKP." end
    end
    if not allowed() or key(r.data.owner) ~= key(own()) then return false, "Only the auction host accepts bids." end
    local order = 0
    for _, bid in ipairs(r.data.bids) do order = math.max(order, bid.order) end
    local ends = r.data.ends
    if not withdraw and ends - GD:GetDKPTime() < 10 then ends = GD:GetDKPTime() + 10 end
    local revision = r.data.revision + 1
    local success, message = publish("DKJ", auctionID .. ":" .. revision, { auctionID, revision, canonical, withdraw and 0 or amount, spec or "MS", order + 1, ends, withdraw and "1" or "0" })
    return success, message or (withdraw and "Bid withdrawn." or "Bid accepted.")
end
function GD:SubmitDKPBid(auctionID, amount, spec, withdraw)
    local r = self:GetDKPAuction(auctionID)
    local eligible, eligibilityReason = self:CanBidDKPAuction(r, own())
    if not eligible then return false, eligibilityReason end
    if key(r.data.owner) == key(own()) then return self:AcceptDKPBid(auctionID, own(), amount, spec, withdraw) end
    if r.data.status ~= "OPEN" or GD:GetDKPTime() >= r.data.ends then return false, "Bidding has closed." end
    if not withdraw and (not integer(amount, r.data.minimum, 1000000) or tonumber(amount) > self:GetDKPAvailable(own(), auctionID)) then return false, "Enter a bid within your available DKP and the item's minimum." end
    local now = GetTime and GetTime() or GD:GetDKPTime()
    if self.dkpLastBidRequest and now - self.dkpLastBidRequest < 0.5 then return false, "Wait a moment before sending another bid." end
    self.dkpLastBidRequest = now
    self.dkpBidStatus = nil
    self:SendDKPRecord("DKR", auctionID, GD:GetDKPTime(), own(), pack({ withdraw and "withdraw" or "bid", tostring(amount or 0), spec or "MS" }), true)
    return true, "Bid sent. Waiting for the hosting officer to accept it."
end
local bidThrottle = {}
GD:RegisterDKPRecordHandler("DKR", function(auctionID, ts, author, content, sender)
    if not allowed() or not clean(content, 120) or not integer(ts, GD:GetDKPTime() - 60, GD:GetDKPTime() + 60) then return end
    local r, canonical = GD:GetDKPAuction(auctionID), GD:GetDKPGuildMember(sender)
    if not r or key(r.data.owner) ~= key(own()) or not canonical or key(canonical) ~= key(author) then return end
    local f = split(content)
    if #f ~= 3 or (f[1] ~= "bid" and f[1] ~= "withdraw") then return end
    local bucketKey = tostring(GD:GetDKPBucket()) .. ":" .. key(canonical)
    local now = GetTime and GetTime() or GD:GetDKPTime()
    if bidThrottle[bucketKey] and now - bidThrottle[bucketKey] < 0.2 then return end
    bidThrottle[bucketKey] = now
    local ok, message = GD:AcceptDKPBid(auctionID, canonical, f[2], f[3], f[1] == "withdraw")
    -- The authoritative bid delta confirms successful bids and updates every
    -- bidder at once. Only rejections require a separate response packet.
    if not ok then GD:SendDKPRecord("DKN", auctionID, GD:GetDKPTime(), own(), pack({ canonical, "0", message or "Bid rejected." }), true) end
end, 120)
GD:RegisterDKPRecordHandler("DKN", function(auctionID, ts, author, content, sender)
    local r = GD:GetDKPAuction(auctionID)
    if not r or not clean(content, 400) or key(GD:GetDKPGuildMember(sender)) ~= key(r.data.owner) then return end
    local f = split(content)
    if #f == 3 and key(f[1]) == key(own()) then
        GD.dkpBidStatus = f[3]
        if GD.RefreshDKPAuctionPopup then GD:RefreshDKPAuctionPopup() end
    end
end, 400)
function GD:CloseDKPAuction(auctionID)
    local r = self:GetDKPAuction(auctionID)
    if not r then return false, "Auction not found." end
    return changeAuction(r, function(a) a.status = "REVIEW"; return true end)
end
function GD:CancelDKPAuction(auctionID)
    local r = self:GetDKPAuction(auctionID)
    if not r then return false, "Auction not found." end
    return changeAuction(r, function(a) a.status = "CANCELLED"; return true end)
end
function GD:RemoveDKPAuctionBid(auctionID, member)
    local r = self:GetDKPAuction(auctionID)
    if not r then return false, "Auction not found." end
    if not allowed() or key(r.data.owner) ~= key(own()) then return false, "Only the auction host can remove bids." end
    if r.data.status ~= "OPEN" and r.data.status ~= "REVIEW" then return false, "This auction has finished." end
    local revision = r.data.revision + 1
    return publish("DKJ", auctionID .. ":" .. revision, { auctionID, revision, member, 0, "MS", revision, r.data.ends, "1" })
end
function GD:AwardDKPAuction(auctionID, expectedMember, expectedCost)
    local r = self:GetDKPAuction(auctionID)
    if not r or self:GetDKPActiveAuction() ~= r or r.data.status ~= "REVIEW" then return false, "Close bidding and review the current auction first." end
    local leader = self:GetDKPAuctionLeader(r)
    if not leader then return false, "No bids. Cancel this auction or record a manual purchase." end
    if key(leader.member) ~= key(expectedMember) or leader.amount ~= tonumber(expectedCost) then return false, "The leading bid changed. Review the winner again." end
    if not self:CanBidDKPAuction(r, leader.member) or leader.amount > self:GetDKPAvailable(leader.member, auctionID) then return false, "The winner is no longer eligible or cannot afford this bid." end
    local raid = self:GetDKPActiveRaid()
    local ok, message = changeAuction(r, function(a) a.status = "AWARDED"; a.winner = leader.member; a.cost = leader.amount; a.spec = leader.spec; return true end)
    if ok and raid then publish("DKT", "loot:" .. auctionID, { raid.id, "loot:" .. auctionID }) end
    return ok, message
end

function GD:RecordDKPLoot(member, item, cost, spec)
    if not allowed() then return false, "Only the GM or rank 1 officers can record purchases." end
    local eligible, canonical = self:IsDKPEligible(member)
    local itemID, label = self:GetDKPItemIdentity(item)
    cost = integer(cost, 1, 1000000)
    if not eligible or not itemID or not cost or (spec ~= "MS" and spec ~= "OS") then return false, "Choose a level-60 guild member, a valid item, a whole-number cost and MS/OS." end
    if cost > self:GetDKPAvailable(canonical) then return false, "This purchase exceeds the member's available DKP." end
    local purchaseID, raid = id("purchase"), self:GetDKPActiveRaid()
    local ok, message = publish("DKL", purchaseID, { canonical, itemID, label, cost, spec })
    if ok and raid then publish("DKT", "loot:" .. purchaseID, { raid.id, "loot:" .. purchaseID }) end
    return ok, message
end
function GD:GetDKPLootDelivery(lootID)
    local loot = self:GetDKPBucket() and self:GetDKPBucket().dkpAwards[lootID]
    if not loot or not loot.loot then return end
    if get("DKX", lootID) then return "Refunded" end
    local record = get("DKY", lootID)
    return record and record.data.delivered and "Delivered" or "Pending", record
end
function GD:SetDKPLootDelivery(lootID, delivered)
    if not allowed() then return false, "Only officers can update loot delivery." end
    local status = self:GetDKPLootDelivery(lootID)
    if not status or status == "Refunded" or type(delivered) ~= "boolean" then return false, "Select an unrefunded loot award." end
    return publish("DKY", lootID, { lootID, delivered and "1" or "0" })
end

-- Compare complete DKP snapshots on demand. Acknowledgements are never inferred from presence.
function GD:GetDKPSyncFingerprint()
    local bucket, lines = self:GetDKPBucket(), {}
    if not bucket then return "0:0:0" end
    local config = bucket.dkpConfig or {}
    lines[#lines + 1] = pack({ "config", config.enabled and "1" or "0", config.ts or 0, config.by or "" })
    for member, balance in pairs(bucket.dkpBalances or {}) do lines[#lines + 1] = pack({ "balance", member, balance }) end
    for recordID, r in pairs(bucket.dkpAwards or {}) do
        lines[#lines + 1] = pack({ "award", recordID, r.ts, r.by, r.member, r.amount, r.reason, r.reverses or "" })
    end
    for item, r in pairs(bucket.dkpStartingBids or {}) do lines[#lines + 1] = pack({ "price", item, r.ts, r.by, r.amount, r.label }) end
    for recordID, r in pairs(bucket.dkpSystems or {}) do lines[#lines + 1] = pack({ "system", recordID, r.ts, r.by, r.content }) end
    table.sort(lines)
    local first, second = 0, 0
    for _, line in ipairs(lines) do
        line = #line .. ":" .. line
        for i = 1, #line do first = (first * 31 + line:byte(i)) % 2147483647; second = (second * 37 + line:byte(i)) % 2147483629 end
    end
    return #lines .. ":" .. first .. ":" .. second
end
function GD:CheckDKPSync()
    if not allowed() or self:IsDKPSoloTesting() then return false, "Exit Solo Test and use an officer character to check guild DKP sync." end
    if self.dkpSyncCheck and self.dkpSyncCheck.bucket == self:GetDKPBucket() and GD:GetDKPTime() - self.dkpSyncCheck.ts < 5 then return false, "Wait five seconds before checking again." end
    local check = { bucket = self:GetDKPBucket(), id = id("sync"), ts = GD:GetDKPTime(), fingerprint = self:GetDKPSyncFingerprint(), members = {} }
    for index = 1, GetNumGuildMembers(true) do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(index)
        if name then check.members[key(name)] = { name = name, online = online == true or online == 1 } end
    end
    check.members[key(own())] = { name = own(), online = true, fingerprint = check.fingerprint, received = GD:GetDKPTime() }
    self.dkpSyncCheck = check
    self:SendDKPRecord("DKSC", check.id, check.ts, own(), check.fingerprint, true)
    return true, "DKP sync check sent. Updated guild clients will acknowledge their snapshot."
end
GD:RegisterDKPRecordHandler("DKSC", function(recordID, ts, author, content, sender)
    local canonical, rank = GD:GetDKPGuildMember(sender)
    if not GD:IsDKPEnabled() or not canonical or rank == nil or rank > 1 or key(canonical) ~= key(author)
        or not clean(recordID, 100) or not integer(ts, GD:GetDKPTime() - 60, GD:GetDKPTime() + 60) or not clean(content, 100) or not content:match("^%d+:%d+:%d+$") then return end
    local now = GetTime and GetTime() or GD:GetDKPTime()
    local throttle = GD.dkpSyncReply
    if throttle and throttle.bucket == GD:GetDKPBucket() and now - throttle.at < 2 then return end
    GD.dkpSyncReply = { bucket = GD:GetDKPBucket(), at = now }
    GD:SendDKPRecord("DKSA", recordID, GD:GetDKPTime(), own(), GD:GetDKPSyncFingerprint(), true)
end, 100)
GD:RegisterDKPRecordHandler("DKSA", function(recordID, ts, author, content, sender)
    local check, canonical = GD.dkpSyncCheck, GD:GetDKPGuildMember(sender)
    if not check or check.bucket ~= GD:GetDKPBucket() or check.id ~= recordID or not canonical or key(canonical) ~= key(author)
        or not integer(ts, check.ts, GD:GetDKPTime() + 60) or GD:GetDKPTime() - check.ts > 60 or not clean(content, 100) or not content:match("^%d+:%d+:%d+$") then return end
    local member = check.members[key(canonical)]
    if member then member.fingerprint, member.received = content, GD:GetDKPTime() end
end, 100)

-- Each officer keeps a guild-specific local queue; only starting an item broadcasts it.
function GD:GetDKPAuctionQueue()
    local bucket = self:GetDKPBucket()
    if not bucket then return {} end
    bucket.dkpAuctionQueues = bucket.dkpAuctionQueues or {}
    bucket.dkpAuctionQueues[key(own())] = bucket.dkpAuctionQueues[key(own())] or {}
    return bucket.dkpAuctionQueues[key(own())]
end
function GD:AddDKPQueuedAuction(item, minimum, increment, duration)
    if not allowed() then return false, "Only officers can manage the auction queue." end
    local itemID, label = self:GetDKPItemIdentity(item)
    minimum = integer(minimum, 1, 1000000); increment = integer(increment, 1, 1000000); duration = integer(duration, 10, 300)
    if not itemID or not minimum or not increment or not duration then return false, "Enter a valid item, whole-number bids and a 10-300 second duration." end
    local queue = self:GetDKPAuctionQueue()
    if #queue >= 40 then return false, "The queue holds up to 40 items." end
    queue[#queue + 1] = { id = id("queue"), item = itemID, label = label, minimum = minimum, increment = increment, duration = duration }
    notify(); return true, "Item added to your auction queue."
end
function GD:ChangeDKPQueuedAuction(queueID, direction)
    if not allowed() then return false, "Only officers can manage the auction queue." end
    local queue = self:GetDKPAuctionQueue()
    for index, entry in ipairs(queue) do
        if entry.id == queueID then
            if direction == "remove" then table.remove(queue, index)
            elseif direction == -1 or direction == 1 then
                local target = index + direction
                if not queue[target] then return false, "This item is already at that end of the queue." end
                queue[index], queue[target] = queue[target], queue[index]
            else return false, "Choose move up, move down or remove." end
            notify(); return true, "Queue updated."
        end
    end
    return false, "That queued item is no longer available."
end
function GD:StartNextDKPQueuedAuction()
    if not allowed() then return false, "Only officers can start queued auctions." end
    local queue = self:GetDKPAuctionQueue(); local entry = queue[1]
    if not entry then return false, "Your auction queue is empty." end
    local ok, message, auctionID = self:StartDKPAuction(entry.item, entry.minimum, entry.increment, entry.duration)
    if ok then table.remove(queue, 1); notify() end
    return ok, message, auctionID
end

function GD:GetDKPRaidSummary(raidID)
    local raid = get("DKS", raidID)
    if not raid then return end
    local summary = { raid = raid, attendees = {}, bosses = {}, loot = {}, earned = 0, checkpoints = 0 }
    local attendees = {}
    for _, event in ipairs(records("DKV")) do
        if event.data.raid == raidID and key(event.by) == key(raid.data.owner) then
            summary.checkpoints = summary.checkpoints + 1
            if event.data.event == "boss" then summary.bosses[#summary.bosses + 1] = event.data.boss end
            for _, member in ipairs(event.data.participants) do
                attendees[member] = attendees[member] or { name = member, checkpoints = 0, earned = 0 }
                attendees[member].checkpoints = attendees[member].checkpoints + 1
            end
        end
    end
    local awards = self:GetDKPBucket().dkpAwards or {}
    for _, award in pairs(awards) do
        local source = award.reverses and awards[award.reverses] or award
        if source and source.raid == raidID and not source.loot then
            summary.earned = summary.earned + award.amount
            if attendees[source.member] then attendees[source.member].earned = attendees[source.member].earned + award.amount end
        end
    end
    for _, link in ipairs(records("DKT")) do
        local loot = awards[link.data.loot]
        if link.data.raid == raidID and loot and loot.loot and key(loot.by) == key(link.by) then
            summary.loot[#summary.loot + 1] = { item = loot.item, label = loot.label, member = loot.member, cost = math.abs(loot.amount),
                spec = loot.spec, refunded = get("DKX", loot.id) ~= nil, delivery = self:GetDKPLootDelivery(loot.id) }
        end
    end
    for _, value in pairs(attendees) do summary.attendees[#summary.attendees + 1] = value end
    table.sort(summary.attendees, function(a,b) return key(a.name) < key(b.name) end)
    table.sort(summary.bosses)
    return summary
end
function GD:ReverseDKPRecord(recordID, reason)
    if not allowed() then return false, "Only the GM or rank 1 officers can reverse DKP entries." end
    local source = self:GetDKPBucket().dkpAwards[recordID]
    if not source or source.reverses or source.amount == 0 or #recordID > 96 then return false, "Select an original DKP entry to reverse." end
    if get("DKX", recordID) then return false, "This entry has already been reversed." end
    if not clean(reason, 160) or not reason:find("%S") then return false, "Enter a reversal reason of 1-160 characters." end
    return publish("DKX", recordID, { recordID, reason })
end
function GD:LinkDKPAlt(alt, main)
    return false, "DKP belongs to each character separately. Main/alt DKP linking is disabled."
end

function GD:GetDKPActiveRaid()
    for _, r in ipairs(records("DKS")) do if r.data.ended == 0 and not get("DKZ", r.id) then return r end end
end
function GD:StopStaleDKPRecording(recordID, scope)
    if not allowed() then return false, "Only the GM or rank 1 officers can stop stale operations." end
    local r = get(scope == "auction" and "DKU" or "DKS", recordID)
    if not r or get("DKZ", recordID) then return false, "This recording has already stopped or is missing." end
    if scope == "auction" then
        if self:GetDKPAuctionStatus(r) == "AWARDED" or r.data.status == "CANCELLED" then return false, "The auction has already finished." end
        if GD:GetDKPTime() < r.data.ends + 60 then return false, "Wait until 60 seconds after the bidding deadline before stopping another host's auction." end
    elseif r.data.ended > 0 then return false, "This raid recording has finished." end
    return publish("DKZ", recordID, { scope, "Stopped by " .. own() })
end
local function raidFields(a) return { a.revision, a.owner, a.label, a.started, a.ended, a.zone, pack(a.participants) } end
local function raidEvent(raid, kind, label, boss)
    if not allowed() or key(raid.data.owner) ~= key(own()) or raid.data.ended > 0 then return false, "Only the recording raid's host can award attendance or kills." end
    local participants = GD:GetDKPParticipants(true)
    if #participants == 0 then return false, "No connected guild members are currently in the raid or party." end
    local suffix = kind == "boss" and ("boss:" .. key(boss)) or kind
    -- Boss names are bounded in the saved identity; collisions are explicitly rejected.
    local recordID = raid.id .. ":" .. suffix
    if #recordID > 100 then return false, "Boss name is too long. Use a shorter consistent name." end
    if get("DKV", recordID) then return false, "This raid event has already been awarded." end
    return publish("DKV", recordID, { raid.id, kind, label, boss or "", pack(participants) })
end
function GD:StartDKPRaid(label)
    if not allowed() then return false, "Only the GM or rank 1 officers can record a raid." end
    if self:GetDKPActiveRaid() then return false, "End the current recording before starting another raid." end
    if not clean(label, 100) or not label:find("%S") then return false, "Enter a raid name." end
    local participants = self:GetDKPParticipants(true)
    if #participants == 0 then return false, "Join a raid or party with connected guild members first." end
    local raidID = id("raid")
    local zone = (GetRealZoneText and GetRealZoneText() or label):sub(1, 100)
    local ok, message = publish("DKS", raidID, { 1, own(), label, GD:GetDKPTime(), 0, zone, pack(participants) })
    if ok then raidEvent(get("DKS", raidID), "ontime", "On time: " .. label, "") end
    return ok, message or "Raid recording started; 10 on-time DKP awarded to the current guild raiders.", raidID
end
function GD:RecordDKPBoss(label)
    local raid = self:GetDKPActiveRaid()
    if not raid or not clean(label, 60) or not label:find("%S") then return false, "Start a raid recording and enter a boss name (up to 60 characters)." end
    return raidEvent(raid, "boss", "Boss kill: " .. label, label)
end
function GD:HandleDKPBossKill(label)
    local raid = self:GetDKPActiveRaid()
    if not allowed() or not raid or key(raid.data.owner) ~= key(own()) then return false end
    local participants = self:GetDKPParticipants(true)
    if #participants == 0 then return false end
    local before = self:GetDKPBalance(participants[1])
    local ok, message = self:RecordDKPBoss(label)
    if ok then
        local amount = self:GetDKPBalance(participants[1]) - before
        print("GuildDB: Auto DKP - " .. label .. ": +" .. amount .. " DKP to " .. #participants .. " guild raider(s).")
    end
    return ok, message
end
function GD:EndDKPRaid()
    local raid = self:GetDKPActiveRaid()
    if not raid or not allowed() or key(raid.data.owner) ~= key(own()) then return false, "Only the recording raid's host can end it." end
    local participants = self:GetDKPParticipants(true)
    if #participants > 0 and not get("DKV", raid.id .. ":finish") then
        local ok, message = raidEvent(raid, "finish", "Raid end: " .. raid.data.label, "")
        if not ok then return false, message end
    end
    local a = copy(raid.data); a.revision = a.revision + 1; a.ended = GD:GetDKPTime()
    local ok, message = publish("DKS", raid.id, raidFields(a))
    if ok and #participants == 0 then return true, "Raid recording ended. No end bonus was awarded because no connected guild participants remain in your group." end
    return ok, message
end
function GD:GetDKPUnfinishedRaidReason(raid)
    if not raid or self:GetDKPActiveRaid() ~= raid then return end
    if key(raid.data.owner) == key(own()) then
        if not ((IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup())) then return "You are no longer in a party or raid." end
        return
    end
    local notice = self.dkpUnfinishedRaidNotice
    if notice and notice.bucket == self:GetDKPBucket() and notice.raidID == raid.id then return "The recording host left their group without ending the raid." end
    for index = 1, GetNumGuildMembers(true) do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(index)
        if key(name) == key(raid.data.owner) and (online == false or online == 0) then return "The recording host is offline and this raid has not been ended." end
    end
end
GD:RegisterDKPRecordHandler("DKRA", function(recordID, ts, author, content, sender)
    if not allowed() or not integer(ts, GD:GetDKPTime() - 60, GD:GetDKPTime() + 60) or (content ~= "unfinished" and content ~= "resumed") then return end
    local raid = GD:GetDKPActiveRaid()
    local canonical, rank = GD:GetDKPGuildMember(sender)
    if not raid or raid.id ~= recordID or not canonical or rank == nil or rank > 1 or key(canonical) ~= key(author) or key(canonical) ~= key(raid.data.owner) then return end
    local previous = GD.dkpUnfinishedRaidNoticeVersion
    if previous and previous.bucket == GD:GetDKPBucket() and previous.raidID == recordID and ts <= previous.ts then return end
    GD.dkpUnfinishedRaidNoticeVersion = { bucket = GD:GetDKPBucket(), raidID = recordID, ts = ts }
    GD.dkpUnfinishedRaidNotice = content == "unfinished" and { bucket = GD:GetDKPBucket(), raidID = recordID } or nil
end, 20)
function GD:CheckDKPRaidRecordingSafety()
    local raid = self:GetDKPActiveRaid()
    if not allowed() or self:IsDKPSoloTesting() or not raid then
        self.dkpRecordingSafety = nil; return
    end
    local state = self.dkpRecordingSafety
    if not state or state.bucket ~= self:GetDKPBucket() or state.raidID ~= raid.id then
        state = { bucket = self:GetDKPBucket(), raidID = raid.id }; self.dkpRecordingSafety = state
    end
    local reason = self:GetDKPUnfinishedRaidReason(raid)
    local host = key(raid.data.owner) == key(own())
    if not reason then
        if host and state.broadcast then
            state.noticeTS = math.max(GD:GetDKPTime(), (state.noticeTS or 0) + 1)
            self:SendDKPRecord("DKRA", raid.id, state.noticeTS, own(), "resumed", true)
        end
        state.ungroupedSince, state.notified, state.broadcast = nil, false, false; return
    end
    state.ungroupedSince = state.ungroupedSince or GD:GetDKPTime()
    if GD:GetDKPTime() - state.ungroupedSince < 5 then return end
    if host and not state.broadcast then
        state.noticeTS = math.max(GD:GetDKPTime(), (state.noticeTS or 0) + 1); state.broadcast = true
        self:SendDKPRecord("DKRA", raid.id, state.noticeTS, own(), "unfinished", true)
    end
    -- Notify officer clients once, and defer each local dialog during combat.
    if state.notified or (InCombatLockdown and InCombatLockdown()) then return end
    if self.ShowDKPRaidEndReminder then
        state.notified = true
        self:ShowDKPRaidEndReminder(raid, reason)
    end
end
function GD:FinishDKPAuction(auctionID)
    local r = self:GetDKPAuction(auctionID)
    if not r or not allowed() or key(r.data.owner) ~= key(own()) then return false, "Only the auction host can finish it." end
    local status = self:GetDKPAuctionStatus(r)
    if status == "OPEN" then
        local ok, message = self:CloseDKPAuction(r.id)
        if not ok then return false, message end
    elseif status ~= "REVIEW" then return false, "This auction has already finished." end
    local leader = self:GetDKPAuctionLeader(self:GetDKPAuction(r.id))
    local awarded, reason
    if leader then awarded, reason = self:AwardDKPAuction(r.id, leader.member, leader.amount) end
    if awarded then return true, "Auction ended: " .. self:Display(leader.member) .. " won " .. r.data.label .. " for " .. leader.amount .. " DKP." end
    local cancelled, message = self:CancelDKPAuction(r.id)
    return cancelled, cancelled and ("Auction ended without an award. " .. (reason or "No bids were placed.")) or message
end
function GD:ResolveExpiredDKPAuctions()
    if not allowed() or self.dkpResolvingAuctions then return end
    self.dkpResolvingAuctions = true
    for _, r in ipairs(records("DKU")) do
        local status = self:GetDKPAuctionStatus(r)
        if (status == "OPEN" or status == "REVIEW") and GD:GetDKPTime() >= r.data.ends and key(r.data.owner) == key(own()) then
            local ok, message = self:FinishDKPAuction(r.id)
            if ok and message then print("GuildDB: " .. message) end
        end
    end
    self.dkpResolvingAuctions = nil
end
function GD:TickDKPSystems()
    if not self:GetDKPBucket() then return end
    self:CheckDKPRaidRecordingSafety()
    self:ResolveExpiredDKPAuctions()
    if self.RefreshDKPAuctionPopup then self:RefreshDKPAuctionPopup() end
end
function GD:SendDKPSystemsHistory()
    if not self:CanConfigureDKP() then return end
    for _, r in pairs(self:GetDKPBucket().dkpSystems) do self:SendDKPRecord(r.kind, r.id, r.ts, r.by, r.content) end
end
GD:RegisterHistoryProvider(function() GD:SendDKPSystemsHistory() end, false)
GD:RegisterEventHandler("GUILD_ROSTER_UPDATE", function()
    identityCache = nil
    local queued = pending; pending = {}
    for _, r in ipairs(queued) do if r.bucket == GD:GetDKPBucket() then receive(unpack(r)) end end
end)
GD:RegisterEventHandler("ENCOUNTER_END", function(_, encounterID, encounterName, difficulty, size, success)
    if success == 1 then GD:HandleDKPBossKill(encounterName) end
end)
GD:RegisterEventHandler("BOSS_KILL", function(_, encounterID, encounterName)
    GD:HandleDKPBossKill(encounterName)
end)
GD:RegisterEventHandler("PLAYER_LOGIN", function()
    local ticker = CreateFrame("Frame")
    local elapsed = 0
    ticker:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= 0.5 then elapsed = 0; GD:TickDKPSystems() end
    end)
end)

function GD:ExportDKPBackup()
    if self:IsDKPSoloTesting() then return false, "Exit Solo Test before exporting guild DKP." end
    if not allowed() then return false, "Only officers can export DKP backups." end
    local lines = { "GuildDB-DKP-2|" .. self:Encode(self.guildName) }
    for _, r in pairs(self:GetDKPBucket().dkpAwards) do
        if not r.system then lines[#lines + 1] = pack({ r.amount < 0 and "DKD" or "DKA", r.id, r.ts, r.by, table.concat({ r.member, math.abs(r.amount), r.reason }, "\n") }) end
    end
    for item, r in pairs(self:GetDKPBucket().dkpStartingBids) do lines[#lines + 1] = pack({ "DKB", item, r.ts, r.by, r.amount .. "\n" .. r.label }) end
    for _, r in pairs(self:GetDKPBucket().dkpSystems) do lines[#lines + 1] = pack({ r.kind, r.id, r.ts, r.by, r.content }) end
    table.sort(lines, function(a, b) if a == b then return false end; if a:match("^GuildDB%-DKP") then return true end; if b:match("^GuildDB%-DKP") then return false end; return a < b end)
    return true, table.concat(lines, "\n")
end
function GD:ImportDKPBackup(value)
    if self:IsDKPSoloTesting() then return false, "Exit Solo Test before restoring guild DKP." end
    if not allowed() then return false, "Only officers can restore DKP backups." end
    if type(value) ~= "string" or #value > 2000000 then return false, "Backup is missing or too large (2 MB maximum)." end
    value = value:gsub("\r", "")
    local header, rest = value:match("^([^\n]+)\n?(.*)$")
    if header ~= "GuildDB-DKP-2|" .. self:Encode(self.guildName) then return false, "This is not a DKP backup for your current guild." end
    local entries = {}
    for line in rest:gmatch("[^\n]+") do
        local f = split(line)
        if #f ~= 5 or not clean(f[2], 100) or f[2] == "" or not integer(f[3], 1, GD:GetDKPTime() + 120) or not clean(f[4], 100) or f[4] == "" then return false, "Malformed backup record; nothing was imported." end
        if schemas[f[1]] then
            if not validate(f[1], f[2], tonumber(f[3]), f[4], f[5]) then return false, "Invalid DKP system record; nothing was imported." end
        elseif f[1] == "DKA" or f[1] == "DKD" then
            local member, amount, reason = f[5]:match("^([^\n]+)\n(%d+)\n([^\n]+)$")
            if not clean(member, 100) or not integer(amount, 1, 1000000) or not clean(reason, 160) or not reason:find("%S") then return false, "Invalid balance record; nothing was imported." end
            if f[2]:sub(1, 10) == "dkp:start:" and (f[1] ~= "DKA" or tonumber(amount) ~= 1000 or reason ~= "One-time starting balance" or f[2] ~= "dkp:start:" .. key(member)) then return false, "Invalid starting grant; nothing was imported." end
        elseif f[1] == "DKB" then
            local amount, label = f[5]:match("^(%d+)\n([^\n]+)$")
            if not integer(f[2], 1, 2147483647) or not integer(amount, 1, 1000000) or not clean(label, 100) or label:find("|") then return false, "Invalid item price; nothing was imported." end
        else return false, "Unsupported backup record; nothing was imported." end
        entries[#entries + 1] = f
        if #entries > 20000 then return false, "Too many records in this backup." end
    end
    local original, stage = self.bucket, {}
    for k, v in pairs(original) do stage[k] = k:match("^dkp") and copy(v) or v end
    self.bucket, self.dkpImporting = stage, true
    local success, errorMessage = pcall(function()
        for _, f in ipairs(entries) do self.recordHandlers[f[1]](f[2], tonumber(f[3]), f[4], f[5], own()) end
        rebuild()
    end)
    self.bucket, self.dkpImporting = original, nil
    rebuilding = false
    if not success then return false, "Restore failed; original data preserved: " .. tostring(errorMessage) end
    for k, v in pairs(stage) do if k:match("^dkp") then original[k] = v end end
    self:SendDKPSystemsHistory()
    for _, f in ipairs(entries) do if not schemas[f[1]] then self:SendRecord(f[1], f[2], tonumber(f[3]), f[4], f[5]) end end
    notify()
    return true, "Merged " .. #entries .. " backup records. Existing entries were preserved and duplicates were not charged twice."
end

-- Ephemeral auction feedback and officer readiness checks. No balance writes.
local _, GD = ...
local function key(value) return tostring(value or ""):lower() end
local function own() return GD:GetDKPGuildMember(GD:PlayerName()) or GD:PlayerName() end
local function clock() return GetTime and GetTime() or GD:GetDKPTime() end
local function state()
    local bucket = GD:GetDKPBucket()
    if not GD.dkpLive or GD.dkpLive.bucket ~= bucket then
        GD.dkpLive = { bucket = bucket, seen = {}, tracked = {}, results = {} }
    end
    return GD.dkpLive
end
function GD:GetDKPAuctionConnection(auction)
    if not auction or not self:IsDKPEnabled() then return false, "Auction unavailable." end
    if self:IsDKPSoloTesting() then return true end
    local _, rank = self:GetDKPGuildMember(auction.data.owner)
    if not rank or rank > 1 then return false, "Host is no longer an officer. Ask an officer to recover this auction." end
    local present = false
    for _, member in ipairs(self:GetDKPParticipants(true)) do
        if key(member) == key(auction.data.owner) then present = true end
    end
    if not present then return false, "Host offline or outside your group. Bids cannot be confirmed." end
    if key(own()) == key(auction.data.owner) then return true end
    local seen = state().seen[auction.id]
    if seen and clock() - seen > 25 then
        return false, "Host updates delayed. Waiting for connection; bids are temporarily disabled."
    end
    return true
end
function GD:ObserveDKPLiveRecord(record, sender)
    if self.dkpImporting or not self:IsDKPEnabled() then return end
    local auction = record.kind == "DKU" and self:GetDKPAuction(record.id)
        or record.kind == "DKJ" and self:GetDKPAuction(record.data.auction)
        or record.kind == "DKZ" and self:GetDKPAuction(record.id)
    if not auction then return end
    local live = state()
    if key(self:GetDKPGuildMember(sender)) == key(auction.data.owner) and math.abs(self:GetDKPTime() - record.ts) <= 60 then
        live.seen[auction.id] = clock()
    end
    local status = self:GetDKPAuctionStatus(auction)
    if status == "OPEN" and self:GetDKPTime() < auction.data.ends and self:CanBidDKPAuction(auction, own()) then
        live.tracked[auction.id] = true
    elseif (status == "AWARDED" or status == "CANCELLED") and live.tracked[auction.id] and not live.results[auction.id] then
        live.results[auction.id] = true
        if self.ShowDKPAuctionResult then self:ShowDKPAuctionResult(auction) end
    end
end
GD:RegisterDKPRecordHandler("DKH", function(auctionID, ts, author, content, sender)
    local auction = GD:GetDKPAuction(auctionID)
    local canonical, rank = GD:GetDKPGuildMember(sender)
    if not GD:IsDKPEnabled() or not auction or not canonical or not rank or rank > 1
        or key(canonical) ~= key(author) or key(canonical) ~= key(auction.data.owner)
        or content ~= "alive" or type(ts) ~= "number" or math.abs(GD:GetDKPTime() - ts) > 30 then return end
    state().seen[auctionID] = clock()
end, 5)
function GD:TickDKPLive()
    local live, auction = state(), self:GetDKPActiveAuction()
    if not self:IsDKPEnabled() then
        if self.RefreshDKPLiveControls then self:RefreshDKPLiveControls() end
        return
    end
    if auction and key(auction.data.owner) == key(own()) and self:CanConfigureDKP() and not self:IsDKPSoloTesting()
        and (not live.heartbeat or clock() - live.heartbeat >= 10) then
        live.heartbeat = clock()
        self:SendDKPRecord("DKH", auction.id, self:GetDKPTime(), own(), "alive", true)
    end
end
function GD:RecoverDKPAuction(auctionID)
    if not self:IsDKPEnabled() or not self:CanConfigureDKP() or self:IsDKPSoloTesting() then return false, "Only officers can recover live guild auctions." end
    local auction = self:GetDKPAuction(auctionID)
    if not auction or self:GetDKPActiveAuction() ~= auction then return false, "This is no longer the active auction." end
    -- A connected but delayed host must never be displaced.
    for _, member in ipairs(self:GetDKPParticipants(true)) do
        if key(member) == key(auction.data.owner) then return false, "The host is still connected in your group." end
    end
    local grouped = false
    local recoveryOfficer, recoveryRank
    local originalGroup = false
    for _, member in ipairs(self:GetDKPParticipants(true)) do
        if key(member) == key(own()) then grouped = true end
        for _, participant in ipairs(auction.data.participants) do if key(participant) == key(member) then originalGroup = true end end
        local _, rank = self:GetDKPGuildMember(member)
        if rank and rank <= 1 and (not recoveryOfficer or rank < recoveryRank or rank == recoveryRank and key(member) < key(recoveryOfficer)) then
            recoveryOfficer, recoveryRank = member, rank
        end
    end
    if not grouped then return false, "Join the raid or party before recovering an auction." end
    if not originalGroup then return false, "Join the original auction's group before recovering it." end
    if key(recoveryOfficer) ~= key(own()) then return false, "Recovery officer: " .. tostring(recoveryOfficer) .. ". The GM takes priority, then the first officer by name, to prevent competing restarts." end
    if self:GetDKPTime() < auction.data.ends + 60 then return false, "Recovery is available 60 seconds after the bidding deadline." end
    local ok, message = self:StopStaleDKPRecording(auctionID, "auction", true)
    if not ok then return false, message end
    local started, reason, newID = self:StartDKPAuction(auction.data.item, auction.data.minimum, auction.data.increment, 60)
    return started, started and "Auction recovered under your control. Previous bids were cleared; everyone must bid again." or reason, newID
end
function GD:CheckDKPReadiness()
    if not self:IsDKPEnabled() or not self:CanConfigureDKP() or self:IsDKPSoloTesting() then return false, "Only officers can check live raid readiness." end
    local live = state()
    if live.readiness and clock() - live.readiness.started < 5 then return false, "Wait five seconds before checking again." end
    local members = self:GetDKPParticipants(true)
    if #members == 0 then return false, "Join a raid or party first." end
    live.sequence = (live.sequence or 0) + 1
    local check = { id = "ready:" .. self:GetDKPTime() .. ":" .. live.sequence .. ":" .. own(), started = clock(), members = {} }
    for _, member in ipairs(members) do check.members[key(member)] = { name = member } end
    check.members[key(own())] = { name = own(), version = self.version or "unknown", enabled = true, received = clock() }
    live.readiness = check
    self:SendDKPRecord("DKRC", check.id, self:GetDKPTime(), own(), "check", true)
    return true, "Raid readiness check sent."
end
function GD:GetDKPReadiness() return state().readiness end
GD:RegisterDKPRecordHandler("DKRC", function(recordID, ts, author, content, sender)
    local canonical, rank = GD:GetDKPGuildMember(sender)
    if not GD:GetDKPBucket() or not canonical or not rank or rank > 1 or key(canonical) ~= key(author)
        or content ~= "check" or #recordID > 100 or type(ts) ~= "number" or math.abs(GD:GetDKPTime() - ts) > 30 then return end
    local grouped = false
    -- This path must also work with DKP disabled on the receiving client.
    local inRaid = IsInRaid and IsInRaid()
    local count = inRaid and (GetNumGroupMembers and GetNumGroupMembers() or 40)
        or IsInGroup and IsInGroup() and (GetNumSubgroupMembers and GetNumSubgroupMembers() or 4) or 0
    for i = 0, math.min(40, count) do
        local name
        if i == 0 then name = own()
        elseif inRaid and GetRaidRosterInfo then name = GetRaidRosterInfo(i)
        elseif GetUnitName then name = GetUnitName("party" .. i, true) end
        if key(GD:GetDKPGuildMember(name)) == key(canonical) then grouped = true end
    end
    if not grouped then return end
    local live = state()
    if live.lastReply and clock() - live.lastReply < 2 then return end
    live.lastReply = clock()
    GD:SendDKPRecord("DKRS", recordID, GD:GetDKPTime(), own(), (GD:IsDKPEnabled() and "1" or "0") .. "|" .. (GD.version or "unknown"), true)
end, 5)
GD:RegisterDKPRecordHandler("DKRS", function(recordID, ts, author, content, sender)
    if not GD:CanConfigureDKP() or not GD:IsDKPEnabled() then return end
    local check, canonical = state().readiness, GD:GetDKPGuildMember(sender)
    if not check or check.id ~= recordID or clock() - check.started > 30 or not canonical or key(canonical) ~= key(author)
        or type(ts) ~= "number" or math.abs(GD:GetDKPTime() - ts) > 30 then return end
    local member = check.members[key(canonical)]
    local enabled, version = content:match("^([01])|([%w%.%-]+)$")
    if not member or not version or #version > 30 then return end
    member.enabled, member.version, member.received = enabled == "1", version, clock()
end, 40)

-- Optional physical delivery. DKP awards remain independent of game loot delivery.
local _, GD = ...
local function key(value) return tostring(value or ""):lower() end
local function masterLooter()
    local query = GetLootMethod or (C_PartyInfo and C_PartyInfo.GetLootMethod)
    if not query then return false end
    local method, partyIndex, raidIndex = query()
    if method ~= "master" then return false end
    return partyIndex == 0 or (raidIndex and UnitIsUnit and UnitIsUnit("raid" .. raidIndex, "player"))
end
local function source(slot)
    if not GetLootSourceInfo then return end
    local info, values = { GetLootSourceInfo(slot) }, {}
    for i = 1, #info, 2 do
        if type(info[i]) ~= "string" or type(info[i + 1]) ~= "number" then return end
        values[#values + 1] = info[i] .. ":" .. info[i + 1]
    end
    if #values == 0 then return end
    table.sort(values); return table.concat(values, "|")
end
local function uniqueSlot(item)
    if not GetNumLootItems or not GetLootSlotLink then return end
    local found
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        if link and link:match("item:(%d+)") == tostring(item) then
            if found then return end -- Never guess between identical drops.
            found = slot
        end
    end
    return found
end
function GD:ObserveDKPMasterLoot(auction)
    if self.dkpImporting or self:IsDKPSoloTesting() or not self:IsDKPEnabled() or not self:CanConfigureDKP()
        or not self.GetSetting or not self:GetSetting("dkpAutoMasterLoot") then return end
    local bucket = self:GetDKPBucket()
    if self.dkpMasterLootBucket ~= bucket then
        self.dkpMasterLootBucket, self.dkpMasterLootBindings, self.dkpMasterLootReceipts = bucket, {}, {}
    end
    local bindings, a = self.dkpMasterLootBindings, auction.data
    if self:GetDKPAuctionStatus(auction) == "CANCELLED" then bindings[auction.id] = nil; return end
    if a.status == "OPEN" and a.ends > self:GetDKPTime() and not bindings[auction.id] then
        local session = self.dkpMasterLootSession
        local slot = session and masterLooter() and uniqueSlot(a.item)
        bindings[auction.id] = { session = session, slot = slot, link = slot and GetLootSlotLink(slot), source = slot and source(slot) }
    elseif a.status == "AWARDED" then
        local binding = bindings[auction.id]
        if not binding or binding.attempted then return end
        binding.attempted = true
        local function pending(reason) print("GuildDB: Auto Master Loot: " .. reason .. " Deliver " .. a.label .. " to " .. self:Display(a.winner) .. " manually; delivery remains Pending.") end
        if not masterLooter() then return pending("You are no longer the Master Looter.") end
        if InCombatLockdown and InCombatLockdown() then return pending("Distribution deferred to manual delivery during combat.") end
        local session, slot = self.dkpMasterLootSession, binding.slot
        if not session or session ~= binding.session or not slot or not binding.source or not GetLootSlotLink
            or uniqueSlot(a.item) ~= slot or GetLootSlotLink(slot) ~= binding.link or source(slot) ~= binding.source then
            return pending("The original unique boss loot slot is no longer available.")
        end
        if not GiveMasterLoot or not GetMasterLootCandidate then return pending("This client does not expose Master Loot distribution.") end
        if session.claimed[slot] then return pending("This loot slot already has a delivery attempt.") end
        if self:GetDKPLootDelivery("loot:" .. auction.id) ~= "Pending" then return end
        local candidate, winner = nil, self:GetDKPGuildMember(a.winner)
        for index = 1, 40 do
            local name = GetMasterLootCandidate(slot, index)
            if name and key(self:GetDKPGuildMember(name)) == key(winner) then
                if candidate then return pending("The recipient could not be uniquely identified.") end
                candidate = index
            end
        end
        if not candidate or not winner then return pending("The winner is not eligible for this loot slot.") end
        session.claimed[slot] = true
        local receipt = { id = "loot:" .. auction.id, member = winner, item = tostring(a.item), at = self:GetDKPTime() }
        self.dkpMasterLootReceipts[receipt.id] = receipt
        local ok, result = pcall(GiveMasterLoot, slot, candidate)
        if not ok or result == false then self.dkpMasterLootReceipts[receipt.id] = nil; return pending("The game did not accept automatic distribution.") end
        print("GuildDB: Master Loot requested for " .. self:Display(winner) .. ": " .. a.label .. ". Complete any game confirmation; delivery stays Pending until receipt is confirmed.")
    end
end
GD:RegisterEventHandler("LOOT_OPENED", function()
    GD.dkpMasterLootSession = { claimed = {} }
end)
GD:RegisterEventHandler("LOOT_CLOSED", function() GD.dkpMasterLootSession = nil end)
GD:RegisterEventHandler("CHAT_MSG_LOOT", function(_, message, recipient)
    if GD.dkpImporting or not GD:IsDKPEnabled() or not GD:CanConfigureDKP() or GD:IsDKPSoloTesting() or GD.dkpMasterLootBucket ~= GD:GetDKPBucket() then return end
    local item = type(message) == "string" and message:match("item:(%d+)")
    local member = GD:GetDKPGuildMember(recipient)
    if not item or not member then return end
    for id, receipt in pairs(GD.dkpMasterLootReceipts or {}) do
        if GD:GetDKPTime() - receipt.at > 30 then GD.dkpMasterLootReceipts[id] = nil
        elseif receipt.item == item and key(receipt.member) == key(member) then
            GD.dkpMasterLootReceipts[id] = nil
            if GD:GetDKPLootDelivery(id) == "Pending" then GD:SetDKPLootDelivery(id, true) end
            return
        end
    end
end)

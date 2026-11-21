-- Crafting request board with claims and automatic expiry.
local _, GH = ...
GH:RegisterBucket("crafting", function() return {} end)

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function activeRequests()
    local result = {}
    for _, request in ipairs((GH.bucket and GH.bucket.crafting) or {}) do
        if request.status ~= "done" and (request.expires or 0) > time() then result[#result + 1] = request end
    end
    table.sort(result, function(a, b) return a.ts > b.ts end)
    return result
end
GH.GetActiveCraftingRequests = activeRequests

local function payload(request)
    return table.concat({ request.expires, request.status, request.crafter or "", request.item, request.details }, "\n")
end

local function saveRequest(request)
    local list = GH.bucket.crafting
    for i, current in ipairs(list) do
        if current.id == request.id then list[i] = request; if GH.RefreshUI then GH:RefreshUI() end; return end
    end
    GH:StoreRecord("crafting", request)
end

GH:RegisterRecordHandler("M", function(id, ts, author, content)
    local expires, status, crafter, item, details = content:match("^(%d+)\n(.-)\n(.-)\n(.-)\n(.*)$")
    expires = tonumber(expires)
    if not expires or not item or item == "" or #item > 100 or #details > 300 or (status ~= "pending" and status ~= "claimed" and status ~= "done") then return end
    local old
    for _, request in ipairs(GH.bucket.crafting) do if request.id == id then old = request; break end end
    if old and (old.updatedAt or old.ts) > ts then return end
    saveRequest({ id = id, ts = old and old.ts or ts, updatedAt = ts, by = author, expires = expires, status = status, crafter = crafter, item = item, details = details })
end)

local function applyStatus(id, status, crafter, ts)
    for _, request in ipairs(GH.bucket.crafting) do
        if request.id == id then
            if (request.updatedAt or request.ts) > ts then return end
            request.status, request.crafter, request.updatedAt = status, crafter, ts
            if GH.RefreshUI then GH:RefreshUI() end
            return
        end
    end
end

GH:RegisterRecordHandler("MC", function(id, ts, crafter)
    applyStatus(id, "claimed", crafter, ts)
end)
GH:RegisterRecordHandler("MD", function(id, ts, crafter)
    applyStatus(id, "done", crafter, ts)
end)

GH:RegisterHistoryProvider(function()
    local requests = {}
    for _, request in ipairs(GH.bucket.crafting or {}) do requests[#requests + 1] = request end
    table.sort(requests, function(a, b) return a.ts > b.ts end)
    for i = math.min(#requests, 12), 1, -1 do
        local request = requests[i]
        GH:SendRecord("M", request.id, request.updatedAt or request.ts, request.by, payload(request))
    end
end)

function GH:PostCraftingRequest(item, details)
    if not self.bucket then return false, "Join a guild first." end
    item, details = trim(item), trim(details)
    if item == "" then return false, "Enter an item or recipe to request." end
    local entry = self:NewRecord({ item = item:sub(1, 100), details = details:sub(1, 300), status = "pending", crafter = "", expires = time() + 7 * 24 * 60 * 60 })
    entry.updatedAt = entry.ts
    self:StoreRecord("crafting", entry, "M", payload(entry))
    return true, "Crafting request posted; it expires in 7 days."
end

function GH:ChangeCraftingRequest(id, done)
    local entry
    for _, candidate in ipairs(activeRequests()) do if candidate.id == id then entry = candidate; break end end
    if not entry then return false, "That crafting request is no longer active." end
    local player = UnitName and UnitName("player") or ""
    if done and entry.by:lower() ~= player:lower() and entry.crafter:lower() ~= player:lower() and not self:CanManage() then
        return false, "Only the requester, claiming crafter, or an officer can close it."
    end
    if not done and entry.status == "claimed" and entry.crafter:lower() ~= player:lower() then
        return false, "This request has already been claimed."
    end
    player = player ~= "" and player or "Guild member"
    local ts = time()
    entry.status = done and "done" or "claimed"
    if not done then entry.crafter = player end
    entry.updatedAt = ts
    if done then self:SendRecord("MD", entry.id, ts, player, "done") else self:SendRecord("MC", entry.id, ts, player, "claimed") end
    if self.RefreshUI then self:RefreshUI() end
    return true, "Crafting request " .. entry.status .. "."
end

function GH:FindGuildCrafters(needle)
    needle = trim(needle):lower()
    if needle == "" then return {} end
    local matches = {}
    for _, member in ipairs(self.roster or {}) do
        local profile = self.bucket and self.bucket.profiles and self.bucket.profiles[member.name]
        if not profile and self.bucket and self.bucket.profiles then
            local memberBase = (member.name:match("^([^-]+)") or member.name):lower()
            for profileName, candidate in pairs(self.bucket.profiles) do
                if (profileName:match("^([^-]+)") or profileName):lower() == memberBase then profile = candidate; break end
            end
        end
        if member.online and profile and (profile.professions or ""):lower():find(needle, 1, true) then
            matches[#matches + 1] = member.name .. " - " .. profile.professions
        end
    end
    return matches
end

GH:RegisterCommand("craft", function(rest)
    local action, content = rest:match("^(%S+)%s*(.*)$")
    action = (action or ""):lower()
    if action == "request" then
        local item, details = content:match("^(.-)%s*|%s*(.*)$")
        local _, message = GH:PostCraftingRequest(item or content, details)
        print("GuildDB: " .. message)
    elseif action == "claim" or action == "done" then
        local entry = activeRequests()[tonumber(content) or 0]
        local _, message = GH:ChangeCraftingRequest(entry and entry.id, action == "done")
        print("GuildDB: " .. message)
    elseif action == "who" then
        local needle = trim(content):lower()
        if needle == "" then print("GuildDB: Use /gd craft who Recipe or profession."); return end
        local matches = GH:FindGuildCrafters(needle)
        print(#matches > 0 and ("GuildDB crafters: " .. table.concat(matches, "; ")) or "GuildDB: No online member lists that profession or recipe in their profile.")
    else GH.activeTab = "Crafting"; GH:Open() end
end)

GH:RegisterTab("Crafting", function()
    if not GH.bucket then return "Join a guild to see crafting requests." end
    local requests = activeRequests()
    if #requests == 0 then return "No active crafting requests. Use /gd craft request Item | Details to post one." end
    local lines = { "Crafting requests · posts expire after 7 days", "Use /gd craft claim # to claim; /gd craft done # to close; /gd craft who Recipe to search online profiles.", "" }
    for index, entry in ipairs(requests) do
        local days = math.max(1, math.ceil((entry.expires - time()) / (24 * 60 * 60)))
        lines[#lines + 1] = ("%d. %s · %s · %d day(s) left"):format(index, GH:Display(entry.item), entry.status:upper(), days)
        if entry.details ~= "" then lines[#lines + 1] = GH:Display(entry.details) end
        lines[#lines + 1] = entry.status == "claimed" and ("Claimed by " .. GH:Display(entry.crafter)) or ("Requested by " .. GH:Display(entry.by))
        lines[#lines + 1] = ""
    end
    return table.concat(lines, "\n")
end)

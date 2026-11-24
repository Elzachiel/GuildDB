-- Short-lived guild requests for groups, roles, and activities.
local _, GD = ...
GD:RegisterBucket("lookingFor", function() return {} end)

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function activeRequests()
    local result = {}
    for _, request in ipairs((GD.bucket and GD.bucket.lookingFor) or {}) do
        if not request.closed and (request.expires or 0) > time() then result[#result + 1] = request end
    end
    table.sort(result, function(a, b) return a.ts > b.ts end)
    return result
end
GD.GetActiveLookingRequests = activeRequests

local function requestPayload(request)
    return table.concat({ request.role, request.activity, request.details, request.expires }, "\n")
end

local function updateRequest(id, closed)
    for _, request in ipairs(GD.bucket.lookingFor or {}) do
        if request.id == id then
            request.closed = closed
            request.closedAt = time()
            if GD.RefreshUI then GD:RefreshUI() end
            return
        end
    end
end

GD:RegisterRecordHandler("L", function(id, ts, author, content)
    local role, activity, details, expires = content:match("^(.-)\n(.-)\n(.-)\n(%d+)$")
    expires = tonumber(expires)
    if not role or #role > 60 or #activity > 100 or #details > 250 or not expires or expires <= ts then return end
    GD:StoreRecord("lookingFor", { id = id, ts = ts, by = author, role = role, activity = activity, details = details, expires = expires })
end)
GD:RegisterRecordHandler("LC", function(id) updateRequest(id, true) end)

GD:RegisterHistoryProvider(function()
    local requests = {}
    for _, request in ipairs(GD.bucket.lookingFor or {}) do requests[#requests + 1] = request end
    table.sort(requests, function(a, b) return a.ts > b.ts end)
    for i = math.min(#requests, 12), 1, -1 do
        local request = requests[i]
        GD:SendRecord("L", request.id, request.ts, request.by, requestPayload(request))
        if request.closed then GD:SendRecord("LC", request.id, request.closedAt or request.ts, request.by, "closed") end
    end
end)

function GD:PostLookingRequest(role, activity, details)
    if not self.bucket then return false, "Join a guild first." end
    role, activity, details = trim(role), trim(activity), trim(details)
    if role == "" or activity == "" then return false, "Role and activity are required." end
    local request = self:NewRecord({ role = role:sub(1, 60), activity = activity:sub(1, 100), details = details:sub(1, 250), expires = time() + 3 * 60 * 60 })
    self:StoreRecord("lookingFor", request, "L", requestPayload(request))
    return true, "Looking For post created; it expires in 3 hours."
end

function GD:CloseLookingRequest(id)
    local request
    for _, candidate in ipairs(activeRequests()) do if candidate.id == id then request = candidate; break end end
    if not request then return false, "That Looking For post is no longer active." end
    local player = UnitName and UnitName("player") or ""
    if request.by:lower() ~= player:lower() and not self:CanManage() then return false, "You can only close your own post." end
    updateRequest(request.id, true)
    self:SendRecord("LC", request.id, time(), player, "closed")
    return true, "Looking For post closed."
end

GD:RegisterCommand("looking", function(rest)
    local action, content = rest:match("^(%S+)%s*(.*)$")
    action = (action or ""):lower()
    if action == "close" then
        local request = activeRequests()[tonumber(content) or 0]
        local _, result = GD:CloseLookingRequest(request and request.id)
        print("GuildDB: " .. result)
        return
    end
    if action == "list" then GD.activeTab = "Requests"; GD:Open(); return end
    local role, activity, details = rest:match("^(.-)%s*|%s*(.-)%s*|%s*(.*)$")
    local _, result = GD:PostLookingRequest(role, activity, details)
    print("GuildDB: " .. result)
end)
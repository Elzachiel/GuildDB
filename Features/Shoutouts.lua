-- Guild member shoutouts.
local _, GD = ...
GD:RegisterBucket("shoutouts", function() return {} end)
GD:RegisterBucket("shoutoutDeletes", function() return {} end)

local function isOfficer(name)
    if not GetNumGuildMembers or not GetGuildRosterInfo then return end
    local count = GetNumGuildMembers(true)
    if not count or count == 0 then return end
    for index = 1, count do
        local member, _, rank = GetGuildRosterInfo(index)
        if member and member:lower() == tostring(name):lower() then
            rank = tonumber(rank)
            return rank ~= nil and rank <= 1
        end
    end
    return false
end

local function applyDeletion(id, ts, author)
    if not GD.bucket or type(id) ~= "string" or id == "" or #id > 100
        or type(ts) ~= "number" or ts <= 0 or ts > time() + 60 or not isOfficer(author) then return false end
    GD.bucket.shoutoutDeletes = GD.bucket.shoutoutDeletes or {}
    local previous = GD.bucket.shoutoutDeletes[id]
    if previous and previous.ts >= ts then return false end
    GD.bucket.shoutoutDeletes[id] = { ts = ts, by = author }
    local records = GD.bucket.shoutouts or {}
    for index = #records, 1, -1 do if records[index].id == id then table.remove(records, index) end end
    if GD.RefreshUI then GD:RefreshUI() end
    return true
end

function GD:DeleteShoutout(id)
    if not self.bucket then return false, "Join a guild first." end
    if not self:CanManage() then return false, "Only the GM or rank 1 officers can delete shoutouts." end
    local found
    for _, record in ipairs(self.bucket.shoutouts or {}) do if record.id == id then found = true; break end end
    if not found then return false, "That shoutout is no longer available." end
    local ts, author = time(), self:PlayerName()
    if not applyDeletion(id, ts, author) then return false, "Could not delete the shoutout. Check the guild roster and try again." end
    self:SendRecord("SX", id, ts, author, "deleted")
    return true, "Shoutout deleted and shared with the guild."
end

local pending = {}
local function receiveDeletion(id, ts, author)
    if not GD.bucket then return end
    if isOfficer(author) == nil then
        if #pending < 100 then pending[#pending + 1] = { id, ts, author, bucket = GD.bucket } end
        return
    end
    applyDeletion(id, ts, author)
end
GD:RegisterRecordHandler("SX", receiveDeletion, 20)
GD:RegisterEventHandler("GUILD_ROSTER_UPDATE", function()
    local records = pending
    pending = {}
    for _, record in ipairs(records) do
        if record.bucket == GD.bucket then receiveDeletion(record[1], record[2], record[3]) end
    end
end)

local function clean(value)
    return tostring(value or ""):gsub("[%c|]", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

function GD:GetGuildShoutouts()
    local records = {}
    for _, record in ipairs(self.bucket and self.bucket.shoutouts or {}) do records[#records + 1] = record end
    table.sort(records, function(a, b)
        if a.ts ~= b.ts then return a.ts > b.ts end
        return a.id < b.id
    end)
    return records
end

function GD:PostShoutout(target, text)
    if not self.bucket then return false, "Join a guild first." end
    target, text = clean(target), clean(text)
    if target == "" or text == "" then return false, "Use /gd shout Player Name | message" end
    local record = self:NewRecord({ target = target:sub(1, 80), text = text:sub(1, 250) })
    self:StoreRecord("shoutouts", record, "S", record.target .. "\n" .. record.text)
    return true, "Shoutout saved and sent to online GuildDB users."
end

GD:RegisterRecordHandler("S", function(id, ts, author, content)
    if not GD.bucket or (GD.bucket.shoutoutDeletes or {})[id] then return end
    local target, text = content:match("^(.-)\n(.*)$")
    if not target or target == "" or #target > 80 or #text > 250 then return end
    GD:StoreRecord("shoutouts", { id = id, ts = ts, by = author, target = target, text = text })
end)

GD:RegisterHistoryProvider(function()
    if not GD.bucket then return end
    for id, record in pairs(GD.bucket.shoutoutDeletes or {}) do
        GD:SendRecord("SX", id, record.ts, record.by, "deleted")
    end
    local list = GD.bucket.shoutouts or {}
    for i = math.min(#list, 12), 1, -1 do
        local record = list[i]
        GD:SendRecord("S", record.id, record.ts, record.by, record.target .. "\n" .. record.text)
    end
end)

GD:RegisterCommand("shout", function(rest)
    local target, text = rest:match("^(.-)%s*|%s*(.*)$")
    local _, result = GD:PostShoutout(target, text)
    print("GuildDB: " .. result)
end)

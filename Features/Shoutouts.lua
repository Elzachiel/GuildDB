-- Guild member shoutouts.
local _, GD = ...
GD:RegisterBucket("shoutouts", function() return {} end)

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
    local target, text = content:match("^(.-)\n(.*)$")
    if not target or target == "" or #target > 80 or #text > 250 then return end
    GD:StoreRecord("shoutouts", { id = id, ts = ts, by = author, target = target, text = text })
end)

GD:RegisterHistoryProvider(function()
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

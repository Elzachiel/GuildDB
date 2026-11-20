-- Guild member shoutouts.
local _, GH = ...
GH:RegisterBucket("shoutouts", function() return {} end)

local function clean(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function GH:PostShoutout(target, text)
    if not self.bucket then return false, "Join a guild first." end
    target, text = clean(target), clean(text)
    if target == "" or text == "" then return false, "Use /gh shout Player Name | message" end
    local record = self:NewRecord({ target = target:sub(1, 80), text = text:sub(1, 250) })
    self:StoreRecord("shoutouts", record, "S", record.target .. "\n" .. record.text)
    return true, "Shoutout saved and sent to online Guild Hall users."
end

GH:RegisterRecordHandler("S", function(id, ts, author, content)
    local target, text = content:match("^(.-)\n(.*)$")
    if not target or target == "" or #target > 80 or #text > 250 then return end
    GH:StoreRecord("shoutouts", { id = id, ts = ts, by = author, target = target, text = text })
end)

GH:RegisterHistoryProvider(function()
    local list = GH.bucket.shoutouts or {}
    for i = math.min(#list, 12), 1, -1 do
        local record = list[i]
        GH:SendRecord("S", record.id, record.ts, record.by, record.target .. "\n" .. record.text)
    end
end)

GH:RegisterCommand("shout", function(rest)
    local target, text = rest:match("^(.-)%s*|%s*(.*)$")
    local _, result = GH:PostShoutout(target, text)
    print("Guild Hall: " .. result)
end)

-- Guild announcements: officer-only creation, display, and sync.
local _, GH = ...
GH:RegisterBucket("announcements", function() return {} end)

local function clean(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function GH:PostAnnouncement(text)
    if not self:CanManage() then return false, "Only the guild leader or rank 1 can post announcements." end
    text = clean(text)
    if text == "" then return false, "Enter announcement text." end
    local record = self:NewRecord({ text = text:sub(1, 600) })
    self:StoreRecord("announcements", record, "A", record.text)
    return true, "Announcement saved and sent to online Guild Hall users."
end

GH:RegisterRecordHandler("A", function(id, ts, author, content)
    if #content > 600 then return end
    GH:StoreRecord("announcements", { id = id, ts = ts, by = author, text = content })
end)

GH:RegisterHistoryProvider(function()
    local list = GH.bucket.announcements or {}
    for i = math.min(#list, 12), 1, -1 do
        local record = list[i]
        GH:SendRecord("A", record.id, record.ts, record.by, record.text)
    end
end)

GH:RegisterCommand("post", function(text)
    local _, result = GH:PostAnnouncement(text)
    print("Guild Hall: " .. result)
end)

GH:RegisterTab("Announcements", function()
    if not GH.bucket then return "Join a guild to see announcements." end
    local lines = {}
    for _, record in ipairs(GH.bucket.announcements or {}) do
        lines[#lines + 1] = ("%s · %s\n%s"):format(date("%b %d, %I:%M %p", record.ts), GH:Display(record.by), GH:Display(record.text))
    end
    return #lines > 0 and table.concat(lines, "\n\n") or "No announcements yet. Officers can post with /gh post Message text."
end)

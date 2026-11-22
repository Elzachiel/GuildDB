-- Local read receipts; these are never included in guild history or messages.
local _, GD = ...
GD:RegisterBucket("unreadSeen", function() return {} end)

local function revision(record)
    return tostring(record.ts or 0) .. "|" .. tostring(record.by or "")
end

local function snapshot(tab)
    local bucket, result = GD.bucket, {}
    if not bucket then return result end
    if tab == "Events" then
        for _, event in ipairs(GD:GetUpcomingEvents()) do
            if event.id and not event.preview then
                result[event.id] = revision(event)
            end
        end
    elseif tab == "Guild Info" then
        local info = bucket.guildInfo
        if info and info.ts then result.info = revision(info) end
    elseif tab == "Polls" then
        for _, poll in ipairs(bucket.polls or {}) do
            if poll.id then
                result[poll.id] = revision(poll) .. "|" .. tostring(poll.closed == true) ..
                    "|" .. tostring(poll.closedAt or 0) .. "|" .. tostring(poll.closedBy or "")
            end
        end
    end
    return result
end

local tracked = { Events = true, ["Guild Info"] = true, Polls = true }

local function receipts()
    if not GD.bucket then return end
    GD.bucket.unreadSeen = GD.bucket.unreadSeen or {}
    local player = GD:PlayerName()
    GD.bucket.unreadSeen[player] = GD.bucket.unreadSeen[player] or {}
    return GD.bucket.unreadSeen[player]
end

function GD:GetTabUnreadCount(tab)
    if not tracked[tab] then return 0 end
    local seen = receipts()
    if not seen then return 0 end
    local previous, count = seen[tab] or {}, 0
    for id, value in pairs(snapshot(tab)) do
        if previous[id] ~= value then count = count + 1 end
    end
    return count
end

function GD:UpdateUnreadState(active)
    -- Background refreshes run even while the window is hidden. Only content
    -- displayed in a visible section counts as read.
    if not tracked[active] or not self.frame or not self.frame:IsShown() then return end
    local seen = receipts()
    if seen then seen[active] = snapshot(active) end
end

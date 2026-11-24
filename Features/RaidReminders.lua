-- Local reminders and per-character receipts; never sent to guild peers.
local _, GD = ...
local LEAD_TIME = 15 * 60
local nextCheck = 0
GD:RegisterBucket("raidReminderSeen", function() return {} end)

function GD:CheckRaidReminders()
    if not self.bucket or not self:GetSetting("raidReminders") then return end
    local player = self:PlayerName()
    if not player or player == "" or player == "Guild member" then return end
    local now = time()
    self.bucket.raidReminderSeen = self.bucket.raidReminderSeen or {}
    local allSeen = self.bucket.raidReminderSeen
    allSeen[player] = allSeen[player] or {}
    local seen, upcoming = allSeen[player], {}
    for _, event in ipairs(self.bucket.events or {}) do
        local at = tonumber(event.at)
        if event.id and at and at > now and not event.preview
            and not (self.bucket.eventDeletes or {})[event.id] then
            upcoming[event.id] = at
            local response = (event.rsvps or {})[player]
            local status = type(response) == "table" and response.status or response
            local removal = (event.signupDeletes or {})[player]
            local removed = removal and (type(response) ~= "table" or (removal.ts or 0) >= (response.ts or 0))
            if (status == "going" or status == "tentative") and not removed
                and at - now <= LEAD_TIME and seen[event.id] ~= at then
                seen[event.id] = at
                local minutes = math.max(1, math.ceil((at - now) / 60))
                local message = ("Starts in %d min (%s). Your signup: %s."):format(
                    minutes, date("%I:%M %p", at), status == "going" and "Going" or "Maybe")
                print("GuildDB reminder: " .. self:Display(event.title or "Guild event") .. " - " .. message)
                if self.ShowPopout then
                    self:ShowPopout("Raid reminder", event.title or "Guild event", message,
                        "Interface/Icons/INV_Misc_GroupLooking", function()
                            GD.activeTab = "Events"
                            GD:Open()
                        end, 12)
                end
            end
        end
    end
    for id, at in pairs(seen) do
        if upcoming[id] ~= at then seen[id] = nil end
    end
end

function GD:RaidReminderUpdate(now)
    if not self.playerLoggedIn or now < nextCheck then return end
    nextCheck = now + 10
    self:CheckRaidReminders()
end

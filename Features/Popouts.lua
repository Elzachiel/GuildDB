-- Compact, queued screen notifications for PvP rewards and Guild Hall news.
local _, GH = ...

local WIDTH, HEIGHT = 340, 68
local DEFAULT_DURATION, FADE_DURATION, MAX_QUEUE = 6, 0.7, 6
local queue, toast = {}, nil
local pvpPopup

local function fitTextHeight(frame, minimum, topPadding, gap, bottomPadding)
    local titleHeight = frame.title:GetStringHeight() or 18
    local bodyHeight = frame.body:GetStringHeight() or 0
    local contentHeight = math.ceil(topPadding + titleHeight + gap + bodyHeight + bottomPadding)
    local screenHeight = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 768
    local maximum = math.max(minimum, screenHeight - 160)
    frame:SetHeight(math.min(maximum, math.max(minimum, contentHeight)))
end

local function nextToast()
    if not toast then
        toast = CreateFrame("Frame", "GuildHallAnnouncementPopout", UIParent, "BackdropTemplate")
        toast:SetSize(WIDTH, HEIGHT)
        toast:SetFrameStrata("DIALOG")
        toast:SetClampedToScreen(true)
        toast:EnableMouse(true)
        toast:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        toast:SetBackdropColor(0.025, 0.032, 0.043, 0.99)
        toast:SetBackdropBorderColor(0.20, 0.62, 0.98, 0.9)

        toast.accent = toast:CreateTexture(nil, "ARTWORK")
        toast.accent:SetPoint("TOPLEFT", 6, -7)
        toast.accent:SetPoint("BOTTOMLEFT", 6, 7)
        toast.accent:SetWidth(3)
        toast.accent:SetColorTexture(0.20, 0.62, 0.98, 1)

        toast.icon = toast:CreateTexture(nil, "ARTWORK")
        toast.icon:SetSize(36, 36)
        toast.icon:SetPoint("LEFT", 10, 0)
        toast.icon:SetTexture("Interface/Icons/INV_Misc_Note_01")
        toast.title = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        toast.title:SetPoint("TOPLEFT", 56, -10)
        toast.title:SetPoint("RIGHT", -12, 0)
        toast.title:SetJustifyH("LEFT")
        toast.title:SetWordWrap(true)
        toast.title:SetTextColor(0.92, 0.96, 1)
        toast.body = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        toast.body:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -4)
        toast.body:SetPoint("RIGHT", -12, 0)
        toast.body:SetJustifyH("LEFT")
        toast.body:SetJustifyV("TOP")
        toast.body:SetWordWrap(true)
        toast.body:SetTextColor(0.78, 0.84, 0.9)
        toast:Hide()

        toast:SetScript("OnMouseUp", function(self)
            local callback = self.onClick
            self:Hide()
            if callback then callback() end
            nextToast()
        end)
        toast:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = (self.elapsed or 0) + elapsed
            local duration = self.duration or DEFAULT_DURATION
            if self.elapsed > duration then
                local alpha = math.max(0, 1 - (self.elapsed - duration) / FADE_DURATION)
                self:SetAlpha(alpha)
                if alpha <= 0 then
                    self:Hide()
                    nextToast()
                end
            end
        end)
    end

    if toast:IsShown() then return end
    local item = table.remove(queue, 1)
    if not item then return end
    toast:ClearAllPoints()
    toast:SetPoint("TOP", UIParent, "TOP", 0, -140)
    toast.title:SetText(item.title)
    toast.body:SetText(item.message)
    fitTextHeight(toast, HEIGHT, 10, 4, 10)
    toast.icon:SetTexture(item.icon or "Interface/Icons/INV_Misc_Note_01")
    toast.duration = math.max(2, tonumber(item.duration) or DEFAULT_DURATION)
    toast.elapsed = 0
    toast.onClick = item.onClick
    toast:SetAlpha(1)
    toast:Show()
end

function GH:ShowPopout(category, title, message, icon, onClick, duration)
    if self.GetSetting and self:GetSetting("popups") == false then return false end
    queue[#queue + 1] = {
        title = tostring(title or category or "Guild Hall"),
        message = tostring(message or ""),
        icon = icon,
        onClick = onClick,
        duration = duration,
    }
    while #queue > MAX_QUEUE do table.remove(queue, 1) end
    nextToast()
end

-- PvP rewards use their own compact popup, matching the stacking behavior of
-- GuildHQ while keeping GuildHall's blue and dark color scheme.
function GH:ShowPvPPopup(points, victim, level, totalPoints)
    if self.GetSetting and self:GetSetting("popups") == false then return end
    points = tonumber(points) or 0
    if points <= 0 then return end
    if not pvpPopup then
        pvpPopup = CreateFrame("Frame", "GuildHallPvPPointsPopout", UIParent, "BackdropTemplate")
        pvpPopup:SetSize(350, 78)
        pvpPopup:SetFrameStrata("DIALOG")
        pvpPopup:SetClampedToScreen(true)
        pvpPopup:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        pvpPopup:SetBackdropColor(0.025, 0.032, 0.043, 0.99)
        pvpPopup:SetBackdropBorderColor(0.20, 0.62, 0.98, 0.9)
        pvpPopup.accent = pvpPopup:CreateTexture(nil, "ARTWORK")
        pvpPopup.accent:SetPoint("TOPLEFT", 5, -6)
        pvpPopup.accent:SetPoint("BOTTOMLEFT", 5, 6)
        pvpPopup.accent:SetWidth(4)
        pvpPopup.accent:SetColorTexture(0.20, 0.62, 0.98, 1)
        pvpPopup.icon = pvpPopup:CreateTexture(nil, "ARTWORK")
        pvpPopup.icon:SetTexture("Interface/Icons/Achievement_PVP_A_01")
        pvpPopup.icon:SetSize(46, 46)
        pvpPopup.icon:SetPoint("LEFT", 13, 0)
        pvpPopup.title = pvpPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        pvpPopup.title:SetPoint("TOPLEFT", 68, -11)
        pvpPopup.title:SetPoint("RIGHT", -12, 0)
        pvpPopup.title:SetJustifyH("LEFT")
        pvpPopup.title:SetWordWrap(true)
        pvpPopup.title:SetTextColor(0.92, 0.96, 1)
        pvpPopup.body = pvpPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pvpPopup.body:SetPoint("TOPLEFT", pvpPopup.title, "BOTTOMLEFT", 0, -4)
        pvpPopup.body:SetPoint("RIGHT", -12, 0)
        pvpPopup.body:SetJustifyH("LEFT")
        pvpPopup.body:SetTextColor(0.78, 0.84, 0.9)
        pvpPopup:SetScript("OnUpdate", function(self, elapsed)
            self.left = (self.left or 0) - elapsed
            if self.left <= 0 then
                self:Hide()
                self.sum, self.count = 0, 0
            elseif self.left < 0.8 then
                self:SetAlpha(self.left / 0.8)
            end
        end)
        pvpPopup:Hide()
    end

    local showing = pvpPopup:IsShown()
    pvpPopup.sum = (showing and pvpPopup.sum or 0) + points
    pvpPopup.count = (showing and pvpPopup.count or 0) + 1
    pvpPopup.title:SetText("+" .. pvpPopup.sum .. " PvP" .. (pvpPopup.count > 1 and ("  (" .. pvpPopup.count .. " kills)") or ""))
    local levelText = tonumber(level) and tonumber(level) > 0 and tostring(level) or "?"
    pvpPopup.body:SetText(tostring(victim or "Unknown") .. " · lvl " .. levelText .. " · " .. tostring(totalPoints or 0) .. " pts")
    pvpPopup.left = 3
    fitTextHeight(pvpPopup, 78, 11, 4, 10)
    pvpPopup:ClearAllPoints()
    pvpPopup:SetPoint("TOP", UIParent, "TOP", 0, -216)
    pvpPopup:SetAlpha(1)
    pvpPopup:Show()
end

local seenMilestones = {}
local function milestoneToast(kind, value, author, profession)
    if kind == "L" then
        GH:ShowPopout("Level milestone", "Level " .. value .. " reached!", author .. " reached level " .. value .. ".", "Interface/Icons/Achievement_Level_" .. value)
    elseif kind == "P" then
        GH:ShowPopout("Profession milestone", profession .. " " .. value .. "!", author .. " reached " .. value .. " in " .. profession .. ".", "Interface/Icons/Trade_BlackSmithing")
    end
end

local function broadcastMilestone(kind, value, profession)
    if not GH.bucket then return end
    local author = UnitName and UnitName("player") or "Guild member"
    local content = kind == "L" and ("L\n" .. value) or ("P\n" .. profession .. "\n" .. value)
    local id = "milestone:" .. tostring(time()) .. ":" .. tostring(math.random(100000, 999999))
    seenMilestones[id] = true
    GH:SendRecord("MP", id, time(), author, content)
    milestoneToast(kind, value, author, profession)
end

GH:RegisterRecordHandler("MP", function(id, ts, author, content, sender)
    if not GH.bucket or seenMilestones[id] then return end
    local senderName = tostring(sender or ""):match("^([^-]+)") or tostring(sender or "")
    local authorName = tostring(author or ""):match("^([^-]+)") or tostring(author or "")
    if senderName:lower() ~= authorName:lower() then return end

    local kind, first, second = content:match("^(L)\n(%d+)$")
    if kind then
        local level = tonumber(first)
        if level ~= 10 and level ~= 20 and level ~= 30 and level ~= 40 and level ~= 50 and level ~= 60 then return end
        seenMilestones[id] = true
        milestoneToast("L", level, author)
        return
    end

    kind, first, second = content:match("^(P)\n(.-)\n(%d+)$")
    if not kind or first == "" or #first > 60 then return end
    local rank = tonumber(second)
    if rank ~= 150 and rank ~= 225 and rank ~= 300 then return end
    seenMilestones[id] = true
    milestoneToast("P", rank, author, first)
end)

local levelMilestones = { [10] = true, [20] = true, [30] = true, [40] = true, [50] = true, [60] = true }
GH:RegisterEventHandler("PLAYER_LEVEL_UP", function(_, newLevel)
    local level = tonumber(newLevel) or (UnitLevel and tonumber(UnitLevel("player")))
    if not level or not levelMilestones[level] then return end
    broadcastMilestone("L", level)
    if GH:GetSetting("levelGuildChat") and IsInGuild and IsInGuild() and SendChatMessage then
        SendChatMessage("Ding! " .. (UnitName and UnitName("player") or "A guild member") .. " hit level " .. level .. "!", "GUILD")
    end
end)

local professionMilestones = { 150, 225, 300 }
local professionScanPending = false
local function scanProfessionMilestones()
    if professionScanPending then return end
    professionScanPending = true
    local function scan()
        professionScanPending = false
        if not GH.GetPlayerProfessions then return end
        local _, professions = GH:GetPlayerProfessions()
        if type(professions) ~= "table" then return end

        GuildHallDB = type(GuildHallDB) == "table" and GuildHallDB or {}
        GuildHallDB.professionMilestoneRanks = type(GuildHallDB.professionMilestoneRanks) == "table" and GuildHallDB.professionMilestoneRanks or {}
        local characterKey = UnitGUID and UnitGUID("player") or (UnitName and UnitName("player") or "player")
        local previous = GuildHallDB.professionMilestoneRanks[characterKey]
        local current = {}
        for _, skill in ipairs(professions) do
            local name, rank = tostring(skill.name or ""), tonumber(skill.rank) or 0
            if name ~= "" then
                current[name] = rank
                local oldRank = previous and (tonumber(previous[name]) or 0)
                if oldRank then
                    for _, milestone in ipairs(professionMilestones) do
                        if oldRank < milestone and rank >= milestone then
                            broadcastMilestone("P", milestone, name)
                        end
                    end
                end
            end
        end
        GuildHallDB.professionMilestoneRanks[characterKey] = current
    end
    if C_Timer and C_Timer.After then C_Timer.After(1, scan) else scan() end
end

GH:RegisterEventHandler("PLAYER_LOGIN", scanProfessionMilestones)
GH:RegisterEventHandler("SKILL_LINES_CHANGED", scanProfessionMilestones)
GH:RegisterEventHandler("TRADE_SKILL_UPDATE", scanProfessionMilestones)

GH:RegisterCommand("popout", function(rest)
    local action, milestone = (rest or ""):lower():match("^(%S+)%s*(.-)$")
    -- Accept the previous `test <kind>` form too, while making each preview
    -- directly available as `/gh popout pvp`, `/gh popout level10`, etc.
    if action == "test" then
        if milestone == "" then action = "pvp"
        else action, milestone = milestone:match("^(%S+)%s*(.-)$") end
    end
    action = (action or ""):gsub("%s+", "")
    local selected = action == "" and milestone or action
    if (action == "level" or action == "profession") and milestone ~= "" then
        selected = action .. milestone
    end
    local player = UnitName and UnitName("player") or "Your character"
    selected = (selected or ""):gsub("%s+", "")
    if selected == "pvp" then
        local playerPoints = 0
        local seasonStart = GH.bucket and GH.bucket.pvpSeason and GH.bucket.pvpSeason.start or 0
        local totals = GH.bucket and GH.bucket.pvpTotals and GH.bucket.pvpTotals[tostring(seasonStart) .. "|" .. player]
        if totals then playerPoints = totals.points or 0 end
        GH:ShowPvPPopup(3, "Enemy Player", 60, playerPoints + 3)
        return
    end

    local level = tonumber(selected:match("^level(%d+)$"))
    if level and (level == 10 or level == 20 or level == 30 or level == 40 or level == 50 or level == 60) then
        GH:ShowPopout("Level milestone", "Level " .. level .. " reached!", player .. " reached level " .. level .. ".", "Interface/Icons/Achievement_Level_" .. level)
        return
    end

    local profession = tonumber(selected:match("^profession(%d+)$"))
    if profession and (profession == 150 or profession == 225 or profession == 300) then
        GH:ShowPopout("Profession milestone", profession .. " skill reached!", player .. " reached " .. profession .. " skill in a profession.", "Interface/Icons/Trade_BlackSmithing")
        return
    end

    print("Guild Hall: use /gh popout pvp, /gh popout level10/20/30/40/50/60, or /gh popout profession150/225/300.")
end)

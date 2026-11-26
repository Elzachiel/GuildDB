-- The DKP workspace and movable player auction popup share GuildDB's theme.
local _, GD = ...
local popup, dismissed, popupBucket = nil, {}, nil
local escapeSequence = 0
local function escapeWindow(frame, name)
    escapeSequence = escapeSequence + 1
    name = name or "GuildDBDKPWindow" .. escapeSequence
    _G[name] = frame
    UISpecialFrames = UISpecialFrames or {}
    for _, existing in ipairs(UISpecialFrames) do if existing == name then return end end
    table.insert(UISpecialFrames, name)
end
local function key(value) return tostring(value or ""):lower() end
local function isHost(r) return r and GD:CanConfigureDKP() and key(GD:GetDKPGuildMember(GD:PlayerName())) == key(r.data.owner) end
local function label(parent, font, x, y)
    local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", x, y); text:SetJustifyH("LEFT"); text:SetWordWrap(true)
    return text
end
local function button(parent, text, width, callback)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetSize(width or 100, 26); control:SetText(text); GD:StyleButton(control)
    control:SetScript("OnClick", callback)
    return control
end
local function report(ok, message)
    if message then print("GuildDB: " .. message) end
    return ok, message
end
local function leadingText(bid)
    return bid and (GD:DKPCharacterText(bid.member) .. " leads with " .. bid.amount .. " DKP (" .. bid.spec .. ")") or "No bids yet."
end
local function deliveryText(status)
    status = status or "Pending"
    local tint = ({ Delivered = "66dd88", Pending = "ffcc66", Refunded = "ff7777" })[status]
    return tint and ("|cff" .. tint .. status .. "|r") or status
end
local function confirm(title, summary, callback, accept)
    local used = false
    GD.ShowInputForm(title, { { label = "Review", value = summary, readOnly = true, multiline = true, max = 2000 } }, function()
        if used then return false, "This action has already completed." end
        local ok, message = callback()
        if ok then used = true end
        return ok, message
    end, accept or "Confirm")
end
local function guildNames(all)
    local result = {}
    if GD:IsDKPSoloTesting() then return { GD:GetDKPGuildMember(GD:PlayerName()) } end
    for index = 1, GetNumGuildMembers(true) do
        local name, _, _, level = GetGuildRosterInfo(index)
        if name and (all or tonumber(level) == 60) then result[#result + 1] = name end
    end
    table.sort(result); return result
end
local function ownedBucket(callback)
    local bucket = GD:GetDKPBucket()
    return function(...)
        if GD:GetDKPBucket() ~= bucket or not GD:IsDKPEnabled() then return false, "Your guild or DKP access changed. Open this window again." end
        return callback(...)
    end
end

local qualityNames = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact", "Heirloom" }
function GD:GetDKPItemAppearance(item, fallback)
    local hint = self.dkpItemLinks and self.dkpItemLinks[tostring(item)]
    local info = { self:GetDKPItemInfo(hint and hint.link or tonumber(item)) }
    if not info[1] and hint then info = { self:GetDKPItemInfo(tonumber(item)) } end
    local name, link, quality, icon = info[1], info[2], info[3], info[10]
    if not name and C_Item and C_Item.RequestLoadItemDataByID then
        self.dkpItemRequests = self.dkpItemRequests or {}
        if not self.dkpItemRequests[item] then
            self.dkpItemRequests[item] = true; C_Item.RequestLoadItemDataByID(tonumber(item))
        end
    end
    if not icon then local _, _, _, _, instantIcon = self:GetDKPItemInfoInstant(tonumber(item)); icon = instantIcon end
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    local r, g, b = unpack(self:GetAppearanceColors().accent)
    if color then r, g, b = color.r, color.g, color.b
    elseif quality and GetItemQualityColor then r, g, b = GetItemQualityColor(quality) end
    return { name = name or (hint and hint.name) or (fallback and not fallback:match("^Item %d+$") and fallback) or "Loading item...",
        link = link or (hint and hint.link) or ("item:" .. item), icon = icon or "Interface/Icons/INV_Misc_QuestionMark",
        r = r, g = g, b = b, rarity = quality and (_G["ITEM_QUALITY" .. quality .. "_DESC"] or qualityNames[quality]) or "Loading item details..." }
end
local function itemTooltip(control, getLink)
    control:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(getLink()); GameTooltip:Show()
        if GameTooltip_ShowCompareItem then GameTooltip_ShowCompareItem(GameTooltip) end
    end)
    control:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
        if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
    end)
end
function GD:CreateDKPItemPreview(parent, item, fallback, showPrice)
    local preview = CreateFrame("Button", nil, parent, "BackdropTemplate")
    preview:SetSize(370, 46)
    preview:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    preview.icon = preview:CreateTexture(nil, "ARTWORK"); preview.icon:SetSize(34, 34); preview.icon:SetPoint("LEFT", 6, 0)
    preview.name = label(preview, "GameFontNormal", 48, -7); preview.name:SetPoint("TOPRIGHT", -8, -7); preview.name:SetHeight(18)
    preview.rarity = label(preview, "GameFontHighlightSmall", 48, -27)
    local function refresh()
        local info = GD:GetDKPItemAppearance(item, fallback)
        preview.link = info.link; preview.name:SetText(info.name); preview.name:SetTextColor(info.r, info.g, info.b)
        local price = showPrice and GD:GetDKPStartingBid(item)
        preview.rarity:SetText(info.rarity .. (showPrice and (price and (" | Guild minimum: " .. price .. " DKP") or " | Guild price unavailable") or ""))
        preview.rarity:SetTextColor(info.r, info.g, info.b); preview.icon:SetTexture(info.icon)
        preview:SetBackdropColor(unpack(GD:GetAppearanceColors().panel)); preview:SetBackdropBorderColor(info.r, info.g, info.b, 1)
    end
    itemTooltip(preview, function() return preview.link end)
    preview:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed >= 0.5 then self.elapsed = 0; refresh() end
    end)
    refresh(); return preview
end

function GD:ShowDKPStartAuction(itemLink, queueMode)
    if not self:IsDKPEnabled() or not self:CanConfigureDKP() then return end
    local review = ownedBucket(function(values)
        local item, name = self:GetDKPItemIdentity(values[1])
        if not item then return false, "Enter an item link or numeric ID." end
        local price = self:GetDKPStartingBid(values[1])
        self.ShowInputForm(queueMode and "Queue DKP Item" or "Start DKP Auction", {
            { label = "Item", value = item, readOnly = true, itemPreview = item, itemName = name, pricePreview = queueMode == true },
            { label = price and ("Starting bid (configured: " .. price .. " DKP)") or "Starting bid (no configured price yet; review the fallback)", value = tostring(price or 10), max = 7 },
            { label = "Minimum bid increase", value = "10", max = 7 },
            { label = "Bidding duration in seconds (10-300)", value = "45", max = 3 },
        }, ownedBucket(function(v)
            if queueMode then return self:AddDKPQueuedAuction(item, v[2], v[3], v[4]) end
            return self:StartDKPAuction(item, v[2], v[3], v[4])
        end), queueMode and "Queue" or "Start")
        return true
    end)
    if itemLink then return review({ itemLink }) end
    self.ShowInputForm("Auction an Item", {
        { label = "Item link or numeric ID (shift-click an item)", value = "", itemLink = true, max = 500 },
    }, review, "Next")
end

local function listWindow(title)
    local w = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    escapeWindow(w)
    w:SetSize(620, 520); w:SetPoint("CENTER"); w:SetFrameStrata("FULLSCREEN_DIALOG"); w:SetFrameLevel(100)
    w:SetClampedToScreen(true); w:SetMovable(true); w:EnableMouse(true); w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", function(s) s:StartMoving() end)
    w:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    w:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 14 })
    w.title = label(w, "GameFontNormalLarge", 16, -16); w.title:SetText(title)
    w.description = label(w, nil, 16, -46); w.description:SetWidth(580); w.description:SetHeight(50)
    w.scroll = CreateFrame("ScrollFrame", nil, w, "UIPanelScrollFrameTemplate")
    w.scroll:SetPoint("TOPLEFT", 16, -104); w.scroll:SetPoint("BOTTOMRIGHT", -36, 54)
    w.content = CreateFrame("Frame", nil, w.scroll); w.content:SetSize(560, 350); w.scroll:SetScrollChild(w.content)
    w.close = button(w, "Close", 90, function() w:Hide() end); w.close:SetPoint("BOTTOMRIGHT", -16, 14)
    return w
end
local function styleList(w)
    local c = GD:GetAppearanceColors()
    w:SetBackdropColor(c.panel[1], c.panel[2], c.panel[3], 1); w:SetBackdropBorderColor(unpack(c.accent))
    w.title:SetTextColor(unpack(c.accent)); w.description:SetTextColor(unpack(c.muted))
    GD:StyleButton(w.close); GD:StyleScrollFrame(w.scroll)
    return c
end
function GD:ShowDKPAuctionQueue()
    if not self:CanConfigureDKP() then return end
    if not self:IsDKPEnabled() then return end
    local w = self.dkpQueueWindow
    if not w then
        w = listWindow("Auction Queue"); w.rows = {}; self.dkpQueueWindow = w
        w.add = button(w, "Add item", 100, function() if w.bucket == self:GetDKPBucket() then self:ShowDKPStartAuction(nil, true) end end); w.add:SetPoint("BOTTOMLEFT", 16, 14)
        w.start = button(w, "Start next", 110, function() if w.bucket ~= self:GetDKPBucket() then w:Hide(); return end; report(self:StartNextDKPQueuedAuction()); self:ShowDKPAuctionQueue() end); w.start:SetPoint("BOTTOMLEFT", 124, 14)
        w.empty = label(w.content, nil, 8, -8)
        w:SetScript("OnUpdate", function(s, elapsed)
            if s.bucket ~= self:GetDKPBucket() or not self:IsDKPEnabled() or not self:CanConfigureDKP() then s:Hide(); return end
            s.elapsed = (s.elapsed or 0) + elapsed
            if s.elapsed >= .5 then s.elapsed = 0; self:ShowDKPAuctionQueue() end
        end)
    end
    w.bucket = self:GetDKPBucket()
    local colors, queue = styleList(w), self:GetDKPAuctionQueue()
    w.description:SetText(#queue .. " items | Saved for your character and guild.\nReorder upcoming drops below. Starting an item opens bidding for everyone.")
    w.content:SetHeight(math.max(350, #queue * 68))
    for index, entry in ipairs(queue) do
        local r = w.rows[index]
        if not r then
            r = CreateFrame("Frame", nil, w.content); r:SetSize(560, 64); r:SetPoint("TOPLEFT", 0, -(index - 1) * 68)
            r.icon = CreateFrame("Button", nil, r); r.icon:SetSize(38, 38); r.icon:SetPoint("LEFT", 4, 0)
            r.texture = r.icon:CreateTexture(nil, "ARTWORK"); r.texture:SetAllPoints()
            itemTooltip(r.icon, function() return r.link end)
            r.name = label(r, "GameFontNormal", 50, -8); r.name:SetWidth(285); r.name:SetHeight(18)
            r.detail = label(r, nil, 50, -32); r.detail:SetWidth(285)
            for _, action in ipairs({ {"up", "Up", -1, 340, 52}, {"down", "Down", 1, 396, 58}, {"remove", "Remove", "remove", 458, 82} }) do
                local direction = action[3]
                r[action[1]] = button(r, action[2], action[5], function() if w.bucket ~= self:GetDKPBucket() then w:Hide(); return end; report(self:ChangeDKPQueuedAuction(r.entryID, direction)); self:ShowDKPAuctionQueue() end)
                r[action[1]]:SetPoint("LEFT", action[4], 0)
            end
            w.rows[index] = r
        end
        local info = self:GetDKPItemAppearance(entry.item, entry.label)
        r.entryID, r.link = entry.id, info.link; r.texture:SetTexture(info.icon)
        r.name:SetText(index .. ". " .. info.name); r.name:SetTextColor(info.r, info.g, info.b)
        r.detail:SetText(entry.minimum .. " DKP | +" .. entry.increment .. " | " .. entry.duration .. " sec"); r.detail:SetTextColor(unpack(colors.text))
        r.up:SetEnabled(index > 1); r.down:SetEnabled(index < #queue)
        for _, c in ipairs({r.up, r.down, r.remove}) do self:StyleButton(c) end
        r:Show()
    end
    for index = #queue + 1, #w.rows do w.rows[index]:Hide() end
    w.empty:SetText("Your queue is empty. Add an item to prepare the next drop."); w.empty:SetTextColor(unpack(colors.text)); w.empty:SetShown(#queue == 0)
    w.start:SetEnabled(#queue > 0 and not self:GetDKPActiveAuction()); self:StyleButton(w.start); self:StyleButton(w.add); w:Show()
end

function GD:GetDKPSyncReport()
    local check = self.dkpSyncCheck
    if not check or check.bucket ~= self:GetDKPBucket() then return "No sync check yet. Click Check Again.", "" end
    local stale = self:GetDKPSyncFingerprint() ~= check.fingerprint
    local heading = "Checked " .. date("%I:%M:%S %p", check.ts) .. (stale and " | Data changed: check again." or " | Replies confirm this snapshot.")
    local lines, members = {}, {}
    for _, member in pairs(check.members) do members[#members + 1] = member end
    table.sort(members, function(a,b) return a.name < b.name end)
    for _, member in ipairs(members) do
        local status
        if member.fingerprint then status = member.fingerprint == check.fingerprint and "Confirmed" or "Different data"
        elseif not member.online then status = "Offline"
        elseif GD:GetDKPTime() - check.ts > 15 then status = "No response"
        else status = "Waiting for reply" end
        lines[#lines + 1] = self:DKPCharacterText(member.name) .. " - " .. status
    end
    return heading, table.concat(lines, "\n")
end
function GD:ShowDKPSyncStatus()
    if not self:IsDKPEnabled() or not self:CanConfigureDKP() then return end
    local w = self.dkpSyncWindow
    if not w then
        w = listWindow("DKP Sync Status"); self.dkpSyncWindow = w
        w.report = label(w.content, nil, 4, -4); w.report:SetWidth(540)
        w.check = button(w, "Check Again", 120, function() if w.bucket ~= self:GetDKPBucket() then w:Hide(); return end; report(self:CheckDKPSync()); self:ShowDKPSyncStatus() end); w.check:SetPoint("BOTTOMLEFT", 16, 14)
        w:SetScript("OnUpdate", function(s, elapsed)
            if s.bucket ~= self:GetDKPBucket() or not self:IsDKPEnabled() or not self:CanConfigureDKP() then s:Hide(); return end
            s.elapsed = (s.elapsed or 0) + elapsed
            if s.elapsed >= 2 then s.elapsed = 0; self:ShowDKPSyncStatus() end
        end)
        if not self.dkpSyncCheck or self.dkpSyncCheck.bucket ~= self:GetDKPBucket() then report(self:CheckDKPSync()) end
    end
    w.bucket = self:GetDKPBucket()
    local colors = styleList(w)
    local heading, lines = self:GetDKPSyncReport()
    w.description:SetText(heading .. "\nNo response can mean an older addon, a delay, or a disconnected member.")
    w.report:SetText(lines); w.report:SetTextColor(unpack(colors.text))
    w.content:SetHeight(math.max(350, (w.report:GetStringHeight() or 350) + 16))
    self:StyleButton(w.check); w:Show()
end

function GD:ShowDKPMasterLootSettings()
    if not self:CanConfigureDKP() then return end
    self.ShowInputForm("DKP Master Loot", {
        { label = "Auto-give boss loot to auction winners", checkbox = true, value = self:GetSetting("dkpAutoMasterLoot") },
        { label = "How it works", value = "Personal setting for the GM/officer acting as Master Looter.\nOpen boss loot before starting bidding and keep it open.\nOnly the original unique loot slot is used. The winner must be an eligible Master Loot recipient.\nGame confirmations may still require a click. Bags, ambiguous drops, combat or unavailable loot stay Pending for manual delivery.", readOnly = true, multiline = true, max = 700 },
    }, ownedBucket(function(values)
        if not self:CanConfigureDKP() then return false, "Only officers can change Master Loot preferences." end
        self:SetSetting("dkpAutoMasterLoot", values[1] == true)
        return true, values[1] and "Automatic Master Loot enabled for your character. Open boss loot before starting the auction." or "Automatic Master Loot disabled. Distribute items manually."
    end), "Save")
end

function GD:ShowDKPAlertSettings()
    self.ShowInputForm("Auction Alerts", {
        { label = "Open bidding popups automatically", checkbox = true, value = self:GetDKPBucket().dkpAuctionPopups ~= false },
        { label = "Play a sound when outbid", checkbox = true, value = self:GetSetting("dkpOutbidSound") },
        { label = "Flash the screen border when outbid", checkbox = true, value = self:GetSetting("dkpOutbidFlash") },
        { label = "Countdown sounds at 10, 5 and 3 seconds", checkbox = true, value = self:GetSetting("dkpCountdownSound") },
        { label = "Reset DKP window positions to center on Save", checkbox = true, value = false },
    }, ownedBucket(function(values)
        self:GetDKPBucket().dkpAuctionPopups = values[1] == true
        self:SetSetting("dkpOutbidSound", values[2] == true); self:SetSetting("dkpOutbidFlash", values[3] == true)
        self:SetSetting("dkpCountdownSound", values[4] == true)
        if values[5] == true then self:ResetDKPWindowPositions() end
        self:RefreshDKPAuctionPopup(); return true, "Your auction alert preferences were saved."
    end), "Save")
end

function GD:CheckDKPOutbidAlert()
    local auction = self:GetDKPActiveAuction()
    if not auction or self:GetDKPAuctionStatus(auction) ~= "OPEN" then self.dkpOutbidState = nil; return false end
    local leader, bids = self:GetDKPAuctionLeader(auction)
    local account, ownBid = key(self:GetDKPAccount(self:PlayerName()))
    for _, bid in ipairs(bids) do if key(self:GetDKPAccount(bid.member)) == account then ownBid = bid; break end end
    local previous = self.dkpOutbidState
    local outbid = previous and previous.bucket == self:GetDKPBucket() and previous.id == auction.id and previous.leading
        and ownBid and leader and ownBid ~= leader and ownBid.order == previous.order
    self.dkpOutbidState = { bucket = self:GetDKPBucket(), id = auction.id, leading = ownBid ~= nil and ownBid == leader, order = ownBid and ownBid.order }
    if not outbid then return false end
    if self:GetSetting("dkpOutbidSound") and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
    if self:GetSetting("dkpOutbidFlash") then
        local flash = self.dkpOutbidFlash
        if not flash then
            flash = CreateFrame("Frame", nil, UIParent, "BackdropTemplate"); flash:SetAllPoints(UIParent)
            flash:SetFrameStrata("FULLSCREEN_DIALOG"); flash:SetFrameLevel(90); flash:EnableMouse(false)
            flash:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 5 })
            flash:SetBackdropBorderColor(1, .3, .1, 1)
            flash.message = label(flash, "GameFontNormalLarge", 0, 0); flash.message:ClearAllPoints(); flash.message:SetPoint("TOP", 0, -120)
            flash:SetScript("OnUpdate", function(self, elapsed)
                self.elapsed = self.elapsed + elapsed; self:SetAlpha(math.max(0, 1 - self.elapsed / 2))
                if self.elapsed >= 2 then self:Hide() end
            end)
            self.dkpOutbidFlash = flash
        end
        flash.elapsed = 0; flash:SetAlpha(1)
        flash.message:SetText("Outbid: " .. self:GetDKPItemAppearance(auction.data.item, auction.data.label).name)
        flash:Show()
    end
    return true
end

local function liveWindow(name, title, width, height)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    escapeWindow(frame, name)
    frame:SetSize(width, height); frame:SetPoint("CENTER"); frame:SetClampedToScreen(true)
    frame:SetFrameStrata("FULLSCREEN_DIALOG"); frame:SetFrameLevel(110)
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 14 })
    frame.title = label(frame, "GameFontNormalLarge", 16, -16); frame.title:SetText(title)
    frame.close = button(frame, "Close", 90, function() frame:Hide() end); frame.close:SetPoint("BOTTOMRIGHT", -16, 14)
    return frame
end
local function styleLiveWindow(frame)
    local colors = GD:GetAppearanceColors()
    frame:SetBackdropColor(colors.panel[1], colors.panel[2], colors.panel[3], 1)
    frame:SetBackdropBorderColor(unpack(colors.accent)); frame.title:SetTextColor(unpack(colors.accent))
    GD:StyleButton(frame.close)
end
function GD:ResetDKPWindowPositions()
    local frames = { popup }
    for _, name in ipairs({ "dkpQueueWindow", "dkpRaidSummaryWindow", "dkpSyncWindow", "dkpAuctionResultWindow", "dkpReadinessWindow", "dkpRaidExportWindow", "dkpAuctionLauncher" }) do
        if self[name] then frames[#frames + 1] = self[name] end
    end
    for _, frame in pairs(frames) do
        frame:StopMovingOrSizing(); frame:ClearAllPoints(); frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end
local function renderAuctionResult(frame, auction)
    local awarded = GD:GetDKPAuctionStatus(auction) == "AWARDED"
    local won = awarded and key(GD:GetDKPGuildMember(GD:PlayerName())) == key(auction.data.winner)
    frame.title:SetText(won and "You won!" or "Auction Result")
    frame.result:SetText(awarded and ((won and "You won for " or GD:DKPCharacterText(auction.data.winner) .. " won for ") .. auction.data.cost .. " DKP (" .. auction.data.spec .. ").\nLoot delivery: " .. deliveryText(GD:GetDKPLootDelivery("loot:" .. auction.id))) or "Auction cancelled. No DKP charged.")
    frame.result:SetTextColor(unpack(GD:GetAppearanceColors().text)); styleLiveWindow(frame)
    if won then frame.title:SetTextColor(1, .82, 0); frame:SetBackdropBorderColor(1, .82, 0, 1) end
    frame.youWon = won
end
function GD:ShowDKPRaidExport(raidID)
    local text, message = self:BuildDKPRaidReport(raidID)
    if not text then return report(false, message) end
    local frame = self.dkpRaidExportWindow
    if not frame then
        frame = liveWindow("GuildDBDKPRaidExport", "Copy Raid Report", 600, 460)
        frame.help = label(frame, "GameFontHighlightSmall", 16, -46); frame.help:SetText("Click Select All, then Ctrl+C. Paste into Discord; long reports may need several messages.")
        frame.help:SetWidth(560); frame.help:SetHeight(36)
        frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        frame.scroll:SetPoint("TOPLEFT", 16, -90); frame.scroll:SetPoint("BOTTOMRIGHT", -36, 52)
        frame.text = CreateFrame("EditBox", nil, frame.scroll, "BackdropTemplate")
        frame.text:SetMultiLine(true); frame.text:SetAutoFocus(false); frame.text:SetWidth(540); frame.text:SetMaxLetters(0)
        GD:StyleEditBox(frame.text, true); frame.scroll:SetScrollChild(frame.text)
        frame.measure = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); frame.measure:SetWidth(540); frame.measure:Hide()
        frame.text:SetScript("OnEscapePressed", function(self) self:ClearFocus(); frame:Hide() end)
        frame.text:SetScript("OnTextChanged", function(self)
            frame.measure:SetText(self:GetText()); self:SetHeight(math.max(300, (frame.measure:GetStringHeight() or 300) + 20))
        end)
        frame.select = button(frame, "Select All", 110, function() frame.text:SetFocus(); frame.text:HighlightText() end)
        frame.select:SetPoint("BOTTOMLEFT", 16, 14)
        frame:SetScript("OnHide", function(self) self.text:ClearFocus() end)
        frame:SetScript("OnUpdate", function(self)
            if self.bucket ~= GD:GetDKPBucket() or not GD:IsDKPEnabled() or not GD:CanConfigureDKP() then self.text:SetText(""); self:Hide(); return end
            styleLiveWindow(self); GD:StyleButton(self.select); GD:StyleScrollFrame(self.scroll)
        end)
        self.dkpRaidExportWindow = frame
    end
    frame.bucket = self:GetDKPBucket(); frame.text:SetText(text); frame.measure:SetText(text); frame.text:SetHeight(math.max(300, (frame.measure:GetStringHeight() or 300) + 20))
    frame.scroll:SetVerticalScroll(0); styleLiveWindow(frame); frame:Show()
    frame.text:SetFocus(); frame.text:HighlightText()
    return true
end
function GD:ShowDKPAuctionResult(auction)
    local frame = self.dkpAuctionResultWindow
    if not frame then
        frame = liveWindow("GuildDBDKPAuctionResult", "Auction Result", 460, 210)
        frame:ClearAllPoints(); frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        frame.icon = frame:CreateTexture(nil, "ARTWORK"); frame.icon:SetSize(36, 36); frame.icon:SetPoint("TOPLEFT", 16, -48)
        frame.hover = CreateFrame("Button", nil, frame); frame.hover:SetAllPoints(frame.icon)
        itemTooltip(frame.hover, function() return "item:" .. frame.itemID end)
        frame.item = label(frame, "GameFontNormal", 62, -48); frame.item:SetWidth(378); frame.item:SetHeight(36)
        frame.result = label(frame, "GameFontHighlight", 16, -96); frame.result:SetWidth(424); frame.result:SetHeight(66)
        frame:SetScript("OnUpdate", function(self)
            if self.bucket ~= GD:GetDKPBucket() or not GD:IsDKPEnabled() then self:Hide(); return end
            local auction = GD:GetDKPAuction(self.auctionID)
            if auction then renderAuctionResult(self, auction) end
        end)
        self.dkpAuctionResultWindow = frame
    end
    local item, status = self:GetDKPItemAppearance(auction.data.item, auction.data.label), self:GetDKPAuctionStatus(auction)
    frame.bucket, frame.itemID, frame.auctionID = self:GetDKPBucket(), auction.data.item, auction.id
    frame.icon:SetTexture(item.icon); frame.item:SetText(item.name); frame.item:SetTextColor(item.r, item.g, item.b)
    renderAuctionResult(frame, auction); frame:Show()
end
function GD:ShowDKPReadiness()
    if not self:IsDKPEnabled() or not self:CanConfigureDKP() then return end
    local ok, message = self:CheckDKPReadiness()
    if not ok and not self:GetDKPReadiness() then report(ok, message); return end
    local frame = self.dkpReadinessWindow
    if not frame then
        frame = liveWindow("GuildDBDKPReadiness", "Raid Readiness", 540, 480)
        frame.status = label(frame, "GameFontHighlightSmall", 16, -46); frame.status:SetWidth(504); frame.status:SetHeight(52)
        frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        frame.scroll:SetPoint("TOPLEFT", 16, -104); frame.scroll:SetPoint("BOTTOMRIGHT", -36, 52)
        frame.content = CreateFrame("Frame", nil, frame.scroll); frame.content:SetSize(480, 400); frame.scroll:SetScrollChild(frame.content)
        frame.report = label(frame.content, "GameFontHighlightSmall", 0, 0); frame.report:SetWidth(480)
        frame.refresh = button(frame, "Check Again", 120, function() report(GD:CheckDKPReadiness()) end); frame.refresh:SetPoint("BOTTOMLEFT", 16, 14)
        frame:SetScript("OnUpdate", function(self, elapsed)
            if self.bucket ~= GD:GetDKPBucket() or not GD:IsDKPEnabled() or not GD:CanConfigureDKP() then self:Hide(); return end
            self.elapsed = (self.elapsed or .25) + (elapsed or .25)
            if self.elapsed < .25 then return end
            self.elapsed = 0
            local check = GD:GetDKPReadiness(); if not check then self:Hide(); return end
            local lines, received, count = {}, 0, 0
            local members = {}; for _, member in pairs(check.members) do members[#members + 1] = member end
            table.sort(members, function(a, b) return a.name < b.name end)
            local now = GetTime and GetTime() or GD:GetDKPTime()
            for _, member in ipairs(members) do
                count = count + 1
                if member.received then received = received + 1 end
                local status = member.received and ((member.enabled and "DKP enabled" or "|cffff7777DKP disabled|r") .. " | v" .. member.version
                    .. (member.version ~= GD.version and " | |cffffcc66Different version|r" or ""))
                    or (now - check.started > 10 and "No response (older addon, missing addon or delayed connection)" or "Waiting for response...")
                lines[#lines + 1] = GD:DKPCharacterText(member.name) .. "\n" .. status .. "\n"
            end
            self.status:SetText(received .. "/" .. count .. " responses. Group snapshot at time of check.\nA response confirms addon version and DKP setting; it does not confirm balance sync.")
            self.status:SetTextColor(unpack(GD:GetAppearanceColors().muted)); self.report:SetText(table.concat(lines, "\n"))
            self.report:SetTextColor(unpack(GD:GetAppearanceColors().text)); self.content:SetHeight(math.max(300, (self.report:GetStringHeight() or 300) + 16))
            self.refresh:SetEnabled(now - check.started >= 5); GD:StyleButton(self.refresh); GD:StyleScrollFrame(self.scroll); styleLiveWindow(self)
        end)
        self.dkpReadinessWindow = frame
    end
    frame.bucket = self:GetDKPBucket(); frame.elapsed = .25; styleLiveWindow(frame); frame:Show()
    -- Populate immediately; the update handler keeps responses live.
    local update = frame:GetScript("OnUpdate"); if update then update(frame, 0) end
end
function GD:RefreshDKPLiveControls()
    local auction = self:IsDKPEnabled() and self:GetDKPActiveAuction()
    local show = auction and (self:GetDKPAuctionStatus(auction) == "PAUSED" or self:GetDKPAuctionStatus(auction) == "OPEN" and self:GetDKPTime() < auction.data.ends)
        and self:CanBidDKPAuction(auction, self:PlayerName()) and not (popup and popup:IsShown())
    local control = self.dkpAuctionLauncher
    if not show then if control then control:Hide() end; return end
    if not control then
        control = button(UIParent, "Auction active - Open", 210, function(self)
            local current = GD:GetDKPActiveAuction()
            if current and current.id == self.auctionID then GD:ShowDKPAuctionPopup(current.id) end
        end)
        control:SetPoint("CENTER", UIParent, "CENTER", 0, 220); control:SetFrameStrata("DIALOG")
        control:SetClampedToScreen(true); control:SetMovable(true); control:RegisterForDrag("LeftButton")
        control:SetScript("OnDragStart", function(self) self:StartMoving() end)
        control:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        self.dkpAuctionLauncher = control
    end
    control.auctionID = auction.id
    local connected = self:GetDKPAuctionConnection(auction)
    control:SetText(connected and (auction.data.status == "PAUSED" and "Auction paused - Open" or "Auction active - Open") or "Auction - Host unavailable")
    self:StyleButton(control, "primary"); control:Show()
end

function GD:ShowDKPRaidSummary(raidID)
    local summary = self:GetDKPRaidSummary(raidID)
    if not summary then return end
    local window = self.dkpRaidSummaryWindow
    if not window then
        window = CreateFrame("Frame", nil, UIParent, "BackdropTemplate"); window:SetSize(560, 580); window:SetPoint("CENTER")
        escapeWindow(window, "GuildDBDKPRaidSummary")
        window:SetFrameStrata("FULLSCREEN_DIALOG"); window:SetFrameLevel(100); window:SetClampedToScreen(true)
        window:SetMovable(true); window:EnableMouse(true); window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart", function(self) self:StartMoving() end); window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        window:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 14 })
        window.title = label(window, "GameFontNormalLarge", 16, -16)
        window.metrics = label(window, "GameFontHighlight", 16, -44); window.metrics:SetWidth(520); window.metrics:SetHeight(40)
        window.scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
        window.scroll:SetPoint("TOPLEFT", 16, -96); window.scroll:SetPoint("BOTTOMRIGHT", -36, 52)
        window.content = CreateFrame("Frame", nil, window.scroll); window.content:SetWidth(500); window.content:SetHeight(400); window.scroll:SetScrollChild(window.content)
        window.report = label(window.content, "GameFontHighlightSmall", 0, 0); window.report:SetWidth(500)
        window.attendance = button(window, "Checkpoints", 110, function() GD:ShowDKPRaidAttendance(window.raid) end)
        window.attendance:SetPoint("BOTTOMLEFT", 16, 14)
        window.refresh = button(window, "Refresh", 90, function() GD:ShowDKPRaidSummary(window.raid.id) end); window.refresh:SetPoint("BOTTOM", 0, 14)
        window.close = button(window, "Close", 100, function() window:Hide() end); window.close:SetPoint("BOTTOMRIGHT", -16, 14)
        window:SetScript("OnUpdate", function(self) if self.bucket ~= GD:GetDKPBucket() or not GD:IsDKPEnabled() or self.lootVisible ~= GD:CanConfigureDKP() then self:Hide() end end)
        self.dkpRaidSummaryWindow = window
    end
    if window.raid and window.raid.id ~= raidID then window.scroll:SetVerticalScroll(0) end
    window.raid, window.bucket = summary.raid, self:GetDKPBucket()
    window.lootVisible = self:CanConfigureDKP()
    local colors = self:GetAppearanceColors()
    window:SetBackdropColor(colors.panel[1], colors.panel[2], colors.panel[3], 1); window:SetBackdropBorderColor(unpack(colors.accent))
    window.title:SetText(summary.raid.data.label); window.title:SetTextColor(unpack(colors.accent))
    window.metrics:SetText(#summary.attendees .. " attendees  |  " .. #summary.bosses .. " bosses  |  " .. summary.earned .. " DKP earned\n" .. (window.lootVisible and (#summary.loot .. " loot awards  |  ") or "") .. summary.checkpoints .. " attendance checkpoints")
    local recap = self:GetDKPPersonalRaidRecap(raidID)
    local lines = { "YOUR RAID RECAP", "You earned " .. recap.earned .. " DKP, spent " .. recap.spent .. " DKP, and won " .. #recap.loot .. " item(s)." }
    for _, loot in ipairs(recap.loot) do lines[#lines + 1] = self:GetDKPItemAppearance(loot.item, loot.label).name .. " - " .. loot.cost .. " DKP" end
    lines[#lines + 1] = "\nATTENDANCE / DKP EARNED"
    for _, member in ipairs(summary.attendees) do lines[#lines + 1] = self:DKPCharacterText(member.name) .. " - " .. member.checkpoints .. "/" .. summary.checkpoints .. " checkpoints, " .. member.earned .. " DKP" end
    lines[#lines + 1] = "\nBOSSES KILLED"
    for _, boss in ipairs(summary.bosses) do lines[#lines + 1] = boss end
    if #summary.bosses == 0 then lines[#lines + 1] = "No bosses recorded yet." end
    if window.lootVisible then
        lines[#lines + 1] = "\nLOOT AWARDED"
        for _, loot in ipairs(summary.loot) do
            lines[#lines + 1] = self:GetDKPItemAppearance(loot.item, loot.label).name .. " - " .. self:DKPCharacterText(loot.member) .. ", " .. loot.cost .. " DKP (" .. loot.spec .. ") - " .. deliveryText(loot.delivery)
        end
        if #summary.loot == 0 then lines[#lines + 1] = "No loot linked to this raid." end
    end
    window.report:SetText(table.concat(lines, "\n")); window.report:SetTextColor(unpack(colors.text)); window.metrics:SetTextColor(unpack(colors.text))
    window.content:SetHeight(math.max(400, (window.report:GetStringHeight() or 400) + 16))
    for _, control in ipairs({ window.attendance, window.refresh, window.close }) do self:StyleButton(control) end
    self:StyleScrollFrame(window.scroll); window:Show()
end

function GD:HandleDKPAuctionItemClick(link, mouseButton)
    if mouseButton ~= "RightButton" or not IsAltKeyDown or not IsAltKeyDown()
        or (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown())
        or not self:IsDKPEnabled() or not self:CanConfigureDKP() then return false end
    if type(link) ~= "string" or #link > 500 then return false end
    -- Preserve the hyperlink's name and payload while querying item metadata.
    if not link:find("item:%d+") or not self:GetDKPItemIdentity(link) then return false end
    -- One click can pass through a native function and its button post-hook.
    local now = GetTime and GetTime()
    local previous = self.dkpAuctionGesture
    if now and previous and previous.link == link and now - previous.at < 0.05 then return true end
    if now then self.dkpAuctionGesture = { link = link, at = now } end
    local active = self:GetDKPActiveAuction()
    if active then
        self:ShowDKPAuctionPopup(active.id)
        print("GuildDB: Finish or cancel the current auction before starting another.")
    else self:ShowDKPStartAuction(link) end
    return true
end

-- Observe native clicks securely. Replacing bag handlers taints protected item use.
local itemClickHooks = {}
local bagClickScripts = setmetatable({}, { __mode = "k" })
local bagEvents
local function hookItemClick(owner, name, resolve)
    if not hooksecurefunc or not owner or type(owner[name]) ~= "function" then return end
    itemClickHooks[owner] = itemClickHooks[owner] or {}
    if itemClickHooks[owner][name] == owner[name] then return end
    hooksecurefunc(owner, name, function(...)
        if IsAltKeyDown and IsAltKeyDown() and GD:IsDKPEnabled() and GD:CanConfigureDKP() then
            local link, mouseButton = resolve(...)
            GD:HandleDKPAuctionItemClick(link, mouseButton)
        end
    end)
    itemClickHooks[owner][name] = owner[name]
end
function GD:InstallDKPAuctionItemClicks()
    if not bagEvents then
        -- Runtime routes only our own ADDON_LOADED event; watch late bag UI loading directly.
        bagEvents = CreateFrame("Frame")
        bagEvents:RegisterEvent("ADDON_LOADED"); bagEvents:RegisterEvent("BAG_UPDATE_DELAYED")
        bagEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
        bagEvents:SetScript("OnEvent", function() GD:InstallDKPAuctionItemClicks() end)
    end
    local function bagItem(control, mouseButton)
        if not control then return end
        local bag = control.GetBagID and control:GetBagID()
        if bag == nil and control.GetBag then bag = control:GetBag() end
        if bag == nil and control.GetParent then
            local parent = control:GetParent(); bag = parent and parent:GetID()
        end
        local slot = control.GetID and control:GetID()
        if bag == nil or not slot then return end
        local link = C_Container and C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)
        if not link and GetContainerItemLink then link = GetContainerItemLink(bag, slot) end
        if not link and C_Item and C_Item.GetItemLink and ItemLocation and ItemLocation.CreateFromBagAndSlot then
            link = C_Item.GetItemLink(ItemLocation:CreateFromBagAndSlot(bag, slot))
        end
        return link, mouseButton
    end
    local function attachButton(control)
        if not control or not control.HookScript or bagClickScripts[control] then return end
        bagClickScripts[control] = true
        control:HookScript("OnClick", function(self, mouseButton)
            if IsAltKeyDown and IsAltKeyDown() then
                local link = bagItem(self, mouseButton)
                GD:HandleDKPAuctionItemClick(link, mouseButton)
            end
        end)
    end
    local function attachContainer(container, name)
        if not container then return end
        if container.EnumerateValidItems then
            for _, control in container:EnumerateValidItems() do attachButton(control) end
        else
            for slot = 1, 72 do attachButton(_G[name .. "Item" .. slot]) end
        end
        if not container.GuildDBAuctionShowHook and container.HookScript then
            container.GuildDBAuctionShowHook = true
            container:HookScript("OnShow", function() GD:InstallDKPAuctionItemClicks() end)
        end
    end
    -- Existing buttons may hold copies of native handlers, bypassing the globals/mixin.
    attachContainer(ContainerFrameCombinedBags, "ContainerFrameCombinedBags")
    for index = 1, NUM_CONTAINER_FRAMES or 13 do
        local name = "ContainerFrame" .. index; attachContainer(_G[name], name)
    end
    hookItemClick(_G, "ContainerFrameItemButton_OnClick", bagItem)
    hookItemClick(_G, "ContainerFrameItemButton_OnModifiedClick", bagItem)
    hookItemClick(ContainerFrameItemButtonMixin, "OnClick", bagItem)
    hookItemClick(ContainerFrameItemButtonMixin, "OnModifiedClick", bagItem)
    hookItemClick(_G, "LootButton_OnClick", function(control, mouseButton)
        return control and control.slot and GetLootSlotLink and GetLootSlotLink(control.slot), mouseButton
    end)
    hookItemClick(_G, "SetItemRef", function(link, _, mouseButton) return link, mouseButton end)
    -- Loot templates and other item widgets can call this directly for modified clicks.
    hookItemClick(_G, "HandleModifiedItemClick", function(link)
        return link, GetMouseButtonClicked and GetMouseButtonClicked()
    end)
end
GD:RegisterEventHandler("PLAYER_LOGIN", function() GD:InstallDKPAuctionItemClicks() end)
GD:RegisterEventHandler("ADDON_LOADED", function() GD:InstallDKPAuctionItemClicks() end)

function GD:ShowDKPRecordLoot()
    if not self:CanConfigureDKP() then return end
    self.ShowInputForm("Record Loot Purchase", {
        { label = "Item link or numeric ID", value = "", max = 500, itemLink = true },
    }, ownedBucket(function(values)
        local item, name = self:GetDKPItemIdentity(values[1])
        if not item then return false, "Enter an item link or numeric ID." end
        local choices, price = guildNames(), self:GetDKPStartingBid(values[1])
        if #choices == 0 then return false, "No level-60 guild members found." end
        self.ShowInputForm(name .. " - Purchase", {
            { label = "Recipient", options = choices, value = choices[1] },
            { label = "DKP cost", value = tostring(price or 10), max = 7 },
            { label = "Spec", options = { "Main spec", "Off spec" }, value = "Main spec" },
        }, ownedBucket(function(v)
            local member, cost, spec = v[1], tonumber(v[2]), v[3] == "Off spec" and "OS" or "MS"
            if not cost or cost < 1 or cost > 1000000 or cost ~= math.floor(cost) then return false, "Enter a whole-number cost from 1 to 1,000,000." end
            confirm("Confirm Loot Purchase", name .. "\nRecipient: " .. member .. " (" .. spec .. ")\nCost: " .. cost .. " DKP\nAvailable: " .. self:GetDKPAvailable(member) .. " DKP\nThis records the purchase and deducts its cost.",
                ownedBucket(function() return self:RecordDKPLoot(member, item, cost, spec) end), "Record")
            return true
        end), "Review")
        return true
    end), "Next")
end

function GD:ShowDKPEntry(record)
    if not record then return end
    local source = record.reverses and self:GetDKPBucket().dkpAwards[record.reverses]
    if (record.loot or source and source.loot) and not self:CanConfigureDKP() then return end
    local reversed = self:GetDKPBucket().dkpSystems["DKX:" .. record.id] ~= nil
    local summary = self:DKPCharacterText(record.member) .. "  " .. (record.amount > 0 and "+" or "") .. record.amount .. " DKP\n"
        .. date("%b %d, %Y %I:%M %p", record.ts) .. " - " .. self:DKPCharacterText(record.by) .. "\n" .. self:Display(record.reason)
        .. (record.spec and ("\nSpec: " .. record.spec) or "") .. (reversed and "\nREVERSED - original entry retained." or "")
    if self:CanConfigureDKP() and not record.reverses and not reversed and record.amount ~= 0 then
        self.ShowInputForm("DKP Entry", {
            { label = "History", value = summary, readOnly = true, multiline = true, max = 1500 },
            { label = "Reason if reversing this entry", value = "", max = 160 },
        }, ownedBucket(function(values)
            local reason = values[2]
            if not reason or not reason:find("%S") then return false, "Enter a reason before reversing." end
            confirm("Reverse DKP Entry", summary .. "\n\nAn opposite adjustment will be recorded.\nReason: " .. self:Display(reason),
                ownedBucket(function() return self:ReverseDKPRecord(record.id, reason) end), "Reverse")
            return true
        end), "Reverse")
    else self.ShowInputForm("DKP Entry", { { label = "History", value = summary, readOnly = true, multiline = true, max = 1500 } }, function() return true end, "Close") end
end

function GD:ShowDKPLinkAlt()
    return report(false, "Each character has its own DKP. Main/alt DKP linking is disabled.")
end

function GD:ShowDKPBackup()
    local ok, backup = self:ExportDKPBackup()
    if not ok then report(ok, backup); return end
    self.ShowInputForm("Export DKP Backup", {
        { label = "Click text, Ctrl+A, Ctrl+C; save outside the game", value = backup, multiline = true, max = 2000000 },
    }, function() return true end, "Close")
end
function GD:ShowDKPRestore()
    if not self:CanConfigureDKP() then return end
    self.ShowInputForm("Restore DKP Backup", {
        { label = "Paste a backup from this guild; records will be merged", value = "", multiline = true, max = 2000000 },
    }, ownedBucket(function(values)
        local backup = values[1]
        confirm("Confirm DKP Restore", "Merge this backup into the current guild's DKP?\nExisting records are preserved. Duplicate entries are applied once.\nRestored data will synchronize to guild members.",
            ownedBucket(function() return self:ImportDKPBackup(backup) end), "Restore")
        return true
    end), "Review")
end

function GD:ShowDKPRecordedReward(preset)
    local raid = self:GetDKPActiveRaid()
    if not isHost(raid) then return false, "Only the recording host can record boss kills or attendance. Ask the host, or use a custom correction." end
    local function currentRecording(callback)
        return ownedBucket(function(...)
            local current = self:GetDKPActiveRaid()
            if not current or current.id ~= raid.id then return false, "The recording changed. Reopen Award Raid." end
            if not isHost(current) then return false, "Only the recording host can award this event." end
            return callback(...)
        end)
    end
    if preset.event == "boss" then
        self.ShowInputForm("Record Boss Kill", {
            { label = "Boss name (use the exact encounter name)", value = "", max = 60 },
            { label = "Recording", value = raid.data.label .. "\n20 DKP per connected guild participant, plus 10 if guild history confirms a first kill.\nAlready-recorded kills cannot be awarded again, including automatic kills.", readOnly = true, multiline = true, max = 500 },
        }, currentRecording(function(values)
            local boss = tostring(values[1] or ""):match("^%s*(.-)%s*$")
            if boss == "" or #boss > 60 or boss:find("%c") then return false, "Enter the boss's encounter name (up to 60 characters)." end
            local members = self:GetDKPParticipants(true)
            if #members == 0 then return false, "No connected guild participants remain in your group." end
            confirm("Confirm Recorded Boss Kill", boss .. "\nRecord this kill for connected guild participants in the current group at confirmation?\n20 DKP each, plus the guild-first bonus when applicable.\nUse the exact boss name to match automatic kill detection.", currentRecording(function() return self:RecordDKPBoss(boss) end), "Record Kill")
            return true
        end), "Review")
    elseif preset.event == "finish" then
        confirm("End DKP Raid", "End " .. raid.data.label .. "?\nConnected guild participants currently grouped receive 10 DKP.\nIf you left the group, recording ends without an end bonus.", currentRecording(function() return self:EndDKPRaid() end), "End Raid")
    else
        self.ShowInputForm("Recorded Attendance", {
            { label = "On-time attendance", value = "The recording grants on-time DKP when it starts.\nCheck Raids > Summary > Checkpoints for the original recipients.\nUse Custom raid award for a reviewed attendance correction.", readOnly = true, multiline = true, max = 500 },
        }, currentRecording(function() return true end), "OK")
    end
    return true
end

function GD:ShowDKPRaidEndReminder(raid, reason)
    if not self:CanConfigureDKP() or self:IsDKPSoloTesting() then return end
    local host = isHost(raid)
    print("GuildDB: RAID NOT ENDED: " .. raid.data.label .. " | Host: " .. self:DKPCharacterText(raid.data.owner) .. ". " .. (reason or "Open DKP > Raids to review the recording."))
    local action = host and "End the recording now?" or "Stop this unfinished recording now?"
    confirm("DKP Raid Still Recording", "RAID NOT ENDED: " .. raid.data.label .. "\nHost: " .. self:DKPCharacterText(raid.data.owner) .. "\n" .. (reason or "The recording is still active.") .. "\n" .. action .. " Already-earned DKP is preserved; no end bonus will be awarded.\nCancel leaves recording active. Review it later in DKP > Raids.", ownedBucket(function()
        local current = self:GetDKPActiveRaid()
        if not current or current.id ~= raid.id then return false, "This recording is no longer active. Open DKP > Raids to review it." end
        if not self:CanConfigureDKP() then return false, "Only officers and the GM can stop this recording." end
        if not self:GetDKPUnfinishedRaidReason(current) then return false, "The host has resumed recording. Open DKP > Raids to review it." end
        if host then return self:EndDKPRaid() end
        return self:StopStaleDKPRecording(raid.id, "raid")
    end), host and "End Recording" or "Stop Recording")
end

function GD:ShowDKPStartRaid()
    if not self:CanConfigureDKP() then return end
    self.ShowInputForm("Record a DKP Raid", {
        { label = "Raid name", value = GetRealZoneText and GetRealZoneText() or "", max = 100 },
        { label = "Attendance and boss awards", value = "Testing: a raid or party is allowed, at any level.\nStart: 10 on-time DKP for connected guild participants.\nBoss kills: 20 DKP plus 10 on the guild's first kill.\nEnd: 10 DKP for current guild participants.\nOnly this host records automatic kills.", readOnly = true, multiline = true, max = 500 },
    }, ownedBucket(function(values) return self:StartDKPRaid(values[1]) end), "Start")
end

function GD:ShowDKPRaidAttendance(raid)
    local options, entries = {}, {}
    for _, event in ipairs(self:GetDKPSystemRecords("DKV")) do
        if event.data.raid == raid.id then
            local title = event.data.label .. " - " .. date("%I:%M %p", event.ts)
            options[#options + 1] = title; entries[title] = event
        end
    end
    if #options == 0 then print("GuildDB: No attendance events have arrived for this raid yet."); return end
    self.ShowInputForm("Raid Attendance", {
        { label = raid.data.label .. " - choose a checkpoint", options = options, value = options[1] },
    }, ownedBucket(function(values)
        local event = entries[values[1]]
        if not event then return false, "Choose a recorded attendance checkpoint." end
        self.ShowInputForm("Attendance Checkpoint", {
            { label = "Event", value = event.data.label, readOnly = true, max = 200 },
            { label = "Attending guild characters (one award per character)", checklist = event.data.participants, value = event.data.participants, readOnly = true },
        }, function() return true end, "Close")
        return true
    end), "View")
end

local function auctionTimer(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
    bar.background = bar:CreateTexture(nil, "BACKGROUND"); bar.background:SetAllPoints()
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); bar.text:SetPoint("CENTER")
    return bar
end
local function updateTimer(bar, record)
    if not record then return end
    local a, colors = record.data, GD:GetAppearanceColors()
    local remaining = GD:GetDKPAuctionRemaining(record)
    local status = GD:GetDKPAuctionStatus(record)
    local clock = GetTime and GetTime()
    if clock and remaining > 0 and status ~= "PAUSED" then
        if bar.clockID ~= record.id or bar.clockEnds ~= a.ends or not bar.clockExpires
            or math.abs(bar.clockExpires - clock - remaining) > 1.2 then
            bar.clockID, bar.clockEnds, bar.clockExpires = record.id, a.ends, clock + remaining
        end
        remaining = math.max(0, bar.clockExpires - clock)
    elseif not clock then bar.clockExpires = nil end
    local seconds = math.ceil(remaining)
    bar:SetMinMaxValues(0, math.max(1, a.duration or 1, remaining))
    bar:SetValue((status == "OPEN" or status == "PAUSED") and remaining or 0)
    bar:SetStatusBarColor(unpack(status == "PAUSED" and {1, .65, .15} or remaining <= 10 and { 0.9, 0.25, 0.18 } or colors.accent))
    bar.background:SetColorTexture(unpack(colors.alternate))
    bar.text:SetText(status == "OPEN" and (string.format("%d:%02d remaining", math.floor(seconds / 60), seconds % 60))
        or status == "PAUSED" and (string.format("Paused - %d:%02d remaining", math.floor(seconds / 60), seconds % 60))
        or status == "REVIEW" and "Bidding closed - awaiting winner confirmation" or status)
end
local function bidderColors()
    local result = {}
    for index = 1, GetNumGuildMembers(true) do
        local name, _, _, _, _, _, _, _, _, _, class = GetGuildRosterInfo(index)
        if name then result[key(name)] = GD:GetDKPClassColor(name) end
    end
    return result
end
local function savedPopupState(field)
    local bucket = GD:GetDKPBucket()
    bucket[field] = bucket[field] or {}
    local character = key(GD:GetDKPGuildMember(GD:PlayerName()) or GD:PlayerName())
    bucket[field][character] = bucket[field][character] or {}
    return bucket[field][character]
end
local function savedDismissals() return savedPopupState("dkpAuctionDismissals") end
local function auctionGroupPresent(auction)
    for _, member in ipairs(GD:GetDKPParticipants(true)) do
        if key(member) == key(auction.data.owner) then return true end
    end
    return false
end
local function buildPopup()
    local frame = CreateFrame("Frame", "GuildDBDKPAuctionPopup", UIParent, "BackdropTemplate")
    escapeWindow(frame, "GuildDBDKPAuctionPopup")
    frame:SetSize(math.max(500, math.min(800, tonumber(GD:GetSetting("dkpAuctionWidth")) or 520)),
        math.max(540, math.min(900, tonumber(GD:GetSetting("dkpAuctionHeight")) or 610)))
    frame:SetPoint("CENTER"); frame:SetFrameStrata("FULLSCREEN_DIALOG"); frame:SetFrameLevel(20)
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(500, 540, 800, 900)
    else frame:SetMinResize(500, 540); frame:SetMaxResize(800, 900) end
    frame:SetClampedToScreen(true); frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame.grip = CreateFrame("Button", nil, frame)
    frame.grip:SetSize(16, 16); frame.grip:SetPoint("BOTTOMRIGHT", -3, 3)
    frame.grip:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
    frame.grip:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
    frame.grip:SetScript("OnMouseDown", function(_, mouse) if mouse == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end end)
    frame.grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        GD:SetSetting("dkpAuctionWidth", frame:GetWidth()); GD:SetSetting("dkpAuctionHeight", frame:GetHeight())
        GD:RefreshDKPAuctionPopup()
    end)
    frame:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    frame.title = label(frame, "GameFontNormalLarge", 16, -16)
    frame.title:SetText("DKP Auction")
    frame.close = button(frame, "X", 28, function()
        if frame.auctionID then dismissed[frame.auctionID] = true end
        frame.manual = false; frame:Hide()
    end)
    frame.close:SetPoint("TOPRIGHT", -12, -10)
    frame:SetScript("OnHide", function()
        if frame.auctionID and frame.dkpBucket == GD:GetDKPBucket() then savedDismissals()[frame.auctionID] = true end
        frame.manual = false
        if frame.amount then frame.amount:ClearFocus() end
        if GameTooltip then GameTooltip:Hide() end
    end)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(32, 32); frame.icon:SetPoint("TOPLEFT", 16, -48)
    frame.iconHover = CreateFrame("Button", nil, frame); frame.iconHover:SetAllPoints(frame.icon)
    itemTooltip(frame.iconHover, function() local r = GD:GetDKPAuction(frame.auctionID); return r and ("item:" .. r.data.item) or "" end)
    frame.item = button(frame, "", 370, function()
        local r = GD:GetDKPAuction(frame.auctionID)
        if r and ChatEdit_InsertLink then
            local _, link = GD:GetDKPItemInfo(tonumber(r.data.item))
            ChatEdit_InsertLink(link or ("item:" .. r.data.item))
        end
    end)
    frame.item:SetPoint("TOPLEFT", 56, -50)
    frame.item:SetPoint("TOPRIGHT", -16, -50)
    frame.item:SetScript("OnEnter", function(self)
        local r = GD:GetDKPAuction(frame.auctionID)
        if r then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:" .. r.data.item); GameTooltip:Show() end
    end)
    frame.item:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.status = label(frame, "GameFontHighlightSmall", 16, -88); frame.status:SetPoint("TOPRIGHT", -16, -88); frame.status:SetHeight(24)
    frame.timer = auctionTimer(frame); frame.timer:SetPoint("TOPLEFT", 16, -118); frame.timer:SetPoint("TOPRIGHT", -16, -118); frame.timer:SetHeight(18)
    frame.leaderCard = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.leaderCard:SetPoint("TOPLEFT", 16, -146); frame.leaderCard:SetPoint("TOPRIGHT", -16, -146); frame.leaderCard:SetHeight(54)
    frame.leaderCard:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    frame.leader = label(frame.leaderCard, "GameFontNormal", 10, -9); frame.leader:SetPoint("TOPRIGHT", -10, -9); frame.leader:SetHeight(18)
    frame.available = label(frame.leaderCard, "GameFontHighlightSmall", 10, -32)
    frame.available:SetPoint("TOPRIGHT", -10, -32); frame.available:SetHeight(16); frame.available:SetWordWrap(false)
    local function submit(amount)
        local ok, message = GD:SubmitDKPBid(frame.auctionID, amount, frame.specValue)
        frame.feedback:SetText(message or (ok and "Bid submitted." or "Bid rejected."))
    end
    frame.minus = button(frame, "-", 32, function() frame.quickOffset = math.max(0, (frame.quickOffset or 0) - 1); GD:RefreshDKPAuctionPopup() end)
    frame.minus:SetPoint("TOPLEFT", 16, -210); frame.minus:SetHeight(32)
    frame.plus = button(frame, "+", 32, function() frame.quickOffset = (frame.quickOffset or 0) + 1; GD:RefreshDKPAuctionPopup() end)
    frame.plus:SetPoint("TOPRIGHT", -16, -210); frame.plus:SetHeight(32)
    frame.quick = button(frame, "Bid", 300, function() submit(frame.quickAmount) end)
    frame.quick:SetPoint("TOPLEFT", 54, -210); frame.quick:SetPoint("TOPRIGHT", -54, -210); frame.quick:SetHeight(32)
    frame.amount = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    frame.amount:SetSize(110, 28); frame.amount:SetPoint("TOPLEFT", 16, -252); frame.amount:SetAutoFocus(false); frame.amount:SetMaxLetters(7)
    GD:StyleEditBox(frame.amount)
    frame.amount:SetScript("OnEnterPressed", function(self)
        if frame.canBid then submit(self:GetText()); self:ClearFocus() end
    end)
    frame.amount:SetScript("OnEscapePressed", function(self) self:ClearFocus(); frame:Hide() end)
    frame.specValue = "MS"
    frame.spec = button(frame, "Main spec", 104, function()
        frame.specValue = frame.specValue == "MS" and "OS" or "MS"
        frame.quickOffset = 0; GD:RefreshDKPAuctionPopup()
    end)
    frame.spec:SetPoint("LEFT", frame.amount, "RIGHT", 8, 0)
    frame.bid = button(frame, "Custom bid", 106, function() submit(frame.amount:GetText()) end)
    frame.bid:SetPoint("LEFT", frame.spec, "RIGHT", 8, 0)
    frame.allIn = button(frame, "All In", 104, function() submit(GD:GetDKPAvailable(GD:PlayerName(), frame.auctionID)) end)
    frame.allIn:SetPoint("TOPRIGHT", -16, -253)
    frame.withdraw = button(frame, "Withdraw bid", 125, function()
        local _, message = GD:SubmitDKPBid(frame.auctionID, 0, frame.specValue, true); frame.feedback:SetText(message or "")
    end)
    frame.withdraw:SetPoint("BOTTOMLEFT", 16, 12)
    frame.pass = button(frame, "Pass", 100, function()
        local auctionID = frame.auctionID
        local function pass()
            local ok, message = GD:SubmitDKPBid(auctionID, 0, "MS", true, true)
            frame.feedback:SetText(message or ""); return ok, message
        end
        local auction, hasBid = GD:GetDKPAuction(auctionID), false
        for _, bid in ipairs(auction and auction.data.bids or {}) do if key(bid.member) == key(GD:GetDKPGuildMember(GD:PlayerName())) then hasBid = true end end
        if hasBid then confirm("Pass on Item", "Passing removes your current bid. You can bid again before bidding closes.", ownedBucket(pass), "Pass") else pass() end
    end)
    frame.pass:SetPoint("LEFT", frame.withdraw, "RIGHT", 8, 0)
    frame.bidderHeader = label(frame, "GameFontNormalSmall", 16, -296)
    frame.bidderHeader:SetText("BIDDERS")
    frame.responses = label(frame, "GameFontHighlightSmall", 0, 0)
    frame.responses:ClearAllPoints(); frame.responses:SetPoint("TOPRIGHT", -16, -296)
    frame.bidderColumns = label(frame, "GameFontHighlightSmall", 16, -314)
    frame.bidderColumns:SetText("Rank / Character")
    frame.specHeader = label(frame, "GameFontHighlightSmall", 0, 0)
    frame.specHeader:ClearAllPoints(); frame.specHeader:SetPoint("TOPRIGHT", -110, -314); frame.specHeader:SetText("Spec")
    frame.amountHeader = label(frame, "GameFontHighlightSmall", 0, 0)
    frame.amountHeader:ClearAllPoints(); frame.amountHeader:SetPoint("TOPRIGHT", -40, -314); frame.amountHeader:SetText("DKP")
    frame.bidScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.bidScroll:SetPoint("TOPLEFT", 16, -334); frame.bidScroll:SetPoint("BOTTOMRIGHT", -36, 114)
    frame.bidContent = CreateFrame("Frame", nil, frame.bidScroll); frame.bidContent:SetSize(440, 100); frame.bidScroll:SetScrollChild(frame.bidContent)
    frame.bidRows = {}; frame.emptyBids = label(frame.bidContent, "GameFontHighlightSmall", 8, -10)
    frame.emptyBids:SetText("No bids yet. Be the first to bid!")
    frame.feedback = label(frame, "GameFontHighlightSmall", 16, -310)
    frame.feedback:ClearAllPoints(); frame.feedback:SetPoint("BOTTOMLEFT", 16, 80); frame.feedback:SetPoint("BOTTOMRIGHT", -16, 80); frame.feedback:SetHeight(28)
    frame.officerControls = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.officerControls:SetPoint("BOTTOMLEFT", 16, 12); frame.officerControls:SetPoint("BOTTOMRIGHT", -16, 12); frame.officerControls:SetHeight(64)
    frame.officerControls:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    frame.officerControls:Hide()
    frame.officerTitle = label(frame.officerControls, "GameFontNormalSmall", 10, -8)
    frame.officerTitle:SetText("OFFICER CONTROLS")
    frame.pause = button(frame.officerControls, "Pause", 110, function()
        local auction = GD:GetDKPAuction(frame.auctionID)
        if auction then report(GD:SetDKPAuctionPaused(auction.id, auction.data.status ~= "PAUSED")) end
    end)
    frame.pause:SetHeight(20); frame.pause:SetPoint("TOPRIGHT", -10, -3)
    frame.stop = button(frame.officerControls, "End auction", 140, function() report(GD:FinishDKPAuction(frame.auctionID)) end)
    frame.stop:SetPoint("BOTTOMLEFT", 10, 10)
    frame.award = button(frame.officerControls, "Confirm winner", 140, function()
        local r = GD:GetDKPAuction(frame.auctionID); local leader = GD:GetDKPAuctionLeader(r)
        if not leader then frame.feedback:SetText("No bids to award."); return end
        local auctionID, winner, cost = r.id, leader.member, leader.amount
        confirm("Confirm Auction Winner", r.data.label .. "\nWinner: " .. winner .. " (" .. leader.spec .. ")\nCost: " .. cost .. " DKP\nThe cost will be deducted and loot history saved.",
            ownedBucket(function() return GD:AwardDKPAuction(auctionID, winner, cost) end), "Award")
    end)
    frame.award:SetPoint("BOTTOMLEFT", 10, 10)
    frame.cancel = button(frame.officerControls, "Cancel auction", 125, function()
        local auctionID = frame.auctionID
        confirm("Cancel Auction", "Cancel this auction? No DKP will be spent.", ownedBucket(function() return GD:CancelDKPAuction(auctionID) end), "Cancel it")
    end)
    frame.cancel:SetPoint("BOTTOMRIGHT", -10, 10)
    frame.remove = button(frame.officerControls, "Remove a bid", 140, function()
        local r = GD:GetDKPAuction(frame.auctionID); if not r then return end
        local options = {}; for _, bid in ipairs(r.data.bids) do options[#options + 1] = bid.member end
        if #options == 0 then return end
        local auctionID = r.id
        GD.ShowInputForm("Remove Auction Bid", { { label = "Bidder", options = options, value = options[1] } }, ownedBucket(function(v) return GD:RemoveDKPAuctionBid(auctionID, v[1]) end), "Remove")
    end)
    frame.remove:SetPoint("LEFT", frame.stop, "RIGHT", 8, 0)
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.timerElapsed = (self.timerElapsed or 0) + elapsed
        if self.timerElapsed >= 0.1 then self.timerElapsed = 0; updateTimer(self.timer, GD:GetDKPAuction(self.auctionID)) end
    end)
    frame:Hide()
    return frame
end

function GD:ShowDKPAuctionPopup(auctionID)
    if not self:IsDKPEnabled() or not self:GetDKPAuction(auctionID) then return end
    if popupBucket ~= self:GetDKPBucket() then popupBucket, dismissed = self:GetDKPBucket(), savedDismissals() end
    popup = popup or buildPopup()
    popup.manual = true; popup.auctionID = auctionID; popup.initializedID = nil; popup.wasLive = false
    savedPopupState("dkpAuctionPresented")[auctionID] = true
    self:RefreshDKPAuctionPopup()
end
function GD:RefreshDKPAuctionPopup()
    if not self:IsDKPEnabled() then self.dkpOutbidState = nil; if popup then popup:Hide() end; return end
    self:CheckDKPOutbidAlert()
    self:CheckDKPCountdownSound()
    if popupBucket ~= self:GetDKPBucket() then
        popupBucket, dismissed = self:GetDKPBucket(), savedDismissals()
        if popup then popup:Hide(); popup.manual = false; popup.auctionID = nil end
    end
    dismissed = savedDismissals()
    if self:GetDKPBucket().dkpAuctionPopups == false and popup and not popup.manual then popup:Hide(); return end
    local active = self:GetDKPActiveAuction()
    local presented = savedPopupState("dkpAuctionPresented")
    local inAuctionGroup = active and auctionGroupPresent(active)
        and (self:CanBidDKPAuction(active, self:PlayerName()) or isHost(active))
    if active and not dismissed[active.id] and not presented[active.id] and self:GetDKPBucket().dkpAuctionPopups ~= false
        and self:GetDKPAuctionStatus(active) == "OPEN" and GD:GetDKPTime() < active.data.ends and inAuctionGroup then
        popup = popup or buildPopup()
        if not popup.manual then popup.auctionID = active.id; presented[active.id] = true end
    end
    if popup and not popup.manual and active and popup.auctionID == active.id and not self:CanBidDKPAuction(active, self:PlayerName()) then
        popup:Hide(); popup.auctionID = nil; return
    end
    if not popup or not popup.auctionID or (dismissed[popup.auctionID] and not popup.manual) then return end
    local r = self:GetDKPAuction(popup.auctionID)
    if not r then popup:Hide(); return end
    popup.dkpBucket = self:GetDKPBucket()
    local a, colors = r.data, self:GetAppearanceColors()
    local leading, bids = self:GetDKPAuctionLeader(r)
    if popup.initializedID ~= r.id then
        popup.initializedID = r.id; popup.amount:SetText(tostring(self:GetDKPNextBid(r.id, "MS")))
        popup.feedback:SetText(""); popup.specValue = "MS"; self.dkpBidStatus = nil
        popup.quickOffset = 0; popup.bidScroll:SetVerticalScroll(0)
    end
    if popup.bidRevision ~= a.revision then popup.bidRevision = a.revision; popup.quickOffset = 0 end
    popup:SetBackdropColor(colors.panel[1], colors.panel[2], colors.panel[3], 1); popup:SetBackdropBorderColor(unpack(colors.accent))
    popup.title:SetTextColor(unpack(colors.accent))
    popup.title:SetText(self:IsDKPSoloTesting() and "SOLO TEST - DKP Auction" or "DKP Auction")
    local itemInfo = self:GetDKPItemAppearance(a.item, a.label)
    popup.item:SetText(itemInfo.name); popup.icon:SetTexture(itemInfo.icon)
    local remaining = self:GetDKPAuctionRemaining(r)
    local status = self:GetDKPAuctionStatus(r)
    popup.status:SetText("Minimum " .. a.minimum .. " | Increase " .. a.increment .. " | Host: " .. self:DKPCharacterText(a.owner))
    updateTimer(popup.timer, r)
    popup.leaderCard:SetBackdropColor(unpack(colors.alternate)); popup.leaderCard:SetBackdropBorderColor(unpack(colors.accent))
    popup.leader:SetText(a.status == "AWARDED" and ("Winner: " .. self:DKPCharacterText(a.winner) .. " - " .. a.cost .. " DKP (" .. a.spec .. ")")
        or (leading and ("Leading: " .. self:DKPCharacterText(leading.member) .. " - " .. leading.amount .. " DKP (" .. leading.spec .. ")") or "No bids yet."))
    local available = self:GetDKPAvailable(self:PlayerName(), r.id)
    local yourBid, account = nil, key(self:GetDKPAccount(self:PlayerName()))
    for _, bid in ipairs(bids) do if key(self:GetDKPAccount(bid.member)) == account then yourBid = bid; break end end
    local ownState = "No bid placed"
    if yourBid then
        ownState = (yourBid == leading and "You lead: " or "Your bid: ") .. yourBid.amount .. " DKP (" .. yourBid.spec .. ")"
        if yourBid ~= leading then ownState = ownState .. " - outbid" end
    end
    if status == "CANCELLED" then ownState = "Auction cancelled"
    elseif status == "AWARDED" then
        ownState = key(self:GetDKPAccount(a.winner)) == account and ("You won: " .. a.cost .. " DKP") or "Auction awarded"
    end
    popup.available:SetText("Available: " .. available .. " DKP  |  " .. ownState)
    local nextBid = self:GetDKPNextBid(r.id, popup.specValue)
    local maximum = math.min(available, 1000000)
    popup.quickOffset = math.min(popup.quickOffset or 0, math.max(0, math.floor((maximum - nextBid) / a.increment)))
    popup.quickAmount = nextBid + popup.quickOffset * a.increment
    popup.quick:SetText((yourBid and yourBid == leading and yourBid.spec == popup.specValue and "Raise to " or "Bid ") .. popup.quickAmount .. " DKP")
    popup.bidderHeader:SetText("BIDDERS (" .. #bids .. ")")
    local responses = self:GetDKPAuctionResponses(r)
    popup.responses:SetText(responses.bid .. " bid / " .. responses.passed .. " passed / " .. responses.waiting .. " waiting")
    popup.responses:SetShown(self:CanConfigureDKP()); popup.responses:SetTextColor(unpack(colors.muted))
    local classColors, own = bidderColors(), key(self:GetDKPGuildMember(self:PlayerName()))
    local width = math.max(100, popup.bidScroll:GetWidth())
    popup.bidContent:SetWidth(width); popup.bidContent:SetHeight(math.max(1, #bids * 28))
    for index, bid in ipairs(bids) do
        local row = popup.bidRows[index]
        if not row then
            row = CreateFrame("Frame", nil, popup.bidContent); row:SetHeight(26)
            row.background = row:CreateTexture(nil, "BACKGROUND"); row.background:SetAllPoints()
            row.name = label(row, "GameFontHighlightSmall", 8, -7); row.name:SetWordWrap(false)
            row.spec = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.spec:SetPoint("RIGHT", -74, 0)
            row.amount = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.amount:SetPoint("RIGHT", -8, 0)
            popup.bidRows[index] = row
        end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -(index - 1) * 28); row:SetPoint("TOPRIGHT", 0, -(index - 1) * 28)
        row.name:SetWidth(math.max(1, width - 128))
        row.name:SetText(index .. ". " .. self:DKPCharacterText(bid.member) .. (key(bid.member) == own and " (You)" or ""))
        local class = classColors[key(bid.member)]
        if class then row.name:SetTextColor(class.r, class.g, class.b) else row.name:SetTextColor(unpack(colors.text)) end
        row.spec:SetText(bid.spec); row.amount:SetText(tostring(bid.amount))
        row.spec:SetTextColor(unpack(colors.muted)); row.amount:SetTextColor(unpack(index == 1 and colors.accent or colors.text))
        row.background:SetColorTexture(unpack(index == 1 and colors.alternate or colors.panel)); row:Show()
    end
    for index = #bids + 1, #popup.bidRows do popup.bidRows[index]:Hide() end
    popup.emptyBids:SetShown(#bids == 0); popup.emptyBids:SetTextColor(unpack(colors.muted))
    self:StyleScrollFrame(popup.bidScroll)
    local pendingBid = self:GetDKPPendingBid(r.id)
    if pendingBid then self.dkpBidStatus = pendingBid.pass and "Sending pass..." or pendingBid.withdraw and "Sending withdrawal..." or "Sending bid..." end
    if self.dkpBidStatus then popup.feedback:SetText(self.dkpBidStatus) end
    local eligible, eligibilityReason = self:CanBidDKPAuction(r, self:PlayerName())
    local connected, connectionReason = true, nil
    if self.GetDKPAuctionConnection then connected, connectionReason = self:GetDKPAuctionConnection(r) end
    local bidding = status == "OPEN" and remaining > 0 and eligible and not pendingBid and connected
    if not connected and (status == "OPEN" or status == "PAUSED" or status == "REVIEW") then
        popup.status:SetText("|cffff7777" .. connectionReason .. "|r")
    end
    if pendingBid then popup.quick:SetText("Sending bid...") end
    if status == "OPEN" and remaining > 0 and not eligible then popup.feedback:SetText(eligibilityReason or "You cannot bid in this auction.") end
    popup.canBid = bidding
    popup.bid:SetEnabled(bidding); popup.withdraw:SetEnabled(bidding and yourBid ~= nil); popup.amount:SetEnabled(bidding); popup.spec:SetEnabled(bidding)
    popup.pass:SetEnabled(bidding and not (a.passed or {})[key(self:GetDKPGuildMember(self:PlayerName()))])
    popup.pass:SetText((a.passed or {})[key(self:GetDKPGuildMember(self:PlayerName()))] and "Passed" or "Pass")
    self:StyleButton(popup.pass)
    popup.quick:SetEnabled(bidding and popup.quickAmount <= maximum)
    popup.allIn:SetEnabled(bidding and available >= nextBid and available <= 1000000)
    popup.minus:SetEnabled(bidding and popup.quickOffset > 0)
    popup.plus:SetEnabled(bidding and popup.quickAmount + a.increment <= maximum)
    popup.spec:SetText(popup.specValue == "MS" and "Main spec" or "Off spec")
    if status == "PAUSED" then
        popup.feedback:SetText("Auction paused by the host. Bids and timer are frozen."); popup.pauseNotice = true
    elseif popup.pauseNotice then
        popup.pauseNotice = nil; popup.feedback:SetText(self.dkpBidStatus or "Bidding resumed.")
    end
    local host, live = isHost(r), status == "OPEN" or status == "PAUSED" or status == "REVIEW"
    local showOfficer = host and live
    popup.officerControls:SetShown(showOfficer)
    popup.officerTitle:SetShown(showOfficer)
    popup.officerControls:SetBackdropColor(unpack(colors.alternate)); popup.officerControls:SetBackdropBorderColor(unpack(colors.muted))
    popup.officerTitle:SetTextColor(unpack(colors.accent))
    popup.stop:SetShown(host and status == "OPEN"); popup.award:SetShown(host and status == "REVIEW")
    popup.cancel:SetShown(host and live); popup.remove:SetShown(host and live)
    popup.stop:SetEnabled(showOfficer and status == "OPEN")
    popup.award:SetEnabled(showOfficer and status == "REVIEW" and leading ~= nil)
    popup.cancel:SetEnabled(showOfficer); popup.remove:SetEnabled(showOfficer and #bids > 0)
    popup.remove:SetEnabled(showOfficer and status ~= "PAUSED" and #bids > 0)
    popup.pause:SetShown(host and (status == "OPEN" or status == "PAUSED")); popup.pause:SetText(status == "PAUSED" and "Resume" or "Pause"); self:StyleButton(popup.pause)
    popup.withdraw:ClearAllPoints(); popup.withdraw:SetPoint("BOTTOMLEFT", 16, showOfficer and 86 or 12)
    popup.bidScroll:ClearAllPoints(); popup.bidScroll:SetPoint("TOPLEFT", 16, -334); popup.bidScroll:SetPoint("BOTTOMRIGHT", -36, showOfficer and 154 or 80)
    popup.feedback:ClearAllPoints(); popup.feedback:SetPoint("BOTTOMLEFT", 16, showOfficer and 118 or 46); popup.feedback:SetPoint("BOTTOMRIGHT", -16, showOfficer and 118 or 46); popup.feedback:SetHeight(28)
    for _, control in ipairs({ popup.close, popup.item, popup.spec, popup.bid, popup.withdraw, popup.stop, popup.award, popup.cancel, popup.remove, popup.minus, popup.plus, popup.allIn }) do self:StyleButton(control) end
    self:StyleButton(popup.quick, "primary")
    popup.item:GetFontString():SetTextColor(itemInfo.r, itemInfo.g, itemInfo.b)
    for _, text in ipairs({ popup.status, popup.available, popup.feedback, popup.bidderColumns, popup.specHeader, popup.amountHeader }) do text:SetTextColor(unpack(colors.text)) end
    popup.leader:SetTextColor(unpack(colors.accent)); popup.bidderHeader:SetTextColor(unpack(colors.accent))
    popup.amount:SetBackdropColor(unpack(colors.panel)); popup.amount:SetTextColor(unpack(colors.text)); popup.amount:SetGuildDBFocusState(popup.amount:HasFocus())
    if not live and (popup.wasLive or not popup.manual) then
        popup.wasLive = false; popup.manual = false; popup:Hide(); return
    end
    popup.wasLive = live; popup:Show()
end

local function buildWorkspace(panel)
    panel.navigation = {}
    for index, section in ipairs({ "Standings", "Auctions", "Raids", "Officer" }) do
        local view = section
        local control = button(panel, section, 76, function()
            if view == "Officer" and not GD:CanConfigureDKP() then return end
            if view == "Standings" then panel.section = nil else panel.section = view end
            if panel.workspace then panel.workspace.scroll:SetVerticalScroll(0) end
            panel.historyMode = false; panel.search:SetText(""); GD:RefreshDKP()
        end)
        control:SetPoint("TOPLEFT", 16 + (index - 1) * 80, -130)
        panel.navigation[section] = control
    end
    local area = CreateFrame("Frame", nil, panel)
    area:SetPoint("TOPLEFT", 16, -168); area:SetPoint("BOTTOMRIGHT", -16, 42)
    area.actions, area.rows = {}, {}
    for index = 1, 6 do
        local b = button(area, "", 96, function(self) if self.action then self.action() end end)
        b:SetPoint("TOPLEFT", (index - 1) * 100, 0); area.actions[index] = b
    end
    area.description = label(area, "GameFontHighlightSmall", 0, -38); area.description:SetHeight(44)
    area.live = CreateFrame("Frame", nil, area, "BackdropTemplate")
    area.live:SetPoint("TOPLEFT", 0, -36); area.live:SetPoint("TOPRIGHT", 0, -36); area.live:SetHeight(102)
    area.live:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    area.live.icon = area.live:CreateTexture(nil, "ARTWORK"); area.live.icon:SetSize(32, 32); area.live.icon:SetPoint("TOPLEFT", 10, -10)
    area.live:EnableMouse(true)
    itemTooltip(area.live, function() local r = GD:GetDKPAuction(area.live.auctionID); return r and ("item:" .. r.data.item) or "" end)
    area.live.title = label(area.live, "GameFontNormal", 50, -10); area.live.title:SetPoint("TOPRIGHT", -10, -10); area.live.title:SetHeight(20)
    area.live.rarity = label(area.live, "GameFontHighlightSmall", 50, -30)
    area.live.detail = label(area.live, "GameFontHighlightSmall", 10, -48); area.live.detail:SetPoint("TOPRIGHT", -10, -48); area.live.detail:SetHeight(26)
    area.live.timer = auctionTimer(area.live); area.live.timer:SetPoint("BOTTOMLEFT", 10, 8); area.live.timer:SetPoint("BOTTOMRIGHT", -10, 8); area.live.timer:SetHeight(18)
    area.live:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed >= 0.1 then self.elapsed = 0; updateTimer(self.timer, GD:GetDKPAuction(self.auctionID)) end
    end)
    area.live:Hide()
    area.nextItem = CreateFrame("Button", nil, area, "BackdropTemplate")
    area.nextItem:SetHeight(44); area.nextItem:SetPoint("TOPRIGHT", 0, -90)
    area.nextItem:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    area.nextItem.icon = area.nextItem:CreateTexture(nil, "ARTWORK"); area.nextItem.icon:SetSize(30, 30); area.nextItem.icon:SetPoint("LEFT", 6, 0)
    area.nextItem.text = label(area.nextItem, "GameFontHighlightSmall", 44, -7); area.nextItem.text:SetPoint("TOPRIGHT", -8, -7); area.nextItem.text:SetHeight(32)
    area.nextItem:SetScript("OnClick", function() GD:ShowDKPAuctionQueue() end)
    itemTooltip(area.nextItem, function() return area.nextItem.link or "" end)
    area.nextItem:Hide()
    area.scroll = CreateFrame("ScrollFrame", nil, area, "UIPanelScrollFrameTemplate")
    area.scroll:SetPoint("TOPLEFT", 0, -90); area.scroll:SetPoint("BOTTOMRIGHT", -20, 0)
    area.content = CreateFrame("Frame", nil, area.scroll); area.content:SetSize(400, 200); area.scroll:SetScrollChild(area.content)
    area.empty = label(area.content, "GameFontHighlight", 8, -8)
    panel.workspace = area
end
local function matching(query, value) return query == "" or key(value):find(query, 1, true) end
function GD:RefreshDKPWorkspace(panel)
    if not panel.workspace then buildWorkspace(panel) end
    if panel.section == "Standings" then panel.section = nil end
    if panel.section == "Loot" then panel.section = "Officer"; panel.officerView = "Loot" end
    panel.navigation.Officer:SetShown(self:CanConfigureDKP())
    if panel.section == "Officer" and not self:CanConfigureDKP() then panel.section = nil end
    local position = 0
    for _, section in ipairs({ "Standings", "Auctions", "Raids", "Officer" }) do
        local control = panel.navigation[section]
        if control:IsShown() then
            control:ClearAllPoints(); control:SetPoint("TOPLEFT", 16 + position * 80, -130)
            position = position + 1
        end
    end
    for section, control in pairs(panel.navigation) do self:StyleButton(control, (panel.section or "Standings") == section and "primary" or nil) end
    local area = panel.workspace
    if not panel.section then
        area:Hide(); panel.nameHeader:Show(); panel.pointsHeader:Show(); panel.scroll:Show()
        return false
    end
    panel.nameHeader:Hide(); panel.pointsHeader:Hide(); panel.scroll:Hide(); area:Show()
    local colors, query, rows, actions = self:GetAppearanceColors(), key(panel.search:GetText()), {}, {}
    local officer, section = self:CanConfigureDKP(), panel.section
    local officerLoot = section == "Officer" and panel.officerView ~= "Adjustments"
    if section == "Officer" then
        actions = {
            { "Starting DKP", function() self:ShowDKPStartingGrantForm() end },
            { "Record Loot", function() self:ShowDKPRecordLoot() end },
            { officerLoot and "Adjustments" or "Loot History", function()
                if not self:CanConfigureDKP() then return end
                panel.officerView = officerLoot and "Adjustments" or "Loot"
                panel.search:SetText(""); area.scroll:SetVerticalScroll(0); self:RefreshDKP()
            end },
            { "Master Loot", function() self:ShowDKPMasterLootSettings() end },
        }
    end
    area.live:Hide(); area.nextItem:Hide(); area.description:Show()
    area.scroll:ClearAllPoints(); area.scroll:SetPoint("TOPLEFT", 0, -90); area.scroll:SetPoint("BOTTOMRIGHT", -20, 0)
    panel.title:SetText((self:IsDKPSoloTesting() and "SOLO TEST - DKP " or "DKP ") .. section); panel.searchLabel:SetText("Search " .. section:lower())
    if section == "Auctions" then
        local active = self:GetDKPActiveAuction()
        if officer and not active then actions[#actions + 1] = { "Start Auction", function() self:ShowDKPStartAuction() end } end
        actions[#actions + 1] = { "Alerts", function() self:ShowDKPAlertSettings() end }
        if officer then actions[#actions + 1] = { "Queue (" .. #self:GetDKPAuctionQueue() .. ")", function() self:ShowDKPAuctionQueue() end } end
        if officer and not active and #self:GetDKPAuctionQueue() > 0 then actions[#actions + 1] = { "Start Next", function() report(self:StartNextDKPQueuedAuction()) end } end
        if officer then actions[#actions + 1] = { "Readiness", function() self:ShowDKPReadiness() end } end
        if active then
            local leader, bids = self:GetDKPAuctionLeader(active)
            area.description:Hide(); area.live:Show(); area.live.auctionID = active.id
            area.live:SetBackdropColor(unpack(colors.panel)); area.live:SetBackdropBorderColor(unpack(colors.accent))
            local itemInfo = self:GetDKPItemAppearance(active.data.item, active.data.label)
            area.live.title:SetText(itemInfo.name .. " - " .. #bids .. " bidder(s)")
            area.live.title:SetTextColor(itemInfo.r, itemInfo.g, itemInfo.b)
            area.live.icon:SetTexture(itemInfo.icon); area.live.rarity:SetText(itemInfo.rarity)
            area.live.rarity:SetTextColor(itemInfo.r, itemInfo.g, itemInfo.b)
            area.live.detail:SetText(leadingText(leader) .. "\nMinimum " .. active.data.minimum .. " | Increase " .. active.data.increment .. " | Host: " .. self:DKPCharacterText(active.data.owner))
            area.live.detail:SetTextColor(unpack(colors.text)); updateTimer(area.live.timer, active)
            area.scroll:ClearAllPoints(); area.scroll:SetPoint("TOPLEFT", 0, -150); area.scroll:SetPoint("BOTTOMRIGHT", -20, 0)
            local openAction = { "Bid Window", function() self:ShowDKPAuctionPopup(active.id) end }
            table.insert(actions, 1, openAction)
            local classColors = bidderColors()
            for index, bid in ipairs(bids) do
                if matching(query, bid.member .. " " .. bid.spec) then
                    local class = classColors[key(bid.member)]
                    rows[#rows + 1] = { title = index .. ". " .. self:DKPCharacterText(bid.member) .. " - " .. bid.amount .. " DKP",
                        detail = (bid.spec == "MS" and "Main spec" or "Off spec") .. (index == 1 and " | Leading" or ""),
                        height = 52, color = class and { class.r, class.g, class.b } or colors.accent }
                end
            end
        end
        if officer and active and not isHost(active) then
            actions[#actions + 1] = { "Recover", function()
                confirm("Recover Auction", "Use this only after the host leaves or disconnects.\nAvailable 60 seconds after the deadline.\nThe old auction stops without charging DKP. The same item opens under your control for 60 seconds.\nAll players must bid again.", ownedBucket(function() return self:RecoverDKPAuction(active.id) end), "Recover")
            end }
            actions[#actions + 1] = { "Stop Stale", function()
                confirm("Stop Stale Auction", "Stop this auction if its host disconnected?\nAvailable 60 seconds after the bidding deadline.\nNo DKP is charged for a cancelled auction.", ownedBucket(function() return self:StopStaleDKPRecording(active.id, "auction") end), "Stop")
            end }
        end
        area.description:SetText("MS bids take priority over OS. Equal bids use acceptance order. Last-second bids extend the shared deadline. At timeout, the host automatically awards the valid winner or cancels without a charge.")
        for _, r in ipairs(self:GetDKPSystemRecords("DKU")) do
            local a, current = r.data, r
            local leader = self:GetDKPAuctionLeader(r)
            local itemInfo = self:GetDKPItemAppearance(a.item, a.label)
            if (not active or r.id ~= active.id) and matching(query, itemInfo.name .. " " .. a.label .. " " .. a.owner .. " " .. a.status .. " " .. a.winner) then
                local statusLabels = { OPEN = "Bidding open", PAUSED = "Paused", REVIEW = "Awaiting award", AWARDED = "Awarded", CANCELLED = "Cancelled" }
                local status = self:GetDKPAuctionStatus(r)
                rows[#rows + 1] = { title = itemInfo.name .. " - " .. (statusLabels[status] or status), itemInfo = itemInfo,
                    color = { itemInfo.r, itemInfo.g, itemInfo.b }, detail = "Host: " .. self:DKPCharacterText(a.owner) .. " | Minimum " .. a.minimum .. " DKP\n"
                    .. (a.status == "AWARDED" and (self:DKPCharacterText(a.winner) .. " paid " .. a.cost .. " DKP") or leadingText(leader)), action = function() self:ShowDKPAuctionPopup(current.id) end, button = "Open" }
            end
        end
    elseif officerLoot then
        panel.title:SetText("DKP Officer - Loot History"); panel.searchLabel:SetText("Search loot history")
        area.description:SetText("Purchases and auction winners share this loot ledger. Reversals retain the original purchase and record a refund separately.")
        for _, r in ipairs(self:GetDKPAwardHistory(query)) do
            if r.loot then
                local entry = r
                local itemInfo = r.item and self:GetDKPItemAppearance(r.item, r.label)
                local delivery = self:GetDKPLootDelivery(r.id)
                rows[#rows + 1] = { title = (itemInfo and itemInfo.name or r.label or r.reason) .. " - " .. math.abs(r.amount) .. " DKP",
                    itemInfo = itemInfo, color = itemInfo and { itemInfo.r, itemInfo.g, itemInfo.b }, detail = self:DKPCharacterText(r.member) .. " (" .. (r.spec or "MS") .. ") | " .. date("%b %d, %I:%M %p", r.ts)
                    .. "\n" .. deliveryText(delivery) .. " | By " .. self:DKPCharacterText(r.by), action = function() self:ShowDKPEntry(entry) end, button = "Details",
                    deliveryText = officer and delivery ~= "Refunded" and (delivery == "Delivered" and "Mark pending" or "Mark delivered") or nil,
                    deliveryAction = ownedBucket(function() report(self:SetDKPLootDelivery(entry.id, delivery ~= "Delivered")) end) }
            end
        end
    elseif section == "Raids" then
        local active = self:GetDKPActiveRaid()
        if officer then
            if not active then actions[#actions + 1] = { "Start Raid", function() self:ShowDKPStartRaid() end } end
            if isHost(active) then
                actions[#actions + 1] = { "End Raid", function()
                    confirm("End DKP Raid", "End this recording?\nConnected guild members currently in your raid or party receive 10 DKP.\nIf you have left the group, the recording ends without an end bonus.", ownedBucket(function() return self:EndDKPRaid() end), "End Raid")
                end }
                actions[#actions + 1] = { "Stop Recording", function()
                    confirm("Stop Raid Recording", "Stop recording without an end-of-raid bonus?\nAlready-earned points are preserved.", ownedBucket(function() return self:StopStaleDKPRecording(active.id, "raid") end), "Stop")
                end }
            elseif active then
                actions[#actions + 1] = { "Stop Recording", function()
                    confirm("Stop Raid Recording", "Stop this raid recording?\nAlready-earned points are preserved. No end-of-raid bonus is awarded.", ownedBucket(function() return self:StopStaleDKPRecording(active.id, "raid") end), "Stop")
                end }
            end
        end
        if officer and (not active or self:IsDKPSoloTesting()) then
            actions[math.min(#actions + 1, 4)] = { self:IsDKPSoloTesting() and "Exit Test" or "Solo Test", function() report(self:ToggleDKPSoloTest()) end }
        end
        local unfinished = officer and active and self:GetDKPUnfinishedRaidReason(active)
        area.description:SetText(unfinished and ("RAID NOT ENDED | Host: " .. self:DKPCharacterText(active.data.owner) .. ". " .. unfinished .. " Use End Raid or Stop Recording to finish it.")
            or self:IsDKPSoloTesting() and "SOLO TEST: you can record a raid and auction items by yourself, at any level. Your 1,000 starting DKP and all test results are temporary."
            or active and ("Auto boss awards active. Host: " .. self:DKPCharacterText(active.data.owner) .. ". 20 DKP per boss, plus 10 for the guild's first recorded kill. Current connected guild raiders receive the award.")
            or "Start recording inside the raid instance, or choose Solo Test to try it alone. Awards: 10 on time, 20 per boss, 10 guild-first bonus, 10 on raid end.")
        for _, r in ipairs(self:GetDKPSystemRecords("DKS")) do
            local raid = r
            if matching(query, r.data.label .. " " .. r.data.owner) then
                rows[#rows + 1] = { title = r.data.label .. (self:GetDKPBucket().dkpSystems["DKZ:" .. r.id] and " - Stopped" or r.data.ended > 0 and " - Finished" or " - Recording"), detail = "Host: " .. self:DKPCharacterText(r.data.owner) .. " | " .. date("%b %d, %I:%M %p", r.data.started),
                    button = "Summary", action = function()
                        self:ShowDKPRaidSummary(raid.id)
                    end }
            end
        end
    elseif section == "Officer" then
        panel.title:SetText("DKP Officer - Adjustments"); panel.searchLabel:SetText("Search adjustments")
        area.description:SetText("GM and rank-1 officer tools. Select a history entry to reverse it with a reason. Every character, including alts, has its own DKP and starting grant.")
        for _, r in ipairs(self:GetDKPAwardHistory(query)) do
            local entry = r
            rows[#rows + 1] = { title = self:DKPCharacterText(r.member) .. " " .. (r.amount > 0 and "+" or "") .. r.amount .. " DKP", detail = date("%b %d, %I:%M %p", r.ts) .. " | " .. self:DKPCharacterText(r.by) .. "\n" .. self:Display(r.reason),
                action = function() self:ShowDKPEntry(entry) end, button = "Details" }
        end
    end
    for index, control in ipairs(area.actions) do
        local action = actions[index]; control:SetShown(action ~= nil)
        control.action = action and action[2] or nil
        if action then control:SetText(action[1]); self:StyleButton(control, index == 1 and "primary" or nil) end
    end
    local counts = { Raids = "raids", Officer = officerLoot and "purchases" or "adjustments" }
    local summary = section == "Auctions" and (#self:GetDKPSystemRecords("DKU") .. " auctions saved")
        or (#rows .. " " .. (counts[section] or "entries"))
    panel.summary:SetText("Your DKP: " .. self:GetDKPBalance(self:PlayerName()) .. "  |  " .. summary)
    if section == "Officer" then panel.summary:SetText(panel.summary:GetText() .. "  |  " .. self:GetDKPPendingDeliveryCount() .. " pending deliveries") end
    if section == "Auctions" and officer then
        local entry = self:GetDKPAuctionQueue()[1]
        if entry then
            local info = self:GetDKPItemAppearance(entry.item, entry.label)
            local nextItem = area.nextItem
            nextItem:ClearAllPoints(); nextItem:SetPoint("TOPLEFT", 0, self:GetDKPActiveAuction() and -146 or -90); nextItem:SetPoint("TOPRIGHT", 0, self:GetDKPActiveAuction() and -146 or -90)
            nextItem.icon:SetTexture(info.icon); nextItem.link = info.link
            nextItem.text:SetText("Next in your queue: " .. info.name .. "\n" .. entry.minimum .. " DKP minimum | " .. entry.duration .. " sec")
            nextItem.text:SetTextColor(info.r, info.g, info.b); nextItem:SetBackdropColor(unpack(colors.alternate)); nextItem:SetBackdropBorderColor(unpack(colors.muted)); nextItem:Show()
            area.scroll:ClearAllPoints(); area.scroll:SetPoint("TOPLEFT", 0, self:GetDKPActiveAuction() and -202 or -144); area.scroll:SetPoint("BOTTOMRIGHT", -20, 0)
        end
    end
    area.description:SetWidth(math.max(100, area:GetWidth())); area.description:SetTextColor(unpack(colors.muted))
    local width, totalHeight = math.max(100, area.scroll:GetWidth()), 0
    for _, value in ipairs(rows) do totalHeight = totalHeight + (value.height or 82) end
    area.content:SetWidth(width); area.content:SetHeight(math.max(area.scroll:GetHeight(), totalHeight))
    local offset = 0
    for index, value in ipairs(rows) do
        local row = area.rows[index]
        if not row then
            row = CreateFrame("Frame", nil, area.content); row:SetHeight(78)
            row.background = row:CreateTexture(nil, "BACKGROUND"); row.background:SetAllPoints()
            row.title = label(row, "GameFontNormal", 8, -8); row.detail = label(row, "GameFontHighlightSmall", 8, -28)
            row.itemIcon = CreateFrame("Button", nil, row); row.itemIcon:SetSize(32, 32); row.itemIcon:SetPoint("LEFT", 8, 0)
            row.itemIcon.texture = row.itemIcon:CreateTexture(nil, "ARTWORK"); row.itemIcon.texture:SetAllPoints()
            itemTooltip(row.itemIcon, function() return row.itemLink or "" end)
            row.action = button(row, "Open", 82, function() if row.callback then row.callback() end end); row.action:SetPoint("RIGHT", -8, 0)
            row.delivery = button(row, "Mark delivered", 118, function() if row.deliveryCallback then row.deliveryCallback() end end)
            row.delivery:SetPoint("BOTTOMRIGHT", -8, 6)
            area.rows[index] = row
        end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -offset); row:SetPoint("TOPRIGHT", 0, -offset)
        row:SetHeight((value.height or 82) - 4); offset = offset + (value.height or 82)
        local inset = value.itemInfo and 48 or 8
        row.title:ClearAllPoints(); row.title:SetPoint("TOPLEFT", inset, -8)
        row.detail:ClearAllPoints(); row.detail:SetPoint("TOPLEFT", inset, -28)
        row.itemIcon:SetShown(value.itemInfo ~= nil)
        if value.itemInfo then row.itemLink = value.itemInfo.link; row.itemIcon.texture:SetTexture(value.itemInfo.icon) end
        local reserved = value.deliveryText and 138 or value.action and 102 or 12
        row.title:SetWidth(math.max(1, width - reserved - inset)); row.detail:SetWidth(math.max(1, width - reserved - inset)); row.detail:SetHeight(value.height and 18 or 40)
        row.title:SetText(value.title); row.detail:SetText(value.detail); row.callback = value.action
        row.title:SetTextColor(unpack(value.color or colors.accent)); row.detail:SetTextColor(unpack(colors.text))
        row.action:SetShown(value.action ~= nil)
        row.action:ClearAllPoints(); row.action:SetPoint(value.deliveryText and "TOPRIGHT" or "RIGHT", -8, value.deliveryText and -6 or 0)
        row.deliveryCallback = value.deliveryAction; row.delivery:SetShown(value.deliveryText ~= nil)
        if value.deliveryText then row.delivery:SetText(value.deliveryText); self:StyleButton(row.delivery) end
        if value.action then row.action:SetText(value.button or "Details"); self:StyleButton(row.action) end
        row.background:SetColorTexture(unpack(index % 2 == 0 and colors.panel or colors.alternate)); row:Show()
    end
    for index = #rows + 1, #area.rows do area.rows[index]:Hide() end
    local emptyText = { Auctions = "No auctions yet. Officers can start one above or Alt + right-click an item.",
        Loot = "No loot purchases recorded yet.", Raids = "No raids recorded yet. Start a raid or choose Solo Test to try it alone.",
        Officer = officerLoot and "No loot purchases recorded yet." or "No DKP adjustments recorded yet." }
    if not officer then emptyText.Auctions = "No auctions have been started yet."; emptyText.Raids = "No raids have been recorded by your officers yet." end
    area.empty:SetWidth(math.max(100, width - 16)); area.empty:SetHeight(52)
    area.empty:SetText(query ~= "" and "No matches. Clear the search to see all entries."
        or section == "Auctions" and self:GetDKPActiveAuction() and "No bids yet. Open Bid Window to place a bid."
        or emptyText[section] or "No entries yet.")
    area.empty:SetShown(#rows == 0)
    self:StyleScrollFrame(area.scroll)
    panel.footer:SetText(self:IsDKPSoloTesting() and "SOLO TEST: temporary data, no guild sync. /gd dkptest exits."
        or section == "Officer" and "Loot purchases, delivery and corrections are managed by officers and the GM." or "Every character has its own DKP balance. Items are distributed by the loot master.")
    return true
end

local refreshAuctionPopup = GD.RefreshDKPAuctionPopup
function GD:RefreshDKPAuctionPopup(...)
    refreshAuctionPopup(self, ...)
    self:RefreshDKPLiveControls()
end

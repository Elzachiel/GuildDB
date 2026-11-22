-- Guild-master-owned invite, relayed by guild peers during normal history sync.
local _, GD = ...
GD:RegisterBucket("discordInvite", function() return {} end)

local function rankOf(name)
    local function key(value)
        return (tostring(value or ""):match("^([^-]+)") or ""):lower():gsub("%s", "")
    end
    if not GetNumGuildMembers or not GetGuildRosterInfo then return end
    for i = 1, GetNumGuildMembers(true) do
        local member, _, rank = GetGuildRosterInfo(i)
        if member and key(member) == key(name) then return tonumber(rank) end
    end
end

function GD:CanManageGuildInvite()
    if not self.bucket or not GetGuildInfo then return false end
    local _, _, rank = GetGuildInfo("player")
    return tonumber(rank) == 0
end

function GD:NormalizeDiscordInvite(value)
    value = tostring(value or ""):match("^%s*(.-)%s*$")
    if value == "" then return "" end
    if #value > 200 then return end
    if not value:find("://", 1, true) then value = "https://" .. value end
    local host, path = value:match("^https://([^/]+)/(.+)$")
    if not host then return end
    host = host:lower()
    local code
    if host == "discord.gg" then code = path:match("^([%w_-]+)/?$")
    elseif host == "discord.com" or host == "www.discord.com" then
        code = path:match("^invite/([%w_-]+)/?$")
    end
    if code then
        local url = "https://discord.gg/" .. code
        if #url <= 200 then return url end
    end
end

function GD:GetGuildDiscordInvite()
    return self.bucket and self.bucket.discordInvite and self.bucket.discordInvite.url or ""
end

function GD:SetGuildDiscordInvite(value)
    if not self:CanManageGuildInvite() then return false, "Only the guild master can change the Discord invite." end
    local url = self:NormalizeDiscordInvite(value)
    if not url then return false, "Paste a discord.gg invite or a discord.com/invite link, or leave blank to remove it." end
    local current = self.bucket.discordInvite or {}
    local record = {url = url, ts = math.max(time(), (current.ts or 0) + 1), by = self:PlayerName()}
    self.bucket.discordInvite = record
    self:SendRecord("DI", "invite", record.ts, record.by, url)
    if self.RefreshUI then self:RefreshUI() end
    return true, url == "" and "Discord invite removed." or "Discord invite saved and shared with the guild."
end

local pending = {}
local function receive(id, ts, author, content, sender)
    if not GD.bucket or id ~= "invite" then return end
    local url = GD:NormalizeDiscordInvite(content)
    if not url then return end
    if GetNumGuildMembers and GetNumGuildMembers(true) == 0 then
        if #pending < 60 then pending[#pending + 1] = {
            id = id, ts = ts, author = author, content = content, sender = sender, bucket = GD.bucket,
        } end
        return
    end
    if rankOf(author) ~= 0 or rankOf(sender) == nil then return end
    local current = GD.bucket.discordInvite or {}
    if ts < (current.ts or 0) or (ts == (current.ts or 0) and author <= (current.by or "")) then return end
    GD.bucket.discordInvite = {url = url, ts = ts, by = author}
    if GD.RefreshUI then GD:RefreshUI() end
end
GD:RegisterRecordHandler("DI", receive, 200)
GD:RegisterEventHandler("GUILD_ROSTER_UPDATE", function()
    if not GetNumGuildMembers or GetNumGuildMembers(true) == 0 then return end
    local records = pending
    pending = {}
    for _, record in ipairs(records) do
        if record.bucket == GD.bucket then receive(record.id, record.ts, record.author, record.content, record.sender) end
    end
end)
GD:RegisterHistoryProvider(function()
    local record = GD.bucket and GD.bucket.discordInvite
    if record and record.ts then GD:SendRecord("DI", "invite", record.ts, record.by, record.url or "") end
end)

function GD:ShowGuildDiscordInvite()
    local url = self:GetGuildDiscordInvite()
    if url == "" then return end
    local dialog = self.discordInviteDialog
    if not dialog then
        dialog = CreateFrame("Frame", "GuildDBDiscordInviteDialog", UIParent, "BackdropTemplate")
        self.discordInviteDialog = dialog
        dialog:SetSize(430, 180)
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetClampedToScreen(true)
        dialog:EnableMouse(true)
        dialog:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 16})
        dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        dialog.title:SetPoint("TOPLEFT", 20, -18)
        dialog.title:SetText("Join our Discord server")
        dialog.note = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        dialog.note:SetPoint("TOPLEFT", 20, -48)
        dialog.note:SetWidth(390)
        dialog.note:SetText("Press Ctrl+C to copy, then paste into your browser.")
        dialog.input = CreateFrame("EditBox", nil, dialog, "BackdropTemplate")
        dialog.input:SetSize(390, 28)
        dialog.input:SetPoint("TOPLEFT", 20, -78)
        dialog.input:SetAutoFocus(false)
        dialog.input:SetMaxLetters(200)
        self:StyleEditBox(dialog.input)
        dialog.input:SetScript("OnEscapePressed", function() dialog:Hide() end)
        dialog.input:SetScript("OnEnterPressed", function() dialog:Hide() end)
        dialog.input:SetScript("OnEditFocusGained", function(input) input:HighlightText() end)
        dialog.input:SetScript("OnMouseUp", function(input) input:SetFocus(); input:HighlightText() end)
        dialog.input:SetScript("OnTextChanged", function(input)
            if input:GetText() ~= dialog.url then input:SetText(dialog.url or ""); input:HighlightText() end
        end)
        dialog.close = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        dialog.close:SetSize(90, 26)
        dialog.close:SetPoint("BOTTOMRIGHT", -20, 18)
        dialog.close:SetText("Close")
        dialog.close:SetScript("OnClick", function() dialog:Hide() end)
        dialog:SetScript("OnHide", function() dialog.input:ClearFocus() end)
        UISpecialFrames = UISpecialFrames or {}
        table.insert(UISpecialFrames, "GuildDBDiscordInviteDialog")
    end
    self:StyleSurface(dialog, "window")
    self:StyleButton(dialog.close, "primary")
    dialog.url, dialog.guildBucket = url, self.bucket
    dialog.input:SetText(url)
    dialog:Show()
    dialog.input:SetFocus()
    dialog.input:HighlightText()
end

function GD:RefreshDiscordInviteButton()
    local button = self.frame and self.frame.discordButton
    if button then
        self:StyleButton(button, "primary")
        local configured = self:GetGuildDiscordInvite() ~= ""
        button:SetText(configured and "Join Guild Discord" or "Discord Not Set")
        button:SetEnabled(configured)
    end
    local dialog = self.discordInviteDialog
    if dialog and (dialog.guildBucket ~= self.bucket or dialog.url ~= self:GetGuildDiscordInvite()) then dialog:Hide() end
end

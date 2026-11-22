-- A single officer-maintained page for rules, Discord, raid times, and more.
local _, GD = ...
local limit = 3000
GD:RegisterBucket("guildInfo", function() return {} end)
GD:RegisterTab("Guild Info", function() return "" end)

local function nameKey(name)
    return (tostring(name or ""):match("^([^-]+)") or ""):lower():gsub("%s", "")
end

local function rankOf(name)
    if not GetNumGuildMembers or not GetGuildRosterInfo then return end
    for i = 1, GetNumGuildMembers(true) do
        local member, _, rank = GetGuildRosterInfo(i)
        if member and nameKey(member) == nameKey(name) then return tonumber(rank) end
    end
end

function GD:GetGuildInfoText()
    return self.bucket and self.bucket.guildInfo and self.bucket.guildInfo.text or ""
end

function GD:SetGuildInfoText(text)
    if not self.bucket then return false, "Join a guild first." end
    if not self:CanManage() then return false, "Only the guild leader or rank 1 can edit Guild Info." end
    text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("%z", ""):gsub("|", " ")
    if #text > limit then return false, "Guild Info must be 3,000 bytes or fewer." end
    local current = self.bucket.guildInfo or {}
    local record = {text = text, ts = math.max(time(), (current.ts or 0) + 1), by = self:PlayerName()}
    self.bucket.guildInfo = record
    self:SendRecord("GI", "info", record.ts, record.by, text)
    if self.RefreshUI then self:RefreshUI() end
    return true, "Guild Info saved and shared with the guild."
end

local pending = {}
local function receive(id, ts, author, content, sender)
    if not GD.bucket or id ~= "info" or #content > limit then return end
    if GetNumGuildMembers and GetNumGuildMembers(true) == 0 then
        if #pending < 60 then pending[#pending + 1] = {
            id = id, ts = ts, author = author, content = content, sender = sender, bucket = GD.bucket,
        } end
        return
    end
    local rank = rankOf(author)
    if rank == nil or rank > 1 or rankOf(sender) == nil then return end
    local current = GD.bucket.guildInfo or {}
    if ts < (current.ts or 0) or (ts == (current.ts or 0) and author <= (current.by or "")) then return end
    GD.bucket.guildInfo = {text = content, ts = ts, by = author}
    if GD.RefreshUI then GD:RefreshUI() end
end
GD:RegisterRecordHandler("GI", receive, limit)
GD:RegisterEventHandler("GUILD_ROSTER_UPDATE", function()
    if not GetNumGuildMembers or GetNumGuildMembers(true) == 0 then return end
    local records = pending
    pending = {}
    for _, record in ipairs(records) do
        if record.bucket == GD.bucket then
            receive(record.id, record.ts, record.author, record.content, record.sender)
        end
    end
end)
GD:RegisterHistoryProvider(function()
    local info = GD.bucket and GD.bucket.guildInfo
    if info and info.ts then GD:SendRecord("GI", "info", info.ts, info.by, info.text or "") end
end)

local function label(parent, font)
    local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    return text
end

local function layout(panel)
    local width = math.max(80, panel.scroll:GetWidth())
    panel.content:SetWidth(width)
    panel.text:SetWidth(width - 16)
    panel.input:SetWidth(width - 4)
    local height = panel.editing and math.max(panel.scroll:GetHeight(), panel.input:GetNumLines() * 20 + 24)
        or math.max(panel.scroll:GetHeight(), panel.text:GetStringHeight() + 16)
    panel.input:SetHeight(height)
    panel.content:SetHeight(height)
    panel.scroll:SetVerticalScroll(math.min(panel.scroll:GetVerticalScroll(), math.max(0, height - panel.scroll:GetHeight())))
end

local function build(frame)
    local panel = CreateFrame("Frame", nil, frame.detailPanel, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", 10, -10)
    panel:SetPoint("BOTTOMRIGHT", -10, 12)
    panel:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1})
    panel.title = label(panel, "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 14, -14)
    panel.title:SetText("Guild Info")
    panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scroll:SetPoint("TOPLEFT", 12, -50)
    panel.scroll:SetPoint("BOTTOMRIGHT", -30, 42)
    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetSize(100, 100)
    panel.scroll:SetScrollChild(panel.content)
    panel.text = label(panel.content)
    panel.text:SetPoint("TOPLEFT", 8, -8)
    panel.input = CreateFrame("EditBox", nil, panel.content, "BackdropTemplate")
    GD:StyleEditBox(panel.input, true)
    panel.input:SetPoint("TOPLEFT")
    panel.input:SetAutoFocus(false)
    panel.input:SetMaxLetters(limit)
    panel.input:SetScript("OnTextChanged", function() if panel.editing then layout(panel) end end)
    panel.input:SetScript("OnCursorChanged", function(_, _, y, _, height)
        if not panel.editing then return end
        local top, scroll = -y, panel.scroll:GetVerticalScroll()
        local bottom = top + height
        if top < scroll then panel.scroll:SetVerticalScroll(math.max(0, top))
        elseif bottom > scroll + panel.scroll:GetHeight() then
            panel.scroll:SetVerticalScroll(math.max(0, bottom - panel.scroll:GetHeight()))
        end
    end)
    panel.input:SetScript("OnEscapePressed", function(input) input:ClearFocus() end)
    panel.input:SetScript("OnHide", function(input) input:ClearFocus() end)
    panel.note = label(panel, "GameFontHighlightSmall")
    panel.note:SetPoint("BOTTOMLEFT", 14, 14)
    panel.note:SetPoint("BOTTOMRIGHT", -14, 14)
    local function button(text, width, click)
        local control = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        control:SetSize(width, 24)
        control:SetText(text)
        control:SetScript("OnClick", click)
        return control
    end
    panel.edit = button("Edit", 62, function()
        if not GD.bucket or not GD:CanManage() then return end
        panel.editing, panel.editBucket = true, GD.bucket
        panel.input:SetText(GD:GetGuildInfoText())
        panel.scroll:SetVerticalScroll(0)
        GD:RefreshUI()
        panel.input:SetFocus()
    end)
    panel.edit:SetPoint("TOPRIGHT", -14, -10)
    panel.save = button("Save", 62, function()
        if not panel.editing or panel.editBucket ~= GD.bucket then return end
        local ok, message = GD:SetGuildInfoText(panel.input:GetText())
        if not ok then panel.note:SetText(message); return end
        panel.editing = false
        panel.input:ClearFocus()
        panel.scroll:SetVerticalScroll(0)
        GD:RefreshUI()
    end)
    panel.save:SetPoint("TOPRIGHT", -84, -10)
    panel.cancel = button("Cancel", 62, function()
        panel.editing = false
        panel.input:ClearFocus()
        panel.scroll:SetVerticalScroll(0)
        GD:RefreshUI()
    end)
    panel.cancel:SetPoint("TOPRIGHT", -14, -10)
    panel.scroll:SetScript("OnSizeChanged", function() layout(panel) end)
    frame.guildInfo = panel
    return panel
end

function GD:RefreshGuildInfoAppearance()
    local panel = self.frame and self.frame.guildInfo
    if not panel then return end
    local colors = self:GetAppearanceColors()
    panel:SetBackdropColor(unpack(colors.alternate))
    panel:SetBackdropBorderColor(colors.accent[1] * 0.5, colors.accent[2] * 0.5, colors.accent[3] * 0.5, 1)
    panel.title:SetTextColor(unpack(colors.accent))
    panel.text:SetTextColor(unpack(colors.text))
    panel.note:SetTextColor(unpack(colors.muted))
    self:StyleEditBox(panel.input, true)
    self:StyleButton(panel.edit)
    self:StyleButton(panel.save, "primary")
    self:StyleButton(panel.cancel)
end

function GD:RefreshGuildInfo()
    local frame = self.frame
    local panel = frame.guildInfo or build(frame)
    for _, key in ipairs({"detailScroll", "detailTitle", "detailMeta", "detailRule", "footer"}) do frame[key]:Hide() end
    local editable = self.bucket ~= nil and self:CanManage()
    if not editable or panel.editBucket ~= self.bucket then panel.editing = false end
    panel.edit:SetShown(editable and not panel.editing)
    panel.save:SetShown(panel.editing == true)
    panel.cancel:SetShown(panel.editing == true)
    panel.input:SetShown(panel.editing == true)
    panel.text:SetShown(not panel.editing)
    local text = self:GetGuildInfoText()
    panel.text:SetText(self:Display(text ~= "" and text or (self.bucket and
        "No guild information yet. An officer can add rules, a Discord link, raid times, and more." or
        "Join a guild to view Guild Info.")))
    local record = self.bucket and self.bucket.guildInfo
    panel.note:SetText(panel.editing and "Rules, Discord link, raid times, and more." or
        (record and record.by and ("Last updated by " .. self:Display(record.by)) or ""))
    panel:Show()
    layout(panel)
    self:RefreshGuildInfoAppearance()
end

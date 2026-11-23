-- Separate officer-maintained information and rules pages.
local _, GD = ...
local limit = 3000
GD:RegisterBucket("guildInfo", function() return {} end)
GD:RegisterBucket("guildRules", function() return {} end)
GD:RegisterTab("Guild Info", function() return "" end)
local pageKeys = {info = "guildInfo", rules = "guildRules"}
local starterText = {
    info = "Welcome to our guild!\n\nWe are a growing guild building a friendly, active community. Whether you are leveling, running dungeons, crafting, raiding, or enjoying world PvP, there is a place for you here.\n\nHelp us grow\nKnow someone looking for a guild? Invite them to get to know us and speak with an officer about joining. Help new members settle in, include guildmates in your groups, and keep guild chat welcoming.\n\nGuildDB is a work in progress\nThis addon is being developed and improved as our guild grows. Features and layouts may change, and you may encounter bugs. Please share issues and suggestions with an officer, and keep your addon updated.\n\nStay involved\nCheck Raid Info for upcoming activities, answer guild polls, and use the boards to find groups or request crafting. Use Join Guild Discord at the top of GuildDB to get our server invite.",
    rules = "Guild Rules\n\n1. Respect everyone. Treat guildmates and other players with courtesy. Harassment, hate speech, and personal attacks are not welcome.\n\n2. Keep chat welcoming. Avoid spam and disruptive arguments. Take disagreements to an officer privately.\n\n3. Play fairly. Follow the server rules. Do not cheat, scam, or take advantage of guildmates.\n\n4. Be considerate with loot. Agree on loot rules before a run, follow the group's rules, and ask if anything is unclear.\n\n5. Respect people's time. Sign up honestly, arrive prepared, and let the organizer know if you will be late or cannot attend.\n\n6. Work as a team. Follow the group leader's calls during organized activities and give feedback respectfully.\n\n7. Help the guild grow. Welcome new members, offer help when you can, and represent the guild well.\n\n8. Speak up when needed. Bring concerns to an officer so they can be handled fairly.",
}

function GD:GetGuildInfoPageText(section)
    section = section == "rules" and "rules" or "info"
    if not self.bucket then return "" end
    local record = self.bucket[pageKeys[section]]
    if record and (record.ts or record.text ~= nil) then return record.text or "" end
    return starterText[section]
end

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

local function savePage(self, section, text)
    if not self.bucket then return false, "Join a guild first." end
    if not self:CanManage() then return false, "Only the guild leader or rank 1 can edit Guild Info." end
    text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("%z", ""):gsub("|", " ")
    if #text > limit then return false, "Guild Info must be 3,000 bytes or fewer." end
    local key = pageKeys[section]
    local current = self.bucket[key] or {}
    local record = {text = text, ts = math.max(time(), (current.ts or 0) + 1), by = self:PlayerName()}
    self.bucket[key] = record
    self:SendRecord("GI", section, record.ts, record.by, text)
    if self.RefreshUI then self:RefreshUI() end
    return true, (section == "rules" and "Guild Rules" or "Guild Info") .. " saved and shared with the guild."
end

function GD:SetGuildInfoText(text)
    return savePage(self, "info", text)
end

function GD:SetGuildRulesText(text)
    return savePage(self, "rules", text)
end

local pending = {}
local function receive(id, ts, author, content, sender)
    if not GD.bucket or not pageKeys[id] or #content > limit then return end
    if GetNumGuildMembers and GetNumGuildMembers(true) == 0 then
        if #pending < 60 then pending[#pending + 1] = {
            id = id, ts = ts, author = author, content = content, sender = sender, bucket = GD.bucket,
        } end
        return
    end
    local rank = rankOf(author)
    if rank == nil or rank > 1 or rankOf(sender) == nil then return end
    local current = GD.bucket[pageKeys[id]] or {}
    if ts < (current.ts or 0) or (ts == (current.ts or 0) and author <= (current.by or "")) then return end
    GD.bucket[pageKeys[id]] = {text = content, ts = ts, by = author}
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
    for section, key in pairs(pageKeys) do
        local record = GD.bucket and GD.bucket[key]
        if record and record.ts then GD:SendRecord("GI", section, record.ts, record.by, record.text or "") end
    end
end)

local function label(parent, font)
    local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    return text
end

-- Return a UTF-8 byte offset at the nearest character on the clicked visual
-- line. Forever clients can focus a multiline box without moving its cursor.
local function cursorLines(text, width, measure)
    local chars, lines = {}, {}
    local offset = 0
    while offset < #text do
        local byte = text:byte(offset + 1)
        local length = byte < 128 and 1 or byte < 224 and 2 or byte < 240 and 3 or 4
        length = math.min(length, #text - offset)
        chars[#chars + 1] = {first = offset, last = offset + length, value = text:sub(offset + 1, offset + length)}
        offset = offset + length
    end
    local first, index, space = 0, 1, nil
    while index <= #chars do
        local char = chars[index]
        if char.value == "\n" then
            lines[#lines + 1] = {first = first, last = char.first}
            first, space, index = char.last, nil, index + 1
        elseif char.first > first and measure(text:sub(first + 1, char.last)) > width then
            if char.value == " " or char.value == "\t" then
                lines[#lines + 1] = {first = first, last = char.first}
                first, index = char.last, index + 1
            elseif space and space.first > first then
                lines[#lines + 1] = {first = first, last = space.first}
                first, index = space.last, space.index + 1
            else
                lines[#lines + 1] = {first = first, last = char.first}
                first = char.first
            end
            space = nil
        else
            if char.value == " " or char.value == "\t" then
                space = {first = char.first, last = char.last, index = index}
            end
            index = index + 1
        end
    end
    lines[#lines + 1] = {first = first, last = #text}
    return chars, lines
end

function GD:GuildInfoClickOffset(text, width, lineHeight, x, y, measure)
    local chars, lines = cursorLines(text, width, measure)
    local row = math.max(1, math.min(#lines, math.floor(math.max(0, y) / math.max(1, lineHeight)) + 1))
    local line, previous = lines[row], 0
    for _, char in ipairs(chars) do
        if char.first >= line.first and char.last <= line.last then
            local right = measure(text:sub(line.first + 1, char.last))
            if x < (previous + right) / 2 then return char.first end
            previous = right
        end
    end
    return line.last
end

function GD:GuildInfoCursorPoint(text, width, lineHeight, position, measure)
    local _, lines = cursorLines(text, width, measure)
    for row, line in ipairs(lines) do
        if not lines[row + 1] or position < lines[row + 1].first then
            return measure(text:sub(line.first + 1, math.min(position, line.last))), (row - 1) * lineHeight
        end
    end
end

local function cursorMetrics(panel)
    local input = panel.input
    local font, size, flags = input:GetFont()
    if not font then return end
    local left, right, top = input:GetTextInsets()
    panel.cursorMeasure:SetFont(font, size, flags or "")
    local function measure(value)
        panel.cursorMeasure:SetText(value)
        return panel.cursorMeasure:GetStringWidth()
    end
    return left, top, input:GetWidth() - left - right, panel.cursorLineHeight or size, measure
end

local function clickedPosition(panel)
    if not panel.editing or not GetCursorPosition then return end
    local input = panel.input
    local pointerX, pointerY = GetCursorPosition()
    local scale = panel.scroll:GetEffectiveScale()
    local left, top = panel.scroll:GetLeft(), panel.scroll:GetTop()
    if not left or not top or not scale or scale <= 0 then return end
    local insetLeft, insetTop, width, lineHeight, measure = cursorMetrics(panel)
    if not measure then return end
    local x = pointerX / scale - left - insetLeft
    local y = top - pointerY / scale + panel.scroll:GetVerticalScroll() - insetTop
    return GD:GuildInfoClickOffset(input:GetText(), width, lineHeight, x, y, measure)
end

local function updateSelection(panel)
    local position = clickedPosition(panel)
    if position == nil or panel.dragAnchor == nil then return end
    if panel.dragPosition == position then return end
    panel.dragPosition = position
    panel.input:SetCursorPosition(position)
    if position == panel.dragAnchor then
        panel.input:HighlightText(0, 0)
    else
        panel.input:HighlightText(math.min(position, panel.dragAnchor), math.max(position, panel.dragAnchor))
    end
    panel.caretDirty, panel.caretElapsed = true, 0
end

local function updateCaret(panel, elapsed)
    local input = panel.input
    if not panel.editing or not input:HasFocus() then panel.caret:Hide(); return end
    local position, text = input:GetCursorPosition(), input:GetText()
    if type(position) ~= "number" then position = #text end
    if panel.caretDirty or position ~= panel.caretPosition or text ~= panel.caretText or input:GetWidth() ~= panel.caretWidth then
        local left, top, width, lineHeight, measure = cursorMetrics(panel)
        if not measure then panel.caret:Hide(); return end
        local x, y = GD:GuildInfoCursorPoint(text, width, lineHeight, position, measure)
        panel.caret:ClearAllPoints()
        panel.caret:SetPoint("TOPLEFT", input, "TOPLEFT", left + x, -top - y)
        panel.caret:SetSize(2, lineHeight)
        panel.caretPosition, panel.caretText, panel.caretWidth = position, text, input:GetWidth()
        panel.caretDirty, panel.caretElapsed = false, 0
    end
    panel.caretElapsed = (panel.caretElapsed or 0) + elapsed
    panel.caret:SetShown(panel.caretElapsed % 1 < 0.5)
end

local function layout(panel)
    if panel.infoTab then
        local tabWidth = math.max(80, (panel:GetWidth() - 36) / 2)
        panel.infoTab:SetWidth(tabWidth)
        panel.rulesTab:SetWidth(tabWidth)
    end
    local width = math.max(80, panel.scroll:GetWidth())
    panel.content:SetWidth(width)
    panel.text:SetWidth(width - 16)
    if panel.input:GetWidth() ~= width - 4 then panel.input:SetWidth(width - 4) end
    local height = panel.editing and math.max(panel.scroll:GetHeight(), panel.input:GetNumLines() * 20 + 24)
        or math.max(panel.scroll:GetHeight(), panel.text:GetStringHeight() + 16)
    if panel.input:GetHeight() ~= height then panel.input:SetHeight(height) end
    panel.content:SetHeight(height)
    panel.scroll:SetVerticalScroll(math.min(panel.scroll:GetVerticalScroll(), math.max(0, height - panel.scroll:GetHeight())))
end

local function build(frame)
    local panel = CreateFrame("Frame", nil, frame.detailPanel, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", 10, -10)
    panel:SetPoint("BOTTOMRIGHT", -10, 12)
    panel:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1})
    panel.title = label(panel, "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 14, -60)
    panel.title:SetText("Guild Info")
    panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scroll:SetPoint("TOPLEFT", 12, -98)
    panel.scroll:SetPoint("BOTTOMRIGHT", -30, 42)
    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetSize(100, 100)
    panel.scroll:SetScrollChild(panel.content)
    panel.scrollChild = panel.content
    panel.text = label(panel.content)
    panel.text:SetPoint("TOPLEFT", 8, -8)
    -- A multiline EditBox must be the direct scroll child while editing so
    -- the client hit-tests clicks against the same coordinates as its text.
    panel.input = CreateFrame("EditBox", nil, panel.scroll, "BackdropTemplate")
    GD:StyleEditBox(panel.input, true)
    panel.input:SetPoint("TOPLEFT")
    panel.input:SetAutoFocus(false)
    panel.input:EnableMouse(true)
    panel.input:SetBlinkSpeed(0.5)
    panel.input:SetAltArrowKeyMode(false)
    panel.input:SetMaxLetters(limit)
    panel.cursorMeasure = panel:CreateFontString(nil, "OVERLAY")
    panel.cursorMeasure:SetWordWrap(false)
    panel.cursorMeasure:Hide()
    panel.caret = panel.input:CreateTexture(nil, "OVERLAY")
    panel.caret:SetColorTexture(1, 1, 1, 1)
    panel.caret:Hide()
    panel.input:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local position = clickedPosition(panel)
        if position == nil then return end
        local shift = IsShiftKeyDown and IsShiftKeyDown()
        local previous = panel.input:GetCursorPosition()
        panel.dragAnchor = shift and (panel.selectionAnchor or previous) or position
        panel.dragPosition = nil
        panel.selectionAnchor = panel.dragAnchor
        panel.input:SetFocus()
        updateSelection(panel)
        updateCaret(panel, 0)
    end)
    panel.input:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        updateSelection(panel)
        panel.dragAnchor = nil
        updateCaret(panel, 0)
    end)
    panel.input:SetScript("OnUpdate", function(_, elapsed)
        if panel.dragAnchor ~= nil then updateSelection(panel) end
        updateCaret(panel, elapsed)
    end)
    panel.input:SetScript("OnEditFocusGained", function() panel.caretDirty = true; updateCaret(panel, 0) end)
    panel.input:SetScript("OnEditFocusLost", function() panel.dragAnchor = nil; panel.caret:Hide() end)
    panel.input:SetScript("OnTextChanged", function()
        panel.caretDirty, panel.selectionAnchor, panel.dragAnchor = true, nil, nil
        if panel.editing then layout(panel) end
    end)
    panel.input:SetScript("OnCursorChanged", function(_, _, y, _, height)
        if not panel.editing then return end
        if height > 0 then panel.cursorLineHeight = height end
        panel.caretDirty = true
        local top, scroll = -y, panel.scroll:GetVerticalScroll()
        local bottom = top + height
        if top < scroll then panel.scroll:SetVerticalScroll(math.max(0, top))
        elseif bottom > scroll + panel.scroll:GetHeight() then
            panel.scroll:SetVerticalScroll(math.max(0, bottom - panel.scroll:GetHeight()))
        end
    end)
    panel.input:SetScript("OnEscapePressed", function(input) input:ClearFocus() end)
    panel.input:SetScript("OnHide", function(input) input:ClearFocus(); panel.dragAnchor = nil; panel.caret:Hide() end)
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
        panel.editing, panel.editBucket, panel.editSection = true, GD.bucket, GD.guildInfoSection or "info"
        panel.input:SetText(GD:GetGuildInfoPageText(panel.editSection))
        panel.scroll:SetVerticalScroll(0)
        GD:RefreshUI()
        panel.input:SetFocus()
    end)
    panel.edit:SetPoint("TOPRIGHT", -14, -56)
    panel.save = button("Save", 62, function()
        if not panel.editing or panel.editBucket ~= GD.bucket then return end
        if panel.editSection ~= (GD.guildInfoSection or "info") then return end
        local ok, message = savePage(GD, panel.editSection, panel.input:GetText())
        if not ok then panel.note:SetText(message); return end
        panel.editing = false
        panel.input:ClearFocus()
        panel.scroll:SetVerticalScroll(0)
        GD:RefreshUI()
    end)
    panel.save:SetPoint("TOPRIGHT", -84, -56)
    panel.cancel = button("Cancel", 62, function()
        panel.editing = false
        panel.input:ClearFocus()
        panel.scroll:SetVerticalScroll(0)
        GD:RefreshUI()
    end)
    panel.cancel:SetPoint("TOPRIGHT", -14, -56)
    local function selectSection(section)
        if section == (GD.guildInfoSection or "info") then return end
        if panel.editing then
            panel.note:SetText("Save or cancel your changes before switching pages.")
            return
        end
        GD.guildInfoSection = section
        panel.scroll:SetVerticalScroll(0)
        GD:RefreshUI()
    end
    panel.infoTab = button("Guild Info", 140, function() selectSection("info") end)
    panel.infoTab:SetHeight(30)
    panel.infoTab:SetPoint("TOPLEFT", 14, -12)
    panel.rulesTab = button("Guild Rules", 140, function() selectSection("rules") end)
    panel.rulesTab:SetHeight(30)
    panel.rulesTab:SetPoint("TOPRIGHT", -14, -12)
    panel.scroll:SetScript("OnSizeChanged", function() layout(panel) end)
    panel.scroll:SetScript("OnVerticalScroll", function(_, offset)
        if panel.editing then
            panel.input:SetHitRectInsets(0, 0, offset,
                math.max(0, panel.input:GetHeight() - offset - panel.scroll:GetHeight()))
        end
    end)
    frame.guildInfo = panel
    return panel
end

function GD:RefreshGuildInfoAppearance()
    local panel = self.frame and self.frame.guildInfo
    if not panel then return end
    local colors = self:GetAppearanceColors()
    self:StyleScrollFrame(panel.scroll)
    panel:SetBackdropColor(unpack(colors.alternate))
    panel:SetBackdropBorderColor(colors.accent[1] * 0.5, colors.accent[2] * 0.5, colors.accent[3] * 0.5, 1)
    panel.title:SetTextColor(unpack(colors.accent))
    panel.text:SetTextColor(unpack(colors.text))
    panel.note:SetTextColor(unpack(colors.muted))
    -- Reapplying multiline/font settings while typing can disturb the native
    -- insertion point. Keep the active editor intact during background refreshes.
    if not panel.editing then self:StyleEditBox(panel.input, true) end
    self:StyleButton(panel.edit)
    self:StyleButton(panel.save, "primary")
    self:StyleButton(panel.cancel)
    self:StyleButton(panel.infoTab, self.guildInfoSection ~= "rules" and "primary" or nil)
    self:StyleButton(panel.rulesTab, self.guildInfoSection == "rules" and "primary" or nil)
end

function GD:RefreshGuildInfo()
    local frame = self.frame
    local panel = frame.guildInfo or build(frame)
    for _, key in ipairs({"detailScroll", "detailTitle", "detailMeta", "detailRule", "footer"}) do frame[key]:Hide() end
    local editable = self.bucket ~= nil and self:CanManage()
    local section = self.guildInfoSection == "rules" and "rules" or "info"
    if not editable or panel.editBucket ~= self.bucket or panel.editSection ~= section then panel.editing = false end
    local scrollChild = panel.editing and panel.input or panel.content
    if panel.scrollChild ~= scrollChild then
        panel.scroll:SetScrollChild(scrollChild)
        panel.scrollChild = scrollChild
        panel.scroll:SetVerticalScroll(0)
    end
    panel.title:SetText(section == "rules" and "Guild Rules" or "Guild Info")
    if self.UpdateUnreadState then self:UpdateUnreadState("Guild Info") end
    local function tabText(id, title)
        local unread = self.GetTabUnreadCount and self:GetTabUnreadCount("Guild Info", id) > 0
        return title .. (unread and "  |cffffd140NEW|r" or "")
    end
    panel.infoTab:SetText(tabText("info", "Guild Info"))
    panel.rulesTab:SetText(tabText("rules", "Guild Rules"))
    panel.edit:SetShown(editable and not panel.editing)
    panel.save:SetShown(panel.editing == true)
    panel.cancel:SetShown(panel.editing == true)
    panel.input:SetShown(panel.editing == true)
    panel.text:SetShown(not panel.editing)
    local text = self:GetGuildInfoPageText(section)
    panel.text:SetText(self:Display(text ~= "" and text or (self.bucket and
        (section == "rules" and "No guild rules yet. An officer can edit this page." or "No guild information yet. An officer can edit this page.") or
        "Join a guild to view Guild Info.")))
    local record = self.bucket and self.bucket[pageKeys[section]]
    panel.note:SetText(panel.editing and "Edit this page, then Save to share it with the guild." or
        (record and record.by and ("Last updated by " .. self:Display(record.by)) or ""))
    panel:Show()
    layout(panel)
    self:RefreshGuildInfoAppearance()
end

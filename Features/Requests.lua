-- One workspace with independent group and crafting request panels.
local _, GD = ...

GD:RegisterTab("Requests", function() return "Group and crafting requests" end)

local function button(parent, text, width, click)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetSize(width, 24)
    control:SetText(text)
    control:SetScript("OnClick", click)
    return control
end

local function createPanel(parent, title)
    local panel = CreateFrame("Frame", nil, parent)
    panel.bg = panel:CreateTexture(nil, "BACKGROUND")
    panel.bg:SetAllPoints()
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 12, -12)
    panel.title:SetText(title)
    panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scroll:SetPoint("TOPLEFT", 8, -78)
    panel.scroll:SetPoint("BOTTOMRIGHT", -28, 10)
    panel.child = CreateFrame("Frame", nil, panel.scroll)
    panel.child:SetSize(1, 1)
    panel.scroll:SetScrollChild(panel.child)
    panel.scroll:SetScript("OnSizeChanged", function(_, width)
        panel.child:SetWidth(math.max(1, width))
        if panel.refreshPending or not C_Timer or not C_Timer.After then return end
        panel.refreshPending = true
        C_Timer.After(0, function()
            panel.refreshPending = nil
            if parent:IsShown() then GD:RefreshUI() end
        end)
    end)
    panel.empty = panel.child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.empty:SetPoint("TOPLEFT", 6, -6)
    panel.empty:SetJustifyH("LEFT")
    panel.empty:SetWordWrap(true)
    panel.rows = {}
    return panel
end

local function refreshPanel(panel, entries, crafting, colors)
    panel.bg:SetColorTexture(unpack(colors.alternate))
    panel.title:SetTextColor(unpack(colors.accent))
    GD:StyleButton(panel.post, "primary")
    if panel.find then GD:StyleButton(panel.find) end
    local width = math.max(1, panel.scroll:GetWidth())
    panel.child:SetWidth(width)
    panel.empty:SetWidth(math.max(1, width - 12))
    panel.empty:SetText(GD.bucket and "No active requests." or "Join a guild to view requests.")
    panel.empty:SetTextColor(unpack(colors.text))
    panel.empty:SetShown(#entries == 0)
    local y = 4
    local player = ((UnitName and UnitName("player")) or ""):lower()
    for index, entry in ipairs(entries) do
        local row = panel.rows[index]
        if not row then
            row = CreateFrame("Frame", nil, panel.child)
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.text:SetPoint("TOPLEFT", 8, -8)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(true)
            row.action = button(row, "", 86, function() end)
            row.action:SetPoint("BOTTOMRIGHT", -8, 8)
            panel.rows[index] = row
        end
        local title = crafting and entry.item or (entry.role .. " - " .. entry.activity)
        local remaining = math.max(1, math.ceil((entry.expires - time()) / (crafting and 86400 or 60)))
        local meta = "By " .. GD:Display(entry.by) .. " - " .. remaining .. (crafting and " day(s) left" or " min left")
        if crafting then
            meta = meta .. "\n" .. entry.status:upper()
            if entry.crafter ~= "" then meta = meta .. " - " .. GD:Display(entry.crafter) end
        end
        row.text:SetWidth(math.max(1, width - 20))
        row.text:SetText(GD:Display(title) .. "\n" .. meta .. "\n" .. GD:Display(entry.details))
        row.text:SetTextColor(unpack(colors.text))
        local id, done = entry.id, crafting and entry.status == "claimed"
        local allowed = crafting and entry.status == "pending"
            or entry.by:lower() == player or GD:CanManage()
            or (crafting and done and entry.crafter:lower() == player)
        row.action:SetShown(allowed == true)
        row.action:SetText(crafting and (done and "Complete" or "Claim") or "Close")
        row.action:SetScript("OnClick", function()
            local _, message
            if crafting then _, message = GD:ChangeCraftingRequest(id, done)
            else _, message = GD:CloseLookingRequest(id) end
            if message then print("GuildDB: " .. message) end
        end)
        GD:StyleButton(row.action, "primary")
        row.bg:SetColorTexture(unpack(colors.panel))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 2, -y)
        row:SetWidth(math.max(1, width - 4))
        row:SetHeight(math.max(80, row.text:GetStringHeight() + (allowed and 44 or 18)))
        row:Show()
        y = y + row:GetHeight() + 8
    end
    for index = #entries + 1, #panel.rows do panel.rows[index]:Hide() end
    panel.child:SetHeight(math.max(1, panel.scroll:GetHeight(), y))
    panel.scroll:SetVerticalScroll(math.min(panel.scroll:GetVerticalScroll(), math.max(0, y - panel.scroll:GetHeight())))
end

function GD:RefreshRequests(frame, showForm)
    if not frame.requests then
        local workspace = CreateFrame("Frame", nil, frame.detailPanel)
        workspace:SetPoint("TOPLEFT", 10, -48)
        workspace:SetPoint("BOTTOMRIGHT", -10, 32)
        workspace.looking = createPanel(workspace, "Looking For")
        workspace.crafting = createPanel(workspace, "Crafting")
        workspace.looking:SetPoint("TOPLEFT")
        workspace.looking:SetPoint("BOTTOMRIGHT", workspace, "BOTTOM", -5, 0)
        workspace.crafting:SetPoint("TOPLEFT", workspace, "TOP", 5, 0)
        workspace.crafting:SetPoint("BOTTOMRIGHT")
        workspace.looking.post = button(workspace.looking, "New request", 112, function()
            showForm("Post a group request", {
                { label = "Role", value = "DPS", max = 60 },
                { label = "Activity", value = "", max = 100 },
                { label = "Details", value = "", max = 250, multiline = true },
            }, function(values) return GD:PostLookingRequest(values[1], values[2], values[3]) end)
        end)
        workspace.crafting.post = button(workspace.crafting, "Request a craft", 120, function()
            showForm("Request a craft", {
                { label = "Item or recipe", value = "", max = 100 },
                { label = "Details", value = "", max = 300, multiline = true },
            }, function(values) return GD:PostCraftingRequest(values[1], values[2]) end)
        end)
        workspace.crafting.find = button(workspace.crafting, "Find crafter", 104, function()
            showForm("Find an online crafter", {
                { label = "Profession or recipe", value = "", max = 80 },
            }, function(values)
                local matches = GD:FindGuildCrafters(values[1])
                print(#matches > 0 and ("GuildDB crafters: " .. table.concat(matches, "; ")) or "GuildDB: No online member lists that profession or recipe in their profile.")
                return true
            end)
        end)
        workspace.looking.post:SetPoint("TOPLEFT", 10, -40)
        workspace.crafting.post:SetPoint("TOPLEFT", 10, -40)
        workspace.crafting.find:SetPoint("LEFT", workspace.crafting.post, "RIGHT", 6, 0)
        frame.requests = workspace
    end
    local workspace = frame.requests
    local colors = self:GetAppearanceColors()
    refreshPanel(workspace.looking, self:GetActiveLookingRequests(), false, colors)
    refreshPanel(workspace.crafting, self:GetActiveCraftingRequests(), true, colors)
    workspace:Show()
end

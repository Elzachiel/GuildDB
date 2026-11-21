-- Officer-maintained guild rules and loot reference.
local _, GH = ...
GH:RegisterBucket("guide", function() return { rules = "", loot = "", ts = 0 } end)

GH:RegisterRecordHandler("G", function(id, ts, author, content)
    local rules, loot = content:match("^(.-)\n(.*)$")
    if not rules or #rules > 700 or #loot > 700 then return end
    if ts >= (GH.bucket.guide.ts or 0) then GH.bucket.guide = { rules = rules, loot = loot, ts = ts, by = author } end
    if GH.RefreshUI then GH:RefreshUI() end
end)

GH:RegisterHistoryProvider(function()
    local guide = GH.bucket.guide or {}
    if (guide.ts or 0) > 0 then GH:SendRecord("G", "guide", guide.ts, guide.by or "Guild officer", (guide.rules or "") .. "\n" .. (guide.loot or "")) end
end)

function GH:SetGuide(rules, loot)
    if not self:CanManage() then return false, "Only the guild leader or rank 1 can edit the guide." end
    rules, loot = tostring(rules or ""):sub(1, 700), tostring(loot or ""):sub(1, 700)
    local now = time()
    local player = UnitName and UnitName("player") or "Guild officer"
    self.bucket.guide = { rules = rules, loot = loot, ts = now, by = player }
    self:SendRecord("G", "guide", now, player, rules .. "\n" .. loot)
    self:RefreshUI()
    return true, "Guild guide updated."
end

GH:RegisterCommand("guide", function(rest)
    local action, content = rest:match("^(%S+)%s*(.*)$")
    if (action or ""):lower() ~= "set" then GH.activeTab = "Guide"; GH:Open(); return end
    local rules, loot = content:match("^(.-)%s*|%s*(.*)$")
    if not rules then print("GuildDB: Use /gd guide set Rules | Loot rules."); return end
    local _, result = GH:SetGuide(rules, loot)
    print("GuildDB: " .. result)
end)

GH:RegisterTab("Guide", function()
    if not GH.bucket then return "Join a guild to view the guild guide." end
    local guide = GH.bucket.guide or {}
    if (guide.rules or "") == "" and (guide.loot or "") == "" then return "The guild guide has not been set up yet. An officer can use /gd guide set Rules | Loot rules." end
    return "Guild rules\n\n" .. GH:Display(guide.rules or "Not set") .. "\n\nLoot rules\n\n" .. GH:Display(guide.loot or "Not set")
end)

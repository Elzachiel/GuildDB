-- Officer-maintained guild rules and loot reference.
local _, GD = ...
GD:RegisterBucket("guide", function() return { rules = "", loot = "", ts = 0 } end)

GD:RegisterRecordHandler("G", function(id, ts, author, content)
    local rules, loot = content:match("^(.-)\n(.*)$")
    if not rules or #rules > 700 or #loot > 700 then return end
    if ts >= (GD.bucket.guide.ts or 0) then GD.bucket.guide = { rules = rules, loot = loot, ts = ts, by = author } end
    if GD.RefreshUI then GD:RefreshUI() end
end)

GD:RegisterHistoryProvider(function()
    local guide = GD.bucket.guide or {}
    if (guide.ts or 0) > 0 then GD:SendRecord("G", "guide", guide.ts, guide.by or "Guild officer", (guide.rules or "") .. "\n" .. (guide.loot or "")) end
end)

function GD:SetGuide(rules, loot)
    if not self:CanManage() then return false, "Only the guild leader or rank 1 can edit the guide." end
    rules, loot = tostring(rules or ""):sub(1, 700), tostring(loot or ""):sub(1, 700)
    local now = time()
    local player = UnitName and UnitName("player") or "Guild officer"
    self.bucket.guide = { rules = rules, loot = loot, ts = now, by = player }
    self:SendRecord("G", "guide", now, player, rules .. "\n" .. loot)
    self:RefreshUI()
    return true, "Guild guide updated."
end

GD:RegisterCommand("guide", function(rest)
    local action, content = rest:match("^(%S+)%s*(.*)$")
    if (action or ""):lower() ~= "set" then GD.activeTab = "Guide"; GD:Open(); return end
    local rules, loot = content:match("^(.-)%s*|%s*(.*)$")
    if not rules then print("GuildDB: Use /gd guide set Rules | Loot rules."); return end
    local _, result = GD:SetGuide(rules, loot)
    print("GuildDB: " .. result)
end)

GD:RegisterTab("Guide", function()
    if not GD.bucket then return "Join a guild to view the guild guide." end
    local guide = GD.bucket.guide or {}
    if (guide.rules or "") == "" and (guide.loot or "") == "" then return "The guild guide has not been set up yet. An officer can use /gd guide set Rules | Loot rules." end
    return "Guild rules\n\n" .. GD:Display(guide.rules or "Not set") .. "\n\nLoot rules\n\n" .. GD:Display(guide.loot or "Not set")
end)

-- Use the client's own tabard renderer so emblem, background and border match.
local _, GD = ...

function GD:RefreshGuildEmblem()
    local frame = self.frame
    if not frame or not frame.logoMark then return end
    local badge = frame.guildBadge
    if not badge then
        badge = CreateFrame("Frame", nil, frame.header)
        badge:SetSize(54, 54)
        badge:SetPoint("CENTER", frame.logoMark, "CENTER")
        badge.background = badge:CreateTexture(nil, "BACKGROUND")
        badge.background:SetAllPoints()
        badge.emblem = badge:CreateTexture(nil, "ARTWORK")
        badge.emblem:SetPoint("CENTER", 0, -1)
        badge.border = badge:CreateTexture(nil, "OVERLAY")
        badge.border:SetAllPoints()
        frame.guildBadge = badge
    end
    badge:Hide()
    frame.logoMark:Show()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    frame.logoMark:SetTexture("Interface\\AddOns\\GuildDB\\Assets\\" .. (faction == "Horde" and "HordeEmblem.png" or "AllianceEmblem.png"))
    if not self.guildName or type(SetLargeGuildTabardTextures) ~= "function" then return end

    local info
    local hasInfoAPI = type(C_GuildInfo) == "table" and type(C_GuildInfo.GetGuildTabardInfo) == "function"
    if hasInfoAPI then
        local ok, result = pcall(C_GuildInfo.GetGuildTabardInfo, "player")
        if not ok or type(result) ~= "table" or not result.emblemFileID then return end
        info = result
    end
    -- The circular background/border atlas regions used by Blizzard's guild UI.
    badge.background:SetTexture("Interface\\GuildFrame\\GuildFrame")
    badge.background:SetTexCoord(0.63183594, 0.69238281, 0.61914063, 0.74023438)
    badge.border:SetTexture("Interface\\GuildFrame\\GuildFrame")
    badge.border:SetTexCoord(0.63183594, 0.69238281, 0.74414063, 0.86523438)
    for _, texture in ipairs({ badge.background, badge.emblem, badge.border }) do
        texture:SetVertexColor(1, 1, 1, 1)
        texture:SetBlendMode("BLEND")
    end
    badge.emblem:SetTexture(nil)
    badge.emblem:SetTexCoord(0, 1, 0, 1)
    badge.emblem:SetSize(46, 53)
    local ok = pcall(SetLargeGuildTabardTextures, "player", badge.emblem, badge.background, badge.border, info)
    badge.border:Show()
    if not ok or not badge.emblem:GetTexture() then return end
    frame.logoMark:Hide()
    badge:Show()
end

for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE", "GUILDTABARD_UPDATE" }) do
    GD:RegisterEventHandler(event, function() GD:RefreshGuildEmblem() end)
end

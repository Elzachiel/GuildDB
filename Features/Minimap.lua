-- Standard broker launcher, recognized as GuildDB by minimap-button menus.
local _, GD = ...
local launcherName = "GuildDB"

function GD:RefreshMinimapButton()
    if not Minimap or not LibStub then return end
    local broker = LibStub("LibDataBroker-1.1", true)
    local icons = LibStub("LibDBIcon-1.0", true)
    if not broker or not icons then return end
    local visible = self:GetSetting("showMinimapButton") ~= false
    if type(GDB.minimap) ~= "table" then
        GDB.minimap = {minimapPos = tonumber(self:GetSetting("minimapAngle")) or 225}
    end
    GDB.minimap.hide = not visible
    if not self.minimapLauncher then
        self.minimapLauncher = broker:NewDataObject(launcherName, {
            type = "launcher", text = launcherName, label = launcherName,
            icon = "Interface/Icons/INV_Misc_GroupLooking",
            OnClick = function(_, button)
                if button == "RightButton" then
                    GD.activeTab = "Settings"
                    GD:Open()
                elseif GD.frame and GD.frame:IsShown() then
                    GD.frame:Hide()
                else
                    GD:Open()
                end
            end,
            OnTooltipShow = function(tooltip)
                tooltip:AddLine(launcherName)
                tooltip:AddLine("Left-click: Open or close GuildDB", 1, 1, 1)
                tooltip:AddLine("Right-click: Settings", 1, 1, 1)
                tooltip:AddLine("Drag: Move around the minimap", 1, 1, 1)
            end,
        })
    end
    if not icons:IsRegistered(launcherName) then
        icons:Register(launcherName, self.minimapLauncher, GDB.minimap)
    end
    self.minimapButton = icons:GetMinimapButton(launcherName)
    if self.minimapButton and not self.minimapButton.GuildDBVisibilityHook then
        self.minimapButton.GuildDBVisibilityHook = true
        self.minimapButton:HookScript("OnShow", function(button)
            if GD:GetSetting("showMinimapButton") == false then button:Hide() end
        end)
    end
    icons:Refresh(launcherName, GDB.minimap)
    if visible then icons:Show(launcherName) else icons:Hide(launcherName) end
end

GD:RegisterEventHandler("PLAYER_LOGIN", function() GD:RefreshMinimapButton() end)
GD:RegisterEventHandler("PLAYER_ENTERING_WORLD", function() GD:RefreshMinimapButton() end)

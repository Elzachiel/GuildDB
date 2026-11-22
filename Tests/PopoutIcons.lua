-- Run: npm.cmd exec --yes --package=fengari-node-cli -- fengari Tests/PopoutIcons.lua
local GD = { bucket = {}, records = {} }
function GD:RegisterRecordHandler(kind, callback) self.records[kind] = callback end
function GD:RegisterEventHandler() end
function GD:RegisterCommand() end

local fallback = 'Interface/Icons/INV_Misc_Note_01'
local available = { [fallback] = true }
local toast
local function widget()
    return setmetatable({}, { __index = function(_, key)
        if key == 'CreateTexture' or key == 'CreateFontString' then return widget end
        if key == 'SetScript' then return function(self, event, callback) self[event] = callback end end
        if key == 'SetTexture' then return function(self, path)
            self.texture = available[path] and path or nil
            return rawget(self, 'texture') ~= nil
        end end
        if key == 'Show' then return function(self) self.shown = true end end
        if key == 'Hide' then return function(self) self.shown = false end end
        if key == 'IsShown' then return function(self) return self.shown end end
        if key == 'GetHeight' then return function() return 768 end end
        if key == 'GetStringHeight' then return function() return 18 end end
        if key == 'GetFont' then return function() return 'font', 12, '' end end
        return function() end
    end })
end
UIParent = widget()
CreateFrame = function() toast = widget(); return toast end
assert(loadfile('Features/Popouts.lua'))('GuildDB', GD)

-- Exercise the real received milestone path, including the screenshot's skill.
local cases = {
    { 'Enchanting', 'Trade_Engraving' },
    { 'Herbalism', 'Spell_Nature_NatureTouch' },
    { 'Skinning', 'INV_Misc_Pelt_Wolf_01' },
    { 'First Aid', 'Spell_Holy_SealOfSacrifice' },
}
for index, case in ipairs(cases) do
    local path = 'Interface/Icons/' .. case[2]
    available[path] = true
    GD.records.MP('profession:' .. index, 1000, 'Bot Lock', 'P\n' .. case[1] .. '\n225', 'Bot Lock')
    assert(toast:IsShown() and toast.icon.texture == path, case[1] .. ' must show its profession icon')
    toast:OnMouseUp()
end

GD:ShowPopout('Test', 'Missing icon', 'Fallback test', 'Interface/Icons/Missing_Texture')
assert(toast.icon.texture == fallback, 'an unavailable texture must show a fallback')
GD:ShowPopout('Test', 'Next icon', 'Queue test', 'Interface/Icons/Trade_Engraving')
toast:OnMouseUp()
assert(toast.icon.texture == 'Interface/Icons/Trade_Engraving', 'the next toast must replace the fallback')
toast:OnMouseUp()
GD:ShowPopout('Test', 'Default icon', 'Default test')
assert(toast.icon.texture == fallback, 'a toast without an icon must retain the default')
print('Popout profession icons and texture fallback tests passed')

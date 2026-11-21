-- Run: npm.cmd exec --yes --package=fengari-node-cli -- fengari Tests/Analytics.lua
unpack = unpack or table.unpack
local GD = { guildName = 'Test Guild', activeTab = 'Analytics' }
local profiles = {
    A = { race = 'Human', spec = 'Frost', role = 'dps' },
    B = { race = 'Human', spec = 'Frost', role = 'Damage' },
    C = { role = 'Tank', race = '  ' },
}
function GD:RegisterTab(name) self.tab = name end
function GD:GetProfile(name) return profiles[name] end
function GD:Display(value) return tostring(value or ''):gsub('|', '||') end
function GD:StyleButton() end
function GD:GetAppearanceColors()
    return { accent = {0.2,0.6,1}, muted = {0.4,0.5,0.6}, text = {1,1,1}, alternate = {0.1,0.1,0.1,1} }
end
RAID_CLASS_COLORS = { MAGE = {r=0.25,g=0.78,b=0.92} }
assert(loadfile('Features/Analytics.lua'))('GuildDB', GD)
assert(GD.tab == 'Analytics')
GD.roster = {
    {name='A',class='Mage',classFile='MAGE',rank='Member',rankIndex=3,level=60,online=true},
    {name='B',class='Mage',classFile='MAGE',rank='Leader',rankIndex=0,level=51,online=false},
    {name='C',class='Warrior',rank='Member',rankIndex=3,level=10,online=true},
    {name='D',rank='Officer',rankIndex=1,level=0},
}
local data = GD:GetAnalyticsData()
assert(data.total == 4 and data.online == 2 and data.included == 4)
assert(data.charts[1].counts.Mage.count == 2)
assert(data.charts[1].counts.Mage.color == RAID_CLASS_COLORS.MAGE)
assert(data.charts[2].counts.Unknown.count == 2)
assert(data.charts[3].counts['Frost - Mage'].count == 2)
assert(data.charts[4].counts.DPS.count == 2)
assert(#data.charts == 5)
assert(data.charts[5].rows[1].label == '51 - 60' and data.charts[5].counts['1 - 10'].count == 1)
for _, chart in ipairs(data.charts) do
    local total = 0
    for _, row in ipairs(chart.rows) do total = total + row.count end
    assert(total == data.included, chart.title .. ' must account for every included character')
end
data = GD:GetAnalyticsData(true)
assert(data.included == 2 and data.total == 4 and data.charts[1].counts.Mage.count == 1)

-- UI smoke check: charts, filtering, pooled rows and empty states.
local methods = {}
local function widget()
    return setmetatable({shown=true,width=820,height=500,text='',scripts={}}, {__index=function(_,k)
        return methods[k] or (k:match('^%u') and function() end)
    end})
end
function methods:CreateFontString() return widget() end
function methods:CreateTexture() return widget() end
function methods:SetSize(w,h) self.width=w;self.height=h end
function methods:SetWidth(w) self.width=w end
function methods:GetWidth() return self.width end
function methods:SetHeight(h) self.height=h end
function methods:GetHeight() return self.height end
function methods:SetText(s) self.text=s end
function methods:SetScript(k,f) self.scripts[k]=f end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:IsShown() return self.shown end
function methods:SetShown(v) self.shown=v end
function methods:GetVerticalScroll() return rawget(self, 'scroll') or 0 end
function methods:SetVerticalScroll(v) self.scroll=v end
CreateFrame = function() return widget() end
GD.frame={detailPanel=widget(),detailScroll=widget(),detailTitle=widget(),detailMeta=widget(),detailRule=widget(),footer=widget()}
function GD:RefreshUI() self:RefreshAnalytics() end
GD:RefreshAnalytics()
local panel=GD.frame.analytics
assert(panel.shown and #panel.cards == 5 and not GD.frame.detailScroll.shown)
assert(panel.cards[1].rows[1].name.text == 'Mage')
panel.filter.scripts.OnClick()
assert(panel.onlineOnly and panel.summary.text:find('2 shown',1,true))
GD.guildName=nil
GD:RefreshAnalytics()
assert(panel.cards[1].empty.shown and not panel.cards[1].rows[1].shown)
assert(panel.summary.text:find('Join a guild',1,true))
assert(GD:GetAnalyticsData().total == 0, 'stale roster must not appear after leaving guild')
print('PASS: Analytics aggregation, unknown data, ordering, online filter, chart rendering and row reuse')

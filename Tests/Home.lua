-- Standalone mocked regression harness; run from the addon root with:
-- npm.cmd exec --yes --package=fengari-node-cli -- fengari Tests/Home.lua
-- Covers Home permissions, MOTD submission/confirmation, and recent joins.
local handlers, events, histories = {}, {}, {}
local clock, rank, player = 1000, 0, 'Leader Moon'
local roster = {{'Leader Moon','Leader',0},{'Officer Moon','Officer',1},{'Member Moon','Member',3}}
local GD = {bucket={}, tabs={}, sent={}, frame=nil, recentJoinsVersion="0.1.88", recentJoinsStart=100}
function GD:RegisterBucket(k,f) self.bucket[k]=f() end
function GD:RegisterRecordHandler(k,f) assert(not handlers[k]); handlers[k]=f end
function GD:RegisterHistoryProvider(f) histories[#histories+1]=f end
function GD:RegisterEventHandler(k,f) events[k]=f end
function GD:PlayerName() return player end
function GD:CanManage() return rank <= 1 end
function GD:SendRecord(...) self.sent[#self.sent+1]={...} end
function GD:Display(s) return tostring(s or '') end
function GD:StyleButton() end
function GD:RefreshUI() end
GetNumGuildMembers=function() return #roster end
GetGuildRosterInfo=function(i) if roster[i] then return table.unpack(roster[i]) end end
time=function() return clock end
date=function() return 'Nov 21' end
local nativeMOTD, nativeCalls = 'Native guild MOTD', 0
GetGuildRosterMOTD=function() return nativeMOTD end
CanEditMOTD=function() return true end
GuildSetMOTD=function(text) nativeMOTD=text; nativeCalls=nativeCalls+1 end
assert(loadfile('Core/Runtime.lua'))
assert(loadfile('UI/Main.lua'))
assert(loadfile('Features/Announcements.lua'))
assert(loadfile('Features/Settings.lua'))
assert(loadfile('Features/Home.lua'))('GuildDB',GD)
GD:TrackHomeMembers()
assert(next(GD.bucket.homeMembers.recent)==nil,'baseline must not announce existing members')
roster[#roster+1]={'New Moon','Member',3}
clock=1001
GD:TrackHomeMembers()
assert(GD.bucket.homeMembers.recent.newmoon.name=='New Moon')
GD:TrackHomeMembers()
assert(GD.bucket.homeMembers.recent.newmoon.ts==1001,'refresh must not reset first seen')
GD.bucket.homeRoles={ranks={[1]=false,[3]=true}} -- obsolete saved settings must have no effect
player,rank='Officer Moon',1
assert(GD:CanEditHomeMOTD())
assert(GD:SetHomeMOTD('Welcome!'))
assert(GD.bucket.homeMOTD.text=='Welcome!')
player,rank='Member Moon',3
assert(not GD:CanEditHomeMOTD())
assert(not GD:SetHomeMOTD('blocked'))
handlers.HM('motd',2002,'Officer Moon','Shared message')
assert(GD.bucket.homeMOTD.text=='Shared message')
handlers.HM('motd',2000,'Officer Moon','Older message')
assert(GD.bucket.homeMOTD.text=='Shared message')
handlers.HM('motd',2003,'Outsider','Forged message')
assert(GD.bucket.homeMOTD.text=='Shared message')
GD.sent={}; histories[1]()
assert(GD.sent[1][1]=='HM' and #GD.sent==1,'obsolete rank settings must not sync')
-- Basic UI construction, row reuse, and empty-state smoke check.
local methods={}
local function widget() return setmetatable({shown=true,width=820,height=500,text='',scripts={}}, {__index=function(t,k) return methods[k] or (k:match("^%u") and not k:match("^GuildDB") and function() end or nil) end}) end
function methods:CreateFontString() return widget() end
function methods:SetSize(w,h) self.width=w;self.height=h end
function methods:SetWidth(w) self.width=w end
function methods:GetWidth() return self.width end
function methods:SetHeight(h) self.height=h end
function methods:GetHeight() return self.height end
function methods:SetText(s) self.text=s end
function methods:GetStringHeight() return 30 end
function methods:SetScript(k,f) self.scripts[k]=f end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:SetShown(v) self.shown=v end
CreateFrame=function() return widget() end
GD.frame={detailPanel=widget(),detailScroll=widget(),detailTitle=widget(),detailMeta=widget(),detailRule=widget(),footer=widget()}
GD.bucket.announcements={{id='post1',title='Welcome',text='Guild news',by='Leader Moon',ts=1000}}
GD:RefreshHome()
assert(GD.frame.home.shown and not GD.frame.detailScroll.shown)
assert(GD.frame.home.rows[1].post.id=='post1')
GD.bucket.announcements={}
GD:RefreshHome()
assert(not GD.frame.home.rows[1].shown and GD.frame.home.empty.shown)
GD.bucket=nil
GD:RefreshHome()
assert(not GD.frame.home.edit.shown)
print('PASS: Lua syntax, MOTD permissions, sync ordering, roster baseline/new arrivals, Home UI rows and empty states')

-- Records received before the roster must wait for rank authorization.
GD.recordHandlers=handlers
GD.bucket={homeRoles={},homeMOTD={},homeMembers={}}
local savedRoster=roster
roster={}
handlers.HM('motd',3001,'Officer Moon','Deferred welcome')
assert(GD.bucket.homeMOTD.text==nil)
roster=savedRoster
events.GUILD_ROSTER_UPDATE()
assert(GD.bucket.homeMOTD.text=='Deferred welcome')
print('PASS: MOTD and permission records survive roster loading')

-- Native guild edits, API failures, and independent native changes.
player,rank='Leader Moon',0
assert(GD:SetHomeMOTD('Official guild message'))
assert(nativeMOTD=='Official guild message' and nativeCalls==2)
assert(GD:GetHomeMOTD()=='Official guild message')
local before=GD.bucket.homeMOTD
CanEditMOTD=function() return false end
assert(not GD:SetHomeMOTD('Denied'))
assert(GD.bucket.homeMOTD==before and nativeCalls==2)
CanEditMOTD=function() return true end
GuildSetMOTD=function() error('blocked') end
assert(not GD:SetHomeMOTD('Failed'))
assert(GD.bucket.homeMOTD==before)
assert(not GD:SetHomeMOTD(string.rep('x',256)))
C_GuildInfo={SetMOTD=function(text) nativeMOTD=text end}
assert(GD:SetHomeMOTD('Modern API message'))
assert(nativeMOTD=='Modern API message')
nativeMOTD='Changed through guild window'
assert(GD:GetHomeMOTD()==nativeMOTD)
assert(GD.frame.home.roles==nil,'rank controls must be absent from Home')
print('PASS: native MOTD setters, permission and API failures, length check, authoritative guild text')
-- Reproduce silent modern API, delayed roster data, and GM permission flags.
local timers, notices, requests = {}, {}, 0
C_Timer={After=function(delay,callback) timers[delay]=callback end}
C_GuildInfo={SetMOTD=function() end, GuildRoster=function() requests=requests+1 end}
GuildSetMOTD=function(text) nativeMOTD=text end
GetGuildInfo=function() return 'Guild','Guild Master',0 end
CanEditMOTD=function() return false end
nativeMOTD='Before fallback'
local sentBefore=#GD.sent
assert(GD:SetHomeMOTD('After fallback'),'GM must not be rejected by a stale permission flag')
assert(#GD.sent==sentBefore,'unconfirmed writes must not be shared')
timers[3]()
assert(nativeMOTD=='After fallback' and requests>0)
assert(#GD.sent==sentBefore+1 and GD.bucket.homeMOTD.text=='After fallback')
local originalPrint=print
print=function(text) notices[#notices+1]=text end
timers[12]()
assert(#notices==0,'confirmed fallback must not produce a warning')
-- Server event confirms the update while the roster getter is still old.
nativeMOTD='Old cached getter'
C_GuildInfo.SetMOTD=function() end
GuildSetMOTD=nil
sentBefore=#GD.sent
assert(GD:SetHomeMOTD('  Event confirmed\nmessage  '))
assert(#GD.sent==sentBefore)
events.GUILD_MOTD('GUILD_MOTD','Event confirmed message')
assert(#GD.sent==sentBefore+1)
assert(GD:GetHomeMOTD()=='Event confirmed message','event must win over a stale roster getter')
timers[3]();timers[12]()
assert(#notices==0,'delayed getter must not be mistaken for denied permissions')
-- Unconfirmed no-op retains the prior saved record and reports no rank diagnosis.
local saved=GD.bucket.homeMOTD
assert(GD:SetHomeMOTD('Never confirmed'))
timers[3]();timers[12]()
assert(GD.bucket.homeMOTD==saved)
assert(#notices==1 and notices[1]:find('not confirmed',1,true))
assert(not notices[1]:find("rank",1,true))
-- Older timeouts must not affect a newer request.
assert(GD:SetHomeMOTD('First pending'))
local obsolete=timers[12]
assert(GD:SetHomeMOTD('Second pending'))
obsolete()
events.GUILD_MOTD('GUILD_MOTD','Second pending')
assert(GD.bucket.homeMOTD.text=='Second pending' and #notices==1)
print=originalPrint
print('PASS: GM permission flags, silent API fallback, event confirmation with stale getter, failed write preservation, superseded timers')
-- Regression: current setter/getter with an absent or stale legacy getter.
local currentNative='Current guild message'
C_GuildInfo={GetMOTD=function() return currentNative end,
    SetMOTD=function(text) currentNative=text end}
GetGuildRosterMOTD=function() return 'Outdated legacy message' end
GuildSetMOTD=nil
CanEditMOTD=function() return true end
local countBefore=#GD.sent
assert(GD:SetHomeMOTD('Modern native message'))
assert(currentNative=='Modern native message')
assert(GD:GetHomeMOTD()=='Modern native message')
assert(#GD.sent==countBefore+1,'current native getter must confirm without a GUILD_MOTD event')
GetGuildRosterMOTD=nil
assert(GD:SetHomeMOTD('Modern API only'))
assert(GD:GetHomeMOTD()=='Modern API only')
GD:RefreshHome()
assert(GD.frame.home.motdText.text=='Modern API only')
-- Officers always retain MOTD access even with obsolete disabled settings.
GetGuildInfo=function() return 'Guild','Rank',rank end
GD.bucket.homeRoles={ranks={[1]=false}}
rank,player=1,'Officer Moon'
assert(GD:CanEditHomeMOTD())
assert(GD.OpenHomeRoleSettings==nil and GD.SetHomeRoles==nil)
assert(GD:SetHomeMOTD('Officer updated guild MOTD'))
assert(currentNative=='Officer updated guild MOTD')
-- A real messaging lock is reported before making a write.
C_ChatInfo={InChatMessagingLockdown=function() return true end}
assert(not GD:SetHomeMOTD('Locked'))
assert(currentNative=='Officer updated guild MOTD')
print('PASS: modern-only and stale legacy getters, immediate native confirmation/display, unconditional Officer access, messaging-lock handling')
-- Join notifications and historical guild joins must work without roster changes.
clock=clock+100000
C_ChatInfo=nil
ERR_GUILD_JOIN_S='%s has joined the guild.'
events.CHAT_MSG_SYSTEM('CHAT_MSG_SYSTEM','|Hplayer:Fresh Moon|h[Fresh Moon]|h has joined the guild.')
assert(GD.bucket.homeMembers.recent.freshmoon.joined)
ERR_GUILD_JOIN_S='Bienvenue, %s (guilde)!'
events.UI_INFO_MESSAGE('UI_INFO_MESSAGE',112,'Bienvenue, Second Moon (guilde)!')
assert(GD.bucket.homeMembers.recent.secondmoon.name=='Second Moon')
GetNumGuildEvents=function() return 3 end
GetGuildEventInfo=function(i)
    if i==1 then return 'join','Offline Moon',nil,nil,0,0,1,2 end
    if i==2 then return 'promote','Not New Moon',nil,nil,0,0,0,0 end
    return 'join','Too Old Moon',nil,nil,0,2,0,0
end
GD:ReadHomeGuildLog()
assert(GD.bucket.homeMembers.recent.offlinemoon.joined)
assert(not GD.bucket.homeMembers.recent.notnewmoon)
assert(not GD.bucket.homeMembers.recent.toooldmoon)
local recorded=GD.bucket.homeMembers.recent.offlinemoon.ts
clock=clock+60
GD:ReadHomeGuildLog()
assert(GD.bucket.homeMembers.recent.offlinemoon.ts==recorded)
print('PASS: linked/localized live joins, UI info joins, guild history, old/non-join exclusion, stable join times')
-- Exercise the real form code. The mock native setter rejects all addon calls;
-- only the secure template handler invoked by a hardware click can write.
local frames={}
function methods:CreateTexture() return widget() end
function methods:HookScript(event,callback)
    self.hooks=self.hooks or {}
    self.hooks[event]=self.hooks[event] or {}
    table.insert(self.hooks[event],callback)
end
local function fireHooks(frame,event)
    for _,callback in ipairs(frame.hooks and frame.hooks[event] or {}) do callback(frame) end
end
function methods:SetText(text)
    self.text=text
    fireHooks(self,'OnTextChanged')
end
function methods:GetText() return self.text end
function methods:SetAttribute(k,v) self.attributes=self.attributes or {};self.attributes[k]=v end
function methods:GetAttribute(k) return self.attributes and self.attributes[k] end
CreateFrame=function(kind,name,parent,template)
    local frame=widget();frame.kind=kind;frame.template=template;frames[#frames+1]=frame
    if template and template:find('SecureActionButtonTemplate',1,true) then
        frame.scripts.OnClick=function(self)
            if self:GetAttribute('type')~='macro' then return end
            local macro=self:GetAttribute('macrotext')
            assert(macro:find('/stopmacro [combat]',1,true))
            currentNative=assert(macro:match('\n/gmotd (.*)'))
            events.GUILD_MOTD('GUILD_MOTD',currentNative)
        end
    end
    return frame
end
GD.RegisterTab=function() end
assert(loadfile('UI/Main.lua'))('GuildDB',GD)
GD.RefreshUI=function() end
rank,player=0,'Leader Moon'
C_GuildInfo.GetMOTD=function() return currentNative end
local insecureWrites=0
C_GuildInfo.SetMOTD=function() insecureWrites=insecureWrites+1 end
SLASH_GUILD_MOTD1='/gmotd'
GD.ShowInputForm('MOTD',{{label='Message',value='Welcome from Home',max=255,multiline=true}},
    function(values) return GD:SetHomeMOTD(values[1],true) end,'Save',nil,
    function(values) return GD:HomeMOTDMacro(values[1]) end)
local secureSave
for _,frame in ipairs(frames) do
    if frame.template and frame.template:find('SecureActionButtonTemplate',1,true) then secureSave=frame end
end
assert(secureSave and secureSave.scripts.OnClick,'secure template handler must remain installed')
fireHooks(secureSave,'PreClick')
secureSave.scripts.OnClick(secureSave)
fireHooks(secureSave,'PostClick')
assert(currentNative=='Welcome from Home')
assert(GD.bucket.homeMOTD.text=='Welcome from Home')
assert(insecureWrites==0,'Home must submit through the native command, not the blocked Lua API')
assert(not GD:HomeMOTDMacro(string.rep('x',256)))
assert(not GD:HomeMOTDMacro('Hello\n/gquit'):find('\n/gquit',1,true),'MOTD text cannot inject extra commands')
print('PASS: real Home form preserves secure click handler, native command confirms/saves, no insecure writer, input cannot inject commands')


-- Recently joined shows live roster levels/class colors and retains known details.
RAID_CLASS_COLORS={MAGE={r=0.25,g=0.5,b=1}}
GD.roster={{name='Fresh Moon',level=42,classFile='MAGE'}}
GD:RecordHomeJoin('Fresh Moon',time(),'system')
rank,player=0,'Leader Moon'
GD:RefreshHome()
assert(GD.frame.home.joinText.text:find('|cff4080ffFresh Moon|r - Level 42',1,true))
assert(GD.frame.home.clearJoins==nil,'Clear button must be removed')
assert(GD.frame.home.joinSince==nil,'tracking label must stay hidden')
GD.roster={}
GD:RefreshHome()
assert(GD.frame.home.joinText.text:find('Level 42',1,true),'known level must survive a missing roster entry')
-- Existing saved data is filtered at the release boundary and stays filtered.
GD.bucket.homeMembers.recent.older={name='Older Moon',ts=99}
GD.bucket.homeMembers.clearedAt=clock
GD.bucket.homeMembers.ignoredLog={newmoon=true}
GD:RefreshHome()
assert(not GD.bucket.homeMembers.recent.older)
assert(GD.bucket.homeMembers.clearedAt==nil and GD.bucket.homeMembers.ignoredLog==nil)
GD:RecordHomeJoin('Before Release',99,'system')
GD:RecordHomeJoin('At Release',100,'system')
assert(not GD.bucket.homeMembers.recent.beforerelease)
assert(GD.bucket.homeMembers.recent.atrelease)
local stableStart=GD.bucket.homeMembers.trackingSince
clock=clock+100
GD:RefreshHome()
assert(GD.bucket.homeMembers.trackingSince==stableStart,'reload/refresh must not move release cutoff')
local savedGetInfo=GetGuildEventInfo
GetNumGuildEvents=function() return 2 end
GetGuildEventInfo=function(i)
    if i==1 then return 'join','Boundary Moon',nil,nil,0,0,0,0 end
    return 'join','Definite Moon',nil,nil,0,0,0,0
end
local savedClock=clock
clock=GD.recentJoinsStart+1000
GD:ReadHomeGuildLog()
assert(not GD.bucket.homeMembers.recent.boundarymoon,'ambiguous pre-release log entries must not leak into feed')
clock=GD.recentJoinsStart+4000
GD:ReadHomeGuildLog()
assert(GD.bucket.homeMembers.recent.definitemoon)
clock=savedClock
print('PASS: class colors/levels, hidden tracking label, removed Clear, persisted release cutoff, pre-release exclusion, conservative guild-log boundary')
-- Appearance changes recolor existing Home widgets without rebuilding them.
function methods:SetBackdropColor(...) self.backdropColor={...} end
function methods:SetBackdropBorderColor(...) self.borderColor={...} end
function methods:SetTextColor(...) self.textColor={...} end
local appearance={uiTheme=3,accentColor=3}
GD.GetSetting=function(_,key) return appearance[key] end
local existingHome=GD.frame.home
GD:RefreshHome()
local forest=GD:GetThemeChoices()[3]
local violet=GD:GetAccentChoices()[3]
for _,panel in ipairs({existingHome.motd,existingHome.posts,existingHome.joins}) do
    assert(panel.backdropColor[1]==forest.alternate[1] and panel.backdropColor[2]==forest.alternate[2])
    assert(panel.title.textColor[1]==violet[1] and panel.borderColor[2]==violet[2]*0.5)
end
local surface=widget()
GD:StyleSurface(surface,'window')
assert(surface.backdropColor[1]==forest.frame[1])
appearance.uiTheme,appearance.accentColor=4,6
GD:RefreshHome()
GD:StyleSurface(surface,'window')
local ember=GD:GetThemeChoices()[4]
local amber=GD:GetAccentChoices()[6]
assert(GD.frame.home==existingHome,'appearance must refresh existing widgets')
assert(existingHome.motd.backdropColor[1]==ember.alternate[1])
assert(existingHome.motd.title.textColor[1]==amber[1])
assert(existingHome.rows[1].title.textColor[1]==amber[1],'reused announcement rows must follow accent')
assert(surface.backdropColor[1]==ember.frame[1] and surface.borderColor[1]==amber[1])
GD.roster={{name='Fresh Moon',level=42,classFile='MAGE'}}
GD:RecordHomeJoin('Fresh Moon',time(),'system')
GD:RefreshHome()
assert(existingHome.joinText.text:find('|cff4080ffFresh Moon|r',1,true),'member class colors must survive appearance changes')
print('PASS: Home theme/accent refresh, reused announcement styles, dialog palette, preserved member class colors')

// Run with Node.js and the fengari/luaparse development dependencies.
const fs=require('fs'), path=require('path');
process.chdir(path.resolve(__dirname,'..'));
const dependency=name=>require(process.env.GUILDDB_TEST_ROOT ? path.join(process.env.GUILDDB_TEST_ROOT,'node_modules',name) : name);
const parse=dependency('luaparse');
const files=['Features/DKP.lua','Features/DKPSystems.lua','Features/DKPWindows.lua','Features/Settings.lua','UI/Main.lua','Core/Runtime.lua'];
const sources=Object.fromEntries(files.map(name=>{const s=fs.readFileSync(name,'utf8');parse.parse(s,{luaVersion:'5.1'});return [name,s]}));
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=dependency('fengari');
const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
const setup=`
unpack=table.unpack
local now=100000;time=function() return now end
local active, rosterReady=true,true
local roster={{'Leader One-Realm',0},{'Officer One-Realm',1},{'Member One-Realm',2}}
GetNumGuildMembers=function() return rosterReady and #roster or 0 end
GetGuildRosterInfo=function(i) local r=roster[i];return r[1],'Rank',r[2] end
GetGuildInfo=function() return active.guildName,'Rank',active.rank end
C_Timer={After=function() end}
local dkpSource,settingsSource=DKP_SOURCE,SETTINGS_SOURCE
local function client(rank,name,bucket)
 local g={rank=rank,name=name,bucket=bucket or {},guildName='Guild A',tabs={'Home','Roster'},handlers={},events={},history={},sent={},views={}}
 function g:RegisterBucket(k,fn) if not self.bucket[k] then self.bucket[k]=fn() end end
 function g:RegisterRecordHandler(k,fn) self.handlers[k]=fn end
 function g:RegisterEventHandler(k,fn) self.events[k]=self.events[k] or {};table.insert(self.events[k],fn) end
 function g:RegisterHistoryProvider(fn) table.insert(self.history,fn) end
 function g:RegisterTab(k,fn) table.insert(self.tabs,k);self.views[k]=fn end
 function g:PlayerName() return self.name end
 function g:CanManage() return self.rank==0 or self.rank==1 end
 function g:Display(v) return v end
 function g:SendRecord(...) table.insert(self.sent,{...}) end
 function g:RefreshUI() self.refreshes=(self.refreshes or 0)+1 end
 function g:RegisterCommand() end
  g.recordHandlers=g.handlers
 assert(load(TRANSPORT_SOURCE))('GuildDB',g)
 active=g;assert(load(dkpSource))('GuildDB',g);assert(load(SYSTEM_SOURCE))('GuildDB',g);assert(load(WINDOW_SOURCE))('GuildDB',g);assert(load(settingsSource))('GuildDB',g)
 return g
end
local function deliver(target,record,sender)
 active=target;local kind,id,ts,author,content=unpack(record);target.handlers[kind](id,ts,author,content,sender)
end
local function event(g,name)
 active=g;for _,fn in ipairs(g.events[name] or {}) do fn(name) end
end
`;
const tests=String.raw`
local gm,officer,member=client(0,'Leader One'),client(1,'Officer One'),client(2,'Member One')
for _,g in ipairs({gm,officer,member}) do g.bucket.dkpConfig={enabled=true} end
local function lastAward(g) for i=#g.sent,1,-1 do if g.sent[i][1]=='DKA' then return g.sent[i] end end end
active=officer;local ok,message,id=officer:AwardDKP('Member One',10,'Raid attendance');assert(ok and id)
local first=lastAward(officer);assert(first[2]==id and officer:GetDKPBalance('Member One')==10)
deliver(member,first,'Officer One');deliver(member,first,'Officer One')
assert(member:GetDKPBalance('Member One')==10 and #member:GetDKPAwardHistory()==1)
assert(member:GetDKPAwardHistory()[1].reason=='Raid attendance')
-- Concurrent positive awards merge in either order without overwriting balances.
active=gm;assert(gm:AwardDKP('Member One',5,'On time'));local second=lastAward(gm)
deliver(officer,second,'Leader One');deliver(gm,first,'Officer One');deliver(member,second,'Leader One')
for _,g in ipairs({gm,officer,member}) do active=g;assert(g:GetDKPBalance('Member One')==15) end
active=member;assert(not member:AwardDKP('Member One',10,'Unauthorized'))
deliver(member,{'DKA','forged',now,'Officer One','Member One-Realm\n100\nForged'},'Member One')
assert(member:GetDKPBalance('Member One')==15)
local modified={unpack(first)};modified[5]='Member One-Realm\n999\nChanged';deliver(member,modified,'Officer One')
assert(member:GetDKPBalance('Member One')==15)
active=officer
for _,amount in ipairs({0,-1,1.5,1000001,math.huge,'bad'}) do assert(not officer:AwardDKP('Member One',amount,'Reason')) end
assert(not officer:AwardDKP('Member One',10,''));assert(not officer:AwardDKP('Member One',10,'two\nlines'))
assert(not officer:AwardDKP('Unknown',10,'Reason'))
assert(#officer:GetDKPAwardHistory()==2 and #officer:GetDKPAwardHistory('attendance')==1)
local reloaded=client(2,'Member One',member.bucket);active=reloaded;assert(reloaded:GetDKPBalance('Member One')==15)
-- Offline catch-up is served by an authorized officer, with duplicate protection.
local newcomer=client(2,'Member One');newcomer.bucket.dkpConfig={enabled=true}
active=officer;local start=#officer.sent;officer.history[2]()
for i=start+1,#officer.sent do if officer.sent[i][1]=='DKA' then deliver(newcomer,officer.sent[i],'Officer One') end end
assert(newcomer:GetDKPBalance('Member One')==15)
-- Roster deferral is guild-bound and cannot double-count a replay.
local late=client(2,'Member One');late.bucket.dkpConfig={enabled=true};rosterReady=false;deliver(late,first,'Officer One')
assert(late:GetDKPBalance('Member One')==0);rosterReady=true;event(late,'GUILD_ROSTER_UPDATE');assert(late:GetDKPBalance('Member One')==10)
local moved=client(2,'Member One');rosterReady=false;deliver(moved,first,'Officer One');moved.bucket={dkpConfig={enabled=true}};rosterReady=true;event(moved,'GUILD_ROSTER_UPDATE');assert(moved:GetDKPBalance('Member One')==0)
-- DKP must be enabled for new awards; history can catch up before the flag arrives.
active=officer;officer:SetDKPEnabled(false);assert(not officer:AwardDKP('Member One',1,'Disabled'));officer:SetDKPEnabled(true)
local g=officer;active=g;date=function() return 'Nov 25, 2026 10:00 AM' end
GetGuildRosterInfo=function(i) local r=roster[i];return r[1],'Rank',r[2],60,'Mage','Zone',nil,nil,true,nil,'MAGE' end
local methods={}
local widget
function methods:SetScript(event,fn) self.scripts[event]=fn end
function methods:RegisterEvent(event) self.registeredEvents=self.registeredEvents or {};self.registeredEvents[event]=true end
function methods:HookScript(event,fn) self.scripts[event]=fn end
function methods:SetText(text) self.textValue=text end
function methods:GetText() return self.textValue or '' end
function methods:SetEnabled(v) self.enabled=v end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:SetShown(v) self.shown=v end
function methods:IsShown() return self.shown end
function methods:GetObjectType() return self.kind end
function methods:CreateFontString() return widget('FontString') end
function methods:CreateTexture() return widget('Texture') end
for _,method in ipairs({'GetNormalTexture','GetPushedTexture','GetHighlightTexture','GetDisabledTexture','GetFontString'}) do
 methods[method]=function(self) self.parts[method]=self.parts[method] or widget('Texture');return self.parts[method] end
end
widget=function(kind) return setmetatable({kind=kind,scripts={},parts={}}, {__index=function(_,key)
 if methods[key] then return methods[key] end
 if key:match('^[A-Z]') then return function() end end
end}) end
CreateFrame=function(kind) return widget(kind) end;UIParent=widget('Frame')

function methods:SetWidth(w) self.width=w end
function methods:SetHeight(h) self.height=h end
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:GetWidth() return self.width or 420 end
function methods:GetHeight() return self.height or 260 end
function methods:HasFocus() return false end
function methods:SetTextColor(...) self.color={...} end
function methods:SetColorTexture(...) self.color={...} end
function methods:SetTexture(texture) self.texture=texture end
function methods:SetFrameStrata(strata) self.strata=strata end
function methods:SetFrameLevel(level) self.frameLevel=level end
function methods:SetBackdropColor(...) self.backdropColor={...} end
function methods:SetVerticalScroll(v) self.scrollValue=v end
function methods:SetMinMaxValues(minimum,maximum) self.minimum,self.maximum=minimum,maximum end
function methods:SetValue(value) self.value=value end
function methods:SetStatusBarColor(...) self.barColor={...} end
function g:StyleEditBox(control) control.SetGuildDBFocusState=function() end end
function g:StyleScrollFrame() end
function g:StyleButton() end
local palette={accent={1,.6,.1,1},text={.9,.9,.9,1},muted={.5,.5,.5,1},panel={.1,.1,.1,1},alternate={.2,.2,.2,1}}
function g:GetAppearanceColors() return palette end
RAID_CLASS_COLORS={MAGE={r=.25,g=.78,b=.92},WARRIOR={r=.78,g=.61,b=.43}}

g.frame={detailPanel=widget('Frame')}
for _,key in ipairs({'detailScroll','detailTitle','detailMeta','detailRule','detailBody','footer'}) do g.frame[key]=widget('Frame') end
g.ShowInputForm=function(title,fields,callback) g.form={title=title,fields=fields,callback=callback} end
function g:ConfirmAction(title,body,callback) self.confirm=callback end
g.activeTab='DKP';g:RefreshDKP();local panel=g.frame.dkp
assert(panel.rows[1].member=='Member One-Realm' and panel.rows[1].award:IsShown())
panel.rows[1].award.scripts.OnClick();assert(g.form.fields[1].value=='Member One-Realm')
assert(g.form.callback({'Member One-Realm','10','Test award'}));assert(g:GetDKPBalance('Member One')==15)
local confirm=g.confirm;assert(confirm());assert(g:GetDKPBalance('Member One')==25)
assert(not confirm());assert(g:GetDKPBalance('Member One')==25)
g:RefreshDKP();panel.history.scripts.OnClick();assert(panel.historyMode and panel.rows[1].points:GetText():sub(1,1)=='+')
assert(not panel.rows[1].award:IsShown() and panel.rows[1].meta:GetText():find('Test award',1,true))
-- Permission and guild are checked again at final confirmation.
g:ShowDKPAwardForm('Member One');assert(g.form.callback({'Member One','10','Permission test'}));g.rank=2;assert(not g.confirm());g.rank=1
assert(g:GetDKPBalance('Member One')==25)
g:ShowDKPAwardForm('Member One');g.form.callback({'Member One','10','Guild test'});local confirmation=g.confirm
g.bucket={dkpConfig={enabled=true}};assert(not confirmation());assert(g:GetDKPBalance('Member One')==0)
-- Deductions retain signed history and sync independently of arrival order.
local debitOfficer, debitGM, debitMember = client(1,'Officer One'),client(0,'Leader One'),client(2,'Member One')
for _,c in ipairs({debitOfficer,debitGM,debitMember}) do c.bucket.dkpConfig={enabled=true} end
active=debitOfficer
assert(debitOfficer:DeductDKP('Member One',20,'Loot purchase'))
local debit=debitOfficer.sent[#debitOfficer.sent];assert(debit[1]=='DKD')
assert(debitOfficer:GetDKPBalance('Member One')==-20)
assert(debitOfficer:GetDKPAwardHistory()[1].amount==-20)
for _,amount in ipairs({0,-1,1.5,1000001,math.huge,'bad'}) do assert(not debitOfficer:DeductDKP('Member One',amount,'Invalid')) end
assert(not debitOfficer:DeductDKP('Member One',1,''))
assert(not debitOfficer:DeductDKP('Unknown',1,'Unknown'))
active=debitMember;assert(not debitMember:DeductDKP('Member One',1,'Unauthorized'))
deliver(debitMember,debit,'Member One');assert(debitMember:GetDKPBalance('Member One')==0)
active=debitGM;assert(debitGM:AwardDKP('Member One',10,'Attendance'));local credit=lastAward(debitGM)
assert(debitGM:DeductDKP('Member One',3,'Correction'));local secondDebit=debitGM.sent[#debitGM.sent]
-- Different delivery orders and duplicate replays must produce the same -13 balance.
for _,c in ipairs({debitMember,debitOfficer}) do
 deliver(c,secondDebit,'Leader One');deliver(c,credit,'Leader One');deliver(c,debit,'Officer One');deliver(c,debit,'Officer One')
 assert(c:GetDKPBalance('Member One')==-13 and #c:GetDKPAwardHistory()==3)
end
deliver(debitGM,debit,'Officer One');assert(debitGM:GetDKPBalance('Member One')==-13)
local loaded=client(2,'Member One',debitMember.bucket);active=loaded;assert(loaded:GetDKPBalance('Member One')==-13)
local catchup=client(2,'Member One');catchup.bucket.dkpConfig={enabled=true}
active=debitOfficer;local start=#debitOfficer.sent;debitOfficer.history[2]()
for i=start+1,#debitOfficer.sent do deliver(catchup,debitOfficer.sent[i],'Officer One') end
assert(catchup:GetDKPBalance('Member One')==-13 and #catchup:GetDKPAwardHistory()==3)
local deferred=client(2,'Member One');deferred.bucket.dkpConfig={enabled=true}
rosterReady=false;deliver(deferred,debit,'Officer One');rosterReady=true;event(deferred,'GUILD_ROSTER_UPDATE')
assert(deferred:GetDKPBalance('Member One')==-20)
active=debitOfficer;debitOfficer.bucket.dkpConfig.enabled=false;assert(not debitOfficer:DeductDKP('Member One',1,'Disabled'))
-- UI: Review leaves balances unchanged; confirmation deducts once and shows signed history.
active=g;g.bucket=officer.bucket -- prior test changed this bucket: start a fresh balance.
g.bucket.dkpConfig={enabled=true};g.bucket.dkpAwards={};g.bucket.dkpBalances={}
g:AwardDKP('Member One',10,'Setup');g:RefreshDKP();panel=g.frame.dkp
assert(panel.rows[1].deduct:IsShown());panel.rows[1].deduct.scripts.OnClick();assert(g.form.title=='Take DKP')
local body;function g:ConfirmAction(title,summary,callback) self.confirm=callback;body=summary end
assert(g.form.callback({'Member One','15','Loot test'}));assert(g:GetDKPBalance('Member One')==10)
assert(body:find('Balance after adjustment: -5 DKP',1,true) and body:find('negative',1,true))
local confirmation=g.confirm;assert(confirmation());assert(not confirmation());assert(g:GetDKPBalance('Member One')==-5)
g:RefreshDKP();panel.history.scripts.OnClick()
local found=false
for _,row in ipairs(panel.rows) do if row.record and row.record.reason=='Loot test' then
 assert(row.points:GetText()=='-15' and row.points.color[1]==1 and not row.deduct:IsShown());found=true
end end
assert(found)
g:ShowDKPAwardForm('Member One',true);assert(g.form.callback({'Member One','1','Permission'}));g.rank=2;assert(not g.confirm());g.rank=1
assert(g:GetDKPBalance('Member One')==-5)
g:ShowDKPAwardForm('Member One',true);assert(g.form.callback({'Member One','1','Guild'}));local stale=g.confirm
g.bucket={dkpConfig={enabled=true}};assert(not stale())
local raider=client(1,'Officer One');raider.bucket.dkpConfig={enabled=true};active=raider
local raid={'Leader One','Member One','Unknown Visitor','Member One'}
IsInRaid=function() return true end
GetNumGroupMembers=function() return #raid end
GetRaidRosterInfo=function(i) return raid[i] end
assert(#raider:GetDKPRaidMembers()==2)
assert(not raider:AwardRaidDKP({},10,'Empty'))
assert(not raider:AwardRaidDKP({'Member One','Member One'},10,'Duplicate'))
assert(not raider:AwardRaidDKP({'Leader One','Officer One'},10,'Not in raid'))
assert(not raider:AwardRaidDKP({'Leader One','Member One'},1.5,'Invalid'))
assert(not raider:AwardRaidDKP({'Leader One','Member One'},10,''))
assert(#raider:GetDKPAwardHistory()==0)
assert(raider:AwardRaidDKP({'Leader One','Member One'},10,'Raid boss'))
assert(raider:GetDKPBalance('Leader One')==10 and raider:GetDKPBalance('Member One')==10 and raider:GetDKPBalance('Officer One')==0)
assert(#raider:GetDKPAwardHistory()==2)
local remote=client(2,'Member One');remote.bucket.dkpConfig={enabled=true}
for _,record in ipairs(raider.sent) do deliver(remote,record,'Officer One');deliver(remote,record,'Officer One') end
assert(remote:GetDKPBalance('Member One')==10 and #remote:GetDKPAwardHistory()==2)
active=raider;raider.rank=2;assert(not raider:AwardRaidDKP({'Member One'},10,'Permission'));raider.rank=1
raider.bucket.dkpConfig.enabled=false;assert(not raider:AwardRaidDKP({'Member One'},10,'Disabled'));raider.bucket.dkpConfig.enabled=true
IsInRaid=function() return false end;assert(#raider:GetDKPRaidMembers()==0 and not raider:AwardRaidDKP({'Member One'},10,'Solo'))
IsInRaid=function() return true end
-- Use the real shared form to exercise checklist selection, read-only review and confirm buttons.
local created={}
CreateFrame=function(kind,name,parent)
 local object=widget(kind);object.parent=parent;object.frameName=name;created[#created+1]=object;return object
end
function methods:SetChecked(value) self.checked=value end
function methods:GetChecked() return self.checked end
function raider:StyleSurface() end; function raider:StyleCloseButton() end
function raider:StyleCheckbox() end
function raider:StyleButton() end
function raider:StyleEditBox(control) control.SetGuildDBFocusState=function() end end
function raider:StyleScrollFrame() end
assert(load(MAIN_FORM_SOURCE))('GuildDB',raider)
active=raider;raider:ShowDKPRaidAwardForm()
local function latestDialog()
 for i=#created,1,-1 do if created[i].frameName and created[i].frameName:find('GuildDBActionDialog') then return created[i] end end
end
local function clickButton(dialog,label)
 for _,object in ipairs(created) do if object.parent==dialog and object.textValue==label then object.scripts.OnClick();return end end
 error('Missing button '..label)
end
local dialog=latestDialog();assert(dialog.inputs[1]:GetText()=='10' and #dialog.inputs[3].selectedValue==2)
dialog.inputs[2]:SetText('Selected raid award')
-- Exclude the leader through a real checkbox, leaving just Member One.
for _,object in ipairs(created) do
 if object.kind=='CheckButton' and object.parent.parent.parent==dialog.inputs[3] then
  object:SetChecked(false);object.scripts.OnClick(object);break
 end
end
assert(#dialog.inputs[3].selectedValue==1 and dialog.inputs[3].selectedValue[1]=='Member One-Realm')
clickButton(dialog,'Review');assert(raider:GetDKPBalance('Member One')==10)
local review=latestDialog();assert(review~=dialog and review.title:GetText()=='Confirm Raid DKP')
assert(review.inputs[1]:GetText():find('10 DKP each to 1 members',1,true) and #review.inputs[2].selectedValue==1)
for _,object in ipairs(created) do
 if object.kind=='CheckButton' and object.parent.parent.parent==review.inputs[2] then assert(object.enabled==false) end
end
clickButton(review,'Award Raid');clickButton(review,'Award Raid');assert(raider:GetDKPBalance('Member One')==20 and raider:GetDKPBalance('Leader One')==10)
-- A selected departure invalidates the whole batch at confirmation.
raider:ShowDKPRaidAwardForm();dialog=latestDialog();dialog.inputs[2]:SetText('Departure test');clickButton(dialog,'Review');review=latestDialog()
raid={'Leader One'};clickButton(review,'Award Raid');assert(raider:GetDKPBalance('Leader One')==10 and raider:GetDKPBalance('Member One')==20)
raid={'Leader One','Member One'}
raider:ShowDKPRaidAwardForm();dialog=latestDialog();dialog.inputs[2]:SetText('Demotion');clickButton(dialog,'Review');review=latestDialog()
raider.rank=2;clickButton(review,'Award Raid');assert(raider:GetDKPBalance('Member One')==20);raider.rank=1
raider:ShowDKPRaidAwardForm();dialog=latestDialog();dialog.inputs[2]:SetText('Guild change');clickButton(dialog,'Review');review=latestDialog()
local saved=raider.bucket;raider.bucket={dkpConfig={enabled=true}};clickButton(review,'Award Raid');assert(raider:GetDKPBalance('Member One')==0);raider.bucket=saved
-- Forty-member raid, no truncation; one independent entry per recipient.
raid={}
for i=1,40 do local name='Raider '..i..'-Realm';roster[#roster+1]={name,2};raid[#raid+1]=name end
assert(#raider:GetDKPRaidMembers()==40)
assert(raider:AwardRaidDKP(raid,7,'Forty player raid'))
assert(#raider:GetDKPAwardHistory('Forty player raid')==40)
for _,name in ipairs(raid) do assert(raider:GetDKPBalance(name)==7) end
raider:ShowDKPRaidAwardForm();dialog=latestDialog();assert(#dialog.inputs[3].selectedValue==40)
local bidder=client(1,'Officer One');bidder.bucket.dkpConfig={enabled=true};active=bidder
local itemLink='|cffa335ee|Hitem:19019:0:0:0:0:0:0:0|h[Thunderfury]|h|r'
assert(bidder:SetDKPStartingBid(itemLink,25))
local bidRecord=bidder.sent[#bidder.sent];assert(bidRecord[1]=='DKB' and bidRecord[2]=='19019')
local price,entry=bidder:GetDKPStartingBid('19019');assert(price==25 and entry.label=='Thunderfury')
assert(bidder:GetDKPBalance('Member One')==0 and #bidder:GetDKPAwardHistory()==0)
for _,amount in ipairs({0,-1,1.5,1000001,math.huge,'bad'}) do assert(not bidder:SetDKPStartingBid(itemLink,amount)) end
for _,item in ipairs({'','not an item','0','2147483648','12\n34','|Hspell:19019|h[Wrong]|h','|Hitem:19019|h[Bad|Text]|h'}) do assert(not bidder:SetDKPStartingBid(item,10)) end
local viewer=client(2,'Member One');viewer.bucket.dkpConfig={enabled=true}
deliver(viewer,bidRecord,'Member One');assert(viewer:GetDKPStartingBid('19019')==nil)
deliver(viewer,bidRecord,'Officer One');deliver(viewer,bidRecord,'Officer One');assert(viewer:GetDKPStartingBid(itemLink)==25)
active=viewer;assert(not viewer:SetDKPStartingBid('19019',99))
active=bidder;assert(bidder:SetDKPStartingBid('item:19019',30));local newer=bidder.sent[#bidder.sent]
deliver(viewer,newer,'Officer One');deliver(viewer,bidRecord,'Officer One');assert(viewer:GetDKPStartingBid('19019')==30)
-- Concurrent changes with equal timestamps converge using the author's name.
local leader=client(0,'Leader One');leader.bucket.dkpConfig={enabled=true};active=leader
assert(leader:SetDKPStartingBid('19019',40));local parallel=leader.sent[#leader.sent]
deliver(viewer,parallel,'Leader One');assert(viewer:GetDKPStartingBid('19019')==30)
local fresh=client(2,'Member One');fresh.bucket.dkpConfig={enabled=true}
deliver(fresh,bidRecord,'Officer One');deliver(fresh,parallel,'Leader One');assert(fresh:GetDKPStartingBid('19019')==25)
-- Same timestamp, opposite order gives the same result.
local fresh2=client(2,'Member One');fresh2.bucket.dkpConfig={enabled=true}
deliver(fresh2,parallel,'Leader One');deliver(fresh2,bidRecord,'Officer One');assert(fresh2:GetDKPStartingBid('19019')==25)
local reload=client(2,'Member One',bidder.bucket);active=reload;assert(reload:GetDKPStartingBid('19019')==30)
local sync=client(2,'Member One');sync.bucket.dkpConfig={enabled=true};active=bidder
local start=#bidder.sent;bidder.history[2]()
for i=start+1,#bidder.sent do deliver(sync,bidder.sent[i],'Officer One') end
assert(sync:GetDKPStartingBid('19019')==30 and #sync:GetDKPAwardHistory()==0)
local late=client(2,'Member One');late.bucket.dkpConfig={enabled=true};rosterReady=false;deliver(late,newer,'Officer One')
rosterReady=true;event(late,'GUILD_ROSTER_UPDATE');assert(late:GetDKPStartingBid('19019')==30)
local moved=client(2,'Member One');rosterReady=false;deliver(moved,newer,'Officer One');moved.bucket={dkpConfig={enabled=true},dkpStartingBids={}}
rosterReady=true;event(moved,'GUILD_ROSTER_UPDATE');assert(moved:GetDKPStartingBid('19019')==nil)
active=bidder;bidder.bucket.dkpConfig.enabled=false;assert(not bidder:SetDKPStartingBid('19019',1));bidder.bucket.dkpConfig.enabled=true
-- Real starting-bid form: shift-click insertion, save, saved-item picker and edit.
local hooked
ChatEdit_InsertLink=function() end
hooksecurefunc=function(name,callback) assert(name=='ChatEdit_InsertLink');hooked=callback end
function methods:GetFrameLevel() return self.frameLevel or 100 end
function methods:GetScript(event) return self.scripts[event] end
function methods:SetFocus() self.focused=true end
function methods:HasFocus() return self.focused==true end
function bidder:StyleSurface() end
function bidder:StyleCloseButton() end
function bidder:StyleButton() end
function bidder:StyleEditBox() end
function bidder:StyleScrollFrame() end
assert(load(MAIN_FORM_SOURCE))('GuildDB',bidder)
active=bidder;bidder:ShowDKPStartingBidForm();local form=latestDialog()
assert(form.title:GetText()=='Item Starting Bid' and form.inputs[2]:GetText()=='10')
form.inputs[1].shown=true;form.inputs[1]:SetFocus();hooked(itemLink);assert(form.inputs[1]:GetText()==itemLink)
form.inputs[2]:SetText('35');clickButton(form,'Save Bid');assert(bidder:GetDKPStartingBid('19019')==35)
bidder:ShowDKPStartingBids();local picker=latestDialog();assert(picker.title:GetText()=='Starting Bids')
-- Choose the saved entry from the actual dropdown and open it.
local dropdown=picker.inputs[1];dropdown.scripts.OnClick(dropdown)
local selectedOption
for _,object in ipairs(created) do if object.textValue and object.textValue:find('19019',1,true) and object.kind=='Button' and object.scripts.OnClick then selectedOption=object end end
assert(selectedOption);selectedOption.scripts.OnClick();clickButton(picker,'Open');form=latestDialog()
assert(form.inputs[1]:GetText()=='19019' and form.inputs[1].enabled==false and form.inputs[2]:GetText()=='35')
form.inputs[2]:SetText('45');clickButton(form,'Save Bid');assert(bidder:GetDKPStartingBid('19019')==45)
bidder:ShowDKPStartingBidForm('19019');form=latestDialog();bidder.rank=2;form.inputs[2]:SetText('99');clickButton(form,'Save Bid')
assert(bidder:GetDKPStartingBid('19019')==45);bidder.rank=1
bidder:ShowDKPStartingBidForm('19019');form=latestDialog();local old=bidder.bucket;bidder.bucket={dkpConfig={enabled=true},dkpStartingBids={}}
clickButton(form,'Save Bid');assert(bidder:GetDKPStartingBid('19019')==nil);bidder.bucket=old
assert(#bidder:GetDKPAwardHistory()==0 and bidder:GetDKPBalance('Member One')==0)
-- Exact guild price schedule, using numeric slots/subclasses rather than localized names.
local rulesClient=client(1,'Officer One');rulesClient.bucket.dkpConfig={enabled=true};active=rulesClient
local slots={
 {'INVTYPE_NECK',100},{'INVTYPE_FINGER',100},{'INVTYPE_CLOAK',150},{'INVTYPE_WRIST',150},{'INVTYPE_WAIST',150},{'INVTYPE_FEET',150},{'INVTYPE_THROWN',150},
 {'INVTYPE_HEAD',200},{'INVTYPE_CHEST',200},{'INVTYPE_ROBE',200},{'INVTYPE_SHOULDER',200},{'INVTYPE_LEGS',200},{'INVTYPE_HAND',200},
 {'INVTYPE_WEAPON',250},{'INVTYPE_WEAPONMAINHAND',250},{'INVTYPE_WEAPONOFFHAND',250},{'INVTYPE_SHIELD',250},{'INVTYPE_HOLDABLE',250},
 {'INVTYPE_2HWEAPON',350},{'INVTYPE_RANGED',350},{'INVTYPE_RANGEDRIGHT',350},{'INVTYPE_TRINKET',300},
 {'INVTYPE_RANGEDRIGHT',150,2,19}, {'INVTYPE_RANGEDRIGHT',350,2,3}, {'INVTYPE_RANGEDRIGHT',350,2,18},
}
GetItemInfo=function(id)
 id=tonumber(tostring(id):match('item:(%d+)') or id)
 local info=slots[id-1000]
 if info then return 'Localized Item '..id,nil,nil,nil,nil,'Localized Class','Localized Subclass',1,info[1],nil,0,info[3] or 4,info[4] or 0 end
end
for index,info in ipairs(slots) do
 local price,rule,source=rulesClient:GetDKPStartingBid(tostring(1000+index))
 assert(price==info[2] and source=='category','Wrong price for '..info[1])
end
assert(rulesClient:GetDKPStartingBid('99999')==nil)
GetItemInfoInstant=function(id) if id==2000 then return id,'Armor','Plate','INVTYPE_CHEST',nil,4,4 end end
assert(rulesClient:GetDKPStartingBid('2000')==200)
assert(rulesClient:SetDKPStartingBid('1001',125));assert(rulesClient:GetDKPStartingBid('1001')==125)
local rewards=rulesClient:GetDKPRewardValues()
assert(rewards.starting==1000 and rewards.boss==20 and rewards.firstKillBonus==10 and rewards.onTime==10 and rewards.raidEnd==10)
rewards.starting=1;assert(rulesClient:GetDKPRewardValues().starting==1000)
-- Starting grants are additive, once per character, with atomic validation.
local grantOfficer,grantGM,grantViewer=client(1,'Officer One'),client(0,'Leader One'),client(2,'Member One')
for _,c in ipairs({grantOfficer,grantGM,grantViewer}) do c.bucket.dkpConfig={enabled=true} end
active=grantOfficer;assert(grantOfficer:AwardDKP('Member One',20,'Existing points'))
assert(not grantOfficer:GrantDKPStartingBalance({'Member One','Unknown'}));assert(grantOfficer:GetDKPBalance('Member One')==20)
assert(grantOfficer:GrantDKPStartingBalance({'Member One','Member One-Realm'}))
local grantA=grantOfficer.sent[#grantOfficer.sent];assert(grantA[2]=='dkp:start:member one-realm')
assert(grantOfficer:GetDKPBalance('Member One')==1020 and grantOfficer:HasDKPStartingGrant('Member One'))
assert(not grantOfficer:GrantDKPStartingBalance({'Member One'}))
active=grantGM;assert(grantGM:GrantDKPStartingBalance({'Member One'}));local grantB=grantGM.sent[#grantGM.sent]
-- Two officers granted concurrently: both histories converge without a second credit.
deliver(grantOfficer,grantB,'Leader One');deliver(grantGM,grantA,'Officer One')
assert(grantOfficer:GetDKPBalance('Member One')==1020 and grantGM:GetDKPBalance('Member One')==1000)
assert(grantOfficer.bucket.dkpAwards[grantA[2]].by=='Leader One-Realm' and grantGM.bucket.dkpAwards[grantA[2]].by=='Leader One-Realm')
deliver(grantViewer,grantA,'Officer One');deliver(grantViewer,grantB,'Leader One');deliver(grantViewer,grantA,'Officer One')
assert(grantViewer:GetDKPBalance('Member One')==1000 and #grantViewer:GetDKPAwardHistory()==1)
active=grantGM;assert(grantGM:DeductDKP('Member One',350,'Weapon'));assert(not grantGM:GrantDKPStartingBalance({'Member One'}));assert(grantGM:GetDKPBalance('Member One')==650)
local loaded=client(0,'Leader One',grantGM.bucket);active=loaded;assert(loaded:HasDKPStartingGrant('Member One') and not loaded:GrantDKPStartingBalance({'Member One'}))
local catchup=client(2,'Member One');catchup.bucket.dkpConfig={enabled=true};active=grantGM
local start=#grantGM.sent;grantGM.history[2]()
for i=start+1,#grantGM.sent do deliver(catchup,grantGM.sent[i],'Leader One') end
assert(catchup:GetDKPBalance('Member One')==650 and catchup:HasDKPStartingGrant('Member One'))
active=grantViewer;assert(not grantViewer:GrantDKPStartingBalance({'Leader One'}))
local forged=client(2,'Member One');forged.bucket.dkpConfig={enabled=true}
deliver(forged,grantA,'Member One');assert(forged:GetDKPBalance('Member One')==0)
for _,bad in ipairs({
 {'DKA',grantA[2],now,'Officer One','Member One-Realm\n999\nOne-time starting balance'},
 {'DKD',grantA[2],now,'Officer One','Member One-Realm\n1000\nOne-time starting balance'},
 {'DKA',grantA[2],now,'Officer One','Leader One-Realm\n1000\nOne-time starting balance'},
 {'DKA',grantA[2],now,'Officer One','Member One-Realm\n1000\nOther reason'},
}) do deliver(forged,bad,'Officer One') end
assert(forged:GetDKPBalance('Member One')==0 and #forged:GetDKPAwardHistory()==0)
active=grantOfficer;grantOfficer.bucket.dkpConfig.enabled=false;assert(not grantOfficer:GrantDKPStartingBalance({'Leader One'}));grantOfficer.bucket.dkpConfig.enabled=true
-- Exercise the real reviewed grant UI. No character is preselected.
local ui=raider;active=ui
ui.bucket.dkpAwards={};ui.bucket.dkpBalances={};ui.bucket.dkpStartingBids={};ui.bucket.dkpConfig.enabled=true
ui:ShowDKPStartingGrantForm();local form=latestDialog();assert(#form.inputs[2].selectedValue==0)
local count=0
for _,object in ipairs(created) do
 if object.kind=='CheckButton' and object.parent.parent.parent==form.inputs[2] and count<2 then
  object:SetChecked(true);object.scripts.OnClick(object);count=count+1
 end
end
assert(count==2 and #form.inputs[2].selectedValue==2)
local selected={unpack(form.inputs[2].selectedValue)}
clickButton(form,'Review');local review=latestDialog();assert(review.title:GetText()=='Confirm Starting DKP')
for _,name in ipairs(selected) do assert(ui:GetDKPBalance(name)==0) end
clickButton(review,'Grant DKP');clickButton(review,'Grant DKP')
for _,name in ipairs(selected) do assert(ui:GetDKPBalance(name)==1000) end
ui:ShowDKPStartingGrantForm();form=latestDialog()
for _,name in ipairs(form.inputs[2].selectedValue) do assert(not ui:HasDKPStartingGrant(name)) end
-- Presets prefill the agreed values and reason; guild-first is 30 TOTAL.
local simulated=client(1,'Officer One');simulated.bucket.dkpConfig={enabled=true};active=simulated
raid={'Leader One','Member One'}
simulated.ShowInputForm=function(title,fields,callback) simulated.form={title=title,fields=fields,callback=callback} end
local expected={20,30,10,10}
for index,points in ipairs(expected) do
 simulated:ShowDKPRaidRewardPicker();local picker=simulated.form
 assert(picker.callback({picker.fields[1].options[index]}))
 local award=simulated.form;assert(tonumber(award.fields[1].value)==points and award.fields[2].value~='')
 assert(award.callback({award.fields[1].value,award.fields[2].value,{'Member One-Realm'}}))
 local confirm=simulated.form;assert(confirm.callback());assert(not confirm.callback())
end
assert(simulated:GetDKPBalance('Member One')==70 and #simulated:GetDKPAwardHistory()==4)
simulated:ShowDKPRaidRewardPicker();local picker=simulated.form
assert(picker.callback({'Starting balance - 1,000 DKP once'}));assert(simulated.form.title=='Starting DKP')
-- Ordinary members can inspect rules and look up an item price without write access.
local reader=client(2,'Member One');reader.bucket.dkpConfig={enabled=true};active=reader
reader.ShowInputForm=function(title,fields,callback) reader.form={title=title,fields=fields,callback=callback} end
reader:ShowDKPStartingBids();local menu=reader.form;assert(#menu.fields[1].options==2)
assert(menu.callback({menu.fields[1].options[1]}));assert(#reader.form.fields==7)
local amounts={100,150,200,250,350,300}
for i,price in ipairs(amounts) do assert(reader.form.fields[i].value==price..' DKP' and reader.form.fields[i].readOnly) end
reader:ShowDKPPriceLookup();assert(reader.form.callback({'1023'}));assert(reader.form.fields[1].value=='150 DKP')
-- Both final permissions and guild identity are rechecked for starting grants.
active=ui;ui:ShowDKPStartingGrantForm();form=latestDialog();form.inputs[2].selectedValue={'Officer One-Realm'}
clickButton(form,'Review');review=latestDialog();ui.rank=2;clickButton(review,'Grant DKP');assert(ui:GetDKPBalance('Officer One')==0);ui.rank=1
ui:ShowDKPStartingGrantForm();form=latestDialog();form.inputs[2].selectedValue={'Officer One-Realm'};clickButton(form,'Review');review=latestDialog()
local saved=ui.bucket;ui.bucket={dkpConfig={enabled=true},dkpAwards={},dkpBalances={}};clickButton(review,'Grant DKP');assert(ui:GetDKPBalance('Officer One')==0);ui.bucket=saved
local filtered=client(1,'Officer One');filtered.bucket.dkpConfig={enabled=true};active=filtered
GetGuildRosterInfo=function(i)
 local r=roster[i];local level=i==1 and 59 or (i==2 or i==3) and 60 or 50
 return r[1],'Rank',r[2],level,i==2 and 'Warrior' or 'Mage','Zone',nil,nil,i~=2,nil,i==2 and 'WARRIOR' or 'MAGE'
end
assert(filtered:AwardDKP('Leader One',100,'Preserve hidden balance'))
assert(filtered:AwardDKP('Officer One',20,'Offline level sixty'))
local rows,total=filtered:GetDKPStandings()
assert(#rows==2 and total==2 and rows[1].name=='Officer One-Realm' and not rows[1].online)
assert(#filtered:GetDKPStandings('Leader')==0 and #filtered:GetDKPStandings('Warrior')==1)
assert(filtered:GetDKPBalance('Leader One')==100 and #filtered:GetDKPAwardHistory()==2)
GetGuildRosterInfo=function(i) local r=roster[i];return r[1],'Rank',r[2],i==1 and 60 or 59,'Mage' end
rows,total=filtered:GetDKPStandings();assert(#rows==1 and total==1 and rows[1].balance==100)
-- Full multi-client workflow.
local function systemClient(rank,name,bucket)
 local c=client(rank,name,bucket);c.bucket.dkpConfig={enabled=true}
 function c:GetAppearanceColors() return palette end
 function c:StyleButton() end;function c:StyleCheckbox() end;function c:StyleCloseButton() end;function c:StyleSurface() end
 function c:StyleEditBox(control) control.SetGuildDBFocusState=function() end end
 function c:StyleScrollFrame() end
 c.ShowInputForm=function(title,fields,callback) c.form={title=title,fields=fields,callback=callback} end
 return c
end
roster[#roster+1]={'Alt One-Realm',2};roster[#roster+1]={'Novice One-Realm',2}
GetGuildRosterInfo=function(i) local r=roster[i];return r[1],'Rank',r[2],r[1]=='Novice One-Realm' and 59 or 60,'Mage','Molten Core',nil,nil,true,nil,'MAGE' end
GetRealZoneText=function() return 'Molten Core' end
raid={'Leader One','Officer One','Member One','Alt One','Novice One'}
IsInRaid=function() return true end
local host,player,other=systemClient(1,'Officer One'),systemClient(2,'Member One'),systemClient(0,'Leader One')
active=host;assert(host:GrantDKPStartingBalance({'Leader One','Officer One','Member One'}))
local function broadcast(c,start,targets,sender)
 for i=start+1,#c.sent do local r=c.sent[i];if r[1]~='DKR' then for _,target in ipairs(targets) do deliver(target,r,sender) end end end
end
broadcast(host,0,{player,other},'Officer One')
assert(player:GetDKPBalance('Member One')==1000)
active=host;local ok,message,auctionID=host:StartDKPAuction('19019',250,10,30);assert(ok,message)
local opened=host.sent[#host.sent];broadcast(host,3,{player,other},'Officer One')
assert(host:GetDKPActiveAuction().id==auctionID and player:GetDKPActiveAuction().id==auctionID)
assert(not host:StartDKPAuction('19019',250,10,30))
assert(not host:AcceptDKPBid(auctionID,'Novice One',300,'MS'))
active=player;assert(not player:SubmitDKPBid(auctionID,1001,'MS'));assert(player:SubmitDKPBid(auctionID,250,'MS'))
local request=player.sent[#player.sent];local mark=#host.sent;deliver(host,request,'Member One');broadcast(host,mark,{player,other},'Officer One')
assert(host:GetDKPAuctionLeader(host:GetDKPAuction(auctionID)).member=='Member One-Realm')
assert(player:GetDKPAuctionLeader(player:GetDKPAuction(auctionID)).amount==250)
active=host;assert(host:AcceptDKPBid(auctionID,'Leader One',900,'OS'))
assert(host:GetDKPAuctionLeader(host:GetDKPAuction(auctionID)).spec=='MS')
assert(not host:AcceptDKPBid(auctionID,'Leader One',250,'MS'))
assert(host:AcceptDKPBid(auctionID,'Leader One',300,'MS'))
assert(host:GetDKPAuctionLeader(host:GetDKPAuction(auctionID)).member=='Leader One-Realm')
active=other;assert(not other:CloseDKPAuction(auctionID))
active=host;now=host:GetDKPAuction(auctionID).data.ends-2
assert(host:AcceptDKPBid(auctionID,'Member One',310,'MS'));assert(host:GetDKPAuction(auctionID).data.ends==now+10)
-- Out-of-order bid deltas reconstruct every accepted bidder.
local late=systemClient(2,'Member One');active=late
for i=#host.sent,1,-1 do local r=host.sent[i];if r[1]=='DKJ' then deliver(late,r,'Officer One') end end
deliver(late,opened,'Officer One');assert(late:GetDKPAuctionLeader(late:GetDKPAuction(auctionID)).amount==310)
active=host;assert(host:DeductDKP('Member One',800,'Balance changed'));assert(host:CloseDKPAuction(auctionID))
assert(not host:AwardDKPAuction(auctionID,'Member One-Realm',310))
assert(host:RemoveDKPAuctionBid(auctionID,'Member One'));assert(host:GetDKPAuctionLeader(host:GetDKPAuction(auctionID)).member=='Leader One-Realm')
assert(host:AwardDKPAuction(auctionID,'Leader One-Realm',300));assert(host:GetDKPBalance('Leader One')==700)
assert(not host:AwardDKPAuction(auctionID,'Leader One-Realm',300))
local finished=host.sent[#host.sent]
local settlement=systemClient(2,'Member One');active=settlement
deliver(settlement,finished,'Member One');assert(#settlement:GetDKPSystemRecords('DKU')==0)
deliver(settlement,finished,'Officer One');deliver(settlement,finished,'Officer One')
assert(settlement:GetDKPBalance('Leader One')==-300 and #settlement:GetDKPAwardHistory()==1)
-- History fills missing credits without duplicating the purchase.
active=host;local before=#host.sent;host.history[2]();host:SendDKPSystemsHistory();broadcast(host,before,{settlement},'Officer One')
assert(settlement:GetDKPBalance('Leader One')==700 and settlement:GetDKPBalance('Member One')==200)
active=host;assert(host:RecordDKPLoot('Member One','19019',100,'OS'));assert(host:GetDKPBalance('Member One')==100)
assert(not host:RecordDKPLoot('Member One','19019',101,'MS'))
local manual=host:GetDKPSystemRecords('DKL')[1]
assert(host:ReverseDKPRecord('loot:'..manual.id,'Wrong recipient'));assert(host:GetDKPBalance('Member One')==200)
assert(not host:ReverseDKPRecord('loot:'..manual.id,'Again'))
-- Reversal arriving before the original purchase waits for its dependency.
local reversePacket=host.sent[#host.sent];local purchasePacket
for _,r in ipairs(host.sent) do if r[1]=='DKL' then purchasePacket=r end end
local reverseClient=systemClient(2,'Member One');deliver(reverseClient,reversePacket,'Officer One');assert(reverseClient:GetDKPBalance('Member One')==0)
deliver(reverseClient,purchasePacket,'Officer One');assert(reverseClient:GetDKPBalance('Member One')==0)
active=host;assert(host:LinkDKPAlt('Alt One','Member One'))
assert(host:GetDKPBalance('Alt One')==200 and host:GetDKPAccount('Alt One')=='Member One-Realm')
assert(not host:GrantDKPStartingBalance({'Alt One'}))
assert(host:AwardDKP('Alt One',10,'Alt activity'));assert(host:GetDKPBalance('Alt One')==210 and host:GetDKPBalance('Member One')==210)
assert(not host:LinkDKPAlt('Leader One','Officer One')) -- two starting grants
-- Recorded raids award accounts once, automatic boss notifications deduplicate.
local startBalance=host:GetDKPBalance('Member One');local _,_,raidID=host:StartDKPRaid('Molten Core');assert(raidID)
assert(host:GetDKPBalance('Member One')==startBalance+10)
assert(host:RecordDKPBoss('Ragnaros'));assert(host:GetDKPBalance('Member One')==startBalance+40)
assert(not host:RecordDKPBoss('Ragnaros'))
for _,fn in ipairs(host.events.ENCOUNTER_END) do fn('ENCOUNTER_END',1,'Ragnaros',1,40,1) end
for _,fn in ipairs(host.events.BOSS_KILL) do fn('BOSS_KILL',1,'Ragnaros') end
assert(host:GetDKPBalance('Member One')==startBalance+40)
assert(host:EndDKPRaid());assert(host:GetDKPBalance('Member One')==startBalance+50)
now=now+60;assert(host:StartDKPRaid('Molten Core'));assert(host:RecordDKPBoss('Ragnaros'));assert(host:EndDKPRaid())
assert(host:GetDKPBalance('Member One')==startBalance+90)
-- Testing recordings work with only lower-level guild raiders, including every reward checkpoint.
local savedRaid, savedRaidInfo = raid, GetRaidRosterInfo
raid={'Novice One'};local noviceBefore=host:GetDKPBalance('Novice One');local remoteNoviceBefore=player:GetDKPBalance('Novice One');local testStart=#host.sent
assert(#host:GetDKPParticipants()==0 and #host:GetDKPParticipants(true)==1)
assert(host:StartDKPRaid('Lower-level testing'))
assert(host:GetDKPBalance('Novice One')==noviceBefore+10)
assert(host:RecordDKPBoss('Training Boss'));assert(host:EndDKPRaid())
assert(host:GetDKPBalance('Novice One')==noviceBefore+50)
broadcast(host,testStart,{player},'Officer One');assert(player:GetDKPBalance('Novice One')==remoteNoviceBefore+50)
active=host;assert(not host:StartDKPAuction('19019',250,10,45))
assert(#host:GetDKPStandings('Novice One')==0)
GetRaidRosterInfo=function(i) return raid[i],nil,nil,nil,nil,nil,nil,false end
assert(not host:StartDKPRaid('Offline test'))
GetRaidRosterInfo=savedRaidInfo;raid={'Not In Guild'};assert(not host:StartDKPRaid('Non-guild test'))
raid=savedRaid
-- Automatic signals award a new kill, not a wipe, using the roster present at that kill.
do
 local priorRaid,priorRaidInfo=raid,GetRaidRosterInfo
 local auto=systemClient(1,'Officer One');active=auto
 assert(not auto:HandleDKPBossKill('Ragnaros'))
 raid={'Leader One','Officer One','Member One','Alt One','Novice One'}
 assert(auto:StartDKPRaid('Automatic awards'))
 local memberBefore,altBefore=auto:GetDKPBalance('Member One'),auto:GetDKPBalance('Alt One')
 raid={'Officer One','Alt One','Novice One','Outside Guild'}
 GetRaidRosterInfo=function(i) return raid[i],nil,nil,nil,nil,nil,nil,raid[i]~='Alt One' end
 for _,fn in ipairs(auto.events.ENCOUNTER_END) do fn('ENCOUNTER_END',1,'Ragnaros',1,40,0) end
 assert(auto:GetDKPBalance('Officer One')==10)
 for _,fn in ipairs(auto.events.ENCOUNTER_END) do fn('ENCOUNTER_END',1,'Ragnaros',1,40,1) end
 assert(auto:GetDKPBalance('Officer One')==40 and auto:GetDKPBalance('Novice One')==40)
 assert(auto:GetDKPBalance('Member One')==memberBefore and auto:GetDKPBalance('Alt One')==altBefore)
 for _,fn in ipairs(auto.events.BOSS_KILL) do fn('BOSS_KILL',1,'Ragnaros') end
 assert(auto:GetDKPBalance('Officer One')==40)
 local observer=systemClient(0,'Leader One',auto.bucket);active=observer
 assert(not observer:HandleDKPBossKill('Garr') and observer:GetDKPBalance('Officer One')==40)
 active=auto;assert(auto:EndDKPRaid());now=now+1;assert(auto:StartDKPRaid('Repeat raid'))
 local before=auto:GetDKPBalance('Officer One')
 for _,fn in ipairs(auto.events.BOSS_KILL) do fn('BOSS_KILL',1,'Ragnaros') end
 assert(auto:GetDKPBalance('Officer One')==before+20)
 assert(auto:EndDKPRaid());before=auto:GetDKPBalance('Officer One')
 assert(not auto:HandleDKPBossKill('Garr') and auto:GetDKPBalance('Officer One')==before)
 raid,GetRaidRosterInfo=priorRaid,priorRaidInfo;active=host
end
-- Backup import merges atomically, preserves reversals/mappings, and is idempotent.
local exported,backup=host:ExportDKPBackup();assert(exported and backup:find('GuildDB%-DKP%-2'))
local restored=systemClient(0,'Leader One');active=restored;assert(restored:ImportDKPBackup(backup))
assert(restored:GetDKPBalance('Member One')==host:GetDKPBalance('Member One') and restored:GetDKPBalance('Alt One')==host:GetDKPBalance('Alt One'))
local balance=restored:GetDKPBalance('Member One');assert(restored:ImportDKPBackup(backup));assert(restored:GetDKPBalance('Member One')==balance)
assert(not restored:ImportDKPBackup(backup..'\nINVALID|data'));assert(restored:GetDKPBalance('Member One')==balance)
restored.guildName='Other guild';assert(not restored:ImportDKPBackup(backup));restored.guildName='Guild A'
active=player;assert(not player:ImportDKPBackup(backup));assert(not player:RecordDKPLoot('Member One','19019',1,'MS'));assert(not player:StartDKPRaid('Bad'))
-- Workspace and themed popup render through the same widget API as the real UI.
active=host;host.frame={detailPanel=widget('Frame')}
for _,name in ipairs({'detailScroll','detailTitle','detailMeta','detailRule','detailBody','footer'}) do host.frame[name]=widget('Frame') end
host.activeTab='DKP';host:RefreshDKP();local panel=host.frame.dkp
for _,section in ipairs({'Auctions','Loot','Raids','Officer','Standings'}) do
 panel.navigation[section].scripts.OnClick()
 if section=='Standings' then
  assert(panel.section==nil and not panel.workspace.shown and panel.scroll.shown)
  assert(panel.nameHeader.shown and panel.pointsHeader.shown)
 else assert(panel.section==section and panel.workspace.shown and not panel.scroll.shown) end
end
panel.navigation.Officer.scripts.OnClick();assert(panel.workspace.actions[3]:GetText()=='Backup' and panel.workspace.actions[4]:GetText()=='Restore')
panel.navigation.Standings.scripts.OnClick();assert(not panel.workspace.shown and panel.scroll.shown)
panel.section='Standings';host:RefreshDKP();assert(panel.section==nil and not panel.workspace.shown)
panel.navigation.Officer.scripts.OnClick();host.rank=2;host:RefreshDKP()
assert(panel.section==nil and not panel.workspace.shown and not panel.navigation.Officer.shown);host.rank=1
panel.navigation.Loot.scripts.OnClick();assert(not panel.raidAward.shown and panel.summary:GetText():find('purchases',1,true))
panel.workspace.scroll:SetVerticalScroll(150);panel.search:SetText('No such item');panel.search.scripts.OnTextChanged()
assert(panel.clearSearch.shown and panel.workspace.scroll.scrollValue==0 and panel.workspace.empty:GetText():find('Clear the search',1,true))
panel.clearSearch.scripts.OnClick();assert(panel.search:GetText()=='' and not panel.clearSearch.shown)
panel.navigation.Raids.scripts.OnClick();assert(panel.raidAward.shown and panel.workspace.scroll.scrollValue==0)
panel.navigation.Standings.scripts.OnClick();assert(panel.raidAward.shown and panel.scroll.shown)
local _,_,nextAuction=host:StartDKPAuction('19019',250,10,30);assert(nextAuction);host:ShowDKPAuctionPopup(nextAuction)
local function auctionPopup(id)
 for i=#created,1,-1 do local f=created[i];if f.frameName=='GuildDBDKPAuctionPopup' and f.auctionID==id then return f end end
 error('Missing auction popup')
end
local bidWindow=auctionPopup(nextAuction)
assert(bidWindow.timer.value==30 and bidWindow.timer.maximum==30 and bidWindow.quickAmount==250)
assert(bidWindow.officerControls.shown and bidWindow.officerTitle.shown and bidWindow.stop.enabled and not bidWindow.remove.enabled)
-- Reused officer UI must disappear on demotion; regular members retain read/bid views only.
host.rank=2;host:RefreshDKPAuctionPopup();host:RefreshDKP()
assert(not bidWindow.officerControls.shown and not bidWindow.officerTitle.shown)
assert(not bidWindow.stop.shown and not bidWindow.cancel.shown and not bidWindow.award.shown and not bidWindow.remove.shown)
assert(not bidWindow.stop.enabled and not bidWindow.cancel.enabled and not bidWindow.award.enabled and not bidWindow.remove.enabled)
assert(not panel.navigation.Officer.shown and not panel.raidAward.shown)
panel.navigation.Officer.scripts.OnClick();assert(panel.section~= 'Officer')
for _,view in ipairs({'Auctions','Loot','Raids'}) do
 panel.navigation[view].scripts.OnClick()
 for _,control in ipairs(panel.workspace.actions) do
  if control.shown then assert(control:GetText()=='Bid Window' or control:GetText()=='Alerts','Officer action visible to member') end
 end
end
panel.navigation.Standings.scripts.OnClick()
for _,row in ipairs(panel.rows) do if row.shown then assert(not row.award.shown and not row.deduct.shown) end end
host.rank=1;host:RefreshDKPAuctionPopup();host:RefreshDKP()
assert(bidWindow.officerControls.shown and panel.navigation.Officer.shown and panel.raidAward.shown)
assert(bidWindow.available:GetText():find('No bid placed',1,true) and not bidWindow.withdraw.enabled)
do
 local oldClock=GetTime;local clock=1000;GetTime=function() return clock end
 bidWindow.scripts.OnUpdate(bidWindow,.1);clock=clock+.25;bidWindow.scripts.OnUpdate(bidWindow,.1)
 assert(math.abs(bidWindow.timer.value-29.75)<.001,'Countdown should interpolate between whole seconds')
 GetTime=oldClock;host:RefreshDKPAuctionPopup()
 local oldWidth,oldHeight=host:GetSetting('dkpAuctionWidth'),host:GetSetting('dkpAuctionHeight')
 bidWindow:SetSize(600,700);bidWindow.grip.scripts.OnMouseUp()
 assert(host:GetSetting('dkpAuctionWidth')==600 and host:GetSetting('dkpAuctionHeight')==700)
 host:SetSetting('dkpAuctionWidth',oldWidth);host:SetSetting('dkpAuctionHeight',oldHeight)
 bidWindow:SetSize(oldWidth,oldHeight)
end
local themeBefore=palette.accent;palette.accent={.3,.8,.4,1}
host:RefreshDKPAuctionPopup();assert(bidWindow.timer.barColor[1]==.3);palette.accent=themeBefore
assert(bidWindow.quick.enabled and bidWindow.allIn.enabled and not bidWindow.minus.enabled)
bidWindow.amount:SetText('777');bidWindow.plus.scripts.OnClick();assert(bidWindow.quickAmount==260 and bidWindow.amount:GetText()=='777')
bidWindow.minus.scripts.OnClick();assert(bidWindow.quickAmount==250)
bidWindow.quick.scripts.OnClick();assert(host:GetDKPAuctionLeader(host:GetDKPAuction(nextAuction)).amount==250)
assert(bidWindow.available:GetText():find('You lead: 250',1,true) and bidWindow.quick:GetText():find('Raise to',1,true))
assert(bidWindow.withdraw.enabled)
assert(bidWindow.quickAmount==260 and bidWindow.amount:GetText()=='777' and bidWindow.bidRows[1].shown)
assert(not bidWindow.bidRows[2] or not bidWindow.bidRows[2].shown)
assert(bidWindow.bidRows[1].name:GetText():find('(You)',1,true))
assert(bidWindow.bidRows[1].name.color[1]==RAID_CLASS_COLORS.MAGE.r)
bidWindow.spec.scripts.OnClick();assert(bidWindow.specValue=='OS' and bidWindow.quickAmount==250)
assert(bidWindow.quick:GetText()=='Bid 250 DKP')
assert(host:GetDKPNextBid(nextAuction,'MS')==260 and host:GetDKPNextBid(nextAuction,'OS')==250)
bidWindow.spec.scripts.OnClick();now=now+26;host:RefreshDKPAuctionPopup()
assert(bidWindow.timer.value==4 and bidWindow.timer.barColor[1]==0.9)
bidWindow.quick.scripts.OnClick();assert(host:GetDKPAuction(nextAuction).data.ends==now+10 and bidWindow.timer.value==10)
bidWindow.allIn.scripts.OnClick()
assert(host:GetDKPAuctionLeader(host:GetDKPAuction(nextAuction)).amount==host:GetDKPAvailable('Officer One',nextAuction))
assert(not bidWindow.allIn.enabled and not bidWindow.quick.enabled)
panel.navigation.Auctions.scripts.OnClick();assert(panel.workspace.live.shown and panel.workspace.rows[1].title:GetText():find('Officer One',1,true))
assert(panel.workspace.actions[1]:GetText()=='Bid Window' and not panel.workspace.rows[1].action.shown and not panel.raidAward.shown)
for _,row in ipairs(panel.workspace.rows) do
 if row.shown then assert(not row.title:GetText():find('Bidding open',1,true),'Live auction duplicated in history') end
end
bidWindow.withdraw.scripts.OnClick();assert(not host:GetDKPAuctionLeader(host:GetDKPAuction(nextAuction)))
assert(bidWindow.emptyBids.shown and not bidWindow.bidRows[1].shown and bidWindow.quick.enabled)
assert(not bidWindow.withdraw.enabled)
bidWindow.amount:SetText('250');bidWindow.amount.scripts.OnEnterPressed(bidWindow.amount)
assert(host:GetDKPAuctionLeader(host:GetDKPAuction(nextAuction)).amount==250)
bidWindow.amount.scripts.OnEscapePressed(bidWindow.amount)
bidWindow.close.scripts.OnClick();host:RefreshDKPAuctionPopup();assert(not bidWindow.shown)
host:ShowDKPAuctionPopup(nextAuction);assert(bidWindow.shown)
now=now+11;host:TickDKPSystems();assert(host:GetDKPAuction(nextAuction).data.status=='REVIEW');assert(host:CancelDKPAuction(nextAuction))
assert(bidWindow.timer.value==0 and not bidWindow.quick.enabled and not bidWindow.allIn.enabled)
assert(bidWindow.available:GetText():find('Auction cancelled',1,true))
local closedBidCount=#host:GetDKPAuction(nextAuction).data.bids
bidWindow.amount.scripts.OnEnterPressed(bidWindow.amount);assert(#host:GetDKPAuction(nextAuction).data.bids==closedBidCount)
-- Disconnected-host recovery, offline attendance and transport capacity.
active=host;local _,_,staleID=host:StartDKPAuction('19019',250,10,10);assert(staleID)
local stalePacket=host.sent[#host.sent];deliver(other,stalePacket,'Officer One')
active=other;assert(not other:StopStaleDKPRecording(staleID,'auction'))
now=now+71;assert(other:StopStaleDKPRecording(staleID,'auction'));local stopPacket=other.sent[#other.sent]
deliver(host,stopPacket,'Leader One');assert(host:GetDKPAuctionStatus(host:GetDKPAuction(staleID))=='CANCELLED' and other:GetDKPAuctionStatus(other:GetDKPAuction(staleID))=='CANCELLED')
active=host;assert(not host:CloseDKPAuction(staleID))
assert(host:StartDKPRaid('Recovery raid'));local openRaid=host:GetDKPActiveRaid();local raidPacket=host.sent[#host.sent-1]
assert(raidPacket[1]=='DKS');deliver(other,raidPacket,'Officer One');active=other
assert(other:StopStaleDKPRecording(openRaid.id,'raid'));deliver(host,other.sent[#other.sent],'Leader One');assert(not host:GetDKPActiveRaid())
GetRaidRosterInfo=function(i) return raid[i],nil,nil,nil,nil,nil,nil,raid[i]~='Leader One' end
local participants=host:GetDKPParticipants();for _,name in ipairs(participants) do assert(name~='Leader One-Realm') end
GetRaidRosterInfo=function(i) return raid[i] end
-- Full forty-player auction packets must fit the transport's sixty 180-byte fragments.
raid={}
for i=1,40 do local name='Capacity Raider '..i..'-Realm';roster[#roster+1]={name,2};raid[#raid+1]=name end
active=host;assert(host:GrantDKPStartingBalance(raid))
local _,_,capacityAuction=host:StartDKPAuction('19019',100,1,300);assert(capacityAuction)
for i=1,40 do assert(host:AcceptDKPBid(capacityAuction,raid[i],100+i,'MS')) end
host:ShowDKPAuctionPopup(capacityAuction);local fullWindow=auctionPopup(capacityAuction)
assert(#fullWindow.bidRows==40 and fullWindow.bidRows[40].shown and fullWindow.bidRows[1].amount:GetText()=='140')
assert(fullWindow.bidContent.height==40*28 and not fullWindow.quick.enabled) -- officer is outside this raid
fullWindow.bidScroll:SetVerticalScroll(140)
assert(host:RemoveDKPAuctionBid(capacityAuction,raid[1]))
assert(fullWindow.bidRows[39].shown and not fullWindow.bidRows[40].shown and fullWindow.bidScroll.scrollValue==140)
assert(host:GetDKPNextBid(capacityAuction,'MS')==141 and host:GetDKPNextBid(capacityAuction,'OS')==100)
assert(not host:GetDKPNextBid('missing','MS') and not host:GetDKPNextBid(capacityAuction,'invalid'))
host:RefreshDKP();assert(panel.workspace.live.shown and panel.workspace.rows[39].shown)
assert(host:AcceptDKPBid(capacityAuction,raid[1],141,'MS')) -- restore forty bids for the packet capacity check
assert(host:CloseDKPAuction(capacityAuction));local snapshot=host.sent[#host.sent]
local wire=table.concat({snapshot[1],host:Encode(snapshot[2]),snapshot[3],host:Encode(snapshot[4]),host:Encode(snapshot[5])},'|')
assert(#wire<=10800,'Auction snapshot exceeds transport capacity: '..#wire)
assert(host:CancelDKPAuction(capacityAuction))
-- Alt-right-click consumes only authorized item gestures, using the same reviewed start flow.
active=host
local alt,shift,ctrl=true,false,false
assert(host:SetDKPStartingBid('19019',250))
IsAltKeyDown=function() return alt end;IsShiftKeyDown=function() return shift end;IsControlKeyDown=function() return ctrl end
do
 local secureHooks={}
 -- Emulate secure post-hooks without replacing native functions or their return values.
 hooksecurefunc=function(owner,name,callback)
  assert(type(owner)=='table' and type(owner[name])=='function')
  secureHooks[owner]=secureHooks[owner] or {};secureHooks[owner][name]=secureHooks[owner][name] or {}
  table.insert(secureHooks[owner][name],callback)
 end
 local function dispatch(owner,name,...)
  local result={owner[name](...)}
  for _,callback in ipairs(secureHooks[owner] and secureHooks[owner][name] or {}) do callback(...) end
  return unpack(result)
 end
 local nativeClicks=0
 local function nativeClick(...) nativeClicks=nativeClicks+1;return 'native',select('#',...) end
 ContainerFrameItemButton_OnClick=nativeClick;ContainerFrameItemButton_OnModifiedClick=nativeClick
 ContainerFrameItemButtonMixin={OnClick=nativeClick,OnModifiedClick=nativeClick}
 SetItemRef=nativeClick;HandleModifiedItemClick=nativeClick
 local clickedButton='RightButton';GetMouseButtonClicked=function() return clickedButton end
 local bagControl={GetID=function() return 3 end,GetParent=function() return {GetID=function() return 0 end} end}
 local currentItem='item:19019'
 GetContainerItemLink=function(bag,slot) assert(bag==0 and slot==3);return currentItem end
 GetLootSlotLink=function(slot) assert(slot==7);return 'item:19019' end
 host:InstallDKPAuctionItemClicks();host:InstallDKPAuctionItemClicks()
 assert(ContainerFrameItemButton_OnClick==nativeClick and ContainerFrameItemButtonMixin.OnClick==nativeClick)
 assert(#secureHooks[_G].ContainerFrameItemButton_OnClick==1)
 local returned,count=dispatch(_G,'ContainerFrameItemButton_OnClick',bagControl,'RightButton')
 assert(returned=='native' and count==2 and nativeClicks==1)
 assert(host.form.title=='Start DKP Auction' and host.form.fields[1].value=='19019' and host.form.fields[2].value=='250')
 assert(not host:GetDKPActiveAuction());assert(host.form.callback({'19019','250','10','45'}))
 local shortcutAuction=host:GetDKPActiveAuction();assert(shortcutAuction)
 dispatch(_G,'SetItemRef','item:19019:0:0:0','Item','RightButton');assert(auctionPopup(shortcutAuction.id).shown)
 assert(host:GetDKPActiveAuction().id==shortcutAuction.id);assert(host:CancelDKPAuction(shortcutAuction.id))
 dispatch(_G,'ContainerFrameItemButton_OnModifiedClick',bagControl,'RightButton')
 C_Container={GetContainerItemLink=GetContainerItemLink}
 dispatch(ContainerFrameItemButtonMixin,'OnModifiedClick',{GetBagID=function() return 0 end,GetID=function() return 3 end},'RightButton')
 LootButton_OnClick=nativeClick;host:InstallDKPAuctionItemClicks()
 dispatch(_G,'LootButton_OnClick',{slot=7},'RightButton');dispatch(_G,'HandleModifiedItemClick','item:19019')
 local bagNativeCalls=0
 local function liveButton()
  local native=function() bagNativeCalls=bagNativeCalls+1;return 'bag native' end
  local hooks={}
  return {GetID=function() return 3 end,GetParent=bagControl.GetParent,
   GetScript=function() return native end,SetScript=function() error('Must not replace a native bag script') end,
   HookScript=function(_,event,callback) assert(event=='OnClick');hooks[#hooks+1]=callback end,
   Click=function(self,mouse) local result=native(self,mouse);for _,callback in ipairs(hooks) do callback(self,mouse) end;return result end,
   hookCount=function() return #hooks end}
 end
 local legacy,combined=liveButton(),liveButton();local original=legacy:GetScript('OnClick')
 ContainerFrame1={HookScript=function() end};ContainerFrame1Item1=legacy
 ContainerFrameCombinedBags={EnumerateValidItems=function() return ipairs({combined}) end,HookScript=function() end}
 host:InstallDKPAuctionItemClicks();host:InstallDKPAuctionItemClicks()
 assert(legacy:GetScript('OnClick')==original and legacy.hookCount()==1)
 assert(legacy:Click('RightButton')=='bag native' and combined:Click('RightButton')=='bag native')
 -- Ordinary right-click must always reach native use for gear, food and potions, with DKP on or off.
 alt=false;local previousForm=host.form
 for _,item in ipairs({'item:19019','item:117','item:118'}) do
  currentItem=item;local before=bagNativeCalls
  assert(legacy:Click('RightButton')=='bag native' and bagNativeCalls==before+1)
  assert(dispatch(_G,'ContainerFrameItemButton_OnClick',bagControl,'RightButton')=='native' and host.form==previousForm)
 end
 host.bucket.dkpConfig.enabled=false;assert(legacy:Click('RightButton')=='bag native');host.bucket.dkpConfig.enabled=true
 alt=true;currentItem='item:19019'
 local late=liveButton();ContainerFrame1Item2=late
 local watcher
 for i=#created,1,-1 do if created[i].registeredEvents and created[i].registeredEvents.BAG_UPDATE_DELAYED then watcher=created[i];break end end
 assert(watcher);watcher.scripts.OnEvent(watcher,'ADDON_LOADED','Blizzard_ContainerUI')
 assert(late:Click('RightButton')=='bag native' and late.hookCount()==1)
 local legacyLink,modernLink=GetContainerItemLink,C_Container.GetContainerItemLink
 GetContainerItemLink=nil;C_Container.GetContainerItemLink=function() end
 ItemLocation={CreateFromBagAndSlot=function(_,bag,slot) return {bag=bag,slot=slot} end}
 C_Item={GetItemLink=function(location) assert(location.bag==0 and location.slot==3);return '|cnIQ4:|Hitem:19019:0|h[Item]|h|r' end}
 late:Click('RightButton');assert(host.form.fields[1].value=='19019')
 GetContainerItemLink=legacyLink;C_Container.GetContainerItemLink=modernLink;ItemLocation=nil;C_Item=nil
 ContainerFrame1=nil;ContainerFrame1Item1=nil;ContainerFrame1Item2=nil;ContainerFrameCombinedBags=nil
 previousForm=host.form
 clickedButton=nil;dispatch(_G,'HandleModifiedItemClick','item:19019');clickedButton='RightButton'
 dispatch(_G,'SetItemRef','item:19019','Item','LeftButton');dispatch(_G,'SetItemRef','spell:123','Spell','RightButton')
 shift=true;dispatch(_G,'SetItemRef','item:19019','Item','RightButton');shift=false
 ctrl=true;dispatch(_G,'SetItemRef','item:19019','Item','RightButton');ctrl=false
 host.rank=2;dispatch(_G,'SetItemRef','item:19019','Item','RightButton');host.rank=1
 host.bucket.dkpConfig.enabled=false;dispatch(_G,'LootButton_OnClick',{slot=7},'RightButton');host.bucket.dkpConfig.enabled=true
 assert(host.form==previousForm and not host:GetDKPActiveAuction())
 assert(ContainerFrameItemButton_OnClick==nativeClick and HandleModifiedItemClick==nativeClick)
 local oldGetTime=GetTime;GetTime=function() return 12345 end
 dispatch(_G,'SetItemRef','item:19019','Item','RightButton');local once=host.form
 dispatch(_G,'SetItemRef','item:19019','Item','RightButton');assert(host.form==once)
 GetTime=oldGetTime
end
-- Permissions and guild changes are rechecked when the reviewed auction is submitted.
assert(host:ShowDKPStartAuction('item:19019'));local startReview=host.form;host.rank=2
assert(not startReview.callback({'19019','250','10','45'}));host.rank=1
assert(host:ShowDKPStartAuction('item:19019'));startReview=host.form
local shortcutBucket=host.bucket;host.bucket={dkpConfig={enabled=true}}
assert(not startReview.callback({'19019','250','10','45'}));host.bucket=shortcutBucket
IsAltKeyDown=nil;IsShiftKeyDown=nil;IsControlKeyDown=nil
-- Import failure after staging begins preserves the original saved bucket.
local beforeBalance=restored:GetDKPBalance('Member One');local normalHandler=restored.recordHandlers.DKA
restored.recordHandlers.DKA=function() error('Injected validation/runtime failure') end
active=restored;assert(not restored:ImportDKPBackup(backup));assert(restored:GetDKPBalance('Member One')==beforeBalance)
restored.recordHandlers.DKA=normalHandler
-- Solo testing exercises real workflows against a temporary DKP bucket without a raid or level 60.
do
 local originalRaid,originalInRaid,originalRoster=raid,IsInRaid,GetGuildRosterInfo
 raid={};IsInRaid=function() return false end
 GetGuildRosterInfo=function(i)
  local name,rankName,rank,level,class,zone,note,officerNote,online,status,classFile=originalRoster(i)
  return name,rankName,rank,name=='Officer One-Realm' and 10 or level,class,zone,note,officerNote,online,status,classFile
 end
 local solo=systemClient(1,'Officer One');active=solo
 assert(solo:AwardDKP('Officer One',75,'Real guild points'));assert(solo:SetDKPStartingBid('19019',250))
 local realBucket=solo.bucket;local beforeMessages=#solo.sent
 assert(solo:ToggleDKPSoloTest());assert(solo:IsDKPSoloTesting() and solo:GetDKPBalance('Officer One')==1000)
 assert(solo.bucket==realBucket and realBucket.dkpBalances['officer one-realm']==75)
 assert(#solo:GetDKPStandings()==1 and #solo:GetDKPRaidMembers()==1)
 solo.frame={detailPanel=widget('Frame')}
 for _,name in ipairs({'detailScroll','detailTitle','detailMeta','detailRule','detailBody','footer'}) do solo.frame[name]=widget('Frame') end
 solo:RefreshDKP();local soloPanel=solo.frame.dkp
 soloPanel.navigation.Raids.scripts.OnClick()
 assert(soloPanel.title:GetText():find('SOLO TEST',1,true) and soloPanel.workspace.actions[2]:GetText()=='Exit Test')
 assert(not solo:ExportDKPBackup() and not solo:ImportDKPBackup(backup))
 assert(solo:StartDKPRaid('Solo training'));assert(solo:RecordDKPBoss('Solo Boss'));assert(solo:EndDKPRaid())
 assert(solo:GetDKPBalance('Officer One')==1050)
 local _,_,soloAuction=solo:StartDKPAuction('19019',250,10,30);assert(soloAuction)
 solo:ShowDKPAuctionPopup(soloAuction);local soloWindow=auctionPopup(soloAuction)
 assert(soloWindow.quick.enabled and soloWindow.title:GetText():find('SOLO TEST',1,true))
 soloWindow.quick.scripts.OnClick();assert(solo:GetDKPAuctionLeader(solo:GetDKPAuction(soloAuction)).amount==250)
 assert(solo:CloseDKPAuction(soloAuction));assert(solo:AwardDKPAuction(soloAuction,'Officer One-Realm',250))
 assert(solo:RecordDKPLoot('Officer One','19019',100,'OS'));assert(solo:GetDKPBalance('Officer One')==700)
 for _,provider in ipairs(solo.history) do provider() end
 assert(#solo.sent==beforeMessages and realBucket.dkpBalances['officer one-realm']==75)
 -- Real guild updates arriving during testing wait for exit and never enter test balances.
 local peer=systemClient(0,'Leader One');active=peer;assert(peer:AwardDKP('Officer One',5,'Live guild award'))
 deliver(solo,peer.sent[#peer.sent],'Leader One');assert(solo:GetDKPBalance('Officer One')==700)
 assert(realBucket.dkpBalances['officer one-realm']==75)
 active=solo;solo:ShowDKPStartAuction('item:19019');local testReview=solo.form
 solo:RefreshDKP();soloPanel.workspace.actions[2].action()
 assert(not solo:IsDKPSoloTesting() and solo:GetDKPBalance('Officer One')==80)
 assert(not soloWindow.shown and not testReview.callback({'19019','250','10','30'}))
 assert(#solo:GetDKPRaidMembers()==0 and #solo:GetDKPStandings('Officer One')==0)
 assert(not solo:GetDKPActiveAuction() and not solo:GetDKPActiveRaid())
 solo.bucket.dkpConfig.enabled=false;assert(solo:ToggleDKPSoloTest());assert(solo:IsDKPEnabled())
 assert(not realBucket.dkpConfig.enabled);assert(solo:ToggleDKPSoloTest());assert(not solo:IsDKPEnabled())
 solo.bucket.dkpConfig.enabled=true;assert(solo:ToggleDKPSoloTest())
 local reloadedSolo=systemClient(1,'Officer One',realBucket);active=reloadedSolo
 assert(not reloadedSolo:IsDKPSoloTesting() and reloadedSolo:GetDKPBalance('Officer One')==80)
 solo.bucket={};assert(not solo:IsDKPSoloTesting() and solo:GetDKPBucket()==solo.bucket)
 local ordinary=systemClient(2,'Member One');active=ordinary;assert(not ordinary:ToggleDKPSoloTest())
 raid,IsInRaid,GetGuildRosterInfo=originalRaid,originalInRaid,originalRoster
end
-- Queue, optional outbid alerts and raid summaries exercise real persisted/synchronized workflows.
do
 local oldRaid=raid;raid={};local queued=systemClient(1,'Officer One');active=queued
 assert(queued:AddDKPQueuedAuction('19019',100,10,30));assert(queued:AddDKPQueuedAuction('19019',200,20,45))
 assert(#queued.sent==0 and #queued:GetDKPAuctionQueue()==2)
 local first=queued:GetDKPAuctionQueue()[1].id
 assert(queued:ChangeDKPQueuedAuction(first,1));assert(queued:GetDKPAuctionQueue()[2].id==first)
 assert(not queued:ChangeDKPQueuedAuction(first,1));assert(not queued:StartNextDKPQueuedAuction())
 assert(#queued:GetDKPAuctionQueue()==2)
 local reload=systemClient(1,'Officer One',queued.bucket);active=reload;assert(#reload:GetDKPAuctionQueue()==2)
 assert(#systemClient(0,'Leader One',queued.bucket):GetDKPAuctionQueue()==0)
 active=queued;raid={'Officer One','Leader One','Member One'}
 assert(queued:GrantDKPStartingBalance(raid))
 local ok,_,auction=queued:StartNextDKPQueuedAuction();assert(ok and auction and #queued:GetDKPAuctionQueue()==1)
 assert(not queued:StartNextDKPQueuedAuction() and #queued:GetDKPAuctionQueue()==1)
 assert(queued:CancelDKPAuction(auction));assert(queued:StartNextDKPQueuedAuction())
 assert(#queued:GetDKPAuctionQueue()==0);assert(queued:CancelDKPAuction(queued:GetDKPActiveAuction().id))
 queued:ShowDKPStartAuction('19019',true);assert(queued.form.title=='Queue DKP Item')
 assert(queued.form.callback({'19019','100','10','30'}));assert(#queued:GetDKPAuctionQueue()==1 and not queued:GetDKPActiveAuction())
 assert(queued:ChangeDKPQueuedAuction(queued:GetDKPAuctionQueue()[1].id,'remove'))
 for i=1,40 do assert(queued:AddDKPQueuedAuction('19019',100,10,30)) end
 assert(not queued:AddDKPQueuedAuction('19019',100,10,30) and #queued:GetDKPAuctionQueue()==40)
 queued.rank=2;assert(not queued:AddDKPQueuedAuction('19019',100,10,30));assert(not queued:StartNextDKPQueuedAuction());queued.rank=1
 local originalSound,originalKit=PlaySound,SOUNDKIT;local sounds=0
 local oldSoundPref,oldFlashPref=queued:GetSetting('dkpOutbidSound'),queued:GetSetting('dkpOutbidFlash')
 PlaySound=function() sounds=sounds+1 end;SOUNDKIT={RAID_WARNING=1}
 queued:SetSetting('dkpOutbidSound',false);queued:SetSetting('dkpOutbidFlash',false)
 local _,_,bidAuction=queued:StartDKPAuction('19019',100,10,30);assert(bidAuction)
 assert(queued:AcceptDKPBid(bidAuction,'Officer One',100,'MS'));assert(queued:AcceptDKPBid(bidAuction,'Leader One',110,'MS'))
 assert(sounds==0 and not queued.dkpOutbidFlash)
 queued:SetSetting('dkpOutbidSound',true);queued:SetSetting('dkpOutbidFlash',true)
 assert(queued:AcceptDKPBid(bidAuction,'Officer One',120,'MS'));assert(queued:AcceptDKPBid(bidAuction,'Leader One',130,'MS'))
 assert(sounds==1 and queued.dkpOutbidFlash.shown);queued:TickDKPSystems();assert(sounds==1)
 queued:GetDKPBucket().dkpAuctionPopups=false
 queued:ShowDKPAuctionPopup(bidAuction);auctionPopup(bidAuction).close.scripts.OnClick()
 assert(queued:AcceptDKPBid(bidAuction,'Officer One',140,'MS'));assert(queued:AcceptDKPBid(bidAuction,'Leader One',150,'MS'));assert(sounds==2)
 queued.dkpOutbidFlash.scripts.OnUpdate(queued.dkpOutbidFlash,2.1);assert(not queued.dkpOutbidFlash.shown)
 assert(queued:AcceptDKPBid(bidAuction,'Officer One',0,'MS',true));assert(sounds==2)
 assert(queued:CancelDKPAuction(bidAuction));assert(not queued:CheckDKPOutbidAlert())
 queued:SetSetting('dkpOutbidSound',oldSoundPref);queued:SetSetting('dkpOutbidFlash',oldFlashPref);PlaySound,SOUNDKIT=originalSound,originalKit
 local summary=systemClient(1,'Officer One');active=summary;assert(summary:GrantDKPStartingBalance(raid))
 raid={'Officer One','Member One'}
 local _,_,raidID=summary:StartDKPRaid('Summary test');assert(raidID);assert(summary:RecordDKPBoss('Summary Boss'))
 assert(summary:RecordDKPLoot('Officer One','19019',100,'OS'))
 local purchase=summary:GetDKPSystemRecords('DKL')[1];assert(summary:ReverseDKPRecord('loot:'..purchase.id,'Test refund'))
 local _,_,lootAuction=summary:StartDKPAuction('19019',250,10,30);assert(lootAuction)
 assert(summary:AcceptDKPBid(lootAuction,'Member One',250,'MS'));assert(summary:CloseDKPAuction(lootAuction))
 assert(summary:AwardDKPAuction(lootAuction,'Member One-Realm',250))
 raid={'Officer One','Leader One'};assert(summary:EndDKPRaid())
 local result=summary:GetDKPRaidSummary(raidID)
 assert(result.earned==100 and #result.attendees==3 and #result.bosses==1 and result.checkpoints==3 and #result.loot==2)
 local refunds=0;for _,loot in ipairs(result.loot) do if loot.refunded then refunds=refunds+1 end end;assert(refunds==1)
 summary:ShowDKPRaidSummary(raidID);assert(summary.dkpRaidSummaryWindow.shown and summary.dkpRaidSummaryWindow.report:GetText():find('Summary Boss',1,true))
 summary.dkpRaidSummaryWindow.attendance.scripts.OnClick();assert(summary.form.title=='Raid Attendance')
 local remote=systemClient(2,'Member One');active=remote
 for _,packet in ipairs(summary.sent) do if packet[1]=='DKT' then deliver(remote,packet,'Officer One') end end
 broadcast(summary,0,{remote},'Officer One');broadcast(summary,0,{remote},'Officer One')
 local synced=remote:GetDKPRaidSummary(raidID);assert(synced.earned==100 and #synced.loot==2 and #synced.attendees==3)
 active=summary;local exported,data=summary:ExportDKPBackup();assert(exported)
 local backupClient=systemClient(0,'Leader One');active=backupClient;assert(backupClient:ImportDKPBackup(data))
 assert(#backupClient:GetDKPRaidSummary(raidID).loot==2)
 raid=oldRaid
end
print('Passed queue/alerts/summary: local queue persistence/order/capacity/permissions and safe start failures; optional sound/flash once per outbid even with popup dismissed; checkpoint earnings/attendance, linked auction/manual loot/refunds, out-of-order sync/replay and backup restore')
do
 local c=systemClient(1,'Officer One');active=c
 assert(c:GrantDKPStartingBalance({'Officer One','Member One'}))
 assert(c:AddDKPQueuedAuction('19019',100,10,30));assert(c:AddDKPQueuedAuction('19020',200,20,45))
 c:ShowDKPAuctionQueue();local w=c.dkpQueueWindow
 assert(w.shown and w.rows[1].texture.texture and not w.rows[1].up.enabled and w.rows[1].down.enabled)
 local first,second=c:GetDKPAuctionQueue()[1].id,c:GetDKPAuctionQueue()[2].id
 w.rows[2].up.scripts.OnClick();assert(c:GetDKPAuctionQueue()[1].id==second and w.rows[1].entryID==second)
 w.rows[1].down.scripts.OnClick();assert(c:GetDKPAuctionQueue()[1].id==first)
 w.rows[2].remove.scripts.OnClick();assert(#c:GetDKPAuctionQueue()==1 and not w.rows[2].shown)
 w.start.scripts.OnClick();assert(#c:GetDKPAuctionQueue()==0 and not w.start.enabled)
 assert(c:CancelDKPAuction(c:GetDKPActiveAuction().id))
 c.rank=2;w.scripts.OnUpdate(w,.5);assert(not w.shown);c.rank=1
 assert(c:RecordDKPLoot('Member One','19019',100,'MS'))
 local loot='loot:'..c:GetDKPSystemRecords('DKL')[1].id
 assert(c:GetDKPLootDelivery(loot)=='Pending');local balance=c:GetDKPBalance('Member One')
 assert(c:SetDKPLootDelivery(loot,true));local marked=c.sent[#c.sent]
 assert(c:GetDKPLootDelivery(loot)=='Delivered' and c:GetDKPBalance('Member One')==balance)
 assert(c:SetDKPLootDelivery(loot,false));local unmarked=c.sent[#c.sent]
 assert(c:GetDKPLootDelivery(loot)=='Pending');assert(c:SetDKPLootDelivery(loot,true))
 local early=systemClient(2,'Member One');deliver(early,c.sent[#c.sent],'Member One');assert(#early:GetDKPSystemRecords('DKY')==0)
 deliver(early,c.sent[#c.sent],'Officer One');assert(not early:GetDKPLootDelivery(loot))
 broadcast(c,0,{early},'Officer One');assert(early:GetDKPLootDelivery(loot)=='Delivered')
 local peer=systemClient(2,'Member One');broadcast(c,0,{peer},'Officer One')
 assert(peer:GetDKPLootDelivery(loot)=='Delivered');deliver(peer,unmarked,'Officer One');deliver(peer,marked,'Officer One')
 assert(peer:GetDKPLootDelivery(loot)=='Delivered' and peer:GetDKPBalance('Member One')==balance)
 active=peer;assert(not peer:SetDKPLootDelivery(loot,false))
 active=c;assert(c:AwardDKP('Member One',25,'Attendance'));assert(c:DeductDKP('Member One',5,'Correction'))
 assert(#c:GetDKPAwardHistory(nil,'Earned')==3 and #c:GetDKPAwardHistory(nil,'Spent')==2)
 assert(#c:GetDKPAwardHistory(nil,'Loot')==1 and #c:GetDKPAwardHistory(nil,'Corrections')==1)
 assert(#c:GetDKPAwardHistory('attendance','Earned')==1)
 assert(c:ReverseDKPRecord(loot,'Wrong winner'));assert(c:GetDKPLootDelivery(loot)=='Refunded' and not c:SetDKPLootDelivery(loot,true))
 assert(#c:GetDKPAwardHistory(nil,'Loot')==2 and #c:GetDKPAwardHistory(nil,'Corrections')==2)
 local ok,backup=c:ExportDKPBackup();assert(ok)
 local restored=systemClient(0,'Leader One');active=restored;assert(restored:ImportDKPBackup(backup))
 assert(restored:GetDKPLootDelivery(loot)=='Refunded' and restored:GetDKPSystemRecords('DKY')[1].data.delivered)
 active=c;c.activeTab='DKP';c.frame={detailPanel=widget()}
 for _,name in ipairs({'detailScroll','detailTitle','detailMeta','detailRule','detailBody','footer'}) do c.frame[name]=widget() end
 c:RefreshDKP();local panel=c.frame.dkp;panel.history.scripts.OnClick();assert(panel.historyFilter.shown)
 panel.historyFilter.scripts.OnClick();assert(c.form.callback({'Corrections'}));assert(panel.historyCategory=='Corrections')
 panel.section='Loot';panel.historyMode=false;c:RefreshDKP()
 assert(panel.workspace.rows[1].detail:GetText():find('Refunded',1,true) and not panel.workspace.rows[1].delivery.shown)
 assert(c:RecordDKPLoot('Member One','19020',50,'OS'));c:RefreshDKP()
 local deliveryRow
 for _,r in ipairs(panel.workspace.rows) do if r.shown and r.delivery.shown then deliveryRow=r end end
 assert(deliveryRow);deliveryRow.delivery.scripts.OnClick();c:RefreshDKP();assert(deliveryRow.detail:GetText():find('Delivered',1,true))
 c.rank=2;c:RefreshDKP();assert(not deliveryRow.delivery.shown);c.rank=1
 broadcast(c,0,{peer},'Officer One');active=c
 assert(c:GetDKPSyncFingerprint()==peer:GetDKPSyncFingerprint())
 c:ShowDKPSyncStatus();assert(c.dkpSyncWindow.shown)
 local check=c.dkpSyncCheck;assert(check and c.sent[#c.sent][1]=='DKSC')
 check.members['absent']={name='Absent',online=false};check.members['waiting']={name='Waiting',online=true}
 local _,initialReport=c:GetDKPSyncReport();assert(initialReport:find('Absent - Offline',1,true) and initialReport:find('Waiting - Waiting for reply',1,true))
 deliver(peer,c.sent[#c.sent],'Officer One');local ack=peer.sent[#peer.sent];assert(ack[1]=='DKSA')
 deliver(c,ack,'Member One');assert(check.members['member one-realm'].fingerprint==check.fingerprint)
 local heading,lines=c:GetDKPSyncReport();assert(lines:find('Member One-Realm - Confirmed',1,true))
 local mismatch=systemClient(2,'Member One');now=now+3;deliver(mismatch,{'DKSC',check.id,check.ts,'Officer One-Realm',check.fingerprint},'Officer One')
 deliver(c,mismatch.sent[#mismatch.sent],'Member One');assert(check.members['member one-realm'].fingerprint~=check.fingerprint)
 local previous=check.members['member one-realm'].fingerprint
 deliver(c,{'DKSA','wrong-token',now,'Member One-Realm',check.fingerprint},'Member One')
 deliver(c,ack,'Leader One');assert(check.members['member one-realm'].fingerprint==previous)
 active=c;assert(c:AwardDKP('Member One',1,'After snapshot'));heading,lines=c:GetDKPSyncReport()
 assert(heading:find('Data changed',1,true) and lines:find('Different data',1,true))
 now=now+61;deliver(c,ack,'Member One');assert(check.members['member one-realm'].fingerprint==previous)
 local _,lateReport=c:GetDKPSyncReport();assert(lateReport:find('Waiting - No response',1,true))
 assert(not peer:CheckDKPSync());active=c;c.rank=2;c.dkpSyncWindow.scripts.OnUpdate(c.dkpSyncWindow,2);assert(not c.dkpSyncWindow.shown)
end
print('Passed visible queue, loot delivery persistence/sync/permissions, history filters and controls, snapshot acknowledgements/mismatches/staleness/spoof rejection')
print('Passed recovery/capacity: stale auction and raid cancellation, offline attendee exclusion, forty live bidders and bounded transport packet, staged restore rollback')
do
 local originalInfo,originalColors,originalTooltip,originalCItem,originalInstant=GetItemInfo,ITEM_QUALITY_COLORS,GameTooltip,C_Item,GetItemInfoInstant
 local loaded=false
 ITEM_QUALITY_COLORS={[4]={r=.64,g=.21,b=.93}}
 GetItemInfo=function(id)
  if loaded and id==19019 then return 'Crystal Test Blade','|cffa335ee|Hitem:19019:0|h[Crystal Test Blade]|h|r',4,60,60,'Weapon','Sword',1,'INVTYPE_WEAPON','test-icon' end
 end
 GameTooltip=widget('Tooltip');GameTooltip.SetHyperlink=function(self,link) self.link=link end
 local previewOwner=systemClient(1,'Officer One');active=previewOwner
 assert(load(MAIN_FORM_SOURCE))('GuildDB',previewOwner)
 assert(previewOwner:ShowDKPStartAuction('item:19019'))
 local form=latestDialog();local preview=form.inputs[1].itemPreview
 assert(preview and not form.inputs[1].shown and form.inputs[1]:GetText()=='19019')
 assert(preview.name:GetText()=='Loading item...' and preview.icon.texture=='Interface/Icons/INV_Misc_QuestionMark')
 local _,_,previewAuction=previewOwner:StartDKPAuction('19019',250,10,30);assert(previewAuction)
 previewOwner:ShowDKPAuctionPopup(previewAuction);local window=auctionPopup(previewAuction)
 assert(window.strata=='FULLSCREEN_DIALOG' and window.frameLevel==20 and window.backdropColor[4]==1)
 assert(form.strata=='FULLSCREEN_DIALOG' and form:GetFrameLevel()>window:GetFrameLevel())
 assert(window.item:GetText()=='Loading item...')
 loaded=true;preview.scripts.OnUpdate(preview,.5);previewOwner:TickDKPSystems()
 assert(preview.name:GetText()=='Crystal Test Blade' and preview.rarity:GetText()=='Epic')
 assert(preview.name.color[1]==.64 and preview.icon.texture=='test-icon')
 assert(window.item:GetText()=='Crystal Test Blade' and window.item:GetFontString().color[3]==.93 and window.icon.texture=='test-icon')
 preview.scripts.OnEnter(preview);assert(GameTooltip.link:find('item:19019',1,true) and GameTooltip.shown)
 preview.scripts.OnLeave();assert(not GameTooltip.shown)
 window.iconHover.scripts.OnEnter(window.iconHover);assert(GameTooltip.link=='item:19019' and GameTooltip.shown)
 assert(previewOwner:CancelDKPAuction(previewAuction))
 -- Forever clients expose namespaced item APIs without the old globals.
 GetItemInfo=nil;GetItemInfoInstant=nil
 local modernReady,requests=false,0
 local modernLink='|cnIQ3:|Hitem:19019:0|h[Cobalt Blade]|h|r'
 ITEM_QUALITY_COLORS[3]={r=0,g=.44,b=.87}
 C_Item={GetItemInfo=function(value)
  if modernReady then return 'Cobalt Blade',modernLink,3,60,60,'Weapon','Sword',1,'INVTYPE_WEAPON','modern-icon' end
 end,GetItemInfoInstant=function() return 19019,'Weapon','Sword','INVTYPE_WEAPON','modern-icon',2,7 end,
 RequestLoadItemDataByID=function(id) assert(id==19019);requests=requests+1 end}
 assert(previewOwner:ShowDKPStartAuction(modernLink));local modernForm=latestDialog();local modernPreview=modernForm.inputs[1].itemPreview
 assert(modernPreview.name:GetText()=='Cobalt Blade' and modernPreview.icon.texture=='modern-icon')
 modernPreview.scripts.OnUpdate(modernPreview,.5);assert(requests==1)
 modernReady=true;modernPreview.scripts.OnUpdate(modernPreview,.5)
 assert(modernPreview.rarity:GetText()=='Rare' and modernPreview.name.color[3]==.87)
 assert(previewOwner:GetDKPStartingBid('19019')==250)
 modernPreview.scripts.OnEnter(modernPreview);assert(GameTooltip.link==modernLink)
 GetItemInfo,ITEM_QUALITY_COLORS,GameTooltip,C_Item,GetItemInfoInstant=originalInfo,originalColors,originalTooltip,originalCItem,originalInstant
end
print('Passed item previews: real auction setup card, hidden canonical ID, uncached-to-cached names/icons, epic rarity color/text, popup refresh and hover tooltips')
print('Passed automatic boss awards: success vs wipe, current connected guild roster, first/repeat kill amounts, duplicate events, hosting officer only and recording required; popup/form layers stay above main window')
print('Passed auction UI: quick/custom bid isolation, per-spec increments, All In/funds limits, countdown/soft close, theme updates, own/class-colored bids, forty scrollable bidders, withdrawals, host eligibility, live workspace and reopen/closed states')
print('Passed Alt-right-click auctions: bag/loot/chat item resolution, legacy/modern bag APIs, late loading/idempotent hooks, reviewed prices/start, active-auction protection, ordinary click delegation, modifiers, permissions, disabled DKP and guild rechecks')
print('Passed item-use regression: secure post-hooks preserve native function/script identities and returns, ordinary gear/food/potion right-click with DKP enabled/disabled, single auction form per gesture')
print('Passed lower-level raid testing: creation, on-time/boss/end rewards, member sync, offline/non-guild exclusion, preserved level-60 standings and auction eligibility')
print('Passed solo sandbox: level-10 officer without raid, temporary 1000 balance, raid/boss/end awards, bid/award/purchase, zero test broadcasts, deferred live guild updates, isolated real balances, disabled guild DKP, exit/reload/guild/form isolation and officer permissions')
print('Passed full DKP workflow: multi-client bids/ack, MS priority, increments, soft close, out-of-order deltas, winner balance recheck, exactly-once loot, replay/catch-up, reversal before original, main/alt balances and grant protection, raid/boss/attendance deduplication and guild-first bonus, atomic backup merge/reimport, permissions, workspace/popup and timer')
print('Passed: level-60-only standings and totals, offline level 60s, filtered name/class searches, preserved hidden balances/history, newly level-60 member visible')
print('Passed: all gear-slot prices, wand vs ranged classification/localization, uncached fallback, item overrides, 1000 starting grant with existing points, concurrent officer deduplication/history convergence, replay/reload/catch-up, invalid reserved records, real recipient review/confirmation, 20/30/10/10 presets, member price/rules lookup and permission/guild rechecks')
print('Passed: item links/IDs, starting-bid validation, persistence, guild sync, stale and simultaneous edits, officer-only writes, roster deferral/isolation, real forms/dropdown/edit, shift-click links, permission/guild rechecks, no DKP deductions or award history changes')
print('Passed: raid eligibility, deduplication, selected recipients, batch prevalidation, permissions/enabled checks, remote sync and replay, real scrollable checklist/review/confirmation, double-click protection, departures, demotion, guild changes, full 40-member awards')
print('Passed: deductions, negative balances, reason/amount validation, concurrent signed adjustments, duplicate replay, unauthorized rejection, reload/catch-up, deferred roster, UI review/result/confirmation, red signed history, permission and guild rechecks')
print('Passed: +10 award, required reason and positive whole numbers, GM/officer permissions, duplicate/conflicting replay protection, concurrent awards, persisted history/balances, officer catch-up, roster deferral, guild isolation, UI review/confirmation/history and permission rechecks')
`;
const main=sources['UI/Main.lua']; const formSource='local _,GD=...; local GOLD={1,1,1}; local CREAM={1,1,1}; local MUTED_GOLD={1,1,1}; local function setTextColor() end; local function styleRaidButton() end; '+main.slice(main.indexOf('local dialogCounter = 0'),main.indexOf('function GD:ConfirmAction')) ; const transport='local _,GD=...; '+sources['Core/Runtime.lua'].slice(sources['Core/Runtime.lua'].indexOf('function GD:Encode'),sources['Core/Runtime.lua'].indexOf('function GD:Enqueue')); const program='TRANSPORT_SOURCE='+JSON.stringify(transport)+'\nSYSTEM_SOURCE='+JSON.stringify(sources['Features/DKPSystems.lua'])+'\nWINDOW_SOURCE='+JSON.stringify(sources['Features/DKPWindows.lua'])+'\nMAIN_FORM_SOURCE='+JSON.stringify(formSource)+'\nDKP_SOURCE='+JSON.stringify(sources['Features/DKP.lua'])+'\nSETTINGS_SOURCE='+JSON.stringify(sources['Features/Settings.lua'])+'\n'+setup+tests;

if(lauxlib.luaL_dostring(L,to_luastring(program))!==lua.LUA_OK) {
 const message=to_jsstring(lua.lua_tostring(L,-1)), line=Number((message.match(/\]:(\d+):/)||[])[1]);
 if(line) console.error(program.split('\n').slice(Math.max(0,line-3),line+2).join('\n'));
 throw Error(message);
}
console.log('Lua 5.1 syntax passed for all tested modules');

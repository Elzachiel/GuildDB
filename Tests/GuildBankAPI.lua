-- Run: npm.cmd exec --yes --package=fengari-node-cli -- fengari Tests/GuildBankAPI.lua
local output, reads, queries = {}, 0, 0
local realPrint = print
print = function(message) output[#output + 1] = message end
local GD = { version = 'test', commands = {} }
function GD:RegisterCommand(name, fn) self.commands[name] = fn end
local frame = { events = {} }
function frame:RegisterEvent(event)
    if event == 'GUILDBANK_UPDATE_TABS' then error('unsupported event') end
    self.events[event] = true
end
function frame:IsEventRegistered(event) return self.events[event] end
function frame:SetScript(_, fn) self.onEvent = fn end
CreateFrame = function() return frame end
assert(loadfile('Features/GuildBank.lua'))('GuildDB', GD)
local function report(mode)
    output = {}
    GD.commands.bankapi(mode or '')
    return table.concat(output, '\n')
end
assert(report():find('Available: none', 1, true), 'missing APIs must be safe')
assert(report():find('GUILDBANK_UPDATE_TABS: unavailable', 1, true))
GetNumGuildBankTabs = function() return 2 end
GetCurrentGuildBankTab = function() return 1 end
GetGuildBankTabInfo = function() return 'Materials', 123, true end
GetGuildBankItemLink = function(_, slot)
    reads = reads + 1
    if slot == 2 then return 'item:123' end
end
GetGuildBankItemInfo = function(_, slot) return 123, slot == 2 and 5 or 0 end
QueryGuildBankTab = function(tab) assert(tab == 1); queries = queries + 1 end
local text = report()
assert(text:find('1 item links, 5 total stack count, 0 slot read failures', 1, true))
assert(queries == 0, 'report must not query the server automatically')
report('query')
assert(queries == 0, 'unknown bank access must not allow requests')
frame.onEvent(frame, 'GUILDBANKFRAME_OPENED')
report('query')
assert(queries == 1)
assert(report():find('GUILDBANKFRAME_OPENED: registered; observed 1', 1, true))
frame.onEvent(frame, 'GUILDBANKFRAME_CLOSED')
report('query')
assert(queries == 1, 'closed bank must not allow requests')
local before = reads
GetGuildBankTabInfo = function() return 'Restricted', 123, false end
report()
assert(reads == before, 'do not scan tabs without confirmed view permission')
GetGuildBankTabInfo = function() return 'Materials', 123, true end
GetGuildBankItemLink = function() error('client read failed') end
assert(report():find('98 slot read failures', 1, true), 'API errors must not break the command')
GetCurrentGuildBankTab = function() return nil end
assert(report():find('No valid selected tab', 1, true))
realPrint('PASS: missing APIs, unsupported events, tab reads, permissions, explicit queries, bank lifecycle and API errors')

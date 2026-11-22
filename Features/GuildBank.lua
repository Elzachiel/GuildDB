-- Local, read-only API diagnostics for the future GuildDB bank viewer.
local _, GD = ...
local probe, atBank
local registrations, seen = {}, {}
local apiNames = {
    "GetNumGuildBankTabs", "GetGuildBankTabInfo", "GetCurrentGuildBankTab",
    "GetGuildBankItemLink", "GetGuildBankItemInfo", "QueryGuildBankTab", "GetGuildBankMoney",
}
local events = { "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED",
    "GUILDBANKBAGSLOTS_CHANGED", "GUILDBANK_UPDATE_TABS" }

local function say(message) print("GuildDB bank API: " .. message) end

local function call(name, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then return false, "missing" end
    return pcall(fn, ...)
end

local function startProbe()
    if probe then return end
    probe = CreateFrame("Frame")
    probe:SetScript("OnEvent", function(_, event)
        seen[event] = (seen[event] or 0) + 1
        if event == "GUILDBANKFRAME_OPENED" then atBank = true end
        if event == "GUILDBANKFRAME_CLOSED" then atBank = false end
    end)
    for _, event in ipairs(events) do
        local ok = pcall(probe.RegisterEvent, probe, event)
        if ok and probe.IsEventRegistered then
            local checked, registered = pcall(probe.IsEventRegistered, probe, event)
            ok = checked and registered
        end
        registrations[event] = ok and "registered" or "unavailable"
    end
end

local function bankIsOpen()
    local manager = C_PlayerInteractionManager
    local kind = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker
    if manager and type(manager.IsInteractingWithNpcOfType) == "function" and kind then
        local ok, open = pcall(manager.IsInteractingWithNpcOfType, kind)
        if ok then return open end
    end
    if atBank ~= nil then return atBank end
    if GuildBankFrame and GuildBankFrame.IsShown then return GuildBankFrame:IsShown() end
    return nil
end

GD:RegisterCommand("bankapi", function(message)
    startProbe()
    local mode = (message or ""):lower():match("^%s*(.-)%s*$")
    if mode ~= "" and mode ~= "query" then say("Use /gd bankapi or /gd bankapi query."); return end
    say("GuildDB v" .. GD.version .. "; bank open: " .. tostring(bankIsOpen()))
    if GetBuildInfo then
        local ok, version, build, _, interface = pcall(GetBuildInfo)
        if ok then say("Client " .. tostring(version) .. ", build " .. tostring(build) .. ", interface " .. tostring(interface)) end
    end
    local available, missing = {}, {}
    for _, name in ipairs(apiNames) do
        local list = type(_G[name]) == "function" and available or missing
        list[#list + 1] = name
    end
    say("Available: " .. (#available > 0 and table.concat(available, ", ") or "none"))
    say("Missing: " .. (#missing > 0 and table.concat(missing, ", ") or "none"))
    for _, event in ipairs(events) do
        say(event .. ": " .. registrations[event] .. "; observed " .. (seen[event] or 0))
    end
    local tabsOK, tabs = call("GetNumGuildBankTabs")
    local tabOK, tab = call("GetCurrentGuildBankTab")
    say("Tab count: " .. tostring(tabs) .. "; selected tab: " .. tostring(tab))
    if not tabsOK or type(tabs) ~= "number" or tabs < 1 or tabs > 100 or
        not tabOK or type(tab) ~= "number" or tab % 1 ~= 0 or tab < 1 or tab > tabs then
        say("No valid selected tab. Open the guild bank, select a tab, then run /gd bankapi again.")
        return
    end
    if mode == "query" then
        if not bankIsOpen() then say("Open the guild bank before requesting tab data."); return end
        local ok, result = call("QueryGuildBankTab", tab)
        say("QueryGuildBankTab(" .. tab .. "): " .. (ok and "call completed; wait for data, then run /gd bankapi" or tostring(result)))
        return
    end
    local infoOK, name, _, viewable = call("GetGuildBankTabInfo", tab)
    say("Selected tab: " .. tostring(name) .. "; viewable: " .. tostring(viewable))
    if not infoOK or viewable ~= true then
        say("Tab access is not confirmed. No item scan performed.")
        return
    end
    local occupied, stacks, failures = 0, 0, 0
    for slot = 1, 98 do
        local linkOK, link = call("GetGuildBankItemLink", tab, slot)
        local itemOK, _, count = call("GetGuildBankItemInfo", tab, slot)
        if not linkOK or not itemOK then failures = failures + 1
        elseif type(link) == "string" and link ~= "" then
            occupied = occupied + 1
            if type(count) == "number" then stacks = stacks + count end
        end
    end
    say("98 slots checked: " .. occupied .. " item links, " .. stacks .. " total stack count, " .. failures .. " slot read failures.")
    say("Returned data can be cached or incomplete; zero items alone does not confirm an empty bank.")
    say("To verify updates: open/select a populated bank tab, use /gd bankapi query, wait, then /gd bankapi. Results stay local.")
end)

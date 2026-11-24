-- Retained milestone awards and officer-recorded raid clears.
local _, GD = ...
local LIMIT = 500
GD:RegisterBucket("guildAchievements", function() return {} end)
GD:RegisterBucket("guildAchievementDeletes", function() return {} end)

local function officer(name, gmOnly)
    if not GetNumGuildMembers or not GetGuildRosterInfo then return end
    local count = GetNumGuildMembers(true)
    if not count or count == 0 then return end
    local wanted = tostring(name or ""):lower()
    for index = 1, count do
        local member, _, rank = GetGuildRosterInfo(index)
        if member and member:lower() == wanted then
            rank = tonumber(rank)
            if gmOnly then return rank == 0 end
            return rank ~= nil and rank <= 1
        end
    end
    return false
end

function GD:CanDeleteGuildAchievements()
    if not self.bucket or not GetGuildInfo then return false end
    local _, _, rank = GetGuildInfo("player")
    return tonumber(rank) == 0
end

local function payload(record)
    return table.concat({ record.kind, record.value or 0, record.profession or "", record.title or "", record.details or "" }, "\n")
end

local function matchesDeletion(record, id, deletion)
    return record.id == id or (record.kind ~= "R" and record.kind == deletion.kind
        and record.by:lower() == deletion.targetAuthor:lower() and record.value == deletion.value
        and record.profession == deletion.profession)
end

local function deletePayload(record)
    return table.concat({ record.kind, record.value, record.profession, record.targetAuthor }, "\n")
end

local function applyDeletion(id, ts, author, content)
    if not GD.bucket or type(id) ~= "string" or #id == 0 or #id > 100
        or not ts or ts <= 0 or ts > time() + 60 or not officer(author, true) then return false end
    local kind, value, profession, targetAuthor = content:match("^([LPR])\n(%d+)\n([^\n]*)\n([^\n]+)$")
    value = tonumber(value)
    if not kind or #profession > 60 or #targetAuthor > 100
        or profession:find("[%c|]") or targetAuthor:find("[%c|]") then return false end
    if kind == "L" and (value < 10 or value > 60 or value % 10 ~= 0 or profession ~= "") then return false end
    if kind == "P" and ((value ~= 150 and value ~= 225 and value ~= 300) or profession == "") then return false end
    if kind == "R" and (value ~= 0 or profession ~= "") then return false end
    GD.bucket.guildAchievementDeletes = GD.bucket.guildAchievementDeletes or {}
    local previous = GD.bucket.guildAchievementDeletes[id]
    if previous and previous.ts >= ts then return false end
    local deletion = { ts = ts, by = author, kind = kind, value = value, profession = profession, targetAuthor = targetAuthor }
    GD.bucket.guildAchievementDeletes[id] = deletion
    local records = GD.bucket.guildAchievements or {}
    for index = #records, 1, -1 do
        if matchesDeletion(records[index], id, deletion) then table.remove(records, index) end
    end
    return true
end

function GD:DeleteGuildAchievement(id, deferRefresh)
    if not self.bucket then return false, "Join a guild first." end
    if not self:CanDeleteGuildAchievements() then return false, "Only the guild master can remove achievements." end
    local target
    for _, record in ipairs(self.bucket.guildAchievements or {}) do if record.id == id then target = record; break end end
    if not target then return false, "That achievement is no longer available." end
    local content = deletePayload({ kind = target.kind, value = target.value, profession = target.profession, targetAuthor = target.by })
    local ts, author = time(), self:PlayerName()
    if not applyDeletion(id, ts, author, content) then return false, "Could not remove the achievement. Check the guild roster and try again." end
    self:SendRecord("GAX", id, ts, author, content)
    if not deferRefresh and self.RefreshUI then self:RefreshUI() end
    return true, "Achievement removed and shared with the guild."
end

function GD:GetGuildAchievements(filter)
    local records, result = self.bucket and self.bucket.guildAchievements or {}, {}
    table.sort(records, function(a, b)
        if a.ts ~= b.ts then return a.ts > b.ts end
        return a.id < b.id
    end)
    while #records > LIMIT do table.remove(records) end
    for _, record in ipairs(records) do
        if not filter or filter == "All" or filter == record.kind then result[#result + 1] = record end
    end
    return result
end

function GD:RecordGuildAchievement(id, ts, author, kind, value, profession, title, details, broadcast)
    if not self.bucket or type(id) ~= "string" or #id == 0 or #id > 100
        or type(author) ~= "string" or author == "" or #author > 100 or author:find("[%c|]") then return false end
    ts, value = tonumber(ts), tonumber(value)
    if not ts or ts <= 0 or ts > time() + 60 then return false end
    profession, title, details = profession or "", title or "", details or ""
    for _, field in ipairs({ profession, title, details }) do
        if type(field) ~= "string" or field:find("[%c|]") then return false end
    end
    if #profession > 60 or #title > 100 or #details > 250 then return false end
    if kind == "L" then
        if not value or value < 10 or value > 60 or value % 10 ~= 0 or profession ~= "" or title ~= "" or details ~= "" then return false end
    elseif kind == "P" then
        if (value ~= 150 and value ~= 225 and value ~= 300) or profession == "" or title ~= "" or details ~= "" then return false end
    elseif kind == "R" then
        if value ~= 0 or profession ~= "" or title:match("^%s*$") or not officer(author) then return false end
    else return false end
    self.bucket.guildAchievements = self.bucket.guildAchievements or {}
    local records = self.bucket.guildAchievements
    local candidate = { id = id, kind = kind, by = author, value = value, profession = profession }
    for deletedId, deletion in pairs(self.bucket.guildAchievementDeletes or {}) do
        if matchesDeletion(candidate, deletedId, deletion) then return false end
    end
    for _, record in ipairs(records) do
        if record.id == id then return false end
        if kind ~= "R" and record.kind == kind and record.by:lower() == author:lower()
            and record.value == value and record.profession == profession then return false end
    end
    local record = { id = id, ts = ts, by = author, kind = kind, value = value,
        profession = profession, title = title, details = details }
    records[#records + 1] = record
    self:GetGuildAchievements()
    if broadcast then self:SendRecord("GA", id, ts, author, payload(record)) end
    if not self.importingAchievements and self.RefreshUI and self.activeTab == "Guild Achievements" then self:RefreshUI() end
    return true
end

function GD:ImportActivityAchievements()
    self.importingAchievements = true
    for _, record in ipairs(self.bucket and self.bucket.activity or {}) do
        self:RecordGuildAchievement(record.id, record.ts, record.by, record.kind, record.value, record.profession)
    end
    self.importingAchievements = nil
end

function GD:PostRaidAchievement(title, details)
    if not self.bucket then return false, "Join a guild first." end
    if not self:CanManage() then return false, "Only the guild leader or rank 1 can record raid clears." end
    local function clean(value, limit)
        return tostring(value or ""):gsub("[%c|]", " "):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, limit)
    end
    title, details = clean(title, 100), clean(details, 250)
    if title == "" then return false, "Enter the raid or boss cleared." end
    local record = self:NewRecord({})
    if not self:RecordGuildAchievement(record.id, record.ts, record.by, "R", 0, "", title, details, true) then
        return false, "The clear could not be recorded. Wait for the guild roster and try again."
    end
    return true, "Guild raid clear recorded and shared."
end

local pending = {}
local function receive(id, ts, author, content, deletion)
    if deletion then
        if not GD.bucket then return end
        if officer(author, true) == nil then
            if #pending < 100 then pending[#pending + 1] = { id, ts, author, content, deletion = true, bucket = GD.bucket } end
        elseif applyDeletion(id, ts, author, content) and GD.RefreshUI then GD:RefreshUI() end
        return
    end
    local kind, value, profession, title, details = content:match("^([LPR])\n(%d+)\n([^\n]*)\n([^\n]*)\n([^\n]*)$")
    if not kind or not GD.bucket then return end
    if kind == "R" and officer(author) == nil then
        if #pending < 100 then pending[#pending + 1] = { id, ts, author, content, bucket = GD.bucket } end
        return
    end
    GD:RecordGuildAchievement(id, ts, author, kind, value, profession, title, details)
end
GD:RegisterRecordHandler("GA", function(id, ts, author, content) receive(id, ts, author, content) end, 450)
GD:RegisterRecordHandler("GAX", function(id, ts, author, content) receive(id, ts, author, content, true) end, 200)
GD:RegisterEventHandler("GUILD_ROSTER_UPDATE", function()
    local records = pending
    pending = {}
    for _, record in ipairs(records) do
        if record.bucket == GD.bucket then receive(record[1], record[2], record[3], record[4], record.deletion) end
    end
end)
GD:RegisterHistoryProvider(function()
    GD:ImportActivityAchievements()
    for id, record in pairs(GD.bucket.guildAchievementDeletes or {}) do
        if officer(record.by, true) then GD:SendRecord("GAX", id, record.ts, record.by, deletePayload(record)) end
    end
    local records = GD:GetGuildAchievements()
    for index = math.min(#records, 100), 1, -1 do
        local record = records[index]
        GD:SendRecord("GA", record.id, record.ts, record.by, payload(record))
    end
end)

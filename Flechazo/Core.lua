-- Flechazo: pure logic (no WoW API calls) so it can be unit tested outside the game.
local _, ns = ...
ns = ns or {}

local Core = {}
ns.Core = Core

Core.PROTOCOL = 2
Core.SEP = "~"
Core.MAX_DESC_BYTES = 80
Core.PROFILE_TTL = 180            -- seconds a received profile stays valid
Core.REJECT_COOLDOWN = 24 * 3600  -- a rejected player shows up again after a day
Core.POSITION_GRID = 10           -- yards; positions are rounded before being shared

Core.DEFAULT_SETTINGS = {
    radius = 500,       -- yards
    maxLevelDiff = 0,   -- 0 = no limit
    discoverable = true,
}

Core.RADIUS_STEPS = { 100, 250, 500, 1000, 2000, 5000 }

-- Preset front-facing photos: the two race portraits the game ships (raceicon128-<race>-<variant>)
-- or the class icon. Only this one-letter code travels over the network.
Core.PORTRAITS = { "m", "f", "c" }
local PORTRAIT_VARIANT = { m = "male", f = "female" }

-- clientFileString from C_CreatureInfo.GetRaceInfo -> atlas race slug, where they differ.
local RACE_SLUGS = {
    scourge = "undead",
    highmountaintauren = "highmountain",
    lightforgeddraenei = "lightforged",
    zandalaritroll = "zandalari",
    earthendwarf = "earthen",
}
Core.LEVEL_DIFF_STEPS = { 0, 3, 5, 10, 20 }

local function copyDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then dst[k] = v end
    end
end

function Core.EnsureDB(db)
    db = type(db) == "table" and db or {}
    db.version = db.version or 1
    db.description = type(db.description) == "string" and db.description or ""
    if not Core.IsPortrait(db.portrait) then db.portrait = nil end
    db.settings = type(db.settings) == "table" and db.settings or {}
    copyDefaults(db.settings, Core.DEFAULT_SETTINGS)
    for _, key in ipairs({ "liked", "likedBy", "rejected", "matches", "blocked" }) do
        if type(db[key]) ~= "table" then db[key] = {} end
    end
    return db
end

function Core.IsPortrait(code)
    for _, c in ipairs(Core.PORTRAITS) do
        if c == code then return true end
    end
    return false
end

-- Returns the atlas name for a portrait code, given the race clientFileString and the class file.
function Core.PortraitAtlas(code, raceFile, classFile)
    local variant = PORTRAIT_VARIANT[code]
    if variant and raceFile then
        local slug = raceFile:lower()
        return "raceicon128-" .. (RACE_SLUGS[slug] or slug) .. "-" .. variant
    end
    return "classicon-" .. (classFile or "warrior"):lower()
end

-- Cuts a string to at most maxBytes without splitting a UTF-8 character.
function Core.Utf8Truncate(s, maxBytes)
    if #s <= maxBytes then return s end
    local i = maxBytes
    while i > 0 do
        local nextByte = s:byte(i + 1)
        if nextByte < 0x80 or nextByte >= 0xC0 then break end
        i = i - 1
    end
    return s:sub(1, i)
end

-- Removes control characters, UI escape sequences ("|") and the protocol separator.
function Core.SanitizeDescription(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("[%c|" .. Core.SEP .. "]", " ")
    text = text:gsub("%s+", " ")
    text = text:gsub("^ ", ""):gsub(" $", "")
    text = Core.Utf8Truncate(text, Core.MAX_DESC_BYTES)
    text = text:gsub(" $", "")
    return text
end

local function split(s, sep)
    local parts = {}
    for part in (s .. sep):gmatch("(.-)" .. sep) do
        parts[#parts + 1] = part
    end
    return parts
end

local function roundToGrid(v)
    return math.floor(v / Core.POSITION_GRID + 0.5) * Core.POSITION_GRID
end

-- Message formats (all fields separated by SEP):
--   H~proto~raceID~classID~level~instanceID~x~y~portrait~description   profile broadcast
--   Q~proto                                                  ask nearby players to broadcast
--   L~proto                                                  like (sent by whisper)
function Core.EncodeHello(p)
    return table.concat({
        "H", Core.PROTOCOL, p.raceID, p.classID, p.level, p.instanceID,
        roundToGrid(p.x), roundToGrid(p.y), Core.IsPortrait(p.portrait) and p.portrait or "c",
        Core.SanitizeDescription(p.description),
    }, Core.SEP)
end

function Core.EncodeQuery()
    return "Q" .. Core.SEP .. Core.PROTOCOL
end

function Core.EncodeLike()
    return "L" .. Core.SEP .. Core.PROTOCOL
end

-- Returns kind, data. kind is nil for anything malformed or from another protocol version.
function Core.Decode(msg)
    if type(msg) ~= "string" then return nil end
    local parts = split(msg, Core.SEP)
    local kind, proto = parts[1], tonumber(parts[2])
    if proto ~= Core.PROTOCOL then return nil end
    if kind == "Q" or kind == "L" then
        return kind
    elseif kind == "H" and #parts == 10 then
        local p = {
            raceID = tonumber(parts[3]),
            classID = tonumber(parts[4]),
            level = tonumber(parts[5]),
            instanceID = tonumber(parts[6]),
            x = tonumber(parts[7]),
            y = tonumber(parts[8]),
            portrait = Core.IsPortrait(parts[9]) and parts[9] or "c",
            description = Core.SanitizeDescription(parts[10]),
        }
        if not (p.raceID and p.classID and p.level and p.instanceID and p.x and p.y) then
            return nil
        end
        return "H", p
    end
    return nil
end

function Core.Distance(a, b)
    if not (a and b) or a.instanceID ~= b.instanceID then return nil end
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function snapshot(profile)
    if not profile then return {} end
    return {
        raceID = profile.raceID,
        classID = profile.classID,
        level = profile.level,
        portrait = profile.portrait,
        description = profile.description,
    }
end

-- Called when the local player likes `name`. Returns true if this creates a match.
function Core.RecordLike(db, name, now, profile)
    db.liked[name] = now
    db.rejected[name] = nil
    if db.likedBy[name] and not db.matches[name] then
        local m = snapshot(profile)
        m.time = now
        db.matches[name] = m
        return true
    end
    return false
end

-- Called when a like from `name` arrives. Returns true if this creates a match.
function Core.ReceiveLike(db, name, now, profile)
    if db.blocked[name] then return false end
    db.likedBy[name] = now
    if db.liked[name] and not db.matches[name] then
        local m = snapshot(profile)
        m.time = now
        db.matches[name] = m
        return true
    end
    return false
end

function Core.RecordReject(db, name, now)
    db.rejected[name] = now
end

function Core.RemoveMatch(db, name, block)
    db.matches[name] = nil
    db.liked[name] = nil
    db.likedBy[name] = nil
    if block then db.blocked[name] = true end
end

function Core.ForgetRejected(db)
    for k in pairs(db.rejected) do db.rejected[k] = nil end
end

-- Drops profiles that have not been refreshed recently.
function Core.PruneProfiles(profiles, now)
    for name, p in pairs(profiles) do
        if now - (p.seen or 0) > Core.PROFILE_TTL then profiles[name] = nil end
    end
end

-- Returns the list of { name = ..., profile = ..., distance = ... } still to be shown, closest first.
function Core.Candidates(db, profiles, me, now)
    local s = db.settings
    local list = {}
    for name, p in pairs(profiles) do
        local rejectedAt = db.rejected[name]
        local skip = name == me.name
            or db.liked[name] or db.matches[name] or db.blocked[name]
            or (rejectedAt and now - rejectedAt < Core.REJECT_COOLDOWN)
            or now - (p.seen or 0) > Core.PROFILE_TTL
            or (s.maxLevelDiff > 0 and math.abs(p.level - me.level) > s.maxLevelDiff)
        if not skip then
            local d = p.demo and p.distance or Core.Distance(me, p)
            if d and d <= s.radius then
                list[#list + 1] = { name = name, profile = p, distance = d }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        return a.name < b.name
    end)
    return list
end

function Core.NextStep(steps, current, delta)
    local idx = 1
    for i, v in ipairs(steps) do
        if v == current then idx = i break end
        if v < current then idx = i end
    end
    idx = math.max(1, math.min(#steps, idx + delta))
    return steps[idx]
end

return ns

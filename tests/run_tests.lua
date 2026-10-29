-- Run from the repository root with: lua5.1 tests/run_tests.lua
local ns = {}
assert(loadfile("Flechazo/Core.lua"))("Flechazo", ns)
local Core = ns.Core

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else failed = failed + 1 print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function eq(a, b) assert(a == b, ("expected %s, got %s"):format(tostring(b), tostring(a))) end

test("sanitize removes separators, escapes and control chars", function()
    eq(Core.SanitizeDescription("  hola~|cffff0000rojo|r\nadiós  "), "hola cffff0000rojo r adiós")
    eq(Core.SanitizeDescription(nil), "")
end)

test("sanitize truncates without breaking UTF-8", function()
    local s = Core.SanitizeDescription(("ñ"):rep(60))   -- 120 bytes
    eq(#s, 80)
    eq(s, ("ñ"):rep(40))
    local t = Core.SanitizeDescription("a" .. ("ñ"):rep(60))
    eq(#t, 79)
end)

test("hello round trip", function()
    local msg = Core.EncodeHello({ raceID = 1, classID = 8, level = 40, instanceID = 0,
        x = -8913.4, y = 554.6, portrait = "f", description = "Busco grupo" })
    assert(#msg <= 255)
    local kind, p = Core.Decode(msg)
    eq(kind, "H"); eq(p.raceID, 1); eq(p.classID, 8); eq(p.level, 40); eq(p.instanceID, 0)
    eq(p.x, -8910); eq(p.y, 550); eq(p.portrait, "f"); eq(p.description, "Busco grupo")
end)

test("longest hello fits in an addon message", function()
    local msg = Core.EncodeHello({ raceID = 85, classID = 13, level = 80, instanceID = 2552,
        x = -12345.6, y = -12345.6, portrait = "m", description = ("ñ"):rep(100) })
    assert(#msg <= 255, #msg)
end)

test("decode rejects junk and other protocol versions", function()
    eq(Core.Decode("H~1~1~1~1~0~0~0~m~x"), nil)          -- old protocol
    eq(Core.Decode("H~2~a~1~1~0~0~0~m~x"), nil)
    eq(Core.Decode("H~2~1~1~1~0~0~0~x"), nil)            -- missing field
    eq(Core.Decode("Z~1"), nil)
    eq(Core.Decode(nil), nil)
    eq((Core.Decode(Core.EncodeQuery())), "Q")
    eq((Core.Decode(Core.EncodeLike())), "L")
end)

test("unknown portrait codes fall back to the class icon", function()
    local _, p = Core.Decode("H~2~1~1~1~0~0~0~zz~hola")
    eq(p.portrait, "c")
    local msg = Core.EncodeHello({ raceID = 1, classID = 1, level = 1, instanceID = 0, x = 0, y = 0, portrait = "x" })
    eq(select(2, Core.Decode(msg)).portrait, "c")
end)

test("portrait atlas names", function()
    eq(Core.PortraitAtlas("m", "Human", "MAGE"), "raceicon128-human-male")
    eq(Core.PortraitAtlas("f", "Scourge", "PRIEST"), "raceicon128-undead-female")
    eq(Core.PortraitAtlas("f", "HighmountainTauren", "DRUID"), "raceicon128-highmountain-female")
    eq(Core.PortraitAtlas("m", "KulTiran", "DRUID"), "raceicon128-kultiran-male")
    eq(Core.PortraitAtlas("c", "Human", "DEATHKNIGHT"), "classicon-deathknight")
    eq(Core.PortraitAtlas("m", nil, "MAGE"), "classicon-mage")
end)

test("EnsureDB drops an invalid saved portrait", function()
    eq(Core.EnsureDB({ portrait = "zz" }).portrait, nil)
    eq(Core.EnsureDB({ portrait = "f" }).portrait, "f")
end)

test("distance only within the same instance", function()
    eq(Core.Distance({ instanceID = 0, x = 0, y = 0 }, { instanceID = 0, x = 3, y = 4 }), 5)
    eq(Core.Distance({ instanceID = 0, x = 0, y = 0 }, { instanceID = 1, x = 3, y = 4 }), nil)
end)

test("match when I like first", function()
    local db = Core.EnsureDB(nil)
    eq(Core.RecordLike(db, "A-R", 1, { classID = 1 }), false)
    eq(Core.ReceiveLike(db, "A-R", 2), true)
    assert(db.matches["A-R"])
    eq(Core.ReceiveLike(db, "A-R", 3), false)   -- no duplicate match
end)

test("match when they like first", function()
    local db = Core.EnsureDB(nil)
    eq(Core.ReceiveLike(db, "B-R", 1), false)
    eq(Core.RecordLike(db, "B-R", 2, { classID = 2, raceID = 2, level = 10, portrait = "f", description = "x" }), true)
    eq(db.matches["B-R"].classID, 2)
    eq(db.matches["B-R"].portrait, "f")
end)

test("blocked players can't match", function()
    local db = Core.EnsureDB(nil)
    Core.RecordLike(db, "C-R", 1)
    Core.RemoveMatch(db, "C-R", true)
    Core.RecordLike(db, "C-R", 2)
    eq(Core.ReceiveLike(db, "C-R", 3), false)
end)

test("candidates filter and sort", function()
    local db = Core.EnsureDB(nil)
    db.settings.radius = 500
    local me = { name = "Me-R", level = 40, instanceID = 0, x = 0, y = 0 }
    local now = 1000
    local profiles = {
        ["Me-R"] = { level = 40, instanceID = 0, x = 0, y = 0, seen = now },
        ["Far-R"] = { level = 40, instanceID = 0, x = 900, y = 0, seen = now },
        ["Near-R"] = { level = 40, instanceID = 0, x = 100, y = 0, seen = now },
        ["Mid-R"] = { level = 40, instanceID = 0, x = 300, y = 0, seen = now },
        ["Old-R"] = { level = 40, instanceID = 0, x = 10, y = 0, seen = now - 600 },
        ["Other-R"] = { level = 40, instanceID = 1, x = 0, y = 0, seen = now },
        ["Low-R"] = { level = 10, instanceID = 0, x = 50, y = 0, seen = now },
        ["Liked-R"] = { level = 40, instanceID = 0, x = 20, y = 0, seen = now },
        ["Rej-R"] = { level = 40, instanceID = 0, x = 30, y = 0, seen = now },
    }
    db.liked["Liked-R"] = now
    db.rejected["Rej-R"] = now
    db.settings.maxLevelDiff = 5
    local list = Core.Candidates(db, profiles, me, now)
    eq(#list, 2); eq(list[1].name, "Near-R"); eq(list[2].name, "Mid-R")
    db.settings.maxLevelDiff = 0
    eq(#Core.Candidates(db, profiles, me, now), 3)
    eq(#Core.Candidates(db, profiles, me, now + Core.REJECT_COOLDOWN + 1), 0)  -- everything expired
    Core.ForgetRejected(db)
    eq(#Core.Candidates(db, profiles, me, now), 4)
end)

test("prune drops stale profiles", function()
    local profiles = { a = { seen = 0 }, b = { seen = 1000 } }
    Core.PruneProfiles(profiles, 1000)
    eq(profiles.a, nil); assert(profiles.b)
end)

test("steppers", function()
    eq(Core.NextStep(Core.RADIUS_STEPS, 500, 1), 1000)
    eq(Core.NextStep(Core.RADIUS_STEPS, 500, -1), 250)
    eq(Core.NextStep(Core.RADIUS_STEPS, 5000, 1), 5000)
    eq(Core.NextStep(Core.RADIUS_STEPS, 300, 1), 500)
end)

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)

-- Loads the whole addon against a fake WoW API to catch runtime errors in the glue code.
-- Run from the repository root with: lua5.1 tests/smoke_test.lua
local sent, frames, timers, printed = {}, {}, {}, {}

local function dummy()
    local obj = { scripts = {}, events = {}, attrs = {}, shown = true }
    return setmetatable(obj, { __index = function(t, k)
        if k == "SetScript" then return function(self, n, f) self.scripts[n] = f end end
        if k == "RegisterEvent" then return function(self, e) self.events[e] = true end end
        if k == "SetAttribute" then return function(self, a, v) self.attrs[a] = v end end
        if k == "Show" then return function(self) self.shown = true end end
        if k == "Hide" then return function(self) self.shown = false end end
        if k == "SetShown" then return function(self, v) self.shown = v and true or false end end
        if k == "IsShown" or k == "IsVisible" then return function(self) return self.shown end end
        if k == "SetText" then return function(self, v) self.text = v end end
        if k == "GetText" then return function(self) return self.text or "" end end
        if k == "SetChecked" then return function(self, v) self.checked = v end end
        if k == "GetChecked" then return function(self) return self.checked end end
        return function() return dummy() end
    end })
end

_G.CreateFrame = function() local f = dummy() frames[#frames + 1] = f return f end
_G.UIParent = dummy()
_G.UISpecialFrames = {}
_G.tinsert = table.insert
_G.time = os.time
local clock = 100
_G.GetTime = function() return clock end
_G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end, NewTicker = function() end }
_G.print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
_G.IsInInstance = function() return false end
_G.UnitPosition = function() return 500, -8900, 0, 0 end
_G.UnitFullName = function(u) if u == "player" then return "Yo", "Reino" end end
_G.GetNormalizedRealmName = function() return "Reino" end
_G.UnitRace = function() return "Humano", "Human", 1 end
_G.UnitClass = function() return "Mago", "MAGE", 8 end
_G.UnitLevel = function() return 40 end
_G.UnitSex = function() return 3 end
local portraitUnits = {}
_G.SetPortraitTexture = function(_, unit) portraitUnits[#portraitUnits + 1] = unit end
_G.UnitExists = function() return false end
_G.InCombatLockdown = function() return false end
_G.GetChannelName = function() return 5, "FlechazoAddon0" end
_G.JoinTemporaryChannel = function() end
_G.LeaveChannelByName = function() end
_G.Ambiguate = function(n, mode) if mode == "short" then return (n:gsub("%-.*", "")) end return n end
_G.PlaySound = function() end
_G.SOUNDKIT = { READY_CHECK = 1 }
_G.SlashCmdList = {}
_G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() end,
    SendAddonMessage = function(...) sent[#sent + 1] = { ... } return 0 end,
    SendAddonMessageLogged = function(...) sent[#sent + 1] = { logged = true, ... } return 0 end,
}
_G.C_CreatureInfo = {
    GetClassInfo = function(id) return { className = "Clase" .. id, classFile = "MAGE" } end,
    GetRaceInfo = function(id) return { raceName = "Raza" .. id, clientFileString = "Human" } end,
}
_G.C_ClassColor = { GetClassColor = function() return { WrapTextInColorCode = function(_, t) return t end } end }
_G.C_Texture = { GetAtlasInfo = function() return {} end }
_G.C_FriendList = { AddFriend = function() end }
_G.C_PartyInfo = { InviteUnit = function() end }

local ns = {}
for _, file in ipairs({ "Core.lua", "Comm.lua", "UI.lua", "Flechazo.lua" }) do
    assert(loadfile("Flechazo/" .. file))("Flechazo", ns)
end

local function fire(event, ...)
    for _, f in ipairs(frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end
local function runTimers() local t = timers timers = {} for _, fn in ipairs(t) do fn() end end

fire("ADDON_LOADED", "Flechazo")
assert(ns.db and SlashCmdList.FLECHAZO, "addon did not initialize")
fire("PLAYER_ENTERING_WORLD"); runTimers(); runTimers()
assert(#sent >= 1 and sent[1].logged and sent[1][3] == "CHANNEL", "no hello broadcast")

-- Demo flow: the mirror entry comes first and shows your real face; like everyone, two like back.
SlashCmdList.FLECHAZO("demo")
assert(ns.Candidates()[1].name == "Espejo-Reino", "mirror entry should be first")
assert(portraitUnits[#portraitUnits] == "player", "mirror card should draw the real portrait")
for _ = 1, 5 do
    local c = ns.Candidates()[1]
    ns.Like(c.name)
end
local n = 0 for _ in pairs(ns.db.matches) do n = n + 1 end
assert(n == 2, "expected 2 demo matches, got " .. n)
SlashCmdList.FLECHAZO("demo")   -- clears demo data
assert(next(ns.db.matches) == nil)

-- Network flow: another player broadcasts, I like them, they like me back.
assert(ns.Core.Decode(sent[1][2]), "own hello not decodable")
assert(select(2, ns.Core.Decode(sent[1][2])).portrait == "f", "default portrait should follow the character")
local hello = ns.Core.EncodeHello({ raceID = 2, classID = 1, level = 41, instanceID = 0, x = -8850, y = 520, portrait = "m", description = "Hola" })
fire("CHAT_MSG_ADDON_LOGGED", "FLECHAZO", hello, "CHANNEL", "Otro-Reino")
local c = ns.Candidates()
assert(#c == 1 and c[1].name == "Otro-Reino", "remote profile not listed")
sent = {}
ns.Like("Otro-Reino")
assert(sent[1][3] == "WHISPER" and sent[1][4] == "Otro-Reino", "like not whispered")
fire("CHAT_MSG_ADDON", "FLECHAZO", ns.Core.EncodeLike(), "WHISPER", "Otro-Reino")
assert(ns.db.matches["Otro-Reino"], "no match after mutual like")

-- Own and malformed messages are ignored.
fire("CHAT_MSG_ADDON_LOGGED", "FLECHAZO", hello, "CHANNEL", "Yo-Reino")
fire("CHAT_MSG_ADDON", "FLECHAZO", "basura", "CHANNEL", "X-Reino")
assert(ns.Comm.profiles["Yo-Reino"] == nil and ns.Comm.profiles["X-Reino"] == nil)

-- UI tabs and slash commands run without errors.
SlashCmdList.FLECHAZO("")
SlashCmdList.FLECHAZO("estado")
SlashCmdList.FLECHAZO("ayuda")
for _, f in ipairs(frames) do if f.scripts.OnClick then f.scripts.OnClick(f) end end

io.stdout:write("smoke test ok\n")

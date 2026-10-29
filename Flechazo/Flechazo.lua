-- Flechazo: entry point, slash commands and glue between Comm and UI.
local addonName, ns = ...
local Core = ns.Core

ns.demo = {}   -- local fake profiles for trying the UI alone (/fz demo)

local function chat(msg)
    print("|cffff5fa2Flechazo|r: " .. msg)
end
ns.Print = chat

-- Profiles from the network plus demo ones.
function ns.AllProfiles()
    local all = {}
    for k, v in pairs(ns.Comm.profiles) do all[k] = v end
    for k, v in pairs(ns.demo) do all[k] = v end
    return all
end

function ns.GetProfile(name)
    return ns.demo[name] or ns.Comm.profiles[name]
end

function ns.Candidates()
    local me = ns.Comm.MyProfile()
    return Core.Candidates(ns.db, ns.AllProfiles(), me, time())
end

function ns.OnProfilesChanged()
    if ns.UI then ns.UI.Refresh() end
end

local function announceMatch(name)
    chat(("¡Match con |cffffd100%s|r! Abre /fz para agregaros o invitarle al grupo."):format(name))
    if SOUNDKIT and SOUNDKIT.READY_CHECK then PlaySound(SOUNDKIT.READY_CHECK) end
    if ns.UI then ns.UI.Refresh() end
end

function ns.Like(name)
    local profile = ns.GetProfile(name)
    if profile and profile.demo then
        if profile.likesBack then Core.ReceiveLike(ns.db, name, time(), profile) end
    else
        ns.Comm.SendLike(name)
    end
    if Core.RecordLike(ns.db, name, time(), profile) then announceMatch(name) end
end

function ns.Reject(name)
    Core.RecordReject(ns.db, name, time())
end

function ns.OnLikeReceived(name)
    if Core.ReceiveLike(ns.db, name, time(), ns.GetProfile(name)) then announceMatch(name) end
end

-- Fake nearby players so the whole flow can be tested without a second account.
local function loadDemo()
    local me = ns.Comm.MyProfile()
    local realm = GetNormalizedRealmName() or "Demo"
    local entries = {
        { "Aria", 1, 8, 40, "Busco grupo para mazmorras por la tarde. ¡Me encanta pescar!", true },
        { "Brakk", 2, 1, 38, "Tanque tranquilo, juego de noche. Paciencia con los nuevos.", false },
        { "Lunethil", 4, 11, 42, "Druida curandera. Rol ligero y exploración.", true },
        { "Tikka", 8, 3, 35, "Cazadora en busca de compis para subir de nivel.", false },
    }
    for i, e in ipairs(entries) do
        ns.demo[e[1] .. "-" .. realm] = {
            demo = true, raceID = e[2], classID = e[3], level = e[4], description = e[5],
            likesBack = e[6], distance = i * 40, seen = time() + 3600, instanceID = me.instanceID,
        }
    end
    chat("Modo demo activado: 4 jugadores de prueba (Aria y Lunethil te devolverán el like).")
end

local function clearDemo()
    for name in pairs(ns.demo) do
        ns.demo[name] = nil
        Core.RemoveMatch(ns.db, name, false)
        ns.db.rejected[name] = nil
    end
    chat("Modo demo desactivado.")
end

local function handleSlash(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "" then
        ns.UI.Toggle()
    elseif msg == "demo" then
        if next(ns.demo) then clearDemo() else loadDemo() end
        ns.UI.Show()
    elseif msg == "estado" or msg == "status" then
        local x, _, instanceID = ns.Comm.MyPosition()
        chat(("Visible: %s | Posición: %s | Jugadores recibidos: %d"):format(
            ns.db.settings.discoverable and "sí" or "no",
            x and ("continente " .. instanceID) or "no disponible (¿estás en una instancia?)",
            (function() local n = 0 for _ in pairs(ns.Comm.profiles) do n = n + 1 end return n end)()))
    else
        chat("Comandos: /fz (abrir), /fz demo (jugadores de prueba), /fz estado")
    end
end

function Flechazo_OnAddonCompartmentClick()
    ns.UI.Toggle()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    FlechazoCharDB = Core.EnsureDB(FlechazoCharDB)
    ns.db = FlechazoCharDB
    ns.Comm.Init()
    ns.UI.Init()
    SLASH_FLECHAZO1 = "/flechazo"
    SLASH_FLECHAZO2 = "/fz"
    SlashCmdList.FLECHAZO = handleSlash
end)

-- Flechazo: addon communication (custom channel per continent + whispers for likes).
local _, ns = ...
local Core = ns.Core

local Comm = {}
ns.Comm = Comm

Comm.PREFIX = "FLECHAZO"
Comm.CHANNEL_BASE = "FlechazoAddon"   -- custom channel names can't contain "-"
Comm.HELLO_INTERVAL = 60
Comm.QUERY_COOLDOWN = 30
Comm.REPLY_COOLDOWN = 20

Comm.profiles = {}   -- name -> profile received from other players

local channelName      -- currently joined channel
local lastHello, lastQuery = 0, 0

local function isSecret(v)
    return issecretvalue and issecretvalue(v)
end

function Comm.FullName(name, realm)
    if not name or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    realm = realm and realm ~= "" and realm or GetNormalizedRealmName()
    return realm and (name .. "-" .. realm) or name
end

function Comm.MyName()
    local name, realm = UnitFullName("player")
    return Comm.FullName(name, realm)
end

-- Returns x, y, instanceID or nil (nil inside instances, battlegrounds and arenas).
function Comm.MyPosition()
    if IsInInstance() then return nil end
    local y, x, _, instanceID = UnitPosition("player")
    if not x or isSecret(x) or isSecret(instanceID) then return nil end
    return x, y, instanceID
end

function Comm.MyProfile()
    local x, y, instanceID = Comm.MyPosition()
    return {
        name = Comm.MyName(),
        raceID = select(3, UnitRace("player")),
        classID = select(3, UnitClass("player")),
        level = UnitLevel("player"),
        instanceID = instanceID,
        x = x, y = y,
        description = ns.db.description,
    }
end

local function channelIndex()
    if not channelName then return nil end
    local id = GetChannelName(channelName)
    return id and id > 0 and id or nil
end

local function hideChannelFromChat(name)
    local remove = ChatFrame_RemoveChannel or (ChatFrameUtil and ChatFrameUtil.RemoveChannel)
    if not remove then return end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame then pcall(remove, frame, name) end
    end
end

-- Joins the channel for the current continent (one channel per instanceID keeps traffic local).
function Comm.UpdateChannel()
    local _, _, instanceID = Comm.MyPosition()
    if not instanceID then return end
    local wanted = Comm.CHANNEL_BASE .. instanceID
    if wanted == channelName then return end
    if channelName then LeaveChannelByName(channelName) end
    channelName = wanted
    JoinTemporaryChannel(wanted)
    C_Timer.After(2, function() hideChannelFromChat(wanted) end)
end

local function send(msg, chatType, target, logged)
    local fn = logged and C_ChatInfo.SendAddonMessageLogged or C_ChatInfo.SendAddonMessage
    local ok, result = pcall(fn, Comm.PREFIX, msg, chatType, target)
    if not ok then return false end
    -- 0 = Enum.SendAddonMessageResult.Success; older clients return a boolean.
    return result == 0 or result == true or result == nil
end

function Comm.SendHello(force)
    local now = GetTime()
    if not ns.db.settings.discoverable then return end
    if not force and now - lastHello < Comm.REPLY_COOLDOWN then return end
    local me = Comm.MyProfile()
    local idx = channelIndex()
    if not (me.instanceID and idx) then return end
    if send(Core.EncodeHello(me), "CHANNEL", idx, true) then lastHello = now end
end

function Comm.SendQuery()
    local now = GetTime()
    if now - lastQuery < Comm.QUERY_COOLDOWN then return end
    local idx = channelIndex()
    if idx and send(Core.EncodeQuery(), "CHANNEL", idx) then lastQuery = now end
end

function Comm.SendLike(name)
    return send(Core.EncodeLike(), "WHISPER", name)
end

local function onMessage(prefix, text, chatType, sender)
    if prefix ~= Comm.PREFIX or isSecret(text) or isSecret(sender) then return end
    sender = Comm.FullName(Ambiguate(sender, "none"))
    if not sender or sender == Comm.MyName() or ns.db.blocked[sender] then return end

    local kind, data = Core.Decode(text)
    if kind == "H" and chatType == "CHANNEL" then
        data.seen = time()
        Comm.profiles[sender] = data
        ns.OnProfilesChanged()
    elseif kind == "Q" and chatType == "CHANNEL" then
        -- Random delay so everyone doesn't answer in the same second.
        C_Timer.After(math.random() * 5, function() Comm.SendHello(false) end)
    elseif kind == "L" and chatType == "WHISPER" then
        ns.OnLikeReceived(sender)
    end
end

function Comm.Init()
    C_ChatInfo.RegisterAddonMessagePrefix(Comm.PREFIX)
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("CHAT_MSG_ADDON_LOGGED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" or event == "CHAT_MSG_ADDON_LOGGED" then
            onMessage(...)
        else
            -- Give the default channels (General, Trade...) time to take the first slots.
            C_Timer.After(event == "PLAYER_ENTERING_WORLD" and 10 or 2, function()
                Comm.UpdateChannel()
                C_Timer.After(3, function() Comm.SendHello(true) end)
            end)
        end
    end)
    C_Timer.NewTicker(Comm.HELLO_INTERVAL, function()
        Core.PruneProfiles(Comm.profiles, time())
        Comm.SendHello(true)
        ns.OnProfilesChanged()
    end)
end

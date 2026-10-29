-- Flechazo: user interface (discover cards, matches list, profile/settings).
local _, ns = ...
local Core = ns.Core

local UI = {}
ns.UI = UI

local WIDTH, HEIGHT = 340, 500
local frame, panels, tabs = nil, {}, {}
local current            -- candidate currently shown on the card
local cardWidgets = {}

local function classInfo(classID)
    return C_CreatureInfo.GetClassInfo(classID) or { className = "?", classFile = "PRIEST" }
end

local function raceName(raceID)
    local info = C_CreatureInfo.GetRaceInfo(raceID)
    return info and info.raceName or "?"
end

local function colorByClass(text, classFile)
    local c = C_ClassColor and C_ClassColor.GetClassColor(classFile)
    return c and c:WrapTextInColorCode(text) or text
end

local function shortName(name)
    return Ambiguate(name, "short")
end

local function describe(p)
    local ci = classInfo(p.classID)
    return ("%s · %s · nivel %d"):format(raceName(p.raceID), colorByClass(ci.className, ci.classFile), p.level), ci
end

-- Draws a player's chosen preset photo (race portrait or class icon) on a texture.
local function setPortrait(tex, p)
    local race = C_CreatureInfo.GetRaceInfo(p.raceID)
    local classFile = classInfo(p.classID).classFile
    local atlas = Core.PortraitAtlas(p.portrait, race and race.clientFileString, classFile)
    if not C_Texture.GetAtlasInfo(atlas) then atlas = Core.PortraitAtlas("c", nil, classFile) end
    if C_Texture.GetAtlasInfo(atlas) then
        tex:SetAtlas(atlas)
    else
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
end

local function button(parent, text, width, template)
    local b = CreateFrame("Button", nil, parent, template or "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetText(text)
    return b
end

local function label(parent, font, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    if text then fs:SetText(text) end
    return fs
end

----------------------------------------------------------------------------- Discover

local function showCard()
    local w = cardWidgets
    local list = ns.Candidates()
    current = list[1]
    w.empty:SetShown(not current)
    w.card:SetShown(current and true or false)
    w.counter:SetText(current and ("%d cerca"):format(#list) or "")
    if not current then return end
    local p = current.profile
    local info, ci = describe(p)
    w.name:SetText(colorByClass(shortName(current.name), ci.classFile))
    w.info:SetText(info)
    w.distance:SetText(("a unas %d yardas"):format(math.floor(current.distance + 0.5)))
    w.desc:SetText(p.description ~= "" and p.description or "|cff888888(Sin descripción)|r")
    setPortrait(w.photo, p)
    -- With a race portrait, a small class icon in the corner keeps the class visible at a glance.
    w.badge:SetShown(p.portrait ~= "c")
    setPortrait(w.badge, { raceID = p.raceID, classID = p.classID, portrait = "c" })
end

local function buildDiscover(p)
    local w = cardWidgets
    w.empty = label(p, "GameFontHighlight",
        "No hay nadie cerca usando Flechazo.\n\nPrueba a ampliar el radio en Perfil,\nmuévete por zonas concurridas\no escribe /fz demo para probar.")
    w.empty:SetPoint("CENTER", 0, 20)
    w.empty:SetJustifyH("CENTER")

    local card = CreateFrame("Frame", nil, p)
    card:SetAllPoints()
    w.card = card

    w.photo = card:CreateTexture(nil, "ARTWORK")
    w.photo:SetSize(160, 160)
    w.photo:SetPoint("TOP", 0, -24)
    w.badge = card:CreateTexture(nil, "OVERLAY")
    w.badge:SetSize(40, 40)
    w.badge:SetPoint("BOTTOMRIGHT", w.photo, "BOTTOMRIGHT", 6, -6)

    w.name = label(card, "GameFontNormalLarge")
    w.name:SetPoint("TOP", w.photo, "BOTTOM", 0, -16)
    w.info = label(card, "GameFontHighlight")
    w.info:SetPoint("TOP", w.name, "BOTTOM", 0, -4)
    w.distance = label(card, "GameFontDisableSmall")
    w.distance:SetPoint("TOP", w.info, "BOTTOM", 0, -2)
    w.desc = label(card, "GameFontHighlight")
    w.desc:SetPoint("TOP", w.distance, "BOTTOM", 0, -8)
    w.desc:SetWidth(280)
    w.desc:SetJustifyH("CENTER")
    w.desc:SetMaxLines(3)

    local pass = button(card, "|cffff4040X|r  Pasar", 120)
    pass:SetPoint("BOTTOMLEFT", 20, 10)
    pass:SetScript("OnClick", function()
        if current then ns.Reject(current.name) end
        showCard()
    end)
    local like = button(card, "|cff40ff40<3|r  Me gusta", 120)
    like:SetPoint("BOTTOMRIGHT", -20, 10)
    like:SetScript("OnClick", function()
        if current then ns.Like(current.name) end
        showCard()
    end)

    w.counter = label(p, "GameFontDisableSmall")
    w.counter:SetPoint("TOPRIGHT", -2, -2)

    p.Refresh = showCard
end

----------------------------------------------------------------------------- Matches

local rows = {}

local function openWhisper(name)
    if ChatFrameUtil and ChatFrameUtil.SendTell then
        ChatFrameUtil.SendTell(name)
    elseif ChatFrame_SendTell then
        ChatFrame_SendTell(name)
    elseif ChatFrame_OpenChat then
        ChatFrame_OpenChat("/w " .. name .. " ")
    end
end

local function makeRow(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(290, 58)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * 60)
    row.photo = row:CreateTexture(nil, "ARTWORK")
    row.photo:SetSize(30, 30)
    row.photo:SetPoint("TOPLEFT", 2, -1)
    row.name = label(row, "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.photo, "TOPRIGHT", 6, -1)
    row.info = label(row, "GameFontHighlightSmall")
    row.info:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    local actions = {
        { "Amigo", function(n) C_FriendList.AddFriend(n, "Flechazo") end },
        { "Invitar", function(n) C_PartyInfo.InviteUnit(n) end },
        { "Susurrar", openWhisper },
        { "Quitar", function(n) Core.RemoveMatch(ns.db, n, true) UI.Refresh() end },
    }
    for j, a in ipairs(actions) do
        local b = button(row, a[1], 70)
        b:SetPoint("BOTTOMLEFT", (j - 1) * 72, 2)
        b:SetScript("OnClick", function() a[2](row.player) end)
    end
    return row
end

local function refreshMatches(p)
    local names = {}
    for name in pairs(ns.db.matches) do names[#names + 1] = name end
    table.sort(names, function(a, b) return ns.db.matches[a].time > ns.db.matches[b].time end)
    for i, name in ipairs(names) do
        local row = rows[i] or makeRow(p.child, i)
        rows[i] = row
        local m = ns.db.matches[name]
        row.player = name
        if m.classID then
            local info, ci = describe(m)
            row.name:SetText(colorByClass(shortName(name), ci.classFile))
            row.info:SetText(info)
            setPortrait(row.photo, m)
            row.photo:Show()
        else
            row.name:SetText(shortName(name))
            row.info:SetText("")
            row.photo:Hide()
        end
        row:Show()
    end
    for i = #names + 1, #rows do rows[i]:Hide() end
    p.child:SetHeight(math.max(1, #names * 60))
    p.empty:SetShown(#names == 0)
end

local function buildMatches(p)
    local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    p.child = CreateFrame("Frame", nil, scroll)
    p.child:SetSize(290, 1)
    scroll:SetScrollChild(p.child)
    p.empty = label(p, "GameFontHighlight", "Aún no tienes matches.\nCuando os deis like mutuamente\naparecerán aquí.")
    p.empty:SetPoint("CENTER")
    p.Refresh = function() refreshMatches(p) end
end

----------------------------------------------------------------------------- Profile

local function buildProfile(p)
    local db = ns.db
    local y = -8
    local function place(widget, dy)
        widget:SetPoint("TOPLEFT", 8, y)
        y = y - dy
    end

    place(label(p, "GameFontNormal", "Tu descripción (máx. 80 caracteres):"), 20)
    local edit = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    edit:SetSize(290, 24)
    edit:SetAutoFocus(false)
    edit:SetMaxBytes(Core.MAX_DESC_BYTES + 1)
    edit:SetPoint("TOPLEFT", 14, y)
    y = y - 40
    local function save()
        db.description = Core.SanitizeDescription(edit:GetText())
        edit:SetText(db.description)
        edit:ClearFocus()
    end
    edit:SetScript("OnEnterPressed", save)
    edit:SetScript("OnEscapePressed", function() edit:SetText(db.description) edit:ClearFocus() end)
    edit:SetScript("OnEditFocusLost", save)

    place(label(p, "GameFontNormal", "Tu foto:"), 22)
    local PHOTO_NAMES = { m = "Retrato 1", f = "Retrato 2", c = "Icono de clase" }
    local prevPhoto = button(p, "<", 30)
    prevPhoto:SetPoint("TOPLEFT", 14, y - 8)
    local preview = p:CreateTexture(nil, "ARTWORK")
    preview:SetSize(40, 40)
    preview:SetPoint("LEFT", prevPhoto, "RIGHT", 10, 0)
    local photoName = label(p, "GameFontHighlight")
    photoName:SetPoint("LEFT", preview, "RIGHT", 10, 0)
    photoName:SetWidth(110)
    local nextPhoto = button(p, ">", 30)
    nextPhoto:SetPoint("LEFT", photoName, "RIGHT", 6, 0)
    y = y - 50
    local function updatePhoto()
        local me = ns.Comm.MyProfile()
        setPortrait(preview, me)
        photoName:SetText(PHOTO_NAMES[me.portrait])
    end
    local function cyclePhoto(delta)
        local list, idx = Core.PORTRAITS, 1
        for i, c in ipairs(list) do if c == ns.MyPortrait() then idx = i end end
        db.portrait = list[(idx - 1 + delta) % #list + 1]
        updatePhoto()
    end
    prevPhoto:SetScript("OnClick", function() cyclePhoto(-1) end)
    nextPhoto:SetScript("OnClick", function() cyclePhoto(1) end)

    local check = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    place(check, 36)
    local checkLabel = label(p, "GameFontHighlight", "Visible para otros jugadores")
    checkLabel:SetPoint("LEFT", check, "RIGHT", 4, 0)
    check:SetScript("OnClick", function(self) db.settings.discoverable = self:GetChecked() and true or false end)

    local function stepper(title, steps, key, fmt)
        place(label(p, "GameFontNormal", title), 22)
        local value = label(p, "GameFontHighlight")
        local minus = button(p, "<", 30)
        local plus = button(p, ">", 30)
        minus:SetPoint("TOPLEFT", 14, y)
        value:SetPoint("LEFT", minus, "RIGHT", 10, 0)
        value:SetWidth(120)
        plus:SetPoint("LEFT", value, "RIGHT", 10, 0)
        y = y - 40
        local function update() value:SetText(fmt(db.settings[key])) end
        minus:SetScript("OnClick", function() db.settings[key] = Core.NextStep(steps, db.settings[key], -1) update() end)
        plus:SetScript("OnClick", function() db.settings[key] = Core.NextStep(steps, db.settings[key], 1) update() end)
        return update
    end
    local updRadius = stepper("Radio de búsqueda:", Core.RADIUS_STEPS, "radius", function(v) return v .. " yardas" end)
    local updLevel = stepper("Diferencia máxima de nivel:", Core.LEVEL_DIFF_STEPS, "maxLevelDiff",
        function(v) return v == 0 and "sin límite" or ("±" .. v) end)

    local forget = button(p, "Volver a ver rechazados", 200)
    place(forget, 40)
    forget:SetScript("OnClick", function() Core.ForgetRejected(db) ns.Print("Los jugadores rechazados volverán a aparecer.") end)

    local note = label(p, "GameFontDisableSmall",
        "Solo aparecen jugadores que también usan Flechazo.\nTu posición se comparte redondeada mientras\nseas visible y estés fuera de instancias.")
    place(note, 0)
    note:SetJustifyH("LEFT")

    p.Refresh = function()
        edit:SetText(db.description)
        check:SetChecked(db.settings.discoverable)
        updatePhoto()
        updRadius()
        updLevel()
    end
end

----------------------------------------------------------------------------- Frame

local function selectTab(index)
    for i, panel in ipairs(panels) do
        panel:SetShown(i == index)
        if i == index then tabs[i]:LockHighlight() else tabs[i]:UnlockHighlight() end
    end
    UI.selected = index
    panels[index].Refresh()
    if index == 1 then ns.Comm.SendQuery() end
end

function UI.Init()
    frame = CreateFrame("Frame", "FlechazoFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()
    tinsert(UISpecialFrames, "FlechazoFrame")   -- close with Escape

    local title = label(frame, "GameFontHighlight", "Flechazo")
    title:SetPoint("TOP", 0, -5)

    local builders = { buildDiscover, buildMatches, buildProfile }
    local names = { "Descubrir", "Matches", "Perfil" }
    for i, build in ipairs(builders) do
        local tab = button(frame, names[i], 100)
        tab:SetPoint("TOPLEFT", 12 + (i - 1) * 106, -30)
        tab:SetScript("OnClick", function() selectTab(i) end)
        tabs[i] = tab
        local panel = CreateFrame("Frame", nil, frame)
        panel:SetPoint("TOPLEFT", 12, -62)
        panel:SetPoint("BOTTOMRIGHT", -12, 10)
        build(panel)
        panels[i] = panel
    end
end

function UI.Show()
    frame:Show()
    selectTab(UI.selected or 1)
end

function UI.Toggle()
    if frame:IsShown() then frame:Hide() else UI.Show() end
end

-- Only the discover panel refreshes on its own while visible, so a card isn't swapped mid-decision
-- unless it was empty.
function UI.Refresh()
    if not (frame and frame:IsShown()) then return end
    local panel = panels[UI.selected or 1]
    if UI.selected == 1 and current then
        cardWidgets.counter:SetText(("%d cerca"):format(#ns.Candidates()))
        return
    end
    panel.Refresh()
end

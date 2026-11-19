local _, NS = ...
local Integration = {}
NS.RareScanner = Integration

local hooked = setmetatable({}, {__mode = "k"})
local installed, button, activePin, activePOI
local feedback
local PULSE_DURATION, PULSE_ALPHA = 0.42, 0.62
local markHooked = false
local observedMarks = {}
local zoneCache

local function isForever()
    local interface = GetBuildInfo and select(4, GetBuildInfo())
    return type(interface) == "number" and interface >= 16000 and interface < 17000
end

local function scannerDB()
    if not isForever() or not LibStub then return end
    local ace = LibStub("AceAddon-3.0", true)
    local addon = ace and ace:GetAddon("RareScanner", true)
    return addon and addon.db
end

function Integration.MarkingAvailable()
    return RSOverlayMixin ~= nil and type(RSOverlayMixin.OnAcquired) == "function"
        and type(RegisterStateDriver) == "function" and scannerDB() ~= nil
end

function Integration.ZoneAvailable()
    return Integration.MarkingAvailable() and C_Map and type(C_Map.GetBestMapForUnit) == "function"
        and RSWorldMapButtonMixin and type(RSWorldMapButtonMixin.SetupMenu) == "function"
        and DropdownButtonMixin and type(DropdownButtonMixin.SetupMenu) == "function"
end

local function observeMark(_, _, _, _, _, _, source, groupPin)
    local poi = source and (groupPin and source or source.POI)
    local db = scannerDB()
    local overlays = db and db.char and db.char.overlayActive
    local id = poi and poi.entityID
    local record = id and overlays and overlays[id]
    if not record then return end
    local mark = observedMarks[id]
    if not mark or mark.record ~= record then
        mark = {record = record}
        observedMarks[id] = mark
    end
    mark.npc = poi.isNpc == true
    mark.name = mark.npc and (NS.Core.SafeName(poi.name) or mark.name) or nil
end

local function observeOverlays()
    if markHooked or not Integration.MarkingAvailable() then return end
    hooksecurefunc(RSOverlayMixin, "OnAcquired", observeMark)
    markHooked = true
end

local function markedEntry(app)
    local db = scannerDB()
    local overlays = db and db.char and db.char.overlayActive
    local global = db and db.global
    if not global then return end
    local locale = GetLocale()
    local saved = app.db.rareScannerMarks
    if type(saved) ~= "table" or saved.locale ~= locale or type(saved.names) ~= "table" then
        saved = {locale=locale, names={}}
        app.db.rareScannerMarks = saved
    end
    local cachedNames = global.rare_names and global.rare_names[locale]
    local entry = {nameList = {}, names = {}}
    for id in pairs(saved.names) do
        if not overlays or not overlays[id] then saved.names[id] = nil end
    end
    for id, mark in pairs(observedMarks) do
        if not overlays or overlays[id] ~= mark.record then observedMarks[id] = nil end
    end
    for id, overlay in pairs(overlays or {}) do
        if type(id) == "number" and type(overlay) == "table" then
            local seen = observedMarks[id]
            if seen then
                saved.names[id] = seen.npc and (seen.name or saved.names[id] or true) or nil
            end
            local knownRare = saved.names[id] or (global.rares_found and global.rares_found[id])
            if knownRare and (not seen or seen.npc) then
                local candidate = NS.Core.SafeName(cachedNames and cachedNames[id])
                    or NS.Core.SafeName(saved.names[id])
                if candidate and not entry.names[candidate] then
                    entry.names[candidate] = true
                    entry.nameList[#entry.nameList + 1] = candidate
                end
            end
        end
    end
    table.sort(entry.nameList)
    entry.name = entry.nameList[1]
    if entry.name then return entry end
end

local rareSearchOptions = {autoMark = false}

-- WoW instance map IDs to RareScanner's synthetic dungeon maps.
-- Some wings share an instance map ID and have separate RareScanner entries.
local dungeonMaps = {
    [33] = {100003}, -- Shadowfang Keep
    [36] = {100001}, -- Deadmines
    [43] = {100002}, -- Wailing Caverns
    [47] = {100004}, -- Razorfen Kraul
    [90] = {100006}, -- Gnomeregan
    [109] = {100005, 100022}, -- Temple of Atal'Hakkar / Sunken Temple
    [189] = {100007, 100033, 100034, 100035}, -- Scarlet Monastery
    [209] = {100010}, -- Zul'Farrak
    [229] = {100009, 100012}, -- Blackrock Spire
    [230] = {100008}, -- Blackrock Depths
    [329] = {100011, 100036}, -- Stratholme
    [349] = {100015}, -- Maraudon
    [429] = {100013, 100014, 100032}, -- Dire Maul
    [2970] = {100027}, -- The Drowned City
    [2974] = {100030, 100042}, -- Blackmaw Hold
    [2999] = {100023}, -- Ruins of Lordaeron
    [3039] = {100028}, -- Krol'dok Stronghold
}

local function ignoreMenuItem() end
local ignoredMenu = {
    SetEnabled = ignoreMenuItem, SetResponder = ignoreMenuItem, SetScrollMode = ignoreMenuItem,
    CreateTitle = ignoreMenuItem, CreateDivider = ignoreMenuItem, SetTag = ignoreMenuItem,
}
function ignoredMenu:CreateButton() return ignoredMenu end
ignoredMenu.CreateCheckbox = ignoredMenu.CreateButton

local function readZoneRares(mapID, entry)
    -- RareScanner builds the NPC filter from its zone catalogue, independently of visible pins.
    -- Collect the submenu labels without opening a menu or invoking any of its actions.
    local map = {GetMapID = function() return mapID end}
    local dropdown = {GetParent = function() return map end, IsShown = function() return false end}
    if RSWorldMapButtonMixin.OnLoad then RSWorldMapButtonMixin.OnLoad(dropdown) end
    RSWorldMapButtonMixin.SetupMenu(dropdown)
    if type(dropdown.menuGenerator) ~= "function" then return end

    local filter = setmetatable({}, {__index = ignoredMenu})
    function filter:CreateCheckbox(text)
        local label = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
        local name = NS.Core.SafeName(label:match("^%s*(.-)%s+%(%d+%)$"))
        if name and not entry.names[name] then
            entry.names[name] = true
            entry.nameList[#entry.nameList + 1] = name
        end
        return ignoredMenu
    end
    local npcs = setmetatable({CreateButton = function() return filter end}, {__index = ignoredMenu})
    local root = setmetatable({}, {__index = ignoredMenu})
    function root:CreateButton()
        self.CreateButton = ignoredMenu.CreateButton
        return npcs
    end
    dropdown.menuGenerator(dropdown, root)
end

local function collectZoneRares(mapID, instanceID)
    local entry = {nameList = {}, names = {}, scope = instanceID and ("dungeon:" .. instanceID) or mapID}
    local seen = {}
    local function read(id)
        if not id or seen[id] then return end
        seen[id] = true
        pcall(readZoneRares, id, entry)
    end
    local mapInfo = instanceID and mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    local dungeonType = Enum and Enum.UIMapType and Enum.UIMapType.Dungeon
    -- In an instance, some clients may report the outdoor zone at the entrance.
    if not mapInfo or not dungeonType or mapInfo.mapType >= dungeonType then
        read(mapID)
        if instanceID and mapID and C_Map.GetMapGroupID and C_Map.GetMapGroupMembersInfo then
            local groupID = C_Map.GetMapGroupID(mapID)
            if groupID and groupID > 0 then
                for _, member in ipairs(C_Map.GetMapGroupMembersInfo(groupID) or {}) do read(member.mapID) end
            end
        end
    end
    for _, id in ipairs(instanceID and dungeonMaps[instanceID] or {}) do read(id) end
    table.sort(entry.nameList)
    entry.name = entry.nameList[1]
    return entry
end

local function searchEntry(app)
    if app.db.rareScannerZone ~= true then
        zoneCache = nil
        return markedEntry(app)
    end
    if not Integration.ZoneAvailable() then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    local instanceID
    if GetInstanceInfo then
        local _, kind, _, _, _, _, _, id = GetInstanceInfo()
        if kind == "party" and type(id) == "number" and id > 0 then instanceID = id end
    end
    if not mapID and not instanceID then
        zoneCache = nil
        return
    end
    local now = GetTime()
    if not zoneCache or zoneCache.mapID ~= mapID or zoneCache.instanceID ~= instanceID
        or now >= zoneCache.refreshAt then
        zoneCache = {
            mapID = mapID, instanceID = instanceID, refreshAt = now + 15,
            entry = collectZoneRares(mapID, instanceID),
        }
    end
    local entry = zoneCache.entry
    if entry and entry.name then return entry end
end

local function prepareMarkMacro(target, entry, clicked)
    if InCombatLockdown() then return end
    local macro, nextIndex
    if entry and #entry.nameList > 1 then
        NS.Proximity.Order(entry)
        if target.markKey ~= entry.proximityKey or target.markScope ~= entry.scope then target.markIndex = nil end
        target.markKey, target.markScope = entry.proximityKey, entry.scope
        macro, nextIndex = NS.Core.EntryMacro(entry, rareSearchOptions, target.markIndex)
        if clicked then target.markIndex = nextIndex end
    else
        target.markKey, target.markScope, target.markIndex = nil, nil, nil
        macro = entry and "/targetexact " .. entry.name or nil
    end
    if target:GetAttribute("macrotext1") ~= macro then target:SetAttribute("macrotext1", macro) end
    target.markedNames = entry and entry.nameList or nil
    local active = entry ~= nil
    if target.markActive ~= active then
        target.markActive = active
        target:SetAlpha(active and 1 or 0.5)
        for _, texture in ipairs({target:GetNormalTexture(), target:GetPushedTexture()}) do
            if active then texture:SetVertexColor(0.77, 0.52, 1)
            else texture:SetVertexColor(0.65, 0.65, 0.65) end
        end
    end
end

local function createMarkButton(app)
    local target = CreateFrame("Button", "QuestTargetsRareScannerMark", UIParent, "SecureActionButtonTemplate,SecureHandlerStateTemplate")
    target:RegisterForClicks("AnyUp")
    target:SetAttribute("useOnKeyDown", false)
    target:SetAttribute("type1", "macro")
    -- Keep its place on the bar and block the action from clicks and bindings during combat.
    target:SetAttribute("_onstate-qtcombat", [[
        if newstate == "combat" then self:SetAttribute("type1", nil)
        else self:SetAttribute("type1", "macro") end
    ]])
    RegisterStateDriver(target, "qtcombat", "[combat] combat; ready")
    NS.UI.StyleTargetButton(target, 0.77, 0.52, 1)
    target:SetScript("PreClick", function(self, mouseButton, down)
        if mouseButton == "LeftButton" and not down and not InCombatLockdown() then
            prepareMarkMacro(self, app.db.rareScannerButton ~= false and searchEntry(app) or nil, true)
        end
    end)
    target:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(NS.L("rareScannerButton"))
        local zone = app.db.rareScannerZone == true
        if zone then GameTooltip:AddLine(NS.L("rareScannerZone"), 0.82, 0.82, 0.82, true) end
        for _, name in ipairs(self.markedNames or {}) do GameTooltip:AddLine(name, 1, 1, 1, true) end
        if not self.markedNames then
            GameTooltip:AddLine(NS.L(zone and "rareScannerNoZoneRares" or "rareScannerNoMarks"), 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end)
    target:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Integration.markButton = target
    return target
end

function Integration.SyncMark(app)
    if InCombatLockdown() or not NS.UI.master then return end
    observeOverlays()
    local show = Integration.MarkingAvailable() and app.db.rareScannerButton ~= false
    local target = Integration.markButton
    if not target and show then target = createMarkButton(app) end
    if not target then return end
    if not show then zoneCache = nil end
    prepareMarkMacro(target, show and searchEntry(app) or nil)
    if target:IsShown() ~= show then target:SetShown(show) end
    NS.UI.LayoutTargetButtons(app)
end

local function createFeedback()
    feedback = CreateFrame("Frame", nil, UIParent)
    Integration.feedback = feedback
    feedback:SetFrameStrata("TOOLTIP")
    feedback:EnableMouse(false)
    local ring = feedback:CreateTexture(nil, "ARTWORK")
    ring:SetAllPoints()
    ring:SetTexture("Interface\\AddOns\\QuestTargets\\Textures\\RarePulse")
    ring:SetVertexColor(0.55, 0.88, 0.86)
    feedback:Hide()
    feedback:SetScript("OnUpdate", function(self, delta)
        self.age = self.age + delta
        local progress = self.age / PULSE_DURATION
        if progress >= 1 then
            self:Hide()
            return
        end
        local size = self.startSize * (1 + progress * 0.95)
        self:SetSize(size, size)
        self:SetAlpha(PULSE_ALPHA * (1 - progress))
    end)
end

local function plainLeftClick(mouseButton)
    return mouseButton == "LeftButton" and not InCombatLockdown()
        and not IsShiftKeyDown() and not IsControlKeyDown() and not IsAltKeyDown()
end

local function pulseAt(frame)
    local x, y = frame:GetCenter()
    if not x or not y then return end
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local size = math.max(frame:GetWidth(), frame:GetHeight()) * scale
    feedback:ClearAllPoints()
    feedback:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * scale, y * scale)
    feedback.startSize = size * 1.2
    feedback.age = 0
    feedback:SetSize(feedback.startSize, feedback.startSize)
    feedback:SetAlpha(PULSE_ALPHA)
    feedback:Show()
end

local function clicked(self, mouseButton, down)
    if not down and plainLeftClick(mouseButton) and self:GetAttribute("macrotext1") then
        pulseAt(self)
    end
end

local function nameFor(pin)
    local poi = pin and pin.POI
    if type(poi) ~= "table" or not poi.isNpc or poi.worldmap then return end
    return NS.Core.SafeName(poi.name)
end

local function hide()
    if InCombatLockdown() or not button then return end
    button:Hide()
    button:SetAttribute("macrotext1", nil)
    activePin, activePOI = nil, nil
end

local function position(pin)
    if InCombatLockdown() then return false end
    local x, y = pin:GetCenter()
    if not x or not y then return false end
    local scale = pin:GetEffectiveScale() / UIParent:GetEffectiveScale()
    button:ClearAllPoints()
    -- No parent or anchor dependency on a pooled RareScanner frame: making
    -- those frames protected would prevent RareScanner recycling them in combat.
    button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * scale, y * scale)
    button:SetSize(pin:GetWidth() * scale, pin:GetHeight() * scale)
    button:SetFrameStrata(pin:GetFrameStrata())
    button:SetFrameLevel(pin:GetFrameLevel() + 5)
    return true
end

local function show(pin)
    if InCombatLockdown() then return end
    local name = nameFor(pin)
    if not name or not pin:IsVisible() then hide(); return end
    if not position(pin) then hide(); return end
    activePin, activePOI = pin, pin.POI
    button:SetAttribute("macrotext1", "/targetexact " .. name)
    button:Show()
end

local function attach(pin)
    if not pin or hooked[pin] or not RSMinimapPinMixin
        or pin.OnEnter ~= RSMinimapPinMixin.OnEnter or pin:GetParent() ~= Minimap then return end
    hooked[pin] = true
    pin:HookScript("OnEnter", show)
end

local function minimapClicked(_, mouseButton)
    if not plainLeftClick(mouseButton) then return end
    -- The native Minimap can receive the click if the hover button did not
    -- acquire mouse focus. Check visible RareScanner pins on this input path.
    local hovered
    for pin in pairs(hooked) do
        if pin:IsVisible() and pin:IsMouseOver() and nameFor(pin)
            and (not hovered or pin:GetFrameLevel() > hovered:GetFrameLevel()) then
            hovered = pin
        end
    end
    if hovered then
        pulseAt(hovered)
        show(hovered)
    end
end

function Integration.Initialize()
    if installed or InCombatLockdown() then return end
    if not isForever() or not LibStub or not RSMinimapPinMixin or not RegisterStateDriver then return end
    local pins = LibStub("HereBeDragons-Pins-2.0", true)
    if not pins or type(pins.AddMinimapIconMap) ~= "function" then return end

    local gate = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    RegisterStateDriver(gate, "visibility", "[combat] hide; show")
    button = CreateFrame("Button", "QuestTargetsRareScannerTarget", gate, "SecureActionButtonTemplate")
    Integration.button = button
    button:Hide()
    button:RegisterForClicks("LeftButtonUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type1", "macro")
    createFeedback()
    button:SetScript("PostClick", clicked)
    for _, modifier in ipairs({"shift-", "ctrl-", "alt-", "ctrl-shift-", "alt-shift-", "alt-ctrl-", "alt-ctrl-shift-"}) do
        button:SetAttribute(modifier .. "type1", "")
    end
    button:SetScript("OnEnter", function()
        if InCombatLockdown() or not activePin then return end
        -- Preserve RareScanner's own tooltip (including deferred name resolution).
        local enter = activePin:GetScript("OnEnter")
        if enter then enter(activePin) end
    end)
    button:SetScript("OnLeave", function()
        if InCombatLockdown() then return end
        local leave = activePin and activePin:GetScript("OnLeave")
        if leave then leave(activePin) end
        hide()
    end)
    local elapsed = 0
    button:SetScript("OnUpdate", function(_, delta)
        if InCombatLockdown() then return end
        elapsed = elapsed + delta
        if elapsed < 0.05 then return end
        elapsed = 0
        if not activePin or not activePin:IsVisible() or activePin.POI ~= activePOI
            or not nameFor(activePin) then hide(); return end
        -- Pins move with the player. Refresh the hit area and any resolved name.
        show(activePin)
    end)
    hooksecurefunc(pins, "AddMinimapIconMap", function(_, _, pin) attach(pin) end)
    for _, pin in ipairs({Minimap:GetChildren()}) do attach(pin) end
    Minimap:HookScript("OnMouseUp", minimapClicked)
    installed = true
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then hide() end
    observeOverlays()
    Integration.Initialize()
end)
observeOverlays()

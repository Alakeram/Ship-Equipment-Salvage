-- Ship Equipment Salvaging: "Salvage Wreck" (right-click a wreck) and "Riptide Salvage in Area"
-- (right-click in space) interact-menu orders, plus Remote Salvage / Remote Weld
-- (right-click an S/M ship) and the regulator hand-over rows for a pilot.
-- Vanilla's interact menu only lists hard-coded orders, and SirNukes' Interact Menu
-- API never fired under Kuertee's menu on this setup (MCP test 2026-10-09), so the
-- entry is added through Kuertee UIX interact-menu callbacks. Lua only offers the
-- row; md/ses_salvage_standin.xml validates every ship and wreck again and creates
-- the SESSalvageWreck order.

local ffi = require("ffi")
local C = ffi.C

local CONTENT_TYPE = "ses_salvage_wreck"
local ORDER_ID = "SESSalvageWreck"

local ses = rawget(_G, "__ses_salvage_wreck_interact")
if not ses then
    ses = {}
    _G.__ses_salvage_wreck_interact = ses
end
-- UI reloads rebuild InteractMenu callback tables: register again for this load.
ses.callbacksRegistered = false
local interactMenu

pcall(ffi.cdef, [[typedef uint64_t UniverseID;]])
pcall(ffi.cdef, [[
    UniverseID GetPlayerID(void);
    UniverseID GetPlayerControlledShipID(void);
    bool IsComponentClass(UniverseID componentid, const char* classname);
    size_t GetNumUpgradeSlots(UniverseID destructibleid, const char* macroname, const char* upgradetypename);
    UniverseID GetUpgradeSlotCurrentComponent(UniverseID destructibleid, const char* upgradetypename, size_t slot);
]])
pcall(ffi.cdef, [[bool IsUnit(UniverseID controllableid);]])
pcall(ffi.cdef, [[
    typedef struct {
        const char* id;
        const char* name;
        const char* desc;
        uint32_t amount;
        uint32_t numtiers;
        bool canhire;
    } PeopleInfo;
]])
pcall(ffi.cdef, [[uint32_t GetNumAllRoles(void);]])
pcall(ffi.cdef, [[UniverseID GetPlayerContainerID(void);]])
pcall(ffi.cdef, [[UniverseID GetPlayerOccupiedShipID(void);]])
pcall(ffi.cdef, [[UniverseID GetContextByClass(UniverseID componentid, const char* classname, bool includeself);]])
pcall(ffi.cdef, [[uint32_t GetPeople2(PeopleInfo* result, uint32_t resultlen, UniverseID controllableid, bool includearriving);]])
pcall(ffi.cdef, [[bool IsOrderSelectableFor(const char* orderdefid, UniverseID controllableid);]])
pcall(ffi.cdef, [[bool RemoveAllOrders2(UniverseID controllableid, bool onlytrade, bool onlypriority);]])
pcall(ffi.cdef, [[uint32_t GetNumStoredUnits(UniverseID defensibleid, const char* cat, bool virtualammo);]])

local AREA_CONTENT_TYPE = "ses_salvage_in_area"
local AREA_ORDER_ID = "SESSalvageInRadius"

-- Salvage gear (MD global.$SES_Salvage_Gear_Macros is the authority; this only
-- keeps the menu entry off ships that could never salvage).
local SALVAGE_GEAR_MACROS = {
    ses_weapon_s_salvage_01_mk1_macro = true,
    ses_weapon_m_salvage_01_mk1_macro = true,
    ses_turret_rip_m_salvage_01_mk1_macro = true,
}

local function componentID(value)
    return ConvertStringTo64Bit(tostring(value))
end

local function sesText(id, fallback)
    if ReadText then
        local ok, value = pcall(ReadText, 1171361, id)
        if ok and value and value ~= "" then return value end
    end
    return fallback
end

local function betaEnabled()
    if not GetNPCBlackboard then return false end
    local ok, value = pcall(GetNPCBlackboard, componentID(C.GetPlayerID()), "$SES_Wreck_Mining_Beta_Enabled")
    return ok and (value == true or value == 1)
end

local function targetWreck()
    if not interactMenu or not interactMenu.componentSlot or not interactMenu.componentSlot.component then return nil end
    local ok, object64 = pcall(componentID, interactMenu.componentSlot.component)
    if not ok or not object64 or object64 == 0 then return nil end
    if IsValidComponent and not IsValidComponent(object64) then return nil end
    -- Wrecks keep their ship class only as realclass (as in vanilla menu_map).
    local iswreck, realclass = GetComponentData(object64, "iswreck", "realclassid")
    if iswreck ~= true then return nil end
    if not (Helper.isComponentClass(realclass, "ship_s") or Helper.isComponentClass(realclass, "ship_m")) then return nil end
    -- Drones and deployables (laser towers) are ship_s too but not salvageable hulls.
    if GetComponentData(object64, "isdeployable") then return nil end
    local unitOk, isUnit = pcall(function() return C.IsUnit(object64) end)
    if unitOk and isUnit then return nil end
    return object64
end

local function hasSalvageGear(ship64)
    for _, slotType in ipairs({ "weapon", "turret" }) do
        local ok, count = pcall(function() return tonumber(C.GetNumUpgradeSlots(ship64, "", slotType)) or 0 end)
        for slot = 1, (ok and count or 0) do
            local gear = C.GetUpgradeSlotCurrentComponent(ship64, slotType, slot)
            if gear ~= 0 then
                local macro = GetComponentData(componentID(gear), "macro")
                if macro and SALVAGE_GEAR_MACROS[macro] then return true end
            end
        end
    end
    return false
end

-- Selected player ships with a pilot that the player is not flying and salvage gear.
local function participants()
    local result = {}
    if not interactMenu or type(interactMenu.selectedplayerships) ~= "table" then return result end
    local controlled = componentID(C.GetPlayerControlledShipID())
    for _, component in ipairs(interactMenu.selectedplayerships) do
        local ok, ship64 = pcall(componentID, component)
        if ok and ship64 and ship64 ~= 0 and ship64 ~= controlled
            and (not IsValidComponent or IsValidComponent(ship64))
            and (not IsComponentOperational or IsComponentOperational(ship64)) then
            local isPlayerOwned, pilot = GetComponentData(ship64, "isplayerowned", "pilot")
            if isPlayerOwned == true and pilot ~= nil and pilot ~= 0 and hasSalvageGear(ship64) then
                result[#result + 1] = ship64
            end
        end
    end
    return result
end

local function finishAction()
    if interactMenu and interactMenu.shown and type(interactMenu.onCloseElement) == "function" then
        pcall(interactMenu.onCloseElement, "close")
        return
    end
    -- Kuertee's map order popup may run the action after shown turned false;
    -- perform the same teardown proven by other UIX interact-menu integrations.
    if Helper and type(Helper.resetUpdateHandler) == "function" then pcall(Helper.resetUpdateHandler) end
    local config
    if interactMenu and type(interactMenu.uix_getConfig) == "function" then
        local ok, result = pcall(interactMenu.uix_getConfig)
        if ok then config = result end
    end
    if Helper and type(Helper.clearFrame) == "function" and config and config.layer then
        pcall(Helper.clearFrame, interactMenu, config.layer)
    end
    if Helper and type(Helper.returnFromInteractMenu) == "function" then
        pcall(Helper.returnFromInteractMenu, interactMenu.currentOverTable, "refresh")
    end
    if interactMenu and type(interactMenu.cleanup) == "function" then pcall(interactMenu.cleanup) end
end

local function salvageWreck()
    local wreck = targetWreck()
    local ships = participants()
    if wreck and #ships > 0 and AddUITriggeredEvent and ConvertStringToLuaID then
        -- Versioned list: named Lua table fields are not carried by AddUITriggeredEvent.
        local wire = { 1, ConvertStringToLuaID(tostring(wreck)) }
        for _, ship64 in ipairs(ships) do
            wire[#wire + 1] = ConvertStringToLuaID(tostring(ship64))
        end
        pcall(AddUITriggeredEvent, "SES_Salvage_Wreck", "order", wire)
    end
    finishAction()
end

-- Kuertee's prepareActions returns before its custom-action hooks when the target
-- has no native player actions or is not "known", which is the normal case for a
-- wreck with a non-tug ship selected (MCP test 2026-10-09: the hook never ran).
-- prepareSections_on_end runs first, for every opening, so the row is added here.
local function insertSalvageWreck()
    local wreck = targetWreck()
    local ships = participants()
    if not betaEnabled() or not wreck or #ships == 0 then return end
    if type(interactMenu.insertInteractionContent) ~= "function" then return end
    local iconText = ""
    if type(interactMenu.orderIconText) == "function" then
        local ok, result = pcall(interactMenu.orderIconText, ORDER_ID)
        if ok and type(result) == "string" then iconText = result end
    end
    interactMenu.insertInteractionContent("selected_orders", {
        type = CONTENT_TYPE,
        text = iconText .. sesText(930, "Salvage Wreck"),
        script = salvageWreck,
        active = true,
        -- No mouseOverText: with orderid set, the menu already shows the order description.
        orderid = ORDER_ID,
        helpOverlayID = "",
        helpOverlayText = "",
        helpOverlayHighlightOnly = true,
    })
end

-- "Riptide Salvage in Area" on a right-click in space, next to vanilla Collect
-- Drops (menu_interactmenu "collectspace"). Same gates as the order: the engine
-- checks the order's <requires> with IsOrderSelectableFor, plus a pilot.
local function areaShips()
    local result, selected = {}, 0
    if not interactMenu or type(interactMenu.selectedplayerships) ~= "table" then return result, selected end
    for _, component in ipairs(interactMenu.selectedplayerships) do
        local ok, ship64 = pcall(componentID, component)
        if ok and ship64 and ship64 ~= 0 then
            selected = selected + 1
            local okSel, selectable = pcall(function() return C.IsOrderSelectableFor(AREA_ORDER_ID, ship64) end)
            if okSel and selectable and GetComponentData(ship64, "assignedpilot") then
                result[#result + 1] = ship64
            end
        end
    end
    return result, selected
end

local function areaClicked()
    return interactMenu and interactMenu.offsetcomponent and interactMenu.offsetcomponent ~= 0
        and interactMenu.offset and C.IsComponentClass(interactMenu.offsetcomponent, "sector")
end

local function salvageInArea()
    if areaClicked() and CreateOrder and ConvertStringToLuaID then
        local sector = ConvertStringToLuaID(tostring(interactMenu.offsetcomponent))
        local offset = interactMenu.offset
        for _, ship64 in ipairs(areaShips()) do
            -- As vanilla menu.orderCollectRadius.
            if interactMenu.clearOtherOrders then
                pcall(function() C.RemoveAllOrders2(ship64, false, interactMenu.clearOtherOrders and interactMenu.priorityOrderMode) end)
            end
            local params = { destination = { sector, { offset.x, offset.y, offset.z } } }
            pcall(CreateOrder, ship64, AREA_ORDER_ID, params, false, false, interactMenu.priorityOrderMode, nil, nil, nil, true)
        end
    end
    finishAction()
end

local function insertSalvageInArea()
    if not betaEnabled() or not areaClicked() then return end
    if type(interactMenu.insertInteractionContent) ~= "function" then return end
    -- Only offered when a selected ship can take the order (Marek: no greyed row).
    local ships = areaShips()
    if #ships == 0 then return end
    local iconText = ""
    if type(interactMenu.orderIconText) == "function" then
        local ok, result = pcall(interactMenu.orderIconText, AREA_ORDER_ID)
        if ok and type(result) == "string" then iconText = result end
    end
    interactMenu.insertInteractionContent("selected_orders", {
        type = AREA_CONTENT_TYPE,
        text = iconText .. sesText(938, "Riptide Salvage in Area"),
        script = salvageInArea,
        hidetarget = true,
        active = true,
        orderid = AREA_ORDER_ID,
        prioritysupported = true,
        helpOverlayID = "",
        helpOverlayText = "",
        helpOverlayHighlightOnly = true,
    })
end

-- L/XL update BETA gate (Extension Options, default off; MD checks it again).
local function lxlBetaEnabled()
    if not GetNPCBlackboard then return false end
    local ok, value = pcall(GetNPCBlackboard, componentID(C.GetPlayerID()), "$SES_LXL_Salvage_Beta_Enabled")
    return ok and (value == true or value == 1)
end

-- Remote service (md/ses_remote_service.xml): a selected ship whose pilot
-- carries the matching Avarice regulator and that has service crew salvages
-- from, or welds onto, the right-clicked S/M ship. The row opens the native
-- planner; MD validates everything again.
local REMOTE_ORDER_ID = "SESRemoteService"
local REMOTE_TOOL = { salvage = "ses_equipment_salvager", weld = "ses_equipment_welder" }

local function serviceCrew(ship64)
    local ok, amount = pcall(function()
        local num = C.GetNumAllRoles()
        local people = ffi.new("PeopleInfo[?]", num)
        num = C.GetPeople2(people, num, ship64, false)
        for i = 0, num - 1 do
            if ffi.string(people[i].id) == "service" then return people[i].amount end
        end
        return 0
    end)
    return ok and tonumber(amount) or 0
end

local function assignedPilot(ship64)
    local pilot = GetComponentData(ship64, "assignedpilot")
    if not pilot or pilot == 0 then return nil end
    return componentID(pilot)
end

local function carries(entity, wareid)
    if not entity or not GetInventory then return false end
    local ok, inventory = pcall(GetInventory, entity)
    local entry = ok and type(inventory) == "table" and inventory[wareid] or nil
    return type(entry) == "table" and (tonumber(entry.amount) or 0) > 0
end

-- The right-clicked ship when it is an intact S/M ship.
local function remoteTarget()
    if not interactMenu or not interactMenu.componentSlot or not interactMenu.componentSlot.component then return nil end
    local ok, target64 = pcall(componentID, interactMenu.componentSlot.component)
    if not ok or not target64 or target64 == 0 then return nil end
    if IsValidComponent and not IsValidComponent(target64) then return nil end
    if not (C.IsComponentClass(target64, "ship_s") or C.IsComponentClass(target64, "ship_m")) then return nil end
    if GetComponentData(target64, "iswreck") then return nil end
    return target64
end

local function remoteTargetOK(target64, mode)
    local isPlayerOwned, owner, pilot = GetComponentData(target64, "isplayerowned", "owner", "pilot")
    if mode == "weld" then return isPlayerOwned == true end
    if isPlayerOwned == true then return true end
    return owner == "ownerless" and (not pilot or pilot == 0)
end

-- Drone ships (outfitting, L/XL update BETA): repair drones aboard replace the
-- regulator and the service crew, and the ship may work on itself.
local function repairDrones(ship64)
    local ok, count = pcall(function() return tonumber(C.GetNumStoredUnits(ship64, "repair", false)) or 0 end)
    return ok and count or 0
end

local function isDroneShip(ship64)
    return lxlBetaEnabled() and repairDrones(ship64) > 0
end

-- Selected ships that can do the work: drone ships, or ships whose pilot
-- carries the regulator. With requireCrew, regulator ships also need service
-- crew (the ones that can take the order).
local function remoteShips(target64, mode, requireCrew)
    if requireCrew == nil then requireCrew = true end
    local result = {}
    if not interactMenu or type(interactMenu.selectedplayerships) ~= "table" then return result end
    local controlled = componentID(C.GetPlayerControlledShipID())
    for _, component in ipairs(interactMenu.selectedplayerships) do
        local ok, ship64 = pcall(componentID, component)
        if ok and ship64 and ship64 ~= 0 and ship64 ~= controlled
            and (not IsValidComponent or IsValidComponent(ship64))
            and (not IsComponentOperational or IsComponentOperational(ship64))
            and GetComponentData(ship64, "isplayerowned") == true
            and assignedPilot(ship64) then
            local drone = isDroneShip(ship64)
            if drone or (ship64 ~= target64
                and carries(assignedPilot(ship64), REMOTE_TOOL[mode])
                and ((not requireCrew) or serviceCrew(ship64) > 0)) then
                result[#result + 1] = ship64
            end
        end
    end
    return result
end

local function remoteOrder(mode)
    local target64 = remoteTarget()
    local ships = target64 and remoteShips(target64, mode) or {}
    if target64 and #ships > 0 and AddUITriggeredEvent and ConvertStringToLuaID then
        -- One planner per order: the first eligible selected ship takes the job.
        pcall(AddUITriggeredEvent, "SES_Remote_Service", "order", {
            1, (mode == "weld") and 2 or 1,
            ConvertStringToLuaID(tostring(target64)),
            ConvertStringToLuaID(tostring(ships[1])),
        })
    end
    finishAction()
end

local function insertRemoteService()
    if type(interactMenu.insertInteractionContent) ~= "function" then return end
    local target64 = remoteTarget()
    if not target64 then return end
    local iconText = ""
    if type(interactMenu.orderIconText) == "function" then
        local ok, result = pcall(interactMenu.orderIconText, REMOTE_ORDER_ID)
        if ok and type(result) == "string" then iconText = result end
    end
    -- A selected ship whose pilot carries the regulator shows the row; it is
    -- greyed when none of those ships has service crew (Marek). Without a
    -- regulator-carrying pilot there is no row at all.
    for _, entry in ipairs({ { mode = "salvage", text = 1248, fallback = "Salvage Equipment" }, { mode = "weld", text = 1249, fallback = "Weld Equipment" } }) do
        if remoteTargetOK(target64, entry.mode) and #remoteShips(target64, entry.mode, false) > 0 then
            local ready = #remoteShips(target64, entry.mode, true) > 0
            interactMenu.insertInteractionContent("selected_orders", {
                type = "ses_remote_" .. entry.mode,
                text = iconText .. sesText(entry.text, entry.fallback),
                script = function () return remoteOrder(entry.mode) end,
                active = ready,
                mouseOverText = (not ready) and sesText(1269, "No service crew aboard.") or nil,
                orderid = REMOTE_ORDER_ID,
                helpOverlayID = "",
                helpOverlayText = "",
                helpOverlayHighlightOnly = true,
            })
        end
    end
end

-- Hand a regulator to, or take regulators back from, the pilot of the
-- right-clicked player ship. Only offered when the player is with the ship,
-- the same test as SES_Remote_Handover_V1 (which checks again): aboard it,
-- docked on it, or both docked at the same container.
local function playerNearShip(ship64)
    local ok, near = pcall(function()
        local occupied = componentID(C.GetPlayerOccupiedShipID())
        local container = componentID(C.GetPlayerContainerID())
        if ship64 == occupied or ship64 == container then return true end
        local occupiedDock = (occupied ~= 0) and componentID(C.GetContextByClass(occupied, "container", false)) or 0
        if occupiedDock == ship64 then return true end
        local shipDock = componentID(C.GetContextByClass(ship64, "container", false))
        return shipDock ~= 0 and (shipDock == container or shipDock == occupiedDock)
    end)
    return ok and near == true
end

local function handover(ship64, action)
    if AddUITriggeredEvent and ConvertStringToLuaID then
        pcall(AddUITriggeredEvent, "SES_Remote_Service", "handover", { 1, action, ConvertStringToLuaID(tostring(ship64)) })
    end
    finishAction()
end

local function insertHandover()
    if type(interactMenu.insertInteractionContent) ~= "function" then return end
    if not interactMenu.componentSlot or not interactMenu.componentSlot.component then return end
    local ok, ship64 = pcall(componentID, interactMenu.componentSlot.component)
    if not ok or not ship64 or ship64 == 0 or not C.IsComponentClass(ship64, "ship") then return end
    if GetComponentData(ship64, "isplayerowned") ~= true or GetComponentData(ship64, "iswreck") then return end
    local pilot = assignedPilot(ship64)
    if not pilot or not playerNearShip(ship64) then return end
    local player = componentID(C.GetPlayerID())
    local rows = {}
    for action, tool in ipairs({ REMOTE_TOOL.salvage, REMOTE_TOOL.weld }) do
        if carries(player, tool) and not carries(pilot, tool) then
            rows[#rows + 1] = { action = action, text = (action == 1) and 1252 or 1253, fallback = (action == 1) and "Hand Beam Regulator to Pilot" or "Hand Bonding Regulator to Pilot" }
        end
    end
    if carries(pilot, REMOTE_TOOL.salvage) or carries(pilot, REMOTE_TOOL.weld) then
        rows[#rows + 1] = { action = 3, text = 1254, fallback = "Take Regulators from Pilot" }
    end
    for _, row in ipairs(rows) do
        interactMenu.insertInteractionContent("interaction", {
            type = "ses_regulator_handover_" .. row.action,
            text = sesText(row.text, row.fallback),
            script = function () return handover(ship64, row.action) end,
            active = true,
            helpOverlayID = "",
            helpOverlayText = "",
            helpOverlayHighlightOnly = true,
        })
    end
end

-- "Deconstruct Wreck" (md/ses_drone_salvage.xml): selected ships carrying
-- building drones take a wreck of any size apart. MD validates everything
-- again, claims the wreck and spends the catalysts.
local DRONE_ORDER_ID = "SESDroneDeconstruct"

local function droneWreck()
    if not interactMenu or not interactMenu.componentSlot or not interactMenu.componentSlot.component then return nil end
    local ok, object64 = pcall(componentID, interactMenu.componentSlot.component)
    if not ok or not object64 or object64 == 0 then return nil end
    if IsValidComponent and not IsValidComponent(object64) then return nil end
    local iswreck, realclass = GetComponentData(object64, "iswreck", "realclassid")
    if iswreck ~= true then return nil end
    local sized = false
    for _, class in ipairs({ "ship_s", "ship_m", "ship_l", "ship_xl" }) do
        if Helper.isComponentClass(realclass, class) then sized = true end
    end
    if not sized or GetComponentData(object64, "isdeployable") then return nil end
    local unitOk, isUnit = pcall(function() return C.IsUnit(object64) end)
    if unitOk and isUnit then return nil end
    return object64
end

local function buildDrones(ship64)
    local ok, count = pcall(function() return tonumber(C.GetNumStoredUnits(ship64, "build", false)) or 0 end)
    return ok and count or 0
end

local function droneShips()
    local result = {}
    if not interactMenu or type(interactMenu.selectedplayerships) ~= "table" then return result end
    local controlled = componentID(C.GetPlayerControlledShipID())
    for _, component in ipairs(interactMenu.selectedplayerships) do
        local ok, ship64 = pcall(componentID, component)
        if ok and ship64 and ship64 ~= 0 and ship64 ~= controlled
            and (not IsValidComponent or IsValidComponent(ship64))
            and (not IsComponentOperational or IsComponentOperational(ship64))
            and GetComponentData(ship64, "isplayerowned") == true
            and assignedPilot(ship64) and buildDrones(ship64) > 0 then
            result[#result + 1] = ship64
        end
    end
    return result
end

local function deconstructWreck()
    local wreck = droneWreck()
    local ships = droneShips()
    if wreck and #ships > 0 and AddUITriggeredEvent and ConvertStringToLuaID then
        local wire = { 1, ConvertStringToLuaID(tostring(wreck)) }
        for _, ship64 in ipairs(ships) do
            wire[#wire + 1] = ConvertStringToLuaID(tostring(ship64))
        end
        pcall(AddUITriggeredEvent, "SES_Drone_Salvage", "order", wire)
    end
    finishAction()
end

local function insertDeconstructWreck()
    if not lxlBetaEnabled() then return end
    if type(interactMenu.insertInteractionContent) ~= "function" then return end
    if not droneWreck() or #droneShips() == 0 then return end
    local iconText = ""
    if type(interactMenu.orderIconText) == "function" then
        local ok, result = pcall(interactMenu.orderIconText, DRONE_ORDER_ID)
        if ok and type(result) == "string" then iconText = result end
    end
    interactMenu.insertInteractionContent("selected_orders", {
        type = "ses_drone_deconstruct",
        text = iconText .. sesText(1270, "Deconstruct Wreck"),
        script = deconstructWreck,
        active = true,
        orderid = DRONE_ORDER_ID,
        helpOverlayID = "",
        helpOverlayText = "",
        helpOverlayHighlightOnly = true,
    })
end

local function insertSesOrders()
    pcall(insertSalvageWreck)
    pcall(insertDeconstructWreck)
    pcall(insertSalvageInArea)
    pcall(insertRemoteService)
    pcall(insertHandover)
end

local function registerCallbacks()
    if not Helper or not Helper.getMenu then return false end
    local ok, menu = pcall(Helper.getMenu, "InteractMenu")
    if not ok or not menu or type(menu.registerCallback) ~= "function" then return false end
    interactMenu = menu
    if not ses.callbacksRegistered then
        interactMenu.registerCallback("prepareSections_on_end", insertSesOrders, "ses_salvage_wreck_order")
        ses.callbacksRegistered = true
    end
    return true
end

registerCallbacks()
if Register_OnLoad_Init then
    Register_OnLoad_Init(registerCallbacks, "SES salvage wreck interact order")
end
if Helper and Helper.addDelayedOneTimeCallbackOnUpdate and getElapsedTime then
    Helper.addDelayedOneTimeCallbackOnUpdate(registerCallbacks, false, getElapsedTime() + 1)
    Helper.addDelayedOneTimeCallbackOnUpdate(registerCallbacks, false, getElapsedTime() + 3)
end

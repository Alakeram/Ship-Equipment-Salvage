-- Ship Equipment Salvaging: "Salvage Wreck" (right-click a wreck) and "Riptide Salvage in Area"
-- (right-click in space) interact-menu orders.
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
pcall(ffi.cdef, [[bool IsOrderSelectableFor(const char* orderdefid, UniverseID controllableid);]])
pcall(ffi.cdef, [[bool RemoveAllOrders2(UniverseID controllableid, bool onlytrade, bool onlypriority);]])

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

local function insertSesOrders()
    pcall(insertSalvageWreck)
    pcall(insertSalvageInArea)
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

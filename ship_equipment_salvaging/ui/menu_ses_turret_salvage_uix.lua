-- Ship Equipment Salvaging: mining-turret Salvage BETA.
-- Uses official UIX All-turret callbacks for the All row; individual rows keep
-- the native setter and show the Mining entry of a salvage turret as "Salvage".
-- The virtual actions affect mining turrets only through MD authority.

local ffi = require("ffi")
local C = ffi.C
local version = "v410"
local callbackID = "ship_equipment_salvaging_mining_turrets"
local loggedConflicts = {}

pcall(ffi.cdef, [[typedef uint64_t UniverseID;]])
pcall(ffi.cdef, [[
    UniverseID GetPlayerID(void);
    UniverseID GetPlayerControlledShipID(void);
    bool IsComponentClass(UniverseID componentid, const char* classname);
    size_t GetNumUpgradeSlots(UniverseID destructibleid, const char* macroname, const char* upgradetypename);
    UniverseID GetUpgradeSlotCurrentComponent(UniverseID destructibleid, const char* upgradetypename, size_t slot);
    void SetAllTurretModes(UniverseID defensibleid, const char* mode);
    void SetWeaponMode(UniverseID weaponid, const char* mode);
]])

local function componentID(value)
    return ConvertStringTo64Bit(tostring(value))
end

local function isTrue(value)
    return value == true or value == 1
end

local function readPlayerBoard(key)
    if not GetNPCBlackboard then return nil end
    -- GetNPCBlackboard accepts entities, never ship components. MD publishes
    -- a ship-identified snapshot on the player's entity for UI readback.
    local ok, value = pcall(GetNPCBlackboard, componentID(C.GetPlayerID()), key)
    if ok then return value end
end

local function isControlledShip(ship)
    return ship ~= nil and ship ~= 0 and tostring(ship) ~= "0"
        and componentID(ship) == componentID(C.GetPlayerControlledShipID())
end

local function betaEnabled()
    return isTrue(readPlayerBoard("$SES_Wreck_Mining_Beta_Enabled"))
end

local function salvageEnabled(ship)
    local state = readPlayerBoard("$SES_Turret_Salvage_UI_State")
    if type(state) ~= "table" then return false end
    local publishedShip = state["$ship"] or state.ship
    local enabled = state["$enabled"]
    if enabled == nil then enabled = state.enabled end
    return publishedShip ~= nil and componentID(publishedShip) == componentID(ship)
        and isTrue(enabled)
end

-- Only Avarice salvage turrets can salvage wrecks; ordinary mining turrets do not
-- (MD global.$SES_Salvage_Gear_Macros is the authority; this only gates the menu entry).
local SALVAGE_TURRET_MACROS = { ses_turret_rip_m_salvage_01_mk1_macro = true }

local function hasMiningTurret(ship)
    local count = tonumber(C.GetNumUpgradeSlots(ship, "", "turret")) or 0
    for slot = 1, count do
        local turret = C.GetUpgradeSlotCurrentComponent(ship, "turret", slot)
        if turret ~= 0 and C.IsComponentClass(turret, "turret") then
            local macro = GetComponentData(componentID(turret), "macro")
            if macro and SALVAGE_TURRET_MACROS[macro] then return true end
        end
    end
    return false
end

local function customAvailable(ship)
    return betaEnabled() and isControlledShip(ship) and hasMiningTurret(ship)
end

-- Per-turret "Salvage". A salvage turret in native mining mode is salvaging
-- (md/ses_salvage_standin.xml request tick), so "Salvage" stands in for that
-- turret's Mining entry.
-- * UIX with the per-turret callbacks (fork PR, alakeram markers):
--   display_on_create_turret_mode_dropdown / setupLoadoutInfoSubmenuRows_on_create_turret_mode_dropdown
--   SES builds that row's dropdown with a real "Salvage" entry.
-- * Older UIX: those rows call the native setter directly, so SES only relabels
--   the Mining entry of salvage turrets via Helper.getTurretModes.
local PER_TURRET_CALLBACKS = {
    DockedMenu = "display_on_create_turret_mode_dropdown",
    MapMenu = "setupLoadoutInfoSubmenuRows_on_create_turret_mode_dropdown",
}
local SALVAGE_MODE_ID = "ses_salvage_turret"

local function isSalvageTurret(turret)
    if turret == nil or turret == 0 or tostring(turret) == "0" then return false end
    local ok, macro = pcall(GetComponentData, componentID(turret), "macro")
    return ok and macro ~= nil and SALVAGE_TURRET_MACROS[macro] == true
end

if Helper and Helper.getTurretModes and not Helper.sesNativeGetTurretModes then
    Helper.sesNativeGetTurretModes = Helper.getTurretModes
end

local function installMiningRelabel()
    if not Helper or not Helper.sesNativeGetTurretModes or Helper.sesSalvageTurretModesWrapped then return end
    local nativeGetTurretModes = Helper.sesNativeGetTurretModes
    Helper.getTurretModes = function(turret, ...)
        local options = nativeGetTurretModes(turret, ...)
        if turret ~= nil and betaEnabled() and isSalvageTurret(turret) then
            for _, option in ipairs(options) do
                if option.id == "mining" then
                    option.text = ReadText(1171361, 900)
                    option.mouseovertext = ReadText(1171361, 1242)
                end
            end
        end
        return options
    end
    Helper.sesSalvageTurretModesWrapped = true
end

local function createTurretRowDropdown(menu, isMap, context)
    local turret = type(context) == "table" and context.turret or nil
    if not turret or not betaEnabled() or not isControlledShip(context.ship) or not isSalvageTurret(turret) then
        return nil
    end
    local getModes = Helper.sesNativeGetTurretModes or Helper.getTurretModes
    local options = getModes(turret)
    for index, option in ipairs(options) do
        if option.id == "mining" then
            options[index] = {
                id = SALVAGE_MODE_ID, text = ReadText(1171361, 900), icon = "",
                displayremoveoption = false, mouseovertext = ReadText(1171361, 1242),
            }
        end
    end
    local cell = context.row[context.column]
    cell:setColSpan(context.colspan):createDropDown(options, {
        startOption = function()
            local mode = menu.getDropDownTurretModeOption(turret)
            return mode == "mining" and SALVAGE_MODE_ID or mode
        end,
    })
    cell.handlers.onDropDownConfirmed = function(_, mode)
        if isMap then menu.noupdate = false end
        C.SetWeaponMode(turret, mode == SALVAGE_MODE_ID and "mining" or mode)
    end
    return { handled = true }
end

local function request(ship, enabled, setmining)
    if not AddUITriggeredEvent or not ConvertStringToLuaID or not isControlledShip(ship) then return false end
    if setmining and not customAvailable(ship) then return false end
    -- Match vanilla ShipConfigurationMenu's positional list + LuaID bridge.
    -- Named Lua table fields are not carried by AddUITriggeredEvent.
    -- Wire v1: { version, ship component, enabled, setmining }.
    -- One event owns its payload; no shared blackboard slot can be overwritten.
    AddUITriggeredEvent("SES_TurretSalvage", "request", {
        1, ConvertStringToLuaID(tostring(ship)), enabled, setmining,
    })
    print("[SES][TURRET UI] Mode request sent. ship=" .. tostring(ship)
        .. " salvage=" .. tostring(enabled) .. " setmining=" .. tostring(setmining)
        .. " version=" .. version)
    return true
end

local function hasOtherProvider(menu, callback)
    for key in pairs((menu.uix_callbacks and menu.uix_callbacks[callback]) or {}) do
        if key ~= callbackID then
            if not loggedConflicts[menu.name] then
                print("[SES][TURRET UI] Existing All-turret dropdown provider on " .. tostring(menu.name)
                    .. "; leaving that control unchanged (" .. version .. ").")
                loggedConflicts[menu.name] = true
            end
            return true
        end
    end
    return false
end

local function createDropdown(menu, callback, row, ship, isMap)
    local column = isMap and 5 or 2
    if hasOtherProvider(menu, callback) then
        -- UIX's legacy dispatcher keeps the last callback return. Preserve a
        -- previously created provider widget instead of causing native redraw.
        return row[column].type == "dropdown" or nil
    end
    if not customAvailable(ship) then return nil end

    -- A real mining turret means this is not a tug-only ship. Match vanilla's
    -- forall=true list exactly; add custom entries only to this private copy.
    local options = Helper.getTurretModes(nil, true, not isMap and "docked_turretconfig_modes_dropdown_" or nil)
    local nativeModes = {}
    for _, option in ipairs(options) do nativeModes[option.id] = true end
    options[#options + 1] = {
        id = "ses_salvage", text = ReadText(1171361, 900), icon = "",
        displayremoveoption = false, mouseovertext = ReadText(1171361, 901),
    }
    local properties = {
        startOption = function()
            -- Like vanilla, All shows a mode only when every turret shares it:
            -- "Salvage" when all turrets are in mining mode and salvage is on;
            -- mixed modes (e.g. one turret on Salvage, one on Defend) stay blank.
            local allmode = menu.getDropDownTurretModeOption(ship, "all")
            if allmode == "mining" and isControlledShip(ship) and betaEnabled()
                and salvageEnabled(ship) then
                return "ses_salvage"
            end
            return allmode
        end,
    }
    if not isMap then
        properties.helpOverlayID = "docked_turretconfig_modes"
        properties.helpOverlayText = " "
        properties.helpOverlayHighlightOnly = true
        properties.uiTriggerID = "docked_turretconfig_modes"
    end
    local widget = row[column]:setColSpan(isMap and 9 or 5):createDropDown(options, properties)
    if not isMap then widget.properties.helpOverlayID = "docked_turretconfig_modes_dropdown" end
    widget.handlers.onDropDownConfirmed = function(_, mode)
        if isMap then menu.noupdate = false end
        if mode == "ses_salvage" then
            request(ship, true, true)
            return -- A custom identifier must never reach the native setter.
        end
        if nativeModes[mode] then
            request(ship, false, false)
            C.SetAllTurretModes(ship, mode)
        end
    end
    return true
end

local function findMenu(name)
    if Helper and Helper.getMenu then
        local ok, menu = pcall(Helper.getMenu, name)
        if ok and menu then return menu end
    end
    for _, menu in ipairs(Menus or {}) do if menu.name == name then return menu end end
end

local function register()
    for _, surface in ipairs({
        { name = "DockedMenu", callback = "sto_addTurretBehavioursDockMenu" },
        { name = "MapMenu", callback = "sto_addTurretBehavioursMapMenu", isMap = true },
    }) do
        local menu = findMenu(surface.name)
        if menu and menu.registerCallback and not menu.sesMiningTurretCallbacksRegistered
            and not hasOtherProvider(menu, surface.callback) then
            local callback, isMap = surface.callback, surface.isMap
            menu.registerCallback(callback, function(row, inputobject)
                -- DockedMenu.currentplayership is vanilla's occupied ship;
                -- createDropdown independently restricts it to the piloted ship.
                return createDropdown(menu, callback, row, isMap and inputobject or menu.currentplayership, isMap)
            end, callbackID)
            menu.sesMiningTurretCallbacksRegistered = true
        end
        -- Per-turret rows: the UIX hook when this UIX build has it, else the relabel.
        if menu and menu.registerCallback and not menu.sesPerTurretSalvageRegistered then
            local perTurret, isMap = PER_TURRET_CALLBACKS[surface.name], surface.isMap
            if type(menu.uix_isCallbackSupported) == "function" and menu.uix_isCallbackSupported(perTurret) then
                menu.registerCallback(perTurret, function(context)
                    return createTurretRowDropdown(menu, isMap, context)
                end, callbackID .. "_per_turret")
                print("[SES][TURRET UI] Per-turret Salvage uses UIX callback " .. perTurret .. " (" .. version .. ").")
            else
                installMiningRelabel()
                print("[SES][TURRET UI] UIX has no " .. tostring(perTurret) .. "; per-turret Mining is shown as Salvage (" .. version .. ").")
            end
            menu.sesPerTurretSalvageRegistered = true
        end
    end
end

register()
if Register_OnLoad_Init then Register_OnLoad_Init(register, "SES mining turret callbacks") end
if Helper and Helper.addDelayedOneTimeCallbackOnUpdate and getElapsedTime then
    Helper.addDelayedOneTimeCallbackOnUpdate(register, true, getElapsedTime() + 1)
    Helper.addDelayedOneTimeCallbackOnUpdate(register, true, getElapsedTime() + 3)
end

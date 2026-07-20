-- Ship Equipment Salvaging
-- Kuertee UI Extensions-compatible SES Tool Mode row for the spacesuit
-- Weapon Configuration panel. This file is loaded through the SES ui.xml addon
-- path and registers against Kuertee's official DockedMenu callback. This
-- intentionally leaves the Bomb Launcher
-- ammunition dropdown untouched. The dropdown selects SES behaviour only; it
-- does not replace the visible Hand Laser projectile/beam.

local ffi = require("ffi")
local C = ffi.C
local sesUnpack = table.unpack or unpack

pcall(ffi.cdef, [[
	typedef uint64_t UniverseID;
	UniverseID GetPlayerOccupiedShipID(void);
	bool IsComponentClass(UniverseID componentid, const char* classname);
	const char* GetUserData(const char* name);
	void SetUserData(const char* name, const char* value);
]])

pcall(ffi.cdef, [[
	typedef struct {
		bool primary;
		uint32_t idx;
	} UIWeaponGroup;
]])

pcall(ffi.cdef, [[
	const char* GetComponentName(UniverseID componentid);
	uint32_t GetDefensibleActiveWeaponGroup(UniverseID defensibleid, bool primary);
	size_t GetNumUpgradeSlots(UniverseID destructibleid, const char* macroname, const char* upgradetypename);
	UniverseID GetUpgradeSlotCurrentComponent(UniverseID destructibleid, const char* upgradetypename, size_t slot);
	uint32_t GetNumWeaponGroupsByWeapon(UniverseID defensibleid, UniverseID weaponid);
	uint32_t GetWeaponGroupsByWeapon(UIWeaponGroup* result, uint32_t resultlen, UniverseID defensibleid, UniverseID weaponid);
	const char* GetWeaponMode(UniverseID weaponid);
	bool IsWeaponArmed(UniverseID weaponid);
	void SetDefensibleActiveWeaponGroup(UniverseID defensibleid, bool primary, uint32_t groupidx);
	void SetWeaponArmed(UniverseID weaponid, bool arm);
	void SetWeaponGroup(UniverseID defensibleid, UniverseID weaponid, bool primary, uint32_t groupidx, bool value);
]])

local ses = {
	version = "v368-md-localization-resolution",
	userdatakey = "ses_tool_mode",
	controlid = "ses_tool_mode",
	rowid = "ses_tool_mode_row",
	patchid = "ship_equipment_salvaging",
}

local sesTools = {
	salvage = {
		ware = "ses_equipment_salvager",
		macro = "ses_equipment_salvager_macro",
		label = "Avarice Beam Regulator",
		secondarygroup = 1,
	},
	install = {
		ware = "ses_equipment_welder",
		macro = "ses_equipment_welder_macro",
		label = "Avarice Bonding Regulator",
		secondarygroup = 2,
	},
}

local function sesLog(message)
	print("[SES][MODE UI] " .. tostring(message))
end

local function emit(control, param)
	if AddUITriggeredEvent then
		pcall(AddUITriggeredEvent, "SES_Tool_Mode_UI", control, param or ses.version)
	end
end

local function emitMode(mode)
	if AddUITriggeredEvent then
		pcall(AddUITriggeredEvent, "MapMenu", ses.controlid, mode)
	end
end

local function getStoredMode()
	local mode = ""
	if C.GetUserData then
		local rawmode = C.GetUserData(ses.userdatakey)
		if rawmode ~= nil then
			mode = ffi.string(rawmode)
		end
	end

	if mode == "salvage" or mode == "install" or mode == "off" then
		return mode
	end
	return "off"
end

local function setStoredMode(mode)
	if mode ~= "salvage" and mode ~= "install" and mode ~= "off" then
		mode = "off"
	end
	C.SetUserData(ses.userdatakey, mode)
	return mode
end

local toUniverseID
local getInventoryAmount
local getWeaponContext
local forceOffIfHandLaserMissing
local deactivateSESToolWeapons
local refreshToolModeMenu

local toolInventoryState = {
	source = "unknown",
	salvager = nil,
	welder = nil,
}

local function safeString(value)
	local ok, result = pcall(tostring, value)
	if ok then
		return result
	end
	return "<tostring failed>"
end

local SES_TEXT_PAGE = 1171361

local function sesText(id, fallback)
	if ReadText then
		local ok, value = pcall(ReadText, SES_TEXT_PAGE, id)
		if ok and value and value ~= "" then
			return value
		end
	end
	return fallback or ""
end

local function sesFormat(id, fallback, ...)
	local ok, value = pcall(string.format, sesText(id, fallback), ...)
	if ok then
		return value
	end
	local fallbackOK, fallbackValue = pcall(string.format, fallback or "", ...)
	return fallbackOK and fallbackValue or (fallback or "")
end

local function numericAmount(value)
	local amount = tonumber(value)
	if amount == nil then
		return nil
	end
	return amount
end

local function normalizeWareID(value)
	if value == nil then
		return ""
	end
	local text = safeString(value)
	if text:sub(1, 5) == "ware." then
		text = text:sub(6)
	end
	return text
end

local function wareMatches(value, ware)
	return normalizeWareID(value) == ware
end

local function toolStateKeyForWare(ware)
	if ware == "ses_equipment_salvager" then
		return "salvager"
	elseif ware == "ses_equipment_welder" then
		return "welder"
	end
	return nil
end

local function amountFromInventoryEntry(entry)
	if type(entry) == "table" then
		return numericAmount(entry.amount or entry.count)
	elseif type(entry) == "number" or type(entry) == "string" then
		return numericAmount(entry)
	end
	return nil
end

local function publishedToolAmount(ware)
	local key = toolStateKeyForWare(ware)
	if key and toolInventoryState[key] ~= nil then
		return toolInventoryState[key]
	end
	return nil
end

local function updatePublishedToolInventory(param, source)
	local text = safeString(param or "")
	local salvagerText, welderText = string.match(text, "^%s*([^;]+)%s*;%s*([^;]+)%s*$")
	local salvagerAmount = numericAmount(salvagerText)
	local welderAmount = numericAmount(welderText)
	if salvagerAmount == nil or welderAmount == nil then
		emit("inventory_state_rejected", "source=" .. safeString(source)
			.. ", param=" .. text)
		return false
	end

	toolInventoryState.source = safeString(source or "md")
	toolInventoryState.salvager = salvagerAmount
	toolInventoryState.welder = welderAmount
	emit("inventory_state_received", "source=" .. toolInventoryState.source
		.. ", salvager=" .. tostring(salvagerAmount)
		.. ", welder=" .. tostring(welderAmount))
	return true
end

local function onPublishedToolInventory(_, param)
	updatePublishedToolInventory(param, "md_event")
end

local function updatePublishedToolMode(param, source)
	local mode = safeString(param or "off")
	if mode ~= "salvage" and mode ~= "install" and mode ~= "off" then
		mode = "off"
	end
	local previousMode = getStoredMode()
	setStoredMode(mode)
	emit("mode_state_received", "source=" .. safeString(source or "md")
		.. ", mode=" .. mode
		.. ", version=" .. ses.version)
	if previousMode ~= mode and refreshToolModeMenu then
		refreshToolModeMenu(mode)
	end
	return true
end

local function onPublishedToolMode(_, param)
	updatePublishedToolMode(param, "md_event")
end

local function requestPublishedToolInventory(source)
	emit("inventory_state_request", "source=" .. safeString(source or "unknown")
		.. ", version=" .. ses.version)
end

local function requestPublishedToolMode(source)
	emit("mode_state_request", "source=" .. safeString(source or "unknown")
		.. ", version=" .. ses.version)
end

local function registerToolInventoryEvent()
	if RegisterEvent and not (_G and _G.__ses_tool_inventory_event_registered) then
		local ok, err = pcall(RegisterEvent, "SES.ToolInventory", onPublishedToolInventory)
		if ok then
			if _G then
				_G.__ses_tool_inventory_event_registered = true
			end
			emit("inventory_event_registered", ses.version)
		else
			emit("inventory_event_register_failed", safeString(err))
		end
	end
end

local function registerToolModeEvent()
	if RegisterEvent and not (_G and _G.__ses_tool_mode_event_registered) then
		local ok, err = pcall(RegisterEvent, "SES.ToolMode", onPublishedToolMode)
		if ok then
			if _G then
				_G.__ses_tool_mode_event_registered = true
			end
			emit("mode_event_registered", ses.version)
		else
			emit("mode_event_register_failed", safeString(err))
		end
	end
end

local function ffiString(rawvalue)
	if rawvalue == nil then
		return ""
	end
	local ok, result = pcall(ffi.string, rawvalue)
	if ok then
		return result
	end
	return ""
end

local function safeC(label, fallback, fn)
	local ok, result = pcall(fn)
	if ok then
		return result
	end
	emit("weapon_diag_error", label .. "=" .. safeString(result))
	return fallback
end

local function componentData(componentid, ...)
	if not GetComponentData then
		return nil
	end

	local args = { ... }
	local converted = toUniverseID(componentid)
	local ok, value1, value2, value3, value4

	if converted ~= 0 then
		ok, value1, value2, value3, value4 = pcall(function()
			return GetComponentData(converted, sesUnpack(args))
		end)
		if ok and value1 ~= nil then
			return value1, value2, value3, value4
		end
		if not ok then
			emit("weapon_diag_error", "getcomponentdata_converted=" .. safeString(value1))
		end
	end

	ok, value1, value2, value3, value4 = pcall(function()
		return GetComponentData(componentid, sesUnpack(args))
	end)
	if ok then
		return value1, value2, value3, value4
	end
	emit("weapon_diag_error", "getcomponentdata=" .. safeString(value1))

	return nil
end

local function bool01(value)
	return value and "1" or "0"
end

local function groupString(groups, primary)
	local result = {}
	for _, groupinfo in ipairs(groups) do
		if groupinfo.primary == primary then
			table.insert(result, tostring(groupinfo.idx))
		end
	end
	if #result == 0 then
		return "-"
	end
	return table.concat(result, "|")
end

local function collectWeaponGroups(shipid, weaponid, label)
	local groups = {}
	local numgroups = safeC("getnumgroups" .. tostring(label), 0, function()
		return tonumber(C.GetNumWeaponGroupsByWeapon(shipid, weaponid))
	end)
	if numgroups > 0 then
		local rawgroups = ffi.new("UIWeaponGroup[?]", numgroups)
		local actualgroups = safeC("getgroups" .. tostring(label), 0, function()
			return tonumber(C.GetWeaponGroupsByWeapon(rawgroups, numgroups, shipid, weaponid))
		end)
		for groupidx = 0, actualgroups - 1 do
			table.insert(groups, {
				primary = rawgroups[groupidx].primary,
				idx = tonumber(rawgroups[groupidx].idx),
			})
		end
	end
	return groups
end

local function diagnoseMountedWeapons(source, defensibleid)
	if defensibleid == nil or safeString(defensibleid) == "nil" then
		emit("weapon_list_unavailable", "source=" .. safeString(source) .. ", reason=no_defensible")
		return
	end

	local shipid = defensibleid
	local converted = toUniverseID(defensibleid)
	if converted ~= 0 then
		shipid = converted
	end

	local numslots = safeC("getnumupgradeslots", nil, function()
		return tonumber(C.GetNumUpgradeSlots(shipid, "", "weapon"))
	end)
	if numslots == nil then
		emit("weapon_list_unavailable", "source=" .. safeString(source)
			.. ", defensible=" .. safeString(shipid)
			.. ", reason=no_weapon_slot_api")
		return
	end

	local activePrimary = safeC("active_primary", -1, function()
		return tonumber(C.GetDefensibleActiveWeaponGroup(shipid, true))
	end)
	local activeSecondary = safeC("active_secondary", -1, function()
		return tonumber(C.GetDefensibleActiveWeaponGroup(shipid, false))
	end)

	local weaponcount = 0
	local hasSalvager = false
	local hasWelder = false

	for slot = 1, numslots do
		local weaponid = safeC("getslotcomponent" .. tostring(slot), 0, function()
			return C.GetUpgradeSlotCurrentComponent(shipid, "weapon", slot)
		end)
		if weaponid ~= 0 then
			local weaponcomponentid = toUniverseID(weaponid)
			if weaponcomponentid == 0 then
				weaponcomponentid = weaponid
			end
			weaponcount = weaponcount + 1
			local name = ffiString(safeC("getcomponentname" .. tostring(slot), nil, function()
				return C.GetComponentName(weaponcomponentid)
			end))
			local macro, classid = componentData(weaponcomponentid, "macro", "classid")
			macro = safeString(macro or "")
			classid = safeString(classid or "")
			local mode = ffiString(safeC("getweaponmode" .. tostring(slot), nil, function()
				return C.GetWeaponMode(weaponcomponentid)
			end))
			local armed = safeC("isweaponarmed" .. tostring(slot), false, function()
				return C.IsWeaponArmed(weaponcomponentid)
			end)
			local isWeapon = safeC("isweaponclass" .. tostring(slot), false, function()
				return C.IsComponentClass(weaponcomponentid, "weapon")
			end)
			local isMissile = safeC("ismissileclass" .. tostring(slot), false, function()
				return C.IsComponentClass(weaponcomponentid, "missilelauncher")
			end)
			local groups = collectWeaponGroups(shipid, weaponcomponentid, tostring(slot))

			local isSalvager = macro == "ses_equipment_salvager_macro"
			local isWelder = macro == "ses_equipment_welder_macro"
			hasSalvager = hasSalvager or isSalvager
			hasWelder = hasWelder or isWelder

			emit("weapon_list_item", "source=" .. safeString(source)
				.. ", slot=" .. tostring(slot)
				.. ", index=" .. tostring(weaponcount)
				.. ", weaponid=" .. safeString(weaponcomponentid)
				.. ", name=" .. name
				.. ", macro=" .. macro
				.. ", classid=" .. classid
				.. ", mode=" .. mode
				.. ", armed=" .. bool01(armed)
				.. ", weaponclass=" .. bool01(isWeapon)
				.. ", missileclass=" .. bool01(isMissile)
				.. ", primarygroups=" .. groupString(groups, true)
				.. ", secondarygroups=" .. groupString(groups, false)
				.. ", salvager=" .. bool01(isSalvager)
				.. ", welder=" .. bool01(isWelder))
		end
	end

	emit("weapon_list_summary", "source=" .. safeString(source)
		.. ", defensible=" .. safeString(shipid)
		.. ", slots=" .. tostring(numslots)
		.. ", weapons=" .. tostring(weaponcount)
		.. ", activeprimary=" .. tostring(activePrimary)
		.. ", activesecondary=" .. tostring(activeSecondary)
		.. ", hassalvager=" .. bool01(hasSalvager)
		.. ", haswelder=" .. bool01(hasWelder)
		.. ", inventorysalvager=" .. safeString(getInventoryAmount("ses_equipment_salvager"))
		.. ", inventorywelder=" .. safeString(getInventoryAmount("ses_equipment_welder")))
end

local function objectDebug(inputobject, mode, instance)
	local objectid = 0
	local occupied = 0
	local occupiedMatch = false
	local spacesuitClass = false
	local macro = ""

	pcall(function()
		objectid = toUniverseID(inputobject)
	end)
	pcall(function()
		occupied = C.GetPlayerOccupiedShipID()
	end)
	pcall(function()
		occupiedMatch = (inputobject == occupied) or (objectid ~= 0 and objectid == occupied)
	end)
	pcall(function()
		if objectid ~= 0 then
			spacesuitClass = C.IsComponentClass(objectid, "spacesuit")
		else
			spacesuitClass = C.IsComponentClass(inputobject, "spacesuit")
		end
	end)
	pcall(function()
		if GetComponentData then
			macro = safeString(componentData(inputobject, "macro") or "")
		end
	end)

	return "mode=" .. safeString(mode)
		.. ", instance=" .. safeString(instance)
		.. ", input=" .. safeString(inputobject)
		.. ", objectid=" .. safeString(objectid)
		.. ", occupied=" .. safeString(occupied)
		.. ", occupiedmatch=" .. safeString(occupiedMatch)
		.. ", spacesuitclass=" .. safeString(spacesuitClass)
		.. ", macro=" .. macro
end

function getInventoryAmount(ware)
	if GetPlayerInventory then
		local ok, inventory = pcall(GetPlayerInventory)
		if ok and type(inventory) == "table" then
			local direct = amountFromInventoryEntry(inventory[ware])
			if direct ~= nil then
				return direct
			end
			direct = amountFromInventoryEntry(inventory["ware." .. ware])
			if direct ~= nil then
				return direct
			end

			for key, entry in pairs(inventory) do
				if wareMatches(key, ware) then
					local amount = amountFromInventoryEntry(entry)
					if amount ~= nil then
						return amount
					end
				elseif type(entry) == "table" and (wareMatches(entry.ware, ware) or wareMatches(entry.id, ware)) then
					local amount = amountFromInventoryEntry(entry)
					if amount ~= nil then
						return amount
					end
				end
			end

			return 0
		end
	end

	return publishedToolAmount(ware)
end

local function inventoryAllows(ware)
	local amount = getInventoryAmount(ware)
	if amount == nil then
		requestPublishedToolInventory("inventory_unknown_" .. safeString(ware))
		return false, nil
	end
	return amount > 0, amount
end

local function modeInventoryAllowed(mode)
	local tool = sesTools[mode]
	if not tool then
		return true, nil, nil
	end
	local allowed, amount = inventoryAllows(tool.ware)
	return allowed, amount, tool
end

local function getToolAvailability(context)
	local hasSalvager, salvagerAmount = inventoryAllows("ses_equipment_salvager")
	local hasWelder, welderAmount = inventoryAllows("ses_equipment_welder")
	local hasHandLaser = context and context.hasHandLaser
	local inventoryKnown = (salvagerAmount ~= nil) and (welderAmount ~= nil)
	local hasAnyTool = hasSalvager or hasWelder
	return {
		hasSalvager = hasSalvager,
		salvagerAmount = salvagerAmount,
		hasWelder = hasWelder,
		welderAmount = welderAmount,
		hasHandLaser = hasHandLaser,
		inventoryKnown = inventoryKnown,
		hasAnyTool = hasAnyTool,
		showRow = hasAnyTool or not inventoryKnown,
	}
end

local function getModeOptions(context, availability)
	local state = availability or getToolAvailability(context)
	local handLaserRequirement = "Requires the Hand Laser to be mounted on the current spacesuit weapon list."
	local options = {
		{ id = "off", text = sesText(200, "Off"), icon = "", displayremoveoption = false },
	}

	local salvagerText = sesText(10, "Avarice Beam Regulator")
	if state.salvagerAmount == nil then
		salvagerText = sesText(10, "Avarice Beam Regulator")
	elseif state.salvagerAmount <= 0 then
		salvagerText = sesFormat(205, "%s (not in inventory)", sesText(10, "Avarice Beam Regulator"))
	elseif not state.hasHandLaser then
		salvagerText = sesFormat(206, "%s (requires Hand Laser)", sesText(10, "Avarice Beam Regulator"))
	end

	local welderText = sesText(20, "Avarice Bonding Regulator")
	if state.welderAmount == nil then
		welderText = sesText(20, "Avarice Bonding Regulator")
	elseif state.welderAmount <= 0 then
		welderText = sesFormat(205, "%s (not in inventory)", sesText(20, "Avarice Bonding Regulator"))
	elseif not state.hasHandLaser then
		welderText = sesFormat(206, "%s (requires Hand Laser)", sesText(20, "Avarice Bonding Regulator"))
	end

	if state.hasSalvager and state.hasHandLaser then
		options[#options + 1] = {
			id = "salvage",
			text = salvagerText,
			icon = "",
			displayremoveoption = false,
			mouseOverText = sesText(203, "Hand Laser hits open the SES salvage flow when close enough; transactions are limited to 25 m."),
		}
	elseif state.hasSalvager and not state.hasHandLaser then
		emit("option_hidden_no_handlaser", "mode=salvage, amount=" .. safeString(state.salvagerAmount)
			.. ", reason=" .. handLaserRequirement)
	elseif state.salvagerAmount ~= nil and state.salvagerAmount <= 0 then
		emit("option_hidden_no_toolware", "mode=salvage, amount=" .. safeString(state.salvagerAmount))
	end

	if state.hasWelder and state.hasHandLaser then
		options[#options + 1] = {
			id = "install",
			text = welderText,
			icon = "",
			displayremoveoption = false,
			mouseOverText = sesText(204, "Hand Laser hits open the SES installation flow on valid nearby player-owned S/M ships; transactions are limited to 25 m."),
		}
	elseif state.hasWelder and not state.hasHandLaser then
		emit("option_hidden_no_handlaser", "mode=install, amount=" .. safeString(state.welderAmount)
			.. ", reason=" .. handLaserRequirement)
	elseif state.welderAmount ~= nil and state.welderAmount <= 0 then
		emit("option_hidden_no_toolware", "mode=install, amount=" .. safeString(state.welderAmount))
	end

	return options, state
end

local function optionExists(options, optionid)
	for _, option in ipairs(options or {}) do
		if option and option.id == optionid then
			return true
		end
	end
	return false
end

local function normalizeStartModeForOptions(mode, options, source)
	if optionExists(options, mode) then
		return mode
	end
	if mode ~= "off" then
		setStoredMode("off")
		emit("mode_forced_off_option_hidden", "source=" .. safeString(source)
			.. ", previous=" .. safeString(mode))
		emitMode("off")
	end
	return "off"
end

function toUniverseID(value)
	if value == nil then
		return 0
	end
	if not ConvertStringTo64Bit then
		return 0
	end
	return ConvertStringTo64Bit(tostring(value))
end

local function looksLikePlayerSpacesuit(inputobject)
	if (not C.GetPlayerOccupiedShipID) or (not C.IsComponentClass) then
		return false
	end

	local objectid = toUniverseID(inputobject)
	if objectid == 0 then
		return false
	end

	if objectid ~= C.GetPlayerOccupiedShipID() then
		return false
	end

	if C.IsComponentClass(objectid, "spacesuit") then
		return true
	end

	if GetComponentData then
		local macro = GetComponentData(objectid, "macro")
		if macro and string.find(tostring(macro), "spacesuit") then
			return true
		end
	end

	return false
end

local function isHandLaserMacro(macro)
	return macro == "spacesuit_gen_laser_01_macro"
end

local function isDefaultSuitToolMacro(macro)
	return macro == "spacesuit_gen_laser_01_macro"
end

function getWeaponContext(defensibleid, source)
	local context = {
		source = source or "unknown",
		shipid = nil,
		slots = 0,
		weapons = {},
		hasHandLaser = false,
		hasSalvager = false,
		hasWelder = false,
		handLaserGroup = nil,
		fallbackPrimaryGroup = nil,
	}

	if defensibleid == nil or safeString(defensibleid) == "nil" then
		context.reason = "no_defensible"
		return context
	end

	local shipid = toUniverseID(defensibleid)
	if shipid == 0 then
		shipid = defensibleid
	end
	context.shipid = shipid

	local numslots = safeC("context_getnumupgradeslots" .. safeString(source), nil, function()
		return tonumber(C.GetNumUpgradeSlots(shipid, "", "weapon"))
	end)
	if numslots == nil then
		context.reason = "no_weapon_slot_api"
		return context
	end
	context.slots = numslots

	for slot = 1, numslots do
		local weaponid = safeC("context_getslotcomponent" .. tostring(slot), 0, function()
			return C.GetUpgradeSlotCurrentComponent(shipid, "weapon", slot)
		end)
		local weaponcomponentid = toUniverseID(weaponid)
		if weaponcomponentid == 0 then
			weaponcomponentid = weaponid
		end
		if weaponcomponentid ~= 0 and safeString(weaponcomponentid) ~= "nil" then
			local name = ffiString(safeC("context_getcomponentname" .. tostring(slot), nil, function()
				return C.GetComponentName(weaponcomponentid)
			end))
			local macro = componentData(weaponcomponentid, "macro")
			macro = safeString(macro or "")
			local groups = collectWeaponGroups(shipid, weaponcomponentid, "context" .. tostring(slot))
			local weaponinfo = {
				slot = slot,
				weaponid = weaponcomponentid,
				name = name,
				macro = macro,
				groups = groups,
			}
			table.insert(context.weapons, weaponinfo)

			if isHandLaserMacro(macro) then
				context.hasHandLaser = true
				for _, groupinfo in ipairs(groups) do
					if groupinfo.primary and not context.handLaserGroup then
						context.handLaserGroup = tonumber(groupinfo.idx)
					end
				end
			elseif macro == "ses_equipment_salvager_macro" then
				context.hasSalvager = true
			elseif macro == "ses_equipment_welder_macro" then
				context.hasWelder = true
			elseif not context.fallbackPrimaryGroup then
				for _, groupinfo in ipairs(groups) do
					if groupinfo.primary then
						context.fallbackPrimaryGroup = tonumber(groupinfo.idx)
						break
					end
				end
			end
		end
	end

	return context
end

function deactivateSESToolWeapons(context, source)
	if not (context and context.shipid and context.weapons) then
		return
	end

	local changed = 0
	for _, weaponinfo in ipairs(context.weapons) do
		if weaponinfo.macro == "ses_equipment_salvager_macro" or weaponinfo.macro == "ses_equipment_welder_macro" then
			for group = 1, 4 do
				safeC("deactivate_ses_primary" .. tostring(group), false, function()
					C.SetWeaponGroup(context.shipid, weaponinfo.weaponid, true, group, false)
					return true
				end)
				safeC("deactivate_ses_secondary" .. tostring(group), false, function()
					C.SetWeaponGroup(context.shipid, weaponinfo.weaponid, false, group, false)
					return true
				end)
			end
			safeC("deactivate_ses_armed", false, function()
				C.SetWeaponArmed(weaponinfo.weaponid, false)
				return true
			end)
			changed = changed + 1
		end
	end

	local fallback = context.handLaserGroup or context.fallbackPrimaryGroup
	if fallback then
		safeC("deactivate_ses_setactiveprimary", false, function()
			C.SetDefensibleActiveWeaponGroup(context.shipid, true, fallback)
			return true
		end)
	end

	if changed > 0 then
		emit("ses_tool_groups_cleared", "source=" .. safeString(source)
			.. ", defensible=" .. safeString(context.shipid)
			.. ", tools=" .. tostring(changed)
			.. ", fallbackprimary=" .. safeString(fallback)
			.. ", handlaser=" .. bool01(context.hasHandLaser))
	end
end

function forceOffIfHandLaserMissing(context, source)
	local mode = getStoredMode()
	if mode ~= "off" then
		local toolAllowed, toolAmount, tool = modeInventoryAllowed(mode)
		if not toolAllowed then
			setStoredMode("off")
			emit("mode_forced_off_no_toolware", "source=" .. safeString(source)
				.. ", previous=" .. safeString(mode)
				.. ", ware=" .. safeString(tool and tool.ware)
				.. ", amount=" .. safeString(toolAmount)
				.. ", handlaser=" .. bool01(context and context.hasHandLaser))
			emitMode("off")
			deactivateSESToolWeapons(context, source)
			return "off"
		end
	end
	if mode ~= "off" and not (context and context.hasHandLaser) then
		setStoredMode("off")
		emit("mode_forced_off_no_handlaser", "source=" .. safeString(source)
			.. ", previous=" .. safeString(mode)
			.. ", slots=" .. safeString(context and context.slots)
			.. ", handlaser=0")
		emitMode("off")
		deactivateSESToolWeapons(context, source)
		return "off"
	end
	return mode
end

local function activeMountProbe(mode, source)
	local tool = sesTools[mode]
	if not tool then
		emit("active_mount_probe_skipped", "source=" .. safeString(source)
			.. ", mode=" .. safeString(mode)
			.. ", reason=no_tool_mode")
		return
	end

	local rawshipid = safeC("active_mount_getoccupied", 0, function()
		return C.GetPlayerOccupiedShipID()
	end)
	local shipid = toUniverseID(rawshipid)
	if shipid == 0 then
		shipid = rawshipid
	end
	if shipid == 0 or safeString(shipid) == "nil" then
		emit("active_mount_probe_result", "source=" .. safeString(source)
			.. ", mode=" .. safeString(mode)
			.. ", tool=" .. tool.label
			.. ", result=failed"
			.. ", reason=no_player_spacesuit")
		return
	end

	local numslots = safeC("active_mount_getnumupgradeslots", nil, function()
		return tonumber(C.GetNumUpgradeSlots(shipid, "", "weapon"))
	end)
	if numslots == nil then
		emit("active_mount_probe_result", "source=" .. safeString(source)
			.. ", mode=" .. safeString(mode)
			.. ", defensible=" .. safeString(shipid)
			.. ", tool=" .. tool.label
			.. ", result=failed"
			.. ", reason=no_weapon_slot_api")
		return
	end

	local activePrimaryBefore = safeC("active_mount_primary_before", -1, function()
		return tonumber(C.GetDefensibleActiveWeaponGroup(shipid, true))
	end)
	local activeSecondaryBefore = safeC("active_mount_secondary_before", -1, function()
		return tonumber(C.GetDefensibleActiveWeaponGroup(shipid, false))
	end)
	local inventoryAmount = getInventoryAmount(tool.ware)
	local candidates = 0
	local matching = nil

	emit("active_mount_probe_start", "source=" .. safeString(source)
		.. ", mode=" .. safeString(mode)
		.. ", defensible=" .. safeString(shipid)
		.. ", tool=" .. tool.label
		.. ", ware=" .. tool.ware
		.. ", macro=" .. tool.macro
		.. ", targetsecondarygroup=" .. tostring(tool.secondarygroup)
		.. ", slots=" .. tostring(numslots)
		.. ", activeprimarybefore=" .. tostring(activePrimaryBefore)
		.. ", activesecondarybefore=" .. tostring(activeSecondaryBefore)
		.. ", inventoryamount=" .. safeString(inventoryAmount))

	for slot = 1, numslots do
		local weaponid = safeC("active_mount_getslotcomponent" .. tostring(slot), 0, function()
			return C.GetUpgradeSlotCurrentComponent(shipid, "weapon", slot)
		end)
		local weaponcomponentid = toUniverseID(weaponid)
		if weaponcomponentid == 0 then
			weaponcomponentid = weaponid
		end
		if weaponcomponentid ~= 0 and safeString(weaponcomponentid) ~= "nil" then
			candidates = candidates + 1
			local name = ffiString(safeC("active_mount_getcomponentname" .. tostring(slot), nil, function()
				return C.GetComponentName(weaponcomponentid)
			end))
			local macro, classid = componentData(weaponcomponentid, "macro", "classid")
			macro = safeString(macro or "")
			classid = safeString(classid or "")
			local modeText = ffiString(safeC("active_mount_getweaponmode" .. tostring(slot), nil, function()
				return C.GetWeaponMode(weaponcomponentid)
			end))
			local armed = safeC("active_mount_isweaponarmed" .. tostring(slot), false, function()
				return C.IsWeaponArmed(weaponcomponentid)
			end)
			local groups = collectWeaponGroups(shipid, weaponcomponentid, "active" .. tostring(slot))
			local matches = macro == tool.macro

			emit("active_mount_probe_candidate", "source=" .. safeString(source)
				.. ", mode=" .. safeString(mode)
				.. ", slot=" .. tostring(slot)
				.. ", weaponid=" .. safeString(weaponcomponentid)
				.. ", name=" .. name
				.. ", macro=" .. macro
				.. ", classid=" .. classid
				.. ", weaponmode=" .. modeText
				.. ", armed=" .. bool01(armed)
				.. ", primarygroups=" .. groupString(groups, true)
				.. ", secondarygroups=" .. groupString(groups, false)
				.. ", matches=" .. bool01(matches))

			if matches and not matching then
				matching = {
					slot = slot,
					weaponid = weaponcomponentid,
					macro = macro,
					groups = groups,
				}
			end
		end
	end

	if not matching then
		emit("active_mount_probe_result", "source=" .. safeString(source)
			.. ", mode=" .. safeString(mode)
			.. ", defensible=" .. safeString(shipid)
			.. ", tool=" .. tool.label
			.. ", ware=" .. tool.ware
			.. ", macro=" .. tool.macro
			.. ", result=not_mounted"
			.. ", reason=inventory_only_no_mounted_component"
			.. ", candidates=" .. tostring(candidates)
			.. ", slots=" .. tostring(numslots)
			.. ", inventoryamount=" .. safeString(inventoryAmount)
			.. ", activeprimarybefore=" .. tostring(activePrimaryBefore)
			.. ", activesecondarybefore=" .. tostring(activeSecondaryBefore))
		return
	end

	local activePrimaryAfter = safeC("active_mount_primary_after", -1, function()
		return tonumber(C.GetDefensibleActiveWeaponGroup(shipid, true))
	end)
	local activeSecondaryAfter = safeC("active_mount_secondary_after", -1, function()
		return tonumber(C.GetDefensibleActiveWeaponGroup(shipid, false))
	end)
	local groupsAfter = collectWeaponGroups(shipid, matching.weaponid, "active_after")
	local armedAfter = safeC("active_mount_isarmed_after", false, function()
		return C.IsWeaponArmed(matching.weaponid)
	end)

	emit("active_mount_probe_result", "source=" .. safeString(source)
		.. ", mode=" .. safeString(mode)
		.. ", defensible=" .. safeString(shipid)
		.. ", tool=" .. tool.label
		.. ", ware=" .. tool.ware
		.. ", macro=" .. tool.macro
		.. ", result=mounted_detected_no_activation"
		.. ", reason=handlaser_mode_required"
		.. ", slot=" .. tostring(matching.slot)
		.. ", weaponid=" .. safeString(matching.weaponid)
		.. ", targetsecondarygroup=" .. tostring(tool.secondarygroup)
		.. ", armedafter=" .. bool01(armedAfter)
		.. ", activeprimarybefore=" .. tostring(activePrimaryBefore)
		.. ", activeprimaryafter=" .. tostring(activePrimaryAfter)
		.. ", activesecondarybefore=" .. tostring(activeSecondaryBefore)
		.. ", activesecondaryafter=" .. tostring(activeSecondaryAfter)
		.. ", primarygroupsafter=" .. groupString(groupsAfter, true)
		.. ", secondarygroupsafter=" .. groupString(groupsAfter, false))
end

local function addModeRow(rowgroup, defensibleid, source)
	requestPublishedToolMode(source or "map_row")
	local context = getWeaponContext(defensibleid, source or "map_row")
	local startMode = forceOffIfHandLaserMissing(context, source or "map_row")
	local options, availability = getModeOptions(context)
	if not availability.showRow then
		setStoredMode("off")
		emit("row_hidden_no_tools", "source=" .. safeString(source or "map_row")
			.. ", salvager=" .. safeString(availability.salvagerAmount)
			.. ", welder=" .. safeString(availability.welderAmount)
			.. ", inventoryknown=" .. bool01(availability.inventoryKnown)
			.. ", handlaser=" .. bool01(availability.hasHandLaser))
		emitMode("off")
		deactivateSESToolWeapons(context, source or "map_row")
		return nil
	end
	startMode = normalizeStartModeForOptions(startMode, options, source or "map_row")
	if #options <= 1 then
		emit("row_visible_off_only", "source=" .. safeString(source or "map_row")
			.. ", salvager=" .. safeString(availability.salvagerAmount)
			.. ", welder=" .. safeString(availability.welderAmount)
			.. ", inventoryknown=" .. bool01(availability.inventoryKnown)
			.. ", handlaser=" .. bool01(availability.hasHandLaser))
	end
	local row = rowgroup:addRow(ses.rowid, {})
	row[1]:setColSpan(2):createText("    " .. sesText(201, "SES Tool Mode:"))
	row[3]:setColSpan(11):createDropDown(options, {
		startOption = startMode,
		active = true,
		mouseOverText = sesText(202, "Select what the mounted Hand Laser should do for Ship Equipment Salvaging. Only modes with the matching SES tool in inventory and a mounted Hand Laser are shown."),
		uiTriggerID = ses.controlid,
	})
	if row[3].properties then
		row[3].properties.uiTriggerID = ses.controlid
	end
	row[3].handlers.onDropDownConfirmed = function(_, mode)
		local latestContext = getWeaponContext(defensibleid, source or "map_dropdown")
		local toolAllowed, toolAmount, tool = modeInventoryAllowed(mode)
		if mode ~= "off" and not toolAllowed then
			setStoredMode("off")
			emit("selection_rejected_no_toolware", "source=" .. safeString(source or "map_dropdown")
				.. ", requested=" .. safeString(mode)
				.. ", ware=" .. safeString(tool and tool.ware)
				.. ", amount=" .. safeString(toolAmount)
				.. ", handlaser=" .. bool01(latestContext.hasHandLaser))
			emitMode("off")
			deactivateSESToolWeapons(latestContext, source or "map_dropdown")
			return
		end
		if mode ~= "off" and not latestContext.hasHandLaser then
			setStoredMode("off")
			emit("selection_rejected_no_handlaser", "source=" .. safeString(source or "map_dropdown")
				.. ", requested=" .. safeString(mode)
				.. ", slots=" .. safeString(latestContext.slots))
			emitMode("off")
			deactivateSESToolWeapons(latestContext, source or "map_dropdown")
			return
		end
		local storedMode = setStoredMode(mode)
		sesLog("Tool mode selected from Weapon Configuration: " .. tostring(storedMode))
		emit("selected", storedMode)
		emitMode(storedMode)
		if storedMode == "off" then
			deactivateSESToolWeapons(latestContext, source or "map_dropdown")
		else
			activeMountProbe(storedMode, "map_dropdown")
		end
	end
end

local function addModeRowDocked(uitable, defensibleid, source)
	requestPublishedToolMode(source or "docked_row")
	local context = getWeaponContext(defensibleid, source or "docked_row")
	local startMode = forceOffIfHandLaserMissing(context, source or "docked_row")
	local options, availability = getModeOptions(context)
	if not availability.showRow then
		setStoredMode("off")
		emit("row_hidden_no_tools_docked", "source=" .. safeString(source or "docked_row")
			.. ", salvager=" .. safeString(availability.salvagerAmount)
			.. ", welder=" .. safeString(availability.welderAmount)
			.. ", inventoryknown=" .. bool01(availability.inventoryKnown)
			.. ", handlaser=" .. bool01(availability.hasHandLaser))
		emitMode("off")
		deactivateSESToolWeapons(context, source or "docked_row")
		return nil
	end
	startMode = normalizeStartModeForOptions(startMode, options, source or "docked_row")
	if #options <= 1 then
		emit("row_visible_off_only_docked", "source=" .. safeString(source or "docked_row")
			.. ", salvager=" .. safeString(availability.salvagerAmount)
			.. ", welder=" .. safeString(availability.welderAmount)
			.. ", inventoryknown=" .. bool01(availability.inventoryKnown)
			.. ", handlaser=" .. bool01(availability.hasHandLaser))
	end
	local row = uitable:addRow(ses.rowid .. "_docked", {})
	row[1]:setColSpan(2):createText("    " .. sesText(201, "SES Tool Mode:"))
	row[3]:setColSpan(9):createDropDown(options, {
		startOption = startMode,
		active = true,
		mouseOverText = sesText(202, "Select what the mounted Hand Laser should do for Ship Equipment Salvaging. Only modes with the matching SES tool in inventory and a mounted Hand Laser are shown."),
		uiTriggerID = ses.controlid,
	})
	if row[3].properties then
		row[3].properties.uiTriggerID = ses.controlid
	end
	row[3].handlers.onDropDownConfirmed = function(_, mode)
		local latestContext = getWeaponContext(defensibleid, source or "docked_dropdown")
		local toolAllowed, toolAmount, tool = modeInventoryAllowed(mode)
		if mode ~= "off" and not toolAllowed then
			setStoredMode("off")
			emit("selection_rejected_no_toolware", "source=" .. safeString(source or "docked_dropdown")
				.. ", requested=" .. safeString(mode)
				.. ", ware=" .. safeString(tool and tool.ware)
				.. ", amount=" .. safeString(toolAmount)
				.. ", handlaser=" .. bool01(latestContext.hasHandLaser))
			emitMode("off")
			deactivateSESToolWeapons(latestContext, source or "docked_dropdown")
			return
		end
		if mode ~= "off" and not latestContext.hasHandLaser then
			setStoredMode("off")
			emit("selection_rejected_no_handlaser", "source=" .. safeString(source or "docked_dropdown")
				.. ", requested=" .. safeString(mode)
				.. ", slots=" .. safeString(latestContext.slots))
			emitMode("off")
			deactivateSESToolWeapons(latestContext, source or "docked_dropdown")
			return
		end
		local storedMode = setStoredMode(mode)
		sesLog("Tool mode selected from DockedMenu Weapon Configuration: " .. tostring(storedMode))
		emit("selected_docked", storedMode)
		emitMode(storedMode)
		if storedMode == "off" then
			deactivateSESToolWeapons(latestContext, source or "docked_dropdown")
		else
			activeMountProbe(storedMode, "docked_dropdown")
		end
	end
	return row
end

local function patchMapMenu(mapMenu)
	if not mapMenu then
		return false
	end
	if mapMenu.sesToolModePatched == ses.version then
		return true
	end

	local original = mapMenu.setupLoadoutInfoSubmenuRows
	if type(original) ~= "function" then
		return false
	end

	mapMenu.setupLoadoutInfoSubmenuRows = function(mode, inputtable, inputobject, instance)
		local debugContext = objectDebug(inputobject, mode, instance)
		emit("loadout_function_called", debugContext)
		if looksLikePlayerSpacesuit(inputobject) then
			diagnoseMountedWeapons("map_loadout", inputobject)
		end

		if not inputtable then
			emit("no_inputtable", debugContext)
			return original(mode, inputtable, inputobject, instance)
		end

		local originalAddRowGroup = inputtable.addRowGroup
		if type(originalAddRowGroup) ~= "function" then
			emit("no_addrowgroup", debugContext)
			return original(mode, inputtable, inputobject, instance)
		end

		local rowGroupCount = 0
		local rowProbeCount = 0
		local inserted = false
		local looksLikeSuit = looksLikePlayerSpacesuit(inputobject)

		inputtable.addRowGroup = function(tableSelf, ...)
			local rowgroup = originalAddRowGroup(tableSelf, ...)
			rowGroupCount = rowGroupCount + 1

			-- In the Kuertee/vanilla MapMenu loadout panel, the Weapon
			-- Configuration block creates rows named info_weaponconfig#.
			-- For v175, hook every row group and insert at the first matching
			-- concrete weapon row. This is intentionally broader than final so
			-- we can discover the exact runtime shape on the user's install.
			if rowgroup and (type(rowgroup.addRow) == "function") then
				local originalAddRow = rowgroup.addRow

				rowgroup.addRow = function(rowGroupSelf, rowdata, properties)
					local row = originalAddRow(rowGroupSelf, rowdata, properties)
					if rowProbeCount < 14 then
						rowProbeCount = rowProbeCount + 1
						emit("row_probe", "group=" .. safeString(rowGroupCount)
							.. ", row=" .. safeString(rowdata)
							.. ", suit=" .. safeString(looksLikeSuit)
							.. ", " .. debugContext)
					end
					if looksLikeSuit and (not inserted) and (type(rowdata) == "string") and string.match(rowdata, "^info_weaponconfig%d+$") then
						inserted = true
						local okAdd, addErr = pcall(addModeRow, rowGroupSelf, inputobject, "map_row")
						if okAdd then
							emit("row_added_uixml", "group=" .. safeString(rowGroupCount)
								.. ", row=" .. safeString(rowdata)
								.. ", suit=" .. safeString(looksLikeSuit)
								.. ", " .. debugContext)
						else
							emit("row_add_error", safeString(addErr))
						end
					end
					return row
				end
			end

			return rowgroup
		end

		local ok, result = pcall(original, mode, inputtable, inputobject, instance)
		inputtable.addRowGroup = originalAddRowGroup
		if not ok then
			error(result)
		end
		if not inserted then
			emit("row_not_inserted", "groups=" .. safeString(rowGroupCount)
				.. ", probes=" .. safeString(rowProbeCount)
				.. ", suit=" .. safeString(looksLikeSuit)
				.. ", " .. debugContext)
		end
		return result
	end

	mapMenu.sesToolModePatched = ses.version
	if type(mapMenu.registerCallback) == "function" then
		sesLog("Patched MapMenu through Kuertee UIX-loaded SES addon; UIX callback registry detected.")
		emit("patched_uix")
	else
		sesLog("Patched MapMenu through SES UI addon; UIX callback registry was not detected.")
		emit("patched_no_uix_registry")
	end
	return true
end

local function patchDockedMenu(dockedMenu)
	if not dockedMenu then
		return false
	end
	if dockedMenu.sesToolModeDockedPatched == ses.version then
		return true
	end

	if type(dockedMenu.registerCallback) == "function" then
		dockedMenu.registerCallback("display_on_after_weaponconfig_weapon_row", function(context)
			if (not context) or (context.index ~= 1) then
				return
			end
			local currentplayership = context.currentplayership
			if not looksLikePlayerSpacesuit(currentplayership) then
				emit("docked_row_hidden_nonspacesuit", "currentplayership=" .. safeString(currentplayership)
					.. ", mode=" .. safeString(dockedMenu.mode)
					.. ", version=" .. ses.version)
				return
			end

			diagnoseMountedWeapons("docked_official_callback", currentplayership)
			local okAdd, rowOrError = pcall(addModeRowDocked, context.table_header, currentplayership, "docked_official_callback")
			if not okAdd then
				emit("docked_row_add_error", safeString(rowOrError))
				return
			end
			local row = rowOrError
			if row and context.titlerow and context.titlerow[1] and context.titlerow[1].properties then
				context.titlerow[1].properties.helpOverlayHeight = context.titlerow[1].properties.helpOverlayHeight + row:getHeight() + Helper.borderSize
			end
			if row then
				emit("docked_row_added", "currentplayership=" .. safeString(currentplayership)
					.. ", source=official_callback, version=" .. ses.version)
			end
		end, "ship_equipment_salvaging")

		dockedMenu.sesToolModeDockedPatched = ses.version
		sesLog("Registered SES Tool Mode through Kuertee's official DockedMenu callback.")
		emit("registered_docked_official", ses.version)
		return true
	end

	local originalDisplay = dockedMenu.display
	if type(originalDisplay) ~= "function" then
		return false
	end

	dockedMenu.display = function(...)
		emit("docked_display_called", "mode=" .. safeString(dockedMenu.mode)
			.. ", currentplayership=" .. safeString(dockedMenu.currentplayership)
			.. ", version=" .. ses.version)
		local looksLikeSuit = looksLikePlayerSpacesuit(dockedMenu.currentplayership)
		if looksLikeSuit then
			diagnoseMountedWeapons("docked_display", dockedMenu.currentplayership)
		else
			emit("docked_row_hidden_nonspacesuit", "currentplayership=" .. safeString(dockedMenu.currentplayership)
				.. ", mode=" .. safeString(dockedMenu.mode)
				.. ", version=" .. ses.version)
		end

		if not (Helper and type(Helper.createFrameHandle) == "function") then
			emit("docked_no_createframe", ses.version)
			return originalDisplay(...)
		end

		local originalCreateFrame = Helper.createFrameHandle
		local inserted = false
		local rowProbeCount = 0
		local tableCount = 0
		local weaponRowsSeen = 0
		local currentShip = safeString(dockedMenu.currentplayership)

		Helper.createFrameHandle = function(menuArg, frameProperties)
			local frame = originalCreateFrame(menuArg, frameProperties)
			if (menuArg == dockedMenu) and frame and (type(frame.addTable) == "function") then
				local originalAddTable = frame.addTable
				frame.addTable = function(frameSelf, ...)
					local tableObj = originalAddTable(frameSelf, ...)
					tableCount = tableCount + 1
					if tableObj and (type(tableObj.addRow) == "function") then
						local originalAddRow = tableObj.addRow
						tableObj.addRow = function(tableSelf, rowdata, properties)
							local row = originalAddRow(tableSelf, rowdata, properties)
							if rowProbeCount < 24 then
								rowProbeCount = rowProbeCount + 1
								emit("docked_row_probe", "table=" .. safeString(tableCount)
									.. ", row=" .. safeString(rowdata)
									.. ", mode=" .. safeString(dockedMenu.mode)
									.. ", currentplayership=" .. safeString(dockedMenu.currentplayership)
									.. ", suit=" .. safeString(looksLikeSuit))
							end
							if looksLikeSuit and rowdata == "weaponconfig" then
								weaponRowsSeen = weaponRowsSeen + 1
								if not inserted then
									inserted = true
									local okAdd, addErr = pcall(addModeRowDocked, tableSelf, dockedMenu.currentplayership, "docked_row")
									if okAdd then
										emit("docked_row_added", "table=" .. safeString(tableCount)
											.. ", weaponrow=" .. safeString(weaponRowsSeen)
											.. ", currentplayership=" .. safeString(dockedMenu.currentplayership))
									else
										emit("docked_row_add_error", safeString(addErr))
									end
								end
							end
							return row
						end
					end
					return tableObj
				end
			end
			return frame
		end

		local ok, result = pcall(originalDisplay, ...)
		Helper.createFrameHandle = originalCreateFrame
		if not ok then
			error(result)
		end
		if not inserted then
			emit("docked_row_not_inserted", "tables=" .. safeString(tableCount)
				.. ", probes=" .. safeString(rowProbeCount)
				.. ", weaponrows=" .. safeString(weaponRowsSeen)
				.. ", startship=" .. currentShip
				.. ", endship=" .. safeString(dockedMenu.currentplayership)
				.. ", mode=" .. safeString(dockedMenu.mode))
		end
		return result
	end

	dockedMenu.sesToolModeDockedPatched = ses.version
	if type(dockedMenu.registerCallback) == "function" then
		sesLog("Patched DockedMenu display through SES Lua addon; UIX callback registry detected.")
		emit("patched_docked")
	else
		sesLog("Patched DockedMenu display through SES Lua addon; UIX callback registry was not detected.")
		emit("patched_docked_no_uix_registry")
	end
	return true
end

local function findMenuByName(name, globalName)
	if Helper and Helper.getMenu then
		local ok, menu = pcall(Helper.getMenu, name)
		if ok and menu then
			return menu
		end
	end

	if Menus then
		for _, menu in ipairs(Menus) do
			if menu.name == name then
				return menu
			end
		end
	end

	if globalName and _G and _G[globalName] then
		return _G[globalName]
	end

	return nil
end

local function findMapMenu()
	return findMenuByName("MapMenu", "MapMenu")
end

local function findDockedMenu()
	return findMenuByName("DockedMenu", "DockedMenu")
end

refreshToolModeMenu = function(mode)
	local dockedMenu = findDockedMenu()
	if dockedMenu and type(dockedMenu.display) == "function" and looksLikePlayerSpacesuit(dockedMenu.currentplayership) then
		local ok, err = pcall(dockedMenu.display)
		if ok then
			emit("mode_menu_refreshed", "mode=" .. safeString(mode) .. ", version=" .. ses.version)
		else
			emit("mode_menu_refresh_failed", "error=" .. safeString(err) .. ", version=" .. ses.version)
		end
	end
end

local function tryPatch()
	local mapMenu = findMapMenu()
	if mapMenu then
		emit("mapmenu_skipped_official_docked_only", ses.version)
	end

	local dockedMenu = findDockedMenu()
	if not dockedMenu then
		sesLog("DockedMenu not found; SES Tool Mode DockedMenu addon will retry.")
		emit("docked_missing")
	else
		patchDockedMenu(dockedMenu)
	end

	return dockedMenu ~= nil
end

local function runPatchAttempt()
	local ok, result = pcall(tryPatch)
	if not ok then
		sesLog("Patch attempt failed: " .. tostring(result))
		emit("error", tostring(result))
	end
end

local function init()
	sesLog("Loaded SES Tool Mode UI addon via ui.xml/Kuertee UIX path.")
	emit("loaded_uixml", ses.version)
	emit("loaded_uix", ses.version)
	registerToolInventoryEvent()
	registerToolModeEvent()
	requestPublishedToolInventory("init")
	requestPublishedToolMode("init")
	runPatchAttempt()

	if Register_OnLoad_Init then
	Register_OnLoad_Init(runPatchAttempt, "SES Tool Mode DockedMenu addon")
	end

	if Helper and Helper.addDelayedOneTimeCallbackOnUpdate and getElapsedTime then
		Helper.addDelayedOneTimeCallbackOnUpdate(runPatchAttempt, true, getElapsedTime() + 1)
		Helper.addDelayedOneTimeCallbackOnUpdate(runPatchAttempt, true, getElapsedTime() + 3)
	end
end

init()

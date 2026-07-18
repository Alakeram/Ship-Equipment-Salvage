-- Ship Equipment Salvaging
-- Milestone 5 public native salvage/weld planner integration.
--
-- SES owns all behavior in this file. Kuertee UI Extensions owns only the
-- published callback dispatchers that this addon registers against.

local ffi = require("ffi")
local C = ffi.C

local ModLua = {}

local userQuestionMenu = nil
local shipConfigurationMenu = nil
local suppressCleanupEvent = false
local runRegistration = nil
local plannerData = nil
local selectedSalvageIndex = 0
local selectedWeldCategory = ""
local selectedWeldIndex = 0
local weldResultText = ""
local weldPreviewBaseline = nil
local weldPreviewObject = ""
local weldPendingReservations = {}
local weldPendingPreviewButton = nil
local weldPendingPreviewItem = nil
local weldPreviewExpectedRows = nil
local weldPreviewSlots = {}
local reconcileWeldPreviewRequest = nil
local salvagePendingPreviewButton = nil
local salvagePendingPreviewItem = nil
local salvagePreviewExpectedRows = nil
local salvagePreviewSelections = {}
local salvagePreviewNeedsReplay = false
local salvagePreviewReplayScheduled = false
local reconcileSalvagePreviewRequest = nil
local weldPlanRows = nil
local weldTileStateDiagnostics = {}

pcall(ffi.cdef, [[
	typedef uint64_t UniverseID;
	UniverseID GetPlayerID(void);
	bool IsUpgradeGroupMacroCompatible(UniverseID destructibleid, const char* macroname, const char* path, const char* group, const char* upgradetypename, const char* upgrademacroname);
	bool IsUpgradeMacroCompatible(UniverseID objectid, UniverseID moduleid, const char* macroname, bool ismodule, const char* upgradetypename, size_t slot, const char* upgrademacroname);
	bool IsVirtualUpgradeMacroCompatible(UniverseID defensibleid, const char* macroname, const char* upgradetypename, size_t slot, const char* upgrademacroname);
]])

local ses = {
	version = "v367-faction-and-overview",
	salvageMode = "custom_ses_m5_salvage",
	salvageResultMode = "custom_ses_m5_salvage_result",
	weldMode = "custom_ses_m5_weld",
	callbackID = "ship_equipment_salvaging_m5_weld",
	bridgeCallbackID = "ship_equipment_salvaging_m5_titlebar_dispatch",
	blackboard = "$SES_M5_Native_PlannerData",
}

local state = {
	enabled = true,
	kind = "",
	target = "",
	targetID = "",
	available = 0,
	pendingRows = 0,
	pendingQuantity = 0,
	catalysts = 0,
	catalystCost = 0,
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

local function emit(control, param)
	if AddUITriggeredEvent then
		pcall(AddUITriggeredEvent, "SES_M5_Native_UI", control, param or ses.version)
	end
end

local function playerID()
	if C.GetPlayerID and ConvertStringTo64Bit then
		local ok, id = pcall(function()
			return ConvertStringTo64Bit(tostring(C.GetPlayerID()))
		end)
		if ok then
			return id
		end
	end
	return nil
end

local function itemField(item, key)
	if type(item) ~= "table" then
		return nil
	end
	if item[key] ~= nil then
		return item[key]
	end
	return item["$" .. key]
end

local function numeric(value)
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function loadPlannerData()
	local id = playerID()
	if not id or not GetNPCBlackboard then
		return false
	end
	local ok, data = pcall(GetNPCBlackboard, id, ses.blackboard)
	if not ok or type(data) ~= "table" then
		return false
	end
	plannerData = data
	state.targetID = safeString(itemField(data, "targetid") or "")
	local selected = numeric(itemField(data, "selectedindex"))
	if selected > 0 then
		if safeString(itemField(data, "kind")) == "weld" then
			selectedWeldIndex = selected
		else
			selectedSalvageIndex = selected
		end
	end
	local category = safeString(itemField(data, "selectedcategory") or "")
	if category ~= "" then
		selectedWeldCategory = category
	end
	return true
end

local function requestRefresh(reason)
	loadPlannerData()
	weldPendingReservations = {}
	if reconcileWeldPreviewRequest then
		reconcileWeldPreviewRequest()
	end
	if reconcileSalvagePreviewRequest then
		reconcileSalvagePreviewRequest()
	end
	if userQuestionMenu and (userQuestionMenu.mode == ses.salvageMode or userQuestionMenu.mode == ses.weldMode) and getElapsedTime then
		userQuestionMenu.refresh = getElapsedTime()
	end
	if (state.kind == "weld" or state.kind == "salvage") and shipConfigurationMenu and shipConfigurationMenu.mode == "upgrade" and shipConfigurationMenu.displayMenu then
		pcall(shipConfigurationMenu.displayMenu)
	end
	emit("native_refresh_seen", safeString(reason or "state"))
end

local function sesLog(message)
	print("[SES][M5 UIX] " .. safeString(message))
end

local function split(value)
	local fields = {}
	for field in string.gmatch(safeString(value or "") .. ";", "(.-);") do
		table.insert(fields, field)
	end
	return fields
end

local function parseState(_, param)
	local fields = split(param)
	if fields[1] == "gate" then
		-- Kept as a compatibility handshake for older saved MD state. The public
		-- native planner is always enabled as of v351.
		state.enabled = true
		emit("gate_state_received", "enabled=" .. safeString(state.enabled) .. ", version=" .. ses.version)
		return
	end
	if fields[1] == "result" and fields[2] == "weld" then
		weldResultText = (fields[3] or "0") .. " installed; " .. (fields[4] or "0") .. " skipped"
		weldPreviewBaseline = nil
		weldPreviewObject = ""
		weldPendingReservations = {}
		weldPendingPreviewButton = nil
		weldPendingPreviewItem = nil
		weldPreviewExpectedRows = nil
		weldPreviewSlots = {}
		requestRefresh("weld_result")
		return
	end
	if fields[1] ~= "state" then
		return
	end

	local nextKind = fields[2] or ""
	local nextTarget = fields[3] or ""
	if nextKind ~= "weld" or (state.target ~= "" and state.target ~= nextTarget) then
		weldPreviewSlots = {}
	end
	state.kind = nextKind
	-- Planner state is authoritative for the public native workflow.
	state.enabled = true
	state.target = nextTarget
	state.available = tonumber(fields[4]) or 0
	state.pendingRows = tonumber(fields[5]) or 0
	state.pendingQuantity = tonumber(fields[6]) or 0
	state.catalysts = tonumber(fields[7]) or 0
	state.catalystCost = tonumber(fields[8]) or 0
	if state.kind == "weld" and state.pendingRows == 0 and not weldPreviewExpectedRows then
		weldPreviewSlots = {}
	end
	if state.kind ~= "salvage" or (state.pendingRows == 0 and not salvagePreviewExpectedRows) then
		salvagePreviewSelections = {}
		salvagePreviewNeedsReplay = false
		salvagePreviewReplayScheduled = false
	end
	requestRefresh("planner_state")
	if (state.kind == "weld" or state.kind == "salvage") and runRegistration then
		emit("shipconfig_registration_attempt", "reason=weld_state, version=" .. ses.version)
		runRegistration("weld_state")
		emit("shipconfig_registration_complete", "reason=weld_state, version=" .. ses.version)
	end
	emit("planner_state_received", "kind=" .. state.kind
		.. ", available=" .. safeString(state.available)
		.. ", pendingrows=" .. safeString(state.pendingRows)
		.. ", pendingquantity=" .. safeString(state.pendingQuantity)
		.. ", version=" .. ses.version)
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

local function helperNumber(key, fallback)
	if Helper and tonumber(Helper[key]) then
		return tonumber(Helper[key])
	end
	return fallback
end

local function currentPlannerKind()
	if not userQuestionMenu then
		return ""
	end
	if userQuestionMenu.mode == ses.salvageMode then
		return "salvage"
	elseif userQuestionMenu.mode == ses.salvageResultMode then
		return "salvage_result"
	elseif userQuestionMenu.mode == ses.weldMode then
		return "weld"
	end
	return ""
end

local function closePlanner(reason, notifyMD)
	local kind = currentPlannerKind()
	if kind == "" then
		return
	end
	suppressCleanupEvent = true
	if notifyMD then
		emit("native_cancel", kind)
	end
	state.kind = ""
	if userQuestionMenu and userQuestionMenu.onCloseElement then
		userQuestionMenu.onCloseElement("close")
	end
end

local function plannerTitle(kind)
	if kind == "salvage" then
		return sesText(400, "Avarice Beam Regulator - Salvage")
	end
	return sesText(401, "Avarice Bonding Regulator - Loadout")
end

local function paneLabels(kind)
	if kind == "salvage" then
		return sesText(402, "AVAILABLE EQUIPMENT"), sesText(403, "PENDING SALVAGE"), sesText(404, "Beam Catalysts")
	end
	return sesText(405, "SALVAGED PARTS INVENTORY"), sesText(406, "PENDING INSTALL"), sesText(407, "Bonding Catalysts")
end

local excludedSalvageWares = {
	countermeasure_flares_01 = true,
	ship_gen_xs_lasertower_01_a = true,
	ship_gen_s_lasertower_01_a = true,
	weapon_gen_mine_01 = true,
	weapon_gen_mine_02 = true,
	weapon_gen_mine_03 = true,
	satellite_mk1 = true,
	satellite_mk2 = true,
	resourceprobe_01 = true,
	waypointmarker_01 = true,
}

local allowedCategories = {
	weapons = true,
	shields = true,
	engines = true,
	thrusters = true,
	turrets = true,
}

local function categoryName(category)
	local names = {
		weapons = sesText(100, "Weapons"),
		shields = sesText(101, "Shield Generators"),
		engines = sesText(102, "Engines"),
		thrusters = sesText(103, "Thrusters"),
		turrets = sesText(104, "Turrets"),
	}
	return names[safeString(category)] or safeString(category or sesText(106, "Equipment"))
end

local function equipmentName(item)
	local name = itemField(item, "name")
	if name and safeString(name) ~= "" then
		return safeString(name)
	end
	return safeString(itemField(item, "wareid") or itemField(item, "id") or sesText(408, "Installed equipment"))
end

local function nativeEquipmentName(item, macro)
	local name = type(item) == "table" and item.name or nil
	if name and safeString(name) ~= "" then
		return safeString(name)
	end
	macro = safeString(macro or "")
	if macro ~= "" and GetMacroData then
		local ok, macroName = pcall(GetMacroData, macro, "name")
		if ok and macroName and safeString(macroName) ~= "" then
			return safeString(macroName)
		end
	end
	return sesText(409, "Saved equipment")
end

local makerCodes = {
	arg = "ARG", argon = "ARG",
	bor = "BOR", boron = "BOR",
	drn = "DRN", drone = "DRN",
	khk = "KHK", khaak = "KHK",
	par = "PAR", paranid = "PAR",
	spl = "SPL", split = "SPL",
	tel = "TEL", teladi = "TEL",
	ter = "TER", terran = "TER",
	xen = "XEN", xenon = "XEN",
}

local function makerCode(item, macro)
	local faction = type(item) == "table" and safeString(item.faction or "") or ""
	local normalized = string.lower(faction)
	if makerCodes[normalized] then
		return makerCodes[normalized]
	end
	if string.match(faction, "^[A-Z][A-Z][A-Z]$") then
		return faction
	end
	macro = safeString(macro or "")
	if macro ~= "" and GetMacroData then
		local ok, races = pcall(GetMacroData, macro, "makerrace")
		if ok then
			if type(races) ~= "table" then
				races = { races }
			end
			for _, race in ipairs(races) do
				local raceText = safeString(race or "")
				local code = makerCodes[string.lower(raceText)]
				if code then
					return code
				end
				if string.match(raceText, "^[A-Z][A-Z][A-Z]$") then
					return raceText
				end
			end
		end
	end
	return ""
end

local function abbreviatedEquipmentName(name, item, macro)
	name = safeString(name or "")
	local code = makerCode(item, macro)
	if code == "" or string.match(name, "^" .. code .. "[%s%-]") then
		return name
	end
	return code .. " " .. name
end

local function nativeTileName(button, item, macro)
	-- Ship Configuration has already width-truncated the native name into the
	-- first line of this two-line box. Preserve that fitted line and reserve the
	-- second line for the SES stock receipt. Reintroducing the full localized
	-- name here can wrap it to two lines and push the receipt into a third line.
	local nativeText = type(button) == "table" and safeString(button.extratext or "") or ""
	local firstLine = string.match(nativeText, "^([^\r\n]+)")
	if firstLine and firstLine ~= "" then
		return abbreviatedEquipmentName(firstLine, item, macro)
	end
	macro = safeString(macro or "")
	if macro ~= "" and GetMacroData then
		local ok, shortName = pcall(GetMacroData, macro, "shortname")
		if ok and shortName and safeString(shortName) ~= "" then
			return abbreviatedEquipmentName(shortName, item, macro)
		end
	end
	return abbreviatedEquipmentName(nativeEquipmentName(item, macro), item, macro)
end

local function salvageRows()
	local rows = {}
	local byKey = {}
	local available = plannerData and itemField(plannerData, "available") or {}
	local plan = plannerData and itemField(plannerData, "plan") or {}
	for sourceIndex, item in pairs(type(available) == "table" and available or {}) do
		local wareid = safeString(itemField(item, "wareid") or itemField(item, "id") or "")
		local categoryValue = itemField(item, "category") or itemField(item, "group")
		local category = safeString(type(categoryValue) == "table" and (itemField(categoryValue, "id") or "") or categoryValue or "")
		local macro = safeString(itemField(item, "macro") or itemField(item, "objectmacro") or "")
		if allowedCategories[category] and not excludedSalvageWares[wareid] and macro ~= "" then
			local key = table.concat({ category, wareid, macro }, "|")
			local row = byKey[key]
			if not row then
				row = {
					key = key,
					index = tonumber(itemField(item, "index")) or tonumber(sourceIndex) or 0,
					wareid = wareid,
					macro = macro,
					category = category,
					name = equipmentName(item),
					faction = safeString(itemField(item, "faction") or ""),
					installed = 0,
					planned = 0,
					cost = 0,
				}
				byKey[key] = row
				table.insert(rows, row)
			end
			row.installed = row.installed + 1
		end
	end
	for _, item in pairs(type(plan) == "table" and plan or {}) do
		local wareid = safeString(itemField(item, "wareid") or "")
		local category = safeString(itemField(item, "category") or "")
		local macro = safeString(itemField(item, "macro") or "")
		local row = byKey[table.concat({ category, wareid, macro }, "|")]
		if row then
			row.planned = row.planned + math.max(1, numeric(itemField(item, "plannedquantity")))
		end
	end
	local perPiece = numeric(plannerData and itemField(plannerData, "catalystperpiece"))
	if perPiece <= 0 then
		perPiece = 1
	end
	local catalystsAvailable = math.max(0, state.catalysts - state.catalystCost)
	for _, row in ipairs(rows) do
		row.addQuantity = 1
		if row.category == "engines" and row.installed > 1 then
			local otherEngines = false
			for _, candidate in ipairs(rows) do
				if candidate ~= row and candidate.category == "engines" then
					otherEngines = true
					break
				end
			end
			if not otherEngines then
				row.addQuantity = row.installed
			end
		end
		row.cost = row.addQuantity * perPiece
		row.canAdd = row.planned + row.addQuantity <= row.installed and catalystsAvailable >= row.cost
	end
	table.sort(rows, function(a, b)
		if a.category ~= b.category then
			local order = { weapons = 1, shields = 2, engines = 3, thrusters = 4, turrets = 5 }
			return (order[a.category] or 99) < (order[b.category] or 99)
		end
		return a.name < b.name
	end)
	return rows
end

local function salvagePlanRows()
	local rows = {}
	local plan = plannerData and itemField(plannerData, "plan") or {}
	for index, item in pairs(type(plan) == "table" and plan or {}) do
		table.insert(rows, {
			index = tonumber(itemField(item, "index")) or tonumber(index) or 0,
			name = equipmentName(item),
			wareid = safeString(itemField(item, "wareid") or ""),
			macro = safeString(itemField(item, "macro") or ""),
			faction = safeString(itemField(item, "faction") or ""),
			category = safeString(itemField(item, "category") or ""),
			quantity = math.max(1, numeric(itemField(item, "plannedquantity"))),
			cost = math.max(1, numeric(itemField(item, "beamcatalystcost"))),
		})
	end
	table.sort(rows, function(a, b) return a.index < b.index end)
	return rows
end

local function nativeAction(action, index, category)
	if category and category ~= "" then
		emit("native_" .. action, category)
	else
		emit("native_" .. action, numeric(index))
	end
end

local function dataList(key)
	local value = plannerData and itemField(plannerData, key) or {}
	return type(value) == "table" and value or {}
end

local function weldCategories()
	local rows = {}
	for _, item in pairs(dataList("categories")) do
		local id = safeString(itemField(item, "id") or "")
		if allowedCategories[id] then
			table.insert(rows, {
				id = id,
				text = safeString(itemField(item, "text") or categoryName(id)),
				rows = numeric(itemField(item, "rows")),
				open = numeric(itemField(item, "open")),
			})
		end
	end
	return rows
end

local function weldAvailableRows()
	local rows = {}
	for _, item in pairs(dataList("available")) do
		local index = numeric(itemField(item, "value") or itemField(item, "index"))
		local category = safeString(itemField(item, "category") or selectedWeldCategory)
		if index > 0 and allowedCategories[category] then
			local canAddValue = itemField(item, "canadd")
			table.insert(rows, {
				index = index,
				wareid = safeString(itemField(item, "wareid") or ""),
				macro = safeString(itemField(item, "macro") or ""),
				name = safeString(itemField(item, "name") or sesText(409, "Saved equipment")),
				faction = safeString(itemField(item, "faction") or "--"),
				category = category,
				available = numeric(itemField(item, "available")),
				status = safeString(itemField(item, "status") or sesText(410, "Checking compatibility")),
				canAdd = canAddValue == true or canAddValue == 1 or safeString(canAddValue) == "true",
				quantity = math.max(1, numeric(itemField(item, "quantity"))),
				cost = math.max(1, numeric(itemField(item, "cost"))),
			})
		end
	end
	return rows
end

local function weldItemKey(macro, category)
	return safeString(category or "") .. "|" .. safeString(macro or "")
end

local function weldSlotKey(button)
	if type(button) ~= "table" then
		return ""
	end
	return safeString(button.upgradetype or "") .. "|" .. tostring(numeric(button.slot))
end

local function pendingWeldSlotMacro(button)
	local key = weldSlotKey(button)
	if key ~= "" and weldPendingPreviewButton and weldSlotKey(weldPendingPreviewButton) == key then
		return safeString(weldPendingPreviewButton.macro or "")
	end
	return ""
end

local function reservedWeldQuantity(item)
	return numeric(weldPendingReservations[weldItemKey(item.macro, item.category)])
end

local plannedWeldQuantity

local function remainingWeldQuantity(item)
	-- MD publishes item.available after subtracting every accepted weld-plan row.
	-- Only subtract the short-lived local reservation that covers the interval
	-- between a click and the authoritative planner-state refresh. Subtracting
	-- plannedWeldQuantity here counted accepted rows twice (for example 5 -> 3
	-- after reserving one weapon, or 2 -> 0 after reserving one shield).
	return math.max(0, numeric(item.available)
		- reservedWeldQuantity(item))
end

local function reserveWeldQuantity(item)
	local key = weldItemKey(item.macro, item.category)
	weldPendingReservations[key] = numeric(weldPendingReservations[key]) + math.max(1, numeric(item.quantity))
end

plannedWeldQuantity = function(macro, category)
	local total = 0
	for _, item in pairs(dataList("plan")) do
		if safeString(itemField(item, "macro") or "") == safeString(macro or "")
			and safeString(itemField(item, "category") or "") == safeString(category or "") then
			total = total + math.max(1, numeric(itemField(item, "plannedquantity")))
		end
	end
	return total
end

local function nativeCategoryFromMode(mode)
	local categories = {
		weapon = "weapons",
		shield = "shields",
		engine = "engines",
		enginegroup = "engines",
		thruster = "thrusters",
		turret = "turrets",
		turretgroup = "turrets",
	}
	return categories[safeString(mode)] or ""
end

local function nativeSlotCompatible(menu, upgradetype, slot, macro, grouped)
	if not menu or safeString(upgradetype) == "" or numeric(slot) <= 0 or safeString(macro) == "" then
		return false
	end
	local ok, compatible
	if grouped then
		local group = type(menu.groups) == "table" and menu.groups[numeric(slot)] or nil
		if type(group) ~= "table" or safeString(group.path or "") == "" or safeString(group.group or "") == "" then
			return false
		end
		local groupType = safeString(upgradetype)
		local upgradeTypeInfo = Helper and Helper.findUpgradeType and Helper.findUpgradeType(groupType) or nil
		if upgradeTypeInfo and safeString(upgradeTypeInfo.grouptype or "") ~= "" then
			groupType = safeString(upgradeTypeInfo.grouptype)
		elseif groupType == "enginegroup" then
			groupType = "engine"
		elseif groupType == "shieldgroup" then
			groupType = "shield"
		elseif groupType == "turretgroup" then
			groupType = "turret"
		end
		ok, compatible = pcall(C.IsUpgradeGroupMacroCompatible,
			menu.object, menu.macro, group.path, group.group, groupType, macro)
	elseif safeString(upgradetype) == "thruster" then
		ok, compatible = pcall(C.IsVirtualUpgradeMacroCompatible,
			menu.object, menu.macro, upgradetype, numeric(slot), macro)
	else
		ok, compatible = pcall(C.IsUpgradeMacroCompatible,
			menu.object, 0, menu.macro, false, upgradetype, numeric(slot), macro)
	end
	return ok and compatible == true
end

local function refreshShipConfiguration()
	if shipConfigurationMenu and shipConfigurationMenu.displayMenu then
		pcall(shipConfigurationMenu.displayMenu)
	end
end

local function rememberWeldPreviewBaseline()
	if not shipConfigurationMenu or not shipConfigurationMenu.upgradeplan or not Helper or not Helper.tableCopy then
		return false
	end
	local object = safeString(shipConfigurationMenu.object or "")
	if not weldPreviewBaseline or weldPreviewObject ~= object then
		weldPreviewBaseline = Helper.tableCopy(shipConfigurationMenu.upgradeplan, 3)
		weldPreviewObject = object
	end
	return true
end

local function updateWeldPreviewDisplay(refresh)
	if not shipConfigurationMenu or not shipConfigurationMenu.upgradeplan then
		return false
	end
	local ok, err = pcall(function()
		shipConfigurationMenu.newShipStats = false
		if shipConfigurationMenu.holomap and shipConfigurationMenu.holomap ~= 0 and Helper and Helper.callLoadoutFunction then
			Helper.callLoadoutFunction(shipConfigurationMenu.upgradeplan, nil, function(loadout, _)
				return C.UpdateObjectConfigurationMap(shipConfigurationMenu.holomap, shipConfigurationMenu.object, 0, shipConfigurationMenu.macro, false, loadout)
			end)
		end
		if refresh then
			refreshShipConfiguration()
		end
	end)
	if not ok then
		emit("weld_preview_failed", "error=" .. safeString(err) .. ", version=" .. ses.version)
	end
	return ok
end

local function previewWeldEquipment(button, item)
	if not rememberWeldPreviewBaseline() then
		return false
	end
	local ok, err = pcall(function()
		if button.grouped and shipConfigurationMenu.buttonSelectGroupUpgrade then
			shipConfigurationMenu.buttonSelectGroupUpgrade(button.upgradetype, button.slot, button.macro, nil, nil)
			local typeplan = shipConfigurationMenu.upgradeplan[button.upgradetype]
			local groupplan = typeplan and typeplan[button.slot]
			if groupplan and item.quantity > 1 then
				groupplan.count = math.max(tonumber(groupplan.count) or 0, item.quantity)
				if shipConfigurationMenu.refreshMenu then
					shipConfigurationMenu.refreshMenu()
				end
			end
		elseif shipConfigurationMenu.setSlotMacro then
			local upgradetype = Helper and Helper.findUpgradeType and Helper.findUpgradeType(button.upgradetype) or nil
			local slots = shipConfigurationMenu.slots and shipConfigurationMenu.slots[button.upgradetype] or nil
			if upgradetype and upgradetype.mergeslots and type(slots) == "table" and item.quantity > 1 then
				-- S/M engines are exposed through native individual-slot callbacks even
				-- though X4 treats them as one merged selection. Mirror vanilla's merged
				-- behavior so all physical engine slots, the category gauge, the required
				-- icon, the model, and the Overview agree on the accepted quantity.
				for slot in ipairs(slots) do
					shipConfigurationMenu.setSlotMacro(button.upgradetype, slot, button.macro)
				end
			else
				-- Weapons, shields, and other finite slots remain exact-slot previews;
				-- one accepted SES item must never spill into a sibling slot.
				shipConfigurationMenu.setSlotMacro(button.upgradetype, button.slot, button.macro)
			end
			if shipConfigurationMenu.addUndoStep then
				shipConfigurationMenu.addUndoStep()
			end
		end
		updateWeldPreviewDisplay(true)
	end)
	if ok then
		emit("weld_preview_applied", "category=" .. safeString(item.category)
			.. ", macro=" .. safeString(item.macro)
			.. ", quantity=" .. tostring(item.quantity)
			.. ", type=" .. safeString(button.upgradetype)
			.. ", slot=" .. safeString(button.slot)
			.. ", grouped=" .. tostring(button.grouped == true)
			.. ", version=" .. ses.version)
	else
		emit("weld_preview_failed", "error=" .. safeString(err) .. ", version=" .. ses.version)
	end
	return ok
end

local function restoreWeldPreview()
	if not weldPreviewBaseline or not shipConfigurationMenu then
		return false
	end
	local baseline = Helper and Helper.tableCopy and Helper.tableCopy(weldPreviewBaseline, 3) or weldPreviewBaseline
	weldPreviewBaseline = nil
	weldPreviewObject = ""
	local ok, err = pcall(function()
		if shipConfigurationMenu.getDataAndDisplay then
			shipConfigurationMenu.getDataAndDisplay(baseline, nil, nil, nil, true)
		else
			shipConfigurationMenu.upgradeplan = baseline
			updateWeldPreviewDisplay(true)
		end
	end)
	if not ok then
		emit("weld_preview_restore_failed", "error=" .. safeString(err) .. ", version=" .. ses.version)
	end
	return ok
end

local function previewSalvageEquipment(button, item, rememberSelection, refresh)
	if not rememberWeldPreviewBaseline() then
		return false
	end
	local ok, err = pcall(function()
		if button.grouped then
			local typeplan = shipConfigurationMenu.upgradeplan[button.upgradetype]
			local groupplan = typeplan and typeplan[button.slot]
			if not groupplan then
				error("missing native group plan")
			end
			local remaining = math.max(0, (tonumber(groupplan.count) or 0) - math.max(1, numeric(item.addQuantity)))
			groupplan.count = remaining
			if remaining == 0 then
				groupplan.macro = ""
				groupplan.ammomacro = ""
				groupplan.weaponmode = ""
				local upgradetype = Helper and Helper.findUpgradeType and Helper.findUpgradeType(button.upgradetype) or nil
				if upgradetype and upgradetype.pseudogroup and shipConfigurationMenu.slots and shipConfigurationMenu.slots[upgradetype.grouptype] then
					for slot in ipairs(shipConfigurationMenu.slots[upgradetype.grouptype]) do
						local slotplan = shipConfigurationMenu.upgradeplan[upgradetype.grouptype]
						local groupinfo = C.GetUpgradeSlotGroup(shipConfigurationMenu.object, shipConfigurationMenu.macro, upgradetype.grouptype, slot)
						local matchesGroup = upgradetype.mergeslots or (groupinfo.path == groupplan.path and groupinfo.group == groupplan.group)
						if matchesGroup and slotplan and slotplan[slot] and slotplan[slot].macro == item.macro then
							slotplan[slot] = { macro = "", ammomacro = "", weaponmode = "" }
						end
					end
				end
			end
		elseif shipConfigurationMenu.setSlotMacro then
			local upgradetype = Helper and Helper.findUpgradeType and Helper.findUpgradeType(button.upgradetype) or nil
			local slots = shipConfigurationMenu.slots and shipConfigurationMenu.slots[button.upgradetype] or nil
			if upgradetype and upgradetype.mergeslots and type(slots) == "table" and numeric(item.addQuantity) > 1 then
				-- Native S/M engine tiles can arrive through the individual-slot callback
				-- even though the category is one merged selection. Clear every physical
				-- slot so the model, Overview, category gauge and quantity all show the
				-- authoritative grouped removal published by MD.
				for slot in ipairs(slots) do
					shipConfigurationMenu.setSlotMacro(button.upgradetype, slot, "")
				end
			else
				shipConfigurationMenu.setSlotMacro(button.upgradetype, button.slot, "")
			end
		else
			error("native slot removal helper unavailable")
		end
		if shipConfigurationMenu.addUndoStep then
			shipConfigurationMenu.addUndoStep()
		end
		updateWeldPreviewDisplay(refresh ~= false)
	end)
	if ok then
		if rememberSelection ~= false then
			table.insert(salvagePreviewSelections, {
				button = {
					macro = button.macro,
					upgradetype = button.upgradetype,
					slot = button.slot,
					grouped = button.grouped,
				},
				item = {
					category = item.category,
					macro = item.macro,
					addQuantity = item.addQuantity,
				},
			})
		end
		emit("salvage_preview_applied", "category=" .. safeString(item.category)
			.. ", macro=" .. safeString(item.macro)
			.. ", quantity=" .. tostring(item.addQuantity)
			.. ", version=" .. ses.version)
	else
		emit("salvage_preview_failed", "error=" .. safeString(err) .. ", version=" .. ses.version)
	end
	return ok
end

local function replaySalvagePreviewSelections()
	if state.kind ~= "salvage" or not shipConfigurationMenu or #salvagePreviewSelections == 0 then
		salvagePreviewNeedsReplay = false
		return false
	end
	-- Back to Plan creates a fresh Ship Configuration menu. Rebuild its visual
	-- loadout from the exact slot/group choices that produced the still-live MD
	-- plan so the model and Overview continue to match the confirmation rows.
	salvagePreviewNeedsReplay = false
	weldPreviewBaseline = nil
	weldPreviewObject = ""
	local replayed = 0
	for _, selection in ipairs(salvagePreviewSelections) do
		if previewSalvageEquipment(selection.button, selection.item, false, false) then
			replayed = replayed + 1
		end
	end
	updateWeldPreviewDisplay(true)
	emit("salvage_preview_replayed", "rows=" .. tostring(replayed) .. ", version=" .. ses.version)
	return replayed == #salvagePreviewSelections
end

reconcileWeldPreviewRequest = function()
	if not weldPreviewExpectedRows then
		return
	end
	local accepted = state.pendingRows >= weldPreviewExpectedRows
	if accepted and weldPendingPreviewButton and weldPendingPreviewItem then
		local slotKey = weldSlotKey(weldPendingPreviewButton)
		local previousMacro = weldPreviewSlots[slotKey]
		weldPreviewSlots[slotKey] = safeString(weldPendingPreviewButton.macro or "")
		if not previewWeldEquipment(weldPendingPreviewButton, weldPendingPreviewItem) then
			weldPreviewSlots[slotKey] = previousMacro
		end
	elseif not accepted then
		weldResultText = "Selection was not added"
		emit("weld_preview_rejected", "expectedrows=" .. tostring(weldPreviewExpectedRows)
			.. ", actualrows=" .. tostring(state.pendingRows)
			.. ", version=" .. ses.version)
	end
	weldPendingPreviewButton = nil
	weldPendingPreviewItem = nil
	weldPreviewExpectedRows = nil
end

reconcileSalvagePreviewRequest = function()
	if not salvagePreviewExpectedRows then
		return
	end
	local accepted = state.pendingRows >= salvagePreviewExpectedRows
	if accepted and salvagePendingPreviewButton and salvagePendingPreviewItem then
		previewSalvageEquipment(salvagePendingPreviewButton, salvagePendingPreviewItem)
	elseif not accepted then
		weldResultText = "Salvage selection was not added"
		emit("salvage_preview_rejected", "expectedrows=" .. tostring(salvagePreviewExpectedRows)
			.. ", actualrows=" .. tostring(state.pendingRows)
			.. ", version=" .. ses.version)
	end
	salvagePendingPreviewButton = nil
	salvagePendingPreviewItem = nil
	salvagePreviewExpectedRows = nil
end

local function findWeldInventoryRow(macro, category)
	macro = safeString(macro or "")
	category = safeString(category or "")
	for _, item in ipairs(weldAvailableRows()) do
		if item.macro == macro and item.category == category then
			return item
		end
	end
	return nil
end

local function nativeUpgradeTypeFromCategory(category)
	local types = {
		weapons = "weapon",
		shields = "shield",
		engines = "engine",
		thrusters = "thruster",
		turrets = "turret",
	}
	return types[safeString(category)] or ""
end

function ModLua.getDataAndDisplay_on_assemble_possible_upgrades(data)
	if not state.enabled or (state.kind ~= "weld" and state.kind ~= "salvage") or type(data) ~= "table" or not data.isreadonly or type(data.upgradewares) ~= "table" then
		return nil
	end
	local added = 0
	local filtered = 0
	-- This read-only SES configuration screen must not inherit the normal
	-- shipyard catalogue. Rebuild the five supported lists from exact MD
	-- compatibility results, retaining already-fitted and already-planned macros.
	-- The fitted rows are required by Ship Configuration's Overview calculation;
	-- dropping them caused every unchanged hardware category to disappear there.
	local fittedWares = {}
	for _, upgradetype in ipairs({ "weapon", "shield", "engine", "thruster", "turret" }) do
		fittedWares[upgradetype] = {}
		for _, entry in ipairs(type(data.upgradewares[upgradetype]) == "table" and data.upgradewares[upgradetype] or {}) do
			if not entry.isFromShipyard and numeric(entry.objectamount) > 0 and safeString(entry.macro or "") ~= "" then
				table.insert(fittedWares[upgradetype], entry)
			end
		end
		data.upgradewares[upgradetype] = fittedWares[upgradetype]
	end
	if state.kind == "salvage" then
		for _, item in ipairs(salvageRows()) do
			local upgradetype = nativeUpgradeTypeFromCategory(item.category)
			if upgradetype ~= "" and item.wareid ~= "" and item.macro ~= "" then
				local existing = nil
				for _, candidate in ipairs(data.upgradewares[upgradetype]) do
					if candidate.macro == item.macro then
						existing = candidate
						break
					end
				end
				if existing then
					existing.ware = item.wareid
					existing.name = item.name
					existing.objectamount = math.max(numeric(existing.objectamount), item.installed)
					existing.isFromShipyard = false
				else
					table.insert(data.upgradewares[upgradetype], {
						ware = item.wareid,
						macro = item.macro,
						name = item.name,
						objectamount = item.installed,
						isFromShipyard = false,
					})
				end
				added = added + 1
			end
		end
		emit("salvage_native_wares_injected", "rows=" .. tostring(added) .. ", version=" .. ses.version)
		return { upgradewares = data.upgradewares }
	end
	for _, item in ipairs(weldAvailableRows()) do
		local upgradetype = nativeUpgradeTypeFromCategory(item.category)
		-- Publish every structurally valid saved item. The per-tile callback is
		-- responsible for disabling unavailable rows and explaining why they
		-- cannot currently be added.
		if upgradetype ~= "" and item.wareid ~= "" and item.macro ~= "" then
			data.upgradewares[upgradetype] = data.upgradewares[upgradetype] or {}
			local duplicate = nil
			for _, existing in ipairs(data.upgradewares[upgradetype]) do
				if existing.macro == item.macro then
					duplicate = existing
					break
				end
			end
			if not duplicate then
				table.insert(data.upgradewares[upgradetype], {
					ware = item.wareid,
					macro = item.macro,
					name = item.name,
					objectamount = item.available,
					-- Ship Configuration treats non-provider group wares as equipment
					-- already owned by the physical ship and clamps their preview count
					-- to the currently installed count. Weld rows are instead supplied
					-- by SES inventory in this read-only menu, so expose them as provider
					-- stock for native preview accounting. SES still owns every stock,
					-- catalyst, compatibility, and apply-time authority check.
					isFromShipyard = true,
				})
				added = added + 1
			else
				-- A saved copy may match hardware already fitted to the ship. Keep one
				-- catalogue row, but expose the SES stock as provider-backed inventory.
				duplicate.ware = item.wareid
				duplicate.name = item.name
				duplicate.objectamount = item.available
				duplicate.isFromShipyard = true
			end
		else
			filtered = filtered + 1
		end
	end
	for _, item in ipairs(weldPlanRows()) do
		local upgradetype = nativeUpgradeTypeFromCategory(item.category)
		if upgradetype ~= "" and item.wareid ~= "" and item.macro ~= "" then
			local duplicate = false
			for _, existing in ipairs(data.upgradewares[upgradetype]) do
				if existing.macro == item.macro then
					duplicate = true
					break
				end
			end
			if not duplicate then
				table.insert(data.upgradewares[upgradetype], {
					ware = item.wareid,
					macro = item.macro,
					name = item.name,
					objectamount = 0,
					-- Keep an exhausted-but-planned weld row provider-backed as well so
					-- native redraws do not clamp an accepted grouped preview to zero.
					isFromShipyard = true,
				})
				added = added + 1
			end
		end
	end
	emit("weld_native_wares_injected", "rows=" .. tostring(added) .. ", filtered=" .. tostring(filtered) .. ", version=" .. ses.version)
	return { upgradewares = data.upgradewares }
end

weldPlanRows = function()
	local rows = {}
	for index, item in pairs(dataList("plan")) do
		table.insert(rows, {
			index = numeric(itemField(item, "index")) > 0 and numeric(itemField(item, "index")) or (tonumber(index) or 0),
			name = safeString(itemField(item, "name") or sesText(409, "Saved equipment")),
			wareid = safeString(itemField(item, "wareid") or ""),
			macro = safeString(itemField(item, "macro") or ""),
			faction = safeString(itemField(item, "faction") or ""),
			category = safeString(itemField(item, "category") or ""),
			quantity = math.max(1, numeric(itemField(item, "plannedquantity"))),
			cost = math.max(1, numeric(itemField(item, "bondingcatalystcost"))),
		})
	end
	table.sort(rows, function(a, b) return a.index < b.index end)
	return rows
end

local function frameProperties(config)
	local border = 3 * helperNumber("borderSize", 2)
	local width = helperNumber("viewWidth", 1920) * 0.78
	local height = helperNumber("viewHeight", 1080) * 0.62
	return {
		standardButtons = { close = true },
		width = width,
		height = height,
		x = (helperNumber("viewWidth", 1920) - width) / 2,
		y = (helperNumber("viewHeight", 1080) - height) / 2,
		layer = config.layer,
		startAnimation = false,
		playerControls = false,
	}
end

local function createPlannerTables(frame, kind)
	loadPlannerData()
	if kind == "salvage_result" then
		local border = 3 * helperNumber("borderSize", 2)
		local resultTable = frame:addTable(6, {
			tabOrder = 1,
			borderEnabled = true,
			width = (helperNumber("viewWidth", 1920) * 0.78) - (2 * border),
			x = border,
			y = 3 * helperNumber("borderSize", 2),
			maxVisibleHeight = helperNumber("viewHeight", 1080) * 0.68,
		})
		local row = resultTable:addRow(false, { fixed = true })
		row[1]:setColSpan(6):createText(sesText(411, "Avarice Beam Regulator - Salvage Results"), Helper.titleTextProperties)
		row = resultTable:addRow(false, { fixed = true })
		row[1]:setColSpan(6):createText(sesFormat(413, "Target: %s\nRecovered: %d / %d    Success: %d    Partial: %d    Failed: %d    Blocked: %d",
			safeString(itemField(plannerData, "targetname") or sesText(412, "Unknown target")),
			numeric(itemField(plannerData, "recovered")), numeric(itemField(plannerData, "attempted")),
			numeric(itemField(plannerData, "success")), numeric(itemField(plannerData, "partial")),
			numeric(itemField(plannerData, "failed")), numeric(itemField(plannerData, "blocked"))), { wordwrap = true, font = Helper.standardFontBold })
		row = resultTable:addRow(false, { fixed = true, bgColor = Color["row_title_background"] })
		row[1]:createText(sesText(414, "Result"), Helper.subHeaderTextProperties)
		row[2]:createText(sesText(415, "Recovered"), Helper.subHeaderTextProperties)
		row[3]:createText(sesText(416, "Chance"), Helper.subHeaderTextProperties)
		row[4]:setColSpan(2):createText(sesText(119, "Item"), Helper.subHeaderTextProperties)
		row[6]:createText(sesText(417, "Reason"), Helper.subHeaderTextProperties)
		for _, item in pairs(dataList("results")) do
			row = resultTable:addRow(false, {})
			local status = safeString(itemField(item, "status") or sesText(117, "Unknown"))
			row[1]:createText(status, { color = (status == sesText(703, "Success") or status == sesText(702, "Partial")) and Color["text_positive"] or Color["text_negative"] })
			row[2]:createText(tostring(numeric(itemField(item, "recovered"))) .. " / " .. tostring(numeric(itemField(item, "attempted"))))
			row[3]:createText(tostring(numeric(itemField(item, "chance"))) .. "%")
			row[4]:setColSpan(2):createText(equipmentName(item))
			row[6]:createText(safeString(itemField(item, "reason") or sesText(118, "Completed")), { wordwrap = true })
		end
		return resultTable
	end
	local leftLabel, rightLabel, catalystLabel = paneLabels(kind)
	local border = 3 * helperNumber("borderSize", 2)
	local width = (helperNumber("viewWidth", 1920) * 0.78) - (2 * border)
	local planner = frame:addTable(8, {
		tabOrder = 1,
		borderEnabled = true,
		width = width,
		x = border,
		y = border,
		maxVisibleHeight = helperNumber("viewHeight", 1080) * 0.58,
	})
	local row = planner:addRow(false, { fixed = true })
	row[1]:setColSpan(8):createText(plannerTitle(kind), Helper.titleTextProperties)
	row = planner:addRow(false, { fixed = true })
	row[1]:setColSpan(8):createText(sesFormat(418, "Target Ship: %s", state.target ~= "" and state.target or sesText(419, "Awaiting Mission Director context")), { wordwrap = true })

	if kind == "salvage" then
		local availableRows = salvageRows()
		local planRows = salvagePlanRows()
		local options = {}
		local selectedRow = nil
		for _, item in ipairs(availableRows) do
			table.insert(options, {
				id = item.index,
				text = categoryName(item.category) .. " - " .. item.name,
				icon = "",
				displayremoveoption = false,
			})
			if item.index == selectedSalvageIndex then
				selectedRow = item
			end
		end
		if not selectedRow and availableRows[1] then
			selectedRow = availableRows[1]
			selectedSalvageIndex = selectedRow.index
		end

		row = planner:addRow(false, { fixed = true })
		row[1]:setColSpan(4):createText(leftLabel, Helper.subHeaderTextProperties)
		row[5]:setColSpan(4):createText(rightLabel, Helper.subHeaderTextProperties)
		row = planner:addRow(true, { fixed = true })
		row[1]:createText(sesText(106, "Equipment"), { halign = "right" })
		if #options > 0 then
			row[2]:setColSpan(3):createDropDown(options, {
				startOption = selectedSalvageIndex,
				active = true,
				mouseOverText = sesText(420, "Choose installed equipment to add to the pending salvage plan."),
			})
			row[2].handlers.onDropDownConfirmed = function(_, value)
				selectedSalvageIndex = numeric(value)
				nativeAction("salvage_select", selectedSalvageIndex)
				if userQuestionMenu and getElapsedTime then
					userQuestionMenu.refresh = getElapsedTime()
				end
			end
		else
			row[2]:setColSpan(3):createText(sesText(421, "No supported installed equipment remains."))
		end
		row[5]:createText(sesText(422, "Rows"), { halign = "right" })
		row[6]:createText(tostring(#planRows))
		row[7]:createText(sesText(110, "Quantity"), { halign = "right" })
		row[8]:createText(tostring(state.pendingQuantity))

		row = planner:addRow(false, {})
		row[1]:createText(sesText(108, "Selected"), Helper.subHeaderTextProperties)
		row[2]:setColSpan(3):createText(selectedRow and selectedRow.name or "--")
		row[5]:createText(catalystLabel, Helper.subHeaderTextProperties)
		row[6]:createText(tostring(state.catalysts), { halign = "right" })
		row[7]:createText(sesText(423, "Plan cost"), Helper.subHeaderTextProperties)
		row[8]:createText(tostring(state.catalystCost), { halign = "right" })
		row = planner:addRow(false, {})
		row[1]:createText(sesText(107, "Category"))
		row[2]:createText(selectedRow and categoryName(selectedRow.category) or "--")
		row[3]:createText(sesText(111, "Installed"))
		row[4]:createText(selectedRow and tostring(selectedRow.installed) or "0", { halign = "right" })
		row[5]:createText(sesText(112, "Planned"))
		row[6]:createText(selectedRow and tostring(selectedRow.planned) or "0", { halign = "right" })
		row[7]:createText(sesText(424, "Add cost"))
		row[8]:createText(selectedRow and tostring(selectedRow.cost) or "0", { halign = "right" })
		row = planner:addRow(true, {})
		row[1]:setColSpan(4):createButton({ active = selectedRow and selectedRow.canAdd or false }):setText(selectedRow and sesFormat(425, "Add %d", selectedRow.addQuantity) or sesText(426, "Add Selected"), { halign = "center" })
		row[1].handlers.onClick = function()
			if selectedRow then
				nativeAction("salvage_add", selectedRow.index)
			end
		end
		row[5]:setColSpan(4):createText(selectedRow and (selectedRow.canAdd and sesText(116, "Ready") or sesText(427, "Already planned, unavailable, or needs catalysts")) or sesText(428, "No equipment selected"), { halign = "center" })

		if #planRows == 0 then
			row = planner:addRow(false, {})
			row[5]:setColSpan(4):createText(sesText(429, "-- No pending salvage --"), { halign = "center" })
		else
			for _, item in ipairs(planRows) do
				local planIndex = item.index
				row = planner:addRow(true, {})
				row[5]:createButton({ active = true }):setText(sesText(113, "Remove"), { halign = "center" })
				row[5].handlers.onClick = function()
					nativeAction("salvage_remove", planIndex)
				end
				row[6]:setColSpan(2):createText(tostring(item.quantity) .. " x " .. item.name)
				row[8]:createText(tostring(item.cost), { halign = "right" })
			end
		end

		row = planner:addRow(true, { fixed = true })
		row[3]:setColSpan(2):createButton({ active = #planRows > 0 and state.catalysts >= state.catalystCost }):setText(sesText(430, "Review Salvage"), { halign = "center" })
		row[3].handlers.onClick = function()
			suppressCleanupEvent = true
			if userQuestionMenu and userQuestionMenu.onCloseElement then
				userQuestionMenu.onCloseElement("close")
			end
			nativeAction("salvage_begin", 0)
		end
		row[5]:setColSpan(2):createButton({ active = #planRows > 0 }):setText(sesText(115, "Clear Plan"), { halign = "center" })
		row[5].handlers.onClick = function()
			nativeAction("salvage_clear", 0)
		end
		row[7]:setColSpan(2):createButton({ active = true }):setText(sesText(114, "Cancel"), { halign = "center" })
		row[7].handlers.onClick = function()
			closePlanner("button", true)
		end

		emit("native_opened", kind .. ";" .. ses.version)
		return planner
	end

	local categories = weldCategories()
	local availableRows = weldAvailableRows()
	local planRows = weldPlanRows()
	local categoryOptions = {}
	local selectedCategoryRow = nil
	for _, item in ipairs(categories) do
		table.insert(categoryOptions, {
			id = item.id,
			text = sesFormat(431, "%s (%d saved / %d open)", item.text, item.rows, item.open),
			icon = "",
			displayremoveoption = false,
		})
		if item.id == selectedWeldCategory then
			selectedCategoryRow = item
		end
	end
	if not selectedCategoryRow and categories[1] then
		selectedCategoryRow = categories[1]
		selectedWeldCategory = selectedCategoryRow.id
		nativeAction("weld_category", 0, selectedWeldCategory)
	end
	local inventoryOptions = {}
	local selectedInventoryRow = nil
	for _, item in ipairs(availableRows) do
		table.insert(inventoryOptions, {
			id = item.index,
			text = item.name .. " | " .. item.faction .. " | " .. item.status,
			icon = "",
			displayremoveoption = false,
		})
		if item.index == selectedWeldIndex then
			selectedInventoryRow = item
		end
	end
	if not selectedInventoryRow and availableRows[1] then
		selectedInventoryRow = availableRows[1]
		selectedWeldIndex = selectedInventoryRow.index
	end

	row = planner:addRow(false, { fixed = true })
	row[1]:setColSpan(4):createText(leftLabel, Helper.subHeaderTextProperties)
	row[5]:setColSpan(4):createText(rightLabel, Helper.subHeaderTextProperties)
	row = planner:addRow(true, { fixed = true })
	row[1]:createText(sesText(107, "Category"), { halign = "right" })
	if #categoryOptions > 0 then
		row[2]:setColSpan(3):createDropDown(categoryOptions, {
			startOption = selectedWeldCategory,
			active = true,
			mouseOverText = sesText(432, "Choose a saved-equipment category with inventory and open target capacity."),
		})
		row[2].handlers.onDropDownConfirmed = function(_, value)
			selectedWeldCategory = safeString(value)
			selectedWeldIndex = 0
			nativeAction("weld_category", 0, selectedWeldCategory)
		end
	else
		row[2]:setColSpan(3):createText(sesText(433, "No category currently has both saved parts and open target capacity."))
	end
	row[5]:createText(sesText(434, "Plan rows"), { halign = "right" })
	row[6]:createText(tostring(#planRows))
	row[7]:createText(sesText(110, "Quantity"), { halign = "right" })
	row[8]:createText(tostring(state.pendingQuantity))

	row = planner:addRow(true, { fixed = true })
	row[1]:createText(sesText(435, "Saved Part"), { halign = "right" })
	if #inventoryOptions > 0 then
		row[2]:setColSpan(3):createDropDown(inventoryOptions, {
			startOption = selectedWeldIndex,
			active = true,
			mouseOverText = sesText(436, "Choose a saved part. Compatibility is calculated against the live target loadout."),
		})
		row[2].handlers.onDropDownConfirmed = function(_, value)
			selectedWeldIndex = numeric(value)
			nativeAction("weld_select", selectedWeldIndex)
		end
	else
		row[2]:setColSpan(3):createText(#categoryOptions > 0 and sesText(437, "No compatible saved part in this category.") or sesText(438, "Awaiting compatible category data."))
	end
	row[5]:createText(catalystLabel, Helper.subHeaderTextProperties)
	row[6]:createText(tostring(state.catalysts), { halign = "right" })
	row[7]:createText(sesText(423, "Plan cost"), Helper.subHeaderTextProperties)
	row[8]:createText(tostring(state.catalystCost), { halign = "right" })

	row = planner:addRow(false, {})
	row[1]:createText(sesText(108, "Selected"), Helper.subHeaderTextProperties)
	row[2]:setColSpan(3):createText(selectedInventoryRow and selectedInventoryRow.name or "--")
	row[5]:createText(sesText(109, "Available"))
	row[6]:createText(selectedInventoryRow and tostring(selectedInventoryRow.available) or "0", { halign = "right" })
	row[7]:createText(sesText(439, "Install cost"))
	row[8]:createText(selectedInventoryRow and tostring(selectedInventoryRow.cost) or "0", { halign = "right" })
	row = planner:addRow(true, {})
	row[1]:setColSpan(4):createButton({ active = selectedInventoryRow and selectedInventoryRow.canAdd or false }):setText(selectedInventoryRow and sesFormat(425, "Add %d", selectedInventoryRow.quantity) or sesText(426, "Add Selected"), { halign = "center" })
	row[1].handlers.onClick = function()
		if selectedInventoryRow then
			nativeAction("weld_add", selectedInventoryRow.index)
		end
	end
	row[5]:setColSpan(4):createText(selectedInventoryRow and selectedInventoryRow.status or sesText(440, "No compatible part selected"), { halign = "center" })

	if #planRows == 0 then
		row = planner:addRow(false, {})
		row[5]:setColSpan(4):createText(sesText(441, "-- No pending installs --"), { halign = "center" })
	else
		for _, item in ipairs(planRows) do
			local planIndex = item.index
			row = planner:addRow(true, {})
			row[5]:createButton({ active = true }):setText(sesText(113, "Remove"), { halign = "center" })
			row[5].handlers.onClick = function()
				nativeAction("weld_remove", planIndex)
			end
			row[6]:setColSpan(2):createText(tostring(item.quantity) .. " x " .. item.name)
			row[8]:createText(tostring(item.cost), { halign = "right" })
		end
	end

	row = planner:addRow(true, { fixed = true })
	row[3]:setColSpan(2):createButton({ active = #planRows > 0 and state.catalysts >= state.catalystCost }):setText(sesText(442, "Install Loadout"), { halign = "center" })
	row[3].handlers.onClick = function()
		suppressCleanupEvent = true
		if userQuestionMenu and userQuestionMenu.onCloseElement then
			userQuestionMenu.onCloseElement("close")
		end
		nativeAction("weld_confirm", 0)
	end
	row[5]:setColSpan(2):createButton({ active = #planRows > 0 }):setText(sesText(115, "Clear Plan"), { halign = "center" })
	row[5].handlers.onClick = function()
		weldPreviewSlots = {}
		restoreWeldPreview()
		nativeAction("weld_clear", 0)
	end
	row[7]:setColSpan(2):createButton({ active = true }):setText(sesText(114, "Cancel"), { halign = "center" })
	row[7].handlers.onClick = function()
		closePlanner("button", true)
	end

	emit("native_opened", kind .. ";" .. ses.version)
	return planner
end

function ModLua.cleanup_end()
	local kind = currentPlannerKind()
	if kind == "salvage_result" then
		emit("native_salvage_result_close", 0)
		if shipConfigurationMenu and shipConfigurationMenu.onCloseElement then
			pcall(shipConfigurationMenu.onCloseElement, "close")
		end
		return
	end
	if kind ~= "" and not suppressCleanupEvent then
		emit("native_cancel", kind)
	end
	suppressCleanupEvent = false
end

function ModLua.createInfoFrame_custom_frame_properties(config)
	if currentPlannerKind() == "" then
		return nil
	end
	return frameProperties(config)
end

function ModLua.createTable_new_custom_table(frame)
	local kind = currentPlannerKind()
	if kind == "" then
		return nil
	end
	return createPlannerTables(frame, kind)
end

function ModLua.createTitleBar_on_create_controls(frame, ftable, _, menu, data)
	emit("weld_entry_callback_seen", "enabled=" .. safeString(state.enabled)
		.. ", kind=" .. safeString(state.kind)
		.. ", mode=" .. safeString(menu and menu.mode)
		.. ", version=" .. ses.version)
	if not state.enabled or (state.kind ~= "weld" and state.kind ~= "salvage") or not menu or menu.mode ~= "upgrade" or not menu.isReadOnly or not ftable then
		return
	end
	-- Ship Configuration can finish data assembly before this addon registers
	-- with UIX. Replace the native read-only catalogue here and add all saved
	-- macros to the already-derived slot lists. The button callback below still
	-- decides whether each entry is usable and explains unavailable choices.
	local nativeWares = ModLua.getDataAndDisplay_on_assemble_possible_upgrades({
		upgradewares = menu.upgradewares,
		mode = menu.mode,
		object = menu.object,
		macro = menu.macro,
		isreadonly = menu.isReadOnly,
	})
	if nativeWares and nativeWares.upgradewares then
		menu.upgradewares = nativeWares.upgradewares
	end
	local catalogueRows = state.kind == "weld" and weldAvailableRows() or salvageRows()
	if state.kind == "weld" then
		for _, item in ipairs(weldPlanRows()) do
			table.insert(catalogueRows, item)
		end
	end
	local macrosByType = {}
	for _, item in ipairs(catalogueRows) do
		local upgradetype = nativeUpgradeTypeFromCategory(item.category)
		if upgradetype ~= "" and item.macro ~= "" then
			macrosByType[upgradetype] = macrosByType[upgradetype] or {}
			macrosByType[upgradetype][item.macro] = true
		end
	end
	local function mergePossibleMacros(possiblemacros, macroset, isCompatible)
		if type(possiblemacros) ~= "table" or type(macroset) ~= "table" then
			return 0
		end
		local present = {}
		for _, macro in ipairs(possiblemacros) do
			present[macro] = true
		end
		local added = 0
		for macro in pairs(macroset) do
			if not present[macro] and isCompatible(macro) then
				table.insert(possiblemacros, macro)
				present[macro] = true
				added = added + 1
			end
		end
		table.sort(possiblemacros, Helper.sortMacroRaceAndShortname)
		return added
	end
	local possibleMacrosAdded = 0
	for upgradetype, slots in pairs(type(menu.slots) == "table" and menu.slots or {}) do
		for slotIndex, slot in ipairs(type(slots) == "table" and slots or {}) do
			possibleMacrosAdded = possibleMacrosAdded + mergePossibleMacros(slot.possiblemacros, macrosByType[upgradetype], function(macro)
				return nativeSlotCompatible(menu, upgradetype, slotIndex, macro, false)
			end)
		end
	end
	for groupIndex, group in ipairs(type(menu.groups) == "table" and menu.groups or {}) do
		for upgradetype, groupdata in pairs(type(group) == "table" and group or {}) do
			if type(groupdata) == "table" and type(groupdata.possiblemacros) == "table" then
				possibleMacrosAdded = possibleMacrosAdded + mergePossibleMacros(groupdata.possiblemacros, macrosByType[upgradetype], function(macro)
					return nativeSlotCompatible(menu, upgradetype, groupIndex, macro, true)
				end)
			end
		end
	end
	emit("native_possible_macros_injected", "rows=" .. tostring(#catalogueRows)
		.. ", added=" .. tostring(possibleMacrosAdded)
		.. ", version=" .. ses.version)
	if ftable.sesM5NativeWeldControlsAdded then
		return
	end
	ftable.sesM5NativeWeldControlsAdded = true

	local ok, err = pcall(function()
		local nativeCategory = nativeCategoryFromMode(menu.upgradetypeMode)
		if state.kind == "weld" and nativeCategory ~= "" and nativeCategory ~= selectedWeldCategory then
			selectedWeldCategory = nativeCategory
			selectedWeldIndex = 0
			nativeAction("weld_category", 0, nativeCategory)
		end

		local isSalvage = state.kind == "salvage"
		local planRows = isSalvage and salvagePlanRows() or weldPlanRows()
		local planData = menu.planData or {}
		local panel = frame:addTable(4, {
			tabOrder = 18,
			width = tonumber(planData.width) or (helperNumber("viewWidth", 1920) * 0.24),
			x = tonumber(planData.offsetX) or (helperNumber("viewWidth", 1920) * 0.75),
			y = 0,
			reserveScrollBar = false,
			backgroundID = "solid",
			backgroundColor = Color["table_background_3d_editor"],
		})
		panel:setColWidthPercent(1, 34)
		panel:setColWidthPercent(2, 24)
		panel:setColWidthPercent(3, 21)

		local summary = isSalvage and sesText(467, "Planned Salvage") or sesText(468, "Planned Installation")
		if weldResultText ~= "" then
			summary = summary .. " - " .. weldResultText
		end
		local row = panel:addRow(false, { fixed = true, bgColor = Color["row_title_background"] })
		row[1]:setColSpan(4):createText(summary, { font = Helper.standardFontBold, titleColor = Color["row_title"] })

		if #planRows == 0 then
			row = panel:addRow(false, { fixed = true })
			row[1]:setColSpan(4):createText(sesText(443, "-- No pending equipment --"), { halign = "center" })
		else
			for index, item in ipairs(planRows) do
				if index > 4 then
					row = panel:addRow(false, { fixed = true })
					row[1]:setColSpan(4):createText(sesFormat(444, "+ %d more planned item(s)", #planRows - 4), { color = Color["text_positive"] })
					break
				end
				row = panel:addRow(false, { fixed = true })
				local displayName = abbreviatedEquipmentName(item.name, item, item.macro)
				row[1]:setColSpan(4):createText((isSalvage and "- " or "+ ") .. tostring(item.quantity) .. " x " .. displayName, { color = isSalvage and Color["text_negative"] or Color["text_positive"], mouseOverText = categoryName(item.category) })
			end
		end

		row = panel:addRow(true, { fixed = true })
		row[1]:createText(isSalvage and sesFormat(446, "Beam Catalysts\nPlanned: %d  Total: %d", state.catalystCost, state.catalysts) or sesFormat(445, "Catalysts\nPlanned: %d  Total: %d", state.catalystCost, state.catalysts), { halign = "center", wordwrap = true, height = 2 * Helper.standardTextHeight })
		row[2]:createButton({
			active = #planRows > 0,
			mouseOverText = isSalvage and sesText(447, "Clear every item from the pending salvage plan and restore the preview.") or sesText(448, "Clear every saved part from the pending installation plan.")
		}):setText(sesText(115, "Clear Plan"), { halign = "center" })
		row[2].handlers.onClick = function()
			weldResultText = ""
			weldPendingReservations = {}
			weldPendingPreviewButton = nil
			weldPendingPreviewItem = nil
			weldPreviewExpectedRows = nil
			weldPreviewSlots = {}
			salvagePendingPreviewButton = nil
			salvagePendingPreviewItem = nil
			salvagePreviewExpectedRows = nil
			if isSalvage then
				salvagePreviewSelections = {}
				salvagePreviewNeedsReplay = false
				salvagePreviewReplayScheduled = false
			end
			restoreWeldPreview()
			nativeAction(isSalvage and "salvage_clear" or "weld_clear", 0)
		end
		row[3]:setColSpan(2):createButton({
			active = #planRows > 0 and state.catalysts >= state.catalystCost,
			mouseOverText = isSalvage and sesText(449, "Review the pending removals in a native confirmation dialog.") or sesText(450, "Open the final Apply Plan confirmation for the currently previewed loadout.")
		}):setText(isSalvage and sesText(430, "Review Salvage") or sesText(442, "Install Loadout"), { halign = "center" })
		row[3].handlers.onClick = function()
			weldResultText = isSalvage and sesText(469, "Salvage confirmation opened") or sesText(470, "Installation confirmation opened")
			if isSalvage then
				-- The native confirmation closes Ship Configuration. Preserve the
				-- accepted slot choices, then capture a fresh baseline and replay them
				-- if the player returns with Back to Plan.
				salvagePreviewNeedsReplay = #salvagePreviewSelections > 0
				salvagePreviewReplayScheduled = false
				weldPreviewBaseline = nil
				weldPreviewObject = ""
			end
			nativeAction(isSalvage and "salvage_begin" or "weld_confirm", 0)
		end
		local closeButtonHeight = Helper.scaleY(Helper.standardButtonHeight)
		local bottomOffset = tonumber(planData.offsetY) or Helper.frameBorder
		panel.properties.y = Helper.viewHeight - closeButtonHeight - panel:getFullHeight() - (2 * Helper.borderSize) - bottomOffset
		emit("weld_controls_added", "mode=" .. safeString(menu.mode)
			.. ", object=" .. safeString(menu.object)
			.. ", category=" .. safeString(nativeCategory)
			.. ", version=" .. ses.version)
	end)
	if not ok then
		emit("weld_controls_failed", "error=" .. safeString(err) .. ", version=" .. ses.version)
	end
	if state.kind == "salvage" and salvagePreviewNeedsReplay and not salvagePreviewReplayScheduled
		and Helper and Helper.addDelayedOneTimeCallbackOnUpdate and getElapsedTime then
		salvagePreviewReplayScheduled = true
		Helper.addDelayedOneTimeCallbackOnUpdate(function()
			salvagePreviewReplayScheduled = false
			if state.kind == "salvage" and salvagePreviewNeedsReplay then
				replaySalvagePreviewSelections()
			end
		end, true, getElapsedTime())
	end
end

function ModLua.displaySlots_on_create_upgrade_button(button)
	if not state.enabled or (state.kind ~= "weld" and state.kind ~= "salvage") or not shipConfigurationMenu or shipConfigurationMenu.mode ~= "upgrade" or not shipConfigurationMenu.isReadOnly or type(button) ~= "table" then
		return nil
	end
	local category = nativeCategoryFromMode(button.upgradetype or shipConfigurationMenu.upgradetypeMode)
	if category == "" then
		return nil
	end
	local macro = safeString(button.macro or "")
	if state.kind == "salvage" then
		if macro == "" then
			return { active = false, useable = false, mouseovertext = sesText(451, "Select installed equipment to add it to the salvage plan.") }
		end
		local salvageItem = nil
		for _, candidate in ipairs(salvageRows()) do
			if candidate.macro == macro and candidate.category == category then
				salvageItem = candidate
				break
			end
		end
		if not salvageItem then
			return { active = false, useable = false, mouseovertext = sesText(452, "This installed item is not salvageable.") }
		end
		-- Ship Configuration shows every compatible catalogue macro for the
		-- selected slot. Salvage must only act on the macro that is actually in
		-- that slot/group; otherwise selecting (for example) a Boson tile while a
		-- Gatling slot is selected queues one Boson in MD but removes the Gatling
		-- from the native preview. Duplicate counts then reach zero independently
		-- of the slot tabs and the UI can no longer represent the queued plan.
		local isInstalledInSelectedSlot = safeString(button.plannedmacro or "") == macro
		local canAddFromSelectedSlot = isInstalledInSelectedSlot and salvageItem.canAdd
		local status = sesFormat(453, "Installed: %d  |  Planned: %d  |  Beam Catalyst cost: %d", salvageItem.installed, salvageItem.planned, salvageItem.cost)
		if not isInstalledInSelectedSlot then
			status = sesFormat(454, "Select the slot or group where this item is currently installed.  |  %s", status)
		end
		return {
			active = canAddFromSelectedSlot,
			useable = canAddFromSelectedSlot,
			mouseovertext = status,
			extratext = sesFormat(471, "%s\nInstalled: %d", nativeTileName(button, salvageItem, macro), math.max(0, salvageItem.installed - salvageItem.planned)),
			onclick = canAddFromSelectedSlot and function()
				selectedSalvageIndex = salvageItem.index
				weldResultText = ""
				salvagePendingPreviewButton = {
					macro = button.macro,
					upgradetype = button.upgradetype,
					slot = button.slot,
					grouped = button.grouped,
				}
				salvagePendingPreviewItem = salvageItem
				salvagePreviewExpectedRows = state.pendingRows + 1
				nativeAction("salvage_add", salvageItem.index)
			end or nil,
		}
	end
	if macro == "" then
		return {
			active = false,
			useable = false,
			mouseovertext = sesText(456, "The Avarice Bonding Regulator installs saved equipment; empty-slot removal is unavailable here."),
		}
	end
	local nativePlanned = macro ~= "" and safeString(button.plannedmacro or "") == macro
	local authoritativePlannedQuantity = plannedWeldQuantity(macro, category)
	local isUngroupedWeapon = category == "weapons" and not button.grouped
	local slotKey = weldSlotKey(button)
	local acceptedSlotMacro = safeString(weldPreviewSlots[slotKey] or "")
	local pendingSlotMacro = pendingWeldSlotMacro(button)
	local slotReservedForPreview = acceptedSlotMacro ~= "" or pendingSlotMacro ~= ""
	local nativeFiniteSlotCategory = category == "weapons" or category == "shields" or category == "turrets"
	local selectedSlotCurrentMacro = ""
	if nativeFiniteSlotCategory then
		local upgradeSlots = type(shipConfigurationMenu.slots) == "table" and shipConfigurationMenu.slots[button.upgradetype] or nil
		local slotData = type(upgradeSlots) == "table" and upgradeSlots[numeric(button.slot)] or nil
		selectedSlotCurrentMacro = type(slotData) == "table" and safeString(slotData.currentmacro or "") or ""
	end
	local selectedSlotOccupied = selectedSlotCurrentMacro ~= ""
	local isInstalledInSelectedSlot = selectedSlotCurrentMacro == macro
	-- Native plannedmacro is catalogue-wide for merged S/M weapon presentation:
	-- once one saved macro is previewed it can appear planned on sibling tabs.
	-- Track the exact native slot accepted by SES instead, so a macro planned in
	-- S1 does not lock S2-S5 (or make two distinct macros cap the plan at two).
	local isPlanned = nativePlanned
	if isUngroupedWeapon then
		isPlanned = acceptedSlotMacro == macro or pendingSlotMacro == macro
	end
	local item = findWeldInventoryRow(macro, category)
	if not item then
		if isUngroupedWeapon then
			local diagnosticKey = category .. "|" .. tostring(numeric(button.slot)) .. "|" .. macro
			local diagnostic = "item=0, current=" .. tostring(isInstalledInSelectedSlot)
				.. ", occupied=" .. tostring(selectedSlotOccupied)
				.. ", currentmacro=" .. selectedSlotCurrentMacro
				.. ", nativeplanned=" .. tostring(nativePlanned)
				.. ", sesplanned=" .. tostring(authoritativePlannedQuantity)
			if weldTileStateDiagnostics[diagnosticKey] ~= diagnostic then
				weldTileStateDiagnostics[diagnosticKey] = diagnostic
				emit("weld_weapon_tile_state", "slot=" .. tostring(numeric(button.slot)) .. ", macro=" .. macro .. ", " .. diagnostic .. ", version=" .. ses.version)
			end
		end
		return {
			active = isInstalledInSelectedSlot or isPlanned,
			useable = false,
			mouseovertext = authoritativePlannedQuantity > 0 and sesText(457, "All saved copies are already assigned to the pending installation plan.") or sesText(458, "No saved copy is available in the SES salvage inventory."),
			extratext = sesFormat(472, "%s\nSaved: %d", nativeTileName(button, nil, macro), 0),
		}
	end
	local remaining = remainingWeldQuantity(item)
	local slotCompatible = nativeSlotCompatible(shipConfigurationMenu, button.upgradetype, button.slot, macro, button.grouped)
	-- As on the salvage side, the native Ship Configuration slot is the
	-- authority for component compatibility. generate_loadout expands a single
	-- S/M weapon or shield macro across sibling slots, so its category totals
	-- cannot safely decide whether this one selected native slot is clickable.
	-- MD still independently enforces target state, stock, capacity and catalyst
	-- costs when it receives the add request.
	local nativeSlotAuthority = nativeFiniteSlotCategory
	local catalystsAvailable = state.catalysts >= (state.catalystCost + item.cost)
	local mdOrNativeEligible = item.canAdd or nativeSlotAuthority
	local requestPending = weldPreviewExpectedRows ~= nil
	local canAdd = slotCompatible and (not selectedSlotOccupied) and (not isPlanned)
		and (not slotReservedForPreview)
		and (not requestPending) and mdOrNativeEligible and catalystsAvailable and remaining >= item.quantity
	local receipt = sesFormat(472, "%s\nSaved: %d", nativeTileName(button, item, macro), remaining)
	local status = sesFormat(460, "Saved: %d  |  Cost: %d", remaining, item.cost)
	if isInstalledInSelectedSlot then
		status = sesFormat(461, "This component is already installed in the selected slot  |  %s", status)
	elseif selectedSlotOccupied then
		status = sesFormat(462, "The selected slot already contains a component. Salvage it before welding a replacement.  |  %s", status)
	elseif slotReservedForPreview and not isPlanned then
		status = sesFormat(463, "This slot already has a pending SES installation  |  %s", status)
	elseif requestPending then
		status = sesFormat(464, "Waiting for the previous SES selection  |  %s", status)
	elseif not slotCompatible then
		status = sesFormat(465, "Not compatible with the selected slot  |  %s", status)
	elseif not catalystsAvailable then
		status = sesFormat(466, "Need %d more available Catalyst capacity  |  %s", item.cost, status)
	elseif not nativeSlotAuthority and item.status ~= "" and item.status ~= "Compatible" then
		status = item.status .. "  |  " .. status
	end
	if isUngroupedWeapon then
		local diagnosticKey = category .. "|" .. tostring(numeric(button.slot)) .. "|" .. macro
		local diagnostic = "item=1, current=" .. tostring(isInstalledInSelectedSlot)
			.. ", occupied=" .. tostring(selectedSlotOccupied)
			.. ", currentmacro=" .. selectedSlotCurrentMacro
			.. ", nativeplanned=" .. tostring(nativePlanned)
			.. ", sesplanned=" .. tostring(authoritativePlannedQuantity)
			.. ", slotplanned=" .. safeString(acceptedSlotMacro)
			.. ", slotpending=" .. safeString(pendingSlotMacro)
			.. ", mdcanadd=" .. tostring(item.canAdd)
			.. ", remaining=" .. tostring(remaining)
			.. ", compatible=" .. tostring(slotCompatible)
			.. ", canadd=" .. tostring(canAdd)
		if weldTileStateDiagnostics[diagnosticKey] ~= diagnostic then
			weldTileStateDiagnostics[diagnosticKey] = diagnostic
			emit("weld_weapon_tile_state", "slot=" .. tostring(numeric(button.slot)) .. ", macro=" .. macro .. ", " .. diagnostic .. ", version=" .. ses.version)
		end
	end
	return {
		active = slotCompatible and (isInstalledInSelectedSlot or isPlanned or canAdd),
		useable = canAdd,
		mouseovertext = status,
		extratext = receipt,
		onclick = canAdd and function()
			if remainingWeldQuantity(item) < item.quantity then
				emit("weld_add_blocked_no_stock", "macro=" .. safeString(item.macro) .. ", version=" .. ses.version)
				refreshShipConfiguration()
				return
			end
			selectedWeldIndex = item.index
			weldResultText = ""
			weldPendingPreviewButton = {
				macro = button.macro,
				plannedmacro = button.plannedmacro,
				upgradetype = button.upgradetype,
				slot = button.slot,
				grouped = button.grouped,
			}
			weldPendingPreviewItem = item
			weldPreviewExpectedRows = state.pendingRows + 1
			reserveWeldQuantity(item)
			-- Redraw immediately so a rapid second click cannot overwrite the one
			-- in-flight MD acknowledgement and attach its preview to the wrong slot.
			refreshShipConfiguration()
			nativeAction("weld_add", item.index)
		end or nil,
	}
end

function ModLua.onShowMenu_on_check_selectable_ship_owner(data)
	if not state.enabled or state.kind ~= "salvage" or type(data) ~= "table"
		or data.mode ~= "upgrade" or not data.isreadonly or data.ownerallowed then
		return nil
	end
	loadPlannerData()
	if state.targetID == "" then
		return nil
	end
	local target = tonumber(state.targetID)
	local ship = tonumber(data.ship)
	local matches = target and ship and ship == target
	emit("shipconfig_nonplayer_owner_checked", "target=" .. safeString(state.targetID)
		.. ", targetnumeric=" .. safeString(target)
		.. ", ship=" .. safeString(data.ship)
		.. ", shipnumeric=" .. safeString(ship)
		.. ", allowed=" .. safeString(matches)
		.. ", version=" .. ses.version)
	if matches then
		return { ownerallowed = true }
	end
	return nil
end

local function callbackAlreadyRegistered(menu, callbackName, callback)
	if not menu.uix_callbacks or not menu.uix_callbacks[callbackName] then
		return false
	end
	for _, existing in pairs(menu.uix_callbacks[callbackName]) do
		if existing == callback then
			return true
		end
	end
	return false
end

local function registerShipConfigurationCallbacks()
	shipConfigurationMenu = (Helper and Helper.uix_shipConfigurationMenu) or findMenuByName("ShipConfigurationMenu", "ShipConfigurationMenu")
	if not shipConfigurationMenu or not shipConfigurationMenu.registerCallback then
		emit("shipconfig_callback_missing", ses.version)
		return false
	end
	local bridge = shipConfigurationMenu.uix_fire_createTitleBar_on_create_controls
	if type(bridge) ~= "function" then
		emit("shipconfig_bridge_missing", ses.version)
		return false
	end
	if shipConfigurationMenu.sesM5NativePlannerCallbacksVersion == ses.version
		and callbackAlreadyRegistered(shipConfigurationMenu, "uix_fire_createTitleBar_on_create_controls", bridge)
		and callbackAlreadyRegistered(shipConfigurationMenu, "createTitleBar_on_create_controls", ModLua.createTitleBar_on_create_controls)
		and callbackAlreadyRegistered(shipConfigurationMenu, "getDataAndDisplay_on_assemble_possible_upgrades", ModLua.getDataAndDisplay_on_assemble_possible_upgrades)
		and callbackAlreadyRegistered(shipConfigurationMenu, "displaySlots_on_create_upgrade_button", ModLua.displaySlots_on_create_upgrade_button)
		and callbackAlreadyRegistered(shipConfigurationMenu, "onShowMenu_on_check_selectable_ship_owner", ModLua.onShowMenu_on_check_selectable_ship_owner) then
		return true
	end
	if not callbackAlreadyRegistered(shipConfigurationMenu, "uix_fire_createTitleBar_on_create_controls", bridge) then
		shipConfigurationMenu.registerCallback("uix_fire_createTitleBar_on_create_controls", bridge, ses.bridgeCallbackID)
	end
	if not callbackAlreadyRegistered(shipConfigurationMenu, "createTitleBar_on_create_controls", ModLua.createTitleBar_on_create_controls) then
		shipConfigurationMenu.registerCallback("createTitleBar_on_create_controls", ModLua.createTitleBar_on_create_controls, ses.callbackID)
	end
	if not callbackAlreadyRegistered(shipConfigurationMenu, "getDataAndDisplay_on_assemble_possible_upgrades", ModLua.getDataAndDisplay_on_assemble_possible_upgrades) then
		shipConfigurationMenu.registerCallback("getDataAndDisplay_on_assemble_possible_upgrades", ModLua.getDataAndDisplay_on_assemble_possible_upgrades, "ship_equipment_salvaging_m5_native_wares")
	end
	if not callbackAlreadyRegistered(shipConfigurationMenu, "displaySlots_on_create_upgrade_button", ModLua.displaySlots_on_create_upgrade_button) then
		shipConfigurationMenu.registerCallback("displaySlots_on_create_upgrade_button", ModLua.displaySlots_on_create_upgrade_button, "ship_equipment_salvaging_m5_native_equipment")
	end
	if not callbackAlreadyRegistered(shipConfigurationMenu, "onShowMenu_on_check_selectable_ship_owner", ModLua.onShowMenu_on_check_selectable_ship_owner) then
		shipConfigurationMenu.registerCallback("onShowMenu_on_check_selectable_ship_owner", ModLua.onShowMenu_on_check_selectable_ship_owner, "ship_equipment_salvaging_m5_ownerless_readonly_target")
	end
	shipConfigurationMenu.sesM5NativePlannerCallbacksVersion = ses.version
	emit("shipconfig_callbacks_registered", ses.version)
	return true
end

local function registerUserQuestionCallbacks()
	userQuestionMenu = findMenuByName("UserQuestionMenu", "UserQuestionMenu")
	if not userQuestionMenu or not userQuestionMenu.registerCallback then
		emit("userquestion_callback_missing", ses.version)
		return false
	end
	if userQuestionMenu.sesM5NativePlannerCallbacksVersion == ses.version then
		return true
	end
	userQuestionMenu.registerCallback("cleanup_end", ModLua.cleanup_end, "ship_equipment_salvaging_m5_native_planners")
	userQuestionMenu.registerCallback("createInfoFrame_custom_frame_properties", ModLua.createInfoFrame_custom_frame_properties, "ship_equipment_salvaging_m5_native_planners")
	userQuestionMenu.registerCallback("createTable_new_custom_table", ModLua.createTable_new_custom_table, "ship_equipment_salvaging_m5_native_planners")
	userQuestionMenu.sesM5NativePlannerCallbacksVersion = ses.version
	emit("userquestion_callbacks_registered", ses.version)
	return true
end

runRegistration = function(reason)
	local userQuestionOK = registerUserQuestionCallbacks()
	local shipConfigurationOK = registerShipConfigurationCallbacks()
	sesLog("Registration pass " .. safeString(reason) .. ": userquestion=" .. safeString(userQuestionOK)
		.. ", shipconfiguration=" .. safeString(shipConfigurationOK))
end

function ModLua.init()
	sesLog("Loaded gated Milestone 5 native Ship Configuration equipment integration.")
	emit("lua_loaded", ses.version)
	if RegisterEvent then
		local ok, err = pcall(RegisterEvent, "SES.M5.NativePlanner", parseState)
		emit(ok and "state_event_registered" or "state_event_register_failed", safeString(err or ses.version))
	end
	runRegistration("init")
	emit("state_request", ses.version)

	if Register_OnLoad_Init then
		Register_OnLoad_Init(function()
			runRegistration("onload")
			emit("state_request", ses.version)
		end, "SES Milestone 5 native planner callbacks")
	end
	if Helper and Helper.addDelayedOneTimeCallbackOnUpdate and getElapsedTime then
		Helper.addDelayedOneTimeCallbackOnUpdate(function()
			runRegistration("delayed_1s")
		end, true, getElapsedTime() + 1)
		Helper.addDelayedOneTimeCallbackOnUpdate(function()
			runRegistration("delayed_3s")
			emit("state_request", ses.version)
		end, true, getElapsedTime() + 3)
	end
end

ModLua.init()

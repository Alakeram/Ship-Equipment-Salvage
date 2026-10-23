-- Ship Equipment Salvaging
-- Kuertee UI Extensions-compatible Player Information > Player Inventory
-- Salvage Inventory tab. This file is loaded through the X4 ui.xml addon
-- path and patches PlayerInfoMenu only through its exposed config/menu surface.

local ffi = require("ffi")
local C = ffi.C
pcall(ffi.cdef, [[
	typedef uint64_t UniverseID;
	UniverseID GetPlayerID(void);
]])

local ses = {
	version = "v411",
	screen = "SES_Salvage_Inventory_UI",
	category = "ses_salvage",
	patchid = "ship_equipment_salvaging",
}

local state = {
	rows = {},
	visible = 0,
	total = 0,
	loading = true,
	lastrequest = nil,
	lastdone = nil,
	subview = "saved",
	fabrication = { beta = false, patterns = {}, refines = {}, research = {} },
	fabricationFilters = { category = "all", size = "all", maker = "all", grade = "all", known = false, search = "" },
}

local function sesLog(message)
	print("[SES][INV UI] " .. tostring(message))
end

local function safeString(value)
	local ok, result = pcall(tostring, value)
	if ok then
		return result
	end
	return "<tostring failed>"
end

local function emit(control, param)
	if AddUITriggeredEvent then
		pcall(AddUITriggeredEvent, ses.screen, control, param or ses.version)
	end
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

local function splitPayload(text)
	local parts = {}
	local value = safeString(text or "")
	local start = 1
	while true do
		local separator = string.find(value, ";", start, true)
		if not separator then
			table.insert(parts, string.sub(value, start))
			break
		end
		table.insert(parts, string.sub(value, start, separator - 1))
		start = separator + 1
	end
	return parts
end

local function requestInventory(source)
	state.loading = true
	state.lastrequest = source or "unknown"
	emit("inventory_request", "source=" .. safeString(source or "unknown") .. ", version=" .. ses.version)
end

local function requestDropOne(index)
	local numericindex = tonumber(index)
	if numericindex and numericindex > 0 then
		emit("drop_one", numericindex)
	end
end

local function onSalvageInventory(_, param)
	local parts = splitPayload(param)
	local kind = parts[1] or ""

	if kind == "begin" then
		state.rows = {}
		state.visible = 0
		state.total = tonumber(parts[2]) or 0
		state.loading = true
	elseif kind == "row" then
		local row = {
			index = tonumber(parts[2]) or 0,
			category = parts[3] or "",
			ware = parts[4] or "",
			macro = parts[5] or "",
			count = tonumber(parts[6]) or 0,
		}
		if row.index > 0 and row.count > 0 then
			table.insert(state.rows, row)
		end
	elseif kind == "done" then
		state.visible = tonumber(parts[2]) or #state.rows
		state.total = tonumber(parts[3]) or state.total
		state.loading = false
		state.lastdone = getElapsedTime and getElapsedTime() or nil
		local menu = findMenuByName("PlayerInfoMenu", "PlayerInfoMenu")
		if menu and menu.mode == "inventory" and menu.inventoryData and menu.inventoryData.mode == ses.category and type(menu.refreshInfoFrame) == "function" then
			local ok, err = pcall(menu.refreshInfoFrame)
			if not ok then
				sesLog("Salvage Inventory refresh failed. reason=inventory_done, subview=" .. tostring(state.subview) .. ", error=" .. tostring(err))
			end
		end
	elseif kind == "drop_result" then
		state.loading = true
		requestInventory("drop_result")
	else
		emit("inventory_event_rejected", "param=" .. safeString(param))
	end
end

local function registerInventoryEvent()
	if RegisterEvent and not (_G and _G.__ses_salvage_inventory_event_registered) then
		local ok, err = pcall(RegisterEvent, "SES.SalvageInventory", onSalvageInventory)
		if ok then
			if _G then
				_G.__ses_salvage_inventory_event_registered = true
			end
			emit("inventory_event_registered", ses.version)
		else
			emit("inventory_event_register_failed", safeString(err))
		end
	end
end

local function wareDisplayName(ware)
	if GetWareData and type(ware) == "string" and ware ~= "" then
		local ok, name = pcall(GetWareData, ware, "name")
		if ok and name and name ~= "" then
			return name
		end
	end
	return ware
end

local function macroDisplayName(macro, fallback)
	if GetMacroData and type(macro) == "string" and macro ~= "" then
		local ok, name = pcall(GetMacroData, macro, "name")
		if ok and name and name ~= "" then
			return name
		end
	end
	return fallback or macro
end

local function readText(page, id, fallback)
	if ReadText then
		local ok, text = pcall(ReadText, page, id)
		if ok and text and text ~= "" then
			return text
		end
	end
	return fallback
end

local function sesText(id, fallback)
	return readText(1171361, id, fallback)
end

local function sesFormat(id, fallback, ...)
	local ok, value = pcall(string.format, sesText(id, fallback), ...)
	if ok then
		return value
	end
	local fallbackOK, fallbackValue = pcall(string.format, fallback or "", ...)
	return fallbackOK and fallbackValue or (fallback or "")
end

-- Vanilla names an M-ship turret/shield (unhittable mount) and its L/XL-ship
-- twin (hittable "standard" mount) the same. MD publishes the L/XL-only ware
-- IDs (global.$SES_Future_LXL_WareIds).
local lxlWareIds = {}

-- M-ship parts stay untagged (the name already says M); only L/XL-only wares
-- a player owns are marked, so they are not mistaken for M-ship parts.
local function withTurretVariant(wareid, name)
	if type(wareid) ~= "string" or type(name) ~= "string" or name == "" then return name end
	if lxlWareIds[wareid] then
		return name .. " (" .. sesText(1204, "L/XL-Class") .. ")"
	end
	return name
end

local function wareAvgPrice(ware)
	if GetWareData and type(ware) == "string" and ware ~= "" then
		local ok, avgprice = pcall(GetWareData, ware, "avgprice")
		if ok and tonumber(avgprice) then
			return tonumber(avgprice)
		end
	end
	return 0
end

local function moneyText(value)
	local amount = tonumber(value) or 0
	if ConvertMoneyString then
		local ok, text = pcall(ConvertMoneyString, amount, false, true, 0, true)
		if ok and text then
			return text .. " " .. readText(1001, 101, "Cr")
		end
	end
	return tostring(amount) .. " " .. readText(1001, 101, "Cr")
end

local function markSafeRefresh(reason)
	state.forceSafeRefresh = true
	state.forceSafeRefreshReason = safeString(reason or "unknown")
end

local function tableId(tablehandle)
	if tablehandle and tablehandle.id then
		return tablehandle.id
	end
	return nil
end

local function clearInventoryTableState(playerInfoMenu, reason)
	if not playerInfoMenu then
		return
	end

	local infotableid = tableId(playerInfoMenu.inventoryInfoTable)
	local buttontableid = tableId(playerInfoMenu.inventoryButtonTable)
	local headertableid = tableId(playerInfoMenu.inventoryHeaderTable)

	if playerInfoMenu.selectedRows then
		playerInfoMenu.selectedRows["inventoryHeaderTable"] = nil
		if infotableid then
			playerInfoMenu.selectedRows[infotableid] = nil
		end
		if buttontableid then
			playerInfoMenu.selectedRows[buttontableid] = nil
		end
		if headertableid then
			playerInfoMenu.selectedRows[headertableid] = nil
		end
	end
	if playerInfoMenu.selectedCols then
		playerInfoMenu.selectedCols["inventoryHeaderTable"] = nil
		if infotableid then
			playerInfoMenu.selectedCols[infotableid] = nil
		end
		if buttontableid then
			playerInfoMenu.selectedCols[buttontableid] = nil
		end
		if headertableid then
			playerInfoMenu.selectedCols[headertableid] = nil
		end
	end
	if (playerInfoMenu.lastactivetable == infotableid) or (playerInfoMenu.lastactivetable == buttontableid) or (playerInfoMenu.lastactivetable == headertableid) then
		playerInfoMenu.lastactivetable = nil
	end
	if infotableid and (playerInfoMenu.infoTable == infotableid) then
		playerInfoMenu.infoTable = nil
	end
	playerInfoMenu.inventoryInfoTable = nil
	playerInfoMenu.inventoryButtonTable = nil
	playerInfoMenu.inventoryHeaderTable = nil
	playerInfoMenu.settoprow = nil
	playerInfoMenu.setselectedrow = nil
	playerInfoMenu.setselectedrow2 = nil
	playerInfoMenu.setselectedcol = nil
	playerInfoMenu.setselectedcol2 = nil
	markSafeRefresh(reason)
	emit("playerinfo_clear_table_state", "reason=" .. safeString(reason or "unknown") .. ", version=" .. ses.version)
end

local function currentEntryIndex(playerInfoMenu, infotable)
	if Helper and Helper.getCurrentRowData and infotable and infotable.id then
		local rowdata = Helper.getCurrentRowData(playerInfoMenu, infotable.id)
		if type(rowdata) == "table" and rowdata.ses_index then
			return tonumber(rowdata.ses_index)
		elseif type(rowdata) == "string" then
			return tonumber(string.match(rowdata, "^ses_salvage_(%d+)$"))
		end
	end
	return nil
end

local function categoryKey(category)
	local value = string.lower(tostring(category or ""))
	value = string.gsub(value, "[%s_%-]", "")
	if value == "weapon" or value == "weapons" or value == "missilelauncher" or value == "missilelaunchers" then
		return "weapons"
	elseif value == "turret" or value == "turrets" then
		return "turrets"
	elseif value == "shield" or value == "shields" or value == "shieldgenerator" or value == "shieldgenerators" then
		return "shields"
	elseif value == "engine" or value == "engines" then
		return "engines"
	elseif value == "thruster" or value == "thrusters" then
		return "thrusters"
	end
	return value ~= "" and value or "other"
end

local function categoryName(key, rawcategory)
	local names = {
		weapons = sesText(100, "Weapons"),
		turrets = sesText(104, "Turrets"),
		shields = sesText(101, "Shield Generators"),
		engines = sesText(102, "Engines"),
		thrusters = sesText(103, "Thrusters"),
		other = sesText(105, "Other Equipment"),
	}
	return names[key] or tostring(rawcategory or sesText(105, "Other Equipment"))
end

-- MD owns recipes, material balances, learned patterns, revisions and tokens.
-- This view only presents a snapshot and submits an exact one-item request.
local function fabricationField(value, key)
	if type(value) ~= "table" then return nil end
	if value[key] ~= nil then return value[key] end
	return value["$" .. key]
end

local function fabricationNumber(value)
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function fabricationBool(value)
	return value == true or value == 1
end

-- Crafting Bench integration. When the installed UI Extensions supports these
-- CraftingMenu callbacks, Fabrication becomes a tab in the vanilla Crafting
-- menu. Otherwise (older or Workshop UIX builds) it stays in Salvage Inventory,
-- gated by the MD bench session. Detected by feature, not by version: UIX
-- keeps content.xml at 900 for every 9.0.0.x release.
local CRAFTING_TAB_ID = "ses_fabrication"
-- Named like the accepted ShipConfiguration hooks (PR #111/#112):
-- <function>_on_<verb>_<thing>, one context table in, a named result table out.
local CRAFTING_CALLBACKS = { "createCrafting_on_assemble_categories", "createCrafting_on_create_category_rows" }

local function craftingHookSupported(craftingMenu)
	if not craftingMenu or type(craftingMenu.registerCallback) ~= "function" or type(craftingMenu.uix_isCallbackSupported) ~= "function" then
		return false
	end
	for _, callbackName in ipairs(CRAFTING_CALLBACKS) do
		local ok, supported = pcall(craftingMenu.uix_isCallbackSupported, callbackName)
		if not ok or not supported then return false end
	end
	return true
end

local function refreshCraftingView(reason)
	local craftingMenu = findMenuByName("CraftingMenu", "CraftingMenu")
	if craftingMenu and craftingMenu.sesCraftingHookActive and craftingMenu.category == CRAFTING_TAB_ID and craftingMenu.infoFrame and type(craftingMenu.refreshInfoFrame) == "function" then
		local ok, err = pcall(craftingMenu.refreshInfoFrame)
		if not ok then
			sesLog("Crafting menu refresh failed. reason=" .. tostring(reason) .. ", error=" .. tostring(err))
		end
	end
end

local function refreshSalvageView(reason)
	refreshCraftingView(reason)
	local menu = findMenuByName("PlayerInfoMenu", "PlayerInfoMenu")
	if menu and menu.mode == "inventory" and menu.inventoryData and menu.inventoryData.mode == ses.category and type(menu.refreshInfoFrame) == "function" then
		clearInventoryTableState(menu, reason)
		local ok, err = pcall(menu.refreshInfoFrame, 1, 1)
		if not ok then
			sesLog("Salvage Inventory refresh failed. reason=" .. tostring(reason) .. ", subview=" .. tostring(state.subview) .. ", error=" .. tostring(err))
		end
	end
end

local function loadFabricationState()
	if not GetNPCBlackboard or not ConvertStringTo64Bit then return false end
	local ok, data = pcall(function()
		return GetNPCBlackboard(ConvertStringTo64Bit(tostring(C.GetPlayerID())), "$SES_Fabrication_UI_State")
	end)
	if not ok or type(data) ~= "table" then return false end
	local snapshot = {
		beta = fabricationBool(fabricationField(data, "beta")),
		atbench = fabricationBool(fabricationField(data, "atbench")),
		revision = fabricationNumber(fabricationField(data, "revision")),
		token = fabricationField(data, "token"),
		result = fabricationField(data, "result") or "",
		patterns = {},
		refines = {},
	}
	-- L/XL-only wares (mount class tags); read before any name is tagged.
	lxlWareIds = {}
	for _, lxlid in ipairs(fabricationField(data, "lxlids") or {}) do
		lxlWareIds[tostring(lxlid)] = true
	end
	-- Ingredient rows published by MD: { wareid, name, need, have }.
	local function readInputs(item)
		local inputs = {}
		for _, input in ipairs(fabricationField(item, "inputs") or {}) do
			local wareid = tostring(fabricationField(input, "wareid") or "")
			if wareid ~= "" then
				table.insert(inputs, { wareid = wareid, name = tostring(fabricationField(input, "name") or wareid), need = fabricationNumber(fabricationField(input, "need")), have = fabricationNumber(fabricationField(input, "have")) })
			end
		end
		return inputs
	end
	for _, item in ipairs(fabricationField(data, "patterns") or {}) do
		local entry = { action = "fabricate" }
		for _, key in ipairs({ "wareid", "macro", "name", "category", "size", "maker", "grade", "reason" }) do
			entry[key] = tostring(fabricationField(item, key) or "")
		end
		entry.owned = fabricationNumber(fabricationField(item, "owned"))
		entry.unlocked = fabricationBool(fabricationField(item, "unlocked"))
		entry.inputs = readInputs(item)
		entry.name = withTurretVariant(entry.wareid, entry.name)
		if entry.wareid ~= "" then table.insert(snapshot.patterns, entry) end
	end
	-- Bench refining (cores, casings): always known, output credited to inventory.
	for _, item in ipairs(fabricationField(data, "refines") or {}) do
		local entry = { action = "refine", unlocked = true }
		entry.wareid = tostring(fabricationField(item, "wareid") or "")
		entry.name = tostring(fabricationField(item, "name") or entry.wareid)
		entry.owned = fabricationNumber(fabricationField(item, "have"))
		entry.inputs = readInputs(item)
		if entry.wareid ~= "" then table.insert(snapshot.refines, entry) end
	end
	table.sort(snapshot.patterns, function(a, b)
		if a.name == b.name then return a.wareid < b.wareid end
		return a.name < b.name
	end)
	-- Systems research rows, one per maker and Mk tier (MD computes everything).
	snapshot.research = {}
	for _, item in ipairs(fabricationField(data, "research") or {}) do
		local entry = {}
		for _, key in ipairs({ "schematicid", "name", "schematicname", "group" }) do
			entry[key] = tostring(fabricationField(item, key) or "")
		end
		for _, key in ipairs({ "tier", "carriedschematics", "needteardowns", "haveteardowns", "blueprints" }) do
			entry[key] = fabricationNumber(fabricationField(item, key))
		end
		entry.researched = fabricationBool(fabricationField(item, "researched"))
		entry.compiled = fabricationBool(fabricationField(item, "compiled"))
		entry.delivering = fabricationBool(fabricationField(item, "delivering"))
		entry.researching = fabricationBool(fabricationField(item, "researching"))
		entry.eligible = {}
		for _, eligible in ipairs(fabricationField(item, "eligible") or {}) do
			local eligibleid = tostring(fabricationField(eligible, "wareid") or "")
			table.insert(entry.eligible, { wareid = eligibleid, name = withTurretVariant(eligibleid, tostring(fabricationField(eligible, "name") or "")), owned = fabricationNumber(fabricationField(eligible, "owned")) })
		end
		table.sort(entry.eligible, function(a, b) return a.name < b.name end)
		if entry.schematicid ~= "" then table.insert(snapshot.research, entry) end
	end
	table.sort(snapshot.research, function(a, b)
		if a.group == b.group then return a.tier < b.tier end
		return a.group < b.group
	end)
	state.fabrication = snapshot
	state.fabricationRequested = true
	if not snapshot.beta then
		state.subview = "saved"
		state.fabricationConfirm = nil
	end
	return true
end

local function requestFabrication(action, confirmation, skipRefresh)
	if action ~= "refresh" and (state.fabricationPending or not state.fabrication.beta or not confirmation) then return end
	if not AddUITriggeredEvent then return end
	local snapshot = confirmation or state.fabrication
	-- AddUITriggeredEvent carries positional lists, not named table fields.
	-- Wire v1: { version, action, ware ID, quantity, revision, token }.
	local request = {
		1, action, snapshot.wareid or "", math.max(1, math.floor(tonumber(snapshot.quantity) or 1)), snapshot.revision or 0, snapshot.token or "",
	}
	state.fabricationRequested = true
	state.fabricationPending = true
	local ok = pcall(AddUITriggeredEvent, "SES_Fabrication", "Request", request)
	if not ok then
		state.fabricationPending = false
		state.fabrication.result = "failed"
	end
	if not skipRefresh then refreshSalvageView("fabrication_request") end
end

local function onFabricationState()
	if loadFabricationState() then
		state.fabricationPending = false
		-- Any publication invalidates an open confirmation. Its MD token must
		-- never silently acquire a newer revision or changed material costs.
		state.fabricationConfirm = nil
		state.fabricationCraft = nil
		refreshSalvageView("fabrication_state")
	end
end

local function fabricationMessage(code)
	local messages = {
		locked = { 856, "Decode this blueprint in Research first." },
		materials = { 879, "Not enough fabrication materials." },
		insufficient = { 879, "Not enough fabrication materials." },
		refined = { 876, "Material crafted." },
		fabricated = { 877, "Equipment fabricated and added to Saved Equipment." },
		stale = { 878, "Stock changed. Review the updated materials and try again." },
		beta_off = { 880, "Wreck Mining & Fabrication BETA is disabled." },
		unsupported = { 881, "This equipment does not have a supported recipe." },
		failed = { 882, "Fabrication request failed. Refresh and try again." },
		research_teardown = { 1077, "Teardown recorded." },
		research_nothing = { 1080, "No matching components or saved copies to add." },
		research_need_copy = { 1081, "Recover a copy of this item first." },
		sys_compiled = { 1184, "Schematics compiled. Take them to Boso Ta at your HQ." },
		nobench = { 1202, "Use a Crafting Bench to fabricate. Fabrication stays available while you remain in that room." },
	}
	local message = messages[code]
	return message and sesText(message[1], message[2]) or ""
end

-- How many the player can make right now (0 when anything is missing), max 99.
local function fabricationMax(entry)
	if not entry or not entry.inputs or #entry.inputs == 0 then return 0 end
	local max = 99
	for _, input in ipairs(entry.inputs) do
		if input.need > 0 then
			max = math.min(max, math.floor(input.have / input.need))
		end
	end
	return math.max(max, 0)
end

-- "2 x Shield Casing, 14 x Salvaged Emitter Coils" for a quantity.
local function fabricationCostText(entry, quantity)
	local parts = {}
	for _, input in ipairs(entry and entry.inputs or {}) do
		table.insert(parts, tostring(input.need * (quantity or 1)) .. " x " .. input.name)
	end
	return table.concat(parts, ", ")
end

local function fabricationCanMake(entry)
	local snapshot = state.fabrication
	return snapshot.beta and snapshot.atbench and not state.fabricationPending and entry.unlocked
		and snapshot.token ~= nil and fabricationMax(entry) >= 1
end

local function beginFabricationConfirmation(entry)
	local snapshot = state.fabrication
	if state.fabricationPending or not snapshot.beta or not snapshot.token or not entry then return end
	if not fabricationCanMake(entry) then return end
	state.fabricationConfirm = {
		action = entry.action, wareid = entry.wareid, name = entry.name, inputs = entry.inputs,
		owned = entry.owned or 0, revision = snapshot.revision, token = snapshot.token,
	}
	refreshSalvageView("fabrication_confirm")
end

local function addSalvageSubviews(infotable)
	if not state.fabrication.beta then return end
	local row = infotable:addRow(true, { fixed = true })
	-- Saved Equipment spans columns 1-2; Fabrication and Research take 3 and 4.
	-- With the Crafting menu hook, Fabrication lives at the Crafting Bench.
	local definitions = { { "saved", 850, "Saved Equipment", 1, 2 }, { "fabrication", 851, "Fabrication", 3, 1 }, { "research", 1061, "Research", 4, 1 } }
	if ses.craftingHookActive then
		definitions = { { "saved", 850, "Saved Equipment", 1, 2 }, { "research", 1061, "Research", 3, 2 } }
		if state.subview == "fabrication" then state.subview = "saved" end
	end
	for _, definition in ipairs(definitions) do
		local key, col = definition[1], definition[4]
		row[col]:setColSpan(definition[5]):createButton({ active = state.subview ~= key and not state.fabricationPending }):setText(sesText(definition[2], definition[3]), { halign = "center" })
		row[col].handlers.onClick = function()
			state.subview = key
			state.fabricationConfirm = nil
			if key == "saved" then refreshSalvageView("saved_subview") else requestFabrication("refresh") end
		end
	end
end

-- Research requests reuse the fabrication wire; the snapshot supplies the
-- MD-issued revision and token.
local function requestResearch(action, entry)
	local snapshot = state.fabrication
	if state.fabricationPending or not snapshot.beta or not snapshot.token or not entry then return end
	requestFabrication(action, { wareid = entry.wareid, revision = snapshot.revision, token = snapshot.token })
end

local function beginResearchConfirmation(action, entry)
	local snapshot = state.fabrication
	if state.fabricationPending or not snapshot.beta or not snapshot.token or not entry then return end
	state.fabricationConfirm = { action = action, wareid = entry.wareid, name = entry.name, revision = snapshot.revision, token = snapshot.token }
	refreshSalvageView("research_confirm")
end

local function renderResearch(infotable)
	local snapshot = state.fabrication
	local row
	local result = fabricationMessage(snapshot.result)
	if state.fabricationPending or result ~= "" then
		row = infotable:addRow(true, { fixed = true })
		row[1]:setColSpan(3):createText(state.fabricationPending and sesText(859, "Waiting for Mission Director...") or result, { wordwrap = true })
		row[4]:createButton({ active = true }):setText(sesText(875, "Refresh"))
		row[4].handlers.onClick = function() requestFabrication("refresh") end
	end
	local confirmation = state.fabricationConfirm
	if confirmation and confirmation.action == "sys_teardown" then
		row = infotable:addRow(false, { fixed = true })
		row[1]:setColSpan(4):createText(sesFormat(1074, "Tear down 1 x %s? The saved item is destroyed.", confirmation.name), { wordwrap = true })
		row = infotable:addRow(true, { fixed = true })
		row[1]:setColSpan(2):createButton({ active = not state.fabricationPending }):setText(sesText(1083, "Back"), { halign = "center" })
		row[1].handlers.onClick = function() state.fabricationConfirm = nil; refreshSalvageView("research_back") end
		row[3]:setColSpan(2):createButton({ active = not state.fabricationPending and snapshot.revision == confirmation.revision and snapshot.token == confirmation.token })
			:setText(sesText(1068, "Tear Down"), { halign = "center" })
		row[3].handlers.onClick = function() requestFabrication(confirmation.action, confirmation) end
		return
	end
	row = infotable:addRow(false, { fixed = true })
	row[1]:setColSpan(4):createText(sesText(1086, "Tear down different saved items of a maker to compile its schematics, then bring the schematics and that maker's components to Boso Ta at your HQ."), { wordwrap = true })
	if #snapshot.research == 0 then
		row = infotable:addRow(false, {})
		row[1]:setColSpan(4):createText(sesText(1082, "Nothing to research yet. Recover equipment with the Avarice Beam Regulator, then start research on it here."), { wordwrap = true })
		return
	end
	local idle = not state.fabricationPending and snapshot.token ~= nil
	-- One card per maker and Mk tier: compile schematics here, research at the HQ.
	for _, entry in ipairs(snapshot.research) do
		row = infotable:addRow({ ses_research = entry.schematicid }, {})
		row[1]:setColSpan(3):createText(entry.name, { font = Helper.standardFontBold, wordwrap = false })
		row[4]:createText(entry.researched and sesText(1182, "Researched at HQ") or sesFormat(1185, "Blueprints: %d", entry.blueprints), { halign = "right" })
		if entry.researched then
			-- Done; nothing left to compile.
		elseif entry.researching then
			row = infotable:addRow(false, {})
			row[1]:setColSpan(4):createText(sesText(1201, "Researching at your HQ."), { wordwrap = true })
		elseif entry.delivering then
			row = infotable:addRow(false, {})
			row[1]:setColSpan(4):createText(sesText(1200, "Research started. Deliver the items to Boso Ta at your HQ."), { wordwrap = true })
		elseif entry.compiled then
			row = infotable:addRow(false, {})
			row[1]:setColSpan(4):createText(sesFormat(1183, "Schematics ready. Start %s at your HQ and deliver the schematics and components to Boso Ta.", entry.name), { wordwrap = true })
		else
			row = infotable:addRow(false, {})
			row[1]:setColSpan(4):createText(sesFormat(1186, "Different Mk%d teardowns: %d / %d", entry.tier, entry.haveteardowns, entry.needteardowns))
			if entry.haveteardowns < entry.needteardowns then
				if #entry.eligible == 0 then
					row = infotable:addRow(false, {})
					row[1]:setColSpan(4):createText(sesFormat(1187, "No eligible saved items. Recover more of this maker's Mk%d equipment with the Avarice Beam Regulator.", entry.tier), { wordwrap = true })
				else
					for _, item in ipairs(entry.eligible) do
						row = infotable:addRow(true, {})
						row[1]:setColSpan(3):createText("   " .. item.name .. "   " .. sesFormat(858, "Saved: %d", item.owned), { wordwrap = false })
						row[4]:createButton({ active = idle }):setText(sesText(1068, "Tear Down"), { halign = "center" })
						row[4].handlers.onClick = function() beginResearchConfirmation("sys_teardown", { wareid = item.wareid, name = item.name }) end
					end
				end
			end
		end
	end
end

local function addFabricationFilters(infotable)
	local filters = state.fabricationFilters
	local definitions = {
		{ "category", 107, "Category" }, { "size", 863, "Size" },
		{ "maker", 864, "Manufacturer" }, { "grade", 865, "Grade" },
	}
	local row = infotable:addRow(false, { fixed = true })
	for index, definition in ipairs(definitions) do row[index]:createText(sesText(definition[2], definition[3]), { font = Helper.standardFontBold }) end
	row = infotable:addRow(true, { fixed = true })
	for index, definition in ipairs(definitions) do
		local key = definition[1]
		-- X4 9.00 rejects a dropdown option without a boolean displayremoveoption
		-- and then aborts the whole frame.
		local options = { { id = "all", text = sesText(866, "All"), icon = "", displayremoveoption = false } }
		local seen, values = {}, {}
		for _, entry in ipairs(state.fabrication.patterns) do
			local value = entry[key]
			if value ~= "" and not seen[value] then seen[value] = true; table.insert(values, value) end
		end
		table.sort(values)
		for _, value in ipairs(values) do
			table.insert(options, { id = value, text = key == "category" and categoryName(categoryKey(value), value) or value, icon = "", displayremoveoption = false })
		end
		if filters[key] ~= "all" and not seen[filters[key]] then filters[key] = "all" end
		-- Explicit height as in vanilla Player Information; without it the
		-- selected text rides up into the label row above.
		row[index]:createDropDown(options, { height = Helper.standardTextHeight, startOption = filters[key], active = not state.fabricationPending })
		row[index].handlers.onDropDownConfirmed = function(_, value)
			filters[key] = tostring(value)
			refreshSalvageView("fabrication_filter")
		end
	end
	row = infotable:addRow(true, { fixed = true })
	row[1]:setColSpan(3):createEditBox({ description = sesText(868, "Search patterns"), defaultText = sesText(868, "Search patterns"), maxChars = 80 }):setText(filters.search)
	row[1].handlers.onEditBoxDeactivated = function(_, value)
		filters.search = tostring(value or "")
		refreshSalvageView("fabrication_search")
	end
	-- Toggle shown by highlight, as vanilla Crafting/Diplomacy mark the selected button.
	row[4]:createButton({ active = not state.fabricationPending, bgColor = filters.known and Color["row_background_selected"] or nil }):setText(sesText(867, "Known only"), { halign = "center" })
	row[4].handlers.onClick = function() filters.known = not filters.known; refreshSalvageView("fabrication_known_filter") end
end

local function fabricationMatches(entry)
	local filters = state.fabricationFilters
	for _, key in ipairs({ "category", "size", "maker", "grade" }) do
		if filters[key] ~= "all" and filters[key] ~= entry[key] then return false end
	end
	if filters.known and not entry.unlocked then return false end
	local needle = string.lower(filters.search)
	return needle == "" or string.find(string.lower(entry.name .. " " .. entry.maker .. " " .. entry.wareid), needle, 1, true) ~= nil
end

-- Confirmation rows shared by the Salvage Inventory and Crafting menu views.
local function renderFabricationConfirmation(infotable)
	local snapshot = state.fabrication
	local confirmation = state.fabricationConfirm
	local isrefine = confirmation.action == "refine"
	local row = infotable:addRow(false, { fixed = true })
	row[1]:setColSpan(4):createText(isrefine and sesFormat(871, "Craft 1 x %s?", confirmation.name) or sesFormat(869, "Fabricate 1 x %s?", confirmation.name), Helper.subHeaderTextProperties)
	row = infotable:addRow(false, { fixed = true })
	row[1]:setColSpan(4):createText(sesFormat(857, "Cost: %s", fabricationCostText(confirmation, 1)), { wordwrap = true })
	row = infotable:addRow(false, { fixed = true })
	row[1]:setColSpan(4):createText(isrefine and sesFormat(872, "Carried after crafting: %d", confirmation.owned + 1) or sesFormat(870, "Saved Equipment after crafting: %d", confirmation.owned + 1))
	row = infotable:addRow(true, { fixed = true })
	row[1]:setColSpan(2):createButton({ active = not state.fabricationPending }):setText(sesText(873, "Cancel"), { halign = "center" })
	row[1].handlers.onClick = function() state.fabricationConfirm = nil; refreshSalvageView("fabrication_cancel") end
	row[3]:setColSpan(2):createButton({ active = not state.fabricationPending and snapshot.revision == confirmation.revision and snapshot.token == confirmation.token }):setText(sesText(874, "Fabricate"), { halign = "center" })
	row[3].handlers.onClick = function() requestFabrication(confirmation.action, confirmation) end
end

-- Two rows per recipe: name + amount, then cost + button. Full details in the tooltip.
local function addFallbackRecipeRows(infotable, entry, amountText, tooltip)
	local row = infotable:addRow({ ses_fabrication = entry.wareid }, {})
	row[1]:setColSpan(3):createText(entry.name .. ((entry.maker or "") ~= "" and entry.maker ~= "--" and "  [" .. entry.maker .. "]" or ""), { wordwrap = false, height = Helper.standardTextHeight, mouseOverText = tooltip })
	row[4]:createText(amountText, { halign = "right", wordwrap = false, height = Helper.standardTextHeight, mouseOverText = tooltip })
	row = infotable:addRow(true, {})
	row[1]:setColSpan(3):createText(entry.unlocked and sesFormat(857, "Cost: %s", fabricationCostText(entry, 1)) or sesText(856, "Decode this blueprint in Research first."), { wordwrap = false, height = Helper.standardTextHeight, mouseOverText = tooltip })
	row[4]:createButton({ active = fabricationCanMake(entry), mouseOverText = tooltip }):setText(entry.unlocked and sesText(874, "Fabricate") or sesText(855, "Locked"))
	row[4].handlers.onClick = function() beginFabricationConfirmation(entry) end
end

local function fabricationTooltip(entry, header)
	local lines = { header }
	for _, input in ipairs(entry.inputs or {}) do
		table.insert(lines, input.name .. ": " .. input.have .. " / " .. input.need)
	end
	return table.concat(lines, "\n")
end

local function renderFabrication(infotable)
	local snapshot = state.fabrication
	local row
	if not snapshot.atbench then
		row = infotable:addRow(false, { fixed = true })
		row[1]:setColSpan(4):createText(fabricationMessage("nobench"), { wordwrap = true, color = Color["text_warning"] })
	end
	local result = snapshot.result ~= "nobench" and fabricationMessage(snapshot.result) or ""
	if state.fabricationPending or result ~= "" then
		-- Selectable: X4 rejects a button in an unselectable row, and a failed
		-- frame update reloads the whole UI.
		row = infotable:addRow(true, { fixed = true })
		row[1]:setColSpan(3):createText(state.fabricationPending and sesText(859, "Waiting for Mission Director...") or result, { wordwrap = true })
		row[4]:createButton({ active = true }):setText(sesText(875, "Refresh"))
		row[4].handlers.onClick = function() requestFabrication("refresh") end
	end
	if state.fabricationConfirm then
		renderFabricationConfirmation(infotable)
		return
	end
	-- Bench materials: cores and casings.
	row = infotable:addRow(false, {})
	row[1]:setColSpan(4):createText(sesText(1238, "Materials"), Helper.subHeaderTextProperties)
	row[1].properties.halign = "center"
	for _, entry in ipairs(snapshot.refines) do
		addFallbackRecipeRows(infotable, entry, sesFormat(1237, "Carried: %d", entry.owned), fabricationTooltip(entry, entry.name))
	end
	row = infotable:addRow(false, {})
	row[1]:setColSpan(4):createText(sesText(1239, "Equipment"), Helper.subHeaderTextProperties)
	row[1].properties.halign = "center"
	addFabricationFilters(infotable)
	local visible = 0
	for _, entry in ipairs(snapshot.patterns) do
		if fabricationMatches(entry) then
			visible = visible + 1
			local reason = not entry.unlocked and fabricationMessage("locked") or (not fabricationCanMake(entry) and fabricationMessage(entry.reason ~= "" and entry.reason or "materials") or "")
			local tooltip = fabricationTooltip(entry, entry.name .. "\n" .. categoryName(categoryKey(entry.category), entry.category) .. " / " .. entry.size .. " / " .. entry.maker .. " / " .. entry.grade)
			if reason ~= "" then tooltip = tooltip .. "\n" .. reason end
			addFallbackRecipeRows(infotable, entry, sesFormat(858, "Saved: %d", entry.owned), tooltip)
		end
	end
	if visible == 0 then
		row = infotable:addRow(false, {})
		row[1]:setColSpan(4):createText(sesText(884, "No patterns match these filters."), { halign = "center" })
	end
	row = infotable:addRow(true, {})
	row[1]:setColSpan(2):createButton({ active = not state.fabricationPending }):setText(sesText(883, "Reset Filters"))
	row[1].handlers.onClick = function()
		state.fabricationFilters = { category = "all", size = "all", maker = "all", grade = "all", known = false, search = "" }
		refreshSalvageView("fabrication_reset_filters")
	end
	-- Refresh also recovers an interrupted MD/UI response without replaying a
	-- mutation; the old token is invalidated by the new MD publication.
	row[3]:setColSpan(2):createButton({ active = true }):setText(sesText(875, "Refresh"))
	row[3].handlers.onClick = function() requestFabrication("refresh") end
end

-- Crafting menu tab: same layout as the vanilla crafting categories (see
-- menu_crafting addInventoryWareEntry). Blue product row per known blueprint,
-- indented resource rows with have / need, and the Craft Item button below
-- acting on the selected product row. Returns that button's description.
local function addNativeCraftingRow(infotable, rowdata, name, amount, price, options)
	options = options or {}
	-- Only product rows are blue; resource rows keep the default background (as vanilla).
	local rowproperties = {}
	if not options.isresource then
		rowproperties.bgColor = Color["row_background_blue"]
	end
	local row = infotable:addRow(rowdata, rowproperties)
	row[1]:createText(options.isresource and ("    " .. name) or name, { color = options.color or Color["text_normal"], mouseOverText = options.tooltip })
	if options.isresource then
		row[2]:createText(amount .. " / " .. options.needed, { halign = "right", color = (amount < options.needed) and Color["text_error"] or nil })
	else
		row[2]:createText(amount, { halign = "right" })
	end
	row[3]:createText(moneyText(price), { halign = "right" })
	row[4]:createText(moneyText(price * amount), { halign = "right" })
	return row
end

local function craftingRowKey(rowdata)
	if type(rowdata) ~= "table" then return nil end
	return tostring(rowdata[1]) .. "|" .. tostring(rowdata[2] or "")
end

local function renderFabricationNative(infotable)
	local snapshot = state.fabrication
	local result = fabricationMessage(snapshot.result)
	if state.fabricationPending or result ~= "" then
		local row = infotable:addRow(false, { fixed = true })
		row[1]:setColSpan(4):createText(state.fabricationPending and sesText(859, "Waiting for Mission Director...") or result, { wordwrap = true })
	end
	if state.fabricationConfirm then
		renderFabricationConfirmation(infotable)
		return nil
	end

	-- header
	local row = infotable:addRow(false, { bgColor = Color["row_background_unselectable"] })
	row[1]:createText(ReadText(1001, 45), { font = Helper.standardFontBold })
	row[2]:createText(ReadText(1001, 1202), { font = Helper.standardFontBold, halign = "right" })
	row[3]:createText(ReadText(1001, 2413), { font = Helper.standardFontBold, halign = "right" })
	row[4]:createText(ReadText(1001, 2927), { font = Helper.standardFontBold, halign = "right" })

	-- The last crafted recipe keeps the selection across refreshes; its row
	-- index moves when a result line is added above the list.
	local selectIndex
	local products = {}
	local first = true
	local function addProduct(entry, tooltip)
		if not first then infotable:addEmptyRow(Helper.standardTextHeight / 2) end
		first = false
		local rowdata = { entry.action, entry.wareid }
		products[craftingRowKey(rowdata)] = entry
		local productrow = addNativeCraftingRow(infotable, rowdata, entry.name, entry.owned, wareAvgPrice(entry.wareid), { color = fabricationCanMake(entry) and Color["text_normal"] or Color["text_inactive"], tooltip = tooltip })
		if productrow and state.craftingSelectKey and craftingRowKey(rowdata) == state.craftingSelectKey then
			selectIndex = productrow.index
		end
		for _, input in ipairs(entry.inputs or {}) do
			addNativeCraftingRow(infotable, rowdata, input.name, input.have, wareAvgPrice(input.wareid), { isresource = true, needed = input.need })
		end
	end

	-- Bench materials first (cores, casings), then every decoded blueprint
	-- (patterns are already sorted by name).
	for _, entry in ipairs(snapshot.refines) do
		addProduct(entry, entry.name)
	end
	for _, entry in ipairs(snapshot.patterns) do
		if entry.unlocked then
			addProduct(entry, entry.name .. "\n" .. categoryName(categoryKey(entry.category), entry.category) .. " / " .. entry.size .. " / " .. entry.maker .. " / " .. entry.grade)
		end
	end

	if selectIndex then
		-- Vanilla applies menu.setselectedrow right after this callback.
		local craftingMenu = findMenuByName("CraftingMenu", "CraftingMenu")
		if craftingMenu then craftingMenu.setselectedrow = selectIndex end
	end

	local ready = snapshot.atbench and snapshot.token ~= nil and not state.fabricationPending
	local craft = state.fabricationCraft
	if craft and craft.token == snapshot.token then
		-- Craft mode, as vanilla: amount slider, Craft Item makes that many, Cancel leaves.
		return {
			text = ReadText(1001, 7706),
			active = ready,
			onClick = function()
				state.fabricationCraft = nil
				requestFabrication(craft.action, { wareid = craft.wareid, revision = craft.revision, token = craft.token, quantity = craft.amount })
			end,
			slider = {
				max = craft.max, start = craft.amount, text = craft.name,
				onChanged = function(value) craft.amount = math.max(1, math.min(craft.max, math.floor(tonumber(value) or 1))) end,
			},
			onCancel = function()
				state.fabricationCraft = nil
				refreshSalvageView("fabrication_craft_cancel")
			end,
		}
	end
	state.fabricationCraft = nil

	return {
		text = ReadText(1001, 7706),
		active = ready,
		onClick = function(rowdata)
			if type(rowdata) ~= "table" or not ready then return end
			state.craftingSelectKey = craftingRowKey(rowdata)
			local entry = products[craftingRowKey(rowdata)]
			if not entry or not fabricationCanMake(entry) then return end
			local max = fabricationMax(entry)
			if max < 1 then return end
			state.fabricationCraft = { action = entry.action, wareid = entry.wareid, name = entry.name, amount = 1, max = max, revision = snapshot.revision, token = snapshot.token }
			refreshSalvageView("fabrication_craft_mode")
		end,
	}
end

local function resetInventorySubmode(playerInfoMenu, reason)
	if playerInfoMenu and playerInfoMenu.inventoryData and playerInfoMenu.inventoryData.mode == ses.category then
		state.fabricationConfirm = nil
		state.subview = "saved"
		playerInfoMenu.inventoryData.mode = "normal"
		playerInfoMenu.inventoryData.curEntry = {}
		playerInfoMenu.inventoryData.selectedWares = {}
		playerInfoMenu.inventoryData.dropWares = {}
		playerInfoMenu.inventoryData.craftWare = nil
		playerInfoMenu.inventoryData.craftAmount = nil
		clearInventoryTableState(playerInfoMenu, reason)
		emit("playerinfo_reset_to_normal", "reason=" .. safeString(reason or "unknown") .. ", version=" .. ses.version)
	end
end

local function clearInventoryTransients(playerInfoMenu, reason)
	if playerInfoMenu and playerInfoMenu.inventoryData then
		playerInfoMenu.inventoryData.curEntry = {}
		playerInfoMenu.inventoryData.selectedWares = {}
		playerInfoMenu.inventoryData.dropWares = {}
		playerInfoMenu.inventoryData.craftWare = nil
		playerInfoMenu.inventoryData.craftAmount = nil
		clearInventoryTableState(playerInfoMenu, reason)
		emit("playerinfo_clear_transients", "reason=" .. safeString(reason or "unknown") .. ", version=" .. ses.version)
	end
end

local function addInventoryTab(playerInfoMenu)
	if not playerInfoMenu or type(playerInfoMenu.uix_getConfig) ~= "function" then
		emit("playerinfo_config_missing", ses.version)
		return false
	end

	local ok, config = pcall(playerInfoMenu.uix_getConfig)
	if (not ok) or type(config) ~= "table" or type(config.inventoryTabs) ~= "table" then
		emit("playerinfo_inventory_tabs_missing", ses.version)
		return false
	end

	for _, entry in ipairs(config.inventoryTabs) do
		if entry.category == ses.category then
			entry.name = "Salvage Inventory"
			entry.icon = entry.icon or "pi_inventory"
			entry.helpOverlayID = "playerinfo_inventory_ses_salvage"
			entry.helpOverlayText = "Ship Equipment Salvaging inventory"
			return true
		end
	end

	table.insert(config.inventoryTabs, {
		category = ses.category,
		name = "Salvage Inventory",
		icon = "pi_inventory",
		helpOverlayID = "playerinfo_inventory_ses_salvage",
		helpOverlayText = "Ship Equipment Salvaging inventory",
	})
	emit("playerinfo_tab_added", ses.version)
	return true
end

local function renderSalvageInventory(playerInfoMenu, frame, tableProperties, mode, tabOrderOffset)
	if playerInfoMenu.mode ~= "inventory" then
		resetInventorySubmode(playerInfoMenu, "render_guard_non_inventory")
		return
	end

	tabOrderOffset = tabOrderOffset or 0
	tableProperties = tableProperties or {}

	-- The addon can initialize before Mission Director is ready when it lives in
	-- the main save-persistent extension. Retry on the first visible render until
	-- a complete ledger response has actually arrived; the startup request alone
	-- is not proof that MD received it.
	if not state.lastdone then
		requestInventory("first_render")
	end
	if not state.fabricationRequested then requestFabrication("refresh", nil, true) end

	-- Keep the header focus on the active Salvage tab. Clearing this state makes
	-- X4 fall back to column 1 and leaves Player Inventory looking selected.
	if playerInfoMenu.selectedRows then
		playerInfoMenu.selectedRows["inventoryHeaderTable"] = 1
	end
	if playerInfoMenu.selectedCols then
		playerInfoMenu.selectedCols["inventoryHeaderTable"] = state.salvagecol or 1
	end

	if type(playerInfoMenu.createInventoryHeader) == "function" then
		playerInfoMenu.createInventoryHeader(frame, tableProperties)
	end

	local width = tableProperties.width or (Helper and Helper.viewWidth or 1000)
	local x = tableProperties.x or 0
	local y = tableProperties.y or 0
	local height = tableProperties.height or (Helper and Helper.viewHeight or 700)
	local border = (Helper and Helper.borderSize) or 5
	local frameborder = (Helper and Helper.frameBorder) or 0

	if playerInfoMenu.inventoryHeaderTable and type(playerInfoMenu.inventoryHeaderTable.getFullHeight) == "function" then
		y = y + playerInfoMenu.inventoryHeaderTable:getFullHeight() + border
	end

	local infotable = frame:addTable(4, {
		tabOrder = 1 + tabOrderOffset,
		borderEnabled = true,
		width = width,
		maxVisibleHeight = height,
		x = x,
		y = y,
	})
	playerInfoMenu.inventoryInfoTable = infotable
	playerInfoMenu.infoTable = infotable.id
	-- The connection graph below makes the SES contents table the sole default.
	playerInfoMenu.setdefaulttable = nil
	-- Column widths are final once the first row exists, so pick the layout now.
	local showFabrication = (state.subview == "fabrication" or state.subview == "research") and state.fabrication.beta
	if showFabrication then
		-- Equal columns keep all four filters legible; equipment names and
		-- costs span the first three columns of each two-line pattern card.
		for col = 2, 4 do infotable:setColWidth(col, width / 4, false) end
	else
		infotable:setColWidth(2, width / 10, false)
		infotable:setColWidth(3, width / 5, false)
		infotable:setColWidth(4, width / 5, false)
	end
	infotable:setDefaultBackgroundColSpan(1, 4)

	local row = infotable:addRow(nil, { fixed = true, bgColor = Color["row_title_background"] })
	row[1]:setColSpan(4):createText(sesText(300, "Salvage Inventory"), Helper.titleTextProperties)
	addSalvageSubviews(infotable)
	if showFabrication then
		if state.subview == "research" then renderResearch(infotable) else renderFabrication(infotable) end
		infotable.properties.maxVisibleHeight = math.max(0, height - (y - (tableProperties.y or 0)) - frameborder)
		playerInfoMenu.inventoryButtonTable = nil
		if playerInfoMenu.inventoryHeaderTable then
			playerInfoMenu.inventoryHeaderTable:addConnection(1, 2)
			infotable:addConnection(2, 2, true)
		else
			infotable:addConnection(1, 2, true)
		end
		return
	end

	row = infotable:addRow(nil, { fixed = true, bgColor = Color["row_background_unselectable"] })
	row[1]:createText(readText(1001, 95, "Item"), { font = Helper.standardFontBold })
	row[2]:createText(readText(1001, 1202, "Amount"), { font = Helper.standardFontBold, halign = "right" })
	row[3]:createText(readText(1001, 2413, "Base Price"), { font = Helper.standardFontBold, halign = "right" })
	row[4]:createText(readText(1001, 2927, "Total Price"), { font = Helper.standardFontBold, halign = "right" })

	row = infotable:addRow(false, { fixed = true, bgColor = Color["row_separator"] })
	row[1]:setColSpan(4):createText("", { height = 1 })

	local totalvalue = 0
	if state.loading and #state.rows == 0 then
		row = infotable:addRow(true, { interactive = false })
		row[1]:setColSpan(4):createText(sesText(301, "Loading SES salvage ledger..."), { halign = "center" })
	elseif #state.rows == 0 then
		row = infotable:addRow(true, { interactive = false })
		row[1]:setColSpan(4):createText(sesText(302, "-- None --"), { halign = "center" })
	else
		local groups = {}
		local order = { "weapons", "turrets", "shields", "engines", "thrusters" }
		local seen = {}
		for _, key in ipairs(order) do
			seen[key] = true
		end
		for _, entry in ipairs(state.rows) do
			local key = categoryKey(entry.category)
			if not groups[key] then
				groups[key] = {}
				if not seen[key] then
					table.insert(order, key)
					seen[key] = true
				end
			end
			table.insert(groups[key], entry)
		end

		for _, key in ipairs(order) do
			local entries = groups[key]
			if entries and #entries > 0 then
				row = infotable:addRow(nil, {})
				row[1]:setColSpan(4):createText(categoryName(key, entries[1].category), Helper.subHeaderTextProperties)
				row[1].properties.halign = "center"
				for _, entry in ipairs(entries) do
					local name = withTurretVariant(entry.ware, macroDisplayName(entry.macro, wareDisplayName(entry.ware)))
					local avgprice = wareAvgPrice(entry.ware)
					totalvalue = totalvalue + (avgprice * entry.count)
					row = infotable:addRow({ ses_salvage = true, ses_index = entry.index }, {})
					row[1]:createText(name)
					row[2]:createText(tostring(entry.count), { halign = "right" })
					row[3]:createText(moneyText(avgprice), { halign = "right", mouseOverText = categoryName(key, entry.category) .. "\n" .. entry.ware .. "\n" .. entry.macro })
					row[4]:createText(moneyText(avgprice * entry.count), { halign = "right" })
				end
			end
		end
	end
	state.totalvalue = totalvalue

	local buttontable = frame:addTable(4, {
		tabOrder = 2 + tabOrderOffset,
		borderEnabled = true,
		width = width,
		x = x,
		y = y,
	})
	playerInfoMenu.inventoryButtonTable = buttontable

	row = buttontable:addRow(false, { fixed = true })
	row[1]:setColSpan(4):createText(" ")

	row = buttontable:addRow(false, { fixed = true, bgColor = Color["row_background_unselectable"] })
	row[1]:setBackgroundColSpan(4):setColSpan(3):createText(readText(1001, 2442, "Total Value"))
	row[4]:createText(moneyText(state.totalvalue or 0), { halign = "right" })

	row = buttontable:addRow(false, { fixed = true })
	row[1]:setColSpan(4):createText(" ")

	row = buttontable:addRow(false, { fixed = true, bgColor = Color["row_title_background"] })
	row[1]:setColSpan(4):createText(sesText(303, "Secure Container"), { halign = "center" })

	row = buttontable:addRow(true, { fixed = true, bgColor = Color["row_background_unselectable"] })
	row[1]:setColSpan(2):createButton({
		active = function () return currentEntryIndex(playerInfoMenu, infotable) ~= nil end,
		mouseOverText = sesText(304, "Drop one selected salvage stack item into a new secure lockbox near the player."),
		helpOverlayID = "playerinfo_inventory_ses_salvage_drop",
		helpOverlayText = " ",
	}):setText("Drop Selected", { halign = "center" })
	row[1].handlers.onClick = function ()
		local selectedindex = currentEntryIndex(playerInfoMenu, infotable)
		if selectedindex then
			requestDropOne(selectedindex)
		end
	end
	row[3]:setColSpan(2):createText(sesFormat(305, "Stacks: %d", #state.rows), { halign = "center" })

	local maxVisibleHeight = height - buttontable:getFullHeight() - frameborder
	if playerInfoMenu.inventoryHeaderTable and type(playerInfoMenu.inventoryHeaderTable.getFullHeight) == "function" then
		maxVisibleHeight = maxVisibleHeight - playerInfoMenu.inventoryHeaderTable:getFullHeight() - border
	end
	buttontable.properties.y = y + math.min(maxVisibleHeight, infotable:getFullHeight())
	infotable.properties.maxVisibleHeight = buttontable.properties.y - y

	if playerInfoMenu.inventoryHeaderTable then
		playerInfoMenu.inventoryHeaderTable:addConnection(1, 2)
		infotable:addConnection(2, 2, true)
		buttontable:addConnection(3, 2)
	else
		infotable:addConnection(1, 2, true)
		buttontable:addConnection(2, 2)
	end
end

local function patchPlayerInfoMenu(playerInfoMenu)
	if not playerInfoMenu then
		return false
	end
	if playerInfoMenu.sesSalvageInventoryPatched == ses.version then
		return true
	end

	if not addInventoryTab(playerInfoMenu) then
		return false
	end

	local originalCreateInventory = playerInfoMenu.createInventory
	if type(originalCreateInventory) ~= "function" then
		emit("create_inventory_missing", ses.version)
		return false
	end

	playerInfoMenu.createInventory = function(frame, tableProperties, mode, tabOrderOffset)
		if playerInfoMenu.inventoryData and playerInfoMenu.inventoryData.mode == ses.category then
			return renderSalvageInventory(playerInfoMenu, frame, tableProperties, mode, tabOrderOffset)
		end
		return originalCreateInventory(frame, tableProperties, mode, tabOrderOffset)
	end

	if type(playerInfoMenu.refreshInfoFrame) == "function" and not playerInfoMenu.sesOriginalRefreshInfoFrame then
		playerInfoMenu.sesOriginalRefreshInfoFrame = playerInfoMenu.refreshInfoFrame
		playerInfoMenu.refreshInfoFrame = function(toprow, selectedrow, mode, selectedrow2)
			if state.forceSafeRefresh then
				local reason = state.forceSafeRefreshReason or "unknown"
				state.forceSafeRefresh = false
				state.forceSafeRefreshReason = nil
				emit("playerinfo_force_safe_refresh", "reason=" .. safeString(reason) .. ", version=" .. ses.version)
				return playerInfoMenu.sesOriginalRefreshInfoFrame(toprow or 1, selectedrow or 1, mode, selectedrow2 or 1)
			end
			return playerInfoMenu.sesOriginalRefreshInfoFrame(toprow, selectedrow, mode, selectedrow2)
		end
	end

	if type(playerInfoMenu.buttonTogglePlayerInfo) == "function" and not playerInfoMenu.sesOriginalButtonTogglePlayerInfo then
		playerInfoMenu.sesOriginalButtonTogglePlayerInfo = playerInfoMenu.buttonTogglePlayerInfo
		playerInfoMenu.buttonTogglePlayerInfo = function(mode)
			if playerInfoMenu.mode == "inventory" and playerInfoMenu.inventoryData and playerInfoMenu.inventoryData.mode == ses.category and ((mode ~= "inventory") or (mode == playerInfoMenu.mode)) then
				resetInventorySubmode(playerInfoMenu, "leave_inventory_to_" .. safeString(mode))
			end
			return playerInfoMenu.sesOriginalButtonTogglePlayerInfo(mode)
		end
	end
	if type(playerInfoMenu.buttonInventorySubMode) == "function" and not playerInfoMenu.sesOriginalButtonInventorySubMode then
		playerInfoMenu.sesOriginalButtonInventorySubMode = playerInfoMenu.buttonInventorySubMode
		playerInfoMenu.buttonInventorySubMode = function(mode, col)
			if mode == ses.category then
				state.salvagecol = col
				state.fabricationConfirm = nil
				requestFabrication("refresh", nil, true)
				emit("playerinfo_connect_salvage_table", "col=" .. safeString(col) .. ", version=" .. ses.version)
			elseif playerInfoMenu.inventoryData and playerInfoMenu.inventoryData.mode == ses.category then
				clearInventoryTransients(playerInfoMenu, "submode_switch_to_" .. safeString(mode))
			end
			return playerInfoMenu.sesOriginalButtonInventorySubMode(mode, col)
		end
	end
	if type(playerInfoMenu.deactivatePlayerInfo) == "function" and not playerInfoMenu.sesOriginalDeactivatePlayerInfo then
		playerInfoMenu.sesOriginalDeactivatePlayerInfo = playerInfoMenu.deactivatePlayerInfo
		playerInfoMenu.deactivatePlayerInfo = function(...)
			resetInventorySubmode(playerInfoMenu, "deactivate_playerinfo")
			return playerInfoMenu.sesOriginalDeactivatePlayerInfo(...)
		end
	end
	if type(playerInfoMenu.createInfoFrame) == "function" and not playerInfoMenu.sesOriginalCreateInfoFrame then
		playerInfoMenu.sesOriginalCreateInfoFrame = playerInfoMenu.createInfoFrame
		playerInfoMenu.createInfoFrame = function(...)
			if playerInfoMenu.inventoryData and playerInfoMenu.inventoryData.mode == ses.category then
				if playerInfoMenu.mode ~= "inventory" then
					resetInventorySubmode(playerInfoMenu, "create_frame_start_non_inventory_" .. safeString(playerInfoMenu.mode))
				elseif playerInfoMenu.sesLastMainMode and playerInfoMenu.sesLastMainMode ~= "inventory" then
					resetInventorySubmode(playerInfoMenu, "create_frame_start_return_inventory_from_" .. safeString(playerInfoMenu.sesLastMainMode))
				end
			end
			playerInfoMenu.sesLastMainMode = playerInfoMenu.mode
			return playerInfoMenu.sesOriginalCreateInfoFrame(...)
		end
	end

	playerInfoMenu.sesSalvageInventoryPatched = ses.version
	emit("playerinfo_patched", ses.version)
	sesLog("Patched PlayerInfoMenu with SES Salvage Inventory tab.")
	return true
end

local function patchCraftingMenu()
	local craftingMenu = findMenuByName("CraftingMenu", "CraftingMenu")
	if not craftingHookSupported(craftingMenu) then
		if not ses.craftingFallbackLogged then
			ses.craftingFallbackLogged = true
			sesLog("Crafting menu hook not supported by the installed UI Extensions; Fabrication stays in Salvage Inventory.")
		end
		return false
	end
	if craftingMenu.sesCraftingHookActive == ses.version then return true end
	-- context: { categories, category }; result: { categories = { { id, name }, ... } }
	craftingMenu.registerCallback(CRAFTING_CALLBACKS[1], function(context)
		if not state.fabrication.beta then return nil end
		return { categories = { { id = CRAFTING_TAB_ID, name = sesText(851, "Fabrication") } } }
	end, "ship_equipment_salvaging_fabrication")
	-- context: { infotable, frame, tableproperties, category }
	-- result: { handled = true, craftbutton = { text, active, onClick(rowdata) } }
	craftingMenu.registerCallback(CRAFTING_CALLBACKS[2], function(context)
		if not context or context.category ~= CRAFTING_TAB_ID or not context.infotable then return nil end
		local ok, craftbutton = pcall(renderFabricationNative, context.infotable)
		if not ok then
			sesLog("Crafting menu Fabrication render failed: " .. tostring(craftbutton))
			craftbutton = nil
		end
		return { handled = true, craftbutton = craftbutton }
	end, "ship_equipment_salvaging_fabrication")
	craftingMenu.sesCraftingHookActive = ses.version
	ses.craftingHookActive = true
	sesLog("Registered Fabrication tab in the Crafting menu.")
	return true
end

local function runPatchAttempt()
	pcall(patchCraftingMenu)
	local ok, result = pcall(function ()
		return patchPlayerInfoMenu(findMenuByName("PlayerInfoMenu", "PlayerInfoMenu"))
	end)
	if not ok then
		sesLog("Patch attempt failed: " .. safeString(result))
		emit("error", safeString(result))
	elseif not result then
		emit("playerinfo_missing", ses.version)
	end
end

local function init()
	sesLog("Loaded SES Salvage Inventory UI addon via ui.xml/Kuertee UIX path.")
	emit("loaded_uixml", ses.version)
	registerInventoryEvent()
	if RegisterEvent and not (_G and _G.__ses_fabrication_event_registered) then
		local ok = pcall(RegisterEvent, "SES.FabricationState", onFabricationState)
		if ok and _G then _G.__ses_fabrication_event_registered = true end
	end
	requestInventory("init")
	requestFabrication("refresh", nil, true)
	runPatchAttempt()

	if Register_OnLoad_Init then
		Register_OnLoad_Init(runPatchAttempt, "SES Salvage Inventory PlayerInfo patch")
	end

	if Helper and Helper.addDelayedOneTimeCallbackOnUpdate and getElapsedTime then
		Helper.addDelayedOneTimeCallbackOnUpdate(runPatchAttempt, true, getElapsedTime() + 1)
		Helper.addDelayedOneTimeCallbackOnUpdate(runPatchAttempt, true, getElapsedTime() + 3)
	end
end

init()

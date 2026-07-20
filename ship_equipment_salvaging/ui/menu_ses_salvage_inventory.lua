-- Ship Equipment Salvaging
-- Kuertee UI Extensions-compatible Player Information > Player Inventory
-- Salvage Inventory tab. This file is loaded through the X4 ui.xml addon
-- path and patches PlayerInfoMenu only through its exposed config/menu surface.

local ffi = require("ffi")

local ses = {
	version = "v368-md-localization-resolution",
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
			pcall(menu.refreshInfoFrame)
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

local function resetInventorySubmode(playerInfoMenu, reason)
	if playerInfoMenu and playerInfoMenu.inventoryData and playerInfoMenu.inventoryData.mode == ses.category then
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
	infotable:setColWidth(2, width / 10, false)
	infotable:setColWidth(3, width / 5, false)
	infotable:setColWidth(4, width / 5, false)
	infotable:setDefaultBackgroundColSpan(1, 4)

	local row = infotable:addRow(nil, { fixed = true, bgColor = Color["row_title_background"] })
	row[1]:setColSpan(4):createText(sesText(300, "Salvage Inventory"), Helper.titleTextProperties)

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
					local name = macroDisplayName(entry.macro, wareDisplayName(entry.ware))
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

local function runPatchAttempt()
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
	requestInventory("init")
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

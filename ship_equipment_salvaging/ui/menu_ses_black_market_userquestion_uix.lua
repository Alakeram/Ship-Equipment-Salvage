-- Ship Equipment Salvaging
-- Kuertee UI Extensions-style UserQuestionMenu trader for SES salvage inventory.
--
-- This follows the proven shape used by kuertee_mod_parts_trader:
-- Mission Director builds a player blackboard payload, opens UserQuestionMenu
-- with a custom mode, and this Lua file renders a custom barter/trader table
-- through UserQuestionMenu UIX callbacks.
--
-- v313 production keeps Kuertee's ware-object-keyed barter bridge, uses 60-percent player
-- sell offers and 120-percent prices for all dealer stock, and renders up to
-- ten rotating S/M component rows after the delayed global announcement.
-- v297 mirrors Kuertee's ware-object-keyed barter bridge end to end: slider
-- changes write barterAmount onto the original keyed inventory rows; final
-- confirmation persists those tables and emits a parameterless MD event.

local ffi = require("ffi")
local C = ffi.C

local ModLua = {}

local userQuestionMenu = nil
local tradeData = nil
local tradeMenu = {}

local ses = {
	version = "v367-faction-and-overview",
	mode = "custom_ses_black_market_trade",
	blackboard = "$SES_Black_Market_BarterData",
	tradepayloadblackboard = "$SES_Black_Market_TradePayload",
}

pcall(ffi.cdef, [[
	typedef uint64_t UniverseID;
	UniverseID GetPlayerID(void);
]])

local function safeString(value)
	local ok, result = pcall(tostring, value)
	if ok then
		return result
	end
	return "<tostring failed>"
end

local function sesLog(message)
	print("[SES][SHOP UIX] " .. safeString(message))
end

local function emit(control, param)
	if AddUITriggeredEvent then
		pcall(AddUITriggeredEvent, "UserQuestionMenu", control, param or ses.version)
	end
end

local function emitDebug(message)
	emit("ses_black_market_debug", safeString(message))
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

local function standardTextHeight()
	return helperNumber("standardTextHeight", 20)
end

local function scaledTextWidth(multiplier)
	if Helper and Helper.scaleY then
		return Helper.scaleY(standardTextHeight()) * multiplier
	end
	return standardTextHeight() * multiplier
end

local function getElapsed()
	if getElapsedTime then
		return getElapsedTime()
	end
	return os.clock()
end

local function getFrameProperties()
	local borderSize = 3 * helperNumber("borderSize", 2)
	return {
		width = helperNumber("viewWidth", 1920) * 0.82,
		height = helperNumber("viewHeight", 1080) * 0.72,
		borderSize = borderSize,
	}
end

local function getTableProperties(frameProperties)
	return {
		width = frameProperties.width * 0.5,
		height = frameProperties.height,
	}
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

local function moneyText(value)
	local amount = tonumber(value) or 0
	if ConvertMoneyString then
		local ok, text = pcall(ConvertMoneyString, amount, false, true, nil, true)
		if ok and text then
			return text .. " " .. readText(1001, 101, "Cr")
		end
	end
	return tostring(math.floor(amount)) .. " " .. readText(1001, 101, "Cr")
end

local function wareAvgPrice(ware)
	if GetWareData and ware and ware ~= "" then
		local ok, avgprice = pcall(GetWareData, ware, "avgprice")
		if ok and tonumber(avgprice) then
			return tonumber(avgprice)
		end
	end
	return 0
end

local function categoryKey(category)
	local value = string.lower(safeString(category or ""))
	value = string.gsub(value, "[%s_%-]", "")
	if value == "weapon" or value == "weapons" then
		return "weapons"
	elseif value == "shield" or value == "shields" or value == "shieldgenerator" or value == "shieldgenerators" then
		return "shields"
	elseif value == "engine" or value == "engines" then
		return "engines"
	elseif value == "thruster" or value == "thrusters" then
		return "thrusters"
	elseif value == "turret" or value == "turrets" then
		return "turrets"
	end
	return value ~= "" and value or "other"
end

local function categoryName(key)
	local names = {
		weapons = sesText(100, "Weapons"),
		shields = sesText(101, "Shield Generators"),
		engines = sesText(102, "Engines"),
		thrusters = sesText(103, "Thrusters"),
		turrets = sesText(104, "Turrets"),
		other = sesText(105, "Other Equipment"),
	}
	return names[key] or safeString(key or sesText(105, "Other Equipment"))
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

local function rowKey(item)
	return table.concat({
		categoryKey(itemField(item, "category")),
		safeString(itemField(item, "wareid") or itemField(item, "ware") or ""),
		safeString(itemField(item, "macro") or ""),
	}, "|")
end

local function getItemName(item)
	local name = itemField(item, "name")
	if name and safeString(name) ~= "" then
		return safeString(name)
	end
	local wareid = itemField(item, "wareid")
	if wareid and GetWareData then
		local ok, wareName = pcall(GetWareData, wareid, "name")
		if ok and wareName and wareName ~= "" then
			return wareName
		end
	end
	return safeString(itemField(item, "wareid") or itemField(item, "ware") or sesText(505, "Salvaged Part"))
end

local function numericCount(value)
	local count = tonumber(value) or 0
	if count < 0 then
		count = 0
	end
	return math.floor(count)
end

local function sourceIndexFor(item, isPlayer)
	local index = tonumber(itemField(item, "index")) or 0
	if index > 0 then
		return math.floor(index)
	end
	local id = safeString(itemField(item, "id") or "")
	local prefix = isPlayer and "player_" or "stock_"
	local parsed = string.match(id, "^" .. prefix .. "(%d+)$")
	if not parsed then
		parsed = string.match(id, "(%d+)$")
	end
	return tonumber(parsed) or 0
end

local function sellPriceFor(wareid)
	return math.max(1, math.floor((wareAvgPrice(wareid) * 0.60) + 0.5))
end

local function buyPriceFor(wareid)
	return math.max(1, math.floor((wareAvgPrice(wareid) * 1.20) + 0.5))
end

local function addSource(row, item, isPlayer)
	local count = numericCount(itemField(item, "count"))
	if count <= 0 then
		return
	end
	local source = {
		item = item,
		index = sourceIndexFor(item, isPlayer),
		count = count,
		wareid = safeString(itemField(item, "wareid") or itemField(item, "ware") or ""),
		macro = safeString(itemField(item, "macro") or ""),
		category = categoryKey(itemField(item, "category")),
	}
	if isPlayer then
		table.insert(row.playerSources, source)
		row.playeramount = row.playeramount + count
	else
		table.insert(row.storeSources, source)
		row.storeamount = row.storeamount + count
	end
end

local function addGroupedRow(target, item, isPlayer)
	if type(item) ~= "table" or numericCount(itemField(item, "count")) <= 0 then
		return
	end
	local key = rowKey(item)
	local row = target.bykey[key]
	if not row then
		local wareid = safeString(itemField(item, "wareid") or itemField(item, "ware") or "")
		row = {
			key = key,
			category = categoryKey(itemField(item, "category")),
			wareid = wareid,
			macro = safeString(itemField(item, "macro") or ""),
			name = getItemName(item),
			faction = safeString(itemField(item, "faction") or ""),
			sellprice = sellPriceFor(wareid),
			buyprice = buyPriceFor(wareid),
			playeramount = 0,
			storeamount = 0,
			playerSources = {},
			storeSources = {},
			sellAmount = 0,
			buyAmount = 0,
		}
		target.bykey[key] = row
		table.insert(target.rows, row)
	end
	addSource(row, item, isPlayer)
end

local function syncSourceBarterAmounts(row)
	local remainingSell = numericCount(row.sellAmount)
	for _, source in ipairs(row.playerSources or {}) do
		local take = math.min(remainingSell, numericCount(source.count))
		if type(source.item) == "table" then
			source.item.barterAmount = take
		end
		remainingSell = remainingSell - take
	end

	local remainingBuy = numericCount(row.buyAmount)
	for _, source in ipairs(row.storeSources or {}) do
		local take = math.min(remainingBuy, numericCount(source.count))
		if type(source.item) == "table" then
			source.item.barterAmount = take
		end
		remainingBuy = remainingBuy - take
	end
end

local function sortedGroupedRows()
	local grouped = { rows = {}, bykey = {} }
	if tradeData and tradeData.playerData and type(tradeData.playerData.inventory) == "table" then
		for _, item in pairs(tradeData.playerData.inventory) do
			addGroupedRow(grouped, item, true)
		end
	end
	if tradeData and tradeData.storeData and type(tradeData.storeData.inventory) == "table" then
		for _, item in pairs(tradeData.storeData.inventory) do
			addGroupedRow(grouped, item, false)
		end
	end
	table.sort(grouped.rows, function(a, b)
		if a.category ~= b.category then
			local order = { weapons = 1, shields = 2, engines = 3, thrusters = 4, turrets = 5, other = 6 }
			return (order[a.category] or 99) < (order[b.category] or 99)
		end
		return a.name < b.name
	end)
	return grouped.rows
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

local function loadTradeData()
	if tradeData then
		return
	end
	local id = playerID()
	if id and GetNPCBlackboard then
		local ok, data = pcall(GetNPCBlackboard, id, ses.blackboard)
		if ok and type(data) == "table" then
			tradeData = data
		end
	end
	if not tradeData then
		tradeData = {
			playerData = { name = "Salvage Inventory", inventory = {} },
			storeData = { name = "Black Market Stock", inventory = {} },
			rows = {},
		}
	end
	tradeData.rows = sortedGroupedRows()
	tradeData.opened = true
	emit("ses_black_market_opened", ses.version)
	sesLog("Opened SES Black Market UserQuestionMenu slider trader rows=" .. tostring(#tradeData.rows))
end

local function clearTradeData()
	tradeData = nil
	tradeMenu = {}
end

local function selectedAmount(row, isPlayer)
	if isPlayer then
		return numericCount(row.sellAmount)
	end
	return numericCount(row.buyAmount)
end

local function setSelectedAmount(row, isPlayer, amount)
	local quantity = numericCount(amount)
	if isPlayer then
		row.sellAmount = math.min(quantity, numericCount(row.playeramount))
		if row.sellAmount > 0 then
			row.buyAmount = 0
		end
	else
		row.buyAmount = math.min(quantity, numericCount(row.storeamount))
		if row.buyAmount > 0 then
			row.sellAmount = 0
		end
	end
	syncSourceBarterAmounts(row)
end

local function tradeValue(row, isPlayer)
	local quantity = selectedAmount(row, isPlayer)
	if isPlayer then
		return quantity * row.sellprice
	end
	return quantity * row.buyprice
end

local function totalNetToTrader()
	local total = 0
	if tradeData and tradeData.rows then
		for _, row in ipairs(tradeData.rows) do
			total = total + (numericCount(row.buyAmount) * row.buyprice)
			total = total - (numericCount(row.sellAmount) * row.sellprice)
		end
	end
	return total
end

local function splitSourcesForPayload(result, mode, sources, quantity)
	local remaining = numericCount(quantity)
	for _, source in ipairs(sources or {}) do
		if remaining <= 0 then
			break
		end
		local take = math.min(remaining, numericCount(source.count))
		if take > 0 then
			table.insert(result, {
				["$mode"] = mode,
				["$index"] = source.index or 0,
				["$quantity"] = take,
				["$wareid"] = source.wareid or "",
				["$macro"] = source.macro or "",
				["$category"] = source.category or "",
			})
			remaining = remaining - take
		end
	end
	return remaining
end

local function buildConfirmPayload()
	local payloadRows = {}
	local selectedRows = 0
	local selectedQuantity = 0
	if tradeData and tradeData.rows then
		for _, row in ipairs(tradeData.rows) do
			local sellAmount = numericCount(row.sellAmount)
			local buyAmount = numericCount(row.buyAmount)
			if sellAmount > 0 then
				selectedRows = selectedRows + 1
				selectedQuantity = selectedQuantity + sellAmount
				splitSourcesForPayload(payloadRows, "sell", row.playerSources, sellAmount)
			end
			if buyAmount > 0 then
				selectedRows = selectedRows + 1
				selectedQuantity = selectedQuantity + buyAmount
				splitSourcesForPayload(payloadRows, "buy", row.storeSources, buyAmount)
			end
		end
	end
	local payload = {
		["$version"] = ses.version,
		["$token"] = tradeData and tradeData.token or "",
		["$totalprice"] = totalNetToTrader(),
		["$selectedrows"] = selectedRows,
		["$selectedquantity"] = selectedQuantity,
		["$payloadrowcount"] = #payloadRows,
		["$rows"] = payloadRows,
	}
	sesLog("Built confirm payload selectedRows=" .. tostring(selectedRows) .. ", selectedQuantity=" .. tostring(selectedQuantity) .. ", payloadRows=" .. tostring(#payloadRows) .. ", net=" .. tostring(payload["$totalprice"]))
	return payload
end

local function isConfirmActive()
	local net = totalNetToTrader()
	if net == 0 then
		return false
	end
	if net > 0 then
		return (GetPlayerMoney and GetPlayerMoney() or 0) >= net
	end
	return true
end

local function renderTradeTable(frame, data, properties, isPlayer)
	local title = "Salvage Inventory"
	if data and data.name then
		title = safeString(data.name)
	end
	local ftable = frame:addTable(5, properties)
	ftable:setColWidth(2, scaledTextWidth(7), false)
	ftable:setColWidth(3, scaledTextWidth(5), false)
	ftable:setColWidth(4, scaledTextWidth(9), false)
	ftable:setColWidth(5, scaledTextWidth(7), false)

	if isPlayer then
		tradeMenu.playerFTable = ftable
	else
		tradeMenu.storeFTable = ftable
	end

	local row = ftable:addRow(true, { bgColor = Helper.defaultTitleBackgroundColor })
	row[1]:setColSpan(5):createText(title, Helper.titleTextProperties)

	row = ftable:addRow(true, { bgColor = Helper.color.transparent })
	row[1]:createText(sesText(500, "Ship Part"), Helper.subHeaderTextProperties)
	row[2]:createText(sesText(501, "Price"), Helper.subHeaderTextProperties)
	row[3]:createText(sesText(109, "Available"), Helper.subHeaderTextProperties)
	row[4]:createText(isPlayer and sesText(502, "Sell") or sesText(503, "Buy"), Helper.subHeaderTextProperties)
	row[5]:createText(sesText(504, "Value"), Helper.subHeaderTextProperties)

	if tradeData and tradeData.rows and #tradeData.rows > 0 then
		local lastCategory = ""
		for _, item in ipairs(tradeData.rows) do
			local available = isPlayer and item.playeramount or item.storeamount
			if available > 0 then
				if item.category ~= lastCategory then
					lastCategory = item.category
					row = ftable:addRow(true, { bgColor = Helper.color.transparent })
					row[1]:setColSpan(5):createText(categoryName(item.category), Helper.subHeaderTextProperties)
					row[1].properties.halign = "center"
				end

				local selected = selectedAmount(item, isPlayer)
				local price = isPlayer and item.sellprice or item.buyprice
				local value = price * selected

				row = ftable:addRow(true, { bgColor = Helper.color.transparent })
				row[1]:createText(item.name)
				row[2]:createText(moneyText(price), { halign = "right" })
				row[3]:createText(tostring(available), { halign = "right" })
				row[4]:createSliderCell({
					min = 0,
					max = available,
					start = selected,
				})
				row[4].handlers.onSliderCellChanged = function(_, value)
					setSelectedAmount(item, isPlayer, value)
					if isPlayer then
						tradeMenu.playerRow = row.index
					else
						tradeMenu.storeRow = row.index
					end
					return
				end
				row[4].handlers.onSliderCellConfirm = function()
					emitDebug("slider confirm side=" .. (isPlayer and "sell" or "buy") .. ", name=" .. safeString(item.name) .. ", selected=" .. tostring(selectedAmount(item, isPlayer)) .. ", net=" .. tostring(totalNetToTrader()))
					userQuestionMenu.refresh = getElapsed()
					return
				end
				row[5]:createText(moneyText(value), { halign = "right" })
			end
		end
	else
		row = ftable:addRow(true, { bgColor = Helper.color.transparent })
		row[1]:setColSpan(5):createText(sesText(506, "-- No salvaged ship parts available --"), { halign = "center" })
	end

	local total = 0
	if tradeData and tradeData.rows then
		for _, item in ipairs(tradeData.rows) do
			total = total + tradeValue(item, isPlayer)
		end
	end

	row = ftable:addRow(true, { bgColor = Helper.color.transparent })
	row[4]:createText(sesText(507, "Total"), Helper.subHeaderTextProperties)
	row[5]:createText(moneyText(total), { halign = "right" })
	return ftable
end

local function completeTrade()
	local payload = buildConfirmPayload()
	if not payload["$rows"] or #payload["$rows"] <= 0 then
		emitDebug("complete ignored selectedrows=" .. tostring(payload["$selectedrows"]) .. ", selectedquantity=" .. tostring(payload["$selectedquantity"]) .. ", payloadrows=" .. tostring(payload["$payloadrowcount"]) .. ", net=" .. tostring(payload["$totalprice"]))
		sesLog("Complete trade ignored because no selected slider rows produced a payload.")
		if userQuestionMenu then
			userQuestionMenu.refresh = getElapsed()
		end
		return
	end
	local id = playerID()
	local blackboardOK = false
	if id and SetNPCBlackboard then
		-- Match Kuertee's proven barter bridge: persist the MD-created barter
		-- inventory with per-source barterAmount values, then emit a parameterless
		-- UI event. UI-only grouped rows contain shared Lua references and must not
		-- cross the blackboard boundary.
		local groupedRows = tradeData.rows
		tradeData.rows = nil
		local ok = pcall(SetNPCBlackboard, id, ses.blackboard, tradeData)
		tradeData.rows = groupedRows
		blackboardOK = ok
	end
	emitDebug("complete emit selectedrows=" .. tostring(payload["$selectedrows"]) .. ", selectedquantity=" .. tostring(payload["$selectedquantity"]) .. ", payloadrows=" .. tostring(payload["$payloadrowcount"]) .. ", net=" .. tostring(payload["$totalprice"]) .. ", barterblackboardok=" .. tostring(blackboardOK))
	if AddUITriggeredEvent then
		pcall(AddUITriggeredEvent, "UserQuestionMenu", "ses_black_market_complete_trade")
	end
	userQuestionMenu.onCloseElement("close")
end

local function createTradeTables(frame)
	local frameProperties = getFrameProperties()
	local tableProperties = getTableProperties(frameProperties)
	local properties = {
		tabOrder = 1,
		borderEnabled = true,
		width = tableProperties.width,
		x = frameProperties.borderSize,
		y = frameProperties.borderSize,
		maxVisibleHeight = frameProperties.height * 0.68,
	}
	local playerTable = renderTradeTable(frame, tradeData.playerData, properties, true)

	properties = {
		tabOrder = 2,
		borderEnabled = true,
		width = tableProperties.width,
		x = frameProperties.borderSize + tableProperties.width + frameProperties.borderSize,
		y = frameProperties.borderSize,
		maxVisibleHeight = frameProperties.height * 0.68,
	}
	local storeTable = renderTradeTable(frame, tradeData.storeData, properties, false)

	local y = math.max(playerTable:getVisibleHeight(), storeTable:getVisibleHeight())
	properties = {
		tabOrder = 3,
		borderEnabled = true,
		-- X4's scaled UserQuestionMenu viewport is narrower than Helper.viewWidth
		-- on the active 2048-wide profile. Keep the four-column footer inside the
		-- visible frame so the right-aligned Complete Trade and Cancel buttons are
		-- both fully reachable.
		width = frameProperties.width * 0.82,
		x = frameProperties.borderSize,
		y = frameProperties.borderSize + y + frameProperties.borderSize,
	}
	local confirmTable = frame:addTable(4, properties)
	tradeMenu.confirmFTable = confirmTable

	local net = totalNetToTrader()
	local color = Helper.color.white
	if net < 0 then
		color = Helper.color.green
	elseif net > 0 then
		color = Helper.color.red
	end

	local row = confirmTable:addRow(true, { bgColor = Helper.color.transparent })
	row[1]:createText(sesText(508, "Transaction Value"), Helper.subHeaderTextProperties)
	row[2]:createText(moneyText(math.abs(net)), { halign = "right", color = color })
	row[3]:createText(sesText(509, "Balance"), Helper.subHeaderTextProperties)
	row[4]:createText(moneyText(GetPlayerMoney and GetPlayerMoney() or 0), { halign = "right" })

	row = confirmTable:addRow(true, { bgColor = Helper.color.transparent })
	row[3]:createButton({ active = isConfirmActive() }):setText(sesText(510, "Complete Trade"), { halign = "center" })
	row[3].handlers.onClick = function()
		tradeMenu.confirmRow = row.index
		return completeTrade()
	end
	row[4]:createButton({ active = true }):setText(sesText(114, "Cancel"), { halign = "center" })
	row[4].handlers.onClick = function()
		emit("ses_black_market_closed", { ["$reason"] = "cancelled", ["$version"] = ses.version })
		userQuestionMenu.onCloseElement("close")
	end

	return confirmTable
end

function ModLua.cleanup_end()
	if tradeData then
		emit("ses_black_market_closed", { ["$reason"] = "cleanup", ["$version"] = ses.version })
	end
	clearTradeData()
end

function ModLua.createInfoFrame_custom_frame_properties(config)
	local menu = userQuestionMenu
	if menu.mode ~= ses.mode then
		return nil
	end

	loadTradeData()
	local frameProperties = getFrameProperties()
	local width = frameProperties.width + 3 * frameProperties.borderSize
	local height = frameProperties.height + 3 * frameProperties.borderSize
	local viewWidth = helperNumber("viewWidth", 1920)
	local viewHeight = helperNumber("viewHeight", 1080)
	return {
		standardButtons = { close = true },
		width = width,
		height = height,
		x = (viewWidth - width) / 2,
		y = (viewHeight - height) / 2,
		layer = config.layer,
		startAnimation = false,
		playerControls = false,
	}
end

function ModLua.createTable_new_custom_table(frame)
	local menu = userQuestionMenu
	if menu.mode ~= ses.mode then
		return nil
	end
	loadTradeData()
	local ftable = createTradeTables(frame)
	if tradeMenu.playerFTable and tradeMenu.playerRow then
		tradeMenu.playerFTable:setSelectedRow(tradeMenu.playerRow)
		tradeMenu.playerRow = nil
	end
	if tradeMenu.storeFTable and tradeMenu.storeRow then
		tradeMenu.storeFTable:setSelectedRow(tradeMenu.storeRow)
		tradeMenu.storeRow = nil
	end
	if tradeMenu.confirmFTable and tradeMenu.confirmRow then
		tradeMenu.confirmFTable:setSelectedRow(tradeMenu.confirmRow)
		tradeMenu.confirmRow = nil
	end
	return ftable
end

local function runPatchAttempt(reason)
	userQuestionMenu = findMenuByName("UserQuestionMenu", "UserQuestionMenu")
	if userQuestionMenu and userQuestionMenu.registerCallback then
		if userQuestionMenu.sesBlackMarketCallbacksVersion == ses.version then
			return true
		end
		userQuestionMenu.registerCallback("cleanup_end", ModLua.cleanup_end, "ship_equipment_salvaging_black_market")
		userQuestionMenu.registerCallback("createInfoFrame_custom_frame_properties", ModLua.createInfoFrame_custom_frame_properties, "ship_equipment_salvaging_black_market")
		userQuestionMenu.registerCallback("createTable_new_custom_table", ModLua.createTable_new_custom_table, "ship_equipment_salvaging_black_market")
		userQuestionMenu.sesBlackMarketCallbacksVersion = ses.version
		emit("ses_black_market_loaded", ses.version)
		sesLog("Loaded SES UserQuestionMenu Black Market slider trader callbacks. reason=" .. safeString(reason or "direct"))
		return true
	else
		emit("ses_black_market_missing_userquestion", safeString(reason or "direct"))
		sesLog("UserQuestionMenu callback registration unavailable. reason=" .. safeString(reason or "direct"))
	end
	return false
end

function ModLua.init()
	sesLog("Loaded SES Black Market UserQuestionMenu slider addon via ui.xml/Kuertee UIX path.")
	emit("ses_black_market_lua_loaded", ses.version)
	runPatchAttempt("init")

	if Register_OnLoad_Init then
		Register_OnLoad_Init(function()
			runPatchAttempt("onload")
		end, "SES Black Market UserQuestionMenu callback patch")
	end

	if Helper and Helper.addDelayedOneTimeCallbackOnUpdate and getElapsedTime then
		Helper.addDelayedOneTimeCallbackOnUpdate(function()
			runPatchAttempt("delayed_1s")
		end, true, getElapsedTime() + 1)
		Helper.addDelayedOneTimeCallbackOnUpdate(function()
			runPatchAttempt("delayed_3s")
		end, true, getElapsedTime() + 3)
	end
end

ModLua.init()

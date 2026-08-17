--print("Loaded <Compat.lua>")
--[[
	Compatibility layer for the 3.3.5a (Wrath of the Lich King) client used by
	WoW Ascension.

	LootZ was written against the modern client API. The 3.3.5a client is
	missing a fair amount of it, so everything that differs between clients is
	collected here instead of being scattered through the addon.

	Every helper feature-detects, so the addon keeps working on the retail and
	Classic clients it was originally written for.
]]

local addonName = ...
if (addonName == nil or addonName == "") then addonName = "LootZ" end

local function class()
	local obj = {}

	obj.addonName = addonName
	obj.isLegacyClient = (C_Timer == nil)

	local driver = CreateFrame("Frame", "LootZCompatDriver")



	--Timers (C_Timer does not exist on 3.3.5a)
	local timers = {}

	local function TimerCancel(self)
		self.cancelled = true
	end

	local function AddTimer(delay, callback, interval, iterations)
		if (type(callback) ~= "function") then return nil end

		local timer = {}
		timer.at = GetTime() + (delay or 0)
		timer.callback = callback
		timer.interval = interval
		timer.iterations = iterations
		timer.cancelled = false
		timer.Cancel = TimerCancel
		timer.IsCancelled = function(self) return self.cancelled end

		table.insert(timers, timer)
		return timer
	end

	local function UpdateTimers()
		local now = GetTime()

		--Reverse order so finished timers can be removed while iterating
		for i = #timers, 1, -1 do
			local timer = timers[i]

			if (timer.cancelled) then
				table.remove(timers, i)
			elseif (now >= timer.at) then
				if (timer.interval == nil) then
					table.remove(timers, i)
				else
					timer.at = now + timer.interval
					if (timer.iterations ~= nil) then
						timer.iterations = timer.iterations - 1
						if (timer.iterations <= 0) then
							timer.cancelled = true
						end
					end
				end

				timer.callback(timer)
			end
		end
	end

	if (C_Timer == nil) then
		C_Timer = {}

		function C_Timer.After(delay, callback)
			AddTimer(delay, callback)
		end

		function C_Timer.NewTimer(delay, callback)
			return AddTimer(delay, callback)
		end

		function C_Timer.NewTicker(interval, callback, iterations)
			return AddTimer(interval, callback, interval, iterations)
		end
	end



	--Addon metadata (C_AddOns is a modern namespace)
	function obj:GetAddOnMetadata(name, field)
		if (C_AddOns ~= nil and C_AddOns.GetAddOnMetadata ~= nil) then
			return C_AddOns.GetAddOnMetadata(name, field)
		end
		if (GetAddOnMetadata ~= nil) then
			return GetAddOnMetadata(name, field)
		end

		return nil
	end



	--Item loading (the Item mixin / ContinueOnItemLoad does not exist on 3.3.5a)
	local itemCache = {}
	local itemRequests = {}
	local itemRequestCount = 0
	local itemTimeout = 10.0
	local itemQueryInterval = 1.0
	local itemQueriesPerUpdate = 20
	local itemUpdateInterval = 0.1
	local nextItemUpdate = 0
	local scanTooltip = nil

	function obj:GetItemData(itemId)
		local name, link, rarity, level, minLevel, itemType, subType,
			stackCount, slot, texture, sellprice, classId, subClassId = GetItemInfo(itemId)

		if (name == nil or link == nil) then return nil end

		local item = {}
		item.id = itemId
		item.name = name
		item.link = link
		item.rarity = rarity or 1
		item.level = level or 0
		item.minLevel = minLevel or 0
		item.type = itemType or ""
		item.subtype = subType or ""
		item.stackCount = stackCount or 1
		item.slot = slot or ""
		item.texture = texture
		item.sellprice = sellprice or 0
		item.classId = classId
		item.subClassId = subClassId

		return item
	end

	function obj:QueryItem(itemId)
		--Asking for a tooltip makes the 3.3.5a client request the item from the
		--server, which is what populates GetItemInfo a moment later.
		if (scanTooltip == nil) then
			scanTooltip = CreateFrame("GameTooltip", "LootZScanTooltip", UIParent, "GameTooltipTemplate")
		end

		scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
		pcall(scanTooltip.SetHyperlink, scanTooltip, "item:" .. itemId)
		scanTooltip:Hide()
	end

	function obj:RequestItem(itemId, callback)
		if (callback == nil) then return end

		itemId = tonumber(itemId)
		if (itemId == nil) then
			callback(nil)
			return
		end

		--Already known
		local cached = itemCache[itemId]
		if (cached ~= nil) then
			callback(cached)
			return
		end

		--Available right away
		local item = obj:GetItemData(itemId)
		if (item ~= nil) then
			itemCache[itemId] = item
			callback(item)
			return
		end

		--Wait for the client to cache it
		local request = itemRequests[itemId]
		if (request == nil) then
			request = {}
			request.callbacks = {}
			request.deadline = GetTime() + itemTimeout
			request.nextQuery = 0
			itemRequests[itemId] = request
			itemRequestCount = itemRequestCount + 1
		end

		table.insert(request.callbacks, callback)
	end

	local function ResolveRequest(itemId, request, item)
		itemRequests[itemId] = nil
		itemRequestCount = itemRequestCount - 1

		for i = 1, #request.callbacks do
			request.callbacks[i](item)
		end
	end

	local function UpdateItemRequests()
		if (itemRequestCount <= 0) then return end

		local now = GetTime()
		if (now < nextItemUpdate) then return end
		nextItemUpdate = now + itemUpdateInterval

		local queries = 0
		for itemId, request in pairs(itemRequests) do
			local item = obj:GetItemData(itemId)

			if (item ~= nil) then
				itemCache[itemId] = item
				ResolveRequest(itemId, request, item)
			elseif (now >= request.deadline) then
				ResolveRequest(itemId, request, nil)
			elseif (queries < itemQueriesPerUpdate and now >= request.nextQuery) then
				queries = queries + 1
				request.nextQuery = now + itemQueryInterval
				obj:QueryItem(itemId)
			end
		end
	end

	function obj:GetItemIdFromLink(link)
		if (link == nil) then return nil end

		if (GetItemInfoFromHyperlink ~= nil) then
			return GetItemInfoFromHyperlink(link)
		end

		return tonumber(string.match(link, "item:(%d+)"))
	end



	--Unit GUIDs (3.3.5a uses a 64 bit hex string instead of a dashed string)
	local legacyGuidTypes = {
		["F130"] = "Creature",
		["F140"] = "Pet",
		["F150"] = "Vehicle",
		["F110"] = "GameObject",
		["F120"] = "Transport",
		["F100"] = "DynamicObject",
		["F101"] = "Corpse",
		["4000"] = "Item",
		["0000"] = "Player",
	}

	function obj:BreakGUID(guid)
		local data = {}
		if (guid == nil or guid == "") then return data end

		--Modern dashed GUID: "Creature-0-970-0-11-448-0000018B1D"
		if (string.find(guid, "-", 1, true) ~= nil) then
			local parts = { strsplit("-", guid) }
			data.type = parts[1]

			if (data.type == "Player") then
				data.realm = tonumber(parts[2])
				data.instance = parts[3]
			else
				data.realm = tonumber(parts[3])
				data.zone = tonumber(parts[5])
				data.index = tonumber(parts[6])
				data.instance = parts[7]
			end

			return data
		end

		--3.3.5a GUID: "0x" .. <high:4><entry:6><counter:6>
		local hex = string.gsub(guid, "^0[xX]", "")
		hex = string.upper(hex)
		if (string.len(hex) < 16) then
			hex = string.rep("0", 16 - string.len(hex)) .. hex
		end

		data.type = legacyGuidTypes[string.sub(hex, 1, 4)] or "Unknown"
		if (data.type ~= "Player" and data.type ~= "Item") then
			data.index = tonumber(string.sub(hex, 5, 10), 16)
			data.counter = tonumber(string.sub(hex, 11, 16), 16)
		end

		return data
	end



	--World position (3.3.5a has no world coordinates at all)
	function obj:GetPlayerPosition()
		if (UnitPosition ~= nil) then
			return UnitPosition("player")
		end

		return nil, nil
	end

	--Continent name (C_Map is a modern namespace)
	function obj:GetContinentName()
		if (C_Map ~= nil and C_Map.GetBestMapForUnit ~= nil) then
			local mapID = C_Map.GetBestMapForUnit("player")
			while (mapID) do
				local info = C_Map.GetMapInfo(mapID)
				if (info == nil) then return nil end
				if (info.mapType == 2) then return info.name end
				mapID = info.parentMapID
			end

			return nil
		end

		if (GetCurrentMapContinent == nil or GetMapContinents == nil) then return nil end

		--The world map has to point at the player for this to be accurate
		if (SetMapToCurrentZone ~= nil and (WorldMapFrame == nil or not WorldMapFrame:IsShown())) then
			pcall(SetMapToCurrentZone)
		end

		local continents = { GetMapContinents() }
		return continents[GetCurrentMapContinent()]
	end



	--Global mouse events (GLOBAL_MOUSE_UP does not exist on 3.3.5a)
	--Polling the button state works identically on every client, and unlike a
	--WorldFrame hook it also sees clicks that land on top of a UI frame.
	local trackedButtons = { "LeftButton", "RightButton", "MiddleButton", "Button4", "Button5" }
	local buttonWasDown = {}
	local mouseUpHandlers = {}
	local mouseDownHandlers = {}

	function obj:RegisterGlobalMouseUp(handler)
		table.insert(mouseUpHandlers, handler)
	end

	function obj:RegisterGlobalMouseDown(handler)
		table.insert(mouseDownHandlers, handler)
	end

	local function UpdateMouseButtons()
		if (IsMouseButtonDown == nil) then return end

		for i = 1, #trackedButtons do
			local button = trackedButtons[i]
			local isDown = IsMouseButtonDown(button) and true or false

			if (isDown ~= (buttonWasDown[button] or false)) then
				buttonWasDown[button] = isDown

				local handlers = isDown and mouseDownHandlers or mouseUpHandlers
				for j = 1, #handlers do
					handlers[j](button)
				end
			end
		end
	end



	--Keyboard input
	--Without SetPropagateKeyboardInput a frame that listens for keys swallows
	--them, so on 3.3.5a the keyboard is only captured while binding a hotkey.
	obj.hasKeyboardPropagation = (driver.SetPropagateKeyboardInput ~= nil)

	function obj:SetKeyboardCapture(frame, enabled)
		if (frame == nil) then return end

		if (obj.hasKeyboardPropagation) then
			frame:EnableKeyboard(true)
			frame:SetPropagateKeyboardInput(true)
			return
		end

		frame:EnableKeyboard(enabled and true or false)
	end



	--Widgets
	function obj:SetSize(frame, width, height)
		--Region:SetSize is not available on every 3.3.5a build
		frame:SetWidth(width)
		frame:SetHeight(height)
	end

	function obj:CreateButton(name, parent)
		local templates = { "UIPanelButtonTemplate", "GameMenuButtonTemplate", "OptionsButtonTemplate" }

		for i = 1, #templates do
			local ok, button = pcall(CreateFrame, "Button", name, parent, templates[i])
			if (ok and button ~= nil and button.SetText ~= nil) then
				return button
			end
		end

		--Last resort: a plain button that still renders its label
		local button = CreateFrame("Button", name, parent)
		local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("CENTER")
		button:SetFontString(label)

		return button
	end

	function obj:CreateCheckButton(name, parent)
		local templates = { "UICheckButtonTemplate", "OptionsCheckButtonTemplate", "InterfaceOptionsCheckButtonTemplate" }

		for i = 1, #templates do
			local ok, button = pcall(CreateFrame, "CheckButton", name, parent, templates[i])
			if (ok and button ~= nil and button.SetChecked ~= nil) then
				return button
			end
		end

		return CreateFrame("CheckButton", name, parent)
	end

	function obj:SetCursorTexture(cursor)
		if (SetCursor == nil) then return end
		pcall(SetCursor, cursor)
	end

	function obj:ResetCursorTexture()
		if (ResetCursor == nil) then return end
		pcall(ResetCursor)
	end



	--Money strings ("1 Gold, 20 Silver, 5 Copper")
	local function AmountWord(pattern, fallback)
		if (pattern == nil) then return fallback end

		local word = string.gsub(pattern, "%%d", "")
		word = string.gsub(word, "^%s+", "")
		word = string.gsub(word, "%s+$", "")
		if (word == "") then return fallback end

		return word
	end

	local function MatchAmount(text, word)
		if (word == nil) then return 0 end

		local pattern = "(%d+)%s*" .. string.gsub(word, "(%W)", "%%%1")
		return tonumber(string.match(text, pattern)) or 0
	end

	function obj:ParseMoneyString(text)
		if (text == nil) then return 0 end

		local gold = MatchAmount(text, AmountWord(GOLD_AMOUNT, "Gold"))
		local silver = MatchAmount(text, AmountWord(SILVER_AMOUNT, "Silver"))
		local copper = MatchAmount(text, AmountWord(COPPER_AMOUNT, "Copper"))

		return (gold * 10000) + (silver * 100) + copper
	end



	--Combat log
	--3.3.5a passes the payload as event arguments, later clients pass it
	--through CombatLogGetCurrentEventInfo and insert extra fields
	function obj:ReadCombatLogEvent(...)
		local args
		if (CombatLogGetCurrentEventInfo ~= nil) then
			args = { CombatLogGetCurrentEventInfo() }
		else
			args = { ... }
		end

		local data = {}
		data.event = args[2]

		if (type(args[3]) == "boolean") then
			--timestamp, event, hideCaster, sourceGUID, sourceName, sourceFlags,
			--sourceRaidFlags, destGUID, destName
			data.sourceGUID = args[4]
			data.sourceName = args[5]
			data.destGUID = args[8]
			data.destName = args[9]
		else
			--timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID,
			--destName, destFlags
			data.sourceGUID = args[3]
			data.sourceName = args[4]
			data.destGUID = args[6]
			data.destName = args[7]
		end

		return data
	end



	--Loot chat messages, used when something loots for you and no loot window
	--is ever opened
	local function MessagePrefix(pattern, fallback)
		if (pattern == nil) then return fallback end

		local prefix = string.match(pattern, "^(.-)%%s")
		if (prefix == nil or prefix == "") then return fallback end

		return prefix
	end

	function obj:IsSelfLootMessage(message)
		if (message == nil) then return false end

		local prefixes = {
			MessagePrefix(LOOT_ITEM_SELF, "You receive loot:"),
			MessagePrefix(LOOT_ITEM_SELF_MULTIPLE, "You receive loot:"),
			MessagePrefix(LOOT_ITEM_PUSHED_SELF, "You receive item:"),
			MessagePrefix(LOOT_ITEM_PUSHED_SELF_MULTIPLE, "You receive item:"),
		}

		for i = 1, #prefixes do
			local prefix = prefixes[i]
			if (string.sub(message, 1, string.len(prefix)) == prefix) then
				return true
			end
		end

		return false
	end

	function obj:ParseLootMessage(message)
		if (message == nil) then return nil end

		local itemId = tonumber(string.match(message, "|Hitem:(%d+)"))
		if (itemId == nil) then return nil end

		--"...|h|rx3." - a single item has no count at all
		local quantity = tonumber(string.match(message, "[xX](%d+)%.?%s*$")) or 1
		local name = string.match(message, "%[(.-)%]")

		return itemId, quantity, name
	end



	--Tooltip helpers
	function obj:GetTooltipSpell(tooltip)
		if (tooltip.GetSpell == nil) then return nil end

		local ok, name = pcall(tooltip.GetSpell, tooltip)
		if (not ok) then return nil end

		return name
	end

	--Drive everything that needs a heartbeat
	driver:SetScript("OnUpdate", function()
		UpdateTimers()
		UpdateItemRequests()
		UpdateMouseButtons()
	end)

	return obj
end

_G.LEDII_LZ_COMPAT = class()

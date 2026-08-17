--print("Loaded <Looting.lua>")
local log = _G.LEDII_LZ_LOG
local const = _G.LEDII_LZ_CONST
local utils = _G.LEDII_LZ_UTILS
local compat = _G.LEDII_LZ_COMPAT

local function class()
	local obj = {}
	local cachedGUIDs = {}
	local currentLootSource = nil
	local openedLootSources = {}
	local lootSourceLocked = false
	local lootObjectLocked = false

	--Companion looting (Ascension's Lootbot 3000 and friends). Nothing ever
	--opens a loot window, the items simply appear, so the only trace is the
	--chat message. It is matched against the creatures that just died.
	local recentKills = {}
	local recentKillMax = 12
	local recentKillTimeout = 30.0
	local lootWindowOpen = false
	local lootWindowOpenedAt = 0
	--Not 0: that would read as "a window just closed" at the start of a session
	local lootWindowClosedAt = -math.huge
	local lootWindowSettleTime = 1.5
	local lootWindowTimeout = 30.0

	function obj:OnTargetChanged()
		obj:CleanupCache("target")
		--obj:TryCacheUnit("target")
	end

	function obj:OnMouseoverChanged()
		obj:CleanupCache("mouseover")
		--obj:TryCacheUnit("mouseover")
	end

	function obj:PrepareCache()
		if (LediiData_LootZ == nil) then
			LediiData_LootZ = {}
		end
		if (LediiData_LootZ.cache == nil) then
			LediiData_LootZ.cache = {}
		end
		cachedGUIDs = LediiData_LootZ.cache
	end

	function obj:SaveCache()
		LediiData_LootZ.cache = cachedGUIDs
	end

	function obj:CleanupCache(unitId)
		--Validate guid
		local guid = UnitGUID(unitId)
		if (guid == nil) then return end
		if (UnitIsDead(unitId)) then return end

		--Remove from looting cache
		--log:Info("Cleanup guid: " .. guid)
		obj:PrepareCache()
		cachedGUIDs[guid] = nil;
		obj:SaveCache()
	end

	function obj:TryCacheGUID(guid)
		--Ignore objects without GUID (Chests, Mining, etc...)
		if (guid == nil) then
			return false
		end

		--Ignore objects which has already been looted
		obj:PrepareCache()
		--log:Info("Looting GUID: " .. guid)
		if (cachedGUIDs[guid] ~= nil) then
			return false
		end

		--New valid loot
		cachedGUIDs[guid] = true
		obj:SaveCache()
		return true
	end

	function obj:IsValidLootTarget(unitId)
		local name = UnitName(unitId)
		if (name == nil) then return false end

		local dead = UnitIsDead(unitId)
		return dead
	end 

	function obj:OnMouseUp(...)
		--Handle only right clicks
		local button = ...
		if (button ~= "RightButton") then return end

		--Handle valid targets
		local unitId = "target"
		local validTarget = obj:IsValidLootTarget(unitId)
		if (not validTarget) then return end

		--Prevent accidental objects
		local objName = utils:GetCurrentObjectName()
		if (lootObjectLocked) then return end
		if (objName ~= nil) then
			currentLootSource = nil
			lootObjectLocked = true
			log:Info(const:Color("WARNING") .. "Statistics not supported for object <" .. objName .. ">")
			log:Info(const:Color("WARNING") .. "Next loot window will be ignored!")
			return
		end

		--Prevent accidental rapid clicks
		if (lootSourceLocked) then return end
		lootSourceLocked = true
		C_Timer.After(0.5, function()
			lootSourceLocked = false
		end)
		--log:Info(const:Color("WARNING") .. "Source locked for 0.5s <" .. UnitName(unitId) .. ">")

		--Update loot source
		currentLootSource = obj:BuildLootSource(unitId)
		--log:Info("Loot source: " .. currentLootSource.name)
	end

	function obj:BuildLootSource(unitId)
		local source = {}
		source.guid = UnitGUID(unitId)
		source.name = UnitName(unitId)
		source.level = UnitLevel(unitId)
		source.type = UnitCreatureType(unitId)
		source.family = UnitCreatureFamily(unitId) or "Solitary"
		source.dead = UnitIsDead(unitId)
		source.unitId = utils:BreakGUID(source.guid).index

		return source
	end

	function obj:TryBuildTargetLootSource()
		--Only a dead unit can be a loot source
		if (not obj:IsValidLootTarget("target")) then return nil end

		--Never attribute the loot of a world object to the current target
		if (utils:GetCurrentObjectName() ~= nil) then return nil end

		return obj:BuildLootSource("target")
	end

	function obj:GetLootSlot(index)
		local lootIcon, lootName, lootQuantity, rarity, locked, isQuestItem, questId, isActive = GetLootSlotInfo(index);

		local data = {}
		data.name = lootName
		data.quantity = lootQuantity
		data.isQuest = isQuestItem
		data.link = GetLootSlotLink(index)

		--Handle money
		if (data.link == nil) then
			return data
		end

		local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, itemSellPrice = GetItemInfo(data.link)

		--Handle invisible party loot
		if (itemLink == nil) then
			data.name = nil
			return data
		end

		data.ilvl = itemLevel
		data.type = itemType
		data.subType = itemSubType
		data.itemId = compat:GetItemIdFromLink(itemLink)

		return data
	end

	function obj:LogItem()
		log:ValueString({ UnitClass("target") }, "UnitClass")
		log:ValueString({ UnitFactionGroup("target") }, "UnitFactionGroup")
		log:ValueString({ UnitRace("target") }, "UnitRace")
	end

	function obj:SaveUnit(lootSrc, dataUnit)
		LediiData_LootZ.units[lootSrc.unitId] = dataUnit

		--Shared statistics are merged with these numbers, drop the merge
		utils:InvalidateStatsCache()
	end

	function obj:OnLootReady()
		--log:Info("OnLootReady")
		
		--Consume object lock
		if (lootObjectLocked) then
			lootObjectLocked = false
			return
		end

		--Fall back to the target when the click was not seen. Looting a corpse
		--always targets it on 3.3.5a, and this also covers looting through a
		--keybind instead of the mouse.
		local targetSource = obj:TryBuildTargetLootSource()
		if (targetSource ~= nil) then
			if (currentLootSource == nil or currentLootSource.guid ~= targetSource.guid) then
				currentLootSource = targetSource
			end
		end

		if (currentLootSource == nil) then return end
		if (not currentLootSource.dead) then return end
		openedLootSources = {}
		table.insert(openedLootSources, currentLootSource)
		--log:Info("Opened Source: " .. openedLootSource.name)
	end

	function obj:OnLootOpened()
		--log:Info("OnLootOpened")
		lootWindowOpen = true
		lootWindowOpenedAt = GetTime()

		--Validate disabled
		obj:PrepareCache()
		obj:DebugLog("LOOT_OPENED source=" .. tostring(currentLootSource and currentLootSource.name))
		if (LediiData_LootZ.statsGatherDisabled) then return end

		--Validate sources
		if (#openedLootSources == 0) then
			if (not LediiData_LootZ.logStatsEnabled) then return end
			log:Info(const:Color("WARNING") .. "Warning: No loot source available!")
			return
		end

		if (#openedLootSources > 1) then
			if (LediiData_LootZ.logStatsEnabled) then return end
			log:Info(const:Color("WARNING") .. "Warning: Multiple loot sources detected!")

			for i, v in ipairs(openedLootSources) do
				log:Info(const:Color("WARNING") .. "Source[" .. i .. "] = " .. v.name)
			end
			openedLootSources = {}
			return
		end

		--Validate already looted
		local lootSrc = openedLootSources[1]
		if (lootSrc == nil or lootSrc.unitId == nil) then return end

		--log:Info("Source: " .. lootSrc.name .. " (Level " .. lootSrc.level .. ")")
		local validCache = obj:TryCacheGUID(lootSrc.guid)
		if (not validCache) then
			openedLootSources = {}
			return
		end
		
		--log:Info("New loot data for " .. lootSrc.name .. " (Level " .. lootSrc.level .. ")")
		--log:Info("[" .. lootSrc.type .. ", " .. lootSrc.family .. ", " .. lootSrc.zone .. "]")
		--obj:LogItem()

		local dataUnit = obj:PrepareUnitData(lootSrc)
		obj:RegisterLooting(lootSrc, dataUnit)
		for i = 1, 20 do
			local lootSlot = obj:GetLootSlot(i)

			if (lootSlot.name ~= nil) then
				if (lootSlot.link ~= nil) then
					obj:RegisterItem(lootSrc, lootSlot, dataUnit)
				else
					obj:RegisterMoney(lootSrc, lootSlot, dataUnit)
				end
			end
		end
		obj:SaveUnit(lootSrc, dataUnit)
		openedLootSources = {}
	end

	function obj:PrepareUnitData(lootSrc)
		if (LediiData_LootZ.units == nil) then
			LediiData_LootZ.units = {}
		end
		if (LediiData_LootZ.units[lootSrc.unitId] == nil) then
			local dataUnit = {}
			dataUnit.name = lootSrc.name
			dataUnit.lootingCount = 0
			dataUnit.items = {}
			dataUnit.money = nil
			LediiData_LootZ.units[lootSrc.unitId] = dataUnit
		end

		return LediiData_LootZ.units[lootSrc.unitId]
	end

	function obj:RegisterLooting(lootSrc, dataUnit)
		dataUnit.lootingCount = dataUnit.lootingCount + 1
	end

	function obj:RegisterItem(lootSrc, lootSlot, dataUnit)
		--log:Info("Item: " .. lootSlot.link .. "x" .. lootSlot.quantity .. " (" .. lootSlot.type .. ", " .. lootSlot.subType .. ")")

		dataUnit.items[lootSlot.itemId] = obj:RegisterSlot(lootSlot, dataUnit.items[lootSlot.itemId])
	end

	function obj:RegisterMoney(lootSrc, lootSlot, dataUnit)
		--The coin text is formatted differently per client and per locale,
		--the compat layer reads the amounts straight out of the string
		local total = compat:ParseMoneyString(lootSlot.name)

		--log:Info("Money: " .. const:Color("TEXT_HIGHLIGHT") .. GetCoinTextureString(total))
		lootSlot.name = "Money"
		lootSlot.quantity = total

		dataUnit.money = obj:RegisterSlot(lootSlot, dataUnit.money)
	end

	--Companion looting -------------------------------------------------------

	function obj:IsCompanionLootEnabled()
		return LediiData_LootZ ~= nil and LediiData_LootZ.companionLootEnabled == true
	end

	function obj:OnLootClosed()
		lootWindowOpen = false
		lootWindowClosedAt = GetTime()
	end

	function obj:OnUnitDied(destGUID, destName)
		if (destGUID == nil) then return end

		local ids = utils:BreakGUID(destGUID)
		if (ids.index == nil) then return end
		if (ids.type ~= "Creature" and ids.type ~= "Vehicle") then return end

		--Newest first, so the most recent corpse wins
		local kill = {}
		kill.guid = destGUID
		kill.name = destName
		kill.unitId = ids.index
		kill.time = GetTime()
		table.insert(recentKills, 1, kill)

		while (#recentKills > recentKillMax) do
			table.remove(recentKills)
		end

		obj:DebugLog("UNIT_DIED " .. tostring(destName) .. " (id " .. ids.index .. ")")
	end

	function obj:FindRecentKill()
		local now = GetTime()

		for i = 1, #recentKills do
			local kill = recentKills[i]
			if (now - kill.time <= recentKillTimeout) then
				return kill
			end
		end

		return nil
	end

	function obj:IsLootWindowOpen()
		if (not lootWindowOpen) then return false end

		--A LOOT_CLOSED that never arrives would silently stop all companion
		--tracking, so never trust the flag on its own
		if (GetTime() - lootWindowOpenedAt > lootWindowTimeout) then return false end
		if (LootFrame ~= nil and LootFrame.IsShown ~= nil and not LootFrame:IsShown()) then return false end

		return true
	end

	function obj:IsCompanionLootWindow()
		--Anything that arrives while a loot window is open, or right after one
		--closed, is already handled by OnLootOpened
		if (obj:IsLootWindowOpen()) then return false end
		if (GetTime() < lootWindowClosedAt + lootWindowSettleTime) then return false end

		return true
	end

	function obj:OnChatLoot(message)
		obj:DebugLog("CHAT_MSG_LOOT " .. tostring(message))

		if (not obj:IsCompanionLootEnabled()) then return end
		if (LediiData_LootZ.statsGatherDisabled) then return end
		if (not obj:IsCompanionLootWindow()) then return end
		if (not compat:IsSelfLootMessage(message)) then return end

		local itemId, quantity, name = compat:ParseLootMessage(message)
		if (itemId == nil) then return end

		local kill = obj:FindRecentKill()
		if (kill == nil) then
			log:Info(const:Color("WARNING") .. "Companion loot with no recent kill to match, ignored.")
			return
		end

		local lootSlot = {}
		lootSlot.name = name or ("Item " .. itemId)
		lootSlot.quantity = quantity
		lootSlot.itemId = itemId

		local dataUnit = obj:RegisterCompanionKill(kill)
		dataUnit.items[itemId] = obj:RegisterSlot(lootSlot, dataUnit.items[itemId])
		obj:SaveUnit(kill, dataUnit)

		obj:DebugLog("companion loot " .. lootSlot.name .. " x" .. quantity .. " -> " .. kill.name)
	end

	function obj:OnChatMoney(message)
		obj:DebugLog("CHAT_MSG_MONEY " .. tostring(message))

		if (not obj:IsCompanionLootEnabled()) then return end
		if (LediiData_LootZ.statsGatherDisabled) then return end
		if (not obj:IsCompanionLootWindow()) then return end

		local total = compat:ParseMoneyString(message)
		if (total <= 0) then return end

		local kill = obj:FindRecentKill()
		if (kill == nil) then return end

		local lootSlot = {}
		lootSlot.name = "Money"
		lootSlot.quantity = total

		local dataUnit = obj:RegisterCompanionKill(kill)
		dataUnit.money = obj:RegisterSlot(lootSlot, dataUnit.money)
		obj:SaveUnit(kill, dataUnit)
	end

	--Counts the corpse once, the first time anything is attributed to it. The
	--guid cache is shared with the loot window path, so a corpse can never be
	--counted by both.
	function obj:RegisterCompanionKill(kill)
		obj:PrepareCache()
		local dataUnit = obj:PrepareUnitData(kill)

		if (obj:TryCacheGUID(kill.guid)) then
			obj:RegisterLooting(kill, dataUnit)
		end

		return dataUnit
	end

	function obj:OnLootWindowOpened()
		lootWindowOpen = true
	end

	function obj:DebugLog(text)
		if (LediiData_LootZ == nil) then return end
		if (not LediiData_LootZ.debugEnabled) then return end

		log:Info(const:Color("TEXT_HIGHLIGHT") .. "[debug] " .. const:Color("TEXT") .. text)
	end

	function obj:RegisterSlot(lootSlot, dataSlot)
		if (dataSlot == nil) then
			dataSlot = {}
			dataSlot.name = lootSlot.name
			dataSlot.minAmount = math.huge
			dataSlot.maxAmount = -math.huge
			dataSlot.totalAmount = 0
			dataSlot.totalCount = 0
		end

		if (lootSlot.quantity < dataSlot.minAmount) then
			dataSlot.minAmount = lootSlot.quantity
		end
		if (lootSlot.quantity > dataSlot.maxAmount) then
			dataSlot.maxAmount = lootSlot.quantity
		end
		dataSlot.totalAmount = dataSlot.totalAmount + lootSlot.quantity
		dataSlot.totalCount = dataSlot.totalCount + 1

		return dataSlot
	end

	return obj
end

_G.LEDII_LZ_LOOT = class()
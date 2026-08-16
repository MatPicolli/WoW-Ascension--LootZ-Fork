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

		--Validate disabled
		obj:PrepareCache()
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
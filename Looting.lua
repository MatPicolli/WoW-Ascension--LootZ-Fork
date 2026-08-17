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
	local recentKillTimeout = 90.0
	local deathsSeen = 0
	local lastUnmatchedWarning = -math.huge
	local unmatchedWarningInterval = 10.0
	local lootWindowOpen = false
	local lootWindowOpenedAt = 0
	--Not 0: that would read as "a window just closed" at the start of a session
	local lootWindowClosedAt = -math.huge
	local lootWindowSettleTime = 1.5
	local lootWindowTimeout = 30.0
	local lastWindowWasCreature = true

	function obj:OnTargetChanged()
		obj:CleanupCache("target")
		obj:CacheUnitName("target")
	end

	function obj:OnMouseoverChanged()
		obj:CleanupCache("mouseover")
		obj:CacheUnitName("mouseover")
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
		lastWindowWasCreature = (#openedLootSources > 0)
		obj:DebugLog("LOOT_OPENED source=" .. tostring(currentLootSource and currentLootSource.name))
		if (LediiData_LootZ.statsGatherDisabled) then return end

		--Companion mode counts the kill and reads the items from chat, which
		--also covers looting by hand. Recording here as well would count twice.
		if (obj:IsCompanionLootEnabled()) then
			obj:DebugLog("loot window not recorded, companion looting is on")
			openedLootSources = {}
			return
		end

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
	--
	--A companion that loots for you never opens a loot window, so the items only
	--show up as chat messages that do not name the creature. Kills are tracked
	--separately and the two are matched up.
	--
	--On some servers (Ascension among them) the combat log never reports a
	--single death to addons, so there are three sources, best first:
	--  1. the combat log, which carries a guid and therefore a creature id
	--  2. the kill text in chat ("X dies, you gain N experience"), which only
	--     carries a name, resolved through a remembered name to id map
	--  3. a corpse under the cursor, used only while the first two are silent

	function obj:IsCompanionLootEnabled()
		return LediiData_LootZ ~= nil and LediiData_LootZ.companionLootEnabled == true
	end

	function obj:IsDebugEnabled()
		return LediiData_LootZ ~= nil and LediiData_LootZ.debugEnabled == true
	end

	function obj:DebugLog(text)
		if (not obj:IsDebugEnabled()) then return end

		log:Info(const:Color("TEXT_HIGHLIGHT") .. "[debug] " .. const:Color("TEXT") .. text)
	end

	function obj:GetCompanionState()
		return deathsSeen, #recentKills, recentKillTimeout
	end



	--Creature names, so a kill that is only reported as text can still be
	--credited to the right creature id. Kept in saved variables, so a creature
	--only has to be seen once ever.
	function obj:RememberUnitName(name, unitId)
		if (name == nil or unitId == nil) then return end

		obj:PrepareCache()
		if (LediiData_LootZ.names == nil) then
			LediiData_LootZ.names = {}
		end

		LediiData_LootZ.names[name] = unitId
	end

	function obj:FindUnitIdByName(name)
		if (name == nil) then return nil end
		if (LediiData_LootZ == nil or LediiData_LootZ.names == nil) then return nil end

		return LediiData_LootZ.names[name]
	end

	function obj:CacheUnitName(unitId)
		local guid = UnitGUID(unitId)
		if (guid == nil) then return end
		if (UnitIsPlayer(unitId)) then return end

		local ids = utils:BreakGUID(guid)
		obj:RememberUnitName(UnitName(unitId), ids.index)
	end



	--Kills
	--Things that are definitely not a lootable creature. Anything else is
	--accepted, including an unrecognised guid type: a server using custom guid
	--ranges would otherwise record no deaths at all.
	local nonCreatureTypes = {
		["Player"] = true,
		["Item"] = true,
		["GameObject"] = true,
		["Corpse"] = true,
		["DynamicObject"] = true,
		["Transport"] = true,
	}

	--Records a kill, counting it as one sample the first time it is seen.
	--With a companion looting there is no per corpse loot window, so the kill
	--is what defines a sample, not the loot.
	function obj:TouchKill(unitId, name, guid, source)
		if (unitId == nil) then
			obj:DebugLog("kill ignored, no creature id known for " .. tostring(name))
			return nil
		end

		--A corpse already in the list is the same sample, not a new one
		if (guid ~= nil) then
			for i = 1, #recentKills do
				if (recentKills[i].guid == guid) then return recentKills[i] end
			end
		end

		local kill = {}
		kill.guid = guid
		kill.name = name or ("Creature #" .. unitId)
		kill.unitId = unitId
		kill.time = GetTime()

		table.insert(recentKills, 1, kill)
		while (#recentKills > recentKillMax) do
			table.remove(recentKills)
		end

		--Only kills reported by an event prove the addon can see deaths at all.
		--A corpse under the cursor must not switch that fallback off.
		if (source ~= "corpse") then
			deathsSeen = deathsSeen + 1
		end

		obj:RememberUnitName(name, unitId)

		--Counting shares the looted corpse list with the loot window path, so a
		--corpse can never be counted by both
		local isNewCorpse = (guid == nil) or obj:TryCacheGUID(guid)
		if (isNewCorpse and obj:IsCompanionLootEnabled() and not LediiData_LootZ.statsGatherDisabled) then
			local dataUnit = obj:PrepareUnitData(kill)
			obj:RegisterLooting(kill, dataUnit)
			obj:SaveUnit(kill, dataUnit)
		end

		obj:DebugLog("kill " .. kill.name .. " id " .. unitId .. " from " .. tostring(source))
		return kill
	end

	function obj:OnUnitDied(destGUID, destName)
		if (destGUID == nil) then return end

		local ids = utils:BreakGUID(destGUID)
		if (ids.index == nil or ids.index == 0) then
			obj:DebugLog("death ignored, no creature id in guid " .. tostring(destGUID))
			return
		end
		if (nonCreatureTypes[ids.type]) then
			obj:DebugLog("death ignored, guid type " .. tostring(ids.type) .. " " .. tostring(destGUID))
			return
		end

		obj:TouchKill(ids.index, destName, destGUID, "combatlog")
	end

	--"Scourge Champion dies, you gain 213 experience."
	function obj:OnKillText(message)
		obj:DebugLog("kill text " .. tostring(message))

		local name = compat:ParseKillMessage(message)
		if (name == nil) then return end

		local unitId = obj:FindUnitIdByName(name)
		if (unitId == nil) then
			obj:DebugLog("kill text ignored, never seen a creature called " .. name)

			--Something died that cannot be identified, so whatever is looted
			--next must not be credited to an earlier creature
			recentKills = {}
			return
		end

		obj:TouchKill(unitId, name, nil, "text")
	end

	function obj:FindRecentKill()
		local now = GetTime()

		for i = 1, #recentKills do
			local kill = recentKills[i]
			if (now - kill.time <= recentKillTimeout) then
				return kill
			end
		end

		--No kill was ever reported by an event, so fall back to a corpse the
		--player is looking at. This is why the mouse has to be on the creature
		--when the other two sources are silent.
		if (deathsSeen == 0) then
			return obj:FindTargetedCorpse()
		end

		return nil
	end

	function obj:FindTargetedCorpse()
		local unitIds = { "target", "mouseover" }

		for i = 1, #unitIds do
			local unitId = unitIds[i]
			if (obj:IsValidLootTarget(unitId)) then
				local source = obj:BuildLootSource(unitId)
				if (source.unitId ~= nil) then
					obj:DebugLog("no reported deaths, using " .. unitId .. " corpse " .. tostring(source.name))
					return obj:TouchKill(source.unitId, source.name, source.guid, "corpse")
				end
			end
		end

		return nil
	end

	--Explains why loot could not be credited, instead of repeating one line
	function obj:WarnUnmatchedLoot()
		local now = GetTime()
		if (now - lastUnmatchedWarning < unmatchedWarningInterval) then return end
		lastUnmatchedWarning = now

		if (deathsSeen == 0) then
			log:Info(const:Color("WARNING") .. "Companion loot ignored: no kill has been reported at all.")
			log:Info(const:Color("WARNING") .. "Keep the mouse over creatures as they die, or type "
				.. const:Color("TEXT_HIGHLIGHT") .. "/lootz debug" .. const:Color("WARNING") .. " and report the output.")
			return
		end

		local age = "?"
		if (recentKills[1] ~= nil) then
			age = string.format("%.0f", now - recentKills[1].time)
		end

		log:Info(const:Color("WARNING") .. "Companion loot ignored: the last kill was " .. age
			.. "s ago, and the limit is " .. recentKillTimeout .. "s.")
	end



	--Loot windows
	function obj:OnLootClosed()
		lootWindowOpen = false
		lootWindowClosedAt = GetTime()
	end

	function obj:IsLootWindowOpen()
		if (not lootWindowOpen) then return false end

		--A LOOT_CLOSED that never arrives would silently stop all companion
		--tracking, so never trust the flag on its own
		if (GetTime() - lootWindowOpenedAt > lootWindowTimeout) then return false end
		if (LootFrame ~= nil and LootFrame.IsShown ~= nil and not LootFrame:IsShown()) then return false end

		return true
	end

	--Whether chat loot arriving now belongs to a creature.
	--A creature's loot window is fine, the items arrive in chat either way and
	--the corpse was already counted when it died. A chest, herb or ore node is
	--not: its contents have nothing to do with the last kill.
	function obj:IsCompanionLootWindow()
		if (obj:IsLootWindowOpen()) then return lastWindowWasCreature end

		if (not lastWindowWasCreature and GetTime() < lootWindowClosedAt + lootWindowSettleTime) then
			return false
		end

		return true
	end



	--Chat loot
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
			obj:WarnUnmatchedLoot()
			return
		end

		local lootSlot = {}
		lootSlot.name = name or ("Item " .. itemId)
		lootSlot.quantity = quantity
		lootSlot.itemId = itemId

		local dataUnit = obj:PrepareUnitData(kill)
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
		if (kill == nil) then
			obj:WarnUnmatchedLoot()
			return
		end

		local lootSlot = {}
		lootSlot.name = "Money"
		lootSlot.quantity = total

		local dataUnit = obj:PrepareUnitData(kill)
		dataUnit.money = obj:RegisterSlot(lootSlot, dataUnit.money)
		obj:SaveUnit(kill, dataUnit)
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
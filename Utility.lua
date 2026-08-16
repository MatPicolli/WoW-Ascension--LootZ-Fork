--print("Loaded <Utility.lua>")
local const = _G.LEDII_LZ_CONST
local log = _G.LEDII_LZ_LOG
local compat = _G.LEDII_LZ_COMPAT

local function class()
	local obj = {}

	--Database
	function obj:GetTablesDB(dbName)
		local tables = {}
		local numTables = 100

		--The loot database is optional, see Database/Setup.lua
		local db = _G.LEDII_DB
		if (db == nil) then return tables end

		for i = 1, numTables do
			local dbTable = db[dbName .. "_" .. i]
			if (dbTable ~= nil) then
				table.insert(tables, dbTable)
			end
		end

		return tables
	end

	local missingTablesWarned = {}

	function obj:FindIndexFromDB(dbName, index, failWarning)
		local tables = obj:GetTablesDB(dbName)
		if (#tables == 0) then
			--Only warn once per table, otherwise a missing database spams the chat
			if (not missingTablesWarned[dbName]) then
				missingTablesWarned[dbName] = true
				log:Info(const:Color("ERROR") .. "Database table <" .. dbName .. "> does not exist")
				log:Info(const:Color("ERROR") .. "See the readme on how to install the loot database.")
			end
			return nil
		end

		for i = 1, #tables do
			local dbTable = tables[i]
			if (dbTable ~= nil) then
				local entry = dbTable[index .. ""]
				if (entry ~= nil) then
					--log:Info("Found entry <" .. index .. "> in database table <" .. dbName .. ">")
					return entry
				end
			end
		end

		if (failWarning == nil or failWarning == true) then
			log:Info(const:Color("WARNING") .. "No entry <" .. index .. "> in database table <" .. dbName .. ">")
		end
		return nil
	end

	function obj:ValidateObjectPosition(index, px, py, maxDistance, failWarning)
		--invalid positions in dungeons
		if (px == nil or py == nil) then return false end

		--log:Info("Validating position of index: " .. index)
		local objectInstance = obj:FindIndexFromDB("GameObjectInstance", index, failWarning)
		if (objectInstance == nil) then return false end

		for i = 1, #objectInstance do
			local ox = objectInstance[i].positionX
			local oy = objectInstance[i].positionY
			local oz = objectInstance[i].positionZ
			local dist = math.sqrt(math.pow((ox) - (px), 2) + math.pow((oy) - (py), 2))

			--if (dist <= 1000) then
				--log:Info("Object distance: " .. string.format("%.2f", dist))
			--end

			if (dist <= maxDistance) then
				--log:Info("Object position: " .. string.format("%.2f", ox) .. ", " .. string.format("%.2f", oy) .. " (Distance: " .. string.format("%.2f", dist) .. ")")
				--log:Info("Respawn time: " .. objectInstance[i].spawnTime)
				return true
			end
		end

		return false
	end

	function obj:GetCurrentObjectName()
		--Prevent non objects
		local tUnit = GameTooltip:GetUnit()
		local tItem = GameTooltip:GetItem()
		local tSpell = compat:GetTooltipSpell(GameTooltip)
		if (tUnit ~= nil or tItem ~= nil or tSpell ~= nil) then return end

		--Get name of object from tooltip
		local nameLine = _G["GameTooltipTextLeft1"]
		if (nameLine == nil) then return end
		local name = nameLine:GetText()
		if (name == nil) then return end
		--log:Info("Name: " .. name)

		--Handle invalid tooltip owners (menu ui buttons)
		--World objects anchor their tooltip to UIParent
		local owner = GameTooltip:GetOwner()
		if (owner == nil) then return end
		if (owner ~= UIParent) then
			if (owner["firstTimeLoaded"] == nil) then return end
			if (owner["variablesLoaded"] == nil) then return end
		end
		--log:ValueString(owner, "owner")

		return name
	end

	function obj:FindNearbyObjectInstances(validObjectRows, objectInstances, maxDistance)
		if (#objectInstances > 0) then return end

		--3.3.5a has no world coordinates, every candidate is accepted instead
		local px, py = compat:GetPlayerPosition()

		for i = 1, #validObjectRows do
			local row = validObjectRows[i]
			local loot = obj:FindIndexFromDB("GameObjectLoot", row.loot, false)
			if (loot ~= nil) then
				local invalidPosition = (px == nil or py == nil)
				if (obj:ValidateObjectPosition(row.entry, px, py, maxDistance, false) or invalidPosition) then
					table.insert(objectInstances, row)
				end
			end
		end
	end

	function obj:GetObjectRowsWithLoot(objectRows)
		local rows = {}

		for i = 1, #objectRows do
			local row = objectRows[i]
			local loot = obj:FindIndexFromDB("GameObjectLoot", row.loot, false)
			if (loot ~= nil) then
				table.insert(rows, row)
			end
		end

		return rows
	end

	function obj:FindObjectIndexes(objectName, warnMultiple)
		--Validate object for looting
		if (objectName == nil) then return nil end

		--log:Info("Finding index for: " .. objectName)
		local objectRows = obj:FindIndexFromDB("GameObjectData", objectName, failWarning)
		if (objectRows == nil) then return nil end

		local validObjectRows = obj:GetObjectRowsWithLoot(objectRows)
		if (#validObjectRows == 0) then return nil end

		--Validate object's distance to player (incrementally)
		local objectInstances = {}
		--obj:FindNearbyObjectInstances(validObjectRows, objectInstances, 20)
		--obj:FindNearbyObjectInstances(validObjectRows, objectInstances, 40)
		--obj:FindNearbyObjectInstances(validObjectRows, objectInstances, 60)
		--obj:FindNearbyObjectInstances(validObjectRows, objectInstances, 80)
		obj:FindNearbyObjectInstances(validObjectRows, objectInstances, 100)
		obj:FindNearbyObjectInstances(validObjectRows, objectInstances, 200)
		obj:FindNearbyObjectInstances(validObjectRows, objectInstances, 300)
		obj:FindNearbyObjectInstances(validObjectRows, objectInstances, 400)

		--Determine unique ids
		local uniqueIds = {}
		for i, v in ipairs(objectInstances) do
			if not(obj:TableContains(uniqueIds, v.loot)) then
				table.insert(uniqueIds, v.loot)
			end
		end

		--Warn about assumed inaccuracy
		if (#uniqueIds == 0) then return nil end
		if (#uniqueIds > 1 and warnMultiple) then
			log:Info(const:Color("WARNING") .. "Unable to determine exact object.")
			--log:Info(const:Color("WARNING") .. "The following object ids are nearby: " .. table.concat(entries, ", "))
			log:Info(const:Color("WARNING") .. "The following object ids are nearby: " .. table.concat(uniqueIds, ", "))
			log:Info(const:Color("WARNING") .. "Try move closer, or open the loot window through the chat command...")
		end

		return uniqueIds
	end

	function obj:FindObjectName(index)
		local dbTables = obj:GetTablesDB("GameObjectData")

		--For each table section
		for i = 1, #dbTables do
			local dbTable = dbTables[i]

			--For each key
			for key in pairs(dbTable) do
				local dbNames = dbTable[key]

				--For each element
				for j = 1, #dbNames do
					local dbRow = dbNames[j]

					if (dbRow.loot == index) then
						return key
					end
				end
			end
		end

		return nil
	end

	function obj:BreakGUID(guid)
		--Handles both the modern dashed GUID and the 3.3.5a hex GUID
		return compat:BreakGUID(guid)
	end

	function obj:MakeCustomLoot(item, reference, minCount, maxCount, chance, groupId)
		local loot = {}
		loot.item = item
		loot.reference = reference
		loot.chance = chance
		loot.questRequired = false
		loot.lootMode = 1
		loot.groupId = groupId
		loot.minCount = minCount
		loot.maxCount = maxCount

		return loot
	end

	function obj:FindIndexFromStats(dbName, index, failWarning)
		local rows = {}
		local dataUnit = obj:GetTrackedUnitData(index, false)
		local itemCountSum = 0
		local itemAmountSum = 0

		if (dataUnit == nil) then
			return rows
		end

		--Count sum of items
		for i, item in pairs(dataUnit.items) do
			itemCountSum = itemCountSum + 1
			itemAmountSum = itemAmountSum + item.totalAmount
		end

		--Add header row
		local totalChance = itemAmountSum / dataUnit.lootingCount * 100
		table.insert(rows, obj:MakeCustomLoot(itemCountSum, -1, 0, 0, totalChance, itemAmountSum))

		--Add item rows
		for i, item in pairs(dataUnit.items) do
			local min = item.minAmount
			local max = item.maxAmount
			local chance = item.totalCount / dataUnit.lootingCount * 100
			local group = item.totalAmount
			table.insert(rows, obj:MakeCustomLoot(i, 0, min, max, chance, group))
		end

		return rows
	end

	function obj:FindIndexFromAll(dbName, index, failWarning)
		local rows = {}

		--for i = 1, 1000 do
			--table.insert(rows, obj:MakeCustomLoot(i, 0, 0, 0, 0.0, i))
		--end

		return rows
	end



	--General use
	function obj:Split(s, delimiter)
		local result = {};
		for match in (s..delimiter):gmatch("(.-)"..delimiter) do
			table.insert(result, match);
		end
		return result;
	end

	function obj:CloneTableShallow(inTable)
		local orig_type = type(inTable)
		local copy
		if orig_type == 'table' then
			copy = {}
			for orig_key, orig_value in pairs(inTable) do
				copy[orig_key] = orig_value
			end
		else -- number, string, boolean, etc
			copy = inTable
		end
		return copy
	end

	function obj:CloneTableDeep(inTable)
		local orig_type = type(inTable)
		local copy
		if orig_type == 'table' then
			copy = {}
			for orig_key, orig_value in next, inTable, nil do
				copy[obj:CloneTableDeep(orig_key)] = obj:CloneTableDeep(orig_value)
			end
			setmetatable(copy, obj:CloneTableDeep(getmetatable(inTable)))
		else -- number, string, boolean, etc
			copy = inTable
		end
		return copy
	end

	function obj:JoinTable(inTable, delimiter)
		local text = ""

		for key in pairs(inTable) do
			if (text ~= "") then
				text = text .. delimiter
			end
			text = text .. inTable[key]
		end

		return text
	end

	function obj:RoundNumberNear(number, treshhold)
		treshhold = treshhold or 0.1

		local nearest = math.floor(number + 0.5)
		if (math.abs(nearest - number) < treshhold) then
			return nearest
		else
			return number
		end
	end

	function obj:RoundNumberAbove(number, treshhold)
		if (number >= treshhold) then
			return math.floor(number + 0.5)
		else
			return number
		end
	end

	function obj:LimitNumber(number, maxDecimals)
		local text = string.format("%." .. maxDecimals .. "f", number)
		return tonumber(text)

		--local text = number .. ""
		--if (string.find(text, "%.")) then
			--text = string.format("%." .. maxDecimals .. "f", number)
		--end

		--return text
	end

	function obj:DynamicNumber(number, maxDigits)
		--log:Info("Number: " .. number)
		local intStr, decStr = strsplit(".", number .. "")

		local intCount = string.len(intStr)
		local decCount = maxDigits - intCount

		local text = string.format("%." .. decCount .. "f", number)
		return tonumber(text)
	end

	function obj:TableContains(items, item)
		if (item == nil) then
			return false
		end

		for i = 1, #items do
			--Plain search, item names may contain pattern characters
			if (items[i] ~= nil and string.find(items[i], item, 1, true)) then
				return true
			end
		end

		return false
	end

	function obj:StringAfter(string, find)
		return string.sub(string, string.len(find) + 1)
	end

	function obj:GetContinent()
		return compat:GetContinentName()
	end



	-- Addon Specific
	function obj:GetRateStrings(inRate, maxDigits)
		if (inRate <= 0) then
			return "--", "--"
		end

		local rate = obj:DynamicNumber(inRate, maxDigits)

		local count = obj:RoundNumberNear(100.0 / inRate)
		count = obj:RoundNumberAbove(count, 100)
		count = obj:LimitNumber(count, 2)

		local rateStr = rate .. "%"
		local countStr = "x" .. count

		return rateStr, countStr
	end

	function obj:GetTrackedUnitData(index, showWarning)
		if (showWarning == nil) then
			showWarning = true
		end

		if (LediiData_LootZ ~= nil and LediiData_LootZ.units ~= nil) then
			local unitData = LediiData_LootZ.units[index]
			if (unitData ~= nil) then
				return unitData
			end
		end

		if (showWarning) then
			log:Info(const:Color("WARNING") .. "No data available for unit " .. index .. ".")
		end
		return nil
	end

	function obj:GetGroupDataType(rate)
		local data = {}

		if (rate <= 0.01) then
			--Range 0.0025% to 0.005%
			data.color = const:Color("EPIC")
			data.name = "World Epic"
		elseif (rate <= 0.1) then
			--Range 0.01% to 0.025%
			data.color = const:Color("RARE")
			data.name = "World Rare"
		elseif (rate <= 1.0) then
			--Range 0.1% to 1.0%
			data.color = const:Color("UNCOMMON")
			data.name = "World Uncommon"
		else
			--Range 1.0% to 2.5%
			data.color = const:Color("JUNK")
			data.name = "World Junk"
		end

		return data
	end

	function obj:GetGroupName(items)
		local data = {}
		table.insert(data, { "Poor", 0 })
		table.insert(data, { "Common", 0 })
		table.insert(data, { "Uncommon", 0 })
		table.insert(data, { "Rare", 0 })
		table.insert(data, { "Epic", 0 })
		table.insert(data, { "Legendary", 0 })

		for key in ipairs(items) do
			local item = items[key]
			local rarityIndex = item.rarity + 1
			data[rarityIndex][2] = data[rarityIndex][2] + 1
		end

		table.sort(data, function(a, b) return a[2] > b[2] end)
		local mostFrequentRarityName = data[1][1]
		return mostFrequentRarityName .. " Group"
	end

	function obj:FormatRange(min, max)
		if (min == max) then
			return min .. ""
		else
			return min .. "-" .. max
		end
	end

	function obj:TryFindItemInfo(index, successCallback, errorCallback)
		if (index == nil) then
			if (errorCallback ~= nil) then
				errorCallback("Item does not exist")
			end
			return
		end

		--The compat layer resolves the item now if the client already knows it,
		--otherwise it asks the server and calls back once the data arrives.
		--Items that never resolve call back with nil, which triggers a retry.
		compat:RequestItem(index, successCallback)
	end

	return obj
end

_G.LEDII_LZ_UTILS = class()
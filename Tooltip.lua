--print("Loaded <Tooltip.lua>")
local log = _G.LEDII_LZ_LOG
local const = _G.LEDII_LZ_CONST
local utils = _G.LEDII_LZ_UTILS
local requestUpdate = false
local currentObjectName = nil

local function class()
	local obj = {}

	function obj:OnSetUnit()
		--Validate disabled
		if (LediiData_LootZ.statsTooltipDisabled) then return end

		--Determine whether to read from mouseover or target
		local unitId = "mouseover"
		if (not UnitExists(unitId)) then
			unitId = "target"
		end

		--Determine whether unit should draw data
		if (not UnitCanAttack(unitId, "player")) then return end
		if (UnitCreatureType(unitId) == "Critter") then return end
		if (UnitIsPlayer(unitId)) then return end

		--log:Info(string.format("Tooltip for: %s (%s)", UnitName(unitId), UnitGUID(unitId)))
		local ids = utils:BreakGUID(UnitGUID(unitId))
		local dataUnit = utils:GetTrackedUnitData(ids.index, false)

		local lootCount = 0
		if (dataUnit ~= nil) then
			lootCount = dataUnit.lootingCount
		end

		obj:AddLine(" ")
		obj:AddLine(lootCount .. " Looted (ID: " .. ids.index .. ")")

		if (dataUnit == nil) then return end
		obj:PopulateMoney(dataUnit)
		obj:PopulateItems(dataUnit)
	end

	function obj:OnShow()
		obj:OnUpdate()
	end

	function obj:OnUpdate()
		--Validate disabled
		if (LediiData_LootZ.statsTooltipDisabled) then return end

		--Validate consumed update
		if (not requestUpdate) then return end
		requestUpdate = false

		--Validate new object
		local name = utils:GetCurrentObjectName()
		if (name == nil) then return end
		if (name == currentObjectName) then return end
		--log:Info("Name: " .. name)
		currentObjectName = name

		--Attempt to find data
		local indexes = utils:FindObjectIndexes(name, false)
		if (indexes == nil) then return end

		--Validate object for tooltip
		local validObject = false
		for i, index in ipairs(indexes) do
			local data = utils:FindIndexFromDB("GameObjectLoot", index, false)
			if (data ~= nil) then
				validObject = true
			end
		end
		if (not validObject) then return end

		--Update tooltip
		local indexStr = table.concat(indexes, ", ")
		obj:AddLine(" ")
		obj:AddLine("? Looted (ID: " .. indexStr .. ")")
		obj:AddLine("Object statistics not implemented")
		GameTooltip:Show()
	end

	function obj:OnLootOpened()
		--obj:TryFixFrozenTooltip()
	end

	function obj:TryFixFrozenTooltip()
		if (currentObjectName ~= nil) then
			log:Info("Attempt to fix frozen tooltip")
			GameTooltip:FadeOut()
		end
	end

	function obj:OnHide()
		currentObjectName = nil
		--log:Info("hiding")
	end

	function obj:OnCursorChanged()
		if (_G.LEDII_LZ_CURSOR_IGNORE) then
			_G.LEDII_LZ_CURSOR_IGNORE = false
			return
		end

		--Prevents possible messed up tooltips
		if (IsMouseButtonDown("RightButton")) then
			return
		end

		if (currentObjectName == nil) then
			requestUpdate = true
			--log:Info("Update tooltip")
		else
			currentObjectName = nil
			--log:Info("Leave tooltip")
		end
	end

	function obj:AddLine(text)
		GameTooltip:AddLine(text, 0, 1, 1)
	end

	function obj:PopulateItems(dataUnit)
		local itemCount = 0
		local sumAmountTotal = 0
		for key in pairs(dataUnit.items) do
			local item = dataUnit.items[key]
			itemCount = itemCount + 1
			sumAmountTotal = sumAmountTotal + item.totalAmount
		end

		local lootCount = dataUnit.lootingCount
		local lootAvg = sumAmountTotal / lootCount
		local avgStr = string.format("%.2f", lootAvg * 100)

		obj:AddLine("Items: " .. itemCount .. " Unique / " .. sumAmountTotal .. " Total (" .. avgStr .. "%)")
	end

	function obj:PopulateMoney(dataUnit)
		if (dataUnit.money ~= nil) then
			local minStr = GetCoinTextureString(dataUnit.money.minAmount)
			local maxStr = GetCoinTextureString(dataUnit.money.maxAmount)
			local rate = dataUnit.money.totalCount / dataUnit.lootingCount
			local rateStr = string.format("%.2f", rate * 100)
			--log:ValueString(dataUnit.money, "test money")
			obj:AddLine("Money: " .. minStr .. " to " .. maxStr .. " (" .. rateStr .. "%)")
		else
			--obj:AddLine("Money: Unknown")
		end
	end

	function obj:GetTooltipLines()
		local textLines = {}
		local regions = { GameTooltip:GetRegions() }

		for _, r in ipairs(regions) do
			if r:IsObjectType("FontString") then
				local line = {}
				line.text = r:GetText()
				line.color = { r:GetTextColor() }
				table.insert(textLines, line)
			end
		end

		return textLines
	end

	return obj
end

local class = class()
_G.LEDII_LZ_TOOLTIP = class

local function OnTooltipSetUnit()
	class:OnSetUnit()
end

local function OnTooltipShow()
	class:OnShow()
end

local function OnTooltipUpdate()
	class:OnUpdate()
end

local function OnTooltipHide()
	class:OnHide()
end

GameTooltip:HookScript("OnTooltipSetUnit", OnTooltipSetUnit)
GameTooltip:HookScript("OnShow", OnTooltipShow)
GameTooltip:HookScript("OnUpdate", OnTooltipUpdate)
GameTooltip:HookScript("OnHide", OnTooltipHide)
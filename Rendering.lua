--print("Loaded <Rendering.lua>")
local log = _G.LEDII_LZ_LOG
local const = _G.LEDII_LZ_CONST
local utils = _G.LEDII_LZ_UTILS
local compat = _G.LEDII_LZ_COMPAT

local target = {}
local hierarchy = nil
local hierarchyRendered = false

local visible = false
local mainFrame = nil
local mainPanelPivot = "TOPRIGHT"
local mainPanelEdgeOffset = { -10, -10 }
local mainPanelSize = { 600, 400 }
local scrollFrame = nil
local scrollViewport = nil
local headerLabel = nil
local dataButton = nil
local sortButton = nil
local searchField = nil
local searchInitialized = false
local optionsButton = nil
local closeButton = nil
local rowHeight = 20
local headerHeight = 30
local sortModes = { "Rate", "Name", "Type", "Color", "Group" }
local sortModeIndex = 1
--local dataModes = { "Data", "Stats", "Find" }
local dataModes = { "Data", "Stats" }
local dataModeIndex = 1
local tickDelay = 1/30
local rowFrames = {}
local rowIndex = 0
local rowFrameHovered = nil
local isShowingTooltip = false
local numRequestedItems = 0
local validObjectTargetTimer = nil
local isShowingCursor = false
local retryTarget = nil
local retryTargetType = nil
local retryConsumed = false
local retryDelay = 0.25
local sampleModifier = false
local filterCount = 0
local filterMaxCount = 1000
local buttonColor = const:Color("BUTTON")
local loadingDelay = 0.25

local function class()
	local obj = {}

	--Data logic
	function obj:FindNearestObject()
		local name = utils:GetCurrentObjectName()
		if (name == nil) then return end
		local indexes = utils:FindObjectIndexes(name, true)
		if (indexes == nil) then return end

		return "Object", indexes[1], name
	end

	function obj:SetTargetData(type, index, name)
		--Validate new target
		if (type == target.type and index == target.index) then return end
		if (type ~= nil and type == "Player") then
			type = nil
			index = nil
			name = nil
		end

		--Update display info
		target = {}
		target.type = type
		target.index = index
		target.name = name

		local name = UnitName("target")
		if (name == target.name) then
			target.level = UnitLevel("target")
		end

		-- Handle retry
		if (type == "RetryClear") then
			target.type = nil
			--log:Info("Retry target clear")
		elseif (type == "RetryUpdate") then
			target.type = retryTargetType
			--log:Info("Retry target update")
		else
			retryConsumed = false
			retryTarget = target
			retryTargetType = target.type
			--log:Info("Retry target setup")
		end

		obj:ClearHierarchy()
		if (type ~= nil) then
			obj:SetupHierarchy()
		end

		obj:ResetUI()
	end

	function obj:FindLayerPath(findLayer, layer)
		layer = layer or hierarchy

		if (layer.name == findLayer.name) then
			return { layer }
		end

		for i = 1, #layer.childLayers do
			local path = obj:FindLayerPath(findLayer, layer.childLayers[i])
			if (path ~= nil) then
				table.insert(path, 1, layer)
				return path
			end
		end

		return nil
	end

	function obj:GetLayerPathString(path)
		if (path == nil) then return nil end

		local pathStr = path[1].name
		for i = 2, #path do
			pathStr = pathStr .. " > " .. path[i].name
		end

		return pathStr
	end

	function obj:GetLayerPathChance(path)
		if (path == nil) then return nil end

		local pathChance = 1.0
		local str = "Main"
		for i = 2, #path do
			local chance = path[i].ref.chance * 0.01
			str = str .. " > " .. path[i].ref.chance
			pathChance = pathChance * chance
		end

		--local t = path[#path]
		--log:PairTable(t)
		--log:ValueString(t, "Test", 1)
		--log:Info("Test: " .. t.name .. " - " .. str)

		return pathChance * 100
	end

	function obj:SetupHierarchy()
		--log:Info("Setup new hierarchy...")

		--Account for professions from target
		local profession = obj:FindTooltipProfession()
		if (target.type == "Creature") then
			if (profession == "Skinnable") then
				target.type = "Skinning"
			end
		end

		--Gather data based on display mode
		local dataMode = dataModes[dataModeIndex]
		local dataRows = nil

		if (dataMode == "Data") then

			if (target.type == "Creature") then
				dataRows = utils:FindIndexFromDB("CreatureLoot", target.index)
			elseif (target.type == "Object") then
				dataRows = utils:FindIndexFromDB("GameObjectLoot", target.index)
			elseif (target.type == "Skinning") then
				dataRows = utils:FindIndexFromDB("SkinningLoot", target.index)
				if (dataRows == nil) then
					dataRows = obj:FindDefaultSkinning()
					--dataRows = utils:FindIndexFromDB("SkinningLoot", 100007)
				end
			elseif (target.type == "Pickpocketing") then
				dataRows = utils:FindIndexFromDB("PickpocketingLoot", target.index)
			end

		elseif (dataMode == "Stats") then

			dataRows = utils:FindIndexFromStats("CreatureLoot", target.index)

		elseif (dataMode == "Find") then

			dataRows = utils:FindIndexFromAll("CreatureLoot", target.index)

		end

		--Need data to continue
		if (dataRows == nil) then return end
		numRequestedItems = 1
		obj:SetupHierarchyLayer(nil, nil, dataRows)
		obj:FinishRequest()
	end

	function obj:FindDefaultSkinning()
		if (target.level == nil) then return nil end

		log:Info(const:Color("WARNING") .. "Finding assumed skinning for target...")
		local customEntity = {}
		local continent = utils:GetContinent()
		log:ValueString(continent, "continent")

		--Classic
		if (continent == "Kalimdor" or continent == "Eastern Kingdoms") then
			if (target.level >= 1 and target.level <= 17) then
				table.insert(customEntity, utils:MakeCustomLoot(2934, 0, 1, 1, 0, 1)) --Ruined Leather Scraps
			end
			if (target.level >= 1 and target.level <= 27) then
				table.insert(customEntity, utils:MakeCustomLoot(2318, 0, 1, 1, 0, 1)) --Light Leather
			end
			if (target.level >= 15 and target.level <= 38) then
				table.insert(customEntity, utils:MakeCustomLoot(2318, 0, 1, 1, 0, 1)) --Medium Leather
			end
			if (target.level >= 26 and target.level <= 46) then
				table.insert(customEntity, utils:MakeCustomLoot(2318, 0, 1, 1, 0, 1)) --Heavy Leather
			end
			if (target.level >= 35 and target.level <= 58) then
				table.insert(customEntity, utils:MakeCustomLoot(2318, 0, 1, 1, 0, 1)) --Thick Leather
			end
			if (target.level >= 45 and target.level <= 60) then
				table.insert(customEntity, utils:MakeCustomLoot(2318, 0, 1, 1, 0, 1)) --Rugged Leather
			end
		end

		--The Burning Crusade
		if (continent == "Outland") then
			if (target.level >= 58) then
				table.insert(customEntity, utils:MakeCustomLoot(2318, 0, 1, 1, 0, 1)) --Knothide Leather Scraps
			end
			if (target.level >= 58) then
				table.insert(customEntity, utils:MakeCustomLoot(2318, 0, 1, 1, 0, 1)) --Knothide Leather
			end
		end

		--Wrath of the Lich King
		if (continent == "Northrend") then
			if (target.level >= 68) then
				table.insert(customEntity, utils:MakeCustomLoot(2318, 0, 1, 1, 0, 1)) --Borean Leather Scraps
			end
			if (target.level >= 73) then
				table.insert(customEntity, utils:MakeCustomLoot(2318, 0, 1, 1, 0, 1)) --Borean Leather
			end
		end

		return customEntity
	end

	function obj:FindWorldLoot()
		if (target.level == nil) then return nil end

		log:Info(const:Color("WARNING") .. "Finding assumed world loot for target...")
		local customEntity = {}
		local continent = utils:GetContinent()
		log:ValueString(continent, "continent")

		--Classic
		if (continent == "Kalimdor" or continent == "Eastern Kingdoms") then
			if (target.level >= 1 and target.level <= 17) then
				table.insert(customEntity, utils:MakeCustomLoot(8181, 0, 1, 1, 0, 0)) --Ruined Leather Scraps
			end
		end

		return customEntity
	end

	function obj:GetReferenceLayerName(ref)
		local dataMode = dataModes[dataModeIndex]

		if (dataMode == "Data") then
			if (ref.reference > 0) then
				return ref.reference
			else
				local groupData = utils:GetGroupDataType(ref.item)
				return groupData.name
			end
		elseif (dataMode == "Stats") then
			return "Statistics"
		elseif (dataMode == "Find") then
			return "Item Search"
		end

		return "Unknown"
	end

	function obj:GetMainLayerName()
		local dataMode = dataModes[dataModeIndex]

		if (dataMode == "Data") then
			return "Main"
		elseif (dataMode == "Stats") then
			return "Account"
		elseif (dataMode == "Find") then
			return "Main"
		end

		return "Unknown"
	end

	function obj:SetupHierarchyLayer(previousLayer, ref, rows)
		--Create new layer
		local layer = {}
		layer.ref = ref
		layer.itemSets = {}
		layer.childLayers = {}

		if (previousLayer ~= nil) then
			layer.name = previousLayer.name .. " > " .. obj:GetReferenceLayerName(ref)
			table.insert(previousLayer.childLayers, layer)
			--log:Info("Setup layer: " .. layer.name)
			--log:Info("Prev / Next: " .. previousLayer.name .. " / " .. layer.ref.reference)
		else
			layer.name = obj:GetMainLayerName()
			hierarchy = layer
			--log:Info("Setup layer: " .. layer.name)
		end

		--Handle all rows for this layer
		local rowSkipCount = 0
		for i = 1, #rows do
			if (rowSkipCount > 0) then
				--Skip rows which are handled by next layer
				rowSkipCount = rowSkipCount - 1
			else
				local row = rows[i]
				if (row.reference > 0) then
					--Handle reference row
					local refData = utils:FindIndexFromDB("ReferenceLoot", row.reference)
					obj:SetupHierarchyLayer(layer, row, refData)
				elseif (row.reference < 0) then
					--Handle custom reference row
					local refData = {}
					local itemCount = row.item
					rowSkipCount = itemCount
					for j = 1, itemCount do
						local data = rows[i + j]
						table.insert(refData, data)
					end

					obj:SetupHierarchyLayer(layer, row, refData)
				else
					--Handle item row
					numRequestedItems = numRequestedItems + 1
					utils:TryFindItemInfo(row.item, function(item)
						obj:SetupHierarchyItem(layer, row, item)
					end)
				end
			end
		end
	end

	function obj:SetupHierarchyItem(layer, row, item)
		--Add item to set
		local set = {}
		set.row = row
		set.item = item
		table.insert(layer.itemSets, set)
		--log:Info("Setup row: " .. item.name)

		obj:FinishRequest()
	end

	function obj:ClearHierarchy()
		hierarchy = nil
		hierarchyRendered = false
	end

	function obj:GetGroupItemCount(layer, row)
		local findId = row.groupId
		if (findId == 0) then return 1, 0 end

		--local itemCount = 0
		--for i = 1, #layer.itemSets do
			--if (layer.itemSets[i].row.groupId == findId) then
				--itemCount = itemCount + 1
			--end
		--end

		local itemCount = layer.groupItemCount[findId]
		local refCount = 0

		return itemCount, refCount
	end

	function obj:FinishRequest()
		--Handle loading order issue
		numRequestedItems = numRequestedItems - 1
		if (numRequestedItems > 0) then return end

		--The 3.3.5a client only knows the items it has already seen, the rest
		--arrive from the server a moment later. Anything that lands after the
		--panel was drawn needs a redraw, or those rows are simply missing.
		if (not hierarchyRendered) then return end

		--log:Info("Done loading items... Updating UI")
		obj:UpdateUI()
	end



	--Events
	function obj:GetHotkeyModifierName()
		if (LediiData_LootZ == nil) then return false end
		local mod = LediiData_LootZ["HOTKEY_MOD"] or "CTRL"
		return mod
	end

	function obj:IsHotkeyModifierDown()
		if (LediiData_LootZ == nil) then return false end
		local mod = LediiData_LootZ["HOTKEY_MOD"] or "CTRL"
		if (mod == "SHIFT") then return IsShiftKeyDown() end
		if (mod == "CTRL") then return IsControlKeyDown() end
		if (mod == "ALT") then return IsAltKeyDown() end
		return false
	end

	function obj:SetKeyboardCapture(enabled)
		--Events.lua owns the frame that listens for keys
		local events = _G.LEDII_LZ_EVENTS
		if (events ~= nil) then
			events:SetKeyboardCapture(enabled)
		end
	end

	function obj:SampleModifierHotkey()
		sampleModifier = true
		obj:SetKeyboardCapture(true)
		log:Info("Next modifier { SHIFT | CTRL | ALT } pressed will be bound...")
	end

	function obj:HandleCustomHotkeyMap(key)
		if (sampleModifier == false) then return end
		if (LediiData_LootZ == nil) then return end

		LediiData_LootZ["HOTKEY_MOD"] = key
		sampleModifier = false
		obj:SetKeyboardCapture(false)
		log:Info("Assigned modifier: " .. key)
	end

	function obj:OnKeyDown(key)
		--log:Info("Key down: " .. key)

		if (key == "LSHIFT" or key == "RSHIFT") then key = "SHIFT" end
		if (key == "LCTRL" or key == "RCTRL") then key = "CTRL" end
		if (key == "LALT" or key == "RALT") then key = "ALT" end
		if (key ~= "SHIFT" and key ~= "CTRL" and key ~= "ALT") then return end

		obj:HandleCustomHotkeyMap(key)
	end

	function obj:OnKeyUp(key)
		--log:Info("Key down: " .. key)
	end

	function obj:OnGlobalMouseUp(button)
		--Validate click type
		obj:HandleCustomHotkeyMap(button)
		if (button ~= "LeftButton") then return end

		--Update search focus
		if (MouseIsOver(searchField)) then
			searchField:SetFocus(true)
		else
			searchField:ClearFocus()
		end

		--Handle row clicks
		obj:TickUI()
		if (rowFrameHovered ~= nil) then
			if (IsShiftKeyDown()) then
				obj:AppendChatLinkFromRowFrame(rowFrameHovered)
			end
		
			if (IsControlKeyDown()) then
				obj:DressUpFromRowFrame(rowFrameHovered)
			end

			return
		end

		--Activate display toggle only with bound modifier
		if (not obj:IsHotkeyModifierDown()) then return end

		--Prevent spell tooltips
		--if (false) then return end

		--Find current target
		local type, index, name = obj:FindNearestObject()
		if (type == nil) then
			local ids = utils:BreakGUID(UnitGUID("target"))
			type = ids.type
			index = ids.index
			name = UnitName("target")
		end
		obj:SetTargetData(type, index, name)

		--Update visibility
		if (target.type ~= nil) then
			obj:Show()
		else
			obj:Hide()
		end
	end

	function obj:OnCursorChanged(...)
		--log:Info("OnCursorChanged")
		if (validObjectTargetTimer ~= nil) then
			validObjectTargetTimer:Cancel()
		end
		validObjectTargetTimer = C_Timer.NewTimer(0.1, function() validObjectTargetTimer = nil end)
	end

	function obj:OnSearchChanged()
		if (searchInitialized) then
			obj:ResetUI()
		end
		searchInitialized = true
	end

	function obj:OnSortButton()
		--Cycle sort modes
		sortModeIndex = sortModeIndex + 1
		if (sortModeIndex > #sortModes) then
			sortModeIndex = sortModeIndex - #sortModes
		end
		sortButton:SetText(buttonColor .. sortModes[sortModeIndex])

		--Scroll to top
		scrollFrame:SetVerticalScroll(0)
		obj:ResetUI()
	end

	function obj:OnDataButton()
		--Cycle sort modes
		dataModeIndex = dataModeIndex + 1
		if (dataModeIndex > #dataModes) then
			dataModeIndex = dataModeIndex - #dataModes
		end
		dataButton:SetText(buttonColor .. dataModes[dataModeIndex])

		--Scroll to top
		scrollFrame:SetVerticalScroll(0)
		--obj:ResetUI()
		obj:RetryCurrent()
	end

	function obj:OnOptionsButton()
		log:Info("Todo: Options button")
		--obj:UpdateUI()
	end

	function obj:OnCloseButton()
		obj:SetTargetData(nil, nil, nil)
		obj:Hide()
	end

	function obj:OnRowFrameEnter(rowFrame)
		rowFrame.row:SetBackdrop({
			bgFile = "Interface/Tooltips/UI-Tooltip-Background",
			insets = { left = 20, right = -10, top = 0, bottom = 0 }
		})
		rowFrame.row:SetBackdropColor(1, 1, 0, .6)
		rowFrameHovered = rowFrame
	end

	function obj:OnRowFrameLeave(rowFrame)
		rowFrame.row:SetBackdrop()
		rowFrameHovered = nil
	end


	--General UI
	local buttonCount = 0

	function obj:CreateButton(parent, text)
		--Templates differ per client, and 3.3.5a needs a real frame name for
		--the templated child regions
		buttonCount = buttonCount + 1
		local button = compat:CreateButton("LootZButton" .. buttonCount, parent)
		button:SetText(buttonColor .. text)

		return button
	end

	function obj:CreateCell(name, color)
		--Validate params (unnamed on purpose, these are created per row)
		local frame = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate")
		frame:SetFrameStrata("BACKGROUND")
		frame:SetBackdrop({
			bgFile = "Interface/Tooltips/UI-Tooltip-Background", 
			edgeFile = "Interface/Tooltips/UI-Tooltip-Border", 
			tile = true, tileSize = 16, edgeSize = 16, 
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		})

		--local frameColor = color or {0, 0, 0, 1}
		local r = color[1] or 0
		local g = color[2] or 0
		local b = color[3] or 0
		local a = color[4] or 1
		frame:SetBackdropColor(r, g, b, a)

		return frame
	end

	function obj:CreateLabeledColumn(row, ratios)
		local column = obj:CreateCell("Column", {0, 1, 0, 0})
		column:SetBackdrop()
		obj:AddHorizontalChild(column, row, ratios)

		local label = column:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("CENTER")
		label:SetText("")

		return column, label
	end

	function obj:AddVerticalChildFixed(frame, parent, height)
		frame:SetParent(parent)
		frame:SetHeight(height)
		frame:SetWidth(parent:GetWidth())

		local children = { parent:GetChildren() }

		local y = 0
		for i, child in ipairs(children) do
			child:ClearAllPoints()
			child:SetPoint("TOPLEFT", 0, -y)
			y = y + child:GetHeight()
		end
	end

	function obj:AddHorizontalChild(frame, parent, ratios)
		frame:SetParent(parent)
		local children = { parent:GetChildren() }

		ratios = ratios or {}
		local totalRatio = obj:GetTotalRatio(ratios, children)
		
		local x = 0
		for i, child in ipairs(children) do
			local ratio = ratios[i] or 1.0
			local w = parent:GetWidth() * (ratio / totalRatio)
			child:ClearAllPoints()
			child:SetWidth(w)
			child:SetHeight(parent:GetHeight())
			child:SetPoint("TOPLEFT", x, 0)
			x = x + w
		end
	end

	function obj:GetTotalRatio(ratios, children)
		local total = 0.0
		for i = 1, #children do
			local ratio = ratios[i] or 1.0
			total = total + ratio
		end

		return total
	end



	--UI Elements
	function obj:Init()
		obj:SetupMainPanel()
		obj:SetupScrollPanel(headerHeight)

		headerLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		headerLabel:SetPoint("TOPLEFT", 14, -6)
		headerLabel:SetWidth(mainFrame:GetWidth() * 0.5)
		headerLabel:SetHeight(headerHeight)
		headerLabel:SetText("")
		headerLabel:SetJustifyH("LEFT")

		searchField = CreateFrame("EditBox", "LootZSearchBox", mainFrame, "InputBoxTemplate");
		searchField:SetPoint("TOPRIGHT", -194, -10);
		searchField:SetWidth(160)
		searchField:SetHeight(20)
		searchField:SetAutoFocus(false)
		searchField:SetScript("OnTextChanged", function()
			obj:OnSearchChanged()
		end)

		dataButton = obj:CreateButton(mainFrame, dataModes[dataModeIndex])
		dataButton:SetPoint("TOPRIGHT", -130, -10)
		dataButton:SetWidth(60)
		dataButton:SetHeight(20)
		dataButton:SetScript("OnClick", function()
			obj:OnDataButton()
		end)

		sortButton = obj:CreateButton(mainFrame, sortModes[sortModeIndex])
		sortButton:SetPoint("TOPRIGHT", -70, -10)
		sortButton:SetWidth(60)
		sortButton:SetHeight(20)
		sortButton:SetScript("OnClick", function()
			obj:OnSortButton()
		end)

		optionsButton = obj:CreateButton(mainFrame, "#")
		optionsButton:SetPoint("TOPRIGHT", -40, -10)
		optionsButton:SetWidth(30)
		optionsButton:SetHeight(20)
		optionsButton:SetScript("OnClick", function()
			obj:OnOptionsButton()
		end)

		closeButton = obj:CreateButton(mainFrame, "x")
		closeButton:SetPoint("TOPRIGHT", -10, -10)
		closeButton:SetWidth(30)
		closeButton:SetHeight(20)
		closeButton:SetScript("OnClick", function()
			obj:OnCloseButton()
		end)

		obj:Hide()
		obj:UpdateUI()
		C_Timer.NewTicker(tickDelay, function() obj:TickUI() end)
	end

	function obj:Hide()
		mainFrame:Hide()
		visible = false

		--Clear frame for generic ESC closing
		for i, name in ipairs(UISpecialFrames) do
			if name == mainFrame:GetName() then
				table.remove(UISpecialFrames, i)
				break
			end
		end
	end

	function obj:Show()
		mainFrame:Show()
		visible = true

		--Store frame for generic ESC closing
		if not tContains(UISpecialFrames, mainFrame:GetName()) then
			tinsert(UISpecialFrames, mainFrame:GetName())
		end
	end

	function obj:SetupMainPanel()
		--Create background frame
		mainFrame = CreateFrame("Frame", "LootZMainPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate")
		mainFrame:SetFrameStrata("HIGH")
		mainFrame:SetPoint(mainPanelPivot, mainPanelEdgeOffset[1], mainPanelEdgeOffset[2])
		mainFrame:SetWidth(mainPanelSize[1])
		mainFrame:SetHeight(mainPanelSize[2])
		mainFrame:SetBackdrop({
			bgFile = "Interface/Tooltips/UI-Tooltip-Background", 
			edgeFile = "Interface/Tooltips/UI-Tooltip-Border", 
			tile = true, tileSize = 16, edgeSize = 16, 
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		})
		mainFrame:SetBackdropColor(0, 0, 0, 1)
		mainFrame:EnableMouse(true)

		--mainFrame:Hide()
	end

	function obj:SetupScrollPanel(parentTopOffset)
		scrollFrame = CreateFrame("ScrollFrame", "LootZScrollPanel", mainFrame, "UIPanelScrollFrameTemplate")
		local areaPadding = 6
		--Setup scroll bar buttons
		local scrollBarName = scrollFrame:GetName()
		local scrollBarOffset = 22
		local scrollButtonUp = _G[scrollBarName .. "ScrollBarScrollUpButton"]
		local scrollButtonDown = _G[scrollBarName .. "ScrollBarScrollDownButton"]
		local scrollBar = _G[scrollBarName .. "ScrollBar"]

		if (scrollButtonUp ~= nil and scrollButtonDown ~= nil and scrollBar ~= nil) then
			scrollButtonUp:ClearAllPoints()
			scrollButtonUp:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", -4, -4 + areaPadding)

			scrollButtonDown:ClearAllPoints()
			scrollButtonDown:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -4, 4 - areaPadding)

			scrollBar:ClearAllPoints()
			scrollBar:SetPoint("TOP", scrollButtonUp, "BOTTOM", 0, 2)
			scrollBar:SetPoint("BOTTOM", scrollButtonDown, "TOP", 0, -2)
			scrollBarOffset = scrollBar:GetWidth() + 6
		end

		local scrollChild = CreateFrame("Frame")
		scrollFrame:SetScrollChild(scrollChild)
		scrollFrame:SetAllPoints(mainFrame)
		compat:SetSize(scrollChild, scrollFrame:GetWidth() - scrollBarOffset - 10, scrollFrame:GetHeight() - parentTopOffset - areaPadding - 6)
		scrollFrame:SetPoint("BOTTOM", 0, areaPadding)
		scrollFrame:SetPoint("TOPLEFT", 0, -areaPadding - parentTopOffset)

		scrollViewport = CreateFrame("Frame", nil, scrollChild)
		scrollViewport:SetAllPoints(scrollChild)
	end

	function obj:ResetUI()
		pageIndex = 1
		scrollFrame:SetVerticalScroll(0)
		obj:UpdateUI()
	end

	function obj:UpdateUI()
		obj:ClearUI()

		if (target.type == nil) then return end
		headerLabel:SetText(target.name)

		if (hierarchy == nil) then return end
		hierarchyRendered = true
		local filteredHierarchy = obj:FilterHierarchy()

		obj.layerQueue = {}
		obj:SetupUI(filteredHierarchy, false)
		--print("begin queue")
		C_Timer.After(loadingDelay, obj.ProcessSetupQueue)
	end

	function obj:ClearUI()
		for i = 1, rowIndex do
			local frames = rowFrames[i]
			if (frames ~= nil) then
				frames.row:Hide()
			end
		end
		rowIndex = 0
	end

	function obj:SetupUI_old(layer)
		obj:Sort(layer)

		--Setup items
		--obj:AddRefRow(nil, layer)
		for i = 1, #layer.itemSets do
			local set = layer.itemSets[i]
			obj:AddItemRow(layer, set.row, set.item)
		end

		for i = 1, #layer.childLayers do
			local childLayer = layer.childLayers[i]
			obj:AddRefRow(layer, childLayer)
			obj:SetupUI(childLayer)
		end
	end

	function obj:SetupUI(layer, fromQueue)
		if (layer.name == "Main" or fromQueue) then
			--print("process layer: ", layer.name)
			obj:Sort(layer)

			--Setup items
			--obj:AddRefRow(nil, layer)
			for i = 1, #layer.itemSets do
				local set = layer.itemSets[i]
				obj:AddItemRow(layer, set.row, set.item)
			end
		end

		if (fromQueue) then return end

		for i = 1, #layer.childLayers do
			local childLayer = layer.childLayers[i]

			--print("queued layer: ", childLayer.name)
			table.insert(obj.layerQueue, layer)
			table.insert(obj.layerQueue, childLayer)
			--obj:AddRefRow(layer, childLayer)
			obj:SetupUI(childLayer, fromQueue)
		end
	end

	function obj:ProcessSetupQueue()
		if (obj.layerQueue == nil or #obj.layerQueue <= 0) then return end

		local layer = table.remove(obj.layerQueue, 1)
		local childLayer = table.remove(obj.layerQueue, 1)

		obj:AddRefRow(layer, childLayer)
		obj:SetupUI(childLayer, true)

        C_Timer.After(loadingDelay, obj.ProcessSetupQueue)
	end

	function obj:TickUI()
		if (not visible) then return end
		local newHover = obj:FindHoveredRowFrame()

		--Show custom tooltip while holding ALT
		if (isShowingTooltip) then
			GameTooltip:Hide()
			isShowingTooltip = false
		end
		if (IsAltKeyDown() and newHover ~= nil) then
			obj:ShowCustomItemTooltip(newHover)
		end

		--Show custom cursor while holding CTRL
		if (IsControlKeyDown() and newHover ~= nil) then
			if (not isShowingCursor) then
				_G.LEDII_LZ_CURSOR_IGNORE = true
				compat:SetCursorTexture("INSPECT_CURSOR")
				isShowingCursor = true
				--log:Info("Show inspect cursor")
			end
		elseif (isShowingCursor) then
			_G.LEDII_LZ_CURSOR_IGNORE = true
			compat:ResetCursorTexture()
			isShowingCursor = false
			--log:Info("Reset inspect cursor")
		end

		--Run hover events if there is a change
		if (newHover == rowFrameHovered) then return end
		if (rowFrameHovered ~= nil) then
			obj:OnRowFrameLeave(rowFrameHovered)
		end

		if (newHover ~= nil) then
			obj:OnRowFrameEnter(newHover)
		end
	end

	function obj:FilterHierarchy()
		local searchText = string.lower(searchField:GetText() or "")

		filterCount = 0
		local uLayer = hierarchy
		local fLayer = {}
		obj:FilterHierarchyLayer(uLayer, fLayer, searchText)

		if (filterCount > filterMaxCount) then
			log:Info("Filter count is: " .. filterCount)
			local emptyLayer = {}
			emptyLayer.name = "Empty"
			emptyLayer.ref = 0
			emptyLayer.itemSets = {}
			emptyLayer.groupItemCount = {}
			emptyLayer.childLayers = {}
			return emptyLayer
		end

		return fLayer
	end

	function obj:FilterHierarchyLayer(unfilteredLayer, filteredLayer, searchText)
		filteredLayer.name = unfilteredLayer.name
		filteredLayer.ref = unfilteredLayer.ref

		--Handle items
		filteredLayer.itemSets = {}
		filteredLayer.groupItemCount = {}
		for i = 1, #unfilteredLayer.itemSets do
			--Whether to include item
			local uSet = unfilteredLayer.itemSets[i]
			if (obj:FilterHierarchyItem(unfilteredLayer, uSet, searchText)) then
				table.insert(filteredLayer.itemSets, uSet)
				filterCount = filterCount + 1
			end

			--Increment group id count
			local groupId = uSet.row.groupId
			if (filteredLayer.groupItemCount[groupId] == nil) then
				filteredLayer.groupItemCount[groupId] = 0
			end
			filteredLayer.groupItemCount[groupId] = filteredLayer.groupItemCount[groupId] + 1
		end
		--log:Info("Filter hierarchy layer <" .. filteredLayer.name .. "> with <" .. #unfilteredLayer.itemSets .. "> items...")

		--Handle layers
		filteredLayer.childLayers = {}
		for i = 1, #unfilteredLayer.childLayers do
			local uLayer = unfilteredLayer.childLayers[i]
			local fLayer = {}
			obj:FilterHierarchyLayer(uLayer, fLayer, searchText)

			if (#fLayer.itemSets > 0) then
				table.insert(filteredLayer.childLayers, fLayer)
			end
		end
	end

	function obj:FilterHierarchyItem(layer, set, searchText)
		if (string.len(searchText) == 0) then
			return true
		end
		if (set.item == nil) then
			return false
		end

		if (string.find(searchText, "*rate > ")) then
			--Greather than rate
			local after = utils:StringAfter(searchText, "*rate > ")
			local number = tonumber(after) or math.huge
			local relChance, absChance = obj:GetItemChances(layer, set.row)
			return (relChance > number)
		elseif (string.find(searchText, "*rate >= ")) then
			--Greather than or equals rate
			local after = utils:StringAfter(searchText, "*rate > ")
			local number = tonumber(after) or math.huge
			local relChance, absChance = obj:GetItemChances(layer, set.row)
			return (relChance >= number)
		elseif (string.find(searchText, "*rate < ")) then
			--Less than rate
			local after = utils:StringAfter(searchText, "*rate < ")
			local number = tonumber(after) or -math.huge
			local relChance, absChance = obj:GetItemChances(layer, set.row)
			return (relChance < number)
		elseif (string.find(searchText, "*rate <= ")) then
			--Less than or equals rate
			local after = utils:StringAfter(searchText, "*rate < ")
			local number = tonumber(after) or -math.huge
			local relChance, absChance = obj:GetItemChances(layer, set.row)
			return (relChance <= number)
		elseif (string.find(searchText, "*group ")) then
			--Matching group
			local after = utils:StringAfter(searchText, "*group ")
			local number = tonumber(after) or -1
			return (set.row.groupId == number)
		elseif (string.find(searchText, "*")) then
			return true
		else
			--Matching parts of name
			local filterName = string.lower(set.item.name)
			return string.find(filterName, searchText)
		end
	end

	function obj:FindHoveredRowFrame()
		if (not obj:IsMouseOverPanel(mainFrame)) then return nil end

		for i = 1, #rowFrames do
			local rowFrame = rowFrames[i]
			if (MouseIsOver(rowFrame.row) and rowFrame.row:IsVisible()) then
				return rowFrame
			end
		end

		return nil
	end

	function obj:AddItemRow(layer, row, item)
		--Attempt retry on invalid item
		if (item == nil) then
			obj:InvalidItemRow(layer, row)
			return
		end

		--Prepare next frame row
		rowIndex = rowIndex + 1
		local frames = rowFrames[rowIndex]
		if (frames == nil) then
			frames = obj:CreateCellRow()
			rowFrames[rowIndex] = frames
		end

		local txtColor = const:Color("LOOT_ITEM")
		if (row.questRequired) then
			txtColor = const:Color("QUEST_ITEM")
		end

		local displayRate = row.chance -- or 100.0 / #layer.items
		local rateStr, countStr = utils:GetRateStrings(displayRate, 3)
		local amountStr = utils:FormatRange(row.minCount, row.maxCount)
		local dataMode = dataModes[dataModeIndex]

		--Set data of frame row
		frames.row:Show()
		frames.icon:SetTexture(item.texture)
		frames.icon:Show()

		frames.typeLabel:SetText(txtColor .. obj:GetDisplayType(item))

		if (dataMode == "Data") then
			frames.linkLabel:SetText(txtColor .. item.link .. " x" .. amountStr)
			frames.rateLabel1:SetText(txtColor .. rateStr)
			frames.rateLabel2:SetText(txtColor .. countStr)
			frames.groupLabel:SetText(txtColor .. row.groupId)

		elseif (dataMode == "Stats")  then
			frames.linkLabel:SetText(txtColor .. item.link .. " x" .. amountStr)
			frames.rateLabel1:SetText(txtColor .. rateStr)
			frames.rateLabel2:SetText("")
			frames.groupLabel:SetText(txtColor .. row.groupId)

		elseif (dataMode == "Find") then
			frames.linkLabel:SetText(txtColor .. item.link)
			frames.rateLabel1:SetText("")
			frames.rateLabel2:SetText("")
			frames.groupLabel:SetText(txtColor .. row.groupId)
			
		end

		frames.layerPayload = layer
		frames.rowPayload = row
		frames.itemPayload = item
	end

	function obj:AddRefRow(layer, childLayer)
		--Prepare next frame row
		rowIndex = rowIndex + 1
		local frames = rowFrames[rowIndex]
		if (frames == nil) then
			frames = obj:CreateCellRow()
			rowFrames[rowIndex] = frames
		end

		--local path = obj:FindLayerPath(childLayer)
		local link = childLayer.name --obj:GetLayerPathString(path)
		local type = ""
		local displayRate = childLayer.ref.chance
		local rateStr, countStr = utils:GetRateStrings(displayRate, 3)
		local group = childLayer.ref.groupId
		local dataMode = dataModes[dataModeIndex]

		--Set data of frame row
		frames.row:Show()
		frames.icon:SetTexture(nil)
		frames.icon:Hide()
		frames.linkLabel:SetText(link)
		frames.typeLabel:SetText(type)
		frames.rateLabel1:SetText(rateStr)
		if (dataMode == "Data") then
			frames.rateLabel2:SetText(countStr)
		else
			frames.rateLabel2:SetText("")
		end
		frames.groupLabel:SetText(group)

		frames.layerPayload = layer
		frames.rowPayload = nil
		frames.itemPayload = nil
	end

	function obj:CreateCellRow()
		local frames = {}

		frames.row = obj:CreateCell("Row", {1, 0, 0, 0})
		obj:AddVerticalChildFixed(frames.row, scrollViewport, rowHeight)
		frames.row:SetBackdrop()

		local columnRatios = {1.5, 8, 4, 2, 2, 1}
		frames.iconColumn, frames.iconLabel = obj:CreateLabeledColumn(frames.row, columnRatios)
		frames.linkColumn, frames.linkLabel = obj:CreateLabeledColumn(frames.row, columnRatios)
		frames.linkLabel:SetPoint("LEFT")
		frames.typeColumn, frames.typeLabel = obj:CreateLabeledColumn(frames.row, columnRatios)
		frames.typeLabel:SetPoint("RIGHT")
		frames.rateColumn1, frames.rateLabel1 = obj:CreateLabeledColumn(frames.row, columnRatios)
		frames.rateLabel1:SetPoint("RIGHT")
		frames.rateColumn2, frames.rateLabel2 = obj:CreateLabeledColumn(frames.row, columnRatios)
		frames.rateLabel2:SetPoint("RIGHT")
		frames.groupColumn, frames.groupLabel = obj:CreateLabeledColumn(frames.row, columnRatios)
		frames.groupColumn:SetPoint("RIGHT")

		frames.icon = frames.iconColumn:CreateTexture(nil, "OVERLAY")
		frames.icon:SetWidth(rowHeight)
		frames.icon:SetHeight(rowHeight)
		frames.icon:SetPoint("CENTER")

		return frames
	end

	function obj:GetDisplayType(item)
		--Debug test for specific case, save for later in case of changes
		--if (string.find(item.link, "Ruined Pelt")) then
			--log:ValueString(item, "Item")
		--end

		if (item.slot == "" or item.slot == "INVTYPE_NON_EQUIP_IGNORE") then
			local basicTypes = { "Recipe", "Gem", "Trade Goods" }
			if (utils:TableContains(basicTypes, item.type)) then
				return item.type
			else
				return item.subtype
			end

			return item.type .. ", " .. item.subtype
		end

		local typeStr = string.sub(item.slot, 9)
		local niceStr = string.lower(typeStr)
		niceStr = niceStr:gsub("^%l", string.upper)

		if (typeStr == "2HWEAPON") then
			niceStr = "Two-Hand"
		elseif (typeStr == "WEAPONMAINHAND") then
			niceStr = "Main-Hand"
		elseif (typeStr == "WEAPONOFFHAND" or typeStr == "HOLDABLE" or typeStr == "SHIELD") then
			niceStr = "Off-Hand"
		elseif (typeStr == "WEAPON") then
			niceStr = "One-Hand"
		elseif (typeStr == "RANGEDRIGHT") then
			niceStr = "Ranged"
		elseif (typeStr == "CLOAK") then
			niceStr = "Back"
		end

		local directTypes = { "Neck", "Finger", "Back" }
		if (utils:TableContains(directTypes, niceStr)) then
			return niceStr
		end

		local directSubtypes = { "Miscellaneous", "Shields" }
		if (utils:TableContains(directSubtypes, item.subtype)) then
			return niceStr
		end

		if (niceStr == "Robe") then
			niceStr = "Chest"
		end

		if (item.type == "Armor") then
			niceStr = niceStr .. ", " .. item.subtype
		end

		return niceStr
	end

	function obj:GetItemChances(layer, row)
		local path = obj:FindLayerPath(layer)
		local pathChance = obj:GetLayerPathChance(path)

		local itemCount, refCount = obj:GetGroupItemCount(layer, row)
		local groupCount = itemCount + refCount

		local itemChance = row.chance
		if (itemChance == 0) then
			itemChance = 100
		end

		local relChance = (pathChance * 0.01) * (itemChance * 0.01) * 100.0
		local absChance = relChance / groupCount

		return relChance, absChance
	end

	function obj:AppendChatLinkFromRowFrame(rowFrame)
		--Group header rows carry no item
		if (rowFrame.itemPayload == nil) then return end

		--log:Info("Append chat link...")
		local editBox = DEFAULT_CHAT_FRAME.editBox
		editBox:SetText(editBox:GetText() .. rowFrame.itemPayload.link)
	end

	function obj:DressUpFromRowFrame(rowFrame)
		--Group header rows carry no item
		if (rowFrame.itemPayload == nil) then return end

		--log:Info("Equipping item: " .. rowFrame.itemPayload.link)
		DressUpItemLink(rowFrame.itemPayload.link)
	end

	function obj:ShowCustomItemTooltip(rowFrame)
		if (rowFrame.itemPayload == nil) then return end

		GameTooltip:SetOwner(rowFrame.row, "ANCHOR_LEFT", 0, -rowHeight)
		GameTooltip:SetHyperlink(rowFrame.itemPayload.link)

		local dataMode = dataModes[dataModeIndex]
		local txtColor = const:Color("LOOT_ITEM")
		local txtPrefix = ""
		if (rowFrame.rowPayload.questRequired) then
			txtColor = const:Color("QUEST_ITEM")
			GameTooltip:AddLine(txtColor .. "Item only available on quest")
		end

		--GameTooltip:AddLine(txtColor .. "Item Level: " .. frames.item.level)
		--GameTooltip:AddLine(txtColor .. frames.item.slot)
		--GameTooltip:AddLine(txtColor .. frames.item.type)
		--GameTooltip:AddLine(txtColor .. frames.item.subtype)

		local path = obj:FindLayerPath(rowFrame.layerPayload)
		local pathString = rowFrame.layerPayload.name --obj:GetLayerPathString(path)
		local pathChance = obj:GetLayerPathChance(path)

		local itemCount, refCount = obj:GetGroupItemCount(rowFrame.layerPayload, rowFrame.rowPayload)
		local groupCount = itemCount + refCount
		local relChance, absChance = obj:GetItemChances(rowFrame.layerPayload, rowFrame.rowPayload)

		if (dataMode == "Data") then
			local pathStr = string.format("Loot Path: %s", pathString)
			GameTooltip:AddLine(txtColor .. pathStr)
		end

		--local pathStr2 = string.format("Loot Group: %s", frames.item.rowData.groupString)
		--GameTooltip:AddLine(txtColor .. pathStr2)

		--local pathStr3 = string.format("Sort Group: %s", obj:GetPathSortGroup(frames.item.rowData))
		--GameTooltip:AddLine(txtColor .. pathStr3)

		if (dataMode == "Data") then
			local rRateStr, rCountStr = utils:GetRateStrings(relChance, 6)
			local relRateStr = string.format("Relative Chance: %s (%s)", rRateStr, rCountStr)
			GameTooltip:AddLine(txtColor .. relRateStr)

			local aRateStr, aCountStr = utils:GetRateStrings(absChance, 6)
			local absRateStr = string.format("Absolute Chance: %s (%s)", aRateStr, aCountStr)
			GameTooltip:AddLine(txtColor .. absRateStr)
		elseif (dataMode == "Stats") then
			local rRateStr, rCountStr = utils:GetRateStrings(rowFrame.rowPayload.chance, 6)
			local relRateStr = string.format("Found Rate: %s (%s)", rRateStr, rCountStr)
			GameTooltip:AddLine(txtColor .. relRateStr)
		end

		if (groupCount > 1 and dataMode == "Data") then
			local groupId = rowFrame.rowPayload.groupId
			local groupDescStr = string.format(
				"Shares an equal chance of 1 / %s "
				.. "\nwith other entries in <Group %s>"
				.. "\n%s Items, %s References",
				groupCount, groupId, itemCount, refCount
			)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(txtColor .. groupDescStr)
		end

		GameTooltip:Show()
		isShowingTooltip = true
	end

	function obj:FindTooltipProfession()
		local valid = { "Skinnable", "Minable", "Gatherable", "Salvageable" }

		for i = 1, GameTooltip:NumLines() do
			local lineFrame = _G["GameTooltipTextLeft" .. i]
			local line = lineFrame and lineFrame:GetText()
			if (line == nil) then break end

			local lineR, lineG, lineB = lineFrame:GetTextColor()
			local hasValidLevel = (lineR < 1.0)

			--log:Info("Line: " .. line .. " (Color: " .. lineR .. ", " .. lineG .. ", " .. lineB .. ")")

			if (utils:TableContains(valid, line) and hasValidLevel) then
				return line
			end
		end

		return nil
	end

	function obj:IsMouseOverPanel(panel)
		--Get min and max of panel
		local _, _, _, _, py = panel:GetPoint()
		local h = UIParent:GetHeight()
		local topY = h + py - rowHeight
		local botY = topY - panel:GetHeight() + rowHeight + 6

		--Get scaled cursor postion
		local uiScale = UIParent:GetEffectiveScale()
		local _, mouseY = GetCursorPosition()
		mouseY = mouseY / uiScale

		--local debugStr = string.format("Top: %.0f / Bot: %.0f / Mouse %.0f", topY, botY, mouseY)
		--log:Info(debugStr)

		return (mouseY < topY and mouseY > botY)
	end

	function obj:RetryCurrent()
		obj:SetTargetData("RetryClear", nil, nil)
		obj:SetTargetData("RetryUpdate", retryTarget.index, retryTarget.name)
	end

	function obj:InvalidItemRow(layer, row)
		if (retryConsumed) then return end
		retryConsumed = true

		--log:Info("Invalid item found. Reload is required...")
		C_Timer.After(retryDelay, function() obj:RetryCurrent() end)
	end



	--Sorting
	function obj:Sort(layer)
		--Apply current sorting method
		local sortMode = sortModes[sortModeIndex]
		--log:Info("Sorting mode: " .. sortMode)

		if (sortMode == "Rate") then
			table.sort(layer.itemSets, function(a, b) return obj:GetSortRateFromSet(a) > obj:GetSortRateFromSet(b) end)
			table.sort(layer.childLayers, function(a, b) return obj:GetSortRateFromLayer(a) > obj:GetSortRateFromLayer(b) end)
		elseif (sortMode == "Name") then
			table.sort(layer.itemSets, function(a, b) return obj:GetSortNameFromSet(a) < obj:GetSortNameFromSet(b) end)
			table.sort(layer.childLayers, function(a, b) return obj:GetSortNameFromLayer(a) < obj:GetSortNameFromLayer(b) end)
		elseif (sortMode == "Type") then
			table.sort(layer.itemSets, function(a, b) return obj:GetSortTypeFromSet(a) < obj:GetSortTypeFromSet(b) end)
			--table.sort(layer.childLayers, function(a, b) return obj:GetSortTypeFromLayer(a) < obj:GetSortTypeFromLayer(b) end
			table.sort(layer.childLayers, function(a, b) return obj:GetSortNameFromLayer(a) < obj:GetSortNameFromLayer(b) end)
		elseif (sortMode == "Color") then
			table.sort(layer.itemSets, function(a, b) return obj:GetSortColorFromSet(a) > obj:GetSortColorFromSet(b) end)
			--table.sort(layer.childLayers, function(a, b) return obj:GetSortColorFromLayer(a) > obj:GetSortColorFromLayer(b) end)
			table.sort(layer.childLayers, function(a, b) return obj:GetSortNameFromLayer(a) < obj:GetSortNameFromLayer(b) end)
		elseif (sortMode == "Group") then
			table.sort(layer.itemSets, function(a, b) return obj:GetSortGroupFromSet(a) < obj:GetSortGroupFromSet(b) end)
			table.sort(layer.childLayers, function(a, b) return obj:GetSortGroupFromLayer(a) < obj:GetSortGroupFromLayer(b) end)
		end
	end

	function obj:GetSortRateFromSet(set)
		return set.row.chance
	end

	function obj:GetSortRateFromLayer(layer)
		return layer.ref.chance
	end

	function obj:GetSortNameFromSet(set)
		if (set.item == nil) then return "Invalid" end
		return set.item.name
	end

	function obj:GetSortNameFromLayer(layer)
		return layer.name
	end

	function obj:GetSortTypeFromSet(set)
		if (set.item == nil) then return "None" end

		local item = set.item
		local baseType = obj:GetDisplayType(item)

		local basicTypes = { "Recipe", "Gem", "Trade Goods" }
		if (utils:TableContains(basicTypes, item.type)) then
			return baseType .. ", " .. item.subtype
		end

		local directSubtypes = { "Miscellaneous", "Shields" }
		if (utils:TableContains(directSubtypes, item.subtype)) then
			return baseType .. ", " .. item.subtype
		end

		return baseType
	end

	function obj:GetSortTypeFromLayer(layer)
		return 0
	end

	function obj:GetSortColorFromSet(set)
		if (set.item == nil) then return 0 end
		return set.item.rarity
	end

	function obj:GetSortColorFromLayer(layer)
		return 0
	end

	function obj:GetSortGroupFromSet(set)
		return set.row.groupId
	end

	function obj:GetSortGroupFromLayer(layer)
		return layer.ref.groupId
	end

	return obj
end

local class = class()
class:Init()

_G.LEDII_LZ_RENDER = class
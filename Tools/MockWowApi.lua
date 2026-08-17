--[[
	A small mock of the 3.3.5a (WotLK / Ascension) client API.

	This is NOT loaded by the game, it exists so the addon can be executed
	outside of WoW with plain Lua 5.1 (the same Lua version the client uses).

	It deliberately leaves out everything 3.3.5a does not have, so anything that
	reaches for a modern API - C_Timer, C_AddOns, C_Map, the Item mixin,
	UnitPosition, GetItemInfoFromHyperlink, GLOBAL_MOUSE_UP - fails here exactly
	like it would fail in game.
]]

local Mock = {}

Mock.time = 0
Mock.frames = {}
Mock.mouse = {}
Mock.keys = {}
Mock.events = {}
Mock.printed = {}
Mock.items = {}
Mock.itemCached = {}
Mock.lootSlots = {}
Mock.units = {}
Mock.currentUnits = {}
Mock.errors = {}
Mock.cursorX = 500
Mock.cursorY = 500
Mock.mouseOverAll = false

--Widget methods that simply do not exist on 3.3.5a
Mock.missingMethods = {
	SetPropagateKeyboardInput = true,
}

local function noop() end

--Widgets -------------------------------------------------------------------

local widgetMethods = {}

function widgetMethods:GetName() return self.__name end
function widgetMethods:GetObjectType() return self.__type end
function widgetMethods:IsObjectType(t) return self.__type == t end
function widgetMethods:GetParent() return self.__parent end
function widgetMethods:SetParent(p) self.__parent = p end
function widgetMethods:GetChildren() return unpack(self.__children) end
function widgetMethods:GetRegions() return unpack(self.__regions) end

function widgetMethods:SetWidth(w) self.__width = w end
function widgetMethods:SetHeight(h) self.__height = h end
function widgetMethods:GetWidth() return self.__width or 0 end
function widgetMethods:GetHeight() return self.__height or 0 end
function widgetMethods:SetSize(w, h) self.__width = w; self.__height = h end
function widgetMethods:GetEffectiveScale() return 1 end
function widgetMethods:GetScale() return 1 end

function widgetMethods:SetPoint(point, a, b, c, d)
	--Mimic both SetPoint(point, x, y) and SetPoint(point, rel, relPoint, x, y)
	if (type(a) == "number") then
		self.__point = { point, nil, nil, a, b }
	else
		self.__point = { point, a, b, c, d }
	end
end
function widgetMethods:GetPoint()
	local p = self.__point or { "TOPLEFT", nil, nil, 0, 0 }
	return p[1], p[2], p[3], p[4], p[5]
end
function widgetMethods:ClearAllPoints() self.__point = nil end
function widgetMethods:SetAllPoints() end

function widgetMethods:Show() self.__shown = true end
function widgetMethods:Hide() self.__shown = false end
function widgetMethods:IsShown() return self.__shown ~= false end
function widgetMethods:IsVisible() return self.__shown ~= false end

function widgetMethods:SetScript(name, fn) self.__scripts[name] = fn end
function widgetMethods:GetScript(name) return self.__scripts[name] end
function widgetMethods:HookScript(name, fn)
	local previous = self.__scripts[name]
	self.__scripts[name] = function(...)
		if (previous) then previous(...) end
		fn(...)
	end
end

function widgetMethods:SetText(text) self.__text = text end
function widgetMethods:GetText() return self.__text end
function widgetMethods:SetTextColor(r, g, b) self.__color = { r, g, b } end
function widgetMethods:GetTextColor()
	local c = self.__color or { 1, 1, 1 }
	return c[1], c[2], c[3]
end

function widgetMethods:RegisterEvent(event)
	if (Mock.knownEvents[event] == nil) then
		error("Attempt to register unknown event '" .. tostring(event) .. "'", 2)
	end
	self.__events[event] = true
end
function widgetMethods:UnregisterEvent(event) self.__events[event] = nil end
function widgetMethods:IsEventRegistered(event) return self.__events[event] == true end

function widgetMethods:CreateFontString(name, layer, template)
	local fs = Mock.CreateWidget("FontString", name, self)
	table.insert(self.__regions, fs)
	return fs
end

function widgetMethods:CreateTexture(name, layer)
	local tex = Mock.CreateWidget("Texture", name, self)
	table.insert(self.__regions, tex)
	return tex
end

function widgetMethods:SetChecked(value) self.__checked = value and true or false end
function widgetMethods:GetChecked() return self.__checked == true end
function widgetMethods:Click()
	local onClick = self.__scripts.OnClick
	if (onClick ~= nil) then onClick(self, "LeftButton") end
end

function widgetMethods:SetScrollChild(child) self.__scrollChild = child end
function widgetMethods:GetScrollChild() return self.__scrollChild end

--Tooltip surface
function widgetMethods:NumLines() return self.__numLines or 0 end
function widgetMethods:GetOwner() return self.__owner end
function widgetMethods:SetOwner(owner) self.__owner = owner end
function widgetMethods:GetUnit() return self.__unit end
function widgetMethods:GetItem() return self.__item, self.__itemLink end
function widgetMethods:GetSpell() return self.__spell end
function widgetMethods:AddLine(text) self.__numLines = (self.__numLines or 0) + 1 end
function widgetMethods:ClearLines() self.__numLines = 0 end
function widgetMethods:SetHyperlink(link)
	--Asking for a tooltip is what makes the client cache an item
	local id = tonumber(string.match(tostring(link), "item:(%d+)"))
	if (id ~= nil) then Mock.itemCached[id] = true end
	self.__lastHyperlink = link
end

function Mock.CreateWidget(frameType, name, parent, template)
	local widget = {
		__type = frameType,
		__name = name,
		__parent = parent,
		__children = {},
		__regions = {},
		__scripts = {},
		__events = {},
		__shown = true,
	}

	setmetatable(widget, {
		__index = function(t, key)
			--Internal bookkeeping fields are plain data, never a method
			if (type(key) == "string" and string.sub(key, 1, 2) == "__") then return nil end

			--Methods the 3.3.5a client does not have at all
			if (Mock.missingMethods[key]) then return nil end

			local method = widgetMethods[key]
			if (method ~= nil) then return method end

			--Unknown widget methods are harmless no-ops, the same way an
			--unused Blizzard method would simply do nothing here
			return noop
		end,
	})

	--An empty edit box returns an empty string in game, not nil
	if (frameType == "EditBox") then widget.__text = "" end

	if (name ~= nil) then _G[name] = widget end
	if (parent ~= nil and parent.__children ~= nil) then
		table.insert(parent.__children, widget)
	end

	table.insert(Mock.frames, widget)
	return widget
end

--Globals -------------------------------------------------------------------

Mock.knownEvents = {
	PLAYER_LOGIN = true,
	LOOT_OPENED = true,
	LOOT_CLOSED = true,
	UPDATE_MOUSEOVER_UNIT = true,
	PLAYER_TARGET_CHANGED = true,
	CURSOR_UPDATE = true,
	CHAT_MSG_LOOT = true,
	CHAT_MSG_MONEY = true,
	CHAT_MSG_COMBAT_XP_GAIN = true,
	COMBAT_LOG_EVENT_UNFILTERED = true,
	--Deliberately missing, like a client that does not report it:
	--CHAT_MSG_COMBAT_HOSTILE_DEATH
	--Deliberately missing on 3.3.5a: LOOT_READY, CURSOR_CHANGED,
	--GLOBAL_MOUSE_UP, GLOBAL_MOUSE_DOWN
}

function Mock.Install()
	_G.CreateFrame = function(frameType, name, parent, template)
		local frame = Mock.CreateWidget(frameType, name, parent, template)
		frame.__template = template

		--UIPanelScrollFrameTemplate builds named scrollbar children
		if (template ~= nil and string.find(template, "UIPanelScrollFrameTemplate", 1, true) and name ~= nil) then
			local bar = Mock.CreateWidget("Slider", name .. "ScrollBar", frame)
			bar:SetWidth(16)
			Mock.CreateWidget("Button", name .. "ScrollBarScrollUpButton", bar)
			Mock.CreateWidget("Button", name .. "ScrollBarScrollDownButton", bar)
		end

		return frame
	end

	_G.GetTime = function() return Mock.time end
	_G.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			table.insert(parts, tostring(select(i, ...)))
		end
		table.insert(Mock.printed, table.concat(parts, " "))
	end

	_G.UIParent = Mock.CreateWidget("Frame", "UIParent", nil)
	_G.UIParent:SetWidth(1920)
	_G.UIParent:SetHeight(1080)
	_G.UIParent.firstTimeLoaded = 1
	_G.UIParent.variablesLoaded = 1

	_G.WorldFrame = Mock.CreateWidget("Frame", "WorldFrame", nil)

	_G.GameTooltip = Mock.CreateWidget("GameTooltip", "GameTooltip", _G.UIParent)
	for i = 1, 10 do
		Mock.CreateWidget("FontString", "GameTooltipTextLeft" .. i, _G.GameTooltip)
	end
	_G.ItemRefTooltip = Mock.CreateWidget("GameTooltip", "ItemRefTooltip", _G.UIParent)
	Mock.CreateWidget("FontString", "ItemRefTooltipTextLeft1", _G.ItemRefTooltip)

	_G.NUM_CHAT_WINDOWS = 7
	for i = 1, _G.NUM_CHAT_WINDOWS do
		Mock.CreateWidget("Frame", "ChatFrame" .. i, _G.UIParent)
	end
	_G.DEFAULT_CHAT_FRAME = _G.ChatFrame1
	_G.DEFAULT_CHAT_FRAME.editBox = Mock.CreateWidget("EditBox", "ChatFrame1EditBox", _G.ChatFrame1)
	_G.DEFAULT_CHAT_FRAME.editBox:SetText("")
	_G.SELECTED_CHAT_FRAME = _G.ChatFrame1

	_G.UISpecialFrames = {}
	_G.SlashCmdList = {}

	--Money strings, as the 3.3.5a client defines them
	_G.GOLD_AMOUNT = "%d Gold"
	_G.SILVER_AMOUNT = "%d Silver"
	_G.COPPER_AMOUNT = "%d Copper"
	_G.COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
	_G.COMBATLOG_XPGAIN_FIRSTPERSON_GROUP = "%s dies, you gain %d experience. (%s exp %s group bonus)"
	_G.LOOT_ITEM_SELF = "You receive loot: %s."
	_G.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
	_G.LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
	_G.LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."

	--Lua helpers the client adds
	_G.strsplit = function(delimiter, text)
		local result = {}
		for match in (text .. delimiter):gmatch("(.-)" .. delimiter) do
			table.insert(result, match)
		end
		return unpack(result)
	end
	_G.format = string.format
	_G.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
	_G.tinsert = table.insert
	_G.tremove = table.remove
	_G.tContains = function(list, value)
		for i = 1, #list do
			if (list[i] == value) then return true end
		end
		return false
	end

	_G.GetBuildInfo = function() return "3.3.5", "12340", "Dec 20 2009", 30300 end
	_G.GetAddOnMetadata = function(name, field)
		if (field == "Version") then return "1.2.8-ascension" end
		return nil
	end

	--Units
	_G.UnitExists = function(unitId) return Mock.currentUnits[unitId] ~= nil end
	local function unitField(unitId, field)
		local unit = Mock.currentUnits[unitId]
		if (unit == nil) then return nil end
		return unit[field]
	end
	_G.UnitGUID = function(unitId) return unitField(unitId, "guid") end
	_G.UnitName = function(unitId) return unitField(unitId, "name") end
	_G.UnitLevel = function(unitId) return unitField(unitId, "level") end
	_G.UnitIsDead = function(unitId) return unitField(unitId, "dead") == true end
	_G.UnitCreatureType = function(unitId) return unitField(unitId, "type") end
	_G.UnitCreatureFamily = function(unitId) return unitField(unitId, "family") end
	_G.UnitIsPlayer = function(unitId) return unitField(unitId, "isPlayer") == true end
	_G.UnitCanAttack = function(unitId) return Mock.currentUnits[unitId] ~= nil end
	_G.UnitClass = function() return "Warrior", "WARRIOR" end
	_G.UnitRace = function() return "Orc", "Orc" end
	_G.UnitFactionGroup = function() return "Horde", "Horde" end

	--Items (10 return values, exactly like 3.3.5a)
	_G.GetItemInfo = function(key)
		local id = tonumber(key)
		if (id == nil) then id = tonumber(string.match(tostring(key), "item:(%d+)")) end
		if (id == nil) then return nil end

		local item = Mock.items[id]
		if (item == nil) then return nil end
		if (item.needsQuery and not Mock.itemCached[id]) then return nil end

		return item.name, item.link, item.rarity, item.level, item.minLevel,
			item.type, item.subtype, item.stackCount, item.slot, item.texture
	end

	--Loot
	_G.GetLootSlotInfo = function(slot)
		local data = Mock.lootSlots[slot]
		if (data == nil) then return nil end
		return data.texture, data.name, data.quantity, data.quality, false
	end
	_G.GetLootSlotLink = function(slot)
		local data = Mock.lootSlots[slot]
		if (data == nil) then return nil end
		return data.link
	end
	_G.GetNumLootItems = function() return #Mock.lootSlots end
	_G.GetCoinTextureString = function(amount) return tostring(amount) .. "c" end

	--Input
	_G.IsMouseButtonDown = function(button) return Mock.mouse[button] == true end
	_G.IsShiftKeyDown = function() return Mock.keys.SHIFT == true end
	_G.IsControlKeyDown = function() return Mock.keys.CTRL == true end
	_G.IsAltKeyDown = function() return Mock.keys.ALT == true end
	_G.GetCursorPosition = function() return Mock.cursorX, Mock.cursorY end
	_G.MouseIsOver = function(frame)
		if (Mock.mouseOverAll) then return true end
		return Mock.mouseOver == frame
	end
	_G.SetCursor = noop
	_G.ResetCursor = noop
	_G.DressUpItemLink = noop

	--Maps (3.3.5a style)
	_G.GetMapContinents = function() return "Kalimdor", "Eastern Kingdoms", "Outland", "Northrend" end
	_G.GetCurrentMapContinent = function() return Mock.continent or 1 end
	_G.SetMapToCurrentZone = noop
	_G.WorldMapFrame = Mock.CreateWidget("Frame", "WorldMapFrame", _G.UIParent)
	_G.WorldMapFrame:Hide()
end

--Driving -------------------------------------------------------------------

function Mock.RunFrames(count, step)
	count = count or 1
	step = step or (1 / 30)

	for i = 1, count do
		Mock.time = Mock.time + step
		for _, frame in ipairs(Mock.frames) do
			local onUpdate = frame.__scripts and frame.__scripts.OnUpdate
			if (onUpdate ~= nil and frame:IsShown()) then
				onUpdate(frame, step)
			end
		end
	end
end

function Mock.FireEvent(event, ...)
	for _, frame in ipairs(Mock.frames) do
		if (frame.__events and frame.__events[event]) then
			local onEvent = frame.__scripts.OnEvent
			if (onEvent ~= nil) then onEvent(frame, event, ...) end
		end
	end
end

--Search every widget for rendered text, used to prove rows were drawn
function Mock.FindText(text)
	for _, frame in ipairs(Mock.frames) do
		local value = rawget(frame, "__text")
		if (type(value) == "string" and string.find(value, text, 1, true)) then
			return frame
		end
	end
	return nil
end

function Mock.FireScript(frame, script, ...)
	local fn = frame.__scripts[script]
	if (fn == nil) then return end
	fn(frame, ...)
end

function Mock.ClickMouse(button, frames)
	Mock.mouse[button] = true
	Mock.RunFrames(frames or 1)
	Mock.mouse[button] = false
	Mock.RunFrames(frames or 1)
end

function Mock.SetUnit(unitId, unit)
	Mock.currentUnits[unitId] = unit
end

function Mock.AddItem(id, item)
	item.id = id
	item.link = item.link or ("|cffffffff|Hitem:" .. id .. ":0:0:0|h[" .. item.name .. "]|h|r")
	item.rarity = item.rarity or 1
	item.level = item.level or 10
	item.minLevel = item.minLevel or 1
	item.type = item.type or "Miscellaneous"
	item.subtype = item.subtype or "Junk"
	item.stackCount = item.stackCount or 1
	item.slot = item.slot or ""
	item.texture = item.texture or "Interface\\Icons\\INV_Misc_QuestionMark"
	Mock.items[id] = item
end

_G.MockWow = Mock
return Mock

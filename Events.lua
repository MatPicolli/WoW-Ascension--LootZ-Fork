--print("Loaded <Events.lua>")
local log = _G.LEDII_LZ_LOG
local const = _G.LEDII_LZ_CONST
local compat = _G.LEDII_LZ_COMPAT
local loot = _G.LEDII_LZ_LOOT
local tooltip = _G.LEDII_LZ_TOOLTIP
local render = _G.LEDII_LZ_RENDER

local frame = nil
local hasLootReadyEvent = false
local combatLogSamples = 0

local function PrivateClass()
	local obj = {}

	function obj:OnPlayerLogin()
		--Must run first, on a fresh install the saved variables are still nil
		loot:PrepareCache()

		if (not LediiData_LootZ.welcomeDisabled) then
			log:Info("Version " .. const:String("VERSION") .. " loaded!")
			log:Info(_G.LEDII_LZ_WELCOME)
		end
	end

	function obj:OnLootOpened()
		--3.3.5a has no LOOT_READY event, so the loot source is resolved here
		if (not hasLootReadyEvent) then
			obj:OnLootReady()
		end

		loot:OnLootOpened()
		tooltip:OnLootOpened()
	end

	function obj:OnTargetChanged()
		loot:OnTargetChanged()
	end

	function obj:OnMouseoverChanged()
		loot:OnMouseoverChanged()
	end

	function obj:OnMouseUp(...)
		loot:OnMouseUp(...)
		render:OnGlobalMouseUp(...)
	end

	function obj:OnMouseDown(...)
		--Todo
	end

	function obj:OnKeyDown(key)
		render:OnKeyDown(key)
	end

	function obj:OnKeyUp(key)
		render:OnKeyUp(key)
	end

	function obj:OnCursorChanged(...)
		render:OnCursorChanged(...)
		tooltip:OnCursorChanged(...)
	end

	function obj:OnLootReady()
		loot:OnLootReady()
	end

	function obj:OnLootClosed()
		loot:OnLootClosed()
	end

	function obj:OnChatLoot(message)
		loot:OnChatLoot(message)
	end

	function obj:OnChatMoney(message)
		loot:OnChatMoney(message)
	end

	function obj:OnCombatLogEvent(...)
		local data = compat:ReadCombatLogEvent(...)

		--In debug mode the first few events are dumped raw, so an unexpected
		--argument layout on a custom server can be seen rather than guessed at
		if (combatLogSamples < 6 and loot:IsDebugEnabled()) then
			combatLogSamples = combatLogSamples + 1

			local parts = {}
			for i = 1, 8 do
				table.insert(parts, tostring((select(i, ...))))
			end

			loot:DebugLog("combatlog raw " .. table.concat(parts, " | "))
			loot:DebugLog("combatlog read event=" .. tostring(data.event)
				.. " dest=" .. tostring(data.destGUID) .. " " .. tostring(data.destName))
		end

		if (data.event ~= "UNIT_DIED" and data.event ~= "PARTY_KILL") then return end

		loot:OnUnitDied(data.destGUID, data.destName)
	end

	function obj:OnHyperlinkClicked(link, text, button)
		--Todo
	end

	--Used while binding a modifier key, see Rendering:SampleModifierHotkey
	function obj:SetKeyboardCapture(enabled)
		compat:SetKeyboardCapture(frame, enabled)
	end

	return obj
end

local versionName = const:GetVersionName()
local class = PrivateClass()
_G.LEDII_LZ_EVENTS = class

local function OnEvent(self, event, ...)
	if (event == "PLAYER_LOGIN") then
		class:OnPlayerLogin(...)
	elseif (event == "LOOT_OPENED") then
		class:OnLootOpened(...)
	elseif (event == "LOOT_READY") then
		hasLootReadyEvent = true
		class:OnLootReady(...)
	elseif (event == "LOOT_CLOSED") then
		class:OnLootClosed(...)
	elseif (event == "CHAT_MSG_LOOT") then
		class:OnChatLoot(...)
	elseif (event == "CHAT_MSG_MONEY") then
		class:OnChatMoney(...)
	elseif (event == "COMBAT_LOG_EVENT_UNFILTERED") then
		class:OnCombatLogEvent(...)
	elseif (event == "UPDATE_MOUSEOVER_UNIT") then
		class:OnMouseoverChanged(...)
	elseif (event == "PLAYER_TARGET_CHANGED") then
		class:OnTargetChanged(...)
	elseif (event == "CURSOR_CHANGED") then
		class:OnCursorChanged(...)
	elseif (event == "CURSOR_UPDATE") then
		class:OnCursorChanged(...)
	end
end

local function OnHyperlinkClicked(self, link, text, button)
	class:OnHyperlinkClicked(link, text, button)
end

local function OnKeyDown(self, key)
	class:OnKeyDown(key)
end

local function OnKeyUp(self, key)
	class:OnKeyUp(key)
end

--Register the events
frame = CreateFrame("Frame", "LootZEventFrame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("LOOT_CLOSED")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")

--Needed to credit loot that a companion picks up for you, where no loot
--window is ever opened
frame:RegisterEvent("CHAT_MSG_LOOT")
frame:RegisterEvent("CHAT_MSG_MONEY")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

--Events that only exist on some clients
local function TryRegisterEvent(name)
	pcall(frame.RegisterEvent, frame, name)
end

TryRegisterEvent("LOOT_READY")
TryRegisterEvent("CURSOR_CHANGED")
TryRegisterEvent("CURSOR_UPDATE")

frame:SetScript("OnEvent", OnEvent)
frame:SetScript("OnKeyDown", OnKeyDown)
frame:SetScript("OnKeyUp", OnKeyUp)

--3.3.5a has no GLOBAL_MOUSE_UP / GLOBAL_MOUSE_DOWN, the compat layer tracks
--the mouse buttons instead and reports them the same way
compat:RegisterGlobalMouseUp(function(button) class:OnMouseUp(button) end)
compat:RegisterGlobalMouseDown(function(button) class:OnMouseDown(button) end)

--Keyboard is only captured while binding a hotkey on clients that cannot
--pass unhandled keys back to the game
compat:SetKeyboardCapture(frame, false)

for i = 1, NUM_CHAT_WINDOWS do
	local cfn = format('ChatFrame%i', i)
	local cf = _G[cfn]

	if (cf ~= nil) then
		cf:HookScript("OnHyperlinkClick", OnHyperlinkClicked)
	end
end

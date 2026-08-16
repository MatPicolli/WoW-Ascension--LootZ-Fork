--print("Loaded <Events.lua>")
local log = _G.LEDII_LZ_LOG
local const = _G.LEDII_LZ_CONST
local loot = _G.LEDII_LZ_LOOT
local tooltip = _G.LEDII_LZ_TOOLTIP
local render = _G.LEDII_LZ_RENDER

local function PrivateClass()
	local obj = {}

	function obj:OnPlayerLogin()
		if (not LediiData_LootZ.welcomeDisabled) then
			log:Info("Version " .. const:String("VERSION") .. " loaded!")
			log:Info(_G.LEDII_LZ_WELCOME)
		end

		loot:PrepareCache()
	end

	function obj:OnLootOpened()
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

	function obj:OnHyperlinkClicked(link, text, button)
		--Todo
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
		class:OnLootReady(...)
	elseif (event == "UPDATE_MOUSEOVER_UNIT") then
		class:OnMouseoverChanged(...)
	elseif (event == "PLAYER_TARGET_CHANGED") then
		class:OnTargetChanged(...)
	elseif (event == "GLOBAL_MOUSE_UP") then
		class:OnMouseUp(...)
	elseif (event == "GLOBAL_MOUSE_DOWN") then
		class:OnMouseDown(...)
	elseif (event == "CURSOR_CHANGED") then
		class:OnCursorChanged(...)
	elseif (event == "CURSOR_UPDATE") then
		class:OnCursorChanged(...)
	end
end

local function OnTooltipSetUnit()
	class:OnTooltipSetUnit()
end

local function OnTooltipCleared()
	class:OnTooltipCleared()
end

local function OnTooltipUpdate()
	class:OnTooltipUpdate()
end

local function OnHyperlinkClicked(self, link, text, button)
	class:OnHyperlinkClicked(link, text, button)
end

local function OnKeyDown(self, key)
	class:OnKeyDown(key)
end

local function OnKeyUp(self, key)
	--Note: Apparently not legal to use (does not work!)
	class:OnKeyUp(key)
end

--Register the events
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("LOOT_READY")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("GLOBAL_MOUSE_UP")
frame:RegisterEvent("GLOBAL_MOUSE_DOWN")

--log:Info("Version name: " .. versionName)
--if (versionName == "Classic") then
	--frame:RegisterEvent("CURSOR_UPDATE")
--else
	frame:RegisterEvent("CURSOR_CHANGED")
--end

frame:SetScript("OnEvent", OnEvent)
frame:SetScript("OnKeyDown", OnKeyDown)
frame:SetScript("OnKeyUp", OnKeyUp)
frame:EnableKeyboard(true)
frame:SetPropagateKeyboardInput(true)

for i = 1, NUM_CHAT_WINDOWS do
    local cfn = format('ChatFrame%i',i)
    local cf = _G[cfn]
 
    cf:HookScript("OnHyperlinkClick", OnHyperlinkClicked)
end
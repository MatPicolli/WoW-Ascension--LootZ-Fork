--print("Loaded <Console.lua>")
local log = _G.LEDII_LZ_LOG
local const = _G.LEDII_LZ_CONST
local render = _G.LEDII_LZ_RENDER
local utils = _G.LEDII_LZ_UTILS
local compat = _G.LEDII_LZ_COMPAT

local function PrivateClass()
	local obj = {}
	local loadingItems = nil
	local cachedItems = {}
	local itemsPerPage = 20
	local allowRounding = false

	function obj:Highlight(highlightText, defaultText)
		local highlightStr = const:Color("TEXT_HIGHLIGHT") .. highlightText
		local defaultStr = const:Color("TEXT") .. defaultText
		return highlightStr .. defaultStr
	end

	function obj:Help()
		local cmd = SLASH_LEDII_LZ1
		log:Info(obj:Highlight(cmd .. " alias", " - Logs all command aliases"))
		log:Info(obj:Highlight(cmd .. " controls", " - Displays hotkeys"))
		log:Info(obj:Highlight(cmd .. " reset", " - Resets all collected data"))
		log:Info(obj:Highlight(cmd .. " creature {index}", " - Displays loot for a creature"))
		log:Info(obj:Highlight(cmd .. " object {index}", " - Displays loot for an object"))
		log:Info(obj:Highlight(cmd .. " skinning {index}", " - Displays loot from skinning"))
		log:Info(obj:Highlight(cmd .. " pickpocket {index}", " - Displays loot from pickpocket"))
		log:Info(obj:Highlight(cmd .. " clear", " - Logs all command aliases"))
		log:Info(obj:Highlight(cmd .. " log {warning | error | stats | all}", " - Toggles logging"))
		log:Info(obj:Highlight(cmd .. " stats {gather | display | all}", " - Toggles statistics"))
		log:Info(obj:Highlight(cmd .. " keybind", " - Sets modifier key to display loot"))
		log:Info(obj:Highlight(cmd .. " companion", " - Toggles credit for loot a companion picks up"))
		log:Info(obj:Highlight(cmd .. " shared", " - Toggles shared statistics from other players"))
		log:Info(obj:Highlight(cmd .. " export", " - Explains where your statistics are saved"))
		log:Info(obj:Highlight(cmd .. " debug", " - Logs loot events, for reporting problems"))
		log:Info(obj:Highlight(cmd .. " welcome", " - Toggles login message"))
		log:Info(obj:Highlight(cmd .. " version", " - Displays current version"))
	end

	function obj:Companion()
		local newState = not LediiData_LootZ.companionLootEnabled
		LediiData_LootZ.companionLootEnabled = newState
		obj:InfoLogToggle("Companion looting", not newState)

		if (newState) then
			log:Info("Loot picked up by a companion is credited to the creature that died most recently.")
			log:Info("Turn this off while playing in a group, it cannot tell whose kill it was.")
		end
	end

	function obj:Shared()
		local newState = not LediiData_LootZ.sharedDisabled
		LediiData_LootZ.sharedDisabled = newState
		obj:InfoLogToggle("Shared statistics", newState)
		utils:InvalidateStatsCache()
	end

	function obj:Debug()
		local newState = not LediiData_LootZ.debugEnabled
		LediiData_LootZ.debugEnabled = newState
		obj:InfoLogToggle("Debug logging", not newState)
	end

	function obj:Export()
		local units = 0
		local lootings = 0

		if (LediiData_LootZ ~= nil and LediiData_LootZ.units ~= nil) then
			for _, unit in pairs(LediiData_LootZ.units) do
				units = units + 1
				lootings = lootings + (unit.lootingCount or 0)
			end
		end

		local shared = 0
		if (_G.LEDII_LZ_SHARED ~= nil and _G.LEDII_LZ_SHARED.units ~= nil) then
			for _ in pairs(_G.LEDII_LZ_SHARED.units) do
				shared = shared + 1
			end
		end

		log:Info(obj:Highlight(units .. " creatures", " tracked, from " .. lootings .. " lootings."))
		log:Info(obj:Highlight(shared .. " creatures", " loaded from shared statistics."))
		log:Info("Your statistics are saved to:")
		log:Info(const:Color("TEXT_HIGHLIGHT") .. "WTF\\Account\\<YOUR ACCOUNT>\\SavedVariables\\LootZ.lua")
		log:Info("The file is written when you log out or reload, not while playing.")
		log:Info("Type " .. const:Color("TEXT_HIGHLIGHT") .. "/reload" .. const:Color("TEXT") .. " to write it right now.")
		log:Info("See the readme for how to share it with other players.")
	end

	function obj:Controls()
		log:Info(obj:Highlight("[" .. render:GetHotkeyModifierName() .. " + LeftMouse]", " Toggles loot window"))
		log:Info(obj:Highlight("[CTRL + LeftMouse]", " Equips item in dressing room"))
		log:Info(obj:Highlight("[SHIFT + LeftMouse]", " Adds an item link to current chat message"))
		log:Info(obj:Highlight("[ALT]", " Shows tooltip for hovered Loot Item"))
		log:Info(obj:Highlight("[SHIFT]", " Shows tooltip to compare stats"))
	end

	function obj:Reset()
		LediiData_LootZ = nil

		local loot = _G.LEDII_LZ_LOOT
		loot:PrepareCache()

		log:Info("All collected data was reset.")
	end

	function obj:Alias()
		local options = { SLASH_LEDII_LZ1, SLASH_LEDII_LZ2 }
		local color1 = const:Color("TEXT_HIGHLIGHT")
		local color2 = const:Color("TEXT")
		local allOptionsStr = color1 .. table.concat(options, color2 .. " or " .. color1)
		log:Info("You can use the following aliases when entering commands:\n" .. allOptionsStr)
	end

	function obj:GetUnloadedCreatureName(index)
		if (index == nil) then return end

		--3.3.5a cannot resolve a creature name from an entry id, the client
		--only knows names it has actually seen. Use a name we recorded before,
		--otherwise show the id so the loot table is still browsable.
		if (compat.isLegacyClient) then
			local dataUnit = utils:GetTrackedUnitData(index, false)
			if (dataUnit ~= nil and dataUnit.name ~= nil) then
				return dataUnit.name
			end

			return "Creature #" .. index
		end

		--Create custom unit link
		local guid = "Creature-0-0-0-0-" .. index .. "-0"
		local link = "|cff000000|Hunit:" .. guid .. "|h[Custom Unit]|h"
		--log:Info("Test: " .. link)

		--Set tooltip link and read name text
		local tempVisible = ItemRefTooltip:IsVisible()
		local _, tempLink = ItemRefTooltip:GetItem()
		ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE")
        ItemRefTooltip:SetHyperlink(link)
		local name = _G["ItemRefTooltipTextLeft1"]:GetText()

		--Restore previous state
		if (tempVisible) then
			ItemRefTooltip:SetHyperlink(tempLink)
		else
			ItemRefTooltip:Hide()
		end

		return name
	end

	function obj:Creature(index)
		local name = obj:GetUnloadedCreatureName(index)
		if (name == nil) then return end

		--log:Info("Show loot for creature: " .. name .. " (" .. index .. ")")
		render:SetTargetData("Creature", index, name)
		render:Show()
	end

	function obj:Skinning(index)
		local name = obj:GetUnloadedCreatureName(index)
		if (name == nil) then
			name = "Unknown Skinning"
		end

		--log:Info("Show loot for creature: " .. name .. " (" .. index .. ")")
		render:SetTargetData("Skinning", index, name)
		render:Show()
	end

	function obj:Pickpocket(index)
		local name = obj:GetUnloadedCreatureName(index)
		if (name == nil) then return end

		--log:Info("Show loot for creature: " .. name .. " (" .. index .. ")")
		render:SetTargetData("Pickpocketing", index, name)
		render:Show()
	end

	function obj:Object(index)
		if (index == nil) then return end
		local name = utils:FindObjectName(index)
		local loot = utils:FindIndexFromDB("GameObjectLoot", index, false)

		if (name == nil or loot == nil) then
			log:Info(const:Color("WARNING") .. "Invalid object index <" .. index .. ">")
			return
		end

		render:SetTargetData("Object", index, name)
		render:Show()
	end

	function obj:Clear()
		SELECTED_CHAT_FRAME:Clear()
	end

	function obj:ToggleLogs(type)
		if (type == "warning") then
			local newState = not LediiData_LootZ.logWarningHidden
			LediiData_LootZ.logWarningHidden = newState
			obj:InfoLogToggle("Warning logging", newState)
		end
		if (type == "error") then
			local newState = not LediiData_LootZ.logErrorHidden
			LediiData_LootZ.logErrorHidden = newState
			obj:InfoLogToggle("Error logging", newState)
		end
		if (type == "stats") then
			local newState = not LediiData_LootZ.logStatsEnabled
			LediiData_LootZ.logStatsEnabled = newState
			obj:InfoLogToggle("Stats logging", not newState)
		end
		if (type == "all") then
			local newState = not LediiData_LootZ.logWarningHidden
			LediiData_LootZ.logWarningHidden = newState
			LediiData_LootZ.logErrorHidden = newState
			LediiData_LootZ.logStatsEnabled = not newState
			obj:InfoLogToggle("All logging", newState)
		end
	end

	function obj:ToggleStats(type)
		if (type == "gather") then
			local newState = not LediiData_LootZ.statsGatherDisabled
			LediiData_LootZ.statsGatherDisabled = newState
			obj:InfoLogToggle("Gathering statistics", newState)
		end
		if (type == "tooltip") then
			local newState = not LediiData_LootZ.statsTooltipDisabled
			LediiData_LootZ.statsTooltipDisabled = newState
			obj:InfoLogToggle("Tooltip statistics", newState)
		end
		if (type == "all") then
			local newState = not LediiData_LootZ.statsGatherDisabled
			LediiData_LootZ.statsGatherDisabled = newState
			LediiData_LootZ.statsTooltipDisabled = newState
			obj:InfoLogToggle("All statistics", newState)
		end
	end

	function obj:InfoLogToggle(type, state)
		local str = const:Color("ENABLED") .. "enabled" .. const:Color("TEXT")
		if (state) then
			str = const:Color("DISABLED") .. "disabled" .. const:Color("TEXT")
		end
		local cType = const:Color("TEXT_HIGHLIGHT") .. type .. const:Color("TEXT")

		log:Info(cType .. " was " .. str)
	end

	function obj:Keybind()
		render:SampleModifierHotkey()
	end

	function obj:Welcome()
		local newState = not LediiData_LootZ.welcomeDisabled
		LediiData_LootZ.welcomeDisabled = newState
		obj:InfoLogToggle("Welcome message", newState)
	end

	function obj:Version()
		log:Info("Version " .. const:String("VERSION"))
	end

	return obj
end

local class = PrivateClass()
_G.LEDII_LZ_CONSOLE = class

SLASH_LEDII_LZ1 = '/lootz'
SLASH_LEDII_LZ2 = '/lz'
function SlashCmdList.LEDII_LZ(msg, editbox)
	local args = utils:Split(msg, " ")

	if (args[1] == "alias") then
		class:Alias()
	elseif (args[1] == "controls") then
		class:Controls()
	elseif (args[1] == "reset") then
		class:Reset()
	elseif (args[1] == "creature") then
		class:Creature(tonumber(args[2]))
	elseif (args[1] == "skinning") then
		class:Skinning(tonumber(args[2]))
	elseif (args[1] == "pickpocket") then
		class:Pickpocket(tonumber(args[2]))
	elseif (args[1] == "object") then
		class:Object(tonumber(args[2]))
	elseif (args[1] == "clear") then
		class:Clear()
	elseif (args[1] == "log") then
		class:ToggleLogs(args[2])
	elseif (args[1] == "stats") then
		class:ToggleStats(args[2])
	elseif (args[1] == "keybind") then
		class:Keybind()
	elseif (args[1] == "companion") then
		class:Companion()
	elseif (args[1] == "shared") then
		class:Shared()
	elseif (args[1] == "export") then
		class:Export()
	elseif (args[1] == "debug") then
		class:Debug()
	elseif (args[1] == "welcome") then
		class:Welcome()
	elseif (args[1] == "version") then
		class:Version()
	else
		class:Help()
	end

end

_G.LEDII_LZ_WELCOME = "Type " .. const:Color("TEXT_HIGHLIGHT") .. SLASH_LEDII_LZ1 .. " help" .. const:Color("TEXT") .. " to show the list of commands."
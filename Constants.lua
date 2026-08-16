--print("Loaded <Constants.lua>")
local name = ...

local function class()
	local obj = {}

	function obj:String(type)
		if (type == "NAME") then return name
		elseif (type == "VERSION") then return C_AddOns.GetAddOnMetadata(name, "Version")
		end

		return ""
	end

	function obj:Color(type)
		if (type == "BACKGROUND") then return "|cFF101010"
		elseif (type == "BACKGROUND") then return "|cFF202020"
		elseif (type == "HEADER") then return "|cFFE6CC80"
		elseif (type == "TEXT") then return "|cFF00AA00"
		elseif (type == "TEXT_HIGHLIGHT") then return "|cFFffffff"
		elseif (type == "NAME") then return "|cFFffff00"

		elseif (type == "JUNK") then return "|cFF9d9d9d"
		elseif (type == "COMMON") then return "|cFFffffff"
		elseif (type == "UNCOMMON") then return "|cFF1eff00"
		elseif (type == "RARE") then return "|cFF0070dd"
		elseif (type == "EPIC") then return "|cFFa335ee"
		elseif (type == "LEGENDARY") then return "|cFFff8000"

		elseif (type == "WARNING") then return "|cFFffff00"
		elseif (type == "ERROR") then return "|cFFff0000"
		elseif (type == "LOOT_ITEM") then return "|cFFffdd00"
		elseif (type == "QUEST_ITEM") then return "|cFFdd4444"

		elseif (type == "ENABLED") then return "|cFF00ff00"
		elseif (type == "DISABLED") then return "|cFFff0000"

		elseif (type == "BUTTON") then return "|cFFffd100"
		end

		return ""
	end

	function obj:ColorRGBA(type)
		local colorStr = obj:Color(type)
		local hexStr = colorStr:gsub("|c", "")
		local r = tonumber("0x" .. hexStr:sub(3, 4))
		local g = tonumber("0x" .. hexStr:sub(5, 6))
		local b = tonumber("0x" .. hexStr:sub(7, 8))
		local a = tonumber("0x" .. hexStr:sub(1, 2))
		return r / 255.0, g / 255.0, b / 255.0, a / 255.0
	end

	function obj:GetVersionName()
		local version, build, date, toc = GetBuildInfo()
		local major, minor, patch = strsplit(".", version)
		local majorNum = tonumber(major)

		if (majorNum == 1) then
			return "Classic"
		elseif (majorNum == 2) then
			return "The Burning Crusade"
		elseif (majorNum == 3) then
			return "Wrath of the Lich King"
		elseif (majorNum == 3) then
			return "Wrath of the Lich King"
		elseif (majorNum == 4) then
			return "Cataclysm"
		elseif (majorNum == 5) then
			return "Mists of Pandaria"
		elseif (majorNum == 6) then
			return "Warlords of Draenor"
		elseif (majorNum == 7) then
			return "Legion"
		elseif (majorNum == 8) then
			return "Battle for Azeroth"
		elseif (majorNum == 9) then
			return "Shadowlands"
		elseif (majorNum == 10) then
			return "Dragonflight"
		else
			return "Unknown"
		end
	end

	return obj
end

_G.LEDII_LZ_CONST = class()
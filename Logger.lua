--print("Loaded <Logger.lua>")
local const = _G.LEDII_LZ_CONST

local function class()
	local obj = {}

	function obj:Info(msg)
		local type = obj:FindMessageType(msg)
		local data = LediiData_LootZ or {}
		if (type == "WARNING" and data.logWarningHidden) then return end
		if (type == "ERROR" and data.logErrorHidden) then return end

		print(const:Color("HEADER") .. "[" .. const:String("NAME") .. "] " .. const:Color("TEXT") .. msg)
	end

	function obj:FindMessageType(msg)
		if (string.find(msg, const:Color("ERROR"))) then
			return "ERROR"
		end
		if (string.find(msg, const:Color("WARNING"))) then
			return "WARNING"
		end

		return "INFO"
	end

	function obj:GetIndentStr(depth)
		string.rep("  ", depth)
	end

	function obj:ValueString(inValue, label, maxDepth, depth)
		label = label or "Value"
		depth = depth or 0
		maxDepth = maxDepth or 0

		local depthStr = string.rep("  ", depth)

		if (type(inValue) ~= "table") then
			obj:Info(string.format("%s%s = %s", depthStr, label, tostring(inValue)))
			return
		end
		if (maxDepth > 0 and depth >= maxDepth) then
			obj:Info(string.format("%s%s = Table { ... }", depthStr, label))
			return
		end

		obj:Info(string.format("%s%s = Table {", depthStr, label))
		for key, value in pairs(inValue) do
			obj:ValueString(value, string.format("[%s]", key), depth + 1)
		end
		obj:Info(string.format("%s}", depthStr))

		return
	end

	function obj:PairTable(table)
		for key, value in pairs(table) do
			obj:Info("[" .. key .. "] = " .. tostring(value))
		end
	end

	function obj:IndexTable(table)
		for i, value in ipairs(table) do
			obj:Info("[" .. i .. "] = " .. tostring(value))
		end
	end

	return obj
end

_G.LEDII_LZ_LOG = class()
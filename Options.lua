--print("Loaded <Options.lua>")
local log = _G.LEDII_LZ_LOG
local const = _G.LEDII_LZ_CONST
local utils = _G.LEDII_LZ_UTILS
local compat = _G.LEDII_LZ_COMPAT
local loot = _G.LEDII_LZ_LOOT

local frame = nil
local rows = {}
local statusLabels = {}
local modifierButton = nil
local resetButton = nil
local resetArmedUntil = 0
local resetArmTime = 5.0

local panelSize = { 380, 470 }
local rowHeight = 26
local sectionSpacing = 12
local modifiers = { "SHIFT", "CTRL", "ALT" }

--Every option is described once, and the panel is built from this
local options = {
	{ section = "Statistics" },
	{
		label = "Record the loot I pick up",
		tip = "Counts every corpse you loot, and what came off it.",
		get = function() return not LediiData_LootZ.statsGatherDisabled end,
		set = function(value) LediiData_LootZ.statsGatherDisabled = not value end,
	},
	{
		label = "Show statistics in unit tooltips",
		tip = "Adds how often you looted a creature to its tooltip.",
		get = function() return not LediiData_LootZ.statsTooltipDisabled end,
		set = function(value) LediiData_LootZ.statsTooltipDisabled = not value end,
	},
	{
		label = "Use statistics shared by other players",
		tip = "Merges Database/Shared with your own numbers.\nYour own data is never overwritten.",
		get = function() return not LediiData_LootZ.sharedDisabled end,
		set = function(value)
			LediiData_LootZ.sharedDisabled = not value
			utils:InvalidateStatsCache()
		end,
	},
	{
		label = "Credit loot my companion picks up",
		tip = "For companions that loot for you, like Lootbot 3000."
			.. "\nCredits loot to the creature that died most recently."
			.. "\n|cFFffff00Turn this off in a group|r, it cannot tell whose kill it was.",
		get = function() return LediiData_LootZ.companionLootEnabled == true end,
		set = function(value) LediiData_LootZ.companionLootEnabled = value end,
	},

	{ section = "Chat" },
	{
		label = "Show the welcome message at login",
		get = function() return not LediiData_LootZ.welcomeDisabled end,
		set = function(value) LediiData_LootZ.welcomeDisabled = not value end,
	},
	{
		label = "Show warnings",
		get = function() return not LediiData_LootZ.logWarningHidden end,
		set = function(value) LediiData_LootZ.logWarningHidden = not value end,
	},
	{
		label = "Show errors",
		get = function() return not LediiData_LootZ.logErrorHidden end,
		set = function(value) LediiData_LootZ.logErrorHidden = not value end,
	},
	{
		label = "Report problems while gathering statistics",
		tip = "Warns when a loot window cannot be matched to a creature.",
		get = function() return LediiData_LootZ.logStatsEnabled == true end,
		set = function(value) LediiData_LootZ.logStatsEnabled = value end,
	},
	{
		label = "Debug logging",
		tip = "Logs every loot event, plus the raw combat log arguments."
			.. "\nUse this when reporting a problem.",
		get = function() return LediiData_LootZ.debugEnabled == true end,
		set = function(value) LediiData_LootZ.debugEnabled = value end,
	},
}

local function class()
	local obj = {}

	function obj:IsReady()
		return frame ~= nil and LediiData_LootZ ~= nil
	end

	function obj:Toggle()
		if (frame == nil) then return end

		if (frame:IsShown()) then
			obj:Hide()
		else
			obj:Show()
		end
	end

	function obj:Show()
		if (frame == nil) then return end

		obj:Refresh()
		frame:Show()

		if (not tContains(UISpecialFrames, frame:GetName())) then
			tinsert(UISpecialFrames, frame:GetName())
		end
	end

	function obj:Hide()
		if (frame == nil) then return end

		frame:Hide()

		for i, name in ipairs(UISpecialFrames) do
			if (name == frame:GetName()) then
				table.remove(UISpecialFrames, i)
				break
			end
		end
	end

	function obj:Refresh()
		if (LediiData_LootZ == nil) then return end

		for i = 1, #rows do
			local row = rows[i]
			row.checkButton:SetChecked(row.option.get() and true or false)
		end

		modifierButton:SetText(const:Color("BUTTON") .. obj:GetModifier())
		obj:RefreshStatus()
	end

	function obj:GetModifier()
		return LediiData_LootZ["HOTKEY_MOD"] or "CTRL"
	end

	function obj:CycleModifier()
		local current = obj:GetModifier()
		local nextIndex = 1

		for i = 1, #modifiers do
			if (modifiers[i] == current) then
				nextIndex = i + 1
				if (nextIndex > #modifiers) then nextIndex = 1 end
			end
		end

		LediiData_LootZ["HOTKEY_MOD"] = modifiers[nextIndex]
		modifierButton:SetText(const:Color("BUTTON") .. modifiers[nextIndex])
		log:Info("Loot window opens with " .. const:Color("TEXT_HIGHLIGHT")
			.. modifiers[nextIndex] .. " + Left Click" .. const:Color("TEXT") .. ".")
	end

	function obj:RefreshStatus()
		local units, lootings = 0, 0
		if (LediiData_LootZ.units ~= nil) then
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

		local deaths, tracked, window = loot:GetCompanionState()

		statusLabels[1]:SetText(const:Color("TEXT") .. "Tracked: " .. const:Color("TEXT_HIGHLIGHT")
			.. units .. const:Color("TEXT") .. " creatures from " .. const:Color("TEXT_HIGHLIGHT")
			.. lootings .. const:Color("TEXT") .. " lootings")
		statusLabels[2]:SetText(const:Color("TEXT") .. "Shared: " .. const:Color("TEXT_HIGHLIGHT")
			.. shared .. const:Color("TEXT") .. " creatures loaded")
		statusLabels[3]:SetText(const:Color("TEXT") .. "Deaths seen: " .. const:Color("TEXT_HIGHLIGHT")
			.. deaths .. const:Color("TEXT") .. " (" .. tracked .. " within " .. window .. "s)")
	end

	function obj:OnReset()
		--Destructive, so it takes two clicks
		if (GetTime() > resetArmedUntil) then
			resetArmedUntil = GetTime() + resetArmTime
			resetButton:SetText(const:Color("ERROR") .. "Are you sure?")
			return
		end

		resetArmedUntil = 0
		resetButton:SetText(const:Color("BUTTON") .. "Reset data")

		local console = _G.LEDII_LZ_CONSOLE
		if (console ~= nil) then console:Reset() end

		obj:Refresh()
	end

	function obj:OnUpdate()
		--Let the reset confirmation expire on its own
		if (resetArmedUntil > 0 and GetTime() > resetArmedUntil) then
			resetArmedUntil = 0
			resetButton:SetText(const:Color("BUTTON") .. "Reset data")
		end
	end

	function obj:ShowTip(owner, option)
		if (option.tip == nil) then return end

		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
		GameTooltip:AddLine(option.label)
		GameTooltip:AddLine(option.tip, 1, 1, 1)
		GameTooltip:Show()
	end



	--Building
	function obj:CreateBackdropFrame(name, parent)
		local created = CreateFrame("Frame", name, parent, BackdropTemplateMixin and "BackdropTemplate")
		created:SetBackdrop({
			bgFile = "Interface/Tooltips/UI-Tooltip-Background",
			edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		})
		created:SetBackdropColor(0, 0, 0, 1)

		return created
	end

	function obj:CreateLabel(parent, text, template)
		local label = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
		label:SetText(text)
		label:SetJustifyH("LEFT")

		return label
	end

	function obj:Init()
		frame = obj:CreateBackdropFrame("LootZOptionsPanel", UIParent)
		frame:SetFrameStrata("DIALOG")
		frame:SetPoint("CENTER")
		compat:SetSize(frame, panelSize[1], panelSize[2])
		frame:EnableMouse(true)
		frame:SetMovable(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
		frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
		frame:SetScript("OnUpdate", function() obj:OnUpdate() end)

		local title = obj:CreateLabel(frame, const:Color("HEADER") .. "LootZ Options")
		title:SetPoint("TOPLEFT", 16, -14)

		local close = compat:CreateButton("LootZOptionsClose", frame)
		close:SetText(const:Color("BUTTON") .. "x")
		close:SetPoint("TOPRIGHT", -12, -10)
		compat:SetSize(close, 26, 20)
		close:SetScript("OnClick", function() obj:Hide() end)

		--Options
		local y = 44
		for i = 1, #options do
			local option = options[i]

			if (option.section ~= nil) then
				y = y + sectionSpacing
				local header = obj:CreateLabel(frame, const:Color("HEADER") .. option.section, "GameFontNormalSmall")
				header:SetPoint("TOPLEFT", 16, -y)
				y = y + 18
			else
				local checkButton = compat:CreateCheckButton("LootZOption" .. i, frame)
				checkButton:SetPoint("TOPLEFT", 14, -y + 4)
				compat:SetSize(checkButton, 24, 24)

				local label = obj:CreateLabel(frame, const:Color("TEXT") .. option.label, "GameFontHighlightSmall")
				label:SetPoint("TOPLEFT", 42, -y)

				checkButton:SetScript("OnClick", function(self)
					if (LediiData_LootZ == nil) then return end
					option.set(self:GetChecked() and true or false)
					obj:Refresh()
				end)
				checkButton:SetScript("OnEnter", function(self) obj:ShowTip(self, option) end)
				checkButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

				table.insert(rows, { option = option, checkButton = checkButton, label = label })
				y = y + rowHeight
			end
		end

		--Hotkey
		y = y + sectionSpacing
		local hotkeyHeader = obj:CreateLabel(frame, const:Color("HEADER") .. "Hotkey", "GameFontNormalSmall")
		hotkeyHeader:SetPoint("TOPLEFT", 16, -y)
		y = y + 20

		local hotkeyLabel = obj:CreateLabel(frame, const:Color("TEXT") .. "Open the loot window with", "GameFontHighlightSmall")
		hotkeyLabel:SetPoint("TOPLEFT", 16, -y - 4)

		modifierButton = compat:CreateButton("LootZOptionsModifier", frame)
		modifierButton:SetPoint("TOPLEFT", 176, -y)
		compat:SetSize(modifierButton, 70, 22)
		modifierButton:SetScript("OnClick", function() obj:CycleModifier() end)

		local hotkeySuffix = obj:CreateLabel(frame, const:Color("TEXT") .. "+ Left Click", "GameFontHighlightSmall")
		hotkeySuffix:SetPoint("TOPLEFT", 254, -y - 4)
		y = y + 32

		--Status
		y = y + sectionSpacing
		local statusHeader = obj:CreateLabel(frame, const:Color("HEADER") .. "Collected data", "GameFontNormalSmall")
		statusHeader:SetPoint("TOPLEFT", 16, -y)
		y = y + 20

		for i = 1, 3 do
			local status = obj:CreateLabel(frame, "", "GameFontHighlightSmall")
			status:SetPoint("TOPLEFT", 16, -y)
			statusLabels[i] = status
			y = y + 16
		end

		--Actions
		y = y + sectionSpacing
		local exportButton = compat:CreateButton("LootZOptionsExport", frame)
		exportButton:SetText(const:Color("BUTTON") .. "Where is my data?")
		exportButton:SetPoint("TOPLEFT", 16, -y)
		compat:SetSize(exportButton, 160, 22)
		exportButton:SetScript("OnClick", function()
			local console = _G.LEDII_LZ_CONSOLE
			if (console ~= nil) then console:Export() end
		end)

		resetButton = compat:CreateButton("LootZOptionsReset", frame)
		resetButton:SetText(const:Color("BUTTON") .. "Reset data")
		resetButton:SetPoint("TOPLEFT", 190, -y)
		compat:SetSize(resetButton, 160, 22)
		resetButton:SetScript("OnClick", function() obj:OnReset() end)

		frame:Hide()
	end

	return obj
end

local class = class()
class:Init()

_G.LEDII_LZ_OPTIONS = class

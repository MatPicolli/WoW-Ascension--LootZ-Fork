--[[
	Runs LootZ against the mocked 3.3.5a client in Tools/MockWowApi.lua.

	It loads every Lua file listed in LootZ.toc, in the same order the client
	would, and then plays through a session: login, killing and looting a
	creature, the unit tooltip, opening the loot panel, the row hotkeys, the
	slash commands and a world object.

	Usage:
		lua5.1 Tools/SmokeTest.lua

	Exits with code 1 if anything fails, so it can be used in CI.
]]

local root = (string.match(arg[0] or "", "^(.*)[/\\]Tools[/\\]") or ".")

--The mock replaces print() with the in game chat frame, keep the real one
local print = print

local Mock = dofile(root .. "/Tools/MockWowApi.lua")
Mock.Install()

--Test helpers ---------------------------------------------------------------

local failures = {}
local checks = 0

local function check(condition, message)
	checks = checks + 1
	if (condition) then
		print("  ok   " .. message)
	else
		print("  FAIL " .. message)
		table.insert(failures, message)
	end
end

local function section(name)
	print("")
	print("== " .. name)
end

local function lastPrinted(count)
	local out = {}
	for i = math.max(1, #Mock.printed - (count or 5) + 1), #Mock.printed do
		table.insert(out, Mock.printed[i])
	end
	return table.concat(out, "\n")
end

local function printedCount(text)
	local count = 0
	for i = 1, #Mock.printed do
		if (string.find(Mock.printed[i], text, 1, true)) then count = count + 1 end
	end
	return count
end

local function printedContains(text)
	for i = 1, #Mock.printed do
		if (string.find(Mock.printed[i], text, 1, true)) then return true end
	end
	return false
end

--Fixtures -------------------------------------------------------------------

local CREATURE_ENTRY = 3561
local CREATURE_GUID = "0xF130000DE9000E38"
local CREATURE_GUID_2 = "0xF130000DE9000E39"

Mock.AddItem(1234, { name = "Linen Cloth", rarity = 1, type = "Trade Goods", subtype = "Cloth" })
Mock.AddItem(5678, { name = "Ornate Blade", rarity = 3, type = "Weapon", subtype = "One-Handed Swords", slot = "INVTYPE_WEAPON" })
Mock.AddItem(2770, { name = "Copper Ore", rarity = 1, type = "Trade Goods", subtype = "Metal & Stone" })
Mock.AddItem(4321, { name = "Bot Salvage", rarity = 2, type = "Trade Goods", subtype = "Parts" })
Mock.AddItem(774, { name = "Malachite", rarity = 2, type = "Gem", subtype = "Simple" })
--This one is not in the client cache yet, it only resolves after a query
Mock.AddItem(9999, { name = "Slow Loading Trinket", rarity = 4, type = "Armor", subtype = "Miscellaneous", slot = "INVTYPE_TRINKET", needsQuery = true })

local function lootRow(item, reference, chance, groupId, minCount, maxCount)
	return {
		item = item,
		reference = reference,
		chance = chance,
		questRequired = false,
		lootMode = 1,
		groupId = groupId,
		minCount = minCount,
		maxCount = maxCount,
	}
end

--Installed before the addon loads, so Database/Setup.lua must not clobber it
_G.LEDII_DB = {
	CreatureLoot_1 = {
		[tostring(CREATURE_ENTRY)] = {
			lootRow(1234, 0, 45.0, 0, 1, 3),
			lootRow(0, 101, 20.0, 0, 1, 1),
			lootRow(9999, 0, 0.5, 1, 1, 1),
		},
	},
	ReferenceLoot_1 = {
		["101"] = {
			lootRow(5678, 0, 50.0, 0, 1, 1),
		},
	},
	GameObjectData_1 = {
		["Copper Vein"] = { { entry = 1731, loot = 1731 } },
	},
	GameObjectLoot_1 = {
		["1731"] = { lootRow(2770, 0, 100.0, 0, 1, 3) },
	},
	GameObjectInstance_1 = {
		["1731"] = { { positionX = 100, positionY = 200, positionZ = 10, spawnTime = 300 } },
	},
}

--Load the addon -------------------------------------------------------------

section("Loading files from LootZ.toc")

local tocFile = assert(io.open(root .. "/LootZ.toc", "r"))
local loaded, skipped = 0, 0

for line in tocFile:lines() do
	line = string.gsub(line, "%s+$", "")
	if (string.find(line, "%.lua$") and not string.find(line, "^#")) then
		local path = root .. "/" .. string.gsub(line, "\\", "/")
		local chunk = loadfile(path)

		if (chunk == nil) then
			--Missing database files are expected, they ship separately
			skipped = skipped + 1
			print("  skip " .. line .. " (file not present)")
		else
			local ok, err = pcall(chunk, "LootZ", {})
			if (not ok) then
				print("  FAIL " .. line .. ": " .. tostring(err))
				table.insert(failures, "loading " .. line)
			else
				loaded = loaded + 1
				print("  ok   " .. line)
			end
		end
	end
end
tocFile:close()

check(#failures == 0, "every present file loaded without errors")
check(_G.LEDII_LZ_COMPAT ~= nil, "compat layer is available")
check(_G.LEDII_LZ_COMPAT.isLegacyClient == true, "detected the legacy 3.3.5a client")
check(_G.LEDII_DB.CreatureLoot_1 ~= nil, "Database/Setup.lua kept the existing database")
check(type(_G.C_Timer) == "table", "C_Timer was polyfilled")

--Login ----------------------------------------------------------------------

section("Login")

check(_G.LediiData_LootZ == nil, "saved variables start empty, like a fresh install")
Mock.FireEvent("PLAYER_LOGIN")
Mock.RunFrames(2)

check(_G.LediiData_LootZ ~= nil, "saved variables were created on login")
check(printedContains("loaded!"), "welcome message was printed")
check(printedContains("1.2.8-ascension"), "version came from the toc metadata")

--Looting a creature ---------------------------------------------------------

section("Looting a creature")

local corpse = {
	guid = CREATURE_GUID,
	name = "Kobold Vermin",
	level = 5,
	dead = true,
	type = "Humanoid",
	family = nil,
}
Mock.SetUnit("target", corpse)
Mock.FireEvent("PLAYER_TARGET_CHANGED")

--Right click the corpse: 3.3.5a has no GLOBAL_MOUSE_UP, the compat layer polls
Mock.ClickMouse("RightButton")

Mock.lootSlots = {
	{ name = "Linen Cloth", quantity = 2, quality = 1, link = Mock.items[1234].link },
	{ name = "1 Gold, 20 Silver, 5 Copper", quantity = 0, quality = 1, link = nil },
}
Mock.FireEvent("LOOT_OPENED")
Mock.RunFrames(2)

local unitData = _G.LediiData_LootZ.units and _G.LediiData_LootZ.units[CREATURE_ENTRY]
check(unitData ~= nil, "loot was recorded against creature entry " .. CREATURE_ENTRY)
check(unitData ~= nil and unitData.name == "Kobold Vermin", "creature name was stored")
check(unitData ~= nil and unitData.lootingCount == 1, "one looting was counted")
check(unitData ~= nil and unitData.items[1234] ~= nil, "the looted item was stored")
check(unitData ~= nil and unitData.items[1234].totalAmount == 2, "item quantity was stored")
check(unitData ~= nil and unitData.money ~= nil and unitData.money.totalAmount == 12005,
	"money string '1 Gold, 20 Silver, 5 Copper' parsed to 12005 copper")

--Re-opening the same corpse must not count twice
Mock.FireEvent("LOOT_OPENED")
Mock.RunFrames(2)
check(_G.LediiData_LootZ.units[CREATURE_ENTRY].lootingCount == 1, "re-opening the same corpse did not count again")

--A second corpse of the same creature counts again
Mock.SetUnit("target", {
	guid = CREATURE_GUID_2, name = "Kobold Vermin", level = 5, dead = true, type = "Humanoid",
})
Mock.FireEvent("PLAYER_TARGET_CHANGED")
Mock.ClickMouse("RightButton")
Mock.FireEvent("LOOT_OPENED")
Mock.RunFrames(2)
check(_G.LediiData_LootZ.units[CREATURE_ENTRY].lootingCount == 2, "a second corpse counted as a new looting")

--Looting without ever seeing the click (keybind looting) still works
Mock.SetUnit("target", {
	guid = "0xF130000DE9000E40", name = "Kobold Vermin", level = 5, dead = true, type = "Humanoid",
})
Mock.FireEvent("PLAYER_TARGET_CHANGED")
Mock.FireEvent("LOOT_OPENED")
Mock.RunFrames(2)
check(_G.LediiData_LootZ.units[CREATURE_ENTRY].lootingCount == 3, "looting without a mouse click fell back to the target")

--Unit tooltip ---------------------------------------------------------------

section("Unit tooltip")

Mock.SetUnit("mouseover", corpse)
_G.GameTooltip:ClearLines()
Mock.FireScript(_G.GameTooltip, "OnTooltipSetUnit")
check(_G.GameTooltip:NumLines() > 0, "statistics were added to the unit tooltip")
Mock.SetUnit("mouseover", nil)

--Loot panel -----------------------------------------------------------------

section("Loot panel")

_G.LediiData_LootZ["HOTKEY_MOD"] = "CTRL"
Mock.keys.CTRL = true
Mock.SetUnit("target", corpse)
Mock.ClickMouse("LeftButton")
Mock.keys.CTRL = false

check(_G.LootZMainPanel ~= nil, "the panel frame exists")
check(_G.LootZMainPanel ~= nil and _G.LootZMainPanel:IsShown(), "the panel opened on modifier + left click")

--Let the queued layers and the async item request resolve
Mock.RunFrames(120, 0.1)
check(Mock.itemCached[9999] == true, "an uncached item was requested from the server")

--The whole pipeline: database -> hierarchy -> item lookup -> rendered row
check(Mock.FindText("Linen Cloth") ~= nil, "a loot row was rendered from the database")
check(Mock.FindText("45%") ~= nil, "the drop chance was rendered")
check(Mock.FindText("Main > 101") ~= nil, "a reference loot group was rendered as its own layer")
check(Mock.FindText("Ornate Blade") ~= nil, "an item inside the reference group was rendered")
check(Mock.FindText("Slow Loading Trinket") ~= nil, "the item that needed a server query was rendered")

--Cycle every sort mode, then the data modes, through the header buttons
for i = 1, 5 do
	Mock.FireScript(_G.LootZButton2, "OnClick")
	Mock.RunFrames(20, 0.1)
end
check(true, "cycled through all sort modes without an error")

Mock.FireScript(_G.LootZButton1, "OnClick")
Mock.RunFrames(20, 0.1)
check(Mock.FindText("Account") ~= nil, "the Stats mode rendered the statistics gathered so far")

Mock.FireScript(_G.LootZButton1, "OnClick")
Mock.RunFrames(20, 0.1)

Mock.FireScript(_G.LootZButton4, "OnClick")
check(_G.LootZMainPanel:IsShown() == false, "the close button hid the panel")

Mock.SetUnit("target", corpse)
Mock.keys.CTRL = true
Mock.ClickMouse("LeftButton")
Mock.keys.CTRL = false
Mock.RunFrames(20, 0.1)
check(_G.LootZMainPanel:IsShown(), "the panel opened again after being closed")

--Hovering a row, with the hotkeys
Mock.mouseOverAll = true
Mock.cursorY = 800
Mock.keys.ALT = true
Mock.RunFrames(2)
Mock.keys.ALT = false

Mock.keys.SHIFT = true
Mock.ClickMouse("LeftButton")
Mock.keys.SHIFT = false
check(string.find(_G.DEFAULT_CHAT_FRAME.editBox:GetText() or "", "item:", 1, true) ~= nil,
	"shift + click appended an item link to the chat box")

Mock.keys.CTRL = true
Mock.ClickMouse("LeftButton")
Mock.keys.CTRL = false
Mock.mouseOverAll = false
Mock.cursorY = 500
Mock.RunFrames(2)

--Slash commands -------------------------------------------------------------

section("Slash commands")

local slash = _G.SlashCmdList.LEDII_LZ
check(slash ~= nil, "/lootz is registered")

local commands = {
	"", "help", "alias", "controls", "version", "welcome", "welcome",
	"log warning", "log error", "log stats", "log all", "log all",
	"stats gather", "stats tooltip", "stats all", "stats all",
	"creature " .. CREATURE_ENTRY, "skinning " .. CREATURE_ENTRY,
	"pickpocket " .. CREATURE_ENTRY, "object 1731", "object 999999",
	"clear", "keybind",
}

for i = 1, #commands do
	local ok, err = pcall(slash, commands[i])
	check(ok, "/lootz " .. commands[i] .. (ok and "" or (" -> " .. tostring(err))))
	Mock.RunFrames(2)
end

--Binding a modifier key
Mock.FireScript(_G.LootZEventFrame, "OnKeyDown", "LSHIFT")
check(_G.LediiData_LootZ["HOTKEY_MOD"] == "SHIFT", "pressing shift bound the modifier after /lootz keybind")

--World object ---------------------------------------------------------------

section("World object")

--The command run above toggled logging off, which is itself worth checking
check(_G.LediiData_LootZ.logWarningHidden == true, "/lootz log left warnings hidden")
_G.LediiData_LootZ.logWarningHidden = false
_G.LediiData_LootZ.logErrorHidden = false

local before = _G.LediiData_LootZ.units[CREATURE_ENTRY].lootingCount

_G.GameTooltip:SetOwner(_G.UIParent)
_G.GameTooltipTextLeft1:SetText("Copper Vein")
Mock.SetUnit("target", corpse)
Mock.ClickMouse("RightButton")
check(printedContains("Statistics not supported for object"), "clicking a world object was detected")

Mock.lootSlots = { { name = "Copper Ore", quantity = 1, quality = 1, link = Mock.items[2770].link } }
Mock.FireEvent("LOOT_OPENED")
Mock.RunFrames(2)
Mock.FireEvent("LOOT_CLOSED")
check(_G.LediiData_LootZ.units[CREATURE_ENTRY].lootingCount == before,
	"object loot was not attributed to the targeted creature")

--Object loot table by name
Mock.FireScript(_G.GameTooltip, "OnUpdate")
local ok, err = pcall(slash, "object 1731")
check(ok, "object loot table opened" .. (ok and "" or (" -> " .. tostring(err))))

_G.GameTooltipTextLeft1:SetText(nil)

--Options window -------------------------------------------------------------

section("Options window")

check(_G.LootZOptionsPanel ~= nil, "the options panel exists")
check(_G.LootZOptionsPanel:IsShown() == false, "it starts hidden")

slash("options")
check(_G.LootZOptionsPanel:IsShown(), "/lootz options opened it")

--The # button in the loot panel header is the same window
slash("options")
check(_G.LootZOptionsPanel:IsShown() == false, "/lootz options closed it again")
Mock.FireScript(_G.LootZButton3, "OnClick")
check(_G.LootZOptionsPanel:IsShown(), "the # button in the loot panel opened it")

--Every checkbox must reflect, and change, a real setting
local checkedOptions = {
	{ frame = "LootZOption2", key = "statsGatherDisabled", inverted = true },
	{ frame = "LootZOption3", key = "statsTooltipDisabled", inverted = true },
	{ frame = "LootZOption4", key = "sharedDisabled", inverted = true },
	{ frame = "LootZOption5", key = "companionLootEnabled", inverted = false },
	{ frame = "LootZOption7", key = "welcomeDisabled", inverted = true },
	{ frame = "LootZOption8", key = "logWarningHidden", inverted = true },
	{ frame = "LootZOption9", key = "logErrorHidden", inverted = true },
	{ frame = "LootZOption10", key = "logStatsEnabled", inverted = false },
	{ frame = "LootZOption11", key = "debugEnabled", inverted = false },
}

for i = 1, #checkedOptions do
	local entry = checkedOptions[i]
	local button = _G[entry.frame]

	if (button == nil) then
		check(false, entry.key .. " has a checkbox")
	else
		--The panel shows the saved value. Written long hand on purpose:
		--"a and b or c" returns c whenever b is false.
		local settingOn = (LediiData_LootZ[entry.key] == true)
		local expected = settingOn
		if (entry.inverted) then expected = not settingOn end
		check(button:GetChecked() == expected, entry.key .. " is shown correctly when the panel opens")

		--Clicking it writes the saved value back. Compared as true/false,
		--since an untouched setting is nil rather than false.
		local before = (LediiData_LootZ[entry.key] == true)
		button:SetChecked(not button:GetChecked())
		button:Click()
		check((LediiData_LootZ[entry.key] == true) ~= before, entry.key .. " changed when its checkbox was clicked")

		--And back, so the rest of the run is unaffected
		button:SetChecked(not button:GetChecked())
		button:Click()
		check((LediiData_LootZ[entry.key] == true) == before, entry.key .. " changed back")
	end
end

--Hotkey modifier cycles through the three usable keys
LediiData_LootZ["HOTKEY_MOD"] = "CTRL"
Mock.FireScript(_G.LootZOptionsModifier, "OnClick")
check(LediiData_LootZ["HOTKEY_MOD"] == "ALT", "the modifier button cycled CTRL to ALT")
Mock.FireScript(_G.LootZOptionsModifier, "OnClick")
check(LediiData_LootZ["HOTKEY_MOD"] == "SHIFT", "and ALT to SHIFT")
Mock.FireScript(_G.LootZOptionsModifier, "OnClick")
check(LediiData_LootZ["HOTKEY_MOD"] == "CTRL", "and back around to CTRL")

--Reset takes two clicks
local unitsBefore = LediiData_LootZ.units
Mock.FireScript(_G.LootZOptionsReset, "OnClick")
check(LediiData_LootZ.units == unitsBefore, "one click on reset does not wipe anything")
check(printedContains("Are you sure") or string.find(_G.LootZOptionsReset:GetText() or "", "sure"),
	"it asks for confirmation first")

Mock.FireScript(_G.LootZOptionsExport, "OnClick")
check(printedContains("SavedVariables"), "the export button explains where the data is saved")

slash("options")
check(_G.LootZOptionsPanel:IsShown() == false, "the panel closed again")

--Item under the cursor ------------------------------------------------------

section("Loot table for an item under the cursor")

_G.LEDII_DB.ItemLoot_1 = {
	["4321"] = { lootRow(2770, 0, 100.0, 0, 1, 5) },
}
_G.LEDII_DB.ProspectingLoot_1 = {
	["2770"] = { lootRow(774, 0, 50.0, 0, 1, 1) },
}

LediiData_LootZ["HOTKEY_MOD"] = "CTRL"
Mock.keys.CTRL = true
Mock.SetUnit("target", nil)

--A bag item: the game is showing its tooltip, which is what the addon reads
_G.GameTooltip.__item = "Bot Salvage"
_G.GameTooltip.__itemLink = Mock.items[4321].link
Mock.ClickMouse("LeftButton")
Mock.RunFrames(30, 0.1)

check(_G.LootZMainPanel:IsShown(), "alt/ctrl clicking an item in your bags opened the panel")
check(Mock.FindText("Bot Salvage - Contents") ~= nil, "the header names the item and where the loot comes from")
check(Mock.FindText("Copper Ore") ~= nil, "the item's loot table was rendered")

--An item with no loot of its own says so instead of opening an empty window
render = _G.LEDII_LZ_RENDER
render:OnCloseButton()
_G.GameTooltip.__item = "Linen Cloth"
_G.GameTooltip.__itemLink = Mock.items[1234].link
Mock.ClickMouse("LeftButton")
check(printedContains("No loot data for Linen Cloth"), "an item with no loot table says so")
check(_G.LootZMainPanel:IsShown() == false, "and the panel stayed closed")

--Prospecting is found when there are no contents
_G.GameTooltip.__item = "Copper Ore"
_G.GameTooltip.__itemLink = Mock.items[2770].link
Mock.ClickMouse("LeftButton")
Mock.RunFrames(30, 0.1)
check(Mock.FindText("Copper Ore - Prospecting") ~= nil, "prospecting loot is found when an item has no contents")

_G.GameTooltip.__item = nil
_G.GameTooltip.__itemLink = nil
Mock.keys.CTRL = false
render:OnCloseButton()

--Companion looting ----------------------------------------------------------

section("Companion looting (Lootbot 3000)")

--The commands run earlier left gathering switched off, which is worth checking
check(_G.LediiData_LootZ.statsGatherDisabled == true, "/lootz stats left gathering disabled")
_G.LediiData_LootZ.statsGatherDisabled = false

--Move past the grace period that follows the loot window closing above
Mock.RunFrames(20, 0.2)

local BOT_ENTRY = 4242
local BOT_GUID = "0xF130001092000001"

--A creature dies in the combat log, no loot window is ever opened
local function KillCreature(guid, name)
	Mock.FireEvent("COMBAT_LOG_EVENT_UNFILTERED",
		Mock.time, "UNIT_DIED", "0x0000000000000001", "Player", 0, guid, name, 0)
end

local function BotLoot(link, count)
	local suffix = count and ("x" .. count .. ".") or "."
	Mock.FireEvent("CHAT_MSG_LOOT", "You receive loot: " .. link .. suffix)
end

--Off by default, nothing is recorded even with a corpse targeted
BotLoot(Mock.items[4321].link, 2)
check(_G.LediiData_LootZ.units[BOT_ENTRY] == nil, "companion looting is off by default")

slash("companion")
check(_G.LediiData_LootZ.companionLootEnabled == true, "/lootz companion enabled it")

--Nothing has died and nothing is targeted: say why, and say it only once
Mock.SetUnit("target", nil)
Mock.SetUnit("mouseover", nil)
BotLoot(Mock.items[4321].link, 1)
check(printedContains("no kill has been reported at all"),
	"loot with no kills at all explains that nothing reported a death")
check(printedContains("/lootz debug"), "and it says how to report that")

BotLoot(Mock.items[4321].link, 1)
BotLoot(Mock.items[4321].link, 1)
BotLoot(Mock.items[4321].link, 1)
check(printedCount("no kill has been reported at all") == 1,
	"the warning is throttled instead of once per item")

--With no combat log deaths at all, a targeted corpse is used instead
local FALLBACK_ENTRY = 4243
Mock.SetUnit("target", {
	guid = "0xF130001093000001", name = "Sludge Beast", level = 9, dead = true, type = "Elemental",
})
BotLoot(Mock.items[4321].link, 1)
check(_G.LediiData_LootZ.units[FALLBACK_ENTRY] ~= nil,
	"a targeted corpse is used when the combat log reports nothing")
Mock.SetUnit("target", nil)

--Killing several at once, on a client whose combat log reports nothing.
--The kill text in chat is the only trace, and it only carries a name.
local AOE_ENTRY = 4245
local AOE_GUID = "0xF130001095000001"

--Seeing the creature once is what teaches the addon its id
Mock.SetUnit("mouseover", { guid = AOE_GUID, name = "Scourge Champion", dead = false, type = "Undead" })
Mock.FireEvent("UPDATE_MOUSEOVER_UNIT")
Mock.SetUnit("mouseover", nil)
check(LediiData_LootZ.names ~= nil and LediiData_LootZ.names["Scourge Champion"] == AOE_ENTRY,
	"seeing a creature remembers its name and id")

local function KillText(name)
	Mock.FireEvent("CHAT_MSG_COMBAT_XP_GAIN", name .. " dies, you gain 213 experience.")
end

--Three die in one pull, then the companion hands over three items
KillText("Scourge Champion")
KillText("Scourge Champion")
KillText("Scourge Champion")
check(LediiData_LootZ.units[AOE_ENTRY] ~= nil, "a kill reported only as chat text was recorded")
check(LediiData_LootZ.units[AOE_ENTRY].lootingCount == 3,
	"three kills in one pull counted as three samples, with no mouse involved")

BotLoot(Mock.items[774].link)
BotLoot(Mock.items[774].link)
BotLoot(Mock.items[774].link)
check(LediiData_LootZ.units[AOE_ENTRY].items[774] ~= nil, "the loot that followed was credited to them")
check(LediiData_LootZ.units[AOE_ENTRY].items[774].totalCount == 3, "all three drops were counted")
check(LediiData_LootZ.units[AOE_ENTRY].lootingCount == 3,
	"and the loot did not inflate the sample count (3 drops from 3 kills, not 1)")

--A creature the addon has never seen cannot be credited, and is not guessed at
local function countUnits()
	local count = 0
	for _ in pairs(LediiData_LootZ.units) do count = count + 1 end
	return count
end

local unitsBeforeUnknown = countUnits()
KillText("Something Never Seen")
BotLoot(Mock.items[774].link)
check(countUnits() == unitsBeforeUnknown, "an unknown creature name is skipped rather than guessed at")
check(LediiData_LootZ.units[AOE_ENTRY].lootingCount == 3,
	"and the unknown kill did not become a sample for the previous creature")
check(LediiData_LootZ.units[AOE_ENTRY].items[774].totalCount == 3,
	"loot following an unidentified kill is dropped, not credited to the wrong creature")

--Loot from a chest or a node must not land on the last creature killed
local aoeItemsBefore = LediiData_LootZ.units[AOE_ENTRY].items[2770]
_G.GameTooltip:SetOwner(_G.UIParent)
_G.GameTooltipTextLeft1:SetText("Copper Vein")
Mock.SetUnit("target", nil)
Mock.ClickMouse("RightButton")
Mock.FireEvent("LOOT_OPENED")
BotLoot(Mock.items[2770].link)
Mock.FireEvent("LOOT_CLOSED")
_G.GameTooltipTextLeft1:SetText(nil)
check(LediiData_LootZ.units[AOE_ENTRY].items[2770] == aoeItemsBefore,
	"loot from a world object was not credited to the last creature killed")

--Past the settle time again for the rest of the run
Mock.RunFrames(20, 0.2)

--At max level there is no experience message either, so the kill has to be
--seen happening. No combat log, no kill text, no mouse at loot time.
local WATCH_ENTRY = 4246
local WATCH_GUID = "0xF130001096000001"
local watchUnit = { guid = WATCH_GUID, name = "Geist Rotbringer", level = 80, dead = false, type = "Undead" }

Mock.SetUnit("target", watchUnit)
Mock.RunFrames(5, 0.2)
check(LediiData_LootZ.units[WATCH_ENTRY] == nil, "a creature that is still alive is not a kill")

watchUnit.dead = true
Mock.RunFrames(5, 0.2)
check(LediiData_LootZ.units[WATCH_ENTRY] ~= nil, "a creature seen dying counted, with no experience message")
check(LediiData_LootZ.units[WATCH_ENTRY].lootingCount == 1, "and counted exactly once")

Mock.RunFrames(10, 0.2)
check(LediiData_LootZ.units[WATCH_ENTRY].lootingCount == 1, "and stays counted once while the corpse is still there")

--The loot can turn up later, after the corpse is no longer targeted
Mock.SetUnit("target", nil)
Mock.RunFrames(5, 0.2)
BotLoot(Mock.items[774].link)
check(LediiData_LootZ.units[WATCH_ENTRY].items[774] ~= nil,
	"loot arriving after the target was cleared was still credited")

--A corpse that was already dead the first time it was seen is someone else's
Mock.SetUnit("target", {
	guid = "0xF130001096000002", name = "Geist Rotbringer", dead = true, type = "Undead",
})
Mock.RunFrames(5, 0.2)
check(LediiData_LootZ.units[WATCH_ENTRY].lootingCount == 1,
	"a corpse that was already dead when first seen was not counted")
Mock.SetUnit("target", nil)
Mock.RunFrames(2, 0.2)

check(pcall(slash, "diag"), "/lootz diag reports how kills are being detected")
check(printedContains("from seen dying"), "and it breaks the kills down by source")

--An unrecognised guid type must still count, custom cores use custom ranges
local ODD_ENTRY = 4244
KillCreature("0xF530001094000001", "Strange Thing")
BotLoot(Mock.items[4321].link, 1)
check(_G.LediiData_LootZ.units[ODD_ENTRY] ~= nil,
	"a death with an unrecognised guid type was still recorded")

KillCreature(BOT_GUID, "Rusty Construct")
BotLoot(Mock.items[4321].link, 2)
Mock.FireEvent("CHAT_MSG_MONEY", "You loot 3 Silver, 40 Copper")

local botData = _G.LediiData_LootZ.units[BOT_ENTRY]
check(botData ~= nil, "loot picked up by the companion was recorded")
check(botData ~= nil and botData.name == "Rusty Construct", "it was credited to the creature that died")
check(botData ~= nil and botData.lootingCount == 1, "the corpse counted as one looting")
check(botData ~= nil and botData.items[4321] ~= nil and botData.items[4321].totalAmount == 2,
	"the item and its stack size were recorded")
check(botData ~= nil and botData.money ~= nil and botData.money.totalAmount == 340,
	"money picked up by the companion was recorded")

--More loot from the same corpse must not count as another looting
BotLoot(Mock.items[1234].link)
check(_G.LediiData_LootZ.units[BOT_ENTRY].lootingCount == 1, "a second item from the same corpse did not count again")
check(_G.LediiData_LootZ.units[BOT_ENTRY].items[1234] ~= nil, "the second item was still recorded")

--A second corpse counts again
local BOT_GUID_2 = "0xF130001092000002"
KillCreature(BOT_GUID_2, "Rusty Construct")
BotLoot(Mock.items[4321].link, 1)
check(_G.LediiData_LootZ.units[BOT_ENTRY].lootingCount == 2, "a second corpse counted as a new looting")

--Manual looting must not be double counted through the chat message
local MANUAL_GUID = "0xF130001092000003"
Mock.SetUnit("target", { guid = MANUAL_GUID, name = "Rusty Construct", level = 5, dead = true, type = "Mechanical" })
Mock.FireEvent("PLAYER_TARGET_CHANGED")
Mock.ClickMouse("RightButton")
Mock.lootSlots = { { name = "Bot Salvage", quantity = 1, quality = 2, link = Mock.items[4321].link } }
KillCreature(MANUAL_GUID, "Rusty Construct")
Mock.FireEvent("LOOT_OPENED")
BotLoot(Mock.items[4321].link)
Mock.FireEvent("LOOT_CLOSED")
check(_G.LediiData_LootZ.units[BOT_ENTRY].lootingCount == 3, "a hand looted corpse counted exactly once")
check(_G.LediiData_LootZ.units[BOT_ENTRY].items[4321].totalCount == 3,
	"the item was counted once for the hand looted corpse, not twice")

--Once kills age out of the window the loot is ignored, and it says how old
Mock.time = Mock.time + 300
BotLoot(Mock.items[5678].link)
check(printedContains("the last kill was"), "loot older than the window is reported with the age of the last kill")
check(_G.LediiData_LootZ.units[BOT_ENTRY].items[5678] == nil, "and it was not credited to anything")

slash("companion")
check(_G.LediiData_LootZ.companionLootEnabled == false, "/lootz companion turned it back off")

--With companion looting off, watching a death must not claim the corpse, or
--the loot window would find it already counted and record nothing
local NORMAL_ENTRY = 4247
local NORMAL_GUID = "0xF130001097000001"
local normalUnit = { guid = NORMAL_GUID, name = "Plagued Ghoul", level = 80, dead = false, type = "Undead" }

Mock.SetUnit("target", normalUnit)
Mock.RunFrames(5, 0.2)
normalUnit.dead = true
Mock.RunFrames(5, 0.2)
check(LediiData_LootZ.units[NORMAL_ENTRY] == nil,
	"with companion looting off, a watched death is not counted on its own")

Mock.FireEvent("PLAYER_TARGET_CHANGED")
Mock.ClickMouse("RightButton")
Mock.lootSlots = { { name = "Linen Cloth", quantity = 1, quality = 1, link = Mock.items[1234].link } }
Mock.FireEvent("LOOT_OPENED")
Mock.RunFrames(2)
Mock.FireEvent("LOOT_CLOSED")
check(LediiData_LootZ.units[NORMAL_ENTRY] ~= nil and LediiData_LootZ.units[NORMAL_ENTRY].lootingCount == 1,
	"and the loot window still records that corpse normally")
Mock.SetUnit("target", nil)

--Shared statistics ----------------------------------------------------------

section("Shared statistics")

--Round trip the real tool: saved variables -> MergeStats.lua -> the addon.
--This is what proves the file the tool writes is the file the addon reads.
local tmpDir = os.getenv("TMPDIR") or "/tmp"
local savedVarsPath = tmpDir .. "/lootz_smoke_savedvars.lua"
local sharedPath = tmpDir .. "/lootz_smoke_shared.lua"

local savedVars = assert(io.open(savedVarsPath, "w"))
savedVars:write([[
LediiData_LootZ = {
	["units"] = {
		[4242] = {
			["name"] = "Rusty Construct",
			["lootingCount"] = 97,
			["money"] = { ["name"] = "Money", ["minAmount"] = 100, ["maxAmount"] = 900, ["totalAmount"] = 40000, ["totalCount"] = 50 },
			["items"] = {
				[4321] = { ["name"] = "Bot Salvage", ["minAmount"] = 1, ["maxAmount"] = 5, ["totalAmount"] = 200, ["totalCount"] = 90 },
				[5678] = { ["name"] = "Ornate Blade", ["minAmount"] = 1, ["maxAmount"] = 1, ["totalAmount"] = 3, ["totalCount"] = 3 },
			},
		},
	},
}
]])
savedVars:close()

local interpreter = arg[-1] or "lua5.1"
local toolStatus = os.execute(string.format(
	'%s "%s/Tools/MergeStats.lua" "%s" "%s" > /dev/null',
	interpreter, root, sharedPath, savedVarsPath))
check(toolStatus == 0 or toolStatus == true, "Tools/MergeStats.lua converted a saved variables file")

_G.LEDII_LZ_SHARED = nil
local sharedChunk = loadfile(sharedPath)
check(sharedChunk ~= nil, "the generated shared file is valid Lua")
if (sharedChunk ~= nil) then sharedChunk() end
check(_G.LEDII_LZ_SHARED ~= nil and _G.LEDII_LZ_SHARED.units[BOT_ENTRY] ~= nil,
	"the addon loads exactly what the tool wrote")

os.remove(savedVarsPath)
os.remove(sharedPath)

local utils = _G.LEDII_LZ_UTILS
utils:InvalidateStatsCache()

local merged = utils:GetTrackedUnitData(BOT_ENTRY, false)
check(merged ~= nil and merged.lootingCount == 100, "shared lootings were added to your own (97 + 3)")
check(merged ~= nil and merged.items[5678] ~= nil, "an item only present in the shared data showed up")
check(merged ~= nil and merged.items[4321].totalCount == 93, "counts for a shared item were summed")
check(merged ~= nil and merged.items[4321].maxAmount == 5, "the largest stack size across both was kept")
check(_G.LediiData_LootZ.units[BOT_ENTRY].lootingCount == 3, "merging did not touch your own saved data")

slash("shared")
local ownOnly = utils:GetTrackedUnitData(BOT_ENTRY, false)
check(ownOnly ~= nil and ownOnly.lootingCount == 3, "/lootz shared hid the shared statistics again")
slash("shared")

local okExport = pcall(slash, "export")
check(okExport, "/lootz export reported where the data is saved")
check(printedContains("SavedVariables"), "the save path was printed")

--Missing database -----------------------------------------------------------

section("Missing loot database")

_G.LEDII_DB = nil
local ok2, err2 = pcall(slash, "creature 12345")
check(ok2, "a missing database did not crash the addon" .. (ok2 and "" or (" -> " .. tostring(err2))))
Mock.RunFrames(5)
check(printedContains("does not exist"), "a missing database was reported to the player")

--Reset ----------------------------------------------------------------------

section("Reset")

local ok3, err3 = pcall(slash, "reset")
check(ok3, "/lootz reset worked" .. (ok3 and "" or (" -> " .. tostring(err3))))
check(_G.LediiData_LootZ ~= nil, "saved variables were recreated after reset")

--Summary --------------------------------------------------------------------

print("")
print(string.rep("-", 60))
if (#failures == 0) then
	print(string.format("All %d checks passed (%d files loaded, %d skipped).", checks, loaded, skipped))
	os.exit(0)
end

print(string.format("%d of %d checks FAILED:", #failures, checks))
for i = 1, #failures do
	print("  - " .. failures[i])
end
print("")
print("Last chat output:")
print(lastPrinted(10))
os.exit(1)

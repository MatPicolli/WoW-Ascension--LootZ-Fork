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
check(_G.LediiData_LootZ.units[CREATURE_ENTRY].lootingCount == before,
	"object loot was not attributed to the targeted creature")

--Object loot table by name
Mock.FireScript(_G.GameTooltip, "OnUpdate")
local ok, err = pcall(slash, "object 1731")
check(ok, "object loot table opened" .. (ok and "" or (" -> " .. tostring(err))))

_G.GameTooltipTextLeft1:SetText(nil)

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

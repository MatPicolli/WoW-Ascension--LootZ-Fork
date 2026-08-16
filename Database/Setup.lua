--print("Loaded <Database/Setup.lua>")
--[[
	The loot database lives in this folder.

	LootZ ships its loot tables as plain Lua files that fill in _G.LEDII_DB.
	They are large, and they are NOT part of this repository - see the readme
	for how to copy them in from the original addon.

	Everything keeps working without them: the addon just cannot show a
	"Data" loot table, and the statistics you gather yourself are unaffected.

	Expected shape (tables are split into numbered chunks so the client can
	load them, LootZ looks for _1 up to _100):

		_G.LEDII_DB["CreatureLoot_1"] = {
			["3561"] = {                 -- creature entry id, as a string
				{
					item = 1234,         -- item id, or 0 for a reference row
					reference = 0,        -- reference loot id, 0 for an item row
					chance = 45.0,        -- drop chance in percent
					questRequired = false,
					lootMode = 1,
					groupId = 0,          -- rows sharing a group share one chance
					minCount = 1,
					maxCount = 3,
				},
			},
		}

	Other tables follow the same pattern:
		ReferenceLoot_*      shared loot groups referenced by other tables
		GameObjectLoot_*     keyed by game object entry id
		GameObjectData_*     keyed by object NAME, rows of { entry, loot }
		GameObjectInstance_* keyed by object entry, rows of { positionX, positionY, positionZ, spawnTime }
		SkinningLoot_*, PickpocketingLoot_*, FishingLoot_*, MillingLoot_*,
		ProspectingLoot_*, DisenchantLoot_*, ItemLoot_*, MailLoot_*, SpellLoot_*
]]

--Never overwrite an already loaded database
_G.LEDII_DB = _G.LEDII_DB or {}

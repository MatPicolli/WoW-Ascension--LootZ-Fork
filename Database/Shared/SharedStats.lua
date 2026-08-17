--print("Loaded <Database/Shared/SharedStats.lua>")
--[[
	Loot statistics shared between players.

	This file is empty until somebody fills it in. Generate it from one or more
	saved statistics files with:

		lua5.1 Tools/MergeStats.lua Database/Shared/SharedStats.lua <LootZ.lua> [...]

	where <LootZ.lua> is a copy of
	WTF\Account\<ACCOUNT>\SavedVariables\LootZ.lua

	The addon merges whatever is in here with your own numbers in the Stats
	view, so downloading someone else's data never overwrites your own. Turn it
	off at any time with /lootz shared.
]]

_G.LEDII_LZ_SHARED = _G.LEDII_LZ_SHARED or {}
_G.LEDII_LZ_SHARED.units = _G.LEDII_LZ_SHARED.units or {}

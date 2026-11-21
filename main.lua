-- Stims: stim injectors for every Helldiver. The loader runs this once when the game boots.
local api = obsidian.import("obsidian.api")
local api_info = obsidian.info and obsidian.info("obsidian.api")

local API = { 1, 56, 0 }

local function api_ok(version)
	local got = {}
	for n in tostring(version or ""):gmatch("%d+") do got[#got + 1] = tonumber(n) end
	if #got == 0 then return false end
	for i, want in ipairs(API) do
		local v = got[i] or 0
		if v ~= want then return v > want end
	end
	return true
end

local export = {}

if not api or not api_ok(api_info and api_info.version) then
	obsidian.log("Stims needs Obsidian API 1.56.0 or later, found " .. tostring(api_info and api_info.version))
	return export
end

local stim = obsidian.module("src/stim")
local hud = obsidian.module("src/hud")

stim.start({
	api = api,
	log = obsidian.log,
	volume = obsidian.module("src/sound").gain(obsidian.settings.get("volume")),
	sounds = obsidian.module("src/sounds"),
	keep_regen = obsidian.settings.get("preserve_passive_healing") == true,
})
hud.start(stim.count_of, obsidian.log, stim.edge_now)

-- Other mods can read the stims of a Helldiver this machine plays or shows.
function export.count(unit)
	local S = stim.S
	for _, o in pairs(S.own) do if o.unit == unit then return o.stock.count end end
	return S.remote[unit]
end

obsidian.log("Stims ready")
return export

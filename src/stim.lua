-- The stims of every Helldiver this machine plays, the key, the boost, ammo boxes, and what the other
-- machines are told and shown.
--
-- A stim: the key starts the motion (src/anim.lua) when the Helldiver stands, walks, runs, aims or lies
-- prone (crawling, or down after a dive), or is downed when the option allow_downed_stim is on, and has
-- a stim. The sound starts with the motion, so its stab lands on the stab (SOUND_LEAD). At anim.STAB the
-- stim is spent and the boost starts: BOOST seconds of infinite stamina and HEAL hitpoints a second, up
-- to the maximum; a downed Helldiver is brought to GET_UP hitpoints first, which stands them up.
-- A knockdown, being downed, a reload, a throw, a melee or anything else outside the states in KEEP before
-- the stab cuts the motion and the sound short and keeps the stim. With none left, the key shows "Out of
-- stims!" over the Helldiver (api.ui.speech, Obsidian API 1.57.0).
--
-- Passive healing: the game heals a Helldiver 2 hitpoints a second (health_decay -2 in the Helldiver's
-- health_info; the Autoinjector perk, perk_adrenaline, makes it 12), as a negative hitpoints_decay. Unless
-- the option preserve_passive_healing is on, the base 2 is taken off the decay of an own Helldiver, so
-- only what the perk adds stays (M.regen_without_base), every frame, as respawns and perks set it again.
-- A positive decay (damage over time) is left alone, and so is Obsidian API's regen effect.
-- set_health_decay with no value gives the game's back.
--
-- Status effects: with the option status_immunity on, a Helldiver holding a boost takes no new status
-- effect but the environment slows, and the stab clears the ones on (M.blocks_status).
--
-- Health and stamina belong to the machine that plays the body, so each machine boosts only its own
-- Helldivers. The others learn the count and each stim through lobby data (src/sync.lua) and play the
-- motion and the sound from there, about a second late.
local stock = obsidian.module("src/stock")
local sync = obsidian.module("src/sync")
local anim = obsidian.module("src/anim")

local M = {}

local function g(name) return rawget(_G, name) end

M.BOOST = 4
M.HEAL = 60
M.REFRESH = 4      -- seconds after a stim takes effect before another can start: the whole boost
-- While the motion plays the Helldiver moves as when aiming: the aim speed over the jog speed of the
-- Helldiver's character_info (1.5 / 4), through the mover's velocity_scale (as Obsidian API's speed).
M.SLOW = 0.375
M.SLOW_OFF = 0.15  -- seconds before the end of the motion that the Helldiver moves freely again
-- The stab of the sound (its low thump, measured in the recording) comes SOUND_LEAD seconds after it
-- starts: the sound starts that long before anim.STAB, at once when the stab comes sooner.
M.SOUND_LEAD = 0.52
M.GET_UP = 10      -- hitpoints a downed stim stands the Helldiver up with
M.EMPTY_GAP = 2    -- seconds between two "Out of stims!"

-- How strong the screen edge is, `t` seconds after a stim took effect: up at once, a third weaker by the
-- end of the boost, then gone over EDGE_FADE. 0 when no stim (nil). Pure, for tests.
M.EDGE_RISE = 0.08
M.EDGE_FADE = 0.8
function M.edge_strength(t)
	if not t or t < 0 then return 0 end
	if t < M.EDGE_RISE then return t / M.EDGE_RISE end
	if t < M.BOOST then return 1 - 0.35 * (t / M.BOOST) end
	local k = 1 - (t - M.BOOST) / M.EDGE_FADE
	if k <= 0 then return 0 end
	return 0.65 * k * k * (3 - 2 * k)
end

-- Whether a stim can start `since` seconds after the last one took effect (nil: none yet).
function M.refreshed(since)
	return since == nil or since >= M.REFRESH
end
-- States a stim can start in, and states the motion goes on through.
-- Prone is CharacterStateCrawl, and CharacterStateDodge once the dive has landed (the game keeps it until
-- the Helldiver moves).
M.START = { CharacterStateIdle = true, CharacterStateWalk = true, CharacterStateSprint = true,
	CharacterStateAim = true, CharacterStateAimWalk = true, CharacterStateCrawl = true, CharacterStateDodge = true }
M.KEEP = { CharacterStateIdle = true, CharacterStateWalk = true, CharacterStateSprint = true,
	CharacterStateAim = true, CharacterStateAimWalk = true, CharacterStateFire = true,
	CharacterStateWalkFire = true, CharacterStateAimFire = true, CharacterStateAimWalkFire = true,
	CharacterStateCrawl = true, CharacterStateDodge = true }
M.DOWNED_START = { CharacterStateDownedIdle = true, CharacterStateDownedCrawl = true, CharacterStateDownedAim = true }
M.DOWNED_KEEP = { CharacterStateDownedIdle = true, CharacterStateDownedCrawl = true, CharacterStateDownedAim = true,
	CharacterStateDownedAimFire = true }

M.allow_downed = true

-- Whether a Helldiver in this character state, downed or not, can start a stim, or keep one going.
function M.can_start(state_name, downed)
	if downed then return M.allow_downed and M.DOWNED_START[state_name] == true end
	return M.START[state_name] == true
end
function M.can_keep(state_name, downed)
	if downed then return M.allow_downed and M.DOWNED_KEEP[state_name] == true end
	return M.KEEP[state_name] == true
end

-- Whether the motion still slows the Helldiver. Only on foot: a dive (CharacterStateDodge) keeps all of
-- its reach, and crawling and the downed states are slower than aiming already.
M.SLOWED_STATES = { CharacterStateIdle = true, CharacterStateWalk = true, CharacterStateSprint = true,
	CharacterStateAim = true, CharacterStateAimWalk = true, CharacterStateFire = true,
	CharacterStateWalkFire = true, CharacterStateAimFire = true, CharacterStateAimWalkFire = true }
function M.slows(m, state_name)
	if state_name ~= nil and not M.SLOWED_STATES[state_name] then return false end
	return not m.cut and m.t < anim.LENGTH - M.SLOW_OFF
end

-- The hitpoints a frame of boost adds: HEAL a second, never past the maximum. Pure, for tests.
function M.heal_step(hp, max, dt)
	if not (hp and max) or hp >= max then return 0 end
	return math.min(M.HEAL * dt, max - hp)
end

local S = {
	mission = nil,     -- the game state object of the mission these belong to
	own = {},          -- player record -> { unit, stock, used }
	motions = {},      -- unit -> motion (every Helldiver being shown a stim)
	pending = {},      -- unit -> record, own stims before the stab
	boosts = {},       -- unit -> seconds left
	stamina_on = {},   -- unit -> true while the boost holds the stamina
	since = {},        -- unit -> seconds since the last own stim took effect
	slowed = {},       -- unit -> true while the motion slows it
	no_regen = {},     -- unit -> true once passive healing was taken off
	remote = {},       -- unit -> stims, from other machines
	seen = {},         -- "<peer>:<id>" -> used, the last count of stims seen
	sent = nil,
	empty_at = -100,   -- clock of the last "Out of stims!"
}

local api, log, player, volume, keep_regen

local function state_of(unit)
	local ch = api.game.master(unit, "character")
	local name = ch and ch.current_state and ch.current_state.name
	local health = api.game.master(unit, "health")
	-- The health state of a downed Helldiver has no is_downed (checked in game, 2026-11-21): downed is the
	-- character's Downed states, or hitpoints at or under 0.
	local dead = (health and health.is_dead) or name == "CharacterStateDead" or false
	local downed = dead or (type(name) == "string" and name:find("^CharacterStateDowned") ~= nil)
		or (health and health.is_downed) or (health and type(health.hitpoints_real) == "number" and health.hitpoints_real <= 0) or false
	return name, downed, health, dead
end

local function go_id(st, unit)
	local storage = st and st.entity_storage
	if not storage then return nil end
	local ok, id = pcall(storage.go_id, storage, unit)
	return ok and type(id) == "number" and id or nil
end

local function unit_of_id(st, id)
	local storage = st and st.entity_storage
	if not storage then return nil end
	local ok, unit = pcall(storage.unit, storage, id)
	return ok and unit or nil
end

local function heard_from(unit)
	local mine = api.game.my_unit()
	local U = g("Unit")
	if not (mine and U.alive(mine) and U.alive(unit)) then return false end
	local a, b = U.world_position(mine, 0), U.world_position(unit, 0)
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return dx * dx + dy * dy + dz * dz <= 25 * 25
end

local function play(gain)
	if player then pcall(player.play, gain) end
end

local function stop_sound()
	if player and player.stop then pcall(player.stop) end
end

-- Shares the counts of this machine's Helldivers when they changed.
local function share(st)
	local entries = {}
	for _, o in pairs(S.own) do
		local id = go_id(st, o.unit)
		if id then entries[#entries + 1] = { id = id, count = o.stock.count, used = o.used } end
	end
	table.sort(entries, function(a, b) return a.id < b.id end)
	local text = sync.encode(st.mission_seed, entries)
	if text ~= S.sent then
		local ok = api.lobby.share(sync.NAME, text)
		if ok then S.sent = text end
	end
end

-- The mover's speed factor back to what Obsidian API's speed effect wants, or the game's.
local function unslow(unit)
	S.slowed[unit] = nil
	if not g("Unit").alive(unit) then return end
	local mover = api.game.master(unit, "mover")
	if mover then mover.velocity_scale = api.effects.get("speed") or nil end
end

local function slow(unit)
	local mover = api.game.master(unit, "mover")
	if not mover then return end
	mover.velocity_scale = (api.effects.get("speed") or 1) * M.SLOW
	S.slowed[unit] = true
end

local function reset()
	for unit in pairs(S.stamina_on) do
		if g("Unit").alive(unit) and not api.effects.is_on("infinite_stamina") then
			pcall(api.game.command, unit, "character", "infinite_stamina", false)
		end
	end
	for unit in pairs(S.slowed) do pcall(unslow, unit) end
	for unit in pairs(S.no_regen) do
		if g("Unit").alive(unit) and not api.effects.is_on("regen") then
			pcall(api.game.command, unit, "health", "set_health_decay", nil)
		end
	end
	-- Emptied in place: src/anim.lua holds S.motions.
	for _, t in ipairs({ S.own, S.motions, S.pending, S.boosts, S.stamina_on, S.remote, S.seen, S.since, S.slowed, S.no_regen }) do
		for k in pairs(t) do t[k] = nil end
	end
	S.sent = nil
end

-- The own Helldivers: a new unit for a record is a new drop or a respawn, with a fresh START.
local function refresh(st)
	local alive = {}
	for _, a in ipairs(api.game.all_avatars()) do
		if a.owned then
			alive[a.record] = true
			local o = S.own[a.record]
			if not o then
				S.own[a.record] = { unit = a.unit, stock = stock.new(), used = 0 }
			elseif o.unit ~= a.unit then
				o.unit, o.stock = a.unit, stock.new()
			end
		end
	end
	for rec in pairs(S.own) do if not alive[rec] then S.own[rec] = nil end end
end

local function record_of(unit)
	for rec, o in pairs(S.own) do if o.unit == unit then return rec, o end end
	return nil
end

-- The key: a stim for this player's Helldiver, when one can start.
function M.press()
	if not api.game.in_mission() then return end
	local unit = api.game.my_unit()
	if not unit then return end
	local _, o = record_of(unit)
	if not o or S.pending[unit] or not M.refreshed(S.since[unit]) then return end
	local name, downed, _, dead = state_of(unit)
	if dead or not M.can_start(name, downed) then return end
	if o.stock.count <= 0 then
		local now = os.clock()
		if now - S.empty_at >= M.EMPTY_GAP and api.ui.speech then
			S.empty_at = now
			api.ui.speech(unit, M.text("stims_out"), 2)
		end
		return
	end
	S.motions[unit] = { t = 0 }
	S.pending[unit] = true
end

-- Words of the mod in the game language (locales/), English when missing.
function M.text(key)
	local ok, t = pcall(obsidian.text, key)
	return ok and type(t) == "string" and t ~= key and t or "Out of stims!"
end

-- Status effects stopped while a stim lasts (option status_immunity): every element but "environment",
-- whose slows (deep water, snow, a carried objective) stay on the whole time the Helldiver is in them and
-- would be missing after the stim. StatusComponent.add_status_effect runs on the machine that plays the
-- Helldiver, the same machine that holds the boost.
M.status_immunity = true
M.IMMUNE_ELEMENTS = { "fire", "poison", "lightning", "psychic", "generic_stun", "knockdown", "physical" }
function M.blocks_status(template, boosted)
	if not (M.status_immunity and boosted) then return false end
	local T = g("StatusTemplateSettings")
	local t = type(T) == "table" and T[template]
	return type(t) == "table" and t.element ~= "environment"
end

-- Clears the status effects a stim makes the Helldiver immune to, at the stab.
local function clear_statuses(unit)
	if not M.status_immunity or not api.game.master(unit, "status") then return end
	for _, element in ipairs(M.IMMUNE_ELEMENTS) do
		pcall(api.game.command, unit, "status", "remove_statuses_by_element", element)
	end
end

local function stab(st, unit, o)
	if not stock.take(o.stock) then return end
	o.used = o.used + 1
	S.boosts[unit] = M.BOOST
	S.since[unit] = 0
	if not S.stamina_on[unit] then
		api.game.command(unit, "character", "infinite_stamina", true)
		S.stamina_on[unit] = true
	end
	local _, downed, health, dead = state_of(unit)
	if downed and not dead and health and type(health.hitpoints_real) == "number" then
		api.game.command(unit, "health", "do_heal", M.GET_UP - math.min(0, health.hitpoints_real))
	end
	clear_statuses(unit)
	share(st)
end

local function boost(dt)
	for unit, left in pairs(S.boosts) do
		local _, _, health, dead = state_of(unit)
		left = left - dt
		if left <= 0 or not g("Unit").alive(unit) then
			S.boosts[unit] = nil
			if S.stamina_on[unit] then
				if g("Unit").alive(unit) and not api.effects.is_on("infinite_stamina") then
					api.game.command(unit, "character", "infinite_stamina", false)
				end
				S.stamina_on[unit] = nil
			end
		else
			S.boosts[unit] = left
			local ch = api.game.master(unit, "character")
			local lsm = g("LuaSettingsManager")
			local settings = lsm and lsm:get_settings_by_unit(unit)
			local info = settings and settings.character_info
			if ch then ch.sprint_stamina = info and info.sprint_stamina or 5 end
			-- Downed again while the boost lasts (as when hit while getting up), the healing goes on and
			-- stands the Helldiver up again once hitpoints pass 0, as the downed stim does.
			if health and not dead then
				local step = M.heal_step(health.hitpoints_real, health.max_hitpoints, dt)
				if step > 0 then api.game.command(unit, "health", "do_heal", step) end
			end
		end
	end
end

-- The decay to set for a Helldiver whose decay is `decay` and whose health_info gives `base`: the base
-- passive healing taken off, what a perk adds on top kept (the Autoinjector perk, perk_adrenaline, sets -12
-- over the base -2, so -10 stays). nil when nothing needs setting: no healing, or `decay` is `set`, the
-- value set last. Pure, for tests.
function M.regen_without_base(decay, base, set)
	if type(decay) ~= "number" or decay >= 0 or decay == set then return nil end
	base = (type(base) == "number" and base < 0) and base or 0
	return math.min(0, decay - base)
end

-- Passive healing off for the own Helldivers (see the top).
local function no_regen()
	if api.effects.is_on("regen") then return end
	for _, o in pairs(S.own) do
		local health = api.game.master(o.unit, "health")
		local info = health and health.health_info
		local want = health and M.regen_without_base(health.hitpoints_decay, info and info.health_decay, S.no_regen[o.unit])
		if want then
			api.game.command(o.unit, "health", "set_health_decay", want)
			S.no_regen[o.unit] = want
		end
	end
end

-- Stims of the other machines' Helldivers: counts for the cards, and a motion for each new stim.
local function listen(st)
	local now = {}
	for peer, text in pairs(api.lobby.shared(sync.NAME) or {}) do
		for _, e in ipairs(sync.decode(text, st.mission_seed)) do
			local unit = unit_of_id(st, e.id)
			if unit and g("Unit").alive(unit) and not record_of(unit) then
				now[unit] = e.count
				local key = tostring(peer) .. ":" .. e.id
				local last = S.seen[key]
				S.seen[key] = e.used
				if last and e.used > last and not S.motions[unit] then
					S.motions[unit] = { t = 0, remote = true }
				end
			end
		end
	end
	S.remote = now
end

local function frame(dt)
	local st, name = api.game.state()
	if name ~= "game" or type(st) ~= "table" then
		if S.mission then reset() S.mission = nil end
		return
	end
	if S.mission ~= st then reset() S.mission = st end
	refresh(st)
	for unit, m in pairs(S.motions) do
		local before = m.t
		m.t = m.t + dt
		if not g("Unit").alive(unit) then
			S.motions[unit], S.pending[unit] = nil, nil
		else
			if not m.cut and not m.sounded and m.t >= anim.STAB - M.SOUND_LEAD then
				m.sounded = true
				if not m.remote then play(volume) elseif heard_from(unit) then play(volume * M.FAR) end
			end
			if S.pending[unit] then
				local sname, downed = state_of(unit)
				if not M.can_keep(sname, downed) then
					anim.cancel(m)
					S.pending[unit] = nil
					stop_sound()
				elseif before < anim.STAB and m.t >= anim.STAB then
					S.pending[unit] = nil
					local _, o = record_of(unit)
					if o then stab(st, unit, o) end
				end
			end
		end
		if S.motions[unit] and not anim.sample(m) then S.motions[unit] = nil end
		if S.motions[unit] and not m.remote and record_of(unit) and M.slows(m, (state_of(unit))) then slow(unit) end
	end
	for unit in pairs(S.slowed) do
		local m = S.motions[unit]
		if not (m and M.slows(m, (state_of(unit)))) then unslow(unit) end
	end
	for unit, t in pairs(S.since) do
		t = t + dt
		S.since[unit] = (t < M.BOOST + M.EDGE_FADE + M.REFRESH and g("Unit").alive(unit)) and t or nil
	end
	if not keep_regen then no_regen() end
	boost(dt)
	listen(st)
	share(st)
end

-- The stims of the player whose inventory state this is, for the card; nil when unknown.
function M.count_of(inventory)
	if type(inventory) ~= "table" then return nil end
	local masters, slaves = api.game.masters("inventory"), api.game.slaves("inventory")
	local function is(unit)
		local m, s = masters[unit], slaves[unit]
		return (m and m.state == inventory) or (s and s.state == inventory)
	end
	for _, o in pairs(S.own) do
		if is(o.unit) then return o.stock.count end
	end
	for unit, count in pairs(S.remote) do
		if is(unit) then return count end
	end
	-- A card seen before its player's numbers arrive shows a full START.
	return stock.START
end

-- How strong the screen edge of this player's Helldiver is now.
function M.edge_now()
	local unit = api and api.game.my_unit()
	return unit and M.edge_strength(S.since[unit]) or 0
end

-- An ammo box: REFILL more for the Helldiver it went to, when this machine plays it.
local function on_ammo(unit)
	local _, o = record_of(unit)
	if o and stock.add(o.stock) > 0 then
		local st = api.game.state()
		if type(st) == "table" then share(st) end
	end
end

-- Whether an ammo box may be picked up for stims alone, with every weapon full.
local function wants_stims(unit)
	local _, o = record_of(unit)
	return o ~= nil and not stock.full(o.stock)
end

function M.start(env)
	api, log = env.api, env.log
	volume = env.volume
	keep_regen = env.keep_regen
	if env.allow_downed ~= nil then M.allow_downed = env.allow_downed end
	if env.status_immunity ~= nil then M.status_immunity = env.status_immunity end
	if env.max then stock.set_max(env.max) end
	M.FAR = obsidian.module("src/sound").FAR_GAIN
	if env.sounds then
		local made, why = obsidian.module("src/sound").new(env.sounds)
		if made then
			player = made
			pcall(made.warm, volume)
			pcall(made.warm, volume * M.FAR)
		else
			log("no stim sound: " .. tostring(why))
		end
	end
	anim.start(api, S.motions, log)
	obsidian.on_frame(function()
		local ok, err = pcall(frame, rawget(_G, "ENGINE_DT") or 0.016)
		if not ok then log("stims frame: " .. tostring(err)) end
	end)
	obsidian.keybind("stim", function()
		local ok, err = pcall(M.press)
		if not ok then log("stim key: " .. tostring(err)) end
	end)
	obsidian.hook("InventoryComponent", "rpc_give_ammunition", function(original, self, sender, unit, ...)
		local out = { original(self, sender, unit, ...) }
		pcall(on_ammo, unit)
		return unpack(out)
	end)
	obsidian.hook("AmmoPickupComponent", "setup_slave", function(original, self, unit, ctx, ...)
		local out = { original(self, unit, ctx, ...) }
		local st = type(ctx) == "table" and ctx.state
		local can = st and st.can_interact
		if type(can) == "function" then
			st.can_interact = function(who, ...)
				if can(who, ...) then return true end
				local ok, yes = pcall(wants_stims, who)
				return ok and yes or false
			end
		end
		return unpack(out)
	end)
	obsidian.hook("StatusComponent", "add_status_effect", function(original, self, unit, ctx, template, ...)
		local ok, blocked = pcall(M.blocks_status, template, S.boosts[unit] ~= nil)
		if ok and blocked then return end
		return original(self, unit, ctx, template, ...)
	end)
	obsidian.on_session(function(on) if not on then reset() end end)
end

M.S = S
return M

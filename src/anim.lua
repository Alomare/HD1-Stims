-- The stim motion, in the user's drawing: the left upper arm comes out level to the side with the
-- forearm up and the fist raised, back of the hand forward (the arm at 90 degrees); the forearm folds in
-- so the fist stabs the left side of the neck, the elbow staying out; the arm goes back to the raised
-- fist, then down to the game's pose. The game has no such animation, so the bones of the left arm are set
-- on top of whatever the game plays, just before World.update_scene of the game world (the bones then
-- hold the animation of this frame; a turn set later isn't drawn, as Eyes of Liberty found for its aim
-- pose). Every machine poses every Helldiver it shows, so other players see it too (late by the lobby).
--
-- Bones (checked in game, 2026-11-21): l_shoulder -> l_elbow (0.255 m) -> l_wrist (0.281 m), each bone
-- along its local +x; the thumb root sits at local (0.049, -0.039, -0.051) of the wrist; fingers are
-- l_finger_<name><1..3>.
local P = obsidian.module("src/pose")

local M = {}

local function g(name) return rawget(_G, name) end

-- Timeline in seconds: the arm eases up to the raised fist (to RAISE), stabs in fast and even (to STAB,
-- where the stim takes effect unless the motion was cut short before), holds a moment (to RELEASE), then
-- goes from the stab straight back to the game's pose (to LENGTH).
M.RAISE = 0.40
M.STAB = 0.50
M.RELEASE = 0.62
M.LENGTH = 0.95
M.OUT = 0.18     -- blend back to the game's pose when cut short

-- Directions in the Helldiver's axes (x right, y forward, z up). The upper arm points ELBOW from the
-- shoulder when raised, ELBOW_STAB at the stab (a little forward and in, so the fist reaches the neck).
M.ELBOW = { x = -1, y = 0.12, z = -0.05 }
M.ELBOW_STAB = { x = -0.85, y = 0.4, z = -0.1 }
-- The forearm points FIST_UP when raised; at the stab it points at NECK_SIDE (metres from the neck node),
-- and the fist (FIST metres past the wrist) lands there.
M.FIST_UP = { x = 0.05, y = 0.1, z = 1 }
-- The neck node sits about 0.16 m behind the shoulders (measured 2026-11-21), so the stab lands well in
-- front of it, under the jaw, where the fist shows past the shoulder armour from the game camera.
M.NECK_SIDE = { x = -0.13, y = 0.13, z = 0.04 }
M.FIST = 0.09
M.THUMB_LOCAL = P.normalize({ x = 0, y = -0.039, z = -0.051 })
-- Fingers close into a fist: each joint turns CURL degrees about CURL_AXIS (local).
M.CURL = 75
M.CURL_AXIS = { x = 0, y = 0, z = 1 }
M.FINGERS = { "index", "middle", "ring", "pinky" }

local X = { x = 1, y = 0, z = 0 }

local function smooth(x)
	x = math.max(0, math.min(1, x))
	return x * x * (3 - 2 * x)
end

-- How far the arm is in the stim pose (0 to 1) and how far into the jab, at time t of the motion.
function M.weights(t)
	local w
	if t < M.RAISE then w = smooth(t / M.RAISE)
	elseif t < M.RELEASE then w = 1
	else w = 1 - smooth((t - M.RELEASE) / (M.LENGTH - M.RELEASE)) end
	local j = 0
	if t >= M.STAB then j = 1
	elseif t > M.RAISE then j = (t - M.RAISE) / (M.STAB - M.RAISE) end
	return w, j
end

-- A motion: { t = seconds in }, cut short with M.cancel. Answers the weights now, or nil when over.
function M.sample(m)
	if m.cut then
		local k = 1 - (m.t - m.cut) / M.OUT
		if k <= 0 then return nil end
		return m.w0 * smooth(k), 0
	end
	if m.t >= M.LENGTH then return nil end
	return M.weights(m.t)
end

function M.cancel(m)
	if m.cut then return end
	m.w0 = M.sample(m) or 0
	m.cut = m.t
end

local function axes(b, v)
	return P.add(P.add(P.scale(b.right, v.x), P.scale(b.fwd, v.y)), P.scale(b.up, v.z))
end

-- The arm in the stim pose, in plain numbers. b: world positions s, e, w (shoulder, elbow, wrist) and
-- neck; world rotations rs, re (shoulder, elbow) and rp (the shoulder's parent); the Helldiver's axes
-- right, fwd, up; hs, he: the elbow's hinge in the shoulder's and the elbow's local axes. j: the jab.
-- Answers the local rotations of the shoulder, elbow and wrist in the full pose.
function M.solve(b, j)
	local a, l = P.length(P.sub(b.e, b.s)), P.length(P.sub(b.w, b.e))
	local edir = P.normalize(P.lerp(P.normalize(axes(b, M.ELBOW)), P.normalize(axes(b, M.ELBOW_STAB)), j))
	local elbow = P.add(b.s, P.scale(edir, a))
	local target = P.add(b.neck, axes(b, M.NECK_SIDE))
	local stab = P.normalize(P.sub(target, elbow))
	local d = P.normalize(P.lerp(P.normalize(axes(b, M.FIST_UP)), stab, j))
	local wrist = P.add(elbow, P.scale(d, l))
	local hinge = P.hinge(b.s, elbow, wrist) or P.normalize(P.cross(edir, b.up))
	local rs = P.align(X, b.hs, edir, hinge)
	local re = P.align(X, b.he, d, hinge)
	-- The hand along the forearm, palm to the back: the back of the hand faces forward.
	local rw = P.align(X, M.THUMB_LOCAL, d, P.cross(d, P.scale(b.fwd, -1)))
	return P.mul(P.conj(b.rp), rs), P.mul(P.conj(rs), re), P.mul(P.conj(re), rw), wrist, P.add(wrist, P.scale(d, M.FIST))
end

-- The hinge of the arm as it stands, in the shoulder's and the elbow's local axes, or nil when the arm
-- is too straight to tell.
function M.hinges(b)
	local n = P.cross(P.sub(b.e, b.s), P.sub(b.w, b.e))
	if P.length(n) < 1e-4 then return nil end
	n = P.normalize(n)
	return P.rotate(P.conj(b.rs), n), P.rotate(P.conj(b.re), n)
end

-- Engine glue -------------------------------------------------------------------------------------------

local function vec(v) return { x = v.x, y = v.y, z = v.z } end
local function quat(Q, q)
	local x, y, z, w = Q.to_elements(q)
	return { x = x, y = y, z = z, w = w }
end
local function to_q(Q, q) return Q.from_elements(q.x, q.y, q.z, q.w) end

local hinge_cache = setmetatable({}, { __mode = "k" }) -- unit -> { hs, he }
local written = {} -- unit -> { [node] = { was, now } }

-- Every unit drawn with the Helldiver: the body pieces skinned to its bones and what is linked under it.
local function linked(api, avatar)
	local U = g("Unit")
	local list, seen = {}, { [avatar] = true }
	local function add(u)
		if u ~= nil and not seen[u] and U.alive(u) then
			seen[u] = true
			list[#list + 1] = u
			local kids = {}
			pcall(U.children, u, kids)
			for _, k in ipairs(kids) do add(k) end
		end
	end
	local slaves = api.game.slaves and api.game.slaves("customization")
	local c = slaves and slaves[avatar]
	local s = c and c.state
	if type(s) == "table" then
		for _, k in ipairs({ "body_unit", "helmet_unit", "cape_unit", "heavy_armor_unit", "all_terrain_boots_unit" }) do add(s[k]) end
	end
	local kids = {}
	pcall(U.children, avatar, kids)
	for _, k in ipairs(kids) do add(k) end
	return list
end

local function same(a, b)
	return math.abs(a.x - b.x) + math.abs(a.y - b.y) + math.abs(a.z - b.z) + math.abs(a.w - b.w) < 1e-4
end

-- Bones set last frame go back to the game's pose where they still hold the stim pose: the game leaves
-- bones as they were until it animates them again (Eyes of Liberty, 2026-11-20), so a pose set on top of
-- the last one would pile up.
function M.restore(world)
	local U, Q, W = g("Unit"), g("Quaternion"), g("World")
	for unit, nodes in pairs(written) do
		if U.alive(unit) then
			local any = false
			for i, e in pairs(nodes) do
				if same(quat(Q, U.local_rotation(unit, i)), e.now) then
					U.set_local_rotation(unit, i, to_q(Q, e.was))
					any = true
				end
			end
			if any and world then W.update_unit(world, unit) end
		end
	end
	written = {}
end

local function set_local(U, Q, unit, i, q)
	local nodes = written[unit]
	if not nodes then nodes = {} written[unit] = nodes end
	if not nodes[i] then nodes[i] = { was = quat(Q, U.local_rotation(unit, i)) } end
	nodes[i].now = q
	U.set_local_rotation(unit, i, to_q(Q, q))
end

-- Poses one Helldiver: w how far into the pose, j how far into the jab.
function M.pose(api, world, unit, w, j)
	local U, Q, W = g("Unit"), g("Quaternion"), g("World")
	if not (U.alive(unit) and U.has_node(unit, "l_wrist") and U.has_node(unit, "neck")) then return false end
	W.update_unit(world, unit)
	local si, ei, wi = U.node(unit, "l_shoulder"), U.node(unit, "l_elbow"), U.node(unit, "l_wrist")
	local pi = U.scene_graph_parent(unit, si)
	local root = U.world_rotation(unit, 0)
	local b = {
		s = vec(U.world_position(unit, si)), e = vec(U.world_position(unit, ei)), w = vec(U.world_position(unit, wi)),
		neck = vec(U.world_position(unit, U.node(unit, "neck"))),
		rs = quat(Q, U.world_rotation(unit, si)), re = quat(Q, U.world_rotation(unit, ei)),
		rp = pi and quat(Q, U.world_rotation(unit, pi)) or P.IDENTITY,
		right = vec(Q.right(root)), fwd = vec(Q.forward(root)), up = vec(Q.up(root)),
	}
	local hs, he = M.hinges(b)
	local cached = hinge_cache[unit]
	if hs then hinge_cache[unit] = { hs, he } elseif cached then hs, he = cached[1], cached[2] else hs, he = { x = 0, y = 0, z = 1 }, { x = 0, y = 0, z = 1 } end
	b.hs, b.he = hs, he
	local ls, le, lw = M.solve(b, j)
	local now_s, now_e, now_w = quat(Q, U.local_rotation(unit, si)), quat(Q, U.local_rotation(unit, ei)), quat(Q, U.local_rotation(unit, wi))
	set_local(U, Q, unit, si, P.nlerp(now_s, ls, w))
	set_local(U, Q, unit, ei, P.nlerp(now_e, le, w))
	set_local(U, Q, unit, wi, P.nlerp(now_w, lw, w))
	local curl = P.axis_angle(M.CURL_AXIS, math.rad(M.CURL) * w)
	for _, f in ipairs(M.FINGERS) do
		for k = 1, 3 do
			local name = "l_finger_" .. f .. k
			if U.has_node(unit, name) then
				local i = U.node(unit, name)
				set_local(U, Q, unit, i, P.mul(quat(Q, U.local_rotation(unit, i)), curl))
			end
		end
	end
	W.update_unit(world, unit)
	for _, u in ipairs(linked(api, unit)) do W.update_unit(world, u) end
	return true
end

-- A small blood splash at the left side of the neck of `unit`, at the stab: the game's own bullet-on-flesh
-- particle (effect_settings: bullet hits on "flesh"). Particles of a package that isn't loaded stop the
-- game, and the engine has no way to ask (no Application.can_get in this build, checked 2026-11-21). The
-- game plays this one for any bullet that hits a Helldiver, whose surface is flesh, so it is loaded in
-- every mission; it is spawned in missions only.
M.SPLASH = "effects/surface_effects/projectile_flesh"
function M.splash(unit)
	local U, Q, W = g("Unit"), g("Quaternion"), g("World")
	if not (U.alive(unit) and U.has_node(unit, "neck")) then return false end
	local world = M.game_world()
	if not world then return false end
	local root = U.world_rotation(unit, 0)
	local left = -Q.right(root)
	local pos = U.world_position(unit, U.node(unit, "neck")) + left * 0.08 + Q.forward(root) * 0.04
	return pcall(W.create_particles, world, M.SPLASH, pos, Q.look(left, Q.up(root)))
end

-- The game world, where the Helldivers are.
function M.game_world()
	local wm = g("WorldManager")
	if type(wm) ~= "table" then return nil end
	local ok, proxy = pcall(wm.get_world_proxy, wm, "game_world")
	if not ok or not proxy then return nil end
	local got, world = pcall(proxy.get_world, proxy)
	return got and world or nil
end

-- motions: unit -> motion. Runs the pose of each just before the game world's scene update.
function M.start(api, motions, log)
	local failed = false
	obsidian.hook("World", "update_scene", function(original, world, ...)
		if not failed and (next(motions) ~= nil or next(written) ~= nil) and world == M.game_world() then
			local ok, err = pcall(function()
				M.restore(world)
				for unit, m in pairs(motions) do
					local w, j = M.sample(m)
					if w and w > 0.001 then M.pose(api, world, unit, w, j) end
				end
			end)
			if not ok then
				failed = true
				log("stim motion stopped: " .. tostring(err))
			end
		end
		return original(world, ...)
	end)
end

return M

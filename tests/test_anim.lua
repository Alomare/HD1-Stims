local anim = obsidian.module("src/anim")
local P = obsidian.module("src/pose")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

test("the motion rises, jabs at the stab, and ends", function()
	local w0, j0 = anim.weights(0)
	near(w0, 0) near(j0, 0)
	local w1, j1 = anim.weights(anim.STAB)
	near(w1, 1, 1e-6, "arm up at the stab") near(j1, 1, 1e-6, "jab in at the stab")
	local w2 = anim.weights(anim.LENGTH)
	near(w2, 0, 1e-6, "back at the end")
	eq(anim.sample({ t = anim.LENGTH + 0.01 }), nil, "over")
end)

test("a motion cut short blends out from where it was", function()
	local m = { t = 0.2 }
	local w = anim.sample(m)
	anim.cancel(m)
	near((anim.sample(m)), w, 1e-6)
	m.t = 0.2 + anim.OUT / 2
	local half = anim.sample(m)
	yes(half > 0 and half < w, "fading")
	m.t = 0.2 + anim.OUT + 0.01
	eq(anim.sample(m), nil)
end)

-- A Helldiver facing +y at the origin with the left arm hanging: shoulder, elbow straight below, wrist below.
local function arm()
	local down = P.axis_angle({ x = 0, y = 1, z = 0 }, math.rad(90)) -- local +x to world -z
	-- bend the elbow a little forward so the hinge is known
	local rs = down
	local re = P.mul(P.axis_angle({ x = 1, y = 0, z = 0 }, math.rad(-20)), down)
	local s = { x = -0.2, y = 0, z = 1.6 }
	local e = P.add(s, P.rotate(rs, { x = 0.255, y = 0, z = 0 }))
	local w = P.add(e, P.rotate(re, { x = 0.281, y = 0, z = 0 }))
	return {
		s = s, e = e, w = w, neck = { x = 0, y = 0, z = 1.8 },
		rs = rs, re = re, rp = P.IDENTITY,
		right = { x = 1, y = 0, z = 0 }, fwd = { x = 0, y = 1, z = 0 }, up = { x = 0, y = 0, z = 1 },
	}
end

-- Walks the chain with the solved locals: elbow, wrist, wrist rotation.
local function walk(b, ls, le, lw)
	local rs = P.mul(b.rp, ls)
	local e = P.add(b.s, P.rotate(rs, { x = P.length(P.sub(b.e, b.s)), y = 0, z = 0 }))
	local re = P.mul(rs, le)
	local w = P.add(e, P.rotate(re, { x = P.length(P.sub(b.w, b.e)), y = 0, z = 0 }))
	return e, w, P.mul(re, lw)
end

test("raised: upper arm level out to the left, forearm up, back of the hand forward", function()
	local b = arm()
	b.hs, b.he = anim.hinges(b)
	yes(b.hs, "hinge known")
	local ls, le, lw, want = anim.solve(b, 0)
	local e, w, rw = walk(b, ls, le, lw)
	near(P.length(P.sub(w, want)), 0, 1e-3, "wrist where solved")
	yes(e.x < b.s.x - 0.2, "elbow out to the left")
	near(e.z, b.s.z, 0.03, "elbow at shoulder height")
	yes(w.z > e.z + 0.25, "forearm up")
	local palm_back = P.cross(P.rotate(rw, { x = 1, y = 0, z = 0 }), P.rotate(rw, anim.THUMB_LOCAL))
	yes(P.rotate(rw, { x = 1, y = 0, z = 0 }).z > 0.9, "hand up along the forearm")
end)

test("stab: the fist reaches the left side of the neck, the elbow still out", function()
	local b = arm()
	b.hs, b.he = anim.hinges(b)
	local ls, le, lw, _, fist = anim.solve(b, 1)
	local e, w = walk(b, ls, le, lw)
	local target = P.add(b.neck, anim.NECK_SIDE)
	yes(P.length(P.sub(fist, target)) < 0.08, "fist at the neck (" .. P.length(P.sub(fist, target)) .. " m)")
	yes(e.x < b.s.x - 0.15, "elbow still out")
	yes(w.x > e.x, "forearm folded in")
end)

return T

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

test("the solved arm puts the wrist at the neck with the hand pointing across and the thumb up", function()
	local b = arm()
	b.hs, b.he = anim.hinges(b)
	yes(b.hs, "hinge known")
	local ls, le, lw, want = anim.solve(b, 1)
	-- Walk the chain with the solved locals.
	local rs = P.mul(b.rp, ls)
	local e = P.add(b.s, P.rotate(rs, { x = P.length(P.sub(b.e, b.s)), y = 0, z = 0 }))
	local re = P.mul(rs, le)
	local w = P.add(e, P.rotate(re, { x = P.length(P.sub(b.w, b.e)), y = 0, z = 0 }))
	local rw = P.mul(re, lw)
	near(P.length(P.sub(w, want)), 0, 1e-3, "wrist reaches the target")
	local off = P.sub(w, b.neck)
	near(off.x, anim.OFF.x + anim.JAB.x, 1e-3, "left of the neck")
	near(off.y, anim.OFF.y + anim.JAB.y, 1e-3, "in front")
	local hand = P.rotate(rw, { x = 1, y = 0, z = 0 })
	yes(hand.x > 0.8, "hand points to the right, toward the neck")
	local thumb = P.rotate(rw, anim.THUMB_LOCAL)
	yes(thumb.z > 0.9, "thumb up")
	yes(e.x < b.s.x, "elbow out to the left")
end)

return T

-- Pose math in plain numbers, with no engine calls: vectors { x, y, z }, quaternions { x, y, z, w }
-- (Hamilton product, a * b turns by b first, then by a; the engine's convention), and two-bone IK.
-- From Eyes of Liberty (src/pose.lua of the firstperson branch), same author.
local M = {}

-- Vectors -------------------------------------------------------------------------------------------

function M.v(x, y, z) return { x = x, y = y, z = z } end
function M.add(a, b) return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z } end
function M.sub(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end
function M.scale(a, s) return { x = a.x * s, y = a.y * s, z = a.z * s } end
function M.dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
function M.cross(a, b)
	return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x }
end
function M.length(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function M.normalize(a, fallback)
	local l = M.length(a)
	if l < 1e-9 then return fallback or { x = 0, y = 1, z = 0 } end
	return { x = a.x / l, y = a.y / l, z = a.z / l }
end
function M.lerp(a, b, t) return { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t, z = a.z + (b.z - a.z) * t } end
-- a plus b times s
function M.mad(a, b, s) return { x = a.x + b.x * s, y = a.y + b.y * s, z = a.z + b.z * s } end

-- Quaternions ---------------------------------------------------------------------------------------

M.IDENTITY = { x = 0, y = 0, z = 0, w = 1 }

function M.q(x, y, z, w) return { x = x, y = y, z = z, w = w } end

-- A turn of angle (radians) about axis (any length).
function M.axis_angle(axis, angle)
	local a = M.normalize(axis)
	local s = math.sin(angle / 2)
	return { x = a.x * s, y = a.y * s, z = a.z * s, w = math.cos(angle / 2) }
end

function M.mul(a, b)
	return {
		x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
		y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
		z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
		w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
	}
end

function M.conj(q) return { x = -q.x, y = -q.y, z = -q.z, w = q.w } end

function M.qnormalize(q)
	local l = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
	if l < 1e-12 then return { x = 0, y = 0, z = 0, w = 1 } end
	return { x = q.x / l, y = q.y / l, z = q.z / l, w = q.w / l }
end

-- v turned by q.
function M.rotate(q, v)
	local u = { x = q.x, y = q.y, z = q.z }
	local t = M.scale(M.cross(u, v), 2)
	return M.add(M.add(v, M.scale(t, q.w)), M.cross(u, t))
end

-- The quaternion of a rotation matrix given by its columns (where it sends x, y and z).
function M.from_axes(cx, cy, cz)
	local m00, m01, m02 = cx.x, cy.x, cz.x
	local m10, m11, m12 = cx.y, cy.y, cz.y
	local m20, m21, m22 = cx.z, cy.z, cz.z
	local tr = m00 + m11 + m22
	local q
	if tr > 0 then
		local s = math.sqrt(tr + 1) * 2
		q = { w = 0.25 * s, x = (m21 - m12) / s, y = (m02 - m20) / s, z = (m10 - m01) / s }
	elseif m00 > m11 and m00 > m22 then
		local s = math.sqrt(1 + m00 - m11 - m22) * 2
		q = { w = (m21 - m12) / s, x = 0.25 * s, y = (m01 + m10) / s, z = (m02 + m20) / s }
	elseif m11 > m22 then
		local s = math.sqrt(1 + m11 - m00 - m22) * 2
		q = { w = (m02 - m20) / s, x = (m01 + m10) / s, y = 0.25 * s, z = (m12 + m21) / s }
	else
		local s = math.sqrt(1 + m22 - m00 - m11) * 2
		q = { w = (m10 - m01) / s, x = (m02 + m20) / s, y = (m12 + m21) / s, z = 0.25 * s }
	end
	return M.qnormalize(q)
end

-- The frame of a direction d and a second direction n (made square to d): columns d, n, d x n.
local function frame(d, n)
	d = M.normalize(d)
	n = M.normalize(M.sub(n, M.scale(d, M.dot(n, d))), M.normalize(M.cross(d, { x = 0, y = 0, z = 1 }), { x = 1, y = 0, z = 0 }))
	return M.from_axes(d, n, M.cross(d, n))
end

-- The turn that takes local direction d_local to world d and local n_local to world n (n is squared
-- against d first): the world rotation of a bone whose axis must point along d with its hinge along n.
function M.align(d_local, n_local, d, n)
	return M.qnormalize(M.mul(frame(d, n), M.conj(frame(d_local, n_local))))
end

-- Normalized linear blend, along the shorter way.
function M.nlerp(a, b, t)
	local d = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
	local s = d < 0 and -1 or 1
	return M.qnormalize({ x = a.x + (b.x * s - a.x) * t, y = a.y + (b.y * s - a.y) * t, z = a.z + (b.z * s - a.z) * t, w = a.w + (b.w * s - a.w) * t })
end


-- Poses (a position and a rotation) -----------------------------------------------------------------

-- child pose given in parent's space, to world
function M.compose(parent_pos, parent_rot, local_pos, local_rot)
	return M.add(parent_pos, M.rotate(parent_rot, local_pos)), M.mul(parent_rot, local_rot)
end

-- world pose, to parent's space
function M.relative(parent_pos, parent_rot, pos, rot)
	local inv = M.conj(parent_rot)
	return M.rotate(inv, M.sub(pos, parent_pos)), M.mul(inv, rot)
end

-- Two-bone IK ---------------------------------------------------------------------------------------

-- The elbow for a shoulder at s and a wrist wanted at w, upper arm a and forearm b metres long, bending
-- toward pole (a point). A wrist out of reach is pulled in to just short of a straight arm. Answers the
-- elbow and the wrist actually reached.
function M.two_bone(s, w, a, b, pole)
	local to = M.sub(w, s)
	local dist = M.length(to)
	local dir = M.normalize(to)
	local reach = math.max(math.abs(a - b) + 1e-3, math.min(a + b - 1e-3, dist))
	local wrist = M.mad(s, dir, reach)
	local p = M.sub(pole, s)
	local bend = M.normalize(M.sub(p, M.scale(dir, M.dot(p, dir))), M.normalize(M.cross(dir, { x = 0, y = 0, z = 1 })))
	local cos_a = (a * a + reach * reach - b * b) / (2 * a * reach)
	cos_a = math.max(-1, math.min(1, cos_a))
	local sin_a = math.sqrt(1 - cos_a * cos_a)
	local elbow = M.add(s, M.add(M.scale(dir, a * cos_a), M.scale(bend, a * sin_a)))
	return elbow, wrist
end

-- The hinge of a bent limb: square to both bones, the way a bend turns. nil for a straight limb.
function M.hinge(s, e, w)
	local n = M.cross(M.sub(e, s), M.sub(w, e))
	if M.length(n) < 1e-6 then return nil end
	return M.normalize(n)
end

return M

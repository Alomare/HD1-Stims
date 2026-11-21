-- How many stims a Helldiver carries: START on each drop and respawn, MAX at the most, REFILL more from
-- each ammo box. Pure, for tests.
local M = {}

M.START = 3
M.MAX = 4
M.REFILL = 2

function M.new()
	return { count = M.START }
end

-- Takes one stim: true when there was one.
function M.take(s)
	if s.count <= 0 then return false end
	s.count = s.count - 1
	return true
end

-- Adds n stims (REFILL when nil) up to MAX: how many went in.
function M.add(s, n)
	local before = s.count
	s.count = math.min(M.MAX, s.count + (n or M.REFILL))
	return s.count - before
end

function M.full(s)
	return s.count >= M.MAX
end

return M

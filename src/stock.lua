-- How many stims a Helldiver carries: MAX at the most (the option max_stims, 1 to 4), as many on each
-- drop and respawn (START), REFILL more from each ammo box. Pure, for tests.
local M = {}

M.START = 2
M.MAX = 2
M.REFILL = 2

-- The most a Helldiver carries, and starts with: 1 to 4.
function M.set_max(n)
	n = math.max(1, math.min(4, math.floor(tonumber(n) or 2)))
	M.MAX, M.START = n, n
end

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

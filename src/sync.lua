-- What each machine tells the others through lobby member data (api.lobby.share, about a second late):
-- for every Helldiver it plays, the network id of the avatar, the stims carried, and how many stims that
-- avatar has used (a number that only goes up, so a rise means a stim the other machines should show).
-- The mission seed leads, as member data outlives the mission. Pure, for tests.
--
-- Text: "<seed>;<id>:<count>:<used>;<id>:<count>:<used>..."
local M = {}

M.NAME = "s"

-- entries: list of { id, count, used }.
function M.encode(seed, entries)
	local parts = { tostring(seed or 0) }
	for _, e in ipairs(entries) do
		parts[#parts + 1] = string.format("%d:%d:%d", e.id, e.count, e.used)
	end
	return table.concat(parts, ";")
end

-- The entries of a text, or an empty list when it is for another mission or can't be read.
function M.decode(text, seed)
	local out = {}
	if type(text) ~= "string" then return out end
	local head, rest = text:match("^([^;]*);?(.*)$")
	if head ~= tostring(seed or 0) then return out end
	for id, count, used in rest:gmatch("(%d+):(%d+):(%d+)") do
		out[#out + 1] = { id = tonumber(id), count = tonumber(count), used = tonumber(used) }
	end
	return out
end

return M

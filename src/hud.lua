-- The syringe on each player's loadout card, right of the weapon: one cell per stim carried, white while
-- the player has it and grey once used, as the game draws grenades.
--
-- A gui draws only the materials it was made with, so the mod's material (res/hud.material, in the boot
-- bundle, which is always loaded) joins the list when the game makes the HUD's gui ("hud_gui", HdGui.init).
-- A gui made while the mod was off has no such material and gets no syringe: drawing a sprite a gui
-- doesn't have could stop the game.
--
-- The card calls Hud.draw_inventory every frame with the HUD's gui moved to the card (HdGui.move), so the
-- syringe is drawn there in the card's design units, with HdGui.image (the gui's immediate part).
local layout = obsidian.module("src/hud_layout")

local M = {}

local function g(name) return rawget(_G, name) end

M.MATERIAL = "stims/hud"
M.X, M.Y, M.Z = 149, 0, 4  -- bottom left corner on the card, design units (y up)
M.HEIGHT = 38              -- the syringe's height, design units
M.GREY = 128

-- The bands to draw for `count` stims: { v0, v1, y, h, lit } with v from the top of the texture and y, h
-- in design units from the syringe's bottom. Pure, for tests.
function M.bands(count, height)
	local out = {}
	local function band(v, lit)
		out[#out + 1] = { v[1], v[2], (1 - v[2]) * height, (v[2] - v[1]) * height, lit }
	end
	band(layout.top, count > 0)
	band(layout.bottom, count > 0)
	for i, v in ipairs(layout.cells) do band(v, i <= count) end
	return out
end

-- count_of(inventory_state): the stims of the card's player, or nil to draw nothing.
function M.start(count_of, log)
	local ours = setmetatable({}, { __mode = "k" }) -- HdGui objects made with the material

	obsidian.hook("HdGui", "init", function(original, self, world, name, materials, ...)
		local add = name == "hud_gui" and type(materials) == "table"
		if add then
			local copy = {}
			for i, m in ipairs(materials) do copy[i] = m end
			copy[#copy + 1] = M.MATERIAL
			materials = copy
		end
		local out = { original(self, world, name, materials, ...) }
		if add then ours[self] = true end
		return unpack(out)
	end)

	local failed = false
	obsidian.hook("Hud", "draw_inventory", function(original, self, a1, a2, a3, a4, info, inventory, ...)
		local out = { original(self, a1, a2, a3, a4, info, inventory, ...) }
		local gui = self.hd_gui
		if not failed and gui and ours[gui] and type(info) == "table" then
			local ok, err = pcall(function()
				local count = count_of(inventory)
				if not count then return end
				local V2, V3, C = g("Vector2"), g("Vector3"), g("Color")
				local a = 255 * math.max(0, math.min(1, tonumber(info.fade) or 1))
				local w = M.HEIGHT * layout.aspect
				for _, b in ipairs(M.bands(count, M.HEIGHT)) do
					local c = b[5] and 255 or M.GREY
					gui:image(layout.sprite, V3(M.X, M.Y + b[3], M.Z), V2(w, b[4]), C(a, c, c, c), V2(0, b[1]), V2(1, b[2]))
				end
			end)
			if not ok then
				failed = true
				log("syringe drawing stopped: " .. tostring(err))
			end
		end
		return unpack(out)
	end)
end

return M

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
M.X, M.Y, M.Z = 150, 4, 4  -- bottom left corner on the card, design units (y up)
M.HEIGHT = 31              -- the syringe's height, design units
-- The game's card icons are drawn white over textures about 0.78 white (198 of 255 measured on screen);
-- the syringe's texture is pure white, so it is tinted to match. Empty cells take the grenades' grey
-- (128) at the same share.
M.LIT = 198
M.GREY = 100

-- The boost's screen edge (stims_edge): light blue, drawn under the HUD on the HUD's gui.
M.EDGE_COLOR = { 120, 200, 255 }
M.EDGE_ALPHA = 215
M.EDGE_LAYER = 1

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

-- count_of(inventory_state): the stims of the card's player, or nil to draw nothing. edge_of(): how strong
-- the screen edge is now, 0 to 1.
function M.start(count_of, log, edge_of)
	local ours = setmetatable({}, { __mode = "k" }) -- HdGui objects made with the material
	local seen = { gui = nil, frame = -1 }             -- the HUD gui last seen drawing a card
	local frames = 0

	-- The edge goes on the gui of the HUD that drew a card in the last frames: a HUD gone with its mission
	-- is never drawn on.
	local edge_failed = false
	obsidian.on_frame(function()
		frames = frames + 1
		if edge_failed or not edge_of then return end
		local ok, err = pcall(function()
			local s = edge_of()
			local gui = seen.gui
			if s <= 0.004 or not gui or not ours[gui] or frames - seen.frame > 30 then return end
			local res = gui.screen_resolution
			local w, h = res and res.width, res and res.height
			if not (w and h and w > 0 and h > 0) then return end
			local V2, V3, C, c = g("Vector2"), g("Vector3"), g("Color"), M.EDGE_COLOR
			g("Gui").bitmap_uv(gui.gui, "stims_edge", V2(0, 0), V2(1, 1), V3(0, 0, M.EDGE_LAYER), V2(w, h),
				C(math.floor(M.EDGE_ALPHA * s + 0.5), c[1], c[2], c[3]))
		end)
		if not ok then
			edge_failed = true
			log("screen edge stopped: " .. tostring(err))
		end
	end)

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
		if gui and ours[gui] then seen.gui, seen.frame = gui, frames end
		if not failed and gui and ours[gui] and type(info) == "table" then
			local ok, err = pcall(function()
				local count = count_of(inventory)
				if not count then return end
				local V2, V3, C = g("Vector2"), g("Vector3"), g("Color")
				local a = 255 * math.max(0, math.min(1, tonumber(info.fade) or 1))
				local w = M.HEIGHT * layout.aspect
				for _, b in ipairs(M.bands(count, M.HEIGHT)) do
					local c = b[5] and M.LIT or M.GREY
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

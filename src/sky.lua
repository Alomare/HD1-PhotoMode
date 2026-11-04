-- A sky over the level. The game draws nothing past the level, as its camera never looks there; with
-- the Fix skies option, Obsidian adds the mod's skies to the game (tools/build_sky.py), and one of
-- them goes around the camera here: a dome 500 m across as made, scaled up and kept centred under the
-- camera so its edge never shows.
--
-- A unit the game hasn't loaded stops the game when spawned, past any pcall. The skies are only there
-- when the option was on at launch, which obsidian.settings.get answers.
local M = { prop = nil, name = nil }

M.NAMES = { "day", "dawn", "dusk", "night", "overcast" }
M.RADIUS = 1800        -- metres
M.MADE_RADIUS = 500    -- the dome's own size
M.MATERIAL = "mat_sky" -- the dome's material slot

function M.available()
	local ok, on = pcall(obsidian.settings.get, "fix_sky")
	return ok and on == true
end

function M.unit_of(name) return "photomode/sky/" .. name end

local function g(name) return rawget(_G, name) end

-- The dome's "intensity", on every material of every mesh, the way the game's MaterialAux.set_scalar
-- reaches them: Unit.mesh, then Mesh.material. Answers how many materials took it.
function M.set_brightness(value)
	local p = M.prop
	if not (p and p:alive()) then return 0 end
	local U, Mesh, Mat = g("Unit"), g("Mesh"), g("Material")
	local count = 0
	local ok, err = pcall(function()
		for i = 0, U.num_meshes(p.unit) - 1 do
			local mesh = U.mesh(p.unit, i)
			for j = 0, Mesh.num_materials(mesh) - 1 do
				Mat.set_scalar(Mesh.material(mesh, j), "intensity", value)
				count = count + 1
			end
		end
	end)
	if (not ok or count == 0) and not M.brightness_warned then
		M.brightness_warned = true
		obsidian.log("photo mode: sky brightness: " .. tostring(ok and "no materials" or err))
	end
	return count
end

-- Shows the named sky around pos, or none for nil. Answers true, or false and why not.
function M.show(api, name, pos, brightness)
	if name == nil then
		M.hide()
		return true
	end
	if not M.available() then return false, "off" end
	local known = false
	for _, n in ipairs(M.NAMES) do known = known or n == name end
	if not known then return false, "unknown" end
	if M.name == name and M.prop and M.prop:alive() then
		M.follow(pos)
		return true
	end
	M.hide()
	local prop, why = api.world.prop(M.unit_of(name), { x = pos.x, y = pos.y, z = 0 }, { scale = M.RADIUS / M.MADE_RADIUS })
	if not prop then return false, why end
	M.prop, M.name = prop, name
	M.set_brightness(brightness or 2)
	return true
end

-- Keeps the dome centred under the camera.
function M.follow(pos)
	if M.prop and M.prop:alive() then M.prop:move({ x = pos.x, y = pos.y, z = 0 }) end
end

function M.hide()
	if M.prop then pcall(M.prop.remove, M.prop) end
	M.prop, M.name = nil, nil
end

-- How far the camera has to see for the dome.
function M.far()
	return M.RADIUS + 600
end

return M

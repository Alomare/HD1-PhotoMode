-- The Helldiver's size, place and turn, the film effects and the tab icons, without the game.
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function base(yaw_deg)
	local half = math.rad(yaw_deg) / 2
	return { pos = { x = 10, y = 20, z = 1 }, rot = { 0, 0, math.sin(half), math.cos(half) }, scale = { x = 1, y = 1, z = 1 } }
end

local function state(t)
	local h = obsidian.module("src/helldiver")
	local s = {}
	for k, v in pairs(h.DEFAULTS) do s[k] = v end
	for k, v in pairs(t or {}) do s[k] = v end
	return s
end

test("the_defaults_leave_the_helldiver_where_it_stood", function()
	local h = obsidian.module("src/helldiver")
	local t = h.target(base(30), state())
	near(t.pos.x, 10)
	near(t.pos.y, 20)
	near(t.pos.z, 1)
	near(t.rot[3], math.sin(math.rad(15)))
	near(t.rot[4], math.cos(math.rad(15)))
	near(t.scale.x, 1)
end)

test("forward_and_sideways_follow_the_way_the_helldiver_faces", function()
	local h = obsidian.module("src/helldiver")
	-- Turned 90 degrees to the left, forward (+y) points along -x and the right (+x) along +y.
	local t = h.target(base(90), state({ forward = 2, side = 1, up = 0.5 }))
	near(t.pos.x, 10 - 2, "forward along -x", 1e-9)
	near(t.pos.y, 20 + 1, "the right along +y", 1e-9)
	near(t.pos.z, 1.5)
end)

test("a_turn_adds_to_the_helldivers_own_and_size_scales_every_axis", function()
	local h = obsidian.module("src/helldiver")
	local t = h.target(base(30), state({ turn = 60, scale = 2 }))
	near(t.rot[3], math.sin(math.rad(45)), "30 + 60 degrees", 1e-9)
	near(t.rot[4], math.cos(math.rad(45)), nil, 1e-9)
	near(t.scale.x, 2)
	near(t.scale.z, 2)
end)

test("moved_is_false_at_the_defaults", function()
	local h = obsidian.module("src/helldiver")
	h.reset()
	eq(h.moved(), false)
	h.set("up", 0.2)
	eq(h.moved(), true)
	h.reset()
end)

test("poses_leave_out_events_the_unit_lacks", function()
	local h = obsidian.module("src/helldiver")
	rawset(_G, "Unit", { has_animation_event = function(_, e) return e == "salute" or e == "aim" end })
	local ids = {}
	for _, p in ipairs(h.poses({})) do ids[#ids + 1] = p.id end
	eq(table.concat(ids, ","), "game,salute,aim")
	rawset(_G, "Unit", nil)
end)

test("a_pose_sends_its_event_and_asks_for_the_pose_time", function()
	local h = obsidian.module("src/helldiver")
	local sent = nil
	rawset(_G, "Unit", { animation_event = function(_, e) sent = e end })
	h.reset()
	h.unit = {}
	h.set("pose_time", 0.8)
	eq(h.pose("salute"), true)
	eq(sent, "salute")
	near(h.settle, 0.8)
	h.unit, h.settle = nil, 0
	eq(select(2, h.pose("salute")), "no_helldiver")
	rawset(_G, "Unit", nil)
end)

test("grain_scales_with_the_amount_and_the_screen", function()
	local overlay = obsidian.module("src/overlay")
	eq(overlay.grain_count(0, 1920, 1080), 0)
	eq(overlay.grain_count(1, 1920, 1080), overlay.GRAIN_MAX)
	eq(overlay.grain_count(0.5, 3840, 2160), overlay.GRAIN_MAX * 2)
end)

test("the_film_effects_draw_and_stay_off_at_zero", function()
	local overlay = obsidian.module("src/overlay")
	local rects, polys = 0, 0
	local kit = { rect = function() rects = rects + 1 end, poly = function(_, pts) polys = polys + 1 eq(#pts % 2, 0) end }
	eq(overlay.draw_flare(kit, { flare = 0, flare_at = { x = 100, y = 100 } }, 1920, 1080, 1), false)
	eq(overlay.draw_flare(kit, { flare = 1, flare_at = nil }, 1920, 1080, 1), false, "no sun in view")
	eq(overlay.draw_flare(kit, { flare = 1, flare_at = { x = 4000, y = 100 } }, 1920, 1080, 1), false, "far off screen")
	eq(overlay.draw_flare(kit, { flare = 1, flare_at = { x = 400, y = 800 } }, 1920, 1080, 1), true)
	eq(overlay.draw_leak(kit, { leak = 0.5, leak_rgb = { 1, 0.6, 0.2 } }, 1920, 1080, 1), true)
	eq(overlay.draw_grain(kit, { grain = 0.1, grain_type = "color" }, 1920, 1080, 1), 500)
	eq(polys > 0 and rects >= 500, true)
end)

-- The API draws each polygon as a fan from its first point, so each has to be convex.
local function convex(poly)
	local n, sign = #poly / 2, 0
	for i = 0, n - 1 do
		local ax, ay = poly[i * 2 + 1], poly[i * 2 + 2]
		local bx, by = poly[((i + 1) % n) * 2 + 1], poly[((i + 1) % n) * 2 + 2]
		local cx, cy = poly[((i + 2) % n) * 2 + 1], poly[((i + 2) % n) * 2 + 2]
		local cross = (bx - ax) * (cy - by) - (by - ay) * (cx - bx)
		if math.abs(cross) > 1e-9 then
			local s = cross > 0 and 1 or -1
			if sign ~= 0 and s ~= sign then return false end
			sign = s
		end
	end
	return true
end

test("every_tab_icon_is_convex_polygons_on_the_grid", function()
	local icons = obsidian.module("src/icons")
	for name in pairs(icons.GLYPH) do
		local shapes = icons[name]
		eq(type(shapes), "table", name)
		eq(#shapes > 0, true, name)
		for i, poly in ipairs(shapes) do
			eq(#poly >= 6 and #poly % 2 == 0, true, name .. " polygon " .. i)
			for j = 1, #poly do eq(poly[j] >= -0.5 and poly[j] <= 16.5, true, name .. " polygon " .. i .. " point " .. j) end
			eq(convex(poly), true, name .. " polygon " .. i .. " is convex")
		end
	end
	eq(icons.of("camera", false), "weapons", "an older API gets the glyph")
	eq(icons.of("camera", true), icons.camera)
end)

return T

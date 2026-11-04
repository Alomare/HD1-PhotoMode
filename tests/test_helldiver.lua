-- The Helldiver's size, place and turn, the film effects and the tab icons, without the game.
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function base(angle)
	return { pos = { x = 10, y = 20, z = 1 }, angle = angle, scale = { x = 1, y = 1, z = 1 } }
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
	near(t.angle, 30)
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
	near(t.angle, 90, "30 + 60 degrees", 1e-9)
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
	h.reset()
	h.unit, h.api = {}, { world = { pose = function(_, e) sent = e return true end } }
	h.set("pose_time", 0.8)
	eq(h.pose("salute"), true)
	eq(sent, "salute")
	near(h.settle, 0.8)
	h.unit, h.settle = nil, 0
	eq(select(2, h.pose("salute")), "no_helldiver")
	h.api = nil
end)

test("grain_scales_with_the_amount_and_the_screen", function()
	local overlay = obsidian.module("src/overlay")
	eq(overlay.grain_count(0, 1920, 1080), 0)
	eq(overlay.grain_count(1, 1920, 1080), overlay.GRAIN_MAX)
	eq(overlay.grain_count(0.5, 3840, 2160), overlay.GRAIN_MAX * 2)
end)

test("grain_is_in_step_with_the_amount_so_the_low_end_is_fine", function()
	local overlay = obsidian.module("src/overlay")
	local rects = 0
	local kit = { rect = function() rects = rects + 1 end }
	eq(overlay.grain_strength(0), 0)
	eq(overlay.grain_strength(0.05), 0.05, "a twentieth of the most, not a third as before")
	eq(overlay.grain_strength(1), 1)
	local specks = overlay.draw_grain(kit, { grain = 0.1, grain_type = "color" }, 1920, 1080, 1)
	eq(math.abs(specks - 900) <= 60, true, "about a tenth of the most, one per cell of an even grid")
	eq(rects, specks)
	eq(overlay.draw_flare, nil, "no lens flare")
	eq(overlay.draw_leak, nil, "no light leak")
end)

test("grain_from_the_texture_covers_the_screen_and_falls_back_to_specks", function()
	local overlay = obsidian.module("src/overlay")
	local arts, rects = {}, 0
	local kit = { art = function(_, name, x, y, w, h, c, uv) arts[#arts + 1] = { name = name, x = x, y = y, w = w, c = c, uv = uv } end,
		rect = function() rects = rects + 1 end }
	obsidian.ui.art = function(name, opts) return name == "photomode_grain" and opts.path == "photomode/grain" end
	eq(overlay.load_grain(), true)
	local n = overlay.draw_grain_art(kit, { grain = 1, grain_type = "mono", grain_size = 1 }, 1920, 1080, 1)
	eq(n, 2 * 6 * 3, "light and dark, 6 across and 3 down")
	eq(arts[1].name, "photomode_grain")
	eq(arts[1].c[1], 255, "light in white")
	eq(arts[#arts].c[1], 0, "dark in black")
	local light, dark = arts[1].uv, arts[#arts].uv
	near(dark[1] - light[1], 0.5, "the same spot of the dark tile, so the two balance")
	near(light[3] - light[1], overlay.WINDOW / overlay.GRAIN_ART.size)
	eq(light[1] >= 0 and light[3] <= 0.5 and light[2] >= 0 and light[4] <= 0.5, true, "inside the light tile")
	arts = {}
	eq(overlay.draw_grain_art(kit, { grain = 0.5, grain_type = "color", grain_size = 2 }, 1920, 1080, 1), 4 * 3 * 2, "four fields, twice as big")
	eq(overlay.draw_grain_art(kit, { grain = 0 }, 1920, 1080, 1), 0)
	-- Without the texture, the overlay draws specks.
	obsidian.ui.art = nil
	eq(overlay.load_grain(), false)
	rawset(_G, "Application", { resolution = function() return 1920, 1080 end })
	overlay.kit = { layer = function() end, rect = function() rects = rects + 1 end, poly = function() end, art = function() return false end }
	overlay.draw({ film = { grain = 0.2, grain_type = "mono" }, aspect = "screen" }, 0)
	eq(rects > 100, true, "specks")
	overlay.kit = nil
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

test("a_pose_goes_through_the_api_and_as_it_was_ends_it", function()
	local helldiver = obsidian.module("src/helldiver")
	local sent = {}
	local api = { world = { pose = function(_, e) sent[#sent + 1] = e return true end,
		end_pose = function() sent[#sent + 1] = "end" return true end } }
	helldiver.unit, helldiver.api, helldiver.settle = "unit", api, 0
	eq(helldiver.pose("radio"), true)
	eq(sent[1], "radio_activate")
	eq(helldiver.settle > 0, true, "the game runs to blend it in")
	helldiver.settle = 0
	helldiver.pose("game")
	eq(sent[2], "end", "As it was ends the pose")
	eq(helldiver.settle > 0, true, "and lets the game run to clear it")
	helldiver.unit, helldiver.api = nil, nil
end)

test("parts_hide_through_the_api_and_all_come_back", function()
	local helldiver = obsidian.module("src/helldiver")
	local calls = {}
	local api = { world = { part_visible = function(_, part, on) calls[#calls + 1] = part .. "=" .. tostring(on) return part ~= "backpack" end,
		part_units = function() return {} end } }
	helldiver.unit = "me"
	eq(helldiver.set_part(api, "armour", false), true)
	eq(calls[1], "heavy_armor=false", "the API's name for the part")
	eq(helldiver.part_shown("armour"), false)
	eq(helldiver.set_part(api, "pack", false), false, "a part the Helldiver doesn't have")
	calls = {}
	helldiver.show_parts(api)
	eq(table.concat(calls, " "), "heavy_armor=true backpack=true")
	eq(helldiver.part_shown("armour"), true)
	helldiver.unit = nil
end)

return T

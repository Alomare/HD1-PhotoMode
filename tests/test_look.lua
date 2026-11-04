local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function fake_api()
	local api = { calls = {}, shading = {}, times = {} }
	api.world = {
		shading = function(name, kind, value)
			api.calls[#api.calls + 1] = name
			api.shading[name] = value ~= nil and { kind = kind, value = value } or nil
			return true
		end,
		time_of_day = function(...) api.times[#api.times + 1] = { ... } return true end,
	}
	return api
end

test("only_what_was_changed_reaches_the_game_and_restore_gives_it_back", function()
	local look = obsidian.module("src/look")
	local api = fake_api()
	look.apply(api)
	eq(#api.calls, 0, "nothing changed, nothing sent")
	look.set("exposure", 2)
	look.apply(api)
	eq(api.shading.exposure.value, 2)
	look.apply(api)
	eq(#api.calls, 1, "the same value isn't sent again")
	look.clear("exposure")
	look.apply(api)
	eq(api.shading.exposure, nil, "a cleared value goes back to the planet")
	look.set("fog", "dense")
	look.set("time", 21)
	look.apply(api)
	eq(api.shading.fog_depth_range.value[2], 45)
	eq(api.times[1][1], "dusk")
	eq(api.times[1][2], "night")
	near(api.times[1][3], 0.5)
	look.restore(api)
	eq(api.shading.fog_depth_range, nil)
	eq(api.times[#api.times][1], nil, "the mission's own time")
	eq(look.state.fog, nil, "and the state starts fresh")
end)

test("depth_of_field_frames_the_focus", function()
	local look = obsidian.module("src/look")
	look.set("dof", true)
	look.set("depth", 4)
	local w = look.wanted(10)
	eq(w.dof_near_setting[2][1], 8)
	eq(w.dof_far_setting[2][1], 12)
	eq(w.dof_amount[2], look.DEFAULTS.blur)
end)

test("the_sun_comes_from_its_direction_and_height", function()
	local look = obsidian.module("src/look")
	look.set("sun", true)
	look.set("sun_az", 90)
	look.set("sun_height", 0.0001)
	local d = look.wanted().sun_direction[2]
	near(d[1], -1, "from the east, travelling west", 1e-3)
	near(d[3], 0, "flat", 1e-3)
	look.set("sun_height", 89.999)
	eq(look.wanted().sun_direction[2][3] < -0.99, true, "straight down from overhead")
end)

test("a_filter_sets_its_values_and_none_clears_them", function()
	local look = obsidian.module("src/look")
	look.set("glow", 3)
	eq(look.use_filter("golden"), true)
	eq(look.state.sun, true)
	eq(look.state.glow, nil, "a filter starts from the planet")
	look.use_filter("none")
	eq(look.state.sun, nil)
	eq(look.use_filter("nonsense"), false)
end)

test("hours_blend_through_the_day_and_pick_a_sky", function()
	local look = obsidian.module("src/look")
	local a, b, t = look.blend_of(9)
	eq(a, "dawn")
	eq(b, "day")
	near(t, 0.5)
	a = look.blend_of(24)
	eq(a, "night")
	eq(look.sky_of(2), "night")
	eq(look.sky_of(7), "dawn")
	eq(look.sky_of(12), "day")
	eq(look.sky_of(18), "dusk")
end)

return T

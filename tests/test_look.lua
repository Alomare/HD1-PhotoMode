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
	eq(api.shading.dof_amount.value, look.DEFAULTS.blur, "depth of field is on from the start")
	local opening = #api.calls
	look.apply(api)
	eq(#api.calls, opening, "nothing changed, nothing sent")
	look.set("exposure", 2)
	look.apply(api)
	eq(api.shading.exposure.value, 2)
	look.apply(api)
	eq(#api.calls, opening + 1, "the same value isn't sent again")
	look.clear("exposure")
	look.apply(api)
	eq(api.shading.exposure, nil, "a cleared value goes back to the planet")
	look.planet_fog = { 10, 130 }
	look.set("fog", 2)
	look.set("time", 21)
	look.apply(api)
	eq(api.shading.fog_depth_range.value[1], 5, "twice the planet's fog starts at half the distance")
	eq(api.shading.fog_depth_range.value[2], 65)
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

test("a_filter_sets_its_values_and_none_clears_them_but_leaves_the_sun_and_time", function()
	local look = obsidian.module("src/look")
	look.set("exposure", 3)
	look.set("time", 20)
	eq(look.use_filter("golden"), true)
	eq(look.state.sun, true, "golden hour sets the sun")
	eq(look.state.exposure, nil, "a filter starts from the planet")
	eq(look.state.time, 20, "the time stays")
	look.use_filter("none")
	eq(look.state.sun, true, "None leaves the sun")
	eq(look.state.sun_height, 12)
	look.clear("sun")
	look.use_filter("film")
	eq(look.state.sun, nil, "a filter without a sun doesn't add one")
	eq(look.use_filter("nonsense"), false)
end)

test("fog_is_a_thickness_of_the_planets_own", function()
	local look = obsidian.module("src/look")
	local r = look.fog_range(1, { 20, 200 })
	eq(r[1], 20) eq(r[2], 200)
	r = look.fog_range(0, { 20, 200 })
	eq(r[1], look.NO_FOG[1], "none")
	r = look.fog_range(0.5, nil)
	eq(r[2], look.FALLBACK_FOG[2] * 2, "a light haze stands in for an unknown planet fog")
	eq(look.fog_range(nil), nil)
	eq(look.wanted().fog_depth_range, nil, "untouched, the planet's fog stays")
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

test("filters_nudge_the_planets_exposure_and_bloom_by_a_little", function()
	local look = obsidian.module("src/look")
	look.reset()
	look.planet = { exposure = 1.4, bloom = 0.83 }
	for _, id in ipairs({ "cinematic", "vivid", "sunlit" }) do
		look.use_filter(id)
		local e, b = look.state.exposure, look.state.bloom
		eq(e > 1.4 and e <= 1.4 * 1.1 + 1e-9, true, id .. " exposure a step over the planet's")
		eq(b < 0.83 and b >= 0.79, true, id .. " bloom threshold a step under the planet's")
	end
	look.planet = {}
	look.use_filter("vivid")
	near(look.state.exposure, look.DEFAULTS.exposure * 1.08, "the default stands in for an unread planet")
	for _, f in ipairs(look.FILTERS) do
		for k in pairs(f.set or {}) do eq(k ~= "flare" and k ~= "leak", true, f.id .. " sets no flare or leak") end
	end
	look.reset()
end)

return T

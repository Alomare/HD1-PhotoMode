-- The look of the picture: the planet's own lighting values, changed one by one through
-- api.world.shading, the time of day, depth of field, and a color laid over everything. A value nobody
-- changed stays the planet's. Everything goes back when Photo Mode closes.
local M = {}

M.COLORS = {
	{ id = "white", label = "White", rgb = { 1, 1, 1 } },
	{ id = "warm", label = "Warm", rgb = { 1, 0.78, 0.55 } },
	{ id = "sunset", label = "Sunset", rgb = { 1, 0.5, 0.25 } },
	{ id = "amber", label = "Amber", rgb = { 1, 0.65, 0.1 } },
	{ id = "red", label = "Red", rgb = { 1, 0.28, 0.22 } },
	{ id = "violet", label = "Violet", rgb = { 0.72, 0.45, 1 } },
	{ id = "cold", label = "Cold", rgb = { 0.6, 0.75, 1 } },
	{ id = "green", label = "Green", rgb = { 0.45, 1, 0.5 } },
	{ id = "black", label = "Black", rgb = { 0, 0, 0 } },
}
for _, c in ipairs(M.COLORS) do
	c.swatch = { math.floor(c.rgb[1] * 255 + 0.5), math.floor(c.rgb[2] * 255 + 0.5), math.floor(c.rgb[3] * 255 + 0.5) }
end

function M.color(id)
	for _, c in ipairs(M.COLORS) do
		if c.id == id then return c.rgb end
	end
	return M.COLORS[1].rgb
end

-- Fog as a thickness: 1 is the planet's own (planet_fog, read when Photo Mode opens), 0 none, 2 twice
-- as thick. Where the planet's can't be read, a light haze stands in for it.
M.planet_fog = nil
M.FALLBACK_FOG = { 30, 320 }
M.NO_FOG = { 5000, 5001 }

function M.fog_range(thickness, planet)
	if not thickness then return nil end
	if thickness <= 0.001 then return { M.NO_FOG[1], M.NO_FOG[2] } end
	local base = planet or M.FALLBACK_FOG
	return { base[1] / thickness, base[2] / thickness }
end

-- The planet's own exposure and bloom threshold, read when Photo Mode opens (session.lua), for the
-- filters that nudge them. nil where they can't be read: the defaults below stand in.
M.planet = {}

-- Ready-made looks. Each sets some of the values below; any of them can be changed after. `scale`
-- multiplies the planet's value and `shift` adds to it, so a filter brightens a dark planet and a
-- bright one alike by a little.
M.FILTERS = {
	{ id = "none", label = "None" },
	{ id = "cinematic", label = "Cinematic", set = { vignette = 0.55 }, scale = { exposure = 1.04 }, shift = { bloom = -0.02 } },
	{ id = "golden", label = "Golden hour", set = { sun = true, sun_color = "warm", sun_power = 7, sun_height = 12, fog_color = "sunset", fill = 0.4, vignette = 0.4 } },
	{ id = "cold", label = "Cold front", set = { sun = true, sun_color = "cold", sun_power = 3, sun_height = 30, fog = 1.8, fog_color = "cold", fill = 0.6, grading = false } },
	{ id = "overcast", label = "Overcast", set = { sun = true, sun_color = "white", sun_power = 1.2, sun_height = 60, fog = 1.8, fog_color = "white", fill = 1.2, clouds = 0 } },
	{ id = "moonlight", label = "Moonlight", set = { time = 0, sun = true, sun_color = "cold", sun_power = 2, sun_height = 25, fill = 0.3, vignette = 0.5 } },
	{ id = "toxic", label = "Toxic", set = { fog = 1.8, fog_color = "green", fill = 0.5, tint = 0.12, tint_color = "green" } },
	{ id = "ember", label = "Ember", set = { fog = 1.8, fog_color = "red", sun = true, sun_color = "sunset", sun_power = 5, sun_height = 8, tint = 0.08, tint_color = "red" } },
	{ id = "vivid", label = "Vivid", set = { grading = true }, scale = { exposure = 1.08 }, shift = { bloom = -0.03 } },
	{ id = "film", label = "Old film", set = { grain = 0.5, grain_type = "mono", vignette = 0.7, tint = 0.06, tint_color = "warm" } },
	{ id = "sunlit", label = "Sunlit", set = { grain = 0.08, grain_type = "color" }, scale = { exposure = 1.1 }, shift = { bloom = -0.02 } },
}

-- The planet's value of a look field, or the default where it isn't known.
function M.planet_value(k)
	local v = M.planet[k]
	if v == nil then return M.DEFAULTS[k] end
	return v
end

-- Film grain: specks of grey, or of color, over the picture.
M.GRAINS = { { id = "mono", label = "Mono" }, { id = "color", label = "Color" } }

-- The values, nil while the planet's own shows.
-- What a filter changes: everything on the Look, Lens and Film tabs. The sun and the time stay as they
-- are unless a filter sets them.
local FIELDS = { "exposure", "vignette", "bloom", "clouds", "dust", "grading", "fog", "fog_color", "fill", "tint", "tint_color",
	"grain", "grain_type", "grain_size" }
M.FIELDS = FIELDS

M.DEFAULTS = { exposure = 1.5, vignette = 0.5, bloom = 0.2, clouds = 0.5, dust = 0.5, grading = true, fog = 1, fog_color = "white",
	sun = false, sun_az = 135, sun_height = 35, sun_color = "white", sun_power = 5, fill = 0.5, time = 12, tint = 0, tint_color = "warm",
	grain = 0, grain_type = "mono", grain_size = 1,
	dof = false, focus = 12, depth = 6, blur = 0.7, focus_player = true }

M.state = {}
-- Values Photo Mode itself asks for while something needs them, such as fog that reaches the sky; a
-- value the player set wins.
M.extra = {}
M.applied = {}  -- name -> { kind, value }, what reached api.world.shading
M.applied_time = nil

function M.reset()
	M.state = { dof = false, focus = 12, depth = 6, blur = 0.7, focus_player = true, filter = "none" }
end
M.reset()

function M.get(k)
	local v = M.state[k]
	if v == nil then return M.DEFAULTS[k] end
	return v
end

function M.is_set(k) return M.state[k] ~= nil end

function M.set(k, v) M.state[k] = v end

function M.clear(k) M.state[k] = nil end

function M.use_filter(id)
	for _, f in ipairs(M.FILTERS) do
		if f.id == id then
			for _, k in ipairs(FIELDS) do M.state[k] = nil end
			for k, v in pairs(f.set or {}) do M.state[k] = v end
			for k, v in pairs(f.scale or {}) do M.state[k] = M.planet_value(k) * v end
			for k, v in pairs(f.shift or {}) do M.state[k] = math.max(0, M.planet_value(k) + v) end
			M.state.filter = id
			return true
		end
	end
	return false
end

-- The hour as the game's times of day: night at 0, dawn at 6, day at 12, dusk at 18, night at 24, each
-- blended into the next. Answers from, towards and how far.
function M.blend_of(hour)
	local names = { "night", "dawn", "day", "dusk", "night" }
	hour = math.max(0, math.min(24, hour)) % 24
	local i = math.floor(hour / 6)
	return names[i + 1], names[i + 2], (hour - i * 6) / 6
end

-- Which sky fits an hour.
function M.sky_of(hour)
	if hour < 4.5 or hour >= 20.5 then return "night" end
	if hour < 8 then return "dawn" end
	if hour < 16.5 then return "day" end
	return "dusk"
end

local function scaled(rgb, s) return { rgb[1] * s, rgb[2] * s, rgb[3] * s } end

-- Toward the sun set with Sun position, as a unit vector, or nil while the planet's sun shows. any:
-- the default sun of the Light tab even while Sun position is off.
function M.sun_dir(any)
	if not M.state.sun and not any then return nil end
	local az, h = math.rad(M.get("sun_az")), math.rad(M.get("sun_height"))
	return { x = math.sin(az) * math.cos(h), y = math.cos(az) * math.cos(h), z = math.sin(h) }
end

-- What the state asks of api.world.shading, by name: { kind, value }.
function M.wanted(focus_override)
	local s, out = M.state, {}
	if s.exposure then out.exposure = { "scalar", s.exposure } end
	if s.vignette then out.vignette_opacity = { "scalar", s.vignette } end
	if s.bloom then out.bloom_threshold_offset = { "vector2", { s.bloom, M.planet.bloom_y or 0.385 } } end
	if s.clouds then out.cloud_shadow_opacity = { "scalar", s.clouds } end
	if s.dust then out.dust_opacity = { "scalar", s.dust } end
	if s.grading ~= nil then out.color_grading_enabled = { "scalar", s.grading and 1 or 0 } end
	if type(s.fog) == "number" then out.fog_depth_range = { "vector2", M.fog_range(s.fog, M.planet_fog) } end
	if s.fog_color then out.fog_color = { "vector3", scaled(M.color(s.fog_color), 0.6) } end
	if s.sun then
		local az, h = math.rad(M.get("sun_az")), math.rad(M.get("sun_height"))
		local to_sun = { math.sin(az) * math.cos(h), math.cos(az) * math.cos(h), math.sin(h) }
		out.sun_direction = { "vector3", { -to_sun[1], -to_sun[2], -to_sun[3] } }
		out.sun_color = { "vector3", scaled(M.color(M.get("sun_color")), M.get("sun_power")) }
	end
	if s.fill then
		local f = s.fill
		out.ambient_top_color = { "vector3", { f, f, f * 1.05 } }
		out.ambient_bottom_color = { "vector3", { f * 0.6, f * 0.6, f * 0.6 } }
	end
	if s.dof then
		local focus = focus_override or s.focus or M.DEFAULTS.focus
		local depth = s.depth or M.DEFAULTS.depth
		local ramp = math.max(1, depth * 0.6)
		out.dof_amount = { "scalar", s.blur or M.DEFAULTS.blur }
		out.dof_near_setting = { "vector2", { math.max(0, focus - depth / 2), ramp } }
		out.dof_far_setting = { "vector2", { focus + depth / 2, ramp } }
	end
	for name, w in pairs(M.extra) do
		if not out[name] then out[name] = w end
	end
	return out
end

local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for i = 1, math.max(#a, #b) do
		if math.abs((a[i] or 0) - (b[i] or 0)) > 1e-4 then return false end
	end
	return true
end

-- Sends what changed since the last call. focus: a focus distance worked out this frame.
function M.apply(api, focus)
	local want = M.wanted(focus)
	for name, now in pairs(M.applied) do
		if not want[name] then
			api.world.shading(name, now[1])
			M.applied[name] = nil
		end
	end
	for name, w in pairs(want) do
		local now = M.applied[name]
		if not now or not same(now[2], w[2]) then
			local ok, why = api.world.shading(name, w[1], w[2])
			if ok then M.applied[name] = w elseif not M.warned then
				M.warned = true
				obsidian.log("photo mode: " .. name .. ": " .. tostring(why))
			end
		end
	end
	local hour = M.state.time
	if hour ~= M.applied_time then
		if hour then
			local from, towards, blend = M.blend_of(hour)
			api.world.time_of_day(from, towards, blend)
		else
			api.world.time_of_day(nil)
		end
		M.applied_time = hour
	end
end

-- Gives every value back to the planet.
function M.restore(api)
	for name, now in pairs(M.applied) do pcall(api.world.shading, name, now[1]) end
	M.applied = {}
	if M.applied_time then pcall(api.world.time_of_day, nil) end
	M.applied_time = nil
	M.extra = {}
	M.reset()
end

return M

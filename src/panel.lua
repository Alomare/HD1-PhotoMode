-- The controls in tabs: api.menu.panel. Each row's help line says what the row changes.
local settings = obsidian.module("src/settings")
local camera = obsidian.module("src/camera")
local look = obsidian.module("src/look")
local lights = obsidian.module("src/lights")
local sky = obsidian.module("src/sky")
local overlay = obsidian.module("src/overlay")
local session = obsidian.module("src/session")
local icons = obsidian.module("src/icons")
local helldiver = obsidian.module("src/helldiver")

local M = {}

M.OPACITY = 0.7 -- the panel background's opacity until the player changes it

local function choices(list)
	local out = {}
	for i, c in ipairs(list) do out[i] = { id = c.id, label = c.label, swatch = c.swatch } end
	return out
end

local COLORS = choices(look.COLORS)
local FOCAL = {}
for _, mm in ipairs(camera.FOCAL_LENGTHS) do FOCAL[#FOCAL + 1] = { id = mm, label = mm .. " mm" } end

local function kept(id, extra)
	local opts = { get = function() return settings.get(id) end, set = function(v) settings.set(id, v) end, default = settings.KEPT[id] }
	for k, v in pairs(extra or {}) do opts[k] = v end
	return opts
end

-- A look value that stays the planet's until it's changed, and goes back with reset.
local function looked(k, extra)
	local opts = { get = function() return look.get(k) end, set = function(v) look.set(k, v) end,
		reset = function() look.clear(k) end, changed = function() return look.is_set(k) end }
	for key, v in pairs(extra or {}) do opts[key] = v end
	return opts
end

local function percent(v) return string.format("%d%%", v * 100 + 0.5) end

local function cam() return session.cam end

local function clock(h)
	local hours = math.floor(h) % 24
	return string.format("%02d:%02d", hours, math.floor((h - math.floor(h)) * 60 + 0.5) % 60)
end

local function camera_tab(page)
	local c = cam()
	if not c then return end
	page:choice("Mode", { choices = { { id = "free", label = "Free" }, { id = "orbit", label = "Orbit" }, { id = "isometric", label = "Isometric" } },
		get = function() return c.mode end, set = function(v) camera.set_mode(c, v) page:refresh() end, default = "free",
		help = "Free flies anywhere. Orbit circles a point, starting on the Helldiver. Isometric looks down at a fixed angle." })
	page:slider("Move speed", kept("move_speed", { min = 1, max = 40, step = 1, format = "%d m/s", help = "Camera speed for W A S D. Shift moves four times faster and Alt four times slower." }))
	page:slider("Look speed", kept("look_speed", { min = 0.2, max = 3, step = 0.1, format = "%.1f", help = "How far the camera turns when the mouse moves with the right button held, or when a pad's right stick moves." }))
	page:slider("Smoothing", kept("smoothing", { min = 0, max = 0.9, step = 0.05, format = "%.2f", help = "Delay before the camera catches up with the keys and mouse. At 0 it follows at once." }))
	page:toggle("Invert vertical look", kept("invert", { help = "Moving the mouse up turns the camera down." }))
	page:toggle("Ground collision", kept("ground", { help = "Keeps the camera above the ground." }))
	page:slider("Range", kept("range", { min = 20, max = 300, step = 10, format = function(v) return v >= 300 and "No limit" or string.format("%d m", v) end,
		help = "Farthest the camera can go from where the Helldiver stood when Photo Mode opened. Past the edge of the level only the sky is drawn." }))
	if c.mode == "orbit" then
		page:slider("Distance", { min = 1.5, max = 80, step = 0.5, format = "%.1f m", get = function() return c.distance end, set = function(v) c.distance = v end, default = 6,
			help = "Distance from the camera to the orbit point. The wheel and W S change it too." })
		page:slider("Auto orbit", { min = -60, max = 60, step = 5, format = "%d deg/s", get = function() return c.spin or 0 end, set = function(v) c.spin = v end, default = 0,
			help = "Circles the point without any input, like a turntable. 0 stops it." })
	elseif c.mode == "isometric" then
		page:choice("Projection", { choices = { { id = "telephoto", label = "Telephoto" }, { id = "orthographic", label = "Orthographic" } },
			get = function() return c.projection end, set = function(v) c.projection = v end, default = "telephoto",
			help = "Telephoto shoots from far away through a narrow lens, which looks almost flat. Orthographic removes perspective completely, and shadows and fog may change." })
		page:slider("Angle", { min = 20, max = 75, step = 0.5, format = "%.1f deg", get = function() return c.iso_angle end, set = function(v) c.iso_angle = v end, default = -camera.ISO_PITCH,
			help = "How steeply the camera looks down. A true isometric view is 35.3 degrees." })
		page:slider("Zoom", { min = 5, max = 250, step = 1, format = "%d m", get = function() return c.iso_zoom end, set = function(v) c.iso_zoom = v end, default = 30,
			help = "Height of the view in metres, from the top of the screen to the bottom. Q and E turn the view a quarter at a time." })
	end
	page:toggle("Lock camera", { get = function() return session.locked == true end, set = function(v) session.locked = v end, default = false,
		help = "Stops keys, mouse and pad from moving the camera, for setting up lights and panel values." })
	page:action("Recenter on Helldiver", function() return session.recenter() end, { help = "Moves the camera, or the orbit point, back to the Helldiver." })
end

local function lens_tab(page)
	local c = cam()
	if not c then return end
	page:choice("Focal length", { choices = FOCAL, get = function() return camera.focal_of(c.fov) end,
		set = function(mm) c.fov = camera.fov_of(mm) c.fov_before = c.fov end,
		help = "Standard lens lengths on a full-frame camera. Field of view below shows the exact angle." })
	page:slider("Field of view", { min = 10, max = 120, step = 1, format = function(v) return string.format("%d deg (%d mm)", v, camera.mm_of(v)) end, get = function() return c.fov end, set = function(v) c.fov = v c.fov_before = v end, default = 50,
		help = "Vertical angle the lens takes in. Lower values zoom in. In Free mode the wheel changes it too." })
	page:slider("Roll", { min = -45, max = 45, step = 1, format = "%d deg", get = function() return c.roll end, set = function(v) c.roll = v end, default = 0,
		help = "Tilts the picture sideways. Z and C do the same." })
	page:header("Depth of field")
	page:toggle("Depth of field", { get = function() return look.state.dof == true end, set = function(v) look.set("dof", v) page:refresh() end, default = false,
		help = "Blurs everything nearer or farther than the focus distance." })
	if look.state.dof then
		page:toggle("Autofocus on Helldiver", looked("focus_player", { help = "Keeps the Helldiver in focus as the camera moves. A double click in the picture focuses on the point under the cursor instead." }))
		if not look.get("focus_player") then
			page:slider("Focus distance", looked("focus", { min = 0.5, max = 100, step = 0.5, format = "%.1f m", help = "Distance from the camera to the sharp part of the picture." }))
		end
		page:slider("Focus range", looked("depth", { min = 0.5, max = 40, step = 0.5, format = "%.1f m", help = "Depth of the sharp zone around the focus distance." }))
		page:slider("Blur", looked("blur", { min = 0, max = 1, step = 0.05, format = "%.2f", help = "Strength of the blur outside the sharp zone." }))
	end
	page:header("Image")
	page:slider("Exposure", looked("exposure", { min = 0.2, max = 4, step = 0.05, format = "%.2f", help = "Brightness of the whole picture. R restores the planet's value." }))
	page:slider("Vignette", looked("vignette", { min = 0, max = 1, step = 0.05, format = "%.2f", help = "Darkens the corners of the picture." }))
	page:slider("Bloom threshold", looked("bloom", { min = 0, max = 1, step = 0.02, format = "%.2f", help = "Brightness a surface needs before it glows. Lower values make more of the picture glow." }))
end

local function look_tab(page)
	page:choice("Filter", { choices = choices(look.FILTERS), get = function() return look.state.filter or "none" end,
		set = function(v) look.use_filter(v) page:refresh() end, default = "none",
		help = "Preset values for the rows on this tab, the Lens tab and the Film tab, each adjustable afterwards. Golden hour, Cold front, Overcast, Moonlight and Ember also set the sun on the Light tab. None restores the planet's look and leaves the sun and time alone." })
	page:choice("Color grading", looked("grading", { choices = { { id = true, label = "On" }, { id = false, label = "Off" } },
		help = "The planet's color grading. Off shows the plain texture colors." }))
	page:choice("Color overlay", looked("tint_color", { choices = COLORS, help = "Color laid over the whole picture. Photos keep it." }))
	page:slider("Overlay strength", looked("tint", { min = 0, max = 0.6, step = 0.02, format = "%.2f", help = "Opacity of the color overlay. 0 turns it off." }))
	page:slider("Fog", looked("fog", { min = 0, max = 3, step = 0.05, format = function(v) return v <= 0 and "None" or string.format("%d%%", v * 100 + 0.5) end,
		help = "Fog thickness, where 100% is the planet's own fog and None clears it. Fog covers the sky as well." }))
	page:choice("Fog color", looked("fog_color", { choices = COLORS, help = "Color that distant parts of the level fade to." }))
	page:slider("Cloud shadows", looked("clouds", { min = 0, max = 1, step = 0.05, format = "%.2f", enabled = function() return session.supports("clouds") end, help = "Darkness of the cloud shadows moving across the ground." }))
	page:slider("Screen dust", looked("dust", { min = 0, max = 1, step = 0.05, format = "%.2f", enabled = function() return session.supports("dust") end, help = "The planet's scrolling dust layer, made for the overhead camera and drawn flat over the screen. Off when Photo Mode opens; R restores the planet's value." }))
end

local GRAINS = choices(look.GRAINS)

local function film_tab(page)
	page:header("Grain")
	page:slider("Grain", looked("grain", { min = 0, max = 1, step = 0.05, format = "%.2f", help = "Fine specks over the picture, like film or a high ISO. 0 turns them off." }))
	page:choice("Grain type", looked("grain_type", { choices = GRAINS, help = "Mono specks are light and dark grey. Color specks are red, green and blue." }))
	page:slider("Grain size", looked("grain_size", { min = 1, max = 3, step = 0.5, format = "%.1f px", help = "Size of each speck on a 1080-line screen." }))
	page:header("Lens")
	page:slider("Lens flare", looked("flare", { min = 0, max = 1, step = 0.05, format = "%.2f",
		help = "Glow, streak and rings from the sun while it's in view. Sun position on the Light tab moves it." }))
	page:slider("Light leak", looked("leak", { min = 0, max = 1, step = 0.05, format = "%.2f", help = "Light bleeding in from the left edge of the frame, as from a worn camera." }))
	page:choice("Leak color", looked("leak_color", { choices = COLORS, help = "Color of the light leak." }))
end

local function alone_only()
	return session.alone, "Only with nobody else in the lobby. A running game moves the Helldiver back."
end

local function hd(k, extra)
	local opts = { get = function() return helldiver.get(k) end, set = function(v) helldiver.set(k, v) end, default = helldiver.DEFAULTS[k], enabled = alone_only }
	for key, v in pairs(extra or {}) do opts[key] = v end
	return opts
end

local function helldiver_tab(page)
	page:choice("Visibility", { choices = { { id = "shown", label = "Shown" }, { id = "mine", label = "Hide player" }, { id = "all", label = "Hide all" } },
		get = function() return session.helldivers end, set = function(v) session.set_helldivers(v) end, default = "shown",
		help = "Hides the player's Helldiver or every Helldiver, armour and weapons included." })
	page:choice("Cape", { choices = { { id = true, label = "Shown" }, { id = false, label = "Hidden" } },
		get = function() return session.cape ~= false end, set = function(v) session.set_cape(v) end, default = true,
		help = "The cape is cloth and doesn't follow the Size, Turn or place changes below while the game is stopped. Hiding it avoids a stretched cape." })
	page:header("Pose")
	local poses = {}
	for _, p in ipairs(helldiver.poses(helldiver.unit)) do poses[#poses + 1] = { id = p.id, label = p.label } end
	page:choice("Pose", { choices = poses, get = function() return helldiver.get("pose") end,
		set = function(v) return session.set_pose(v) end, default = "game",
		help = "One of the game's Helldiver animations. The game runs for the pose time to blend it in, then stops again." })
	page:slider("Pose time", { min = 0.1, max = 3, step = 0.1, format = "%.1f s", default = helldiver.DEFAULTS.pose_time,
		get = function() return helldiver.get("pose_time") end, set = function(v) helldiver.set("pose_time", v) end,
		help = "How long the game runs after a pose is picked, which decides the moment of the animation it stops on." })
	page:action("Play pose again", function() return session.set_pose(helldiver.get("pose")) end,
		{ help = "Restarts the pose and runs it for the pose time." })
	page:header("Size and place")
	page:slider("Size", hd("scale", { min = 0.25, max = 3, step = 0.05, format = percent, help = "Size of the Helldiver, armour and weapons included." }))
	page:slider("Move sideways", hd("side", { min = -5, max = 5, step = 0.1, format = "%.1f m", help = "Moves the Helldiver right, or left below 0." }))
	page:slider("Move forward", hd("forward", { min = -5, max = 5, step = 0.1, format = "%.1f m", help = "Moves the Helldiver forward, or back below 0." }))
	page:slider("Raise", hd("up", { min = -2, max = 5, step = 0.05, format = "%.2f m", help = "Lifts the Helldiver off the ground, or sinks it below 0." }))
	page:slider("Turn", hd("turn", { min = -180, max = 180, step = 5, format = "%d deg", help = "Turns the Helldiver on the spot." }))
	page:action("Reset Helldiver", function()
		local pose_time = helldiver.get("pose_time")
		helldiver.reset()
		helldiver.set("pose_time", pose_time)
		page:refresh()
	end, { help = "Restores the size, place and turn. The pose stays." })
end

local function light_page(l)
	return function(page)
		page:choice("Color", { choices = COLORS, get = function() return l.color end, set = function(v) l.color = v lights.update(l) end, default = "warm",
			help = "Color of the light." })
		page:slider("Brightness", { min = 0, max = 20, step = 0.25, format = "%.2f", get = function() return l.intensity end, set = function(v) l.intensity = v lights.update(l) end, default = 3,
			help = "Strength of the light." })
		page:slider("Range", { min = 1, max = 60, step = 0.5, format = "%.1f m", get = function() return l.range end, set = function(v) l.range = v lights.update(l) end, default = 10,
			help = "Distance the light reaches before fading out." })
		page:choice("Shape", { choices = { { id = "point", label = "Point" }, { id = "spot", label = "Spot" } }, get = function() return l.shape end,
			set = function(v) l.shape = v lights.update(l) page:refresh() end, default = "point",
			help = "A point light shines in every direction. A spot shines in a cone, aimed where the camera looked when the light was placed." })
		if l.shape == "spot" then
			page:slider("Spot angle", { min = 10, max = 170, step = 5, format = "%d deg", get = function() return l.angle end, set = function(v) l.angle = v lights.update(l) end, default = 50,
				help = "Width of the spot's cone." })
			page:action("Aim with camera", function()
				local p = session.pose
				if p then l.yaw, l.pitch = p.yaw, p.pitch lights.update(l) end
			end, { help = "Points the spot where the camera is looking." })
		end
		page:toggle("Shadows", { get = function() return l.shadows end, set = function(v) l.shadows = v lights.update(l) end, default = true,
			help = "Lets the light cast shadows. Levels have unseen shapes that also block light; with Shadows off, the light passes through them." })
		page:action("Place at camera", function()
			local p = session.pose
			if p then lights.move(l, session.ahead(3), p.yaw, p.pitch) end
		end, { help = "Moves the light 3 m in front of the camera." })
		page:action("Remove light", function() lights.remove(l) return "Light removed" end, { help = "Deletes this light." })
	end
end

local function light_tab(page)
	page:header("Time and sun")
	page:toggle("Time override", { enabled = function() return session.supports("time") end, get = function() return look.state.time ~= nil end,
		set = function(v) if v then look.set("time", look.get("time")) else look.clear("time") end page:refresh() end, default = false,
		help = "Lights the level at a chosen hour, blending the planet's dawn, day, dusk and night. Off shows the mission's own time." })
	if look.state.time then
		page:slider("Time of day", { enabled = function() return session.supports("time") end, min = 0, max = 24, step = 0.25, format = clock, get = function() return look.get("time") end, set = function(v) look.set("time", v) end,
			help = "Night at 0:00, dawn at 6:00, day at 12:00, dusk at 18:00." })
	end
	page:toggle("Sun position", { get = function() return look.state.sun == true end, set = function(v) if v then look.set("sun", true) else look.clear("sun") end page:refresh() end,
		default = false, help = "Replaces the planet's sunlight with the direction, height, color and brightness below." })
	if look.state.sun then
		page:slider("Sun direction", looked("sun_az", { min = 0, max = 355, step = 5, format = "%d deg", help = "Compass direction the sunlight comes from. Shadows turn with it." }))
		page:slider("Sun height", looked("sun_height", { min = 2, max = 89, step = 1, format = "%d deg", help = "Height of the sun above the horizon. A low sun throws long shadows." }))
		page:choice("Sun color", looked("sun_color", { choices = COLORS, help = "Color of the sunlight." }))
		page:slider("Sun brightness", looked("sun_power", { min = 0, max = 20, step = 0.25, format = "%.2f", help = "Strength of the sunlight." }))
	end
	page:slider("Shadow fill", looked("fill", { min = 0, max = 3, step = 0.05, format = "%.2f", help = "Light that reaches the shaded areas." }))
	page:toggle("Helldiver flashlight", { get = function() return session.flashlight end, set = function(v) session.set_flashlight(v) end, default = false,
		help = "Turns on the Helldiver's flashlight, as on night missions." })
	page:header("Lights")
	page:action("Add light", function()
		local p = session.pose
		if not p then return end
		local l, why = lights.add(session.api, session.ahead(3), p.yaw, p.pitch)
		if not l then return why == "full" and ("At most " .. lights.MAX .. " lights.") or "The light couldn't be placed here." end
		page:refresh()
		return "Light added"
	end, { enabled = function() return session.supports("lights") end, help = "Places a light 3 m in front of the camera, shown as a marker. Click a marker to select the light, then drag the colored handles to move it." })
	page:action("Three-point lighting", function()
		local at, p = session.chest(), session.pose
		if not (at and p) then return "No Helldiver to light." end
		local made = lights.rig(session.api, at, p.yaw)
		page:refresh()
		return made > 0 and (made .. " lights added") or "No room for more lights."
	end, { enabled = function() return session.supports("lights") end, help = "Adds a key light, a fill light and a rim light around the Helldiver, aimed at it from the camera's side." })
	for _, l in ipairs(lights.list) do
		page:page(function() return lights.name_of(l) end, light_page(l), { help = "Color, brightness, range, shape and shadows of this light." })
	end
	if #lights.list > 0 then
		page:action("Remove all lights", function() lights.clear() page:refresh() end, { help = "Deletes every placed light." })
	end
end

local TIMES = { { id = 0, label = "Paused" }, { id = 0.1, label = "0.1x" }, { id = 0.25, label = "0.25x" }, { id = 0.5, label = "0.5x" }, { id = 1, label = "Normal" } }

local function scene_tab(page)
	page:choice("Time", { choices = TIMES, get = function() return session.api.world.time_now() end,
		set = function(v)
			if session.api.world.time_scale(v) then settings.set("time", v) end
		end, default = 0,
		enabled = function() return session.alone, "Only with nobody else in the lobby." end,
		help = "Pauses the game, slows it down or lets it run. With other players in the lobby the game keeps running." })
	local sky_off = "Turn on Fix skies in Photo Mode's options in Obsidian, then restart the game."
	local function sky_ok()
		local ok, why = session.supports("sky")
		if not ok then return false, why end
		return sky.available(), sky_off
	end
	page:choice("Sky", { choices = { { id = "off", label = "Off" }, { id = "auto", label = "Matches the time" }, { id = "day", label = "Day" },
		{ id = "dawn", label = "Dawn" }, { id = "dusk", label = "Dusk" }, { id = "night", label = "Night" }, { id = "overcast", label = "Overcast" } },
		get = function() return session.sky end, set = function(v) session.sky = v end, default = "auto", enabled = sky_ok,
		help = "A sky beyond the edge of the level, where the game draws nothing: clouds by day, stars by night. Fog hides it; lower Fog on the Look tab to see more." })
	page:slider("Sky brightness", { min = 0, max = 4, step = 0.1, format = "%.1f", get = function() return session.sky_brightness end,
		set = function(v) session.sky_brightness = v sky.set_brightness(v) end, default = session.SKY_BRIGHTNESS, enabled = sky_ok,
		help = "Brightness of the sky." })
end

local function frame_tab(page)
	page:choice("Aspect ratio", kept("aspect", { choices = choices(overlay.ASPECTS), help = "Shape of the picture, outlined on the screen." }))
	page:toggle("Letterbox bars", kept("bars", { help = "On keeps the full screen size with black bars around the frame. Off crops the photo to the frame." }))
	page:choice("Grid", kept("grid", { choices = choices(overlay.GRIDS), help = "Composition lines, left out of photos." }))
	page:input(function() return session.caption ~= "" and ("Caption: " .. session.caption) or "Caption" end,
		function(text) session.caption = text end, { help = "Text written on the picture in the game's title font." })
	page:choice("Caption position", { choices = choices(overlay.CAPTION_PLACES), get = function() return session.caption_place end,
		set = function(v) session.caption_place = v end, default = "bottom_left", help = "Where the caption sits in the frame." })
	page:slider("Caption size", { min = 20, max = 120, step = 2, format = "%d", get = function() return session.caption_size end,
		set = function(v) session.caption_size = v end, default = 40, help = "Height of the caption letters." })
	page:action("Clear caption", function() session.caption = "" end, { help = "Removes the caption." })
end

local function export_tab(page)
	page:action("Take photo", function() session.take_picture() end, { help = "Saves the picture without the panel and markers. P does the same." })
	page:choice("Format", kept("format", { choices = { { id = "png", label = "PNG" }, { id = "jpg", label = "JPEG" } },
		help = "PNG keeps every pixel exactly. JPEG makes smaller files." }))
	page:slider("JPEG quality", kept("quality", { min = 50, max = 100, step = 1, format = "%d", help = "Higher values keep more detail and make larger files." }))
	page:label(function()
		local folder = session.folder()
		return folder and ("Saved in " .. folder) or "Pictures can't be saved in this game."
	end)
	page:action("Open photo folder", function()
		local folder = session.folder()
		if not folder then return "The folder isn't available." end
		session.api.capture.open_folder(folder)
	end, { help = "Opens the photo folder in File Explorer." })
end

local function settings_tab(page)
	page:toggle("Music", kept("music", { help = "Plays the mission's exploration music a few seconds after Photo Mode opens. On the ship, the ship's music returns instead." }))
	page:toggle("Controls overlay", kept("guide", { help = "The camera keys at the bottom left. Left out of photos." }))
	page:header("Panel")
	local function panel_call(name, ...)
		local p = M.panel
		if p and type(p[name]) == "function" then return p[name](p, ...) end
	end
	page:slider("Panel opacity", { min = 0.1, max = 1, step = 0.05, format = percent,
		get = function() return panel_call("opacity") or M.OPACITY end, set = function(v) panel_call("set_opacity", v) end, default = M.OPACITY,
		help = "Opacity of the panel background. Rows and text stay solid." })
	page:slider("Panel scale", { min = 0.6, max = 1.6, step = 0.05, format = percent,
		get = function() return panel_call("scale") or 1 end, set = function(v) panel_call("set_scale", v) end, default = 1,
		help = "Size of the panel and everything in it. The title bar moves the panel and the corner grip resizes it." })
	page:action("Reset panel position", function() panel_call("reset_place") end,
		{ help = "Returns the panel to the bottom right corner at the default size." })
end

-- Every setting back to the default, from the button in the panel's title bar. Lights stay.
function M.reset_all()
	settings.reset()
	look.reset()
	look.set("dust", 0)
	session.caption, session.caption_place, session.caption_size = "", "bottom_left", 40
	session.sky, session.sky_brightness = session.default_sky(), session.SKY_BRIGHTNESS
	sky.set_brightness(session.SKY_BRIGHTNESS)
	helldiver.reset()
	if M.panel then M.panel:refresh() end
	return "All settings reset"
end

-- Tab icons drawn from shapes (src/icons.lua) where the API draws them (1.27.0, which also brought
-- api.world.sun), else the nearest of obsidian.ui's glyphs. The tab's name shows over the help lines.
function M.make(api)
	local shapes = api.world.sun ~= nil
	local function icon(name) return icons.of(name, shapes) end
	M.panel = api.menu.panel({
		id = "photo",
		title = "Photo Mode",
		opacity = M.OPACITY,
		status = session.status,
		guide = { { keys = { "P" }, label = "Take photo" }, { keys = { "H" }, label = "Hide" } },
		buttons = { { glyph = "reset", help = "Resets every setting to the default. Placed lights stay.", run = M.reset_all } },
		on_close = function() session.stop() end,
		tabs = {
			{ title = "Camera", icon = icon("camera"), build = camera_tab },
			{ title = "Lens", icon = icon("lens"), build = lens_tab },
			{ title = "Look", icon = icon("look"), build = look_tab },
			{ title = "Film", icon = icon("film"), build = film_tab },
			{ title = "Light", icon = icon("light"), build = light_tab },
			{ title = "Scene", icon = icon("scene"), build = scene_tab },
			{ title = "Helldiver", icon = icon("helldiver"), build = helldiver_tab },
			{ title = "Frame", icon = icon("frame"), build = frame_tab },
			{ title = "Export", icon = icon("save"), build = export_tab },
			{ title = "Settings", icon = icon("settings"), build = settings_tab },
		},
	})
	return M.panel
end

return M

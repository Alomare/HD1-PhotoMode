-- The controls, down the right of the screen in tabs: api.menu.panel. Each row says what it changes in
-- its help line.
local settings = obsidian.module("src/settings")
local camera = obsidian.module("src/camera")
local look = obsidian.module("src/look")
local lights = obsidian.module("src/lights")
local sky = obsidian.module("src/sky")
local overlay = obsidian.module("src/overlay")
local session = obsidian.module("src/session")

local M = {}

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
		help = "Free flies anywhere. Orbit circles a point, the Helldiver at first. Isometric looks down at a fixed angle, without perspective." })
	page:slider("Move speed", kept("move_speed", { min = 1, max = 40, step = 1, format = "%d m/s", help = "How fast W A S D move the camera. Shift is four times faster, Alt four times slower." }))
	page:slider("Look speed", kept("look_speed", { min = 0.2, max = 3, step = 0.1, format = "%.1f", help = "How far the camera turns for a move of the mouse with the right button held, or of a pad's right stick." }))
	page:slider("Smoothing", kept("smoothing", { min = 0, max = 0.9, step = 0.05, format = "%.2f", help = "How long the camera takes to catch up with the keys and the mouse. 0 follows at once." }))
	page:toggle("Invert vertical look", kept("invert", { help = "Moving the mouse up looks down." }))
	page:toggle("Ground collision", kept("ground", { help = "Holds the camera above the ground." }))
	page:slider("Range", kept("range", { min = 20, max = 300, step = 10, format = function(v) return v >= 300 and "No limit" or string.format("%d m", v) end,
		help = "How far the camera can go from where the Helldiver stood when Photo Mode opened. Past the level, nothing is drawn but the sky." }))
	if c.mode == "orbit" then
		page:slider("Distance", { min = 1.5, max = 80, step = 0.5, format = "%.1f m", get = function() return c.distance end, set = function(v) c.distance = v end, default = 6,
			help = "How far the camera stays from the point it circles. The wheel and W S change it too." })
		page:slider("Auto orbit", { min = -60, max = 60, step = 5, format = "%d deg/s", get = function() return c.spin or 0 end, set = function(v) c.spin = v end, default = 0,
			help = "Orbit speed without input, for a turntable view. 0 stops it." })
	elseif c.mode == "isometric" then
		page:choice("Projection", { choices = { { id = "telephoto", label = "Telephoto" }, { id = "orthographic", label = "Orthographic" } },
			get = function() return c.projection end, set = function(v) c.projection = v end, default = "telephoto",
			help = "Telephoto looks from far away with a narrow lens, nearly flat. Orthographic draws with no perspective at all; shadows and fog may look different." })
		page:slider("Angle", { min = 20, max = 75, step = 0.5, format = "%.1f deg", get = function() return c.iso_angle end, set = function(v) c.iso_angle = v end, default = -camera.ISO_PITCH,
			help = "How steeply the view looks down. 35.3 degrees is a true isometric view." })
		page:slider("Zoom", { min = 5, max = 250, step = 1, format = "%d m", get = function() return c.iso_zoom end, set = function(v) c.iso_zoom = v end, default = 30,
			help = "How much of the level fits from the top of the screen to the bottom. Q and E turn the view by a quarter." })
	end
	page:toggle("Lock camera", { get = function() return session.locked == true end, set = function(v) session.locked = v end, default = false,
		help = "Keys, mouse and pad leave the camera where it is, for work on lights and the panel." })
	page:action("Recenter on Helldiver", function() return session.recenter() end, { help = "Puts the camera, or the orbit point, next to the Helldiver." })
end

local function lens_tab(page)
	local c = cam()
	if not c then return end
	page:choice("Focal length", { choices = FOCAL, get = function() return camera.focal_of(c.fov) end,
		set = function(mm) c.fov = camera.fov_of(mm) c.fov_before = c.fov end,
		help = "Common lens lengths, for a full-frame camera. The field of view below shows the exact angle." })
	page:slider("Field of view", { min = 10, max = 120, step = 1, format = function(v) return string.format("%d deg (%d mm)", v, camera.mm_of(v)) end, get = function() return c.fov end, set = function(v) c.fov = v c.fov_before = v end, default = 50,
		help = "How wide the lens sees, from the top of the screen to the bottom. Low values zoom in. The wheel changes it in Free mode." })
	page:slider("Roll", { min = -45, max = 45, step = 1, format = "%d deg", get = function() return c.roll end, set = function(v) c.roll = v end, default = 0,
		help = "Tips the picture to one side. Z and C roll it too." })
	page:header("Depth of field")
	page:toggle("Depth of field", { get = function() return look.state.dof == true end, set = function(v) look.set("dof", v) page:refresh() end, default = false,
		help = "Blurs what's nearer and farther than the focus." })
	if look.state.dof then
		page:toggle("Autofocus on Helldiver", looked("focus_player", { help = "Focus distance follows the Helldiver as the camera moves. A double click in the picture focuses on the point under the cursor." }))
		if not look.get("focus_player") then
			page:slider("Focus distance", looked("focus", { min = 0.5, max = 100, step = 0.5, format = "%.1f m", help = "How far from the camera the picture is sharp." }))
		end
		page:slider("Focus range", looked("depth", { min = 0.5, max = 40, step = 0.5, format = "%.1f m", help = "Depth of the sharp zone around the focus distance." }))
		page:slider("Blur", looked("blur", { min = 0, max = 1, step = 0.05, format = "%.2f", help = "How strong the blur is outside the sharp part." }))
	end
	page:header("Image")
	page:slider("Exposure", looked("exposure", { min = 0.2, max = 4, step = 0.05, format = "%.2f", help = "How bright the whole picture is. R gives the planet's own back." }))
	page:slider("Vignette", looked("vignette", { min = 0, max = 1, step = 0.05, format = "%.2f", help = "How dark the corners get." }))
	page:slider("Bloom threshold", looked("bloom", { min = 0, max = 1, step = 0.02, format = "%.2f", help = "How bright a part has to be to glow. Lower values make more of the picture glow." }))
end

local function look_tab(page)
	page:choice("Filter", { choices = choices(look.FILTERS), get = function() return look.state.filter or "none" end,
		set = function(v) look.use_filter(v) page:refresh() end, default = "none",
		help = "A ready-made look, made of the values below. Each can be changed after; None gives them all back to the planet." })
	page:choice("Color grading", looked("grading", { choices = { { id = true, label = "On" }, { id = false, label = "Off" } },
		help = "The planet's color grading. Off shows the unprocessed texture colors." }))
	page:choice("Color overlay", looked("tint_color", { choices = COLORS, help = "A color laid over the whole picture, saved with the photo." }))
	page:slider("Overlay strength", looked("tint", { min = 0, max = 0.6, step = 0.02, format = "%.2f", help = "Opacity of the color overlay. 0 turns it off." }))
	page:choice("Fog", looked("fog", { choices = choices(look.FOGS), help = "How far the air stays clear before the fog closes in." }))
	page:choice("Fog color", looked("fog_color", { choices = COLORS, help = "The color the distance fades to." }))
	page:slider("Glow", looked("glow", { min = 0, max = 4, step = 0.1, format = "%.1f", help = "How brightly lights, screens and other glowing surfaces shine." }))
	page:slider("Cloud shadows", looked("clouds", { min = 0, max = 1, step = 0.05, format = "%.2f", help = "How dark the shadows of passing clouds are on the ground." }))
	page:slider("Screen dust", looked("dust", { min = 0, max = 1, step = 0.05, format = "%.2f", help = "The planet's scrolling dust layer, drawn flat over the screen for the top-down view. Off by default in Photo Mode; R restores the planet's value." }))
end

local function light_page(l)
	return function(page)
		page:choice("Color", { choices = COLORS, get = function() return l.color end, set = function(v) l.color = v lights.update(l) end, default = "warm",
			help = "The color of the light." })
		page:slider("Brightness", { min = 0, max = 20, step = 0.25, format = "%.2f", get = function() return l.intensity end, set = function(v) l.intensity = v lights.update(l) end, default = 3,
			help = "How strong the light is." })
		page:slider("Range", { min = 1, max = 60, step = 0.5, format = "%.1f m", get = function() return l.range end, set = function(v) l.range = v lights.update(l) end, default = 10,
			help = "How far the light gets before it fades out." })
		page:choice("Shape", { choices = { { id = "point", label = "Point" }, { id = "spot", label = "Spot" } }, get = function() return l.shape end,
			set = function(v) l.shape = v lights.update(l) page:refresh() end, default = "point",
			help = "A point lights all round. A spot lights a cone, aimed where the camera looked when the light was placed or aimed." })
		if l.shape == "spot" then
			page:slider("Spot angle", { min = 10, max = 170, step = 5, format = "%d deg", get = function() return l.angle end, set = function(v) l.angle = v lights.update(l) end, default = 50,
				help = "How wide the spot's cone is." })
			page:action("Aim with camera", function()
				local p = session.pose
				if p then l.yaw, l.pitch = p.yaw, p.pitch lights.update(l) end
			end, { help = "Points the spot the way the camera looks now." })
		end
		page:toggle("Shadows", { get = function() return l.shadows end, set = function(v) l.shadows = v lights.update(l) end, default = true,
			help = "Whether the light casts shadows." })
		page:action("Place at camera", function()
			local p = session.pose
			if p then lights.move(l, session.ahead(3), p.yaw, p.pitch) end
		end, { help = "Puts the light 3 m ahead of the camera." })
		page:action("Remove light", function() lights.remove(l) return "Light removed" end, { help = "Deletes this light." })
	end
end

local function light_tab(page)
	page:header("Time and sun")
	page:toggle("Time override", { get = function() return look.state.time ~= nil end,
		set = function(v) if v then look.set("time", look.get("time")) else look.clear("time") end page:refresh() end, default = false,
		help = "Lights the level at an hour of your choice, blending the planet's dawn, day, dusk and night. Off, the mission's own time shows." })
	if look.state.time then
		page:slider("Time of day", { min = 0, max = 24, step = 0.25, format = clock, get = function() return look.get("time") end, set = function(v) look.set("time", v) end,
			help = "The hour. Night is at midnight, dawn at 6, day at noon and dusk at 18." })
	end
	page:toggle("Sun position", { get = function() return look.state.sun == true end, set = function(v) if v then look.set("sun", true) else look.clear("sun") end page:refresh() end,
		default = false, help = "Direction, height, color and strength of the sunlight, in place of the planet's." })
	if look.state.sun then
		page:slider("Sun direction", looked("sun_az", { min = 0, max = 355, step = 5, format = "%d deg", help = "The compass direction the sunlight comes from. Shadows turn with it." }))
		page:slider("Sun height", looked("sun_height", { min = 2, max = 89, step = 1, format = "%d deg", help = "How high the sun stands. Low suns throw long shadows." }))
		page:choice("Sun color", looked("sun_color", { choices = COLORS, help = "The color of the sunlight." }))
		page:slider("Sun brightness", looked("sun_power", { min = 0, max = 20, step = 0.25, format = "%.2f", help = "How strong the sunlight is." }))
	end
	page:slider("Shadow fill", looked("fill", { min = 0, max = 3, step = 0.05, format = "%.2f", help = "How much light reaches the parts in shadow." }))
	page:toggle("Helldiver flashlight", { get = function() return session.flashlight end, set = function(v) session.set_flashlight(v) end, default = false,
		help = "Lights the Helldiver's flashlight, as on a night mission." })
	page:header("Lights")
	page:action("Add light", function()
		local p = session.pose
		if not p then return end
		local l, why = lights.add(session.api, session.ahead(3), p.yaw, p.pitch)
		if not l then return why == "full" and ("At most " .. lights.MAX .. " lights.") or "The light couldn't be placed here." end
		page:refresh()
		return "Light added"
	end, { help = "Places a light 3 m ahead of the camera. Lights show as markers in the picture: click one to select it, then drag the colored handles to move it." })
	page:action("Three-point lighting", function()
		local at, p = session.chest(), session.pose
		if not (at and p) then return "No Helldiver to light." end
		local made = lights.rig(session.api, at, p.yaw)
		page:refresh()
		return made > 0 and (made .. " lights added") or "No room for more lights."
	end, { help = "Adds a key, a fill and a rim light around the Helldiver, aimed at it, placed from the camera's side." })
	for _, l in ipairs(lights.list) do
		page:page(function() return lights.name_of(l) end, light_page(l), { help = "Color, brightness, reach, shape and shadows of this light." })
	end
	if #lights.list > 0 then
		page:action("Remove all lights", function() lights.clear() page:refresh() end, { help = "Takes every placed light away." })
	end
end

local TIMES = { { id = 0, label = "Paused" }, { id = 0.1, label = "0.1x" }, { id = 0.25, label = "0.25x" }, { id = 0.5, label = "0.5x" }, { id = 1, label = "Normal" } }

local function scene_tab(page)
	page:choice("Time", { choices = TIMES, get = function() return session.api.world.time_now() end,
		set = function(v)
			if session.api.world.time_scale(v) then settings.set("time", v) end
		end, default = 0,
		enabled = function() return session.alone, "Only with nobody else in the lobby." end,
		help = "Pauses the game, runs it slowly, or lets it run. With other players in the lobby, it keeps running." })
	local sky_off = "Turn on Fix skies in the options of Photo Mode in Obsidian, then start the game again."
	page:choice("Sky", { choices = { { id = "off", label = "Off" }, { id = "auto", label = "Matches the time" }, { id = "day", label = "Day" },
		{ id = "dawn", label = "Dawn" }, { id = "dusk", label = "Dusk" }, { id = "night", label = "Night" }, { id = "overcast", label = "Overcast" } },
		get = function() return session.sky end, set = function(v) session.sky = v end, default = "off",
		enabled = function() return sky.available(), sky_off end,
		help = "A sky over the level, which the game never draws: clouds by day, stars by night." })
	page:slider("Sky brightness", { min = 0, max = 6, step = 0.1, format = "%.1f", get = function() return session.sky_brightness end,
		set = function(v) session.sky_brightness = v sky.set_brightness(v) end, default = 2, enabled = function() return sky.available(), sky_off end,
		help = "How bright the sky is." })
	page:choice("Helldivers", { choices = { { id = "shown", label = "Shown" }, { id = "mine", label = "Hide player" }, { id = "all", label = "Hide all" } },
		get = function() return session.helldivers end, set = function(v) session.set_helldivers(v) end, default = "shown",
		help = "Hides this player's Helldiver, or every Helldiver, for a picture of the place alone." })
end

local function frame_tab(page)
	page:choice("Aspect ratio", kept("aspect", { choices = choices(overlay.ASPECTS), help = "The shape of the picture, framed on the screen." }))
	page:toggle("Letterbox bars", kept("bars", { help = "On, the picture keeps the screen's size with black bars around the frame. Off, the picture is cut to the frame." }))
	page:choice("Grid", kept("grid", { choices = choices(overlay.GRIDS), help = "Lines for placing things, which the picture leaves out." }))
	page:input(function() return session.caption ~= "" and ("Caption: " .. session.caption) or "Caption" end,
		function(text) session.caption = text end, { help = "Words written on the picture, in the game's title font." })
	page:choice("Caption position", { choices = choices(overlay.CAPTION_PLACES), get = function() return session.caption_place end,
		set = function(v) session.caption_place = v end, default = "bottom_left", help = "Where the caption sits in the frame." })
	page:slider("Caption size", { min = 20, max = 120, step = 2, format = "%d", get = function() return session.caption_size end,
		set = function(v) session.caption_size = v end, default = 40, help = "How tall the caption's letters are." })
	page:action("Clear caption", function() session.caption = "" end, { help = "Removes the caption." })
end

local function photo_tab(page)
	page:action("Take photo", function() session.take_picture() end, { help = "Saves the picture without the controls. P does the same." })
	page:choice("Format", kept("format", { choices = { { id = "png", label = "PNG" }, { id = "jpg", label = "JPEG" } },
		help = "PNG keeps every pixel as it was. JPEG makes smaller files." }))
	page:slider("JPEG quality", kept("quality", { min = 50, max = 100, step = 1, format = "%d", help = "Higher keeps more detail in a larger file." }))
	page:label(function()
		local folder = session.folder()
		return folder and ("Saved in " .. folder) or "Pictures can't be saved in this game."
	end)
	page:action("Open photo folder", function()
		local folder = session.folder()
		if not folder then return "The folder isn't available." end
		session.api.capture.open_folder(folder)
	end, { help = "Opens the folder with the pictures in the file explorer." })
	page:header("Music")
	page:toggle("Ship music", kept("music", { help = "After a while in Photo Mode, plays the music of the ship." }))
	page:slider("Music delay", kept("music_delay", { min = 0, max = 120, step = 5, format = "%d s", help = "Seconds of silence before the ship music starts." }))
	page:slider("Music level", kept("music_db", { min = -30, max = 0, step = 1, format = "%d dB", help = "How far below the full level the music plays." }))
	page:header("Controls")
	page:toggle("Controls overlay", kept("guide", { help = "The camera keys, at the bottom left. Left out of photos." }))
	page:header("Panel")
	local function panel_call(name, ...)
		local p = M.panel
		if p and type(p[name]) == "function" then return p[name](p, ...) end
	end
	page:slider("Panel opacity", { min = 0.1, max = 1, step = 0.05, format = function(v) return string.format("%d%%", v * 100 + 0.5) end,
		get = function() return panel_call("opacity") or 0.5 end, set = function(v) panel_call("set_opacity", v) end, default = 0.5,
		help = "Opacity of the panel background. Rows and text stay solid." })
	page:slider("Panel scale", { min = 0.6, max = 1.6, step = 0.05, format = function(v) return string.format("%d%%", v * 100 + 0.5) end,
		get = function() return panel_call("scale") or 1 end, set = function(v) panel_call("set_scale", v) end, default = 1,
		help = "Size of the panel and everything in it. Drag the title bar to move the panel and the corner grip to resize it." })
	page:action("Reset panel position", function() panel_call("reset_place") end,
		{ help = "Puts the panel back in the bottom right corner at the default size." })
end

-- Every setting back to the default, from the button in the panel's title bar. Lights stay.
function M.reset_all()
	settings.reset()
	look.reset()
	look.set("dust", 0)
	session.caption, session.caption_place, session.caption_size = "", "bottom_left", 40
	session.sky, session.sky_brightness = "off", 2
	if M.panel then M.panel:refresh() end
	return "All settings reset"
end

-- Tab icons from obsidian.ui's glyphs, the nearest it has to each tab; the tab's name shows over the
-- help lines.
function M.make(api)
	M.panel = api.menu.panel({
		id = "photo",
		title = "Photo Mode",
		status = session.status,
		guide = { { keys = { "P" }, label = "Take photo" }, { keys = { "H" }, label = "Hide" } },
		buttons = { { glyph = "reset", help = "Reset all settings to the defaults. Placed lights stay.", run = M.reset_all } },
		on_close = function() session.stop() end,
		tabs = {
			{ title = "Camera", icon = "weapons", build = camera_tab },
			{ title = "Lens", icon = "search", build = lens_tab },
			{ title = "Look", icon = "editor", build = look_tab },
			{ title = "Light", icon = "world", build = light_tab },
			{ title = "Scene", icon = "mission", build = scene_tab },
			{ title = "Frame", icon = "page", build = frame_tab },
			{ title = "Photo", icon = "run", build = photo_tab },
		},
	})
	return M.panel
end

return M

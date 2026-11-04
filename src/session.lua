-- Photo Mode while it's open: the game stopped (alone in the lobby), the screen cleared, the camera
-- taken, the keys and the mouse read raw for it, the music paused and the ship's music after a while.
-- stop() puts every one of those back.
local settings = obsidian.module("src/settings")
local camera = obsidian.module("src/camera")
local look = obsidian.module("src/look")
local lights = obsidian.module("src/lights")
local sky = obsidian.module("src/sky")
local overlay = obsidian.module("src/overlay")
local music = obsidian.module("src/music")
local gizmo = obsidian.module("src/gizmo")
local helldiver = obsidian.module("src/helldiver")

local M = {
	active = false, api = nil, panel = nil, cam = nil, anchor = nil, pose = nil, alone = false,
	music_time = 0, music_started = false, hidden = {}, flashlight = false, helldivers = "shown",
	sky = "off", sky_brightness = 2, caption = "", caption_place = "bottom_left", caption_size = 40, last_keys = {},
	self_id = nil, solo = false,
}

-- What needs a mission's content, and so stays off on the ship: the lights are beacon flares from the
-- mission's packages, the skies and the time of day belong to a planet's look, and the dust and cloud
-- shadows are layers of a planet's shading.
M.MISSION_ONLY = { lights = true, sky = true, time = true, dust = true, clouds = true }
M.SHIP_ONLY_REASON = "Not available on the ship."

-- Whether a part of Photo Mode works where it's open: true, or false and the reason to show.
function M.supports(feature)
	if M.place == "ship" and M.MISSION_ONLY[feature] then return false, M.SHIP_ONLY_REASON end
	return true
end

local function where(api)
	if api.game.in_mission() then return "mission" end
	if api.game.on_ship and api.game.on_ship() then return "ship" end
	return nil
end

-- The parts of the game's screen Photo Mode mutes (obsidian.ui.mute): the whole HUD, hints, the chat,
-- the sample counter and the save icon.
M.MUTED = { "hud", "hints", "chat", "samples", "save_icon" }
M.CHEST = 1.2 -- metres over the feet that an orbit and the focus aim at

local function g(name) return rawget(_G, name) end

local function toast(text)
	if M.api and M.api.menu and M.api.menu.toast then M.api.menu.toast(text) end
end

local function my_chest()
	local unit = M.api.game.my_unit()
	local U = g("Unit")
	if not unit or not U then return nil end
	local ok, p = pcall(U.world_position, unit, 0)
	if not ok or not p then return nil end
	return { x = p.x, y = p.y, z = p.z + M.CHEST }
end

-- Keys by the game's names, looked up once.
local KEYS = { forward = "w", back = "s", left = "a", right = "d", down = "q", up = "e", rise = "space", sink = "left ctrl",
	fast = "left shift", slow = "left alt", roll_left = "z", roll_right = "c" }
local indices = nil

local function key_indices()
	if indices then return indices end
	indices = {}
	local kb = g("Keyboard")
	for k, name in pairs(KEYS) do
		local ok, i = pcall(kb.button_index, name)
		if ok and i then indices[k] = i end
	end
	return indices
end

local function held(name)
	local i = key_indices()[name]
	if not i then return false end
	local ok, v = pcall(g("Keyboard").button, i)
	return ok and type(v) == "number" and v > 0.5
end

local function tapped(name)
	local i = key_indices()[name]
	if not i then return false end
	local ok, v = pcall(g("Keyboard").pressed, i)
	return ok and v == true
end

local mouse_ids = nil

local function mouse()
	local m = g("Mouse")
	if not m then return nil end
	local ok, r = pcall(function()
		if not mouse_ids then
			local found, delta = pcall(m.axis_index, "mouse")
			mouse_ids = { delta = found and delta or nil, cursor = m.axis_index("cursor"), wheel = m.axis_index("wheel"), right = m.button_index("right") }
		end
		if not mouse_ids.left then mouse_ids.left = m.button_index("left") end
		local out = { right = m.button(mouse_ids.right) > 0.5, wheel = m.axis(mouse_ids.wheel).y, cursor = m.axis(mouse_ids.cursor),
			left = m.button(mouse_ids.left) > 0.5, left_pressed = m.pressed(mouse_ids.left) == true }
		if mouse_ids.delta then out.delta = m.axis(mouse_ids.delta) end
		return out
	end)
	return ok and r or nil
end

local last_cursor = nil

-- What the keys, the mouse and a pad ask of the camera this frame.
function M.read_input(dt)
	local input = { move = { x = 0, y = 0, z = 0 }, look = { x = 0, y = 0 }, zoom = 0, turn = 0, roll = 0 }
	if (M.panel and M.panel:typing()) or M.locked then return input end
	local mv = input.move
	if held("forward") then mv.y = mv.y + 1 end
	if held("back") then mv.y = mv.y - 1 end
	if held("right") then mv.x = mv.x + 1 end
	if held("left") then mv.x = mv.x - 1 end
	local iso = M.cam and M.cam.mode == "isometric"
	if iso then
		if tapped("down") then input.turn = input.turn - 1 end
		if tapped("up") then input.turn = input.turn + 1 end
	else
		if held("up") or held("rise") then mv.z = mv.z + 1 end
		if held("down") or held("sink") then mv.z = mv.z - 1 end
	end
	if held("roll_left") then input.roll = input.roll - 40 end
	if held("roll_right") then input.roll = input.roll + 40 end
	input.fast, input.slow = held("fast"), held("slow")
	local m = mouse()
	if m then
		local rate = 0.12 * settings.get("look_speed")
		local dx, dy = 0, 0
		if m.delta then
			dx, dy = m.delta.x, m.delta.y
		elseif last_cursor then
			dx, dy = m.cursor.x - last_cursor.x, m.cursor.y - last_cursor.y
		end
		last_cursor = { x = m.cursor.x, y = m.cursor.y }
		-- Moving the mouse up looks up: the cursor's y grows upward, and pitch grows looking up, but
		-- the mouse's own movement counts down the screen.
		if m.right then
			input.look.x = dx * rate
			input.look.y = -dy * rate * (settings.get("invert") and -1 or 1)
		end
		M.set_looking(m.right)
		M.mouse_now = m
		if m.wheel ~= 0 and not (M.panel and M.panel:under_mouse()) then input.zoom = m.wheel > 0 and 1 or -1 end
	end
	-- A pad's sticks, where there is one: the left moves, the right looks.
	local pad = g("Pad1")
	if pad then
		pcall(function()
			local l, r = pad.axis(pad.axis_index("left")), pad.axis(pad.axis_index("right"))
			if math.abs(l.x) > 0.15 then mv.x = mv.x + l.x end
			if math.abs(l.y) > 0.15 then mv.y = mv.y + l.y end
			if math.abs(r.x) > 0.15 then input.look.x = input.look.x + r.x * 120 * dt * settings.get("look_speed") end
			if math.abs(r.y) > 0.15 then input.look.y = input.look.y + r.y * 90 * dt * settings.get("look_speed") end
		end)
	end
	mv.x, mv.y, mv.z = math.max(-1, math.min(1, mv.x)), math.max(-1, math.min(1, mv.y)), math.max(-1, math.min(1, mv.z))
	return input
end

-- The cursor hides while the right button turns the camera, where the API's panel can let it go.
function M.set_looking(on)
	if M.looking == on then return end
	M.looking = on
	local p = M.panel
	if p and type(p.set_cursor_hidden) == "function" then pcall(p.set_cursor_hidden, p, on) end
end

local function mute(on)
	local ui = obsidian.ui
	if type(ui) ~= "table" then return end
	for _, id in ipairs(M.MUTED) do
		local fn = on and ui.mute or ui.unmute
		if type(fn) == "function" then pcall(fn, id) end
	end
	if type(ui.solo) == "function" then
		pcall(ui.solo, on and { "obsidian.api", M.self_id } or nil)
		M.solo = on
	end
end

function M.status()
	if not M.active then return "" end
	if not M.alone then return "LIVE" end
	local scale = M.api.world.time_now()
	if scale <= 0 then return "PAUSED" end
	if scale < 1 then return string.format("SLOW %gx", scale) end
	return "LIVE"
end

-- Opens Photo Mode. Answers true, or false and the reason it gave the player.
function M.start()
	local api = M.api
	if M.active then return true end
	local place = where(api)
	if not place then
		toast("Photo Mode is available in missions and on the ship.")
		return false, "not_in_mission"
	end
	M.place = place
	-- From the key with the pause menu open: it closes first, as Resume does.
	local st = api.game.state()
	if type(st) == "table" and st.active_screen and type(st.pop_menu) == "function" then pcall(st.pop_menu, st) end
	local ok, why = api.world.camera.take()
	if not ok then
		toast("Camera unavailable.")
		return false, why
	end
	M.active = true
	look.reset()
	-- The planets' scrolling dust is a layer over the whole screen, made for the camera high above:
	-- off from any other view, and back with R on its row. The ship has none.
	if place == "mission" then look.set("dust", 0) end
	local pose = api.world.camera.get()
	local chest = my_chest()
	M.cam = camera.new(pose, chest)
	M.cam.fov = pose.fov
	M.anchor = chest or pose.position
	M.pose = pose
	M.alone = api.game.alone()
	if M.alone then
		api.world.time_scale(settings.get("time"))
	else
		toast("Other players in the lobby: the game keeps running.")
	end
	api.world.camera.photo(true)
	mute(true)
	api.music.pause()
	M.music_time, M.music_started = 0, false
	M.controls_hidden, M.sky_warned = false, false
	M.helldivers, M.flashlight, M.hidden = "shown", false, {}
	M.sky = M.default_sky()
	M.sky_brightness = 2
	helldiver.begin(api.game.my_unit())
	if M.panel then M.panel:open(1) end
	return true
end

local function show_helldivers()
	for unit in pairs(M.hidden) do pcall(M.api.world.visible, unit, true) end
	M.hidden = {}
end

-- Shown, "mine" or "all" hidden.
function M.set_helldivers(which)
	M.helldivers = which
	show_helldivers()
	if which == "shown" then return end
	for _, p in ipairs(M.api.game.all_avatars()) do
		if p.unit and (which == "all" or p.owned) and M.api.world.visible(p.unit, false) then M.hidden[p.unit] = true end
	end
end

function M.set_flashlight(on)
	local unit = M.api.game.my_unit()
	if not unit then return false end
	M.flashlight = on and true or false
	return M.api.world.flashlight(unit, on)
end

function M.stop()
	if not M.active then return end
	local api = M.api
	M.active = false
	if M.panel and M.panel:is_open() then M.panel:close() end
	pcall(api.world.camera.release)
	pcall(api.world.camera.photo, false)
	mute(false)
	pcall(music.stop)
	pcall(api.music.resume)
	pcall(helldiver.restore, api)
	M.set_looking(false)
	gizmo.selected, gizmo.drag = nil, nil
	pcall(api.world.time_scale, 1)
	look.restore(api)
	lights.clear()
	sky.hide()
	show_helldivers()
	if M.flashlight then
		local unit = api.game.my_unit()
		if unit then pcall(api.world.flashlight, unit, false) end
		M.flashlight = false
	end
	M.sky = "off"
end

function M.toggle()
	if M.active then M.stop() else M.start() end
end

-- The Helldiver's chest, or nil.
function M.chest() return my_chest() end

-- A point some metres ahead of the camera.
function M.ahead(metres)
	local p = M.pose
	local f = camera.forward(p.yaw, p.pitch)
	return { x = p.position.x + f.x * metres, y = p.position.y + f.y * metres, z = p.position.z + f.z * metres }
end

-- The camera back by the Helldiver: behind and above in Free mode, the point to circle otherwise.
function M.recenter()
	local chest = my_chest()
	if not chest or not M.cam then return "No Helldiver to go back to." end
	local c = M.cam
	M.anchor = chest
	if c.mode == "free" then
		local f = camera.forward(c.yaw, 0)
		c.position = { x = chest.x - f.x * 6, y = chest.y - f.y * 6, z = chest.z + 2 }
		c.pitch = -15
	else
		c.pivot = chest
	end
end

-- Where pictures go, worked out once.
function M.folder()
	if M.folder_path == nil then M.folder_path = M.api.capture.folder("Helldivers") or false end
	return M.folder_path or nil
end

-- The time of day the sky follows: the one set in the panel, or the mission's own.
local function hour_now()
	local h = look.state.time
	if h then return h end
	local st = M.api.game.state()
	local level = type(st) == "table" and st.generated_level
	local name = level and level.shading_environment_setting
	return ({ dawn = 6.5, day = 12, dusk = 18, night = 0 })[name] or 12
end

-- The sky Photo Mode opens with: the one matching the time, where the mod's skies are loaded.
function M.default_sky()
	if M.supports("sky") and sky.available() then return "auto" end
	return "off"
end

function M.sky_name()
	if M.sky == "off" then return nil end
	if M.sky == "auto" then return look.sky_of(hour_now()) end
	return M.sky
end

local REASONS = {
	no_ffi = "Pictures can't be saved in this game: the game's FFI is missing.",
	not_windows = "Pictures can be saved on Windows only.",
	black = "The picture came back black. Borderless or windowed mode lets it through.",
	no_window = "The game window wasn't found.",
	minimized = "The game window is minimized.",
}

function M.take_picture()
	if not M.active then return false end
	local api = M.api
	if api.capture.busy() then return false end
	local opts = { format = settings.get("format"), quality = settings.get("quality"), keep = true }
	local ratio = overlay.ratio_of(settings.get("aspect"))
	if ratio and not settings.get("bars") then opts.aspect = ratio end
	local ok, why = api.capture.shot(opts, function(path, reason)
		overlay.flash_now()
		if path then
			toast("Saved " .. path:match("[^\\/]+$"))
		else
			toast(REASONS[reason] or "The picture wasn't saved.")
		end
	end)
	if not ok then toast(REASONS[why] or "The picture wasn't saved.") end
	return ok
end

local function ground_under(p)
	local hit, at = M.api.world.raycast({ x = p.x, y = p.y, z = p.z + 1 }, { x = p.x, y = p.y, z = p.z - 300 })
	if hit and at then return at.z end
	return nil
end

-- Once a frame, from main.lua.
function M.frame(dt)
	if not M.active then return end
	local api = M.api
	if where(api) ~= M.place then return M.stop() end
	local input = M.read_input(dt)
	local c = M.cam
	local pose = camera.update(c, input, dt, { speed = settings.get("move_speed"), smoothing = settings.get("smoothing"),
		aspect = (function() local w, h = g("Application").resolution() return w / math.max(1, h) end)() })
	-- Held near the player and above the ground, where those are asked for.
	local range = settings.get("range")
	if range < 300 then
		if c.mode == "free" then
			c.position = camera.limit(c.position, M.anchor, range)
		else
			c.pivot = camera.limit(c.pivot, M.anchor, range)
		end
	end
	if settings.get("ground") and c.mode ~= "isometric" then
		local floor = ground_under(pose.position)
		if floor and pose.position.z < floor + 0.4 then
			pose.position.z = floor + 0.4
			if c.mode == "free" and c.position.z < floor + 0.4 then c.position.z = floor + 0.4 end
		end
	end
	local name = M.supports("sky") and M.sky_name() or nil
	look.extra = {}
	if name then
		local shown, why = sky.show(api, name, pose.position, M.sky_brightness)
		if shown then
			pose.far = math.max(pose.far or 0, sky.far())
			-- The planet's fog closes in a few hundred metres away and would cover the dome: it reaches
			-- past the dome while a sky shows, unless the player set a fog.
			look.extra.fog_depth_range = { "vector2", { 60, sky.RADIUS * 1.6 } }
		elseif not M.sky_warned then
			M.sky_warned = true
			obsidian.log("photo mode: sky " .. name .. " not shown: " .. tostring(why))
		end
	elseif sky.prop then
		sky.hide()
	end
	api.world.camera.set(pose)
	M.pose = pose
	local focus = nil
	if look.state.dof and look.get("focus_player") then
		local chest = my_chest()
		if chest then focus = math.max(0.5, camera.depth_of(pose, chest)) end
	end
	look.apply(api, focus)
	helldiver.apply(api)
	M.settle_pose(dt)
	M.flare_at = M.sun_on_screen(pose)
	if settings.get("music") and not M.music_started then
		M.music_time = M.music_time + dt
		if M.music_time >= settings.get("music_delay") then
			M.music_started = true
			-- The ship plays its own music, in a world of its own: it only comes back.
			if M.place == "ship" then api.music.resume() else music.start(settings.get("music_db")) end
		end
	end
	music.tick(dt)
	-- The left mouse button in the picture: the lights' markers and handles, and focus by double click.
	local m = M.mouse_now
	if m and not M.controls_hidden then
		gizmo.input({ lights = lights, pose = pose, dt = dt, to_screen = api.world.to_screen,
			screen_h = select(2, g("Application").resolution()),
			over_panel = M.panel and M.panel:under_mouse(),
			mouse = { x = m.cursor.x, y = m.cursor.y, held = m.left, pressed = m.left_pressed },
			on_focus = M.focus_at_cursor })
	end
end

-- A pose blends in while the game runs for a moment, then the game stops again at the speed picked.
function M.settle_pose(dt)
	if helldiver.settle <= 0 then return end
	if not M.settling then
		M.settling = true
		if M.alone then M.api.world.time_scale(1) end
	end
	helldiver.settle = helldiver.settle - dt
	if helldiver.settle <= 0 then
		M.settling = false
		if M.alone then M.api.world.time_scale(settings.get("time")) end
	end
end

-- Sends a pose. Answers a line for the panel when it didn't go.
function M.pose(id)
	local ok, why = helldiver.pose(id)
	if ok then return nil end
	if why == "no_helldiver" then return "No Helldiver to pose." end
	return "The Helldiver can't take that pose here."
end

-- Where the sun is on screen for the lens flare, or nil: off, behind the camera, or behind something.
function M.sun_on_screen(pose)
	if (look.get("flare") or 0) <= 0 or not pose then return nil end
	local api = M.api
	local dir = look.sun_dir() or (api.world.sun and api.world.sun())
	if not dir or dir.z < -0.02 then return nil end
	local f = camera.forward(pose.yaw, pose.pitch)
	if f.x * dir.x + f.y * dir.y + f.z * dir.z <= 0.05 then return nil end
	local p = pose.position
	local x, y = api.world.to_screen({ x = p.x + dir.x * 800, y = p.y + dir.y * 800, z = p.z + dir.z * 800 })
	if not x then return nil end
	local hit = api.world.raycast({ x = p.x + dir.x * 0.5, y = p.y + dir.y * 0.5, z = p.z + dir.z * 0.5 },
		{ x = p.x + dir.x * 400, y = p.y + dir.y * 400, z = p.z + dir.z * 400 })
	if hit then return nil end
	return { x = x, y = y }
end

-- Focus on what's under the cursor: depth of field on, at that distance.
function M.focus_at_cursor()
	local point = M.api.world.cursor()
	if not (point and M.pose) then return end
	local d = camera.depth_of(M.pose, point)
	if d <= 0 then return end
	look.set("dof", true)
	look.set("focus_player", false)
	look.set("focus", math.max(0.5, math.min(100, d)))
	toast(string.format("Focus %.1f m", d))
	if M.panel then M.panel:refresh() end
end

-- Shows or hides everything Photo Mode draws over the game: the panel, the key guide and the markers.
function M.set_controls_hidden(on)
	M.controls_hidden = on
	if M.panel then M.panel:hide(on) end
end

-- What the overlay draws this frame.
function M.view()
	local guide = nil
	if settings.get("guide") and not M.controls_hidden then
		local iso = M.cam and M.cam.mode == "isometric"
		guide = {
			{ keys = { "W", "A", "S", "D" }, label = "Move" },
			{ keys = { "Q", "E" }, label = iso and "Turn" or "Down / up" },
			{ keys = { "Shift" }, label = "Fast" }, { keys = { "Alt" }, label = "Slow" },
			{ keys = { "RMB" }, label = "Look" },
			{ keys = { "Wheel" }, label = M.cam and M.cam.mode == "free" and "Zoom lens" or "Distance" },
			{ keys = { "Z", "C" }, label = "Roll" },
			{ keys = { "LMB x2" }, label = "Focus" },
			{ keys = { "P" }, label = "Take photo" }, { keys = { "H" }, label = "Hide controls" }, { keys = { "F7" }, label = "Exit" },
		}
	end
	local film = nil
	if (look.get("grain") or 0) > 0 or (look.get("flare") or 0) > 0 or (look.get("leak") or 0) > 0 then
		film = { grain = look.get("grain"), grain_type = look.get("grain_type"), grain_size = look.get("grain_size"), flare = look.get("flare"),
			flare_at = M.flare_at, leak = look.get("leak"), leak_rgb = look.color(look.get("leak_color")) }
	end
	return {
		film = film,
		tint = look.color(look.get("tint_color")), tint_amount = look.state.tint or 0, aspect = settings.get("aspect"), bars = settings.get("bars"),
		grid = settings.get("grid"), caption = M.caption, caption_place = M.caption_place, caption_size = M.caption_size, guide = guide,
		capturing = M.api.capture.busy(), markers = not M.controls_hidden and { lights = lights, pose = M.pose, to_screen = M.api.world.to_screen } or nil,
	}
end

return M

-- Photo Mode while it's open: the game stopped (alone in the lobby), the screen cleared, the camera
-- taken, the keys and the mouse read raw for it, the music paused and the ship's music after a while.
-- stop() puts every one of those back.
local settings = obsidian.module("src/settings")
local camera = obsidian.module("src/camera")
local look = obsidian.module("src/look")
local lights = obsidian.module("src/lights")
local sky = obsidian.module("src/sky")
local overlay = obsidian.module("src/overlay")

local M = {
	active = false, api = nil, panel = nil, cam = nil, anchor = nil, pose = nil, alone = false,
	music_time = 0, music_started = false, hidden = {}, flashlight = false, helldivers = "shown",
	sky = "off", sky_brightness = 2, caption = "", caption_place = "bottom_left", caption_size = 40, last_keys = {},
	self_id = nil, solo = false,
}

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
		local out = { right = m.button(mouse_ids.right) > 0.5, wheel = m.axis(mouse_ids.wheel).y, cursor = m.axis(mouse_ids.cursor) }
		if mouse_ids.delta then out.delta = m.axis(mouse_ids.delta) end
		return out
	end)
	return ok and r or nil
end

local last_cursor = nil

-- What the keys, the mouse and a pad ask of the camera this frame.
function M.read_input(dt)
	local input = { move = { x = 0, y = 0, z = 0 }, look = { x = 0, y = 0 }, zoom = 0, turn = 0, roll = 0 }
	if M.panel and M.panel:typing() then return input end
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
		if m.right then
			input.look.x = dx * rate
			input.look.y = dy * rate * (settings.get("invert") and -1 or 1)
		end
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
	if not api.game.in_mission() then
		toast("Photo Mode opens during a mission.")
		return false, "not_in_mission"
	end
	-- From the key with the pause menu open: it closes first, as Resume does.
	local st = api.game.state()
	if type(st) == "table" and st.active_screen and type(st.pop_menu) == "function" then pcall(st.pop_menu, st) end
	local ok, why = api.world.camera.take()
	if not ok then
		toast("The camera isn't free right now.")
		return false, why
	end
	M.active = true
	look.reset()
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
		toast("Other players are in the lobby, so the game keeps running.")
	end
	api.world.camera.photo(true)
	mute(true)
	api.music.pause()
	M.music_time, M.music_started = 0, false
	M.helldivers, M.flashlight, M.hidden = "shown", false, {}
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
	pcall(api.music.release)
	pcall(api.music.resume)
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
			toast("Saved: " .. path:match("[^\\/]+$"))
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
	if not api.game.in_mission() then return M.stop() end
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
	local name = M.sky_name()
	if name then
		local shown = sky.show(api, name, pose.position, M.sky_brightness)
		if shown then pose.far = math.max(pose.far or 0, sky.far()) end
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
	if settings.get("music") and not M.music_started then
		M.music_time = M.music_time + dt
		if M.music_time >= settings.get("music_delay") then
			M.music_started = true
			local ok = api.music.play("music_bridge", { db = settings.get("music_db") })
			if ok then api.music.resume() end
		end
	end
end

-- What the overlay draws this frame.
function M.view()
	local guide = nil
	if settings.get("guide") then
		local turn = M.cam and M.cam.mode == "isometric"
		guide = {
			"W A S D  Move     " .. (turn and "Q E  Turn" or "Q E  Down and up") .. "     Shift  Faster     Alt  Slower",
			"Right mouse  Look     Wheel  " .. (M.cam and M.cam.mode == "free" and "Field of view" or "Zoom") .. "     Z C  Roll",
			"P  Take a picture     H  Hide the controls     F7  Leave",
		}
	end
	return {
		tint = look.color(look.get("tint_color")), tint_amount = look.state.tint or 0, aspect = settings.get("aspect"), bars = settings.get("bars"),
		grid = settings.get("grid"), caption = M.caption, caption_place = M.caption_place, caption_size = M.caption_size, guide = guide,
		capturing = M.api.capture.busy(),
	}
end

return M

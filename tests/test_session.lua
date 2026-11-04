-- Opening and closing Photo Mode against a stand-in for Obsidian API that records what it was asked.
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function setup(opts)
	opts = opts or {}
	local rec = { calls = {}, muted = {}, solo = "never", toasts = {}, shading = {}, visible = {}, props = {} }
	local function log(name, ...) rec.calls[#rec.calls + 1] = { name, ... } end
	local pose = { position = { x = 0, y = 0, z = 20 }, yaw = -45, pitch = -65, roll = 0, fov = 60 }
	local time = 1
	local me = { name = "me" }
	local api = {
		game = {
			in_mission = function() return opts.state ~= "menu" end, alone = function() return opts.alone ~= false end,
			my_unit = function() return me end, all_avatars = function() return { { unit = me, owned = true }, { unit = { name = "friend" }, owned = false } } end,
			state = function() return {} end,
		},
		world = {
			camera = {
				take = function() log("take") rec.taken = true return true end,
				get = function() return pose end,
				set = function(p) rec.set = p return true end,
				release = function() log("release") rec.taken = false return true end,
				photo = function(on) log("photo", on) rec.photo = on return true end,
			},
			time_scale = function(s)
				if s < 1 and opts.alone == false then return false, "solo_only" end
				time = s
				log("time", s)
				return true
			end,
			time_now = function() return time end,
			shading = function(name, kind, value) rec.shading[name] = value return true end,
			time_of_day = function() return true end,
			raycast = function() return true, { x = 0, y = 0, z = 0 } end,
			visible = function(unit, on) rec.visible[unit.name] = on return true end,
			flashlight = function(_, on) rec.flashlight = on return true end,
			light = function() return { alive = function() return true end, set = function() end, move = function() end, remove = function() rec.light_gone = true end } end,
			prop = function(name) local p = { name = name, alive = function() return true end, move = function() end, remove = function() rec.sky_gone = true end }
				rec.props[#rec.props + 1] = p return p end,
		},
		music = {
			pause = function() log("music pause") end, resume = function() log("music resume") end,
			release = function() log("music release") end,
			play = function(track, o) log("music play", track, o.db) return true end,
		},
		menu = { toast = function(t) rec.toasts[#rec.toasts + 1] = t end },
		capture = { busy = function() return rec.busy == true end, shot = function(o, done) rec.shot = o rec.done = done return true end,
			folder = function() return "C:\\Pictures\\Helldivers" end },
	}
	obsidian.ui = {
		mute = function(id) rec.muted[id] = true return true end, unmute = function(id) rec.muted[id] = nil return true end,
		solo = function(ids) rec.solo = ids return true end,
	}
	rawset(_G, "Application", { resolution = function() return 1920, 1080 end })
	rawset(_G, "Keyboard", { button_index = function(n) return n end, button = function(n) return (KEYS_DOWN or {})[n] and 1 or 0 end, pressed = function() return false end })
	rawset(_G, "Mouse", nil)
	rawset(_G, "Unit", { world_position = function() return { x = 1, y = 2, z = 0 } end })
	local session = obsidian.module("src/session")
	obsidian.module("src/settings").load()
	session.api = api
	session.self_id = "alomare.photomode"
	local panel = { open = false }
	function panel:open() self.is = true end
	function panel:close() self.is = false session.stop() end
	function panel:is_open() return self.is == true end
	function panel:typing() return false end
	function panel:under_mouse() return false end
	session.panel = panel
	return session, rec, api
end

local function called(rec, name)
	for _, c in ipairs(rec.calls) do
		if c[1] == name then return c end
	end
	return nil
end

test("opening_stops_the_game_clears_the_screen_and_takes_the_camera", function()
	local session, rec = setup()
	eq(session.start(), true)
	eq(rec.taken, true)
	eq(called(rec, "time")[2], 0, "paused")
	eq(rec.photo, true)
	eq(rec.muted.hud and rec.muted.chat and rec.muted.hints, true, "the HUD, the chat and the hints")
	eq(rec.solo[2], "alomare.photomode", "only the API and this mod draw")
	eq(called(rec, "music pause") ~= nil, true)
	eq(session.panel:is_open(), true)
	eq(session.status(), "PAUSED")
	session.frame(0.016)
	eq(type(rec.set), "table", "the camera goes where Photo Mode puts it")
	eq(session.start(), true, "a second start does nothing")
end)

test("closing_puts_everything_back", function()
	local session, rec = setup()
	session.start()
	session.set_helldivers("all")
	eq(rec.visible.me, false)
	session.set_flashlight(true)
	local look = obsidian.module("src/look")
	look.set("exposure", 3)
	session.sky = "day"
	session.frame(0.016)
	eq(rec.shading.exposure, 3)
	eq(rec.props[1].name, "photomode/sky/day", "the sky around the camera")
	eq(rec.set.far >= 2000, true, "and the camera sees past it")
	session.panel:close()
	eq(session.active, false)
	eq(rec.taken, false, "the camera is the game's")
	eq(rec.photo, false)
	eq(next(rec.muted), nil, "nothing muted")
	eq(rec.solo, nil, "every mod draws again")
	eq(obsidian.module("src/music").state, "idle", "the music stopped")
	eq(rec.calls[#rec.calls][1] ~= "time" or rec.calls[#rec.calls][2] == 1, true)
	eq(rec.shading.exposure, nil, "the planet's exposure")
	eq(rec.visible.me, true, "the Helldiver shows")
	eq(rec.flashlight, false)
	eq(rec.sky_gone, true)
end)

test("with_other_players_the_game_runs_on", function()
	local session, rec = setup({ alone = false })
	session.start()
	eq(called(rec, "time"), nil, "no pause")
	eq(session.status(), "LIVE")
	eq(#rec.toasts, 1, "the player is told")
end)

test("photo_mode_opens_only_in_a_mission", function()
	local session, rec = setup({ state = "menu" })
	eq(session.start(), false)
	eq(rec.taken, nil)
end)

test("the_ship_music_loads_then_plays_after_its_delay_in_a_world_that_never_pauses", function()
	local session, rec = setup()
	local online, events = false, {}
	rawset(_G, "Boot", { brightness_world = "screen world", package_manager = {
		is_package_online = function() return online end, load_package = function(_, name) rec.loaded = name end } })
	rawset(_G, "World", { timpani_world = function(w) return w .. " sound" end })
	rawset(_G, "TimpaniWorld", { LISTENER_2D = 2, has_event = function(_, e) return e == "music_bridge" end,
		trigger_event = function(w, e) events[#events + 1] = { w, e } return #events end,
		set_parameter = function(_, id, k, v) rec.music_volume = v end, is_playing = function() return true end,
		set_listeners = function() end, set_listener_mode = function() end, stop = function(_, id) rec.stopped = id end })
	session.start()
	for _ = 1, 10 do session.frame(1) end
	eq(rec.loaded, nil, "quiet at first")
	for _ = 1, 11 do session.frame(1) end
	eq(rec.loaded, "resource_packages/menu", "the ship's package")
	eq(#events, 0, "waits for it")
	online = true
	session.frame(0.016)
	eq(events[1][1], "screen world sound", "in the screen world's sound")
	eq(events[1][2], "music_bridge")
	near(rec.music_volume, 10 ^ (-6 / 20), "-6 dB", 1e-6)
	session.stop()
	eq(rec.stopped, 1)
end)

test("a_picture_is_cut_to_the_frame_or_keeps_its_bars", function()
	local session, rec = setup()
	local settings = obsidian.module("src/settings")
	session.start()
	settings.set("aspect", "21:9")
	session.take_picture()
	near(rec.shot.aspect, 21 / 9)
	eq(rec.shot.keep, true, "the color and caption stay in it")
	rec.done("C:\\Pictures\\Helldivers\\shot.png")
	eq(rec.toasts[#rec.toasts], "Saved shot.png")
	settings.set("bars", true)
	session.take_picture()
	eq(rec.shot.aspect, nil, "with bars, the whole screen")
	rec.done(nil, "black")
	eq(rec.toasts[#rec.toasts]:find("black", 1, true) ~= nil, true, "the reason in words")
end)

test("the_keys_move_the_camera", function()
	local session, rec = setup()
	session.start()
	obsidian.module("src/settings").set("smoothing", 0)
	local before = session.cam.position.z
	KEYS_DOWN = { e = true }
	session.frame(1)
	KEYS_DOWN = nil
	eq(session.cam.position.z > before, true, "E rises")
end)

test("the_sky_waits_for_the_option", function()
	local session, rec = setup()
	OPTIONS.fix_sky = false
	session.start()
	session.sky = "night"
	session.frame(0.016)
	eq(#rec.props, 0, "no sky unit the game hasn't loaded")
end)

return T

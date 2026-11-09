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
			in_mission = function() return opts.state ~= "menu" and opts.state ~= "ship" end, on_ship = function() return opts.state == "ship" end,
			alone = function() return opts.alone ~= false end,
			my_unit = function() return me end, all_avatars = function() return { { unit = me, owned = true }, { unit = { name = "friend" }, owned = false } } end,
			state = function() return {} end,
			slaves = function() return {} end, master = function() return nil end,
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
			placement = function() return { x = 1, y = 2, z = 0 }, 0 end, place = function() return true end, parts_of = function(u) return { u } end,
			pose = function() return true end, end_pose = function() return false end, part_visible = function() return true end, part_units = function() return {} end,
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
	rawset(_G, "Unit", { world_position = function() return { x = 1, y = 2, z = 0 } end, world_rotation = function() return "rot" end })
	rawset(_G, "Quaternion", { forward = function() return { x = 0, y = 1, z = 0 } end })
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

test("stays_shut_with_third_person_camera", function()
	local session, rec = setup()
	rawset(_G, "HD2CAM_OVERLAY", {})
	local ok, why = session.start()
	rawset(_G, "HD2CAM_OVERLAY", nil)
	eq(ok, false)
	eq(why, "third_person_camera")
	eq(rec.taken, nil, "the camera stays where it is")
	eq(#rec.toasts, 1, "the player is told")
end)

test("closing_puts_everything_back", function()
	local session, rec = setup()
	session.start()
	session.set_helldivers("all")
	eq(rec.visible.me, false)
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
	eq(rec.sky_gone, true)
end)

test("with_other_players_the_game_runs_on", function()
	local session, rec = setup({ alone = false })
	session.start()
	eq(called(rec, "time"), nil, "no pause")
	eq(session.status(), "LIVE")
	eq(#rec.toasts, 1, "the player is told")
end)

test("a_player_joining_lets_the_stopped_game_run_again", function()
	local opts = {}
	local session, rec = setup(opts)
	session.start()
	eq(session.status(), "PAUSED")
	opts.alone = false
	local before = #rec.calls
	session.frame(0.016)
	local runs = false
	for i = before + 1, #rec.calls do runs = runs or (rec.calls[i][1] == "time" and rec.calls[i][2] == 1) end
	eq(runs, true, "the game runs")
	eq(session.alone, false)
	eq(session.status(), "LIVE")
	eq(rec.toasts[#rec.toasts], "A player joined: the game keeps running.")
	local toasts = #rec.toasts
	session.frame(0.016)
	eq(#rec.toasts, toasts, "said once")
	session.stop()
end)

test("photo_mode_opens_only_in_a_mission", function()
	local session, rec = setup({ state = "menu" })
	eq(session.start(), false)
	eq(rec.taken, nil)
end)

test("the_exploring_music_plays_after_its_delay_in_a_sound_world_of_its_own", function()
	local session, rec = setup()
	local events, updates, released = {}, 0, nil
	rawset(_G, "Application", { DISABLE_PHYSICS = 2, new_world = function(flag) rec.world_flag = flag return "own world" end,
		release_world = function(w) released = w end, resolution = function() return 1920, 1080 end })
	rawset(_G, "World", { timpani_world = function(w) return w .. " sound" end, update = function() updates = updates + 1 end })
	rawset(_G, "TimpaniWorld", { LISTENER_2D = 2, has_event = function(_, e) return e == "music_threat" end,
		trigger_event = function(w, e) events[#events + 1] = { w, e } return #events end,
		set_parameter = function(_, id, k, v) rec.music_volume = v end, is_playing = function() return true end,
		set_listeners = function() end, set_listener_mode = function() end, stop = function(_, id) rec.stopped = id end })
	session.start()
	for _ = 1, 4 do session.frame(1) end
	eq(#events, 0, "quiet at first")
	session.frame(1.5)
	eq(rec.world_flag, 2, "a world with sound and no physics")
	eq(events[1][1], "own world sound")
	eq(events[1][2], "music_threat", "the mission's exploring track")
	near(rec.music_volume, 10 ^ (-6 / 20), "at the Music level, -6 dB by default", 1e-6)
	session.frame(0.016)
	eq(updates >= 1, true, "the world moves on while the game is stopped")
	session.stop()
	eq(rec.stopped, 1)
	eq(released, "own world", "and goes away after")
end)

test("the_sky_opens_matching_the_time_where_skies_are_loaded", function()
	local session = setup()
	session.start()
	eq(session.sky, "auto")
	session.stop()
	OPTIONS.fix_sky = false
	session.start()
	eq(session.sky, "off", "no skies without Fix skies")
	session.stop()
end)

test("light_numbers_start_again_once_the_lights_are_gone", function()
	local session = setup()
	local lights = obsidian.module("src/lights")
	session.start()
	local a = lights.add(session.api, { x = 0, y = 0, z = 0 })
	local b = lights.add(session.api, { x = 1, y = 0, z = 0 })
	eq(a.number, 1)
	eq(b.number, 2)
	lights.remove(a)
	eq(lights.add(session.api, { x = 2, y = 0, z = 0 }).number, 1, "the free number")
	lights.clear()
	eq(lights.add(session.api, { x = 3, y = 0, z = 0 }).number, 1, "from 1 after a wipe")
	session.stop()
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

test("the_keys_move_the_camera_while_a_number_is_typed", function()
	local session = setup()
	session.start()
	obsidian.module("src/settings").set("smoothing", 0)
	local function moved(answer)
		function session.panel:typing() return answer() end
		local before = session.cam.position.z
		KEYS_DOWN = { e = true }
		session.frame(1)
		KEYS_DOWN = nil
		return session.cam.position.z > before
	end
	eq(moved(function() return true, "number" end), true, "a number takes no letters")
	eq(moved(function() return true, "text" end), false, "text takes every key")
	eq(moved(function() return true end), false, "an older API says nothing of the kind")
end)

test("the_sky_waits_for_the_option", function()
	local session, rec = setup()
	OPTIONS.fix_sky = false
	session.start()
	session.sky = "night"
	session.frame(0.016)
	eq(#rec.props, 0, "no sky unit the game hasn't loaded")
end)

test("on_the_ship_photo_mode_opens_and_leaves_out_what_needs_a_mission", function()
	local session, rec = setup({ state = "ship" })
	eq(session.start(), true)
	eq(session.place, "ship")
	eq(rec.taken, true)
	for _, feature in ipairs({ "lights", "sky", "time", "dust", "clouds" }) do
		local ok, why = session.supports(feature)
		eq(ok, false, feature)
		eq(why, "Not available on the ship.")
	end
	eq(session.supports("dof"), true, "the rest works")
	eq(obsidian.module("src/look").state.dust, nil, "no dust layer to switch off")
	session.sky = "day"
	for _ = 1, 21 do session.frame(1) end
	eq(#rec.props, 0, "no sky")
	local resumed = 0
	for _, c in ipairs(rec.calls) do if c[1] == "music resume" then resumed = resumed + 1 end end
	eq(resumed, 1, "the ship's own music comes back")
end)

return T

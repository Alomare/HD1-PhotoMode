-- Music while Photo Mode is open in a mission: the mission's exploring track (music_threat, the one the
-- game plays while patrols are about), in a sound world of Photo Mode's own. The mission's own sound
-- world stops with the game, and the world the engine keeps for screen drawing (Boot.brightness_world)
-- is made with Application.DISABLE_SOUND, so it plays nothing. This one is made without physics, holds
-- no units, and is updated here every frame, paused or not. Its banks are the mission's, already loaded.
-- It's set up for flat sound the way the ship sets up its own music world (state_menu.lua:199).
local M = { state = "idle", world = nil, sound = nil, id = nil, db = -6 }

M.EVENT = "music_threat"

local function g(name) return rawget(_G, name) end

local function make_world()
	if M.world then return M.sound end
	local app, W = g("Application"), g("World")
	if not (app and app.new_world and W and W.timpani_world) then return nil, "no_world" end
	local ok, world = pcall(app.new_world, app.DISABLE_PHYSICS)
	if not ok or not world then return nil, "no_world" end
	M.world = world
	M.sound = W.timpani_world(world)
	local T = g("TimpaniWorld")
	pcall(T.set_listeners, M.sound, 0)
	pcall(T.set_listener_mode, M.sound, 0, T.LISTENER_2D)
	return M.sound
end

local function begin()
	local T = g("TimpaniWorld")
	local sound, why = make_world()
	if not (T and sound) then
		M.state = "failed"
		obsidian.log("photo mode: music: " .. tostring(why or "no sound world"))
		return false
	end
	if not T.has_event(sound, M.EVENT) then
		M.state = "failed"
		obsidian.log("photo mode: music: " .. M.EVENT .. " isn't loaded")
		return false
	end
	M.id = T.trigger_event(sound, M.EVENT)
	T.set_parameter(sound, M.id, "volume", 10 ^ (M.db / 20))
	M.state = "playing"
	return true
end

-- Plays the track at db decibels below its own level. Answers true, or false when it can't play.
function M.start(db)
	M.stop()
	M.db = db or -6
	return begin()
end

-- Once a frame while Photo Mode is open: the world moves on, and the track starts again when it ends.
function M.tick(dt)
	if not M.world then return end
	pcall(g("World").update, M.world, dt or 0.016)
	if M.state == "playing" then
		local T = g("TimpaniWorld")
		local ok, on = pcall(T.is_playing, M.sound, M.id)
		if ok and not on then begin() end
	end
end

function M.stop()
	local T = g("TimpaniWorld")
	if M.id and M.sound then pcall(T.stop, M.sound, M.id) end
	M.id, M.state = nil, "idle"
	if M.world then
		local app = g("Application")
		pcall(app.release_world, M.world)
	end
	M.world, M.sound = nil, nil
end

return M

-- The ship's music while Photo Mode is open. The mission's own sound world stops with the game when
-- Photo Mode pauses it, so the track plays in the sound world of the world the engine keeps for screen
-- drawing (Boot.brightness_world), which the boot script updates every frame, paused or not. The track
-- is in the ship's package (resource_packages/menu), which a mission doesn't load: it loads first, in
-- the background, and the track starts once the package is there. It's set up for flat sound the way
-- the ship sets up its own music world (state_menu.lua:199).
local M = { state = "idle", world = nil, id = nil, db = -6 }

M.PACKAGE = "resource_packages/menu"
M.EVENT = "music_bridge"

local function g(name) return rawget(_G, name) end

local function package_manager()
	local boot = g("Boot")
	return type(boot) == "table" and boot.package_manager or nil
end

local function sound_world()
	local boot, W = g("Boot"), g("World")
	if not (type(boot) == "table" and boot.brightness_world and W and W.timpani_world) then return nil end
	return W.timpani_world(boot.brightness_world)
end

-- Starts loading, and plays when ready, at db decibels below the track's own level.
function M.start(db)
	M.stop()
	M.db = db or -6
	local pm = package_manager()
	if not pm then
		M.state = "failed"
		obsidian.log("photo mode: music: no package manager")
		return false
	end
	if not pm:is_package_online(M.PACKAGE) then pm:load_package(M.PACKAGE, false) end
	M.state = "loading"
	return true
end

local function begin()
	local T = g("TimpaniWorld")
	local world = sound_world()
	if not (T and world) then
		M.state = "failed"
		obsidian.log("photo mode: music: no sound world")
		return
	end
	if not T.has_event(world, M.EVENT) then
		M.state = "failed"
		obsidian.log("photo mode: music: " .. M.EVENT .. " isn't loaded after " .. M.PACKAGE)
		return
	end
	if not M.listening then
		pcall(T.set_listeners, world, 0)
		pcall(T.set_listener_mode, world, 0, T.LISTENER_2D)
		M.listening = true
	end
	M.world = world
	M.id = T.trigger_event(world, M.EVENT)
	T.set_parameter(world, M.id, "volume", 10 ^ (M.db / 20))
	M.state = "playing"
end

-- Once a frame while Photo Mode is open.
function M.tick()
	if M.state == "loading" then
		local pm = package_manager()
		if pm and pm:is_package_online(M.PACKAGE) then begin() end
	elseif M.state == "playing" then
		local T = g("TimpaniWorld")
		-- The track ends after a while: it starts again.
		if not T.is_playing(M.world, M.id) then begin() end
	end
end

function M.stop()
	if M.id and M.world then pcall(g("TimpaniWorld").stop, M.world, M.id) end
	M.id, M.state = nil, "idle"
end

return M

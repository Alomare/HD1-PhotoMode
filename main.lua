-- Photo Mode: a mission stopped and cleared for pictures, with a camera of its own and controls down the
-- right of the screen. Opens with its key (F7) or the PHOTO MODE row of the pause menu.
local settings = obsidian.module("src/settings")
local session = obsidian.module("src/session")
local overlay = obsidian.module("src/overlay")
local panel = obsidian.module("src/panel")

local api = obsidian.import("obsidian.api")

-- The camera, the panel and pictures came with Obsidian API 1.23.0; the panel's tabs as icons, its
-- header button, opacity and scale with 1.24.0, which an older API leaves out.
if not (api and api.world and api.world.camera and api.world.camera.take and api.menu and api.menu.panel and api.capture) then
	obsidian.log("photo mode: needs Obsidian API 1.23.0 or later")
	return
end

settings.load()
session.api = api
session.self_id = obsidian.caller()
session.panel = panel.make(api)
if type(obsidian.ui) == "table" and type(obsidian.ui.canvas) == "function" then overlay.kit = obsidian.ui.canvas("photo", { layer = 600 }) end
overlay.load_grain()

api.mod_settings.pause_row("photo_mode", { en = "Photo Mode" }, function() session.start() end,
	{ when = function(screen) return screen == "game" or screen == "menu" end })

local function typing()
	return session.panel and session.panel:typing()
end

obsidian.keybind("toggle", function()
	if not typing() then session.toggle() end
end)
obsidian.keybind("capture", function()
	if session.active and not typing() then session.take_picture() end
end)
obsidian.keybind("hide", function()
	if session.active and not typing() then session.set_controls_hidden(not session.controls_hidden) end
end)

obsidian.on_frame(function()
	if not session.active then return end
	local dt = rawget(_G, "ENGINE_DT") or 0.016
	local ok, err = pcall(session.frame, dt)
	if not ok then
		obsidian.log("photo mode: " .. tostring(err))
		pcall(session.stop)
		return
	end
	if session.active then
		local drawn, why = pcall(overlay.draw, session.view(), dt)
		if not drawn and not overlay.failed then
			overlay.failed = true
			obsidian.log("photo mode: overlay: " .. tostring(why))
		end
	end
end)

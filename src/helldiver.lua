-- The player's Helldiver for a picture: its size, a nudge from where it stood, a turn and a pose. Seen
-- on this machine only, and all of it goes back when Photo Mode closes.
--
-- Size, place and turn are set on the avatar's unit every frame, with the scene nodes of the armour,
-- weapons and backpack linked to it (api.world.parts_of), as a stopped world doesn't move them itself.
-- The game moves the avatar again as soon as it runs, so they hold while the game is stopped. The game
-- keeps its own position in the avatar's mover, which nothing here changes, so it carries on from where
-- the Helldiver was.
--
-- A pose is one of the game's animation events for a Helldiver, sent to the avatar. A stopped world
-- doesn't play animations, so the game runs for a moment (Pose time) to blend it in, then stops again.
local M = { unit = nil, base = nil, settle = 0, hidden = false }

M.DEFAULTS = { scale = 1, side = 0, forward = 0, up = 0, turn = 0, pose = "game", pose_time = 0.6 }
M.state = {}

-- Animation events the game's scripts and its animation list have for a Helldiver
-- (lua/generated/animation_events.lua). A unit without one leaves it out of the list.
M.POSES = {
	{ id = "game", label = "As it was" },
	{ id = "idle", label = "Standing", event = "idle" },
	{ id = "salute", label = "Salute", event = "salute" },
	{ id = "at_ease", label = "At ease", event = "at_ease" },
	{ id = "aim", label = "Aiming", event = "aim" },
	{ id = "aim_hip", label = "Hip fire", event = "aim_hip" },
	{ id = "stratagem", label = "Stratagem input", event = "on_enter_stratagem_input" },
	{ id = "grenade", label = "Grenade", event = "grenade_pull" },
	{ id = "radio", label = "Radio", event = "radio_activate" },
	{ id = "map", label = "Map", event = "map_open" },
	{ id = "yes", label = "Signal: yes", event = "com_yes" },
	{ id = "no", label = "Signal: no", event = "com_no" },
	{ id = "move", label = "Signal: move", event = "com_move" },
	{ id = "stay", label = "Signal: hold", event = "com_stay" },
	{ id = "sit", label = "Sitting", event = "sit" },
	{ id = "dive", label = "Dive", event = "dive" },
	{ id = "downed", label = "Downed", event = "get_downed" },
	{ id = "knocked", label = "Knocked down", event = "knockback_down" },
	{ id = "landing", label = "Landing", event = "intro_land" },
}

local function g(name) return rawget(_G, name) end

function M.reset()
	M.state = {}
	for k, v in pairs(M.DEFAULTS) do M.state[k] = v end
end
M.reset()

function M.get(k) return M.state[k] end

function M.set(k, v) M.state[k] = v end

-- Whether size, place or turn differ from the Helldiver as found.
function M.moved()
	local s = M.state
	return s.scale ~= 1 or s.side ~= 0 or s.forward ~= 0 or s.up ~= 0 or s.turn ~= 0
end

-- The poses this unit has.
function M.poses(unit)
	local U = g("Unit")
	local out = {}
	for _, p in ipairs(M.POSES) do
		local keep = true
		if p.event and unit and U and type(U.has_animation_event) == "function" then
			local ok, has = pcall(U.has_animation_event, unit, p.event)
			keep = not ok or has == true
		end
		if keep then out[#out + 1] = p end
	end
	return out
end

-- Notes where the Helldiver stands, before any change. unit: the avatar.
function M.begin(unit)
	M.reset()
	M.unit, M.base, M.settle = nil, nil, 0
	local U, Q = g("Unit"), g("Quaternion")
	if not (unit and U and Q) then return false end
	local ok, base = pcall(function()
		local p, r, s = U.local_position(unit, 0), U.local_rotation(unit, 0), U.local_scale(unit, 0)
		local x, y, z, w = Q.to_elements(r)
		return { pos = { x = p.x, y = p.y, z = p.z }, rot = { x, y, z, w }, scale = { x = s.x, y = s.y, z = s.z } }
	end)
	if not ok then
		obsidian.log("photo mode: helldiver: " .. tostring(base))
		return false
	end
	M.unit, M.base = unit, base
	return true
end

-- Where the unit goes for the state: { pos, rot (elements), scale } as tables. Pure, for the tests.
function M.target(base, s)
	local bx, by, bz, bw = base.rot[1], base.rot[2], base.rot[3], base.rot[4]
	-- The base rotation's own forward (+y) and right (+x), turned into the level.
	local function rotate(vx, vy, vz)
		local tx = 2 * (by * vz - bz * vy)
		local ty = 2 * (bz * vx - bx * vz)
		local tz = 2 * (bx * vy - by * vx)
		return vx + bw * tx + (by * tz - bz * ty), vy + bw * ty + (bz * tx - bx * tz), vz + bw * tz + (bx * ty - by * tx)
	end
	local fx, fy = rotate(0, 1, 0)
	local rx, ry = rotate(1, 0, 0)
	local pos = { x = base.pos.x + rx * s.side + fx * s.forward, y = base.pos.y + ry * s.side + fy * s.forward, z = base.pos.z + s.up }
	-- A turn about the level's up axis, after the base rotation.
	local half = math.rad(s.turn) / 2
	local tz, tw = math.sin(half), math.cos(half)
	local rot = { tw * bx - tz * by, tw * by + tz * bx, tw * bz + tz * bw, tw * bw - tz * bz }
	return { pos = pos, rot = rot, scale = { x = base.scale.x * s.scale, y = base.scale.y * s.scale, z = base.scale.z * s.scale } }
end

-- The game puts the avatar where its mover is every frame, stopped or not, so the mover goes along.
local function place(api, unit, t)
	local U, V3, Q, W = g("Unit"), g("Vector3"), g("Quaternion"), g("World")
	U.set_local_position(unit, 0, V3(t.pos.x, t.pos.y, t.pos.z))
	U.set_local_rotation(unit, 0, Q.from_elements(t.rot[1], t.rot[2], t.rot[3], t.rot[4]))
	-- A hidden Helldiver is shrunk to nothing by api.world.visible, and stays so.
	local s = M.hidden and (api.world.SHRUNK or 1e-4) or 1
	U.set_local_scale(unit, 0, V3(t.scale.x * s, t.scale.y * s, t.scale.z * s))
	local Mover = g("Mover")
	if Mover and type(U.mover) == "function" then
		local ok, mover = pcall(U.mover, unit)
		if ok and mover then pcall(Mover.set_position, mover, V3(t.pos.x, t.pos.y, t.pos.z)) end
	end
	local st = api.game.state()
	local proxy = type(st) == "table" and st.world_proxy
	local world = proxy and proxy:get_world()
	if not world then return end
	local parts = api.world.parts_of and api.world.parts_of(unit) or { unit }
	for _, part in ipairs(parts) do pcall(W.update_unit, world, part) end
end

-- Once a frame while Photo Mode is open.
function M.apply(api)
	if not (M.unit and M.base) then return end
	local U = g("Unit")
	local ok, alive = pcall(U.alive, M.unit)
	if not (ok and alive) then
		M.unit, M.base = nil, nil
		return
	end
	if not (M.moved() or M.placed) then return end
	local done, err = pcall(place, api, M.unit, M.target(M.base, M.state))
	if not done and not M.warned then
		M.warned = true
		obsidian.log("photo mode: helldiver: " .. tostring(err))
	end
	-- Placed once, the unit is put back by apply until the values are back at the start too.
	M.placed = M.moved()
	if not M.placed then pcall(place, api, M.unit, M.target(M.base, M.DEFAULTS)) end
end

-- Sends a pose's animation event. Answers true when it went, false and why not.
function M.pose(id)
	M.state.pose = id
	local unit = M.unit
	if not unit then return false, "no_helldiver" end
	for _, p in ipairs(M.POSES) do
		if p.id == id then
			if not p.event then return true end
			local ok = pcall(g("Unit").animation_event, unit, p.event)
			if not ok then return false, "no_event" end
			M.settle = M.state.pose_time
			return true
		end
	end
	return false, "unknown"
end

-- Puts the Helldiver back as found.
function M.restore(api)
	if M.unit and M.base then
		local U = g("Unit")
		local ok, alive = pcall(U.alive, M.unit)
		if ok and alive then pcall(place, api, M.unit, M.target(M.base, M.DEFAULTS)) end
	end
	M.unit, M.base, M.placed, M.settle = nil, nil, false, 0
	M.reset()
end

return M

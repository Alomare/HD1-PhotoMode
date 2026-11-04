-- The player's Helldiver for a picture: the size, a nudge from where it stood, a turn, a pose and the
-- parts shown. Seen on this machine only, and all of it goes back when Photo Mode closes.
--
-- Place and turn go through api.world.place every frame, which moves the Helldiver the way the game's
-- own teleport does, in a stopped game too, and keeps the physics mover above where it stood: a mover
-- under the ground would fall out of the level, and the game removes what falls out. The size is set
-- on the avatar's unit, with the armour, weapons and backpack linked to it updated after.
--
-- A pose is one of the game's animation events for a Helldiver (api.world.pose, which ends the one
-- before it). A stopped world doesn't play animations, so the game runs for a moment (Pose time) to
-- blend it in, then stops again. Parts hide one by one through api.world.part_visible.
local M = { unit = nil, base = nil, settle = 0, hidden = false, api = nil }

M.DEFAULTS = { scale = 1, side = 0, forward = 0, up = 0, turn = 0, pose = "game", pose_time = 0.6 }

-- The parts that hide on their own, and their names in api.world.HELLDIVER_PARTS.
M.PARTS = {
	{ id = "helmet", label = "Helmet", part = "helmet" },
	{ id = "armour", label = "Heavy armour", part = "heavy_armor" },
	{ id = "boots", label = "Boots", part = "boots" },
	{ id = "weapon", label = "Weapon in hand", part = "weapon" },
	{ id = "holstered", label = "Other weapons", part = "holstered" },
	{ id = "pack", label = "Backpack", part = "backpack" },
}
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

local function part_of(id)
	for _, p in ipairs(M.PARTS) do
		if p.id == id then return p.part end
	end
	return nil
end

-- The units of a part on the Helldiver.
function M.part_units(api, unit, id)
	local part = part_of(id)
	if not (part and unit and api.world.part_units) then return {} end
	return api.world.part_units(unit, part)
end

-- Shows or hides a part. Answers false when the Helldiver has none of it.
function M.set_part(api, id, on)
	local part = part_of(id)
	if not (part and M.unit) then return false end
	M.state["show_" .. id] = on ~= false
	return api.world.part_visible(M.unit, part, on ~= false) == true
end

function M.part_shown(id) return M.state["show_" .. id] ~= false end

-- Every hidden part back.
function M.show_parts(api)
	for _, p in ipairs(M.PARTS) do
		if M.state["show_" .. p.id] == false and M.unit then pcall(api.world.part_visible, M.unit, p.part, true) end
		M.state["show_" .. p.id] = nil
	end
end

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
function M.begin(unit, api)
	M.reset()
	M.unit, M.base, M.settle, M.api = nil, nil, 0, api
	local U = g("Unit")
	if not (unit and U and api) then return false end
	local ok, pos, angle = pcall(api.world.placement, unit)
	local got, s = pcall(U.local_scale, unit, 0)
	if not (ok and pos and got) then
		obsidian.log("photo mode: helldiver: " .. tostring(ok and "no placement" or pos))
		return false
	end
	M.unit, M.base = unit, { pos = pos, angle = angle or 0, scale = { x = s.x, y = s.y, z = s.z } }
	return true
end

-- Where the Helldiver goes for the state: { pos, angle (degrees), scale } as tables. Pure, for the
-- tests. The angle is the game's rotation_angle: 0 faces +y, and it grows turning left seen from above.
function M.target(base, s)
	local a = math.rad(base.angle)
	local fx, fy = -math.sin(a), math.cos(a)
	local rx, ry = math.cos(a), math.sin(a)
	local pos = { x = base.pos.x + rx * s.side + fx * s.forward, y = base.pos.y + ry * s.side + fy * s.forward, z = base.pos.z + s.up }
	return { pos = pos, angle = base.angle + s.turn, scale = { x = base.scale.x * s.scale, y = base.scale.y * s.scale, z = base.scale.z * s.scale } }
end

local function place(api, unit, t)
	local U, V3 = g("Unit"), g("Vector3")
	api.world.place(unit, t.pos, t.angle, M.base.pos.z)
	-- A hidden Helldiver is shrunk to nothing by api.world.visible, and stays so.
	local s = M.hidden and (api.world.SHRUNK or 1e-4) or 1
	U.set_local_scale(unit, 0, V3(t.scale.x * s, t.scale.y * s, t.scale.z * s))
	local st = api.game.state()
	local proxy = type(st) == "table" and st.world_proxy
	local world = proxy and proxy:get_world()
	if not world then return end
	for _, part in ipairs(api.world.parts_of(unit)) do pcall(g("World").update_unit, world, part) end
end

-- Once a frame while Photo Mode is open.
function M.apply(api)
	if not (M.unit and M.base) then return end
	local ok, alive = pcall(g("Unit").alive, M.unit)
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

-- Sends a pose's animation event, after ending the one before. Answers true when it went, false and
-- why not.
function M.pose(id)
	M.state.pose = id
	local unit, api = M.unit, M.api
	if not (unit and api) then return false, "no_helldiver" end
	for _, p in ipairs(M.POSES) do
		if p.id == id then
			if not p.event then
				if api.world.end_pose(unit) then M.settle = M.state.pose_time end
				return true
			end
			local ok = api.world.pose(unit, p.event)
			if not ok then return false, "no_event" end
			M.settle = M.state.pose_time
			return true
		end
	end
	return false, "unknown"
end

-- Puts the Helldiver back as found: the pose ended, every part shown, the size and place it had.
function M.restore(api)
	M.show_parts(api)
	if M.unit and M.base then
		local ok, alive = pcall(g("Unit").alive, M.unit)
		if ok and alive then
			pcall(api.world.end_pose, M.unit)
			pcall(place, api, M.unit, M.target(M.base, M.DEFAULTS))
		end
	end
	M.unit, M.base, M.placed, M.settle = nil, nil, false, 0
	M.reset()
end

return M

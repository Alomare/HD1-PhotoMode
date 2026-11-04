-- Lights placed for a picture: api.world.light, seen only on this machine, taken away when Photo Mode
-- closes.
local look = obsidian.module("src/look")

local M = { list = {}, made = 0 }

M.MAX = 8

-- A light's settings, as the panel shows them.
local function defaults()
	return { color = "warm", intensity = 3, range = 10, shape = "point", angle = 50, shadows = true, yaw = 0, pitch = -45 }
end

local function opts_of(l)
	return { color = look.color(l.color), intensity = l.intensity, range = l.range, shadows = l.shadows,
		spot = l.shape == "spot" and l.angle or nil, yaw = l.yaw, pitch = l.pitch }
end

-- The lowest number no placed light has, so numbers start again at 1 once the lights are gone.
function M.free_number()
	local used = {}
	for _, l in ipairs(M.list) do used[l.number] = true end
	local n = 1
	while used[n] do n = n + 1 end
	return n
end

-- A light at pos, aimed as the camera looks. Answers it, or nil and why not.
function M.add(api, pos, yaw, pitch)
	if #M.list >= M.MAX then return nil, "full" end
	local l = defaults()
	l.yaw, l.pitch = yaw or 0, pitch or -45
	local handle, why = api.world.light(pos, opts_of(l))
	if not handle then return nil, why end
	l.handle, l.number, l.pos = handle, M.free_number(), { x = pos.x, y = pos.y, z = pos.z }
	M.list[#M.list + 1] = l
	return l
end

-- After a change to one of its settings.
function M.update(l)
	if l.handle and l.handle:alive() then l.handle:set(opts_of(l)) end
end

function M.move(l, pos, yaw, pitch)
	if not (l.handle and l.handle:alive()) then return false end
	l.yaw, l.pitch = yaw or l.yaw, pitch or l.pitch
	l.pos = { x = pos.x, y = pos.y, z = pos.z }
	l.handle:move(pos)
	l.handle:set(opts_of(l))
	return true
end

function M.remove(l)
	for i, other in ipairs(M.list) do
		if other == l then table.remove(M.list, i) end
	end
	if l.handle then pcall(l.handle.remove, l.handle) end
	l.handle = nil
end

function M.clear()
	for _, l in ipairs(M.list) do
		if l.handle then pcall(l.handle.remove, l.handle) end
	end
	M.list = {}
end

-- Three lights around a subject at `at`, seen from a camera turned `yaw`: a warm key in front and to
-- one side, a dim cold fill on the other, and a rim light behind. Each is aimed at the subject.
M.RIG = {
	{ name = "key", turn = 45, distance = 3.5, height = 2.2, color = "warm", intensity = 5, range = 9 },
	{ name = "fill", turn = -60, distance = 4, height = 1.4, color = "cold", intensity = 1.5, range = 9 },
	{ name = "rim", turn = 170, distance = 3, height = 2.6, color = "white", intensity = 6, range = 7 },
}

function M.rig(api, at, yaw)
	local made = 0
	for _, r in ipairs(M.RIG) do
		local a = math.rad(yaw + 180 + r.turn)
		local pos = { x = at.x - math.sin(a) * r.distance, y = at.y + math.cos(a) * r.distance, z = at.z + r.height }
		-- Aimed back at the subject.
		local dx, dy, dz = at.x - pos.x, at.y - pos.y, at.z - pos.z
		local aim_yaw = math.deg(math.atan2(-dx, dy))
		local aim_pitch = math.deg(math.atan2(dz, math.sqrt(dx * dx + dy * dy)))
		local l = M.add(api, pos, aim_yaw, aim_pitch)
		if l then
			l.color, l.intensity, l.range, l.shape, l.angle = r.color, r.intensity, r.range, "spot", 60
			M.update(l)
			made = made + 1
		end
	end
	return made
end

function M.name_of(l)
	local color = l.color
	for _, c in ipairs(look.COLORS) do
		if c.id == l.color then color = c.label end
	end
	return string.format("Light %d: %s %s", l.number, color, l.shape == "spot" and "spot" or "point")
end

return M

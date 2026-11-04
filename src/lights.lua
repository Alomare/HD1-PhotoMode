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

-- A light at pos, aimed as the camera looks. Answers it, or nil and why not.
function M.add(api, pos, yaw, pitch)
	if #M.list >= M.MAX then return nil, "full" end
	local l = defaults()
	l.yaw, l.pitch = yaw or 0, pitch or -45
	local handle, why = api.world.light(pos, opts_of(l))
	if not handle then return nil, why end
	M.made = M.made + 1
	l.handle, l.number = handle, M.made
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

function M.name_of(l)
	local color = l.color
	for _, c in ipairs(look.COLORS) do
		if c.id == l.color then color = c.label end
	end
	return string.format("Light %d: %s %s", l.number, color, l.shape == "spot" and "spot" or "point")
end

return M

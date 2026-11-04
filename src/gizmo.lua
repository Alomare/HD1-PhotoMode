-- The placed lights on screen: a marker at each one, and on the selected one three handles to drag it
-- along the level's axes (red east and west, green north and south, blue up and down) and a centre to
-- drag it across the view. A click on a marker selects it. A double click anywhere else in the picture
-- sets the focus on what's under the cursor. All of it is the left mouse button away from the panel,
-- and none of it is drawn in a picture or while the controls are hidden.
local M = { selected = nil, drag = nil, last_click = -1, clock = 0 }

M.HANDLE = 12        -- pixels a handle answers a click within
M.AXIS_SHARE = 0.12  -- an axis handle's length, as a share of the light's distance from the camera
M.DOUBLE = 0.35      -- seconds between the clicks of a double click
M.AXES = {
	{ id = "x", dir = { x = 1, y = 0, z = 0 }, color = { 235, 80, 70 } },
	{ id = "y", dir = { x = 0, y = 1, z = 0 }, color = { 110, 220, 90 } },
	{ id = "z", dir = { x = 0, y = 0, z = 1 }, color = { 80, 150, 255 } },
}

local function add(p, v, s) return { x = p.x + v.x * s, y = p.y + v.y * s, z = p.z + v.z * s } end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end

-- Where the point of the level a handle runs to is on screen, given a projection `to_screen(pos)`
-- answering x, y, visible.
function M.handles(light_pos, camera_pos, to_screen)
	local cx, cy, seen = to_screen(light_pos)
	if not cx or not seen then return nil end
	local length = math.max(0.3, dist(light_pos, camera_pos) * M.AXIS_SHARE)
	local out = { centre = { x = cx, y = cy }, length = length, axes = {} }
	for _, a in ipairs(M.AXES) do
		local ex, ey = to_screen(add(light_pos, a.dir, length))
		if ex then out.axes[#out.axes + 1] = { id = a.id, dir = a.dir, color = a.color, x = ex, y = ey } end
	end
	return out
end

-- How far along an axis a drag of the mouse by (dx, dy) pixels moves, in metres: the drag measured
-- along the axis as the screen shows it.
function M.along(handle, centre, length, dx, dy)
	local sx, sy = handle.x - centre.x, handle.y - centre.y
	local screen_len2 = sx * sx + sy * sy
	if screen_len2 < 4 then return 0 end
	return (dx * sx + dy * sy) / screen_len2 * length
end

local function near(ax, ay, bx, by, r) return (ax - bx) ^ 2 + (ay - by) ^ 2 <= r * r end

-- Once a frame. ctx: { api, lights (src/lights), pose (the camera's), mouse { x, y, held, pressed },
-- over_panel, dt, on_focus(point) }. Answers true while the mouse is busy here, so a click doesn't
-- also act elsewhere.
function M.input(ctx)
	M.clock = M.clock + (ctx.dt or 0)
	local m = ctx.mouse
	if not m then return false end
	local list = ctx.lights.list
	-- A light that was removed, one by one or with the rest, leaves no handles behind.
	if M.selected and not (M.selected.handle and (not ctx.lights.has or ctx.lights.has(M.selected))) then M.selected, M.drag = nil, nil end
	if M.drag then
		if not m.held then
			M.drag = nil
			return true
		end
		local d, l = M.drag, M.drag.light
		local dx, dy = m.x - d.start_x, m.y - d.start_y
		local pos
		if d.axis then
			pos = add(d.start_pos, d.axis.dir, M.along(d.axis, d.centre, d.length, dx, dy))
		else
			-- Across the view: right and up of the camera, scaled to the light's distance.
			local p = ctx.pose
			local y = math.rad(p.yaw)
			local right = { x = math.cos(y), y = math.sin(y), z = 0 }
			local metres_per_pixel = 2 * dist(d.start_pos, p.position) * math.tan(math.rad(p.fov or 50) / 2) / math.max(1, d.screen_h)
			pos = add(add(d.start_pos, right, dx * metres_per_pixel), { x = 0, y = 0, z = 1 }, dy * metres_per_pixel)
		end
		ctx.lights.move(l, pos)
		return true
	end
	if not m.pressed or ctx.over_panel then return false end
	-- The selected light's handles first, then any marker.
	local sel = M.selected
	if sel and sel.pos then
		local h = M.handles(sel.pos, ctx.pose.position, ctx.to_screen)
		if h then
			for _, a in ipairs(h.axes) do
				if near(m.x, m.y, a.x, a.y, M.HANDLE) then
					M.drag = { light = sel, axis = a, centre = h.centre, length = h.length, start_x = m.x, start_y = m.y, start_pos = sel.pos }
					return true
				end
			end
			if near(m.x, m.y, h.centre.x, h.centre.y, M.HANDLE) then
				M.drag = { light = sel, start_x = m.x, start_y = m.y, start_pos = sel.pos, screen_h = ctx.screen_h }
				return true
			end
		end
	end
	for _, l in ipairs(list) do
		if l.pos then
			local x, y, seen = ctx.to_screen(l.pos)
			if x and seen and near(m.x, m.y, x, y, M.HANDLE) then
				M.selected = l
				return true
			end
		end
	end
	-- A double click on the picture focuses there.
	if M.clock - M.last_click <= M.DOUBLE then
		M.last_click = -1
		if ctx.on_focus then ctx.on_focus() end
		return true
	end
	M.last_click = M.clock
	return false
end

-- A light's marker color: the light's own, kept light enough to see on a dark scene.
local function marker_color(l)
	local rgb = obsidian.module("src/look").color(l.color)
	return { math.floor(80 + rgb[1] * 175), math.floor(80 + rgb[2] * 175), math.floor(80 + rgb[3] * 175) }
end

-- The markers and handles.
function M.draw(kit, ctx)
	local list = ctx.lights.list
	if #list == 0 or not kit then return end
	local s = ctx.scale or 1
	for _, l in ipairs(list) do
		if l.pos then
			local x, y, seen = ctx.to_screen(l.pos)
			if x and seen then
				local on = l == M.selected
				local r = (on and 10 or 8) * s
				kit:layer(640)
				kit:poly({ x, y + r, x + r, y, x, y - r, x - r, y }, { 0, 0, 0, 170 })
				kit:layer(641)
				local c = marker_color(l)
				local r2 = r - 2.5 * s
				kit:poly({ x, y + r2, x + r2, y, x, y - r2, x - r2, y }, { c[1], c[2], c[3], on and 255 or 210 })
				kit:layer(642)
				kit:text(tostring(l.number), x + r + 4 * s, y - 6 * s, { font = "ui", size = math.floor(15 * s), color = { 236, 235, 231, 230 } })
			end
		end
	end
	local sel = M.selected
	if sel and sel.pos and (not ctx.lights.has or ctx.lights.has(sel)) then
		local h = M.handles(sel.pos, ctx.pose.position, ctx.to_screen)
		if h then
			for _, a in ipairs(h.axes) do
				local dx, dy = a.x - h.centre.x, a.y - h.centre.y
				local len = math.max(1e-3, math.sqrt(dx * dx + dy * dy))
				local nx, ny = -dy / len * 1.5 * s, dx / len * 1.5 * s
				kit:layer(643)
				kit:poly({ h.centre.x + nx, h.centre.y + ny, a.x + nx, a.y + ny, a.x - nx, a.y - ny, h.centre.x - nx, h.centre.y - ny }, a.color)
				local r = 6 * s
				kit:poly({ a.x - r, a.y - r, a.x + r, a.y - r, a.x + r, a.y + r, a.x - r, a.y + r }, a.color)
			end
		end
	end
end

return M

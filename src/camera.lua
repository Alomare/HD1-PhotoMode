-- The camera's three ways of moving, in plain numbers. Each frame takes what the keys, the mouse and a
-- pad asked for, moves a target pose, and eases the pose that's shown toward it.
--
-- Angles are degrees, as api.world.camera takes them: yaw turns about the up axis, 0 looking along +y
-- and growing to the left seen from above; pitch looks up when positive. Positions are metres.
local M = {}

M.MODES = { "free", "orbit", "isometric" }
M.ISO_PITCH = -35.264 -- a true isometric view: the angle of a cube's diagonal
M.TELEPHOTO_FOV = 10
M.ORBIT_RATE = 90      -- degrees a second that A and D turn an orbit
M.ISO_TURN = 90        -- degrees each turn of an isometric view
M.ZOOM_STEP = 0.12     -- the share of the distance one step of the wheel moves
-- Lens lengths for a full-frame camera, whose picture is 24 mm tall: the vertical field of view of f mm
-- is 2 atan(12 / f).
M.FOCAL_LENGTHS = { 14, 18, 24, 35, 50, 85, 135, 200 }

function M.fov_of(mm) return math.deg(2 * math.atan(12 / mm)) end

function M.mm_of(fov) return math.floor(12 / math.tan(math.rad(fov) / 2) + 0.5) end

-- The listed length nearest a field of view.
function M.focal_of(fov)
	local mm, best = M.mm_of(fov), nil
	for _, f in ipairs(M.FOCAL_LENGTHS) do
		if not best or math.abs(f - mm) < math.abs(best - mm) then best = f end
	end
	return best
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function wrap(a)
	a = a % 360
	if a > 180 then a = a - 360 end
	return a
end

function M.forward(yaw, pitch)
	local y, p = math.rad(yaw), math.rad(pitch)
	return { x = -math.sin(y) * math.cos(p), y = math.cos(y) * math.cos(p), z = math.sin(p) }
end

function M.right(yaw)
	local y = math.rad(yaw)
	return { x = math.cos(y), y = math.sin(y), z = 0 }
end

local function flat_forward(yaw)
	local y = math.rad(yaw)
	return { x = -math.sin(y), y = math.cos(y), z = 0 }
end

local function add(p, v, s)
	return { x = p.x + v.x * s, y = p.y + v.y * s, z = p.z + v.z * s }
end

-- A camera starting where the game's is. pose: from api.world.camera.get(). focus: the point to orbit,
-- such as the player's chest.
function M.new(pose, focus)
	local f = M.forward(pose.yaw, pose.pitch)
	local pivot = focus or add(pose.position, f, 15)
	local c = {
		mode = "free", yaw = pose.yaw, pitch = pose.pitch, roll = 0, fov = pose.fov,
		position = { x = pose.position.x, y = pose.position.y, z = pose.position.z },
		pivot = { x = pivot.x, y = pivot.y, z = pivot.z },
		distance = 6, iso_yaw = 45, iso_turn = 0, iso_zoom = 30, iso_angle = -M.ISO_PITCH, projection = "telephoto",
		spin = 0, shown = nil,
	}
	c.shown = M.pose(c)
	return c
end

-- Switches the way it moves, keeping the view where it can.
function M.set_mode(c, mode)
	if mode == c.mode then return end
	if mode == "orbit" then
		local d = math.sqrt((c.position.x - c.pivot.x) ^ 2 + (c.position.y - c.pivot.y) ^ 2 + (c.position.z - c.pivot.z) ^ 2)
		c.distance = clamp(d, 1.5, 60)
		local to = { x = c.pivot.x - c.position.x, y = c.pivot.y - c.position.y, z = c.pivot.z - c.position.z }
		local len = math.max(1e-3, math.sqrt(to.x ^ 2 + to.y ^ 2 + to.z ^ 2))
		c.yaw = math.deg(math.atan2(-to.x, to.y))
		c.pitch = math.deg(math.asin(clamp(to.z / len, -1, 1)))
	elseif mode == "isometric" then
		-- The nearest of the four corners the view can look from.
		c.iso_yaw = 45 + 90 * math.floor((wrap(c.yaw) - 45) / 90 + 0.5)
		c.iso_turn = 0
	elseif mode == "free" and c.mode == "isometric" then
		c.fov = c.fov_before or c.fov
	end
	if mode == "isometric" then c.fov_before = c.fov end
	c.mode = mode
end

-- input: move { x right, y forward, z up } from -1 to 1, look { x, y } in degrees (x to the right, y up),
-- zoom (wheel steps, away from the player positive), turn (isometric quarter turns), roll (degrees a
-- second), fast, slow. opts: speed (metres a second), smoothing (0 to 0.95), aspect (width over height).
function M.update(c, input, dt, opts)
	local speed = (opts.speed or 6) * (input.fast and 4 or 1) * (input.slow and 0.25 or 1)
	local move, look = input.move or {}, input.look or {}
	local mx, my, mz = move.x or 0, move.y or 0, move.z or 0
	c.roll = clamp(c.roll + (input.roll or 0) * dt, -90, 90)
	if c.mode == "free" then
		c.yaw = wrap(c.yaw - (look.x or 0))
		c.pitch = clamp(c.pitch + (look.y or 0), -89, 89)
		local f, r = M.forward(c.yaw, c.pitch), M.right(c.yaw)
		c.position = add(add(add(c.position, f, my * speed * dt), r, mx * speed * dt), { x = 0, y = 0, z = 1 }, mz * speed * dt)
		if input.zoom and input.zoom ~= 0 then c.fov = clamp(c.fov - input.zoom * 3, 10, 120) end
	elseif c.mode == "orbit" then
		c.yaw = wrap(c.yaw - (look.x or 0) - mx * M.ORBIT_RATE * dt * (speed / 6) - (c.spin or 0) * dt)
		c.pitch = clamp(c.pitch + (look.y or 0), -85, 85)
		c.distance = clamp(c.distance * (1 - (input.zoom or 0) * M.ZOOM_STEP) - my * speed * dt, 1.5, 80)
		c.pivot = add(c.pivot, { x = 0, y = 0, z = 1 }, mz * speed * dt * 0.5)
		c.position = add(c.pivot, M.forward(c.yaw, c.pitch), -c.distance)
	else
		if input.turn and input.turn ~= 0 then c.iso_turn = c.iso_turn + input.turn * M.ISO_TURN end
		-- A turn eases round rather than jumping.
		local step = c.iso_turn * math.min(1, dt * 8)
		c.iso_yaw, c.iso_turn = c.iso_yaw + step, c.iso_turn - step
		-- The mouse turns an isometric view freely too, between quarter turns.
		c.iso_yaw = c.iso_yaw - (look.x or 0)
		c.yaw, c.pitch = wrap(c.iso_yaw), -c.iso_angle
		local fwd, r = flat_forward(c.yaw), M.right(c.yaw)
		local pan = speed * dt * math.max(0.4, c.iso_zoom / 30)
		c.pivot = add(add(c.pivot, fwd, my * pan), r, mx * pan)
		c.iso_zoom = clamp(c.iso_zoom * (1 - (input.zoom or 0) * M.ZOOM_STEP), 5, 250)
		local distance
		if c.projection == "orthographic" then
			distance = 120
		else
			distance = (c.iso_zoom / 2) / math.tan(math.rad(M.TELEPHOTO_FOV / 2))
		end
		c.position = add(c.pivot, M.forward(c.yaw, c.pitch), -distance)
		c.iso_distance = distance
	end
	local target = M.pose(c, opts.aspect)
	local s = clamp(opts.smoothing or 0, 0, 0.95)
	c.shown = M.ease(c.shown or target, target, s, dt)
	return c.shown
end

-- What api.world.camera.set takes, for the camera's target.
function M.pose(c, aspect)
	local p = { position = { x = c.position.x, y = c.position.y, z = c.position.z }, yaw = c.yaw, pitch = c.pitch, roll = c.roll, fov = c.fov,
		ortho = false, far = nil }
	if c.mode == "isometric" then
		if c.projection == "orthographic" then
			p.ortho = c.iso_zoom * (aspect or 16 / 9)
			p.fov = c.fov_before or c.fov
		else
			p.fov = M.TELEPHOTO_FOV
		end
		p.far = (c.iso_distance or 200) + 400
	end
	return p
end

local function lerp(a, b, t) return a + (b - a) * t end

local function lerp_angle(a, b, t) return a + wrap(b - a) * t end

-- The shown pose a step toward the target. smoothing 0 jumps there; nearer 1 eases longer. The way a
-- view is drawn (ortho, far) changes at once.
function M.ease(shown, target, smoothing, dt)
	if smoothing <= 0 then return target end
	local t = 1 - smoothing ^ (dt * 30)
	local out = {
		position = { x = lerp(shown.position.x, target.position.x, t), y = lerp(shown.position.y, target.position.y, t), z = lerp(shown.position.z, target.position.z, t) },
		yaw = wrap(lerp_angle(shown.yaw, target.yaw, t)), pitch = lerp(shown.pitch, target.pitch, t), roll = lerp(shown.roll, target.roll, t),
		fov = lerp(shown.fov, target.fov, t), ortho = target.ortho, far = target.far,
	}
	if target.ortho and shown.ortho then out.ortho = lerp(shown.ortho, target.ortho, t) end
	return out
end

-- Holds a position within `range` metres (flat) of `anchor`, and at least `floor` high where the
-- ground is known. Answers the position kept.
function M.limit(position, anchor, range, ground)
	local p = { x = position.x, y = position.y, z = position.z }
	if anchor and range and range > 0 then
		local dx, dy = p.x - anchor.x, p.y - anchor.y
		local d = math.sqrt(dx * dx + dy * dy)
		if d > range then p.x, p.y = anchor.x + dx / d * range, anchor.y + dy / d * range end
	end
	if ground and p.z < ground then p.z = ground end
	return p
end

-- How far a point is from the camera, along where it looks: what a focus distance measures.
function M.depth_of(pose, point)
	local f = M.forward(pose.yaw, pose.pitch)
	return (point.x - pose.position.x) * f.x + (point.y - pose.position.y) * f.y + (point.z - pose.position.z) * f.z
end

M.wrap = wrap

return M

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function cam()
	local camera = obsidian.module("src/camera")
	return camera, camera.new({ position = { x = 0, y = 0, z = 10 }, yaw = 0, pitch = 0, fov = 60 }, { x = 0, y = 10, z = 1 })
end

test("free_moves_along_the_view_and_turns_with_the_mouse", function()
	local camera, c = cam()
	local pose = camera.update(c, { move = { y = 1 } }, 1, { speed = 5, smoothing = 0 })
	near(pose.position.y, 5, "forward along +y at yaw 0")
	camera.update(c, { look = { x = 90 } }, 0.1, { speed = 5, smoothing = 0 })
	near(c.yaw, -90, "the mouse to the right turns right")
	pose = camera.update(c, { move = { y = 1 } }, 1, { speed = 5, smoothing = 0 })
	near(pose.position.x, 5, "now forward is +x")
	camera.update(c, { move = { z = 1 }, fast = true }, 1, { speed = 5, smoothing = 0 })
	near(c.position.z, 30, "up, four times faster with Shift")
	camera.update(c, { look = { y = 200 } }, 0.1, { smoothing = 0 })
	near(c.pitch, 89, "pitch stops short of straight up")
	camera.update(c, { zoom = 1 }, 0.1, { smoothing = 0 })
	near(c.fov, 57, "the wheel narrows the field of view")
end)

test("orbit_circles_its_point_at_its_distance", function()
	local camera, c = cam()
	camera.set_mode(c, "orbit")
	near(c.distance, math.sqrt(100 + 81), "the distance it had")
	local pose = camera.update(c, { look = { x = 30 } }, 0.016, { smoothing = 0 })
	local d = math.sqrt((pose.position.x - 0) ^ 2 + (pose.position.y - 10) ^ 2 + (pose.position.z - 1) ^ 2)
	near(d, c.distance, "on the circle", 1e-4)
	camera.update(c, { zoom = 1 }, 0.016, { smoothing = 0 })
	near(c.distance, math.min(80, math.sqrt(181)) * (1 - camera.ZOOM_STEP), "the wheel comes closer", 1e-4)
	c.spin = 30
	local before = c.yaw
	camera.update(c, {}, 1, { smoothing = 0 })
	near(camera.wrap(before - c.yaw), 30, "it turns by itself")
end)

test("isometric_looks_down_at_a_corner_and_turns_by_quarters", function()
	local camera, c = cam()
	c.yaw = 10
	camera.set_mode(c, "isometric")
	eq(c.iso_yaw, 45, "the nearest corner")
	local pose = camera.update(c, {}, 0.016, { smoothing = 0 })
	near(pose.pitch, camera.ISO_PITCH, "a true isometric angle", 1e-3)
	eq(pose.fov, camera.TELEPHOTO_FOV, "a narrow lens")
	eq(pose.ortho, false)
	camera.update(c, { turn = 1 }, 0.016, { smoothing = 0 })
	for _ = 1, 200 do camera.update(c, {}, 0.05, { smoothing = 0 }) end
	near(c.iso_yaw, 135, "a quarter turn", 1e-2)
	c.projection = "orthographic"
	pose = camera.update(c, {}, 0.016, { smoothing = 0, aspect = 2 })
	near(pose.ortho, c.iso_zoom * 2, "as wide as the screen's shape")
	eq(pose.far > 400, true, "it sees far enough")
end)

test("easing_moves_part_way_and_zero_jumps", function()
	local camera = obsidian.module("src/camera")
	local a = { position = { x = 0, y = 0, z = 0 }, yaw = 170, pitch = 0, roll = 0, fov = 60 }
	local b = { position = { x = 10, y = 0, z = 0 }, yaw = -170, pitch = 0, roll = 0, fov = 60 }
	eq(camera.ease(a, b, 0, 0.016), b)
	local mid = camera.ease(a, b, 0.5, 0.016)
	eq(mid.position.x > 0 and mid.position.x < 10, true, "part way")
	eq(math.abs(camera.wrap(mid.yaw)) > 170, true, "the short way round the turn")
end)

test("a_limit_holds_the_camera_near_and_above", function()
	local camera = obsidian.module("src/camera")
	local p = camera.limit({ x = 300, y = 0, z = -5 }, { x = 0, y = 0, z = 0 }, 100, 1)
	near(p.x, 100)
	near(p.z, 1)
	near(camera.depth_of({ position = { x = 0, y = 0, z = 0 }, yaw = 0, pitch = 0 }, { x = 3, y = 7, z = 0 }), 7, "depth along the view")
end)

return T

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

-- A flat projection: x and y of the level straight onto the screen, 10 pixels a metre.
local function to_screen(p) return p.x * 10, p.y * 10 + p.z * 5, true end

local function lights_list()
	local moved = {}
	local l = { number = 1, color = "warm", pos = { x = 0, y = 0, z = 0 }, handle = {} }
	return { list = { l }, move = function(light, pos) light.pos = pos moved[#moved + 1] = pos end, moved = moved }, l
end

test("a_drag_along_an_axis_moves_the_light_by_the_share_of_the_axis_dragged", function()
	local gizmo = obsidian.module("src/gizmo")
	local lights, l = lights_list()
	local pose = { position = { x = 0, y = -50, z = 0 }, yaw = 0, pitch = 0, fov = 50 }
	local ctx = { lights = lights, pose = pose, to_screen = to_screen, dt = 0.016, screen_h = 1080 }
	gizmo.selected = l
	local h = gizmo.handles(l.pos, pose.position, to_screen)
	local x_axis = h.axes[1]
	ctx.mouse = { x = x_axis.x, y = x_axis.y, held = true, pressed = true }
	eq(gizmo.input(ctx), true, "the handle takes the click")
	ctx.mouse = { x = x_axis.x + (x_axis.x - h.centre.x), y = x_axis.y, held = true, pressed = false }
	gizmo.input(ctx)
	near(l.pos.x, h.length, "dragged one handle length along x", 1e-6)
	near(l.pos.y, 0, "and nothing else")
	ctx.mouse = { x = 0, y = 0, held = false, pressed = false }
	gizmo.input(ctx)
	eq(gizmo.drag, nil, "let go")
end)

test("a_marker_click_selects_and_a_double_click_elsewhere_focuses", function()
	local gizmo = obsidian.module("src/gizmo")
	local lights, l = lights_list()
	gizmo.selected = nil
	local focused = 0
	local ctx = { lights = lights, pose = { position = { x = 0, y = -50, z = 0 }, yaw = 0, pitch = 0 }, to_screen = to_screen, dt = 0.1,
		on_focus = function() focused = focused + 1 end }
	ctx.mouse = { x = 0, y = 0, held = true, pressed = true }
	gizmo.input(ctx)
	eq(gizmo.selected, l)
	gizmo.selected = nil
	ctx.mouse = { x = 500, y = 500, held = true, pressed = true }
	gizmo.input(ctx)
	gizmo.input(ctx)
	eq(focused, 1, "two clicks in time")
	ctx.over_panel = true
	gizmo.input(ctx)
	gizmo.input(ctx)
	eq(focused, 1, "nothing over the panel")
end)

return T

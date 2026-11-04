-- What Photo Mode draws over the picture, in screen pixels: a color over everything, the frame of the
-- chosen aspect ratio, a composition grid, a caption, the key guide and the flash of a picture taken.
-- The color, black bars and the caption are part of the picture; the grid, the dimmed frame and the
-- guide are held back while a picture is taken.
local M = { kit = nil, flash = 0 }

M.ASPECTS = {
	{ id = "screen", label = "Screen" }, { id = "16:9", label = "16:9", ratio = 16 / 9 }, { id = "21:9", label = "21:9", ratio = 21 / 9 },
	{ id = "32:9", label = "32:9", ratio = 32 / 9 }, { id = "3:2", label = "3:2", ratio = 3 / 2 }, { id = "4:3", label = "4:3", ratio = 4 / 3 },
	{ id = "1:1", label = "1:1", ratio = 1 }, { id = "4:5", label = "4:5", ratio = 4 / 5 }, { id = "9:16", label = "9:16", ratio = 9 / 16 },
}
M.GRIDS = {
	{ id = "off", label = "Off" }, { id = "thirds", label = "Rule of thirds" }, { id = "golden", label = "Golden ratio" },
	{ id = "center", label = "Center cross" }, { id = "diagonal", label = "Diagonals" },
}
M.CAPTION_PLACES = { { id = "bottom_left", label = "Bottom left" }, { id = "bottom", label = "Bottom" }, { id = "top_left", label = "Top left" } }

local LAYER = 600
local WHITE, SHADOW, GUIDE = { 255, 255, 255, 255 }, { 0, 0, 0, 170 }, { 255, 255, 255, 110 }

function M.ratio_of(id)
	for _, a in ipairs(M.ASPECTS) do
		if a.id == id then return a.ratio end
	end
	return nil
end

-- The frame of an aspect ratio on a w by h screen: x, y (from the bottom left), width, height.
function M.frame(w, h, ratio)
	if not ratio then return 0, 0, w, h end
	if w / h > ratio then
		local fw = math.floor(h * ratio + 0.5)
		return math.floor((w - fw) / 2), 0, fw, h
	end
	local fh = math.floor(w / ratio + 0.5)
	return 0, math.floor((h - fh) / 2), w, fh
end

-- The lines of a grid, as shares of the frame: { vertical = { ... }, horizontal = { ... }, diagonal }.
function M.lines(grid)
	if grid == "thirds" then return { v = { 1 / 3, 2 / 3 }, h = { 1 / 3, 2 / 3 } } end
	if grid == "golden" then return { v = { 0.382, 0.618 }, h = { 0.382, 0.618 } } end
	if grid == "center" then return { v = { 0.5 }, h = { 0.5 } } end
	if grid == "diagonal" then return { v = {}, h = {}, diagonal = true } end
	return { v = {}, h = {} }
end

local function screen()
	local app = rawget(_G, "Application")
	return app.resolution()
end

local function line(kit, ax, ay, bx, by, width, c)
	local dx, dy = bx - ax, by - ay
	local len = math.max(1e-3, math.sqrt(dx * dx + dy * dy))
	local nx, ny = -dy / len * width / 2, dx / len * width / 2
	kit:poly({ ax + nx, ay + ny, bx + nx, by + ny, bx - nx, by - ny, ax - nx, ay - ny }, c)
end

-- view: { tint = { r, g, b } 0 to 1, tint_amount, aspect, bars, grid, caption, caption_place,
-- caption_size, guide = { lines }, capturing, panel_left (x where an open panel starts, or nil) }.
function M.draw(view, dt)
	local kit = M.kit
	if not kit then return end
	local w, h = screen()
	local s = h / 1080
	kit:layer(LAYER)
	if view.tint and (view.tint_amount or 0) > 0 then
		local t = view.tint
		kit:rect(0, 0, w, h, { t[1] * 255, t[2] * 255, t[3] * 255, math.min(1, view.tint_amount) * 255 })
	end
	local fx, fy, fw, fh = M.frame(w, h, M.ratio_of(view.aspect))
	if fw < w or fh < h then
		-- Black bars stay in the picture; otherwise the frame is a guide, dimmed, and the picture is cut.
		local c = view.bars and { 0, 0, 0, 255 } or { 0, 0, 0, 150 }
		if view.bars or not view.capturing then
			kit:layer(LAYER + 1)
			if fx > 0 then
				kit:rect(0, 0, fx, h, c)
				kit:rect(fx + fw, 0, w - fx - fw, h, c)
			end
			if fy > 0 then
				kit:rect(0, 0, w, fy, c)
				kit:rect(0, fy + fh, w, h - fy - fh, c)
			end
		end
	end
	if not view.capturing then
		local g = M.lines(view.grid)
		kit:layer(LAYER + 2)
		for _, v in ipairs(g.v) do kit:rect(fx + fw * v - s, fy, math.max(1, 2 * s), fh, GUIDE) end
		for _, v in ipairs(g.h) do kit:rect(fx, fy + fh * v - s, fw, math.max(1, 2 * s), GUIDE) end
		if g.diagonal then
			line(kit, fx, fy, fx + fw, fy + fh, math.max(1, 2 * s), GUIDE)
			line(kit, fx, fy + fh, fx + fw, fy, math.max(1, 2 * s), GUIDE)
		end
	end
	if view.caption and view.caption ~= "" then
		local size = math.floor((view.caption_size or 40) * s)
		local style = { font = "heading", size = size, color = WHITE }
		local tw = kit:measure(view.caption, style)
		local margin = 48 * s
		local x, y = fx + margin, fy + margin
		if view.caption_place == "bottom" then x = fx + (fw - tw) / 2 end
		if view.caption_place == "top_left" then y = fy + fh - margin - size end
		kit:layer(LAYER + 3)
		kit:text(view.caption, x + 2 * s, y - 2 * s, { font = "heading", size = size, color = SHADOW })
		kit:layer(LAYER + 4)
		kit:text(view.caption, x, y, style)
	end
	if view.markers and not view.capturing then
		local ok, err = pcall(obsidian.module("src/gizmo").draw, kit, { lights = view.markers.lights, pose = view.markers.pose,
			to_screen = view.markers.to_screen, scale = s })
		if not ok and not M.marker_failed then
			M.marker_failed = true
			obsidian.log("photo mode: markers: " .. tostring(err))
		end
	end
	if view.guide and not view.capturing then M.draw_guide(kit, view.guide, s) end
	if M.flash > 0 then
		M.flash = math.max(0, M.flash - (dt or 0))
		kit:layer(LAYER + 5)
		kit:rect(0, 0, w, h, { 255, 255, 255, 200 * M.flash / 0.3 })
	end
end

function M.flash_now() M.flash = 0.3 end

-- The key guide: a box at the bottom left with a keycap row for each control, the label after it, in
-- two columns.
M.GUIDE = { margin = 24, pad = 10, row = 26, cap_h = 19, gap = 4, label_gap = 8, column = 210, text = 15 }
local BOX, CAP, CAP_EDGE, LABEL = { 15, 17, 19, 150 }, { 54, 57, 62, 235 }, { 255, 255, 255, 46 }, { 236, 235, 231, 235 }

function M.guide_layout(kit, guide, s)
	local g = M.GUIDE
	local rows = math.ceil(#guide / 2)
	local cells = {}
	for i, entry in ipairs(guide) do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		local x = (g.pad + col * g.column) * s
		local y = (g.pad + (rows - 1 - row) * g.row) * s
		local caps, cx = {}, x
		for _, key in ipairs(entry.keys) do
			local w = math.max(g.cap_h * s, kit:measure(key, { font = "ui", size = math.floor(g.text * s) }) + 10 * s)
			caps[#caps + 1] = { key = key, x = cx, w = w }
			cx = cx + w + g.gap * s
		end
		cells[#cells + 1] = { caps = caps, y = y, label_x = cx + (g.label_gap - g.gap) * s, label = entry.label }
	end
	return cells, (g.pad * 2 + g.column * 2 - 20) * s, (g.pad * 2 + rows * g.row - (g.row - g.cap_h)) * s
end

function M.draw_guide(kit, guide, s)
	local g = M.GUIDE
	local cells, w, h = M.guide_layout(kit, guide, s)
	local ox, oy = g.margin * s, g.margin * s
	kit:layer(LAYER + 3)
	kit:rect(ox, oy, w, h, BOX)
	local size = math.floor(g.text * s)
	for _, cell in ipairs(cells) do
		for _, c in ipairs(cell.caps) do
			kit:layer(LAYER + 4)
			kit:rect(ox + c.x, oy + cell.y, c.w, g.cap_h * s, CAP_EDGE)
			kit:layer(LAYER + 5)
			kit:rect(ox + c.x + 1, oy + cell.y + 1, c.w - 2, g.cap_h * s - 2, CAP)
			kit:layer(LAYER + 6)
			local tw = kit:measure(c.key, { font = "ui", size = size })
			kit:text(c.key, ox + c.x + (c.w - tw) / 2, oy + cell.y + 4 * s, { font = "ui", size = size, color = LABEL })
		end
		kit:layer(LAYER + 6)
		kit:text(cell.label, ox + cell.label_x, oy + cell.y + 4 * s, { font = "ui", size = size, color = LABEL })
	end
end

return M

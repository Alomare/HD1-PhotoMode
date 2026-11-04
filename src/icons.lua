-- The panel's tab icons, drawn from shapes for Obsidian API 1.27.0: convex polygons on a grid of 16 with
-- y up, each a flat list of points, as the API's glyphs are made. An older API takes a glyph name, so
-- each tab also names the nearest glyph.
local M = {}

local cos, sin, pi = math.cos, math.sin, math.pi

local function line(ax, ay, bx, by, width)
	local dx, dy = bx - ax, by - ay
	local length = math.sqrt(dx * dx + dy * dy)
	local nx, ny = -dy / length * width / 2, dx / length * width / 2
	return { ax + nx, ay + ny, ax - nx, ay - ny, bx - nx, by - ny, bx + nx, by + ny }
end

local function disc(cx, cy, r, sides, from, to)
	local out = {}
	from, to = from or 0, to or 2 * pi
	local whole = to - from >= 2 * pi - 1e-6
	local n = sides or 12
	for i = 0, whole and n - 1 or n do
		local a = from + (i + (whole and 0.5 or 0)) * (to - from) / n
		out[#out + 1] = cx + r * cos(a)
		out[#out + 1] = cy + r * sin(a)
	end
	return out
end

local function arc(cx, cy, r, width, sides, from, to)
	local out, inner = {}, r - width
	for i = 0, sides - 1 do
		local a, b = from + i * (to - from) / sides, from + (i + 1) * (to - from) / sides
		out[#out + 1] = { cx + inner * cos(a), cy + inner * sin(a), cx + r * cos(a), cy + r * sin(a),
			cx + r * cos(b), cy + r * sin(b), cx + inner * cos(b), cy + inner * sin(b) }
	end
	return out
end

local function ring(cx, cy, r, width, sides, turn)
	return arc(cx, cy, r, width, sides, turn or 0, (turn or 0) + 2 * pi)
end

-- One list from shapes and lists of shapes.
local function join(...)
	local out = {}
	for _, part in ipairs({ ... }) do
		if type(part[1]) == "table" then
			for _, poly in ipairs(part) do out[#out + 1] = poly end
		else
			out[#out + 1] = part
		end
	end
	return out
end

local function box(x0, y0, x1, y1, width)
	return join(line(x0, y0, x1, y0, width), line(x1, y0, x1, y1, width), line(x1, y1, x0, y1, width), line(x0, y1, x0, y0, width))
end

-- A camera body with a lens and a viewfinder.
M.camera = join(box(1.5, 2.8, 14.5, 11, 1.5), { 5, 11, 10.4, 11, 9.4, 13.4, 6, 13.4 }, ring(8, 6.9, 3, 1.4, 12), disc(12.2, 9, 0.75, 6))

-- An aperture: a ring with six blades meeting round a hexagonal opening.
M.lens = (function()
	local parts = { ring(8, 8, 7.2, 1.4, 16) }
	for i = 0, 5 do
		local a = i * pi / 3 + pi / 6
		local ix, iy = 8 + 2.6 * cos(a), 8 + 2.6 * sin(a)
		local b = a + pi / 3 + 0.35
		parts[#parts + 1] = line(ix, iy, 8 + 6.2 * cos(b), 8 + 6.2 * sin(b), 1.3)
	end
	local out = {}
	for _, part in ipairs(parts) do
		for _, poly in ipairs(type(part[1]) == "table" and part or { part }) do out[#out + 1] = poly end
	end
	return out
end)()

-- Contrast: a ring with its left half filled.
M.look = join(ring(8, 8, 7, 1.4, 16), disc(8, 8, 5, 10, pi / 2, 3 * pi / 2))

-- A light bulb on its base.
M.light = join(disc(8, 10, 4.6, 14), { 5.8, 4.2, 10.2, 4.2, 10.2, 6.4, 5.8, 6.4 }, { 6.4, 1.2, 9.6, 1.2, 10.2, 3.2, 5.8, 3.2 })

-- Hills under a sun.
M.scene = join({ 0.5, 1.5, 6, 10.5, 11.5, 1.5 }, { 7, 1.5, 11.2, 7.6, 15.5, 1.5 }, disc(12.4, 12.2, 2.3, 10))

-- A Helldiver: a helmet over shoulders.
M.helldiver = join(disc(8, 11.6, 3.6, 12), { 1.6, 0.8, 14.4, 0.8, 12.6, 6.6, 3.4, 6.6 })

-- Crop marks at the corners of a frame.
M.frame = join(line(1.5, 1.5, 6, 1.5, 1.6), line(2.3, 1.5, 2.3, 6, 1.6), line(10, 1.5, 14.5, 1.5, 1.6), line(13.7, 1.5, 13.7, 6, 1.6),
	line(1.5, 14.5, 6, 14.5, 1.6), line(2.3, 14.5, 2.3, 10, 1.6), line(10, 14.5, 14.5, 14.5, 1.6), line(13.7, 14.5, 13.7, 10, 1.6), disc(8, 8, 1.1, 8))

-- Saving: an arrow down into a tray.
M.save = join(line(8, 15, 8, 7.2, 1.8), { 3.8, 8, 12.2, 8, 8, 3.4 }, line(1.5, 1.5, 14.5, 1.5, 1.6), line(2.3, 1.5, 2.3, 5.4, 1.6), line(13.7, 1.5, 13.7, 5.4, 1.6))

-- Film effects: a frame of film with its sprocket holes.
M.film = join(box(2, 1.5, 14, 14.5, 1.4), line(4.4, 1.5, 4.4, 14.5, 1.2), line(11.6, 1.5, 11.6, 14.5, 1.2),
	{ 2.6, 3, 3.8, 3, 3.8, 4.4, 2.6, 4.4 }, { 2.6, 7.3, 3.8, 7.3, 3.8, 8.7, 2.6, 8.7 }, { 2.6, 11.6, 3.8, 11.6, 3.8, 13, 2.6, 13 },
	{ 12.2, 3, 13.4, 3, 13.4, 4.4, 12.2, 4.4 }, { 12.2, 7.3, 13.4, 7.3, 13.4, 8.7, 12.2, 8.7 }, { 12.2, 11.6, 13.4, 11.6, 13.4, 13, 12.2, 13 })

-- A gear: a ring with eight teeth.
M.settings = (function()
	local out = {}
	for _, poly in ipairs(ring(8, 8, 5, 2.2, 16)) do out[#out + 1] = poly end
	for i = 0, 7 do
		local a = i * pi / 4
		local ca, sa = cos(a), sin(a)
		local px, py = -sa, ca
		local inner, outer, half = 4.4, 7.4, 1.25
		out[#out + 1] = { 8 + ca * inner - px * half, 8 + sa * inner - py * half, 8 + ca * outer - px * half, 8 + sa * outer - py * half,
			8 + ca * outer + px * half, 8 + sa * outer + py * half, 8 + ca * inner + px * half, 8 + sa * inner + py * half }
	end
	return out
end)()

-- Where the API can't draw shapes, the nearest glyph.
M.GLYPH = { camera = "weapons", lens = "search", look = "editor", light = "world", scene = "mission", helldiver = "player",
	frame = "page", save = "run", film = "page", settings = "editor" }

-- What a tab gives the API: the shapes, or with an older API the glyph.
function M.of(name, api_version_ok)
	if api_version_ok then return M[name] end
	return M.GLYPH[name]
end

return M

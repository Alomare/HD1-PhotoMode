local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

test("a_frame_is_centred_and_keeps_its_shape", function()
	local overlay = obsidian.module("src/overlay")
	local x, y, w, h = overlay.frame(1920, 1080, 1)
	eq(x, 420)
	eq(w, 1080)
	x, y, w, h = overlay.frame(1920, 1080, 21 / 9)
	eq(y, 128)
	eq(w, 1920)
	x, y, w, h = overlay.frame(1920, 1080, nil)
	eq(w * h, 1920 * 1080)
	eq(overlay.ratio_of("9:16"), 9 / 16)
	eq(overlay.ratio_of("screen"), nil)
end)

-- A kit that records, as obsidian.ui's does.
local function kit()
	local k = { rects = {}, texts = {}, polys = 0 }
	function k:layer() end
	function k:rect(x, y, w, h, c) self.rects[#self.rects + 1] = { x = x, y = y, w = w, h = h, c = c } end
	function k:poly() self.polys = self.polys + 1 end
	function k:text(s) self.texts[#self.texts + 1] = s end
	function k:measure(s) return #s * 10 end
	return k
end

test("guides_leave_the_picture_and_its_color_and_bars_stay", function()
	local overlay = obsidian.module("src/overlay")
	rawset(_G, "Application", { resolution = function() return 1920, 1080 end })
	overlay.kit = kit()
	local view = { tint = { 1, 0, 0 }, tint_amount = 0.2, aspect = "1:1", bars = false, grid = "thirds", caption = "FOR LIBERTY", guide = { { keys = { "W" }, label = "Move" } } }
	overlay.draw(view, 0.016)
	local drawn = #overlay.kit.rects
	eq(drawn, 1 + 2 + 4 + 3, "tint, two dimmed sides, four grid lines, the guide's box and keycap")
	eq(#overlay.kit.texts, 4, "caption and its shadow, the key and its label")
	overlay.kit = kit()
	view.capturing = true
	overlay.draw(view, 0.016)
	eq(#overlay.kit.rects, 1, "only the color is in the picture")
	eq(#overlay.kit.texts, 2, "and the caption")
	overlay.kit = kit()
	view.bars = true
	overlay.draw(view, 0.016)
	eq(#overlay.kit.rects, 3, "black bars stay in the picture")
	eq(overlay.kit.rects[2].c[4], 255)
end)

return T

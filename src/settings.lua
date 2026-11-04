-- What Photo Mode keeps between uses. The ways of working (speeds, keys, the picture's format, the music)
-- are kept for the next launch; the look of a picture starts fresh each time Photo Mode opens.
local M = {}

M.KEPT = {
	move_speed = 6, look_speed = 1, smoothing = 0.4, ground = true, range = 150, invert = false,
	format = "png", quality = 95, aspect = "screen", bars = false, grid = "off",
	music = true, music_db = -6, guide = true, time = 0,
}

M.values = {}

local function storage()
	return type(obsidian) == "table" and obsidian.storage or nil
end

function M.load()
	local s = storage()
	for k, default in pairs(M.KEPT) do
		local v = nil
		if s then
			local ok, got = pcall(s.get, "setting/" .. k)
			if ok then v = got end
		end
		if type(v) ~= type(default) then v = default end
		M.values[k] = v
	end
end

function M.get(k)
	local v = M.values[k]
	if v == nil then return M.KEPT[k] end
	return v
end

function M.set(k, v)
	if M.KEPT[k] == nil or type(v) ~= type(M.KEPT[k]) then return false end
	M.values[k] = v
	local s = storage()
	if s then pcall(s.set, "setting/" .. k, v) end
	return true
end

-- Some of the kept settings back to their defaults.
function M.reset_keys(keys)
	for _, k in ipairs(keys) do
		if M.KEPT[k] ~= nil then M.set(k, M.KEPT[k]) end
	end
end

function M.reset()
	for k, default in pairs(M.KEPT) do M.set(k, default) end
end

return M

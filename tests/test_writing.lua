-- The words players see keep the writing rules: no "its", no first person, nothing addressed as a
-- persona, and every row says what it does.
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function read(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

-- The quoted strings of a Lua file that hold a space: the words, not ids.
local function shown(path)
	local out = {}
	for s in read(path):gmatch('"([^"\n]*)"') do
		if s:find(" ", 1, true) and not s:find("%%[%a]") or s:find("^%u") then out[#out + 1] = s end
	end
	return out
end

local BAD = { "%f[%a][Ii]ts%f[%A]", "%f[%a]I%f[%A]", "%f[%a][Mm]y%f[%A]", "%f[%a][Mm]e%f[%A]", "%f[%a][Mm]ine%f[%A]", "%f[%a][Ww]e%f[%A]", "%f[%a][Oo]ur%f[%A]" }

local function check(text, where)
	for _, pattern in ipairs(BAD) do
		if text:find(pattern) then error(where .. ": \"" .. text .. "\" breaks the writing rules (" .. pattern .. ")", 3) end
	end
end

test("the_panel_and_messages_keep_the_rules", function()
	local n = 0
	for _, file in ipairs({ "src/panel.lua", "src/session.lua", "src/look.lua", "src/overlay.lua", "src/lights.lua", "main.lua" }) do
		for _, s in ipairs(shown(file)) do
			check(s, file)
			n = n + 1
		end
	end
	eq(n > 100, true, "strings checked: " .. n)
end)

test("the_manifest_and_readme_keep_the_rules", function()
	for _, file in ipairs({ "obsidian.json", "README.md" }) do
		local text = read(file):gsub("```.-```", "")
		for line in text:gmatch("[^\n]+") do check(line, file) end
	end
end)

test("every_row_with_a_value_has_help", function()
	local src = read("src/panel.lua")
	local rows, helped = 0, 0
	for call in src:gmatch("page:(%a+)%(") do
		if call == "slider" or call == "toggle" or call == "choice" or call == "action" or call == "input" then rows = rows + 1 end
	end
	for _ in src:gmatch("help = \"") do helped = helped + 1 end
	eq(helped >= rows, true, "rows " .. rows .. ", help lines " .. helped)
end)

return T

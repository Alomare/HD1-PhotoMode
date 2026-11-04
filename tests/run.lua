-- Offline tests for the parts of Photo Mode that don't need the game. From the repository's root:
--   luajit tests/run.lua
local passed, failed = 0, 0

local function fresh_obsidian()
	local loaded = {}
	obsidian = {
		module = function(name)
			if loaded[name] == nil then loaded[name] = dofile(name .. ".lua") end
			return loaded[name]
		end,
		log = function(s) LOGS[#LOGS + 1] = s end,
		caller = function() return "alomare.photomode" end,
		settings = { get = function(id) return OPTIONS[id] end },
		storage = { get = function(k) return STORED[k] end, set = function(k, v) STORED[k] = v end },
		ui = {},
	}
	LOGS, OPTIONS, STORED = {}, { fix_sky = true }, {}
end

function eq(got, want, what)
	if got ~= want then error((what or "value") .. ": expected " .. tostring(want) .. ", got " .. tostring(got), 2) end
end

function near(got, want, what, tolerance)
	if type(got) ~= "number" or math.abs(got - want) > (tolerance or 1e-6) then
		error((what or "value") .. ": expected " .. want .. ", got " .. tostring(got), 2)
	end
end

local function test(name, fn)
	fresh_obsidian()
	local ok, err = xpcall(fn, debug.traceback)
	if ok then passed = passed + 1 else failed = failed + 1 print("FAIL " .. name .. "\n" .. err) end
end

for _, file in ipairs({ "tests/test_camera.lua", "tests/test_look.lua", "tests/test_overlay.lua", "tests/test_session.lua", "tests/test_writing.lua" }) do
	local tests = dofile(file)
	for _, t in ipairs(tests) do test(file .. " " .. t[1], t[2]) end
end
print(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)

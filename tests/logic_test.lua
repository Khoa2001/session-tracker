-- Tests for wezterm/logic.lua. Run with: luajit tests/logic_test.lua
local here = arg[0]:match("^(.*)/tests/[^/]+$") or "."
package.path = here .. "/wezterm/?.lua;" .. package.path
local logic = require("logic")

local fails, passes = 0, 0
local function eq(name, got, want)
	if got == want then
		passes = passes + 1
		print("PASS " .. name)
	else
		fails = fails + 1
		print(("FAIL %s\n  expected [%s] got [%s]"):format(name, tostring(want), tostring(got)))
	end
end

-- worst
eq("worst working over idle", logic.worst({ "idle", "working" }), "working")
eq("worst needs-you over all", logic.worst({ "idle", "needs-you", "working" }), "needs-you")
eq("worst empty", logic.worst({}), nil)
eq("worst unknown only", logic.worst({ "bogus" }), nil)
eq("worst ignores unknown", logic.worst({ "bogus", "idle" }), "idle")

-- counts
local c = logic.counts({ "working", "working", "idle", "needs-you", "bogus" })
eq("counts needs-you", c["needs-you"], 1)
eq("counts working", c.working, 2)
eq("counts idle", c.idle, 1)

-- summary
eq("summary full", logic.summary(c), "1 waiting · 2 working · 1 idle")
eq("summary omits zeros", logic.summary({ ["needs-you"] = 0, working = 3, idle = 0 }), "3 working")
eq("summary all zero", logic.summary({ ["needs-you"] = 0, working = 0, idle = 0 }), "")

-- usage_text
local now = 1792368000 -- 2026-10-19T00:00:00Z
local lines = { "2", "51", "2026-10-19T04:37:00+00:00", "2026-10-23T12:00:00+00:00" }
eq("usage ok", logic.usage_text(lines, 60, now), "4h 37m 2% │ 4d 12h 51%")
eq("usage stale", logic.usage_text(lines, 901, now), "usage n/a")
eq("usage nil lines", logic.usage_text(nil, 60, now), "usage n/a")
eq("usage nil age", logic.usage_text(lines, nil, now), "usage n/a")
eq("usage short lines", logic.usage_text({ "2", "51", "x" }, 60, now), "usage n/a")
eq(
	"usage garbage reset falls back to label",
	logic.usage_text({ "2", "51", "garbage", "2026-10-23T12:00:00+00:00" }, 60, now),
	"5h 2% │ 4d 12h 51%"
)
eq(
	"usage past reset is now",
	logic.usage_text({ "2", "51", "2026-10-18T00:00:00+00:00", "2026-10-23T12:00:00+00:00" }, 60, now),
	"now 2% │ 4d 12h 51%"
)
eq(
	"usage minutes only",
	logic.usage_text({ "2", "51", "2026-10-19T00:12:00+00:00", "2026-10-23T12:00:00+00:00" }, 60, now),
	"12m 2% │ 4d 12h 51%"
)
eq(
	"usage fractional seconds and offset",
	logic.usage_text({ "2", "51", "2026-10-19T04:37:00.997656+00:00", "2026-10-23T12:00:00+00:00" }, 60, now),
	"4h 37m 2% │ 4d 12h 51%"
)

-- tab_label
eq("tab_label repo:branch", logic.tab_label({ repo = "web", branch = "dark-mode" }, "fb"), "web:dark-mode")
eq("tab_label repo only", logic.tab_label({ repo = "web", branch = "" }, "fb"), "web")
eq("tab_label empty repo falls back", logic.tab_label({ repo = "", branch = "main" }, "fb"), "fb")
eq("tab_label branch only falls back", logic.tab_label({ branch = "main" }, "fb"), "fb")
eq("tab_label nil record falls back", logic.tab_label(nil, "fb"), "fb")
eq("tab_label non-string fields fall back", logic.tab_label({ repo = 5, branch = {} }, "fb"), "fb")
eq("tab_label nil fallback", logic.tab_label(nil, nil), nil)

-- right_status: usage first, counts last, so a narrow tab bar clips usage first
eq("right_status both", logic.right_status("1 waiting · 1 idle", "4h 37m 2% │ 4d 12h 51%"), "4h 37m 2% │ 4d 12h 51% │ 1 waiting · 1 idle")
eq("right_status no counts", logic.right_status("", "usage n/a"), "usage n/a")
eq("right_status no usage", logic.right_status("2 working", ""), "2 working")
eq("right_status neither", logic.right_status("", ""), "")

print(("%d passed, %d failed"):format(passes, fails))
os.exit(fails == 0 and 0 or 1)

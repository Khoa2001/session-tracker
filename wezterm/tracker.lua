-- WezTerm glue for the session tracker: tab-title dots, and global counts plus
-- account usage on the right of the tab bar. State files are written by
-- hooks/track-state.sh as <state dir>/<pane id>.json.
--
-- API facts verified against WezTerm 20240203 in a scratch instance:
--   * wezterm.mux.get_tab(tab.tab_id):panes() works inside format-tab-title.
--   * pane:pane_id() equals the $WEZTERM_PANE value seen by hooks.
--   * wezterm.json_parse, io.open, os.getenv, os.remove and wezterm.glob work.
--   * wezterm.read_dir failed inside format-tab-title, so pane files are opened
--     directly by id instead of listing the directory.
local wezterm = require("wezterm")
local logic = require("logic")

local M = {}

-- Same red/yellow/green as the status line dot.
local COLORS = { ["needs-you"] = "#eb6f92", working = "#f6c177", idle = "#98c379" }
-- Same palette as the tab bar in ~/.wezterm.lua.
local BAR_BG, BAR_FG = "#100f17", "#9492a5"

local function state_dir()
	return os.getenv("SESSION_TRACKER_STATE_DIR") or ((os.getenv("HOME") or "") .. "/.claude/state/panes")
end

local function usage_cache_path()
	return os.getenv("SESSION_TRACKER_USAGE_CACHE") or "/tmp/.claude_usage_cache"
end

local function read_state_file(pane_id)
	local ok, rec = pcall(function()
		local f = io.open(state_dir() .. "/" .. pane_id .. ".json", "r")
		if not f then
			return nil
		end
		local content = f:read("*a")
		f:close()
		local parsed = wezterm.json_parse(content)
		if type(parsed) == "table" and type(parsed.state) == "string" then
			return parsed
		end
		return nil
	end)
	if ok then
		return rec
	end
	return nil
end

-- Per-pane cache of one second, so one burst of tab redraws reads each file once.
local state_cache = {}

function M.state_of(pane_id)
	local now = os.time()
	local hit = state_cache[pane_id]
	if hit and hit.at == now then
		return hit.rec
	end
	local rec = read_state_file(pane_id)
	state_cache[pane_id] = { at = now, rec = rec }
	return rec
end

-- What a tab should show: `state` is the worst state among its Claude panes
-- (nil when none), `title` is "repo:branch" of the focused pane (nil when that
-- pane has no state record). Never raises.
function M.tab_view(tab)
	local ok, view = pcall(function()
		local states = {}
		for _, pane in ipairs(wezterm.mux.get_tab(tab.tab_id):panes()) do
			local rec = M.state_of(pane:pane_id())
			if rec then
				states[#states + 1] = rec.state
			end
		end
		local focused = M.state_of(tab.active_pane.pane_id)
		return { state = logic.worst(states), title = logic.tab_label(focused, nil) }
	end)
	if ok then
		return view
	end
	return {}
end

-- FormatItems for the state dot plus a space, or {} when there is no state.
-- `color` overrides the state color (used where the state color would vanish
-- into the tab background).
function M.dot(state, color)
	local c = color or COLORS[state]
	if not c then
		return {}
	end
	return { { Foreground = { Color = c } }, { Text = "● " } }
end

-- Usage cache mtime is looked up with stat at most every 30 seconds.
local mtime_cache = { checked = 0, mtime = nil }

local function usage_text()
	local ok, text = pcall(function()
		local path = usage_cache_path()
		local now = os.time()
		if now - mtime_cache.checked >= 30 then
			mtime_cache.checked = now
			local _, stdout = wezterm.run_child_process({ "/usr/bin/stat", "-f", "%m", path })
			mtime_cache.mtime = tonumber(stdout)
		end
		local lines = {}
		for line in io.lines(path) do
			lines[#lines + 1] = line
		end
		local age = mtime_cache.mtime and (now - mtime_cache.mtime) or nil
		return logic.usage_text(lines, age, now)
	end)
	if ok then
		return text
	end
	return "usage n/a"
end

local function right_status_text()
	local states = {}
	for _, window in ipairs(wezterm.mux.all_windows()) do
		for _, tab in ipairs(window:tabs()) do
			for _, pane in ipairs(tab:panes()) do
				local rec = M.state_of(pane:pane_id())
				if rec then
					states[#states + 1] = rec.state
				end
			end
		end
	end
	return logic.right_status(logic.summary(logic.counts(states)), usage_text())
end

local function wipe_state_files()
	pcall(function()
		for _, path in ipairs(wezterm.glob(state_dir() .. "/*.json")) do
			os.remove(path)
		end
	end)
end

function M.setup(config)
	config.status_update_interval = 1000
	-- The right status carries the session counts, so the bar must stay visible
	-- with a single tab.
	config.hide_tab_bar_if_only_one_tab = false

	wezterm.on("update-right-status", function(window, _)
		local ok, text = pcall(right_status_text)
		if not ok then
			text = ""
		end
		window:set_right_status(wezterm.format({
			{ Background = { Color = BAR_BG } },
			{ Foreground = { Color = BAR_FG } },
			{ Text = " " .. text .. " " },
		}))
	end)

	-- Pane ids restart with the mux, so files left by a previous run could paint
	-- a dot on an unrelated pane. The handler only wipes; WezTerm still spawns
	-- the default window (and honors `start --workspace` and `-- cmd`) itself.
	wezterm.on("gui-startup", function()
		wipe_state_files()
	end)
end

return M

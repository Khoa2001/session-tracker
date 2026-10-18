-- Pure logic for the session tracker. No wezterm dependency, so it runs under
-- plain LuaJIT for tests.
local M = {}

local RANK = { ["needs-you"] = 3, working = 2, idle = 1 }

-- Worst state in the list: needs-you beats working beats idle. nil if none known.
function M.worst(states)
	local best, best_rank = nil, 0
	for _, s in ipairs(states or {}) do
		local r = RANK[s]
		if r and r > best_rank then
			best, best_rank = s, r
		end
	end
	return best
end

function M.counts(states)
	local c = { ["needs-you"] = 0, working = 0, idle = 0 }
	for _, s in ipairs(states or {}) do
		if c[s] then
			c[s] = c[s] + 1
		end
	end
	return c
end

-- "1 waiting · 2 working · 1 idle", zero counts omitted.
function M.summary(counts)
	local parts = {}
	if counts["needs-you"] > 0 then
		parts[#parts + 1] = counts["needs-you"] .. " waiting"
	end
	if counts.working > 0 then
		parts[#parts + 1] = counts.working .. " working"
	end
	if counts.idle > 0 then
		parts[#parts + 1] = counts.idle .. " idle"
	end
	return table.concat(parts, " · ")
end

-- Days since 1970-01-01 for a civil date (Howard Hinnant's algorithm).
local function days_from_civil(y, m, d)
	if m <= 2 then
		y = y - 1
	end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

-- Epoch seconds for an ISO-8601 string like 2026-02-26T12:59:59.997656+00:00, or nil.
local function parse_iso(s)
	if type(s) ~= "string" then
		return nil
	end
	local y, mo, d, h, mi, se = s:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
	if not y then
		return nil
	end
	local epoch = days_from_civil(tonumber(y), tonumber(mo), tonumber(d)) * 86400
		+ tonumber(h) * 3600
		+ tonumber(mi) * 60
		+ tonumber(se)
	local sign, oh, om = s:match("([+-])(%d%d):(%d%d)$")
	if sign then
		local offset = tonumber(oh) * 3600 + tonumber(om) * 60
		epoch = epoch - (sign == "+" and offset or -offset)
	end
	return epoch
end

local function countdown(reset_iso, now)
	local at = parse_iso(reset_iso)
	if not at then
		return nil
	end
	local diff = at - now
	if diff <= 0 then
		return "now"
	end
	local days = math.floor(diff / 86400)
	local hours = math.floor((diff % 86400) / 3600)
	local minutes = math.floor((diff % 3600) / 60)
	if days > 0 then
		return ("%dd %dh"):format(days, hours)
	elseif hours > 0 then
		return ("%dh %dm"):format(hours, minutes)
	end
	return ("%dm"):format(minutes)
end

local MAX_CACHE_AGE = 900

-- lines: the 4 lines of the usage cache (5h pct, 7d pct, 5h reset ISO, 7d reset ISO).
function M.usage_text(lines, age_seconds, now_epoch)
	if type(lines) ~= "table" or #lines < 4 or not age_seconds or age_seconds > MAX_CACHE_AGE then
		return "usage n/a"
	end
	local five = countdown(lines[3], now_epoch) or "5h"
	local seven = countdown(lines[4], now_epoch) or "7d"
	return ("%s %s%% │ %s %s%%"):format(five, lines[1], seven, lines[2])
end

return M

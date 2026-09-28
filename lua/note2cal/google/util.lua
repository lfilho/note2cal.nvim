-- Pure helper functions for the Google Calendar provider. Nothing in this
-- module touches `vim.*`, so it can be required and unit tested under plain
-- Lua (see spec/note2cal_google_spec.lua).
local M = {}

--- Percent-encode a string for use in a URL query component (RFC 3986).
function M.url_encode(str)
	if str == nil then
		return ""
	end
	str = tostring(str)
	str = str:gsub("\n", "\r\n")
	str = str:gsub("([^%w%-%.%_%~])", function(c)
		return string.format("%%%02X", string.byte(c))
	end)
	return str
end

--- Reverse of `url_encode` (also accepts `+` as a space, per form-encoding).
function M.url_decode(str)
	if str == nil then
		return nil
	end
	str = str:gsub("+", " ")
	str = str:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end)
	return str
end

--- Build a "k=v&k2=v2" query/body string from a table, sorted by key so
--- output (and therefore tests) are deterministic.
function M.build_query(params)
	local keys = {}
	for k in pairs(params) do
		table.insert(keys, k)
	end
	table.sort(keys)

	local parts = {}
	for _, k in ipairs(keys) do
		local v = params[k]
		if v ~= nil then
			table.insert(parts, string.format("%s=%s", M.url_encode(k), M.url_encode(v)))
		end
	end
	return table.concat(parts, "&")
end

--- Convert a local wall-clock date/time to a UTC RFC3339 timestamp ending in
--- "Z". Delegates DST/offset handling entirely to the system's os.time /
--- os.date, so the same wall-clock hour on different calendar dates still
--- resolves to the correct UTC instant.
function M.to_rfc3339_utc(year, month, day, hour, min)
	local epoch = os.time({
		year = year,
		month = month,
		day = day,
		hour = hour,
		min = min,
		sec = 0,
		isdst = nil,
	})
	return os.date("!%Y-%m-%dT%H:%M:%SZ", epoch)
end

--- Whether a stored token should be considered expired, with a safety
--- margin so callers refresh slightly before Google would reject it.
function M.is_token_expired(token, now, margin_seconds)
	if not token or not token.expires_at then
		return true
	end
	now = now or os.time()
	margin_seconds = margin_seconds or 60
	return (token.expires_at - margin_seconds) <= now
end

local seeded = false

--- A random opaque string, good enough as an OAuth `state` CSRF nonce for a
--- single-user loopback redirect (not intended as a cryptographic secret).
function M.random_state()
	if not seeded then
		math.randomseed(os.time() + math.floor(os.clock() * 1e6))
		seeded = true
	end
	local chars = {}
	for _ = 1, 24 do
		table.insert(chars, string.format("%x", math.random(0, 15)))
	end
	return table.concat(chars)
end

return M

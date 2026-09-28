-- Schedules events directly into Google Calendar via the Calendar API.
-- No AppleScript, no Calendar.app, and no plugin-hosted server: this talks
-- straight from the user's machine to Google over HTTPS (via curl), using a
-- token obtained through google/auth.lua.
local auth = require("note2cal.google.auth")
local http = require("note2cal.google.http")
local util = require("note2cal.google.util")

local M = {}

local API_BASE = "https://www.googleapis.com/calendar/v3/calendars"

local function build_event_body(event)
	return vim.json.encode({
		summary = event.title,
		start = {
			dateTime = util.to_rfc3339_utc(event.year, event.month, event.day, event.start_hour, event.start_min),
		},
		["end"] = {
			dateTime = util.to_rfc3339_utc(event.year, event.month, event.day, event.end_hour, event.end_min),
		},
	})
end

local function show_debug(events, calendar_id)
	local buf = vim.api.nvim_create_buf(false, true)
	local debug_info = {
		"## [note2cal] Debug Information (google)",
		"",
		string.format("**Events Count**: %d", #events),
		string.format("**Calendar ID**: %s", calendar_id),
		"",
		"**Request bodies**:",
		"```json",
	}
	for _, event in ipairs(events) do
		table.insert(debug_info, build_event_body(event))
	end
	table.insert(debug_info, "```")

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, debug_info)
	vim.api.nvim_command("split")
	vim.api.nvim_win_set_buf(0, buf)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
	vim.api.nvim_win_set_height(0, #debug_info + 1)
end

function M.schedule(events, config)
	local google_config = config.google or {}
	local calendar_id = google_config.calendar_id or "primary"

	if config.debug then
		show_debug(events, calendar_id)
		return
	end

	vim.notify(string.format("Scheduling %d event(s)...", #events), vim.log.levels.INFO)

	auth.ensure_access_token(google_config, function(access_token, auth_err)
		if not access_token then
			vim.notify(string.format("[note2cal] Google Calendar: %s", auth_err), vim.log.levels.ERROR)
			return
		end

		local remaining = #events
		local failures = 0
		local first_error = nil

		local function finish_one(ok, err)
			remaining = remaining - 1
			if not ok then
				failures = failures + 1
				first_error = first_error or err
			end

			if remaining == 0 then
				if failures == 0 then
					vim.notify(string.format("Successfully scheduled %d events", #events), vim.log.levels.INFO)
				else
					vim.notify(
						string.format("Failed to schedule %d/%d events: %s", failures, #events, tostring(first_error)),
						vim.log.levels.ERROR
					)
				end
			end
		end

		for _, event in ipairs(events) do
			http.request({
				method = "POST",
				url = string.format("%s/%s/events", API_BASE, util.url_encode(calendar_id)),
				headers = {
					["Authorization"] = "Bearer " .. access_token,
					["Content-Type"] = "application/json",
				},
				body = build_event_body(event),
			}, function(ok, result)
				if ok then
					finish_one(true)
				else
					local msg = (result and result.decoded and result.decoded.error and result.decoded.error.message)
						or (result and result.body)
						or "unknown error"
					finish_one(false, msg)
				end
			end)
		end
	end)
end

return M

local M = {}

M.default_config = {
	-- "macos-calendar" (default, unchanged behavior) or "google"
	provider = "macos-calendar",
	macos = {
		calendar_name = "Work", -- the calendar's name as it appears in Calendar.app
	},
	keymaps = {
		normal = "<Leader>se",
		visual = "<Leader>se",
	},
	highlights = {
		at_symbol = "WarningMsg",
		at_text = "Folded",
	},
	google = {
		-- Neither client_id nor client_secret are config fields: both must
		-- be set via NOTE2CAL_GOOGLE_CLIENT_ID / NOTE2CAL_GOOGLE_CLIENT_SECRET
		-- environment variables (see docs/google-calendar-setup.md), so they
		-- can never end up committed alongside this config.
		calendar_id = "primary", -- "primary" for your default calendar, or a specific calendar's ID
		scope = "https://www.googleapis.com/auth/calendar.events",
		-- "os-key-store" (default: OS keychain, else GPG-encrypted file) or
		-- "plain-file" (explicit opt-in to an unencrypted token file)
		security = "os-key-store",
	},
	debug = false,
}

M.config = {}

-- Helper function to clean text
local function clean_text(str)
	-- Remove leading/trailing whitespace and normalize internal spaces
	return str:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\n", " "):gsub("\r", " "):gsub("%s+", " ")
end

-- Helper function to convert 12-hour time to 24-hour format
local function convert_to_24h(hour, min, meridiem)
	hour = tonumber(hour)
	min = tonumber(min or "0")

	-- If no meridiem is provided, assume 24-hour format
	if not meridiem then
		return hour, min
	end

	-- Normalize meridiem to just "a" or "p"
	meridiem = meridiem:sub(1, 1):lower()

	-- Handle 12 AM/PM special cases
	if hour == 12 then
		hour = meridiem == "p" and 12 or 0
	elseif meridiem == "p" then
		-- Convert PM times to 24-hour format
		hour = hour + 12
	end

	return hour, min
end

M.parse_time = function(time_str)
	local start_h, start_m, start_meridiem, end_h, end_m, end_meridiem

	-- Try different formats in order of specificity

	-- 1. Standard format with colon and AM/PM: "3:15pm-4:30pm" or "3:15p-4:30p"
	start_h, start_m, start_meridiem, end_h, end_m, end_meridiem =
		time_str:match("(%d+):(%d+)([ap]m?)%-(%d+):(%d+)([ap]m?)")

	if not start_h then
		-- 2. Standard format with colon (24h): "3:15-4:30" or "16:15-17:30"
		start_h, start_m, end_h, end_m = time_str:match("(%d+):(%d+)%-(%d+):(%d+)")
	end

	if not start_h then
		-- 3. Compact format with AM/PM: "315pm-430pm" or "315p-430p"
		local start_time, s_mer, end_time, e_mer = time_str:match("(%d+)([ap]m?)%-(%d+)([ap]m?)")
		if start_time and #start_time >= 3 and #end_time >= 3 then
			start_m = start_time:sub(-2)
			start_h = start_time:sub(1, -3)
			end_m = end_time:sub(-2)
			end_h = end_time:sub(1, -3)
			start_meridiem = s_mer
			end_meridiem = e_mer
		end
	end

	if not start_h then
		-- 4. Military time format: "1500-1630"
		start_h, start_m, end_h, end_m = time_str:match("(%d%d)(%d%d)%-(%d%d)(%d%d)")
	end

	if not start_h then
		-- 5. Compact format without AM/PM: "315-430"
		local start_time, end_time = time_str:match("(%d+)%-(%d+)")
		if start_time and end_time then
			if #start_time <= 2 then
				start_h = tonumber(start_time)
				start_m = 0
			else
				start_m = tonumber(start_time:sub(-2))
				start_h = tonumber(start_time:sub(1, -3))
			end

			if #end_time <= 2 then
				end_h = tonumber(end_time)
				end_m = 0
			else
				end_m = tonumber(end_time:sub(-2))
				end_h = tonumber(end_time:sub(1, -3))
			end
		end
	end

	if not start_h then
		-- 6. Simple hour format with AM/PM: "3pm-4pm" or "3p-4p"
		start_h, start_meridiem, end_h, end_meridiem = time_str:match("(%d+)([ap]m?)%-(%d+)([ap]m?)")

		if start_h then
			if #start_h <= 2 then -- Only match if not compact format
				start_m = 0
			else
				start_m = tonumber(start_h:sub(-2))
				start_h = tonumber(start_h:sub(1, -3))
			end
		end

		if end_h then
			if #end_h <= 2 then -- Only match if not compact format
				end_m = 0
			else
				end_m = tonumber(end_h:sub(-2))
				end_h = tonumber(end_h:sub(1, -3))
			end
		end
	end

	if not start_h then
		-- 7. Simple hour format (24h): "6-7"
		start_h, end_h = time_str:match("(%d+)%-(%d+)")
		if start_h then
			start_m, end_m = "0", "0"
		end
	end

	if not start_h then
		return nil
	end

	-- Convert to 24-hour format if AM/PM is specified
	if start_meridiem or end_meridiem then
		start_h, start_m = convert_to_24h(start_h, start_m, start_meridiem)
		end_h, end_m = convert_to_24h(end_h, end_m, end_meridiem)
	else
		-- Convert to numbers if no AM/PM
		start_h = tonumber(start_h)
		start_m = tonumber(start_m)
		end_h = tonumber(end_h)
		end_m = tonumber(end_m)
	end

	-- Validate hours and minutes
	if
		start_h < 0
		or start_h > 23
		or end_h < 0
		or end_h > 23
		or start_m < 0
		or start_m > 59
		or end_m < 0
		or end_m > 59
	then
		return nil
	end

	-- Validate that end time is after start time
	if (start_h > end_h) or (start_h == end_h and start_m >= end_m) then
		return nil
	end

	return start_h, start_m, end_h, end_m
end

-- Dispatches to the configured calendar provider.
function M.schedule_events(events)
	local provider = M.config.provider or "macos-calendar"

	if provider == "macos-calendar" then
		require("note2cal.providers.macos_calendar").schedule(events, M.config)
	elseif provider == "google" then
		require("note2cal.providers.google").schedule(events, M.config)
	else
		vim.notify(
			string.format(
				'[note2cal] Unknown provider "%s" (expected "macos-calendar" or "google")',
				tostring(provider)
			),
			vim.log.levels.ERROR
		)
	end
end

-- Helper function to extract event details
function M.extract_event_details(text)
	-- Remove markdown task or bullet indicators
	text = text:gsub("^[%-*%[%]%s]*", "")

	-- Match the event title, date, and time
	local event_title, event_date, time = text:match("(.+)%s+@%s+(%d%d%d%d%-%d%d%-%d%d)%s+(.+)")

	-- If no date is found, assume the current date
	if not event_date then
		event_title, time = text:match("(.+)%s+@%s+(.+)")
		if event_title and time then
			event_date = os.date("%Y-%m-%d") -- Get the current date in YYYY-MM-DD format
		end
	end

	return event_title, event_date, time
end

function M.extract_and_schedule(range)
	local mode = vim.api.nvim_get_mode().mode

	local lines
	if mode == "n" then
		if range then -- Command mode with a range given
			local start_line = range.line1
			local end_line = range.line2

			lines = vim.fn.getline(start_line, end_line)
		else -- Normal mode or command mode without a range
			lines = { vim.api.nvim_get_current_line() }
		end
	else
		-- In visual mode, get selected lines
		local start_line = vim.fn.line("v")
		local end_line = vim.fn.line(".")

		-- Get all selected lines
		lines = vim.fn.getline(start_line, end_line)
	end

	-- Remove lines that only contain whitespace
	lines = vim.tbl_filter(function(line) return line:match("%S") end, lines)

	local events = {}
	for _, line in ipairs(lines) do
		local text = clean_text(line)

		local event_title, event_date, time = M.extract_event_details(text)
		if event_title and event_date and time then
			-- Validate date format (YYYY-MM-DD)
			local year, month, day = event_date:match("(%d%d%d%d)%-(%d%d)%-(%d%d)")
			year, month, day = tonumber(year), tonumber(month), tonumber(day)

			-- Check if date is valid
			if
				not year
				or not month
				or not day
				or month < 1
				or month > 12
				or day < 1
				or day > 31
				or (month == 2 and day > 29)
				or ((month == 4 or month == 6 or month == 9 or month == 11) and day > 30)
			then
				vim.notify(string.format("Invalid date: %s", text), vim.log.levels.WARN)
				return
			end

			event_title = clean_text(event_title):gsub('"', '\\"')

			local start_hour, start_min, end_hour, end_min = M.parse_time(time)
			if start_hour and end_hour and start_min and end_min then
				table.insert(events, {
					title = event_title,
					year = year,
					month = month,
					day = day,
					start_hour = start_hour,
					start_min = start_min,
					end_hour = end_hour,
					end_min = end_min,
				})
			else
				vim.notify(string.format("Invalid time format: %s", text), vim.log.levels.WARN)
			end
		else
			vim.notify(string.format("Invalid format: %s", text), vim.log.levels.WARN)
		end
	end

	if #events > 0 then
		M.schedule_events(events)
	end
end

-- Setup function for lazy.nvim
function M.setup(opts)
	opts = opts or {}

	-- Backwards compatibility: `calendar_name` used to be a top-level field
	-- before macos-calendar got its own `macos` table (mirroring `google`).
	if opts.calendar_name then
		vim.notify(
			'[note2cal] "calendar_name" is deprecated; use "macos.calendar_name" instead.',
			vim.log.levels.WARN
		)
		opts.macos = opts.macos or {}
		opts.macos.calendar_name = opts.macos.calendar_name or opts.calendar_name
		opts.calendar_name = nil
	end

	M.config = vim.tbl_deep_extend("force", M.default_config, opts)

	local function set_keymaps()
		if vim.bo.filetype == "markdown" then
			vim.keymap.set(
				{ "n", "x" },
				M.config.keymaps.visual,
				M.extract_and_schedule,
				{ noremap = true, silent = true, desc = "Schedule event(s) from line(s)" }
			)
		end
	end

	local function set_highlights()
		-- Clear existing syntax groups to avoid conflicts
		vim.api.nvim_set_hl(0, "Note2calAtSymbol", { link = M.config.highlights.at_symbol })
		vim.api.nvim_set_hl(0, "Note2calAtText", { link = M.config.highlights.at_text })
		vim.cmd(string.format(
			[[
				syntax clear Note2calAtSymbol
				syntax clear Note2calAtText
				syntax match Note2calAtSymbol "\( \)\@<=@\( \)\@=" containedin=ALL
				syntax match Note2calAtText "\(@ \)\@<=.*" containedin=ALL
			]],
			M.config.highlights.at_symbol,
			M.config.highlights.at_text
		))
	end

	local group = vim.api.nvim_create_augroup("Note2cal", { clear = true })

	vim.api.nvim_create_autocmd("FileType", {
		pattern = "markdown",
		group = group,
		callback = function()
			-- NOTE: Defering for .5 seconds to avoid conflicts with other plugins
			-- let me know if you have a better way to do this
			vim.defer_fn(function()
				set_keymaps()
				set_highlights()
			end, 500)
		end,
	})

	vim.api.nvim_create_user_command(
		"Note2cal",
		M.extract_and_schedule,
		{ range = true, desc = "Schedule event(s) from line(s)" }
	)

	vim.api.nvim_create_user_command("Note2calGoogleLogin", function()
		require("note2cal.google.auth").login(M.config.google, function(ok, err)
			if ok then
				vim.notify("[note2cal] Google Calendar authentication succeeded", vim.log.levels.INFO)
			else
				vim.notify(
					string.format("[note2cal] Google Calendar authentication failed: %s", err),
					vim.log.levels.ERROR
				)
			end
		end)
	end, { desc = "Authenticate note2cal with Google Calendar" })

	vim.api.nvim_create_user_command("Note2calGoogleLogout", function()
		require("note2cal.google.auth").logout(M.config.google, function()
			vim.notify("[note2cal] Google Calendar credentials removed", vim.log.levels.INFO)
		end)
	end, { desc = "Remove stored Google Calendar credentials" })
end

return M

local M = {}

M.default_config = {
	calendar_name = "Work",
	keymaps = {
		normal = "<Leader>se",
		visual = "<Leader>se",
	},
	highlights = {
		at_symbol = "WarningMsg",
		at_text = "Folded",
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

-- Extracted function to schedule events
function M.schedule_events(events)
	local script_lines = {
		"try",
		'  tell application "Calendar"',
	}

	for _, event in ipairs(events) do
		table.insert(script_lines, "    set startDate to (current date)")
		table.insert(script_lines, string.format("    set year of startDate to %s", event.year))
		table.insert(script_lines, string.format("    set month of startDate to %s", event.month))
		table.insert(script_lines, string.format("    set day of startDate to %s", event.day))
		table.insert(script_lines, string.format("    set hours of startDate to %s", event.start_hour))
		table.insert(script_lines, string.format("    set minutes of startDate to %s", event.start_min))
		table.insert(script_lines, "    set seconds of startDate to 0")
		table.insert(script_lines, "    copy startDate to endDate")
		table.insert(script_lines, string.format("    set hours of endDate to %s", event.end_hour))
		table.insert(script_lines, string.format("    set minutes of endDate to %s", event.end_min))
		table.insert(
			script_lines,
			string.format(
				'    make new event at calendar "%s" with properties {summary:"%s", start date:startDate, end date:endDate}',
				M.config.calendar_name,
				event.title
			)
		)
	end

	table.insert(script_lines, "  end tell")
	table.insert(script_lines, "on error errMsg")
	table.insert(script_lines, '  display dialog "Error: " & errMsg')
	table.insert(script_lines, "end try")

	local applescript_command = string.format("osascript -e '%s'", table.concat(script_lines, "\n"))

	if M.config.debug then
		-- Put debug information in a scratch buffer
		local buf = vim.api.nvim_create_buf(false, true)
		local debug_info = {
			"## [note2cal] Debug Information",
			"",
			string.format("**Events Count**: %d", #events),
			"**Events**:",
		}
		table.insert(debug_info, "")
		table.insert(debug_info, "**AppleScript**:")
		table.insert(debug_info, "```applescript")
		for _, line in pairs(script_lines) do
			table.insert(debug_info, line)
		end
		table.insert(debug_info, "```")

		vim.api.nvim_buf_set_lines(buf, 0, -1, false, debug_info)
		vim.api.nvim_command("split")
		vim.api.nvim_win_set_buf(0, buf)
		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
		vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
		vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
		vim.api.nvim_win_set_height(0, #debug_info + 1)
		return
	end

	-- Show initial notification
	vim.notify(string.format("Scheduling %d event(s)...", #events), vim.log.levels.INFO)

	-- Track if we've shown an error
	local error_shown = false

	-- Run AppleScript asynchronously
	vim.fn.jobstart(applescript_command, {
		on_exit = function(_, exit_code)
			if exit_code ~= 0 and not error_shown then
				vim.schedule(function()
					vim.notify(string.format("Failed to schedule %d events", #events), vim.log.levels.ERROR)
				end)
			elseif exit_code == 0 and not error_shown then
				vim.schedule(function()
					vim.notify(string.format("Successfully scheduled %d events", #events), vim.log.levels.INFO)
				end)
			end
		end,
		on_stderr = function(_, data)
			if data and #data > 0 and data[1] ~= "" and not data[1]:match("ApplePersistence=NO") then
				error_shown = true
				vim.schedule(function()
					vim.notify(
						string.format("Error scheduling events: %s", table.concat(data, "\n")),
						vim.log.levels.ERROR
					)
				end)
			end
		end,
	})
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
	M.config = vim.tbl_deep_extend("force", M.default_config, opts or {})

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
end

return M

-- The original provider: schedules events into macOS Calendar.app via
-- AppleScript. Behavior is unchanged from before providers existed; this is
-- still the default so existing configs keep working with no changes.
local M = {}

function M.schedule(events, config)
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
				config.macos.calendar_name,
				event.title
			)
		)
	end

	table.insert(script_lines, "  end tell")
	table.insert(script_lines, "on error errMsg")
	table.insert(script_lines, '  display dialog "Error: " & errMsg')
	table.insert(script_lines, "end try")

	local applescript_command = string.format("osascript -e '%s'", table.concat(script_lines, "\n"))

	if config.debug then
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
			if data and #data > 0 and data[1] ~= "" then
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

return M

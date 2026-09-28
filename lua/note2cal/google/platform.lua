-- Tiny OS-name helper shared by the browser-opener and the secret store
-- backend selection.
local M = {}

function M.name()
	local sysname = vim.uv.os_uname().sysname
	if sysname == "Darwin" then
		return "darwin"
	elseif sysname == "Linux" then
		return "linux"
	elseif sysname:match("^Windows") then
		return "windows"
	end
	return "other"
end

return M

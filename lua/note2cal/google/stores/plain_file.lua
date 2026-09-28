-- Plain JSON file, permissions restricted to the current user. This is the
-- unencrypted escape hatch: only used when google.security = "plain-file"
-- is set explicitly, or as a last-resort *read* fallback so switching away
-- from it doesn't strand an existing session (never used as a silent
-- *write* fallback from "os-key-store").
local M = {}

local function file_path()
	return vim.fn.stdpath("data") .. "/note2cal/google_token.json"
end

function M.available()
	return true
end

function M.save(token, callback)
	local path = file_path()
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")

	local fd, open_err = io.open(path, "w")
	if not fd then
		callback(false, "failed to open " .. path .. " for writing: " .. tostring(open_err))
		return
	end
	fd:write(vim.json.encode(token))
	fd:close()
	vim.fn.setfperm(path, "rw-------")
	callback(true)
end

function M.load(callback)
	local fd = io.open(file_path(), "r")
	if not fd then
		callback(nil)
		return
	end
	local content = fd:read("*a")
	fd:close()

	local ok, decoded = pcall(vim.json.decode, content)
	callback(ok and type(decoded) == "table" and decoded or nil)
end

function M.clear(callback)
	os.remove(file_path())
	callback(true)
end

return M

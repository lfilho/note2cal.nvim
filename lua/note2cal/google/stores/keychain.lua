-- macOS Keychain backend, via the built-in `security` CLI. No extra
-- install required.
--
-- Caveat: `security add-generic-password -w <value>` takes the secret as a
-- CLI argument, so it's briefly visible to other local processes via `ps`
-- during the call (inherent to the `security` CLI; there's no stdin option
-- for the password). Reads/deletes don't have this exposure.
local M = {}

local SERVICE = "note2cal.nvim"
local ACCOUNT = "google-oauth-token"

function M.available()
	return vim.fn.executable("security") == 1
end

function M.save(token, callback)
	local payload = vim.json.encode(token)
	vim.system(
		{ "security", "add-generic-password", "-a", ACCOUNT, "-s", SERVICE, "-w", payload, "-U" },
		{ text = true },
		function(res)
			vim.schedule(function()
				if res.code == 0 then
					callback(true)
				else
					callback(false, "macOS Keychain write failed: " .. tostring(res.stderr))
				end
			end)
		end
	)
end

function M.load(callback)
	vim.system(
		{ "security", "find-generic-password", "-a", ACCOUNT, "-s", SERVICE, "-w" },
		{ text = true },
		function(res)
			vim.schedule(function()
				if res.code ~= 0 then
					callback(nil)
					return
				end
				local ok, decoded = pcall(vim.json.decode, vim.trim(res.stdout or ""))
				callback(ok and decoded or nil)
			end)
		end
	)
end

function M.clear(callback)
	vim.system({ "security", "delete-generic-password", "-a", ACCOUNT, "-s", SERVICE }, { text = true }, function()
		vim.schedule(function()
			callback(true) -- succeed even if there was nothing to delete
		end)
	end)
end

return M

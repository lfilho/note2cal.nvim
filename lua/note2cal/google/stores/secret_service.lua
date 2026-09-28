-- Linux Secret Service (libsecret) backend, via `secret-tool`. Requires a
-- running keyring daemon (gnome-keyring/kwallet), which is commonly absent
-- on headless servers, containers, and minimal WSL installs -- in which
-- case `available()` may be true (the binary exists) but calls still fail,
-- and note2cal falls back to the GPG backend.
local M = {}

local ATTR_SERVICE = "note2cal.nvim"
local ATTR_ACCOUNT = "google-oauth-token"

function M.available()
	return vim.fn.executable("secret-tool") == 1
end

function M.save(token, callback)
	local payload = vim.json.encode(token)
	vim.system({
		"secret-tool",
		"store",
		"--label=note2cal Google Calendar token",
		"service",
		ATTR_SERVICE,
		"account",
		ATTR_ACCOUNT,
	}, { stdin = payload, text = true }, function(res)
		vim.schedule(function()
			if res.code == 0 then
				callback(true)
			else
				callback(false, "secret-tool store failed: " .. tostring(res.stderr))
			end
		end)
	end)
end

function M.load(callback)
	vim.system(
		{ "secret-tool", "lookup", "service", ATTR_SERVICE, "account", ATTR_ACCOUNT },
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
	vim.system({ "secret-tool", "clear", "service", ATTR_SERVICE, "account", ATTR_ACCOUNT }, { text = true }, function()
		vim.schedule(function()
			callback(true)
		end)
	end)
end

return M

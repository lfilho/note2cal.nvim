-- GPG-encrypted file fallback (the same idea `pass` is built on), used when
-- no native OS secret store is available (e.g. headless Linux with no
-- keyring daemon). Encrypts to the user's own default secret key, so
-- decryption is gated by gpg-agent's own passphrase cache -- independent of
-- note2cal, and often already tuned for infrequent prompts on machines that
-- already use gpg for commit signing or `pass`.
local M = {}

local function file_path()
	return vim.fn.stdpath("data") .. "/note2cal/google_token.json.gpg"
end

function M.available()
	return vim.fn.executable("gpg") == 1
end

function M.save(token, callback)
	local payload = vim.json.encode(token)
	local path = file_path()
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")

	vim.system(
		{ "gpg", "--batch", "--yes", "--quiet", "--default-recipient-self", "--encrypt", "-o", path },
		{ stdin = payload, text = true },
		function(res)
			vim.schedule(function()
				if res.code == 0 then
					callback(true)
				else
					callback(
						false,
						"gpg encryption failed (do you have a default secret key? check `gpg --list-secret-keys`): "
							.. tostring(res.stderr)
					)
				end
			end)
		end
	)
end

function M.load(callback)
	local path = file_path()
	if vim.fn.filereadable(path) == 0 then
		callback(nil)
		return
	end

	vim.system({ "gpg", "--batch", "--quiet", "--decrypt", path }, { text = true }, function(res)
		vim.schedule(function()
			if res.code ~= 0 then
				callback(nil)
				return
			end
			local ok, decoded = pcall(vim.json.decode, res.stdout or "")
			callback(ok and decoded or nil)
		end)
	end)
end

function M.clear(callback)
	os.remove(file_path())
	callback(true)
end

return M

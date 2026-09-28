-- Chooses where the Google OAuth token is persisted, based on
-- `google.security` ("os-key-store" (default) | "plain-file") and what's
-- actually available on this machine.
--
-- "os-key-store" tries the native OS secret store first (macOS Keychain /
-- Linux Secret Service / Windows DPAPI), then a GPG-encrypted file, and
-- *never* silently falls back to plaintext: if neither is available, save()
-- reports a clear error instead of writing an unencrypted file. Only an
-- explicit `google.security = "plain-file"` writes plaintext.
local platform = require("note2cal.google.platform")

local M = {}

local function native_backend()
	local name = platform.name()
	if name == "darwin" then
		return require("note2cal.google.stores.keychain")
	elseif name == "linux" then
		return require("note2cal.google.stores.secret_service")
	elseif name == "windows" then
		return require("note2cal.google.stores.dpapi")
	end
	return nil
end

local function gpg_backend()
	return require("note2cal.google.stores.gpg")
end

local function plain_file_backend()
	return require("note2cal.google.stores.plain_file")
end

--- Backends allowed to be *written* to for the given security mode, in
--- priority order. "os-key-store" never includes the plain file here.
local function write_candidates(security)
	if security == "plain-file" then
		return { plain_file_backend() }
	end

	local list = {}
	local native = native_backend()
	if native and native.available() then
		table.insert(list, native)
	end
	if gpg_backend().available() then
		table.insert(list, gpg_backend())
	end
	return list
end

--- Backends worth *reading* from, in priority order. Same as
--- write_candidates, plus the plain file as a last-resort read so switching
--- security modes doesn't strand an existing session.
local function read_candidates(security)
	local list = write_candidates(security)
	if security ~= "plain-file" then
		table.insert(list, plain_file_backend())
	end
	return list
end

--- Saves to the single best available backend for `security`. Never falls
--- back to plaintext on failure. callback(ok, err).
function M.save(security, token, callback)
	local backend = write_candidates(security)[1]
	if not backend then
		callback(
			false,
			'no secure credential store is available (no OS keychain/secret-service, and no usable "gpg" key found). '
				.. 'Install/enable one of those, or explicitly set google.security = "plain-file" to accept an '
				.. "unencrypted token file."
		)
		return
	end
	backend.save(token, callback)
end

--- Tries each plausible backend in priority order and returns the first
--- token found. callback(token_or_nil).
function M.load(security, callback)
	local list = read_candidates(security)
	local i = 0

	local function try_next()
		i = i + 1
		local backend = list[i]
		if not backend then
			callback(nil)
			return
		end
		backend.load(function(token)
			if token then
				callback(token)
			else
				try_next()
			end
		end)
	end

	try_next()
end

--- Clears every backend that might plausibly be holding a token, regardless
--- of the currently configured security mode, so switching modes never
--- leaves a stale credential behind. callback(ok).
function M.clear(callback)
	local list = read_candidates("os-key-store") -- native + gpg + plain-file
	local remaining = #list

	if remaining == 0 then
		callback(true)
		return
	end

	for _, backend in ipairs(list) do
		backend.clear(function()
			remaining = remaining - 1
			if remaining == 0 then
				callback(true)
			end
		end)
	end
end

return M

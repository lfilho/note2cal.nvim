-- Google OAuth for the "google" provider, using the loopback-redirect flow
-- Google recommends for installed/desktop apps (the old copy/paste "OOB"
-- flow was deprecated in 2022). Nothing here talks to anything but Google:
-- the loopback HTTP listener only exists to catch the browser redirect on
-- this machine, and tokens are exchanged with a direct HTTPS call to
-- Google's token endpoint via curl. Where the resulting token is persisted
-- is delegated to secret_store (OS keychain / GPG / plain file).
local http = require("note2cal.google.http")
local util = require("note2cal.google.util")
local secret_store = require("note2cal.google.secret_store")

local M = {}

local AUTH_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth"
local TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
local REVOKE_ENDPOINT = "https://oauth2.googleapis.com/revoke"
local DEFAULT_SCOPE = "https://www.googleapis.com/auth/calendar.events"

local function security_mode(config)
	return (config and config.security) or "os-key-store"
end

-- Neither client_id nor client_secret are valid setup() fields: both must
-- come from the environment, so a public dotfiles repo can never contain
-- either value, even by accident (see the "Google Calendar setup" guide).
local function resolve_credentials()
	return vim.env.NOTE2CAL_GOOGLE_CLIENT_ID, vim.env.NOTE2CAL_GOOGLE_CLIENT_SECRET
end

local function open_url(url)
	local sysname = vim.uv.os_uname().sysname
	local cmd
	if sysname == "Darwin" then
		cmd = { "open", url }
	elseif sysname == "Linux" then
		cmd = { "xdg-open", url }
	elseif sysname:match("^Windows") then
		cmd = { "cmd.exe", "/c", "start", "", url }
	end

	if cmd then
		pcall(vim.system, cmd, { detach = true })
	end

	vim.notify(
		string.format(
			"[note2cal] Opening your browser to authenticate with Google.\nIf it doesn't open automatically, visit:\n%s",
			url
		),
		vim.log.levels.INFO
	)
end

-- Starts a one-shot loopback HTTP listener to receive the OAuth redirect.
-- Returns the bound port synchronously; `on_result(code, err)` fires later,
-- exactly once, when the browser redirect (or a listener error) arrives.
local function start_loopback_server(expected_state, on_result)
	local server = vim.uv.new_tcp()
	server:bind("127.0.0.1", 0)
	local port = server:getsockname().port
	local done = false

	local function finish(code, err)
		if done then
			return
		end
		done = true
		-- We're invoked from a raw libuv callback here (not the main
		-- event loop), where vim.notify/vim.api.* are unsafe to call.
		-- `on_result` (and anything it calls) may call into either, so
		-- hop back onto the main loop first.
		vim.schedule(function()
			on_result(code, err)
		end)
	end

	server:listen(1, function(listen_err)
		if listen_err then
			finish(nil, "listen error: " .. listen_err)
			return
		end

		local client = vim.uv.new_tcp()
		server:accept(client)

		client:read_start(function(read_err, chunk)
			if read_err then
				pcall(function()
					client:close()
				end)
				finish(nil, "connection error: " .. read_err)
				return
			end
			if not chunk or not chunk:find("\n") then
				return -- wait for the rest of the request line
			end

			pcall(function()
				client:read_stop()
			end)

			local request_line = chunk:match("^(.-)\r?\n") or ""
			local query = request_line:match("^GET%s+/?%??(%S*)%s+HTTP")

			local body = "<html><body>note2cal: authentication received, you can close this tab.</body></html>"
			local response = table.concat({
				"HTTP/1.1 200 OK",
				"Content-Type: text/html; charset=utf-8",
				"Content-Length: " .. #body,
				"Connection: close",
				"",
				body,
			}, "\r\n")

			client:write(response, function()
				pcall(function()
					client:close()
					server:close()
				end)
			end)

			if not query then
				finish(nil, "malformed redirect request")
				return
			end

			local state = util.url_decode(query:match("[?&]state=([^&]+)"))
			local code = util.url_decode(query:match("[?&]code=([^&]+)"))
			local err_param = util.url_decode(query:match("[?&]error=([^&]+)"))

			if state ~= expected_state then
				finish(nil, "state mismatch on redirect; ignoring (possible CSRF)")
			elseif code then
				finish(code, nil)
			else
				finish(nil, err_param or "no authorization code received")
			end
		end)
	end)

	return port
end

--- Interactively authenticate with Google: opens the system browser, the
--- user approves access, the authorization code is exchanged for tokens and
--- persisted to disk. `callback(ok, err)`.
function M.login(config, callback)
	callback = callback or function() end
	config = config or {}

	local client_id, client_secret = resolve_credentials()
	if not client_id or not client_secret then
		callback(
			false,
			"NOTE2CAL_GOOGLE_CLIENT_ID and NOTE2CAL_GOOGLE_CLIENT_SECRET environment variables must both be set; "
				.. 'see the "Google Calendar setup" guide'
		)
		return
	end

	local scope = config.scope or DEFAULT_SCOPE
	local state = util.random_state()

	local port = start_loopback_server(state, function(code, err)
		if not code then
			callback(false, "authorization failed: " .. tostring(err))
			return
		end

		local redirect_uri = string.format("http://127.0.0.1:%d/", port)
		local body = util.build_query({
			code = code,
			client_id = client_id,
			client_secret = client_secret,
			redirect_uri = redirect_uri,
			grant_type = "authorization_code",
		})

		http.request({
			method = "POST",
			url = TOKEN_ENDPOINT,
			headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
			body = body,
		}, function(ok, result)
			if not ok or not result.decoded or not result.decoded.access_token then
				callback(false, "token exchange failed: " .. tostring(result and result.body))
				return
			end

			local token = result.decoded
			token.expires_at = os.time() + (token.expires_in or 3600) - 60

			if not token.refresh_token then
				callback(
					false,
					"Google did not return a refresh_token; revoke access at "
						.. "https://myaccount.google.com/permissions and run :Note2calGoogleLogin again"
				)
				return
			end

			secret_store.save(security_mode(config), token, function(saved, save_err)
				if not saved then
					callback(false, save_err)
					return
				end
				callback(true)
			end)
		end)
	end)

	local redirect_uri = string.format("http://127.0.0.1:%d/", port)
	local auth_url = AUTH_ENDPOINT
		.. "?"
		.. util.build_query({
			client_id = client_id,
			redirect_uri = redirect_uri,
			response_type = "code",
			scope = scope,
			-- access_type=offline + prompt=consent guarantee a refresh_token
			-- comes back every time (Google otherwise omits it on repeat
			-- consents), so access-token renewal never needs the browser.
			access_type = "offline",
			prompt = "consent",
			state = state,
		})

	open_url(auth_url)
end

--- Ensures a valid access token, silently refreshing via the stored
--- refresh_token when the cached access token has expired. Never opens a
--- browser; if there's no usable refresh_token it tells the caller to run
--- :Note2calGoogleLogin instead. `callback(access_token_or_nil, err_or_nil)`.
function M.ensure_access_token(config, callback)
	local security = security_mode(config)
	local client_id, client_secret = resolve_credentials()

	secret_store.load(security, function(token)
		if not token then
			callback(nil, "not authenticated with Google Calendar; run :Note2calGoogleLogin")
			return
		end

		if not util.is_token_expired(token) then
			callback(token.access_token)
			return
		end

		if not token.refresh_token then
			callback(nil, "stored Google token has no refresh_token; run :Note2calGoogleLogin")
			return
		end

		local body = util.build_query({
			refresh_token = token.refresh_token,
			client_id = client_id,
			client_secret = client_secret,
			grant_type = "refresh_token",
		})

		http.request({
			method = "POST",
			url = TOKEN_ENDPOINT,
			headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
			body = body,
		}, function(ok, result)
			if not ok or not result.decoded or not result.decoded.access_token then
				-- The refresh_token itself is dead: revoked, or the consent
				-- screen is still in "Testing" and hit Google's 7-day expiry.
				secret_store.clear(function() end)
				callback(
					nil,
					"Google token refresh failed, run :Note2calGoogleLogin again: "
						.. tostring(result and result.body)
				)
				return
			end

			local new_token = result.decoded
			-- Refresh responses normally omit refresh_token; keep the one we have.
			new_token.refresh_token = new_token.refresh_token or token.refresh_token
			new_token.expires_at = os.time() + (new_token.expires_in or 3600) - 60

			secret_store.save(security, new_token, function(saved, save_err)
				if not saved then
					vim.notify(
						string.format("[note2cal] Warning: failed to persist refreshed Google token: %s", save_err),
						vim.log.levels.WARN
					)
				end
				callback(new_token.access_token)
			end)
		end)
	end)
end

--- Revokes (best-effort) and deletes any stored Google credentials.
--- `callback(ok)`.
function M.logout(config, callback)
	callback = callback or function() end

	secret_store.load(security_mode(config), function(token)
		local revoke_target = token and (token.refresh_token or token.access_token)

		local function finish()
			secret_store.clear(function()
				callback(true)
			end)
		end

		if not revoke_target then
			finish()
			return
		end

		http.request({
			method = "POST",
			url = REVOKE_ENDPOINT,
			headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
			body = util.build_query({ token = revoke_target }),
		}, function()
			finish()
		end)
	end)
end

return M

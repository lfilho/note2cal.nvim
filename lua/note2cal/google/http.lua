-- Thin async HTTP client backed by the system `curl` binary. Used for every
-- direct-to-Google request (token exchange, refresh, revoke, event
-- creation). No plugin-hosted server is ever involved.
local M = {}

--- opts: { method, url, headers = {k=v}, body = string|nil, timeout = seconds }
--- callback(ok, result): `result` is `{status, body, decoded}` whether or
--- not `ok` is true; `ok` is false for network failures, non-2xx status, or
--- when curl itself couldn't run.
function M.request(opts, callback)
	local args = { "curl", "-sS", "--max-time", tostring(opts.timeout or 15), "-X", opts.method or "GET" }

	for k, v in pairs(opts.headers or {}) do
		table.insert(args, "-H")
		table.insert(args, string.format("%s: %s", k, v))
	end

	if opts.body then
		table.insert(args, "--data-raw")
		table.insert(args, opts.body)
	end

	table.insert(args, "-w")
	table.insert(args, "\n%{http_code}")
	table.insert(args, opts.url)

	vim.system(args, { text = true, timeout = (opts.timeout or 15) * 1000 }, function(res)
		vim.schedule(function()
			if res.code ~= 0 then
				callback(false, { status = nil, body = res.stderr, decoded = nil })
				return
			end

			local stdout = res.stdout or ""
			local body, status = stdout:match("^(.*)\n(%d+)%s*$")
			if not status then
				callback(false, { status = nil, body = stdout, decoded = nil })
				return
			end

			local ok, decoded = pcall(vim.json.decode, body)
			local result = {
				status = tonumber(status),
				body = body,
				decoded = ok and decoded or nil,
			}

			callback(result.status >= 200 and result.status < 300, result)
		end)
	end)
end

return M

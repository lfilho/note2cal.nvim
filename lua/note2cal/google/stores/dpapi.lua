-- Windows backend using PowerShell's built-in DPAPI-backed SecureString
-- conversion (ConvertTo-SecureString / ConvertFrom-SecureString with no
-- explicit -Key), scoped to the current user+machine. No extra install:
-- every supported Windows ships PowerShell.
local M = {}

local function file_path()
	return vim.fn.stdpath("data") .. "/note2cal/google_token.dpapi"
end

local function powershell()
	return vim.fn.executable("pwsh") == 1 and "pwsh" or "powershell.exe"
end

function M.available()
	return vim.fn.executable("powershell.exe") == 1 or vim.fn.executable("pwsh") == 1
end

-- PowerShell single-quoted string literal escaping (double any embedded ').
local function ps_quote(str)
	return "'" .. str:gsub("'", "''") .. "'"
end

function M.save(token, callback)
	local payload = vim.json.encode(token)
	local path = file_path()
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")

	local script = string.format(
		[[
$ErrorActionPreference = 'Stop'
$plain = [Console]::In.ReadToEnd()
$secure = ConvertTo-SecureString -String $plain -AsPlainText -Force
$encrypted = ConvertFrom-SecureString -SecureString $secure
Set-Content -Path %s -Value $encrypted -NoNewline
]],
		ps_quote(path)
	)

	vim.system(
		{ powershell(), "-NoProfile", "-NonInteractive", "-Command", script },
		{ stdin = payload, text = true },
		function(res)
			vim.schedule(function()
				if res.code == 0 then
					callback(true)
				else
					callback(false, "DPAPI write failed: " .. tostring(res.stderr))
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

	local script = string.format(
		[[
$ErrorActionPreference = 'Stop'
$encrypted = Get-Content -Path %s -Raw
$secure = ConvertTo-SecureString -String $encrypted
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
[Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
]],
		ps_quote(path)
	)

	vim.system({ powershell(), "-NoProfile", "-NonInteractive", "-Command", script }, { text = true }, function(res)
		vim.schedule(function()
			if res.code ~= 0 then
				callback(nil)
				return
			end
			local ok, decoded = pcall(vim.json.decode, vim.trim(res.stdout or ""))
			callback(ok and decoded or nil)
		end)
	end)
end

function M.clear(callback)
	os.remove(file_path())
	callback(true)
end

return M

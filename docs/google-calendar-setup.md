## Google Calendar setup

The `google` provider creates events directly in Google Calendar over HTTPS. **Each user authenticates using their own free Google Cloud OAuth client**. This is a one-time, ~5 minute setup.

### 1. Create a Google Cloud project and enable the Calendar API

1. Go to the [Google Cloud Console](https://console.cloud.google.com/) and create a new project (or reuse an existing personal one).
2. In **APIs & Services → Library**, search for **Google Calendar API** and click **Enable**.

### 2. Configure the OAuth consent screen

1. Go to **APIs & Services → OAuth consent screen**.
2. User type: **External** (this is fine for personal/self-serve use; it doesn't mean the public can use it).
3. Fill in the required app name/support email/developer contact fields with your own.
4. Under **Scopes**, add `https://www.googleapis.com/auth/calendar.events` (view/edit events — intentionally narrower than full calendar access).
5. Under **Test users**, add your own Google account email.
6. **Publish the app** (consent screen → **Publish App**, confirm "In production").
7. You may need to add some fake URLs to your "project" - add anything, you're the only "client" here.

> [!IMPORTANT]
> Publishing to production is highly encouraged. If the consent screen is left in "Testing", Google forcibly expires your refresh token every 7 days, which means `:Note2calGoogleLogin` would silently stop working weekly. 

### 3. Create OAuth client credentials

1. Go to **APIs & Services → Credentials → Create Credentials → OAuth client ID**.
2. Application type: **Desktop app**.
3. Give it any name (e.g. "note2cal.nvim") and click **Create**.
4. Copy the generated **Client ID** and **Client secret**.

### 4. Configure the plugin

```lua
require("note2cal").setup({
  provider = "google",
  google = {
    calendar_id = "primary", -- "primary" for your default calendar, or a specific calendar's ID.
    security = "os-key-store", -- "os-key-store" (default) or "plain-file (not recommended)"
  },
})
```

Set the client secret and id from step 3 as an environment variables somewhere in your dotfiles:

```sh
export NOTE2CAL_GOOGLE_CLIENT_SECRET="your-client-secret"
export NOTE2CAL_GOOGLE_CLIENT_ID="your-client-id.apps.googleusercontent.com"
```

> [!IMPORTANT]
> **Never put these in a committed dotfiles config.** Once your consent screen is published, anyone with your client_id/secret can run the same authorization flow against *your* Google Cloud project (getting a token for their own account, not yours), which can burn your project's quota or trip Google's abuse detection and get your own app suspended.

### 5. Log in

Run `:Note2calGoogleLogin` once. Your browser opens, you approve access, and note2cal exchanges that for a token, which it then stores using whichever [credential storage](#where-credentials-are-stored) backend is active (an OS keychain by default).

From then on, access is refreshed automatically in the background. You should not need to re-run `:Note2calGoogleLogin` for routine use, only if you explicitly revoke access (`:Note2calGoogleLogout`, or from your [Google Account permissions page](https://myaccount.google.com/permissions)) or don't use it for 6+ months.

If you ever see an authentication error, just run `:Note2calGoogleLogin` again.

### Commands

| Command                 | Effect                                                              |
| ------------------------ | -------------------------------------------------------------------- |
| `:Note2calGoogleLogin`  | Opens your browser to (re)authenticate with Google |
| `:Note2calGoogleLogout` | Revokes and deletes the locally cached Google token                |

### Where credentials are stored

`google.security` controls this — `"os-key-store"` (the default) or `"plain-file"`:

- **`"os-key-store"` (default):** tries a native OS secret store first, then falls back to a GPG-encrypted file. **It never silently writes an unencrypted file.** If neither is available, `:Note2calGoogleLogin` fails with a clear error instead of quietly falling back to plaintext.
  - macOS: the login Keychain, via the built-in `security` CLI. (Caveat: `security`'s write command takes the secret as a CLI argument, so it's briefly visible to other local processes via `ps` during that one call; reads and deletes don't have this exposure.)
  - Linux: the Secret Service API (GNOME Keyring / KWallet), via `secret-tool`. Requires a running keyring daemon — commonly unavailable on headless servers, containers, or minimal WSL, in which case note2cal automatically falls through to GPG.
  - Windows: DPAPI (`ConvertTo-SecureString`/`ConvertFrom-SecureString`), via the `powershell.exe`/`pwsh` that ships with Windows — no extra install.
  - GPG fallback (any OS): encrypts to your own default GPG secret key (the same idea `pass` is built on). Requires `gpg` and an existing default secret key (`gpg --list-secret-keys`); decrypt prompts are governed by your `gpg-agent`'s own passphrase cache, not by note2cal.
- **`"plain-file"`:** an explicit opt-in to a plain JSON file (permissions restricted to your user), for when you'd rather not depend on a keyring or GPG. 

`:Note2calGoogleLogout` clears the token from every backend it might be sitting in, so switching `security` modes never leaves an orphaned credential behind.

### Privacy / security notes

- Your `client_id`/`client_secret` and token never leave your machine or go through any third-party server — note2cal talks directly to `accounts.google.com` / `oauth2.googleapis.com` / `www.googleapis.com` via `curl`.
- The plugin author has no access to, and never sees, any user's Google credentials or calendar data — there is no shared backend and no shared OAuth client.
- Requires `curl` on your `PATH`, and a way to open a URL in a browser (`open` on macOS, `xdg-open` on Linux, or `start` on Windows).

# note2cal.nvim

`note2cal` is a Neovim plugin designed to quickly create events directly from markdown files. Making for a great companion to whatever note taking flow you use.

With one keymap (or one command), a line like `Do something @ 3pm-4pm` or `Do something @ 2025-01-20 3pm-4pm` will be converted to an accordingly named event in your calendar at that specified time. See more ways to specifying the time in the [Supported Formats](#supported-formats) section.

![Demo](https://github.com/user-attachments/assets/07f8e0c2-c61d-4e54-8d62-4af082193f56)

## Limitations

Contributions are welcome!

- MacOS only for now as it requires the Calendar.app and AppleScript.
- There's a wide range of supported **time** formats (see below), but for now the only supported **date** format is `YYYY-MM-DD`.
- No support for multi-day events yet.
- Works in Markdown files only for now.

## Supported Formats

We support various time formats, including 24-hour, AM/PM, military time, and compact formats.
The following table summarizes it, you can also see the [spec](spec/note2cal_spec.lua) for more examples:

| Example Input   | Parsed into (formatted here in this table as 24-hour HH:MM-HH:MM for clarity) |
| --------------- | ----------------------------------------------------------------------------- |
| `6-7`           | `06:00-07:00`                                                                 |
| `3-430`         | `03:00-04:30`                                                                 |
| `3p-4p`         | `15:00-16:00`                                                                 |
| `3pm-4pm`       | `15:00-16:00`                                                                 |
| `12pm-1pm`      | `12:00-13:00`                                                                 |
| `12am-1am`      | `00:00-01:00`                                                                 |
| `0500-1730`     | `05:00-17:30`                                                                 |
| `3:15-4:30`     | `03:15-04:30`                                                                 |
| `315a-430a`     | `03:15-04:30`                                                                 |
| `315am-430am`   | `03:15-04:30`                                                                 |
| `3:15am-4:30am` | `03:15-04:30`                                                                 |

## Installation and configuration

Example using Lazy (the values listed are the default ones):

```lua
{
  'lfilho/note2cal.nvim',
  config = function()
    require("note2cal").setup({
      debug = false, -- if true, prints a debug message an return early (won't schedule events)
      calendar_name = "Work", -- the name of the calendar as it appear on Calendar.app
      highlights = {
        at_symbol = "WarningMsg", -- the highlight group for the "@" symbol
        at_text = "Number", -- the highlight group for the date-time part
      },
      keymaps = {
          normal = "<Leader>se", -- mnemonic: Schedule Event
          visual = "<Leader>se", -- mnemonic: Schedule Event
      },
    })
  end,
  ft = "markdown",
},

```

## Usage

It works in normal mode and visual mode (single or multiple lines).
Just call it with the keymap you configured above or invoke the command `:Note2cal` in the desired lines.

> [!NOTE]
>
> - If no date is provided, the script assumes today's date.
> - Even if the Calendar.app is not open, the script will open it in the background in order to schedule the event.

## Contributing

Contributions are welcome!

- Make sure to have lua, luarocks and busted installed (e.g.: `brew install lua luarocks && luarocks install busted`).
- Run tests with `./scripts/test.sh`.

## Ideas / TODOs

- Make `:Note2cal` command take a range
- Make the current `@` pattern configurable.
- Compile the applescript for slightly better performance.
- Add a conceal / virtual icon to denote the event was scheduled.
- Add support for other file types other than markdown.
- Add support for other date formats other than `YYYY-MM-DD`.
- Run tests on Github on push to main.
- Add icon to sign column to indicate there's an event in that line.
- Support natural language (@ tomorrow, @ next tuesday, etc). Thanks u/my_mix_still_sucks on reddit for the suggestion

## Similar plugins

None that I know of, feel free to send me a PR to list it here!

- https://github.com/itchyny/calendar.vim → ❌ It brings a read-only calendar view to inside vim, not what we do)

## Related plugins

This plugin would be a great addition to note taking or task management plugins, such as:

- https://github.com/atiladefreitas/dooing
- https://github.com/zk-org/zk-nvim
- https://github.com/vimwiki/vimwiki
- and probably many others :)

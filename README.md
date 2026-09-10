# Next Theme

A single bar icon that steps through your Omarchy themes in order.

- **Left click** — open a popup naming the current theme, with Previous and
  Next buttons that step through `omarchy theme list`, wrapping at the ends.
- **Scroll** — step forward or back without opening the popup.
- **Hover** — the tooltip names the current theme.

The popup stays open while you step, and its name and colours follow each
theme as it is applied, so you can walk the list and stop where you like.

Right and middle clicks do nothing. No settings, no schedule. If you want
random rotation or sunrise/sunset switching, use `tim.theme-rotate` instead —
this one is deliberately just "one step at a time".

## The icon

The classic contrast circle: an outlined ring with its right half filled. Every
applied theme rotates it a half turn clockwise, so the light and dark halves
trade places. If the change fails, the icon rotates back rather than leaving a
flip that claims something happened.

## Install

```
omarchy plugin add https://github.com/<owner>/omarchy-next-theme --enable
```

## What it does to your system

Applying a theme is the plugin's entire purpose, and it does that by calling
`omarchy theme set`, the stock Omarchy command. That command — not this plugin —
rewrites the theme-derived parts of your terminal, editor and compositor
configuration and reloads the shell. This plugin never edits those files itself.

- **Network access:** none. Nothing here opens a socket or fetches a URL.
- **Files written:** none. The plugin has no state, settings or cache of its own,
  and writes nothing outside what `omarchy theme set` already does.
- **Credentials:** none read, stored or transmitted.
- **Commands run:** `omarchy theme current`, `omarchy theme list`, and
  `omarchy theme set <name>`, each in its own session under an absolute
  deadline with its output capped at the producer.
- **On load:** reads the current theme name. Nothing is installed, downloaded,
  built or written when the plugin starts.
- **IPC:** `open`, `close`, `toggle`, `show` and `hide`, all parameterless and
  limited to showing or hiding the popup. None of them change a theme.

Theme names are directory names, and `omarchy theme install <git-url>` lets a
third party choose one. They are treated as untrusted: the helper refuses names
that are option-shaped, carry non-printable bytes, or exceed 128 bytes, and the
widget strips `<`, `>`, `&`, C0/C1 controls and bidi overrides before the name
reaches the bar tooltip.

## Removing this plugin

Run:

```
omarchy plugin remove chyld.next-theme
```

That deletes the plugin directory and its bar entry. Nothing else survives
removal: no daemons, timers, hooks, sudoers rules, polkit actions, symlinks,
packages or state files, because the plugin creates none of them.

The theme that was active when you removed the plugin stays active. To change
it afterwards, use `omarchy theme set <name>` or the theme switcher.

## Files

| File | Purpose |
|------|---------|
| `BarWidget.qml` | The icon, its rotation, the popup, and click/scroll handling |
| `bin/next-theme.sh` | Resolves the next, previous, or current theme and applies it |
| `tests/` | Validator and sanitiser cases, run with the commands below |

## Tests

```
tests/validate-name.test.sh
node tests/sanitize.test.mjs
```

Both extract the functions they test out of the shipped files rather than
copying them, so they exercise the code that actually runs.

## License

MIT

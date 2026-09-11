# Omadocked

A native dock for [Omarchy](https://omarchy.org): running apps, pins, folders, and custom launchers on every selected display.

Plugin id: `burmjohn.omadocked`.

![The dock](docs/screenshots/dock.png)

![Hover](docs/screenshots/dock-hover.png)

## What it does

Omadocked is a bottom shelf overlay for Hyprland and Omarchy. It shows pinned and running apps, optional folders, and custom launchers, plus a hover window fan with still previews. Settings cover icon size, transparency, magnification, auto-hide, and which outputs show the dock.

Click-to-minimize can be off, the active window, or all windows of an app.

Settings and pins are stored in `~/.config/omadocked/pins.json`.

## Features

- Bottom shelf on the displays you choose
- Wave or zoom magnification, or motion off
- Pins, running apps, folders, and optional names
- Hover window fan with still previews
- Settings for size, transparency, auto-hide, and outputs
- Custom launchers: apps, commands, links, and folders
- Click-to-minimize: active window, all windows, or off

## Install

```sh
omarchy plugin add https://github.com/burmjohn/omadocked --enable
omarchy-launch-shell
```

That restarts the Omarchy shell only, not the session.

## Remove

```sh
omarchy plugin disable burmjohn.omadocked
```

Your `pins.json` is left in place until you delete it.

## Feedback

This is an early public preview. Bug reports, ideas, and pull requests are welcome.

- [Open an issue](https://github.com/burmjohn/omadocked/issues)
- [Open a pull request](https://github.com/burmjohn/omadocked/pulls)

Please include Omarchy and Quickshell versions and steps to reproduce. Do not attach private window titles, notification text, or an unredacted `pins.json`.

## Requirements

- [Omarchy](https://omarchy.org) with Quickshell
- Hyprland
- `python3` and `python-gobject` for desktop-entry launches
- `xdg-terminal-exec` only if you use command-in-terminal items

Version is `0.1.2` in [`manifest.json`](manifest.json). See [CHANGELOG.md](CHANGELOG.md).

## Development

```sh
make preview          # standalone dock, no plugin install
make test             # spawn-safety guards
make test-offscreen   # offscreen Qt tests
make lint
```

## License

[MIT](LICENSE).

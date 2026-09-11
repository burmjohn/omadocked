# Omadocked

A native dock for [Omarchy](https://omarchy.org): running apps, pins, folders, and custom launchers on every selected display.

Plugin id: `burmjohn.omadocked`.

![Omadocked](docs/screenshots/shelf.png)

## Features

- Bottom shelf on the displays you choose
- Wave or zoom magnification, or motion off
- Pins, running apps, folders, and optional names
- Hover window fan with still previews
- Settings for size, transparency, auto-hide, and outputs
- Custom launchers: apps, commands, links, and folders
- Click-to-minimize: active window, all windows, or off

![Settings](docs/screenshots/settings.png)

Settings and pins are stored in `~/.config/omadocked/pins.json`.

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

## Development

```sh
make preview          # standalone dock, no plugin install
make test             # spawn-safety guards
make test-offscreen   # offscreen Qt tests
make lint
```

## License

[MIT](LICENSE). Bugs and ideas: [issues](https://github.com/burmjohn/omadocked/issues).

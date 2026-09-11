# Omadocked

Native Omarchy dock plugin (`burmjohn.omadocked`).

## Install

```sh
omarchy plugin add https://github.com/burmjohn/omadocked --enable
```

Then restart the Omarchy shell (not the session):

```sh
omarchy-launch-shell
```

Disable the older **Omadock** plugin if both would show.

## Remove

```sh
omarchy plugin disable burmjohn.omadocked
```

Pins stay in `~/.config/omadocked/pins.json` until you delete that file.

## Preview (no install)

```sh
make preview
```

## Tests

```sh
make test
make test-offscreen
make lint
```

## License

MIT. Issues: https://github.com/burmjohn/omadocked/issues

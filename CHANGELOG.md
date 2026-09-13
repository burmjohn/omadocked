# Changelog

## 0.1.4 — 2026-09-13

Idle lock on the Omadocked host overlay inherits `OMARCHY_PATH` (`bash -c`
instead of a login shell), so `omarchy-system-lock` reaches the running locker
instead of no-op'ing against stock omarchy-shell. See [docs/idle-lock.md](docs/idle-lock.md).

## 0.1.3 — 2026-09-12

Omarchy menu button left of Settings. Settings keeps the shelf in place when
opening, and a click outside the panel closes it.

## 0.1.2 — 2026-09-11

Parking session rollover, identity rebind, importer destination validation,
folder trailing-slash rejection, fail-closed host privacy, and Settings layout
fixes from the 0.1.1 QA report.

## 0.1.1 — 2026-09-11

Marketplace packaging: MIT `license` in the manifest, root `preview.png`, install/remove docs, and README screenshots.

## 0.1.0 — 2026-09-11

First public source of Omadocked (`burmjohn.omadocked`).

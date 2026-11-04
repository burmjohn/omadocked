# Changelog

## 0.1.7 — Unreleased

- Keep Settings stationary through launch/error status changes; consume outside
  editor gestures without launching apps and freeze inputs during pending saves.
- Preserve keyboard access when the Settings icon is hidden, cancel held
  Settings gestures on scroll, and avoid postponing hover fans on title updates.
- Correct initial folder Up navigation, show app names in launch feedback and
  label click-to-minimize controls.
- Dispatch workspace-scroll actions through Hyprland's Lua dispatcher instead
  of only constructing an action.
- Bound launcher-helper lifetime independently of window feedback; allow
  parking/recovery enough time for sequential helper operations.
- Preserve group restore/close requests across typed QML sequence boundaries
  while retaining exact-key, membership and duplicate checks.
- Qualify host theme imports so theme colors and opacity bind correctly.
- Avoid a Quickshell socket-error reentrancy crash on invalid or truncated
  overlap replies; retain bounded parsing and cancellation.
- Import through the existing configuration Store lease and durable commit path;
  refuse busy owners without touching main or backups and preserve receipts.
- Refuse missing import sources, preserve the original import backup on repeat
  attempts, and reject reserved chrome IDs consistently with the runtime.
- Import explicit numeric icon sizes instead of silently omitting them.
- Preserve existing icon-matching/fallback, compact badge and folder-startup
  fixes; test private scratch paths and short offscreen IPC runtimes explicitly.
- Document parked-window recovery before disabling and the re-enable route.
- Clarify stock-host privacy/notification API limitations; document the tested
  dependency baseline, update/rollback behavior and actual uninstall command.
- Settings can separately show hidden-workspace apps in their own
  shelf area, and hide apps that are already visible on a screen.

## 0.1.6 — 2026-09-28

Window-count badges can be placed in any icon corner and have independently
configurable background and text colors (`theme` or `#RRGGBB`). The choices
persist in Settings → Badges. The attention dot moves out of the way when a
badge occupies the top-right corner.

## 0.1.5 — 2026-09-19

Omadocked is a dock plugin. Stop documenting or testing a host Omarchy overlay
under `~/.local/share/omadocked/omarchy`. Idle and lock stay on packaged
Omarchy (`/usr/share/omarchy`).

## 0.1.4 — 2026-09-13

Idle lock on the Omadocked host overlay inherits `OMARCHY_PATH` (`bash -c`
instead of a login shell), so `omarchy-system-lock` reaches the running locker
instead of no-op'ing against stock omarchy-shell. Superseded in 0.1.5.

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

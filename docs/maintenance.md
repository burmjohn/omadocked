# Compatibility and maintenance

## Verified dependency baseline

The November 2026 review used these installed versions. This is a tested
baseline, **not** a proven minimum-version matrix:

| Component | Version |
|---|---|
| Omarchy | 4.0.6 |
| Hyprland | 0.56.2 |
| Quickshell | 0.3.2.r7.g2b4501a |
| Qt Base / Declarative / Wayland | 6.12.0 |
| Python / PyGObject | 3.14.8 / 3.58.1 |
| xdg-terminal-exec | 0.14.3 |

A fresh `checkupdates` database reported no pending package upgrades from the
configured repositories. The installed Quickshell build is newer than the stock
`extra/quickshell` 0.3.2 package; downgrading is not an update. No system packages
were changed during the review. This project does not have npm or pip dependency
lockfiles: its runtime comes from the host's packages.

Workspace scrolling and parking need Hyprland's Lua `hyprctl eval` API. Parking
also needs `hl.get_windows()`, numeric `stable_id` and Lua window dispatchers.
Older Hyprland releases are not certified by a successfully rendered shelf.
Theme integration uses Omarchy's `qs.Commons` Style and Color APIs.

Desktop-entry launch needs Python and PyGObject/Gio. Opening folder-stack items
needs `xdg-open`; command-in-terminal and folder-stack terminal actions need
`xdg-terminal-exec` and a configured terminal. Optional sound uses
`canberra-gtk-play`, but installing it does not grant the host privacy/DND and
notification access described in the README.

## Update and rollback

1. Recover parked windows and verify the empty journal using
   [recovery.md](recovery.md). Do this before any operation that unloads or
   replaces the running plugin.
2. Record the installed commit with
   `git -C "$HOME/.config/omarchy/plugins/burmjohn.omadocked" rev-parse HEAD`.
   Back up the plugin directory and your configuration/state files to a private
   location. Keep local edits; do not force-reset a dirty checkout.
3. Run `omarchy plugin update burmjohn.omadocked` from an interactive terminal
   and review its proposed changes.
4. Confirm the dock loads, settings remain intact, and the interactions you use
   still work. Manifest validation and a successful shell IPC ping are not
   runtime-health checks.

The Omarchy 4.0.6 updater fetches **origin's default-branch HEAD**, fast-forwards,
validates, then requests a plugin rescan. It does not pin a GitHub Release or the
version in `manifest.json`. A failed manifest validation rolls back that update;
a runtime defect after validation does not trigger an automatic rollback.

For a runtime regression, first recover parked windows, disable the plugin and
preserve the failing checkout for diagnosis. Restore the exact backed-up plugin
directory, validate it, then re-enable and check it. Restore settings only when
needed and from a compatible backup; do not delete the journal or lock file.
If recovery itself fails, stop and retain the current files rather than swapping
versions around parked windows. Restarting the shared shell is a coordinated
last resort, not a routine installation step.

## Development gates

Use the Qt 6 tools in `/usr/lib/qt6/bin`, not any Qt 5 PATH equivalents.
`qt6-declarative` supplies the QML tools used here; `qt6-tools` is not required
merely to run `qmllint` or `qmltestrunner`.

| Command | Coverage and dependencies |
|---|---|
| `make test` | Python spawn/refusal and test-inventory checks only; not full regression acceptance |
| `make test-offscreen` | Classified Python helpers plus Qt/Quickshell offscreen tests; requires a supported Omarchy installation, its plugin CLI tools, Lua, Node.js (pure-policy schema checks), Python/Gio and Qt 6 |
| `make lint` | QML static checks; Quickshell dynamic metadata warnings remain visible |
| `make bench` | Fixed model/magnification microbenchmarks; not compositor frame time or per-plugin CPU |
| `make render` | Owned offscreen software images, not desktop screenshots |
| `make test-native` | Explicitly consented native-backend tests; not automatically visible/physical acceptance |

Temporary fixtures honor `TMPDIR`. Their offscreen IPC runtime is private and
short enough for Linux Unix-domain sockets; test-mode persistence is restricted
to explicitly supplied owned fixture roots, including shared-storage fixtures.
Inherited root overrides are replaced by the guarded launcher. None of these tests should be run
against your live pins or journal.

A prospective release must contain the new test modules and fixtures as well as
tracked modifications. Validate a clean, explicitly assembled candidate tree,
not a developer directory containing historical evidence or host-overlay tools.
Untracked planning documents and old deployment scripts are not install inputs.

`make preview` is a **real standalone dock**, not a nonlaunching demonstration.
It can show live apps, perform actions and use ordinary saved configuration and
state. It can also contend with the installed dock's writer leases. Coordinate
it as live testing; do not start it alongside your daily dock just to run tests.

Offscreen success does not establish native input masks, actual window movement,
physical pointer feel, mixed-DPI hotplug, suspend/resume or lock-screen behavior.
The historical shared-host/relocation scripts also need current public-facade
coverage before their old results can be used as release acceptance.

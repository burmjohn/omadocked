# Idle lock and OMARCHY_PATH

A running screensaver is not a locked session. If idle art is on screen and a
keypress returns to the desktop with no password, idle ran and lock IPC missed
the live shell.

This matters when Omadocked uses a user-owned Omarchy tree
(`OMARCHY_PATH=~/.local/share/omadocked/omarchy`) instead of
`/usr/share/omarchy`.

## What failed

Idle timeouts in `~/.config/omarchy/shell.json` (`idle.screensaver`,
`idle.lock`) are seconds since user idle began. A long lock timeout is not
itself a missed lock.

`omarchy-system-lock` forwards to `omarchy-shell lock lock`, and
`omarchy-shell` talks to `qs ipc -p "$OMARCHY_PATH/shell"`. If
`OMARCHY_PATH` is stock Omarchy, that call hits a shell that is not running
and returns success in a fraction of a second. The Omadocked lock plugin
never sees the request (`lastEvent` stays `init`). PAM is not involved.

The overlay idle service used to spawn helpers as `bash -lc`. A login shell
sources `/etc/profile.d/omarchy.sh` → `env-bootstrap`, which **assigns**
`OMARCHY_PATH=/usr/share/omarchy` when `/etc/omarchy.conf` is absent. The
Quickshell process still has the overlay path; the child does not.

Repro (does not lock the session):

```sh
OMARCHY_PATH=$HOME/.local/share/omadocked/omarchy bash -c 'omarchy-shell lock isLocked'
# false

OMARCHY_PATH=$HOME/.local/share/omadocked/omarchy bash -lc 'omarchy-shell lock isLocked'
# omarchy-shell is not running
```

## Fix

In the overlay idle service
(`~/.local/share/omadocked/omarchy/shell/plugins/services/idle/Service.qml`):

- `runProcess` (screensaver, lock, wake) uses `bash -c`, not `bash -lc`
- stay-awake state writes use `bash -c` as well

Do not edit `/usr/share/omarchy`. QML loads only after `omarchy restart shell`.
File mtime newer than the running Quickshell start time means the patch is
on disk but not loaded.

## Diagnose (read-only)

Do **not** run `omarchy toggle screensaver` or `omarchy toggle idle` to inspect
status; those flip files under `~/.local/state/omarchy/toggles/`.

1. Timeouts: `~/.config/omarchy/shell.json` `idle.screensaver` and `idle.lock`
2. Toggles: list `~/.local/state/omarchy/toggles/` (`screensaver-off` means off)
3. Live shell: `OMARCHY_PATH` from the running Quickshell `/proc/<pid>/environ`
4. IPC against the overlay path, not stock:

   ```sh
   qs -p "$HOME/.local/share/omadocked/omarchy/shell" ipc call lock isLocked
   qs -p "$HOME/.local/share/omadocked/omarchy/shell" ipc call lock status
   qs -p "$HOME/.local/share/omadocked/omarchy/shell" ipc call idle debug
   ```

5. Journal: `omarchy idle … process-start: lock omarchy-system-lock` followed
   by `process-exit` in ~0.25s and no `omarchy lock` lines means a no-op.

Regression: `python3 -m unittest tests.test_idle_lock_env -v`

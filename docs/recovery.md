# Parked-window recovery before disable, update or removal

This procedure uses the existing overlay IPC and `services/parking_store.py`; it does not add a service or require another Quickshell. The helper moves windows only after compositor-session and full window-lifetime identity checks, including stableId, then reads back the result. **Actual desktop movement requires your approval.** Owned fake-compositor execution is recorded in [relocation/recovery evidence](../evidence/phase3-relocation-recovery/report.md); native movement and live host lifecycle remain acceptance gates.

## Lifetime and files

| Operation | Recovery availability |
|---|---|
| Hide/close the dock | `keepLoaded: true` retains its AppService, both writer helpers and `omadocked-recovery` IPC. Hiding is not disabling. |
| Disable / actual Loader unload / host plugin reload | Overlay and its IPC disappear, writer children exit and their locks release. Parked records remain on disk; nothing automatically restores them. |
| Re-enable / recreate | The new controller reacquires the journal, reconciles against the current compositor session and publishes recovery records before new parking. |
| Remove source | No plugin IPC is promised. Use a retained helper copy or restore the reviewed plugin and re-enable it. Do not delete the journal to clear an error. |

Default configuration: `${XDG_CONFIG_HOME:-$HOME/.config}/omadocked/pins.json`.
Default recovery journal: `${XDG_STATE_HOME:-$HOME/.local/state}/omadocked/parking.json`.
If the host was explicitly launched with `OMADOCKED_CONFIG_PATH` or `OMADOCKED_PARKING_JOURNAL`, use **those exact paths**, not these defaults. Configuration LKG recovery and window recovery are different operations. `OMADOCKED_PARKING_DISABLED=1` prevents hosted journal access; it does not restore any windows.

Retain the private state directory and permissions, and use the same compositor login/session. The helper validates paths and refuses symlinks, unsafe permissions, competing writers and mismatched sessions/identities. Never edit stable IDs/session strings, force addresses or loosen permissions to bypass refusal.

## Preferred: recover while still loaded, then disable/remove

1. Identify the existing Omarchy host PID using `quickshell list`; verify its config path. Set `HOST_PID` to that exact PID, not the standalone dock or another shell. Do not run a second shell.
2. Inspect the loaded overlay:

   ```sh
   quickshell ipc --pid "$HOST_PID" call -- omadocked-recovery status
   ```

   Require parsed JSON, `ready: true`, and `busy: false`. `Target not found.` means no handler; the installed CLI may return exit 0 for that message. It is **not** an empty journal or recovery success.
3. Deliberately restore saved origins:

   ```sh
   quickshell ipc --pid "$HOST_PID" call -- omadocked-recovery recover origin
   quickshell ipc --pid "$HOST_PID" call -- omadocked-recovery status
   ```

   The first result is a transaction ID, not completion. Repeat `status` until `busy` is false and `last.transactionId` equals the returned positive ID. Require `last.ok: true` and `records: []`. If the journal was already empty, the helper may return `empty`/false; confirm empty records rather than treating that as a movement failure. If origin is unavailable, decide explicitly whether to request `recover here` to the current normal workspace. Partial/blocked recovery is not success: preserve the remaining records and stop removal. Each window has its own acknowledgement; this is not an atomic group transaction.
4. Only after completion, with no further parking in progress:

   ```sh
   omarchy plugin disable burmjohn.omadocked
   # Optional, after recovery and a retained source backup:
   omarchy plugin remove burmjohn.omadocked --yes
   ```

   The installed disable command mutates enablement through the existing host. Removal may trigger broader plugin reloads. The installed remove command deletes a Git-managed checkout, unlinks a symlink, or moves a plain directory to a hidden backup. **Do not rely on an automatic source backup**: its behavior depends on installation type. It does not explicitly delete the external XDG journal/config. Do not install shell bindings or restart the host as part of recovery.

## Already disabled / unloaded

If the reviewed source remains installed, `omarchy plugin enable burmjohn.omadocked` recreates the overlay through the normal host path. Wait for parsed ready status and use the preferred recovery steps. If the host has not discovered it, the supported command is `omarchy-shell shell rescanPlugins`; this may reload other hosted plugins and requires its own approval. No automatic restore is performed by enabling. Initial visibility is intentionally unchanged: the current build can be hidden until summoned; its hidden IPC is usable.

Alternatively, recover without re-enabling any dock surface using the retained helper below, **only once the hosted writer has unloaded**. A `busy` reply means another writer owns the lock. Wait for owned unload; never remove a lock file or kill unrelated processes.

## Already removed: retained helper, no plugin IPC

Before removing source, copy the reviewed `services/parking_store.py` to a private directory outside the plugin checkout (for example `$HOME/.local/share/omadocked-recovery/parking_store.py`). This Python file uses only the standard library and `/usr/bin/hyprctl`; no repository imports or assets are required. Keep its version associated with the journal version. An entire reviewed source backup is also sufficient. If no copy remains, restore a trusted matching source first; a removed executable cannot be invoked.

Set `RECOVERY_HELPER` to that exact retained file and `JOURNAL` to the original private journal. In the **same compositor session**, with the hosted writer absent:

```sh
printf '%s\n' '{"id":1,"op":"status"}' |
  /usr/bin/python3 "$RECOVERY_HELPER" "$JOURNAL"
```

The helper emits a ready line, then a response for each JSON request. `status` performs reconciliation and can update durable state; it is not a guaranteed read-only inspection. Require ready `ok: true`; inspect `keys`, `records`, `blocked` and `recoveryRequired`. Preserve blocked entries. To deliberately recover:

```sh
printf '%s\n' \
  '{"id":10,"op":"status"}' \
  '{"id":11,"op":"recover","mode":"origin"}' \
  '{"id":12,"op":"status"}' |
  /usr/bin/python3 "$RECOVERY_HELPER" "$JOURNAL"
```

Require the id 11 response to report successful restoration (or an already-empty journal established by status), id 12 `records: []`, and no blocked entries. `mode:"here"` is an explicit alternative when a saved origin is unavailable; ensure the current workspace is a normal destination. EOF exits the helper and releases its flock. A zero Python exit code alone does not establish that individual operations succeeded. Do not set test overrides in a real recovery session; the owned tests use a private `OMADOCKED_HYPRCTL` only with `OMADOCKED_TEST_MODE=1`.

When stale-session/identity, unavailable compositor, corrupt/unsafe journal or partial recovery is reported, stop and keep the original journal/source. This procedure intentionally does not provide a force-move bypass. Manual native recovery, if necessary, needs a separately approved inspection and exact-window scope.

## Verification boundary

`python3 -B tests/relocation_recovery.py` runs installed discovery/entry URL/loader excerpts from a separate host root against an external copied package with spaces and `#` in its path. It executes hosted recovery after hide, disable/re-enable and unload/recreate, and the retained-helper JSONL sequence after removing the owned source. The only compositor is a private fixture executing the production Lua identity guards. `python3 -B -m unittest discover -s tests -p test_recovery_cli.py -v` runs the installed enable/disable/remove scripts with a private HOME and allowlisted IPC shim; it tests actual CLI arguments and removal backup behavior, **not live host mutations/watchers**. Neither test authorizes deployment or certifies physical movement.

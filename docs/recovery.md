# Parked windows

If you used click-to-minimize, recover windows **before** disabling the plugin.

1. Find the Omarchy shell PID (`quickshell list`; config path should be the Omarchy shell).
2. Check status:

```sh
quickshell ipc --pid "$HOST_PID" call -- omadocked-recovery status
```

Need JSON with `ready: true` and `busy: false`. `Target not found.` means the plugin is not loaded.

3. Restore to original workspaces:

```sh
quickshell ipc --pid "$HOST_PID" call -- omadocked-recovery recover origin
```

4. Read the status back explicitly (the recover call's return value is not proof
that windows were restored):

```sh
quickshell ipc --pid "$HOST_PID" call -- omadocked-recovery status
```

Wait for JSON containing `ready: true`, `busy: false`, `last.ok: true`, and exactly
`records: []`. If records remain, `last.ok` is false, or status cannot be read,
stop: do not disable the plugin or delete the journal. Avoid minimizing more
windows between the verified empty status and disabling.

5. Only after that successful empty read-back:

```sh
omarchy plugin disable burmjohn.omadocked
```

## Already disabled?

Re-enable the plugin so its journal owner and recovery IPC are available:

```sh
omarchy plugin enable burmjohn.omadocked
```

Run `quickshell list` again and select the current Omarchy shell PID (set
`HOST_PID` to that PID; do not use an old PID or a standalone preview). Repeat
status → recover origin → status above. If `Target not found.` persists, the
plugin has not loaded; resolve that before attempting recovery. Re-enabling is
not itself evidence of restoration. Do not remove plugin files until recovery
has the verified empty read-back.

Pins: `~/.config/omadocked/pins.json`  
Journal: `~/.local/state/omadocked/parking.json`

These are defaults. `XDG_CONFIG_HOME` / `XDG_STATE_HOME`, or explicit
`OMADOCKED_CONFIG_PATH` / `OMADOCKED_PARKING_JOURNAL` overrides, can relocate
them. Recover through the running instance that owns the actual journal; do not
assume a default-path file belongs to that instance.

Do not delete the journal to “clear an error.” Hiding the dock is not the same as disabling it.

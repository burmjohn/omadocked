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

Then `status` again until `busy` is false, `last.ok` is true, and `records` is empty.

Pins: `~/.config/omadocked/pins.json`  
Journal: `~/.local/state/omadocked/parking.json`

Do not delete the journal to “clear an error.” Hiding the dock is not the same as disabling it.

# Manual runner safety dependencies

Manual runner consent is separate from automated `hidden-backend` consent.
`OMADOCKED_TEST_NATIVE=1` and comma-separated `OMADOCKED_TEST_NATIVE_SCOPE`
values must be explicitly approved in the **caller** environment. The table
lists code dependencies, not authorization to run them. Do not automatically
append scopes, set consent in child overrides, or remove a helper's check.

| Manual runner | Required scopes, if that runner is separately approved |
|---|---|
| `appearance_contract` | `appearance_contract,monitor_contract` |
| `apps_contract` | `apps_contract,monitor_contract` |
| `editor_contract` | `editor_contract,monitor_contract,hidden-backend` |
| `window_contract` | `window_contract,monitor_contract,hidden-backend` |
| `desktop_action_contract` | `desktop_action_contract,hidden-backend` |
| `launcher_contract` | `launcher_contract,hidden-backend` |
| `monitor_contract`, `running_app_contract`, `native_contract`, `smoke`, `live` | Their own filename stem (each individually, not a combined grant) |

`monitor_contract.command` and `owned_layers` retain the monitor scope even
when imported by another runner. `DailyAdapterTests.start` retains its automated
native `hidden-backend` scope when reused by a manual contract. Own-stem consent
alone therefore does **not** complete the composite runners above. Each composite
entry checks its own scope and every listed dependency explicitly, before evidence
writes, temporary fixture setup, or startup. These checks never append consent;
each scope must already be independently approved in the caller. Effective child
environment validation remains at the actual process boundary (including after
preflight); a changed or invalid child environment can still refuse there.

All existing action/visible/input/capture flags and approved runtime/socket
prerequisites remain required. Scope names do not authorize desktop actions by
themselves. No runner is executed by this documentation or the R1 repair.

`manual_process` copies the caller environment for omitted `env` or `env=None`.
An explicit mapping replaces rather than merges with it; `{}` cannot borrow the
caller's display/runtime and fails native prerequisites. Existing guard policy
still defaults missing QPA to Wayland, clears the platform theme for the child,
validates the effective native environment, and reads consent from the caller.
It does not mutate either input mapping or `os.environ`.

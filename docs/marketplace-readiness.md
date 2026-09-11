# Public plugin readiness

## Decision

Target a free public release of Omadocked through the Omarchy plugin ecosystem. Keep the existing phase numbers: add an early shared-shell compatibility checkpoint to Phase 3 (P3-09), then complete packaging and marketplace submission in Phase 5. ROADMAP.md remains the task tracker; this document explains the requirements and current gaps.

Publication, marketplace submission and replacing the installed dock still require explicit approval. This planning update does not authorize those actions.

## Requirements from the guides

- Plugins run inside the long-running Omarchy shell, unsandboxed with the user's permissions; a plugin must not start a second Quickshell process. Review dependencies, commands and privileges.[1]
- Choose the actual plugin kind and matching entry point. The clock tutorial is a `bar-widget` example, not a requirement to turn a dock into one. Permanent IDs must be namespaced and must not use the reserved `omarchy.*` namespace.[1]
- Validate the manifest and folder, use safe relative entry-point paths, and do not include symlinks. Lint against the installed shell imports. Manifest validation alone does not establish working runtime behavior.[1]
- Exercise the relevant open/close, Escape, disable/re-enable, shell restart and removal paths before sharing. Document external dependencies, setup steps, services, privileges, installers and remote builds.[1]
- Marketplace preparation requires a public GitHub repository, a valid root `manifest.json`, README, license, and safe installation/removal. A preview image is optional.[2]
- Submit the repository link, category and tags through the marketplace issue form. Automated validation checks the current commit before maintainer approval. Listing validation is not a security review.[2]

## Current gaps and decisions

| Area | Current state | Required work |
|---|---|---|
| Host process | `Dock.qml` loads through an isolated host-shaped `keepLoaded` overlay fixture; unload/reload tears down and reacquires its helper. The fixture starts one Quickshell and no lock/polkit/notification service. | Independently review and exercise the actual Omarchy host loader without modifying the installed shell before closing P3-09. Keep standalone preview for development only. |
| Persistence | `AppService.qml` starts a long-lived argv-only Python helper. The helper owns `flock` and all main/LKG/recovery I/O; hosted and preview paths are identical. Competing instances, verified readback, recovery, startup/loss failure, encoded paths and QML child-FD isolation are covered. | Independently review the implementation and retain fail-closed behavior. No second shell, shell command, inherited lock, preload shim or user-wide wrapper is permitted. |
| Identity | Manifest declares `burmjohn.omadocked`, `overlay`, and `Dock.qml`. | Check ID availability and retain a stable identity before publication. The guide's reverse-domain example is not a reason to rename automatically. |
| License | No root LICENSE file was found in this checkout. | Recommend MIT for the project, subject to John's choice and the code/asset audit. Add the actual license and applicable upstream notices; being free of charge is not a redistribution license. |
| Package | Development checkout contains harnesses, evidence and local build artifacts. | Define the distributable file set, dependency/build instructions and supported versions. Validate the artifact users will install, not just this workspace. Exclude private configuration, credentials, machine-specific paths and generated test clutter. |
| Installation | Standalone preview works; host-plugin installation/update/removal is not certified. | Exercise a clean test profile/environment, shared-shell load, update, disable/re-enable, restart, removal and rollback. Coordinate any visible or live-host tests. |
| Listing | No public repository or marketplace listing has been created by this work. | Publish only the reviewed candidate with approval, then submit separately and read back the exact resulting repository/listing state. Do not claim acceptance while maintainer review is pending. |

The shared-shell persistence checkpoint must happen before committing to further storage-dependent parking/recovery architecture. Do not leave this discovery until release packaging. Passing standalone tests or `omarchy plugin validate` does not close P3-09.

## Release evidence

Phase 5 should link to the exact tested source revision/artifact, validation and runtime results, supported versions, dependency and license inventory, install/update/remove/rollback results, and security review. Provide a concise README and an issues/reporting route. Use owned-fixture imagery for an optional preview, or obtain permission before capturing a user's desktop.

Marketplace readiness does not waive outstanding Phase 1–4 acceptance or authorize immediate deployment. Recheck the guides and installed shell contracts at the implementation and release checkpoints; these pages can change.

## Sources

[1] https://plugins.omarchy.org/develop.html — Omarchy plugin development guide
[2] https://plugins.omarchy.org/publish.html — Omarchy plugin publishing guide

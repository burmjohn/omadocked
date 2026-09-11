# Phase 1 — feel review

**Historical checklist:** the default dock has advanced to the user-requested Phase 2 app/pin slice. Use the current [README](../README.md) for live controls: app clicks now focus/launch, and pin changes persist. The nonlaunching instructions below describe the earlier fixture prototype, not the current `make preview`. Remaining physical feel/hotplug checks still apply.

This is a **nonlaunching native prototype**, not the replacement dock. Its fixed first icon opens real settings; the remaining six icons are demo items. Settings/selections/reorders affect only the prototype's memory and are discarded on exit. Omadock stays installed and enabled.

## Start and stop

From the repository root, `make preview` opens the compact icon row at the bottom of all connected displays. Click the **first Settings icon** for Size, Transparency, motion, reduced motion, auto-hide and **All displays / Selected displays**. Changes apply across all prototype surfaces immediately, but are temporary until the process exits. No connector is a portable default.

`OMADOCKED_SCREENS` accepts `all` or comma-separated connector names for startup selection. Explicitly selected disconnected outputs remain remembered and do not cause fallback to an unselected display. All mode includes newly connected displays. Physical unplug/replug still requires its own test.

Keep the terminal running. Ctrl+C in that terminal stops only this prototype. The root IPC target is `omadocked-prototype`; direct commands must select the prototype's **exact PID**, never the Omarchy shell. Do not install/enable the manifest for this review.

To enter keyboard review, run `quickshell list --all`, find the instance whose config path is this repository's `shell.qml`, and use its Process ID in `quickshell ipc --pid PID call -- omadocked-prototype keyboard`. Do not use the instance under `/usr/share/omarchy/shell`. Arrow keys navigate; Enter on the first item opens settings, while other items only select a fixture. Escape closes settings or releases keyboard mode. Menu or Shift+F10 on an app fixture opens an inert demo menu. Physical focus-restoration review remains pending.

The bottom offset now defaults to zero, as requested after the first preview. Omadock remains installed/enabled; overlapping docks and competing edge triggers are possible. `OMADOCKED_OFFSET` can still lift the prototype for isolated testing. Do not disable the installed dock without approval.

## Review sequence

| Check | What to try | What should happen |
|---|---|---|
| First impression | Look at the compact icon row, spacing and colors | No persistent demo toolbar; prototype explanation lives in settings/tooltips |
| Settings | Click the first icon; use Close or Escape; click outside | A functional popup opens above the dock and dismisses; first item cannot be dragged away |
| Size | Drag the Size slider; try arrow keys | Icons/shelf resize from 28–72px; popup controls stay in place; narrow displays fit the renderer |
| Transparency | Drag from 0% to 100% | Shelf background fades, not icons or the settings popup |
| Display selection | In Settings, switch All/Selected and change checked connectors | One dock per chosen connected display; changes apply everywhere; last connected choice is protected |
| Bottom placement | Look at each chosen display's bottom edge | The surface and reveal trigger reach that edge; no previous 96-pixel test offset |
| Wave | Sweep across icons, reverse quickly, and enter near each end | Smooth growth/displacement without overlap, unstable targets or queued motion |
| Zoom / Off | Change mode and repeat | Zoom affects hovered art; Off remains steady |
| Selection | Click a visually enlarged app fixture near its edges | The intended demo item is selected; no application or desktop command runs |
| Tooltip / menu | Pause over an icon; right-click it, or use Menu in keyboard mode | A delayed demo label; a local menu with only inert selection/close actions |
| Reorder | Drag the second item toward the end and release within the row | Clear insertion marker; order changes once; Settings remains first |
| Cancellation | Start a normal pointer drag and press Escape; repeat by releasing outside | Original order remains; no item is selected/launched/saved |
| Auto-hide | Enable it, leave the shelf, briefly touch the narrow trigger then leave | Hide/reveal dwell works; a short trigger visit does not leave a delayed reveal |
| Interaction lock | Drag or use keyboard navigation while moving away from the shelf | It stays open until the interaction ends |
| Keyboard | Enter the prototype's keyboard mode, use arrows/Enter, then Escape | Visible focus, inert selection and return to typing in the prior app |
| Reduced motion | Enable it and repeat motion/hiding tests | No magnification/animated transitions; controls remain usable |
| Quit | Stop the exact prototype process | Its surfaces disappear; Omadock and the rest of the desktop remain unchanged |

Do not test real minimization, launchers, app grouping, folder scanning or notifications here. Those are later phases.

## Sign-off

- [ ] John approves the look and motion.
- [ ] John approves click/hide/drag defaults.
- [ ] Keyboard entry/exit and pointer behavior are satisfactory on the intended output.
- [ ] The all-parked-app click proposal in `docs/behavior.md` has a recorded decision before Phase 2 semantics are finalized.

John's initial feedback was **“Looks good”**, with requests for bottom placement and All/Selected monitor choice. This is not full motion/input or daily-use sign-off. Automated and native test results belong in `evidence/`; successful test execution alone cannot check these boxes.

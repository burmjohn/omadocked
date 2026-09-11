# Omadocked — measurement protocol

## Phase 0 evidence

`evidence/reference-passive.json` is a real 60-second `/proc` observation of the existing Omarchy shell with Omadock enabled. The shell PID and process start ticks were checked. It records CPU time and start/end RSS; it makes **no isolated dock-cost, idle, frame-rate or superiority claim**. Other shell plugins, windows and normal user activity were not controlled. The shared shell used 12.5 CPU-seconds during the sample; that cannot be attributed to Omadock.

The native foundation harness actually ran with three hidden per-screen panels and exact-PID IPC. `evidence/smoke.json` is overwritten by the latest project smoke run; `evidence/foundation.md` records the phase-0 result separately.

No reference enablement, settings, windows, pointer position or compositor configuration was changed. Controlled A/B tests remain an explicit release blocker, not a passed Phase 0 performance target. See [risks.md](risks.md), RISK-BASELINE.

## Reproducible workloads

Before comparisons, record package versions, compositor/renderer, output names/scale/refresh, reference commit, plugin settings, process identity and whether the user is interacting. Use only nonprivate disposable fixture windows. Keep other shell work equivalent; use one dock at a time. Obtain approval before toggling plugins or moving windows. Match effect and preview settings rather than comparing a bare prototype to a feature-rich reference.

| ID | Workload | Sample | Evidence required |
|---|---|---|---|
| B-IDLE-HIDDEN | Warm caches, hide the dock, stop user input and do not change windows | 60 seconds per configuration, repeat 3 times | CPU time, RSS, periodic subprocess/capture activity, visible-state confirmation |
| B-IDLE-SHOWN | Show uncovered shelf, pointer outside shelf, fixed windows | 60 seconds, repeat 3 times | Same metrics; detects visible-state overlap polling |
| B-SWEEP | Same fixture icons; cursor travels left/right over shelf and abruptly reverses, then leaves | 30 seconds per output/mode | Actual frame presentation trace plus visual recording; pointer path and display refresh recorded |
| B-DRAG | Reorder first to last, cancel last to first with Escape, release outside valid region | 20 repetitions | Order before/after, no unintended action, input/grab errors, memory trend |
| B-APP | Open/close/focus only approved disposable fixture app windows at fixed intervals | 30 operations | Identity/grouping correctness, model event/refresh counts, input response |
| B-PREVIEW | Show/hide the same fixture popover; close source while open | 20 repetitions | Captures stop hidden, bounded memory, failure fallback; Phase 3+ only |
| B-LIFETIME | Reload only isolated prototype; simulate missing output; reopen controls | 20 repetitions | No duplicate subscriptions, stale QObject errors, stranded surfaces or sustained cache growth |

Collect frame timing with a compositor/Qt presentation-aware profiler available on the test system. A JS timer or elapsed IPC round trip is **not FPS**. If no appropriate capture tool is available, report frame pacing unmeasured rather than estimating it. Isolated QML profiling is allowed; exposing the daily shell's debug port is not.

## Process CPU/RSS calculation

For the exact process, read `/proc/PID/stat` user+system tick counts and `/proc/PID/status` VmRSS before and after a monotonic interval. Verify process start time is unchanged; use `os.sysconf('SC_CLK_TCK')` for ticks/second. CPU seconds = tick delta / tick rate; percent of one core = CPU seconds / elapsed seconds * 100. Record child process activity separately because a parent-only sample misses subprocess work. Do not claim periodic-process counts from coarse snapshots alone.

## Gates

- Proposed hidden budget: below 0.5% of one core added over equivalent dock-disabled shell; no repeated hidden polls/captures.
- Proposed motion budget: fewer than 1% missed presentation frames during B-SWEEP, at each actually tested output refresh rate.
- Establish memory ceilings from reference + replacement evidence; require bounded caches and no sustained B-LIFETIME growth.
- Phase 1 is an interaction prototype with nonlaunching fixtures, not an efficiency or feature-parity release.

## Daily-use model measurement

The [daily-core evidence](../evidence/daily-core.md) records a fixed 500-entry/50-window model benchmark against a hashed pre-change source snapshot: 7.963 ms before and 0.301 ms after indexing, over 2,000 iterations each. `make bench` reproduces the current workload. This measures model processing, not presentation frames or performance relative to Omadock. Standalone passive CPU/RSS samples are also kept separate from controlled idle claims.

## Blocked or untested

Controlled reference/replacement A/B measurements, frame presentation, subprocess lifetime tracing, mixed-DPI, physical hotplug, actual app/window workloads and capture costs are not measured by the passive Phase 0 sample. These remain required before corresponding product/release claims.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- **Run monitor**: `run.bat` (finds AutoHotkey64.exe via registry or default path)
- **Run demo window**: `run_demo.bat` (for testing detectors/overlay without the game)
- **Syntax check**: `"D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" main.ahk --check`
- **Smoke test**: `"D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\smoke_test.ahk`
- **Live combat test**: `"D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\combat_live_test.ahk`
- **Combat screenshot calibration**: `"D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\combat_screenshot_test.ahk screenshot.png 61` (second arg = client top Y offset)
- **Room self-slot live test**: `"D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\room_self_live_test.ahk`
- No package manager, bundler, or test framework — AHK v2 is interpreted directly.

## Architecture

Three-speed scheduler drives a detect → event → overlay pipeline per element:

```
Scheduler.RunLane(lane)
 ├── WindowManager.RegionToScreen(element)   — converts element-relative → screen coords (1040x807 reference)
 ├── *Detector.Detect(element, region)        — returns result Map
 │     room_slots uses ScreenCapture.CaptureRegionPixels() + CountColorMatches() via GDI BitBlt
 ├── MonitorEventBus.Process(element, result) — debounce/cooldown → event name
 └── OverlayManager.Update(element, result)   — transparent HUD windows
```

Modules are wired via constructor dependency injection in `MonitorApp.__New()` (main.ahk:45-56). `#Include` order in main.ahk is the canonical dependency order (scheduler.ahk last).

### #Include Dependency Order

The `#Include` order in `main.ahk` is strict — later files depend on earlier ones:
1. `core/utils.ahk` — JoinPath, NowStamp, CsvParseLine, color utilities, RoomStateZh
2. `core/config.ahk` — MonitorConfig (reads monitor.ini + elements.csv)
3. `core/logger.ahk` — MonitorLogger (text log + JSONL event log)
4. `core/window.ahk` — WindowManager (window finding, region scaling)
5. `capture/pixel_capture.ahk` — PixelCapture (PixelGetColor wrapper)
6. `capture/screen_capture.ahk` — ScreenCapture (GDI BitBlt, CountColorMatches, memchr optimization)
7. `detectors/color_detector.ahk` — ColorDetector
8. `detectors/image_detector.ahk` — ImageDetector (ImageSearch)
9. `detectors/change_detector.ahk` — ChangeDetector (region color diff)
10. `detectors/room_state_detector.ahk` — RoomStateDetector (12-slot analysis)
11. `detectors/combat_hud_detector.ahk` — CombatHudDetector (3-anchor HUD)
12. `core/combat_state.ahk` — CombatStateTracker (enter/exit debounce)
13. `core/eventbus.ahk` — MonitorEventBus (debounce, cooldown, slot state machine)
14. `overlay/overlay.ahk` — OverlayManager (transparent per-element GUIs)
15. `core/scheduler.ahk` — Scheduler (three-speed timer dispatch, scene management)

### Layers

- **Entry** (`main.ahk`): `MonitorApp` class — instantiates all services, builds status GUI, registers Ctrl+Alt+F12 hotkey, logs startup geometry, starts scheduler.
- **Core** (`core/`): config loading, logger (text + JSONL), window finding with foreground detection, event bus state machine, scheduler.
- **Capture** (`capture/`): `PixelCapture` (PixelGetColor), `ScreenCapture` (GDI BitBlt → pixel buffer with memchr-based color matching via `CountColorMatches()` which uses `SelectSearchChannel()` to pick the B/G/R channel farthest from 128 for fastest `memchr` scanning).
- **Detectors** (`detectors/`): `ColorDetector`, `ImageDetector` (ImageSearch), `ChangeDetector` (region color diff), `RoomStateDetector` (12-slot player list analysis), `CombatHudDetector` (3-anchor HUD detection with HP/SHIELD/READY gauges).
- **Overlay** (`overlay/`): transparent per-element GUIs with `PlaceOutsideRegion()` positioning.
- **Config** (`config/`): `monitor.ini` (runtime settings), `elements.csv` (UI element definitions with 18 columns).

### Detection Result Contract

Every `*Detector.Detect()` returns a Map with these fields (callers read `result["matched"]`, `result["score"]`, `result["latency_ms"]`, `result["error"]`):

| Field | Type | Always present |
|---|---|---|
| `matched` | boolean (0/1 in AHK) | yes |
| `score` | float 0.0–1.0 | yes |
| `color` | string | yes |
| `latency_ms` | integer | yes |
| `error` | string | yes |
| `slots` | Array of slot Maps | room_slots method only |
| `slot_count` | integer | room_slots method only |
| `summary_zh` | string | room_slots method only |

Room_slots additionally returns: `occupied_count`, `ready_count`, `master_count`, `self_candidate_index`, `self_candidate_margin`, `self_top_index`, `self_slot_index`.

Combat HUD returns: `combat_active`, `combat_phase` (READY/ACTIVE), `hp_percent`, `shield_percent`, `anchor_hits`, `anchor_left`, `anchor_score`, `anchor_radar`, `ready_raw`.

### Room State Detector (核心模块)

`RoomStateDetector.Detect()` uses `ScreenCapture.CaptureRegionPixels()` (GDI BitBlt) to capture the player list region once, then scans the pixel buffer for all 12 slots. Each slot's region is computed via `BuildSlotBounds()` using `Round()` for precise integer boundaries from floating-point division. The capture region extends ~16% beyond slot boundaries top and bottom to cover slot border highlights.

Each slot is analyzed by `DetectSlot()` via `BuildSlotRegions()`:

| Sub-region | X offset | Width | Detection |
|---|---|---|---|
| Name area | base+65 | 165px | White text (`0xFFFFFF`, variation 70) → NOT_READY |
| Status area | base+245 | ~60px | Green (`0x66F603`, v80) → MASTER; Cyan (`0x00FFFF`, v70) → READY |

Sub-region coordinates scale via `ScaleX(referencePixels, actualWidth / 310)`. Each region is vertically narrowed to ~15% height by `CenterBand()` to focus on text center lines.

Priority: MASTER > READY > NOT_READY > EMPTY. `RequiredColorMatches := 1` — a single matching pixel is enough to confirm a color hit.

Returns `slots[]` with `{index, state, state_zh, occupied, score, region, previous_state}`. Each slot also carries self-identity fields: `is_self`, `self_score`, `self_border_top/bottom/center`, `self_border_eligible`.

### Self-Player Identification

`RoomStateDetector` identifies the local player via bright cyan border edges (not OCR) on each occupied slot:

1. `ComputeSelfBorderMetrics()` — measures top edge and bottom edge coverage of the cyan slot border. Uses `BuildSelfBorderBands()` (a single vertical band at x=230–244 relative to slot width 310). Checks `IsBrightCyan()` (green ≥ 150, blue ≥ 150, min(g,b)–r ≥ 25).

2. **Score formula**: `100 * clamp(0.65 * min(top, bottom) + 0.35 * avg(top, bottom), 0, 1)`. Eligibility requires `min(top, bottom) ≥ 0.70`.

3. `SelectSelfCandidateDetails()` — picks the highest-scoring eligible slot. If the margin over the second-best is < 0.5 (`SelfMinMargin`), the candidate is rejected as ambiguous.

The event bus (`MonitorEventBus.ProcessSelfCandidate`) applies 3-frame + element debounce_ms confirmation. `ValidateStableSelfSlot` clears the identity if the slot becomes empty.

### Combat HUD Detector

`CombatHudDetector.Detect()` captures the full client region once via GDI BitBlt, then analyzes three anchor zones:

| Anchor | Client region | Detection |
|---|---|---|
| HUD left panel | 2%–20.5% x, 2%–12.5% y | Cyan ≥ 1.5% + dark ≥ 15% |
| Score display | 40%–59% x, 2%–14% y | Cyan ≥ 1.5% + red ≥ 0.2% + dark ≥ 15% |
| Mini-map/radar | 80%–99.5% x, 2%–32% y | Cyan ≥ 1.5% + green ≥ 0.2% + dark ≥ 15% |

**Match rule**: ≥ 2 of 3 anchors (`RequiredAnchorHits := 2`). Each anchor is validated via `MeasureHudColors()` using stepped pixel sampling (step = min(w,h)/60).

**Gauge reading** (`MeasureGauge`): samples 3 horizontal lines at 25%/50%/75% height of the gauge region, scans left-to-right for HP-fill (`IsHpFill`: cyan-blue with green ≥ 180, blue ≥ 195, blue-red ≥ 30) or SHIELD-fill (`IsShieldFill`: green with green ≥ 180, green-red ≥ 30, green-blue ≥ 15). Uses gap tolerance (2% of width). Returns median of the 3 line values, or `""` when fewer than 2 valid lines.

**READY detection** (`DetectReady`): scans the ready region for horizontal runs of white text pixels (`IsReadyWhite`: min(r,g,b) ≥ 190, max-min ≤ 65) ≥ 35% of region width across ≥ 2 rows spanning ≥ 15% of region height.

### Combat State Tracker

`CombatStateTracker` is a standalone debounce state machine used by the scheduler for scene transitions:

| Transition | Required frames | Required ms |
|---|---|---|
| Combat enter | 2 (enterFrames) | 250 (enterMs) |
| Combat exit | 3 (exitFrames) | 500 (exitMs) |

Both frame count AND elapsed time must be satisfied. `Reset()` clears pending state without forcing a transition. The scheduler uses two trackers: one for combat presence and one for READY detection.

### Event Bus — Slot State Machine + Snapshot Guard

`MonitorEventBus` manages per-slot state transitions with:
- **Frame counting**: each slot must be observed in the new state for `RequiredSlotFrames := 3` consecutive detection cycles *and* exceed `element["debounce_ms"]` milliseconds before emitting (`IsSlotCandidateConfirmed`). Both must be satisfied.
- **Cooldown**: after emitting an event, the same event type is suppressed for `element["cooldown_ms"]` (`ShouldEmit`).
- **Event types**: `ON_APPEAR` (EMPTY→occupied), `ON_DISAPPEAR` (occupied→EMPTY), `ON_CHANGE` (state changes between non-EMPTY states), `ON_STABLE` (no change).
- **Snapshot guard** (`ShouldSuppressSlotSnapshot`): when ≥4 slots change simultaneously in one frame (`MassChangeThreshold := 4`), the bus buffers the frame and only accepts it after `RequiredMassSnapshotFrames := 2` consecutive identical snapshots.
- **Combat events** (`ProcessCombat`): uses `combat_transition` (ENTER/EXIT) from the scheduler, not raw match state.

### Scheduler Scene Management

`Scheduler.RunLane()` manages game state transitions:
- **Foreground warmup**: when the game window returns to foreground, the scheduler requires 3 consecutive valid combat HUD snapshots (`foregroundWarmupRequired := 3`) before enabling detection. All overlays remain hidden during warmup.
- **Room warmup** (`WarmupRoom`): after combat exits, the scheduler requires 3 consecutive non-empty room snapshots before room overlay resumes.
- **Room empty timeout** (`HandleRoomSnapshot`): 3 consecutive empty snapshots mark the room as stale, hiding overlay and restarting room warmup.
- **Scene gating** (`SceneAllowed`): ROOM-scoped elements are skipped during combat; COMBAT-scoped elements are skipped outside combat. ANY-scoped elements always run.

### Overlay Positioning

OverlayManager handles three placement strategies:
- **Room slot overlay**: position via `PlaceOutsideRegion()` — tries right, left, below, above the monitored region; falls back to clamped screen bounds.
- **Non-slot overlay** (e.g. start_button): same `PlaceOutsideRegion()` but fixed size 300×128.
- **Combat HUD overlay**: position via `PlaceCombatOverlay()` — fixed at bottom-right of the client area (7% right margin, 14% bottom margin from `clientRect`), size 200×130.

Each overlay is a captionless, borderless transparent GUI (`CreateItem()`: `-Caption +ToolWindow +Border -DPIScale`) with `#202020` background, `Microsoft YaHei UI` white text, configurable opacity (20–100%, default 55%), and optional click-through (`+E0x20`). Per-element GUIs are created on first `Update()` and cached in `this.items`.

Slot lines display as `"01号 已准备 ★我"` — 2-digit zero-padded index, self-marker appended when `slot["is_self"]` is true.

### Configuration

`config/monitor.ini` sections: `[develop]` (sibling project path), `[window]` (target exe/title, reference 1040x807 coords), `[lanes]` (fast 16ms/medium 250ms/slow 3000ms), `[overlay]` (opacity 20-100%), `[logging]`.

`config/elements.csv` columns (18): `id,enabled,lane,method,capture_type,region_x,region_y,region_w,region_h,template_path,color_hex,tolerance,threshold,debounce_ms,cooldown_ms,event_type,overlay`. Methods: `color`, `image`, `change`, `room_slots`, `combat_hud`.

Parsed via `CsvParseLine` from utils.ahk — not `StrSplit` — because one element row can break 18-field parsing. Region coordinates are at 1040x807 reference and scaled live via `WindowManager.ScaleRegion()`.

Key elements: `room_slots` (12 slots, region_h=228, debounce=500ms, cooldown=600ms), `start_button`, `room_scene_anchor`, `room_area_change`.

### Naming Conventions

- Files: `lowercase_snake_case.ahk`
- Classes: `PascalCase` (MonitorApp, Scheduler, RoomStateDetector)
- Variables/properties: `camelCase`
- INI keys and CSV column names: `snake_case`
- Game executable resolution: reads `..\develop\Data\Settings.ini` → `[Game] ServerProfile` → `[Server.<Profile>] GameExe` → falls back to `gonline.exe`.

## Logging

Two log files generated on each session start under `logs/`:
- `monitor-{sessionId}.log` — Chinese text with `[信息]`/`[警告]`/`[错误]`/`[事件]` levels
- `events-{sessionId}.jsonl` — structured JSON Lines with both English fields and Chinese translation fields (`event_zh`, `message_zh`, `state_zh`, etc.)

`sessionId` format is `yyyyMMdd-HHmmss`. `MonitorLogger.Cleanup(10)` keeps the most recent 10 log sessions, deleting the oldest on each startup.

## Testing Guidelines

- Smoke test (`tests/smoke_test.ahk`) validates config loading, ScaleRegion, BuildSlotBounds, BuildSlotRegions, HasMinimumMatches, CountColorMatches, SelectSearchChannel, PlaceOutsideRegion, event bus (single + slot + snapshot guard), self-identity transitions, and element config. Run before committing.
- For detector/overlay changes: run `run_demo.bat` to test against `tools/demo_target.ahk`.
- For slot detection changes: `tests/room_self_live_test.ahk` tests live against the game.
- For combat HUD changes: `tests/combat_live_test.ahk` tests live; `tests/combat_screenshot_test.ahk` tests against a provided screenshot for calibration without the game.
- No unit test framework — add test scripts as `tests\*_test.ahk` with `#Include` module dependencies.
- The smoke test includes `BuildSlotBounds` validation for slot indices 1, 6, 12 and snapshot guard mass-change suppression.

## Security Invariant

Monitor pixels and window regions only. No memory reads, process injection, or anti-cheat bypass. This is enforced in `README.md`, `AGENTS.md`, and the config loading code that explicitly avoids any game memory access.

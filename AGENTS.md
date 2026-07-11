# Repository Guidelines

## Project Structure & Module Organization

This repository is an AutoHotkey v2 screen/window monitor for SDGO. `main.ahk` is the entry point. Core services live in `core/` (`config`, `logger`, `scheduler`, `eventbus`, window helpers). Capture implementations are in `capture/`, detection logic is in `detectors/`, and overlay UI code is in `overlay/`. Runtime configuration is under `config/`, especially `monitor.ini` and `elements.csv`. Test and demo utilities live in `tests/` and `tools/`. Treat `logs/` as generated runtime output.

## Build, Test, and Development Commands

- `run.bat`: starts the monitor with the configured target game/window.
- `run_demo.bat`: launches the demo target for local detector and overlay testing.
- `"D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" main.ahk --check`: parses and loads the entry point, then exits before starting monitoring.
- `"D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tests\smoke_test.ahk`: runs the smoke test for config loading, logging, and event bus behavior.

Adjust the AutoHotkey executable path if v2 is installed elsewhere.

## Coding Style & Naming Conventions

Use AutoHotkey v2 syntax only. Keep indentation at 4 spaces inside classes, methods, and control blocks. Follow the existing naming style: lowercase snake_case for files such as `room_state_detector.ahk`, PascalCase for classes such as `MonitorApp`, and camelCase for local variables and object properties. Prefer small modules with explicit `#Include` lines from `main.ahk` or test files. Keep user-facing log text UTF-8 compatible.

## Testing Guidelines

Add tests as `tests\*_test.ahk` when introducing shared logic or detector behavior. Run the smoke test before handing off changes. For detection or overlay changes, also run `run_demo.bat` and confirm visible state changes, event logging, and no fatal entries in `logs\fatal.log`. Manual game validation should include room lobby detection, slot state changes, and combat/scene anchors when those areas are touched.

## Commit & Pull Request Guidelines

No repository Git history is available in this workspace, so use clear imperative commits with a scoped prefix when useful, for example `detectors: debounce room slot changes` or `config: tune default monitor timings`. Pull requests should include the purpose of the change, commands run, configuration files changed, and screenshots or log excerpts for UI/detection behavior. Link related issues when available.

## Security & Configuration Tips

Preserve the project boundary: monitor pixels and window regions only; do not add memory reads, process injection, or anti-cheat bypass behavior. Keep local machine paths in `config/monitor.ini` or external settings rather than hard-coding them into modules.

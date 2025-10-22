# Repository Guidelines

## Project Structure & Module Organization
Keep the root simple: `sp3arbr3ak3r.lua` is the sole source file and must remain the live build. Documentation (`README.md`, `DEVELOPER_CONTEXT.md`, `CLAUDE.md`) sits beside it—refresh these instead of adding new variants. Supporting captures such as `console log.png` should stay lightweight and be cleared once no longer referenced.

## Build, Test, and Development Commands
There is no formal build step; development happens by editing `sp3arbr3ak3r.lua` directly. In Roblox Studio, insert the script under `StarterPlayerScripts` and run Play Solo (`F5`). Executors should load the same contents and run them in a live server. When profiling, collect Studio console logs or micro-profiler exports and keep them concise.

## Coding Style & Naming Conventions
Match the existing Lua style: hard tabs for indentation, concise block comments, and uppercase snake case for configuration constants (e.g., `ESP_ENABLED`). Runtime locals use lower camel case (`nearestPlayerRef`), and helper functions read like verbs (`getDistanceColor`). Cache Roblox services once at the top, favor local aliases for `math`/`table`, and extend the existing state tables instead of adding new modules.

## Testing Guidelines
There are no automated tests, so rely on targeted manual passes. After each change, validate the switchboard in Studio or an executor session: All Toggles (`Ctrl+Enter`), ESP (`Ctrl+E`), Br3ak3r (`Ctrl+B` + `Ctrl+LMB`), AutoClick (`Ctrl+K`), Sky Mode (`Ctrl+L`), and waypoint persistence after restart. Whenever raycast, UI, or waypoint logic shifts, verify edge indicators and gradients from multiple camera angles. Note any regressions or balance shifts in the README Version History.

## Commit & Pull Request Guidelines
History shows short, imperative subjects (`fix`, `doc x`, `Update sp3arbr3ak3r.lua`); keep future commits similarly focused. Call out the touched subsystems in the summary and add a brief body when multiple areas change. Pull requests should state gameplay impact, list manual test passes, and link to issues or design notes. Attach quick screenshots or console snippets if UI behavior changes.

## Security & Distribution Notes
Treat this script as competitive-game IP: avoid public gists and scrub executor identifiers before sharing logs. Keep default toggles aligned with `DEVELOPER_CONTEXT.md`, and coordinate with the design lead before altering power levels or access patterns.

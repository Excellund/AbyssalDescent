# Working preferences

## Act on process-improvement requests

When the user asks to analyze how to improve a process, speed up work, reduce friction, or keep improving, investigate and implement concrete improvements within the existing task scope. Do not stop at recommendations or ask whether to apply routine, reversible fixes. Verify the changes and report what changed and any remaining limitations. Honor an explicit analysis-only request. Preserve approval boundaries for destructive actions, external communications, and changes in project or creative scope.

## Checkpoints and playtest delivery

- When the user agrees that the work is at a good checkpoint or asks to commit, finish the relevant verification, commit the completed task changes and push them. Preserve unrelated local work. Do not create release tags unless requested.
- At that checkpoint, deliver a **normal** playtest build: regular menu, no granted debug powers, normal progress. Use `.github/scripts/export_playtest.ps1` without `-DebugRun`.
- Use debug builds for focused tests when requested. `.github/scripts/start_debug_playtest.ps1` exports and launches the debug preset; `.github/scripts/export_playtest.ps1 -DebugRun` exports it without launching.
- Both modes replace **the same desktop file**, `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe`. Never deliver numbered copies or a source-only debug session that cannot be reopened from that file.
- Keep unique `dev-*` identifiers inside builds, not in delivered filenames. Keep debug saves separate and development builds out of remote telemetry and leaderboard submissions.
- The exporter defaults to the canonical desktop path and replaces it automatically. Other existing output paths require explicit `-Overwrite`. Verify the exported package and final file hash.
- Run Godot automation in disposable copies with isolated user data. Use `.github/scripts/run_gameplay_regressions.ps1` and the scoped test helpers; never run unattended tests against the player's real profile.

# Analyzing a playtest build

Use `fetch_latest_version_analysis.ps1` with an exact build identifier, an explicit UTC date window, and a separate JSON output. `-From` is inclusive; `-To` is exclusive. Keep release and development builds separate. The checked-in May report is historical context.

## Detailed local runs

Normal playtests keep detailed events in `%APPDATA%/Godot/app_userdata/AbyssalDescent/run_telemetry.save`. This contains room entries, damage received, reward choices and offers that the smaller `run_history.json` omits.

From the project directory, for example:

```powershell
& ./playtester_telemetry/fetch_latest_version_analysis.ps1 `
    -Version 'dev-keeper-20260908-225119' `
    -From '2026-09-08T00:00:00Z' -To '2026-09-09T00:00:00Z' `
    -LocalTelemetryPath (Join-Path $env:APPDATA 'Godot/app_userdata/AbyssalDescent/run_telemetry.save') `
    -OutputPath (Join-Path $env:TEMP 'keeper-september-8.json')
```

Replace the version and dates with the build being tested. The output directory must exist. Existing output requires `-Overwrite`; omitting `-OutputPath` creates a unique report in the temporary directory. `-ValidateOnly` checks the selection without launching Godot, reading events or writing a report.

The reader copies the binary save into a disposable project and runs a standalone Godot decoder. It does not start the game, run profile repair, change the original save, contact the telemetry server or submit anything. It uses the configured `.vscode/settings.json` executable, `GODOT_EXE`, or an explicit `-GodotPath`. Player identities are removed from decoded records, run IDs are hashed for duplicate detection, and the final report contains aggregate data. Temporary decoder copies and diagnostic logs stay local and are not project artifacts.

## JSON history and remote data

Use `-LocalHistoryPath <run_history.json>` for the smaller local summary or an existing JSON event export. Choose one local input. Missing event metrics are reported as unavailable; final build presence is not a reward pick rate.

Omit both local input options to read the existing configured Supabase balance RPC. The command only reads data; it does not execute setup or reset SQL. Development builds stay excluded from remote submissions and can be analyzed locally.

## Interpreting a report

The report selects completed, non-debug runs for the exact version and date window and deduplicates IDs. Explicit saved provenance must establish one non-debug build throughout the run; mixed, debug or unknown origins are excluded and counted. Legacy runs without saved origin evidence retain their recorded version, with that limitation disclosed.

Check `sample.field_coverage_runs`, sample size and `limitations` before drawing conclusions. Missing loadouts or events are not zero values. Damage received is not a measure of player activity or enjoyment. Use brief playtest feedback alongside the data; two recent runs can describe what happened but cannot justify numerical balance changes.

The isolated workflow checks are `.github/scripts/test_playtest_workflow.ps1` and `.github/scripts/test_local_telemetry_analysis.ps1`. They generate synthetic data in temporary directories and preserve the real player files and historical report.

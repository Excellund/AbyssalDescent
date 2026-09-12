param([string]$GodotPath = '')
& (Join-Path $PSScriptRoot 'run_gameplay_regressions.ps1') -GodotPath $GodotPath -TestScripts @('res://scripts/tests/test_ordinary_first_act.gd') -FixtureTimeoutSeconds 900

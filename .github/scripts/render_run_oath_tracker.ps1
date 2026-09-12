param(
    [Parameter(Mandatory = $true)][string]$ValidationProject,
    [string]$GodotPath = ''
)
& (Join-Path $PSScriptRoot 'render_gameplay_fixture.ps1') -ValidationProject $ValidationProject -GodotPath $GodotPath -FixtureScript 'res://scripts/tests/render_run_oath_tracker.gd' -FrameFolder 'run_oath_tracker_frames' -ExpectedFrames 18 -PreserveProductionCanvas -MaxFrames 5000

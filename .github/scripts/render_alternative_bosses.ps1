param([Parameter(Mandatory = $true)][string]$ValidationProject, [string]$GodotPath = '')
& (Join-Path $PSScriptRoot 'render_gameplay_fixture.ps1') -ValidationProject $ValidationProject -GodotPath $GodotPath -FixtureScript 'res://scripts/tests/render_alternative_bosses.gd' -FrameFolder 'alternative_boss_frames' -ExpectedFrames 16

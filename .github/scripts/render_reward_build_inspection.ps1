param([Parameter(Mandatory = $true)][string]$ValidationProject, [string]$GodotPath = '')
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'render_gameplay_fixture.ps1') -ValidationProject $ValidationProject -GodotPath $GodotPath -FixtureScript 'res://scripts/tests/render_reward_build_inspection.gd' -FrameFolder 'reward_build_frames' -ExpectedFrames 60

param([Parameter(Mandatory = $true)][string]$ValidationProject, [string]$GodotPath = '')
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'render_gameplay_fixture.ps1') -ValidationProject $ValidationProject -GodotPath $GodotPath -FixtureScript 'res://scripts/tests/render_boss_atmosphere.gd' -FrameFolder 'boss_atmosphere_frames' -ExpectedFrames 18

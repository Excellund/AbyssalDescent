param([Parameter(Mandatory = $true)][string]$ValidationProject, [string]$GodotPath = '')
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'render_gameplay_fixture.ps1') -ValidationProject $ValidationProject -GodotPath $GodotPath -FixtureScript 'res://scripts/tests/render_biome_room_context.gd' -FrameFolder 'biome_room_context_frames' -ExpectedFrames 38 -MaxFrames 2400

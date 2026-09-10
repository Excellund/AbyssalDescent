param(
    [Parameter(Mandatory = $true)][string]$ValidationProject,
    [string]$GodotPath = ''
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'render_gameplay_fixture.ps1') -ValidationProject $ValidationProject -GodotPath $GodotPath -FixtureScript 'res://scripts/tests/render_brittle_cover.gd' -FrameFolder 'brittle_cover_frames' -ExpectedFrames 11 -MaxFrames 1600

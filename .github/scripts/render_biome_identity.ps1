param(
    [Parameter(Mandatory = $true)][string]$ValidationProject,
    [string]$GodotPath = ''
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'render_gameplay_fixture.ps1') -ValidationProject $ValidationProject -GodotPath $GodotPath -FixtureScript 'res://scripts/tests/render_biome_identity.gd' -FrameFolder 'biome_identity_frames' -ExpectedFrames 19 -MaxFrames 1400

param(
    [Parameter(Mandatory = $true)][string]$ValidationProject,
    [string]$GodotPath = ''
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'render_gameplay_fixture.ps1') -ValidationProject $ValidationProject -GodotPath $GodotPath -FixtureScript 'res://scripts/tests/render_descent_environments.gd' -FrameFolder 'descent_environment_frames' -ExpectedFrames 21 -MaxFrames 1600

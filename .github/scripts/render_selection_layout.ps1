param(
    [Parameter(Mandatory = $true)][string]$ValidationProject,
    [string]$GodotPath = ''
)
& (Join-Path $PSScriptRoot 'render_gameplay_fixture.ps1') -ValidationProject $ValidationProject -GodotPath $GodotPath -FixtureScript 'res://scripts/tests/render_selection_layout.gd' -FrameFolder 'selection_layout_frames' -ExpectedFrames 33 -MaxFrames 6000
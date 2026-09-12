param(
    [Parameter(Mandatory = $true)][string]$ValidationProject,
    [string]$GodotPath = ''
)
& (Join-Path $PSScriptRoot 'render_gameplay_fixture.ps1') -ValidationProject $ValidationProject -GodotPath $GodotPath -FixtureScript 'res://scripts/tests/render_rest_site_choices.gd' -FrameFolder 'rest_site_choice_frames' -ExpectedFrames 6 -PreserveProductionCanvas -MaxFrames 5000

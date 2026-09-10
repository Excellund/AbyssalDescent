param(
    [Parameter(Mandatory = $true)][string]$ValidationProject,
    [string]$GodotPath = '',
    [ValidateRange(1, 300)][int]$FixtureTimeoutSeconds = 60
)
& (Join-Path $PSScriptRoot 'test_boss_combinations_enet.ps1') -ValidationProject $ValidationProject -GodotPath $GodotPath -FixtureScript 'res://scripts/tests/test_room_layout_entry_enet.gd' -FixtureTimeoutSeconds $FixtureTimeoutSeconds

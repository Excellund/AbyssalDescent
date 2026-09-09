param(
    [Parameter(Mandatory = $true)][string]$ValidationProject,
    [string]$GodotPath = ''
)
& (Join-Path $PSScriptRoot 'test_boss_combinations_enet.ps1') -ValidationProject $ValidationProject -GodotPath $GodotPath -FixtureScript 'res://scripts/tests/test_archer_projectiles_enet.gd'

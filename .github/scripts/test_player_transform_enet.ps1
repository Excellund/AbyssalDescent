param([Parameter(Mandatory = $true)][string]$ValidationProject, [string]$GodotPath = '')
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test_boss_combinations_enet.ps1') -ValidationProject $ValidationProject -GodotPath $GodotPath -FixtureScript 'res://scripts/tests/test_player_transform_enet.gd'
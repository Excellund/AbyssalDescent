param([Parameter(Mandatory = $true)][string]$ValidationProject, [Parameter(Mandatory = $true)][string]$BaselineProject, [string]$GodotPath = '')
$ErrorActionPreference = 'Stop'
$validationRoot = (Resolve-Path -LiteralPath $ValidationProject).Path
$baselineRoot = (Resolve-Path -LiteralPath $BaselineProject).Path
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $validationRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or -not $baselineRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Both projects must be isolated temporary validation copies.' }
$inputRoot = Join-Path $tempRoot ('abyssal-enemy-visual-input-' + [guid]::NewGuid().ToString('N'))
Copy-Item -LiteralPath $validationRoot -Destination $inputRoot -Recurse
$baselineDirectory = Join-Path $inputRoot 'validation_fixtures/enemy_visual_baseline'
New-Item -ItemType Directory -Path $baselineDirectory | Out-Null
$hashes = @{}
foreach ($role in @('base','chaser','charger','archer','shielder','weaver','drifter','sentinel','pyre','boss')) {
    $filename = 'enemy_' + $role + '.gd'
    $original = Join-Path $baselineRoot ('scripts/' + $filename)
    $hashes[$filename] = (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash
    $source = Get-Content -LiteralPath $original -Raw
    $source = $source.Replace('extends "res://scripts/enemy_base.gd"', 'extends "res://validation_fixtures/enemy_visual_baseline/enemy_base.gd"')
    [IO.File]::WriteAllText((Join-Path $baselineDirectory $filename), $source, (New-Object Text.UTF8Encoding($false)))
}
[IO.File]::WriteAllText((Join-Path $inputRoot 'validation_fixtures/enemy_visual_baseline.json'), (@{source=$baselineRoot;sha256=$hashes} | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
Write-Output "Frozen enemy comparison input: $inputRoot"
& (Join-Path $PSScriptRoot 'render_gameplay_fixture.ps1') -ValidationProject $inputRoot -GodotPath $GodotPath -FixtureScript 'res://scripts/tests/render_enemy_visual_profiles.gd' -FrameFolder 'enemy_visual_frames' -ExpectedFrames 12 -MaxFrames 2200

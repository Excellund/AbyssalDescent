param(
    [Parameter(Mandatory = $true)][string]$ValidationProject,
    [ValidateSet('Baseline', 'Compare')][string]$Mode = 'Baseline',
    [string]$GodotPath = ''
)
$ErrorActionPreference = 'Stop'
$sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$validationRoot = (Resolve-Path -LiteralPath $ValidationProject).Path
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $validationRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Only an isolated temporary validation project is allowed.' }
$baselinePath = Join-Path $sourceRoot '.feedback/workday-20260911/performance-baseline/world_hud.gd'
$baselineHash = (Get-FileHash -LiteralPath $baselinePath -Algorithm SHA256).Hash
if ($baselineHash -ne 'E94CA093DC9DA7701555807190B2D99C588E349000B8A8D84838470757121423') { throw 'The retained pre-change HUD does not match the recorded baseline.' }
$inputRoot = Join-Path $tempRoot ('abyssal-hud-benchmark-input-' + [guid]::NewGuid().ToString('N'))
Copy-Item -LiteralPath $validationRoot -Destination $inputRoot -Recurse
Copy-Item -LiteralPath $baselinePath -Destination (Join-Path $inputRoot 'validation_fixtures/hud_refresh_baseline.gd')
$trialOrder = if ($Mode -eq 'Baseline') { @('baseline', 'baseline') } else { @('baseline', 'candidate', 'candidate', 'baseline') }
$benchmarkConfig = @{ order = $trialOrder; baseline_sha256 = $baselineHash; candidate_sha256 = (Get-FileHash -LiteralPath (Join-Path $sourceRoot 'scripts/world_hud.gd') -Algorithm SHA256).Hash }
[IO.File]::WriteAllText((Join-Path $inputRoot 'validation_fixtures/hud_benchmark.json'), ($benchmarkConfig | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
Write-Output "Frozen HUD benchmark input: $inputRoot"
& (Join-Path $PSScriptRoot 'render_gameplay_fixture.ps1') -ValidationProject $inputRoot -GodotPath $GodotPath -FixtureScript 'res://scripts/tests/benchmark_hud_refresh.gd' -FrameFolder 'hud_benchmark_frames' -ExpectedFrames $trialOrder.Count -MaxFrames 3000

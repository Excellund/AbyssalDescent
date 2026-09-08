param(
    [Parameter(Mandatory = $true)][string]$ValidationProject,
    [string]$GodotPath = '',
    [ValidatePattern('^res://scripts/tests/test_[a-z0-9_]+_enet\.gd$')][string]$FixtureScript = 'res://scripts/tests/test_boss_combinations_enet.gd'
)
$ErrorActionPreference = 'Stop'
$sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $FixtureScript.Substring(6)) -PathType Leaf)) { throw "The requested ENet fixture does not exist: $FixtureScript" }
$snapshotRoot = (Resolve-Path -LiteralPath $ValidationProject).Path
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $snapshotRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Use a disposable validation project inside system temp.' }
$config = Get-Content -LiteralPath (Join-Path $snapshotRoot 'project.godot') -Raw
$autoloads = [regex]::Matches($config, '(?m)^\w+="\*(res://[^"]+)"')
if ($autoloads.Count -eq 0 -or ($autoloads | Where-Object { -not $_.Groups[1].Value.StartsWith('res://validation_fixtures/') }) -or -not $config.Contains('config/use_custom_user_dir=true')) { throw 'All autoload startup must be suppressed and user data isolated.' }
if (-not $GodotPath) { $GodotPath = (Get-Content (Join-Path $sourceRoot '.vscode/settings.json') -Raw | ConvertFrom-Json).'godot.executablePath' }
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
$testRoot = Join-Path $tempRoot ('abyssal-enet-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
foreach ($folder in @('scripts', 'scenes', 'assets', 'music', 'sounds', '.godot', 'validation_fixtures')) {
    if (Test-Path -LiteralPath (Join-Path $snapshotRoot $folder)) { Copy-Item -LiteralPath (Join-Path $snapshotRoot $folder) -Destination $testRoot -Recurse }
}
foreach ($file in @('validation_entry.gd', 'icon.svg', 'icon.svg.import')) { Copy-Item -LiteralPath (Join-Path $snapshotRoot $file) -Destination $testRoot }
Copy-Item -LiteralPath (Join-Path $sourceRoot 'scripts') -Destination $testRoot -Recurse -Force
[IO.File]::WriteAllText((Join-Path $testRoot 'project.godot'), $config, (New-Object Text.UTF8Encoding($false)))
$previousEnvironment = @{}
$ownedProcesses = [Collections.Generic.List[Diagnostics.Process]]::new()
function Set-IsolatedEnvironment([string]$Role) {
    foreach ($name in @('APPDATA','LOCALAPPDATA','XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME')) {
        if (-not $previousEnvironment.ContainsKey($name)) { $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
        $isolated = Join-Path $testRoot ($Role + '/' + $name.ToLowerInvariant())
        New-Item -ItemType Directory -Path $isolated -Force | Out-Null
        [Environment]::SetEnvironmentVariable($name, $isolated, 'Process')
    }
}
function Start-Fixture([string]$Role, [string[]]$ExtraArguments) {
    Set-IsolatedEnvironment $Role
    $arguments = @('--headless', '--path', $testRoot, '--log-file', (Join-Path $testRoot ($Role + '.log'))) + $ExtraArguments
    $line = ($arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $process = Start-Process -FilePath $GodotPath -ArgumentList $line -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testRoot ($Role + '-stdout.log')) -RedirectStandardError (Join-Path $testRoot ($Role + '-stderr.log'))
    $ownedProcesses.Add($process)
    return $process
}
function Assert-Fixture([string]$Role, [Diagnostics.Process]$Process) {
    $Process.WaitForExit()
    $lines = @(Get-Content -LiteralPath (Join-Path $testRoot ($Role + '-stdout.log'))) + @(Get-Content -LiteralPath (Join-Path $testRoot ($Role + '-stderr.log')))
    $errors = @($lines | Where-Object { $_ -match 'SCRIPT ERROR:|Parse Error:|Compile Error:|ERROR:|ObjectDB instances leaked' -and $_ -notmatch 'ERROR: Failed to read the root certificate store\.' })
    if ($Process.ExitCode -ne 0 -or $errors.Count -gt 0) { $lines | Write-Output; throw "$Role failed. Logs: $testRoot" }
    $lines | Where-Object { $_ -match '^\[ENet\]' } | Write-Output
}
try {
    $import = Start-Fixture 'import' @('--editor', '--import')
    if (-not $import.WaitForExit(60000)) { throw 'Isolated import exceeded 60 seconds.' }
    Assert-Fixture 'import' $import
    # Ask the OS for an ephemeral loopback UDP port; the game never uses its
    # configured multiplayer port, external room registry, tunnel, or UPnP.
    $reservation = [Net.Sockets.UdpClient]::new([Net.IPEndPoint]::new([Net.IPAddress]::Loopback, 0))
    $fixturePort = ([Net.IPEndPoint]$reservation.Client.LocalEndPoint).Port
    $reservation.Dispose()
    $reportPrefix = Join-Path $testRoot 'result'
    $common = @('--script', 'res://validation_entry.gd', '--quit-after', '2000', '--', $FixtureScript)
    $hostProcess = Start-Fixture 'host' ($common + @('host', [string]$fixturePort, $reportPrefix))
    $deadline = [DateTime]::UtcNow.AddSeconds(25)
    while (-not (Test-Path -LiteralPath ($reportPrefix + '-ready')) -and -not $hostProcess.HasExited -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
    if (-not (Test-Path -LiteralPath ($reportPrefix + '-ready'))) {
        if ($hostProcess.HasExited) { Assert-Fixture 'host' $hostProcess }
        throw 'Loopback host did not become ready.'
    }
    $clientProcess = Start-Fixture 'client' ($common + @('client', [string]$fixturePort, $reportPrefix))
    while ((-not $hostProcess.HasExited -or -not $clientProcess.HasExited) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
    if (-not $hostProcess.HasExited -or -not $clientProcess.HasExited) { throw 'Two-process fixture exceeded 25 seconds.' }
    Assert-Fixture 'host' $hostProcess
    Assert-Fixture 'client' $clientProcess
    foreach ($role in @('host', 'client')) {
        $report = Get-Content -LiteralPath ($reportPrefix + '-' + $role + '.json') -Raw | ConvertFrom-Json
        if ($report.checks -lt 1 -or $report.failures.Count -ne 0) { throw "$role fixture report failed." }
    }
    Write-Host "ENet reports and logs: $testRoot"
} finally {
    foreach ($process in $ownedProcesses) { if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() } }
    foreach ($name in $previousEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process') }
    Write-Host "Fixture project: $testRoot"
}

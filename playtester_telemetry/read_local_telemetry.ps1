param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$GodotPath = ''
)
$ErrorActionPreference = 'Stop'
$inputPath = (Resolve-Path -LiteralPath $Path).Path
if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf) -or [IO.Path]::GetExtension($inputPath) -ne '.save') { throw 'Select the local run_telemetry.save file.' }
if ((Get-Item -LiteralPath $inputPath).Length -gt 64MB) { throw 'Local telemetry exceeds the 64 MB analysis limit.' }
if (-not $GodotPath) {
    $settings = Join-Path $PSScriptRoot '../.vscode/settings.json'
    if (Test-Path -LiteralPath $settings) { $GodotPath = [string](Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json).'godot.executablePath' }
}
if (-not $GodotPath) { $GodotPath = $env:GODOT_EXE }
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw 'Supply -GodotPath or configure the project Godot executable.' }
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path

# Copy only data and a standalone decoder. No game settings, autoloads, profile
# startup, repair-on-read store methods, or network clients enter this project.
$decodeRoot = Join-Path ([IO.Path]::GetTempPath()) ('abyssal-telemetry-read-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $decodeRoot | Out-Null
Copy-Item -LiteralPath $inputPath -Destination (Join-Path $decodeRoot 'input.save')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'read_local_telemetry.gd') -Destination (Join-Path $decodeRoot 'decode.gd')
Set-Content -LiteralPath (Join-Path $decodeRoot 'project.godot') -Encoding utf8 -Value 'config_version=5'
$previousEnvironment = @{}
$process = $null
try {
    foreach ($name in @('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME')) {
        $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $decodeRoot, 'Process')
    }
    $arguments = @('--headless', '--path', ('"' + $decodeRoot + '"'), '--script', 'res://decode.gd')
    $process = Start-Process -FilePath $GodotPath -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $decodeRoot 'stdout.log') -RedirectStandardError (Join-Path $decodeRoot 'stderr.log')
    if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Local telemetry decoding exceeded 30 seconds.' }
    $lines = @(Get-Content -LiteralPath (Join-Path $decodeRoot 'stdout.log')) + @(Get-Content -LiteralPath (Join-Path $decodeRoot 'stderr.log'))
    $errors = @($lines | Where-Object { $_ -match 'SCRIPT ERROR:|Parse Error:|Compile Error:|ERROR:' -and $_ -notmatch 'ERROR: Failed to read the root certificate store\.' })
    $decodedPath = Join-Path $decodeRoot 'decoded.json'
    if ($process.ExitCode -ne 0 -or $errors.Count -gt 0 -or -not (Test-Path -LiteralPath $decodedPath)) { throw "Local telemetry could not be decoded. Diagnostic logs: $decodeRoot" }
    Get-Content -LiteralPath $decodedPath -Raw | ConvertFrom-Json
} finally {
    if ($null -ne $process) { $process.Dispose() }
    foreach ($name in $previousEnvironment.Keys) {
        if ($null -eq $previousEnvironment[$name]) {
            [Environment]::SetEnvironmentVariable($name, [NullString]::Value, 'Process')
        } else {
            [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
        }
    }
}

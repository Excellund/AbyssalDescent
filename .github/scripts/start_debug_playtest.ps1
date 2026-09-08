param(
    [string]$GodotPath = '',
    [string]$OutputPath = '',
    [string]$BuildVersion = '',
    [switch]$ValidateOnly,
    [switch]$Overwrite
)

# Run outside the Codex sandbox for a visible interactive desktop window.
# Debug and normal playtests share the same desktop executable.
$ErrorActionPreference = 'Stop'
$exporter = Join-Path $PSScriptRoot 'export_playtest.ps1'
$arguments = @{ GodotPath = $GodotPath; OutputPath = $OutputPath; BuildVersion = $BuildVersion; DebugRun = $true; Overwrite = $Overwrite }
if ($ValidateOnly) {
    & $exporter @arguments -ValidateOnly
    return
}
$results = @(& $exporter @arguments)
$build = $results | Where-Object { $_ -is [PSCustomObject] -and $_.PSObject.Properties['OutputPath'] } | Select-Object -Last 1
if ($null -eq $build) { throw 'The exporter did not return a verified playtest.' }
$game = Start-Process -FilePath $build.OutputPath -WorkingDirectory (Split-Path -Parent $build.OutputPath) -WindowStyle Normal -PassThru
$deadline = [DateTime]::UtcNow.AddSeconds(15)
while (-not $game.HasExited -and $game.MainWindowHandle -eq 0 -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 100
    $game.Refresh()
}
if ($game.HasExited -or $game.MainWindowHandle -eq 0) { throw 'The exported debug playtest did not open its game window.' }
[PSCustomObject]@{ ProcessId = $game.Id; Executable = $build.OutputPath; Version = $build.BuildVersion; DebugRun = $true }

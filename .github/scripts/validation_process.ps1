# Windows PowerShell 5.1-compatible process ownership for isolated validation.
# Godot's console executable launches a GUI executable, so timeout cleanup must
# stop the retained wrapper AND its descendants, never every Godot process.
function ConvertTo-ValidationArgument([string]$Value) {
    '"' + (($Value -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}

function Stop-ValidationProcessTree([Diagnostics.Process]$Process, [string]$LogPrefix) {
    if ($Process.HasExited) { return }
    $taskkill = Join-Path ([Environment]::GetFolderPath('System')) 'taskkill.exe'
    $terminator = $null
    try {
        # The retained Process is still running. Use its numeric ID directly;
        # do not discover or terminate processes by executable name.
        $terminator = Start-Process -FilePath $taskkill -ArgumentList @('/PID', [string]$Process.Id, '/T', '/F') -WindowStyle Hidden -PassThru -RedirectStandardOutput ($LogPrefix + '-stop-stdout.log') -RedirectStandardError ($LogPrefix + '-stop-stderr.log')
        $null = $terminator.Handle
        if (-not $terminator.WaitForExit(5000)) {
            $terminator.Kill()
            $null = $terminator.WaitForExit(5000)
            throw "Process-tree cleanup exceeded 5 seconds for owned PID $($Process.Id). Logs: $LogPrefix"
        }
        if (-not $Process.WaitForExit(5000)) {
            throw "Could not stop owned validation process tree $($Process.Id) (taskkill exit $($terminator.ExitCode)). Logs: $LogPrefix"
        }
        # taskkill may race a normal exit. Otherwise its failure needs attention
        # even if the wrapper has exited, because descendants may remain alive.
        if ($terminator.ExitCode -ne 0) {
            throw "Process-tree cleanup returned $($terminator.ExitCode) for owned PID $($Process.Id). Logs: $LogPrefix"
        }
    } finally {
        if ($null -ne $terminator) { $terminator.Dispose() }
    }
}

function Invoke-ValidationProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Program,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$Label,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$LogDirectory,
        [Parameter(Mandatory = $true)][ValidateRange(1, 3600)][int]$TimeoutSeconds
    )
    $logPrefix = Join-Path $LogDirectory $Label
    $stdout = $logPrefix + '-stdout.log'
    $stderr = $logPrefix + '-stderr.log'
    $consoleLog = $logPrefix + '-console.log'
    $process = $null
    $failure = ''
    $exitCode = $null
    try {
        $argumentLine = ($Arguments | ForEach-Object { ConvertTo-ValidationArgument $_ }) -join ' '
        $process = Start-Process -FilePath $Program -ArgumentList $argumentLine -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        # Retain the native handle before a fast process exits. Windows
        # PowerShell otherwise can lose the exit code returned by Start-Process.
        $null = $process.Handle
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $failure = "$Label exceeded $TimeoutSeconds seconds (owned PID $($process.Id))."
        } else {
            $exitCode = $process.ExitCode
        }
    } catch {
        $failure = "$Label could not complete: $($_.Exception.Message)"
    } finally {
        if ($null -ne $process) {
            try {
                Stop-ValidationProcessTree -Process $process -LogPrefix $logPrefix
            } catch {
                $failure += " $($_.Exception.Message)"
            } finally {
                $process.Dispose()
            }
        }
        # Separate streams retain their original evidence; the console summary
        # groups stdout before stderr instead of claiming cross-stream ordering.
        $output = @()
        foreach ($path in @($stdout, $stderr)) {
            if (Test-Path -LiteralPath $path) { $output += @(Get-Content -LiteralPath $path) }
        }
        $output | Set-Content -LiteralPath $consoleLog -Encoding utf8
    }
    $errors = @($output | Where-Object {
        $_ -match 'SCRIPT ERROR:|Parse Error:|Compile Error:|ERROR:' -and
        $_ -notmatch 'ERROR: Failed to read the root certificate store\.'
    })
    if ($failure -or $exitCode -ne 0 -or $errors.Count -gt 0) {
        $output | Write-Host
        if (-not $failure) { $failure = "$Label failed (exit $exitCode)." }
        Add-Content -LiteralPath $consoleLog -Value "[ValidationFailure] $failure Deadline: $TimeoutSeconds seconds." -Encoding utf8
        throw "$failure Deadline: $TimeoutSeconds seconds. Logs: $consoleLog"
    }
    [pscustomobject]@{ ExitCode = $exitCode; Output = $output; ConsoleLog = $consoleLog }
}

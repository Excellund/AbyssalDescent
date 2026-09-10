param(
    [string]$PythonPath = '',
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
if (-not $PythonPath) {
    foreach ($candidate in @('python', 'py')) {
        $runtime = Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($runtime -and $runtime.Source -notlike '*WindowsApps*') {
            $PythonPath = $runtime.Source
            break
        }
    }
}
if (-not $PythonPath) {
    throw 'Python 3.10 or newer is required. Install Python or run start.ps1 -PythonPath <python.exe>.'
}
& $PythonPath -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)'
if ($LASTEXITCODE -ne 0) { throw 'The feedback board requires Python 3.10 or newer.' }
$boardArguments = @((Join-Path $PSScriptRoot 'board.py'), 'launch')
if ($NoBrowser) { $boardArguments += '--no-browser' }
& $PythonPath @boardArguments
if ($LASTEXITCODE -ne 0) { throw 'The feedback board did not open. See the error above.' }

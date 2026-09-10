# Inert native-process tests. No Godot, game data, player profile or network.
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'validation_process.ps1')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('abyssal-process-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$script:checks = 0
function Assert-Check([bool]$Condition, [string]$Message) {
    $script:checks++
    if (-not $Condition) { throw "FAIL: $Message. Evidence: $testRoot" }
}
function Assert-Rejected([scriptblock]$Operation, [string]$Pattern, [string]$Message) {
    $failure = ''
    try { & $Operation | Out-Null } catch { $failure = $_.Exception.Message }
    Assert-Check ($failure -match $Pattern) "$Message; actual result: $failure"
}
# Compile with .NET Framework so the inert executable behaves identically when
# this test is called from Windows PowerShell 5.1 or newer PowerShell.
$nativeSource = Join-Path $testRoot 'inert.cs'
$nativeExe = Join-Path $testRoot 'inert process.exe'
@'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
public class InertValidation {
    public static int Main(string[] args) {
        string mode = args.Length > 0 ? args[0] : "success";
        string root = args.Length > 1 ? args[1] : Environment.CurrentDirectory;
        if (mode == "--headless") {
            root = Environment.CurrentDirectory;
            mode = Environment.GetEnvironmentVariable("ABYSSAL_PROCESS_TEST_MODE") ?? "success";
            bool import = Array.IndexOf(args, "--editor") >= 0;
            if (import && mode != "import-timeout") mode = "success";
            else if (mode == "import-timeout") mode = "timeout";
            int logIndex = Array.IndexOf(args, "--log-file");
            if (logIndex >= 0) File.WriteAllText(args[logIndex + 1], "inert engine evidence\n");
        }
        Console.WriteLine("inert stdout: " + mode);
        Console.Error.WriteLine("inert stderr: " + mode);
        if (mode == "child") {
            File.WriteAllText(Path.Combine(root, "child.pid"), Process.GetCurrentProcess().Id.ToString());
            // A failed watchdog assertion must not leave an indefinite orphan.
            Thread.Sleep(30000);
        }
        if (mode == "timeout") {
            File.WriteAllText(Path.Combine(root, "parent.pid"), Process.GetCurrentProcess().Id.ToString());
            var start = new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName,
                "child \"" + root + "\"");
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            using (var child = Process.Start(start)) child.WaitForExit();
        }
        if (mode == "script-error") Console.Error.WriteLine("SCRIPT ERROR: inert zero-exit failure");
        if (mode == "certificate") Console.Error.WriteLine("ERROR: Failed to read the root certificate store.");
        if (mode == "arguments") Console.WriteLine("argument=" + args[2]);
        return mode == "nonzero" ? 7 : 0;
    }
}
'@ | Set-Content -LiteralPath $nativeSource -Encoding utf8
$compilerScript = Join-Path $testRoot 'compile.ps1'
@'
param([string]$Source, [string]$Output)
$ErrorActionPreference = 'Stop'
Add-Type -Path $Source -OutputAssembly $Output -OutputType ConsoleApplication
'@ | Set-Content -LiteralPath $compilerScript -Encoding utf8
$windowsPowerShell = Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell/v1.0/powershell.exe'
$compileArguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $compilerScript, '-Source', $nativeSource, '-Output', $nativeExe)
$null = Invoke-ValidationProcess -Program $windowsPowerShell -Arguments $compileArguments -Label 'compile-inert' -WorkingDirectory $testRoot -LogDirectory $testRoot -TimeoutSeconds 30

function Invoke-Inert([string]$Mode, [int]$Seconds = 10) {
    Invoke-ValidationProcess -Program $nativeExe -Arguments @($Mode, $testRoot) -Label $Mode -WorkingDirectory $testRoot -LogDirectory $testRoot -TimeoutSeconds $Seconds
}
function Assert-NoOwnedProcess([string]$Directory) {
    foreach ($name in @('parent', 'child')) {
        $pidFile = Join-Path $Directory ($name + '.pid')
        Assert-Check (Test-Path -LiteralPath $pidFile) "$name actually launched"
        $ownedId = [int](Get-Content -LiteralPath $pidFile -Raw)
        Assert-Check ($null -eq (Get-Process -Id $ownedId -ErrorAction SilentlyContinue)) "$name PID $ownedId retired"
    }
}
$success = Invoke-Inert 'success'
Assert-Check ($success.ExitCode -eq 0 -and $success.Output -contains 'inert stdout: success' -and $success.Output -contains 'inert stderr: success') 'Success retains both output streams and actual exit code'
Assert-Rejected { Invoke-Inert 'nonzero' } 'nonzero failed \(exit 7\)' 'Nonzero native exit fails validation'
Assert-Rejected { Invoke-Inert 'script-error' } 'script-error failed \(exit 0\)' 'Godot script-error text fails even with zero native exit'
Assert-Check ((Get-Content -LiteralPath (Join-Path $testRoot 'script-error-console.log') -Raw) -match 'SCRIPT ERROR: inert zero-exit failure') 'Final stderr immediately before process exit is retained in the console log'
$null = Invoke-Inert 'certificate'
Assert-Check $true 'Existing Windows sandbox certificate exception remains allowed'
$argument = 'space "quote" trailing\'
$quoted = Invoke-ValidationProcess -Program $nativeExe -Arguments @('arguments', $testRoot, $argument) -Label 'arguments' -WorkingDirectory $testRoot -LogDirectory $testRoot -TimeoutSeconds 10
Assert-Check ($quoted.Output -contains ('argument=' + $argument)) 'Windows argument quoting preserves spaces, quotes and trailing backslashes'
$timer = [Diagnostics.Stopwatch]::StartNew()
Assert-Rejected { Invoke-Inert 'timeout' 2 } 'timeout exceeded 2 seconds' 'Parent waiting on its child reaches a bounded timeout'
Assert-Check ($timer.Elapsed.TotalSeconds -lt 15) 'Timeout and cleanup return within the watchdog plus cleanup bounds'
Assert-NoOwnedProcess $testRoot
foreach ($suffix in @('-stdout.log', '-stderr.log', '-console.log', '-stop-stdout.log', '-stop-stderr.log')) {
    Assert-Check (Test-Path -LiteralPath (Join-Path $testRoot ('timeout' + $suffix))) "Timeout preserves $suffix"
}
Assert-Check ((Get-Content -LiteralPath (Join-Path $testRoot 'timeout-console.log') -Raw) -match 'inert stdout: timeout') 'Timeout console log retains output produced before termination'
Assert-Check ((Get-Content -LiteralPath (Join-Path $testRoot 'timeout-console.log') -Raw) -match 'timeout exceeded 2 seconds') 'Timeout evidence records the fixture label and deadline'

# Exercise the real runner's import/fixture dispatch and finally block against
# a tiny disposable source tree. The inert executable ignores Godot arguments.
$sourceRoot = Join-Path $testRoot 'tiny source with spaces'
foreach ($folder in @('.github/scripts', 'scripts', 'scenes', 'assets', 'music', 'sounds')) {
    New-Item -ItemType Directory -Path (Join-Path $sourceRoot $folder) -Force | Out-Null
}
foreach ($name in @('run_gameplay_regressions.ps1', 'validation_process.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $sourceRoot '.github/scripts')
}
Set-Content -LiteralPath (Join-Path $sourceRoot 'project.godot') -Value "[application]`nconfig/name=`"InertOnly`"" -Encoding utf8
foreach ($name in @('icon.svg', 'icon.svg.import')) { Set-Content -LiteralPath (Join-Path $sourceRoot $name) -Value '' }
$environmentNames = @('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'TEMP', 'TMP', 'ABYSSAL_PROCESS_TEST_MODE')
$originalEnvironment = @{}
foreach ($name in $environmentNames) { $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$runner = Join-Path $sourceRoot '.github/scripts/run_gameplay_regressions.ps1'
try {
    $env:TEMP = Join-Path $testRoot 'isolated-runs'
    $env:TMP = $env:TEMP
    New-Item -ItemType Directory -Path $env:TEMP | Out-Null
    foreach ($mode in @('success', 'nonzero', 'script-error', 'timeout', 'import-timeout')) {
        $env:ABYSSAL_PROCESS_TEST_MODE = $mode
        $fixtureDeadline = if ($mode -eq 'timeout') { 2 } else { 10 }
        $importDeadline = if ($mode -eq 'import-timeout') { 2 } else { 10 }
        if ($mode -eq 'success') {
            $lines = & $runner -GodotPath $nativeExe -CompileOnly -FixtureTimeoutSeconds $fixtureDeadline -ImportTimeoutSeconds $importDeadline 6>&1
            Assert-Check (($lines | Out-String) -match '\[PASS\] validate_multiplayer_config_sync') 'Real runner completes all compile gates on native success'
        } else {
            $reason = if ($mode -eq 'nonzero') { 'validate_gdscript_compile failed \(exit 7\)' } elseif ($mode -eq 'script-error') { 'validate_gdscript_compile failed \(exit 0\)' } elseif ($mode -eq 'timeout') { 'validate_gdscript_compile exceeded 2 seconds' } else { 'import exceeded 2 seconds' }
            Assert-Rejected { & $runner -GodotPath $nativeExe -CompileOnly -FixtureTimeoutSeconds $fixtureDeadline -ImportTimeoutSeconds $importDeadline } $reason "Real runner propagates $mode"
        }
        foreach ($name in @('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME')) {
            Assert-Check ([Environment]::GetEnvironmentVariable($name, 'Process') -ceq $originalEnvironment[$name]) "$mode restores $name"
        }
    }
    foreach ($directory in Get-ChildItem -LiteralPath $env:TEMP -Directory) {
        if (Test-Path -LiteralPath (Join-Path $directory.FullName 'parent.pid')) { Assert-NoOwnedProcess $directory.FullName }
        Assert-Check (Test-Path -LiteralPath (Join-Path $directory.FullName 'import.log')) 'Real runner preserves its engine log on every outcome'
    }
} finally {
    foreach ($name in $environmentNames) {
        if ($null -eq $originalEnvironment[$name]) {
            [Environment]::SetEnvironmentVariable($name, [System.Management.Automation.Language.NullString]::Value, 'Process')
        } else {
            [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], 'Process')
        }
    }
}
Write-Host "[OK] Validation process: $script:checks checks. Evidence: $testRoot"

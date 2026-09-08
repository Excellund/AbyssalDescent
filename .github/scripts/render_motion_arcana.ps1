param(
    [Parameter(Mandatory = $true)][string]$ValidationProject,
    [string]$GodotPath = ''
)

$ErrorActionPreference = 'Stop'
$sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$ValidationProject = (Resolve-Path -LiteralPath $ValidationProject).Path
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $ValidationProject.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'ValidationProject must be a disposable copy inside the system temporary directory.'
}
$config = Get-Content -LiteralPath (Join-Path $ValidationProject 'project.godot') -Raw
$autoloads = [regex]::Matches($config, '(?m)^\w+="\*(res://[^"]+)"')
if ($autoloads.Count -eq 0 -or ($autoloads | Where-Object { -not $_.Groups[1].Value.StartsWith('res://validation_fixtures/') }) -or -not $config.Contains('config/use_custom_user_dir=true')) {
    throw 'ValidationProject must use isolated user data and only suppressed validation autoloads.'
}
if (-not $GodotPath) {
    $GodotPath = (Get-Content -LiteralPath (Join-Path $sourceRoot '.vscode/settings.json') -Raw | ConvertFrom-Json).'godot.executablePath'
}
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
$renderRoot = Join-Path $tempRoot ('abyssal-motion-render-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $renderRoot | Out-Null
foreach ($folder in @('scripts', 'scenes', 'assets', 'music', 'sounds', '.godot', 'validation_fixtures', '.github')) {
    $sourceFolder = Join-Path $ValidationProject $folder
    if (Test-Path -LiteralPath $sourceFolder) { Copy-Item -LiteralPath $sourceFolder -Destination $renderRoot -Recurse }
}
foreach ($file in @('validation_entry.gd', 'icon.svg', 'icon.svg.import')) {
    Copy-Item -LiteralPath (Join-Path $ValidationProject $file) -Destination $renderRoot
}
# Keep the copied, disabled autoload wrappers, but render the latest production
# scripts. Never modify the supplied validation copy while another test uses it.
Copy-Item -LiteralPath (Join-Path $sourceRoot 'scripts') -Destination $renderRoot -Recurse -Force
$config = [regex]::Replace($config, '(?m)^window/size/(no_focus|mode|viewport_width|viewport_height|window_width_override|window_height_override|initial_position_type|initial_position)=.*\r?\n?', '')
$config += @'

[display]
window/size/no_focus=true
window/size/mode=0
window/size/viewport_width=1280
window/size/viewport_height=720
window/size/window_width_override=1280
window/size/window_height_override=720
window/size/initial_position_type=0
window/size/initial_position=Vector2i(-20000, -20000)
'@
[IO.File]::WriteAllText((Join-Path $renderRoot 'project.godot'), $config, (New-Object Text.UTF8Encoding($false)))

function Invoke-HiddenGodot([string]$Label, [string[]]$Arguments) {
    $stdout = Join-Path $renderRoot ($Label + '-stdout.log')
    $stderr = Join-Path $renderRoot ($Label + '-stderr.log')
    $engineLog = Join-Path $renderRoot ($Label + '.log')
    $allArguments = @('--path', $renderRoot, '--log-file', $engineLog) + $Arguments
    # All variable arguments here are filesystem paths (which cannot contain
    # quotes on Windows). Quote each argument for Start-Process's command line.
    $argumentLine = ($allArguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $process = Start-Process -FilePath $GodotPath -ArgumentList $argumentLine -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if (-not $process.WaitForExit(60000)) {
        $process.Kill()
        throw "$Label exceeded 60 seconds; stopped only its own fixture process. Logs: $renderRoot"
    }
    $process.WaitForExit()
    $lines = @(Get-Content -LiteralPath $stdout) + @(Get-Content -LiteralPath $stderr)
    $errors = @($lines | Where-Object { $_ -match 'SCRIPT ERROR:|Parse Error:|Compile Error:|ERROR:' -and $_ -notmatch 'ERROR: Failed to read the root certificate store\.' })
    if ($process.ExitCode -ne 0 -or $errors.Count -gt 0) {
        $lines | Write-Output
        throw "$Label failed. Logs: $renderRoot"
    }
    Write-Host "[PASS] $Label"
    $lines | Where-Object { $_ -match '^\[OK\]|^\[FRAME\]|^MOTION_FRAMES=' } | Write-Output
}

$previousEnvironment = @{}
try {
    foreach ($name in @('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME')) {
        $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        $isolatedPath = Join-Path $renderRoot $name.ToLowerInvariant()
        New-Item -ItemType Directory -Path $isolatedPath | Out-Null
        [Environment]::SetEnvironmentVariable($name, $isolatedPath, 'Process')
    }
    Invoke-HiddenGodot 'import' @('--headless', '--editor', '--import')
    # Headless uses a dummy renderer on Windows. Use a no-focus, offscreen GPU
    # window instead; synthetic Input actions remain inside this process. See
    # https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-display-window-size-no-focus
    Invoke-HiddenGodot 'render' @('--verbose', '--display-driver', 'windows', '--rendering-method', 'gl_compatibility', '--rendering-driver', 'opengl3', '--audio-driver', 'Dummy', '--windowed', '--resolution', '1280x720', '--position', '-20000,-20000', '--max-fps', '60', '--fixed-fps', '60', '--quit-after', '1000', '--script', 'res://validation_entry.gd', '--', 'res://scripts/tests/render_motion_arcana.gd')
    $manifestPath = Join-Path $renderRoot 'motion_frames/manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'The GPU fixture did not complete its capture manifest.' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.frames.Count -ne 11 -or $manifest.failures.Count -ne 0) { throw 'The GPU fixture did not produce all eleven valid states.' }
    Write-Host "GPU: $($manifest.gpu)"
    Write-Host "Motion frames: $(Split-Path -Parent $manifestPath)"
} finally {
    foreach ($name in $previousEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process') }
    Write-Host "Render project and logs: $renderRoot"
}

# PowerShell pre-commit hook for build validation and debug checks
# This prevents commits when:
# 1. Godot scripts have syntax errors
# 2. Debug options are enabled in the project

$ErrorActionPreference = "Stop"
$projectRoot = git rev-parse --show-toplevel
$scriptsPath = "$projectRoot/scripts"

function Get-DebugSettingValue {
    param(
        [string]$content,
        [string]$settingName
    )

    # Match both typed declarations and plain assignments, and ignore trailing comments.
    $escapedName = [regex]::Escape($settingName)
    $pattern = "(?m)^[ \t]*(?!#).*?\b$escapedName\b\s*(?::\s*[^=\r\n]+)?=\s*([^\r\n#]+)"
    $matches = [regex]::Matches($content, $pattern)
    if ($matches.Count -eq 0) {
        return $null
    }

    return $matches[$matches.Count - 1].Groups[1].Value.Trim()
}

function Test-DebugValueAllowed {
    param(
        [string]$value,
        [string]$allowedPattern
    )

        if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
        return $true
    }

        return ([string]$value) -match $allowedPattern
}

Write-Host "[PRE-COMMIT] Starting validation..." -ForegroundColor Cyan

# ============================================================================
# CHECK 1: Validate Godot script syntax (quick check)
# ============================================================================
Write-Host ""
Write-Host "Checking for syntax issues..." -ForegroundColor Yellow

# Only check recently modified or staged files for performance
$stagedFiles = @()
try {
    $stagedFiles = git diff --cached --name-only --diff-filter=ACM | Where-Object { $_ -like "*.gd" }
} catch {
    Write-Host "[WARN] Could not get staged files" -ForegroundColor Yellow
}

if ($stagedFiles.Count -eq 0) {
    Write-Host "[SKIP] No .gd files staged for commit" -ForegroundColor Yellow
} else {
    $quickErrors = 0
    foreach ($file in $stagedFiles) {
        $fullPath = "$projectRoot/$file"
        if (-not (Test-Path $fullPath)) { continue }
        
        $content = Get-Content -Path $fullPath -Raw
        
        # Quick checks only - unclosed braces at end of file
        if ($content -match '\{\s*$' -and -not ($content -match '\}\s*$')) {
            Write-Host "  [ERROR] $($file): Possible unclosed braces" -ForegroundColor Red
            $quickErrors++
        }
    }
    
    if ($quickErrors -gt 0) {
        exit 1
    }
    
    Write-Host "[OK] Staged .gd files checked ($($stagedFiles.Count) files)" -ForegroundColor Green
}

# ============================================================================
# CHECK 2: Verify debug options are not enabled
# ============================================================================
Write-Host ""
Write-Host "Checking for enabled debug options..." -ForegroundColor Yellow

$debugChecksPassed = $true

# Check world_generator.gd for debug exports
$worldGenPath = "$scriptsPath/world_generator.gd"
if (Test-Path $worldGenPath) {
    $content = Get-Content -Path $worldGenPath -Raw

    # Check debug_apply_test_powers_on_start
    $debugApplyTestPowersValue = Get-DebugSettingValue -content $content -settingName "debug_apply_test_powers_on_start"
    if ($null -ne $debugApplyTestPowersValue -and $debugApplyTestPowersValue -match '^true$') {
        Write-Host "  [ERROR] debug_apply_test_powers_on_start is enabled" -ForegroundColor Red
        $debugChecksPassed = $false
    }

    # Check debug_skip_starting_boon_selection
    $debugSkipBoonSelectionValue = Get-DebugSettingValue -content $content -settingName "debug_skip_starting_boon_selection"
    if ($null -ne $debugSkipBoonSelectionValue -and $debugSkipBoonSelectionValue -match '^true$') {
        Write-Host "  [ERROR] debug_skip_starting_boon_selection is enabled" -ForegroundColor Red
        $debugChecksPassed = $false
    }

    # Check debug_start_power_preset - should have DEBUG_POWER_PRESET_NONE
    $powerPresetValue = Get-DebugSettingValue -content $content -settingName "debug_start_power_preset"
    if ($null -ne $powerPresetValue) {
        $value = $powerPresetValue
        if ($value -notmatch '(^0$|DEBUG_POWER_PRESET_NONE)') {
            Write-Host "  [ERROR] debug_start_power_preset is not set to NONE (currently: $value)" -ForegroundColor Red
            $debugChecksPassed = $false
        }
    }

    # Check debug_start_encounter - should have DEBUG_ENCOUNTER_NONE
    $encounterValue = Get-DebugSettingValue -content $content -settingName "debug_start_encounter"
    if ($null -ne $encounterValue) {
        $value = $encounterValue
        if ($value -notmatch '(^0$|DEBUG_ENCOUNTER_NONE)') {
            Write-Host "  [ERROR] debug_start_encounter is not set to NONE (currently: $value)" -ForegroundColor Red
            $debugChecksPassed = $false
        }
    }

    # Check debug_mutator_override - should have DEBUG_MUTATOR_NONE
    $mutatorValue = Get-DebugSettingValue -content $content -settingName "debug_mutator_override"
    if ($null -ne $mutatorValue) {
        $value = $mutatorValue
        if ($value -notmatch '(^0$|DEBUG_MUTATOR_NONE)') {
            Write-Host "  [ERROR] debug_mutator_override is not set to NONE (currently: $value)" -ForegroundColor Red
            $debugChecksPassed = $false
        }
    }

    # Check debug_end_screen_preview - should have DEBUG_END_SCREEN_NONE
    $endScreenValue = Get-DebugSettingValue -content $content -settingName "debug_end_screen_preview"
    if ($null -ne $endScreenValue) {
        $value = $endScreenValue
        if ($value -notmatch '(^0$|DEBUG_END_SCREEN_NONE)') {
            Write-Host "  [ERROR] debug_end_screen_preview is not set to NONE (currently: $value)" -ForegroundColor Red
            $debugChecksPassed = $false
        }
    }
}

# Check menu_controller.gd for other debug settings
$menuControllerPath = "$scriptsPath/menu_controller.gd"
if (Test-Path $menuControllerPath) {
    $content = Get-Content -Path $menuControllerPath -Raw
    
    # Future debug checks can go here if needed
}

# Check staged scene files for serialized debug overrides.
$stagedSceneFiles = @()
try {
    $stagedSceneFiles = git diff --cached --name-only --diff-filter=ACM | Where-Object { $_ -like "*.tscn" }
} catch {
    Write-Host "[WARN] Could not get staged scene files" -ForegroundColor Yellow
}

if ($stagedSceneFiles.Count -gt 0) {
    $sceneDebugRules = @(
        @{ name = "debug_apply_test_powers_on_start"; allowed = "^false$"; description = "false" },
        @{ name = "debug_skip_starting_boon_selection"; allowed = "^false$"; description = "false" },
        @{ name = "debug_start_power_preset"; allowed = "(^0$|DEBUG_POWER_PRESET_NONE)"; description = "NONE/0" },
        @{ name = "debug_start_encounter"; allowed = "(^0$|DEBUG_ENCOUNTER_NONE)"; description = "NONE/0" },
        @{ name = "debug_mutator_override"; allowed = "(^0$|DEBUG_MUTATOR_NONE)"; description = "NONE/0" },
        @{ name = "debug_end_screen_preview"; allowed = "(^0$|DEBUG_END_SCREEN_NONE)"; description = "NONE/0" }
    )

    foreach ($sceneFile in $stagedSceneFiles) {
        $scenePath = "$projectRoot/$sceneFile"
        if (-not (Test-Path $scenePath)) { continue }

        $sceneContent = Get-Content -Path $scenePath -Raw
        foreach ($rule in $sceneDebugRules) {
            $value = Get-DebugSettingValue -content $sceneContent -settingName $rule.name
            if (-not (Test-DebugValueAllowed -value $value -allowedPattern $rule.allowed)) {
                Write-Host "  [ERROR] ${sceneFile}: $($rule.name) is not $($rule.description) (currently: $value)" -ForegroundColor Red
                $debugChecksPassed = $false
            }
        }
    }
}

if ($debugChecksPassed) {
    Write-Host "[OK] No debug options are enabled" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "[FAIL] Debug options are still enabled. Disable them before committing." -ForegroundColor Red
    exit 1
}

# ============================================================================
# All checks passed!
# ============================================================================
Write-Host ""
Write-Host "[SUCCESS] All pre-commit checks passed! Commit allowed." -ForegroundColor Green
exit 0

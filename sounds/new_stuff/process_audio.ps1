# process_audio.ps1
# Trim, normalize, generate variants, and convert SFX in sounds/new_stuff/
# Requires ffmpeg (Gyan build) - run after winget install Gyan.FFmpeg

$ErrorActionPreference = "Continue"
$IC = [System.Globalization.CultureInfo]::InvariantCulture

# Refresh PATH so ffmpeg is found in this session
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("PATH", "User")

$dir     = "C:\Mike\Godot Projects\godot-2026\sounds\new_stuff"
$origDir = Join-Path $dir "originals"

# === PHASE 2: Backup originals ===
New-Item -ItemType Directory -Path $origDir -Force | Out-Null
Get-ChildItem $dir -Filter "*.wav" | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $origDir $_.Name) -Force
}
Write-Host "[Phase 2] Originals backed up to: $origDir"

# === File config: name, trim target (0=no trim), fade dur, target peak dBFS ===
# peak: target peak level in dBFS. Category targets:
#   UI (quiet): -20 dBFS  |  Combat: -12 dBFS  |  Sustained: -10 dBFS  |  Boss: -7 dBFS
$files = @(
    @{ name="ui_button_click.wav";      trim=0.0;  fade=0.008; peak=-20 }
    @{ name="power_select_confirm.wav"; trim=0.18; fade=0.04;  peak=-18 }
    @{ name="player_hurt.wav";          trim=0.28; fade=0.06;  peak=-12 }
    @{ name="enemy_death.wav";          trim=0.35; fade=0.08;  peak=-12 }
    @{ name="door_open.wav";            trim=0.45; fade=0.08;  peak=-12 }
    @{ name="player_death.wav";         trim=0.60; fade=0.10;  peak=-10 }
    @{ name="low_hp_pulse.wav";         trim=1.00; fade=0.15;  peak=-10 }
    @{ name="rest.wav";                 trim=0.0;  fade=0.12;  peak=-10 }
    @{ name="boss_defeated.wav";        trim=0.0;  fade=0.12;  peak=-7  }
)

# === Helper: get audio duration reliably (avoids Object[] cast issues) ===
function Get-AudioDuration {
    param([string]$Path)
    $raw = & ffprobe -v error -show_entries format=duration -of csv=p=0 "$Path" 2>$null
    if ($raw -is [array]) { $raw = $raw[0] }
    $s = "$raw".Trim()
    if ($s -match '^[\d.]+$') { return [double]$s }
    return 0.0
}

# === Helper: peak-based normalization (works at any file duration) ===
# Uses volumedetect to measure peak, then applies a volume gain to hit TargetPeakDb.
function Invoke-PeakNormalize {
    param([string]$SrcFile, [string]$DstFile, [double]$TargetPeakDb)

    $statsOut = (& ffmpeg -i "$SrcFile" -af "volumedetect" -f null - 2>&1) -join "`n"

    $measPeak = $null
    if ($statsOut -match 'max_volume:\s+([-\d.]+)\s*dB') {
        $measPeak = [double]$matches[1]
    }

    if ($null -eq $measPeak -or $measPeak -le -100.0) {
        Copy-Item "$SrcFile" "$DstFile" -Force
        Write-Host "  Could not measure peak; copied as-is"
        return
    }

    $gainDb  = $TargetPeakDb - $measPeak
    $gainStr = $gainDb.ToString("F2", $IC)

    & ffmpeg -y -i "$SrcFile" -af "volume=${gainStr}dB" -ar 44100 "$DstFile" 2>$null

    if (Test-Path "$DstFile") {
        Write-Host ("  Peak: {0:F1} dBFS -> {1:F1} dBFS  (gain {2} dB)" -f $measPeak, $TargetPeakDb, $gainStr)
    } else {
        Write-Warning "  volume filter failed; falling back to copy"
        Copy-Item "$SrcFile" "$DstFile" -Force
    }
}

# === Helper: pitch variant (semitone shift, pitch-only, no tempo change) ===
function New-PitchVariant {
    param([string]$SrcFile, [string]$DstFile, [double]$Semitones, [double]$TargetPeakDb)

    $ratio    = [Math]::Pow(2.0, $Semitones / 12.0)
    $newSR    = [int][Math]::Round(44100.0 * $ratio)
    $tempo    = (1.0 / $ratio).ToString("F6", $IC)
    $tmpPitch = "$DstFile.pitchtmp.wav"

    & ffmpeg -y -i "$SrcFile" -af "asetrate=${newSR},aresample=44100,atempo=${tempo}" "$tmpPitch" 2>$null
    Invoke-PeakNormalize -SrcFile "$tmpPitch" -DstFile "$DstFile" -TargetPeakDb $TargetPeakDb
    Remove-Item -Force "$tmpPitch" -ErrorAction SilentlyContinue
}

# === PHASES 3 + 4: Trim + Fade, then Peak Normalization ===
foreach ($f in $files) {
    $src     = Join-Path $dir $f.name
    $tmpTrim = Join-Path $dir "tmp_trim_$($f.name)"
    $tmpNorm = Join-Path $dir "tmp_norm_$($f.name)"

    Write-Host ("`n[Phase 3+4] {0}" -f $f.name)

    $actualDur  = Get-AudioDuration -Path $src
    $trimEnd    = [double]$f.trim
    $fadeDur    = [double]$f.fade
    $fadeDurStr = $fadeDur.ToString("F4", $IC)

    if ($trimEnd -gt 0.0 -and $actualDur -gt $trimEnd) {
        $fadeStart    = [Math]::Max(0.0, $trimEnd - $fadeDur)
        $fadeStartStr = $fadeStart.ToString("F4", $IC)
        $trimEndStr   = $trimEnd.ToString("F4", $IC)
        $filter       = "atrim=end=${trimEndStr},afade=t=out:st=${fadeStartStr}:d=${fadeDurStr}"
        & ffmpeg -y -i "$src" -af $filter -ar 44100 "$tmpTrim" 2>$null
        Write-Host ("  Trimmed: {0:F3}s -> {1:F3}s  (fade {2:F3}s)" -f $actualDur, $trimEnd, $fadeDur)
    } else {
        $fadeStart    = [Math]::Max(0.0, $actualDur - $fadeDur)
        $fadeStartStr = $fadeStart.ToString("F4", $IC)
        $filter       = "afade=t=out:st=${fadeStartStr}:d=${fadeDurStr}"
        & ffmpeg -y -i "$src" -af $filter -ar 44100 "$tmpTrim" 2>$null
        Write-Host ("  No trim ({0:F3}s). Fade from {1:F3}s" -f $actualDur, $fadeStart)
    }

    Invoke-PeakNormalize -SrcFile $tmpTrim -DstFile $tmpNorm -TargetPeakDb ([double]$f.peak)

    Move-Item -Force "$tmpNorm" "$src"
    Remove-Item -Force "$tmpTrim" -ErrorAction SilentlyContinue
    Write-Host ("  Saved: {0}" -f $f.name)
}

# === PHASE 5: Pitch variants for player_hurt and enemy_death ===
Write-Host "`n[Phase 5] Generating pitch variants"

$hurtSrc = Join-Path $dir "player_hurt.wav"
Copy-Item $hurtSrc (Join-Path $dir "player_hurt_000.wav") -Force
Write-Host "  player_hurt_000 (base copy)"
New-PitchVariant -SrcFile $hurtSrc -DstFile (Join-Path $dir "player_hurt_001.wav") -Semitones  1.5 -TargetPeakDb -12
Write-Host "  player_hurt_001 (+1.5 semitones)"
New-PitchVariant -SrcFile $hurtSrc -DstFile (Join-Path $dir "player_hurt_002.wav") -Semitones -1.0 -TargetPeakDb -12
Write-Host "  player_hurt_002 (-1.0 semitone)"

$deathSrc = Join-Path $dir "enemy_death.wav"
Copy-Item $deathSrc (Join-Path $dir "enemy_death_000.wav") -Force
Write-Host "  enemy_death_000 (base copy)"
New-PitchVariant -SrcFile $deathSrc -DstFile (Join-Path $dir "enemy_death_001.wav") -Semitones  2.0 -TargetPeakDb -12
Write-Host "  enemy_death_001 (+2.0 semitones)"
New-PitchVariant -SrcFile $deathSrc -DstFile (Join-Path $dir "enemy_death_002.wav") -Semitones -1.5 -TargetPeakDb -12
Write-Host "  enemy_death_002 (-1.5 semitones)"

# === PHASE 6: Convert all WAVs to OGG Vorbis (Godot-preferred format) ===
Write-Host "`n[Phase 6] Converting WAVs to OGG"
Get-ChildItem $dir -Filter "*.wav" | Where-Object { $_.DirectoryName -eq $dir } | Sort-Object Name | ForEach-Object {
    $oggPath = $_.FullName -replace '\.wav$', '.ogg'
    & ffmpeg -y -i $_.FullName -c:a libvorbis -q:a 6 $oggPath 2>$null
    Write-Host ("  {0} -> {1}" -f $_.Name, [IO.Path]::GetFileName($oggPath))
}

# === PHASE 7: Verify output OGG durations ===
Write-Host "`n[Phase 7] Output verification"
Write-Host ("" + "-" * 56)
Write-Host ("{0,-45} {1}" -f "File", "Duration")
Write-Host ("" + "-" * 56)
Get-ChildItem $dir -Filter "*.ogg" | Where-Object { $_.DirectoryName -eq $dir } | Sort-Object Name | ForEach-Object {
    $dur = Get-AudioDuration -Path $_.FullName
    Write-Host ("{0,-45} {1:F3}s" -f $_.Name, $dur)
}
Write-Host ("-" * 56)
Write-Host "`n[Done] All phases complete."

# Pre-Commit Hook System - Quick Start Guide

## What It Does

This pre-commit hook system automatically blocks commits if:

1. **Debug options are enabled** in `scripts/debug_settings.gd`:
   `enabled` must be `false`
   `apply_test_powers_on_start` must be `false`
   `skip_starting_boon_selection` must be `false`
   `start_power_preset` must be `DEBUG_ENUMS.PowerPreset.NONE`
   `start_encounter` must be `DEBUG_ENUMS.Encounter.NONE`
   `mutator_override` must be `DEBUG_ENUMS.MutatorOverride.NONE`
   `end_screen_preview` must be `DEBUG_ENUMS.EndScreenPreview.NONE`
2. **Syntax issues** in staged GDScript files (quick check)

## Setup (One-Time Only)

Run this in the project root:

```powershell
.\.git\hooks\setup-hooks.ps1
```

This will:

- Make the hooks executable
- Configure Git to use the hooks
- Run a validation test

## How It Works

When you run `git commit`, the hook automatically runs before allowing the commit:

```
C:\Mike\Godot Projects\godot-2026> git commit -m "Fix gameplay balance"
[PRE-COMMIT] Starting validation...

Checking for syntax issues...
[OK] Staged .gd files checked (3 files)

Checking for enabled debug options...
[OK] No debug options are enabled

[SUCCESS] All pre-commit checks passed! Commit allowed.
[main abc1234] Fix gameplay balance
 5 files changed, 123 insertions(+)
```

## Bypassing the Hook (Not Recommended)

If you absolutely need to skip the validation:

```powershell
git commit --no-verify -m "Emergency commit"
```

## Files in This System

- `.git/hooks/pre-commit` - Shell wrapper that calls PowerShell
- `.git/hooks/pre-commit.ps1` - Main validation script
- `.git/hooks/setup-hooks.ps1` - Setup and initialization script
- `.git/hooks/HOOK_SETUP.md` - Detailed setup documentation

## Team Setup

If you're working with a team, share these files in your repository so everyone has the same validation rules.

## Customizing the Hook

To add more debug options to check:

1. Edit `.git/hooks/pre-commit.ps1`
2. Add your validation logic in the "Checking for enabled debug options" section
3. Test it: `.\.git\hooks\pre-commit.ps1`
4. Commit your changes

## Testing

To manually run the validation:

```powershell
.\.git\hooks\pre-commit.ps1
```

Expected output when all checks pass:

```
[PRE-COMMIT] Starting validation...
Checking for syntax issues...
[OK] Staged .gd files checked (0 files)
Checking for enabled debug options...
[OK] No debug options are enabled
[SUCCESS] All pre-commit checks passed! Commit allowed.
```

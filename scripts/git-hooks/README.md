# Git Pre-Commit Hooks

This directory contains the pre-commit hook scripts for validating project state before commits.

## Installation

Run this once to install the hooks:

```powershell
.\install-hooks.ps1
```

## Files

- **pre-commit.ps1** - Main validation logic (checks for debug options and syntax errors)
- **pre-commit** - Shell wrapper that calls the PowerShell script
- **install-hooks.ps1** - Setup script that copies hooks to `.git/hooks/` and configures Git

## What Gets Validated

The hooks will block commits if any of these are true:

1. **Debug options enabled in `scripts/debug_settings.gd` or scene debug settings:**
   - `enabled = true`
   - `apply_test_powers_on_start = true`
   - `skip_starting_boon_selection = true`
   - `start_power_preset` is not NONE (`DEBUG_ENUMS.PowerPreset.NONE`, `DEBUG_POWER_PRESET_NONE`, or `0`)
   - `start_encounter` is not NONE (`DEBUG_ENUMS.Encounter.NONE`, `DEBUG_ENCOUNTER_NONE`, or `0`)
   - `mutator_override` is not `DEBUG_MUTATOR_NONE`
   - `end_screen_preview` is not `DEBUG_END_SCREEN_NONE`

2. **Syntax errors in staged GDScript files**

## Testing

Run the validation manually:

```powershell
.\pre-commit.ps1
```

## Customization

To add new debug checks:

1. Edit `pre-commit.ps1`
2. Add logic in the "Checking for enabled debug options" section
3. Test with `.\pre-commit.ps1`
4. Commit your changes

## Bypassing

If needed (not recommended):

```powershell
git commit --no-verify
```

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

1. **Debug options enabled in `scripts/world_generator.gd`:**
   - `debug_apply_test_powers_on_start = true`
   - `debug_skip_starting_boon_selection = true`
   - `debug_start_power_preset` is not `DEBUG_POWER_PRESET_NONE`
   - `debug_start_encounter` is not `ENCOUNTER_CONTRACTS.DEBUG_ENCOUNTER_NONE`
   - `debug_mutator_override` is not `DEBUG_MUTATOR_NONE`
   - `debug_end_screen_preview` is not `DEBUG_END_SCREEN_NONE`

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

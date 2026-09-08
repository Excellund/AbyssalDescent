# Git Pre-Commit Hooks

This directory contains the pre-commit hook scripts for validating project state before commits.

## Installation

Run this once to install the hooks:

```powershell
.\install-hooks.ps1
```

## Files

- **pre-commit.ps1** - Main validation logic (debug checks, syntax checks, and isolated gameplay regressions)
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

3. **Isolated Godot validation and gameplay regressions**
   - Runs `.github/scripts/run_gameplay_regressions.ps1` on every commit.
   - Imports the project and compiles every GDScript, then checks forbidden world property access and multiplayer configuration synchronization.
   - Runs the reward-input, power-reward, and Oath-tracking regression suites.
   - Blocks commit if the runner fails, including script errors or failed assertions.

Godot checks run in a temporary project copy with separate user data. Autoload
fixtures retain production methods for compilation while disabling startup and
background services; external endpoints are cleared in the temporary copy. The
checks do not boot the working project, modify its import cache, or load normal
player saves. The runner prints the retained temporary log directory for review.

## Godot Executable Resolution

The pre-commit hook resolves Godot in this order:

1. `GODOT_EXE` environment variable (absolute path)
2. Workspace setting `godot.executablePath` in `.vscode/settings.json`
3. `godot` on PATH
4. `godot4` on PATH

If none are available, commits are blocked until one is configured.

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

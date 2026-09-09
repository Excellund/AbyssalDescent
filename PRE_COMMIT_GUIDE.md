# Pre-commit validation

The tracked hook checks debug defaults and staged scene overrides, performs quick
GDScript checks, and runs the full isolated gameplay regression suite. A failed
Godot import, compile, contract check, or gameplay assertion blocks the commit.

## Install once

From the repository root:

```powershell
& ./scripts/git-hooks/install-hooks.ps1
```

The installer copies the hooks into `.git/hooks`, sets `core.hooksPath` to that
directory, and runs validation. The installed shell wrapper calls the tracked
`scripts/git-hooks/pre-commit.ps1`, so edit that tracked file when changing rules.
See [the hook reference](scripts/git-hooks/README.md) for executable resolution
and installation details.

## Check a change while developing

For import, compilation and world/network contract checks without gameplay
fixtures, run `& ./.github/scripts/run_gameplay_regressions.ps1 -CompileOnly`.
The VS Code **Validate GDScript Compile** task uses this isolated path;
**Validate Gameplay Regressions** runs the full suite. Neither task runs against
the player's profile. `-CompileOnly` and `-TestScripts` are mutually exclusive.

Select relevant fixtures for a shorter iteration:

```powershell
& ./.github/scripts/run_gameplay_regressions.ps1 -TestScripts @(
    'res://scripts/tests/test_combat_interactions.gd',
    'res://scripts/tests/test_shared_power_wording.gd'
)
```

Every selection still imports the project, compiles all scripts, and checks
world-property access and multiplayer configuration synchronization. Choose
existing fixtures under `res://scripts/tests/` that cover the changed behavior.

## Check a checkpoint

Run the full suite with no fixture selection:

```powershell
& ./.github/scripts/run_gameplay_regressions.ps1
```

The pre-commit hook runs this full suite automatically. When committing
immediately, use that run as the full verification instead of repeating it
manually. To exercise its debug checks as well outside a commit, invoke the
tracked hook from the repository root:

```powershell
& ./scripts/git-hooks/pre-commit.ps1
```

The runner uses a disposable project copy, isolated user data, suppressed
autoload startup, and cleared external endpoints. It retains and prints logs.
Do not run unattended Godot validation against the working project or the
player's normal profile.

Focused ENet tests, GPU captures, playtest workflow checks, and exported executable
smoke checks are separate helpers in `.github/scripts`; run the ones relevant to
the change. A passing headless suite does not replace visual or manual playtesting.

At an agreed checkpoint, follow [AGENTS.md](AGENTS.md): finish relevant checks,
commit and push the completed work, and export the normal desktop playtest with
`& ./.github/scripts/export_playtest.ps1`. Both normal and debug modes use the same
desktop filename; use the debug mode only for requested focused testing.

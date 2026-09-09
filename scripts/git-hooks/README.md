# Git pre-commit hooks

## Installation

From the repository root:

```powershell
& ./scripts/git-hooks/install-hooks.ps1
```

The installer copies `pre-commit` and `pre-commit.ps1` into `.git/hooks`, configures
`core.hooksPath=.git/hooks`, and runs the copied PowerShell validator. Installation
therefore requires a configured Godot executable and runs the full regression
suite. This installer assumes a regular checkout with a `.git` directory.

The installed `pre-commit` shell wrapper executes the **tracked**
`scripts/git-hooks/pre-commit.ps1`. Maintain that tracked source; an older copied
`.git/hooks/pre-commit.ps1` is not used by the wrapper during commits.

## Checks

- Debug settings and staged scene overrides must leave normal gameplay enabled:
  no granted test powers, skipped starting selection, encounter or bearing
  overrides, mutator override, or end-screen preview.
- Staged GDScript files receive quick syntax checks. Registry presence checks
  provide additional diagnostics.
- Every commit runs
  [the isolated regression runner](../../.github/scripts/run_gameplay_regressions.ps1)
  without a fixture selection: resource import, compilation of all GDScript,
  world-property and multiplayer configuration contracts, and the full gameplay
  suite registered in that runner. Failed checks block the commit.

The runner copies the project into system temporary storage and isolates user
data. Autoload fixtures retain production methods for compilation while
suppressing startup and background services; external endpoints are cleared.
It does not boot the working project or load normal player saves, and it prints
the retained log directory.

## Godot configuration

The hook resolves the executable in this order:

1. `GODOT_EXE` environment variable.
2. `godot.executablePath` in `.vscode/settings.json`.
3. `godot` on PATH.
4. `godot4` on PATH.

If no executable is available, the commit is blocked. The standalone regression
runner accepts `-GodotPath`, otherwise reads the workspace setting and then
`GODOT_EXE`; it does not search PATH. Use the project's Godot 4.6 engine.

## Development and checkpoint checks

Run the hook manually from the repository root:

```powershell
& ./scripts/git-hooks/pre-commit.ps1
```

For shorter iterations, call the isolated runner with `-TestScripts` and relevant
`res://scripts/tests/*.gd` fixtures. The selection retains import, full compile,
and world/network contract checks. Omit `-TestScripts` for the full checkpoint
suite; the hook always does so.

ENet multiplayer fixtures, GPU captures, playtest workflow tests, and exported
executable smoke tests are separate checks chosen for the changed behavior.
Use their scoped helpers and disposable profiles. See
[the quick-start guide](../../PRE_COMMIT_GUIDE.md) and
[project checkpoint instructions](../../AGENTS.md).

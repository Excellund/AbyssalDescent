# Pull request validation

[Gameplay Regressions](../.github/workflows/gameplay-regressions.yml) runs the existing [isolated regression runner](../.github/scripts/run_gameplay_regressions.ps1) on GitHub-hosted Windows 2025 with Windows PowerShell and Godot 4.6.2. It covers resource import, all-script compilation, world/network contract checks, and the runner's complete registered gameplay suite.

Initial hosted proof: [7b0d470 branch run](https://github.com/Excellund/AbyssalDescent/actions/runs/34408344808), September 9, 2026, passed in 4 minutes 55 seconds. Its downloaded artifact contains 151 log files, including 71 gameplay fixture console logs, with no copied profiles/assets. Failure exit propagation and log selection were separately checked with a local mocked runner; no intentionally failing hosted gameplay run was performed.

It runs for pull requests targeting `main`, pushes to `main` or `codex/**`, and manual dispatch. A `codex/**` branch with an open PR gets two checks: the push checks the branch commit; the PR checks GitHub's proposed merge commit. New runs cancel older runs for the same caller, event and PR or branch. Manual dispatch becomes available when the workflow is present on the default branch.

The Windows release workflow also calls this reusable workflow from the same tagged commit. Its export/publish job depends on successful gameplay validation, with read-only permission for validation. Caller-aware concurrency keeps this release check independent of ordinary branch checks. Tags pointing to older commits still use their older workflow definitions.

## Isolation and retained evidence

The workflow downloads the standard Windows editor from the [official Godot release](https://github.com/godotengine/godot-builds/releases/tag/4.6.2-stable), verifies its pinned SHA256 and version, then passes its executable through `-GodotPath`. This explicit argument overrides a developer's local VS Code engine setting. No export templates are required.

The runner creates disposable project copies and isolated user data, suppresses background autoload startup, and clears external service endpoints in the copy. The workflow requests only repository read permission, supplies no project secrets, and disables persisted checkout credentials. It does not export or publish a build.

Open the failed step first; the runner identifies the failing fixture. The `gameplay-logs-<run>-<attempt>` artifact retains the workflow transcript, each fixture's stdout/stderr/console/engine logs, and inert process-test logs for seven days. Its paths include only logs, excluding copied assets and save directories. Failures before the regression step starts may have only GitHub's step output. Cancelled jobs or exhausted job time can prevent artifact upload.

The runner allows 300 seconds for import and 180 seconds for each fixture. A timeout attempts to stop the retained process and its descendants by their owned PID, preserves output and reports any cleanup failure. Override those limits with `-ImportTimeoutSeconds` and `-FixtureTimeoutSeconds` when investigating a measured need. The regression step also has a 20-minute limit and the job a 30-minute limit. A timeout is a failure to investigate, not a passing result.

## Reproduce and maintain

From the repository root, use the same isolated runner with a local Godot 4.6.2 executable:

```powershell
.github/scripts/run_gameplay_regressions.ps1 -GodotPath 'C:/path/to/Godot_v4.6.2-stable_win64_console.exe'
```

For a focused rerun, add `-TestScripts 'res://scripts/tests/test_run_result_identity.gd'`; compilation and the world/network contract checks still run. The full CI invocation supplies no selection. See [the pre-commit guide](../PRE_COMMIT_GUIDE.md) for local validation tasks and checkpoint checks.

CI first runs `.github/scripts/test_validation_process.ps1`. Its temporary inert executable exercises success, native errors, zero-exit script errors, quoted arguments, wrapper/child timeouts and environment restoration without loading Godot or player data. The same checks can run locally under Windows PowerShell 5.1 or PowerShell 7. Expected negative cases deliberately retain error text in their logs; the fixture's final result determines whether those checks passed.

When changing the workflow, run `actionlint .github/workflows/gameplay-regressions.yml` and parse each embedded script with Windows PowerShell's parser. Verify action commit pins against official release tags. Update the Godot version, official archive checksum, and version assertion together. Check both a passing hosted run and failure-log retention before relying on a changed gate.

This check covers the default headless suite. GPU captures, real two-process network fixtures, normal playtest export, and human playtesting remain separate checks. A green CI run is not a release approval. Making the check mandatory before merge requires a separate repository branch-protection/ruleset change; the workflow does not configure that policy.

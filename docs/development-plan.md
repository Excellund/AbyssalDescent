# Development plan

Updated September 9, 2026. This is the current entry point for priorities and the development pipeline. Feature documents retain their detailed rules and historical verification records; a file named `next-content-update.md` does not mean that feature is still unimplemented.

**Current checkpoint:** the three approved sense-of-descent updates are implemented on `codex/descent-identity` at gameplay commit `7b0d470`: act environments and saved biome identity; entered-room variety and clear route payoffs; music, boss/act milestones and results. The full local suite, staged ENet and GPU review passed, and a normal desktop playtest has been delivered. The [September 9–10 implementation log](overnight-descent-20260910.md) records the exact build, source, fixes and evidence. The authorized tooling increment adds isolated editor tasks and [branch/PR regression CI](pull-request-validation.md); its [first hosted run](https://github.com/Excellund/AbyssalDescent/actions/runs/34408344808) passed and retained logs were inspected. Next is normal playtest feedback on this checkpoint.

## Current position

This plan was prepared from `main` at `4ee9681` (`Refine reward readability, character passives and Keeper protection`) with a clean working tree. The current gameplay checkpoint is `7b0d470` on the descent branch; the implementation log identifies and verifies its delivered desktop build.

- Connected combat rules, shared keywords, conditional damage, reward-time build inspection and save/network compatibility are implemented. See [connected builds](connected-builds-implementation.md).
- The latest source includes revised reward explanations/layouts, character passive presentation and behavior, and Keeper protection that holds linked allies at 1 HP. See the [combat roster](combat-power-roster.md) and [Keeper/Breach](next-content-update.md).
- Motion powers, Returning Crescent, Undertow/cover formations and Apex Breakwater are already implemented. Their next step is feedback, not another implementation pass. See [content updates](content-updates.md).
- Automated checks have substantial recorded coverage. Ordinary progression, enjoyment, balance and the complete online lobby/join experience still need human acceptance. Older build hashes and passing test counts describe their recorded checkpoints, not every later source revision.

## Now: validate the current game through ordinary progression

Recommended next milestone: make the connected-build update understandable and satisfying in normal runs. Keep the current roster and accepted visual style as the baseline while collecting feedback.

| Focus | What to observe | Decision it informs |
|---|---|---|
| Build choices and character identity | Can the player understand the character passive and choose useful rewards from the card/build view? Do Mark, Slow, Fields and automatic damage produce recognizable benefits as powers are earned? | Fix unclear explanations, weak feedback or an actual mechanic mismatch. |
| Keeper and encounter decisions | Does protection make killing, pushing or separating the Keeper useful? Are the protected ally's survival and the opening after a broken link understandable? | Refine the tactical decision without merely extending room duration. |
| Movement and arena pressure | Are Crescent return paths, Orbit exits, Undertow escape lanes and Breakwater's charge/recovery readable with ordinarily earned powers? | Prioritize specific control, warning or pacing problems. |
| Complete run and co-op flow | Can players start/join, select rewards, move between rooms, pause, retry and resume as applicable? Do crowded fights remain readable? | Address lifecycle, online-flow and performance problems exposed beyond staged fixtures. |

Use a small set of varied normal sessions, spreading the questions across runs rather than requiring a specific random reward combination. Record the build ID, character, Bearing/depth, relevant powers, what happened and what was expected. A short observation or clip is enough; these sessions are qualitative feedback, not a statistical balance sample.

Use [local telemetry analysis](../playtester_telemetry/README.md) with the exact build and UTC date interval to support those observations. Report missing data and sample limitations. Debug loadouts can isolate a reported interaction when requested; they cannot establish normal-progression balance.

**Exit condition:** observations are triaged, blocking issues are reproduced/fixed, and the user accepts the resulting normal playtest as a useful baseline. Passing automation alone does not close this milestone.

## Next: one focused improvement at a time

1. **Resolve the strongest playtest finding.** State the player-visible problem and acceptance condition, implement the smallest complete fix, and deliver it through the pipeline below. Prioritize broken behavior and unclear feedback before speculative numerical tuning.
2. **Use branch and pull-request validation.** The new [workflow](../.github/workflows/gameplay-regressions.yml) runs the existing full isolated suite on Windows with the verified Godot 4.6.2 archive and retains logs. It checks `main`, `codex/**` pushes and PRs targeting `main`. Verify a real hosted run before relying on it; mandatory branch protection remains a separate administrative change. GPU review and real online play remain separate checks.
3. **Select one content slice after feedback.** Choose a concrete gap in encounter decisions or build variety. Destructible-cover formations are an existing candidate, not approved production scope. Define the behavior, payoff and acceptance playtest before implementing more powers, encounters or progression.

Performance work follows a reproducible slowdown and a representative capture. Refactoring follows a concrete maintenance problem in the area being changed. Neither needs a separate broad rewrite to continue development.

## Development pipeline

**Observation -> bounded change -> focused verification -> agreed checkpoint -> normal build -> human playtest -> next observation.**

| Stage | Existing entry point / practice | Completion evidence |
|---|---|---|
| Define | This plan plus the relevant feature document; [combat wording](combat-wording.md) and [roster](combat-power-roster.md) for combat changes | One player-visible outcome, preserved rules and an acceptance condition. |
| Implement | A cohesive change; `codex/` branches for new branch work; independent subtasks only where ownership is clear | Runtime, player-facing text and relevant documentation agree. |
| Check behavior | [run_gameplay_regressions.ps1](../.github/scripts/run_gameplay_regressions.ps1); use `-TestScripts` while iterating | Relevant fixtures pass in a disposable project with isolated user data. Scoped runs still compile all scripts and check world/network contracts. |
| Check branch/PR | [Gameplay Regressions](../.github/workflows/gameplay-regressions.yml) on GitHub-hosted Windows | Full headless suite passes for the pushed branch or proposed PR merge; failure logs are retained. See [workflow details](pull-request-validation.md). |
| Check presentation/networking | Applicable `render_*.ps1` and `test_*_enet.ps1` helpers under [.github/scripts](../.github/scripts) | Inspect actual rendered frames for visual changes; run real host/joiner fixtures for changed network behavior. Choose checks by the change. |
| Checkpoint | Full regression runner with no `-TestScripts`; installed pre-commit wrapper invokes [tracked validation](../scripts/git-hooks/pre-commit.ps1) | Full required checks pass for the completed source. On an agreed checkpoint or commit request, commit and push the task changes while preserving unrelated work. |
| Deliver | [export_playtest.ps1](../.github/scripts/export_playtest.ps1), then [test_playtest_executable.ps1](../.github/scripts/test_playtest_executable.ps1) | Production package and normal-mode checks pass; delivered file hash matches; record source commit, internal build ID and evidence. |
| Accept | Human playtest and exact-build local observations | Confirm the intended improvement, or record the next concrete issue. |

Run focused checks during iteration and the required full suite at checkpoints. The commit hook runs the full suite; avoid a redundant manual full run immediately before it unless a failure or changed source warrants one. Freeze the candidate during final verification, and recheck affected evidence after changes.

All unattended Godot gameplay uses disposable projects and isolated profiles through the existing helpers. Normal delivery is `.github/scripts/export_playtest.ps1` without `-DebugRun`: regular Menu, no debug grants, normal progression. It replaces the one `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe`, with a unique internal `dev-*` ID. Verify the destination in the invoking user's environment. Debug exports use that same desktop filename and separate debug saves when requested. Development runs remain excluded from remote telemetry and leaderboards.

The exporter verifies its staged package and final SHA256 itself. The separate executable helper adds package configuration checks: normal mode mounts the EXE's embedded package in the development engine without launching the EXE or exercising the full Menu-to-run lifecycle; debug mode also boots the exported EXE in isolation. Do not report that smoke check as human playtesting or complete online validation.

## Public release and pipeline gaps

The [Windows release workflow](../.github/workflows/release-windows.yml) runs when a `v*` tag is pushed, exports Windows assets and publishes a GitHub release/update manifest. It still has no gameplay-regression step. The separate [Gameplay Regressions workflow](../.github/workflows/gameplay-regressions.yml), added on the descent branch, checks branches and PRs and publishes no game artifacts. Another workflow cleans up multiplayer rooms.

Use local checkpoint, hosted CI and desktop playtest evidence together when assessing release readiness. Neither a green CI check nor a development build authorizes a public release. Public release/tagging is a separate requested checkpoint; this plan does not schedule or authorize a release.

## Keeping the plan useful

Keep one active gameplay milestone and at most one independent tooling increment. After each accepted checkpoint, update the current baseline, close the completed outcome and select the next priority. Put detailed mechanics and test evidence in their existing feature documents rather than duplicating long logs here.

Checkpoint record: source commit/branch; player-visible changes; focused/full/network/visual evidence as applicable; normal/debug mode; internal build ID; delivered SHA256; open human-feedback questions. Distinguish completed implementation, automated verification and human acceptance.

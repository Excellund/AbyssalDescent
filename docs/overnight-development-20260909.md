# Overnight development — September 9, 2026

The user authorized substantial autonomous development on a separate branch until about 06:00 Europe/Copenhagen, prioritizing working, reliable, worthwhile improvements. The deadline is **2026-09-09 04:00 UTC**. Stop adding scope by 05:15 local and reserve time for final verification and delivery.

Branch: `codex/overnight-buildcraft-20260909`, based on verified checkpoint `5ee445e`. Keep `main` at that checkpoint. Preserve the pre-existing, uncommitted `scenes/Main.tscn` DebugSettings change.

The thread continuation `overnight-abyssaldescent-development` expires at the deadline. Pause it when the overnight delivery is complete. Read this log and the current conversation before continuing; do not restart completed work.

## Intended increments

1. **Reliable attack and movement handoffs.** Fix a held attack queued through dash failing to arm Blast Drive, including the handoff into Orbit. Preserve deliberate input, immediate taps and cancellation at transitions.
2. **Accurate reward information.** Compare existing reward cards, level previews and build descriptions with actual runtime behavior. Correct concrete drift without retuning powers or redesigning the UI.
3. **Returning Crescent.** An accepted attack sends an available blade outward; moving changes its return path. L1 has one active blade, L2 allows two, and L3 adds one outbound ricochet from cover. Each blade hits an enemy once per leg, uses secondary damage, spends a fixed travel budget and expires after two seconds at most. Return contact with cover dissolves the blade. Base damage is 45% of Damage per leg, with 220-pixel outward travel; damage and reach gain 15% of base per level and the existing one-time Prismatic boost. No extra input, progression currency or combat prompt.
4. **Combat presentation and reliability.** Improve unclear impact/state feedback and test the relevant lifecycle, save/resume and host/joiner behavior. Sovereign's Double keeps its existing proc contract unless a separately justified change is recorded.

## Active ownership

- `review_combat_lifecycle`: queued input, Crescent hooks, Ruinous ENet and independent Crescent review completed. Reviewing saved-run/transition safety for the next increment.
- `review_combat_readability`: descriptions/registration/reward sizing completed. Preparing Lacuna warning regressions; production edits wait until the first feature commit.
- `review_hit_context`: Crescent implementation and verification completed. Reviewing existing kill-driven powers and Oath accounting for concrete defects.
- Root: Ruinous presentation and its GPU fixture, full runner/shared GPU helper, work log, independent review, Git and delivery.

Coordinate overlapping files before editing. Agents do not commit independently.

## Verification and delivery rules

- Run Godot only in disposable copies with isolated saves/autoload startup. Never run unattended tests against the real player profile.
- Use focused behavior regressions and negative controls for confirmed bugs, actual GPU frames for visuals, and actual two-process ENet checks for changed network behavior.
- Run the full regression suite at checkpoints. Keep source changes and tests reviewable in cohesive commits.
- Push the development branch without merging into `main` or creating release tags.
- Deliver a verified **normal** build, with regular menu/progression and no debug grants, to the same `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe`. Use a unique internal `dev-*` identifier. Do not create new desktop filenames.
- Development builds retain local history and remain excluded from remote telemetry/leaderboards. Verify the exported package and final desktop hash.

## Completed work and evidence

- 01:25 local: created the branch from `5ee445e`; the only pre-existing working change is `scenes/Main.tscn`.
- 01:27 local: configured the time-limited thread continuation and started independent control, description and content assessments.
- Queued input: 127 focused checks pass (49 fail on the original implementation), plus 197 existing motion checks, 106 boss-combination checks and reward-input regressions. Still-held attacks charge only after the buffered strike succeeds, including into Orbit; released taps, cancellation and dash immunity retain their intended behavior.
- Ruinous presentation: attached directional launch cue, inward compression brackets, fixed-radius fractured burst and one bounded impact sound. Damage, launch speed, delays and cooldowns are unchanged. The host sends reliable room-scoped launch/finish/burst cues; a launch-end signal removes attached effects on cancel. Superseded generic enemy-ring transport was removed.
- Ruinous focused validation: 26 feedback checks, 106 existing boss-combination checks, 29 launch-authority checks and 17 foundation checks passed in `abyssal-validation-62684469b6f74ceabf0b30691353c7d4`. Four real GPU frames passed and were visually inspected in `abyssal-gameplay-render-41bdce7bcdbd47eca2a349d0ba32b07c/ruinous_frames`. Independent review found no production defects; 52 live ENet checks pass, including Boss2 compression, authenticated ownership, exact geometry, stale-room filtering and repeated input cancellation (`abyssal-enet-6cbf17c8120f4702a240f72ad3d19cd2`).
- The isolated regression runner now accepts optional `-TestScripts` selections while retaining compilation and world/network validation. Omitting that option, including in the Git hook, runs the complete suite. A shared `render_gameplay_fixture.ps1` holds the existing isolated GPU workflow; effect-specific commands are small wrappers.
- Descriptions and reward sizing: 262 checks pass against actual characters, upgrades, runtime damage, saved state and viewport shrink/grow. Corrected motion numbers, clamped boon totals, the Blood Pact double plus, Eclipse marked-hit count, repeatable Null Corridor deflections and stale panel/label widths. Four actual GPU frames pass and were inspected by the implementing agent in `abyssal-gameplay-render-d93eec3d6f184f08acb714884031c70f/description_frames`; 172 existing motion-registry checks also pass.
- Returning Crescent: 85 runtime/registry checks and 554 complete reward-pool checks pass. Actual two-process ENet passes 22 checks; the default boss-combination ENet passes 52 after adding an optional fixture selector to the launcher. Four GPU frames passed and were inspected by both implementer and root (`abyssal-gameplay-render-47f9b561ed164cd08e21da77dc5e9f0c/crescent_frames`). Remote blades retain bounded catch tombstones so late corrections cannot make caught blades reappear; disconnected peers tear down cleanly. Independent review found no remaining defects, including thin cover, repeated outbound crossings and long physics frames. With 80 enemies and two blades, the isolated debug benchmark measured 0.84 ms mean / 1.17 ms p95 per tick; no optimization was warranted by that sample.
- The next selected increment corrects Lacuna's lingering/expired overlays and Echo Cross warnings that are narrower than their real damage capsules. Keep damage, movement and timings unchanged. Charge previews also understate reach, but exact reach depends on mid-charge enrage and the final physics step; defer that separate design choice rather than silently changing movement semantics.

## Remaining delivery record

First full regression suite passed with 198 compiled scripts in `abyssal-validation-bed1a26ae85943ca9bba35651f3bce07`. Independent review then caught the missing named debug-grant entry for Returning Crescent; it is corrected and its focused suite now has 86 expectations. The mandatory commit hook reruns the complete suite on that final change.

The next reliability increment also fixes a confirmed co-op defeat path that directly deletes an unrelated suspended solo checkpoint. A disposable-profile reproduction called the production death handler with two actual dead players and observed the saved run disappear. Use the existing co-op-aware checkpoint-clear helper and verify solo death still clears its own save; retain run outcome/history behavior.

Record completed increments, verification results, commits, final build version/hash and any deliberately deferred work here before the morning handoff.

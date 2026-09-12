# Queued development — September 12, 2026

The user requested implementation of every queued item. The board contained three entries, claimed in saved order by separate tasks and developed in separate `codex/queued-20260912-*` worktrees. Each worktree inherited the current playtest source, including the Mirrorline stage-two changes and the approved lighter Crescent swish at its reduced volume.

| Feedback | Intended result | Development owner |
|---|---|---|
| `FB-dc92d28091274da1` | Fully replace the rejected player-centered Pull Field with a compact stationary seal and a Field-damage conversion payoff. | `01a09209-8771-78f3-9df0-b49907c3df66/pillar-redesign` |
| `FB-f54479e18abf4a7a` | Apply the earlier Kilnheart/Glass Weaver callout presentation to every boss and Apex trial. | `01a09209-8771-78f3-9df0-b49907c3df66/callout-reference` |
| `FB-7ffcd26ea1ba408f` | Correct Oathbreaker's stacking and sword origin for Effigy Keeper while preserving the reward's actual rules. | `01a09209-8771-78f3-9df0-b49907c3df66/oathbreaker-effigy` |

The callout reference is the alternate-boss drawing in commit `4025f72`, also retained in `d3a82a2`: centered warm lettering at font size 18, without a background plate. The later shared helper added a dark rectangle that was absent from the praised presentation. Readable screen size, health-bar separation, HUD avoidance and the later timing/replica corrections remain relevant constraints.

Development records, immutable incoming-source copies, the board snapshot and verification receipts are kept locally under `.feedback/queued-20260912/`. The initial preservation manifest covers 1,209 source files; 149 existing changed/untracked files were carried into each worktree. Integration compares each task against that starting source and merges shared edits instead of replacing unrelated work.

## Resulting behavior

Pillar Convergence becomes **Faultline Seal**, retaining its save/network power ID. Three/two distinct Attack-hit or Electric actions plant a stationary seal at the struck foe. It detonates after 0.8 seconds in radius 76/90 for 180%/240% of Damage. Later owned Field damage inside detonates it early for 270%/360%. One seal can be armed; a 0.6-second rearm interval follows detonation. Hits cannot move or extend it. It neither Pulls enemies nor follows the player, registers a Field or refunds Dash. The new role gives existing Fields a stronger timed Burst payoff. Its descendants retain their original-action limits and cannot plant further seals recursively.

All boss and Apex callouts use the earlier alternate-boss warm lettering without the later dark plate. The historical source was rendered directly in an isolated Main scene for comparison. The existing readable size floor, HUD avoidance, health-bar spacing and committed phase/replica expiry fixes remain.

Unbroken Oath uses each original Attack's unique contact index instead of a shared player counter for its multi-victim multiplier. The reproduced interleaved two-Attack case previously awarded 30.2956 Oath rather than 22.072. Ordinary solo fill/spend/refill was already working; the evidence identifies this specific contact-ordering defect. Sword visuals and replicated cues now use the committed Attack origin: body for deployment, effigy for subsequent melee and charged Attacks, including after the player walks away.

## Verification and review

The separate worktrees passed focused gameplay checks and native visual inspection. Oath's real host/joiner fixture also passed. Callout evidence retains 39 before/reference/after images at different widths and actual Apex doors. See [the callout reference](boss-callout-reference-20260912.md) and [Effigy compatibility](effigy-keeper.md).

Independent source review caught an armed-seal cancellation path that stopped running when a player died, plus delayed cue revival within the same room. Both fixes were reviewed: the actual cancellation/room/epoch boundaries clear seal state and partial charges, snapshot restoration clears old charge, and cue receivers check the current epoch and live combat state. Focused tests exercise real death, removal, discard, room, snapshot and epoch transitions while preserving the unrelated Oath bank.

The combined source passes 399-script compilation, the world/network contract gates and all 35 selected gameplay suites. The first run found three overly long glossary paragraphs; authored sentence breaks fixed them without changing wording or semantic spans. Two biome paragraphs were confirmed present in the starting source. The focused glossary check passes 189 assertions; the initial run's other successful suites and the remaining suites retain their separate receipts.

Combined real ENet passes 84 host / 18 joiner checks for Faultline and 27 host / 5 joiner checks for Oath. An initial Oath fixture assertion observed the bank before the host had accepted the probe's four contacts. A bounded contact-count barrier now waits for two accepted hits on each victim before independently asserting 22.072 Oath; it does not wait for the expected bank value or alter production behavior. The final receipt records both issued roots and accepted contact counts.

Native reward/build review passes 199 frames and 2,608 checks at 960, 1280 and 1920 widths, including every unowned/upgrade page and focused Faultline learned summaries, rules and four-offer pages. Thirty-two selected frames are retained. Root also inspected the native seal, Oath sword, historical/corrected boss, Apex and reward frames. The subsequent glossary-only line breaks do not feed the rendered reward/build panels.

Combined logs and machine-readable receipts are under `.feedback/queued-20260912/`: `verification.json`, `combined-network.json`, `reward-layout-evidence/receipt.json` and `source-audit.json`. The integrated source preserves 1,178 files unchanged and limits this batch to 46 changed/new source and documentation files. The original dirty work and audio assets are retained. No commit, push, tag or human acceptance is inferred.

## Normal desktop delivery

Delivered `dev-20260912-072135111-4f73ff34` to `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe` through the normal exporter without `-DebugRun`. The executable starts at the regular menu with normal progress; the isolated smoke test passed menu, first descent, movement, return and reopen. Development upload restrictions remain in place.

- Exported package: 27 checks passed.
- Actual exported executable: 62 checks passed, no shutdown warnings; the player's real profile was not used.
- All 395 compared source scripts and 12 Crescent audio/import files match staging exactly, with generated build information handled separately.
- Final size: 124,417,536 bytes.
- SHA-256: `9F2CF1D20EB91CB6D9C1DA9A70EE3166949469945F3E0C08B3B28EF2165894D6`.
- Export staging: `C:/Users/mikel/AppData/Local/Temp/abyssal-playtest-export-5161c9317c054b73bf2f1ce1b6ce6610/project`.
- Native evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-native-smoke-bec74c59c8a64766adfd73b271dde2e4`.

The three entries move to **Awaiting playtest** with this build ID. Their saved order is preserved; acceptance and any further balance changes remain the user's playtest decisions. No commit, push or release tag was requested or created.

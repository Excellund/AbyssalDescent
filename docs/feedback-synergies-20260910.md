# Boss reward synergy improvements

Feedback: `FB-b05971e543754ebd` — Improve synergies between boons, arcana and boss rewards.

Branch: `codex/feedback-b05971e5-synergies`. This work starts from committed main in its dedicated worktree; it does not import the primary checkout's newer uncommitted work.

## Acceptance condition

Electric damage can charge Pillar Convergence without an Attack. Damage against an already Marked foe can build Sovereign Tempo without an attack hit. Both rewards retain their Attack input and share one charge per original action across all eligible inputs, targets, ticks and descendants. Convergence cannot charge while active. Tempo's Burst and descendants cannot rebuild Tempo. Conditional Damage Boons still resolve once against the actual victim using each effect's own raw damage and coefficient.

## Implemented connections

- Pillar Convergence accepts Electric damage from Static Wake or Storm Crown, retaining its four/two-charge thresholds and existing moving Field. A qualifying action during an active Field cannot bank a later tick after that Field expires.
- Sovereign Tempo accepts damage against a pre-existing Mark from any supported source. Wraithstep, Eclipse Mark and Dread Resonance can prepare foes for Projectiles, Fields and Echoes to build Tempo. Existing six-stack cap, 1.8-second expiry, movement-completion Burst and accepted-damage Dash refund remain.
- The rewards use separate claims in the existing combat interaction ledger. Attack startup ordering remains intact. A canonical Tempo ancestry flag survives damage, Echo normalization, Crown chains and kill descendants; it prevents the payoff from replenishing itself.
- Co-op combat protocol advances to version 2 because older clients strip the new ancestry bit when processing remote kill descendants. Save IDs and saved power levels remain compatible; no new serialized power parameters are needed.
- Cards, build details, keyword matching, glossary and roster describe the new inputs. Convergence's descriptive damage model now correctly identifies the Damage stat as its pulse basis.

The existing generic Boons already serve these engines: First Strike, Blood Pact and Severing Edge scale each source's effective Damage coefficient; Heavy Blow increases its basis; Battle Trance refreshes on accepted damage; Blink Dash supplies more opportunities for movement powers. No Boon values, offer odds, roster size, or power levels change.

## Verification

All Godot runs used disposable projects with suppressed autoload startup, isolated user data and disabled external endpoints, through `run_gameplay_regressions.ps1` and the existing scoped helpers.

- GDScript compilation (303 files), world-property access and multiplayer configuration checks passed.
- Thirteen relevant gameplay suites passed: combat interactions, connected builds, shared damage boundary, shared producers, kill provenance, the new boss reward synergies, shared wording, reward layout, power descriptions, boss combinations, shared Oath attacks, power rewards and power snapshots.
- New native synergy fixture: **110 checks, zero failures**. It covers actual Wake, Convergence, Lacuna, Crescent, Sigil and Double paths, all three Mark generators, First Strike scaling, rejected damage, pre-damage Mark state, action retirement, cancellation and Tempo/Crown descendants.
- New two-process ENet fixture: **62 host + 11 client checks, zero failures**. Existing shared-build ENet: **143 host + 16 client checks, zero failures**, including protocol compatibility and actual owner state delivery.
- Final wording/layout checks: **1,429 wording**, **19,581 layout**, **435 description**, **560 reward** and **895 snapshot** checks, zero failures.
- GPU checks on RTX 4080: **84 upgrade pages / 1,393 checks**, **60 unowned-card and build pages / 772 checks**, and **33 selection/layout frames / 141 checks**, zero failures. Cards were rendered at 960/1280/1920 widths, including three/four offers, level upgrades and Prismatic. The changed cards were inspected at 960 pixels. A longer Tempo stat line initially clipped; shortening it fixed both headless layout and GPU checks while retaining the exact refund in the glossary.
- `git diff --check` passed. Changes remain uncommitted for the requested review checkpoint; no desktop build was delivered.

Local evidence directories (under `C:/Users/mikel/AppData/Local/Temp/`):

| Evidence | Directory |
|---|---|
| Initial combat regression selection | `abyssal-validation-549f1d83a9f84e7aa3edfe7e9416e1b3` |
| Native synergy fixture | `abyssal-validation-f2fc3cee67fa44a190656b2e7f638749` |
| Final wording, layout, rewards and snapshots | `abyssal-validation-b6d53f8800ef4d9d8cd08c0e7f39bade` |
| New synergy ENet | `abyssal-enet-87589f85ac75492c8774f176372b3714` |
| Existing shared-build ENet | `abyssal-enet-e6e4812e1ce14498be5d316b4464f667` |
| Upgrade GPU pages | `abyssal-gameplay-render-03ecaa90208f4db2bd84022539dc24cd` |
| Unowned and build GPU pages | `abyssal-gameplay-render-bbf26fbb4cf04495985ef939be10f8cc` |
| Selection/layout GPU frames | `abyssal-gameplay-render-cba7ecd337ce4864aca167c727664f9b` |

Reproduce the new native fixture with `run_gameplay_regressions.ps1 -TestScripts @('res://scripts/tests/test_boss_reward_synergies.gd')`. Run the ENet fixture with `test_boss_combinations_enet.ps1 -ValidationProject <isolated-project> -FixtureScript res://scripts/tests/test_boss_reward_synergies_enet.gd`.

## Integration

Likely shared files are `scripts/power_registry.gd`, `scripts/upgrade_system.gd`, `scripts/shared/reward_card_copy.gd`, `scripts/shared/glossary_data.gd`, `docs/combat-wording.md`, `docs/combat-power-roster.md` and `.github/scripts/run_gameplay_regressions.ps1`. Merge their small additions alongside the other queued branches. The primary checkout already has unrelated changes to the wording guide and regression runner. Preserve those changes.

The implementation also touches `scripts/shared_build_runtime.gd`, `scripts/shared/combat_interaction_registry.gd` and the lobby protocol constant. Coordinate any other combat protocol changes into one consistent version. No changes are made to `player.gd`, boss encounter scripts, audio, the shared desktop executable or the primary checkout's game files.

## Human playtest

Compare an ordinarily earned Static Wake/Pillar Convergence build with the existing Attack cadence. Check whether four Electric actions at level 1 and two at level 2 feel useful without making the active window constant. Try Wraithstep or Eclipse Mark with Returning Crescent, a damaging Field, and Sovereign Tempo; assess whether Tempo is readable and spendable before its existing 1.8-second timer expires. Confirm that its Burst feels rewarding while requiring another eligible source to rebuild stacks.

Automated contract checks establish eligibility, damage scaling and repeat limits. Human feedback is still needed for pacing and enjoyment; this item remains awaiting playtest rather than accepted as done.

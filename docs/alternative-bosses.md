# Alternative bosses

Each new normal run independently chooses one of two bosses for each act, with equal probability. The original trio remains available: Warden or Kilnheart, Sovereign or Glassweaver, and Lacuna or The Null Archivist. The host rolls the full three-act roster once. Looking at doors, changing rooms and using Continue do not reroll it.

Kilnheart uses close furnace blasts, a hollow halo and marked ground. Glassweaver weaves crossing lanes with safe spaces between them. The Null Archivist records player positions as disks, then revises those positions into hollow rings. Every damaging shape is committed in world space during its warning. Co-op players share the host's geometry and damage resolution.

| Boss | Attack | Response |
| --- | --- | --- |
| Kilnheart | Crucible Slam | Leave the solid disk around the furnace. |
| Kilnheart | Furnace Halo | Step into the empty inner pocket or retreat beyond the ring. |
| Kilnheart | Cinderfall | Move away from your captured position before its disk resolves. |
| Glassweaver | Split Loom | Use the unpainted corridor between the two parallel threads. |
| Glassweaver | Cross Stitch | Move diagonally out of the cross committed to a player's position. |
| Glassweaver | Glass Cage | Stay in the inner pocket or move beyond the outer ring. |
| The Null Archivist | Record | Leave the disks captured at living players' positions. |
| The Null Archivist | Revision | Return to the recorded positions, now hollow safe pockets. |
| The Null Archivist | Final Margin | Move into an unpainted inner quadrant or outside the entire ring and cross. |

Bosses cycle through their three attacks. Kilnheart closes toward melee range; Glassweaver strafes between casts; the Archivist preserves its recorded positions for the following Revision. All stop during warnings and recovery. Warning times remain 0.95–1.25 seconds even below half health; enrage shortens the interval between casts instead. Base health matches the original stage (1100, 2000, 2400), with existing Bearing and co-op scaling. The alternative's `attack_damage` participates in boss damage scaling.

Intersecting co-op rings merge into one enclosing safe pocket, retaining the original dangerous band's thickness. Every original safe disk remains inside that shared pocket, preventing teammates' rings from erasing another player's escape route. Damage applies once per living player per cast, including intersecting shapes and duplicate roster entries. Death, authority changes and loss of all living targets cancel warnings and remembered positions.

The bosses have distinct silhouettes: Kilnheart's segmented furnace shell, Glassweaver's four needles, and the Archivist's open book. Warm outlined areas mark danger and leave safe pockets empty; a boss progress arc and attack name show the cast's progress. Brief white afterglow marks a resolved impact and deals no extra damage. World-space geometry remains stationary when players move or a replica interpolates the boss body.

`scripts/shared/boss_catalogue.gd` owns stable IDs, stage membership and display names without loading combat scripts. `boss_stage_registry.gd` composes stage dimensions and spawn constraints with the selected identity. Its existing one-stage descriptor and two-argument constructor calls still resolve the originals. Alternatives use `enemy_boss_alternative.gd`; the registry configures its ID before `_ready` and sets `boss_id` / `boss_stage` node metadata for replication.

`RunSession.act_boss_ids` stores the roster. Snapshots preserve it without a save version change; missing, invalid or wrong-stage entries fall back to that stage's original boss. Boss doors retain their existing stage route keys and reward rules, while the offered label names the selected boss. Boss reward offers still use the existing nine-reward pool with equal random selection. The first two stages give a boss reward; the third completes the run. Recorded defeats, epitaphs, room labels and results use actual boss IDs. Existing mastery oaths remain tied to their named original bosses.

Reliable progress payloads carry the host roster, applied before a chosen boss door constructs the room. Boss spawn payloads include explicit identity, maximum/current health and full runtime/projectile state. A replica missing its boss can request reconstruction from the host after entering the matching room; room sync IDs and host authority prevent stale-room spawns. The baseline does not support joining an arbitrary active run: this change preserves that boundary instead of adding new room/player progression recovery.

Committed shapes and precise timers travel through the existing unquantized projectile stream and spawn snapshot. Generic runtime state carries only an activity hint, because that stream rounds coordinates and can trim custom data. Increasing snapshot numbers reject reordered packets, while cast/phase guards prevent an older warning from reviving after resolution. A locally expired client warning clears without inventing an impact or dealing damage.

For a focused debug encounter, use `start_debug_encounter("kilnheart")`, `start_debug_encounter("glassweaver")` or `start_debug_encounter("null_archivist")`. Existing named debug entries continue to select their original bosses. Keep focused automation in disposable copies with isolated user data.

Integration overlaps: `world_generator.gd` room entry, door labels, damage scaling and progress RPCs; `RunSession` and `run_snapshot_service.gd`; recorder/tracker results; boss glossary and epitaph metadata; renderer entrance motifs. No new reward powers or accepted-damage interactions are introduced.

## Verification and playtest

Feedback item: `FB-7acc891ded854115`. Run `.github/scripts/run_gameplay_regressions.ps1` with `test_alternative_bosses.gd` and `test_alternative_boss_selection.gd`. These fixtures check real damage against independent geometry samples, recovery/cancellation, overlapping four-player rings, reordered replica packets, seeded selection, legacy saves and actual checkpoint/Continue and victory paths. Existing boss, route, reward and result suites cover compatibility.

Use `.github/scripts/test_alternative_bosses_enet.ps1` against a disposable validation project for two actual host/joiner processes, and `.github/scripts/render_alternative_bosses.ps1` for GPU captures. Automated profiles and logs stay inside disposable temporary projects.

Normal playtest should judge first-encounter readability, Kilnheart's melee openings, Glassweaver's challenge for ranged builds, the Archivist's Record/Revision sequence, and large merged rings near arena edges in four-player co-op. Balance and encounter enjoyment remain human playtest questions. Coordinate desktop build delivery with the other queue tasks; this implementation does not declare a commit or build checkpoint.

Verified September 10, 2026 on `codex/feedback-7acc891d-alternative-bosses`:

- All 307 GDScript files compile; world-property and multiplayer configuration checks pass.
- Alternative combat: 3,301 checks, zero failures. Selection, actual disk Continue, rewards and replica reconstruction: 254 checks, zero failures.
- Existing boss telegraphs, committed charges, combination foundation/combinations, descent routes/presentation, result identity, power rewards and checkpoint isolation pass through the scoped regression runner.
- Glossary readability: 186 checks, zero failures at 960/1280/1920 widths. New descriptions were shortened after the original copy wrapped.
- Separate loopback ENet processes: 145 host and 38 joiner checks, zero failures. The nine two-player warning packets measured 583–827 bytes. Generic quantized body snapshots preserve exact projectile-stream geometry.
- RTX 4080 GPU review: 16 frames covering nine warnings, three entrances, two four-player edge groups, owner cleanup and the three alternative door motifs. Danger borders, hollow pockets, silhouettes and labels were visually inspected at the production camera's arena-fit scale.

Local evidence roots (disposable projects under `C:/Users/mikel/AppData/Local/Temp/`): broad compatibility run `abyssal-validation-59ba26d5d26d4c7c99a6f9fa423a8f41`; final combat/selection/presentation `abyssal-validation-d0b54e1c776446408a546af4bc82c727`; corrected glossary and final compile `abyssal-validation-2ae1f0daf02f423fae57f45ffc9d53c3`; ENet `abyssal-enet-9fb1d75dc7c849488f2b42dc90a2e695`; clean GPU frames `abyssal-gameplay-render-2996507230904f3ab03452dbc1cf3f8c/alternative_boss_frames`. The final combat/selection run also exposed the glossary wrapping, subsequently fixed and verified separately.

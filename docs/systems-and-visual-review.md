# Follow-up: systems implementation and visual review

Requested after the Keeper/Breach update. Review existing systems in small passes while playtesting continues, and turn findings into verified improvements. Do not combine a broad rewrite with new content or introduce live performance/Oath prompts.

## First review increment: combat pause and faithful attack shapes

Implemented September 9, 2026:

- Weaver webs pause damage and lifetime with combat. Closing Build Details behind Pause, or closing Pause while Build Details remains open, keeps combat, waves and the run timer paused. Reward and outcome screens also prevent accidental resume. Original processing flags are restored rather than enabling unrelated disabled actors.
- Shielders resolve the existing directional defense from each attack's actual world origin. The enemy's AI target no longer substitutes for the attacker. Chain hops, trails and bursts retain their own origins; damage ownership remains tied to the authenticated player.
- Idle shield orientation reaches joiners even in crowded rooms. Compact integer angles retain precision, revision ordering rejects older orientation, and heartbeats recover a lost final turn. The drawn wedge uses the same fixed body radius as mitigation.
- Melee swings remain at the hit position during recoil/orbit, with constant reach while fading. Empowered range/arc uses the same geometry calculation as damage. Replicated Razor Wind and shade strikes show their actual inner boundary.
- Applying a saved build clears actual dash collision exceptions before dropping their tracked IDs.

Validation includes isolated gameplay regressions, 28 real pause/lifecycle checks, 62 hit-origin checks and 37 attack-feedback checks. The old hit-origin implementation reproduces failures; a separate Farline regression proves its burst retains one origin even when a hit callback moves the player. Three actual GPU frames cover moving melee, local/remote Razor Wind and the shade's inner boundary. The live ENet suite adds 35 passing checks for authenticated front/rear hits, shield orientation with 64 enemies, stale/duplicate updates, lost-turn recovery and the remote strike's fixed origin and hollow band.

Sovereign's Double retains its current damage, ground bypass and proc rules. This increment corrects presentation and hit provenance without retuning the reward.

The queued Attack/Blast Drive issue was corrected in the overnight branch: a held attack buffered through dash begins charging only after its strike succeeds, including when Orbit acquires movement. Released taps remain single attacks. The 127 focused checks cover all four characters, cooldown/overheat, movement and input cancellation.

## Overnight review increments

Branch `codex/overnight-buildcraft-20260909` continues the review alongside Returning Crescent. The current delivery record is in [overnight-development-20260909.md](overnight-development-20260909.md).

- Reward descriptions now use actual motion damage/reach and current character values. Blood Pact, Eclipse Mark and Null Corridor descriptions match their existing behavior. Reward panels and labels shrink correctly after a viewport resize. The description/layout suite has 262 checks and four inspected GPU frames.
- Ruinous Impact has attached launch streaks, inward compression brackets and a fractured burst at the real damage radius, with bounded effects and sound. Reliable room-scoped cues support the same feedback in co-op; damage and timing are unchanged. Dedicated behavior and two-process ENet checks pass.
- Lacuna's Echo Cross warning now covers the real capsule geometry. Its active seams retain their full radius, and expired or removed-owner warnings are cleared. Host and joiner use the same synchronized seam renderer; 65 checks and four inspected GPU frames cover the corrections.
- Lancer floor zones hit every eligible player exactly once per tick on the host. Their active-time accounting prevents a long frame from applying a tick scheduled after expiry. Fracture Field and Lacuna pulse kills preserve the same narrow non-chaining rules across the host/joiner boundary.
- Co-op defeat preserves a suspended solo save. Departing peers are unregistered and removed, with enemies retargeted and the host rechecking defeat, reward, intro and retry readiness.
- Checkpoints and local history preserve original and observed build provenance. Development, debug, mixed-build and unknown-origin runs stay out of submissions; a release host also retains participating development/debug peers' evidence.
- Crescent, Ruinous, recoil and Orbit now collide with the real arena perimeter, which uses logical clamps rather than physics walls. Room shrink cancels forced motion without creating damage or a shade. Tests include actual world-clamp-before-physics ordering and separate live peers.
- Resume now preserves Surge Step's dash speed and Voidfire's overheat movement multiplier. Older saves reconstruct those omitted values from their saved upgrades, while explicit values win and repeated restoration cannot stack them again. The actual disk/world restore fixture passes 395 checks; the original code fails 113. This change awaits the next verified checkpoint export.
- Dash and enemy charges remove actual physics collision handles after an enemy is freed. Edge escape retargeting and co-op departures clear only their owned relationships, preserving other active phasing. Two regressions cover 101 expectations, including all four party bodies and repeated real room transitions. Crowded-room soaks return to exact node baselines; movement and immunity values are unchanged.
- Heavy impacts on another player no longer flash the host's entire screen. World rings remain visible and the struck joiner receives the existing reliable damage cue. Screen layers follow local ownership even when peer identity arrives after player setup. Focused and real ENet regressions plus two inspected GPU frames verify the change without changing solo flash strength.
- Four actual network processes now verify departure cleanup, reward/survey readiness and retry voting for the remaining party. The reusable harness retains its existing two-process default; all 207 four-process checks pass.

Warden and Lacuna now capture nominal charge speed and duration before the warning and follow a finite straight path with a full rounded contact warning. Lacuna retains tracking during windup; terrain stops travel without shortening the attack timer. Swept host damage and expiring, ordered co-op warnings match the committed geometry. The prototype passes 402 behavior checks, 106 live network checks and six inspected GPU frames. This deliberate movement correction still needs human boss feel/difficulty feedback.

Full verification and delivery evidence are recorded in the overnight log. The snapshot and collision fixes are in the normal lifecycle desktop checkpoint; committed charge paths await the following export.

## Pass 1: combat and movement contracts

Trace attacks, Arcana, boss rewards, enemy protection and pushes from input through accepted damage, kill ownership, statistics and multiplayer authority. Check each playable character at every power level and Prismatic, plus pause, reward, death, retry and resume boundaries. Start with observed inconsistencies and duplicated behavior that has already drifted.

Review the responsibilities and interfaces of the large player/world scripts and their existing helper controllers. Extract or consolidate only when it removes a concrete source of mistakes. Preserve behavior first, then make deliberate gameplay changes separately.

## Pass 2: combat readability

Capture representative encounters at the actual gameplay camera scale, including crowded Act 2–3 rooms and co-op. Review enemy silhouettes, attack warnings, ward links, hit feedback, recoil/orbit direction and shade strikes together. Compare what the player sees with the real damage area and duration.

Fix unclear impacts and obscured warnings before adding more particles. Reuse the current palette, keep effect lifetimes and density bounded, and inspect actual rendered frames after each change. Retain the Keeper's distinction between protection and danger telegraphs.

## Pass 3: progression and interface clarity

Compare reward cards, current-build descriptions and the glossary with runtime behavior. Check that menus clearly distinguish a normal run from debug testing, saved preferences from active run modifiers, and earned unlocks from temporary grants. Review route/encounter cues without adding new required decisions to combat.

## Pass 4: data and performance

Use recent local runs and the existing DB analysis workflow with explicit build/date filters and separate output paths. Do not use the historical May report to justify current tuning. Profile actual crowded rooms before changing update rates, replication budgets or visual detail. Keep client presentation smooth while retaining host authority.

## Delivery

For each pass, record the issue, player-visible consequence, smallest useful correction and verification evidence. Agree on a checkpoint, commit and push the completed changes, then replace the existing desktop playtest with a normal build. Use a temporary debug build only when focused testing calls for it.

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

Next confirmed control issue: holding Attack through a queued dash attack executes the strike but does not arm Blast Drive. Address queued attack/hold handoffs in the next bounded control pass, then continue the broader character, reward and boss-telegraph review below.

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

# Follow-up: systems implementation and visual review

Requested after the Keeper/Breach update. Review existing systems in small passes while playtesting continues, and turn findings into verified improvements. Do not combine a broad rewrite with new content or introduce live performance/Oath prompts.

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

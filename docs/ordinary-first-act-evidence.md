# Ordinary first-act evidence

This bounded September 12, 2026 check complements the Relic Recovery and Rest choice fixtures. It runs actual Main from the starting Arcana draft with active enemies, base Delver Bastion statistics and ordinarily earned rewards. Automated play is evidence about the tested route and controls; it does not establish human difficulty, enjoyment or balance.

## Registered attempts

Both attempts were fixed before combat began. They are not selected from successful bot runs.

| Seed | Rest policy |
|---|---|
| 12092026 | Choose Recover at the first offered Rest. |
| 12092027 | Choose the first offered owned-Boon upgrade at Rest; Recover if none exists. |

The door policy chooses an offered Relic Recovery before an unvisited Rest, then the boss, ordinary Boon combat, another Mission, or the first remaining route. It never inserts a door, replaces an offered profile or retries for different offers. Rewards use the first available ID in a fixed list of conventional Attack benefits; if none matches, the first offered card is chosen. There are no reward rerolls. The exact order is recorded in the fixture's `REWARD_PRIORITY` constant.

The pilot uses the existing headless mouse driver to aim at the nearest enemy. It walks toward Attack range, holds position there, retreats from close contact and uses ordinary Dash. With enemies cleared, it walks to objective positions, relics, the receiver or the selected door. Real movement ends the encounter survey; Interact enters the chosen door, and the actual visible reward card receives Attack input. There is no path planner or boss-specific response system.

Each attempt stops after first-act completion, defeat or 21,600 control frames (six minutes at the normal 60 Hz), plus brief reward-selection presentation time. Defeat and timeout remain recorded outcomes. Invariant checks concern normal starting state, valid offered-card input, damage remaining enabled and actual mouse aiming; a passing invariant suite does not imply that the first act was cleared or that either new feature appeared.

## Isolation and reproducibility

Run `.github/scripts/test_ordinary_first_act.ps1`. It uses the existing disposable-project regression helper with isolated profiles and suppressed external autoload startup. Main, its production methods, scene children, actor updates and combat effects are real. The fixture-only World subclass performs normal bootstrap, then replaces the randomized RNG seed before run content is generated; authored exported Main values are preserved. No production script is changed for the pilot.

The fixture supplies no health, powers, stat adjustments, teleports, idle enemies or disabled damage. The selected starting Arcana is actually earned from the normal draft. The profile records the introductory tutorial as already completed so the run starts at that draft. Seeds fix the source of randomness; this remains an ordinary timed engine run rather than a lockstep replay. Enemy spawning and other legitimate draws share the production RNG and can affect later offers.

`ordinary_first_act.json` in the disposable project records every observed room transition, every offered door and reward, the chosen entries, health, depth, elapsed physics time, earned build, temporary effects and final outcome. The helper also retains logs. No telemetry or leaderboard data is submitted.

## Original pilot results

Both registered attempts ended in defeat. Neither Recovery nor Rest appeared in the actual door offers before defeat. **This does not establish first-act completion, ordinarily reached Recovery, or either Rest policy.** No additional seeds or combat retries were run to fill that gap.

| Seed | Earned build | Ordinary route and outcome |
|---|---|---|
| 12092026 | Razor Wind, Iron Skin, Patient Hunter | Cleared Skirmish and Pursuit. Entered Iron Volley Suppression at depth 2 with 123 HP; defeated at 20.25 seconds. 26 Attacks, 35 enemy hits, 10 kills and two Dashes. |
| 12092027 | Voidfire, Severing Edge, Heavy Blow, Battle Trance | Cleared Skirmish, Pursuit and Onslaught. Entered Vanguard at depth 3 with 69 HP; defeated at 38.15 seconds. 69 Attacks, 85 enemy hits, 30 kills and ten Dashes. |

The first run was offered Pursuit/Skirmish, then Suppression/Intercept Run. The second was offered Pursuit/Skirmish, then Onslaught/Cut the Signal, then Vanguard/Intercept Run. The predefined route policy selected the ordinary Boon encounter each time; all these decisions were available in the actual run.

The isolated helper passed 26 invariant checks, compiled 429 scripts and passed both world/network guards. Both runs retained combat damage for every active combat frame and had no mouse-aim mismatches. These passes validate fixture constraints and route/reward input; they do not turn the defeats into successful gameplay coverage. A simple pilot that stops at Attack range cannot reliably respond to ranged pressure and mixed enemies. This is a limitation of the automated strategy, not a human balance verdict or a reproduced production defect.

Evidence: `%LOCALAPPDATA%/Temp/abyssal-validation-1494dbd4934445a69ada9c378e94196d`. Raw JSON and stdout/stderr are retained under `.feedback/uncharted-descent-20260912/ordinary-first-act/`. The raw JSON SHA-256 is `B8D39D0D61E45B4950E60B6D3113E4014783A71D25B47294A6E43478D99F8BCB`.

A logger-only aliasing defect cleared each recorded `door_choice.chosen` dictionary when entering the next room. All offered dictionaries and subsequent entered-room states remain intact; the routes above are read from those room states. The fixture now deep-copies the chosen dictionary, matching its existing deep copies of offers and rewards, and prints a concise result. The preserved raw receipts are unchanged and the two combat attempts were not replayed after this logging correction.

## Revised driver pilot on the final game source

At 14:28 local, the same two seeds and Rest policies were registered for a separate bounded pilot. It preserved the original reward priorities, offered-door priorities and budget of 21,600 control-loop iterations per attempt, plus reward-selection presentation waits; this is not a strict six-minute elapsed-time limit. The revised driver continuously strafes using its currently earned Attack reach, separates from close enemies and the arena edge, and reacts to currently drawn Archer/Charger windup lanes and visible arrows. Arrow direction is inferred from successive visible positions. It reads current scene geometry corresponding to visible objects; this is neither rendered-pixel input nor human reaction evidence. It does not inspect hidden attack timers, future spawns or future choices.

Only a disposable test copy changed. There were no debug powers, health grants, forced routes or rewards, fixture teleports, suppressed enemies or disabled combat damage. The source and driver differ from the earlier pilot, so outcome differences cannot be attributed solely to the revised strategy. No strategy, seed, reward priority or door priority changed after observing a combat outcome.

### Preparatory failures and input correction

The first invocation never resolved its starting Arcana draft and completed zero attempts. Its verified owned processes were stopped and its logs retained. A separate noncombat preflight disproved the initial fixed-pointer hypothesis: both input methods moved the pointer correctly. The old headless harness left the physical window at its tiny default size; the game's current physical reward layout therefore placed card centers outside usable bounds. That preflight also exposed two errors in its own assertions/helper: a typed Panel-array search received a footer Button, and initial reward acceptance was incorrectly expected to open doors rather than start the first Skirmish.

The authorized correction sets only the isolated root to 1280×720 with the production 2560×1440 logical canvas. The original mouse event helper remains unchanged. After correcting those preflight errors, the disposable helper compiled 455 scripts and passed both guards plus 16 input checks, including original-pointer targeting of all three actual cards and the real initial Skirmish survey gate. An independent source review confirmed the correction. Both failed preparations were retained. A separately locked continuation then ran exactly the two registered combat attempts once.

### Observed outcomes and limits

Both attempts naturally received a Rest offer after their third combat clear and entered Rest Site at depth 4. Each saw three Rest offers across the whole run; the unchanged policy visits only the first, then prioritizes other routes. **Neither seed was offered, entered or completed Relic Recovery.** That ordinary-route coverage gap remains.

| Seed | First Rest observation | Subsequent ordinary play |
|---|---|---|
|12092026, Recover | Left Suppression at depth 3 with 122/140 HP; entered Rest at 29.42 s. Selected the actual Recover card and reached 140/140 HP at 30.98 s. Iron Skin and Long Reach upgrades were also offered. | Continued through Ambush and Convergence to Fortress; defeated at depth 6 after 62.15 s. 100 Attacks, 133 enemy hits, 38 kills and 20 Dashes. |
|12092027, invest | Left Onslaught at depth 3 with 112/130 HP; entered Rest at 22.58 s. Selected the actual offered First Strike upgrade, whose card showed conditional Damage +16→+32. Health remained 112/130 at 24.15 s. | Continued through Fortress, Suppression and Gauntlet to Pulse Window; defeated at depth 7 after 82.92 s. 113 Attacks, 137 enemy hits, 71 kills and 39 Dashes. |

The first trace directly records the 18 HP recovery. The second records acceptance of the owned-Boon upgrade through the real reward path and unchanged health; its compact build snapshots retain power IDs, not post-choice numeric properties. These observations support ordinary Rest access, its two offered action paths and post-visit continuation. They do not establish first-act completion or human balance acceptance.

The final fixture produced **44 checks: 42 passed and two movement-metric checks failed**, so this is not an all-pass pilot receipt. Both runs retained enabled damage throughout active combat and had zero mouse-aim mismatches. The new movement sampler treated equal network room IDs as uninterrupted movement, producing maxima 237.36 and 234.86 units. Source inspection found that normal door entry resets the player's position (`WorldGenerator._choose_door`), while Rest entry changes the room/depth without advancing that network room ID (`_enter_rest_site`). The sampler therefore includes that legitimate transition. The raw events document depth 3 combat → depth 4 Rest in both runs, but contain no per-frame coordinates identifying where the exact maxima occurred. The continuity metric remains unverified; its failed checks were neither removed nor retrospectively counted as passes. No combat replay was performed.

The final raw JSON SHA-256 is `2BB358B3B89547845EB5C7FFC96E1940AFBAC4D178D84EF11B3236D5345D0DFB`. The isolated execution is `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-275f5f8b823e4afa88d708e7f339c65a`. Exact protocol, original/revised drivers, failed preparations, narrow process-termination record, preflight and source hashes are retained in `.feedback/uncharted-descent-20260912/ordinary-first-act-improved/`. Final JSON, strict result, locked launcher and raw logs are in its `corrected-continuation/` subdirectory. All 1,084 primary runtime/helper inputs remained unchanged, and the copied source matched its recorded inputs except the helper's intentional isolated `project.godot`. No default fixture, production script, desktop build or original result was replaced.

# Movement, combinations and Keeper playtests

The [development plan](development-plan.md) tracks current priorities and the delivery pipeline. This document retains feature and playtest history.

These three updates preserve attack, dash, and movement controls. Development exports have unique `dev-*` versions, retain local run history, and cannot submit telemetry or leaderboard records remotely.

Open **AbyssalDescent Playtest.exe** on the desktop (`C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe`). Both normal and debug builds replace this same executable. Keep one desktop playtest file; the unique `dev-*` version inside the build identifies each update in local run history.

The delivery workflow uses `.github/scripts/export_playtest.ps1` for a normal build, which starts at the menu with regular saves and no debug grants. Add `-DebugRun` for the debug preset: Bastion on Delver with both new Arcana at level 3 and both new boss rewards at level 2, using a separate persistent debug save directory. Switching modes replaces the executable while keeping the two save sets separate.

`.github/scripts/start_debug_playtest.ps1` exports the debug build and launches that same desktop executable. Debug delivery uses the packaged desktop game; temporary source sessions remain validation tools. Both export modes are verified. The desktop file currently contains normal build `dev-overnight-hazards-20260909-013751`: regular menu and progression, with no debug powers granted. Its verified SHA256 is `76BE4B7BDCDA6AFD8134790310F9E4AE1F85A186B2D03987A387272CE95B5841`. The [overnight playtest notes](overnight-playtest-notes-20260909.md) cover the new content and useful feedback.

At an agreed checkpoint, verify the completed work, commit and push it, and replace this file with a normal build. Keep debug builds for requested focused tests. The standing workflow is recorded in the repository's `AGENTS.md`.

## Update 1: motion Arcana and Ascension

Historical build version: `dev-content1-20260908-172850`.

- Blast Drive: tap attack normally; hold a successful attack for at least 0.25 seconds, aim, then release. Full charge takes 0.65 seconds. The blast fires forward and recoils backward. Level 2 stores two charges; level 3 steers recoil with movement input within 45 degrees.
- Razor Orbit: tap dash normally; aim directly at an enemy first, then hold dash through the normal dash to hook it. Release to leave tangentially. Level 2 allows column anchors; level 3 allows one aimed transfer when the enemy anchor dies. A charged blast detaches and launches out of an orbit.
- Ascension is effective only on Forsworn. Lower Bearings keep saved Forsworn preferences without applying them. Resuming restores the resolved run setup, including an empty selection. Legacy Forsworn runs without trustworthy modifier evidence remain playable but cannot earn new Ascension records.

Try quick taps, a deliberate hold, a missed hook, attacks during motion, a blast out of orbit, wall/column collisions, and an anchor dying. Opening rewards or menus, death, and lost focus cancel held actions and require release before rearming.

## Update 2: arenas

Historical build version: `dev-content2-20260908-173929`.

Crossfire gets offset firing lanes, Fortress a broken ring, Vanguard forked approaches, and Ambush asymmetric side cover. Undertow is an Act 2–3 standard encounter with an open center, staggered Drifter rings, and light melee pressure. No more than two Drifters can be active, including co-op. Tutorial, Hold the Line, Trials, and Apex retain their obstacle exemptions.

Watch whether the visible ring gap, columns, and side approaches create useful movement choices without hiding enemy telegraphs. In co-op, compare ring origins, gaps, and damage for both players.

## Update 3: boss combinations

Complete build version: `dev-content3-20260908-174847`. Includes the previous two updates and their later integration fixes, delivered through the same **AbyssalDescent Playtest.exe** desktop file.

Ruinous Impact and Sovereign's Double each allow two picks. Ruinous supplies a launch on direct hits and adds one collision burst to launches; immovable enemies compress instead. Sovereign's Double leaves one shade after movement, repeating the next deliberate attack shape at reduced damage. The second pick strengthens Ruinous and lets the shade repeat twice.

Try each reward alone, then with Blast Drive, Razor Orbit, Execution Edge, Razor Wind, Reaper Step, Edict, and Null Corridor. Check that secondary bursts and shade strikes cannot recursively create more launches or echoes.

## Playtest feedback adjustments

Earlier delivery `dev-motion-20260908-190812` replaced **AbyssalDescent Playtest.exe**; that package and desktop copy were verified.

Feedback from playtest `dev-debug-20260908-184946395`: Blast Drive felt oversized and its impact was unclear; Razor Orbit did not activate. Sovereign's Double was liked, and unrestricted Arcana proc expansion is deferred. Ruinous Impact felt bland; its behavior is unchanged in this pass.

Blast Drive now uses a 70-degree cone and 100–160 base reach as charge builds, replacing 100 degrees and 220–300 reach: about 80% smaller nominal cone area at full charge. Damage, recoil, and level scaling stay the same. The cone and expanding shockfront remain at the firing position for 320 milliseconds, with hit flashes to show contact while the player recoils.

Razor Orbit remembers the highlighted target when Dash is pressed. Aim first, hold Dash, then release to leave the orbit. A deliberate aim correction can find a target within the first 0.70 seconds of the hold. Sight checks ignore enemies and teammates but respect cover, and targets removed during the grab are handled safely. Test the gesture on nearby enemies and level 2 columns.

The September 9 direction fix chooses Orbit's circling direction once from the entry dash. Held movement keys no longer reverse it as the tangent rotates. Entry and release tangents now match the actual circular movement. Test both directions, held movement, changing movement input, transfer and tangential release.

## Keeper and Breach

**Keeper** is a vulnerable support enemy that wards up to two ordinary allies within 220 pixels. Active wards reduce damage taken by 30% and keep allies at a minimum of 1 HP. This follow-up addresses feedback that strong builds could overwhelm the original reduction and ignore the Keeper. Damage still wears allies down; once a link breaks, the next damaging hit can finish an ally held at 1 HP.

Dashed gold links show the 0.6-second warmup; solid links and shield marks show active protection. At 1 HP, a brighter link and a gold shield around the ally show what is keeping it alive. Kill the Keeper, push it with at least 40 pixels/second of force, use cover, or move its allies beyond the ward radius to break protection. Pushing the Keeper interrupts both wards for 1.25 seconds before a fresh warmup, giving Ruinous Impact a direct counterplay role. Wards never heal or stack and cannot protect bosses, Apex enemies or other Keepers.

**Breach** introduces one Keeper alongside archers and chasers in Acts 2–3, with an open center and side cover. Each Bearing has its own starting population, and co-op retains the one-Keeper limit. The route, checkpoint and ordinary reward systems include the new encounter. Full behavior and starting counts are in [next-content-update.md](next-content-update.md).

Playtest with enough damage to normally kill a protected ally in one burst: the ally should survive at 1 HP, the gold shield should explain why, and breaking the link should let the next hit finish it. Check whether this creates a useful opening and whether ordinary attacks and movement provide enough answers without the new powers. The requested [systems implementation and visual review](systems-and-visual-review.md) now has its first completed increment below.

## Combat systems and visual review

Normal build `dev-combat-review-20260908-231125` includes the content above and the first review fixes. Weaver webs pause their damage and lifetime with combat. Closing one menu while another remains open keeps combat, waves and the run timer paused. Shielders defend against each attack's actual origin, and their shield facing stays synchronized in crowded co-op rooms.

Melee swings stay at the hit position during recoil and orbit. Empowered attack outlines use the actual damage geometry, while remote Razor Wind and shade strikes show their hollow inner boundary. Sovereign's Double retains its existing damage and proc rules.

Try pausing inside a Weaver web, opening Build Details and Pause together, flanking Shielders in co-op, and attacking while moving with recoil or Orbit. This is an initial correction pass; the broader review continues in [systems-and-visual-review.md](systems-and-visual-review.md).

## Overnight: Returning Crescent and Breakwater

The overnight branch adds **Returning Crescent**: accepted attacks send a blade outward, then moving changes its return path. Level 2 allows two active blades; level 3 adds one outward ricochet from cover or the arena edge. Each enemy can be hit once on each leg. Ruinous Impact now shows attached launch streaks, compression brackets and the actual burst radius. Held attacks queued through a dash arm Blast only after the strike succeeds.

The same checkpoint corrects Lacuna warning shapes/lifetimes, Lancer floor damage in co-op, secondary kill-proc consistency, room-edge collisions, co-op departure and checkpoint isolation. Saved build provenance survives resume and co-op participation, keeping development/debug/mixed or unknown-origin runs local. Reward descriptions and resizing were checked against their actual behavior. Full evidence and the next content increment are in [overnight-development-20260909.md](overnight-development-20260909.md).

**Apex Breakwater** adds a fourth optional Apex encounter from depth 5. Bait its locked charge toward the arena edge, leave the lane, and use its longer recovery after impact. It stays vulnerable throughout; the open plates and cyan core show recovery. It uses the existing Arcana reward and needs no particular power to beat. [Fight details](apex-breakwater.md) include starting values and verification.

Try moving to change Crescent's return path and using your movement build around Breakwater's committed lane. The main questions are whether these create useful positioning decisions and whether the warnings and recovery are clear.

## Baseline and feedback

The September 1–9 UTC query for release `0.6.0` returned 35 runs: 15 clears, 19 deaths, and one quit. All were solo. Five September 8 local `dev` runs were analyzed separately; their plain version label cannot identify the exact patch. The saved May report remains historical context. No existing power tuning was changed solely from these samples.

Use `playtester_telemetry/fetch_latest_version_analysis.ps1` with explicit `-Version`, `-From`, and `-To`, and a separate output file. `-LocalTelemetryPath` reads detailed local events from a disposable copy of `run_telemetry.save`; `-LocalHistoryPath` reads the smaller JSON history. Keep development and release populations separate. [Analysis instructions](../playtester_telemetry/README.md) cover provenance, missing data and sample limitations.

The main feedback is brief: were the holds intentional, did the powers change your decisions, and which combination felt worth building around? There is no live Oath checklist or performance prompt.

## Verification

- `.github/scripts/run_gameplay_regressions.ps1` passes in a disposable project with suppressed production autoload startup and isolated user data. It includes the existing input, power, Oath, and Catalyst checks plus Ascension, motion, formations, Drifter, Keeper/Breach, boss combinations, launch authority, combat pause, hit origins, attack feedback, and development upload eligibility. All GDScript files compile.
- Focused new coverage: 373 Ascension checks, 172 motion registry checks, 197 motion runtime checks, 65 Blast checks, 547 formation/Undertow checks, 72 Drifter checks, 106 boss combination checks, 29 authority checks, and 17 launch/shade lifecycle checks. The expanded power suite has 536 checks. The workflow tools have 40 checks. The direction regressions reproduce 32 failures in the old controller and pass with the fixed controller; boss combinations and the debug package were rechecked after this fix.
- `.github/scripts/test_playtest_executable.ps1` verifies the exact exported package using Godot: 54 debug startup/loadout checks and 26 normal configuration checks passed. The debug executable also passes a separate headless startup check. Export templates ignore `--script`, so node inspection uses the matching Godot engine with `--main-pack`; normal checks do not enter Menu. Forced shutdown reports retained-resource warnings separately from runtime failures.
- `.github/scripts/render_motion_arcana.ps1 -ValidationProject <isolated-project>` renders eleven actual GPU states with damage/movement assertions. Orange blasts/impacts and violet echoes were visually inspected alongside cyan tethers. The fixture uses process-local synthetic actions, not desktop input.
- `.github/scripts/test_boss_combinations_enet.ps1 -ValidationProject <isolated-project>` runs two hidden localhost Godot processes. Its 28 checks cover real production damage, launch, health, effect, kill-notification, and impulse RPCs, plus Blast geometry, hit flashes, and a firing origin that stays fixed through replicated movement. Both processes also resolve Forsworn rank 2 and Delver rank 0 with conflicting menu preferences; that setup payload uses a fixture RPC.
- The Keeper 1 HP floor follow-up passed scoped isolated checks: 101 Keeper runtime, 181 Keeper/Breach profile, 87 shared damage boundary, 199 combat interaction, 28 combat pause, 64 hit origin, 106 boss combination and 162 glossary readability checks. All 290 GDScript files compiled, and world/network configuration gates passed. The earlier full-suite entries above describe prior checkpoint verification; the follow-up reran these scoped checks. Evidence is in temporary project `abyssal-validation-af47a53c12e542b1b88231b75000feb5`; `keeper-final.log` records the final 101 Keeper checks.
- `.github/scripts/test_keeper_enet.ps1 -ValidationProject <isolated-project>` passed 20 host and 3 client checks with no failures for the follow-up, covering real loopback damage requests, the 1 HP floor, damage/kill ownership and replicated links/breaks. Evidence is in temporary project `abyssal-keeper-enet-abf01b1c20a945f2b120bb6d47995d92`.
- `.github/scripts/render_keeper.ps1` captured five GPU states with no failures on an RTX 4080: warming, active, held at 1 HP, broken and vulnerable. All five were visually inspected. The fixture verifies repeated lethal damage leaves health and credited damage unchanged while protected, then verifies a kill after the link breaks. Frames are in temporary project `abyssal-keeper-render-2c065513054a42c5a1df501bc0c6ec55/keeper_frames`. This task did not export a new build; the running desktop playtest and its executable were preserved.
- The combat review adds 28 pause/lifecycle checks, 62 hit-origin checks and 37 attack-feedback checks. `.github/scripts/test_combat_review_enet.ps1 -ValidationProject <isolated-project>` passes 35 checks using real host/joiner damage, crowded shield replication, dropped-update recovery and attack-indicator RPCs. `.github/scripts/render_attack_feedback.ps1 -ValidationProject <isolated-project>` captures three inspected GPU frames for moving melee, local/remote Razor Wind and the shade's inner boundary.
- Exports are inspected as packages without launching production autoloads. Build IDs match, production autoloads are included, tests/fixtures are excluded, and development update feeds are disabled. Desktop copies are hash-verified.

Human playtesting of feel and the complete lobby/join flow is still needed. The deterministic input and network fixtures cannot judge enjoyment, internet latency, or the full lobby experience.

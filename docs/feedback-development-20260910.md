# Feedback development: Oaths and Build Details

Requested September 10, 2026: develop the first four ordered feedback items. The shared feedback board remains the priority authority. This batch does not select items 5–9.

## Current revision: approachable progression and postgame prestige

The user found the replacement milestones too easy, then clarified that a universal Forsworn requirement goes too far. The latest [Oath progression plan](oath-progression.md) restores meaningful Any-Bearing goals and a character/Bearing ladder alongside Delver+ Challenges and Forsworn Prestige. It supersedes the [earlier postgame design](postgame-oaths.md). The compact menu is retained. Earlier sections and hashes below are historical evidence for their respective builds.

## Earlier follow-up: replace confusing Oaths and compact the menu

After the first playtest, the user requested a modest zoom-out and replacement of Empty Hand, Silent Arcana and Uncrowned rather than more explanation of their reward restrictions. Those three active goals are retired and replaced with:

| Oath | Goal | Catalyst unlock |
|---|---|---|
| Hundredfold | Defeat 100 foes in one run. | Draft Compass |
| Pilgrim's Road | Clear a run after visiting three Rest Sites. | Pilgrim's Tonic |
| Crown Breaker | Defeat the Warden and the Sovereign in one run. | Draft Compass |

Hundredfold uses personal kill totals, including in co-op. Crown Breaker uses the run's shared boss victories. Both achievements remain earned if the run subsequently ends in defeat. Pilgrim's Road requires a clear and at least three recorded Rest visits; normal routes offer a Rest Site before each boss. The new goals have fresh completion IDs. Existing profile migration retains retired completion records, claimed rewards and earned Catalysts without marking the replacement goals complete.

Oath titles, body text, reward labels and group headings are approximately 12% smaller, with slightly tighter card padding. The challenge group is now **Descent Challenges**, and Crown Breaker appears in **Boss Mastery**. Other menu tabs retain their layout.

The sections below retain the initial implementation and build evidence; the follow-up verification and delivery record is appended at the end.

## 1. Clarify oath reward restrictions

`FB-b95e8c04523745b7`: Empty Hand now identifies Boons as stat rewards, explicitly includes Mission rewards, and allows Arcana and boss rewards. Silent Arcana explicitly allows Boons, Mission rewards and boss rewards. Singular Focus explains that upgrades remain the same distinct Arcana and that other reward categories are allowed. Eligibility, stable IDs and existing unlocks are unchanged.

Focused isolated validation passed: 323 GDScript files compiled, world/network contract guards passed, and Oath tracking checks passed, including boss rewards, Mission Boons, distinct Arcana versus upgrades, and the production snapshot restore path. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-e2c035288be644238b9f1ed840a11a52`.

## 2. Add more Oaths

`FB-9a5f7c4e99b44afe`: four additional goals use existing rewards and progression tracking:

| Oath | Requirement | Catalyst unlock |
|---|---|---|
| Uncrowned | Clear without taking any boss rewards; other reward categories are allowed. | Draft Compass |
| Many Paths | Clear with at least five different Arcana; upgrades count as the same Arcana. | Reward Reroll |
| Honed Art | Clear with at least one level 3 or Prismatic Arcana. | Prismatic Arcana |
| Untouched Crowns | Clear after taking no damage in each of the Warden, Sovereign and Lacuna fights; damage elsewhere is allowed. | Calm Before Surge |

New goals require valid recorded evidence, support saved runs and per-player co-op summaries, and retain normal-run eligibility and duplicate-award protection. Uncrowned requires complete reward history so legacy partial runs cannot infer that no boss rewards were taken. Malformed build summaries are handled safely.

Independent review also caught a modern checkpoint with missing or malformed saved boss inventory. Resume now marks its tracking incomplete, and that disqualification survives subsequent saves. Valid inventories are preserved. The final focused Oath run passed 146 checks, compilation of 325 scripts and both contract guards: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-26ce2533a49b4e3088f5d1c1477cd4eb`.

Focused isolated validation passed: 324 scripts compiled, Oath tracking 120 checks, Catalyst profile 89 checks, Catalyst rewards 361 checks, Ascension runtime and world/network contract guards. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-d131845b18274d8c81b8a483bcda05c8`.

Oath cards now use larger text. A GPU fixture opened the production menu and checked all seven new or clarified descriptions at physical 1280×720 and 1920×1080, preserving the production logical canvas. All 14 screenshots were inspected; 361 assertions passed, including wrapping, card bounds, Back access and physical text size. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-429821b896bb469ba3e6625d07d85397/oaths_feedback_frames`.

## 3. Remove the selected offer box

`FB-ba7a8a135ea14b88`: Build Details begins with the character passive and shows owned powers. The selected-offer panel and its exclusive connection explanations are removed. Reward cards retain their numerical previews. Opening and closing Build Details preserves the selected card, available offers, RNG and rerolls; owned powers retain expandable rules and keywords with controller scrolling.

Focused isolated validation passed: 324 scripts compiled, both contract guards, and 421 reward inspection checks. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-baa45f6f972f4c8c84e5358700f30dc9`.

## 4. Simplify character passive descriptions

`FB-1ad60ee5d79b459a`: each character now gets one concise Build Details paragraph. Bastion explains how to Brace, its damage bonus, first-hit Burst/Guard and movement interruptions. Hexweaver explains Dash arming, the next attack hit and the one-Burst limit. Veilstrider keeps the two-shard Dash refresh and timed Burst; Riftlancer keeps the farline damage bonus and penalty. The shared catalogue retains full rules for the glossary, including timing, source exceptions and detailed interactions. Combat mechanics and character-selection copy are unchanged.

Build Details now compensates for the production canvas scaling down on smaller physical windows. Its body text stays at least 17 physical pixels at 1280×720 and 1920×1080, including resizing an already-open panel. Owned-rule scrolling accounts for the panel scale.

Final focused inspection passed 443 checks, compilation of 325 scripts and both contract guards: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-acb8890ce01d4d39b26e2b03f33b03fc`. Related passive runtime (52), power descriptions (435) and glossary (186) checks also passed in `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-5cac635064f24ef6a289e377bf98f8b6`.

Production-canvas GPU review passed 129 checks across 10 inspected frames: all four character summaries and expanded owned rules at both physical sizes, including scrolling, Back and live window resizing. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-836fcef72b084548b050abd0a0297ce4/build_details_cleanup_frames`.

## Verification and delivery

Implementation, automated verification and human playtest acceptance are recorded separately. Completed, verified feedback moves to Awaiting playtest.

Final full isolated suite passed: all 80 gameplay fixtures, compilation of 325 GDScript files and world/network contract guards. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-1b6b34018a84475e832937b2e2517308`. All seven changed gameplay source files were hash-matched against that validation copy. The final rendered fixture additionally verifies live resizing and scaled input; its production-canvas run passed as recorded above.

Normal desktop candidate exported from the uncommitted working source based on `b6b1819`, branch `codex/encounter-evolution-20260910`, using `.github/scripts/export_playtest.ps1` without `-DebugRun`:

- Delivered path: `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe`.
- Internal build ID: `dev-20260910-153924834-3d567a57`.
- SHA256: `C872E07F6DFD7B2BF76619E6EA611331EB375091DB6B04232ABDC20A65079C64`.
- Export/package evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-playtest-export-7d23183e1c5d45bd960985d243597219`.

The package verifier now explicitly rejects local feedback data/tooling as well as gameplay test fixtures. Export staging and the preset both exclude the board. The exported package passed production autoload, build ID, disabled update-feed, exclusion and final-file hash checks.

The normal executable passed 27 embedded-package checks and 62 native lifecycle checks (Menu, first descent, movement, Pause, return and reopen). Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-native-smoke-a379d720b4324d5c9b97eec99bf166d4`. This used a byte-identical temporary executable with isolated data, injected controls, headless rendering and disabled remote services. GPU presentation is covered separately above; ordinary progression and enjoyment await human acceptance. All seven changed gameplay source files were also hash-matched against export staging.

At the initial delivery, all four requested feedback IDs were Awaiting playtest and referenced that build ID. Synergy feedback was then the next available queued item. Later user board actions determine the current order. No later item was claimed by this task. Human acceptance, a commit/push checkpoint and release publication remain separate actions.

The render helper now supports `-PreserveProductionCanvas`: it reads the logical viewport size from the production project while keeping the offscreen, isolated render process. Existing altered-canvas fixtures retain their default behavior as stress checks; production-canvas checks vary physical window size without replacing the game's 2560×1440 logical canvas.

## Oath follow-up verification and delivery

The revised menu passed 361 assertions across 14 inspected GPU captures at physical 1280×720 and 1920×1080 with the production logical canvas. The new cards fit completely, typography is approximately 12% smaller than the first playtest and Back remains accessible. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-b6ca1e954236463db3a39d7fdcd60b90/oaths_feedback_frames`.

Focused isolated verification passed for the follow-up: 325 scripts compiled, both contract guards, Oaths (207 checks), Catalyst profile (89), Catalyst rewards (361), checkpoint lifecycle (175), menu fit/focus (183) and Ascension runtime. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-ef271143d9064f8fa5ff0a77280f09d3`. These checks cover goal thresholds, malformed/missing evidence, debug exclusion, save/resume, personal co-op kill attribution, shared boss milestones and retention of retired completion IDs and earned rewards. An independent source review found no additional issues. The earlier full-suite evidence above belongs to the initial build; this targeted revision uses the affected suites.

Updated normal desktop build from working source based on `b6b1819`:

- Path: `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe`.
- Internal ID: `dev-20260910-155417357-f66c3064`.
- SHA256: `2EE31586F006E2AE8E5D7DFF477BA82B316DFA1BC021D5B661AF796AF87E27D7`.
- Export/package evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-playtest-export-25dda7a6f35d4dddac5313311b592531`.

The package passed production settings/autoload, build ID, update-feed, feedback/tooling exclusion and final-file hash checks. The copied normal executable then passed 27 package checks and 62 native lifecycle checks with isolated user data: `C:/Users/mikel/AppData/Local/Temp/abyssal-native-smoke-d5059f6ae82a4595b19c8429afad2dd6`. The four source files touched by this follow-up match both its validation copy and export staging. The two Oath feedback records reference this build and remain Awaiting playtest; concurrent user changes to other feedback and priority were preserved.

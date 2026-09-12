# Oaths, Razor Orbit and Breakwater feedback

September 12, 2026. The user requested all four feedback entries be recorded and developed. Three new entries were appended in the supplied order; the existing Breakwater identity entry was reopened at the bottom, preserving its feedback history. Each entry has its own claimed task, branch and worktree. The shared checkout contains the integrated changes; existing uncommitted work is preserved against a source manifest.

## Oaths vessel order

Vessel Progression now uses the same unlock chain as clearing runs: Bastion, Hexweaver, Veilstrider, Riftlancer and Effigy Keeper. Each vessel retains Pilgrim, Delver, Harbinger and Forsworn in that order. New goals outside the chain remain visible. Completion IDs and progression data are unchanged.

The focused isolated check passed compilation of 399 scripts, both world/network contracts, Oath tracking (1,014 checks), movement evidence (199) and menu fit/focus (211). Evidence: `.feedback/oaths-orbit-breakwater-20260912/oaths-order-validation.log`.

## Oaths Bearing presentation

Ordinary browsing now shows each goal's actual Bearing requirement and its earned Completed marker. The last run's Bearing and a cached setup cannot produce an amber warning or an availability claim. Explicit run setup can still show whether that selected Bearing matches the goal. This is presentation only: the evaluator, difficulty history and saved completions remain unchanged.

The combined Oaths rendering passed 2,095 checks across 18 native frames at 1280×720 and 1920×1080, using the production canvas. It covers every vessel and Bearing unlocked, prior Delver and other run selections, leaving setup, earned markers, correct vessel order and the existing four goals per vessel. Oath tracking (1,014) and menu fit/focus (211) also passed with the final panel. Evidence: `.feedback/oaths-orbit-breakwater-20260912/oaths-bearing-validation.log` and `oaths-bearing-native-final.log`; native frames in `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-2b3d284669be4e778bfa09ea96e197a9/oaths_feedback_frames`.

## Razor Orbit escape control

The former 0.15-second release carried the player along the tangent while discarding movement input. Release, expiry and anchor loss now start a 0.25-second escape that follows fresh movement input immediately and can be steered throughout. No direction preserves momentum. The closing direction cue previews the chosen escape. Normal collision, vulnerability, manual Attacks, cut damage/cadence, transfer limit and the distinction from Dash are preserved. A fresh available Dash can interrupt the escape.

Seven relevant gameplay suites pass: escape (39 checks), motion (314), Toll's moving path oracle (55), character passives (52), Effigy Keeper (64), arena edges (174), and motion registry (196). The final native controller fixture passes 52 checks across 21 frames at 960/1280/1920 widths. Separate host/client play passes 13/7 checks, including a real accepted 14-damage cut from Damage 40, owner credit, the steered destination and cleared remote tether. The earlier fixture had sent its first shared-damage action before the actual run handshake completed; the corrected fixture waits for that handshake and leaves production authority intact.

Native card/build presentation passes 185 frames across unowned offers, upgrades, Prismatic, four offers and learned details; the two main suites report 992 and 1,525 checks. Power descriptions (465), shared wording, build inspection (467) and reward layout also pass. A measured glossary wrap was fixed with one authored line break. Final combined glossary verification passes 189 headless checks and 12 native frames with 78 checks, including the actual Orbit and Breakwater entries.

Evidence: gameplay `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-3331aeb82a2a462fb23ab5f49d08b6d0`, registry `abyssal-validation-6c75c66fb9f84492b03dea94866f5443`, native `abyssal-gameplay-render-77df71ada2bd433e9c434c184b8d4606/orbit_duration_frames`, and multiplayer `abyssal-enet-2a18356141f948549db386f24991d48e` under the same temporary directory. Retained card/build manifests, source hashes and samples are in `.feedback/oaths-orbit-breakwater-20260912/reward-layout-evidence`.

## Breakwater pressure

Harbor Gate now alternates with the ram/Return Tide sequence. Its shore and player-position openings commit before a 1.2-second warning; the seawall then crosses the arena. Breakwater makes a harmless lateral brace step out of the opening's melee pocket. Hold or return to the opening, then pursue after the crest passes. Terrain bait still cancels Return Tide, and terrain can pin the brace for an earned punish. Health and damage are unchanged.

Forty-eight actual movement pilots compared the previous loop, continuous circling against the new loop, and a response delayed by 0.35 seconds. At base speed, continuous circling took 18 contacts versus the previous 9; at reduced speed, 28 versus 8. The response pilots avoided all 32 Harbor Gates. A close-range Attack pilot dealt 320 free damage against the stationary prototype, 40 against the lateral brace, and 320 when real terrain pinned that brace. These are bounded behavioral comparisons, not a claim about every build's difficulty or enjoyment.

The new suite passes 661 checks; preserved runtime (2,148), encounter (2,397) and combinations (29) pass. Real host/client play passes 38/10 checks, including four openings with a full status payload. Compact gate snapshots keep the warning within the existing state fitter; swept player/crest checks cover fast crossings, and the normal contact source preserves Dash immunity. Eleven matching-source native frames pass.

The real Main scene adds seven frames and 22 checks through the normal Apex door, with the HUD, biome and camera. A player at 45% of Bastion's base speed moves inside the fixed opening and survives the crossing with no Dash immunity; the full 1.1-second recovery follows. Evidence and exact parameters: [Harbor Gate feature record](breakwater-harbor-gate-20260912.md). Retained Main evidence: `.feedback/oaths-orbit-breakwater-20260912/main-harbor-evidence`.

## Integration and normal desktop delivery

All four implementations are integrated. Twenty-one distinct scoped suites passed across component and primary runs. The final combined run compiles all 404 scripts and passes world/network contracts, Orbit escape, Harbor Gate, shared keyword synergies, boss callout parity and glossary readability. The new focused gameplay fixtures are registered in the normal regression runner. Native QA now explicitly captures the two changed glossary entries and Harbor Gate in Main. Source-manifest checks preserve unrelated local work. No commit, push or release tag was requested.

- Normal desktop executable: `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe`.
- Internal build: `dev-20260912-075230449-df7424da`.
- SHA256: `45E71AED7ACECDA441FEDDB4E0CED02A4D6F0D0BD9D1067869141898717C2062`.
- Exported source matches 400 primary GDScript files and 12 Crescent audio assets/imports; the intended BuildInfo stamp is the only excluded script difference. Normal menu/progression, no debug grants.
- The actual exported executable passed 27 package checks and 62 native checks in isolated user data, including menu, movement, return and a second run; no shutdown warnings.
- Combined validation: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-0741c7ae3bc246559c00fba07b926c86`.
- Build staging: `C:/Users/mikel/AppData/Local/Temp/abyssal-playtest-export-3c792d67439d4e24b95c66080bcc28d0/project`.
- Executable evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-native-smoke-a04523d5e7024a7081b35571b3b36c7f`.

All four board entries await human playtest and acceptance. Board priority and the existing feedback history are preserved.

# Playtest feedback refinements

Five entries were appended to the feedback board in the player's supplied order and developed under individual claims, branches and worktrees. Prior feedback changes remain included. Implementation does not imply player acceptance; these entries return to awaiting playtest after verification and normal desktop delivery.

| Feedback | Delivered behavior | Focus for the next playtest |
| --- | --- | --- |
| Crescent boomerang sound | Filtered blade swish, distinct rising return cue and short metallic ricochet; SFX settings and cancellation cover all voices. | Repeated throws and overlapping blades against the soundtrack. |
| Keyword layout and held Tab | One-line leading pair on the HUD; collapsible keyword overview in Details; tap Tab/Y opens and closes. Repeats and releases are consumed before GUI focus navigation. | Click and inspect while holding Tab, release, then close with a fresh press. |
| Biome help/danger visuals | Polarity is part of the affected floor border, with smooth helpful contours and scored danger edges; explicit text explains targets. | Distinguish helpful zones beside boss attacks and dangerous floor at smaller window sizes. |
| Spark Relay payoff | The existing bolt seeks a living reachable foe and redirects after hits or target death within its remaining travel budget. | Lethal Burst triggers and moving crowds; cover still blocks the bolt. |
| Kilnheart identity | Accelerating forge plunge followed by separately warned Crucible Vents, faster pursuit, more health and impact presentation even on a successful dodge. | Pressure, impact and safe wedges; first-encounter readability. |

Implementation and feature evidence: [Crescent audio](crescent-sound-20260911.md), [keyword overview](build-keyword-overview.md), [biome contours](biome-polarity-20260911.md), [Spark Relay](spark-relay-seeking-20260911.md), [Kilnheart](kilnheart-forge-identity-20260911.md). The combined verification and package receipt are recorded below.

Audio mixer and gameplay assertions establish functional behavior. Sound quality, visual preference and balance acceptance remain human playtest decisions. No commit, push or release tag is part of this feedback delivery.

## Combined verification

All 387 GDScript files compile; world-property and multiplayer configuration contracts pass. Nineteen scoped suites pass across Crescent, held-Tab input and keyword counts, reward inspection/layout, Spark Relay and shared damage/lifecycle boundaries, Kilnheart and boss callouts, biome geometry/context and Shatterfield breaks.

The final combined source passed 38 native boss/objective biome frames (424 checks) and 18 ordinary-room frames (259 checks) on an RTX 4080. Inspected helpful annuli beside the new Kilnheart, ordinary sectors and split danger lanes; native keyword and Shatterfield views were also reviewed. Feature-level evidence includes real ENet tests for both changed combat systems, Crescent mixer checks and the reward/upgrade card matrices.

Evidence index: `.feedback/refinements-20260911/verification.json`. Disposable integration projects: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-80359a8567ad4c39aae4af9383bcea0a` and `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-7d0a553d6ea543f7a2102d8a0e5b940b`. Independent source reviews found no actionable input, audio lifecycle or Kilnheart authority/geometry regressions.

## Normal desktop delivery

- Build: `dev-20260911-212017964-9d315f2d`. Normal Menu and progression; debug run disabled.
- File: `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe` (124,341,912 bytes).
- SHA256: `81E7FA21F7CBAEF99D8BC165BC146614086D3B82048FB39680CCC6CDA47DB3E2`. Final desktop file, staged package and tested native copy agree.
- All 384 source scripts match export staging byte-for-byte except the intentionally generated development build ID. No unexpected source changes outside the five refinements and this report were found against the saved batch baseline.
- Export/import/package verification passed. The byte-identical exported executable passed 27 package checks and 62 isolated native checks through Menu, first descent, movement, return and reopen. Native smoke is headless with Dummy audio; GPU and audio-mixer evidence are separate above. The player profile was not used.
- All five feedback entries are awaiting playtest, with their supplied queue order preserved.

Receipts: `.feedback/refinements-20260911/playtest-build.json`, `native-verification.json`, `staging-source-verification.json`, `source-audit.json`, and `board-after.json`.

# Practice sandbox and inspection changes — September 12, 2026

The user requested four changes after the autonomous workday ended:

- Replace Warden Practice with a generic tool for choosing the full build, character, floor and enemies.
- Remove Run History search.
- Make Glossary character passives always use the same concise text as Build Details.
- Remove Power Rules from the Glossary.

This explicit request runs on the existing `codex/uncharted-descent-20260912` branch and does not select or reorder feedback. The previous timed automation remains paused. The incremental baseline is `.feedback/practice-sandbox-20260912/baseline.json`: 1,371 files and 363 existing changed paths at HEAD `d3a82a2ba33a943dc42ebde3fc675b5a9ec25cc9`. Earlier workday source, build and test receipts remain historical and unchanged. No commit or push is requested.

## Implementation scope

Practice opens in configuration before combat. It offers every registered character and combat power, independently of profile unlocks. Its editable loadout uses actual Boon counts, Arcana and boss-reward levels and supported Prismatic upgrades. Encounter configuration selects floor, Bearing, biome and an enemy/boss roster with counts. AI and invulnerability are explicit training options. Editing a draft does not alter the current attempt; Start or Apply & Restart builds fresh actors from the complete configuration. Pause, Resume, damage recap and Menu return preserve their actual behavior.

Practice uses normal registries and application paths, including supported combat modifiers. Floor follows actual depth/act semantics; it must not invent an enemy-stat multiplier that normal play does not use. Options that affect only reward or route generation must not advertise a working effect in an arena without those systems. Saved descent, character selection, progression, History and submission queues remain untouched.

Run History retains outcome and solo/co-op filters, its recorded build journey and damage recap. Its text input and text-matching implementation are removed. Passive copy comes from one shared canonical function for Build Details and Glossary; mechanics and compatibility metadata remain unchanged. The Glossary retains keyword definitions and other reference sections while removing the entire Power Rules category.

## Focused verification

All unattended engine runs use the disposable-project helpers and isolated profiles. Focused checks cover history selection/persistence, passive-text equality and glossary absence, Practice configuration and real combat/lifecycle behavior. Practice setup, controls and summaries are rendered and inspected at representative physical window sizes. Final integration and delivery results appear below.

Evidence for this request is stored under `.feedback/practice-sandbox-20260912/` rather than replacing earlier receipts.

- Run History removal passes 26 focused checks, 454-script compilation and both guards. Native Menu History passes 101 checks across eight captures at actual 960×540 and 1280×720, with representative populated, journey, empty and damage states visually inspected. Logs, image hashes and exact dimensions are retained in `history-evidence/`.
- Glossary simplification passes eight focused suites and 4,012 checks, 457-script compilation and both guards. Twenty-one native frames pass 135 checks at 960×540, 1280×720 and 1920×1080; Menu/Pause passive text and keyword typography were inspected, including a separate root review of both 960-pixel passive views. Exact source and verification receipts are in `glossary-simplification/`. The first snapshot's in-flight Practice editor parse failure is preserved separately; the final glossary increment is clean. The shared-passive and no-Power-Rules authoring rule is also recorded in `AGENTS.md`.
- The external native executable probe drives initial Practice setup, all-character availability on an unmodified fresh profile, real keyboard build/roster/floor controls, Resume preserving the current attempt, and atomic Apply/restart.
- Separate full-suite and normal-export receipt helpers preserve earlier receipts, capture current input hashes and do not reuse the prior build as evidence for this changed source.

## Final integration

Practice runtime validation passes seven focused suites and 1,504 assertions: the new sandbox (904), existing lifecycle (108), accepted-damage recap (76), Vessel/Continue isolation (324), actual Warden combat (37), Launch authority (29) and Ruinous feedback (26). All 459 scripts and both guards pass. The live combat fixture records 598 frames, 525 damage dealt and defeat after 130 HP lost. It is separate from the executable's explicitly scripted incoming-damage checks. Runtime receipts and source hashes are in `runtime-final-result.json` and `runtime-final-source-manifest.json`.

The final UI editor pass covers 272 Menu/UI checks, 974 recap checks and 2,424 editor checks, including level-aware descriptions, Prismatic copy, effect search and preserved keyboard focus. All 100 final native captures were individually inspected at 960×540, 1280×720 and 1920×1080: full configuration passes 314 checks/43 frames, real Menu and default attempt passes 272 checks/37 frames, and the six-event recap passes 536 checks/20 frames. This totals 1,122 native checks. Root independently inspected the final 960-pixel roster and Arcana views and the 1280-pixel applied encounter. `ui-final-result.json` records matching owned source hashes, with all images, raw logs and manifests retained in `ui-evidence/`. Earlier input-driver and temporary encoding failures are retained separately and are not counted as passing evidence.

The normal desktop executable is updated to `dev-20260912-191828105-bd4f09ae`, 124,566,936 bytes, SHA-256 `9AD3A5C3461DAC58FCDEDD0E289FCCC18F6F1D0087CE27547156F0E571179F12`. Package verification passes 27 checks; the actual copied executable passes 145 native checks through full Practice configuration, Resume, Apply, restart, normal Menu/Main movement and return/reopen. The exported, delivered and tested executable hashes agree. The artifact receipt is `normal-build-sandbox-receipt.json` with 14 retained raw logs/results. Normal saves and setup remain byte-identical across Practice; the native profile and service settings are isolated.

The full gate passes all **135 registered checks**, with zero failures, missing checks, strict log issues or snapshot hash changes. It captured 1,093 inputs in immutable snapshot `abyssal-validation-1b3604acec0343a3ba7ffda153ede487`. `full-sandbox-result.json` retains each result and the hashes of copied console and raw engine logs. All originally captured inputs remain unchanged. One unreferenced editor `.gd.uid` companion was copied from the passing UI import after capture; the full-suite and export imports had independently generated different UIDs. This is the one recorded working-tree input addition. `editor-uid-supplement.json` records all three values and hashes and confirms that authored code/scenes reference none of them. No gameplay code or scene changed after capture; this metadata exception is explicit rather than rewriting earlier receipts.

The independent preservation audit found no removed baseline files or changes outside the requested features and their verification/documentation. `incremental-source-receipt.json`, `incremental-changes.patch` and `final-source/` preserve this request's increment against its original baseline, including the earlier dirty work. All four requested changes are implemented and verified; the normal desktop build is delivered. No commit, push, release tag or feedback-queue change was made for this request.

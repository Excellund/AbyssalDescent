# Practice encounter selection — September 13, 2026

The user requested encounter selection in place of individual enemy selection, and removal of Recent damage from Practice. Work stays on `codex/uncharted-descent-20260912`; the feedback queue is unchanged.

The new incremental baseline is `.feedback/practice-encounters-20260913/baseline.json`, with 1,383 files and 380 existing dirty paths at HEAD `d3a82a2ba33a943dc42ebde3fc675b5a9ec25cc9`. Earlier work and receipts remain intact, including the main-menu subtitle removal and unrelated changes made since the previous delivery.

## Implementation

Practice offers 37 named choices: Skirmish and 11 formations, seven Trial variants, four Apex encounters, seven Missions, six bosses and an empty training arena. The selected floor, Bearing and biome feed the real encounter generation and objective systems. Full builds, all Vessels, training controls and separate draft/current-attempt behavior remain available.

Trials select their actual mutator before roster generation. Missions retain their objectives, overlays, timed spawns and completion rules; clearing an initial wave cannot finish a pending encounter. Practice shows live Mission progress and changing Pulse Window/Signal rules. Restart repeats the encounter profile and retires the previous actors, waves and effects without granting a completion reward or changing progression.

Recent damage is removed from Practice's setup, pause and results interface and from its attempt-state recording. The obsolete Practice-recap-only fixtures/helper are retired; normal-run recap code, tests and History remain in place. The configuration editor has three tabs: Encounter, Build and Options.

The native executable driver now selects Crossfire through the actual encounter control, retains full-build/Resume/Apply/restart/save-isolation checks, and expects no Practice recap data or fourth tab.

## Verification and delivery

All checks use disposable projects and isolated user data. Evidence is retained under `.feedback/practice-encounters-20260913/`; earlier receipts remain unchanged.

- Runtime: 459 scripts compile, both source guards pass, and five focused suites pass 2,605 assertions (sandbox 2,071; core 108; Vessels 324; live Warden combat 34; normal-run damage recap 68). Every encounter choice and all seven Mission completion conditions are covered. `runtime-final-result.json` records matching source hashes and copied raw evidence.
- UI verification: 2,215 assertions pass across the menu/panel and full configuration editor, including long active and paused Mission rules. This scoped receipt precedes only the final popup-width limit and its explanatory comment. The final native editor run validates that exact correction: 46 frames and 281 passing assertions, including real scrolling to Relic Recovery and a real-time Pulse rule transition. The unchanged menu/Practice lifecycle has a separate 37-frame, 272-assertion native receipt.
- The 37-item popup now has positive maximum dimensions on both axes, keeping it within the viewport and letting keyboard selection scroll the list. A tiny native A/B test confirmed that a zero maximum width made Godot reject the height limit once the popup had a positive minimum width. The diagnostic and earlier unsuccessful checks remain preserved.
- Final actual-executable verification: 27 package checks and 144 native smoke assertions pass, including keyboard selection of Crossfire, configured builds, Resume, Apply/restart, profile preservation and normal descent startup/return. The copied executable uses isolated user data and a separate external input driver. Native rendering above checks presentation; the executable smoke uses headless rendering.

## Delivered normal playtest

The canonical `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe` was replaced using `.github/scripts/export_playtest.ps1` without `-DebugRun`:

- Build: `dev-20260912-224519382-cf712c09`
- Size: 124,575,536 bytes
- SHA256: `1F284BF2D0DB8384878186F2F98EDDE9F4E132FC24B4B25C6F9F2F1B72F7FA64`

`export-final-result.json`, `native-executable-final-result.json` and the final source manifest identify this exact artifact. The earlier export/native receipts are preliminary and are superseded by this build. No commit, push or feedback-board status change was made for this request.

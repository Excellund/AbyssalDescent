# Feedback and Oaths checkpoint — September 10, 2026

The user requested commit, push, merge into main and tag after accepting the revised Oaths progression and its final polish. This checkpoint includes the ordered local feedback board, the first four feedback items (Oaths and Build Details), the approachable-to-prestige Oath ladder, Ascension-only Unassisted and removal of the Selected Bearing box. Existing committed workday changes on the source branch are included by ancestry.

The checkpoint was prepared on `codex/feedback-oaths-checkpoint-20260910` from `b6b181937db95c8424ec8410682ad1ffb55bf048`. Separate uncommitted reroll/held-Tab fixes and workday feedback-triage edits were excluded and preserved in the primary checkout. The five independently developing feature worktrees were not merged. Feedback data stays local and ignored; only tooling is committed. Explicit parallel claims are supported without changing ordinary sequential selection.

## Verification

- All 39 isolated Python board tests passed, including concurrency, recovery and worktree storage resolution. Earlier browser and launcher verification is recorded in the [board guide](../tools/feedback-board/README.md).
- Oath production files are unchanged from the final focused and GPU-verified revision: 921 Oath checks; ten GPU captures at 1280×720 and 1920×1080, with 1,354 assertions. See [Oath progression](oath-progression.md). Build Details presentation evidence remains in the [implementation record](feedback-development-20260910.md).
- The installed commit hook runs the full isolated gameplay suite, compilation, contract checks and debug-default checks against this exact candidate before allowing its commit. The hosted gameplay workflow repeats the complete suite for the pushed source and release tag.
- The normal exporter passed package checks, including explicit exclusion of tests, fixtures and feedback data/tooling. Exported production GDScript was hash-matched against the isolated checkpoint, apart from its intentional BuildInfo version stamp.
- A byte-identical temporary executable passed 27 package checks and 62 native lifecycle checks using isolated user data: normal menu, first descent, movement, return and reopening.

## Normal desktop delivery

- File: `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe`.
- Internal build ID: `dev-20260910-181445279-ea9161d6`.
- SHA256: `DB170CA6E12EB65C80C4D40F99F1FE57095DC118A66C1E5AB68AB1F66B16B15F`.
- Export evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-playtest-export-b784e3441b6a4d109d813636c87e6abd`.
- Native evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-native-smoke-65c211afb77f44bf874bbdf30e780a61`.

The expected next release tag is `v0.6.4`, subject to verifying it remains unused before publication. The tag workflow builds a normal public release after its gameplay gate; the desktop development build stays separate from public update, leaderboard and telemetry services. The final task report records the actual published commit/tag and workflow result.

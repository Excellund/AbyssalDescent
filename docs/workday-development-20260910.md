# Workday development — September 10, 2026

## Authorization and deadline

The user accepted the previous checkpoint, requested its merge and release, then authorized continued development on a new branch while at work until **15:00 Europe/Copenhagen / 13:00 UTC today**. The accepted baseline is public **v0.6.3**, commit `922a4b576165f6af8477f69bc4c41a48f64916b1`; its release export and main regression workflow passed.

Branch: `codex/encounter-evolution-20260910`, created from that clean baseline. Keep `main` and release tags at the accepted version. Useful game improvements, bounded additions and code cleanup remain authorized. Stop adding features at **13:30 local**; reserve the remaining time for fixes, verification and delivery. Do not use the entire time box as a reason to add weak or unverified scope.

The existing task continuation `descent-identity-development-until-06-00` has been updated for this workday: every 20 minutes until 13:00 UTC. Resume current conversation, Git and agent state rather than restarting work. Pause it at final delivery or the deadline.

## Current milestone

**Encounter decisions and feedback.** Shatterfield Crossfire keeps its existing original/mirrored four-column formations, but the two inner columns become cracked cover. Three separate deliberate Attack contacts break a cracked column, opening a crossing lane while removing that shelter from archers. The two outer columns remain solid. This is a bounded design hypothesis to playtest, not a balance conclusion drawn from telemetry.

- Existing melee, charged Blast and the same Attack's Razor Wind geometry can contact cover; a given action contacts a given column at most once. Fields, echoes, returning blades, other descendants, enemy damage and ordinary movement do not break it. Cover never counts as a damaged enemy, successful enemy hit, kill or resource generator.
- Untouched cracked cover looks different from solid cover, further cracks and three small marks show remaining contacts, and sparse flat rubble leaves an obvious open center after destruction. A short existing room-entry subtitle explains the action. Geometry, marks and visual feedback must agree.
- Host authority owns contacts and broadcasts consistent state, rejecting stale run/room updates and duplicate actions. Destruction removes the collider, Orbit anchor and spawn exclusion together. Existing saved profiles without the new optional metadata stay solid; Continue preserves offered profile metadata through the existing between-room checkpoint.
- Acceptance: both formations preserve their four initial radius-28 columns; only the inner two break after exactly three eligible actions; all direct shape variants, non-eligible descendants and action limits behave correctly; opened lanes work physically and on both ENet peers; room/retry/Continue clear or restore the appropriate state; actual camera captures distinguish intact, damaged and open cover. Human playtest must establish whether shelter versus space is an interesting choice.

Supporting correction: Pulse Window currently hides the active rule and duration after its banner, and replicas omit the modifier needed by the HUD. Carry that existing state through the HUD and sync contract, show the rule and remaining active time, and return to the next-pulse countdown on expiry. Preserve all host pulse timing, roster selection and mechanics; client countdown is presentation only and respects combat pause/grace.

**Independent tooling increment:** extend normal exported-build validation to exercise native startup and menu flow in isolation. An inert export from the exact Godot release template proved that an adjacent `override.cfg` can add an external test controller and configure isolated user data before autoload startup while keeping the executable byte-identical. The real smoke will accept only a preflight-verified normal `dev-*` build, disable all service endpoints/credentials, use a unique temporary copy and retain the packaged Menu/Main and disabled debug settings. The existing package probe stays available. Report the external driver and configuration overrides explicitly; this does not prove internet co-op or human enjoyment.

## Ownership

- `encounter_opportunities`: cover controller, player action integration, world authority/replication, anchor cleanup and behavioral/network tests.
- `buildcraft_opportunities`: Pulse Window manager/HUD/coordinator correction and focused behavioral/rendered verification.
- `pipeline_audit`: optional normal native executable smoke and its external fixture/preflight.
- Root: authored cover metadata, renderer and GPU fixture, Pulse Window world HUD forwarding, documentation, independent review coordination and delivery.

Agents do not commit independently. Coordinate shared file ownership. Run all automation in disposable project copies with isolated user data through existing helpers. Preserve combat wording, established controls/visual style, save compatibility and host authority. Keep development telemetry and leaderboards local.

## Delivery

Use scoped checks while iterating, applicable actual rendered/network evidence, and the full required suite at coherent checkpoints. Commit and non-force push the development branch. Deliver a normal build through `.github/scripts/export_playtest.ps1` without `-DebugRun` to the single `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe`; verify package configuration, source identity and final hash. Avoid replacing an actively played build for intermediate experiments. Record what was implemented and verified separately from human acceptance.

## Progress

- 07:44 local: new branch created; continuation updated; three independent opportunity audits running. Root is reviewing run/menu persistence and updating the accepted baseline in the development plan.
- Scope selected: brittle inner cover in Shatterfield Crossfire and the reproduced missing Pulse Window display, with native normal-build validation as the independent tooling increment. Implementation is underway; the desktop build remains the accepted prior checkpoint.
- Cover implementation passes 99 focused checks after full script compilation and world/network guards. Actual Main instances cover all four characters, three contacts and real collision gaps, melee/Wind/Blast, stale actions and duplicate suppression, no enemy-hit resources or stats, saved-profile immutability, legacy solid cover, Orbit detach and next-room state. Review caught and fixed immediate group removal before detach and stale-run pending-state replacement.
- Root inspected all 11 cover GPU frames (81 checks): both formations at all four contact states, intact/damaged cover amid party effects, and 960px intact/open views. Separate arrays keep rubble out of physics/spawn exclusions. A subsequent renderer guard exactly matches the controller's integer-three metadata requirement without changing valid rendered states.
- Pulse checks cover actual host state, replica countdown and expiry, legacy payloads, Pause/Build layering and HUD reuse. GPU review passes six frames/21 checks at 960 and 1280; it also fixed the status card retaining empty height after the active rule expires.
- Native normal-executable validation passes 62 native checks plus the existing 27 package checks on the accepted prior development artifact. It uses injected Enter/Escape input and movement actions, keeps the executable hash unchanged, and exercises normal first-launch prompts, tutorial and a second Main instance. The initial test expected depth one; normal tutorial correctly begins at zero. Explicit final scene/audio/cache retirement produces no shutdown leak warnings. Public/debug rejection, changed-copy/sidecar rejection, isolated preflight failures and PowerShell 5.1 parsing have separate bounded guard evidence. The candidate export must receive its own native run before delivery.
- Final dedicated ENet passes 90 host/93 client checks, including fresh-sequence invalid requests, wrong-run state, both owners' real concurrent Attacks plus replays, joining-player destruction, Orbit release, old solid layouts, next-room reset and actual Pulse RPC/pause/expiry. Final scoped Pulse/pause checks pass 64/28 assertions with all 308 scripts compiling. Independent authority, metadata, rendering and Pulse reviews have no actionable findings. Existing client input ownership remains; this is not a new anti-cheat architecture.

## Verification and handoff

The first bounded implementation is committed and pushed as `87c96346e4e98c6a105c8201ee0c093697595a85`. Its required pre-commit suite passed all 308 scripts and 73 gameplay fixtures, and [hosted CI passed](https://github.com/Excellund/AbyssalDescent/actions/runs/34443642073). The normal candidate export passed package inspection and 62 native startup/menu checks. No replacement desktop build has been delivered yet; preserve the accepted desktop build until final workday delivery.

- Full checkpoint suite: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-ddb23ac82aad4ede995b69d209adc7f3`.
- Normal candidate: `C:/Users/mikel/AppData/Local/Temp/abyssal-workday-candidate-12452527e2764282b74426795c97215a/AbyssalDescent.exe`.
- Candidate build ID: `dev-20260910-060049822-bbca5fdc`; SHA256: `AF9013F34525248DE51489B1645EFF2CB0E08B99A82242FF1BE5667112DF153D`; 114243600 bytes.
- Candidate native report: `C:/Users/mikel/AppData/Local/Temp/abyssal-native-smoke-c9e11b10549f40b58310ae38bc253cc1/report.json`.
- Source identity: 520 of 522 production files match exactly; independently checked the two expected exporter overrides (development build ID and Main debug disabled). Details retained in candidate `source-identity.json`.

- Cover native: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-0907d81aaa5a45f986b04dbedc48d14c`.
- Cover GPU: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-f1d88009a52148718df0ebe602d07a8a/brittle_cover_frames`.
- Pulse GPU: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-6e0716c88c854d50a90221372a52a697/pulse_hud_frames`.
- Final Pulse/pause scoped run: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-71619527334e462eb1d1d72ac5e9a92e`.
- Dedicated real ENet: `C:/Users/mikel/AppData/Local/Temp/abyssal-enet-54c2190fec23490a810105c1389a519f`.
- Native normal executable proof on prior accepted dev build: `C:/Users/mikel/AppData/Local/Temp/abyssal-native-smoke-523c4956b56f464baff028dbd81a705d/report.json`.
- Native guard proof: `C:/Users/mikel/AppData/Local/Temp/abyssal-native-guard-tests-7eff6138eafe4f7cbd6c959d5da0d6ea/`.

Remaining human questions: whether preserving shelter versus opening a lane is useful with ordinarily earned builds, whether the cracked-cover action is discoverable, and whether the Pulse Window rule is readable during a live fight. Local staged ENet and automated tutorial flow do not establish full internet-lobby play or balance.

## Second milestone — Continue reliability

The current checkpoint writer truncates the live save before checking whether replacement succeeded. Menu and world callers also ignore write/clear failure and can silently enter a fresh descent after a failed resume. Improve this bounded active-run store and its callers; other profile/history/settings stores remain outside this milestone.

- Prepare and reopen-verify a candidate and recovery record before replacing primary contents. Recover only an existing, demonstrably invalid primary. A valid primary wins; unreadable/future-format records are preserved. An absent primary is authoritative clear, because older release builds delete only that file. Temporary files never resume. Retire recovery after successful publish/read; never truncate the sole valid recovery copy while preparing another write.
- Keep the version-one envelope and existing normal/debug filenames. Clear succeeds only when the primary is absent or a checked cleared record prevents resuming. Check each operation's result and distinguish missing, invalid, unsupported and I/O failures.
- Menu revalidates Resume at activation and gates new runs on successful clear; errors offer Retry and an explicit error-only Discard saved descent action. A failed resume during Main boot returns to this error state without starting a tutorial or fresh run. No automatic discard of invalid saves.
- Failed voluntary Abandon/Retry/results-menu actions keep the current screen and state. Natural death/victory still finalize once, with a visible storage notice; departure retries clear. Failed doorway saves show a progress warning without promising an earlier checkpoint exists. Co-op callers never touch the suspended solo checkpoint or its resume request.
- `encounter_opportunities` owns the store/delegation and file-failure tests; `buildcraft_opportunities` owns menu/error UI and acceptance; `pipeline_audit` reviewed the protocol and owns lifecycle failure tests; root owns world gating, pause/results notice UI, rendered verification and documentation. Only root registers the new fixtures in the central runner and commits.

This is checked interrupted-write recovery, not an atomic replacement or a hardware power-loss guarantee. Godot 4.6.2's Windows rename removes an existing destination first and its flush uses `fflush`; the implementation therefore verifies reopened contents and retains the primary directory entry. Missing-primary recovery would be incompatible with an older build's deliberate clear. Switching to an older build between an unresolved recovery-cleanup failure and that build's own interrupted new save remains ambiguous; do not claim universal cross-version crash recovery.

Second-milestone implementation is frozen for its full checkpoint check. Independent review found and fixed a sole-backup hazard: unreadable/unsupported recovery now blocks overwrite, and an already-resolved sole recovery is never reread or rewritten during preparation. Review has no remaining findings. UI review also fixed menu actions extending below the viewport, centered Pause resizing during an active entrance animation, and Victory's Escape route opening Pause around result clear gating.

- Store: 72 checks, all 314 scripts and property/network guards pass in `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-d9ef6d6e615544fab0786d9178f1e98e`.
- Menu: 68 new checks plus 183 existing layout/focus checks; `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-d349d0e41561426db2d74e0512cead54`.
- Lifecycle: 159 checks, including actual caller signals, failed doorway save and later recovery, paused Abandon, retry setup ordering, terminal outcomes, failed boot and co-op isolation; `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-c1b0909342a740b2b30e881db334fbdc`.
- Menu GPU: root and owner inspected both 960/1280 error frames and every action, including Exit, fits; `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-3eb2446da7de402b8695dcbf34066507/checkpoint_menu_frames`.
- Pause/results GPU: root inspected all eight frames, 98 checks, 960/1280; notice remains outside scroll content and all actions fit; `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-4782a007421b4d25a1de70a69f48bf1a/checkpoint_notice_frames`.
- All three new behavioral fixtures are registered in the full runner. The low-level fixtures inject failures at file-operation boundaries in disposable profiles; rendered UI states are staged. They do not simulate physical hardware power failure.
- Full-suite integration exposed two old independent-run fixtures relying on silent deletion of their deliberately partial doorway records (`test_room_layout_entry` and `test_brittle_cover`). Both now clear those isolated codec records before starting the next fresh run. Scoped compilation/guards and both corrected fixtures pass in `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-4dd2015e4eac44adb664a9b402b5fda7`. The first stalled fixture and interrupted rerun were stopped only by their verified temporary project/process identities; no player process was touched. A bounded regression-process timeout is a concrete follow-on pipeline fix.

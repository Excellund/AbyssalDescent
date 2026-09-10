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

The first bounded implementation is frozen for checkpoint verification. No replacement desktop build has been delivered yet. Run the full suite through the commit hook, push this branch and verify its hosted run, then verify a normal candidate export including the new native smoke. Later work should start from that coherent checkpoint.

- Cover native: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-0907d81aaa5a45f986b04dbedc48d14c`.
- Cover GPU: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-f1d88009a52148718df0ebe602d07a8a/brittle_cover_frames`.
- Pulse GPU: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-6e0716c88c854d50a90221372a52a697/pulse_hud_frames`.
- Final Pulse/pause scoped run: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-71619527334e462eb1d1d72ac5e9a92e`.
- Dedicated real ENet: `C:/Users/mikel/AppData/Local/Temp/abyssal-enet-54c2190fec23490a810105c1389a519f`.
- Native normal executable proof on prior accepted dev build: `C:/Users/mikel/AppData/Local/Temp/abyssal-native-smoke-523c4956b56f464baff028dbd81a705d/report.json`.
- Native guard proof: `C:/Users/mikel/AppData/Local/Temp/abyssal-native-guard-tests-7eff6138eafe4f7cbd6c959d5da0d6ea/`.

Remaining human questions: whether preserving shelter versus opening a lane is useful with ordinarily earned builds, whether the cracked-cover action is discoverable, and whether the Pulse Window rule is readable during a live fight. Local staged ENet and automated tutorial flow do not establish full internet-lobby play or balance.

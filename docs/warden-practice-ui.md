# Practice presentation

The current **Practice** interface is the configurable sandbox described in the [Practice guide](practice-sandbox.md). Its setup screen provides Encounter, Build and Options tabs, with fixed Start, Apply & restart, Resume and Menu controls. The active sidebar shows the current Vessel, chosen encounter, objective progress and current Mission instructions. The encounter dropdown scrolls within the physical window. The UI uses physical text sizing under the production canvas at 960×540, 1280×720 and 1920×1080.

Current sources are `scripts/ui/practice/practice_panel.gd` and `practice_config_editor.gd`. The editor emits detached configuration requests; the runtime validates and commits them only when starting a fresh attempt. Power copy follows selected levels and Prismatic state without replacing focused controls. The [encounter Practice worklog](practice-encounters-worklog-20260913.md) records current verification.

## Historical Warden-only interface

The following description and receipts document the earlier Warden-only version. They remain historical evidence and do not describe the current setup or its acceptance status.

The normal menu places **Warden Practice** before Multiplayer and explains that it is a base-Bastion drill with no progression or saved-descent changes. The existing brand panel and action order remain; the action column uses 18-pixel text and scrolls on shorter windows. Keyboard focus brings each existing action into view. Options and Glossary hide the enlarged main actions while open.

Entry is unavailable while the menu is hosting or joining, while a real transport or party metadata exists, or while the current RunContext still describes a party. The deferred scene transition rechecks availability. The menu passes only a detached return token containing its checkpoint retry action, error text, discard visibility and focus preference. Practice does not enter the normal Begin, character-selection or Bearing-selection callbacks.

`scripts/ui/practice/practice_panel.gd` presents the arena's snapshots and emits Pause, Resume, Retry and Menu requests. The runtime owns combat and lifecycle. Active play keeps keyboard focus away from the Pause button so Space remains Dash; Escape pauses. Paused play focuses Resume, results focus Retry, and initialization failure focuses Menu. Hidden actions reject stale callbacks. UI layout callbacks stop when the scene leaves the tree.

The right status sidebar shows actual Bastion and Warden health, the attempt number and the no-progression notice. Pause and results repeat the isolation promise. It uses the shared local scaled-font helper and physical sizing under the production 2560×1440 canvas. `get_gameplay_rect()` gives the runtime the logical viewport area left of the sidebar and above the control hint; a change signal allows the Practice camera to fit the complete arena after layout and resize. The sidebar preserves more arena height and larger actors than a full-width top HUD.

## Verification

Run the focused interface checks in a disposable copy:

```powershell
& .github/scripts/run_gameplay_regressions.ps1 -TestScripts @(
    'res://scripts/tests/test_practice_menu_ui.gd',
    'res://scripts/tests/test_checkpoint_menu.gd',
    'res://scripts/tests/test_menu_panel_fit.gd',
    'res://scripts/tests/test_enemy_field_guide.gd'
)
```

The native wrapper takes the resulting isolated validation project:

```powershell
& .github/scripts/render_warden_practice.ps1 -ValidationProject '<disposable validation project>'
```

The native fixture uses the actual normal Menu, standalone Practice and reconstructed Menu with production canvas stretch at 960×540, 1280×720 and 1920×1080. It records normal and Continue entry, then deliberately corrupts only its isolated checkpoint and presses the actual Resume action. Native keyboard events enter Practice, pause, resume, retry and return to the same error controls. File and in-memory snapshots verify that the round trip preserves the checkpoint, selected profile, loadouts, History, progression and pending submissions.

Terminal health and the three selected Warden warning phases are explicitly staged for visual inspection. The separate [Practice live-combat fixture](warden-practice.md) exercises ordinary controls against active, unmodified attacks. Native visual receipts are functional and presentation evidence; they do not replace human playtest acceptance.

## Earlier receipts retained

- The first interface pass found an initially unmeasured wrapped dialog and then exposed the real idle `OfflineMultiplayerPeer` guard issue. The current dialog refits after its minimum size settles; the manager distinguishes an offline peer from an actual transport. The error logs remain available.
- The first native launch was rejected for an inferred fixture variable type. Its corrected run produced 27 frames and 226 passing checks in `abyssal-gameplay-render-c9a866fda122437eaf86f37902e8297c`. Those images prompted the compact HUD and camera framing follow-up; they are not the final framing receipt.
- Before that framing follow-up, 143 interface checks, 72 checkpoint-menu checks, 211 existing menu-fit checks and 260 guide checks passed with 446-script compilation and source guards in `abyssal-validation-30a8aabaaaaa47e0bb5b2a65e595acbc`. The checkpoint fixture now proves every action is fully reachable by focus scrolling instead of requiring the entire list to be visible at once; all original Resume and storage assertions remain.
- The first complete-arena render produced 34 frames and passed 250 of 251 checks in `abyssal-gameplay-render-8a5e866897f0429884f9618ca0e56d73`. At 960 pixels, native focus scrolling left Exit one pixel below the scroll viewport. A retained diagnostic measured the button ending at 463 against a viewport ending at 462. The menu now rounds the remaining scroll distance upward, and the unchanged native containment check passes. Inspection also showed that the full-width HUD unnecessarily reduced actor size; the final sidebar reserves the arena's full available height.

## Historical sidebar receipt — 2026-09-12

- `abyssal-validation-6f2a2d5ceff3458fa6ec4dc75b5ea9a5`: 446 scripts compile, both source guards pass, and all 233 interface checks pass. This includes complete sidebar text, gameplay-area separation, modal geometry, stale actions, party guards, keyboard focus and menu return. The preceding menu-only correction also passed all 72 checkpoint-menu and 211 existing menu-fit checks in `abyssal-validation-1bf7679385a846a7ae71ece351ca4688`.
- `abyssal-gameplay-render-729b544c81fb47f9a2f0f1e5c1c69e83`: 34 native frames and 251 checks pass on the NVIDIA GeForce RTX 4080. Every frame was visually inspected: all three window sizes, normal/Continue/checkpoint-error menus, focused Exit after scrolling, active/paused/retried/victory/defeat states, restored menu focus, and the three actual Warden warning renderers at 960. The full arena stays inside the clear gameplay area through entry, resize and Retry. Body text and health values remain 18 physical pixels.
- The final 240-pixel sidebar preserves readable base-Bastion/no-progression/saved-descent copy while leaving the full arena visible. The three warning frames explicitly stage selection, actor positions and windup timing; terminal states explicitly stage accepted damage. The real input lifecycle and persistence assertions still execute through actual Menu and Practice scenes.
- Retained evidence is under `.feedback/uncharted-descent-20260912/warden-practice-ui/`: all PNGs, original render manifest, raw native/headless logs, and `source-and-frame-receipt.json`. All listed production sources, renderer, wrapper and existing menu fixtures match both passing snapshots. The final sidebar-only assertions in `test_practice_menu_ui.gd` were added after the native copy and match the final headless snapshot. The raw logs contain the helper's known Windows certificate-store diagnostic; there are no script, parse, ObjectDB or resource-retirement diagnostics.

These receipts completed the earlier interface's verification. Current sandbox verification, normal build delivery and human playtest acceptance are separate.

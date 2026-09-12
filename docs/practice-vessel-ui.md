# Practice configuration UI

The current interface is described in the [Practice guide](practice-sandbox.md). All Vessels are available in Practice. Encounter, Build and Options tabs edit a detached setup; Start or Apply & restart creates the chosen encounter and full build together. Resume preserves the current attempt. There is no manual enemy roster or Recent damage tab.

The retained `test_practice_vessel_ui.gd` and `render_practice_vessels.gd` names now cover the full encounter/build editor. The final editor native run passes 281 assertions across 46 inspected frames, including contained popup scrolling and a real Pulse transition. Current receipts and exact source-scope notes live under `.feedback/practice-encounters-20260913/ui-final-result.json`; see the Practice guide for the combined verification.

## Historical Vessel selector prototype — 12 September 2026

The following account and receipts describe the earlier isolated prototype, including its unlock restrictions and now-removed Practice recap. They are historical evidence, not current interface instructions.

The Pause and result panels offer a **Next attempt** selector containing only Vessels already unlocked in the current profile. Practice still starts as base Bastion. Changing the selector keeps the current actor and attempt intact; Resume keeps both the actor and the pending choice. Retry starts a fresh attempt with that choice and clears the prior damage recap. Leaving Practice discards its choice without changing the normal menu's selected Vessel or saved descent.

The selector shares the existing modal with the complete six-row recap and fixed Resume, Retry and Menu actions. Its text and popup use the existing local font treatment at 18 physical pixels. Longer current Vessel/HP labels use two lines inside the existing status sidebar; the sidebar and gameplay rectangle keep their original dimensions. Active combat has no focused selector that could consume Attack or Dash input.

Keyboard focus starts on Resume when paused and Retry after a result. Tab follows Resume, Retry and Menu before reaching the selector. Enter opens the choices; Up/Down and Enter choose the next Vessel. Escape closes an open dropdown before a subsequent Escape resumes combat. Repeated presentation updates preserve selector items, open popup state and keyboard focus.

## Verification scope

`test_practice_vessel_ui.gd` checks all five names and provider selections in paused/victory/defeat modes with six rows at 960×540, 1280×720 and 1920×1080. It checks physical text sizes, complete line bounds, unchanged gameplay/sidebar geometry, pending/current identity, stale requests, immutable provider data, repeated refresh and the single-unlocked-Vessel case.

`render_practice_vessels.gd` uses the actual Practice runtime and native keyboard controls. It deliberately unlocks the five existing Vessels in isolated fixture data before its preservation baseline. Each choice starts fresh actors through Retry, then receives six deliberately staged accepted damage events for visual checks. Separate captures exercise pending selection across Resume/Pause, the real dropdown, resize, fatal damage and victory. These are presentation and integration checks; the core fixtures separately verify each base package and passive. Actor AI/physics is held during these presentation captures, so they are not human balance acceptance.

## UI and native receipt — 2026-09-12

Initial focused validation in `abyssal-validation-fcf78dba92984ef1b03a8af11795b3a3` passes 453-script compilation, both guards, 3,082 new Vessel UI assertions, 974 existing recap UI assertions and 233 existing Practice UI assertions. The UI source remained unchanged through the first clean native verification below.

Native validation in `abyssal-gameplay-render-931ccb10cc3443ae874c1ac405b6c938` passes 39 frames and 1,326 assertions on the NVIDIA GeForce RTX 4080. All 39 PNGs were visually inspected. All five actual base actors and their full six-row Pause panels were captured at each supported window size. Additional frames show pending Hexweaver while the current actor remains Bastion after Resume/Pause, the keyboard dropdown, live resize with Menu focus, and defeat. The victory frame explicitly selects Bastion through Retry, then stages Warden HP before a real accepted melee hit. Every native return preserves saved file bytes and normal selection/loadout state.

The complete selector and six-row modal retain their prior physical dimensions: 660×492 at 960×540 and 660×500 at the larger sizes. No scroll region, smaller type, camera or arena change is needed. Native arrow traversal, Enter, popup-only Escape cancellation, subsequent Resume and repeated presentation all pass.

The final notice clarifies that the saved descent and **normal run setup** stay unchanged, avoiding ambiguity beside Practice's selector. Final focused validation in `abyssal-validation-a421b793d1f0433a91edcd09e894b5bc` passes 454-script compilation, both guards, 3,083 Vessel UI assertions, 974 recap assertions and 233 existing UI assertions. The final native run in `abyssal-gameplay-render-2a3f2d142c3142ee948f911b23048e68` again passes all 39 frames and 1,326 assertions, now including the runtime owner's detached-Player cleanup guard. Six representative final images were inspected after the single-line notice change: paused Effigy Keeper at all three sizes, the 960 dropdown, defeat and pending-Hexweaver/current-Bastion state. The revised notice stays complete and readable; all 39 earlier images had already been inspected for the otherwise unchanged layout.

Earlier failed attempts are preserved separately. The first focused snapshot caught an in-progress exported-probe type inference, subsequently corrected by its owner. The first native driver incorrectly assumed Home would move PopupMenu focus; the final driver observes focus and sends actual Up/Down events. The next driver attempted a direct synthetic melee event with Effigy Keeper instead of its actual Attack setup and did not produce the staged victory; using the explicitly selected Bastion for that one terminal presentation corrected the fixture. The failed exit also exposed a detached-scene cleanup edge, reported to the runtime owner independently. No failed receipt is presented as a clean run.

Exact source, logs and frame hashes accompany `.feedback/uncharted-descent-20260912/practice-vessels-prototype-ui/receipt.json`. This work remains an isolated prototype until the workday owner completes review, verification and integration; it has not changed the primary source or desktop executable.

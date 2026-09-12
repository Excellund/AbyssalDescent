# Practice

Practice is a separate solo sandbox opened from the normal menu. It starts in setup. Choose any of the five Vessels, build levels, supported Prismatic Arcana, floor, Bearing, biome and an encounter. The selector offers Skirmish, all eleven named formations, seven named Trial variants, four Apex fights, seven Missions and six bosses, regardless of normal unlocks. An explicit Empty arena stays active for movement and build experimentation.

Start applies the complete validated configuration to fresh actual Player and enemy actors. The Build editor uses the registered Boons, Arcana and boss rewards with their normal caps and application paths. Riftlancer retains its precision thrust and cannot equip Wide Arc. Practice never alters the normal selected character, loadout, unlocks or progression.

Pause freezes combat and the attempt clock. Edits change only the next attempt's draft; Resume keeps the current actor and the edited draft. Apply & Restart commits the draft to a fresh encounter at full configured health. Restart retires all previous actors, fields, projectiles, Effigy state, terrain and accepted-action identities. Held Attack and Dash must be released before the next attempt. Ordinary encounter victory requires every planned wave to be cleared; a temporary gap between waves is not victory. Each Mission runs its own normal objective and completes only through that condition. Boss victory requires defeating the selected boss. Defeat means the configured player's health reached zero.

Enemy AI may be disabled and player invulnerability enabled explicitly. AI-off keeps spawn transport, status expiry and forced displacement working while preventing decisions, movement and offensive behavior. Pausing stops the entire simulation. Invulnerability blocks incoming damage through a Practice-only Player subclass; it does not disable the accepted outgoing-damage/power boundary or fabricate healing. Practice has no Recent damage tab, recorder or recap presentation. The normal descent damage recap remains unchanged.

Floor maps to normal depth and act context: floors 1-9 are act 1, 10-17 act 2, and 18-25 act 3. The chosen encounter keeps its identity while its shared generator uses the selected depth, Bearing and biome. Skirmish keeps its named opening formation rather than choosing a different late-floor route. Ordinary enemies have no invented floor stat multiplier. Bearing applies the real normal incoming-damage and boss scaling. Applicable Catalysts and Forsworn Ascension modifiers use their actual payloads, normal two-slot Catalyst cap and rank-10 Ascension cap. Calm Before Surge and Relentless Tide affect actual wave cadence; Specialist Pressure and Razor Sigils feed the shared generation/scaling paths. Route, draft, Rest and mutator-frequency options stay unavailable. Named Trials already specify their mutator. Effects apply where the chosen encounter uses their system; selecting a boss does not add ordinary waves.

The chosen biome supplies real terrain and biome rules. Each profile supplies its actual room size and obstacle layout. Bosses and Apex fights use normal biome assistance, ordinary formations use their authored terrain family, and Missions use compact rules with their real objective-route exclusions. Brittle cover accepts the real one-contact-per-Attack boundary, stops projectiles and can anchor Orbit. Seamlock's penalty changes effective room bounds, camera framing and terrain context. Recovery keeps its authored open arena; Sweep reserves every remaining node, and Intercept preserves the entire drone route.

Practice fits the full arena beside the status sidebar and above the controls. The existing player camera remains active, while the scene supplies the whole-arena frame. Resize, restart and effective-bound changes recompute it from the UI's actual clear area. The shared Riot Depth score continues through setup, combat, pause and retries.

## Isolation and runtime contract

`scenes/Practice.tscn` runs `scripts/practice/practice_arena.gd` independently of Main. It creates no run session, recorder, award evaluator, checkpoint or upload record. Configuration is read from actual registries without reading or normalizing a profile. `practice_config.gd` provides detached defaults, catalogue, validation and effective difficulty. `practice_encounters.gd` selects profiles through the shared generator and pins a named Trial before its normal roster conversion and damage scaling. `practice_enemy_spawner.gd` observes the normal spawn factory, so initial waves, later waves and Mission reinforcements share ownership and training controls. ObjectiveManager, ObjectiveRuntime and their lifecycle/frame/progress coordinators run the real Mission rules, with an actual objective overlay. Their completion callback ends only this attempt; Mission reward bonuses are never granted. `current_config` describes the applied encounter and actor; `draft_config` is independently editable. Both are deep-copied in presentation.

Active or pending parties block menu entry. Runtime rechecks actual session state at entry, draft edits and deferred application. Each restart advances the owned combat room generation. The detached encounter seed is reused within the scene so restarting the same configuration regenerates the same profile. Pause and setup freeze both wave timers and objective updates. Exit releases only this arena's enemy-service binding; denied entry preserves another world's registry and processing. The normal Menu's Resume/error notice passes through a detached scene property. Practice never clears or repairs normal Continue bytes.

## Verification

Run only through the disposable helper with isolated user data:

```powershell
& .github/scripts/run_gameplay_regressions.ps1 -TestScripts @(
    'res://scripts/tests/test_practice_sandbox.gd',
    'res://scripts/tests/test_warden_practice.gd',
    'res://scripts/tests/test_damage_recap.gd',
    'res://scripts/tests/test_practice_vessels.gd',
    'res://scripts/tests/test_warden_practice_live_combat.gd'
)
```

The sandbox fixture tests detached validation, every registered power cap and supported Prismatic state, atomic draft/application behavior, full builds, explicit immunity, real Bearing/Catalyst/Ascension scaling, empty arenas, all 37 encounter choices, native planned waves, named Trial mutators, every Mission completion condition, AI-off transport/status/Launch, cover and Seamlock. The inherited lifecycle fixtures preserve actual normal checkpoint/profile/meta/settings/history/upload bytes and in-memory setup through real Practice and Menu transitions, then exercise actual Main Continue and exactly-once run recording. All five base passive integrations and Effigy placement/recall/retirement remain covered.

Current encounter-selection receipts belong to `.feedback/practice-encounters-20260913/`. The earlier individual-roster sandbox receipts remain in `.feedback/practice-sandbox-20260912/` as historical evidence. Native UI details are maintained in [Practice presentation](warden-practice-ui.md). Staged health/actions in lifecycle fixtures prove mechanics and isolation; they do not claim human balance acceptance. The separate seeded live Warden smoke uses ordinary movement, Attack and Dash with default real Bearing scaling and no training advantages.

### Encounter-selection runtime receipt — 2026-09-13

The final focused snapshot `abyssal-validation-9e79a8135daf444ea7030ee8924075d3` compiles 459 scripts and passes both source guards. Five suites pass 2,605 assertions: encounter sandbox 2,071, Practice lifecycle 108, all-Vessel passives 324, ordinary live Warden 34 and the retained normal damage recap 68. All 22 owned runtime/fixture/UID files match the tested copy. The source manifest, 36 raw logs and the exact live JSON are preserved in `.feedback/practice-encounters-20260913/runtime-final-result.json`, `runtime-final-raw/` and `runtime-final-live-combat.json`.

The sandbox visits all 37 choices, checks actual selected Trial mutators and authored geometry, completes all seven Missions through their real conditions, and verifies reserved Gauntlet waves cannot finish early. Crossfire intentionally remains a single wave, matching its ordinary generator. Objective tests stage positions, health and near-complete progress to verify the native boundaries; they are not ordinary-input runs. Saved bytes and normal Continue remain covered.

The live default-Warden seed `12092026` runs 474 physics frames (7.9 simulated seconds), performs 15 Attacks and 3 Dashes, observes all three attack patterns and records 350 damage dealt. Bastion is defeated after losing 130 HP; accepted incoming damage is 150 including overkill. No combat frame disables incoming damage. The helper passes all checks while retaining the existing Windows root-certificate-store diagnostic in its logs; there are no script, parse or teardown leak diagnostics.

The first fixture compile failure (untyped WeakRef) and first gameplay fixture failures remain preserved. Those fixture assumptions were corrected: Apex Seamlock includes escorts, so it must be selected by identity, and Crossfire explicitly forces one wave, so Gauntlet provides the real staggered-wave assertion.

### Historical individual-roster sandbox runtime receipt — 2026-09-12

This receipt predates encounter selection and removal of Practice Recent damage; it does not certify those later changes.

The final focused checks compile 459 scripts and pass both source guards. Seven suites pass 1,504 assertions: sandbox 904, lifecycle 108, damage recap 76, all-Vessel passives 324, ordinary live Warden 37, Launch authority 29 and Ruinous feedback 26. The two exact source snapshots are `abyssal-validation-e290279206cd4c9bbc88104124c2c7d0` (sandbox/lifecycle) and `abyssal-validation-103194a95278413dad97c5ec49e744e9` (remaining checks). All six runtime/shared interface scripts match both snapshots; each final fixture matches its passing snapshot.

The seeded ordinary-input smoke runs 598 physics frames (9.97 simulated seconds), performs 22 Attacks and 4 Dashes, observes all three Warden attack patterns and deals 525 accepted damage. Bastion is defeated after losing 130 HP; 138 accepted incoming damage includes overkill. No combat frame disables damage. This uses the selected Delver's real scaling, so it is distinct from the earlier fixed drill receipt.

Exact source checks, raw logs and the live JSON are preserved in `.feedback/practice-sandbox-20260912/runtime-final-result.json`, `runtime-final-raw/` and `runtime-final-live-combat.json`. Earlier parser/encoding failures and the stale rounded-HP fixture expectations remain preserved. Actual mitigation rounds upward at each stage: raw 25 Warden ability damage against base Delver Bastion loses 23 HP; raw 12 against base Delver Hexweaver loses 12 HP.

## Historical fixed-Warden evidence

The following receipts describe the earlier fixed-base Warden drill. They remain preserved as history and do not certify the configurable sandbox or its new Bearing behavior.

### Core receipts — 2026-09-12

- Final source: `abyssal-validation-2ba23f67328449d0bb180c61a4698ee6` under system Temp; 446 scripts compile, both source guards pass, 106 core checks and 31 live-combat checks pass. This includes the final sidebar and complete-arena visibility at 960, 1280 and 1920 widths, resizing, Resume and Retry. The core fixture is in the default regression runner; the frame-dependent live smoke remains an explicit scoped check.
- Live seed `12092026`: 430 physics frames (7.17 simulated seconds), 18 ordinary Attacks, 4 Dashes, all three Warden attack patterns, 450 accepted damage dealt. Bastion loses 130 actual health and is defeated; 145 accepted incoming damage includes the final overkill. No combat frame suppresses damage. This demonstrates the functioning drill, not a successful boss strategy or balance acceptance.
- Existing integration: 75 Menu join/cancel checks and 72 checkpoint-menu checks pass in `abyssal-validation-a7455a22ad4443038cf96e9803a99f3a`. Actual local ENet cancellation passes 12 host and 37 client checks in `abyssal-enet-d6de7c89808d477f89de664e82aa8b77`.
- Workspace receipts: `.feedback/uncharted-descent-20260912/warden-practice-sidebar-final.log`, `warden-practice-complete.log`, `practice-menu-join-cancel-enet.log`, `warden-practice-live-combat.json` and `warden-practice-source-manifest.json`. The manifest checks the runtime, scene, manager predicate and both fixtures against the final passing source snapshot.

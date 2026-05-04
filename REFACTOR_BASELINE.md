# Refactor Baseline Documentation

## Purpose
This document captures the current behavior of the codebase before Phase 0-1 refactoring begins. It serves as the baseline for validating that structural changes do not inadvertently alter gameplay, persistence, telemetry, or debug behavior.

**Lock Date**: May 4, 2026  
**Scope**: Behavior invariants only. This is not design documentation, but a validation contract.

---

## Non-Goals (Must Not Change Inadvertently)

### 1. Gameplay Behavior
- Encounter identity and composition (9 encounter types, each with distinct enemy mixes across 4 bearings)
- Damage calculations and proc order for all powers, bosses, and enemies
- Movement, dash, and attack cadence mechanics
- Objective spawn timing, completion criteria, and progress decay
- Mutator application to player and enemies
- Character-specific stat baselines
- Boss behavior and phases
- Enemy-specific AI and attack patterns
- Reward offering rules and card mechanics
- Power synergy effects and stacking rules

### 2. Persistence
- Save file format and versioning (RUN_SNAPSHOT_VERSION = 1 in player.gd and world_generator.gd)
- Resume workflow (load, sanitize, re-enter game)
- Meta-progression unlocking and tier advancement
- Settings persistence (display, audio, telemetry consent, version skip)
- Telemetry upload queue state across sessions

### 3. Telemetry
- Payload schema (what fields are collected per run)
- Upload behavior (retry queue, Supabase endpoint, consent checks)
- Local analysis queries (playtester_telemetry/*.sql and extract_telemetry*.gd)
- Run ID generation and uniqueness

### 4. Debug Entry Points
- DebugSettings node on Main.tscn (debug_settings.gd)
- Encounter selection enum (DEBUG_ENUMS.Encounter.*)
- Power preset selection (DEBUG_ENUMS.PowerPreset.*)
- Mutator override (DEBUG_ENUMS.MutatorOverride.*)
- End-screen preview mode
- Telemetry spike sender functionality
- All debug methods in world_generator.gd

### 5. Glossary Sync
- Encounter labels and descriptions must stay in sync with encounter_contracts.gd registry
- Glossary rows in glossary_data.gd must match door presentation and debug labels
- Bearing labels must match encounter_profile_builder.gd BEARING_LABELS
- Validation must run on _ready() via ENCOUNTER_CONTRACTS.validate_encounter_sync()

### 6. Scene Entry Points
- Main.tscn loads and instantiates world_generator.gd
- Player.tscn and Enemy.tscn must remain functional as scene definitions
- Menu.tscn must remain as the main menu entry
- Autoloads must stay registered and accessible (RunContext, Enums, GameBalance, ColorPalette, Sounds, DebugSettings)

### 7. Autoload Access Contracts
- RunContext: global settings, meta-progress, telemetry uploader, selected character, difficulty tier
- Enums: all gameplay enums (RunMode, RewardMode, DoorKind, etc.)
- GameBalance: balance constants (not mutable during refactor)
- ColorPalette: color definitions (not mutable during refactor)
- (Others if defined in project.godot)

---

## Current State Ownership Map

### Global Services (Autoloads)
- **RunContext** (`scripts/run_context.gd`)
  - Owns: settings (audio, display, resolution), meta-progression, telemetry consent, update skip state, telemetry_uploader instance
  - Accessed: on startup, during settings menu, during telemetry decision flow
  - Durable across: entire game lifetime (including multiple runs and menu returns)

- **Enums** (`scripts/shared/enums.gd`), **GameBalance**, **ColorPalette**
  - Owns: immutable gameplay constants and definitions
  - Accessed: everywhere, expected to be stable and readonly

### Per-Run Mutable State (Currently split across 3 files)
- **world_generator.gd** (lines ~100-130)
  - Owns: current_difficulty_tier, current_character_id, rooms_cleared, room_depth, boss_unlocked, in_boss_room, choosing_next_room, run_cleared, boons_taken, arcana_rewards_taken, door_options, pending_room_reward, current_room_enemy_mutator, current_room_player_mutator
  - Responsibility: game flow, room progression, reward state

- **game_state_manager.gd**
  - Owns: state machine, room cleared signal, boss unlock signal, run completion signal, phase tracking (phase_two_rooms_cleared, phase_three_rooms_cleared)
  - Accessed: world_generator watches signals and updates local state mirrors

- **run_telemetry_store.gd**
  - Owns: per-run telemetry events (deaths, kills, damage taken, power usage, etc.)
  - Finalized: on run end, sent to telemetry_uploader via RunContext

### Per-Run Immutable Content Definitions
- **encounter_contracts.gd** (centralized, well-maintained)
  - Single source of truth for encounter metadata, debug IDs, door presentation, glossary labels, bearing definitions

- **power_registry.gd**
  - Single source of truth for all powers: upgrades, trial powers, boss epitaphs, damage models, balance values

- **character_registry.gd**
  - Single source of truth for playable characters: stat baselines, abilities, lore

- **difficulty_config.gd**
  - Single source of truth for bearing definitions: Pilgrim, Delver, Harbinger, Forsworn scaling rules

### Runtime Instances (Created per run)
- **Player** (`player.gd`)
  - Owns: movement, dash, attack, power application, damage intake, health, feedback triggers, serialized snapshot of all stat/power state for save/resume
  - Large property list (`RUN_SNAPSHOT_PROPERTIES`, 75+ fields) that must serialize/deserialize faithfully
  - Accessed: by upgrade_system, player_feedback, camera, objective_manager, enemy damage calculations

- **EnemySpawner** → **Array<Enemy>** (enemy_base.gd + subclasses)
  - Owns: enemy state, AI behavior, damage, procs, mutator stat application
  - Accessed: by objective_manager, player damage logic, HUD displays, telemetry event triggers

- **EncounterProfileBuilder** → encounter profile dict
  - Creates: encounter definition structure (enemy counts, room size, mutators, objectives)
  - Used: by EnemySpawner, ObjectiveManager, HUD rendering

- **ObjectiveManager** + **ObjectiveRuntime**
  - Owns: objective state for current room (last_stand, cut_the_signal, hold_the_line)
  - State: hunt target, kills, control progress, spawning rules
  - Accessed: by HUD, world_renderer, enemy spawner

- **WorldHUD**, **WorldRenderer**, **RewardSelectionUI**, **BuildDetailPanel**
  - Own: UI state and rendering
  - Read: player stats, objective state, enemy groups, power descriptions
  - Write: player input (reward selection, settings changes)

### Startup Sequence & Initialization Order
1. RunContext._ready() → load settings, meta-progress, initialize telemetry_uploader
2. Main/world_generator._ready()
   - `_validate_encounter_content_sync()` — must pass silently or push errors
   - `_initialize_bootstrap_context()` — copy debug settings, set up RNG, load current difficulty config
   - `_setup_world_bootstrap_state()` — initialize room/encounter state
   - `_setup_run_systems_phase()` → create and configure gameplay systems (encounter_profile_builder, enemy_spawner, objective_manager, player, camera, music, etc.)
   - `_setup_ui_phase()` → create HUD, renderer, menus, reward selection
   - `_setup_objective_runtime_system()` → prepare objective state
   - Resume or Debug or New Run flow
3. Player._ready() → health_state, upgrade_system, feedback, camera initialization
4. Enemies spawn via enemy_spawner._ready() or on spawn_interval trigger

### Room/Encounter Progression Flow
1. Door selection UI presented (reward_selection_ui with encounter choices)
2. Door chosen → encounter_flow_system.apply_door_choice()
3. New encounter profile generated → enemy_spawner.spawn_enemies()
4. Objective runtime initialized (if applicable)
5. Combat phase (player vs enemies)
6. Objective completion or defeat
7. Reward offered → player applies power or enters next door choice

### Save/Resume Flow
1. On run end or during pause: `run_snapshot_service.serialize_run_state()` captures player stat snapshot + power state
2. Saved to `user://active_run.save` via RunContext
3. On resume: snapshot loaded, player stats and powers reapplied
4. Run flow resumes from where left off

### Telemetry Collection & Upload Flow
1. Events triggered during gameplay (death, kill, power applied, damage taken, etc.)
2. Recorded in run_telemetry_store.gd
3. On run end: payload assembled and enqueued via RunContext.enqueue_telemetry_payload()
4. telemetry_uploader processes queue asynchronously
5. Retry logic handles transient failures

---

## Validation Rules (Must Pass Before & After Each Phase)

### Rule 1: Script Syntax Validation
- All .gd files compile without syntax errors (Godot headless export or LSP check)
- Current tool: `.git/hooks/pre-commit.ps1` regex check (basic), can be enhanced

### Rule 2: Encounter Sync Validation
- `ENCOUNTER_CONTRACTS.validate_encounter_sync(GLOSSARY_DATA._encounter_rows())` must pass on startup
- All 9 encounter types + rest must be defined in registry
- Bearing label map must match registry bearing encounters
- Door presentation must be complete for each encounter
- Current implementation: runs in world_generator._validate_encounter_content_sync() on _ready()

### Rule 3: Power Registry Validation
- All powers in POWER_REGISTRY must have entries in UPGRADE_BALANCE (for upgrades) or trial power fields
- All power IDs referenced in power_registry must be unique
- All descriptions must fit visible-character cap (checked by description_cap_guard.gd)
- Current implementation: implicit, no runtime check yet—candidate for Phase 1 hardening

### Rule 4: Debug Entry Point Coverage
- All 9 encounter types callable via `build_debug_encounter_profile()` in encounter_profile_builder.gd
- All 4 bearings callable via `start_bearing_encounter()` or similar
- All power presets loadable via debug settings
- All characters selectable via character_registry
- Current implementation: debug_settings.gd export enums + world_generator debug methods

### Rule 5: Save/Resume Integrity
- RUN_SNAPSHOT_VERSION must not change unintentionally
- All properties in player.RUN_SNAPSHOT_PROPERTIES must serialize/deserialize without loss
- Telemetry upload queue must survive app restart
- Current implementation: implicit contracts in player.gd and telemetry_uploader.gd

### Rule 6: Telemetry Payload Stability
- Payload fields must not be added/removed/renamed without version bump
- Upload endpoint must remain stable or be versioned
- Supabase schema must match payload structure
- Current implementation: no versioning yet—candidate for Phase 1 hardening

### Rule 7: Scene/Autoload Access
- Main.tscn must load successfully and instantiate world_generator
- All autoloads (RunContext, Enums, GameBalance, ColorPalette) must be accessible as singletons
- No circular dependencies in autoload initialization order
- Current implementation: implicit in project.godot and _ready() ordering

### Rule 8: Debug Settings Integrity
- No debug options should be enabled in shipped builds
- Pre-commit hook validates this before commit
- Current implementation: `.git/hooks/pre-commit.ps1` hardcoded checks

---

## Smoke Test Scenarios (Minimum Regression Coverage)

Each scenario is a manual or automated test path that must succeed without gameplay changes.

### Scenario S1: New Standard Run (Normal Path)
- Start new run (Pilgrim bearing, default character)
- Enter first 2-3 rooms
- Take a boon and a trial power
- Verify: encounter label, HUD stats, power application, movement/attack work
- Exit: victory or defeat screen shows

### Scenario S2: Debug Encounter Boot (Debug Path)
- Enable DebugSettings.enabled = true
- Select an encounter type (e.g., Crossfire)
- Select a bearing (e.g., Harbinger)
- Start game
- Verify: correct encounter spawned, HUD shows correct mutator, enemies have correct count/type
- Disable debug mode before exiting

### Scenario S3: Resume Saved Run (Persistence Path)
- New run → take boon → defeat one room's encounter → pause
- Close game
- Reopen game → select "Resume"
- Verify: same run ID, same powers applied, same room progression, same stats
- Continue to victory or defeat

### Scenario S4: Telemetry On & Off (Telemetry Path)
- New run with telemetry enabled → complete 1 room → defeat
- Verify: events collected, payload sent to queue
- New run with telemetry disabled → complete 1 room → defeat
- Verify: no events sent (RunContext.get_pending_telemetry_upload_count() == 0)

### Scenario S5: Character Selection (Meta-Progression Path)
- Verify all characters unlock correctly
- Select each character
- New run as each character
- Verify: correct stat baselines, correct powers available in registry, correct archetype abilities

### Scenario S6: Bearing Progression (Difficulty Path)
- Complete Pilgrim run
- Verify Delver unlocked
- Complete Delver run
- Verify Harbinger unlocked
- Complete Harbinger run
- Verify Forsworn unlocked
- Select Forsworn → new run
- Verify: correct difficulty scaling applied

### Scenario S7: Objective Room (Objective Path)
- Force a last_stand objective via debug settings or random seed
- Verify: objective HUD, spawn timing, completion on N kills
- Verify kill quota announced and tracked
- Test: lose the objective (enemies survive threshold)

### Scenario S8: Boss Fight (Boss Path)
- Complete enough rooms to unlock boss
- Enter boss room
- Verify: correct boss spawned (Warden, Sovereign, or Lacuna)
- Deal damage to boss
- Verify: boss health bar, phase transitions work (if any)
- Defeat or die to boss

### Scenario S9: Power Description & Tab (UI Path)
- Apply several powers
- Press Tab to open build detail panel
- Verify: all active powers listed with correct descriptions
- Verify: no text overflow, caps respected
- Close panel

### Scenario S10: Settings Persistence (Settings Path)
- Change audio levels, resolution, display mode
- Exit to menu
- Return to menu
- Verify: settings reloaded and applied
- Quit game
- Restart game
- Verify: settings still applied

---

## Current Validation Entry Points

### Pre-Commit Validation
- **File**: `.git/hooks/pre-commit.ps1`
- **Checks**: Debug settings disabled, basic GDScript syntax
- **Trigger**: automatic on `git commit`
- **Scope**: staged files only

### Startup Validation
- **File**: `world_generator._validate_encounter_content_sync()`
- **Checks**: encounter_contracts registry synced with glossary
- **Trigger**: automatic on Main scene _ready()
- **Output**: console errors if misaligned

### Debug Entry Points (Manual)
- **File**: `debug_settings.gd` + `world_generator` debug methods
- **Allows**: encounter selection, bearing override, power preset, mutator forcing, end-screen preview
- **Trigger**: manual via DebugSettings node in Main.tscn

### Telemetry Analysis (Manual)
- **Files**: `playtester_telemetry/*.sql`, `extract_telemetry*.gd`, `fetch_latest_version_analysis.ps1`
- **Allows**: querying Supabase for per-bearing balance analysis, death rates, power pick rates
- **Trigger**: manual via PowerShell or Godot script execution

---

## Phase 0 Completion Checklist

Before moving to Phase 1, all of the following must be true:

- [ ] REFACTOR_BASELINE.md is complete and reviewed
- [ ] Current startup sequence is documented and validated to work
- [ ] All 10 smoke test scenarios pass on current codebase
- [ ] Pre-commit validation runs cleanly on current staged code
- [ ] Encounter sync validation passes on startup
- [ ] Save/resume cycle confirmed to work (scenario S3)
- [ ] Telemetry upload/queue logic confirmed to work (scenario S4)
- [ ] All debug entry points confirmed to work (scenario S2)
- [ ] No regressions introduced by documentation or validation additions

---

## Phase 1 Enhancement Goals (Validation Hardening)

These are improvements to validation infrastructure that will support later aggressive refactoring:

1. **Script Diagnostics**: Run Godot CLI script validation or LSP-based checks on all .gd files
2. **Power Registry Check**: Validate all power IDs, descriptions, and balance entries at startup
3. **Folder Structure Check**: Validate canonical folder layouts and dependency directions
4. **Telemetry Schema Check**: Validate payload shape matches Supabase schema
5. **Automated Smoke Matrix**: CLI or headless mode to run scenario subset without manual play
6. **Pre-Commit Expansion**: Move beyond debug checks to include encounter/power/path validation

---

## Approval Sign-Off

**Current Baseline State**: VALIDATED as of [DATE - to be filled by lead]  
**Baseline Validator**: [ROLE - to be filled]  
**Refactor Scope Lock**: This baseline defines the invariant contract for all 6 refactor phases.

---

## References
- [world_generator.gd](scripts/world_generator.gd) - Main entry point and orchestrator
- [run_context.gd](scripts/run_context.gd) - Global settings and services
- [encounter_contracts.gd](scripts/shared/encounter_contracts.gd) - Encounter metadata
- [power_registry.gd](scripts/power_registry.gd) - Power definitions
- [player.gd](scripts/player.gd) - Player state and serialization
- [PRE_COMMIT_GUIDE.md](PRE_COMMIT_GUIDE.md) - Current validation hooks
- [REFACTOR_SUMMARY.md](REFACTOR_SUMMARY.md) - Prior encounter centralization work

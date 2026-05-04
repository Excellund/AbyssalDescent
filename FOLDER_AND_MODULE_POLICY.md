# Phase 1: Canonical Module/Folder Policy

## Purpose

This document defines the target folder structure and module ownership boundaries for the AbyssalDescent codebase after refactoring phases 1-6 complete. It serves as the north star for all subsequent refactoring work and ensures consistency in dependency direction and responsibility ownership.

**Status**: CANONICAL POLICY - All phases must follow this structure.  
**Last Updated**: May 4, 2026

---

## Dependency Rules (Sacred Constraints)

### Rule 1: Acyclic Dependency Graph

- No cycles. A → B → A is forbidden.
- Enforce via PR review and grep checks for cross-namespace imports in later phases.

### Rule 2: Downward Dependency Only

- Higher-level subsystems CAN depend on lower-level subsystems.
- Lower-level subsystems MUST NOT depend on higher-level subsystems.
- Hierarchy (highest → lowest):
  1. **systems/** (orchestrators: world_generator, music_system, menu_controller)
  2. **encounters/, objectives/, progression/, telemetry/, ui/** (subsystems)
  3. **gameplay/** (player, enemies, combat)
  4. **core/** (bootstrap, global services)
  5. **shared/** (immutable data, enums, pure helpers)

### Rule 3: Shared Boundary

- **shared/** contains only:
  - Immutable enums and constants
  - Contract/interface definitions (not implementations)
  - Pure utility functions (no side effects, no external state access)
  - Color, audio, and balance constants (read-only)
- **shared/** should NEVER contain:
  - Game loop logic
  - Mutable state
  - System-specific business logic

### Rule 4: Subsystem Autonomy

- Each subsystem (encounters, objectives, progression, telemetry, ui) should be independently testable
- Subsystems communicate via contracts/interfaces in shared/contracts/
- Subsystems SHOULD NOT reach into other subsystems' internals (no `subsystem._private_method()` calls)

### Rule 5: Global State (Autoloads) Restrictions

- **RunContext** (core/): durable settings, services registry, meta-progression store
- **Enums, GameBalance, ColorPalette** (shared/): immutable gameplay constants
- **No new autoloads** without explicit approval. Pass data via dependency injection instead.

### Rule 6: UI Boundaries

- UI should not mutate game state directly
- UI reads from immutable game state snapshots or event streams
- UI changes are signaled back through input handlers or event queues
- UI code lives in ui/; game logic lives in gameplay/, encounters/, objectives/, etc.

---

## Current State → Target State Mapping

| Current Location                     | Target Location                           | Notes                                               |
| ------------------------------------ | ----------------------------------------- | --------------------------------------------------- |
| scripts/world_generator.gd           | systems/world_generator.gd (narrow scope) | Remove orchestration details, keep wiring           |
| scripts/run_context.gd               | core/run_context.gd (narrow scope)        | Keep only settings, services. Extract run state.    |
| scripts/game_state_manager.gd        | MERGE into core/run_session.gd or RENAME  | Extract per-run state owner                         |
| scripts/player.gd                    | gameplay/player/player.gd                 | Extract stats, effects, feedback to collaborators   |
| scripts/upgrade_system.gd            | progression/upgrade_system.gd             | Keep upgrade application logic                      |
| scripts/objective_manager.gd         | REFACTOR into objectives/ subsystem       | Replace broad state holder with contract + handlers |
| scripts/encounter_profile_builder.gd | encounters/encounter_profile_builder.gd   | Extract presentation logic                          |
| scripts/power_registry.gd            | progression/power_registry.gd             | Keep immutable definitions                          |
| scripts/build_detail_panel.gd        | ui/overlays/build_detail_panel.gd         | Extract text formatting helpers                     |
| scripts/world_hud.gd                 | ui/hud/world_hud.gd                       | Split into focused HUD modules                      |
| scripts/debug_settings.gd            | debug/debug_settings.gd                   | Move into organized debug folder                    |
| scripts/shared/\*                    | shared/ (keep organized)                  | Already mostly correct                              |
| scripts/core/                        | core/ (formalize structure)               | Partially exists, needs structure                   |
| scripts/entities/                    | entities/ (keep, formalize)               | Exists but underutilized                            |
| scripts/systems/                     | systems/ (formalize and migrate)          | Partially exists                                    |
| scripts/progression/                 | progression/ (formalize)                  | Partially exists                                    |

---

## Phase 1 Completion Checklist

- [ ] This policy is reviewed and approved
- [ ] Canonical folder structure created (all directories listed above exist)
- [ ] Current files organized under target locations (compatibility forwarding in root if needed temporarily)
- [ ] Autoload registrations updated in project.godot
- [ ] Pre-commit hook updated to validate folder structure (fail if new files outside canonical folders)
- [ ] All scene script bindings updated to reference new paths
- [ ] Validation harness runs clean on new structure
- [ ] All smoke test scenarios pass
- [ ] No new cycles introduced (grep check for circular dependencies)
- [ ] Deprecation markers placed on any transitional/forwarding stubs

---

## Phase 1 Post-Completion: Validation Suite Enhancements

After folder structure is in place, add these checks to pre-commit or CI:

1. **Folder Rule Validator**: Ensure new scripts land in canonical folders, not scattered root
2. **Dependency Rule Validator**: Check for circular imports or rule violations
3. **Autoload Rule Validator**: Ensure no new autoloads without approval
4. **Contract Coverage**: Ensure subsystem-to-subsystem communication uses shared/contracts/
5. **Deprecated Path Detector**: Warn if code imports from transitional/compat stubs (encourage cleanup)

---

## Exceptions and Special Cases

### Exception 1: Temporary Compatibility Wrappers

- During migration, old paths can be kept as thin forwarding stubs (e.g., `_compat_old_name.gd`)
- Marked with `## DEPRECATED: forward to [new location]` comment
- Scheduled for removal after next phase (not left indefinitely)

### Exception 2: Multi-Subsystem Contracts

- Some contracts naturally span multiple subsystems (e.g., damage_packet touches gameplay + encounters)
- Place these in shared/contracts/ and version them
- Document the subsystems that implement/consume each contract

### Exception 3: Platform-Specific or Tool Scripts

- Platform-specific code (Windows/Linux/Mac) can live in dedicated folders outside the canonical structure
- Tool scripts (build, export, analysis) can live in scripts/tools/ or at root without restriction

---

## Implementation Roadmap (Phases 2-6)

| Phase | Subsystem Focus       | Files Affected                                          | Risk        | Effort |
| ----- | --------------------- | ------------------------------------------------------- | ----------- | ------ |
| 2     | Core / Bootstrap      | world_generator, run_context, run_session (NEW)         | Medium      | 6h     |
| 2     | Run State Separation  | Extract per-run state from global                       | Medium      | 4h     |
| 3     | Encounters            | encounter_profile_builder, door presentation, mutators  | Medium      | 8h     |
| 3     | Objectives            | objective_manager → objective handlers + contract       | Medium      | 6h     |
| 4     | Player/Combat         | player.gd split, damage_calculator (NEW), effects (NEW) | Medium-High | 10h    |
| 4     | Enemies               | enemy_base, enemy_helpers, spawner contracts            | Medium      | 6h     |
| 5     | Progression           | power_registry split, descriptions (NEW), UI sync       | Low         | 5h     |
| 5     | UI / Naming           | UI folder consolidation, naming normalization           | Low         | 4h     |
| 6     | Cleanup / Deprecation | Merge legacy paths, validate structure, final polish    | Low         | 3h     |

---

## References

- [REFACTOR_BASELINE.md](REFACTOR_BASELINE.md) — Behavior invariants to preserve
- [SMOKE_TEST_SCENARIOS.md](SMOKE_TEST_SCENARIOS.md) — Regression test coverage
- [validation_harness.gd](scripts/validation_harness.gd) — Automated validators
- [code-quality skill](./../../.github/skills/code-quality/SKILL.md) — Foundational refactor principles

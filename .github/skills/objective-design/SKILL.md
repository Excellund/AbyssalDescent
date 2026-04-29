---
name: objective-design
description: "Design and implement new objective encounter variants in Godot from concept through runtime, UI, glossary, and debug surfaces."
argument-hint: "Objective fantasy, success/fail rules, pressure profile, and desired mutator reward"
---

# Objective Design

Use this skill when adding a new objective type or introducing a new objective-flavored encounter variant.

## Design Targets
- Objective has one clear verb: survive, assassinate, control, escort, etc.
- Success is readable in moment-to-moment HUD feedback.
- Pressure and recoverability both exist; difficulty should come from decisions, not constant overwhelm.
- Overtime escalates stakes without creating instant unwinnable states.
- Encounter identity remains distinct from other objective types.

## Required Implementation Surfaces
1. Contracts and schema
- scripts/shared/encounter_contracts.gd
- Add profile keys, getters, setters, and objective kind constants needed by runtime.

2. Profile builder and selection
- scripts/encounter_profile_builder.gd
- Add/extend objective profile builders and route/debug selection hooks.
- Keep objective-specific parameters data-driven in profile fields.

3. Runtime state machine
- scripts/objective_runtime.gd
- Add objective begin/update/spawn logic.
- Include completion rules, overtime transition, and pressure floor behavior.

4. World/HUD plumbing
- scripts/world_generator.gd
- scripts/world_hud.gd
- Ensure objective state fields are initialized, updated, and displayed clearly.

5. Reward and mutator UX (if objective grants one)
- scripts/reward_selection_ui.gd
- scripts/encounter_profile_builder.gd
- Ensure mutator IDs, labels, and icon fallbacks are present and coherent.

6. Glossary and naming sync
- scripts/shared/glossary_data.gd
- Add or update player-facing objective and mutator descriptions.

## Objective Tuning Heuristics
1. Pressure envelope
- Prefer tuning spawn interval, spawn batch, and cap before raw enemy damage/health.
- Keep floor pressure high enough to force engagement, low enough for reclaim windows.

2. Recoverability
- In-objective positive progress should outpace decay during good execution.
- Contest or failure states should slow progress, not always erase it instantly.

3. Overtime behavior
- Escalate cadence gradually.
- Avoid unconditional +spawn spikes when current enemy count is already high.

4. Bearing monotonicity
- Pilgrim -> Delver -> Harbinger -> Forsworn should feel progressively tighter.
- Keep monotonic pressure unless a deliberate exception is documented.

## Procedure
1. Define objective contract
- Write success/failure conditions and what progress means.

2. Add contract fields first
- Introduce schema and typed accessors in scripts/shared/encounter_contracts.gd.

3. Build profile knobs
- Put tuning variables in scripts/encounter_profile_builder.gd.

4. Implement runtime loop
- Implement begin/update/spawn for the objective in scripts/objective_runtime.gd.

5. Hook presentation
- Wire state to scripts/world_generator.gd and scripts/world_hud.gd.

6. Sync content surfaces
- Update scripts/shared/glossary_data.gd and debug entry points.

7. Validate
- Run diagnostics on all changed files.
- Perform quick sanity checks for Pilgrim, Delver, Harbinger, Forsworn.

## Done Criteria
- Objective is selectable and playable through intended routes/debug paths.
- Success/failure and progress are readable in HUD and world feedback.
- Runtime and profile knobs are data-driven and tunable.
- Glossary text matches gameplay meaning.
- Changed scripts are diagnostics-clean.

## Output Format
1. Objective concept and identity
2. Contract and builder changes
3. Runtime behavior and pacing
4. HUD/world feedback updates
5. Bearing-by-bearing expectations
6. Risks and rollback knobs

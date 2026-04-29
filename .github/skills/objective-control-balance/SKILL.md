---
name: objective-control-balance
description: "Retune Hold the Line-style control objectives when players are getting swarmed too quickly or cannot maintain zone progress. Uses profile/runtime levers that improve recoverability without deleting pressure."
argument-hint: "Player pain report, target bearings, depth band, and desired pressure floor"
---

# Objective Control Balance

Use this skill when a control objective is technically winnable but practically oppressive due to swarm upkeep pressure.

## Problem Signatures
- Players report they get swarmed too fast and cannot hold the zone.
- Progress decays faster than it can be rebuilt during normal play.
- Contest state feels binary (inside zone still feels like losing).
- Overtime escalation immediately collapses recoverability.

## Design Goals
- Preserve control-objective identity: hold territory under pressure.
- Increase recoverability windows after mistakes.
- Keep pressure readable and monotonic across bearings.
- Avoid converting control into a low-pressure free capture.

## Primary Levers
1. Builder-side pressure envelope (scripts/encounter_profile_builder.gd)
- Lower base role counts and slower growth on primary swarm units.
- Increase control zone radius to reduce accidental drop-off.
- Increase spawn interval and cap spawn batch growth.
- Lower progress goal and progress decay for realistic completion pacing.
- Raise contest threshold when contesting is too sticky.
- If identity is being flattened by global scaling, use encounter-specific scaling override in _apply_bearing_count_scaling.

2. Runtime-side recoverability (scripts/objective_runtime.gd)
- Lower objective_max_enemies for control mode.
- Soften pressure_floor and forced spawn_timer clamp.
- Slow initial spawn cadence and reduce overtime acceleration.
- Increase uncontested in-zone gain rate.
- Heavily reduce contested in-zone loss multiplier.
- Reduce out-of-zone decay if repositioning is too punishing.
- Prevent unconditional overtime extra spawns; gate bonus spawns behind low-enemy conditions.

## Guardrails
- Do not solve only by inflating player damage or nerfing all enemy archetypes globally.
- Do not remove contest pressure entirely; contested state must still matter.
- Keep control completion tied to zone commitment, not passive timer drift.
- Keep route/debug/glossary surfaces in sync if objective meaning changes.

## Procedure
1. Read current control profile and runtime state handlers.
- scripts/encounter_profile_builder.gd: _build_control_profile
- scripts/objective_runtime.gd: _begin_control_objective, update_control_objective_state, spawn_control_wave

2. Apply a paired tuning pass.
- First pass: reduce profile envelope (counts/cadence/goal/decay/radius).
- Second pass: reduce runtime maintenance pressure (caps/floor/overtime/contest loss).

3. Validate diagnostics for all touched files.

4. Run per-bearing sanity checks.
- Pilgrim: recoverable by average play, obvious reclaim windows.
- Delver: pressured but maintainable with target priority.
- Harbinger: demanding but not permanently downhill.
- Forsworn: hardest, but losses should come from decisions, not instant swarm lock.

## Output Format
1. Swarm failure diagnosis
2. Builder-side changes
3. Runtime-side changes
4. Bearing-by-bearing expected feel
5. Rollback knobs

## Fast Rollback Knobs
- Easiest down-tune: lower objective_max_enemies and pressure_floor.
- Easiest up-tune: lower zone_radius or raise progress_goal.
- Overtime pain knob: adjust objective_spawn_interval multiplier and bonus spawn condition.

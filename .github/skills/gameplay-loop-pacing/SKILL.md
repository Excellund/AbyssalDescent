---
name: gameplay-loop-pacing
description: "Use when combat feels like repetitive kiting (running in circles), objectives stall pacing, or Last Stand timer gameplay feels passive. Focuses on anti-kiting pressure, engagement incentives, and objective pacing while preserving encounter identity."
argument-hint: "Player pain report, affected mode/objective, bearings, and desired pacing outcome"
---

# Gameplay Loop Pacing

Use this skill when the core loop feels passive, repetitive, or dominated by evasive stalling.

## Problem Signatures
- Players report "running in circles" as dominant survival strategy.
- Last Stand objective resolves by waiting out timer rather than active engagement.
- Damage opportunities are low-risk and low-commitment, and encounters feel too similar.
- Encounter pressure is high in uptime but low in decision variety.

## Design Goals
- Increase meaningful engagement moments without deleting defensive play.
- Reward commitment windows (positioning, timing, target priority).
- Reduce passive stall incentives in objective modes, especially Last Stand.
- Preserve encounter identity and readability.

## Core Levers
1. Anti-kiting pressure
- Add role combinations that punish infinite orbiting (lane cutoffs, flankers, zone denial).
- Use soft containment over hard lock: readable pressure cones, telegraphed intercepts, temporary area taxes.
- Tune pursuit cadence, not just top speed.
- Spectre pattern: predictive repositioner that punishes staying on the same orbit line.
- Pyre pattern: kill-position tax that turns careless clears into temporary denial.
- Tether pattern: moving beam pair that cuts a lane dynamically rather than placing a static zone.

2. Commitment rewards
- Add short-duration bonuses for proximity, chained hits, or objective control presence.
- Shift value from pure survival time to active execution windows.
- Create opportunities where stepping in now is clearly better than continuing to circle.

3. Objective pacing (Last Stand focus)
- Replace pure timer wait with progress accelerants tied to action (kills in zone, streak thresholds, wave breaks).
- Add anti-stall decay if player avoids interaction too long.
- Introduce punctuated mini-phases so pacing has rises and falls, not flat sustain.

4. Encounter rhythm shaping
- Use burst-rest cycles: pressure spikes followed by deliberate relief.
- Mix threat roles so movement pathing decisions matter.
- Keep per-bearing pacing monotonic unless explicitly justified.

## Procedure
1. Define the boredom loop
- Identify exact passive pattern, trigger conditions, and affected bearings and depths.

2. Gather evidence
- Use telemetry where available:
  - Long survival with low engagement density.
  - Last Stand clear/death timing clusters.
  - Damage source distribution during stall periods.
- Use skill: run-telemetry-balance for query patterns.

3. Map to levers
- Encounter composition/cadence: scripts/encounter_profile_builder.gd
- Objective runtime flow: scripts/objective_runtime.gd, scripts/world_generator.gd
- Enemy role pressure: scripts/enemy_spawner.gd, enemy archetype scripts

4. Propose a package
- One anti-stall mechanic.
- One engagement incentive.
- One bearing-aware pacing adjustment.
- One rollback-safe fallback knob.

5. Validate
- Pilgrim, Delver, Harbinger, Forsworn quick checks.
- Last Stand: confirm active play outperforms passive orbiting.
- Confirm encounter identity remains intact.

## Constraints
- Do not solve pacing only by raising enemy damage or health.
- Do not remove defensive movement viability entirely.
- Avoid unreadable hard counters to mobility.
- Keep route, glossary, and debug surfaces in sync when encounter meaning changes.

## Reusable Enemy Patterns
- Use predictive enemies when the player loop is too deterministic; the counterplay should be direction change or tempo break, not raw speed checks.
- Use death-residue enemies when kill order and kill location should matter more than pure survival time.
- Use moving lane-cutters when static hazard circles already exist and you need a different anti-kiting shape.

## Output Format
1. Loop failure diagnosis
2. Proposed pacing package
3. Bearing-by-bearing expectations
4. Last Stand-specific expected behavior change
5. Validation plan
6. Risks and rollback knobs

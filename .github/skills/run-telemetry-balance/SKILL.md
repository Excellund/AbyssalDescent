---
name: run-telemetry-balance
description: "Use when balancing from player-run data. Explains how run telemetry is recorded, filtered, and interpreted, including bearing-level aggregates and debug exclusion rules."
argument-hint: "Run window (max runs / max age), version scope, and the balance question"
---

# Run Telemetry Balance

Use this skill when you need evidence from real runs before changing encounter balance.

## What The Telemetry Captures
- Run metadata: version, difficulty tier, run mode, outcome, depth, rooms cleared.
- Player pressure events: damage source, ability, amount, room label, bearing key, depth.
- Choice events: door choices and reward choices.
- Encounter flow: room entries with room kind, bearing key, bearing label, mutator, objective kind.
- Death context: last known source/ability with bearing key and depth when available.

## Where It Lives
- Runtime hooks and collection:
  - scripts/world_generator.gd
  - scripts/player.gd
- Store and query layer:
  - scripts/run_telemetry_store.gd
- Persisted file:
  - user://run_telemetry.save
- Remote upload pipeline (playtester collection):
  - scripts/telemetry_upload_queue.gd — durable local queue with retry metadata
  - scripts/telemetry_uploader.gd — background HTTP sender, 10s flush interval
  - Destination: Supabase table `public.telemetry_runs`
  - Upload is triggered automatically at run end via `world_generator._finish_active_run_telemetry()`
  - Raw event arrays (`damage_events`, `reward_choices`, `room_entries`, `door_choices`) are included in the remote payload alongside the `aggregate` dict

## Query Path
1. Call world-level query API:
   - scripts/world_generator.gd get_balance_telemetry(max_runs, max_age_days, include_debug, game_version)
2. Use filtered windows intentionally:
   - max_runs for sample size control.
   - max_age_days for recency.
   - game_version for patch-to-patch comparability.
   - include_debug false by default.
3. Read both raw runs and aggregate buckets from the response.

## Example Invocations
1. Recent patch check (default behavior):
   - Query: get_balance_telemetry(20, 14, false, "")
   - Use when: validating a fresh balance change over the last two weeks.
2. Broader trend scan (current version only):
   - Query: get_balance_telemetry(50, 45, false, "")
   - Use when: looking for persistent dominant pressure channels.
3. Cross-version comparison window:
   - Query current: get_balance_telemetry(30, 30, false, "")
   - Query previous: get_balance_telemetry(30, 30, false, "<previous_version>")
   - Use when: checking whether a patch shifted bearing-level deaths or damage.
4. Debug-inclusive investigation (opt-in only):
   - Query: get_balance_telemetry(25, 21, true, "")
   - Use when: reproducing issues that only appear in controlled debug runs.

## Terminology Note
- **Bearing** = difficulty tier (Pilgrim, Delver, Harbinger, Forsworn).
- **Encounter** = room composition type (Skirmish, Crossfire, Blitz, Onslaught, Fortress, Suppression, Vanguard, Ambush, Gauntlet).
- The code stores encounter type in fields called `bearing_key` and `bearing_label`, and aggregate buckets are named `damage_by_bearing`, `deaths_by_bearing`, etc. These are code-level names; conceptually they track **encounter** type, not difficulty tier.

## Core Aggregates To Read First
- outcomes
- damage_by_source
- damage_by_ability
- damage_by_bearing (= damage by encounter type in code)
- deaths_by_bearing (= deaths by encounter type in code)
- room_entries_by_bearing (= room entries by encounter type in code)
- door_choices_by_bearing (= door choices by encounter type in code)

## Interpretation Workflow
1. Validate sample quality.
   - Confirm run_count is enough for the decision.
   - Confirm version filter matches the balance target build.
   - Keep debug runs excluded unless explicitly investigating debug-only behavior.
2. Find dominant pressure channels.
   - Compare damage_by_bearing (per-encounter) vs room_entries_by_bearing (per-encounter).
   - Compare deaths_by_bearing (per-encounter) vs door_choices_by_bearing (per-encounter).
3. Map pressure to design levers.
   - Encounter composition levers in scripts/encounter_profile_builder.gd.
   - Mutator/stat levers in scripts/encounter_profile_builder.gd and scripts/enemy_spawner.gd.
   - Per-bearing (difficulty tier) pressure levers in scripts/difficulty_config.gd.
4. Propose identity-safe adjustments.
   - Preserve each encounter's fantasy while tuning cadence, role mix, and bounded stats.
   - Check per-bearing (difficulty) rank_counts if a specific tier is over- or under-pressured.

## Caveats
- Deleting user://run_telemetry.save resets local history; a new file is created on the next telemetry-enabled run.
- If no file exists yet, verify the run was not started in a debug mode that disables telemetry collection.
- Label-based bearing normalization is stable enough for analysis, but explicit bearing_key fields should be preferred whenever present.
- Reward telemetry currently records the selected `choice_id` but not the full offered choice set. Treat "least picked" reward conclusions as selection-frequency signals, not true pick-rate/offer-rate measurements, unless offer-set logging is added.
- Remote uploads are gated on player consent (`telemetry_consent_asked` + `telemetry_upload_enabled` in settings_store). Debug runs are still uploaded but flagged `is_debug: true`; filter them in Supabase queries for clean production data.

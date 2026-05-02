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

## Pick Rate Calculation
Pick rate = picks / offers. The `reward_choices` array records what was selected; `reward_offers` records what was presented. True pick rate requires both.
- `fetch_latest_version_analysis.ps1` computes this and writes `arcana_pick_rates` and `boon_pick_rates` to the report JSON.
- Each entry has: `{ arcana/boon, offers, picks, pick_rate_pct }`. `pick_rate_pct` is `null` if the reward was never offered (picks came from a source without offer tracking).
- `never_picked_arcana` is the pre-filtered list of arcana offered ≥2 times but never chosen — the highest-priority buff/rework candidates.
- Treat pick rates from very small offer counts (< 5) as directional signals, not reliable percentages.

## Character Analysis
Character data is in `character_popularity` and `character_by_bearing` in the report JSON.
- `character_popularity`: {character, runs, clear_rate_pct, death_rate_pct, avg_max_depth} — use for overall balance.
- `character_by_bearing`: {character, difficulty_tier, runs, clear_rate_pct} — use to identify if a character is strong on Pilgrim but fails on Forsworn.
- Low pick rate does not always mean weakness — check whether unlock gating is the cause before proposing buffs.
- A character > 30 percentage points below average clear rate is a balance concern. A character > 30 points above average is an overperformance concern.

## Fun / Satisfaction Proxy
There is no direct "fun" signal in the telemetry. Use this proxy chain:
1. **Engagement signal** (`boredom_proxy.long_low_engagement_runs`): long runs with very few damage events. Elevated count suggests passive play (kiting, avoidance) rather than active combat.
2. **Arcana outcome depth** (`arcana_outcomes.avg_max_depth`): how far players get with each opening arcana. Low avg depth on frequently-picked arcana suggests it felt compelling but failed to deliver.
3. **Death timing** (`death_timing`): if median death depth is in the first quarter of rooms, players aren't reaching the designed late-game experience.
4. **Character diversity** (`character_popularity`): when players cluster on one character, they are either optimizing heavily or the other options feel unrewarding.
Synthesize these four signals into POSITIVE / MIXED / NEGATIVE. Always state which signals drove the assessment and note that this is not a direct player satisfaction measure.

## Full Analysis Workflow (13 Dimensions)
When a full analysis is requested, work through all 13 dimensions in order. The dedicated Telemetry Analyst agent applies this workflow automatically via `fetch_latest_version_analysis.ps1`.

| # | Dimension | Key Fields | Flag Threshold |
|---|-----------|------------|----------------|
| D1 | Dataset quality | run_count, outcomes | WARN < 10 runs; STOP < 5 |
| D2 | Difficulty calibration | outcomes (clear rate), death_timing | FLAG < 10% or > 70% clear rate |
| D3 | Arcana pick concentration | top_arcana_picks | FLAG if top pick > 50% of total |
| D4 | Arcana never picked | never_picked_arcana, arcana_pick_rates | FLAG all entries (buff/rework candidates) |
| D5 | Arcana win rate | arcana_outcomes | FLAG death_rate > 80% with ≥3 runs |
| D6 | Boon pick concentration | top_boon_picks, boon_pick_rates | FLAG if top boon > 40% of total |
| D7 | Damage pressure | encounter_pressure.damage_per_entry | FLAG if ≥ 2× median |
| D8 | Death concentration | encounter_pressure.deaths_per_100_entries | FLAG > 50; WATCH > 25 |
| D9 | Engagement signal | boredom_proxy | FLAG if long_low_engagement > 15% of runs |
| D10 | Character popularity | character_popularity | FLAG if any character < 15% of runs |
| D11 | Character win rate | character_popularity, character_by_bearing | FLAG if > 30 pts below/above average |
| D12 | Encounter selection | encounter_pressure.entries (share) | FLAG if non-boss < 5% of total entries |
| D13 | Fun proxy | D9 + D5 + D2 + D10 synthesis | POSITIVE / MIXED / NEGATIVE |

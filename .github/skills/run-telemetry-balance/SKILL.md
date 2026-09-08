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
- Reward telemetry records both `reward_choices` and `reward_offers`; use offer counts when available instead of treating selection frequency as pick rate.
- Remote uploads require `telemetry_upload_enabled` in settings_store. Telemetry and leaderboard submissions both exclude debug runs and dev/debug build versions, including previously queued leaderboard submissions. Still filter historical data by debug status and version.
- Export playtests with `.github/scripts/export_playtest.ps1`. Its default `dev-<UTC timestamp>-<suffix>` identifies the exact build in local history; `-BuildVersion dev-<label>` supports a named playtest. Never replace a playtest version with a release version to collect data.
- Maintain one desktop playtest executable at `C:/Users/mikel/Desktop/AbyssalDescent Playtest.exe` for both normal and debug runs. Each update or mode switch replaces this same file. The exporter defaults to this path and permits its replacement automatically; an existing custom `-OutputPath` still requires `-Overwrite`. Keep unique `dev-*` IDs inside builds, not in numbered desktop filenames.
- At a user-agreed checkpoint, verify the completed changes, commit and push them, and replace the desktop playtest with a normal export (without `-DebugRun`). Preserve unrelated local work and do not create release tags unless requested. This is the user's standing checkpoint preference.
- A normal export starts at the menu with regular saves and no debug grants. `export_playtest.ps1 -DebugRun` embeds the current powers preset and uses a separate persistent debug save directory, preserving normal progress. The current preset is Bastion on Delver with Blast Drive and Razor Orbit at level 3, and Ruinous Impact and Sovereign's Double at level 2.
- `start_debug_playtest.ps1` is the export-and-launch wrapper for `-DebugRun`: it must launch the same packaged desktop executable. Temporary source-only debug sessions are validation fixtures, not delivery to the user. Internal staging paths may be temporary, but opening the desktop executable must run the mode most recently exported.

## Safe Report Workflow
- Run `playtester_telemetry/fetch_latest_version_analysis.ps1 -Version '<exact-build>' -From 'YYYY-MM-DD' -To 'YYYY-MM-DD'`. The version is required; dates use UTC, From is inclusive, and To is exclusive. Default window is the last 30 days.
- The script calls only the read RPC and defaults to a unique temporary report, printing `REPORT_JSON=<path>`. Read that returned path. It does not replace the old tracked report; a chosen existing `-OutputPath` requires `-Overwrite`.
- Add `-LocalHistoryPath '<path-to-run_history.json>'` to analyze local dev playtests without launching the game or contacting any service. JSON telemetry exports containing a `runs` array also work; binary `.save` files require a separate isolated export first.
- Local summaries contain final builds and equipped Catalysts but not reward offers or room/damage event arrays. `final_build_presence` is not a pick rate; missing metrics are `null`, and `sample.field_coverage_runs` states the available evidence.
- Verify the selected version, sample dates, and `cohorts` before drawing conclusions. A plain `dev` version may cover several patches, and pooled solo/co-op, Bearing, mode, and Ascension outcomes are not controlled comparisons.
- The current remote telemetry payload/RPC omits Catalyst and Ascension loadouts even though the SQL table defines those columns. Missing data is not evidence of an empty/default loadout.
- `-ValidateOnly` checks parameters without querying data or creating a report. `.github/scripts/test_playtest_workflow.ps1` tests local filtering, read-RPC pagination, privacy, and export parameters using temporary fixtures and mocked HTTP.

## Oath Evidence and Run Summaries
- Trace an Oath from its gameplay event through `run_summary_tracker`, `run_summary_recorder`, peer summary overrides, and persisted progress. An evaluator fix alone does not repair missing or misattributed evidence.
- Keep personal criteria tied to the player: local input owns primary-attack counts, and boss no-hit evidence requires a matching engagement and that participant's damage history. A teammate's hits or attacks must not decide another player's Oaths.
- Checkpoint saves must retain prior attacks, damage, rest visits, completed encounter evidence, and elapsed run time. Legacy saves with unknown history must not treat missing counters as zero; preserve known build data and reject only criteria whose evidence is incomplete.
- Match completion scope to the description: completed boss/Hold encounters can qualify after a later run loss, while `win_*` and Ascension-clear criteria require a full clear. Debug runs must never persist Oath or Ascension awards.
- Ascension effects and rank awards require the actual Forsworn run tier, including host-selected co-op and restored checkpoints. Preserve the exact active modifier loadout in saves; legacy runs lacking modifier history may continue, but cannot establish new Ascension rank records or Oaths. Re-saving must preserve that incomplete evidence, while a fresh retry begins new evidence.
- Verify both success and disqualification paths, joined-player summaries, and save/resume in isolated tests before attributing poor Oath completion rates to balance.

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
1. **Damage received proxy** (`boredom_proxy.long_low_engagement_runs`): long runs with very few damage events. This also describes skilled avoidance; it does not measure attacks, activity, boredom, or enjoyment. Use it only to choose a run for qualitative review.
2. **Arcana outcome depth** (`arcana_outcomes.avg_max_depth`): how far players get with each opening arcana. Low avg depth on frequently-picked arcana suggests it felt compelling but failed to deliver.
3. **Death timing** (`death_timing`): if median death depth is in the first quarter of rooms, players aren't reaching the designed late-game experience.
4. **Character diversity** (`character_popularity`): when players cluster on one character, they are either optimizing heavily or the other options feel unrewarding.
Synthesize these four signals into POSITIVE / MIXED / NEGATIVE. Always state which signals drove the assessment and note that this is not a direct player satisfaction measure.

## Full Analysis Workflow (17 Dimensions)
When a full analysis is requested, work through all 17 dimensions in order. The dedicated Telemetry Analyst agent applies this workflow automatically via `fetch_latest_version_analysis.ps1`. The framework prioritizes decision quality and strategic diversity over numerical symmetry — popularity alone is not a flag.

| # | Dimension | Key Fields | Flag Threshold |
|---|-----------|------------|----------------|
| D1 | Dataset quality | run_count, outcomes, character/bearing skew | WARN < 10 runs; STOP < 5 |
| D2 | Difficulty calibration | outcomes (clear rate), death_timing | FLAG < 10% or > 70% clear rate |
| D3 | Arcana dominance | top_arcana_picks, arcana_outcomes, archetype overlap | FLAG only if high pick rate + high success + cross-archetype + suppresses alternatives + low opportunity cost |
| D4 | Arcana viability | never_picked_arcana, arcana_pick_rates | FLAG offered ≥2 and never picked; FLAG pick_rate < 20% with meaningful offers |
| D5 | Arcana outcome correlation | arcana_outcomes | FLAG death_rate > 80% with ≥3 runs; FLAG clear_rate > 60% with ≥3 runs |
| D6 | Strategic diversity | build variation, archetype entropy | FLAG if successful runs converge to same path |
| D7 | Build lock-in timing | early-pick predictiveness | FLAG if first 20–30% of run predicts outcome |
| D8 | Boon dominance & viability | top_boon_picks, boon_pick_rates | FLAG dominant boon suppressing alternatives |
| D9 | Encounter pressure | encounter_pressure.damage_per_entry | FLAG if ≥ 2× median |
| D10 | Death concentration | encounter_pressure.deaths_per_100_entries, top_death_sources | FLAG > 50; WATCH > 25 |
| D11 | Learnability | first-seen lethality, repeat deaths to same source | FLAG high first-time lethality |
| D12 | Engagement & retention proxy | boredom_proxy, low_engagement_share | FLAG > 15%; WATCH > 8% |
| D13 | Character popularity | character_popularity | FLAG < 15% usage with meaningful availability |
| D14 | Character performance | character_popularity, character_by_bearing | FLAG > 30 pts below/above avg clear rate |
| D15 | Encounter selection & avoidance | encounter_pressure.entries (share) | FLAG non-boss < 5% of total entries |
| D16 | Cognitive load proxy | low-pick / high-success options | FLAG strong options consistently ignored |
| D17 | Fun & design health synthesis | D6 + D7 + D12 + D2 + D13 + diversity | POSITIVE / MIXED / NEGATIVE (proxy only) |

After flagging, run a counterfactual pass on each major FLAG: classify as irrelevant, foundational, oppressive, diversity-enabling, or trap option to avoid overcorrecting healthy asymmetry.

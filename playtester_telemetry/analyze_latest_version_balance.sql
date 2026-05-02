-- ============================================================
-- Latest-Version Balance Analysis (All Runs)
-- Paste into Supabase SQL Editor and run as one script.
--
-- This script:
-- 1) auto-detects latest game_version from non-debug runs
-- 2) scopes to all non-debug runs in that version
-- 3) outputs balance-oriented slices for decision quality, deaths,
--    encounter pressure, reward behavior, objective pain, and boredom proxies
--
-- NOTE: reward_choices captures selected choices; true pick-rate needs
-- reward_offers instrumentation to be present for the analyzed version.
-- ============================================================

-- 0) Scope and cache latest-version runs
-- ------------------------------------------------------------
drop table if exists pg_temp._latest_version_runs;
create temporary table pg_temp._latest_version_runs as
with latest_version as (
  select game_version
  from public.telemetry_runs
  where is_debug = false
  order by ended_at_unix desc nulls last, started_at_unix desc
  limit 1
)
select r.*
from public.telemetry_runs r
join latest_version v on v.game_version = r.game_version
where r.is_debug = false;

-- 1) Dataset quality and framing
-- ------------------------------------------------------------
with base as (
  select
    count(*) as run_count,
    min(started_at_unix) as first_started_at_unix,
    max(ended_at_unix) as last_ended_at_unix,
    min(game_version) as game_version
  from pg_temp._latest_version_runs
),
quality as (
  select
    count(*) filter (where outcome = 'death' and coalesce(death_event, '{}'::jsonb) = '{}'::jsonb) as deaths_missing_death_event,
    count(*) filter (where jsonb_array_length(damage_events) >= 500) as runs_at_damage_cap,
    count(*) filter (where outcome = 'in_progress') as unfinished_runs
  from pg_temp._latest_version_runs
)
select
  b.game_version,
  b.run_count,
  to_timestamp(b.first_started_at_unix) as first_run_at,
  to_timestamp(b.last_ended_at_unix) as last_run_at,
  q.deaths_missing_death_event,
  q.runs_at_damage_cap,
  q.unfinished_runs
from base b
cross join quality q;

-- 2) Outcome mix by bearing (difficulty tier)
-- ------------------------------------------------------------
select
  case difficulty_tier
    when 0 then 'Pilgrim'
    when 1 then 'Delver'
    when 2 then 'Harbinger'
    when 3 then 'Forsworn'
    else 'Unknown'
  end as bearing,
  outcome,
  count(*) as run_count,
  round(100.0 * count(*) / nullif(sum(count(*)) over (partition by difficulty_tier), 0), 1) as bearing_outcome_pct
from pg_temp._latest_version_runs
group by difficulty_tier, outcome
order by difficulty_tier, run_count desc;

-- 3) Death timing and depth clustering
-- ------------------------------------------------------------
with deaths as (
  select
    run_id,
    difficulty_tier,
    max_depth,
    (death_event ->> 'room_depth')::int as death_depth,
    death_event ->> 'bearing_key' as death_encounter,
    death_event ->> 'source' as death_source,
    death_event ->> 'ability' as death_ability
  from pg_temp._latest_version_runs
  where outcome = 'death'
    and coalesce(death_event, '{}'::jsonb) <> '{}'::jsonb
)
select
  case difficulty_tier
    when 0 then 'Pilgrim'
    when 1 then 'Delver'
    when 2 then 'Harbinger'
    when 3 then 'Forsworn'
    else 'Unknown'
  end as bearing,
  coalesce(death_encounter, 'unknown') as death_encounter,
  coalesce(death_source, 'unknown') as death_source,
  coalesce(death_ability, 'unknown') as death_ability,
  count(*) as deaths,
  round(avg(death_depth::numeric), 2) as avg_death_depth,
  percentile_cont(0.5) within group (order by death_depth) as median_death_depth
from deaths
group by difficulty_tier, death_encounter, death_source, death_ability
order by deaths desc, avg_death_depth asc;

-- 4) Damage pressure by source and ability
-- ------------------------------------------------------------
with expanded_damage as (
  select
    r.run_id,
    d.source,
    d.ability,
    coalesce((d.final_amount)::numeric, 0) as final_amount,
    d.bearing_key,
    d.room_depth
  from pg_temp._latest_version_runs r,
       jsonb_to_recordset(r.damage_events) as d(
         unix_time bigint,
         source text,
         ability text,
         raw_amount numeric,
         final_amount numeric,
         health_before int,
         health_after int,
         room_label text,
         bearing_key text,
         room_depth int
       )
)
select
  coalesce(source, 'unknown') as source,
  coalesce(ability, 'unknown') as ability,
  count(*) as hit_count,
  round(sum(final_amount), 1) as total_final_damage,
  round(avg(final_amount), 2) as avg_final_damage_per_hit
from expanded_damage
group by source, ability
order by total_final_damage desc, hit_count desc;

-- 5) Encounter pressure normalized by exposure
-- ------------------------------------------------------------
with entries as (
  select
    e.bearing_key as encounter_key,
    count(*) as room_entries
  from pg_temp._latest_version_runs r,
       jsonb_to_recordset(r.room_entries) as e(
         unix_time bigint,
         room_kind text,
         room_label text,
         bearing_key text,
         bearing_label text,
         enemy_mutator text,
         objective_kind text,
         room_depth int,
         rooms_cleared int
       )
  group by e.bearing_key
),
damage as (
  select
    d.bearing_key as encounter_key,
    sum(coalesce((d.final_amount)::numeric, 0)) as total_final_damage,
    count(*) as damage_hits
  from pg_temp._latest_version_runs r,
       jsonb_to_recordset(r.damage_events) as d(
         unix_time bigint,
         source text,
         ability text,
         raw_amount numeric,
         final_amount numeric,
         health_before int,
         health_after int,
         room_label text,
         bearing_key text,
         room_depth int
       )
  group by d.bearing_key
),
deaths as (
  select
    (death_event ->> 'bearing_key') as encounter_key,
    count(*) as death_count
  from pg_temp._latest_version_runs
  where outcome = 'death'
    and coalesce(death_event, '{}'::jsonb) <> '{}'::jsonb
  group by (death_event ->> 'bearing_key')
)
select
  coalesce(e.encounter_key, d.encounter_key, x.encounter_key, 'unknown') as encounter_key,
  coalesce(e.room_entries, 0) as room_entries,
  coalesce(d.damage_hits, 0) as damage_hits,
  round(coalesce(d.total_final_damage, 0), 1) as total_final_damage,
  coalesce(x.death_count, 0) as death_count,
  round(coalesce(d.total_final_damage, 0) / nullif(e.room_entries, 0), 2) as damage_per_entry,
  round(100.0 * coalesce(x.death_count, 0) / nullif(e.room_entries, 0), 2) as deaths_per_100_entries
from entries e
full outer join damage d on d.encounter_key = e.encounter_key
full outer join deaths x on x.encounter_key = coalesce(e.encounter_key, d.encounter_key)
order by deaths_per_100_entries desc nulls last, damage_per_entry desc nulls last;

-- 6) Reward selection concentration (selection-frequency only)
-- ------------------------------------------------------------
with picks as (
  select
    case c.mode
      when 1 then 'BOON'
      when 3 then 'ARCANA'
      when 4 then 'MISSION'
      else 'OTHER'
    end as reward_mode,
    c.choice_id,
    c.choice_name,
    c.is_initial,
    r.run_id
  from pg_temp._latest_version_runs r,
       jsonb_to_recordset(r.reward_choices) as c(
         unix_time bigint,
         mode int,
         choice_id text,
         choice_name text,
         is_initial boolean,
         room_depth int
       )
),
counts as (
  select
    reward_mode,
    choice_id,
    min(choice_name) as choice_name,
    count(*) as pick_count,
    count(distinct run_id) as runs_with_pick,
    count(*) filter (where is_initial) as initial_pick_count
  from picks
  group by reward_mode, choice_id
),
totals as (
  select reward_mode, sum(pick_count) as mode_total
  from counts
  group by reward_mode
)
select
  c.reward_mode,
  c.choice_id,
  c.choice_name,
  c.pick_count,
  c.runs_with_pick,
  c.initial_pick_count,
  round(100.0 * c.pick_count / nullif(t.mode_total, 0), 2) as mode_pick_share_pct
from counts c
join totals t on t.reward_mode = c.reward_mode
order by c.reward_mode, mode_pick_share_pct desc, c.pick_count desc;

-- 7) Character popularity and opening arcana
-- ------------------------------------------------------------
select
  coalesce(nullif(trim(character_id), ''), 'unknown') as character_id,
  count(*) as run_count,
  round(100.0 * count(*) / nullif(sum(count(*)) over (), 0), 2) as pick_share_pct
from pg_temp._latest_version_runs
group by coalesce(nullif(trim(character_id), ''), 'unknown')
order by run_count desc;

-- Opening arcana remains useful as a build-shape signal.
with arcana_picks as (
  select
    r.run_id,
    c.choice_id,
    c.choice_name,
    c.unix_time,
    row_number() over (partition by r.run_id order by c.unix_time asc) as rn
  from pg_temp._latest_version_runs r,
       jsonb_to_recordset(r.reward_choices) as c(
         unix_time bigint,
         mode int,
         choice_id text,
         choice_name text,
         is_initial boolean,
         room_depth int
       )
  where c.mode = 3
)
select
  choice_id as opening_arcana_id,
  min(choice_name) as opening_arcana_name,
  count(*) as run_count,
  round(100.0 * count(*) / nullif(sum(count(*)) over (), 0), 2) as pick_share_pct
from arcana_picks
where rn = 1
group by choice_id
order by run_count desc;

-- 8) Hold-the-Line objective pressure (including shielder contribution)
-- ------------------------------------------------------------
with room_objectives as (
  select
    r.run_id,
    e.room_depth,
    coalesce(e.objective_kind, '') as objective_kind
  from pg_temp._latest_version_runs r,
       jsonb_to_recordset(r.room_entries) as e(
         unix_time bigint,
         room_kind text,
         room_label text,
         bearing_key text,
         bearing_label text,
         enemy_mutator text,
         objective_kind text,
         room_depth int,
         rooms_cleared int
       )
),
damage as (
  select
    r.run_id,
    d.room_depth,
    d.source,
    coalesce((d.final_amount)::numeric, 0) as final_amount
  from pg_temp._latest_version_runs r,
       jsonb_to_recordset(r.damage_events) as d(
         unix_time bigint,
         source text,
         ability text,
         raw_amount numeric,
         final_amount numeric,
         health_before int,
         health_after int,
         room_label text,
         bearing_key text,
         room_depth int
       )
),
joined as (
  select
    ro.objective_kind,
    dm.source,
    dm.final_amount
  from damage dm
  join room_objectives ro
    on ro.run_id = dm.run_id
   and ro.room_depth = dm.room_depth
)
select
  case when objective_kind = 'hold_the_line' then 'hold_the_line' else 'other_or_none' end as objective_group,
  count(*) as hit_count,
  round(sum(final_amount), 1) as total_final_damage,
  round(sum(case when source = 'enemy_shielder' then final_amount else 0 end), 1) as shielder_damage,
  round(100.0 * sum(case when source = 'enemy_shielder' then final_amount else 0 end) / nullif(sum(final_amount), 0), 2) as shielder_damage_share_pct
from joined
group by objective_group
order by total_final_damage desc;

-- 9) Boredom and running-in-circles proxy signals
-- ------------------------------------------------------------
with run_stats as (
  select
    run_id,
    outcome,
    greatest(ended_at_unix - started_at_unix, 1) as duration_seconds,
    jsonb_array_length(damage_events) as damage_event_count,
    jsonb_array_length(room_entries) as room_entry_count,
    jsonb_array_length(door_choices) as door_choice_count,
    jsonb_array_length(reward_choices) as reward_choice_count
  from pg_temp._latest_version_runs
),
features as (
  select
    *,
    round(damage_event_count::numeric / nullif(duration_seconds / 60.0, 0), 2) as damage_events_per_min,
    round(door_choice_count::numeric / nullif(room_entry_count, 0), 2) as door_choices_per_room,
    round(reward_choice_count::numeric / nullif(room_entry_count, 0), 2) as rewards_per_room
  from run_stats
)
select
  count(*) as run_count,
  round(avg(duration_seconds) / 60.0, 2) as avg_run_minutes,
  round(avg(damage_events_per_min), 2) as avg_damage_events_per_min,
  round(avg(door_choices_per_room), 2) as avg_door_choices_per_room,
  round(avg(rewards_per_room), 2) as avg_rewards_per_room,
  count(*) filter (
    where duration_seconds > (select percentile_cont(0.75) within group (order by duration_seconds) from features)
      and damage_events_per_min < (select percentile_cont(0.25) within group (order by damage_events_per_min) from features)
  ) as long_low_engagement_runs
from features;

-- 10) Heuristic flags for recommendation triage
-- ------------------------------------------------------------
with deaths as (
  select
    coalesce(death_event ->> 'source', 'unknown') as death_source,
    count(*) as deaths
  from pg_temp._latest_version_runs
  where outcome = 'death'
    and coalesce(death_event, '{}'::jsonb) <> '{}'::jsonb
  group by coalesce(death_event ->> 'source', 'unknown')
),
shielder as (
  select coalesce(sum(deaths), 0) as shielder_deaths
  from deaths
  where death_source = 'enemy_shielder'
),
total_deaths as (
  select coalesce(sum(deaths), 0) as total_deaths
  from deaths
),
arcana_concentration as (
  select
    max(pick_count)::numeric / nullif(sum(pick_count)::numeric, 0) as top_arcana_pick_share
  from (
    select c.choice_id, count(*) as pick_count
    from pg_temp._latest_version_runs r,
         jsonb_to_recordset(r.reward_choices) as c(
           unix_time bigint,
           mode int,
           choice_id text,
           choice_name text,
           is_initial boolean,
           room_depth int
         )
    where c.mode = 3
    group by c.choice_id
  ) x
),
voidfire as (
  select count(*) as voidfire_picks
  from pg_temp._latest_version_runs r,
       jsonb_to_recordset(r.reward_choices) as c(
         unix_time bigint,
         mode int,
         choice_id text,
         choice_name text,
         is_initial boolean,
         room_depth int
       )
  where c.choice_id = 'voidfire'
),
base as (
  select (select total_deaths from total_deaths) as total_deaths,
         (select shielder_deaths from shielder) as shielder_deaths,
         (select top_arcana_pick_share from arcana_concentration) as top_arcana_pick_share,
         (select voidfire_picks from voidfire) as voidfire_picks
)
select
  total_deaths,
  shielder_deaths,
  round(100.0 * shielder_deaths / nullif(total_deaths, 0), 2) as shielder_death_share_pct,
  round(100.0 * coalesce(top_arcana_pick_share, 0), 2) as top_arcana_pick_share_pct,
  voidfire_picks,
  case
    when total_deaths >= 20 and (100.0 * shielder_deaths / nullif(total_deaths, 0)) >= 22.0
      then 'FLAG: Hold-the-Line shielder pressure likely overtuned in at least one bearing/depth band'
    else 'OK: Shielder death share not in high-risk band'
  end as hold_line_shielder_flag,
  case
    when coalesce(top_arcana_pick_share, 0) >= 0.30
      then 'FLAG: Arcana concentration high; likely dominant pick or strongest-fun overlap'
    else 'OK: Arcana concentration moderate'
  end as arcana_diversity_flag,
  case
    when voidfire_picks > 0
      then 'NOTE: Voidfire observed in runs; pair telemetry with card readability fix validation'
    else 'NOTE: Voidfire not observed in this version window'
  end as voidfire_observation
from base;

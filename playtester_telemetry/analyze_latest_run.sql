-- ============================================================
-- Latest Run Analysis
-- Paste into Supabase SQL Editor and run.
-- Filters to the most recent non-debug production run.
-- ============================================================

-- ── 0. Pick the run ─────────────────────────────────────────
-- Change is_debug filter or add WHERE run_id = '...' to pin a specific run.
with latest as (
  select *
  from public.telemetry_runs
  where is_debug = false
  order by started_at_unix desc
  limit 1
),

-- ── 1. Run header ────────────────────────────────────────────
header as (
  select
    run_id,
    to_timestamp(started_at_unix)  as started_at,
    to_timestamp(ended_at_unix)    as ended_at,
    round((ended_at_unix - started_at_unix) / 60.0, 1) as duration_minutes,
    game_version,
    case difficulty_tier
      when 0 then 'Pilgrim'
      when 1 then 'Delver'
      when 2 then 'Harbinger'
      when 3 then 'Forsworn'
      else 'Unknown'
    end as bearing,
    outcome,
    max_depth,
    rooms_cleared,
    aggregate -> 'damage_event_count'   as damage_events_total,
    aggregate -> 'reward_choice_count'  as reward_choices_total,
    aggregate -> 'door_choice_count'    as door_choices_total,
    aggregate -> 'room_entry_count'     as room_entries_total
  from latest
),

-- ── 2. Damage by source ──────────────────────────────────────
dmg_by_source as (
  select
    e.source,
    count(*)            as hit_count,
    sum((e.amount)::int) as total_damage
  from latest,
       jsonb_to_recordset(latest.damage_events)
         as e(source text, ability text, amount numeric,
              bearing_key text, room_depth int)
  group by e.source
  order by total_damage desc
),

-- ── 3. Damage by ability ─────────────────────────────────────
dmg_by_ability as (
  select
    e.ability,
    count(*)            as hit_count,
    sum((e.amount)::int) as total_damage
  from latest,
       jsonb_to_recordset(latest.damage_events)
         as e(source text, ability text, amount numeric,
              bearing_key text, room_depth int)
  group by e.ability
  order by total_damage desc
),

-- ── 4. Damage by encounter type ──────────────────────────────
dmg_by_encounter as (
  select
    coalesce(e.bearing_key, 'unknown') as encounter_type,
    count(*)            as hit_count,
    sum((e.amount)::int) as total_damage
  from latest,
       jsonb_to_recordset(latest.damage_events)
         as e(source text, ability text, amount numeric,
              bearing_key text, room_depth int)
  group by encounter_type
  order by total_damage desc
),

-- ── 5. Room path (in order) ──────────────────────────────────
room_path as (
  select
    (e.room_depth)::int                     as depth,
    e.room_label,
    e.bearing_key                           as encounter_type,
    e.enemy_mutator,
    coalesce(e.objective_kind, 'none')      as objective_kind,
    (e.rooms_cleared)::int                  as rooms_cleared_at_entry
  from latest,
       jsonb_to_recordset(latest.room_entries)
         as e(room_label text, bearing_key text, bearing_label text,
              enemy_mutator text, objective_kind text,
              room_depth int, rooms_cleared int)
  order by rooms_cleared_at_entry, depth
),

-- ── 6. Door choices ──────────────────────────────────────────
doors as (
  select
    (e.room_depth)::int     as depth,
    e.bearing_key           as chosen_encounter_type,
    e.bearing_label         as chosen_label
  from latest,
       jsonb_to_recordset(latest.door_choices)
         as e(bearing_key text, bearing_label text, room_depth int)
  order by depth
),

-- ── 7. Rewards taken ─────────────────────────────────────────
rewards as (
  select
    e.mode,
    e.choice_id,
    row_number() over () as pick_order
  from latest,
       jsonb_to_recordset(latest.reward_choices)
         as e(mode text, choice_id text)
  order by pick_order
),

-- ── 8. Death event ───────────────────────────────────────────
death as (
  select
    latest.death_event ->> 'source'      as death_source,
    latest.death_event ->> 'ability'     as death_ability,
    latest.death_event ->> 'bearing_key' as death_encounter,
    (latest.death_event ->> 'room_depth')::int as death_depth
  from latest
  where latest.death_event <> '{}'::jsonb
)

-- ── OUTPUT SECTION: uncomment one block at a time ────────────

-- 1. Run header
select * from header;

-- 2. Damage by source
-- select * from dmg_by_source;

-- 3. Damage by ability
-- select * from dmg_by_ability;

-- 4. Damage by encounter type
-- select * from dmg_by_encounter;

-- 5. Room path
-- select * from room_path;

-- 6. Door choices
-- select * from doors;

-- 7. Rewards taken
-- select * from rewards;

-- 8. Death event
-- select * from death;

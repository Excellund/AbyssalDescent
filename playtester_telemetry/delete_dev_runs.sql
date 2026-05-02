-- Deletes all dev/debug runs from telemetry_runs.
-- Targets:
--   is_debug = true               (flagged debug runs)
--   game_version = 'dev'          (default version string when no version is set)
--   game_version ilike '%dev%'    (any version string containing "dev")
--   game_version ilike '%debug%'  (any version string containing "debug")
--   game_version = ''             (empty version, should not exist but clean up anyway)
--
-- Run this in the Supabase SQL editor. Safe to re-run.
-- Preview first with the SELECT below, then uncomment the DELETE.

-- PREVIEW (shows what will be deleted):
select id, run_id, game_version, is_debug, started_at_unix, outcome
from public.telemetry_runs
where
    is_debug = true
    or lower(trim(game_version)) = 'dev'
    or lower(trim(game_version)) like '%dev%'
    or lower(trim(game_version)) like '%debug%'
    or trim(game_version) = ''
order by started_at_unix desc;

-- DELETE (uncomment and run once preview looks correct):
-- delete from public.telemetry_runs
-- where
--     is_debug = true
--     or lower(trim(game_version)) = 'dev'
--     or lower(trim(game_version)) like '%dev%'
--     or lower(trim(game_version)) like '%debug%'
--     or trim(game_version) = '';

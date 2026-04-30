---
name: telemetry-upload
description: "Configure, repair, or extend the automatic playtester telemetry upload pipeline. Use when adding new payload fields, changing the upload backend, fixing queue/retry behavior, updating consent UI, or migrating the Supabase schema."
argument-hint: "What to change (payload field, backend URL, consent flow, retry behavior) and why."
---

# Telemetry Upload Pipeline

Use this skill when touching the remote upload system for playtester data — consent, queue, HTTP sender, payload shape, or Supabase schema.

## Architecture Overview

```
Run end
  └─ world_generator._finish_active_run_telemetry()
       ├─ run_telemetry_store.gd  →  saves local copy (user://run_telemetry.save)
       └─ run_telemetry_store.build_upload_payload(run_id)
            └─ run_context.enqueue_telemetry_payload(payload)
                 └─ telemetry_upload_queue.gd  (user://telemetry_upload_queue.save)
                      └─ telemetry_uploader.gd  (10s timer flush → HTTP POST → Supabase)
```

## Key Files

| File | Role |
|---|---|
| scripts/run_telemetry_store.gd | `build_upload_payload(run_id)` — assembles full remote payload |
| scripts/telemetry_upload_queue.gd | Durable local queue: `enqueue()`, `get_ready_entries()`, `mark_success()`, `mark_failure()` |
| scripts/telemetry_uploader.gd | Background node; 10s timer flush + immediate flush on enqueue. Exponential backoff capped at 900s. |
| scripts/run_context.gd | Consent state (`telemetry_upload_enabled`, `telemetry_consent_asked`). Instantiates uploader as child. |
| scripts/settings_store.gd | Persists consent flags under `[telemetry]` section in `user://settings.cfg` |
| scripts/menu_controller.gd | First-launch consent prompt (`_maybe_show_telemetry_consent_prompt`), options toggle |
| scripts/pause_menu_controller.gd | In-run telemetry toggle checkbox |
| playtester_telemetry/supabase_production_setup.sql | Live schema; safe to rerun as migration |

## Supabase Configuration

- Project ref: `aizoebowshcnqvuizava`
- Endpoint: `https://aizoebowshcnqvuizava.supabase.co/rest/v1/telemetry_runs`
- API key type: anon/publishable (safe to ship in client)
- Key stored in `project.godot` under:
  - `config/telemetry_upload_endpoint`
  - `config/telemetry_upload_api_key`
- RLS insert policy validates array/object types and bounds; no read policy (write-only from client)

## Payload Shape

`build_upload_payload(run_id)` returns a dict with these top-level keys:

```
run_id, started_at_unix, ended_at_unix, game_version,
difficulty_tier, run_mode, outcome, max_depth, rooms_cleared,
is_debug, upload_source,
death_event,          # dict or null
aggregate,            # summary dict (outcomes, damage_by_*, etc.)
damage_events,        # Array of raw damage event dicts
reward_choices,       # Array of raw reward choice dicts
room_entries,         # Array of raw room entry dicts
door_choices          # Array of raw door choice dicts
```

When adding a new telemetry field:
1. Record it in `run_telemetry_store.gd` (event recording path)
2. Add it to `build_upload_payload()` in `run_telemetry_store.gd`
3. Add the column to `playtester_telemetry/supabase_production_setup.sql` using `ADD COLUMN IF NOT EXISTS`
4. Apply the migration in Supabase SQL editor

## Consent Flow

- First launch: `menu_controller._maybe_show_telemetry_consent_prompt()` shows a modal
- User choices: **Allow** sets `telemetry_upload_enabled=true, telemetry_consent_asked=true`; **Not Now** sets `telemetry_upload_enabled=false, telemetry_consent_asked=true`
- Both flags persist to `user://settings.cfg` via `settings_store`
- Consent is only asked once; prompt is skipped if `telemetry_consent_asked=true`
- Player can change the setting anytime via Options (menu or pause screen)

## Queue and Retry

- Queue file: `user://telemetry_upload_queue.save` (binary, versioned)
- Each entry has: payload, `retry_count`, `next_retry_at` (unix timestamp)
- Uploader sends one entry per tick; on HTTP success calls `mark_success()`
- On failure: `mark_failure()` applies exponential backoff with jitter, capped at 900s
- Upload is skipped entirely if `run_context.is_telemetry_upload_enabled()` returns false

## Debug Runs

- Debug runs are uploaded with `is_debug: true` in the payload
- Filter in Supabase queries: `WHERE is_debug = false` for production balance data
- To strip debug uploads entirely: check `is_debug` in `world_generator._finish_active_run_telemetry()` before calling `run_context.enqueue_telemetry_payload()`

## Spike / Connectivity Probe

- `scripts/telemetry_spike_sender.gd` — one-shot probe, debug only
- Controlled by `debug_settings.gd` exports: `telemetry_spike_enabled`, `telemetry_spike_endpoint`, `telemetry_spike_api_key`, `telemetry_spike_timeout_seconds`
- Set `telemetry_spike_enabled = false` in `scenes/Main.tscn` DebugSettings node once the production path is confirmed stable

## Schema Migration Pattern

Always use `ADD COLUMN IF NOT EXISTS` in `supabase_production_setup.sql` so the file is safe to rerun:

```sql
ALTER TABLE public.telemetry_runs
  ADD COLUMN IF NOT EXISTS my_new_column jsonb;
```

Then apply in Supabase SQL editor. Do not DROP and recreate columns — live data will be lost.

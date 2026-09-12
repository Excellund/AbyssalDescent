# Recent damage and defeat recap

Implemented September 12, 2026 under the user's explicit request to add new features outside the feedback queue on a new branch. No feedback priority or acceptance state changed.

## Player behavior

Results and Run History show the most recent six accepted damage events for that player. The newest entry appears first, with an authored enemy/environment source name, health actually lost, before/after HP, recorded run time and depth. A lethal entry is called **Final damage** only when the run ended in defeat, the player's final recorded health is zero, and the latest health transition is that accepted damage event.

Healing and revival do not erase earlier damage. The panel explains that they can occur between entries. A revival or an unattributed health change removes final-damage eligibility until another accepted damaging transition occurs. Earlier downings remain truthful damage entries, without being advertised as the cause of a later unexplained death. Unknown damage IDs display a neutral source label. Older runs and checkpoints without this evidence omit the panel; aggregate damage totals and old death events do not fabricate a sequence.

The panel precedes the build summary. Existing Results content and action buttons remain in their established order. Results compensate for downscaling the production 2560×1440 canvas so their card and text retain usable physical size in smaller windows. The local MSDF font helper keeps that scaled text crisp without changing the game's global theme. The new source labels use 18-pixel text and supporting lines use 15-pixel text after the stretch transform; content remains scrollable while retry/menu controls stay visible.

## Data and accepted-damage boundary

`scripts/core/damage_recap.gd` owns the bounded evidence normalization and shared `presentation(summary)` API. `scripts/shared/damage_source_catalogue.gd` maps existing ability IDs to player-facing names without loading enemy scenes. `scripts/ui/run_summary/damage_recap_panel.gd` is reused by Results and History.

Summary/checkpoint key `damage_recap` has version 1, `entries`, `ending_health`, `ending_on_damage` and `peer_id`. Entries persist oldest-first and contain `source`, `ability`, `health_before`, `health_after`, derived `health_lost`, `raw_amount`, `final_amount`, `elapsed_seconds` and `room_depth`. The presentation API returns safe plain labels in newest-first order. It rejects malformed numeric fields and arbitrary source text; overkill never inflates displayed HP lost. Only six entries are retained, independent of total run length.

Player damage already resolves immunity, armor, resistance and incoming modifiers before applying HealthState damage. HealthState emits `health_changed` and `died` synchronously. Previously `last_damage_event` was assigned after those signals, allowing death summaries to contain the preceding source. The Player now publishes the resolved clamped health context and a local sequence number immediately before that synchronous mutation. Existing signal order, damage amount, feedback and immunity behavior remain unchanged. The recorder consumes that context through the existing health callback; sequence checks prevent a later reconciliation or health notification from recording it again.

The run tracker keeps separate bounded recaps for each player. Doorway checkpoints persist only the local player's recap, rebinding it to the local identity on resume. Retry/reset clears the evidence. Multiplayer outcome overrides carry each player's own recap, and a missing override cannot substitute the host's damage for another player's. No new damage RPC or enemy behavior is introduced.

## Joining-peer outcome ordering

Real ENet testing exposed an existing race: host HP0 reached a joining player before the host's outcome payload. The joiner's synchronous death callback wrote an incomplete local summary and marked it finished; the later authoritative result appeared on screen but was skipped by the persistence finalizer.

The joining peer now presents that provisional defeat immediately but waits for the authoritative outcome before persisting History, evaluating endgame progression or enqueuing a submission. If the authoritative result never arrives, existing `host_left`, `menu_exit` and `quit` terminal paths still finalize once. Repeated provisional/final callbacks cannot rewrite the saved record or evaluate progression twice. Solo and host outcomes remain immediate. No remote telemetry or leaderboard eligibility rule changes.

## Verification

- Final isolated compilation: 420 GDScript files, world-property guard and multiplayer-configuration guard passed.
- `test_damage_recap.gd`: 68 checks cover actual Player damage and synchronous fatal History, clamped overkill, zero/immune damage, healing, revival, unknown health loss, per-peer ownership, JSON/real checkpoint persistence, legacy/malformed data, bounded history, native panel reuse and delayed/duplicate/fallback outcome finalization. Final evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-e59a376f9b53431eb9c28eec5225c73e`.
- Existing checkpoint isolation: 43 checks; run provenance: 178 checks; party provenance: 11 checks. Evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-validation-b652418918d540b080bf5a8e829df00a`.
- `render_damage_recap.gd`: eight actual-window captures with the production canvas preserved, 296 checks on RTX 4080. It verifies final/older/revived/legacy states at 960- and 1280-pixel window widths, physical text size through the real stretch transform, scrolling and fixed action availability. Final MSDF evidence: `C:/Users/mikel/AppData/Local/Temp/abyssal-gameplay-render-a2e743b4875c491e99e4ceac6e1d8768/damage_recap_frames`. Final and revived MSDF frames inspected visually; all eight prior-layout frames also inspected.
- `test_damage_recap_enet.gd` extends the existing native Main-scene revival harness. It stages accepted damage on the host, performs actual encounter-clear revival and party defeat, and checks the production outcome RPC, local peer overrides, per-process disk histories and repeated authoritative outcomes. **41 host and 41 client checks passed** in `C:/Users/mikel/AppData/Local/Temp/abyssal-enet-3d81ba8a542146c59273436465c33d1c`.

Run focused checks with `.github/scripts/run_gameplay_regressions.ps1 -TestScripts @('res://scripts/tests/test_damage_recap.gd','res://scripts/tests/test_checkpoint_isolation.gd','res://scripts/tests/test_run_provenance.gd','res://scripts/tests/test_party_provenance.gd')`. Use `test_boss_combinations_enet.ps1 -FixtureScript res://scripts/tests/test_damage_recap_enet.gd -FixtureTimeoutSeconds 90` with an isolated validation project for the native network check. Use `render_gameplay_fixture.ps1 -FixtureScript res://scripts/tests/render_damage_recap.gd -FrameFolder damage_recap_frames -ExpectedFrames 8 -PreserveProductionCanvas` for native presentation review.

No commit, push, desktop export or human playtest acceptance is implied by this feature record.

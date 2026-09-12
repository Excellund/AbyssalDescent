extends "res://scripts/tests/test_checkpoint_isolation.gd"

const RECAP := preload("res://scripts/core/damage_recap.gd")
const TRACKER := preload("res://scripts/core/run_summary_tracker.gd")
const MODEL := preload("res://scripts/core/run_summary_model.gd")
const PANEL := preload("res://scripts/ui/run_summary/damage_recap_panel.gd")

class CountingRecorder extends "res://scripts/core/run_summary_recorder.gd":
	var progression_calls: int = 0
	func _apply_endgame_chase_progress(summary: Dictionary) -> void:
		progression_calls += 1
		super._apply_endgame_chase_progress(summary)

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Damage recap requires an isolated project and user profile")
		quit(1)
		return
	_test_normalization()
	await _test_accepted_damage_and_final_order()
	await _test_revival_and_peer_ownership()
	await _test_checkpoint()
	await _test_joiner_terminal_lifecycle()
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()
	HISTORY.clear_all()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await create_timer(0.1).timeout
	print("[OK] Damage recap: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _wire_health() -> void:
	for actor in actors:
		actor.health_changed.connect(Callable(world, "_on_player_health_changed_for_summary").bind(actor))
		actor.set_combat_damage_enabled(true)
		actor.iron_skin_armor = 0
		actor.incoming_damage_taken_mult = 1.0
		actor.health_state.setup(100, 100)
	world.room_depth = 7
	world.current_room_label = "Crossfire"

func _event(before: int, after: int, ability: String = "archer_projectile") -> Dictionary:
	return {"source": "enemy_ability", "ability": ability, "health_before": before,
		"health_after": after, "elapsed_seconds": 93, "room_depth": 7,
		"raw_amount": before - after, "final_amount": before - after}

func _test_normalization() -> void:
	for value in [null, {}, [], "old", {"version": 2, "entries": []}, {"version": 1, "entries": "bad"}]:
		check(RECAP.normalize(value).is_empty(), "Missing/unknown recap never fabricates damage")
	check(not RECAP.presentation({"outcome": "death", "death_event": _event(10, 0), "stats": {"damage_taken_total": 100}}).visible, "Legacy total and death event do not fabricate a recent-damage sequence")
	for value in [_event(0, 0), _event(20, 25), _event(25, -1), {"health_before": "20", "health_after": 0}, {"health_before": NAN, "health_after": 0}]:
		check(RECAP.entry(value).is_empty(), "Reject malformed, healing or zero-loss damage entries")
	var recap: Dictionary = {}
	for index in range(10):
		recap = RECAP.record_health(recap, 99 - index, _event(100 - index, 99 - index))
	check(recap.entries.size() == 6 and recap.entries.front().health_before == 96, "Ring retains exactly the last six accepted damage events")
	var malformed := _event(40, 0, "[b]invented source[/b]")
	malformed.source = "[url=bad]"
	var safe := RECAP.presentation({"outcome": "death", "damage_recap": RECAP.record_health({}, 0, malformed)})
	check(safe.title == "Final damage" and safe.entries[0].label == "Unknown source", "Future/untrusted IDs cannot invent names or formatting")
	var invalid_tail := RECAP.record_health({}, 0, _event(10, 0))
	invalid_tail.entries.append("missing last event")
	check(RECAP.presentation({"outcome": "death", "damage_recap": invalid_tail}).title == "Recent damage", "Malformed final entry cannot promote an older lethal event to the final blow")
	var changed := recap.duplicate(true)
	changed.entries[0].health_lost = 9999
	check(RECAP.normalize(changed).entries[0].health_lost == 1, "Health lost is derived from actual before/after, not caller amount")
	var presentation := RECAP.presentation({"outcome": "clear", "damage_recap": recap})
	check(presentation.title == "Recent damage" and not presentation.entries[0].is_final, "A victory never calls recent damage fatal")
	var normalized := MODEL.create_summary({"damage_recap": changed})
	check(normalized.damage_recap.entries[0].health_lost == 1, "Summary model sanitizes recap evidence")
	var panel := PANEL.new()
	root.add_child(panel)
	panel.set_summary({"damage_recap": recap})
	check(panel.visible and panel.get_child_count() == 14, "Native panel renders bounded damage rows")
	panel.set_summary({})
	check(not panel.visible and panel.get_child_count() == 0, "Reused native panel clears old damage when next summary has no evidence")
	panel.free()

func _test_accepted_damage_and_final_order() -> void:
	_setup("solo")
	_wire_health()
	var actor := actors[0]
	var recorder = world.run_summary_recorder
	actor.take_damage(13, {"source": "enemy_ability", "ability": "archer_projectile"})
	var recap: Dictionary = recorder.run_summary_tracker.get_damage_recap()
	check(recap.entries.size() == 1 and recap.entries[0].health_lost == 13, "Actual accepted damage is recorded through the production health signal")
	actor.take_damage(0, {"source": "enemy_ability", "ability": "warden_nova"})
	actor.set_combat_damage_enabled(false)
	actor.take_damage(15, {"source": "enemy_ability", "ability": "warden_nova"})
	actor.set_combat_damage_enabled(true)
	actor._dash_damage_immune_left = 1.0
	actor.take_damage(15, {"source": "enemy_contact", "ability": "chaser_strike"})
	actor._dash_damage_immune_left = 0.0
	check(recorder.run_summary_tracker.get_damage_recap().entries.size() == 1, "Zero damage, paused combat and dash immunity add no entry")
	actor.health_state.heal(5)
	check(not recorder.run_summary_tracker.get_damage_recap().ending_on_damage, "Healing clears final-damage eligibility without erasing previous entries")
	actor.died.connect(Callable(world, "_on_player_died"))
	var health_before := actor.get_current_health()
	actor.take_damage(1000, {"source": "enemy_ability", "ability": "warden_nova"})
	var saved: Array = HISTORY.load_all()
	check(saved.size() == 1, "Real synchronous death writes exactly one terminal history record")
	if not saved.is_empty():
		var final: Dictionary = saved[0].damage_recap.entries.back()
		check(final.ability == "warden_nova" and final.health_after == 0, "Saved recap contains the actual final blow before damage_taken returns")
		check(final.health_lost == health_before and final.final_amount == 1000, "Overkill displays only HP actually lost and retains resolved incoming amount separately")
		check(saved[0].death_event.ability == "warden_nova", "Existing death-event bookkeeping also sees the final source")
		check(RECAP.presentation(saved[0]).entries[0].is_final, "Terminal presentation identifies the accepted final damage")
	recorder.reconcile_damage_taken_to_player_health()
	check(recorder.run_summary_tracker.get_damage_recap().entries.size() == 2, "Repeated reconciliation cannot duplicate the final damage")
	await _cleanup()

func _test_revival_and_peer_ownership() -> void:
	_setup("host")
	MultiplayerSessionManager.session_connected = false
	_wire_health()
	var recorder = world.run_summary_recorder
	actors[0].take_damage(10, {"source": "enemy_ability", "ability": "archer_projectile"})
	actors[1].take_damage(1000, {"source": "enemy_contact", "ability": "charger_charge"})
	var other: Dictionary = recorder.run_summary_tracker.get_damage_recap(2)
	check(other.entries.size() == 1 and other.entries[0].ability == "charger_charge", "Host records the struck peer's own damage sequence")
	check(recorder.run_summary_tracker.get_damage_recap().entries[0].ability == "archer_projectile", "Remote damage never enters the host's local recap")
	actors[1].revive_with_health(40)
	other = recorder.run_summary_tracker.get_damage_recap(2)
	check(other.ending_health > 0 and not other.ending_on_damage, "Real revival ends the old downing without inventing a new damage entry")
	actors[1].health_state.set_health(0)
	other = recorder.run_summary_tracker.get_damage_recap(2)
	check(RECAP.presentation({"outcome": "death", "damage_recap": other}).title == "Recent damage", "An unattributed later health drop cannot label a pre-revival blow as final")
	actors[1].revive_with_health(40)
	actors[1].take_damage(1000, {"source": "enemy_ability", "ability": "pyre_death_field"})
	var overrides: Dictionary = recorder.build_peer_summary_overrides()
	check(overrides[2].damage_recap.entries.back().ability == "pyre_death_field", "Per-peer outcome payload includes the real post-revival final source")
	world.fixture_peer = 2
	var local: Dictionary = recorder.summary_with_local_peer_overrides({"outcome": "death", "damage_recap": overrides[1].damage_recap}, overrides)
	check(local.damage_recap.peer_id == 2 and local.damage_recap.entries.back().ability == "pyre_death_field", "Outcome override gives the joining player their own recap")
	recorder.run_summary_tracker.local_damage_peer_id = 2
	local = recorder.summary_with_local_peer_overrides({"damage_recap": overrides[1].damage_recap}, {})
	check(local.damage_recap.peer_id == 2, "Missing host overrides cannot leak another player's recap")
	await _cleanup()

func _test_checkpoint() -> void:
	_setup("solo")
	_wire_health()
	actors[0].take_damage(7, {"source": "enemy_ability", "ability": "biome_storm_reach"})
	var snapshot: Dictionary = world._build_active_run_snapshot()
	check(snapshot.tracker_checkpoint.damage_recap.entries.size() == 1, "Real doorway checkpoint captures local recent damage")
	check(RunContext.save_active_run(snapshot), "Damage recap checkpoint writes through the normal save API")
	var loaded := RunContext.load_active_run()
	var tracker := TRACKER.new()
	tracker.reset_for_run({"local_peer_id": 8})
	tracker.restore_checkpoint(loaded.tracker_checkpoint)
	check(tracker.get_damage_recap().peer_id == 8 and tracker.get_damage_recap().entries[0].ability == "biome_storm_reach", "Resume preserves damage and rebinds evidence to the current local identity")
	tracker.restore_checkpoint({})
	check(tracker.get_damage_recap().is_empty(), "Legacy checkpoint cannot inherit stale recap state")
	tracker.restore_checkpoint(loaded.tracker_checkpoint)
	tracker.reset_for_run({"local_peer_id": 8})
	check(tracker.get_damage_recap().is_empty(), "Retry/new run clears recap evidence")
	await _cleanup()

func _test_joiner_terminal_lifecycle() -> void:
	for outcome in ["death", "host_left", "menu_exit", "quit"]:
		_setup("joiner")
		var recorder := CountingRecorder.new(world)
		world.run_summary_recorder = recorder
		recorder.mark_run_start()
		recorder.initialize(false)
		recorder.finish_run("death")
		recorder.finish_run("death")
		check(HISTORY.load_all().is_empty() and not recorder.telemetry_run_finished, outcome + ": repeated provisional death cannot persist incomplete peer data")
		check(recorder.progression_calls == 0 and world.submitted_summaries.is_empty(), outcome + ": provisional death grants no progression or submission")
		var host_summary: Dictionary = recorder.latest_run_summary.duplicate(true)
		if outcome == "death":
			recorder.finalize_synced_run_summary_for_joiner(host_summary, "death")
		else:
			# Actual menu/host-loss callers can tear down the session first.
			MultiplayerSessionManager.session_connected = false
			recorder.finish_run(outcome)
		var records := HISTORY.load_all()
		check(records.size() == 1 and records[0].outcome == outcome, outcome + ": authoritative result or terminal fallback persists exactly once")
		check(recorder.progression_calls == 1 and world.submitted_summaries.size() == 1, outcome + ": finalization evaluates progression/submission once")
		var saved_hash := FileAccess.get_sha256(HISTORY.STORAGE_PATH)
		recorder.finish_run("quit")
		recorder.finalize_synced_run_summary_for_joiner(host_summary, "death")
		check(recorder.progression_calls == 1 and world.submitted_summaries.size() == 1 and FileAccess.get_sha256(HISTORY.STORAGE_PATH) == saved_hash, outcome + ": repeated or delayed outcomes cannot rewrite history or apply progression twice")
		await _cleanup()

extends SceneTree

const TRACKER := preload("res://scripts/core/run_summary_tracker.gd")
const RECORDER := preload("res://scripts/core/run_summary_recorder.gd")
const EVALUATOR := preload("res://scripts/progression/oaths_evaluator.gd")
const META := preload("res://scripts/meta_progress_store.gd")
const OBJECTIVES := preload("res://scripts/objective_runtime.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")

class TestContext extends Node:
	var meta_progress_profile: Dictionary = META._get_default_profile()
	var saves := 0
	func get_profile_uuid() -> String:
		return "oath-test-player"
	func get_profile_name_or_default() -> String:
		return "OathTest"
	func save_meta_progress() -> bool:
		saves += 1
		return true

class TestWorld extends Node:
	var context := TestContext.new()
	var current_player_profile: RefCounted = null
	var is_multiplayer := true
	var submitted: Dictionary = {}
	var player: Node2D
	var party: Array = []
	func _resolve_local_peer_id() -> int:
		return 2
	func _get_run_context() -> Node:
		return context
	func _enqueue_leaderboard_submission(summary: Dictionary) -> void:
		submitted = summary.duplicate(true)
	func _get_multiplayer_player_nodes() -> Array:
		return party

class TestPlayer extends Node2D:
	var dead := false
	func is_dead() -> bool:
		return dead

class CheckpointWorld extends "res://scripts/world_generator.gd":
	var context_accesses := 0
	func _ready() -> void:
		pass
	func _get_run_context() -> RUN_CONTEXT_SCRIPT:
		context_accesses += 1
		return null

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run_tests")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _completed(summary: Dictionary) -> Array:
	return EVALUATOR.evaluate_run(summary, META._get_default_profile()).get("completed_oath_ids", [])

func _run_tests() -> void:
	_test_encounter_and_full_run_rules()
	_test_boss_damage_attribution()
	_test_checkpoint_evidence()
	_test_joiner_summary_and_persistence()
	_test_control_zone_participants()
	_test_coop_checkpoint_isolation()
	if _failures.is_empty():
		print("Oath tracking regression tests passed")
	quit(0 if _failures.is_empty() else 1)

func _test_encounter_and_full_run_rules() -> void:
	var tracker := TRACKER.new()
	tracker.reset_for_run({})
	tracker.begin_boss_engagement("warden")
	_check(not _completed(tracker.build_summary({"outcome": "death"})).has("warden_no_hit"), "An unfinished boss must not award no-hit")
	tracker.record_boss_defeat("warden")
	tracker.record_hold_full_control()
	var summary := tracker.build_summary({"outcome": "death"})
	var earned := _completed(summary)
	_check(earned.has("warden_no_hit") and earned.has("unbroken_line"), "Completed boss/Hold evidence must survive a later death")
	_check(not earned.has("closed_fist") and not earned.has("flawless_run"), "Whole-run Oaths still require a clear")
	summary["is_debug"] = true
	_check(_completed(summary).is_empty(), "Debug runs must not grant Oaths")
	tracker.reset_for_run({})
	tracker.record_boss_defeat("warden")
	_check(not _completed(tracker.build_summary({"outcome": "clear"})).has("warden_no_hit"), "Defeat without engagement evidence must not grant boss no-hit")
	_check(not _completed(tracker.build_summary({"outcome": "clear"})).has("unbroken_line"), "An unfinished Hold encounter must not award its Oath")
	tracker.begin_boss_engagement("warden")
	tracker.record_damage_taken(1)
	tracker.record_boss_defeat("warden")
	_check(not tracker.boss_no_hit_ids.has("warden"), "Damage during the boss fight disqualifies no-hit")
	tracker.begin_boss_engagement("sovereign")
	tracker.record_boss_defeat("sovereign")
	_check(tracker.boss_no_hit_ids.has("sovereign"), "Damage in a previous fight must not disqualify the next boss")

func _test_boss_damage_attribution() -> void:
	var tracker := TRACKER.new()
	tracker.reset_for_run({})
	tracker.begin_boss_engagement("warden", [1, 2])
	tracker.record_damage_taken(2, 1)
	tracker.record_boss_defeat("warden")
	_check(tracker.get_boss_no_hit_ids_for_peer(1).is_empty(), "The player who took damage must fail boss no-hit")
	_check(tracker.get_boss_no_hit_ids_for_peer(2).has("warden"), "A teammate's damage must not disqualify an untouched player")
	_check(tracker.get_boss_no_hit_ids_for_peer(3).is_empty(), "A player absent from the boss engagement must not earn no-hit")
	tracker.begin_boss_engagement("sovereign", [1, 2])
	tracker.record_damage_taken(1, 2)
	tracker.record_boss_defeat("sovereign")
	_check(tracker.get_boss_no_hit_ids_for_peer(1).has("sovereign"), "Peer boss damage must reset for the next encounter")
	_check(not tracker.get_boss_no_hit_ids_for_peer(2).has("sovereign"), "Joined player damage must disqualify that player's current fight")

func _test_checkpoint_evidence() -> void:
	var tracker := TRACKER.new()
	tracker.reset_for_run({})
	tracker.record_primary_attack_fired()
	tracker.record_rest_visit(1)
	tracker.record_damage_taken(1)
	tracker.begin_boss_engagement("warden")
	tracker.record_boss_defeat("warden")
	tracker.record_hold_full_control()
	var restored := TRACKER.new()
	restored.reset_for_run({})
	restored.restore_checkpoint(tracker.build_checkpoint())
	var earned := _completed(restored.build_summary({"outcome": "clear"}))
	_check(not earned.has("closed_fist") and not earned.has("flawless_run") and not earned.has("the_unbroken_march"), "Resume must retain attacks, damage and rest visits")
	_check(earned.has("warden_no_hit") and earned.has("unbroken_line"), "Resume must retain completed encounter evidence")
	var world := TestWorld.new()
	var recorder := RECORDER.new(world)
	recorder.run_started_at_msec = 1
	recorder._run_finished_at_msec = 1001
	recorder.restore_tracker_items_from_snapshot({"tracker_checkpoint": tracker.build_checkpoint(), "run_elapsed_seconds": 480})
	_check(recorder.get_run_elapsed_seconds() == 481, "Resume must retain elapsed time for Against the Clock")
	recorder.restore_tracker_items_from_snapshot({"tracker_boon_items": {"test": {"id": "test", "name": "Test", "stacks": 1}}})
	earned = _completed(recorder.run_summary_tracker.build_summary({"outcome": "clear"}))
	_check(not earned.has("closed_fist") and not earned.has("flawless_run") and not earned.has("the_unbroken_march") and not earned.has("against_the_clock"), "Legacy snapshots must not treat missing history as zero usage")
	_check(recorder.run_summary_tracker.boon_items.has("test"), "Legacy snapshots must retain the known build")
	world.context.free()
	world.free()

func _test_joiner_summary_and_persistence() -> void:
	var world := TestWorld.new()
	var recorder := RECORDER.new(world)
	recorder.run_summary_tracker.record_primary_attack_fired()
	var summary := {"run_id": "oath-test-host", "outcome": "clear", "primary_attacks_fired": 0, "boss_no_hit_ids": [], "stats": {"damage_taken_total": 1}}
	var overrides := {2: {"boss_no_hit_ids": ["warden"]}}
	summary = recorder.summary_with_local_peer_overrides(summary, overrides)
	recorder.finalize_synced_run_summary_for_joiner(summary, "clear")
	_check(int(recorder.latest_run_summary.get("primary_attacks_fired", -1)) == 1, "Joined summary must retain its local attack count")
	_check(not META.is_oath_completed(world.context.meta_progress_profile, "closed_fist"), "Host abstaining must not award Closed Fist to an attacking joiner")
	_check(META.is_oath_completed(world.context.meta_progress_profile, "warden_no_hit"), "Joined peer boss evidence must reach persisted progress")
	_check(world.context.saves > 0, "Completed Oaths must invoke progression persistence")
	world.context.free()
	world.free()
	world = TestWorld.new()
	recorder = RECORDER.new(world)
	recorder.finalize_synced_run_summary_for_joiner({"run_id": "oath-test-loss", "outcome": "death", "boss_no_hit_ids": ["warden"], "hold_full_control_achieved": true}, "death")
	_check(META.is_oath_completed(world.context.meta_progress_profile, "warden_no_hit") and META.is_oath_completed(world.context.meta_progress_profile, "unbroken_line"), "Later death must persist already completed encounter Oaths")
	world.context.free()
	world.free()
	world = TestWorld.new()
	recorder = RECORDER.new(world)
	recorder.finalize_synced_run_summary_for_joiner({"run_id": "oath-test-idle", "outcome": "clear", "primary_attacks_fired": 50}, "clear")
	_check(META.is_oath_completed(world.context.meta_progress_profile, "closed_fist"), "Host attacks must not disqualify an abstaining joiner")
	world.context.free()
	world.free()
	world = TestWorld.new()
	recorder = RECORDER.new(world)
	recorder.initialize(false)
	recorder.finalize_synced_run_summary_for_joiner({"run_id": "oath-test-debug", "outcome": "clear", "boss_no_hit_ids": ["warden"], "ascension_rank": 5}, "clear")
	_check(world.context.saves == 0 and META.get_completed_oath_ids(world.context.meta_progress_profile).is_empty(), "Debug summaries must not persist Oaths or Ascension progress")
	world.context.free()
	world.free()

func _test_control_zone_participants() -> void:
	var world := TestWorld.new()
	var local := TestPlayer.new()
	var ally := TestPlayer.new()
	world.player = local
	world.party = [local, ally]
	root.add_child(world)
	world.add_child(local)
	world.add_child(ally)
	local.dead = true
	ally.position = Vector2(200, 0)
	var runtime := OBJECTIVES.new()
	runtime.world = world
	_check(not runtime._is_any_active_player_inside_control_zone(Vector2.ZERO, 50), "Fallen players must not hold or capture control zones")
	ally.position = Vector2.ZERO
	_check(runtime._is_any_active_player_inside_control_zone(Vector2.ZERO, 50), "A living ally can hold the shared objective zone")
	runtime.free()
	world.context.free()
	world.free()

func _test_coop_checkpoint_isolation() -> void:
	var world := CheckpointWorld.new()
	world.is_multiplayer = true
	world._save_active_run_checkpoint()
	world._clear_active_run_checkpoint()
	_check(world.context_accesses == 0, "Co-op checkpoints must not access or modify solo saves")
	world.is_multiplayer = false
	world._save_active_run_checkpoint()
	world._clear_active_run_checkpoint()
	_check(world.context_accesses == 2, "Solo checkpoint save and clear paths must remain available")
	world.free()

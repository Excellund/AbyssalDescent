extends "res://scripts/tests/test_checkpoint_isolation.gd"
## Real reward acquisition, disk checkpoints, fresh character setup and resume.
const SNAPSHOT := preload("res://scripts/run_snapshot_service.gd")
const CHARACTER := preload("res://scripts/character_registry.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const EVALUATOR := preload("res://scripts/progression/oaths_evaluator.gd")
const META := preload("res://scripts/meta_progress_store.gd")

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Power snapshots require disposable user data")
		quit(1)
		return
	for character_id in CHARACTER.get_launch_character_ids():
		for picks in [0,1,2,3,4]:
			for legacy in [false,true]:
				await _test_movement_roundtrip(character_id,picks,legacy)
	await _test_explicit_values()
	for character_id in CHARACTER.get_launch_character_ids():
		for picks in [1, 2, 3, 4]:
			await _test_electricity_roundtrip(character_id, picks)
	for single_arcana in [true,false]:
		await _test_build_and_oath_roundtrip(single_arcana)
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()
	HISTORY.clear_all()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Power snapshots: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_electricity_roundtrip(character_id: String, picks: int) -> void:
	_setup("solo")
	world.current_character_id = character_id
	world.player.apply_character_package(CHARACTER.get_character(character_id))
	for index in range(picks):
		world.player.apply_trial_power("static_wake")
		world.player.apply_trial_power("storm_crown")
	var original := world.player.build_run_snapshot()
	var root_action := world.player.new_combat_action("dash")
	world.player.static_wake_controller.begin_dash(root_action)
	world.player.static_wake_controller.append_segment(Vector2.ZERO, Vector2(30.0, 0.0))
	world.player.static_wake_controller.end_dash()
	world._save_active_run_checkpoint()
	var resumed := _replace_player(RunContext.load_active_run())
	var label := "%s electricity picks%d" % [character_id, picks]
	check(resumed.build_run_snapshot().properties == original.properties, label + ": disk resume preserves mapped stats and learned powers")
	for power in ["static_wake", "storm_crown"]:
		check(resumed.get_trial_power_stack_count(power) == mini(picks, 3), label + ": learned level survives")
		check(resumed.upgrade_system.has_trial_power_prismatic(power) == (picks == 4), label + ": one-time Prismatic state survives")
	check(resumed.static_wake_controller.ribbons.is_empty(), label + ": temporary ribbons do not survive disk restore")
	check(resumed.combat_interactions._roots.is_empty(), label + ": reaction allowances do not survive disk restore")
	await _cleanup()

func _replace_player(snapshot: Dictionary) -> Player:
	var old := world.player
	var replacement := Player.new()
	world.add_child(replacement)
	replacement.player_id = 1
	PlayerReplicationService.register_player(1,replacement)
	world.player = replacement
	old.upgrade_system.power_registry.free()
	actors.erase(old)
	old.free()
	actors.append(replacement)
	check(SNAPSHOT.apply_snapshot(world,replacement,RunContext,snapshot,world.room_base_size,ENUMS.RunMode.STANDARD,ENUMS.RewardMode.NONE),"Production world checkpoint restoration succeeds")
	return replacement

func _movement_sample(actor: Player) -> Dictionary:
	actor.velocity = Vector2.ZERO
	actor._voidfire_lockout_left = 0.2
	actor._update_ground_movement(Vector2.RIGHT,1.0)
	var overheat_velocity := actor.velocity.x
	actor.dash_direction = Vector2.RIGHT
	actor.dash_remaining_distance = actor.dash_distance
	actor.dash_time_left = 1.0
	actor._process_active_dash(1.0/60.0)
	return {"overheat_velocity":overheat_velocity,"dash_velocity":actor.velocity.x}

func _test_movement_roundtrip(character_id: String,picks: int,legacy: bool) -> void:
	_setup("solo")
	world.current_character_id = character_id
	world.player.apply_character_package(CHARACTER.get_character(character_id))
	for _index in range(picks):
		world.player.apply_trial_power("voidfire")
		world.player.apply_upgrade("surge_step")
	var label := "%s picks%d %s" % [character_id,picks,"legacy" if legacy else "current"]
	var expected_build := world.player.build_run_snapshot()
	var expected_motion := _movement_sample(world.player)
	world.player.discard_pending_combat_input()
	world._save_active_run_checkpoint()
	var saved := RunContext.load_active_run()
	check(not saved.is_empty(),label+": world writes a real checkpoint")
	if legacy:
		saved.player_snapshot.properties.erase("dash_speed")
		saved.player_snapshot.properties.erase("voidfire_overheat_move_mult")
		check(RunContext.save_active_run(saved),label+": pre-fix fields can be omitted on disk")
	var resumed := _replace_player(RunContext.load_active_run())
	check(_movement_sample(resumed) == expected_motion,label+": resumed dash and subsequent overheat retain their actual movement speeds")
	check(resumed.get_trial_power_stack_count("voidfire") == mini(picks,3) and resumed.upgrade_system.has_trial_power_prismatic("voidfire") == (picks==4),label+": Voidfire level and one-time Prismatic state survive")
	check(resumed.get_upgrade_stack_count("surge_step") == int(expected_build.upgrade_stacks.get("surge_step",0)),label+": resume does not acquire or discard Surge stacks")
	for _repeat in range(2):
		resumed.dash_speed += 200.0
		resumed.voidfire_overheat_move_mult = 0.91
		resumed.apply_run_snapshot(saved.player_snapshot)
		check(_movement_sample(resumed) == expected_motion,label+": repeated restore neither adds Surge again nor retains stale slowdown")
	check(resumed.build_run_snapshot().properties == expected_build.properties,label+": learned values still match after repeated restore")
	await _cleanup()

func _test_explicit_values() -> void:
	_setup("solo")
	world.player.apply_trial_power("voidfire")
	world.player.apply_upgrade("surge_step")
	world.player.dash_speed = 901.0
	world.player.voidfire_overheat_move_mult = 0.57
	world._save_active_run_checkpoint()
	var resumed := _replace_player(RunContext.load_active_run())
	check(resumed.dash_speed == 901.0 and resumed.voidfire_overheat_move_mult == 0.57,"Explicit saved values take precedence over legacy reconstruction")
	await _cleanup()

func _test_build_and_oath_roundtrip(single_arcana: bool) -> void:
	_setup("solo")
	var recorder := RECORDER.new(world)
	world.run_summary_recorder = recorder
	recorder.mark_run_start()
	var tracker = recorder.run_summary_tracker
	for id in (["returning_crescent"] if single_arcana else ["returning_crescent","blast_drive","razor_orbit","voidfire"]):
		for level in range(4):
			world.player.apply_trial_power(id)
			recorder.record_reward_choice_for_tracker({"id":id,"name":id},ENUMS.RewardMode.ARCANA,level)
	for id in ["sovereigns_double","ruinous_impact"]:
		for level in range(2):
			world.player.apply_upgrade(id)
			recorder.record_reward_choice_for_tracker({"id":id,"name":id},ENUMS.RewardMode.BOSS,level)
	if not single_arcana:
		world.player.apply_upgrade("surge_step")
		recorder.record_reward_choice_for_tracker({"id":"surge_step","name":"surge_step"},ENUMS.RewardMode.BOON,2)
		tracker.record_damage_taken(7)
		recorder.record_primary_attack_fired()
		recorder.record_rest_visit(4)
	tracker.begin_boss_engagement("warden")
	tracker.record_boss_defeat("warden")
	tracker.record_hold_full_control()
	recorder._resumed_elapsed_msec = 600000
	var before: Dictionary = tracker.build_summary({"outcome":"clear","duration_seconds":600})
	var expected_build := world.player.build_run_snapshot()
	world._save_active_run_checkpoint()
	var saved := RunContext.load_active_run()
	var resumed := _replace_player(saved)
	check(resumed.build_run_snapshot() == expected_build,"World checkpoint preserves complete Crescent/Blast/Orbit/Double/Ruinous inventory and structural upgrades")
	var restored := RECORDER.new(world)
	world.run_summary_recorder = restored
	restored.mark_run_start()
	restored.restore_tracker_items_from_snapshot(saved)
	RunContext.meta_progress_profile = {} # Evaluate against a fresh profile below.
	restored.finish_run("clear")
	var final: Dictionary = restored.latest_run_summary
	var earned_before: Array = EVALUATOR.evaluate_run(before,META._get_default_profile()).completed_oath_ids
	var earned_after: Array = EVALUATOR.evaluate_run(final,META._get_default_profile()).completed_oath_ids
	check(earned_after == earned_before,"Finalization after disk resume preserves completed encounters and whole-run Oath evidence")
	check(earned_after.has("singular_focus") == single_arcana and earned_after.has("closed_fist") == single_arcana and earned_after.has("flawless_run") == single_arcana,"Single-Arcana, primary-attack and damage evidence retain both their qualifying and disqualifying results")
	check(HISTORY.load_all().size() == 1 and HISTORY.load_all()[0].build_summary == JSON.parse_string(JSON.stringify(final.build_summary)),"Final local history retains the resumed build")
	await _cleanup()

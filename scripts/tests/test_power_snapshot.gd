extends "res://scripts/tests/test_checkpoint_isolation.gd"
## Real reward acquisition, disk checkpoints, fresh character setup and resume.
const SNAPSHOT := preload("res://scripts/run_snapshot_service.gd")
const CHARACTER := preload("res://scripts/character_registry.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const EVALUATOR := preload("res://scripts/progression/oaths_evaluator.gd")
const META := preload("res://scripts/meta_progress_store.gd")
const MISSION_BUILDER := preload("res://scripts/encounter_profile_builder.gd")
const SHARED_POWERS := ["hunters_snare", "wraithstep", "eclipse_mark", "dread_resonance"]
const SHARED_VALUES := [
	"hunters_snare_bonus_ratio", "hunters_snare_slow_duration", "hunters_snare_slow_mult",
	"wraithstep_mark_bonus_ratio", "wraithstep_mark_duration", "wraithstep_dash_mark_radius",
	"wraithstep_splash_radius", "wraithstep_splash_ratio", "eclipse_mark_bonus_ratio",
	"eclipse_mark_duration", "eclipse_mark_radius", "dread_resonance_damage_ratio_per_stack",
	"dread_resonance_max_stacks", "dread_resonance_mark_bonus_ratio", "dread_resonance_mark_duration"
]

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
			await _test_shared_status_migration(character_id, picks, false)
		await _test_overcharge_actions(character_id)
	for picks in [1, 2, 3, 4]:
		await _test_shared_status_migration("bastion", picks, true)
		await _test_analytic_ratio_restore(picks)
	await _test_legacy_reward_flag_migration()
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

func _test_analytic_ratio_restore(picks: int) -> void:
	_setup("solo")
	world.player.damage = 21
	for pick in range(picks):
		world.player.apply_trial_power("phantom_step")
		world.player.apply_trial_power("static_wake")
	var phantom_ratio: float = [0.56, 0.72, 0.88, 1.188][picks - 1]
	var wake_ratio: float = [0.45, 0.60, 0.75, 1.05][picks - 1]
	var label := "Analytic damage picks%d" % picks
	check(is_equal_approx(world.player.phantom_step_damage_ratio, phantom_ratio) and is_equal_approx(world.player.static_wake_damage_ratio, wake_ratio), label + ": actual rewards write both analytic coefficients")
	world.player.apply_upgrade("heavy_blow")
	var phantom_raw := int(ceil(28.0 * [0.56, 0.72, 0.88, 0.88][picks - 1]))
	var wake_raw := int(ceil(28.0 * [0.45, 0.60, 0.75, 0.75][picks - 1]))
	if picks == 4:
		phantom_raw = int(phantom_raw * 1.35)
		wake_raw = int(wake_raw * 1.4)
	check(world.player.damage == 28 and world.player.phantom_step_damage == phantom_raw and world.player.static_wake_damage == wake_raw, label + ": later Damage Boon refreshes existing ceil/Prismatic raw damage")
	check(is_equal_approx(world.player.phantom_step_damage_ratio, phantom_ratio) and is_equal_approx(world.player.static_wake_damage_ratio, wake_ratio), label + ": Damage upgrade cannot change the analytic multiplier")
	world.player.dash_cooldown = 0.37
	world.player.phantom_step_damage += 3 # Explicit legacy raw values stay authoritative.
	world.player.static_wake_damage += 2
	world.player.set_health(37)
	world._save_active_run_checkpoint()
	var saved := RunContext.load_active_run()
	saved.player_snapshot.version = 2
	saved.player_snapshot.properties.erase("phantom_step_damage_ratio")
	saved.player_snapshot.properties.erase("static_wake_damage_ratio")
	check(RunContext.save_active_run(saved), label + ": writes legacy checkpoint without new ratio properties")
	var resumed := _replace_player(RunContext.load_active_run())
	check(is_equal_approx(resumed.phantom_step_damage_ratio, phantom_ratio) and is_equal_approx(resumed.static_wake_damage_ratio, wake_ratio), label + ": actual disk restore reconstructs both learned ratios including Prismatic")
	check(resumed.phantom_step_damage == phantom_raw + 3 and resumed.static_wake_damage == wake_raw + 2, label + ": ratio-only migration preserves explicit saved integer damage")
	check(is_equal_approx(resumed.dash_cooldown, 0.37) and resumed.get_current_health() == 37, label + ": migration never replays Phantom's cooldown reduction or healing")
	resumed.apply_run_snapshot(saved.player_snapshot)
	check(is_equal_approx(resumed.dash_cooldown, 0.37) and resumed.phantom_step_damage == phantom_raw + 3, label + ": repeated restore remains idempotent")
	await _cleanup()

func _shared_values(actor: Player) -> Dictionary:
	var values := {}
	for property_name in SHARED_VALUES:
		values[property_name] = actor.get(property_name)
	return values

func _make_legacy_shared_snapshot(snapshot: Dictionary, level: int, prismatic: bool, omit_levels: bool) -> void:
	snapshot.version = 2
	var properties: Dictionary = snapshot.properties
	for property_name in ["hunters_snare_bonus_ratio", "wraithstep_mark_bonus_ratio", "dread_resonance_damage_ratio_per_stack", "dread_resonance_mark_bonus_ratio", "dread_resonance_mark_duration"]:
		properties.erase(property_name)
	# These were the actual version-2 flat bonuses and Eclipse parameters.
	properties.hunters_snare_bonus_damage = int(float(4 + 4 * level) * (1.75 if prismatic else 1.0))
	properties.wraithstep_mark_bonus_damage = int(float(8 + 8 * level) * (1.5 if prismatic else 1.0))
	properties.dread_resonance_bonus_per_stack = level + (1 if prismatic else 0)
	properties.eclipse_mark_bonus_ratio = (0.25 + 0.10 * level) * (1.45 if prismatic else 1.0)
	properties.eclipse_mark_duration = (3.0 + 0.6 * level) * (1.3 if prismatic else 1.0)
	if omit_levels:
		for power_id in SHARED_POWERS:
			properties.erase(power_id + "_stacks")

func _test_shared_status_migration(character_id: String, picks: int, omit_levels: bool) -> void:
	_setup("solo")
	world.current_character_id = character_id
	world.player.apply_character_package(CHARACTER.get_character(character_id))
	for index in range(picks):
		for power_id in SHARED_POWERS:
			world.player.apply_trial_power(power_id)
	world.player.apply_upgrade("surge_step")
	var builder := MISSION_BUILDER.new()
	world.add_child(builder)
	world.player.apply_objective_mutator(builder._build_overcharge_mutator())
	world.player.tick_objective_mutators_for_encounter()
	world.player.set_max_health_and_current(world.player.get_max_health(), 37)
	var expected := _shared_values(world.player)
	var expected_build := world.player.build_run_snapshot()
	world._save_active_run_checkpoint()
	var saved := RunContext.load_active_run()
	_make_legacy_shared_snapshot(saved.player_snapshot, mini(picks, 3), picks == 4, omit_levels)
	var label := "%s shared powers picks%d%s" % [character_id, picks, " map-only levels" if omit_levels else ""]
	check(RunContext.save_active_run(saved), label + ": writes actual version-2 disk checkpoint")
	var resumed := _replace_player(RunContext.load_active_run())
	check(_shared_values(resumed) == expected, label + ": legacy flat/status values migrate to the current level and Prismatic parameters")
	for power_id in SHARED_POWERS:
		check(resumed.get_trial_power_stack_count(power_id) == mini(picks, 3) and resumed.upgrade_system.has_trial_power_prismatic(power_id) == (picks == 4), label + ": preserves learned " + power_id)
	check(resumed.get_current_health() == 37 and resumed.get_max_health() == int(expected_build.properties.max_health), label + ": migration preserves current and maximum health")
	check(resumed.get_active_objective_mutators() == expected_build.active_objective_mutators and int(resumed.get_active_objective_mutators()[0].remaining_encounters) == 2, label + ": remaining Mission duration is neither renewed nor consumed")
	check(resumed.get_upgrade_stack_count("surge_step") == 1 and resumed.dash_speed == float(expected_build.properties.dash_speed), label + ": permanent Boon is not reapplied")
	check(resumed.build_run_snapshot().version == 3 and resumed.combat_interactions._roots.is_empty(), label + ": new save format starts without temporary action roots")
	resumed.apply_run_snapshot(saved.player_snapshot)
	check(_shared_values(resumed) == expected and resumed.get_current_health() == 37, label + ": repeated restoration is idempotent")
	await _cleanup()

func _test_legacy_reward_flag_migration() -> void:
	_setup("solo")
	for power_id in SHARED_POWERS:
		world.player.apply_trial_power(power_id)
	var expected := _shared_values(world.player)
	world._save_active_run_checkpoint()
	var saved := RunContext.load_active_run()
	_make_legacy_shared_snapshot(saved.player_snapshot, 1, false, true)
	saved.player_snapshot.trial_power_stacks.clear()
	check(RunContext.save_active_run(saved), "Old flag-only learned powers can be stored in the real checkpoint")
	var resumed := _replace_player(RunContext.load_active_run())
	check(_shared_values(resumed) == expected, "Legacy learned flags without either level field recover level 1 shared parameters")
	for power_id in SHARED_POWERS:
		check(resumed.get_trial_power_stack_count(power_id) == 1, "Flag-only migration retains learned " + power_id)
	await _cleanup()

func _sample_action_cooldowns(actor: Player) -> Dictionary:
	Input.action_release("dash")
	Input.action_release("attack")
	await process_frame
	await physics_frame
	await process_frame
	actor.discard_pending_combat_input()
	actor.attack_lock_time_left = 0.0
	actor.attack_cooldown_left = 0.0
	actor.dash_cooldown_left = 0.0
	actor.encounter_input_frozen = false
	actor._refresh_combat_input_release()
	var before := actor.attack_combo_counter
	actor._try_execute_attack(Vector2.RIGHT)
	var attack_left := actor.attack_cooldown_left
	actor.attack_lock_time_left = 0.0
	Input.action_press("dash")
	actor._try_start_dash(Vector2.RIGHT)
	Input.action_release("dash")
	var result := {"attack": attack_left, "dash": actor.dash_cooldown_left, "distance": actor.dash_remaining_distance, "duration": actor.dash_time_left, "immunity": actor._dash_damage_immune_left}
	check(actor.attack_combo_counter == before + 1 and actor._is_dash_active(), "Cooldown sample uses one accepted Attack and one accepted normal Dash")
	actor.discard_pending_combat_input()
	return result

func _test_overcharge_actions(character_id: String) -> void:
	_setup("solo")
	world.player.apply_character_package(CHARACTER.get_character(character_id))
	var baseline := await _sample_action_cooldowns(world.player)
	var builder := MISSION_BUILDER.new()
	world.add_child(builder)
	world.player.apply_objective_mutator(builder._build_overcharge_mutator())
	var charged := await _sample_action_cooldowns(world.player)
	check(is_equal_approx(float(charged.attack), float(baseline.attack) * 0.8) and is_equal_approx(float(charged.dash), float(baseline.dash) * 0.8), character_id + ": Overcharge reduces both actual action cooldowns by 20%")
	check(charged.distance == baseline.distance and charged.duration == baseline.duration and charged.immunity == baseline.immunity, character_id + ": Overcharge preserves dash travel, duration and immunity")
	var target := preload("res://scripts/enemy_chaser.gd").new()
	world.add_child(target)
	target.set_physics_process(false)
	target.global_position = Vector2(800.0, 800.0)
	var target_health := target.get_current_health()
	for index in range(12):
		world.player.notify_enemy_killed(target.global_position)
	check(target.get_current_health() == target_health and world.player.overcharge_kill_stacks == 0 and not world.player.overcharge_is_charged, character_id + ": a kill chain adds neither old Overcharge damage stacks nor a nova")
	for remaining in [2, 1, 0]:
		world.player.tick_objective_mutators_for_encounter()
		var sample := await _sample_action_cooldowns(world.player)
		check(sample.attack == (charged.attack if remaining > 0 else baseline.attack) and sample.dash == (charged.dash if remaining > 0 else baseline.dash), character_id + ": temporary cooldown benefit expires after exactly three cleared encounters")
	await _cleanup()

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

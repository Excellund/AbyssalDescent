extends "res://scripts/tests/test_checkpoint_isolation.gd"
## Entered-room variety and the Shatterfield pilot, with real isolated checkpoints.

const SESSION := preload("res://scripts/core/run_session.gd")
const SNAPSHOT := preload("res://scripts/run_snapshot_service.gd")
const BUILDER := preload("res://scripts/encounter_profile_builder.gd")
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const BIOMES := preload("res://scripts/shared/biome_registry.gd")
const LAYOUTS := preload("res://scripts/shared/arena_layout_registry.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const ORIGINAL_LANES := [Vector2(-240, -150), Vector2(-85, 110), Vector2(110, -110), Vector2(260, 150)]
const MIRRORED_LANES := [Vector2(240, -150), Vector2(85, 110), Vector2(-110, -110), Vector2(-260, 150)]

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Descent route tests require disposable user data")
		quit(1)
		return
	_test_entered_history()
	_test_roster_fallbacks()
	_test_weighted_variety()
	_test_route_choices()
	_test_shatterfield_layouts()
	await _test_checkpoint_roundtrip()
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()
	HISTORY.clear_all()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Descent routes: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _builder(tier: int = 1, seed_value: int = 42) -> BUILDER:
	var builder := BUILDER.new()
	var generator := RandomNumberGenerator.new()
	generator.seed = seed_value
	builder.initialize(generator)
	builder.set_difficulty_tier(tier)
	return builder

func _test_entered_history() -> void:
	var session := SESSION.new()
	var builder := _builder()
	for label in BUILDER.BEARING_LABELS:
		session.record_encounter_entry(builder.build_debug_encounter_profile(label.to_lower(), 9))
		check(session.last_standard_encounter_key == label.to_lower(), "Entered standard room records canonical identity: " + label)
	for kind in ["last_stand", "cut_the_signal", "hold_the_line", "circuit_sweep", "pulse_window", "intercept_run"]:
		session.record_encounter_entry(builder.build_objective_profile(9, kind))
		check(session.last_objective_kind == kind and session.last_standard_encounter_key == "breach", "Objective entry preserves independent standard history: " + kind)
	for key in ["tutorial", "skirmish", "trial", "apex_trial", "apex_mirrorline", "apex_toll", "apex_breakwater"]:
		var profile := builder.build_tutorial_profile() if key == "tutorial" else builder.build_debug_encounter_profile(key, 0 if key == "skirmish" else 9)
		session.record_encounter_entry(profile)
		check(session.last_standard_encounter_key == "breach" and session.last_objective_kind == "intercept_run", "Intro, Trial and Apex entry does not replace tracked categories: " + key)
	var endless := builder.build_debug_encounter_profile("crossfire", 9)
	endless["label"] = "Crossfire  Tier 3"
	session.record_encounter_entry(endless)
	check(session.last_standard_encounter_key == "crossfire", "Endless display suffix retains the standard identity")
	var context := {"depth": 9, "last_standard_encounter_key": "crossfire", "last_objective_kind": "intercept_run"}
	for _offer in range(12):
		builder.roll_route_options(context)
		builder.build_objective_profile(9, "hold_the_line")
	check(session.last_standard_encounter_key == "crossfire" and session.last_objective_kind == "intercept_run", "Generated, declined and debug-preview encounters cannot advance entered history")
	session.act_biome_ids = ["shatterfield", "hollow", "void_breach"]
	session.reset_for_new_run()
	check(session.act_biome_ids.is_empty() and session.last_standard_encounter_key.is_empty() and session.last_objective_kind.is_empty(), "New run clears biome and encounter history")
	builder.free()

func _test_roster_fallbacks() -> void:
	var session := SESSION.new()
	var fallback: Array[String] = ["haunt", "storm_reach", "convergence_end"]
	for malformed in [null, "shatterfield", [], ["shatterfield"], ["shatterfield", "haunt", "void_breach"], ["shatterfield", "hollow", "unknown"], ["shatterfield", 2, "void_breach"], ["shatterfield", "hollow", "void_breach", "crumble"]]:
		session.act_biome_ids = fallback.duplicate()
		session.restore_descent_state({"act_biome_ids": malformed, "last_standard_encounter_key": [], "last_objective_kind": "random_objective"})
		check(session.act_biome_ids == fallback and session.last_standard_encounter_key.is_empty() and session.last_objective_kind.is_empty(), "Invalid optional roster/history keeps rolled biome fallback and clears untrustworthy history")
	session.restore_descent_state({"act_biome_ids": ["shatterfield", "hollow", "void_breach"], "last_standard_encounter_key": "crossfire", "last_objective_kind": "hold_the_line"})
	check(session.act_biome_ids == ["shatterfield", "hollow", "void_breach"] and session.last_standard_encounter_key == "crossfire" and session.last_objective_kind == "hold_the_line", "Canonical biome roster and entered history restore together")
	session.restore_descent_state({})
	check(session.act_biome_ids == ["shatterfield", "hollow", "void_breach"] and session.last_standard_encounter_key.is_empty() and session.last_objective_kind.is_empty(), "Missing legacy fields preserve fallback roster without inventing encountered rooms")

func _test_weighted_variety() -> void:
	var builder := _builder()
	builder.set_active_biome(BIOMES.get_biome("shatterfield"))
	var pool := builder._get_hard_pool_for_depth(5)
	var original_counts := _key_counts(pool)
	var previous_rng_state := builder.rng.state
	var filtered := builder._without_previous_standard_encounter(pool, "crossfire")
	var filtered_counts := _key_counts(filtered)
	check(not filtered_counts.has("crossfire") and original_counts.get("crossfire", 0) == 2, "Both weighted copies of the previous encounter leave the eligible pool")
	var other_weights_preserved := true
	for key in original_counts:
		if key != "crossfire":
			other_weights_preserved = other_weights_preserved and original_counts[key] == filtered_counts.get(key, 0)
	check(other_weights_preserved and filtered_counts.get("suppression", 0) == 2 and filtered_counts.get("convergence", 0) == 2, "Repeat filtering preserves every other biome weight")
	check(builder.rng.state == previous_rng_state and _key_counts(pool) == original_counts, "Filtering consumes no randomness and leaves its source pool intact")
	var one_kind: Array[Dictionary] = [{"label": "Crossfire"}, {"label": "Crossfire"}]
	check(builder._without_previous_standard_encounter(one_kind, "crossfire") == one_kind, "A pool containing only the previous identity remains playable")
	check(builder._without_previous_standard_encounter(pool, "missing") == pool, "Unknown historical identity cannot remove eligible encounters")
	builder.rng.seed = 223
	var first := builder.build_objective_profile(5)
	builder.rng.seed = 223
	var regenerated := builder.build_objective_profile(5)
	check(first == regenerated, "Identical RNG and history regenerate the same objective even after an unchosen offer")
	check(CONTRACTS.profile_objective_kind(builder.build_objective_profile(5, "hold_the_line", "hold_the_line")) == "hold_the_line", "An explicit debug objective request remains authoritative over variety history")
	builder.free()

func _key_counts(pool: Array[Dictionary]) -> Dictionary:
	var result := {}
	for profile in pool:
		var key := CONTRACTS.profile_encounter_key(profile)
		result[key] = int(result.get(key, 0)) + 1
	return result

func _test_route_choices() -> void:
	for tier in range(4):
		var builder := _builder(tier)
		for biome_id in BIOMES.BIOME_DEFINITIONS:
			builder.set_active_biome(BIOMES.get_biome(biome_id))
			var valid := true
			var offered_standard := false
			var offered_objective := false
			for seed_value in range(24):
				builder.rng.seed = seed_value
				var options := builder.roll_route_options({"depth": 5, "rooms_until_boss": 3, "all_players_full_hp": true, "last_standard_encounter_key": "crossfire", "last_objective_kind": "hold_the_line"})
				valid = valid and options.size() == 2
				for option in options:
					var profile := CONTRACTS.door_option_profile(option)
					var objective_kind := CONTRACTS.profile_objective_kind(profile)
					var reward := CONTRACTS.door_option_reward_mode(option)
					if reward == ENUMS.RewardMode.BOON:
						offered_standard = true
						valid = valid and CONTRACTS.profile_encounter_key(profile) != "crossfire" and CONTRACTS.profile_total_enemy_count(profile) > 0
					elif reward == ENUMS.RewardMode.MISSION:
						offered_objective = true
						valid = valid and not objective_kind.is_empty() and objective_kind != "hold_the_line"
					else:
						valid = valid and reward == ENUMS.RewardMode.ARCANA
			check(valid and offered_standard and offered_objective, "Actual two-door rolls respect history, availability and reward categories: %s/%d" % [biome_id, tier])
		var pre_boss := builder.roll_route_options({"depth": 7, "rooms_until_boss": 1, "all_players_full_hp": true, "last_standard_encounter_key": "crossfire", "last_objective_kind": "hold_the_line"})
		check(pre_boss.size() == 2 and (CONTRACTS.door_option_kind_id(pre_boss[0]) == ENUMS.DoorKind.REST or CONTRACTS.door_option_kind_id(pre_boss[1]) == ENUMS.DoorKind.REST), "Pre-boss rest remains offered independently of history on Bearing%d" % tier)
		builder.current_difficulty_config["rest_disabled"] = true
		var no_rest := builder.roll_route_options({"depth": 7, "rooms_until_boss": 1, "last_standard_encounter_key": "crossfire"})
		check(no_rest.size() == 2 and CONTRACTS.door_option_kind_id(no_rest[0]) != ENUMS.DoorKind.REST and CONTRACTS.door_option_kind_id(no_rest[1]) != ENUMS.DoorKind.REST, "Rest-disabled runs retain two combat routes on Bearing%d" % tier)
		builder.free()

func _test_shatterfield_layouts() -> void:
	var generator := RandomNumberGenerator.new()
	var seen := {}
	var valid := true
	for seed_value in range(64):
		generator.seed = seed_value
		var layout := LAYOUTS.pick_layout("Crossfire", Vector2(1040, 760), generator, "shatterfield")
		var positions: Array[Vector2] = []
		for obstacle in layout:
			positions.append(obstacle.pos)
			valid = valid and is_equal_approx(float(obstacle.radius), 28.0)
		valid = valid and layout.size() == 4 and (positions == ORIGINAL_LANES or positions == MIRRORED_LANES)
		seen["original" if positions == ORIGINAL_LANES else "mirror"] = true
	check(valid and seen.size() == 2, "Shatterfield Crossfire chooses only the two authored four-column radius-28 layouts")
	for label in LAYOUTS._ENCOUNTER_POOL:
		for biome_id in ["", "crumble", "haunt", "shatterfield", "hollow"]:
			if label == "Crossfire" and biome_id == "shatterfield":
				continue
			var unchanged := true
			for seed_value in range(8):
				generator.seed = seed_value
				var before := LAYOUTS.pick_layout(label, Vector2(1040, 760), generator)
				var before_state := generator.state
				generator.seed = seed_value
				var after := LAYOUTS.pick_layout(label, Vector2(1040, 760), generator, biome_id)
				unchanged = unchanged and before == after and before_state == generator.state
			check(unchanged, "Other layout pools and their RNG consumption remain unchanged: %s/%s" % [label, biome_id])
	for label in ["Tutorial", "Hold the Line", "Trial Surge", "Apex Breakwater"]:
		check(LAYOUTS.pick_layout(label, Vector2(1040, 760), generator, "shatterfield").is_empty(), "Obstacle exemption survives biome context: " + label)
	var builder := _builder()
	builder.set_active_biome(BIOMES.get_biome("shatterfield"))
	var profile := builder.build_debug_encounter_profile("crossfire", 5)
	check(CONTRACTS.profile_obstacle_layout(profile).size() == 4, "Real profile construction passes the active biome into the layout registry")
	var options: Array[Dictionary] = [CONTRACTS.standard_encounter_door_option(profile)]
	var copy: Array = bytes_to_var(var_to_bytes(options))
	check(CONTRACTS.profile_obstacle_layout(CONTRACTS.door_option_profile(copy[0])) == CONTRACTS.profile_obstacle_layout(profile), "Resolved Shatterfield geometry survives native door serialization")
	builder.free()

func _test_checkpoint_roundtrip() -> void:
	_setup("solo")
	world.run_session = SESSION.new()
	world.run_session.act_biome_ids = ["shatterfield", "hollow", "void_breach"]
	world.run_session.record_encounter_entry({"label": "Crossfire"})
	world.run_session.record_encounter_entry({"objective_kind": "hold_the_line"})
	var builder := _builder()
	builder.set_active_biome(BIOMES.get_biome("shatterfield"))
	world.door_options = [CONTRACTS.standard_encounter_door_option(builder.build_debug_encounter_profile("crossfire", 5))]
	world.choosing_next_room = true
	var expected_doors := world.door_options.duplicate(true)
	world._save_active_run_checkpoint()
	var saved := RunContext.load_active_run()
	check(saved.get("act_biome_ids", []) == ["shatterfield", "hollow", "void_breach"] and saved.get("last_standard_encounter_key", "") == "crossfire" and saved.get("last_objective_kind", "") == "hold_the_line", "Production disk checkpoint includes the canonical roster and both entered histories")
	world.run_session = SESSION.new()
	world.run_session.act_biome_ids = ["haunt", "storm_reach", "convergence_end"]
	check(SNAPSHOT.apply_snapshot(world, world.player, RunContext, saved, world.room_base_size, ENUMS.RunMode.STANDARD, ENUMS.RewardMode.NONE), "Production snapshot service restores the checkpoint")
	check(world.run_session.act_biome_ids == ["shatterfield", "hollow", "void_breach"] and world.run_session.last_standard_encounter_key == "crossfire" and world.run_session.last_objective_kind == "hold_the_line", "Continue replaces a fresh fallback roster and recovers encountered categories")
	check(world.door_options == expected_doors, "Continue retains already offered doors and exact resolved cover without rerolling")
	var legacy := saved.duplicate(true)
	for key in ["act_biome_ids", "last_standard_encounter_key", "last_objective_kind"]:
		legacy.erase(key)
	world.run_session.act_biome_ids = ["haunt", "storm_reach", "convergence_end"]
	check(SNAPSHOT.apply_snapshot(world, world.player, RunContext, legacy, world.room_base_size, ENUMS.RunMode.STANDARD, ENUMS.RewardMode.NONE), "Existing version-1 checkpoints remain loadable without new fields")
	check(world.run_session.act_biome_ids == ["haunt", "storm_reach", "convergence_end"] and world.run_session.last_standard_encounter_key.is_empty() and world.run_session.last_objective_kind.is_empty() and world.door_options == expected_doors, "Legacy Continue keeps fallback biome and offered doors while beginning trustworthy history")
	builder.free()
	await _cleanup()

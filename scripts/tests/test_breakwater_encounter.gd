extends "res://scripts/tests/test_ascension_runtime.gd"
## Real encounter construction, route resolution, disk checkpoint and spawns.

const BUILDER := preload("res://scripts/encounter_profile_builder.gd")
const BIOMES := preload("res://scripts/shared/biome_registry.gd")
const SPAWNER := preload("res://scripts/enemy_spawner.gd")
const ENDLESS := preload("res://scripts/shared/endless_profile_scaler.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const KEY := "apex_breakwater"

class SpawnWorld extends FIXTURES.TestWorld:
	var deaths := 0
	func _on_room_enemy_died(_position: Vector2 = Vector2.ZERO) -> void:
		deaths += 1 # Keep actual spawner death registration; suppress new room UI.

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Breakwater encounter tests require a disposable project and profile")
		quit(1)
		return
	var probe := _builder(0, 1)
	var ready := CONTRACTS.profile_encounter_key(probe.build_debug_encounter_profile(KEY, 5)) == KEY
	_dispose_builder(probe)
	_check(ready, "The real builder exposes the new Apex profile")
	if ready:
		_test_profile_matrix()
		_test_routes()
		_test_disk_checkpoints_and_legacy()
		await _test_actual_spawn_matrix()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[BreakwaterEncounter] %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _builder(tier: int, players: int) -> BUILDER:
	var builder := BUILDER.new()
	var random := RandomNumberGenerator.new()
	random.seed = 4207
	builder.initialize(random)
	builder.set_use_multiplayer_difficulty_config(players > 1)
	builder.set_multiplayer_party_size(players)
	builder.set_difficulty_tier(tier)
	builder.set_ascension_loadout(LOADOUT)
	return builder

func _dispose_builder(builder: BUILDER) -> void:
	builder.multiplayer_difficulty_config.free()
	builder.free()

func _one_breakwater(profile: Dictionary) -> bool:
	if int(profile.get("breakwater_count", 0)) != 1 or CONTRACTS.profile_total_enemy_count(profile) != 1:
		return false
	for enemy_type in SPAWNER.ENEMY_SPAWN_ORDER:
		if enemy_type != "breakwater" and int(profile.get(enemy_type + "_count", 0)) != 0:
			return false
	return true

func _test_profile_matrix() -> void:
	for tier in range(4):
		for players in range(1, 5):
			var builder := _builder(tier, players)
			for biome_id in BIOMES.BIOME_DEFINITIONS:
				builder.set_active_biome(BIOMES.get_biome(biome_id))
				var profile := builder.build_debug_encounter_profile(KEY, 8)
				var detail := "%d/%d/%s" % [tier, players, biome_id]
				_check(_one_breakwater(profile), "Builder has exactly one Apex and no adds: " + detail)
				_check(CONTRACTS.profile_room_size(profile) == BUILDER.TRIAL_ROOM_SIZE and profile.get("obstacle_layout", []).is_empty(), "The actual Apex arena remains open: " + detail)
				var normalized := CONTRACTS.normalize_profile(profile)
				_check(_one_breakwater(normalized) and CONTRACTS.profile_encounter_key(normalized) == KEY, "Normalization preserves count and stable identity: " + detail)
				var pressure := builder._apply_bearing_count_scaling(normalized)
				_check(_one_breakwater(builder.apply_wave_staggering(pressure)), "Bearing/Ascension/co-op pressure cannot add or remove the Apex: " + detail)
				var valid_variants := true
				for mutator in builder.get_hard_enemy_mutator_pool():
					var variant := builder.apply_mutator_variant_to_profile(profile, mutator, 12)
					valid_variants = valid_variants and _one_breakwater(variant) and _one_breakwater(builder.apply_wave_staggering(variant))
				_check(valid_variants, "Every production hard mutator retains the solitary encounter: " + detail)
				var endless := ENDLESS.apply_scaling(profile, true, true, 40, 12, BUILDER.POOL_ROOM_SIZE, 1100.0)
				_check(_one_breakwater(endless) and _one_breakwater(builder.apply_wave_staggering(endless)) and CONTRACTS.profile_encounter_key(endless) == KEY, "Endless changes pressure without adding foes or changing identity: " + detail)
				var contaminated := profile.duplicate(true)
				for enemy_type in SPAWNER.ENEMY_SPAWN_ORDER:
					contaminated[enemy_type + "_count"] = 8
				contaminated["wave_count"] = 3
				_check(_one_breakwater(CONTRACTS.normalize_profile(contaminated)), "Late population modifiers cannot bypass normalized encounter limits: " + detail)
			_dispose_builder(builder)

func _test_routes() -> void:
	var flow := FLOW.new()
	root.add_child(flow)
	var router := ROUTES.new()
	router.set_encounter_flow_system(flow)
	for tier in range(4):
		for players in range(1, 5):
			var builder := _builder(tier, players)
			var early_apex := false
			for depth in range(5):
				for seed_value in range(24):
					builder.rng.seed = seed_value
					early_apex = early_apex or not builder._build_apex_trial_route_option(depth).is_empty()
					for door in builder.roll_route_options({"depth": depth, "rooms_until_boss": 3, "all_players_full_hp": true}):
						early_apex = early_apex or CONTRACTS.profile_encounter_key(CONTRACTS.door_option_profile(door)).begins_with("apex_")
			_check(not early_apex, "Ordinary Apex eligibility starts at depth five: %d/%d" % [tier, players])
			var found: Dictionary = {}
			for seed_value in range(640):
				builder.rng.seed = seed_value
				var routes := builder.roll_route_options({"depth": 5, "rooms_until_boss": 3, "all_players_full_hp": true})
				for door in routes:
					if CONTRACTS.profile_encounter_key(CONTRACTS.door_option_profile(door)) == KEY:
						found = door
						break
				if not found.is_empty():
					break
			_check(not found.is_empty(), "Real seeded two-door routes can offer Breakwater at depth five: %d/%d" % [tier, players])
			if not found.is_empty():
				var state := router.build_route_state(false, [], false, false, false, 5, 220.0, [found], false, false)
				var door := router.find_used_door(CONTRACTS.door_option_get_position(state.door_options[0]), state.door_options, 60.0)
				var choice := router.resolve_choice(door)
				_check(CONTRACTS.door_choice_action_id(choice) == CONTRACTS.ACTION_ENCOUNTER and CONTRACTS.door_choice_reward_mode(choice) == ENUMS.RewardMode.ARCANA and _one_breakwater(CONTRACTS.door_choice_profile(choice)), "Actual door use retains the existing Arcana reward and one enemy")
				var cleared := flow.resolve_room_cleared(false, CONTRACTS.door_choice_reward_mode(choice), 4, 5, 12)
				_check(int(cleared.get("open_reward_mode", -1)) == ENUMS.RewardMode.ARCANA, "Clearing the selected Apex uses the existing Arcana reward flow")
			_dispose_builder(builder)
	var builder := _builder(2, 1)
	var frequencies: Dictionary = {}
	for seed_value in range(1024):
		builder.rng.seed = seed_value
		var key := CONTRACTS.profile_encounter_key(builder._pick_apex_encounter_profile(8))
		frequencies[key] = int(frequencies.get(key, 0)) + 1
	for key in ["apex_seamlock", "apex_mirrorline", "apex_toll", KEY]:
		_check(int(frequencies.get(key, 0)) >= 190 and int(frequencies.get(key, 0)) <= 325, "Actual Apex draws give each of four variants comparable weight: " + key)
	_dispose_builder(builder)
	flow.free()

func _test_disk_checkpoints_and_legacy() -> void:
	for tier in range(4):
		var world := _make_world(tier)
		var profile: Dictionary = world.encounter_profile_builder.build_debug_encounter_profile(KEY, 8)
		var legacy := world.encounter_profile_builder.build_debug_encounter_profile("apex_toll", 8)
		legacy.erase("breakwater_count")
		var original_legacy := legacy.duplicate(true)
		world.door_options = [CONTRACTS.apex_trial_door_option(profile, "Apex Breakwater", Color.WHITE), CONTRACTS.apex_trial_door_option(legacy, "Apex Toll", Color.WHITE)]
		world.rooms_cleared = 7
		world.room_depth = 8
		var snapshot := world._build_active_run_snapshot()
		_check(world.context.save_active_run(snapshot), "Real checkpoint writes the offered Apex profile to isolated disk")
		world.door_options.clear()
		var loaded := world.context.load_active_run()
		_check(world._apply_active_run_snapshot(loaded), "Actual resume restores the persisted pending route")
		_check(world.door_options.size() == 2 and world.rooms_cleared == 7 and world.room_depth == 8, "Resume keeps route choice and progression")
		if world.door_options.size() == 2:
			_check(CONTRACTS.door_option_profile(world.door_options[0]) == profile, "Resume preserves the complete chosen Breakwater profile without rerolling")
			_check(CONTRACTS.door_option_profile(world.door_options[1]) == original_legacy, "A legacy Apex profile without the new count field remains byte-equivalent in the resumed choice")
			var legacy_normalized := CONTRACTS.normalize_profile(CONTRACTS.door_option_profile(world.door_options[1]))
			_check(CONTRACTS.profile_toll_count(legacy_normalized) == 1 and int(legacy_normalized.get("breakwater_count", 0)) == 0, "Legacy normalization does not convert another Apex to Breakwater")
		world.context.clear_active_run()
		_free_world(world)

func _test_actual_spawn_matrix() -> void:
	for tier in range(4):
		for players in range(1, 5):
			var builder := _builder(tier, players)
			for biome_id in BIOMES.BIOME_DEFINITIONS:
				builder.set_active_biome(BIOMES.get_biome(biome_id))
				var world := SpawnWorld.new()
				root.add_child(world)
				for peer_index in range(players):
					var party_member := FIXTURES.TestPlayer.new()
					party_member.player_id = peer_index + 1
					world.add_child(party_member)
					party_member.position = Vector2(float(peer_index) * 45.0, 0.0)
					world.party.append(party_member)
				world.player = world.party[0]
				# This builds the actual production script map; forgetting its new
				# entry must fail even when contract/profile tests still pass.
				world._setup_enemy_spawner_system()
				var spawner := world.enemy_spawner as SPAWNER
				spawner.multiplayer_party_size = players
				var profile := builder.build_debug_encounter_profile(KEY, 8)
				spawner.configure_room(CONTRACTS.profile_room_size(profile), 90.0, 170.0, CONTRACTS.profile_enemy_mutator(profile))
				var contaminated := profile.duplicate(true)
				for enemy_type in SPAWNER.ENEMY_SPAWN_ORDER:
					contaminated[enemy_type + "_count"] = 3
				contaminated["wave_count"] = 3
				var report := spawner.spawn_profile_enemies_report(contaminated)
				var correct := report.size() == 1 and String(report[0].get("enemy_type", "")) == "breakwater"
				_check(correct and spawner._pending_waves.is_empty(), "Actual spawning produces one Breakwater, with no queued adds: %d/%d/%s" % [tier, players, biome_id])
				var refused := true
				for enemy_type in SPAWNER.ENEMY_SPAWN_ORDER:
					refused = refused and spawner.spawn_enemy_type(enemy_type, 2) == 0
				_check(refused, "Direct additional spawn requests cannot bypass the solitary Apex")
				if correct:
					var enemy := report[0].enemy as CharacterBody2D
					enemy.set_physics_process(false)
					_check(enemy.get_script().resource_path == "res://scripts/enemy_breakwater.gd", "Production script mapping creates the real new enemy")
					var safe_position := true
					for party_member in world.party:
						safe_position = safe_position and enemy.global_position.distance_to(party_member.global_position) >= 170.0
					_check(safe_position and int(enemy.get_max_health()) > 0, "Spawn transport begins away from every player with live health")
					_check(enemy.target_candidates.size() == players, "Actual target assignment retains every co-op player")
					var expected_health := int(round(900.0 * [0.8, 1.0, 1.2, 1.4][tier] * (1.0 + 0.6 * float(players - 1))))
					_check(int(enemy.get_max_health()) == expected_health, "Real tier and co-op application scales only the approved health pressure")
					_check(int(enemy.charge_damage) == [12, 16, 18, 20][tier] and is_equal_approx(float(enemy.attack_cooldown), 1.5 * [1.35, 1.0, 0.85, 0.70][tier]), "Co-op does not shorten the tell/cadence or inflate the tier's hit damage")
					enemy.take_damage(999999)
					_check(world.deaths == 1 and spawner.spawn_enemy_type("breakwater", 1) == 0 and spawner.spawn_enemy_type("chaser", 1) == 0, "Its one death is registered; an already-cleared Apex cannot be repopulated")
					var ordinary := CONTRACTS.profile("Skirmish", BUILDER.POOL_ROOM_SIZE, true, 1, 0, 0, 0)
					spawner.configure_room(BUILDER.POOL_ROOM_SIZE, 90.0, 170.0, {})
					var next_report := spawner.spawn_profile_enemies_report(ordinary)
					_check(next_report.size() == 1 and String(next_report[0].get("enemy_type", "")) == "chaser", "The room-scoped spawn lock clears for the next ordinary encounter")
				world.free()
				await process_frame
			_dispose_builder(builder)

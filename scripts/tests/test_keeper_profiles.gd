extends "res://scripts/tests/test_ascension_runtime.gd"
## Reuse isolated checkpoint fixtures, not their scenario runner.

const BUILDER := preload("res://scripts/encounter_profile_builder.gd")
const BIOMES := preload("res://scripts/shared/biome_registry.gd")
const DEBUG := preload("res://scripts/shared/debug_enums.gd")
const GLOSSARY := preload("res://scripts/shared/glossary_data.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const DEFINITIONS := preload("res://scripts/shared/encounter_definition_data.gd")
const SPAWNER := preload("res://scripts/enemy_spawner.gd")
const KEEPER := preload("res://scripts/enemy_keeper.gd")
const ARCHER := preload("res://scripts/enemy_archer.gd")
const CHASER := preload("res://scripts/enemy_chaser.gd")
const ENDLESS := preload("res://scripts/shared/endless_profile_scaler.gd")

func _run() -> void:
	_test_profiles()
	_test_saved_profiles()
	await _test_actual_spawns()
	print("[KeeperProfiles] %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _builder(tier: int, coop: bool = false) -> BUILDER:
	var builder := BUILDER.new()
	var random := RandomNumberGenerator.new()
	random.seed = 2781
	builder.initialize(random)
	builder.set_use_multiplayer_difficulty_config(coop)
	builder.set_multiplayer_party_size(4 if coop else 1)
	builder.set_difficulty_tier(tier)
	return builder

func _test_profiles() -> void:
	_check(BUILDER.validate_bearing_sync().is_empty(), "All encounter definitions match the canonical registry")
	_check(CONTRACTS.validate_encounter_sync(GLOSSARY._encounter_rows()).is_empty(), "Breach routes, debug entries and glossary are synchronized")
	_check(DEBUG.Encounter.BOSS_3 == 25 and DEBUG.Encounter.UNDERTOW == 26, "New debug entries preserve existing saved encounter IDs")
	var archers := [1, 2, 2, 3]
	var chasers := [2, 2, 3, 4]
	for tier in range(4):
		for coop in [false, true]:
			var builder := _builder(tier, coop)
			var profile := builder.build_debug_encounter_profile("breach", 8)
			_check(CONTRACTS.profile_encounter_key(profile) == "breach" and CONTRACTS.profile_label(profile) == "Breach", "Breach has stable route identity on every Bearing/party size")
			_check(int(profile.get("keeper_count", 0)) == 1 and CONTRACTS.profile_archer_count(profile) == archers[tier] and CONTRACTS.profile_chaser_count(profile) == chasers[tier], "Breach uses its approved Keeper/Archer/Chaser population: %d/%s" % [tier, coop])
			_check(CONTRACTS.profile_total_enemy_count(profile) == 1 + archers[tier] + chasers[tier], "Total room population includes the support enemy exactly once")
			var door := CONTRACTS.standard_encounter_door_option(profile)
			_check(CONTRACTS.door_option_kind_id(door) == CONTRACTS.DOOR_KIND_ENCOUNTER and CONTRACTS.door_option_reward_mode(door) == ENUMS.RewardMode.BOON, "Breach keeps ordinary encounter rewards and room pacing")
			for act in [1, 2, 3]:
				builder.set_active_biome({"act": act})
				var found := false
				for candidate in builder._get_hard_pool_for_depth(8):
					found = found or CONTRACTS.profile_encounter_key(candidate) == "breach"
				_check(found == (act >= 2), "Breach eligibility follows Act 2/3, including co-op")
			for biome_id in BIOMES.BIOME_DEFINITIONS:
				builder.set_active_biome(BIOMES.get_biome(biome_id))
				var weighted := builder.build_debug_encounter_profile("breach", 8)
				weighted = builder.apply_mutator_variant_to_profile(weighted, builder.build_debug_mutator("blood_rush"), 8)
				weighted = builder.apply_wave_staggering(weighted)
				_check(int(weighted.get("keeper_count", 0)) == 1, "Biome/mutator/party weighting never adds a second Keeper: %s/%d/%s" % [biome_id, tier, coop])
			profile["keeper_count"] = 20
			profile["drifter_count"] = 4
			profile["sentinel_count"] = 2
			_check(int(builder.apply_wave_staggering(profile).get("keeper_count", 0)) == 1, "Late planned population changes retain the one-Keeper cap")
			var normalized := CONTRACTS.normalize_profile(profile)
			_check(CONTRACTS.profile_drifter_count(normalized) == 0 and int(normalized.get("sentinel_count", 0)) == 0, "Late biome role injection cannot replace Breach's approved three-role composition")
			var endless := ENDLESS.apply_scaling(profile, true, true, 15, 12, DEFINITIONS.POOL_ROOM_SIZE, 1100.0)
			_check(CONTRACTS.profile_encounter_key(endless) == "breach" and int(builder.apply_wave_staggering(endless).get("keeper_count", 0)) == 1, "Endless presentation retains canonical Breach identity and cap")
			var routed := false
			builder.set_active_biome({"act": 2})
			for seed_value in range(128):
				builder.rng.seed = seed_value
				routed = routed or CONTRACTS.door_option_encounter_key(builder._build_hard_route_option(8)) == "breach"
			_check(routed, "Real seeded standard routes can choose Breach")
			builder.multiplayer_difficulty_config.free()
			builder.free()

func _test_saved_profiles() -> void:
	for tier in range(4):
		var world := _make_world(tier)
		var profile: Dictionary = world.encounter_profile_builder.build_debug_encounter_profile("breach", 8)
		world.door_options = [CONTRACTS.standard_encounter_door_option(profile)]
		world.rooms_cleared = 7
		var saved := world._build_active_run_snapshot()
		world.door_options.clear()
		_check(world._apply_active_run_snapshot(saved), "Real run checkpoint restores a pending Breach choice")
		var restored := CONTRACTS.door_option_profile(world.door_options[0])
		_check(restored == profile and world.rooms_cleared == 7, "Checkpoint preserves the selected composition, cover, and run progress")
		_check(int(restored.get("keeper_count", 0)) == 1 and CONTRACTS.profile_total_enemy_count(restored) == CONTRACTS.profile_total_enemy_count(profile), "Saved Keeper population survives actual resume normalization")
		_free_world(world)

func _test_actual_spawns() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var player := FIXTURES.TestPlayer.new()
	arena.add_child(player)
	var spawner := SPAWNER.new()
	arena.add_child(spawner)
	var random := RandomNumberGenerator.new()
	random.seed = 791
	spawner.initialize(arena, player, random, {"keeper": KEEPER, "archer": ARCHER, "chaser": CHASER}, Callable())
	spawner.multiplayer_party_size = 4
	spawner.configure_room(DEFINITIONS.POOL_ROOM_SIZE, 90.0, 170.0, {})
	var builder := _builder(3, true)
	var profile := builder.build_debug_encounter_profile("breach", 8)
	profile["keeper_count"] = 12
	var report := spawner.spawn_profile_enemies_report(profile)
	var keepers: Array[Node2D] = []
	for entry in report:
		var enemy := entry.enemy as Node2D
		enemy.set_physics_process(false)
		if enemy is KEEPER:
			keepers.append(enemy)
	_check(keepers.size() == 1 and report.size() == 8, "Actual co-op Breach spawn obeys the cap and approved total")
	for entry in report:
		entry.enemy._update_spawn_transport(1.5)
	await physics_frame
	await process_frame
	var support := keepers[0] as KEEPER
	support._update_wards(0.001)
	support._update_wards(0.61)
	_check(not support.ward_targets.is_empty(), "Real Breach placement starts close enough to protect an ally after transport and warmup")
	_check(support.global_position.length() >= 170.0, "Nearby support placement still respects the player's spawn safety radius")
	_check(spawner.spawn_enemy_type("keeper", 3) == 0, "Additional spawn requests cannot bypass a living Keeper")
	_check(spawner._spawn_types_immediate(["keeper"], false).is_empty(), "Rejected Keeper spawn returns no phantom room enemy")
	keepers[0].take_damage(999999)
	_check(spawner.spawn_enemy_type("keeper") == 1, "A dead Keeper frees the one live slot")
	builder.multiplayer_difficulty_config.free()
	builder.free()
	arena.free()
	await process_frame

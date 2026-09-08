extends SceneTree

const BUILDER := preload("res://scripts/encounter_profile_builder.gd")
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const DEFINITIONS := preload("res://scripts/shared/encounter_definition_data.gd")
const LAYOUTS := preload("res://scripts/shared/arena_layout_registry.gd")
const BIOMES := preload("res://scripts/shared/biome_registry.gd")
const DEBUG := preload("res://scripts/shared/debug_enums.gd")
const GLOSSARY := preload("res://scripts/shared/glossary_data.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const SPAWNER := preload("res://scripts/enemy_spawner.gd")
const DRIFTER := preload("res://scripts/enemy_drifter.gd")
const CHASER := preload("res://scripts/enemy_chaser.gd")
const CHARGER := preload("res://scripts/enemy_charger.gd")
const FIXTURES := preload("res://scripts/tests/test_catalyst_runtime.gd")
const ENDLESS := preload("res://scripts/shared/endless_profile_scaler.gd")

const NEW_TEMPLATES := {
	"Crossfire": "offset_firing_lanes",
	"Fortress": "broken_ring",
	"Vanguard": "forked_approach",
	"Ambush": "side_cover",
}

var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	_test_registry_and_profiles()
	_test_act_routes_and_biomes()
	_test_layouts()
	_test_endless_identity_and_layouts()
	await _test_spawn_limit_and_stagger()
	print("Undertow and layout regressions: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _builder(tier: int, seed_value: int = 27, coop: bool = false) -> BUILDER:
	var builder := BUILDER.new()
	var seeded_rng := RandomNumberGenerator.new()
	seeded_rng.seed = seed_value
	builder.initialize(seeded_rng)
	builder.set_use_multiplayer_difficulty_config(coop)
	builder.set_multiplayer_party_size(4 if coop else 1)
	builder.set_difficulty_tier(tier)
	return builder

func _free_builder(builder: BUILDER) -> void:
	builder.multiplayer_difficulty_config.free()
	builder.free()

func _test_registry_and_profiles() -> void:
	_check(BUILDER.validate_bearing_sync().is_empty(), "All ten pool encounter definitions match the canonical registry")
	_check(CONTRACTS.validate_encounter_sync(GLOSSARY._encounter_rows()).is_empty(), "Debug names, route presentation and glossary remain synchronized")
	_check(DEBUG.Encounter.BOSS_3 == 25 and DEBUG.Encounter.UNDERTOW == 26, "Appending Undertow preserves saved debug encounter IDs")
	_check(CONTRACTS.debug_encounter_key_from_id(DEBUG.Encounter.UNDERTOW) == "undertow", "Undertow debug enum resolves to its builder key")
	var expected_chasers := [2, 3, 3, 4]
	var expected_chargers := [0, 1, 1, 2]
	var expected_drifters := [1, 1, 2, 2]
	for tier in range(4):
		for coop in [false, true]:
			var builder := _builder(tier, 27, coop)
			for label in BUILDER.BEARING_LABELS:
				var profile := builder.build_debug_encounter_profile(label.to_lower(), 8)
				_check(CONTRACTS.profile_label(profile) == label, "Encounter identity survives setup: %s/%d/%s" % [label, tier, coop])
				_check(CONTRACTS.profile_total_enemy_count(profile) > 0, "Standard encounter has living opposition: %s/%d" % [label, tier])
				var door := CONTRACTS.standard_encounter_door_option(profile)
				_check(CONTRACTS.door_option_kind_id(door) == CONTRACTS.DOOR_KIND_ENCOUNTER and CONTRACTS.door_option_reward_mode(door) == ENUMS.RewardMode.BOON, "Standard reward pacing stays unchanged: %s" % label)
				if label == "Undertow":
					_check(CONTRACTS.profile_drifter_count(profile) == expected_drifters[tier] and CONTRACTS.profile_chaser_count(profile) == expected_chasers[tier] and CONTRACTS.profile_charger_count(profile) == expected_chargers[tier], "Undertow uses approved Drifter/pursuit composition: %d/%s" % [tier, coop])
					_check(CONTRACTS.profile_total_enemy_count(profile) == expected_drifters[tier] + expected_chasers[tier] + expected_chargers[tier], "Undertow introduces no other threat roles")
					_check((profile.get("obstacle_layout", []) as Array).is_empty(), "Undertow leaves ring-reading space open")
			var capped := builder.build_debug_encounter_profile("undertow", 8)
			capped["drifter_count"] = 40
			capped = builder.apply_wave_staggering(capped)
			_check(CONTRACTS.profile_drifter_count(capped) == 2, "Late profile/count scaling cannot exceed the planned Drifter cap")
			for apex_key in ["apex_trial", "apex_mirrorline", "apex_toll"]:
				var apex := builder.build_debug_encounter_profile(apex_key, 9)
				_check(not apex.is_empty() and (apex.get("obstacle_layout", []) as Array).is_empty(), "Apex profiles stay available and obstacle-free")
			_free_builder(builder)

func _test_act_routes_and_biomes() -> void:
	for tier in range(4):
		var builder := _builder(tier)
		for template in builder._get_hard_pool():
			_check(CONTRACTS.profile_label(template) != "Undertow", "Trial/objective template pools keep their existing enemy mixtures")
		for act in [1, 2, 3]:
			builder.set_active_biome({"act": act})
			var pool := builder._get_hard_pool_for_depth(8)
			var found := false
			for profile in pool:
				found = found or CONTRACTS.profile_label(profile) == "Undertow"
			_check(found == (act >= 2), "Undertow route eligibility follows act instead of raw depth: %d/%d" % [tier, act])
		var routed := false
		for seed_value in range(96):
			builder.rng.seed = seed_value
			builder.set_active_biome({"act": 2})
			var option := builder._build_hard_route_option(8)
			routed = routed or CONTRACTS.door_option_encounter_key(option) == "undertow"
		_check(routed, "Undertow is selectable through real standard routes on every Bearing")
		for biome_id in BIOMES.BIOME_DEFINITIONS:
			builder.set_active_biome(BIOMES.get_biome(biome_id))
			var profile := builder.build_debug_encounter_profile("undertow", 8)
			profile = builder.apply_mutator_variant_to_profile(profile, builder.build_debug_mutator("blood_rush"), 8)
			profile = builder.apply_wave_staggering(profile)
			_check(CONTRACTS.profile_drifter_count(profile) <= 2, "Biome and mutator weighting keep at most two planned Drifters: %s/%d" % [biome_id, tier])
		var first := _builder(tier, 871, true)
		var second := _builder(tier, 871, true)
		first.set_active_biome(BIOMES.get_biome("storm_reach"))
		second.set_active_biome(BIOMES.get_biome("storm_reach"))
		for _sample in range(12):
			_check(first.roll_route_options({"depth": 8, "rooms_until_boss": 3}) == second.roll_route_options({"depth": 8, "rooms_until_boss": 3}), "Same co-op seed/setup yields identical route profiles and layouts")
		_free_builder(first)
		_free_builder(second)
		_free_builder(builder)

func _test_layouts() -> void:
	for label in NEW_TEMPLATES:
		var template_name: String = NEW_TEMPLATES[label]
		_check((LAYOUTS._ENCOUNTER_POOL[label] as Array).has(template_name), "New formation is available for its intended encounter: %s" % label)
		var positions := LAYOUTS._resolve_positions(template_name)
		_check(positions.size() >= 4, "Formation has enough distinct cover anchors: %s" % label)
		for index in range(positions.size()):
			var point := positions[index]
			_check(point.length() - LAYOUTS.COLUMN_RADIUS >= 100.0, "Formation preserves a safe open center: %s" % label)
			_check(absf(point.x) + LAYOUTS.COLUMN_RADIUS < DEFINITIONS.INTRO_ROOM_SIZE.x * 0.5 - 70.0 and absf(point.y) + LAYOUTS.COLUMN_RADIUS < DEFINITIONS.INTRO_ROOM_SIZE.y * 0.5 - 70.0, "Cover leaves edge traversal clearance in the smallest room: %s" % label)
			for other_index in range(index + 1, positions.size()):
				_check(point.distance_to(positions[other_index]) - 2.0 * LAYOUTS.COLUMN_RADIUS >= 70.0, "Cover gaps permit ordinary movement as well as Arcana: %s" % label)
		var generated := false
		for seed_value in range(48):
			var random := RandomNumberGenerator.new()
			random.seed = seed_value
			var layout := LAYOUTS.pick_layout(label, DEFINITIONS.POOL_ROOM_SIZE, random)
			if layout.size() == positions.size() and (layout[0]["pos"] as Vector2).is_equal_approx(positions[0]):
				generated = true
		_check(generated, "New formation is reachable through seeded layout selection: %s" % label)
	for label in ["Undertow", "Tutorial", "Hold the Line", "Trial Blood Rush", "Apex Seamlock", "Apex Mirrorline", "Apex Toll"]:
		_check(LAYOUTS.pick_layout(label, DEFINITIONS.POOL_ROOM_SIZE, RandomNumberGenerator.new()).is_empty(), "Open-room exceptions remain open: %s" % label)

func _test_endless_identity_and_layouts() -> void:
	var builder := _builder(3)
	for label in NEW_TEMPLATES:
		var profile := builder.build_debug_encounter_profile(String(label).to_lower(), 8)
		profile["obstacle_layout"] = [{"pos": Vector2(260.0, 155.0), "radius": LAYOUTS.COLUMN_RADIUS}]
		var scaled := ENDLESS.apply_scaling(profile, true, true, 13, 12, DEFINITIONS.POOL_ROOM_SIZE, 1100.0)
		_check(scaled["obstacle_layout"] == profile["obstacle_layout"], "Endless preserves the chosen formation: %s" % label)
		(scaled["obstacle_layout"] as Array)[0]["radius"] = 99.0
		_check(profile["obstacle_layout"][0]["radius"] == LAYOUTS.COLUMN_RADIUS, "Endless layout copy cannot mutate the saved door choice")
	var undertow := builder.build_debug_encounter_profile("undertow", 8)
	var scaled_undertow := ENDLESS.apply_scaling(undertow, true, true, 15, 12, DEFINITIONS.POOL_ROOM_SIZE, 1100.0)
	_check(CONTRACTS.profile_label(scaled_undertow) == "Undertow  Tier 3" and CONTRACTS.profile_encounter_key(scaled_undertow) == "undertow", "Endless changes presentation while retaining Undertow identity")
	scaled_undertow["drifter_count"] = 20
	_check(CONTRACTS.profile_drifter_count(builder.apply_wave_staggering(scaled_undertow)) == 2, "Late Endless modifiers still obey Undertow's planned cap")
	scaled_undertow.erase(CONTRACTS.KEY_ENCOUNTER_KEY)
	_check(CONTRACTS.profile_drifter_count(builder.apply_wave_staggering(scaled_undertow)) == 2, "Legacy Endless labels without identity retain the Drifter cap")
	_free_builder(builder)

func _test_spawn_limit_and_stagger() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var player := FIXTURES.TestPlayer.new()
	arena.add_child(player)
	var spawner := SPAWNER.new()
	arena.add_child(spawner)
	var random := RandomNumberGenerator.new()
	random.seed = 814
	spawner.initialize(arena, player, random, {"drifter": DRIFTER, "chaser": CHASER, "charger": CHARGER}, Callable())
	spawner.configure_room(DEFINITIONS.POOL_ROOM_SIZE, 90.0, 170.0, {CONTRACTS.MUTATOR_STAT_ARCHER_COOLDOWN_MULT: 0.4})
	spawner.multiplayer_party_size = 4
	var profile := CONTRACTS.profile("Undertow  Tier 3", DEFINITIONS.POOL_ROOM_SIZE, true, 4, 2, 0, 0)
	profile["drifter_count"] = 20
	var report := spawner.spawn_profile_enemies_report(profile)
	var drifters: Array[DRIFTER] = []
	for entry in report:
		var enemy := entry["enemy"] as Node
		enemy.set_physics_process(false)
		if enemy is DRIFTER:
			drifters.append(enemy as DRIFTER)
	_check(report.size() == 8 and drifters.size() == 2, "Spawn-time cap keeps actual and planned capped populations aligned")
	_check(absf(drifters[0].wave_timer - drifters[1].wave_timer) >= 0.49 * drifters[0].wave_interval, "Undertow offsets first rings even under cooldown mutators")
	_check(spawner.spawn_enemy_type("drifter", 4) == 0 and spawner._living_drifter_count() == 2, "Extra spawn requests cannot exceed two living Drifters")
	_check(spawner._spawn_types_immediate(["drifter"], false).is_empty(), "Rejected Drifter spawn never reports a phantom enemy")
	drifters[0].take_damage(99999)
	_check(spawner.spawn_enemy_type("drifter") == 1 and spawner._living_drifter_count() == 2, "A dead Drifter frees one slot without blocking room completion")
	spawner.configure_room(DEFINITIONS.POOL_ROOM_SIZE, 90.0, 170.0, {})
	_check(spawner._drifter_limit == 0, "Undertow's local cap does not change other encounter compositions")
	arena.free()
	await process_frame

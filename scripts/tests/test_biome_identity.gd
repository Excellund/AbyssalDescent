extends SceneTree
## Biome terrain must change positioning without replacing encounter rules.

const BIOMES := preload("res://scripts/shared/biome_registry.gd")
const LAYOUTS := preload("res://scripts/shared/arena_layout_registry.gd")
const BUILDER := preload("res://scripts/encounter_profile_builder.gd")
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const DEFINITIONS := preload("res://scripts/shared/encounter_definition_data.gd")
const ENDLESS := preload("res://scripts/shared/endless_profile_scaler.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")

const ORDINARY := ["Skirmish", "Pursuit", "Crossfire", "Onslaught", "Fortress", "Blitz", "Suppression", "Vanguard", "Ambush", "Convergence", "Gauntlet"]
const PROTECTED := ["Undertow", "Breach", "Last Stand", "Cut the Signal", "Hold the Line", "Circuit Sweep", "Pulse Window", "Intercept Run", "Tutorial", "Trial Blood Rush", "Apex Seamlock", "Apex Mirrorline", "Apex Toll", "Apex Breakwater", "Boss Chamber: The Warden", "Abyss Core: Sovereign", "Silent Threshold: Lacuna", "Unknown room"]
const OBSTACLE_COUNTS := {"crumble": 4, "haunt": 4, "shatterfield": 4, "grinding_vault": 6, "storm_reach": 2, "hollow": 3, "void_breach": 0, "the_maelstrom": 4, "convergence_end": 8}

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Biome identity tests require disposable user data")
		quit(1)
		return
	_test_terrain_families()
	_test_protected_layouts()
	_test_profiles_and_serialization()
	_test_route_weights()
	print("[OK] Biome identity: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _rng(seed_value: int) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = seed_value
	return generator

func _builder(tier: int, party_size: int = 1) -> BUILDER:
	var builder := BUILDER.new()
	builder.initialize(_rng(481))
	builder.set_use_multiplayer_difficulty_config(party_size > 1)
	builder.set_multiplayer_party_size(party_size)
	builder.set_difficulty_tier(tier)
	return builder

func _test_terrain_families() -> void:
	check(BIOMES.BIOME_DEFINITIONS.size() == 9 and BIOMES.COMBAT_IDENTITIES.size() == 9, "Every existing biome has one combat identity")
	var signatures := {}
	for biome_id: String in BIOMES.BIOME_DEFINITIONS:
		var identity := BIOMES.get_combat_identity(biome_id)
		check(not identity.is_empty() and not String(identity.get("rule", "")).is_empty() and not String(identity.get("tactic", "")).is_empty() and not String(identity.get("entry_hint", "")).is_empty(), "Biome explains its terrain and an actionable response: " + biome_id)
		var initial := LAYOUTS.pick_layout("Crossfire", DEFINITIONS.INTRO_ROOM_SIZE, _rng(0), biome_id)
		var signature := _geometry_signature(initial)
		check(not signatures.has(signature), "Biome geometry differs from every earlier biome: " + biome_id)
		signatures[signature] = biome_id
		for room_size: Vector2 in [DEFINITIONS.INTRO_ROOM_SIZE, DEFINITIONS.POOL_ROOM_SIZE]:
			for label: String in ORDINARY:
				var deterministic := true
				var safe := true
				var family_matches := true
				var cover_matches := true
				for seed_value in range(32):
					var first_rng := _rng(seed_value)
					var second_rng := _rng(seed_value)
					var first := LAYOUTS.pick_layout(label, room_size, first_rng, biome_id)
					var second := LAYOUTS.pick_layout(label, room_size, second_rng, biome_id)
					deterministic = deterministic and first == second and first_rng.state == second_rng.state
					var crossfire := LAYOUTS.pick_layout("Crossfire", room_size, _rng(seed_value), biome_id)
					family_matches = family_matches and first.size() == int(OBSTACLE_COUNTS[biome_id]) and _geometry_signature(first) == _geometry_signature(crossfire)
					safe = safe and _layout_is_passable(first, room_size)
					for obstacle_index in first.size():
						var obstacle := first[obstacle_index]
						family_matches = family_matches and String(obstacle.get("type", "")) == ("boulder" if biome_id == "crumble" else "")
						var brittle := biome_id == "shatterfield" and label == "Crossfire" and obstacle_index in [1, 2]
						cover_matches = cover_matches and (obstacle.get("break_contacts", 0) == 3 if brittle else not obstacle.has("break_contacts"))
				check(deterministic and family_matches, "Ordinary rooms consistently resolve their seeded biome family: %s/%s/%s" % [biome_id, label, room_size])
				check(cover_matches, "Only Shatterfield Crossfire's inner columns use three-contact brittle cover: %s/%s/%s" % [biome_id, label, room_size])
				check(safe, "Terrain preserves center, perimeter and useful gaps in every sampled layout: %s/%s/%s" % [biome_id, label, room_size])

func _geometry_signature(layout: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for obstacle in layout:
		parts.append("%s/%s" % [obstacle.pos, obstacle.radius])
	parts.sort()
	return "|".join(parts)

func _layout_is_passable(layout: Array[Dictionary], room_size: Vector2) -> bool:
	for index in range(layout.size()):
		var obstacle := layout[index]
		var point: Vector2 = obstacle.pos
		var radius := float(obstacle.radius)
		# A 100px center disk fits the existing party arrival formation. A 70px
		# perimeter and between-obstacle gap admit walking without a dash power.
		if not point.is_finite() or radius <= 0.0 or point.length() - radius < 100.0:
			return false
		if room_size.x * 0.5 - absf(point.x) - radius < 70.0 or room_size.y * 0.5 - absf(point.y) - radius < 70.0:
			return false
		for other_index in range(index + 1, layout.size()):
			var other := layout[other_index]
			if point.distance_to(other.pos) - radius - float(other.radius) < 70.0:
				return false
	# Independent geometric reachability: a player-sized swept disk can leave
	# the center toward each quadrant without relying on wall phasing.
	for quadrant in range(4):
		var escape_exists := false
		for ray_index in range(9):
			var angle := float(quadrant) * PI * 0.5 + float(ray_index) * PI / 16.0
			var endpoint := Vector2.from_angle(angle) * room_size.length()
			var clear := true
			for obstacle in layout:
				var nearest := Geometry2D.get_closest_point_to_segment(obstacle.pos, Vector2.ZERO, endpoint)
				clear = clear and nearest.distance_to(obstacle.pos) >= float(obstacle.radius) + 22.0
			escape_exists = escape_exists or clear
		if not escape_exists:
			return false
	return true

func _test_protected_layouts() -> void:
	for biome_id: String in BIOMES.BIOME_DEFINITIONS:
		for label: String in PROTECTED:
			var unchanged := true
			for seed_value in range(16):
				var baseline_rng := _rng(seed_value)
				var actual_rng := _rng(seed_value)
				var baseline := LAYOUTS.pick_layout(label, DEFINITIONS.POOL_ROOM_SIZE, baseline_rng)
				var actual := LAYOUTS.pick_layout(label, DEFINITIONS.POOL_ROOM_SIZE, actual_rng, biome_id)
				unchanged = unchanged and actual == baseline and actual_rng.state == baseline_rng.state
			check(unchanged, "Specialist, mission, boss and unknown arenas retain geometry and RNG: %s/%s" % [biome_id, label])
	for label: String in ORDINARY:
		var unchanged := true
		for seed_value in range(16):
			var baseline_rng := _rng(seed_value)
			var unknown_rng := _rng(seed_value)
			var baseline := LAYOUTS.pick_layout(label, DEFINITIONS.INTRO_ROOM_SIZE, baseline_rng)
			var unknown := LAYOUTS.pick_layout(label, DEFINITIONS.INTRO_ROOM_SIZE, unknown_rng, "missing_biome")
			unchanged = unchanged and baseline == unknown and baseline_rng.state == unknown_rng.state
		check(unchanged, "Missing biome identity retains the legacy layout pool and RNG: " + label)

func _test_profiles_and_serialization() -> void:
	for tier in range(4):
		for party_size in range(1, 5):
			var actual_builder := _builder(tier, party_size)
			var baseline_builder := _builder(tier, party_size)
			for biome_id: String in BIOMES.BIOME_DEFINITIONS:
				var biome := BIOMES.get_biome(biome_id)
				var baseline_biome := biome.duplicate(true)
				baseline_biome.erase("id")
				actual_builder.set_active_biome(biome)
				baseline_builder.set_active_biome(baseline_biome)
				var unchanged_counts := true
				var capped := true
				var serialized := true
				var terrain_reached := true
				for label: String in BUILDER.BEARING_LABELS + ["Skirmish", "Pursuit"]:
					actual_builder.rng.seed = 72
					baseline_builder.rng.seed = 72
					var profile := _build_profile(actual_builder, label)
					var baseline := _build_profile(baseline_builder, label)
					var without_layout := profile.duplicate(true)
					without_layout.erase("obstacle_layout")
					baseline.erase("obstacle_layout")
					unchanged_counts = unchanged_counts and without_layout == baseline and CONTRACTS.profile_total_enemy_count(profile) > 0
					var weighted := actual_builder.apply_wave_staggering(actual_builder.apply_mutator_variant_to_profile(profile, actual_builder.build_debug_mutator("blood_rush"), 9))
					capped = capped and CONTRACTS.profile_keeper_count(weighted) <= 1 and (label != "Undertow" or CONTRACTS.profile_drifter_count(weighted) <= 2)
					if ORDINARY.has(label):
						terrain_reached = terrain_reached and CONTRACTS.profile_obstacle_layout(profile).size() == int(OBSTACLE_COUNTS[biome_id])
					var door := CONTRACTS.standard_encounter_door_option(profile)
					var restored: Dictionary = bytes_to_var(var_to_bytes(door))
					serialized = serialized and restored == door and CONTRACTS.door_option_reward_mode(restored) == ENUMS.RewardMode.BOON
					var endless := ENDLESS.apply_scaling(profile, true, true, 13, 12, DEFINITIONS.POOL_ROOM_SIZE, 1100.0)
					serialized = serialized and CONTRACTS.profile_obstacle_layout(endless) == CONTRACTS.profile_obstacle_layout(profile)
				check(unchanged_counts and capped, "Terrain preserves all encounter populations, stats and specialist caps: %s/Bearing%d/party%d" % [biome_id, tier, party_size])
				check(serialized and terrain_reached, "Real profiles carry biome terrain through doors, wire serialization and Endless without changing rewards: %s/Bearing%d/party%d" % [biome_id, tier, party_size])
			actual_builder.free()
			baseline_builder.free()

func _build_profile(builder: BUILDER, label: String) -> Dictionary:
	if label == "Pursuit":
		return builder._build_intro_variant_profile(0)
	return builder.build_debug_encounter_profile(label.to_lower(), 9)

func _label_counts(pool: Array[Dictionary]) -> Dictionary:
	var result := {}
	for profile in pool:
		var label := CONTRACTS.profile_label(profile)
		result[label] = int(result.get(label, 0)) + 1
	return result

func _test_route_weights() -> void:
	for tier in range(4):
		var builder := _builder(tier)
		for biome_id: String in BIOMES.BIOME_DEFINITIONS:
			var biome := BIOMES.get_biome(biome_id)
			builder.set_active_biome(biome)
			var pool := builder._get_hard_pool_for_depth(12)
			var counts := _label_counts(pool)
			var weighted_correctly := true
			for label: String in BUILDER.BEARING_LABELS:
				var expected := 3 if (biome.preferred_encounter_labels as Array).has(label) else 1
				if label in ["Undertow", "Breach"] and int(biome.act) == 1:
					expected = 0
				weighted_correctly = weighted_correctly and int(counts.get(label, 0)) == expected
			check(weighted_correctly, "Eligible preferred routes have exactly triple weight; act gates remain authoritative: %s/Bearing%d" % [biome_id, tier])
			var early := _label_counts(builder._get_hard_pool_for_depth(0))
			check(not early.has("Ambush"), "A preferred Ambush cannot bypass its depth gate: %s/Bearing%d" % [biome_id, tier])
			var filtered_correctly := true
			for previous_label: String in counts:
				var before_state := builder.rng.state
				var filtered := _label_counts(builder._without_previous_standard_encounter(pool, previous_label.to_lower()))
				filtered_correctly = filtered_correctly and not filtered.has(previous_label) and builder.rng.state == before_state
				for other_label: String in counts:
					if other_label != previous_label:
						filtered_correctly = filtered_correctly and filtered.get(other_label, 0) == counts[other_label]
			check(filtered_correctly and _label_counts(pool) == counts, "Entered-room exclusion removes every previous weighted copy and preserves other weights and RNG: %s/Bearing%d" % [biome_id, tier])
		builder.free()

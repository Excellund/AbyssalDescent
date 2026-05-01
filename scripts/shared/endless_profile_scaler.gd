extends RefCounted

const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")

static func apply_scaling(profile: Dictionary, is_endless_mode: bool, endless_boss_defeated: bool, room_depth: int, encounter_count: int, room_base_size: Vector2, static_camera_room_threshold: float) -> Dictionary:
	if profile.is_empty():
		return profile
	if not is_endless_mode or not endless_boss_defeated:
		return profile

	var endless_depth := maxi(0, room_depth - encounter_count)
	if endless_depth <= 0:
		return profile

	# Aggressive endless scaling: tier rises every depth after first boss clear.
	var tier := endless_depth
	var scaled := ENCOUNTER_CONTRACTS.normalize_profile(profile.duplicate(true))
	var scaled_chasers := ENCOUNTER_CONTRACTS.profile_chaser_count(scaled) + tier
	var scaled_chargers := ENCOUNTER_CONTRACTS.profile_charger_count(scaled) + int(floor(float(tier) * 0.75))
	var scaled_archers := ENCOUNTER_CONTRACTS.profile_archer_count(scaled) + int(floor(float(tier) * 0.65))
	var scaled_shielders := ENCOUNTER_CONTRACTS.profile_shielder_count(scaled) + int(floor(float(tier) * 0.5))
	ENCOUNTER_CONTRACTS.profile_set_counts(scaled, scaled_chasers, scaled_chargers, scaled_archers, scaled_shielders)

	var base_room_size := ENCOUNTER_CONTRACTS.profile_room_size(scaled)
	if base_room_size == Vector2.ZERO:
		base_room_size = room_base_size
	var room_growth := Vector2(34.0, 22.0) * float(mini(tier, 12))
	var scaled_room_size := Vector2(
		clampf(base_room_size.x + room_growth.x, room_base_size.x, 1800.0),
		clampf(base_room_size.y + room_growth.y, room_base_size.y, 1300.0)
	)
	ENCOUNTER_CONTRACTS.profile_set_room_size(scaled, scaled_room_size)
	ENCOUNTER_CONTRACTS.profile_set_static_camera(scaled, scaled_room_size.x <= static_camera_room_threshold)

	# Merge endless stat pressure into the existing mutator channel.
	var endless_health_mult := clampf(1.0 + float(tier) * 0.28, 1.0, 4.2)
	var endless_damage_mult := clampf(1.0 + float(tier) * 0.14, 1.0, 2.8)
	var endless_speed_mult := clampf(1.0 + float(tier) * 0.07, 1.0, 2.0)
	var endless_windup_mult := clampf(1.0 - float(tier) * 0.03, 0.55, 1.0)
	var merged_mutator := ENCOUNTER_CONTRACTS.profile_enemy_mutator(scaled).duplicate(true)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_ENEMY_HEALTH_MULT, endless_health_mult, 1.0)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_DAMAGE_MULT, endless_damage_mult, 1.0)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_DAMAGE_MULT, endless_damage_mult, 1.0)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_PROJECTILE_DAMAGE_MULT, endless_damage_mult, 1.0)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_SHIELDER_SLAM_DAMAGE_MULT, endless_damage_mult, 1.0)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHASER_SPEED_MULT, endless_speed_mult, 1.0)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_SPEED_MULT, endless_speed_mult, 1.0)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_SHIELDER_SPEED_MULT, endless_speed_mult, 1.0)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_CHARGER_WINDUP_MULT, endless_windup_mult, 1.0)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_ARCHER_WINDUP_MULT, endless_windup_mult, 1.0)
	ENCOUNTER_CONTRACTS.mutator_multiply_stat(merged_mutator, ENCOUNTER_CONTRACTS.MUTATOR_STAT_SHIELDER_SLAM_WINDUP_MULT, endless_windup_mult, 1.0)
	ENCOUNTER_CONTRACTS.profile_set_enemy_mutator(scaled, merged_mutator)

	var base_label := ENCOUNTER_CONTRACTS.profile_label(scaled)
	if base_label.find("Tier ") == -1:
		scaled[ENCOUNTER_CONTRACTS.PROFILE_KEY_LABEL] = "%s  Tier %d" % [base_label, tier]

	return scaled

extends Node
## Multiplayer-specific difficulty tier configurations.
## Mirrors difficulty_config.gd but tuned for 2+ player co-op with quality-over-quantity enemy spawning.
##
## ARCHITECTURE:
## - Base fields (encounter_count_before_boss, difficulty_rank) are inherited from singleplayer config
##   via difficulty_config.gd and embedded below for clarity.
## - Multiplayer-SPECIFIC OVERRIDES are explicitly defined:
##   * base_enemy_pressure_mult: tuned higher for 2-player scaling
##   * depth_pressure_divisor: matches singleplayer semantics (lower = faster depth ramp)
##   * specialist enemy offsets: per-type instead of single offset
##   * player multipliers: specialized for co-op player health/damage dynamics
## - A sync validator runs at editor/build time to catch drifts.

const DIFFICULTY_CONFIG := preload("res://scripts/difficulty_config.gd")
const BEARING_ENUMS := preload("res://scripts/shared/bearing_enums.gd")

## ===== MULTIPLAYER TIER DEFINITIONS (CO-OP BALANCED) =====
## Each tier inherits base structure from singleplayer config and applies multiplayer-specific overrides
## Uses static (not const) because BEARING_DEFINITIONS contains function calls to DIFFICULTY_CONFIG
static var BEARING_DEFINITIONS := {
	BEARING_ENUMS.BearingTier.PILGRIM: {
		# === BASE (from singleplayer) ===
		"name": DIFFICULTY_CONFIG.get_tier_config(BEARING_ENUMS.BearingTier.PILGRIM).get("name", "Pilgrim"),
		"description": DIFFICULTY_CONFIG.get_tier_config(BEARING_ENUMS.BearingTier.PILGRIM).get("description", ""),
		"bearing_key": "Pilgrim",
		"encounter_count_before_boss": DIFFICULTY_CONFIG.get_base_encounter_count_before_boss(),
		"difficulty_rank": 0,
		
		# === MULTIPLAYER OVERRIDES ===
		"base_enemy_pressure_mult": 0.6,  ## Match singleplayer; party-size mult adds the co-op count bump
		"depth_pressure_divisor": 1.5,  ## Match singleplayer ramp; lower = faster depth ramp
		"specialist_enemy_lurker_offset": 5,
		"specialist_enemy_ram_offset": 6,
		"specialist_enemy_lancer_offset": 7,
		"specialist_enemy_spectre_offset": 8,
		"specialist_enemy_pyre_offset": 9,
		"specialist_enemy_tether_offset": 10,
		"mutator_frequency_mult": 0.4,  ## Fewer mutators
		"trial_encounter_frequency_mult": 0.5,  ## Fewer trials
		"mutator_damage_mult": 0.8,
		"boss_difficulty_mult": 0.75,
		"player_health_mult": 1.0,
		"player_starting_health_bonus": 35.0,
		"player_damage_taken_mult": 0.78,  ## Co-op player damage reduction
		"enemy_contact_damage_mult": 1.0,
		"player_damage_dealt_mult": 1.0,
		"player_heal_mult": 1.0,
		"rest_heal_ratio_mult": 1.25,
		"coop_enemy_count_per_extra_player": 0.22,
		"coop_enemy_count_curve_power": 0.85,
		"coop_enemy_count_max_mult": 1.55,
		"coop_enemy_health_per_extra_player": 0.56,
		"coop_enemy_health_curve_power": 0.9,
		"coop_enemy_health_max_mult": 2.5,
		"coop_boss_health_per_extra_player": 1.0,
		"coop_boss_health_curve_power": 0.92,
		"coop_boss_health_max_mult": 3.4
	},
	BEARING_ENUMS.BearingTier.DELVER: {
		# === BASE (from singleplayer) ===
		"name": DIFFICULTY_CONFIG.get_tier_config(BEARING_ENUMS.BearingTier.DELVER).get("name", "Delver"),
		"description": DIFFICULTY_CONFIG.get_tier_config(BEARING_ENUMS.BearingTier.DELVER).get("description", ""),
		"bearing_key": "Delver",
		"encounter_count_before_boss": DIFFICULTY_CONFIG.get_base_encounter_count_before_boss(),
		"difficulty_rank": 1,
		
		# === MULTIPLAYER OVERRIDES ===
		"base_enemy_pressure_mult": 1.0,  ## Match singleplayer; party-size mult adds the co-op count bump
		"depth_pressure_divisor": 1.0,  ## Match singleplayer ramp; lower = faster depth ramp
		"specialist_enemy_lurker_offset": 4,
		"specialist_enemy_ram_offset": 5,
		"specialist_enemy_lancer_offset": 6,
		"specialist_enemy_spectre_offset": 7,
		"specialist_enemy_pyre_offset": 8,
		"specialist_enemy_tether_offset": 9,
		"mutator_frequency_mult": 0.7,
		"trial_encounter_frequency_mult": 0.7,
		"mutator_damage_mult": 1.0,
		"boss_difficulty_mult": 1.0,
		"player_health_mult": 1.0,
		"player_starting_health_bonus": 0.0,
		"player_damage_taken_mult": 1.0,
		"enemy_contact_damage_mult": 0.94,
		"player_damage_dealt_mult": 1.0,
		"player_heal_mult": 1.0,
		"rest_heal_ratio_mult": 1.0,
		"coop_enemy_count_per_extra_player": 0.25,
		"coop_enemy_count_curve_power": 0.85,
		"coop_enemy_count_max_mult": 1.6,
		"coop_enemy_health_per_extra_player": 0.62,
		"coop_enemy_health_curve_power": 0.92,
		"coop_enemy_health_max_mult": 2.7,
		"coop_boss_health_per_extra_player": 1.08,
		"coop_boss_health_curve_power": 0.95,
		"coop_boss_health_max_mult": 3.7
	},
	BEARING_ENUMS.BearingTier.HARBINGER: {
		# === BASE (from singleplayer) ===
		"name": DIFFICULTY_CONFIG.get_tier_config(BEARING_ENUMS.BearingTier.HARBINGER).get("name", "Harbinger"),
		"description": DIFFICULTY_CONFIG.get_tier_config(BEARING_ENUMS.BearingTier.HARBINGER).get("description", ""),
		"bearing_key": "Harbinger",
		"encounter_count_before_boss": DIFFICULTY_CONFIG.get_base_encounter_count_before_boss(),
		"difficulty_rank": 2,
		
		# === MULTIPLAYER OVERRIDES ===
		"base_enemy_pressure_mult": 1.25,  ## Match singleplayer; party-size mult adds the co-op count bump
		"depth_pressure_divisor": 0.8,  ## Match singleplayer ramp; lower = faster depth ramp
		"specialist_enemy_lurker_offset": 3,
		"specialist_enemy_ram_offset": 4,
		"specialist_enemy_lancer_offset": 5,
		"specialist_enemy_spectre_offset": 6,
		"specialist_enemy_pyre_offset": 7,
		"specialist_enemy_tether_offset": 8,
		"mutator_frequency_mult": 1.0,
		"trial_encounter_frequency_mult": 1.0,
		"mutator_damage_mult": 1.1,
		"boss_difficulty_mult": 1.15,
		"player_health_mult": 1.0,
		"player_starting_health_bonus": 0.0,
		"player_damage_taken_mult": 1.15,
		"enemy_contact_damage_mult": 0.94,
		"player_damage_dealt_mult": 1.0,
		"player_heal_mult": 1.0,
		"rest_heal_ratio_mult": 1.0,
		"coop_enemy_count_per_extra_player": 0.28,
		"coop_enemy_count_curve_power": 0.85,
		"coop_enemy_count_max_mult": 1.65,
		"coop_enemy_health_per_extra_player": 0.68,
		"coop_enemy_health_curve_power": 0.95,
		"coop_enemy_health_max_mult": 2.9,
		"coop_boss_health_per_extra_player": 1.18,
		"coop_boss_health_curve_power": 0.98,
		"coop_boss_health_max_mult": 4.0
	},
	BEARING_ENUMS.BearingTier.FORSWORN: {
		# === BASE (from singleplayer) ===
		"name": DIFFICULTY_CONFIG.get_tier_config(BEARING_ENUMS.BearingTier.FORSWORN).get("name", "Forsworn"),
		"description": DIFFICULTY_CONFIG.get_tier_config(BEARING_ENUMS.BearingTier.FORSWORN).get("description", ""),
		"bearing_key": "Forsworn",
		"encounter_count_before_boss": DIFFICULTY_CONFIG.get_base_encounter_count_before_boss(),
		"difficulty_rank": 3,
		
		# === MULTIPLAYER OVERRIDES ===
		"base_enemy_pressure_mult": 1.5,  ## Match singleplayer; party-size mult adds the co-op count bump
		"depth_pressure_divisor": 0.6,  ## Match singleplayer ramp; lower = faster depth ramp
		"specialist_enemy_lurker_offset": 2,
		"specialist_enemy_ram_offset": 3,
		"specialist_enemy_lancer_offset": 4,
		"specialist_enemy_spectre_offset": 5,
		"specialist_enemy_pyre_offset": 6,
		"specialist_enemy_tether_offset": 7,
		"mutator_frequency_mult": 1.35,
		"trial_encounter_frequency_mult": 1.35,
		"mutator_damage_mult": 1.25,
		"boss_difficulty_mult": 1.3,
		"player_health_mult": 1.0,
		"player_starting_health_bonus": 0.0,
		"player_damage_taken_mult": 1.35,
		"enemy_contact_damage_mult": 0.94,
		"player_damage_dealt_mult": 1.0,
		"player_heal_mult": 1.0,
		"rest_heal_ratio_mult": 1.0,
		"coop_enemy_count_per_extra_player": 0.30,
		"coop_enemy_count_curve_power": 0.85,
		"coop_enemy_count_max_mult": 1.7,
		"coop_enemy_health_per_extra_player": 0.74,
		"coop_enemy_health_curve_power": 0.98,
		"coop_enemy_health_max_mult": 3.1,
		"coop_boss_health_per_extra_player": 1.28,
		"coop_boss_health_curve_power": 1.0,
		"coop_boss_health_max_mult": 4.3
	}
}


func get_tier_config(tier: int) -> Dictionary:
	"""Get the multiplayer config for a given difficulty tier."""
	var config: Dictionary = BEARING_DEFINITIONS.get(tier, {})
	if config.is_empty():
		push_error("Invalid tier %d for multiplayer config" % tier)
		return BEARING_DEFINITIONS[BEARING_ENUMS.BearingTier.DELVER]
	return config.duplicate()


func get_all_tiers() -> Array:
	"""Get all available tier indices."""
	return BEARING_DEFINITIONS.keys()


## ===== MULTIPLAYER SYNC VALIDATION =====
## Ensure multiplayer config base definitions match singleplayer

func validate_config_sync() -> Dictionary:
	"""
	Validate that base fields in multiplayer config are synced with singleplayer.
	Returns { "valid": bool, "errors": [str], "warnings": [str] }
	"""
	var result := {"valid": true, "errors": [], "warnings": []}
	
	# Check base encounter count
	var expected_encounter_count := DIFFICULTY_CONFIG.get_base_encounter_count_before_boss()
	var expected_ranks := DIFFICULTY_CONFIG.get_base_progression_ranks()
	
	for tier in get_all_tiers():
		var config = get_tier_config(tier)
		
		# Verify encounter count
		if config.get("encounter_count_before_boss", -1) != expected_encounter_count:
			result["errors"].append("Tier %d: encounter_count_before_boss not synced with singleplayer" % tier)
			result["valid"] = false
		
		# Verify difficulty rank
		if config.get("difficulty_rank", -1) != expected_ranks.get(tier, -1):
			result["errors"].append("Tier %d: difficulty_rank not synced with singleplayer" % tier)
			result["valid"] = false
	
	return result


func _notification(what: int) -> void:
	# Optionally validate at editor time on load
	if what == NOTIFICATION_PREDELETE:
		if Engine.is_editor_hint():
			var sync_result := validate_config_sync()
			if not sync_result.valid:
				for error in sync_result.errors:
					push_error("Multiplayer config sync error: %s" % error)


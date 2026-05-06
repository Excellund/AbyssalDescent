extends Node
## Multiplayer-specific difficulty tier configurations.
## Mirrors difficulty_config.gd but tuned for 2+ player co-op with quality-over-quantity enemy spawning.
##
## ARCHITECTURE:
## - Base fields (encounter_count_before_boss, difficulty_rank) are inherited from singleplayer config
##   via difficulty_config.gd and embedded below for clarity.
## - Multiplayer-SPECIFIC OVERRIDES are explicitly defined:
##   * base_enemy_pressure_mult: tuned higher for 2-player scaling
##   * depth_pressure_divisor: new field for depth scaling (not in singleplayer)
##   * specialist enemy offsets: per-type instead of single offset
##   * player multipliers: specialized for co-op player health/damage dynamics
## - A sync validator runs at editor/build time to catch drifts.

const DIFFICULTY_CONFIG := preload("res://scripts/difficulty_config.gd")
const BEARING_ENUMS := preload("res://scripts/shared/bearing_enums.gd")

## ===== MULTIPLAYER TIER DEFINITIONS (CO-OP BALANCED) =====
## Each tier inherits base structure from singleplayer config and applies multiplayer-specific overrides
const BEARING_DEFINITIONS := {
	BEARING_ENUMS.BearingTier.PILGRIM: {
		# === BASE (from singleplayer) ===
		"bearing_key": "Pilgrim",
		"encounter_count_before_boss": DIFFICULTY_CONFIG.get_base_encounter_count_before_boss(),
		"difficulty_rank": 0,
		
		# === MULTIPLAYER OVERRIDES ===
		"base_enemy_pressure_mult": 1.2,  ## Moderate increase for 2 players (vs 0.6 singleplayer)
		"depth_pressure_divisor": 18,  ## Deeper scaling than singleplayer
		"specialist_enemy_lurker_offset": 5,
		"specialist_enemy_ram_offset": 6,
		"specialist_enemy_lancer_offset": 7,
		"specialist_enemy_spectre_offset": 8,
		"specialist_enemy_pyre_offset": 9,
		"specialist_enemy_tether_offset": 10,
		"mutator_frequency_mult": 0.4,  ## Fewer mutators
		"trial_encounter_frequency_mult": 0.5,  ## Fewer trials
		"player_health_mult": 1.0,
		"player_damage_taken_mult": 0.78,  ## Co-op player damage reduction
		"player_damage_dealt_mult": 1.0,
		"player_heal_mult": 1.0
	},
	BEARING_ENUMS.BearingTier.DELVER: {
		# === BASE (from singleplayer) ===
		"bearing_key": "Delver",
		"encounter_count_before_boss": DIFFICULTY_CONFIG.get_base_encounter_count_before_boss(),
		"difficulty_rank": 1,
		
		# === MULTIPLAYER OVERRIDES ===
		"base_enemy_pressure_mult": 1.35,  ## Moderate-high for co-op (vs 1.0 singleplayer)
		"depth_pressure_divisor": 14,
		"specialist_enemy_lurker_offset": 4,
		"specialist_enemy_ram_offset": 5,
		"specialist_enemy_lancer_offset": 6,
		"specialist_enemy_spectre_offset": 7,
		"specialist_enemy_pyre_offset": 8,
		"specialist_enemy_tether_offset": 9,
		"mutator_frequency_mult": 0.7,
		"trial_encounter_frequency_mult": 0.7,
		"player_health_mult": 1.0,
		"player_damage_taken_mult": 1.0,
		"player_damage_dealt_mult": 1.0,
		"player_heal_mult": 1.0
	},
	BEARING_ENUMS.BearingTier.HARBINGER: {
		# === BASE (from singleplayer) ===
		"bearing_key": "Harbinger",
		"encounter_count_before_boss": DIFFICULTY_CONFIG.get_base_encounter_count_before_boss(),
		"difficulty_rank": 2,
		
		# === MULTIPLAYER OVERRIDES ===
		"base_enemy_pressure_mult": 1.5,  ## Higher for harder difficulty (vs 1.25 singleplayer)
		"depth_pressure_divisor": 12,
		"specialist_enemy_lurker_offset": 3,
		"specialist_enemy_ram_offset": 4,
		"specialist_enemy_lancer_offset": 5,
		"specialist_enemy_spectre_offset": 6,
		"specialist_enemy_pyre_offset": 7,
		"specialist_enemy_tether_offset": 8,
		"mutator_frequency_mult": 1.0,
		"trial_encounter_frequency_mult": 1.0,
		"player_health_mult": 1.0,
		"player_damage_taken_mult": 1.15,
		"player_damage_dealt_mult": 1.0,
		"player_heal_mult": 1.0
	},
	BEARING_ENUMS.BearingTier.FORSWORN: {
		# === BASE (from singleplayer) ===
		"bearing_key": "Forsworn",
		"encounter_count_before_boss": DIFFICULTY_CONFIG.get_base_encounter_count_before_boss(),
		"difficulty_rank": 3,
		
		# === MULTIPLAYER OVERRIDES ===
		"base_enemy_pressure_mult": 1.7,  ## Very high for extreme difficulty (vs 1.5 singleplayer)
		"depth_pressure_divisor": 10,
		"specialist_enemy_lurker_offset": 2,
		"specialist_enemy_ram_offset": 3,
		"specialist_enemy_lancer_offset": 4,
		"specialist_enemy_spectre_offset": 5,
		"specialist_enemy_pyre_offset": 6,
		"specialist_enemy_tether_offset": 7,
		"mutator_frequency_mult": 1.35,
		"trial_encounter_frequency_mult": 1.35,
		"player_health_mult": 1.0,
		"player_damage_taken_mult": 1.35,
		"player_damage_dealt_mult": 1.0,
		"player_heal_mult": 1.0
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


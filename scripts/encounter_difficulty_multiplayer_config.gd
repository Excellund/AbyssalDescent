extends Node
## Multiplayer-specific difficulty tier configurations.
## Mirrors difficulty_config.gd but tuned for 2+ player co-op with quality-over-quantity enemy spawning.

const BEARING_ENUMS := preload("res://scripts/shared/bearing_enums.gd")

## Multiplayer tier definitions (co-op balanced)
const BEARING_DEFINITIONS := {
	BEARING_ENUMS.BearingTier.PILGRIM: {
		"bearing_key": "Pilgrim",
		"encounter_count_before_boss": 8,
		"base_enemy_pressure_mult": 1.2,  ## Moderate increase for 2 players
		"depth_pressure_divisor": 18,
		"specialist_enemy_lurker_offset": 5,
		"specialist_enemy_ram_offset": 6,
		"specialist_enemy_lancer_offset": 7,
		"specialist_enemy_spectre_offset": 8,
		"specialist_enemy_pyre_offset": 9,
		"specialist_enemy_tether_offset": 10,
		"mutator_frequency_mult": 0.4,
		"trial_encounter_frequency_mult": 0.5,
		"player_health_mult": 1.0,
		"player_damage_taken_mult": 0.78,
		"player_damage_dealt_mult": 1.0,
		"player_heal_mult": 1.0
	},
	BEARING_ENUMS.BearingTier.DELVER: {
		"bearing_key": "Delver",
		"encounter_count_before_boss": 8,
		"base_enemy_pressure_mult": 1.35,  ## Moderate-high for co-op
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
		"bearing_key": "Harbinger",
		"encounter_count_before_boss": 8,
		"base_enemy_pressure_mult": 1.5,  ## Higher for harder difficulty
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
		"bearing_key": "Forsworn",
		"encounter_count_before_boss": 8,
		"base_enemy_pressure_mult": 1.7,  ## Very high for extreme difficulty
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

extends Node
## Multiplayer-specific difficulty tier configurations.
## Unified bearing definitions are now stored in difficulty_config.gd (BEARING_DEFINITIONS)
## to eliminate duplication between singleplayer and multiplayer tiers.
##
## ARCHITECTURE:
## - All bearing definitions (base + multiplayer-specific fields) are centralized in 
##   DIFFICULTY_CONFIG.BEARING_DEFINITIONS for single source of truth.
## - Multiplayer-specific fields (coop_enemy_count_per_extra_player, specialist type offsets, etc.)
##   are embedded in the unified definitions.
## - This script provides multiplayer-facing accessors for consistency.
## - A sync validator runs at editor/build time to catch drifts.

const DIFFICULTY_CONFIG := preload("res://scripts/difficulty_config.gd")
const BEARING_ENUMS := preload("res://scripts/shared/bearing_enums.gd")


func get_tier_config(tier: int) -> Dictionary:
	"""Get the tier configuration (uses unified definitions from difficulty_config)."""
	return DIFFICULTY_CONFIG.get_tier_config(tier)


func get_all_tiers() -> Array:
	"""Get all available tier indices."""
	return DIFFICULTY_CONFIG.BEARING_DEFINITIONS.keys()


## ===== VALIDATION =====
## Unified bearing definitions are validated in difficulty_config.gd at startup.
## This script just provides multiplayer-facing accessors for the unified definitions.

func validate_config_sync() -> Dictionary:
	"""
	Validate that unified config is properly initialized.
	Returns { "valid": bool, "errors": [str], "warnings": [str] }
	"""
	var result := {"valid": true, "errors": [], "warnings": []}
	
	# Check that we can access all tiers
	for tier in DIFFICULTY_CONFIG.get_base_progression_ranks().keys():
		var config = get_tier_config(tier)
		if config.is_empty():
			result["errors"].append("Tier %d returned empty config" % tier)
			result["valid"] = false
	
	return result



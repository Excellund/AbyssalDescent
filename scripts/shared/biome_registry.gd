extends RefCounted

# Biome definitions — one active biome per act shapes encounter frequency
# and enemy spawn weights. Rolled once at run start, persists for the act.
#
# enemy_weight_overrides: multipliers applied to per-type counts in the profile
#   (e.g. 1.4 means 40% more of that enemy type; capped at 1 minimum)
# preferred_encounter_labels: these encounter labels get doubled in the pool
#   selection pass, increasing their selection probability.
# color_theme: tints applied to world_renderer (glow, grid, backdrop, accent)

const BIOME_DEFINITIONS: Dictionary = {
	# --- ACT 1 ---
	"crumble": {
		"id": "crumble",
		"name": "The Crumble",
		"act": 1,
		"enemy_weight_overrides": {
			"chaser": 1.4,
			"charger": 1.4,
			"shielder": 1.4
		},
		"preferred_encounter_labels": ["Onslaught", "Fortress", "Vanguard"],
		"color_theme": {
			"glow_tint": Color(0.90, 0.55, 0.12, 1.0),
			"grid_tint": Color(0.45, 0.18, 0.06, 0.6),
			"backdrop_tint": Color(0.22, 0.08, 0.04, 1.0),
			"accent": Color(1.0, 0.68, 0.22, 1.0)
		}
	},
	"haunt": {
		"id": "haunt",
		"name": "The Haunt",
		"act": 1,
		"enemy_weight_overrides": {
			"lurker": 1.6,
			"spectre": 1.6,
			"seamlock": 1.6
		},
		"preferred_encounter_labels": ["Ambush", "Blitz", "Gauntlet"],
		"color_theme": {
			"glow_tint": Color(0.48, 0.14, 0.72, 1.0),
			"grid_tint": Color(0.22, 0.06, 0.36, 0.6),
			"backdrop_tint": Color(0.10, 0.04, 0.18, 1.0),
			"accent": Color(0.78, 0.44, 1.0, 1.0)
		}
	},
	"shatterfield": {
		"id": "shatterfield",
		"name": "The Shatterfield",
		"act": 1,
		"enemy_weight_overrides": {
			"archer": 1.5,
			"lancer": 1.5,
			"tether": 1.5
		},
		"preferred_encounter_labels": ["Crossfire", "Suppression", "Convergence"],
		"color_theme": {
			"glow_tint": Color(0.18, 0.76, 0.98, 1.0),
			"grid_tint": Color(0.06, 0.30, 0.48, 0.6),
			"backdrop_tint": Color(0.04, 0.10, 0.22, 1.0),
			"accent": Color(0.44, 0.92, 1.0, 1.0)
		}
	},

	# --- ACT 2 ---
	"grinding_vault": {
		"id": "grinding_vault",
		"name": "The Grinding Vault",
		"act": 2,
		"enemy_weight_overrides": {
			"mirrorline": 1.5,
			"shielder": 1.4,
			"sentinel": 1.6
		},
		"preferred_encounter_labels": ["Fortress", "Suppression", "Vanguard"],
		"color_theme": {
			"glow_tint": Color(0.72, 0.66, 0.28, 1.0),
			"grid_tint": Color(0.32, 0.28, 0.08, 0.6),
			"backdrop_tint": Color(0.14, 0.12, 0.04, 1.0),
			"accent": Color(0.96, 0.88, 0.42, 1.0)
		}
	},
	"storm_reach": {
		"id": "storm_reach",
		"name": "The Storm Reach",
		"act": 2,
		"enemy_weight_overrides": {
			"pyre": 1.6,
			"tether": 1.5,
			"archer": 1.4,
			"drifter": 1.5
		},
		"preferred_encounter_labels": ["Crossfire", "Blitz", "Onslaught"],
		"color_theme": {
			"glow_tint": Color(0.98, 0.44, 0.08, 1.0),
			"grid_tint": Color(0.46, 0.14, 0.02, 0.6),
			"backdrop_tint": Color(0.18, 0.06, 0.02, 1.0),
			"accent": Color(1.0, 0.66, 0.24, 1.0)
		}
	},
	"hollow": {
		"id": "hollow",
		"name": "The Hollow",
		"act": 2,
		"enemy_weight_overrides": {
			"seamlock": 1.6,
			"mirrorline": 1.4,
			"lurker": 1.5,
			"weaver": 1.6
		},
		"preferred_encounter_labels": ["Ambush", "Convergence", "Gauntlet"],
		"color_theme": {
			"glow_tint": Color(0.14, 0.62, 0.58, 1.0),
			"grid_tint": Color(0.04, 0.24, 0.22, 0.6),
			"backdrop_tint": Color(0.04, 0.12, 0.12, 1.0),
			"accent": Color(0.32, 0.86, 0.82, 1.0)
		}
	},

	# --- ACT 3 ---
	"void_breach": {
		"id": "void_breach",
		"name": "The Void Breach",
		"act": 3,
		"enemy_weight_overrides": {
			"spectre": 1.8,
			"pyre": 1.7,
			"drifter": 1.5
		},
		"preferred_encounter_labels": ["Blitz", "Convergence", "Gauntlet"],
		"color_theme": {
			"glow_tint": Color(0.82, 0.08, 0.14, 1.0),
			"grid_tint": Color(0.38, 0.02, 0.06, 0.6),
			"backdrop_tint": Color(0.12, 0.02, 0.04, 1.0),
			"accent": Color(0.96, 0.24, 0.32, 1.0)
		}
	},
	"the_maelstrom": {
		"id": "the_maelstrom",
		"name": "The Maelstrom",
		"act": 3,
		"enemy_weight_overrides": {
			"chaser": 1.4,
			"charger": 1.4,
			"archer": 1.4,
			"lurker": 1.4,
			"seamlock": 1.4,
			"pyre": 1.4,
			"spectre": 1.4,
			"drifter": 1.4,
			"weaver": 1.4,
			"sentinel": 1.4
		},
		"preferred_encounter_labels": ["Gauntlet", "Onslaught", "Suppression"],
		"color_theme": {
			"glow_tint": Color(0.84, 0.72, 0.18, 1.0),
			"grid_tint": Color(0.18, 0.14, 0.02, 0.7),
			"backdrop_tint": Color(0.06, 0.05, 0.02, 1.0),
			"accent": Color(1.0, 0.92, 0.38, 1.0)
		}
	},
	"convergence_end": {
		"id": "convergence_end",
		"name": "The Convergence",
		"act": 3,
		"enemy_weight_overrides": {
			"tether": 1.6,
			"seamlock": 1.5,
			"lancer": 1.5,
			"sentinel": 1.6
		},
		"preferred_encounter_labels": ["Convergence", "Suppression", "Fortress"],
		"color_theme": {
			"glow_tint": Color(0.82, 0.92, 1.0, 1.0),
			"grid_tint": Color(0.24, 0.38, 0.52, 0.6),
			"backdrop_tint": Color(0.08, 0.12, 0.18, 1.0),
			"accent": Color(0.88, 0.96, 1.0, 1.0)
		}
	}
}


static func get_act_biomes(act: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for biome_variant in BIOME_DEFINITIONS.values():
		var biome := biome_variant as Dictionary
		if int(biome.get("act", 0)) == act:
			result.append(biome)
	return result


static func roll_biome_for_act(act: int, rng: RandomNumberGenerator) -> String:
	var biomes := get_act_biomes(act)
	if biomes.is_empty():
		return ""
	return String(biomes[rng.randi() % biomes.size()].get("id", ""))


static func get_biome(biome_id: String) -> Dictionary:
	return BIOME_DEFINITIONS.get(biome_id, {}) as Dictionary


static func generate_impact_text(biome: Dictionary) -> String:
	var sections: Array[String] = []

	var encounter_labels := biome.get("preferred_encounter_labels", []) as Array
	if not encounter_labels.is_empty():
		var names: Array[String] = []
		for label in encounter_labels:
			names.append(String(label))
		sections.append("ENCOUNTER STYLE\n" + _join_mid_dot(names))

	var weight_overrides := biome.get("enemy_weight_overrides", {}) as Dictionary
	if not weight_overrides.is_empty():
		var pairs: Array = []
		for key in weight_overrides:
			pairs.append([float(weight_overrides[key]), String(key)])
		pairs.sort_custom(func(a: Array, b: Array) -> bool:
			if not is_equal_approx(float(a[0]), float(b[0])):
				return float(a[0]) > float(b[0])
			return String(a[1]) < String(b[1])
		)
		var top: Array[String] = []
		for i in range(mini(3, pairs.size())):
			top.append(_enemy_display_name(String(pairs[i][1])))
		sections.append("COMMON THREATS\n" + _join_mid_dot(top))

	return "\n".join(sections)


static func _enemy_display_name(key: String) -> String:
	var names := {
		"chaser": "Chasers",
		"charger": "Chargers",
		"archer": "Archers",
		"lurker": "Lurkers",
		"spectre": "Spectres",
		"seamlock": "Seamlocks",
		"mirrorline": "Mirror Lines",
		"tether": "Tethers",
		"pyre": "Pyres",
		"drifter": "Drifters",
		"weaver": "Weavers",
		"sentinel": "Sentinels",
		"shielder": "Shielders",
		"ram": "Rams",
		"lancer": "Lancers",
	}
	return String(names.get(key, key.capitalize() + "s"))


static func _join_mid_dot(items: Array) -> String:
	var strs: Array[String] = []
	for item in items:
		strs.append(String(item))
	return "  ·  ".join(strs)

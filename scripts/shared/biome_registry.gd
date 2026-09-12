extends RefCounted

# Biome definitions — one active biome per act shapes encounter frequency
# and enemy spawn weights. Rolled once at run start, persists for the act.
#
# enemy_weight_overrides: multipliers applied to per-type counts in the profile
#   (e.g. 1.4 means 40% more of that enemy type; capped at 1 minimum)
# preferred_encounter_labels: these encounter labels get tripled in the pool
#   selection pass, increasing their selection probability.
# color_theme: tints applied to world_renderer (glow, grid, backdrop, accent)

const PREFERRED_ENCOUNTER_WEIGHT := 3

# Ordinary rooms carry these resolved terrain templates in their existing profile.
# Missions, Trials, Apex rooms, bosses, Breach and Undertow retain authored arenas.
const COMBAT_IDENTITIES: Dictionary = {
	"crumble": {
		"templates": ["rubble_gates", "rubble_gates_mirrored"],
		"terrain": "Falling rubble",
		"rule": "Marked rockfalls strike around the boulder gates, hurting you and foes.",
		"tactic": "Lure pursuers into a marked fall, then leave before the rocks land.",
		"entry_hint": "DANGER: Rockfalls hurt you and foes. Lure them in, then leave the circle."
	},
	"haunt": {
		"templates": ["side_cover", "side_cover_mirrored"],
		"terrain": "Clinging shadows",
		"rule": "Shadow patches near side cover {kw:slow} you and foes inside them.",
		"tactic": "Draw pursuers through the shadows; cross open ground to keep your speed.",
		"entry_hint": "DANGER: Shadows Slow you and foes. Lead pursuers through them."
	},
	"shatterfield": {
		"templates": ["offset_firing_lanes", "offset_firing_lanes_mirrored"],
		"terrain": "Breakable cover",
		"rule": "Three {kw:attack|Attacks} break each cracked inner column, releasing a {kw:burst} that hurts foes only. Outer cover stays intact.",
		"tactic": "Lure foes near cracked cover before breaking it. Keep cover to stop arrows; beams and floor hazards pass through.",
		"entry_hint": "HELP: Breaking cracked pillars bursts nearby foes. Three Attacks; safe for you."
	},
	"grinding_vault": {
		"templates": ["broken_ring", "broken_ring_inverted"],
		"terrain": "Crushing rings",
		"rule": "Crushers alternate between inner and outer floor rings, hurting you and foes.",
		"tactic": "Cross the marked boundary before impact; leave slow or shielded foes behind.",
		"entry_hint": "DANGER: Crushers hurt you and foes. Cross out of the marked ring."
	},
	"storm_reach": {
		"templates": ["storm_shelters", "storm_shelters_mirrored"],
		"terrain": "Baitable lightning",
		"rule": "Lightning marks a player's position, then strikes that fixed spot, hurting you and foes.",
		"tactic": "Place the warning under a crowd, then leave it. The warning stops following you.",
		"entry_hint": "DANGER: Lightning hurts you and foes. Leave its fixed warning circle."
	},
	"hollow": {
		"templates": ["hollow_spine", "hollow_spine_mirrored"],
		"terrain": "Alternating lanes",
		"rule": "Floor eruptions alternate across the divided lanes, hurting you and foes.",
		"tactic": "Use the gaps to change lanes; draw foes into the next marked eruption.",
		"entry_hint": "DANGER: Eruptions hurt you and foes. Switch lanes through the gaps."
	},
	"void_breach": {
		"templates": ["none"],
		"terrain": "Broken void bands",
		"rule": "Void bands step across the arena, hurting you and foes. Each band leaves an open gap.",
		"tactic": "Route through the gap or clear the band before impact. Foes caught in it take damage too.",
		"entry_hint": "DANGER: Void bands hurt you and foes. Use the gap in the marked band."
	},
	"the_maelstrom": {
		"templates": ["maelstrom_orbit", "maelstrom_orbit_mirrored"],
		"terrain": "Turning storm",
		"rule": "A dangerous sector steps around the central pocket, hurting you and foes at impact.",
		"tactic": "Move around the pocket ahead of the next marked sector; leave pursuers in its path.",
		"entry_hint": "DANGER: Storm sectors hurt you and foes. Leave the marked wedge."
	},
	"convergence_end": {
		"templates": ["convergence_gates", "convergence_gates_diagonal"],
		"terrain": "Pulsing gates",
		"rule": "Opposite pairs of gates alternate damaging pulses that can strike you and foes.",
		"tactic": "Choose an unmarked gate and draw enemies through the pair about to pulse.",
		"entry_hint": "DANGER: Gate pulses hurt you and foes. Use the unmarked pair."
	}
}

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
			"spectre": 1.6
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
			"shielder": 1.4,
			"sentinel": 1.6
		},
		"preferred_encounter_labels": ["Fortress", "Suppression", "Vanguard", "Breach"],
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
		"preferred_encounter_labels": ["Crossfire", "Blitz", "Onslaught", "Undertow"],
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
		"preferred_encounter_labels": ["Blitz", "Convergence", "Gauntlet", "Undertow"],
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
			"lancer": 1.5,
			"sentinel": 1.6
		},
		"preferred_encounter_labels": ["Convergence", "Suppression", "Fortress", "Breach"],
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


static func get_combat_identity(biome_id: String) -> Dictionary:
	return COMBAT_IDENTITIES.get(biome_id, {}) as Dictionary


static func get_room_combat_identity(biome_id: String, mode: String = "ordinary", fragments: bool = false) -> Dictionary:
	var identity := get_combat_identity(biome_id).duplicate(true)
	if identity.is_empty() or (mode == "ordinary" and not fragments):
		return identity
	var patterns := {
		"crumble": ["Falling rubble", "Small rockfalls", "rockfalls"],
		"haunt": ["Clinging shadows", "Small shadow patches", "shadows"],
		"shatterfield": ["Falling fragments", "Small fragment falls", "fragment falls"],
		"grinding_vault": ["Crushing rings", "Small crushers alternating discs and rings", "crushers"],
		"storm_reach": ["Baitable lightning", "Small lightning strikes", "lightning strikes"],
		"hollow": ["Alternating lanes", "Short floor eruptions", "eruptions"],
		"void_breach": ["Broken void bands", "Short void bands with an open gap", "void bands"],
		"the_maelstrom": ["Turning storm", "Small turning storm sectors", "storm sectors"],
		"convergence_end": ["Paired pulses", "Pairs of small floor pulses", "floor pulses"]
	}
	var pattern: Array = patterns[biome_id]
	identity.terrain = pattern[0]
	if mode == "assistance":
		identity.rule = "%s affect foes only." % String(pattern[1])
		if biome_id == "haunt":
			identity.rule += " Foes inside are {kw:slow|Slowed}."
		else:
			identity.rule += " A warning shows where damage will land."
		identity.tactic = "Lure foes into the smooth double borders. These biome zones are safe for you; enemy moves still hurt."
		identity.entry_hint = "HELP: %s hurt foes only. Safe for you." % String(pattern[2]).capitalize()
		if biome_id == "haunt":
			identity.entry_hint = "HELP: Shadows Slow foes only. Safe for you."
	else:
		identity.rule = "%s appear between longer pauses, leaving required objective space clear." % String(pattern[1])
		if biome_id == "haunt":
			identity.rule += " They {kw:slow} you and foes inside."
		else:
			identity.rule += " Their warned impacts hurt you and foes."
		identity.tactic = "Lure foes into the marked area, then leave before impact."
		if biome_id == "haunt":
			identity.tactic = "Lead pursuers through the shadows; keep your own route outside them."
		identity.entry_hint = "DANGER: %s hurt you and foes. Leave before impact." % String(pattern[2]).capitalize()
		if biome_id == "haunt":
			identity.entry_hint = "DANGER: Shadows Slow you and foes. Keep outside the marks."
	return identity


static func generate_impact_text(biome: Dictionary, mode: String = "", fragments: bool = false) -> String:
	var sections: Array[String] = []
	var identity := get_room_combat_identity(String(biome.get("id", "")), mode if not mode.is_empty() else "ordinary", fragments)
	if not identity.is_empty():
		var heading := "BIOME RULE" if String(biome.id) == "shatterfield" and not fragments else ("HELP" if mode == "assistance" else "DANGER")
		sections.append(heading + ": " + String(identity.terrain).to_upper() + "\n" + String(identity.rule))
		sections.append("EFFECT\n" + get_effect_text(String(biome.id), mode if not mode.is_empty() else "ordinary", fragments))
		var timing := get_timing_text(String(biome.id), mode if not mode.is_empty() else "ordinary", fragments)
		if not timing.is_empty():
			sections.append("READ THE FLOOR\n" + timing)
		sections.append("USE IT TO YOUR ADVANTAGE\n" + String(identity.tactic))

	var encounter_labels := biome.get("preferred_encounter_labels", []) as Array
	if not encounter_labels.is_empty():
		var names: Array[String] = []
		for label in encounter_labels:
			names.append(String(label))
		sections.append("MORE LIKELY ENCOUNTERS\n" + _join_mid_dot(names))

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

	if not identity.is_empty():
		if mode.is_empty():
			sections.append("EVERY COMBAT ROUTE\nSpecial rooms add smaller biome patterns around objectives. Boss and Apex biome zones affect foes only. Shatterfield uses falling fragments where there is no cracked cover.")
		elif mode == "assistance":
			sections.append("THIS ROOM\nMint double borders mean HELP. Enemy moves remain dangerous.")
		elif mode == "compact":
			sections.append("THIS ROOM\nPatterns avoid required objective space. Crowded rooms switch to smooth double-bordered HELP, affecting foes only.")
	return "\n".join(sections)


static func get_effect_text(biome_id: String, mode: String = "ordinary", fragments: bool = false) -> String:
	if biome_id == "shatterfield" and not fragments:
		return "Each deliberate {kw:attack} contact removes one crack, regardless of damage. Three contacts open a route and release shards: 60 base damage to foes within 160, once per pillar. You are safe."
	var friendly := mode == "assistance"
	if biome_id == "haunt":
		var reduction := 40 if mode == "ordinary" else 25
		return ("Foes only: %d%% slower movement inside. You are safe." if friendly else "You and foes: %d%% slower movement inside. No damage.") % reduction
	var enemy_damage := 50 if biome_id == "storm_reach" else 35
	var player_damage := 10 if biome_id == "storm_reach" else 8
	return ("Foes only: %d base damage per event. You are safe." % enemy_damage if friendly else "%d base damage to you; %d to foes, once per event. Normal damage protection applies." % [player_damage, enemy_damage])


static func get_timing_text(biome_id: String, mode: String = "ordinary", fragments: bool = false) -> String:
	if biome_id == "shatterfield" and not fragments:
		return ""
	var compact := mode != "ordinary" or fragments
	var warning := "1.8" if compact else "1.4"
	var recovery := "6" if mode == "assistance" else ("5" if compact else "2.5")
	if biome_id == "haunt":
		return "%ss warning, then %ss of shadows. %ss pause before the next warning." % [warning, "2" if compact else "3", recovery]
	if biome_id in ["crumble", "storm_reach", "shatterfield"]:
		return "%ss warning, then one impact at the marked spot. %ss pause after the impact fades." % [warning, recovery]
	return "%ss warning, then %ss of damage in the marked area. %ss pause follows." % [warning, "0.5" if compact else "0.85", recovery]


static func get_rule_status(biome_id: String, mode: String, fragments: bool, phase: String) -> String:
	if get_combat_identity(biome_id).is_empty():
		return ""
	if biome_id == "shatterfield" and not fragments:
		return "HELP · SHARD BURST · OPEN ROUTES"
	var target := "HELP · FOES ONLY\n" if mode == "assistance" else "DANGER · YOU + FOES\n"
	match phase:
		"survey":
			return target + "BIOME PAUSED"
		"warning":
			return target + "WARNING"
		"active":
			return target + ("SLOW ACTIVE" if biome_id == "haunt" else ("IMPACT" if biome_id in ["crumble", "storm_reach", "shatterfield"] else "DAMAGE ACTIVE"))
	return target + "BETWEEN PATTERNS"


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
		"keeper": "Keepers",
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

## Centralized power registry and unified data structure
## All upgrades (stat boosts) and trial powers (combat abilities) are defined here
## This is the single source of truth for what powers exist and their metadata

extends Node

const DESCRIPTION_CAP_GUARD := preload("res://scripts/shared/description_cap_guard.gd")
const COMBAT_KEYWORDS := preload("res://scripts/shared/combat_keyword_catalogue.gd")

## Resolved gameplay properties, not recipe names or changes to reward weighting.
## Conditions remain visible alongside keyword matches; a match never grants a proc.
static func get_power_keyword_metadata(power_id: String, level: int = 1, _prismatic: bool = false) -> Dictionary:
	var produces: Array[String] = []
	var accepts: Array[String] = []
	var conditions: Array[String] = []
	var condition_text := ""
	match power_id:
		"farshot":
			accepts = ["damage"]
			condition_text = "Foe center at least 160 from your current body when damage lands, including Fields and Echoes. The bonus scales with contact time and copied-effect strength. Effigy and Projectile origins do not set the distance."
		"patient_hunter", "marked_prey":
			var condition := "slow" if power_id == "patient_hunter" else "mark"
			accepts = ["damage", condition]
			conditions = [condition]
			condition_text = "Adds to the qualifying Damage basis against already %s foes. Conditions are checked before damage and scale with the source's strength and contact time." % ("Slowed" if condition == "slow" else "Marked")
		"stormbrand":
			accepts = ["electric"]
			produces = ["mark"]
			if level >= 3:
				accepts.append("mark")
				produces.append("slow")
			condition_text = "Electric damage applies timed Mark after damage, once per foe per original action. At level 3, a foe already Marked before that damage is also Slowed. Strongest Mark benefits all players."
		"spark_relay":
			accepts = ["burst"]
			produces = ["projectile", "electric", "damage"]
			condition_text = "Accepted Burst damage fires one seeking Electric Projectile from your body per original action. It prefers the struck foe while alive and reachable, then retargets living foes after a hit or target death. It hits each foe once, shares one travel budget and stops at solid cover. No reachable foe means no bolt."
		"shatterwake":
			accepts = ["projectile"]
			produces = ["burst", "damage"]
			condition_text = "Accepted Projectile damage releases one Burst per original action, including return legs and descendants. Its damage includes the struck foe if alive. Each victim resolves its own damage conditions."
		"first_strike", "heavy_blow", "bloodpact", "severing_edge":
			accepts = ["damage"]
			condition_text = {"first_strike": "Enemy at least 80% HP; scales the qualifying Damage basis.", "heavy_blow": "Increases the Damage stat used by your powers.", "bloodpact": "You are at 50% HP or below; scales the qualifying Damage basis.", "severing_edge": "Enemy below 55% HP; scales the qualifying Damage basis."}[power_id]
		"wide_arc", "long_reach", "execution_edge", "bloodvow":
			accepts = ["attack"]
			condition_text = "Modifies qualifying deliberate Attacks; automatic damage does not perform another Attack."
		"fleet_foot", "heartstone", "iron_skin":
			condition_text = "A general movement or survival increase."
		"blink_dash", "surge_step":
			accepts = ["dash"]
		"battle_trance":
			accepts = ["damage"]
			condition_text = "Your accepted damage refreshes movement speed; repeated triggers do not stack its strength."
		"aegis_field":
			produces = ["burst", "slow"]
			condition_text = "Automatic pulse on its cooldown. The pulse does not deal damage or leave a Field."
		"hunters_snare":
			produces = ["slow"]
			accepts.assign(["attack_hit", "slow"] if level < 2 else ["attack_hit", "damage", "slow"])
			conditions = ["slow"]
			condition_text = "Attack hits apply Slow. Bonus checks already Slowed targets before this damage; level 1 affects Attacks, level 2+ all your damage."
		"phantom_step":
			produces = ["damage", "slow"]
			accepts = ["dash"]
			condition_text = "Contact during your normal Dash deals damage and applies Slow."
		"riftpunch":
			accepts = ["dash", "attack_hit"]
			if level >= 2:
				produces.append("slow")
			if level >= 3:
				produces.append_array(["damage", "burst"])
			condition_text = "Dash completion primes one deliberate attack hit, including a ranged arc."
		"reaper_step":
			accepts = ["kill"]
			produces = ["dash"]
			condition_text = "Your Kill fully refreshes Dash."
		"static_wake":
			produces = ["field", "electric", "damage"]
			if level >= 3:
				produces.append("slow")
			accepts = ["dash"]
			condition_text = "Normal Dash only; two trails share one damage clock. Slow is applied after damage at level 3."
		"storm_crown":
			produces = ["electric", "damage"]
			accepts = ["damage"]
			if level >= 2:
				accepts.append("slow")
			condition_text = "Counts each foe once per action; one discharge per action. Crown descendants cannot recharge it. Level 2+ gains one jump through already Slowed foes."
		"wraithstep":
			produces = ["mark"]
			accepts = ["dash"]
			if level >= 2:
				produces.append_array(["burst", "damage"])
				accepts.append_array(["attack_hit", "mark"])
				conditions = ["mark"]
			condition_text = "Dash applies Mark. Level 2: attack hit on an already Marked foe releases one Burst per Attack; level 3 chains through up to three more Marked foes."
		"dread_resonance":
			produces = ["mark"]
			accepts = ["attack_hit", "mark", "damage"]
			conditions = ["mark"]
			condition_text = "Attack hits build one stack per foe per Attack. Your stacks amplify your damage against that Marked foe and persist on each foe until you or that foe dies, or the room ends."
		"eclipse_mark":
			produces = ["mark"]
			accepts = ["kill"]
			condition_text = "Your Kill applies timed Mark nearby. The strongest Mark helps all players; damage does not consume it."
		"rupture_wave", "fracture_field":
			produces = ["burst", "damage"]
			accepts.assign(["attack_hit"] if power_id == "rupture_wave" else ["kill"])
			if power_id == "fracture_field" or level >= 2:
				produces.append("slow")
			condition_text = "Own descendants cannot recursively repeat the same effect."
		"razor_wind":
			produces = ["attack_hit", "damage"]
			accepts = ["attack"]
			condition_text = "Each deliberate Attack extends an immediate slicing arc beyond normal melee reach."
		"voidfire":
			produces = ["burst", "damage"]
			accepts = ["attack_hit"]
			condition_text = "Connected Attacks build Heat; overheating releases a damaging Burst, empties Heat and briefly locks Attacks."
		"farline_volley":
			accepts = ["attack_hit", "dash"]
			if level >= 2:
				produces.append("slow")
			if level >= 3:
				produces.append_array(["burst", "damage"])
			condition_text = "Direct attack hits near the edge of reach build stacks; Dash spends/resets them."
		"sigil_chain":
			produces = ["field", "damage"]
			if level >= 2:
				produces.append("slow")
			accepts = ["attack_hit"]
			condition_text = "Four attack hits arm a sigil; the next connected Attack places its Field. Hexweaver's Sigil Burst detonates existing sigils."
		"blast_drive":
			produces = ["attack_hit", "burst", "recoil", "push", "damage"]
			accepts = ["attack"]
			condition_text = "Hold after a successful Attack, then release. Each blast spends one charge."
		"razor_orbit":
			produces = ["orbit", "damage"]
			accepts = ["dash"]
			condition_text = "Hold through a successful Dash and deliberately aim at an anchor. Orbit cuts do not perform Attacks."
		"returning_crescent":
			produces = ["projectile", "damage"]
			accepts = ["attack"]
			condition_text = "One hit per foe each way; no extra Attack from the blade."
		"wardens_verdict":
			produces = ["burst", "damage"]
			accepts = ["attack_hit"]
			condition_text = "Each foe counts once per Attack; the same foe can count on later Attacks. The fourth contact releases a Burst. Cadence resets after 2.2s without an attack hit. Bonus power scales the rising damage of each contact."
		"lacuna_echo":
			produces = ["field", "slow", "damage"]
			accepts = ["kill", "field"]
			condition_text = "Kills place one damaging well, replacing the last. After pulse damage, surviving foes are Slowed. Your damage gains its bonus once inside any owned Field; overlapping Fields do not stack the bonus."
		"sovereign_tempo":
			produces = ["burst", "damage"]
			accepts = ["attack_hit", "damage", "mark", "dash", "recoil", "orbit"]
			conditions = ["mark"]
			condition_text = "Attack hits or your damage against already Marked foes build one Tempo stack per original action. Completing Dash, Recoil or Orbit spends the stacks in a Burst; its accepted damage refunds Dash once. This Burst and its descendants cannot build Tempo."
		"pillar_convergence":
			produces = ["burst", "damage"]
			accepts = ["attack_hit", "electric", "field"]
			condition_text = "Attack hits or your Electric damage add one charge per original action. Three/two charges plant one stationary seal at the struck foe. It Bursts after 0.8s; later owned Field damage inside detonates it early at +50% damage. No charging while armed or for 0.6s afterward; actions spent then cannot charge later. Its descendants cannot plant another seal."
		"unbroken_oath":
			accepts = ["attack_hit", "attack"]
		"edict_of_the_court":
			produces = ["burst", "slow", "damage"]
			accepts = ["kill"]
			condition_text = "Your Kills release one damaging Burst per original action. After Burst damage, surviving foes are Slowed; all kills and descendants share the action's allowance."
		"null_corridor":
			produces = ["field", "mark", "damage"]
			accepts = ["dash"]
			condition_text = "Normal Dash leaves a corridor; each trail damages a foe at most once every 0.5s and then applies a timed Mark. The strongest active Mark benefits all players."
		"ruinous_impact":
			produces = ["launch", "impact", "burst", "damage"]
			accepts = ["attack_hit", "push", "pull"]
			condition_text = "One impact Burst per Launch. Immovable foes compress; explosions cannot arm further explosions."
		"sovereigns_double":
			produces = ["echo", "damage"]
			accepts = ["dash", "recoil", "orbit", "attack"]
			condition_text = "Movement completion places one shade. An Echo of Blast Drive retains its Burst shape. Echoes share the original action's reaction limits and spend no extra resources."
	var description_keywords: Array[String] = []
	for id in produces + accepts + conditions:
		if not description_keywords.has(id):
			description_keywords.append(id)
	if power_id in ["first_strike", "heavy_blow", "bloodpact", "severing_edge", "patient_hunter", "marked_prey", "farshot", "static_wake", "sigil_chain", "blast_drive", "razor_orbit", "returning_crescent", "null_corridor", "ruinous_impact"]:
		description_keywords.append("damage_stat")
	return {"produces": produces, "accepts": accepts, "conditions": conditions, "condition_text": condition_text, "description_keywords": description_keywords}

# Power type constants
const POWER_TYPE_UPGRADE = "upgrade"  # Stat boosts: Swift Strike, Heavy Blow, etc
const POWER_TYPE_TRIAL = "trial_power"  # Combat abilities: Razor Wind, Execution Edge, Rupture Wave

# Damage modeling metadata
const DAMAGE_KIND_NONE = "none"
const DAMAGE_KIND_FLAT = "flat"
const DAMAGE_KIND_SCALING = "scaling"
const DAMAGE_KIND_HYBRID = "hybrid"

const DAMAGE_SCALE_SOURCE_NONE = "none"
const DAMAGE_SCALE_SOURCE_DAMAGE = "damage_stat"
const DAMAGE_SCALE_SOURCE_HIT = "hit_damage"

# Boss epitaph lines - displayed on boss defeat
const BOSS_EPITAPHS := {
	"kilnheart": {"default": "The furnace cools. Its last spark is yours."},
	"glassweaver": {"default": "The final thread breaks. The prism court falls silent."},
	"null_archivist": {"default": "The last page closes. Your name remains."},
	"warden": {
		"hexweaver": "Your chaos toppled the first pillar. The void approves.",
		"veilstrider": "The guardian never saw you coming.",
		"bastion": "Your walls didn't break. The Warden did.",
		"riftlancer": "You pinned brute force to a single line and broke it where it stood.",
		"default": "A guardian falls."
	},
	"sovereign": {
		"hexweaver": "Order crumbles before true chaos.",
		"veilstrider": "You danced through infinity itself.",
		"bastion": "Not enough stone to hold the cosmos.",
		"riftlancer": "You found the one true vector in a throne of false geometry.",
		"default": "Sovereign's reign ends. The final threshold awaits."
	},
	"lacuna": {
		"hexweaver": "The void answered your call. Now it's silent.",
		"veilstrider": "You stepped through the abyss and back. Impossible.",
		"bastion": "Unbreakable became broken. The irony is exquisite.",
		"riftlancer": "Even the missing beat held long enough for your harpoon to land.",
		"default": "The Abyss itself breathes no more."
	}
}

const DAMAGE_MODEL_BY_POWER := {
	"patient_hunter": {"kind": DAMAGE_KIND_FLAT, "scale_source": DAMAGE_SCALE_SOURCE_NONE, "formula_note": "+X conditional Damage basis against already Slowed foes"},
	"marked_prey": {"kind": DAMAGE_KIND_FLAT, "scale_source": DAMAGE_SCALE_SOURCE_NONE, "formula_note": "+X conditional Damage basis against already Marked foes"},
	"farshot": {"kind": DAMAGE_KIND_FLAT, "scale_source": DAMAGE_SCALE_SOURCE_NONE, "formula_note": "+X conditional Damage basis against foes at least 160 from the owner's current body when damage lands"},
	"stormbrand": {"kind": DAMAGE_KIND_NONE, "scale_source": DAMAGE_SCALE_SOURCE_NONE, "formula_note": "Timed Mark from accepted Electric damage; level 3 also applies Slow to an already Marked foe"},
	"spark_relay": {"kind": DAMAGE_KIND_SCALING, "scale_source": DAMAGE_SCALE_SOURCE_HIT, "formula_note": "A fraction of the triggering Burst's unconditioned damage descriptor and coefficient"},
	"shatterwake": {"kind": DAMAGE_KIND_SCALING, "scale_source": DAMAGE_SCALE_SOURCE_HIT, "formula_note": "A fraction of the triggering Projectile's unconditioned damage descriptor and coefficient"},
	# Upgrades
	"first_strike": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X conditional Damage basis against enemies at or above 80% HP"
	},
	"heavy_blow": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X to Damage stat"
	},
	# Trial powers
	"razor_wind": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Y% of hit damage"
	},
	"execution_edge": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Hit damage multiplied every N swings"
	},
	"rupture_wave": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Y% of hit damage in radius"
	},
	"hunters_snare": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Percentage damage amplification against already Slowed targets"
	},
	"phantom_step": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Y% dash-through damage"
	},
	"riftpunch": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X bonus damage on first melee hit after dashing; grants brief contact grace"
	},
	"static_wake": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Y% wake pulse damage"
	},
	"storm_crown": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Y% of hit damage on chain proc"
	},
	"wraithstep": {
		"kind": DAMAGE_KIND_HYBRID,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Timed shared Mark vulnerability plus a bounded Attack-triggered Burst from level 2"
	},
	# Voidfire archetype
	"voidfire": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Y% of hit damage on detonation burst"
	},
	"dread_resonance": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Owner-specific percentage-point bonus per stack against a Marked foe"
	},
	"farline_volley": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X flat damage per Volley stack; widens attack arc per stack; dashing resets"
	},
	"sigil_chain": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Charged hits drop a sigil zone that ticks player_damage * ratio in radius"
	},
	"blast_drive": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Charged blast deals 150-250% of Damage, multiplied by its Arcana damage scale"
	},
	"razor_orbit": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Orbit cuts deal 35% of Damage, multiplied by their Arcana damage scale, per contact window"
	},
	"returning_crescent": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Each blade deals 45% of Damage times its Arcana scale, once per enemy outbound and once on return"
	},
	# Character-lore bridges
	"bloodvow": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Hit damage multiplied while player is below the wounded threshold"
	},
	"eclipse_mark": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Timed shared vulnerability; strongest active Mark amplifies all player damage"
	},
	"fracture_field": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Y% of hit damage along non-chaining fault lines from kill position"
	},
	# Boons
	"bloodpact": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X conditional Damage basis while at or below 50% HP"
	},
	"severing_edge": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X conditional Damage basis against enemies below 55% HP"
	},
	# Boss rewards
	"wardens_verdict": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "Each hit deals escalating bonus damage; the 4th hit detonates a burst on nearby enemies"
	},
	"lacuna_echo": {
		"kind": DAMAGE_KIND_HYBRID,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Kill zones pulse damage over time and amplify hits inside zone"
	},
	"sovereign_tempo": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Attack hits or damage against already Marked foes build one stack per action; Dash, Recoil or Orbit completion converts stacks into a Damage-based Burst"
	},
	"pillar_convergence": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Three/two Attack-hit or Electric actions plant a stationary seal; 0.8s fuse, radius 76/90, Burst 180/240% of Damage. Later owned Field damage inside detonates it early at 270/360%. One seal, no movement, 0.6s rearm lock; own descendants cannot charge another seal"
	},
	"unbroken_oath": {
		"kind": DAMAGE_KIND_HYBRID,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Single-target hits trickle Oath; multihits scale exponentially. Fill bar to prime next-hit sword strike"
	},
	"edict_of_the_court": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Kills release one Burst per original action for 80%/120% of Damage; accepted damage Slows survivors"
	},
	"null_corridor": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Dash leaves a Field dealing 24%/28% of Damage, at most once every 0.5s per trail; accepted damage applies a 10%/15% Mark for 1s"
	},
	"ruinous_impact": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Launched enemies burst on impact for 100%/140% of Damage; bosses and Apex enemies compress and burst in place"
	},
	"sovereigns_double": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Copies attack shape and damage at 55%; applicable bonuses are checked against each Echo target."
	}
}

const UPGRADE_BALANCE := {
	"patient_hunter": {"kind": "add_int", "property": "patient_hunter_bonus_damage", "add": 12},
	"marked_prey": {"kind": "add_int", "property": "marked_prey_bonus_damage", "add": 12},
	"farshot": {"kind": "add_int", "property": "farshot_bonus_damage", "add": 10},
	"first_strike": {
		"kind": "add_int",
		"property": "first_strike_bonus_damage",
		"add": 16
	},
	"heavy_blow": {
		"kind": "add_int",
		"property": "damage",
		"add": 7
	},
	"wide_arc": {
		"kind": "add_clamp",
		"property": "attack_arc_degrees",
		"add": 28.0,
		"min": 60.0,
		"max": 280.0
	},
	"long_reach": {
		"kind": "add_float",
		"property": "attack_range",
		"add": 11.0
	},
	"fleet_foot": {
		"kind": "add_float",
		"property": "max_speed",
		"add": 17.0
	},
	"blink_dash": {
		"kind": "mul_min",
		"property": "dash_cooldown",
		"mult": 0.80,
		"min": 0.14
	},
	"iron_skin": {
		"kind": "add_int",
		"property": "iron_skin_armor",
		"add": 4,
		"stack_property": "iron_skin_stacks"
	},
	"battle_trance": {
		"kind": "add_float",
		"property": "battle_trance_move_speed_bonus",
		"add": 0.22
	},
	"surge_step": {
		"kind": "add_float",
		"property": "dash_speed",
		"add": 85.0
	},
	"heartstone": {
		"kind": "add_int",
		"property": "max_health",
		"add": 10
	},
	"bloodpact": {
		"kind": "add_int",
		"property": "bloodpact_bonus_damage",
		"add": 9
	},
	"severing_edge": {
		"kind": "add_int",
		"property": "severing_edge_bonus_damage",
		"add": 14
	}
}

const BOSS_REWARD_BALANCE := {
	"shatterwake": {"kind": "add_int", "property": "shatterwake_stacks", "add": 1},
	"wardens_verdict": {
		"kind": "add_int",
		"property": "apex_predator_bonus_damage",
		"add": 34
	},
	"lacuna_echo": {
		"kind": "add_int",
		"property": "void_echo_damage",
		"add": 42
	},
	"sovereign_tempo": {
		"kind": "add_float",
		"property": "apex_momentum_speed_bonus",
		"add": 0.09
	},
	"pillar_convergence": {
		"kind": "add_float",
		"property": "convergence_surge_damage_ratio",
		"add": 0.22
	},
	"unbroken_oath": {
		"kind": "add_float",
		"property": "indomitable_spirit_damage_reduction",
		"add": 0.12
	},
	"edict_of_the_court": {
		"kind": "add_int",
		"property": "edict_court_push_power",
		"add": 40
	},
	"null_corridor": {
		"kind": "add_float",
		"property": "null_corridor_strength",
		"add": 0.5
	},
	"ruinous_impact": {
		"kind": "add_int",
		"property": "ruinous_impact_stacks",
		"add": 1
	},
	"sovereigns_double": {
		"kind": "add_int",
		"property": "sovereigns_double_stacks",
		"add": 1
	}
}

const UPGRADE_STACK_LIMITS := {
	"patient_hunter": 3,
	"marked_prey": 3,
	"farshot": 3,
	"first_strike": 3,
	"heavy_blow": 3,
	"wide_arc": 3,
	"long_reach": 3,
	"fleet_foot": 3,
	"blink_dash": 3,
	"iron_skin": 3,
	"battle_trance": 3,
	"surge_step": 3,
	"heartstone": 2,
	"bloodpact": 3,
	"severing_edge": 3
}

## Unified trial power definitions: canonical source for trial power balance, stack limits, and parameter mapping
## Each trial power now has complete metadata: balance params, stack limit, and parameter mapping rules
## Single source of truth for all trial power configuration
const TRIAL_POWER_DEFINITIONS := {
	"stormbrand": {
		"stack_limit": 3,
		"balance_params": {"mark_ratio_base": 0.10, "mark_ratio_per_level": 0.04, "duration_base": 3.0, "duration_per_level": 0.5, "slow_duration": 1.0, "slow_mult": 0.75},
		"param_map": {
			"reward_flag": "reward_stormbrand", "stack_property": "stormbrand_stacks",
			"parameters": {
				"mark_bonus_ratio": {"property": "stormbrand_mark_bonus_ratio", "type": "float"},
				"mark_duration": {"property": "stormbrand_mark_duration", "type": "float"},
				"slow_duration": {"property": "stormbrand_slow_duration", "type": "float"},
				"slow_mult": {"property": "stormbrand_slow_mult", "type": "float"}
			}
		}
	},
	"spark_relay": {
		"stack_limit": 3,
		"balance_params": {"damage_ratio_base": 0.50, "damage_ratio_per_level": 0.10, "travel_range": 440.0, "max_targets_base": 1, "max_targets_per_level": 1},
		"param_map": {
			"reward_flag": "reward_spark_relay", "stack_property": "spark_relay_stacks",
			"parameters": {
				"damage_ratio": {"property": "spark_relay_damage_ratio", "type": "float"},
				"max_targets": {"property": "spark_relay_max_targets", "type": "int"},
				"travel_range": {"property": "spark_relay_travel_range", "type": "float"}
			}
		}
	},
	"razor_wind": {
		"stack_limit": 3,
		"balance_params": {
			"range_base": 1.20,
			"range_per_stack": 0.10,
			"damage_ratio_base": 0.50,
			"damage_ratio_per_stack": 0.20,
			"attack_cooldown_mult": 0.96,
			"attack_cooldown_min": 0.1,
			"arc_base": 24.0,
			"arc_match_player_at_stack": 3
		},
		"param_map": {
			"reward_flag": "reward_razor_wind",
			"stack_property": "razor_wind_stacks",
			"parameters": {
				"range_scale": {"property": "razor_wind_range_scale", "type": "float"},
				"damage_ratio": {"property": "razor_wind_damage_ratio", "type": "float"},
				"attack_cooldown": {"property": "attack_cooldown", "type": "float"},
				"arc_degrees": {"property": "razor_wind_arc_degrees", "type": "float"}
			}
		}
	},
	"execution_edge": {
		"stack_limit": 3,
		"balance_params": {
			"every_base": 4,
			"every_floor": 1,
			"damage_mult_base": 1.9,
			"damage_mult_per_stack": 0.20,
			"attack_lock_mult": 0.94,
			"attack_lock_min": 0.08
		},
		"param_map": {
			"reward_flag": "reward_execution_edge",
			"stack_property": "execution_edge_stacks",
			"parameters": {
				"every": {"property": "execution_every", "type": "int"},
				"damage_mult": {"property": "execution_damage_mult", "type": "float"},
				"attack_lock_duration": {"property": "attack_lock_duration", "type": "float"}
			}
		}
	},
	"rupture_wave": {
		"stack_limit": 3,
		"balance_params": {
			"radius_base": 70.0,
			"radius_per_stack": 14.0,
			"damage_ratio_base": 0.30,
			"damage_ratio_per_stack": 0.15,
			"damage_add": 2,
			"slow_at_stack": 2,
			"slow_duration": 0.4,
			"slow_mult": 0.75,
			"chain_at_stack": 3,
			"chain_damage_ratio": 0.6,
			"chain_radius_ratio": 0.7
		},
		"param_map": {
			"reward_flag": "reward_rupture_wave",
			"stack_property": "rupture_wave_stacks",
			"parameters": {
				"radius": {"property": "rupture_wave_radius", "type": "float"},
				"damage_ratio": {"property": "rupture_wave_damage_ratio", "type": "float"}
			}
		}
	},
	"aegis_field": {
		"stack_limit": 3,
		"balance_params": {
			"resist_base": 0.16,
			"resist_per_stack": 0.08,
			"resist_cap": 0.42,
			"resist_duration_base": 0.8,
			"resist_duration_per_stack": 0.25,
			"pulse_radius_base": 88.0,
			"pulse_radius_per_stack": 18.0,
			"slow_duration_base": 0.9,
			"slow_duration_per_stack": 0.22,
			"slow_mult_base": 0.74,
			"slow_mult_per_stack": -0.08,
			"slow_mult_min": 0.36,
			"cooldown_base": 5.0,
			"cooldown_per_stack": -0.60,
			"cooldown_min": 2.5
		},
		"param_map": {
			"reward_flag": "reward_aegis_field",
			"stack_property": "aegis_field_stacks",
			"parameters": {
				"resist": {"property": "aegis_field_resist_ratio", "type": "float"},
				"duration": {"property": "aegis_field_resist_duration", "type": "float"},
				"radius": {"property": "aegis_field_pulse_radius", "type": "float"},
				"slow_duration": {"property": "aegis_field_slow_duration", "type": "float"},
				"slow_mult": {"property": "aegis_field_slow_mult", "type": "float"},
				"cooldown": {"property": "aegis_field_cooldown", "type": "float"}
			}
		}
	},
	"hunters_snare": {
		"stack_limit": 3,
		"balance_params": {
			"bonus_ratio_base": 0.15,
			"bonus_ratio_per_stack": 0.05,
			"slow_duration_base": 0.6,
			"slow_duration_per_stack": 0.16,
			"slow_mult_base": 0.72,
			"slow_mult_per_stack": -0.06,
			"slow_mult_min": 0.42
		},
		"param_map": {
			"reward_flag": "reward_hunters_snare",
			"stack_property": "hunters_snare_stacks",
			"parameters": {
				"bonus_ratio": {"property": "hunters_snare_bonus_ratio", "type": "float"},
				"slow_duration": {"property": "hunters_snare_slow_duration", "type": "float"},
				"slow_mult": {"property": "hunters_snare_slow_mult", "type": "float"}
			}
		}
	},
	"phantom_step": {
		"stack_limit": 3,
		"balance_params": {
			"damage_ratio_base": 0.40,
			"damage_ratio_per_stack": 0.16,
			"slow_duration_base": 0.6,
			"slow_duration_per_stack": 0.24,
			"dash_cooldown_mult": 0.86,
			"dash_cooldown_min": 0.16
		},
		"param_map": {
			"reward_flag": "reward_phantom_step",
			"stack_property": "phantom_step_stacks",
			"parameters": {
				"damage": {"property": "phantom_step_damage", "type": "int"},
				"damage_ratio": {"property": "phantom_step_damage_ratio", "type": "float"},
				"slow_duration": {"property": "phantom_step_slow_duration", "type": "float"},
				"dash_cooldown": {"property": "dash_cooldown", "type": "float"}
			}
		}
	},
	"riftpunch": {
		"stack_limit": 3,
		"balance_params": {
			"bonus_damage_base": 24,
			"bonus_damage_per_stack": 18,
			"window_base": 0.9,
			"window_per_stack": 0.15,
			"grace_base": 0.4,
			"grace_per_stack": 0.08
		},
		"param_map": {
			"reward_flag": "reward_riftpunch",
			"stack_property": "riftpunch_stacks",
			"parameters": {
				"bonus_damage": {"property": "riftpunch_bonus_damage", "type": "int"},
				"window_duration": {"property": "riftpunch_window_duration", "type": "float"},
				"grace_duration": {"property": "riftpunch_grace_duration", "type": "float"}
			}
		}
	},
	"reaper_step": {
		"stack_limit": 3,
		"balance_params": {
			"range_mult_base": 1.40,
			"range_mult_per_stack": 0.22,
			"chain_window_at_stack": 2,
			"chain_window_duration": 1.5,
			"chain_grace_at_stack": 3,
			"chain_grace_duration": 0.4
		},
		"param_map": {
			"reward_flag": "reward_void_dash",
			"stack_property": "void_dash_stacks",
			"parameters": {
				"range_mult": {"property": "void_dash_range_mult", "type": "float"},
				"chain_window": {"property": "reaper_chain_window", "type": "float"},
				"chain_grace": {"property": "reaper_chain_grace", "type": "float"}
			}
		}
	},
	"static_wake": {
		"stack_limit": 3,
		"balance_params": {
			"damage_ratio_base": 0.30,
			"damage_ratio_per_stack": 0.15,
			"lifetime_base": 1.5,
			"lifetime_per_stack": 0.50,
			"trail_radius_base": 28.0,
			"trail_radius_per_stack": 6.0,
			"slow_at_stack": 3,
			"slow_duration_base": 0.7,
			"slow_duration_per_stack": 0.08,
			"slow_mult": 0.80
		},
		"param_map": {
			"reward_flag": "reward_static_wake",
			"stack_property": "static_wake_stacks",
			"parameters": {
				"damage": {"property": "static_wake_damage", "type": "int"},
				"damage_ratio": {"property": "static_wake_damage_ratio", "type": "float"},
				"lifetime": {"property": "static_wake_lifetime", "type": "float"},
				"trail_radius": {"property": "static_wake_trail_radius", "type": "float"}
			}
		}
	},
	"storm_crown": {
		"stack_limit": 3,
		"balance_params": {
			"proc_every_base": 4,
			"proc_every_per_stack": -1,
			"proc_every_floor": 1,
			"chain_targets_base": 1,
			"chain_targets_per_stack": 1,
			"chain_radius_base": 160.0,
			"chain_radius_per_stack": 32.0,
			"damage_ratio_base": 0.45,
			"damage_ratio_per_stack": 0.15
		},
		"param_map": {
			"reward_flag": "reward_storm_crown",
			"stack_property": "storm_crown_stacks",
			"parameters": {
				"proc_every": {"property": "storm_crown_proc_every", "type": "int"},
				"chain_targets": {"property": "storm_crown_chain_targets", "type": "int"},
				"chain_radius": {"property": "storm_crown_chain_radius", "type": "float"},
				"damage_ratio": {"property": "storm_crown_damage_ratio", "type": "float"}
			}
		}
	},
	"wraithstep": {
		"stack_limit": 3,
		"balance_params": {
			"mark_duration_base": 2.0,
			"mark_duration_per_stack": 0.5,
			"dash_mark_radius_base": 100.0,
			"dash_mark_radius_per_stack": 20.0,
			"bonus_ratio_base": 0.10,
			"bonus_ratio_per_stack": 0.05,
			"splash_radius_base": 80.0,
			"splash_radius_per_stack": 16.0,
			"splash_ratio_base": 0.60,
			"splash_ratio_per_stack": 0.12
		},
		"param_map": {
			"reward_flag": "reward_wraithstep",
			"stack_property": "wraithstep_stacks",
			"parameters": {
				"mark_duration": {"property": "wraithstep_mark_duration", "type": "float"},
				"dash_mark_radius": {"property": "wraithstep_dash_mark_radius", "type": "float"},
				"bonus_ratio": {"property": "wraithstep_mark_bonus_ratio", "type": "float"},
				"splash_radius": {"property": "wraithstep_mark_splash_radius", "type": "float"},
				"splash_ratio": {"property": "wraithstep_mark_splash_ratio", "type": "float"}
			}
		}
	},
	"voidfire": {
		"stack_limit": 3,
		"balance_params": {
			"heat_per_hit_base": 0.08,
			"heat_per_hit_per_stack": 0.04,
			"heat_cap": 100.0,
			"danger_zone_threshold": 60.0,
			"danger_zone_amp": 0.30,
			"detonate_ratio_base": 0.75,
			"detonate_ratio_per_stack": 0.15,
			"detonate_radius_base": 110.0,
			"detonate_radius_per_stack": 22.0,
			"lockout_duration": 0.4,
			"overheat_move_mult": 0.5,
			"heat_decay_rate_base": 0.05,
			"heat_decay_rate_per_stack": 0.02,
			"danger_zone_heat_gain_mult": 1.5,
			"reckless_heat_ratio": 1.25,
			"reckless_heat_gain_mult": 2.0,
			"danger_zone_decay_mult": 0.5,
			"reckless_decay_mult": 0.0
		},
		"param_map": {
			"reward_flag": "reward_voidfire",
			"stack_property": "voidfire_stacks",
			"parameters": {
				"heat_per_hit": {"property": "voidfire_heat_per_hit", "type": "float"},
				"heat_cap": {"property": "void_heat_cap", "type": "float"},
				"danger_zone_threshold": {"property": "voidfire_danger_zone_threshold", "type": "float"},
				"danger_zone_amp": {"property": "voidfire_danger_zone_amp", "type": "float"},
				"detonate_ratio": {"property": "voidfire_detonate_ratio", "type": "float"},
				"detonate_radius": {"property": "voidfire_detonate_radius", "type": "float"},
				"lockout_duration": {"property": "voidfire_lockout_duration", "type": "float"},
				"overheat_move_mult": {"property": "voidfire_overheat_move_mult", "type": "float"},
				"heat_decay_rate": {"property": "void_heat_decay_rate", "type": "float"},
				"danger_zone_heat_gain_mult": {"property": "voidfire_danger_zone_heat_gain_mult", "type": "float"},
				"reckless_heat_ratio": {"property": "voidfire_reckless_heat_ratio", "type": "float"},
				"reckless_heat_gain_mult": {"property": "voidfire_reckless_heat_gain_mult", "type": "float"},
				"danger_zone_decay_mult": {"property": "voidfire_danger_zone_decay_mult", "type": "float"},
				"reckless_decay_mult": {"property": "voidfire_reckless_decay_mult", "type": "float"}
			}
		}
	},
	"dread_resonance": {
		"stack_limit": 3,
		"balance_params": {
			"damage_ratio_per_stack": 0.02,
			"mark_bonus_ratio": 0.10,
			"mark_duration": 3.0,
			"max_stacks_base": 6,
			"max_stacks_per_stack": 2,
			"max_stacks_cap": 12
		},
		"param_map": {
			"reward_flag": "reward_dread_resonance",
			"stack_property": "dread_resonance_stacks",
			"parameters": {
				"damage_ratio_per_stack": {"property": "dread_resonance_damage_ratio_per_stack", "type": "float"},
				"mark_bonus_ratio": {"property": "dread_resonance_mark_bonus_ratio", "type": "float"},
				"mark_duration": {"property": "dread_resonance_mark_duration", "type": "float"},
				"max_stacks": {"property": "dread_resonance_max_stacks", "type": "int"}
			}
		}
	},
	"bloodvow": {
		"stack_limit": 3,
		"balance_params": {
			"damage_mult_base": 1.15,
			"damage_mult_per_stack": 0.10,
			"low_hp_threshold": 0.40
		},
		"param_map": {
			"reward_flag": "reward_bloodvow",
			"stack_property": "bloodvow_stacks",
			"parameters": {
				"damage_mult": {"property": "bloodvow_damage_mult", "type": "float"},
				"low_hp_threshold": {"property": "bloodvow_low_hp_threshold", "type": "float"}
			}
		}
	},
	"eclipse_mark": {
		"stack_limit": 3,
		"balance_params": {
			"radius_base": 90.0,
			"radius_per_stack": 18.0,
			"mark_duration_base": 3.0,
			"mark_duration_per_stack": 1.0,
			"bonus_ratio_base": 0.10,
			"bonus_ratio_per_stack": 0.05
		},
		"param_map": {
			"reward_flag": "reward_eclipse_mark",
			"stack_property": "eclipse_mark_stacks",
			"parameters": {
				"radius": {"property": "eclipse_mark_radius", "type": "float"},
				"mark_duration": {"property": "eclipse_mark_duration", "type": "float"},
				"bonus_ratio": {"property": "eclipse_mark_bonus_ratio", "type": "float"}
			}
		}
	},
	"fracture_field": {
		"stack_limit": 3,
		"balance_params": {
			"radius_base": 100.0,
			"radius_per_stack": 20.0,
			"damage_ratio_base": 0.30,
			"damage_ratio_per_stack": 0.12,
			"slow_duration_base": 0.8,
			"slow_duration_per_stack": 0.16
		},
		"param_map": {
			"reward_flag": "reward_fracture_field",
			"stack_property": "fracture_field_stacks",
			"parameters": {
				"radius": {"property": "fracture_field_radius", "type": "float"},
				"damage_ratio": {"property": "fracture_field_damage_ratio", "type": "float"},
				"slow_duration": {"property": "fracture_field_slow_duration", "type": "float"}
			}
		}
	},
	"farline_volley": {
		"stack_limit": 3,
		"balance_params": {
			"arc_per_stack_base": 12.0,
			"bonus_per_stack_base": 2,
			"stack_cap_base": 5
		},
		"param_map": {
			"reward_flag": "reward_farline_volley",
			"stack_property": "farline_volley_stacks",
			"parameters": {
				"arc_per_stack": {"property": "farline_volley_arc_per_stack", "type": "float"},
				"bonus_per_stack": {"property": "farline_volley_bonus_per_stack", "type": "int"},
				"stack_cap": {"property": "farline_volley_stack_cap", "type": "int"}
			}
		}
	},
	"blast_drive": {
		"stack_limit": 3,
		"balance_params": {
			"damage_scale_base": 1.0,
			"damage_scale_per_stack": 0.15,
			"reach_scale_base": 1.0,
			"reach_scale_per_stack": 0.15
		},
		"param_map": {
			"reward_flag": "reward_blast_drive",
			"stack_property": "blast_drive_stacks",
			"parameters": {
				"damage_scale": {"property": "blast_drive_damage_scale", "type": "float"},
				"reach_scale": {"property": "blast_drive_reach_scale", "type": "float"}
			}
		}
	},
	"razor_orbit": {
		"stack_limit": 3,
		"balance_params": {
			"damage_scale_base": 1.0,
			"damage_scale_per_stack": 0.15,
			"reach_scale_base": 1.0,
			"reach_scale_per_stack": 0.15
		},
		"param_map": {
			"reward_flag": "reward_razor_orbit",
			"stack_property": "razor_orbit_stacks",
			"parameters": {
				"damage_scale": {"property": "razor_orbit_damage_scale", "type": "float"},
				"reach_scale": {"property": "razor_orbit_reach_scale", "type": "float"}
			}
		}
	},
	"returning_crescent": {
		"stack_limit": 3,
		"balance_params": {
			"damage_scale_base": 1.0,
			"damage_scale_per_stack": 0.15,
			"reach_scale_base": 1.0,
			"reach_scale_per_stack": 0.15
		},
		"param_map": {
			"reward_flag": "reward_returning_crescent",
			"stack_property": "returning_crescent_stacks",
			"parameters": {
				"damage_scale": {"property": "returning_crescent_damage_scale", "type": "float"},
				"reach_scale": {"property": "returning_crescent_reach_scale", "type": "float"}
			}
		}
	},
	"sigil_chain": {
		"stack_limit": 3,
		"balance_params": {
			"radius_base": 70.0,
			"radius_per_stack": 14.0,
			"damage_ratio_base": 0.18,
			"damage_ratio_per_stack": 0.10,
			"charge_threshold": 4,
			"zone_lifetime": 1.0,
			"tick_interval": 0.4,
			"chain_window": 4.0,
			"slow_at_stack": 2,
			"slow_duration": 0.5,
			"slow_mult": 0.7,
			"chain_bonus_at_stack": 3,
			"chain_bonus_per_depth": 0.40,
			"chain_bonus_max_depth": 6
		},
		"param_map": {
			"reward_flag": "reward_sigil_chain",
			"stack_property": "sigil_chain_stacks",
			"parameters": {
				"radius": {"property": "sigil_chain_radius", "type": "float"},
				"damage_ratio": {"property": "sigil_chain_damage_ratio", "type": "float"}
			}
		}
	}
}

const BOSS_REWARD_STACK_LIMITS := {
	"shatterwake": 2,
	"wardens_verdict": 2,
	"lacuna_echo": 2,
	"sovereign_tempo": 2,
	"pillar_convergence": 2,
	"unbroken_oath": 2,
	"edict_of_the_court": 2,
	"null_corridor": 2,
	"ruinous_impact": 2,
	"sovereigns_double": 2
}

# Unified power data structure
class Power:
	var id: String  # Unique identifier: "swift_strike", "razor_wind", etc
	var name: String  # Display name: "Swift Strike"
	var description: String  # Card text
	var power_type: String  # POWER_TYPE_UPGRADE or POWER_TYPE_TRIAL
	var stack_limit: int  # Max times this power can be taken (0 = unlimited)
	var metadata: Dictionary  # Additional fields: scaling params, effect ranges, etc
	
	func _init(p_id: String, p_name: String, p_desc: String, p_type: String, p_stack_limit: int = 0, p_metadata: Dictionary = {}) -> void:
		id = p_id
		name = p_name
		description = p_desc
		power_type = p_type
		stack_limit = p_stack_limit
		metadata = p_metadata.duplicate()
	
	func to_dict() -> Dictionary:
		return {
			"id": id,
			"name": name,
			"desc": description,
			"type": power_type,
			"stack_limit": stack_limit,
			"metadata": metadata.duplicate(true)
		}


const POWER_DISPLAY_CATEGORY_BOSS_REWARD := "boss_reward"

## Canonical display metadata for all powers.
## This supersedes ad-hoc name match blocks in UI scripts.
const POWER_DISPLAY_METADATA := {
	"patient_hunter": {"name": "Patient Hunter", "category": POWER_TYPE_UPGRADE},
	"marked_prey": {"name": "Marked Prey", "category": POWER_TYPE_UPGRADE},
	"farshot": {"name": "Farshot", "category": POWER_TYPE_UPGRADE},
	"stormbrand": {"name": "Stormbrand", "category": POWER_TYPE_TRIAL},
	"spark_relay": {"name": "Spark Relay", "category": POWER_TYPE_TRIAL},
	"shatterwake": {"name": "Shatterwake", "category": POWER_DISPLAY_CATEGORY_BOSS_REWARD},
	# Upgrades
	"first_strike": {"name": "First Strike", "category": POWER_TYPE_UPGRADE},
	"heavy_blow": {"name": "Heavy Blow", "category": POWER_TYPE_UPGRADE},
	"wide_arc": {"name": "Wide Arc", "category": POWER_TYPE_UPGRADE},
	"long_reach": {"name": "Long Reach", "category": POWER_TYPE_UPGRADE},
	"fleet_foot": {"name": "Fleet Foot", "category": POWER_TYPE_UPGRADE},
	"blink_dash": {"name": "Blink Dash", "category": POWER_TYPE_UPGRADE},
	"iron_skin": {"name": "Iron Skin", "category": POWER_TYPE_UPGRADE},
	"battle_trance": {"name": "Battle Trance", "category": POWER_TYPE_UPGRADE},
	"surge_step": {"name": "Surge Step", "category": POWER_TYPE_UPGRADE},
	"heartstone": {"name": "Heartstone", "category": POWER_TYPE_UPGRADE},
	"bloodpact": {"name": "Blood Pact", "category": POWER_TYPE_UPGRADE},
	"severing_edge": {"name": "Severing Edge", "category": POWER_TYPE_UPGRADE},
	# Trial powers
	"razor_wind": {"name": "Razor Wind", "category": POWER_TYPE_TRIAL},
	"execution_edge": {"name": "Execution Edge", "category": POWER_TYPE_TRIAL},
	"rupture_wave": {"name": "Rupture Wave", "category": POWER_TYPE_TRIAL},
	"aegis_field": {"name": "Aegis Pulse", "category": POWER_TYPE_TRIAL},
	"hunters_snare": {"name": "Hunter's Snare", "category": POWER_TYPE_TRIAL},
	"phantom_step": {"name": "Phantom Step", "category": POWER_TYPE_TRIAL},
	"riftpunch": {"name": "Riftpunch", "category": POWER_TYPE_TRIAL},
	"reaper_step": {"name": "Reaper Step", "category": POWER_TYPE_TRIAL},
	"static_wake": {"name": "Static Wake", "category": POWER_TYPE_TRIAL},
	"storm_crown": {"name": "Storm Crown", "category": POWER_TYPE_TRIAL},
	"wraithstep": {"name": "Wraithstep", "category": POWER_TYPE_TRIAL},
	"voidfire": {"name": "Voidfire", "category": POWER_TYPE_TRIAL},
	"dread_resonance": {"name": "Dread Resonance", "category": POWER_TYPE_TRIAL},
	"bloodvow": {"name": "Blood Vow", "category": POWER_TYPE_TRIAL},
	"eclipse_mark": {"name": "Eclipse Mark", "category": POWER_TYPE_TRIAL},
	"fracture_field": {"name": "Fracture", "category": POWER_TYPE_TRIAL},
	"farline_volley": {"name": "Farline Volley", "category": POWER_TYPE_TRIAL},
	"sigil_chain": {"name": "Sigil Chain", "category": POWER_TYPE_TRIAL},
	"blast_drive": {"name": "Blast Drive", "category": POWER_TYPE_TRIAL},
	"razor_orbit": {"name": "Razor Orbit", "category": POWER_TYPE_TRIAL},
	"returning_crescent": {"name": "Returning Crescent", "category": POWER_TYPE_TRIAL},
	# Boss rewards
	"wardens_verdict": {"name": "Warden's Verdict", "category": POWER_DISPLAY_CATEGORY_BOSS_REWARD},
	"lacuna_echo": {"name": "Lacuna Well", "category": POWER_DISPLAY_CATEGORY_BOSS_REWARD},
	"sovereign_tempo": {"name": "Sovereign Tempo", "category": POWER_DISPLAY_CATEGORY_BOSS_REWARD},
	"pillar_convergence": {"name": "Faultline Seal", "category": POWER_DISPLAY_CATEGORY_BOSS_REWARD},
	"unbroken_oath": {"name": "Unbroken Oath", "category": POWER_DISPLAY_CATEGORY_BOSS_REWARD},
	"edict_of_the_court": {"name": "Edict of the Court", "category": POWER_DISPLAY_CATEGORY_BOSS_REWARD},
	"null_corridor": {"name": "Null Corridor", "category": POWER_DISPLAY_CATEGORY_BOSS_REWARD},
	"ruinous_impact": {"name": "Ruinous Impact", "category": POWER_DISPLAY_CATEGORY_BOSS_REWARD},
	"sovereigns_double": {"name": "Sovereign's Double", "category": POWER_DISPLAY_CATEGORY_BOSS_REWARD},
}

const POWER_ID_ALIASES := {
	"bastions_oath": "unbroken_oath"
}

## Ordered pool membership arrays — define which IDs belong to each pool and in what order
const UPGRADE_POOL_IDS: Array[String] = [
	"first_strike", "heavy_blow", "wide_arc", "long_reach", "fleet_foot",
	"blink_dash", "iron_skin", "battle_trance", "surge_step", "heartstone",
	"bloodpact", "severing_edge",
	"patient_hunter", "marked_prey",
	"farshot",
]

const TRIAL_POWER_POOL_IDS: Array[String] = [
	"razor_wind", "execution_edge", "rupture_wave", "aegis_field", "hunters_snare",
	"phantom_step", "riftpunch", "reaper_step", "static_wake", "storm_crown", "wraithstep",
	"voidfire", "dread_resonance", "bloodvow", "eclipse_mark", "fracture_field",
	"farline_volley", "sigil_chain", "blast_drive", "razor_orbit", "returning_crescent",
	"stormbrand", "spark_relay",
]

const BOSS_REWARD_POOL_IDS: Array[String] = [
	"wardens_verdict", "lacuna_echo", "sovereign_tempo", "pillar_convergence", "unbroken_oath",
	"edict_of_the_court", "null_corridor", "ruinous_impact", "sovereigns_double",
	"shatterwake",
]


## Worst-case maximum picks the run can offer per pool. If the sum of stack limits
## ever drops below these, the reward UI can run out of legal cards.
const MAX_BOON_PICKS_PER_RUN := 21
const MAX_BOSS_REWARD_PICKS_PER_RUN := 2
const MAX_ARCANA_PICKS_PER_RUN := 21


func _ready() -> void:
	_assert_pool_capacities()
	_validate_trial_power_definitions()


func _validate_trial_power_definitions() -> void:
	"""Ensures all trial powers in TRIAL_POWER_POOL_IDS have complete definitions."""
	for power_id in TRIAL_POWER_POOL_IDS:
		assert(TRIAL_POWER_DEFINITIONS.has(power_id), "Trial power '%s' in pool but missing TRIAL_POWER_DEFINITIONS" % power_id)
		
		var def = TRIAL_POWER_DEFINITIONS[power_id] as Dictionary
		assert(def.has("stack_limit"), "Trial power '%s' missing stack_limit in TRIAL_POWER_DEFINITIONS" % power_id)
		assert(def.has("balance_params"), "Trial power '%s' missing balance_params in TRIAL_POWER_DEFINITIONS" % power_id)
		assert(def.has("param_map"), "Trial power '%s' missing param_map in TRIAL_POWER_DEFINITIONS" % power_id)
		
		var balance = def.get("balance_params", {}) as Dictionary
		assert(not balance.is_empty(), "Trial power '%s' has empty balance_params" % power_id)
		
		var param_map = def.get("param_map", {}) as Dictionary
		assert(not param_map.is_empty(), "Trial power '%s' has empty param_map" % power_id)
		assert(param_map.has("reward_flag"), "Trial power '%s' param_map missing reward_flag" % power_id)
		assert(param_map.has("stack_property"), "Trial power '%s' param_map missing stack_property" % power_id)
		assert(param_map.has("parameters"), "Trial power '%s' param_map missing parameters" % power_id)


func _assert_pool_capacities() -> void:
	var boon_capacity := _sum_pool_capacity(UPGRADE_POOL_IDS, UPGRADE_STACK_LIMITS)
	var boss_capacity := _sum_pool_capacity(BOSS_REWARD_POOL_IDS, BOSS_REWARD_STACK_LIMITS)
	# Build trial power stack limits from unified definitions
	var trial_limits := {}
	for power_id in TRIAL_POWER_POOL_IDS:
		if TRIAL_POWER_DEFINITIONS.has(power_id):
			var def = TRIAL_POWER_DEFINITIONS[power_id] as Dictionary
			trial_limits[power_id] = def.get("stack_limit", 0)
	var arcana_capacity := _sum_pool_capacity(TRIAL_POWER_POOL_IDS, trial_limits)
	assert(boon_capacity >= MAX_BOON_PICKS_PER_RUN, "Boon pool capacity %d < max picks %d - players can run out of cards" % [boon_capacity, MAX_BOON_PICKS_PER_RUN])
	assert(boss_capacity >= MAX_BOSS_REWARD_PICKS_PER_RUN, "Boss reward pool capacity %d < max picks %d - players can run out of cards" % [boss_capacity, MAX_BOSS_REWARD_PICKS_PER_RUN])
	assert(arcana_capacity >= MAX_ARCANA_PICKS_PER_RUN, "Arcana pool capacity %d < max picks %d - players can run out of cards" % [arcana_capacity, MAX_ARCANA_PICKS_PER_RUN])
	for id in UPGRADE_POOL_IDS:
		assert(UPGRADE_STACK_LIMITS.has(id), "Boon '%s' is in UPGRADE_POOL_IDS but missing UPGRADE_STACK_LIMITS entry" % id)
	for id in TRIAL_POWER_POOL_IDS:
		assert(TRIAL_POWER_DEFINITIONS.has(id), "Arcana '%s' is in TRIAL_POWER_POOL_IDS but missing TRIAL_POWER_DEFINITIONS entry" % id)
	for id in BOSS_REWARD_POOL_IDS:
		assert(BOSS_REWARD_STACK_LIMITS.has(id), "Boss reward '%s' is in BOSS_REWARD_POOL_IDS but missing BOSS_REWARD_STACK_LIMITS entry" % id)


func _sum_pool_capacity(pool_ids: Array, limits: Dictionary) -> int:
	var total := 0
	for id in pool_ids:
		total += int(limits.get(id, 0))
	return total


func _build_power_pool(ids: Array, power_type: String, player_reference: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in ids:
		var display_name := get_power_display_name(id)
		var desc := ""
		if is_instance_valid(player_reference):
			if power_type == POWER_TYPE_TRIAL:
				desc = String(player_reference.get_trial_power_card_desc(id))
			else:
				desc = String(player_reference.get_upgrade_card_desc(id))
		result.append(Power.new(id, display_name, desc, power_type, get_power_stack_limit(id), get_power_balance(id)).to_dict())
	return result


## Return all upgrades (stat boosts)
func get_upgrade_pool(player_reference: Node = null) -> Array[Dictionary]:
	return _build_power_pool(UPGRADE_POOL_IDS, POWER_TYPE_UPGRADE, player_reference)


## Return all trial powers (combat abilities)
func get_trial_power_pool(player_reference: Node = null) -> Array[Dictionary]:
	return _build_power_pool(TRIAL_POWER_POOL_IDS, POWER_TYPE_TRIAL, player_reference)


func get_objective_upgrade_pool(player_reference: Node = null) -> Array[Dictionary]:
	var pool := get_upgrade_pool(player_reference)
	var favored_ids := {
		"first_strike": true,
		"heavy_blow": true,
		"long_reach": true,
		"fleet_foot": true,
		"blink_dash": true,
		"battle_trance": true,
		"surge_step": true,
	}
	var favored: Array[Dictionary] = []
	var fallback: Array[Dictionary] = []
	for entry in pool:
		if favored_ids.has(String(entry.get("id", ""))):
			favored.append(entry)
		else:
			fallback.append(entry)
	favored.append_array(fallback)
	return favored


## Return boss-exclusive reward pool
func get_boss_reward_pool(player_reference: Node = null) -> Array[Dictionary]:
	return _build_power_pool(BOSS_REWARD_POOL_IDS, POWER_TYPE_UPGRADE, player_reference)


## Get all powers (upgrades + trial powers)
func get_all_powers(player_reference: Node = null) -> Array[Dictionary]:
	var all_powers: Array[Dictionary] = []
	all_powers.append_array(get_upgrade_pool(player_reference))
	all_powers.append_array(get_boss_reward_pool(player_reference))
	all_powers.append_array(get_trial_power_pool(player_reference))
	return all_powers


## Get boss epitaph line for a defeated boss
func get_boss_epitaph(boss_id: String, character_id: String = "") -> String:
	var boss_key := boss_id.strip_edges().to_lower()
	if not BOSS_EPITAPHS.has(boss_key):
		return ""
	var epitaph_dict: Variant = BOSS_EPITAPHS[boss_key]
	if epitaph_dict is Dictionary:
		var char_key := character_id.strip_edges().to_lower()
		if not char_key.is_empty() and epitaph_dict.has(char_key):
			return String(epitaph_dict[char_key])
		if epitaph_dict.has("default"):
			return String(epitaph_dict["default"])
		return ""
	return String(epitaph_dict)


func _normalize_power_id_for_display(power_id: String) -> String:
	var normalized := power_id.strip_edges().to_lower()
	if POWER_ID_ALIASES.has(normalized):
		return String(POWER_ID_ALIASES[normalized])
	return normalized


func get_power_display_metadata(power_id: String) -> Dictionary:
	var normalized := _normalize_power_id_for_display(power_id)
	if POWER_DISPLAY_METADATA.has(normalized):
		return (POWER_DISPLAY_METADATA[normalized] as Dictionary).duplicate(true)
	return {}


func get_power_display_name(power_id: String) -> String:
	var metadata := get_power_display_metadata(power_id)
	if not metadata.is_empty():
		var name := String(metadata.get("name", "")).strip_edges()
		if not name.is_empty():
			return name
	var normalized := _normalize_power_id_for_display(power_id)
	if normalized.is_empty():
		return ""
	return normalized.capitalize()


## Check if a power ID exists
func is_valid_power_id(power_id: String) -> bool:
	var normalized := _normalize_power_id_for_display(power_id)
	return POWER_DISPLAY_METADATA.has(normalized)


## Check if a power ID is an upgrade
func is_upgrade(power_id: String) -> bool:
	var id := _normalize_power_id_for_display(power_id)
	return UPGRADE_POOL_IDS.has(id) or BOSS_REWARD_POOL_IDS.has(id)


## Check if a power ID is a trial power
func is_trial_power(power_id: String) -> bool:
	return TRIAL_POWER_POOL_IDS.has(_normalize_power_id_for_display(power_id))


## Get power by ID
func get_power(power_id: String) -> Dictionary:
	var id := _normalize_power_id_for_display(power_id)
	for power in get_all_powers():
		if power["id"] == id:
			return power.duplicate()
	return {}


func get_power_balance(power_id: String) -> Dictionary:
	var id := power_id.strip_edges().to_lower()
	if UPGRADE_BALANCE.has(id):
		return (UPGRADE_BALANCE[id] as Dictionary).duplicate(true)
	if TRIAL_POWER_DEFINITIONS.has(id):
		var def = TRIAL_POWER_DEFINITIONS[id] as Dictionary
		var balance = def.get("balance_params", {}) as Dictionary
		return balance.duplicate(true)
	if BOSS_REWARD_BALANCE.has(id):
		return (BOSS_REWARD_BALANCE[id] as Dictionary).duplicate(true)
	return {}


func get_power_stack_limit(power_id: String) -> int:
	var id := power_id.strip_edges().to_lower()
	if UPGRADE_STACK_LIMITS.has(id):
		return int(UPGRADE_STACK_LIMITS[id])
	if TRIAL_POWER_DEFINITIONS.has(id):
		var def = TRIAL_POWER_DEFINITIONS[id] as Dictionary
		return int(def.get("stack_limit", 0))
	if BOSS_REWARD_STACK_LIMITS.has(id):
		return int(BOSS_REWARD_STACK_LIMITS[id])
	return 0


func get_damage_model(power_id: String) -> Dictionary:
	var id := power_id.strip_edges().to_lower()
	if DAMAGE_MODEL_BY_POWER.has(id):
		return (DAMAGE_MODEL_BY_POWER[id] as Dictionary).duplicate(true)
	return {
		"kind": DAMAGE_KIND_NONE,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "No direct damage"
	}


func get_damage_model_label(power_id: String) -> String:
	var model := get_damage_model(power_id)
	match String(model.get("kind", DAMAGE_KIND_NONE)):
		DAMAGE_KIND_FLAT:
			return "Flat"
		DAMAGE_KIND_SCALING:
			return "Scaling"
		DAMAGE_KIND_HYBRID:
			return "Hybrid"
		_:
			return "None"


## Trial Power Access Helpers
## Centralized accessors for unified TRIAL_POWER_DEFINITIONS

func get_trial_power_definition(power_id: String) -> Dictionary:
	"""Returns the complete trial power definition including balance params, stack limit, and param map."""
	var def := _get_trial_power_definition(power_id)
	return def.duplicate(true) if not def.is_empty() else {}


func get_trial_power_param_map(power_id: String) -> Dictionary:
	"""Returns the parameter mapping configuration for a trial power (reward_flag, stack_property, parameters)."""
	var def := _get_trial_power_definition(power_id)
	if def.is_empty():
		return {}
	var param_map := def.get("param_map", {}) as Dictionary
	return param_map.duplicate(true) if not param_map.is_empty() else {}


func _get_trial_power_definition(power_id: String) -> Dictionary:
	"""Private helper: fetch trial power definition from unified registry."""
	var id := power_id.strip_edges().to_lower()
	if TRIAL_POWER_DEFINITIONS.has(id):
		return TRIAL_POWER_DEFINITIONS[id] as Dictionary
	return {}


func _damage_kind_bracket(_power_id: String) -> String:
	return ""

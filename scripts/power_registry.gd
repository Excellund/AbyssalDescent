## Centralized power registry and unified data structure
## All upgrades (stat boosts) and trial powers (combat abilities) are defined here
## This is the single source of truth for what powers exist and their metadata

extends Node

const DESCRIPTION_CAP_GUARD := preload("res://scripts/shared/description_cap_guard.gd")

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
		"default": "Sovereign's reign ends. Only Lacuna stands."
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
	# Upgrades
	"first_strike": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X extra hit damage vs enemies above 80% HP"
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
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X against slowed targets"
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
		"formula_note": "Flat marked-hit bonus + scaling splash/chain"
	},
	# Voidfire archetype
	"voidfire": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Y% of hit damage on detonation burst"
	},
	"dread_resonance": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X per resonance stack on same target"
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
	# Character-lore bridges
	"bloodvow": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Hit damage multiplied while player is below the wounded threshold"
	},
	"eclipse_mark": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Y% bonus damage on first hit vs marked enemy"
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
		"formula_note": "+X flat damage on every hit while below 50% HP"
	},
	"severing_edge": {
		"kind": DAMAGE_KIND_FLAT,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "+X bonus damage on hits against enemies below 55% HP"
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
		"formula_note": "Hit stacks convert into dash-finish momentum wave damage"
	},
	"pillar_convergence": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_HIT,
		"formula_note": "Every N damaging hits, enter Convergence for ~1.6-2.0s and pulse around player for ~46%-63% damage"
	},
	"unbroken_oath": {
		"kind": DAMAGE_KIND_HYBRID,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Single-target hits trickle Oath; multihits scale exponentially. Fill bar to prime next-hit sword strike"
	},
	"edict_of_the_court": {
		"kind": DAMAGE_KIND_NONE,
		"scale_source": DAMAGE_SCALE_SOURCE_NONE,
		"formula_note": "Emits force pulse from kill position, scattering nearby enemies outward"
	},
	"null_corridor": {
		"kind": DAMAGE_KIND_SCALING,
		"scale_source": DAMAGE_SCALE_SOURCE_DAMAGE,
		"formula_note": "Dash path becomes deflection zone; enemies crossing the trail are pushed hard and take ~20-24% of damage stat once per crossing (0.5s re-entry cooldown)"
	}
}

const UPGRADE_BALANCE := {
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
	}
}

const UPGRADE_STACK_LIMITS := {
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
			"cooldown_base": 3.2,
			"cooldown_per_stack": -0.30,
			"cooldown_min": 1.5
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
			"bonus_damage_base": 4,
			"bonus_damage_per_stack": 4,
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
				"bonus_damage": {"property": "hunters_snare_bonus_damage", "type": "int"},
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
			"bonus_damage_base": 8,
			"bonus_damage_per_stack": 8,
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
				"bonus_damage": {"property": "wraithstep_mark_bonus_damage", "type": "int"},
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
			"bonus_per_stack_base": 0,
			"bonus_per_stack_per_level": 1,
			"max_stacks_base": 6,
			"max_stacks_per_stack": 2,
			"max_stacks_cap": 12
		},
		"param_map": {
			"reward_flag": "reward_dread_resonance",
			"stack_property": "dread_resonance_stacks",
			"parameters": {
				"bonus_per_stack": {"property": "dread_resonance_bonus_per_stack", "type": "int"},
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
			"mark_duration_per_stack": 0.6,
			"bonus_ratio_base": 0.25,
			"bonus_ratio_per_stack": 0.10
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
	"wardens_verdict": 2,
	"lacuna_echo": 2,
	"sovereign_tempo": 2,
	"pillar_convergence": 2,
	"unbroken_oath": 2,
	"edict_of_the_court": 2,
	"null_corridor": 2
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
	"aegis_field": {"name": "Aegis Field", "category": POWER_TYPE_TRIAL},
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
	"fracture_field": {"name": "Fracture Field", "category": POWER_TYPE_TRIAL},
	"farline_volley": {"name": "Farline Volley", "category": POWER_TYPE_TRIAL},
	"sigil_chain": {"name": "Sigil Chain", "category": POWER_TYPE_TRIAL},
	# Boss rewards
	"wardens_verdict": {"name": "Warden's Verdict", "category": POWER_DISPLAY_CATEGORY_BOSS_REWARD},
	"lacuna_echo": {"name": "Lacuna Echo", "category": POWER_DISPLAY_CATEGORY_BOSS_REWARD},
	"sovereign_tempo": {"name": "Sovereign Tempo", "category": POWER_DISPLAY_CATEGORY_BOSS_REWARD},
	"pillar_convergence": {"name": "Pillar Convergence", "category": POWER_DISPLAY_CATEGORY_BOSS_REWARD},
	"unbroken_oath": {"name": "Unbroken Oath", "category": POWER_DISPLAY_CATEGORY_BOSS_REWARD},
	"edict_of_the_court": {"name": "Edict of the Court", "category": POWER_DISPLAY_CATEGORY_BOSS_REWARD},
	"null_corridor": {"name": "Null Corridor", "category": POWER_DISPLAY_CATEGORY_BOSS_REWARD},
}

const POWER_ID_ALIASES := {
	"bastions_oath": "unbroken_oath"
}

## Ordered pool membership arrays — define which IDs belong to each pool and in what order
const UPGRADE_POOL_IDS: Array[String] = [
	"first_strike", "heavy_blow", "wide_arc", "long_reach", "fleet_foot",
	"blink_dash", "iron_skin", "battle_trance", "surge_step", "heartstone",
	"bloodpact", "severing_edge",
]

const TRIAL_POWER_POOL_IDS: Array[String] = [
	"razor_wind", "execution_edge", "rupture_wave", "aegis_field", "hunters_snare",
	"phantom_step", "riftpunch", "reaper_step", "static_wake", "storm_crown", "wraithstep",
	"voidfire", "dread_resonance", "bloodvow", "eclipse_mark", "fracture_field",
	"farline_volley", "sigil_chain",
]

const BOSS_REWARD_POOL_IDS: Array[String] = [
	"wardens_verdict", "lacuna_echo", "sovereign_tempo", "pillar_convergence", "unbroken_oath",
	"edict_of_the_court", "null_corridor",
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

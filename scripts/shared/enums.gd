extends Node

# Global enums used by game systems to avoid magic strings/integers.
enum RunMode {
	STANDARD,
	ENDLESS,
}

enum RewardMode {
	NONE,
	BOON,
	OBJECTIVE,
	ARCANA,
	MISSION,
	BOSS,
}

const REWARD_MODE_NONE := RewardMode.NONE
const REWARD_MODE_BOON := RewardMode.BOON
const REWARD_MODE_ARCANA := RewardMode.ARCANA
const REWARD_MODE_MISSION := RewardMode.MISSION
const REWARD_MODE_BOSS := RewardMode.BOSS

enum DoorKind {
	ENCOUNTER,
	BOSS,
	REST,
}

enum EncounterAction {
	ENCOUNTER,
	BOSS,
	REST,
}

enum RoomState {
	INIT,
	PLAYING,
	CHOOSING_NEXT,
	CLEARED,
	BOSS,
	RUN_CLEARED,
}

enum EnemyType {
	CHASER,
	CHARGER,
	ARCHER,
	SHIELDER,
	BOSS,
}

enum PowerKind {
	UPGRADE,
	ARCANA,
}

enum Character {
	BASTION,
	HEXWEAVER,
	VEILSTRIDER,
	RIFTLANCER,
}

const CHARACTER_ID_BASTION := "bastion"
const CHARACTER_ID_HEXWEAVER := "hexweaver"
const CHARACTER_ID_VEILSTRIDER := "veilstrider"
const CHARACTER_ID_RIFTLANCER := "riftlancer"

# Passive IDs (character passives)
const PASSIVE_ID_IRON_RETORT := "iron_retort"
const PASSIVE_ID_SIGIL_BURST := "sigil_burst"
const PASSIVE_ID_VEILSTEP_RHYTHM := "veilstep_rhythm"
const PASSIVE_ID_FARLINE_FOCUS := "farline_focus"

# Power IDs (boons/upgrades)
const POWER_ID_FIRST_STRIKE := "first_strike"
const POWER_ID_HEAVY_BLOW := "heavy_blow"
const POWER_ID_WIDE_ARC := "wide_arc"
const POWER_ID_LONG_REACH := "long_reach"
const POWER_ID_FLEET_FOOT := "fleet_foot"
const POWER_ID_BLINK_DASH := "blink_dash"
const POWER_ID_IRON_SKIN := "iron_skin"
const POWER_ID_BATTLE_TRANCE := "battle_trance"
const POWER_ID_SURGE_STEP := "surge_step"
const POWER_ID_HEARTSTONE := "heartstone"
const POWER_ID_BLOODPACT := "bloodpact"
const POWER_ID_SEVERING_EDGE := "severing_edge"

# Power IDs (trial powers)
const POWER_ID_RAZOR_WIND := "razor_wind"
const POWER_ID_EXECUTION_EDGE := "execution_edge"
const POWER_ID_RUPTURE_WAVE := "rupture_wave"
const POWER_ID_AEGIS_FIELD := "aegis_field"
const POWER_ID_HUNTERS_SNARE := "hunters_snare"
const POWER_ID_PHANTOM_STEP := "phantom_step"
const POWER_ID_RIFTPUNCH := "riftpunch"
const POWER_ID_REAPER_STEP := "reaper_step"
const POWER_ID_STATIC_WAKE := "static_wake"
const POWER_ID_STORM_CROWN := "storm_crown"
const POWER_ID_WRAITHSTEP := "wraithstep"
const POWER_ID_VOIDFIRE := "voidfire"
const POWER_ID_DREAD_RESONANCE := "dread_resonance"
const POWER_ID_BLOODVOW := "bloodvow"
const POWER_ID_ECLIPSE_MARK := "eclipse_mark"
const POWER_ID_FRACTURE_FIELD := "fracture_field"
const POWER_ID_FARLINE_VOLLEY := "farline_volley"
const POWER_ID_SIGIL_CHAIN := "sigil_chain"

# Power IDs (boss rewards)
const POWER_ID_WARDENS_VERDICT := "wardens_verdict"
const POWER_ID_LACUNA_ECHO := "lacuna_echo"
const POWER_ID_SOVEREIGN_TEMPO := "sovereign_tempo"
const POWER_ID_PILLAR_CONVERGENCE := "pillar_convergence"
const POWER_ID_UNBROKEN_OATH := "unbroken_oath"
const POWER_ID_EDICT_OF_THE_COURT := "edict_of_the_court"
const POWER_ID_NULL_CORRIDOR := "null_corridor"

static func reward_mode_from_legacy(value: String) -> int:
	match value:
		"boon":
			return REWARD_MODE_BOON
		"objective", "objective_reward", "mission_reward":
			return REWARD_MODE_MISSION
		"arcana_reward", "trial_reward":
			return REWARD_MODE_ARCANA
		"boss", "boss_reward":
			return REWARD_MODE_BOSS
		"hard_reward":
			return REWARD_MODE_MISSION
		_:
			return REWARD_MODE_NONE

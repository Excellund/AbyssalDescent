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
}

const REWARD_MODE_NONE := RewardMode.NONE
const REWARD_MODE_BOON := RewardMode.BOON
const REWARD_MODE_ARCANA := RewardMode.ARCANA
const REWARD_MODE_MISSION := RewardMode.MISSION

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
}

const CHARACTER_ID_BASTION := "bastion"
const CHARACTER_ID_HEXWEAVER := "hexweaver"
const CHARACTER_ID_VEILSTRIDER := "veilstrider"

static func reward_mode_from_legacy(value: String) -> int:
	match value:
		"boon":
			return REWARD_MODE_BOON
		"objective", "objective_reward", "mission_reward":
			return REWARD_MODE_MISSION
		"arcana_reward", "trial_reward":
			return REWARD_MODE_ARCANA
		"hard_reward":
			return REWARD_MODE_MISSION
		_:
			return REWARD_MODE_NONE

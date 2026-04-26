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
	HARD,
}

const REWARD_MODE_NONE := RewardMode.NONE
const REWARD_MODE_BOON := RewardMode.BOON
const REWARD_MODE_ARCANA := RewardMode.ARCANA
const REWARD_MODE_HARD := RewardMode.HARD

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

static func reward_mode_from_legacy(value: String) -> int:
	match value:
		"boon":
			return REWARD_MODE_BOON
		"objective", "objective_reward", "mission_reward":
			return REWARD_MODE_HARD
		"arcana_reward", "trial_reward":
			return REWARD_MODE_ARCANA
		"hard_reward":
			return REWARD_MODE_HARD
		_:
			return REWARD_MODE_NONE

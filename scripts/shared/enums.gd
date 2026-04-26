extends Node

# Global enums used by game systems to avoid magic strings/integers.
enum RunMode {
	STANDARD,
	ENDLESS,
}

enum RewardMode {
	NONE,
	BOON,
	ARCANA,
	HARD,
}

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
			return RewardMode.BOON
		"arcana_reward", "trial_reward":
			return RewardMode.ARCANA
		"hard_reward":
			return RewardMode.HARD
		_:
			return RewardMode.NONE

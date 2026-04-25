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

static func reward_mode_to_legacy(value: int) -> String:
	match value:
		RewardMode.BOON:
			return "boon"
		RewardMode.ARCANA:
			return "arcana_reward"
		RewardMode.HARD:
			return "hard_reward"
		_:
			return "none"

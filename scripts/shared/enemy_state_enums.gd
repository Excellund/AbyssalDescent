extends Node

# Shared enemy state/attack enums to avoid per-file magic integer ladders.
enum ChargerState {
	SEEK,
	WINDUP,
	CHARGE,
	RECOVER,
}

enum ArcherState {
	SEEK,
	WINDUP,
	FIRE,
	RECOVER,
}

enum ShielderSlamState {
	IDLE,
	WINDUP,
	THUMP,
	RECOVER,
}

enum LancerState {
	STALK,
	WINDUP,
	FIRE,
	REPOSITION,
}

enum RamState {
	SEEK,
	WINDUP,
	CHARGE,
	CHARGE_PAUSE,
	RECOVER,
}

enum LurkerState {
	STALK,
	LURK,
	STRIKE,
	RECOVER,
}

enum BossState {
	IDLE,
	TELEGRAPH,
	ATTACK,
	RECOVER,
}

enum BossAttack {
	CHARGE,
	NOVA,
	CLEAVE,
}

enum Boss2State {
	STALK,
	WINDUP,
	ATTACK,
	RECOVER,
}

enum Boss2Attack {
	PRISM,
	GRAVITY,
	ECHO_DASH,
	ORBITAL_LANCE,
	POLAR_SHIFT,
}

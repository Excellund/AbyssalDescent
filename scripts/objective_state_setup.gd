extends RefCounted

const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")

func clear_world_state(world: Node) -> void:
	world.active_objective_kind = ""
	world.objective_time_left = 0.0
	world.objective_spawn_interval = 0.0
	world.objective_spawn_timer = 0.0
	world.objective_spawn_batch = 1
	world.objective_max_enemies = 0
	world.objective_kill_target = 0
	world.objective_kills = 0
	world.objective_overtime = false
	world.objective_survival_quota_announced = false
	world.objective_target_enemy = null
	world.objective_target_type = ""
	world.objective_target_name = ""
	world.objective_hunt_kill_progress = 0
	world.objective_control_anchor = Vector2.ZERO
	world.objective_control_radius = 0.0
	world.objective_control_progress = 0.0
	world.objective_control_goal = 0.0
	world.objective_control_decay_rate = 0.0
	world.objective_control_contest_threshold = 0
	world.objective_control_enemies_in_zone = 0
	world.objective_control_player_inside = false
	world.objective_control_contested = false
	world.objective_exposure_left = 0.0
	world.objective_exposure_push_left = 0.0
	world.objective_last_relocated_escort_count = 0
	world.objective_relocation_hint_left = 0.0

func activate_profile_objective_kind(world: Node, profile: Dictionary) -> void:
	world.active_objective_kind = ENCOUNTER_CONTRACTS.profile_objective_kind(profile)

func apply_survival_setup(world: Node, profile: Dictionary, spawn_interval: float, spawn_timer: float, spawn_batch: int, max_enemies: int, kill_target: int) -> void:
	_apply_common_setup(world, profile, spawn_interval, spawn_timer, spawn_batch, max_enemies)
	world.objective_kill_target = kill_target
	world.objective_kills = 0
	world.objective_survival_quota_announced = false

func apply_priority_target_setup(world: Node, profile: Dictionary, target_type: String, target_name: String, spawn_interval: float, spawn_timer: float, spawn_batch: int, max_enemies: int, hunt_kill_goal: int) -> void:
	_apply_common_setup(world, profile, spawn_interval, spawn_timer, spawn_batch, max_enemies)
	world.objective_target_type = target_type
	world.objective_target_name = target_name
	world.objective_hunt_kill_goal = hunt_kill_goal

func apply_control_setup(world: Node, profile: Dictionary, spawn_interval: float, spawn_timer: float, spawn_batch: int, max_enemies: int, control_radius: float, control_goal: float, control_decay_rate: float, control_contest_threshold: int) -> void:
	_apply_common_setup(world, profile, spawn_interval, spawn_timer, spawn_batch, max_enemies)
	world.objective_control_anchor = Vector2.ZERO
	world.objective_control_radius = control_radius
	world.objective_control_progress = 0.0
	world.objective_control_goal = control_goal
	world.objective_control_decay_rate = control_decay_rate
	world.objective_control_contest_threshold = control_contest_threshold
	world.objective_control_enemies_in_zone = 0
	world.objective_control_player_inside = false
	world.objective_control_contested = false
	world.objective_control_kill_baseline = world.objective_kills

func _apply_common_setup(world: Node, profile: Dictionary, spawn_interval: float, spawn_timer: float, spawn_batch: int, max_enemies: int) -> void:
	world.objective_time_left = ENCOUNTER_CONTRACTS.profile_objective_duration(profile)
	world.objective_spawn_interval = spawn_interval
	world.objective_spawn_timer = spawn_timer
	world.objective_spawn_batch = spawn_batch
	world.objective_max_enemies = max_enemies
	world.objective_overtime = false
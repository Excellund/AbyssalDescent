extends RefCounted

const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")

func clear_world_state(objective_manager: Node) -> void:
	objective_manager.reset()

func activate_profile_objective_kind(objective_manager: Node, profile: Dictionary) -> void:
	objective_manager.active_objective_kind = ENCOUNTER_CONTRACTS.profile_objective_kind(profile)

func apply_survival_setup(objective_manager: Node, profile: Dictionary, spawn_interval: float, spawn_timer: float, spawn_batch: int, max_enemies: int, kill_target: int) -> void:
	_apply_common_setup(objective_manager, profile, spawn_interval, spawn_timer, spawn_batch, max_enemies)
	objective_manager.kill_target = kill_target
	objective_manager.kills = 0
	objective_manager.survival_quota_announced = false

func apply_priority_target_setup(objective_manager: Node, profile: Dictionary, target_type: String, target_name: String, spawn_interval: float, spawn_timer: float, spawn_batch: int, max_enemies: int, hunt_kill_goal: int) -> void:
	_apply_common_setup(objective_manager, profile, spawn_interval, spawn_timer, spawn_batch, max_enemies)
	objective_manager.hunt_target_type = target_type
	objective_manager.hunt_target_name = target_name
	objective_manager.hunt_target_kill_goal = hunt_kill_goal

func apply_control_setup(objective_manager: Node, profile: Dictionary, spawn_interval: float, spawn_timer: float, spawn_batch: int, max_enemies: int, control_radius: float, control_goal: float, control_decay_rate: float, control_contest_threshold: int) -> void:
	_apply_common_setup(objective_manager, profile, spawn_interval, spawn_timer, spawn_batch, max_enemies)
	objective_manager.control_anchor = Vector2.ZERO
	objective_manager.control_radius = control_radius
	objective_manager.control_progress = 0.0
	objective_manager.control_goal = control_goal
	objective_manager.control_decay_rate = control_decay_rate
	objective_manager.control_contest_threshold = control_contest_threshold
	objective_manager.control_enemies_in_zone = 0
	objective_manager.control_player_inside = false
	objective_manager.control_contested = false
	objective_manager.control_kill_baseline = objective_manager.kills
	objective_manager.control_unbroken = true

func _apply_common_setup(objective_manager: Node, profile: Dictionary, spawn_interval: float, spawn_timer: float, spawn_batch: int, max_enemies: int) -> void:
	objective_manager.time_left = ENCOUNTER_CONTRACTS.profile_objective_duration(profile)
	objective_manager.spawn_interval = spawn_interval
	objective_manager.spawn_timer = spawn_timer
	objective_manager.spawn_batch = spawn_batch
	objective_manager.max_enemies = max_enemies
	objective_manager.overtime = false

func apply_circuit_sweep_setup(objective_manager: Node, profile: Dictionary, spawn_interval: float, spawn_timer: float, spawn_batch: int, max_enemies: int, node_count: int, capture_goal: float, node_radius: float) -> void:
	_apply_common_setup(objective_manager, profile, spawn_interval, spawn_timer, spawn_batch, max_enemies)
	objective_manager.sweep_node_count = maxi(1, node_count)
	objective_manager.sweep_nodes_completed = 0
	objective_manager.sweep_capture_progress = 0.0
	objective_manager.sweep_capture_goal = maxf(0.5, capture_goal)
	objective_manager.sweep_node_position = Vector2.ZERO
	objective_manager.sweep_node_radius = maxf(32.0, node_radius)

func apply_pulse_window_setup(objective_manager: Node, profile: Dictionary, spawn_interval: float, spawn_timer: float, spawn_batch: int, max_enemies: int, kill_target: int, pulse_interval: float) -> void:
	_apply_common_setup(objective_manager, profile, spawn_interval, spawn_timer, spawn_batch, max_enemies)
	objective_manager.kill_target = kill_target
	objective_manager.kills = 0
	objective_manager.survival_quota_announced = false
	objective_manager.pulse_next_timer = pulse_interval
	objective_manager.pulse_interval = pulse_interval
	objective_manager.pulse_active = false
	objective_manager.pulse_active_timer = 0.0
	objective_manager.pulse_count = 0

func apply_intercept_run_setup(objective_manager: Node, profile: Dictionary, spawn_interval: float, spawn_timer: float, spawn_batch: int, max_enemies: int, drone_speed: float, drone_radius: float) -> void:
	_apply_common_setup(objective_manager, profile, spawn_interval, spawn_timer, spawn_batch, max_enemies)
	objective_manager.intercept_drone_progress = 0.0
	objective_manager.intercept_drone_position = Vector2.ZERO
	objective_manager.intercept_start = Vector2.ZERO
	objective_manager.intercept_end = Vector2.ZERO
	objective_manager.intercept_drone_speed = maxf(0.001, drone_speed)
	objective_manager.intercept_enemies_near_drone = 0
	objective_manager.intercept_drone_stalled = false
	objective_manager.intercept_drone_radius = maxf(32.0, drone_radius)
	objective_manager.intercept_escort_radius = 240.0
	objective_manager.intercept_player_in_escort_zone = true

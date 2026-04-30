extends RefCounted

static func _to_string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for entry in value:
			out.append(String(entry))
	return out

static func build_snapshot(world: Node, player: Node, run_context: Node, snapshot_version: int, fallback_run_mode: Variant) -> Dictionary:
	if not is_instance_valid(player):
		return {}
	var run_mode_value: Variant = fallback_run_mode
	if run_context != null:
		var context_mode: Variant = run_context.get("run_mode")
		if context_mode != null:
			run_mode_value = context_mode
	var player_snapshot: Dictionary = {}
	if player.has_method("build_run_snapshot"):
		player_snapshot = player.build_run_snapshot() as Dictionary
	return {
		"version": snapshot_version,
		"run_mode": run_mode_value,
		"rooms_cleared": world.rooms_cleared,
		"room_depth": world.room_depth,
		"active_room_enemy_count": world.active_room_enemy_count,
		"boss_unlocked": world.boss_unlocked,
		"in_boss_room": world.in_boss_room,
		"in_second_boss_room": world.in_second_boss_room,
		"first_boss_defeated": world.first_boss_defeated,
		"phase_two_rooms_cleared": world.phase_two_rooms_cleared,
		"endless_boss_defeated": world.endless_boss_defeated,
		"choosing_next_room": world.choosing_next_room,
		"run_cleared": world.run_cleared,
		"boons_taken": world.boons_taken.duplicate(),
		"arcana_rewards_taken": world.arcana_rewards_taken.duplicate(),
		"current_room_size": world.current_room_size,
		"current_room_static_camera": world.current_room_static_camera,
		"current_room_label": world.current_room_label,
		"door_options": world.door_options.duplicate(true),
		"pending_room_reward": world.pending_room_reward,
		"current_room_enemy_mutator": world.current_room_enemy_mutator.duplicate(true),
		"current_room_player_mutator": world.current_room_player_mutator.duplicate(true),
		"active_objective_kind": world.active_objective_kind,
		"objective_time_left": world.objective_time_left,
		"objective_spawn_interval": world.objective_spawn_interval,
		"objective_spawn_timer": world.objective_spawn_timer,
		"objective_spawn_batch": world.objective_spawn_batch,
		"objective_max_enemies": world.objective_max_enemies,
		"objective_kill_target": world.objective_kill_target,
		"objective_kills": world.objective_kills,
		"objective_overtime": world.objective_overtime,
		"objective_survival_quota_announced": world.objective_survival_quota_announced,
		"current_difficulty_tier": world.current_difficulty_tier,
		"player_snapshot": player_snapshot
	}

static func apply_snapshot(world: Node, player: Node, run_context: Node, snapshot: Dictionary, room_base_size: Vector2, fallback_run_mode: Variant, reward_mode_none: int) -> bool:
	if not is_instance_valid(player):
		return false
	if run_context != null and run_context.has_method("set_run_mode"):
		run_context.set_run_mode(snapshot.get("run_mode", fallback_run_mode))

	world.rooms_cleared = int(snapshot.get("rooms_cleared", world.rooms_cleared))
	world.room_depth = int(snapshot.get("room_depth", world.room_depth))
	world.active_room_enemy_count = 0
	world.boss_unlocked = bool(snapshot.get("boss_unlocked", world.boss_unlocked))
	world.in_boss_room = bool(snapshot.get("in_boss_room", false))
	world.in_second_boss_room = bool(snapshot.get("in_second_boss_room", false))
	world.first_boss_defeated = bool(snapshot.get("first_boss_defeated", world.first_boss_defeated))
	world.phase_two_rooms_cleared = int(snapshot.get("phase_two_rooms_cleared", world.phase_two_rooms_cleared))
	world.endless_boss_defeated = bool(snapshot.get("endless_boss_defeated", world.endless_boss_defeated))
	world.run_cleared = bool(snapshot.get("run_cleared", false))
	world.choosing_next_room = bool(snapshot.get("choosing_next_room", true))
	if not world.choosing_next_room:
		world.choosing_next_room = true

	world.boons_taken = _to_string_array(snapshot.get("boons_taken", []))
	world.arcana_rewards_taken = _to_string_array(snapshot.get("arcana_rewards_taken", []))
	world.current_room_size = snapshot.get("current_room_size", room_base_size) as Vector2
	world.current_room_static_camera = bool(snapshot.get("current_room_static_camera", true))
	world.current_room_label = String(snapshot.get("current_room_label", "Doorway"))
	var loaded_doors := snapshot.get("door_options", []) as Array
	world.door_options.clear()
	for door in loaded_doors:
		if door is Dictionary:
			world.door_options.append((door as Dictionary).duplicate(true))
	world.pending_room_reward = int(snapshot.get("pending_room_reward", reward_mode_none))
	world.current_room_enemy_mutator = snapshot.get("current_room_enemy_mutator", {}) as Dictionary
	world.current_room_player_mutator = snapshot.get("current_room_player_mutator", {}) as Dictionary

	world.active_objective_kind = String(snapshot.get("active_objective_kind", ""))
	world.objective_time_left = float(snapshot.get("objective_time_left", 0.0))
	world.objective_spawn_interval = float(snapshot.get("objective_spawn_interval", 0.0))
	world.objective_spawn_timer = float(snapshot.get("objective_spawn_timer", 0.0))
	world.objective_spawn_batch = int(snapshot.get("objective_spawn_batch", 1))
	world.objective_max_enemies = int(snapshot.get("objective_max_enemies", 0))
	world.objective_kill_target = int(snapshot.get("objective_kill_target", 0))
	world.objective_kills = int(snapshot.get("objective_kills", 0))
	world.objective_overtime = bool(snapshot.get("objective_overtime", false))
	world.objective_survival_quota_announced = bool(snapshot.get("objective_survival_quota_announced", false))
	world.current_difficulty_tier = int(snapshot.get("current_difficulty_tier", world.current_difficulty_tier))
	world.objective_target_enemy = null
	world.objective_target_type = ""
	world.objective_target_name = ""

	var player_snapshot := snapshot.get("player_snapshot", {}) as Dictionary
	if player.has_method("apply_run_snapshot"):
		player.apply_run_snapshot(player_snapshot)

	return true

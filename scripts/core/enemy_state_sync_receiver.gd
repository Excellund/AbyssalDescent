extends RefCounted

# Phase: world-generator-decomposition / Task: extract-enemy-state-sync-receiver
#
# Mirror of EnemyStateSyncBroadcaster: owns the joiner-side replication
# pipeline that was previously embedded in world_generator.gd. Applies
# host-authoritative payloads for door options, enemy spawn batches,
# objective spawn batches, boss spawn, enemy state ticks, and enemy death.
#
# RPC methods (`_sync_enemy_states`, `_sync_enemy_died`) remain on
# WorldGenerator because they are bound to the host node's authority; their
# bodies delegate here.

const ENEMY_REMOTE_SNAP_DISTANCE_PX_DEFAULT: float = 180.0

var enemy_remote_snap_distance_px: float = ENEMY_REMOTE_SNAP_DISTANCE_PX_DEFAULT

var _world: Node2D


func _init(world: Node2D) -> void:
	_world = world


# --- door sync --------------------------------------------------------------

func can_apply_door_sync() -> bool:
	if not MultiplayerSessionManager.is_remote_replica():
		return false
	if _world._world_multiplayer_sync_state.awaiting_authoritative_door_choice:
		return false
	if _world._is_reward_selection_active():
		return false
	if _world.current_room_label == "Starting Chamber":
		return false
	return true

func should_defer_door_sync_payload(synced_choosing_next_room: bool, progress_state: Dictionary) -> bool:
	if not MultiplayerSessionManager.is_remote_replica():
		return false
	if not synced_choosing_next_room:
		return false
	if _world._world_multiplayer_sync_state.awaiting_authoritative_door_choice:
		return false
	if not _world.choosing_next_room:
		return false
	if _world.door_options.is_empty():
		return false
	var incoming_rooms_cleared := int(progress_state.get("rooms_cleared", _world.rooms_cleared))
	var incoming_room_depth := int(progress_state.get("room_depth", _world.room_depth))
	return incoming_rooms_cleared != _world.rooms_cleared or incoming_room_depth != _world.room_depth

func flush_pending_door_syncs() -> void:
	if not can_apply_door_sync():
		return
	var sync_state: WorldMultiplayerSyncState = _world._world_multiplayer_sync_state
	if not sync_state.pending_chosen_door.is_empty():
		var chosen_payload: Dictionary = sync_state.consume_pending_chosen_door_sync()
		var chosen_door := chosen_payload.get("chosen_door", {}) as Dictionary
		var progress_state := chosen_payload.get("progress_state", {}) as Dictionary
		sync_state.clear_authoritative_door_wait()
		_world._choose_door(chosen_door)
		_world._apply_progress_sync_state(progress_state)
	if not sync_state.pending_door_sync_payload.is_empty():
		var door_payload: Dictionary = sync_state.consume_pending_door_sync_payload()
		var synced_door_options: Array = door_payload.get("door_options", []) as Array
		var synced_choosing_next_room := bool(door_payload.get("choosing_next_room", false))
		var synced_boss_unlocked := bool(door_payload.get("boss_unlocked", _world.boss_unlocked))
		var progress_state := door_payload.get("progress_state", {}) as Dictionary
		_apply_door_options_payload(synced_door_options, synced_choosing_next_room, synced_boss_unlocked, progress_state)


# --- enemy spawn sync -------------------------------------------------------

func can_apply_spawn_sync(payload: Dictionary) -> bool:
	if not MultiplayerSessionManager.is_remote_replica():
		return false
	if not is_instance_valid(_world.enemy_spawner):
		return false
	var source_room_sync_id := int(payload.get("room_sync_id", 0))
	var sync_state: WorldMultiplayerSyncState = _world._world_multiplayer_sync_state
	var allow_initial_sync_alignment: bool = sync_state.current_room_sync_id == 0 and _world.current_room_label == "Starting Chamber" and not _world._is_reward_selection_active()
	if not sync_state.can_accept_source_sync_id(source_room_sync_id, allow_initial_sync_alignment):
		return false
	if _world._is_reward_selection_active():
		return false
	if _world.current_room_label == "Starting Chamber" and not allow_initial_sync_alignment:
		return false
	var payload_room_label := String(payload.get("room_label", "")).strip_edges()
	if payload_room_label.is_empty():
		return true
	if allow_initial_sync_alignment:
		return true
	return payload_room_label == _world.current_room_label

func flush_pending_spawn_syncs() -> void:
	var sync_state: WorldMultiplayerSyncState = _world._world_multiplayer_sync_state
	if not sync_state.has_pending_spawn_sync_payload():
		return
	if not can_apply_spawn_sync(sync_state.peek_pending_spawn_sync_payload()):
		return
	var payload: Dictionary = sync_state.consume_pending_spawn_sync_payload()
	_apply_spawn_batch_payload(payload)

func flush_pending_objective_spawn_syncs() -> void:
	var sync_state: WorldMultiplayerSyncState = _world._world_multiplayer_sync_state
	if not sync_state.has_pending_objective_spawn_sync_payloads():
		return
	var remaining_payloads: Array[Dictionary] = []
	for payload in sync_state.get_pending_objective_spawn_sync_payloads():
		if not can_apply_spawn_sync(payload):
			var source_room_sync_id := int(payload.get("room_sync_id", 0))
			if sync_state.is_stale_room_sync_id(source_room_sync_id):
				continue
			remaining_payloads.append(payload)
			continue
		_apply_objective_spawn_batch_payload(payload)
	sync_state.set_pending_objective_spawn_sync_payloads(remaining_payloads)


# --- boss spawn sync --------------------------------------------------------

func can_apply_boss_spawn_sync(payload: Dictionary) -> bool:
	if not MultiplayerSessionManager.is_remote_replica():
		return false
	if not is_instance_valid(_world.enemy_spawner):
		return false
	if _world._is_reward_selection_active():
		return false
	if _world.current_room_label == "Starting Chamber":
		return false
	var sync_state: WorldMultiplayerSyncState = _world._world_multiplayer_sync_state
	var source_room_sync_id := int(payload.get("room_sync_id", 0))
	if not sync_state.can_accept_source_sync_id(source_room_sync_id, false):
		return false
	var boss_stage := int(payload.get("boss_stage", 0))
	if not _is_current_room_boss_stage(boss_stage):
		return false
	var payload_room_label := String(payload.get("room_label", "")).strip_edges()
	if payload_room_label.is_empty():
		return true
	return payload_room_label == _world.current_room_label

func flush_pending_boss_spawn_syncs() -> void:
	var sync_state: WorldMultiplayerSyncState = _world._world_multiplayer_sync_state
	if not sync_state.has_pending_boss_spawn_sync_payload():
		return
	var peek_payload: Dictionary = sync_state.peek_pending_boss_spawn_sync_payload()
	if not can_apply_boss_spawn_sync(peek_payload):
		return
	var payload: Dictionary = sync_state.consume_pending_boss_spawn_sync_payload()
	_apply_boss_spawn_payload(payload)


# --- enemy state RPC bodies (called from WG @rpc methods) ------------------

func apply_enemy_states(synced_states: Array, synced_enemy_count: int) -> void:
	for state_variant in synced_states:
		if not (state_variant is Dictionary):
			continue
		var state := state_variant as Dictionary
		var enemy_id := int(state.get("enemy_id", -1))
		if enemy_id <= 0:
			continue
		var enemy := EnemyReplicationService.enemy_nodes_by_id.get(enemy_id) as Node2D
		if not is_instance_valid(enemy):
			continue
		if state.has("position"):
			var synced_position := state.get("position", enemy.global_position) as Vector2
			if enemy.global_position.distance_to(synced_position) >= enemy_remote_snap_distance_px:
				enemy.global_position = synced_position
			EnemyReplicationService.target_positions_by_id[enemy_id] = synced_position
		if state.has("facing_angle"):
			var synced_facing_angle := float(state.get("facing_angle", enemy.global_rotation))
			EnemyReplicationService.target_facing_angles_by_id[enemy_id] = synced_facing_angle
		if state.has("health") and enemy.has_method("set_health"):
			enemy.call("set_health", float(state.get("health", 0.0)))
		if enemy.has_method("apply_network_runtime_state"):
			var runtime_state_delta := state.get("runtime_state_delta", {}) as Dictionary
			enemy.call("apply_network_runtime_state", runtime_state_delta)
	_world.active_room_enemy_count = synced_enemy_count

func apply_enemy_died(enemy_id: int, death_effect_payload: Dictionary) -> void:
	var enemy := EnemyReplicationService.enemy_nodes_by_id.get(enemy_id) as Node2D
	if String(death_effect_payload.get("effect", "")) == "pyre_death_field":
		_world._spawn_synced_pyre_death_field(death_effect_payload)
	if is_instance_valid(enemy):
		enemy.queue_free()
	_world.enemy_state_sync_broadcaster.deregister_enemy(enemy_id)


# --- internals --------------------------------------------------------------

func _apply_door_options_payload(synced_door_options: Array, synced_choosing_next_room: bool, synced_boss_unlocked: bool, progress_state: Dictionary) -> void:
	_world.door_options.clear()
	for option in synced_door_options:
		if option is Dictionary:
			_world.door_options.append((option as Dictionary).duplicate(true))
	_world.choosing_next_room = synced_choosing_next_room
	_world.boss_unlocked = synced_boss_unlocked
	_world._apply_progress_sync_state(progress_state)

func _apply_spawn_batch_payload(payload: Dictionary) -> void:
	var spawn_batch: Array = payload.get("spawn_batch", []) as Array
	var synced_enemy_count := int(payload.get("synced_enemy_count", 0))
	var source_room_sync_id := int(payload.get("room_sync_id", 0))
	_world._clear_all_enemies()
	for spawn_entry_variant in spawn_batch:
		if not (spawn_entry_variant is Dictionary):
			continue
		var spawn_entry := spawn_entry_variant as Dictionary
		var enemy_type := String(spawn_entry.get("enemy_type", ""))
		var enemy_position := spawn_entry.get("position", Vector2.ZERO) as Vector2
		var enemy_id := int(spawn_entry.get("enemy_id", -1))
		if enemy_type.is_empty() or enemy_id <= 0:
			continue
		var enemy: CharacterBody2D = _world.enemy_spawner.spawn_enemy_from_sync(enemy_type, enemy_position)
		if is_instance_valid(enemy):
			var synced_max_health := int(spawn_entry.get("max_health", 0))
			if synced_max_health > 0 and enemy.has_method("set_max_health_and_current"):
				enemy.call("set_max_health_and_current", synced_max_health, synced_max_health)
			_world.enemy_state_sync_broadcaster.register_enemy(enemy, enemy_id)
	_world.active_room_enemy_count = synced_enemy_count
	_world._world_multiplayer_sync_state.apply_spawn_sync_id(source_room_sync_id)

func _apply_objective_spawn_batch_payload(payload: Dictionary) -> void:
	var spawn_batch: Array = payload.get("spawn_batch", []) as Array
	var synced_enemy_count := int(payload.get("synced_enemy_count", 0))
	var source_room_sync_id := int(payload.get("room_sync_id", 0))
	var broadcaster: RefCounted = _world.enemy_state_sync_broadcaster
	for spawn_entry_variant in spawn_batch:
		if not (spawn_entry_variant is Dictionary):
			continue
		var spawn_entry := spawn_entry_variant as Dictionary
		var enemy_type := String(spawn_entry.get("enemy_type", ""))
		var enemy_position := spawn_entry.get("position", Vector2.ZERO) as Vector2
		var enemy_id := int(spawn_entry.get("enemy_id", -1))
		var spawn_meta := spawn_entry.get("spawn_meta", {}) as Dictionary
		if enemy_type.is_empty() or enemy_id <= 0:
			continue
		var enemy: CharacterBody2D = _world.enemy_spawner.spawn_enemy_from_sync(enemy_type, enemy_position)
		if is_instance_valid(enemy):
			var synced_max_health := int(spawn_entry.get("max_health", 0))
			if synced_max_health > 0 and enemy.has_method("set_max_health_and_current"):
				enemy.call("set_max_health_and_current", synced_max_health, synced_max_health)
			broadcaster.register_enemy(enemy, enemy_id)
			if not spawn_meta.is_empty():
				_apply_objective_spawn_meta(enemy, spawn_meta)
			if enemy.has_method("set_network_simulation_enabled"):
				enemy.call("set_network_simulation_enabled", false)
		if enemy.has_signal("died"):
			var captured_enemy_id := enemy_id
			if not enemy.died.is_connected(Callable(broadcaster, "on_enemy_died").bind(captured_enemy_id)):
				enemy.died.connect(Callable(broadcaster, "on_enemy_died").bind(captured_enemy_id))
	_world.active_room_enemy_count = synced_enemy_count
	_world._world_multiplayer_sync_state.apply_spawn_sync_id(source_room_sync_id)

func _apply_boss_spawn_payload(payload: Dictionary) -> void:
	var boss_stage := int(payload.get("boss_stage", 0))
	var enemy_id := int(payload.get("enemy_id", -1))
	var spawn_position := payload.get("position", Vector2.ZERO) as Vector2
	var source_room_sync_id := int(payload.get("room_sync_id", 0))
	if boss_stage <= 0 or enemy_id <= 0:
		return
	var existing_enemy := EnemyReplicationService.enemy_nodes_by_id.get(enemy_id) as Node2D
	if is_instance_valid(existing_enemy):
		_world.active_room_enemy_count = maxi(1, _world.active_room_enemy_count)
		return
	var boss: Node2D = _world._spawn_boss_for_stage(boss_stage, spawn_position)
	if is_instance_valid(boss):
		_world.enemy_state_sync_broadcaster.register_enemy(boss, enemy_id)
	_world.active_room_enemy_count = 1
	_world._world_multiplayer_sync_state.apply_spawn_sync_id(source_room_sync_id)

func _apply_objective_spawn_meta(enemy: CharacterBody2D, spawn_meta: Dictionary) -> void:
	if not is_instance_valid(enemy):
		return
	var role := String(spawn_meta.get("role", "")).strip_edges()
	if role.is_empty():
		return
	if role == "cut_signal_target":
		var objective_runtime: Node = _world.objective_runtime
		if is_instance_valid(objective_runtime) and objective_runtime.has_method("configure_priority_target_enemy_from_sync"):
			objective_runtime.call("configure_priority_target_enemy_from_sync", enemy, spawn_meta)
		elif is_instance_valid(_world.objective_manager):
			_world.objective_manager.hunt_target_enemy = enemy

func _is_current_room_boss_stage(boss_stage: int) -> bool:
	match boss_stage:
		1:
			return _world.in_boss_room and not _world.in_second_boss_room and not _world.in_third_boss_room
		2:
			return _world.in_second_boss_room and not _world.in_third_boss_room
		3:
			return _world.in_third_boss_room
		_:
			return false

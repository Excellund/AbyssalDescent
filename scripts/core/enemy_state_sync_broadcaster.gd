extends RefCounted

# Phase: world-generator-decomposition / Task: extract-enemy-state-sync-broadcaster
#
# Owns the host-side enemy state replication pipeline that was previously
# embedded in world_generator.gd: per-enemy bookkeeping, adaptive batching,
# runtime-state delta quantization, far-enemy throttling, and the death
# notification fan-out. The broadcaster reads world context (active enemy
# count, objective manager, players) from the host WorldGenerator and emits
# the @rpc payloads via the host's RPC methods, which remain on WG.

const ENEMY_BASE_SCRIPT := preload("res://scripts/enemy_base.gd")
const ENEMY_TETHER_SCRIPT := preload("res://scripts/enemy_tether.gd")
const ENEMY_PYRE_SCRIPT := preload("res://scripts/enemy_pyre.gd")
const ENEMY_STATE_SYNC_INTERVAL_SEC_DEFAULT: float = 0.08
const ENEMY_STATE_TRANSPORT_MTU_BYTES_DEFAULT: int = 1392
const ENEMY_STATE_FAR_SYNC_DISTANCE_PX_DEFAULT: float = 520.0
const STAT_ATTRIBUTION_TRACE := false

# --- tuning ------------------------------------------------------------------

var sync_interval_sec: float = ENEMY_STATE_SYNC_INTERVAL_SEC_DEFAULT
var sync_batch_size: int = 2
var sync_payload_budget_bytes: int = 550
var transport_mtu_bytes: int = ENEMY_STATE_TRANSPORT_MTU_BYTES_DEFAULT
var transport_safety_margin_bytes: int = 340
var far_sync_distance_px: float = ENEMY_STATE_FAR_SYNC_DISTANCE_PX_DEFAULT
var far_sync_interval_mult: float = 2.0
var position_change_threshold_sq: float = 4.0
var facing_change_threshold_rad: float = 0.06
var transmit_position_quantum: float = 1.0
var transmit_facing_quantum: float = 0.1
var runtime_float_quantum: float = 0.05
var runtime_vector_quantum: float = 0.5
var perf_attribution_enabled: bool = false

# --- last-tick metrics (read by perf logging) -------------------------------

var last_sync_enemy_count: int = 0
var last_sync_batch_count: int = 0
var last_sync_estimated_bytes: int = 0
var last_sync_tether_enemy_count: int = 0
var last_sync_tether_estimated_bytes: int = 0
var perf_runtime_delta_calls: int = 0
var perf_runtime_delta_total_usec: int = 0

# --- internal state ----------------------------------------------------------

var _world: Node2D
var _next_enemy_id: int = 1
var _scan_cursor: int = 0
var _sync_elapsed: float = 0.0
var _priority_cache_sec: float = 0.0
var _priority_cache_elapsed: float = 0.0
var _priority_cache_ttl_sec: float = 0.03
var _previous_positions: Dictionary = {}
var _previous_facing_angles: Dictionary = {}
var _previous_health_values: Dictionary = {}
var _previous_runtime_states: Dictionary = {}
var _far_sync_elapsed_by_id: Dictionary = {}
var _far_combat_hint_by_id: Dictionary = {}


func _init(world: Node2D) -> void:
	_world = world


# --- lifecycle --------------------------------------------------------------

func clear_state() -> void:
	_previous_positions.clear()
	_previous_facing_angles.clear()
	_previous_health_values.clear()
	_previous_runtime_states.clear()
	_far_sync_elapsed_by_id.clear()
	_far_combat_hint_by_id.clear()
	_scan_cursor = 0

func reset_perf_attribution() -> void:
	perf_runtime_delta_calls = 0
	perf_runtime_delta_total_usec = 0


# --- enemy registry ---------------------------------------------------------

func register_enemy(enemy: ENEMY_BASE_SCRIPT, forced_enemy_id: int = -1) -> int:
	if not is_instance_valid(enemy):
		return -1
	var enemy_id := forced_enemy_id
	if enemy_id <= 0:
		enemy_id = _next_enemy_id
		_next_enemy_id += 1
	else:
		_next_enemy_id = maxi(_next_enemy_id, enemy_id + 1)
	enemy.set_meta("network_enemy_id", enemy_id)
	EnemyReplicationService.enemy_nodes_by_id[enemy_id] = enemy
	_initialize_tracking_state(enemy_id, enemy)
	if MultiplayerSessionManager.is_remote_replica():
		enemy.set_network_simulation_enabled(false)
	if not enemy.died.is_connected(Callable(self, "on_enemy_died").bind(enemy_id)):
		enemy.died.connect(Callable(self, "on_enemy_died").bind(enemy_id))
	return enemy_id

func deregister_enemy(enemy_id: int) -> void:
	EnemyReplicationService.enemy_nodes_by_id.erase(enemy_id)
	EnemyReplicationService.last_damage_peer_by_id.erase(enemy_id)
	EnemyReplicationService.target_positions_by_id.erase(enemy_id)
	EnemyReplicationService.target_facing_angles_by_id.erase(enemy_id)
	_previous_runtime_states.erase(enemy_id)
	_previous_positions.erase(enemy_id)
	_previous_facing_angles.erase(enemy_id)
	_previous_health_values.erase(enemy_id)
	_far_sync_elapsed_by_id.erase(enemy_id)
	_far_combat_hint_by_id.erase(enemy_id)

func on_enemy_died(enemy_id: int) -> void:
	var killer_peer_id := EnemyReplicationService.killer_peer_for(enemy_id)
	if STAT_ATTRIBUTION_TRACE:
		print_debug("[StatAttribution][EnemyDied] enemy_id=%d killer_peer=%d" % [enemy_id, killer_peer_id])
	if killer_peer_id > 0:
		_world._record_peer_enemy_kill(killer_peer_id)
	var enemy := EnemyReplicationService.enemy_nodes_by_id.get(enemy_id) as ENEMY_BASE_SCRIPT
	var kill_pos := (enemy.global_position if is_instance_valid(enemy) else Vector2.ZERO)
	var death_effect_payload := _build_enemy_death_effect_payload(enemy)
	deregister_enemy(enemy_id)
	if MultiplayerSessionManager.should_broadcast():
		_world._sync_enemy_died.rpc(enemy_id, death_effect_payload)
	var replication_service := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/PlayerReplicationService")
	if replication_service != null and killer_peer_id > 0:
		replication_service.send_enemy_killed(killer_peer_id, kill_pos)
	elif is_instance_valid(_world) and _world.get("player") != null:
		_world.player.notify_enemy_killed(kill_pos)


# --- tick -------------------------------------------------------------------

func tick(delta: float) -> void:
	if not MultiplayerSessionManager.should_broadcast():
		return
	var active_enemy_count: int = int(_world.active_room_enemy_count)
	var sync_interval := sync_interval_sec
	if active_enemy_count >= 40:
		sync_interval *= 1.45
	elif active_enemy_count >= 30:
		sync_interval *= 1.2
	var objective_manager: Node = _world.objective_manager
	if is_instance_valid(objective_manager) and String(objective_manager.active_objective_kind) == "cut_the_signal":
		if active_enemy_count >= 10:
			sync_interval *= 1.35
		elif active_enemy_count >= 7:
			sync_interval *= 1.2
	var priority_sync_interval := _get_priority_sync_interval_sec(delta)
	if priority_sync_interval > 0.0:
		sync_interval = minf(sync_interval, priority_sync_interval)
	_sync_elapsed += delta
	if _sync_elapsed < sync_interval:
		return
	_sync_elapsed = 0.0
	var synced_states: Array = []
	var synced_state_sizes: Array[int] = []
	var stale_ids: Array = []
	var enemy_ids: Array = EnemyReplicationService.enemy_nodes_by_id.keys()
	var total_enemy_ids := enemy_ids.size()
	if total_enemy_ids <= 0:
		_clear_last_sync_metrics()
		_scan_cursor = 0
		return
	var scan_limit := _get_adaptive_scan_limit(total_enemy_ids, active_enemy_count)
	if scan_limit <= 0:
		scan_limit = total_enemy_ids
	var state_size_limit := _get_adaptive_state_size_limit(active_enemy_count)
	var tether_synced_enemy_count := 0
	var tether_synced_estimated_bytes := 0
	for scan_index in range(scan_limit):
		var enemy_index := (_scan_cursor + scan_index) % total_enemy_ids
		var enemy_id_variant: Variant = enemy_ids[enemy_index]
		var enemy_id := int(enemy_id_variant)
		var enemy := EnemyReplicationService.enemy_nodes_by_id.get(enemy_id) as ENEMY_BASE_SCRIPT
		if not is_instance_valid(enemy):
			stale_ids.append(enemy_id)
			_far_sync_elapsed_by_id.erase(enemy_id)
			_far_combat_hint_by_id.erase(enemy_id)
			continue
		var quantized_position_quantum := maxf(0.0001, transmit_position_quantum)
		var quantized_position := Vector2(
			snappedf(enemy.global_position.x, quantized_position_quantum),
			snappedf(enemy.global_position.y, quantized_position_quantum)
		)
		var is_far_enemy := _enemy_is_far_from_all_players(quantized_position)
		if is_far_enemy:
			var far_elapsed_fast := float(_far_sync_elapsed_by_id.get(enemy_id, 0.0)) + sync_interval
			var required_far_interval_fast := maxf(0.001, sync_interval * maxf(1.0, far_sync_interval_mult))
			var far_combat_hint := bool(_far_combat_hint_by_id.get(enemy_id, false))
			if far_elapsed_fast < required_far_interval_fast and not far_combat_hint:
				_far_sync_elapsed_by_id[enemy_id] = far_elapsed_fast
				continue
			_far_sync_elapsed_by_id[enemy_id] = 0.0
		var enemy_health := 0.0
		enemy_health = enemy.get_current_health()
		var enemy_facing_angle := enemy.get_network_facing_angle()
		var quantized_facing_quantum := maxf(0.0001, transmit_facing_quantum)
		var quantized_facing_angle := snappedf(enemy_facing_angle, quantized_facing_quantum)
		var previous_position := _previous_positions.get(enemy_id, quantized_position) as Vector2
		var previous_facing_angle := float(_previous_facing_angles.get(enemy_id, quantized_facing_angle))
		var previous_health := float(_previous_health_values.get(enemy_id, enemy_health))
		var position_changed := previous_position.distance_squared_to(quantized_position) > maxf(0.0001, position_change_threshold_sq)
		var facing_changed := absf(wrapf(quantized_facing_angle - previous_facing_angle, -PI, PI)) > maxf(0.0001, facing_change_threshold_rad)
		var health_changed := not is_equal_approx(enemy_health, previous_health)
		var previous_combat_hint := bool(_far_combat_hint_by_id.get(enemy_id, false))
		var force_runtime_state_sampling := enemy.should_force_network_runtime_state_sampling()
		var should_sample_runtime_state := position_changed or facing_changed or health_changed or previous_combat_hint or force_runtime_state_sampling or not is_far_enemy
		var allow_runtime_state_sampling := should_sample_runtime_state
		if allow_runtime_state_sampling and active_enemy_count >= 24 and not force_runtime_state_sampling and not previous_combat_hint:
			var runtime_sampling_stride := 2
			if active_enemy_count >= 48:
				runtime_sampling_stride = 4
			elif active_enemy_count >= 36:
				runtime_sampling_stride = 3
			var physics_frame := int(Engine.get_physics_frames())
			allow_runtime_state_sampling = ((enemy_id + physics_frame) % runtime_sampling_stride) == 0
		var runtime_state_delta: Dictionary = {}
		if allow_runtime_state_sampling:
			var runtime_state := enemy.get_network_runtime_state()
			runtime_state = _quantize_runtime_state_for_network(runtime_state)
			var previous_state := _previous_runtime_states.get(enemy_id, {}) as Dictionary
			runtime_state_delta = _compute_runtime_state_delta(runtime_state, previous_state)
			if active_enemy_count >= 24 and not force_runtime_state_sampling and runtime_state_delta.has("custom"):
				runtime_state_delta.erase("custom")
			_previous_runtime_states[enemy_id] = runtime_state
		elif not _previous_runtime_states.has(enemy_id):
			_previous_runtime_states[enemy_id] = {}
		var combat_active := _enemy_is_combat_active(enemy, runtime_state_delta)
		_far_combat_hint_by_id[enemy_id] = combat_active
		if is_far_enemy and not combat_active:
			var far_elapsed := float(_far_sync_elapsed_by_id.get(enemy_id, 0.0)) + _sync_elapsed
			var required_far_interval := maxf(0.001, sync_interval * maxf(1.0, far_sync_interval_mult))
			if far_elapsed < required_far_interval:
				_far_sync_elapsed_by_id[enemy_id] = far_elapsed
				continue
			_far_sync_elapsed_by_id[enemy_id] = 0.0
		else:
			_far_sync_elapsed_by_id[enemy_id] = 0.0
		_previous_positions[enemy_id] = quantized_position
		_previous_facing_angles[enemy_id] = quantized_facing_angle
		_previous_health_values[enemy_id] = enemy_health
		if not position_changed and not facing_changed and not health_changed and runtime_state_delta.is_empty():
			continue
		var synced_state := {
			"enemy_id": enemy_id,
			"runtime_state_delta": runtime_state_delta
		}
		if position_changed:
			synced_state["position"] = quantized_position
		if facing_changed:
			synced_state["facing_angle"] = quantized_facing_angle
		if health_changed:
			synced_state["health"] = enemy_health
		var fitted_synced_state := _fit_state_to_size_limit(synced_state, state_size_limit)
		synced_states.append(fitted_synced_state)
		var synced_state_size := _estimate_state_size_bytes(fitted_synced_state)
		synced_state_sizes.append(synced_state_size)
		if enemy.get_script() == ENEMY_TETHER_SCRIPT:
			tether_synced_enemy_count += 1
			tether_synced_estimated_bytes += synced_state_size
	for stale_id in stale_ids:
		deregister_enemy(int(stale_id))
	_scan_cursor = (_scan_cursor + scan_limit) % maxi(1, total_enemy_ids)
	if synced_states.is_empty() and stale_ids.is_empty():
		_clear_last_sync_metrics()
		return
	var batch_params := _get_adaptive_batch_params(active_enemy_count)
	var max_batch_size := int(batch_params.get("max_batch_size", maxi(1, sync_batch_size)))
	var payload_budget := int(batch_params.get("payload_budget", maxi(256, sync_payload_budget_bytes - 200)))
	var current_batch: Array = []
	var current_batch_bytes := 0
	var total_estimated_bytes := 0
	var total_batch_count := 0
	var per_batch_overhead := 220
	for sync_index in range(synced_states.size()):
		var synced_state := synced_states[sync_index] as Dictionary
		var state_size := int(synced_state_sizes[sync_index])
		total_estimated_bytes += state_size
		var would_exceed_budget := not current_batch.is_empty() and (current_batch_bytes + state_size + per_batch_overhead > payload_budget)
		var would_exceed_count := current_batch.size() >= max_batch_size
		if would_exceed_budget or would_exceed_count:
			_world._sync_enemy_states.rpc(current_batch, active_enemy_count)
			total_batch_count += 1
			current_batch = []
			current_batch_bytes = 0
		current_batch.append(synced_state)
		current_batch_bytes += state_size
	if not current_batch.is_empty():
		_world._sync_enemy_states.rpc(current_batch, active_enemy_count)
		total_batch_count += 1
	last_sync_enemy_count = synced_states.size()
	last_sync_batch_count = total_batch_count
	last_sync_estimated_bytes = total_estimated_bytes
	last_sync_tether_enemy_count = tether_synced_enemy_count
	last_sync_tether_estimated_bytes = tether_synced_estimated_bytes


# --- internals --------------------------------------------------------------

func _initialize_tracking_state(enemy_id: int, enemy: ENEMY_BASE_SCRIPT) -> void:
	EnemyReplicationService.target_positions_by_id[enemy_id] = enemy.global_position
	_previous_positions[enemy_id] = enemy.global_position
	var enemy_facing_angle := enemy.get_network_facing_angle()
	EnemyReplicationService.target_facing_angles_by_id[enemy_id] = enemy_facing_angle
	_previous_facing_angles[enemy_id] = enemy_facing_angle
	_previous_health_values[enemy_id] = float(enemy.get_current_health())
	_far_sync_elapsed_by_id[enemy_id] = 0.0
	_far_combat_hint_by_id[enemy_id] = false

func _build_enemy_death_effect_payload(enemy: ENEMY_BASE_SCRIPT) -> Dictionary:
	if not is_instance_valid(enemy):
		return {}
	if enemy.get_script() == ENEMY_PYRE_SCRIPT:
		return {
			"effect": "pyre_death_field",
			"position": enemy.global_position,
			"radius": float(enemy.get("death_field_radius")),
			"duration": float(enemy.get("death_field_duration")),
			"tick_interval": float(enemy.get("death_field_tick_interval"))
		}
	return {}

func _clear_last_sync_metrics() -> void:
	last_sync_enemy_count = 0
	last_sync_batch_count = 0
	last_sync_estimated_bytes = 0
	last_sync_tether_enemy_count = 0
	last_sync_tether_estimated_bytes = 0

func _compute_runtime_state_delta(current_state: Dictionary, previous_state: Dictionary) -> Dictionary:
	var attr_start_usec := Time.get_ticks_usec() if perf_attribution_enabled else 0
	var delta := {}
	for key_variant in current_state.keys():
		var key := String(key_variant)
		var current_val: Variant = current_state.get(key)
		var previous_val: Variant = previous_state.get(key)
		if current_val != previous_val:
			delta[key] = current_val
	if attr_start_usec > 0:
		perf_runtime_delta_calls += 1
		perf_runtime_delta_total_usec += Time.get_ticks_usec() - attr_start_usec
	return delta

func _quantize_runtime_variant_for_network(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var quantum := maxf(0.0001, runtime_float_quantum)
			return snappedf(float(value), quantum)
		TYPE_VECTOR2:
			var vector_quantum := maxf(0.0001, runtime_vector_quantum)
			var vector_value := value as Vector2
			return Vector2(
				snappedf(vector_value.x, vector_quantum),
				snappedf(vector_value.y, vector_quantum)
			)
		TYPE_DICTIONARY:
			var source_dict := value as Dictionary
			var quantized_dict := {}
			for key_variant in source_dict.keys():
				quantized_dict[key_variant] = _quantize_runtime_variant_for_network(source_dict.get(key_variant))
			return quantized_dict
		TYPE_ARRAY:
			var source_array := value as Array
			var quantized_array: Array = []
			for item in source_array:
				quantized_array.append(_quantize_runtime_variant_for_network(item))
			return quantized_array
		_:
			return value

func _quantize_runtime_state_for_network(runtime_state: Dictionary) -> Dictionary:
	return _quantize_runtime_variant_for_network(runtime_state) as Dictionary

func _enemy_is_far_from_all_players(enemy_position: Vector2) -> bool:
	var far_distance_sq := maxf(0.0, far_sync_distance_px * far_sync_distance_px)
	if bool(_world.is_multiplayer):
		var party_nodes: Array = _world._get_multiplayer_player_nodes()
		for party_node_variant in party_nodes:
			var party_node := party_node_variant as Node2D
			if not is_instance_valid(party_node):
				continue
			if enemy_position.distance_squared_to(party_node.global_position) <= far_distance_sq:
				return false
		return true
	var player: Node2D = _world.player
	if is_instance_valid(player):
		if enemy_position.distance_squared_to(player.global_position) <= far_distance_sq:
			return false
	return true

func _enemy_is_combat_active(_enemy: ENEMY_BASE_SCRIPT, runtime_state_delta: Dictionary) -> bool:
	if runtime_state_delta.has("custom"):
		var custom_state := runtime_state_delta.get("custom", {}) as Dictionary
		if not custom_state.is_empty():
			return true
	if runtime_state_delta.has("attack_anim_time_left") and float(runtime_state_delta.get("attack_anim_time_left", 0.0)) > 0.0:
		return true
	return false

func estimate_variant_size_bytes(value: Variant) -> int:
	match typeof(value):
		TYPE_NIL:
			return 1
		TYPE_BOOL:
			return 2
		TYPE_INT, TYPE_FLOAT:
			return 8
		TYPE_STRING:
			return 4 + String(value).length()
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return 16
		TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_COLOR:
			return 24
		TYPE_ARRAY:
			var total_size := 4
			for item in value:
				total_size += estimate_variant_size_bytes(item)
			return total_size
		TYPE_DICTIONARY:
			var total_size := 8
			for key_variant in value.keys():
				total_size += estimate_variant_size_bytes(key_variant)
				total_size += estimate_variant_size_bytes(value.get(key_variant))
			return total_size
		_:
			return 32

func _estimate_state_size_bytes(state: Dictionary) -> int:
	return estimate_variant_size_bytes(state) + 24

func _fit_state_to_size_limit(synced_state: Dictionary, max_estimated_bytes: int) -> Dictionary:
	var fitted_state := synced_state.duplicate(true)
	var estimated_size := _estimate_state_size_bytes(fitted_state)
	if estimated_size <= max_estimated_bytes:
		return fitted_state
	var runtime_delta := fitted_state.get("runtime_state_delta", {}) as Dictionary
	if runtime_delta.has("custom"):
		runtime_delta.erase("custom")
		fitted_state["runtime_state_delta"] = runtime_delta
		estimated_size = _estimate_state_size_bytes(fitted_state)
		if estimated_size <= max_estimated_bytes:
			return fitted_state
	if not runtime_delta.is_empty():
		fitted_state["runtime_state_delta"] = {}
	return fitted_state

func _get_adaptive_batch_params(active_enemy_count: int) -> Dictionary:
	var max_batch_size := maxi(1, sync_batch_size)
	var payload_budget := maxi(256, sync_payload_budget_bytes - 200)
	if active_enemy_count >= 60:
		max_batch_size = maxi(max_batch_size, 12)
		payload_budget = maxi(payload_budget, 1600)
	elif active_enemy_count >= 50:
		max_batch_size = maxi(max_batch_size, 10)
		payload_budget = maxi(payload_budget, 1450)
	if active_enemy_count >= 40:
		max_batch_size = maxi(max_batch_size, 8)
		payload_budget = maxi(payload_budget, 1300)
	elif active_enemy_count >= 30:
		max_batch_size = maxi(max_batch_size, 5)
		payload_budget = maxi(payload_budget, 1052)
	elif active_enemy_count >= 20:
		max_batch_size = maxi(max_batch_size, 4)
		payload_budget = maxi(payload_budget, 820)
	var mtu_safe_payload_budget := maxi(512, transport_mtu_bytes - transport_safety_margin_bytes)
	payload_budget = mini(payload_budget, mtu_safe_payload_budget)
	return {
		"max_batch_size": max_batch_size,
		"payload_budget": payload_budget
	}

func _get_adaptive_scan_limit(total_enemy_count: int, active_enemy_count: int) -> int:
	if total_enemy_count <= 0:
		return 0
	if active_enemy_count >= 60:
		return mini(total_enemy_count, 28)
	if active_enemy_count >= 50:
		return mini(total_enemy_count, 30)
	if active_enemy_count >= 40:
		return mini(total_enemy_count, 32)
	if active_enemy_count >= 30:
		return mini(total_enemy_count, 40)
	return total_enemy_count

func _get_adaptive_state_size_limit(active_enemy_count: int) -> int:
	if active_enemy_count >= 60:
		return 480
	if active_enemy_count >= 50:
		return 540
	if active_enemy_count >= 40:
		return 620
	return 900

func _compute_priority_sync_interval_sec() -> float:
	var best_interval := 0.0
	for enemy_variant in EnemyReplicationService.enemy_nodes_by_id.values():
		var enemy := enemy_variant as ENEMY_BASE_SCRIPT
		if not is_instance_valid(enemy):
			continue
		var requested_interval := enemy.get_priority_network_sync_interval_sec()
		if requested_interval <= 0.0:
			continue
		if best_interval <= 0.0 or requested_interval < best_interval:
			best_interval = requested_interval
	return best_interval

func _get_priority_sync_interval_sec(delta: float) -> float:
	_priority_cache_elapsed += maxf(0.0, delta)
	if _priority_cache_elapsed < _priority_cache_ttl_sec:
		return _priority_cache_sec
	_priority_cache_elapsed = 0.0
	_priority_cache_sec = _compute_priority_sync_interval_sec()
	return _priority_cache_sec

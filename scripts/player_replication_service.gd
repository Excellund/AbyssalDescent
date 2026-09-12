extends Node
## Service for syncing player state across multiplayer peers.
## Handles position, health, alive status, and upgrade state replication via RPC.

const PLAYER_CUE_EVENT_DISPATCHER_SCRIPT := preload("res://scripts/core/player_cue_event_dispatcher.gd")
const PLAYER_CUE_SYNC_QUEUE_SCRIPT := preload("res://scripts/core/player_cue_sync_queue.gd")
const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const REMOTE_PLAYER_SNAP_DISTANCE_PX: float = 180.0
# Recover the final stop/turn when its unreliable movement packet is lost.
const TRANSFORM_HEARTBEAT_SEC: float = 0.25

## Configuration
var position_sync_interval_sec: float = 0.05  ## ~20 Hz position updates
var position_broadcast_threshold_px: float = 2.0  ## Broadcast low-latency movement updates
var rotation_broadcast_threshold_rad: float = deg_to_rad(2.0)
var position_transmit_quantum_px: float = 0.5
var rotation_transmit_quantum_rad: float = deg_to_rad(2.0)
var remote_position_snap_distance_px: float = REMOTE_PLAYER_SNAP_DISTANCE_PX
## Half-life in seconds for remote position/rotation interpolation (frame-rate independent).
## Lower value = snappier; higher value = smoother.
var remote_position_lerp_half_life_sec: float = 0.04
var remote_rotation_lerp_half_life_sec: float = 0.035
## Dead-reckoning: extrapolate the remote player's authoritative position forward
## using velocity estimated from the last two received samples. This compensates for
## the ~50ms position sync interval so host-side hit detection (boss attacks, AOEs)
## runs against where the remote player actually is, not where they were last sample.
## Capped to avoid runaway extrapolation on direction changes or stalls.
var remote_position_extrapolation_max_sec: float = 0.18
var remote_position_extrapolation_max_speed_px: float = 1200.0
var cue_event_sync_interval_sec: float = 0.05
var cue_event_sync_payload_budget_bytes: int = 640

## References to player nodes (populated by caller)
var player_nodes: Dictionary = {}  ## peer_id -> Player node reference
var local_peer_id: int = 0
var multiplayer_session_manager

## Internal state
var _last_sync_time: float = 0.0
var _last_sync_positions: Dictionary = {}  ## peer_id -> last_synced_position
var _last_sync_rotations: Dictionary = {}  ## peer_id -> last_synced_facing_radians
var _remote_target_positions: Dictionary = {}  ## peer_id -> latest replicated position
var _remote_target_rotations: Dictionary = {}  ## peer_id -> latest replicated facing
var _remote_position_samples: Dictionary = {}  ## peer_id -> {prev_pos, prev_time, last_pos, last_time}
var _outgoing_transform_sequence: int = 0
var _last_received_transform_sequence: Dictionary = {}
var _last_transform_sent_at: Dictionary = {}
var _last_transform_sent_room: Dictionary = {}
var _cue_event_sync_elapsed: float = 0.0
var _pending_cue_events_by_peer: Dictionary = {}  ## peer_id -> Array[Dictionary]
var _last_cue_event_count: int = 0
var _last_cue_event_estimated_bytes: int = 0
var _outgoing_health_sequence_by_peer: Dictionary = {}  ## peer_id -> last emitted health sequence
var _last_applied_health_sequence_by_sender: Dictionary = {}  ## (sender_peer_id, target_peer_id) -> last applied health sequence
var _cue_event_dispatcher: PlayerCueEventDispatcher = PLAYER_CUE_EVENT_DISPATCHER_SCRIPT.new()
var _cue_sync_queue := PLAYER_CUE_SYNC_QUEUE_SCRIPT.new()
var _interaction_epoch_announcements: Dictionary = {}
const SHARED_BUILD_STATE_PROPERTIES := [
	"battle_trance_active_left", "apex_predator_combo_hits", "apex_predator_combo_left",
	"apex_momentum_stacks", "apex_momentum_stack_left", "convergence_surge_hit_counter",
	"_sigil_chain_charge", "_sigil_chain_drop_armed", "_riftpunch_window_left", "void_heat",
	"_farline_volley_current_stacks", "indomitable_damage_bank", "_indomitable_spirit_primed",
	"_dash_damage_immune_left", "_shared_dash_refund_total", "combo_relay_stacks", "combo_relay_stack_timer", "sigil_burst_ready",
	"cross_stitch_window_left", "cross_stitch_target_network_id"
]


func _ready() -> void:
	multiplayer_session_manager = get_node_or_null("/root/MultiplayerSessionManager")
	if multiplayer_session_manager == null:
		push_error("[PlayerReplicationService] MultiplayerSessionManager autoload is missing")
		set_process(false)
		return
	local_peer_id = int(multiplayer_session_manager.local_peer_id)
	set_process(true)


func _process(delta: float) -> void:
	if multiplayer_session_manager == null:
		return
	if not bool(multiplayer_session_manager.is_session_connected()):
		return
	var current_local_peer_id := int(multiplayer_session_manager.local_peer_id)
	if current_local_peer_id > 0 and current_local_peer_id != local_peer_id:
		local_peer_id = current_local_peer_id
	
	_last_sync_time += delta
	if _last_sync_time >= position_sync_interval_sec:
		_last_sync_time = 0.0
		_sync_all_player_positions()
	_cue_event_sync_elapsed += delta
	if _cue_event_sync_elapsed >= cue_event_sync_interval_sec:
		_cue_event_sync_elapsed = 0.0
		_flush_pending_cue_events()
	_interpolate_remote_players(delta)


## Register a player node for a specific peer.
func register_player(peer_id: int, player_node: Node) -> void:
	player_nodes[peer_id] = player_node
	_apply_interaction_epoch_to_player(peer_id)
	_remote_position_samples.erase(peer_id)
	_last_received_transform_sequence.erase(peer_id)
	_last_transform_sent_at.erase(peer_id)
	_last_transform_sent_room.erase(peer_id)
	if not _outgoing_health_sequence_by_peer.has(peer_id):
		_outgoing_health_sequence_by_peer[peer_id] = 0
	_clear_applied_health_sequences_for_target(peer_id)
	var player_body := player_node as Node2D
	if player_body != null:
		_last_sync_positions[peer_id] = player_body.position
		_remote_target_positions[peer_id] = player_body.position
		var initial_rotation := _get_player_facing_angle(player_node)
		_last_sync_rotations[peer_id] = initial_rotation
		_remote_target_rotations[peer_id] = initial_rotation
	else:
		_last_sync_positions[peer_id] = Vector2.ZERO
		_last_sync_rotations[peer_id] = 0.0


## Teleport a remote peer's interpolation target to a new position.
## Call this whenever the remote node is repositioned out-of-band (e.g. room
## transitions) so _interpolate_remote_players does not lerp back to the
## previous position before the first broadcast arrives.
func reset_remote_player_position(peer_id: int, position: Vector2) -> void:
	_remote_target_positions[peer_id] = position
	_remote_position_samples.erase(peer_id)


## Unregister a player node.
func unregister_player(peer_id: int) -> void:
	player_nodes.erase(peer_id)
	_interaction_epoch_announcements.erase(peer_id)
	_last_sync_positions.erase(peer_id)
	_last_sync_rotations.erase(peer_id)
	_remote_target_positions.erase(peer_id)
	_remote_target_rotations.erase(peer_id)
	_remote_position_samples.erase(peer_id)
	_pending_cue_events_by_peer.erase(peer_id)
	_last_received_transform_sequence.erase(peer_id)
	_last_transform_sent_at.erase(peer_id)
	_last_transform_sent_room.erase(peer_id)
	_outgoing_health_sequence_by_peer.erase(peer_id)
	_clear_applied_health_sequences_for_target(peer_id)


## Returns true when this peer is authoritative for the given peer_id:
## always true for the host (or singleplayer), or for a client broadcasting their own peer.
func _is_authority_for_peer(peer_id: int) -> bool:
	if multiplayer_session_manager == null:
		return peer_id == local_peer_id
	return bool(multiplayer_session_manager.is_authoritative_for_peer(peer_id))


## Looks up the player node for peer_id. Returns null and cleans up if invalid.
func _get_player_node(peer_id: int) -> Node:
	var variant: Variant = player_nodes.get(peer_id)
	if not is_instance_valid(variant):
		_remove_invalid_player(peer_id)
		return null
	var node := variant as Node
	if node == null:
		_remove_invalid_player(peer_id)
		return null
	return node


func _remove_invalid_player(peer_id: int) -> void:
	unregister_player(peer_id)


func get_last_cue_event_sync_metrics() -> Dictionary:
	return {
		"event_count": _last_cue_event_count,
		"estimated_bytes": _last_cue_event_estimated_bytes
	}


func broadcast_cue_event(peer_id: int, event_name: String, payload: Dictionary, reliable: bool = false) -> void:
	## Cue events are transient player-facing signals synced for presentation parity across peers.
	if peer_id <= 0:
		return
	if event_name.is_empty() or payload.is_empty():
		return
	if not _is_authority_for_peer(peer_id):
		return
	if event_name in ["shared_build_state", "warden_verdict", "cross_stitch_burst", "shatterwake_burst", "boss_convergence_start", "boss_convergence_pulse", "boss_convergence_clear"] and not MultiplayerSessionManager.should_broadcast():
		return
	var pending_variant: Variant = _pending_cue_events_by_peer.get(peer_id, [])
	var pending_events := _cue_sync_queue.copy_pending_events(pending_variant)
	var event_payload := payload.duplicate(true)
	if event_name == "shared_build_state":
		event_payload = _pack_shared_build_state(payload)
		if event_payload.is_empty():
			return
		# State is cumulative, so only its latest pending snapshot is needed.
		pending_events = pending_events.filter(func(entry: Dictionary) -> bool: return entry.get("event") != "shared_build_state")
	var estimated_bytes := _cue_sync_queue.estimate_event_bytes(event_name, event_payload)
	if not _cue_sync_queue.can_fit_event(estimated_bytes, cue_event_sync_payload_budget_bytes):
		return
	if _cue_sync_queue.requires_pre_flush(pending_events, estimated_bytes, cue_event_sync_payload_budget_bytes):
		_flush_cue_events_for_peer(peer_id, pending_events)
		pending_events.clear()
	pending_events.append(_cue_sync_queue.build_event_entry(event_name, event_payload, reliable, estimated_bytes))
	_pending_cue_events_by_peer[peer_id] = pending_events


func _flush_pending_cue_events() -> void:
	_last_cue_event_count = 0
	_last_cue_event_estimated_bytes = 0
	if _pending_cue_events_by_peer.is_empty():
		return
	for peer_key in _pending_cue_events_by_peer.keys():
		var peer_id := int(peer_key)
		var pending_variant: Variant = _pending_cue_events_by_peer.get(peer_id, [])
		var pending_events := _cue_sync_queue.copy_pending_events(pending_variant)
		_flush_cue_events_for_peer(peer_id, pending_events)
	_pending_cue_events_by_peer.clear()


func _flush_cue_events_for_peer(peer_id: int, pending_events: Array[Dictionary]) -> void:
	if pending_events.is_empty():
		return
	var packet_split := _cue_sync_queue.split_packets(pending_events)
	var unreliable_events := packet_split.get("unreliable_events", []) as Array[Dictionary]
	var reliable_events := packet_split.get("reliable_events", []) as Array[Dictionary]
	_last_cue_event_count += int(packet_split.get("event_count", 0))
	_last_cue_event_estimated_bytes += int(packet_split.get("estimated_bytes", 0))
	if not unreliable_events.is_empty():
		_sync_player_cue_events_unreliable.rpc(peer_id, unreliable_events)
	if not reliable_events.is_empty():
		_sync_player_cue_events_reliable.rpc(peer_id, reliable_events)


## Sync all registered player positions if they've moved significantly.
func _sync_all_player_positions() -> void:
	var now := float(Time.get_ticks_msec()) * 0.001
	var room_sync_id := EnemyReplicationService._current_room_sync_id()
	var run_token := GameStateReplicationService.get_current_run_sync_token()
	for peer_id in player_nodes.keys():
		var player_node := _get_player_node(peer_id)
		if player_node == null:
			continue
		
		if peer_id == local_peer_id:
			## Local player: broadcast own position to peers
			var player_body := player_node as Node2D
			if player_body != null:
				var current_pos: Vector2 = player_body.position
				var position_quantum := maxf(0.0001, position_transmit_quantum_px)
				var quantized_pos := Vector2(
					snappedf(current_pos.x, position_quantum),
					snappedf(current_pos.y, position_quantum)
				)
				var last_pos: Vector2 = _last_sync_positions.get(peer_id, Vector2.ZERO)
				var distance := quantized_pos.distance_to(last_pos)
				var current_rotation := _get_player_facing_angle(player_node)
				var rotation_quantum := maxf(0.0001, rotation_transmit_quantum_rad)
				var quantized_rotation := snappedf(current_rotation, rotation_quantum)
				var last_rotation := float(_last_sync_rotations.get(peer_id, quantized_rotation))
				var rotation_delta := absf(wrapf(quantized_rotation - last_rotation, -PI, PI))
				
				var heartbeat_due := now - float(_last_transform_sent_at.get(peer_id, -TRANSFORM_HEARTBEAT_SEC)) >= TRANSFORM_HEARTBEAT_SEC
				var changed_room := int(_last_transform_sent_room.get(peer_id, -1)) != room_sync_id
				if distance >= position_broadcast_threshold_px or rotation_delta >= rotation_broadcast_threshold_rad or heartbeat_due or changed_room:
					_last_sync_positions[peer_id] = quantized_pos
					_last_sync_rotations[peer_id] = quantized_rotation
					_last_transform_sent_at[peer_id] = now
					_last_transform_sent_room[peer_id] = room_sync_id
					_outgoing_transform_sequence += 1
					_sync_player_transform.rpc(peer_id, quantized_pos, quantized_rotation, _outgoing_transform_sequence, room_sync_id, run_token)


## RPC: Broadcast a player's transform to all peers.
@rpc("unreliable", "any_peer", "call_local")
func _sync_player_transform(peer_id: int, position: Vector2, facing_radians: float, sample_sequence: int, room_sync_id: int, run_token: String) -> void:
	if peer_id not in player_nodes:
		return
	if peer_id == local_peer_id:
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	if not position.is_finite() or not is_finite(facing_radians):
		return
	# Room IDs repeat after retry, so ordering is also scoped to the active run.
	if run_token != GameStateReplicationService.get_current_run_sync_token():
		return
	if room_sync_id != EnemyReplicationService._current_room_sync_id() or sample_sequence <= int(_last_received_transform_sequence.get(peer_id, 0)):
		return
	var player_node := _get_player_node(peer_id)
	if player_node == null:
		return
	_last_received_transform_sequence[peer_id] = sample_sequence
	var player_body := player_node as Node2D
	if player_body != null:
		var distance_to_target := player_body.position.distance_to(position)
		if distance_to_target >= remote_position_snap_distance_px:
			player_body.position = position
		_remote_target_positions[peer_id] = position
		_record_remote_position_sample(peer_id, position)
	_remote_target_rotations[peer_id] = facing_radians


func _record_remote_position_sample(peer_id: int, position: Vector2) -> void:
	var now := float(Time.get_ticks_msec()) * 0.001
	var sample: Dictionary = _remote_position_samples.get(peer_id, {})
	var last_pos: Vector2 = sample.get("last_pos", position)
	var last_time: float = float(sample.get("last_time", now))
	sample["prev_pos"] = last_pos
	sample["prev_time"] = last_time
	sample["last_pos"] = position
	sample["last_time"] = now
	_remote_position_samples[peer_id] = sample


func _get_extrapolated_remote_position(peer_id: int, fallback: Vector2) -> Vector2:
	var sample: Dictionary = _remote_position_samples.get(peer_id, {})
	if sample.is_empty():
		return fallback
	var last_pos: Vector2 = sample.get("last_pos", fallback)
	var last_time: float = float(sample.get("last_time", 0.0))
	var prev_time: float = float(sample.get("prev_time", last_time))
	var sample_dt := last_time - prev_time
	if sample_dt <= 0.0001:
		return last_pos
	var prev_pos: Vector2 = sample.get("prev_pos", last_pos)
	var velocity := (last_pos - prev_pos) / sample_dt
	var speed := velocity.length()
	if speed > remote_position_extrapolation_max_speed_px:
		velocity = velocity * (remote_position_extrapolation_max_speed_px / speed)
	var now := float(Time.get_ticks_msec()) * 0.001
	var elapsed := clampf(now - last_time, 0.0, remote_position_extrapolation_max_sec)
	return last_pos + velocity * elapsed


func _interpolate_remote_players(delta: float) -> void:
	var position_weight := 1.0 - pow(0.5, delta / maxf(0.0001, remote_position_lerp_half_life_sec))
	var rotation_weight := 1.0 - pow(0.5, delta / maxf(0.0001, remote_rotation_lerp_half_life_sec))
	for peer_id in player_nodes.keys():
		if peer_id == local_peer_id:
			continue
		var player_node := _get_player_node(peer_id)
		if player_node == null:
			continue
		var player_body := player_node as Node2D
		if player_body == null:
			continue
		var fallback_pos: Vector2 = _remote_target_positions.get(peer_id, player_body.position)
		var target_pos := _get_extrapolated_remote_position(peer_id, fallback_pos)
		player_body.position = player_body.position.lerp(target_pos, position_weight)
		var current_rotation := _get_player_facing_angle(player_node)
		var target_rotation := float(_remote_target_rotations.get(peer_id, current_rotation))
		var smoothed_rotation := lerp_angle(current_rotation, target_rotation, rotation_weight)
		_set_player_facing_angle(player_node, smoothed_rotation)


func _get_player_facing_angle(player_node: Node) -> float:
	if player_node is Node2D:
		return float(player_node.get_network_facing_angle())
	return 0.0


func _set_player_facing_angle(player_node: Node, facing_radians: float) -> void:
	if player_node is Node2D:
		player_node.set_network_facing_angle(facing_radians)


## RPC: Sync a player's health.
@rpc("reliable", "any_peer", "call_local")
func _sync_player_health(peer_id: int, health: float, health_sequence: int = 0) -> void:
	if peer_id not in player_nodes:
		return
	if health_sequence > 0:
		var sender_peer_id := _resolve_health_sender_peer_id()
		var sender_key := _make_health_sender_key(sender_peer_id, peer_id)
		var last_applied_sequence := int(_last_applied_health_sequence_by_sender.get(sender_key, 0))
		if health_sequence <= last_applied_sequence:
			return
		_last_applied_health_sequence_by_sender[sender_key] = health_sequence
	var player_node := _get_player_node(peer_id)
	if player_node == null:
		return
	if health > 0.0 and bool(player_node.is_dead()):
		# Dead players must only transition back through explicit revive sync.
		return
	player_node.set_health(health)


func _resolve_health_sender_peer_id() -> int:
	## Returns the originating peer of the current RPC, or local_peer_id when call_local triggered it.
	var multiplayer_api := get_tree().get_multiplayer() if is_inside_tree() else null
	if multiplayer_api == null:
		return local_peer_id
	var remote_sender := int(multiplayer_api.get_remote_sender_id())
	if remote_sender > 0:
		return remote_sender
	return local_peer_id


func _make_health_sender_key(sender_peer_id: int, target_peer_id: int) -> String:
	return "%d:%d" % [sender_peer_id, target_peer_id]


func _clear_applied_health_sequences_for_target(target_peer_id: int) -> void:
	var suffix := ":%d" % target_peer_id
	var keys_to_erase: Array = []
	for key in _last_applied_health_sequence_by_sender.keys():
		if String(key).ends_with(suffix):
			keys_to_erase.append(key)
	for key in keys_to_erase:
		_last_applied_health_sequence_by_sender.erase(key)


## RPC: Sync a player's alive/dead status.
@rpc("reliable", "any_peer", "call_local")
func _sync_player_alive_status(peer_id: int, is_alive: bool) -> void:
	if not _is_host_life_state_sender():
		return
	if peer_id not in player_nodes:
		return
	var player_node := _get_player_node(peer_id)
	if player_node == null:
		return
	player_node.set_alive(is_alive)
	player_node.set_combat_removed(not is_alive)


## RPC: Sync a player's revived status.
@rpc("reliable", "any_peer", "call_local")
func _sync_player_revived(peer_id: int, revived_health: float = 1.0) -> void:
	if not _is_host_life_state_sender():
		return
	if peer_id not in player_nodes:
		return
	var player_node := _get_player_node(peer_id)
	if player_node == null:
		return
	player_node.revive_with_health(revived_health)
	player_node.set_combat_removed(false)

func _is_host_life_state_sender() -> bool:
	var remote_sender := multiplayer.get_remote_sender_id()
	if remote_sender > 0:
		return remote_sender == 1
	# Direct local calls follow the current session role, not a cached peer ID
	# that may still belong to the previous session until the next process tick.
	return multiplayer_session_manager != null and bool(multiplayer_session_manager.should_broadcast())


## Called by player's health_state when health changes.
## Should be called from player.gd's health signal handler.
## HP is host-authoritative for ALL players to prevent echo races where a
## joiner's re-broadcast of an inbound RPC reverts damage the host applied
## locally but hadn't yet round-tripped (causing visible HP desync).
func broadcast_health_change(peer_id: int, health: float) -> void:
	if multiplayer_session_manager == null:
		return
	if not bool(multiplayer_session_manager.is_session_connected()):
		return
	if not bool(multiplayer_session_manager.is_host()):
		return
	var next_sequence := int(_outgoing_health_sequence_by_peer.get(peer_id, 0)) + 1
	_outgoing_health_sequence_by_peer[peer_id] = next_sequence
	_sync_player_health.rpc(peer_id, health, next_sequence)


## Called by player when they die.
## Should be called from player.gd's death signal handler.
## Like HP, life state is host-authoritative. A joiner's inbound death callback
## must not echo back after the host has already revived them on room clear.
func broadcast_player_died(peer_id: int) -> void:
	if multiplayer_session_manager != null and bool(multiplayer_session_manager.should_broadcast()):
		_sync_player_alive_status.rpc(peer_id, false)


## Called when a revived player regains control.
## Should be called after encounter clear or revival trigger.
func broadcast_player_revived(peer_id: int, health: float = 1.0) -> void:
	if multiplayer_session_manager != null and bool(multiplayer_session_manager.should_broadcast()):
		_sync_player_revived.rpc(peer_id, health)


func broadcast_attack_indicator(peer_id: int, attack_direction: Vector2, attack_range: float, attack_arc_degrees: float, swing_color: Color, swing_duration: float = 0.12, attack_origin: Vector2 = Vector2.INF, inner_range: float = 0.0) -> void:
	if peer_id <= 0:
		return
	if _is_authority_for_peer(peer_id):
		_sync_attack_indicator.rpc(peer_id, attack_direction, attack_range, attack_arc_degrees, swing_color, swing_duration, attack_origin, inner_range)


@rpc("unreliable", "any_peer", "call_local")
func _sync_attack_indicator(peer_id: int, attack_direction: Vector2, attack_range: float, attack_arc_degrees: float, swing_color: Color, swing_duration: float = 0.12, attack_origin: Vector2 = Vector2.INF, inner_range: float = 0.0) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1 and sender != peer_id:
		return
	if peer_id not in player_nodes:
		return
	if peer_id == local_peer_id:
		return
	var player_node := _get_player_node(peer_id)
	if player_node == null:
		return
	player_node.play_network_attack_indicator(attack_direction, attack_range, attack_arc_degrees, swing_color, swing_duration, attack_origin, inner_range)


func broadcast_player_build_snapshot(peer_id: int, snapshot: Dictionary) -> void:
	if peer_id <= 0:
		return
	if snapshot.is_empty():
		return
	if _is_authority_for_peer(peer_id):
		_sync_player_build_snapshot.rpc(peer_id, snapshot)


@rpc("reliable", "any_peer", "call_local")
func _sync_player_build_snapshot(peer_id: int, snapshot: Dictionary) -> void:
	if snapshot.has("effigy_attack_count"):
		var sender := multiplayer.get_remote_sender_id()
		if sender != 0 and sender != 1 and sender != peer_id:
			return
	if peer_id not in player_nodes:
		return
	if peer_id == local_peer_id:
		return
	if snapshot.is_empty():
		return
	var player_node := _get_player_node(peer_id)
	if player_node == null:
		return
	player_node.apply_network_build_snapshot(snapshot)


@rpc("unreliable", "any_peer", "call_local")
func _sync_player_cue_events_unreliable(peer_id: int, events: Array[Dictionary]) -> void:
	_apply_network_cue_events(peer_id, events)


@rpc("reliable", "any_peer", "call_local")
func _sync_player_cue_events_reliable(peer_id: int, events: Array[Dictionary]) -> void:
	_apply_network_cue_events(peer_id, events)


func _apply_network_cue_events(peer_id: int, events: Array[Dictionary]) -> void:
	if peer_id not in player_nodes:
		return
	if events.is_empty():
		return
	var player_node := _get_player_node(peer_id)
	if player_node == null:
		return
	var accepted_events: Array[Dictionary] = []
	for entry: Dictionary in events:
		if entry.get("event") not in ["shared_build_state", "warden_verdict", "cross_stitch_burst", "shatterwake_burst", "boss_convergence_start", "boss_convergence_pulse", "boss_convergence_clear"]:
			accepted_events.append(entry)
			continue
		var sender := multiplayer.get_remote_sender_id()
		if sender != 1 and not (sender == 0 and MultiplayerSessionManager.is_host()):
			continue
		if entry.get("event") in ["warden_verdict", "cross_stitch_burst", "shatterwake_burst", "boss_convergence_start", "boss_convergence_pulse", "boss_convergence_clear"]:
			accepted_events.append(entry)
			continue
		var packed: Variant = entry.get("payload")
		var unpacked := _unpack_shared_build_state(packed) if packed is Dictionary else {}
		if not unpacked.is_empty():
			var decoded := entry.duplicate()
			decoded["payload"] = unpacked
			accepted_events.append(decoded)
	_cue_event_dispatcher.apply_cue_events(player_node, peer_id, local_peer_id, accepted_events)

## Relay gameplay runs on the host for every owner. Dedicated bounded snapshots
## avoid the transient cue budget and also recover an observer joining mid-flight.
func broadcast_spark_relay_state(peer_id: int, payload: Dictionary, reliable: bool = false) -> void:
	if peer_id <= 0 or not MultiplayerSessionManager.should_broadcast() or not player_nodes.has(peer_id):
		return
	if reliable:
		_sync_spark_relay_state_reliable.rpc(peer_id, payload)
	else:
		_sync_spark_relay_state.rpc(peer_id, payload)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _sync_spark_relay_state(peer_id: int, payload: Dictionary) -> void:
	_apply_spark_relay_state(peer_id, payload)

@rpc("any_peer", "call_remote", "reliable")
func _sync_spark_relay_state_reliable(peer_id: int, payload: Dictionary) -> void:
	_apply_spark_relay_state(peer_id, payload)

func _apply_spark_relay_state(peer_id: int, payload: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not MultiplayerSessionManager.is_remote_replica() or not player_nodes.has(peer_id):
		return
	var actor := _get_player_node(peer_id)
	if actor == null or not (payload.get("projectiles") is Array) or payload.projectiles.size() > 32:
		return
	if payload.projectiles.is_empty() and not is_instance_valid(actor.get("spark_relay_controller")):
		return
	actor._ensure_combat_interactions()
	actor._ensure_spark_relay().apply_network_state(payload)

func _pack_shared_build_state(payload: Dictionary) -> Dictionary:
	if not (payload.get("state") is Dictionary) or not (payload.get("run") is String) or not (payload.get("room") is int) or not (payload.get("serial") is int) or not (payload.get("epoch") is int):
		return {}
	var values: Array = []
	for property: String in SHARED_BUILD_STATE_PROPERTIES:
		var value: Variant = payload.state.get(property)
		if value != null and not (value is bool or value is int or (value is float and is_finite(value))):
			return {}
		values.append(value)
	var packed := {"run": payload.run, "room": payload.room, "serial": payload.serial, "epoch": payload.epoch, "v": values}
	if payload.get("effigy") is Dictionary:
		var state: Dictionary = payload.effigy
		if not (state.get("deployed") is bool and state.get("position") is Vector2 and state.get("seq") is int) or not (state.position as Vector2).is_finite():
			return {}
		packed["e"] = [state.deployed, state.position.x, state.position.y, state.seq, int(state.get("attacks", 0))]
	return packed

func _unpack_shared_build_state(payload: Dictionary) -> Dictionary:
	if not (payload.get("v") is Array) or payload.v.size() != SHARED_BUILD_STATE_PROPERTIES.size() or not (payload.get("run") is String) or not (payload.get("room") is int) or not (payload.get("serial") is int) or not (payload.get("epoch") is int):
		return {}
	var state: Dictionary = {}
	for index in range(SHARED_BUILD_STATE_PROPERTIES.size()):
		var value: Variant = payload.v[index]
		if value != null and not (value is bool or value is int or (value is float and is_finite(value))):
			return {}
		if value != null:
			state[SHARED_BUILD_STATE_PROPERTIES[index]] = value
	var unpacked := {"run": payload.run, "room": payload.room, "serial": payload.serial, "epoch": payload.epoch, "state": state}
	if payload.has("e"):
		var effigy: Variant = payload.e
		if not (effigy is Array) or effigy.size() != 5 or not (effigy[0] is bool) or not (effigy[3] is int) or not (effigy[4] is int) or int(effigy[4]) < 0:
			return {}
		for index: int in [1, 2]:
			if not (effigy[index] is int or effigy[index] is float) or not is_finite(float(effigy[index])):
				return {}
		unpacked["effigy"] = {"deployed": effigy[0], "position": Vector2(float(effigy[1]), float(effigy[2])), "seq": effigy[3], "attacks": effigy[4]}
	return unpacked


## Called by the local owner of a player when their dash phasing state toggles.
## Replicates the flag to every other peer so host-side hit detection (and any other
## peer's local copy) respects the local player's dash i-frames.
func broadcast_dash_phasing_state(peer_id: int, active: bool) -> void:
	if peer_id <= 0:
		return
	if peer_id != local_peer_id:
		return
	if multiplayer_session_manager == null or not bool(multiplayer_session_manager.is_session_connected()):
		return
	_sync_dash_phasing_state.rpc(peer_id, active)


@rpc("any_peer", "call_remote", "reliable")
func _sync_dash_phasing_state(peer_id: int, active: bool) -> void:
	if peer_id == local_peer_id:
		return
	var player_node := _get_player_node(peer_id)
	if player_node == null:
		return
	player_node.set("dash_phasing_active", active)


## Host-authoritative: dispatch a polar shift impulse + dash lockout to the player owned by target_peer_id.
func send_polar_shift_effect(target_peer_id: int, direction: Vector2, force: float, dash_lockout_duration: float) -> void:
	if multiplayer_session_manager == null or not bool(multiplayer_session_manager.is_session_connected()):
		_apply_polar_shift_effect_local(target_peer_id, direction, force, dash_lockout_duration)
		return
	if not bool(multiplayer_session_manager.should_broadcast()):
		return
	if target_peer_id == local_peer_id:
		_apply_polar_shift_effect_local(target_peer_id, direction, force, dash_lockout_duration)
		return
	_rpc_apply_polar_shift_effect.rpc_id(target_peer_id, target_peer_id, direction, force, dash_lockout_duration)


@rpc("authority", "call_remote", "reliable")
func _rpc_apply_polar_shift_effect(target_peer_id: int, direction: Vector2, force: float, dash_lockout_duration: float) -> void:
	_apply_polar_shift_effect_local(target_peer_id, direction, force, dash_lockout_duration)


func _apply_polar_shift_effect_local(target_peer_id: int, direction: Vector2, force: float, dash_lockout_duration: float) -> void:
	var player_node := _get_player_node(target_peer_id)
	if player_node == null:
		return
	player_node.apply_polar_shift_impulse(direction, force)
	if dash_lockout_duration > 0.0:
		player_node.apply_polar_shift_dash_lockout(dash_lockout_duration)


## Host-authoritative: dispatch an external movement slow (duration, multiplier) to a specific player.
func send_external_slow(target_peer_id: int, duration: float, mult: float) -> void:
	if duration <= 0.0 or mult >= 1.0:
		return
	if multiplayer_session_manager == null or not bool(multiplayer_session_manager.is_session_connected()):
		_apply_external_slow_local(target_peer_id, duration, mult)
		return
	if not bool(multiplayer_session_manager.should_broadcast()):
		return
	if target_peer_id == local_peer_id:
		_apply_external_slow_local(target_peer_id, duration, mult)
		return
	_rpc_apply_external_slow.rpc_id(target_peer_id, target_peer_id, duration, mult)


@rpc("authority", "call_remote", "reliable")
func _rpc_apply_external_slow(target_peer_id: int, duration: float, mult: float) -> void:
	_apply_external_slow_local(target_peer_id, duration, mult)


func _apply_external_slow_local(target_peer_id: int, duration: float, mult: float) -> void:
	var player_node := _get_player_node(target_peer_id)
	if player_node == null:
		return
	if player_node.has_method("apply_external_slow"):
		player_node.apply_external_slow(duration, mult)


## Host-authoritative: dispatch an enemy-killed notification to the player who got the kill credit.
func send_enemy_killed(target_peer_id: int, kill_pos: Vector2, suppress_launch: bool = false, kill_proc_suppression: int = 0, interaction: Dictionary = {}) -> void:
	suppress_launch = suppress_launch or DAMAGEABLE.is_launch_suppressed()
	kill_proc_suppression = DAMAGEABLE.sanitize_kill_proc_suppression(kill_proc_suppression) | DAMAGEABLE.get_kill_proc_suppression()
	if interaction.is_empty():
		interaction = DAMAGEABLE.current_interaction_context()
	if multiplayer_session_manager == null or not bool(multiplayer_session_manager.is_session_connected()):
		_apply_enemy_killed_local(target_peer_id, kill_pos, suppress_launch, kill_proc_suppression, interaction)
		return
	if not bool(multiplayer_session_manager.should_broadcast()):
		return
	if target_peer_id == local_peer_id:
		_apply_enemy_killed_local(target_peer_id, kill_pos, suppress_launch, kill_proc_suppression, interaction)
		return
	# Damage modifiers are resolved against the host's copy of the owner. Keep
	# this kill-driven Mission counter current without replaying other kill powers.
	var owner := _get_player_node(target_peer_id)
	if is_instance_valid(owner) and owner.has_method("_trigger_combo_relay_kill"):
		owner._trigger_combo_relay_kill()
	_rpc_apply_enemy_killed.rpc_id(target_peer_id, target_peer_id, kill_pos, suppress_launch, kill_proc_suppression, interaction)
	# The ordinary owner kill callback runs first; the later cumulative snapshot
	# then confirms that same count rather than adding a second client stack.
	if is_instance_valid(owner) and is_instance_valid(owner.get("shared_build_runtime")):
		owner.shared_build_runtime.publish_state()


@rpc("authority", "call_remote", "reliable")
func _rpc_apply_enemy_killed(target_peer_id: int, kill_pos: Vector2, suppress_launch: bool = false, kill_proc_suppression: int = 0, interaction: Dictionary = {}) -> void:
	_apply_enemy_killed_local(target_peer_id, kill_pos, suppress_launch, kill_proc_suppression, interaction)


func _apply_enemy_killed_local(target_peer_id: int, kill_pos: Vector2, suppress_launch: bool = false, kill_proc_suppression: int = 0, interaction: Dictionary = {}) -> void:
	var player_node := _get_player_node(target_peer_id)
	if player_node == null:
		return
	if player_node.has_method("notify_enemy_killed"):
		var previous_interaction := DAMAGEABLE.begin_interaction_scope(interaction)
		var previous_kill_scope := DAMAGEABLE.begin_kill_proc_scope(kill_proc_suppression)
		if suppress_launch:
			DAMAGEABLE.begin_secondary_scope()
		player_node.notify_enemy_killed(kill_pos)
		if suppress_launch:
			DAMAGEABLE.end_secondary_scope()
		DAMAGEABLE.end_kill_proc_scope(previous_kill_scope)
		DAMAGEABLE.end_interaction_scope(previous_interaction)

## Send cancellation immediately, before a later damage RPC can use old roots.
func broadcast_interaction_epoch(peer_id: int, epoch: int, run: String, room: int) -> bool:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED or peer_id != multiplayer.get_unique_id():
		return false
	if epoch <= 0 or run.is_empty() or run != GameStateReplicationService.get_current_run_sync_token() or room != EnemyReplicationService._current_room_sync_id():
		return false
	_sync_interaction_epoch.rpc(peer_id, epoch, run, room)
	return true

@rpc("any_peer", "call_local", "reliable")
func _sync_interaction_epoch(peer_id: int, epoch: int, run: String, room: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if sender != peer_id or not MultiplayerSessionManager.get_peer_ids().has(sender) or epoch <= 0:
		return
	if run.is_empty() or run != GameStateReplicationService.get_current_run_sync_token() or room != EnemyReplicationService._current_room_sync_id():
		return
	var previous: Dictionary = _interaction_epoch_announcements.get(peer_id, {})
	if previous.get("run") == run and previous.get("room") == room and epoch <= int(previous.get("epoch", 0)):
		return
	_interaction_epoch_announcements[peer_id] = {"epoch": epoch, "run": run, "room": room}
	_apply_interaction_epoch_to_player(peer_id)

func _apply_interaction_epoch_to_player(peer_id: int) -> void:
	var entry: Dictionary = _interaction_epoch_announcements.get(peer_id, {})
	var player_node: Variant = player_nodes.get(peer_id)
	if entry.is_empty() or not is_instance_valid(player_node):
		return
	var controller: Node = player_node.get("combat_interactions")
	if is_instance_valid(controller):
		controller.accept_epoch(int(entry.epoch), String(entry.run), int(entry.room))

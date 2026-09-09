extends Node
## Host-accepted interactions use one ledger per player. Effects retain their root
## through delayed hits; eviction burns sequence numbers instead of reopening them.

const REGISTRY := preload("res://scripts/shared/combat_interaction_registry.gd")
const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")

var player: CharacterBody2D
var _next_sequence: int = 0
var _epoch: int = 1
var _accepted_epoch: int = 0
var _announced_identity: String = ""
var _identity: String = ""
var _roots: Dictionary = {}
var _retired_through: int = 0
var _state_sequence: int = 0
var _received_state_sequence: int = 0
var _visual_epoch: int = 0
var _cancel_generation: int = 0

func initialize(owner_player: CharacterBody2D) -> void:
	player = owner_player
	set_process(false)
	set_physics_process(false)

func _owner_id() -> int:
	var peer_id := int(player.get("player_id")) if is_instance_valid(player) else 0
	return peer_id if peer_id > 0 else DAMAGEABLE._resolve_local_peer_id()

func _local_owner() -> bool:
	return is_instance_valid(player) and bool(player._is_local_control_owner())

func _refresh_identity() -> void:
	var identity := "%s|%d" % [REGISTRY.current_run(), REGISTRY.current_room()]
	if identity == _identity:
		return
	_identity = identity
	_roots.clear()
	_retired_through = 0
	_accepted_epoch = 0
	_received_state_sequence = 0
	_visual_epoch = 0
	_announced_identity = ""
	_cancel_generation += 1

func begin_action(kind: String) -> Dictionary:
	if not _local_owner() or kind.is_empty() or kind.length() > 48:
		return {}
	var inherited := DAMAGEABLE.current_interaction_context()
	if not inherited.is_empty():
		return inherited
	_refresh_identity()
	if REGISTRY.current_run().is_empty():
		return {}
	_next_sequence += 1
	_announce_epoch()
	return {"run": REGISTRY.current_run(), "room": REGISTRY.current_room(),
		"owner": _owner_id(), "seq": _next_sequence, "epoch": _epoch,
		"kind": kind, "ancestry": 0}

func _announce_epoch() -> void:
	var identity := "%s|%d" % [_identity, _epoch]
	if identity == _announced_identity:
		return
	if MultiplayerSessionManager.is_session_connected():
		var service := get_node_or_null("/root/PlayerReplicationService")
		if service == null or not service.broadcast_interaction_epoch(_owner_id(), _epoch, REGISTRY.current_run(), REGISTRY.current_room()):
			return
	else:
		accept_epoch(_epoch, REGISTRY.current_run(), REGISTRY.current_room())
	_announced_identity = identity

func accept_epoch(epoch: int, run: String, room: int) -> void:
	_refresh_identity()
	if run.is_empty() or run != REGISTRY.current_run() or room != REGISTRY.current_room() or epoch <= _accepted_epoch:
		return
	_accepted_epoch = epoch
	_roots.clear()
	_retired_through = 0
	_cancel_generation += 1

func accepts_action(action: Dictionary) -> bool:
	_refresh_identity()
	if action.is_empty() or int(action.get("owner", 0)) != _owner_id():
		return false
	if _accepted_epoch == 0 and not MultiplayerSessionManager.is_session_connected():
		accept_epoch(_epoch, REGISTRY.current_run(), REGISTRY.current_room())
	return int(action.get("epoch", 0)) == _accepted_epoch and int(action.get("seq", 0)) > _retired_through

func cancel() -> void:
	_refresh_identity()
	_cancel_generation += 1
	if _local_owner():
		_epoch += 1
		_announced_identity = ""
		_announce_epoch()
	# A remote build snapshot must not independently reopen the owner's ledger.
	# Its authenticated owner announces a newer epoch when cancelling actions.

func _ledger(action: Dictionary) -> Dictionary:
	if not accepts_action(action):
		return {}
	var root_seq := int(action.seq)
	if not _roots.has(root_seq):
		if _roots.size() >= REGISTRY.MAX_ROOTS:
			var oldest := int(_roots.keys().min())
			_roots.erase(oldest)
			_retired_through = maxi(_retired_through, oldest)
			if root_seq <= _retired_through:
				return {}
		_roots[root_seq] = {"targets": {}, "attack_targets": {}, "reactions": {}, "descriptors": {}, "discharged": false}
	return _roots[root_seq]

func has_attack_hit(action: Dictionary, target_id: int) -> bool:
	if not accepts_action(action) or not _roots.has(int(action.get("seq", 0))):
		return false
	var ledger: Dictionary = _roots[int(action.seq)]
	return (ledger.get("attack_targets", {}) as Dictionary).has(target_id)

func has_reaction(action: Dictionary, rule: String, target_id: int = 0) -> bool:
	if rule.is_empty() or rule.length() > 48 or target_id < 0 or not accepts_action(action) or not _roots.has(int(action.seq)):
		return false
	var ledger: Dictionary = _roots[int(action.seq)]
	return (ledger.get("reactions", {}) as Dictionary).has("%s:%d" % [rule, target_id])

func claim_reaction(action: Dictionary, rule: String, target_id: int = 0) -> bool:
	if rule.is_empty() or rule.length() > 48 or target_id < 0:
		return false
	var ledger := _ledger(action)
	if ledger.is_empty():
		return false
	var key := "%s:%d" % [rule, target_id]
	if ledger.reactions.has(key) or ledger.reactions.size() >= REGISTRY.MAX_TARGETS_PER_ROOT * 4:
		return false
	ledger.reactions[key] = true
	return true

func get_echo_descriptor(action: Dictionary, original_source: String, scale: float = 0.55) -> Dictionary:
	if not is_finite(scale) or scale < 0.0 or not REGISTRY.is_attack_hit(original_source) or not accepts_action(action) or not _roots.has(int(action.seq)):
		return {}
	var ledger: Dictionary = _roots[int(action.seq)]
	var descriptor: Dictionary = ledger.get("descriptors", {}).get(original_source, {})
	if descriptor.is_empty():
		return {}
	return {"raw_amount": float(descriptor.raw_amount) * scale, "damage_coefficient": float(descriptor.damage_coefficient) * scale}

func _dispatch_shared_hit(event: Dictionary, action: Dictionary, ledger: Dictionary) -> void:
	if not bool(event.get("shared", false)):
		return
	var target_id := int(event.get("target_id", 0))
	var source := String(action.source)
	var previous := DAMAGEABLE.begin_interaction_scope(action)
	if REGISTRY.is_attack_hit(source) and target_id > 0 and not ledger.attack_targets.has(target_id) and ledger.attack_targets.size() < REGISTRY.MAX_TARGETS_PER_ROOT:
		event["first_attack_hit"] = ledger.attack_targets.is_empty()
		event["first_target_in_action"] = true
		ledger.attack_targets[target_id] = true
		var prior_descriptor: Dictionary = ledger.descriptors.get(source, {})
		if prior_descriptor.is_empty() or float(event.raw_amount) > float(prior_descriptor.raw_amount):
			ledger.descriptors[source] = {"raw_amount": float(event.raw_amount), "damage_coefficient": float(event.damage_coefficient)}
		if player.has_method("_on_shared_attack_hit"):
			player._on_shared_attack_hit(event)
	if player.has_method("_on_shared_damage"):
		player._on_shared_damage(event)
	DAMAGEABLE.end_interaction_scope(previous)

func accept_hit(event: Dictionary) -> void:
	if MultiplayerSessionManager.is_remote_replica() or not is_instance_valid(player):
		return
	var action := REGISTRY.validate_action(event.get("interaction"), _owner_id())
	if int(event.get("cancel_generation", _cancel_generation)) != _cancel_generation:
		return
	if not accepts_action(action) or not bool(player.get("combat_damage_enabled")) or not bool(player.get("_is_alive_state")) or bool(player.get("encounter_input_frozen")):
		return
	if (int(action.get("traits", 0)) & REGISTRY.HIT) == 0 or int(event.get("applied", 0)) <= 0:
		return
	var ledger := _ledger(action)
	if ledger.is_empty():
		return
	_dispatch_shared_hit(event, action, ledger)
	if int(event.get("cancel_generation", _cancel_generation)) != _cancel_generation or not accepts_action(action):
		return
	if not bool(player.get("reward_storm_crown")) or (int(action.get("ancestry", 0)) & REGISTRY.CROWN_ANCESTRY) != 0:
		return
	var target_id := int(event.get("target_id", 0))
	if target_id <= 0 or ledger.targets.has(target_id) or ledger.targets.size() >= REGISTRY.MAX_TARGETS_PER_ROOT:
		return
	ledger.targets[target_id] = true
	if bool(ledger.discharged):
		return
	var every := maxi(1, int(player.get("storm_crown_proc_every")))
	player.storm_crown_hit_counter += 1
	if int(player.storm_crown_hit_counter) % every != 0:
		_publish_state(PackedVector2Array(), action)
		return
	ledger.discharged = true
	_discharge(event, action)

func _discharge(event: Dictionary, action: Dictionary) -> void:
	var origin: Vector2 = event.get("position", Vector2.INF)
	if not origin.is_finite():
		return
	var shared := bool(event.get("shared", false))
	var ratio := float(player.get("storm_crown_damage_ratio"))
	var raw_damage := float(event.get("raw_amount", event.get("amount", 0))) * ratio
	var damage := maxi(0 if shared else 1, int(round(raw_damage)))
	if not shared:
		damage = int(player._apply_objective_mutator_damage_mult(damage))
	var reach := maxf(0.0, float(player.get("storm_crown_chain_radius")))
	var remaining := clampi(int(player.get("storm_crown_chain_targets")), 0, 6)
	var ordinary_hops := remaining
	var visited: Dictionary = {int(event.target_id): true}
	var conduction_available := int(player.get("storm_crown_stacks")) >= 2
	if conduction_available and bool(event.get("pre_slowed", false)):
		remaining += 1
		conduction_available = false
	var links := PackedVector2Array([origin])
	var generation := _cancel_generation
	var previous := DAMAGEABLE.begin_interaction_scope(action)
	while remaining > 0:
		var nearest: Node2D = null
		var nearest_distance := INF
		for node in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(node) or not (node is Node2D) or node.is_queued_for_deletion() or DAMAGEABLE._read_target_health(node) <= 0:
				continue
			var enemy := node as Node2D
			if visited.has(enemy.get_instance_id()):
				continue
			var distance := origin.distance_squared_to(enemy.global_position)
			if distance <= reach * reach and distance < nearest_distance:
				nearest = enemy
				nearest_distance = distance
		if nearest == null:
			break
		var next_position := nearest.global_position
		var was_slowed := bool(nearest.is_slowed())
		visited[nearest.get_instance_id()] = true
		var before := DAMAGEABLE._read_target_health(nearest)
		var context := {"attack_origin": origin}
		if shared:
			context["raw_amount"] = raw_damage
			context["damage_coefficient"] = float(event.get("damage_coefficient", 0.0)) * ratio
		DAMAGEABLE.apply_damage(nearest, damage, REGISTRY.damage_context(action, "storm_crown", context), int(action.owner))
		var accepted := is_instance_valid(nearest) and before > DAMAGEABLE._read_target_health(nearest)
		if generation != _cancel_generation or not bool(player.get("_is_alive_state")) or not bool(player.get("combat_damage_enabled")):
			break
		if conduction_available and accepted and was_slowed:
			remaining += 1
			conduction_available = false
		links.append(next_position)
		origin = next_position
		remaining -= 1
	DAMAGEABLE.end_interaction_scope(previous)
	if generation == _cancel_generation:
		_publish_state(links, action, ordinary_hops + 1 if links.size() - 1 > ordinary_hops else -1)

func _publish_state(links: PackedVector2Array, action: Dictionary, conduction_index: int = -1) -> void:
	_state_sequence += 1
	var payload := {"run": action.run, "room": action.room, "epoch": action.epoch,
		"serial": _state_sequence, "counter": int(player.storm_crown_hit_counter), "links": links, "conduction_index": conduction_index}
	apply_network_state(payload)
	if MultiplayerSessionManager.should_broadcast():
		PlayerReplicationService.broadcast_cue_event(_owner_id(), "combat_interaction_state", payload, true)

func apply_network_state(payload: Dictionary) -> void:
	_refresh_identity()
	if not is_instance_valid(player) or payload.get("run") != REGISTRY.current_run() or payload.get("room") != REGISTRY.current_room():
		return
	for key in ["epoch", "serial", "counter", "conduction_index"]:
		if not (payload.get(key) is int):
			return
	var links: Variant = payload.get("links")
	if not (links is PackedVector2Array) or links.size() > 8 or int(payload.counter) < 0:
		return
	var conduction_index := int(payload.conduction_index)
	if conduction_index != -1 and (conduction_index < 1 or conduction_index >= links.size()):
		return
	for point in links:
		if not point.is_finite():
			return
	var epoch := int(payload.epoch)
	if epoch < _accepted_epoch or epoch < _visual_epoch or (_local_owner() and epoch != _epoch):
		return
	if epoch == _visual_epoch and int(payload.serial) <= _received_state_sequence:
		return
	if MultiplayerSessionManager.is_session_connected():
		var sender := multiplayer.get_remote_sender_id()
		if sender > 0 and sender != 1:
			return
	_visual_epoch = epoch
	_received_state_sequence = int(payload.serial)
	player.storm_crown_hit_counter = int(payload.counter)
	var feedback: Node = player.get("player_feedback")
	if feedback != null and not links.is_empty():
		feedback.play_storm_crown_discharge(links[0])
		for index in range(1, links.size()):
			var conductive := index == conduction_index
			var color := Color(0.42, 1.0, 0.92, 0.95) if conductive else Color(0.98, 0.98, 0.76, 0.92)
			feedback.play_chain_lightning(links[index - 1], links[index], color)
			feedback.play_world_ring(links[index], 20.0 if conductive else 16.0, color, 0.14 if conductive else 0.1)
		player.storm_crown_discharge_flash_left = player.storm_crown_discharge_flash_duration
	player.queue_redraw()

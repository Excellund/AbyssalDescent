extends RefCounted

const ENEMY_BASE_SCRIPT := preload("res://scripts/enemy_base.gd")
const INTERACTIONS := preload("res://scripts/shared/combat_interaction_registry.gd")
const TARGET_STATUS := preload("res://scripts/shared/combat_target_status.gd")
const SHARED_MODIFIERS := preload("res://scripts/shared/shared_damage_modifiers.gd")
const STAT_ATTRIBUTION_TRACE := false
static var _secondary_scope_depth: int = 0
const KILL_PROC_SUPPRESS_FRACTURE := 1
const KILL_PROC_SUPPRESS_ECHO_PULSE := 2
const KILL_PROC_SUPPRESSION_MASK := KILL_PROC_SUPPRESS_FRACTURE | KILL_PROC_SUPPRESS_ECHO_PULSE
static var _kill_proc_suppression: int = 0
static var _interaction_scope: Dictionary = {}
static var _damage_depth: int = 0
static var _pending_interaction_hits: Array[Dictionary] = []
static var _flushing_interactions: bool = false

## Plain value scopes cross synchronous descendants; delayed effects keep a copy.
static func begin_interaction_scope(action: Dictionary) -> Dictionary:
	var previous := _interaction_scope
	_interaction_scope = action.duplicate()
	return previous

static func end_interaction_scope(previous: Dictionary) -> void:
	_interaction_scope = previous

static func current_interaction_context() -> Dictionary:
	return _interaction_scope.duplicate()

static func _with_interaction_context(context: Dictionary) -> Dictionary:
	var raw: Variant = context.get("interaction", _interaction_scope)
	if not (raw is Dictionary) or raw.is_empty():
		return context
	var source := String(context.get("attack_type", raw.get("source", "")))
	var merged := INTERACTIONS.damage_context(raw, source, context)
	# A child cannot shed its parent's reaction ancestry during a kill callback.
	if not _interaction_scope.is_empty():
		merged.interaction["ancestry"] = int(merged.interaction.get("ancestry", 0)) | int(_interaction_scope.get("ancestry", 0))
	return merged

static func _capture_interaction_hit(target: Object, amount: int, context: Dictionary, source_peer: int) -> Dictionary:
	if not (target is Node2D) or not target.is_in_group("enemies"):
		return {}
	var action := INTERACTIONS.validate_action(context.get("interaction"), source_peer)
	if action.is_empty() or (int(action.traits) & INTERACTIONS.HIT) == 0:
		return {}
	var owner := _find_combat_owner(source_peer)
	var controller: Node = owner.get("combat_interactions") if owner != null else null
	if not is_instance_valid(controller) or not controller.accepts_action(action):
		return {}
	return {"interaction": action, "target": weakref(target), "target_id": target.get_instance_id(),
		"position": (target as Node2D).global_position, "amount": amount,
		"attack_origin": context.get("attack_origin", Vector2.INF), "context": context.duplicate(true),
		"pre_slowed": bool(target.is_slowed()) if target.has_method("is_slowed") else false,
		"controller": weakref(controller), "cancel_generation": int(controller.get("_cancel_generation"))}

static func _flush_interaction_hits() -> void:
	if _damage_depth > 0 or _flushing_interactions:
		return
	_flushing_interactions = true
	var processed := 0
	while not _pending_interaction_hits.is_empty() and processed < INTERACTIONS.MAX_PENDING_HITS:
		var event: Dictionary = _pending_interaction_hits.pop_front()
		var controller: Variant = event.controller.get_ref()
		if is_instance_valid(controller):
			controller.accept_hit(event)
		processed += 1
	_pending_interaction_hits.clear()
	_flushing_interactions = false

## Only the existing non-chaining kill rules belong here. This mask does not
## change primary/secondary classification, kill credit, or other kill benefits.
static func sanitize_kill_proc_suppression(value: Variant) -> int:
	return int(value) & KILL_PROC_SUPPRESSION_MASK if value is int else 0

static func get_kill_proc_suppression() -> int:
	return _kill_proc_suppression

static func is_kill_proc_suppressed(mask: int) -> bool:
	return (_kill_proc_suppression & mask) != 0

## Returns the previous scope to restore after synchronous damage or an RPC's
## kill callback. Nested effects inherit the existing restrictions.
static func begin_kill_proc_scope(mask: int) -> int:
	var previous := _kill_proc_suppression
	_kill_proc_suppression |= sanitize_kill_proc_suppression(mask)
	return previous

static func end_kill_proc_scope(previous: int) -> void:
	_kill_proc_suppression = sanitize_kill_proc_suppression(previous)

## Scope survives synchronous kill procs; RPC boundaries carry its boolean value.
static func begin_secondary_scope() -> void:
	_secondary_scope_depth += 1

static func end_secondary_scope() -> void:
	_secondary_scope_depth = maxi(0, _secondary_scope_depth - 1)

static func is_launch_suppressed() -> bool:
	return _secondary_scope_depth > 0

# Shared helper to enforce the take_damage contract consistently.
static func can_take_damage(target: Object) -> bool:
	return is_instance_valid(target)

## Boss/Apex telegraphs must never be disabled by player-created displacement.
static func is_displacement_immune(target: Object) -> bool:
	if not is_instance_valid(target):
		return true
	var script := target.get_script() as Script
	while script != null:
		var file := script.resource_path.get_file()
		if file.begins_with("enemy_boss") or file in ["enemy_seamlock.gd", "enemy_mirrorline.gd", "enemy_toll.gd", "enemy_breakwater.gd"]:
			return true
		script = script.get_base_script()
	return false

static func apply_damage(target: Object, amount: int, damage_context: Dictionary = {}, source_peer_id: int = 0) -> bool:
	var shared := damage_context.has("damage_coefficient")
	if amount < 0 or (amount == 0 and not shared and damage_context.get("hunters_snare_aoe_bonus") != true):
		return false
	if not can_take_damage(target):
		return false
	var route_to_host := _should_route_enemy_damage_to_host(target)
	source_peer_id = _resolve_source_peer(source_peer_id, route_to_host)
	damage_context = _with_interaction_context(damage_context)
	damage_context = _with_attack_origin(target, damage_context, source_peer_id)
	var secondary := is_launch_suppressed() or bool(damage_context.get("secondary", false))
	if secondary:
		damage_context = damage_context.duplicate(true)
		damage_context["secondary"] = true
	var kill_proc_suppression := _kill_proc_suppression | sanitize_kill_proc_suppression(damage_context.get("kill_proc_suppression", 0))
	if kill_proc_suppression > 0 or damage_context.has("kill_proc_suppression"):
		damage_context = damage_context.duplicate()
		damage_context["kill_proc_suppression"] = kill_proc_suppression
	if route_to_host:
		_route_enemy_damage_to_host(target, amount, damage_context)
		return true
	var shared_event: Dictionary = {}
	if shared:
		shared_event = _resolve_shared_damage(target, amount, damage_context, source_peer_id)
		if shared_event.is_empty():
			return false
		amount = int(shared_event.amount)
	elif damage_context.get("hunters_snare_aoe_bonus") == true:
		var action := INTERACTIONS.validate_action(damage_context.get("interaction"), source_peer_id)
		var owner := _find_combat_owner(source_peer_id)
		var controller: Node = owner.get("combat_interactions") if owner != null else null
		if not action.is_empty() and action.source == "static_wake" and is_instance_valid(controller) and controller.accepts_action(action) and owner.has_method("_hunters_snare_aoe_bonus_against"):
			amount += maxi(0, int(owner._hunters_snare_aoe_bonus_against(target)))
	if amount <= 0:
		_commit_damage_fraction(shared_event)
		return false
	var health_before := _read_target_health(target)
	var interaction_event := _capture_interaction_hit(target, amount, damage_context, source_peer_id) if health_before > 0 else {}
	if not interaction_event.is_empty() and not shared_event.is_empty():
		interaction_event.merge(shared_event, true)
	var accepted_action := INTERACTIONS.validate_action(damage_context.get("interaction", {}), source_peer_id)
	if not accepted_action.is_empty() and target is Node2D:
		var origin: Variant = damage_context.get("attack_origin")
		if origin is Vector2 and origin.is_finite():
			accepted_action["attack_origin"] = origin
			var direction: Variant = damage_context.get("damage_direction", damage_context.get("attack_direction", (target as Node2D).global_position - origin))
			if direction is Vector2 and direction.is_finite() and direction.length_squared() > 0.0:
				accepted_action["damage_direction"] = direction.normalized()
	var previous_interaction := begin_interaction_scope(accepted_action)
	_damage_depth += 1
	# Death signals fire inside take_damage. Make this hit's owner visible to
	# kill-triggered powers before those signals, then undo rejected hits.
	var pending_credit := _prepare_enemy_damage_credit(target, health_before, source_peer_id)
	var previous_kill_scope := begin_kill_proc_scope(kill_proc_suppression)
	if secondary:
		begin_secondary_scope()
	if health_before > 0:
		_apply_declared_hit_slows(target, damage_context, source_peer_id)
	if damage_context.is_empty():
		target.take_damage(amount)
	else:
		target.take_damage(amount, damage_context)
	_restore_rejected_damage_credit(target, health_before, pending_credit)
	_report_enemy_damage_applied(target, health_before, source_peer_id)
	var health_after := _read_target_health(target)
	if health_after >= 0 and health_after < health_before:
		_commit_damage_fraction(shared_event)
	if not secondary and health_after > 0 and health_after < health_before and String(damage_context.get("attack_type", "")) in ["melee", "razor_wind", "blast_drive"]:
		_arm_primary_launch(target, source_peer_id)
	if secondary:
		end_secondary_scope()
	end_kill_proc_scope(previous_kill_scope)
	end_interaction_scope(previous_interaction)
	_damage_depth -= 1
	if not interaction_event.is_empty() and health_after >= 0 and health_after < health_before and _pending_interaction_hits.size() < INTERACTIONS.MAX_PENDING_HITS:
		interaction_event["applied"] = health_before - health_after
		_pending_interaction_hits.append(interaction_event)
	_flush_interaction_hits()
	return true


static func _resolve_shared_damage(target: Object, legacy_amount: int, context: Dictionary, source_peer: int) -> Dictionary:
	if not is_instance_valid(target) or _read_target_health(target) <= 0:
		return {}
	var raw: Variant = context.get("raw_amount", legacy_amount)
	var coefficient: Variant = context.get("damage_coefficient")
	if not SHARED_MODIFIERS.valid_number(raw) or not SHARED_MODIFIERS.valid_number(coefficient) or float(raw) < 0.0 or float(coefficient) < 0.0:
		return {}
	var action := INTERACTIONS.validate_action(context.get("interaction"), source_peer)
	var owner := _find_combat_owner(source_peer)
	var controller: Node = owner.get("combat_interactions") if owner != null else null
	if action.is_empty() or (int(action.traits) & INTERACTIONS.HIT) == 0 or not is_instance_valid(controller) or not controller.accepts_action(action):
		return {}
	var state: Node = _target_status(target, true)
	if state == null:
		return {}
	var pre: Dictionary = state.snapshot(source_peer)
	pre["slowed"] = bool(target.is_slowed()) if target.has_method("is_slowed") else false
	var descriptor := {"raw_amount": float(raw), "damage_coefficient": float(coefficient), "context": context.duplicate(true)}
	var direct := INTERACTIONS.is_attack_hit(String(action.source))
	if direct and not controller.has_attack_hit(action, target.get_instance_id()) and owner.has_method("_prepare_shared_attack_damage"):
		var prepared: Variant = owner._prepare_shared_attack_damage(target, descriptor.duplicate(true), action)
		if prepared is Dictionary:
			descriptor.merge(prepared, true)
	elif String(action.source) == "sovereigns_double":
		var inherited: Dictionary = controller.get_echo_descriptor(action, String(action.get("echo_source", "")), 0.55)
		if not inherited.is_empty():
			descriptor.merge(inherited, true)
	if not SHARED_MODIFIERS.valid_number(descriptor.raw_amount) or not SHARED_MODIFIERS.valid_number(descriptor.damage_coefficient) or float(descriptor.raw_amount) < 0.0 or float(descriptor.damage_coefficient) < 0.0:
		return {}
	var resolved := SHARED_MODIFIERS.resolve(owner, target, float(descriptor.raw_amount), float(descriptor.damage_coefficient), pre, direct)
	if not is_finite(resolved) or resolved < 0.0:
		return {}
	var round_down: bool = String(action.source) == "static_wake" and context.get("fractional_rounding") == "floor"
	var fraction: Dictionary = state.prepare_damage(source_peer, String(action.source), resolved, round_down)
	return {"shared": true, "raw_amount": float(descriptor.raw_amount), "damage_coefficient": float(descriptor.damage_coefficient),
		"pending_bonuses": descriptor.get("pending_bonuses", {}), "pre_mark_ratio": float(pre.mark_ratio), "pre_dread_stacks": int(pre.dread_stacks),
		"pre_slowed": bool(pre.slowed), "amount": int(fraction.amount), "fraction_state": weakref(state), "fraction": fraction}

static func _commit_damage_fraction(event: Dictionary) -> void:
	if event.get("fraction_state") is WeakRef:
		var state: Variant = event.fraction_state.get_ref()
		if is_instance_valid(state):
			state.commit_damage(event.fraction)


static func _target_status(target: Object, create: bool = false) -> Node:
	if not is_instance_valid(target) or not (target is Node) or not target.is_in_group("enemies") or target.is_queued_for_deletion():
		return null
	var existing := target.get_node_or_null("SharedCombatStatus") as Node
	if existing != null or not create:
		return existing
	var state := TARGET_STATUS.new()
	state.name = "SharedCombatStatus"
	target.add_child(state)
	return state

static func status_snapshot(target: Object, source_peer_id: int = 0) -> Dictionary:
	var state := _target_status(target)
	return state.snapshot(source_peer_id) if state != null else {"mark_ratio": 0.0, "dread_stacks": 0}

static func clear_statuses(target: Object) -> void:
	var state := _target_status(target)
	if state != null:
		state.clear()

static func cancel_owner(source_peer_id: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or source_peer_id <= 0:
		return
	for state: Node in tree.get_nodes_in_group("shared_combat_status"):
		if is_instance_valid(state) and state.has_method("cancel_owner"):
			state.cancel_owner(source_peer_id)

static func get_status_network_state(target: Object) -> Dictionary:
	var state := _target_status(target)
	return state.network_state() if state != null else {}

static func get_status_network_packet(target: Object) -> PackedByteArray:
	var state := _target_status(target)
	return state.network_packet() if state != null else PackedByteArray()

static func apply_status_network_packet(target: Object, packet: PackedByteArray) -> bool:
	if not MultiplayerSessionManager.is_remote_replica() or packet.is_empty():
		return false
	var state := _target_status(target, true)
	return state.apply_network_packet(packet) if state != null else false

static func apply_status_network_state(target: Object, payload: Dictionary) -> bool:
	if not MultiplayerSessionManager.is_remote_replica() or payload.is_empty():
		return false
	var state := _target_status(target, true)
	return state.apply_network_state(payload) if state != null else false

static func _status_action(interaction: Dictionary, source_peer: int) -> Dictionary:
	var action := INTERACTIONS.validate_action(interaction if not interaction.is_empty() else current_interaction_context(), source_peer)
	var owner := _find_combat_owner(source_peer)
	var controller: Node = owner.get("combat_interactions") if owner != null else null
	return action if not action.is_empty() and is_instance_valid(controller) and controller.accepts_action(action) else {}

static func apply_mark(target: Object, source: String, ratio: float, duration: float, source_peer_id: int = 0, interaction: Dictionary = {}) -> bool:
	if not is_instance_valid(target) or _read_target_health(target) <= 0 or source not in TARGET_STATUS.MARK_SOURCES or not is_finite(ratio) or not is_finite(duration) or ratio <= 0.0 or duration <= 0.0:
		return false
	var route := _should_route_enemy_damage_to_host(target)
	source_peer_id = _resolve_source_peer(source_peer_id, route)
	var action := _status_action(interaction, source_peer_id)
	if action.is_empty():
		return false
	if route:
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null or tree.current_scene == null or not tree.current_scene.has_method("request_enemy_mark_from_client"):
			return false
		tree.current_scene.request_enemy_mark_from_client(int(target.get_meta("network_enemy_id", 0)), source, ratio, duration, action)
		return true
	var owner := _find_combat_owner(source_peer_id)
	if owner == null or owner.get("_is_alive_state") == false or owner.get("_combat_removed") == true:
		return false
	var enabled_property := "passive_cross_stitch" if source == "cross_stitch" else "reward_" + source
	if not bool(owner.get(enabled_property)):
		return false
	match source:
		"cross_stitch":
			# This passive is generated only by the accepted-attack boundary.
			var scope := current_interaction_context()
			var thread_ref: Variant = owner.get("cross_stitch_target")
			if MultiplayerSessionManager.is_remote_replica() or not INTERACTIONS.is_attack_hit(String(action.get("source", ""))) or scope.get("seq") != action.get("seq") or scope.get("owner") != source_peer_id or not (thread_ref is WeakRef) or thread_ref.get_ref() != target:
				return false
			ratio = 0.12
			duration = 4.0
		"wraithstep":
			ratio = SHARED_MODIFIERS.property_number(owner, "wraithstep_mark_bonus_ratio")
			duration = SHARED_MODIFIERS.property_number(owner, "wraithstep_mark_duration")
		"eclipse_mark":
			ratio = SHARED_MODIFIERS.property_number(owner, "eclipse_mark_bonus_ratio")
			duration = SHARED_MODIFIERS.property_number(owner, "eclipse_mark_duration")
		"dread_resonance":
			ratio = 0.1
			duration = 3.0
	var state := _target_status(target, true)
	return state.apply_mark(source_peer_id, source, ratio, duration) if state != null else false

static func add_dread_stack(target: Object, source_peer_id: int, cap: int, interaction: Dictionary) -> int:
	if MultiplayerSessionManager.is_remote_replica() or not is_instance_valid(target) or _read_target_health(target) <= 0:
		return 0
	var action := _status_action(interaction, source_peer_id)
	var owner := _find_combat_owner(source_peer_id)
	if action.is_empty() or not INTERACTIONS.is_attack_hit(String(action.source)) or owner == null or owner.get("_is_alive_state") == false or owner.get("_combat_removed") == true or not bool(owner.get("reward_dread_resonance")):
		return 0
	cap = mini(15, maxi(0, int(SHARED_MODIFIERS.property_number(owner, "dread_resonance_max_stacks"))))
	var controller: Node = owner.get("combat_interactions")
	var state := _target_status(target, true)
	if not controller.claim_reaction(action, "dread_stack", target.get_instance_id()):
		return int(state.snapshot(source_peer_id).dread_stacks)
	return state.add_dread(source_peer_id, cap, action)

static func _valid_slow(duration: float, mult: float) -> bool:
	return is_finite(duration) and is_finite(mult) and duration > 0.0 and mult > 0.0 and mult < 1.0

static func _apply_declared_hit_slows(target: Object, context: Dictionary, source_peer: int) -> void:
	if not target.has_method("apply_slow"):
		return
	var raw_action: Variant = context.get("interaction", {})
	if not (raw_action is Dictionary):
		return
	if not raw_action.is_empty():
		var action := INTERACTIONS.validate_action(raw_action, source_peer)
		var owner := _find_combat_owner(source_peer)
		var controller: Node = owner.get("combat_interactions") if owner != null else null
		if action.is_empty() or not is_instance_valid(controller) or not controller.accepts_action(action):
			return
	var declarations: Array = []
	if context.get("slow_on_hit") is Dictionary:
		declarations.append(context.slow_on_hit)
	if context.get("slows_on_hit") is Array:
		declarations.append_array(context.slows_on_hit)
	for index in range(mini(declarations.size(), 8)):
		var entry: Variant = declarations[index]
		if not (entry is Dictionary) or not (entry.get("duration") is float or entry.get("duration") is int) or not (entry.get("mult") is float or entry.get("mult") is int):
			continue
		var duration := float(entry.duration)
		var mult := float(entry.mult)
		if _valid_slow(duration, mult):
			target.apply_slow(duration, mult)

## Status gameplay is reliable and host-owned; visual cues cannot create slows.
static func apply_slow(target: Object, duration: float, mult: float, source_peer_id: int = 0, interaction: Dictionary = {}) -> bool:
	if not is_instance_valid(target) or not (target is ENEMY_BASE_SCRIPT) or target.is_queued_for_deletion() or _read_target_health(target) <= 0 or not _valid_slow(duration, mult):
		return false
	var route_to_host := _should_route_enemy_damage_to_host(target)
	source_peer_id = _resolve_source_peer(source_peer_id, route_to_host)
	var action := interaction if not interaction.is_empty() else current_interaction_context()
	if not action.is_empty():
		action = INTERACTIONS.validate_action(action, source_peer_id)
		if action.is_empty():
			return false
	if route_to_host:
		if action.is_empty():
			return false
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null or tree.current_scene == null:
			return false
		tree.current_scene.request_enemy_slow_from_client(int(target.get_meta("network_enemy_id", 0)), duration, mult, action)
		return true
	if not action.is_empty():
		var owner := _find_combat_owner(source_peer_id)
		var controller: Node = owner.get("combat_interactions") if owner != null else null
		if not is_instance_valid(controller) or not controller.accepts_action(action):
			return false
	target.apply_slow(duration, mult)
	return true


## Returns the original context when unchanged, otherwise a shallow copy.
## Origins describe geometry only; ownership comes from the authenticated peer
## argument, never from a caller-provided context field or an enemy's AI target.
static func _with_attack_origin(target: Object, context: Dictionary, source_peer_id: int) -> Dictionary:
	if not (target is Node) or not (target as Node).is_in_group("enemies"):
		return context
	var origin: Variant = context.get("attack_origin")
	if origin is Vector2 and (origin as Vector2).is_finite():
		return context
	var owner := _find_combat_owner(source_peer_id)
	if owner != null and owner.global_position.is_finite():
		var resolved := context.duplicate()
		resolved["attack_origin"] = owner.global_position
		return resolved
	if context.has("attack_origin"):
		var resolved := context.duplicate()
		resolved.erase("attack_origin")
		return resolved
	return context


static func _prepare_enemy_damage_credit(target: Object, health_before: int, source_peer_id: int) -> Dictionary:
	if health_before <= 0 or not (target is Node):
		return {}
	var enemy := target as Node
	if not enemy.is_in_group("enemies"):
		return {}
	var enemy_id := int(enemy.get_meta("network_enemy_id", 0))
	if enemy_id <= 0 or source_peer_id <= 0:
		return {}
	var previous_peer_id := int(EnemyReplicationService.killer_peer_for(enemy_id))
	EnemyReplicationService.credit_damage(enemy_id, source_peer_id)
	return {"enemy_id": enemy_id, "previous_peer_id": previous_peer_id, "source_peer_id": source_peer_id}


## Enemy movement is authoritative on the host, just like enemy health.
static func apply_impulse(target: Object, impulse: Vector2, source_peer_id: int = 0, suppress_launch: bool = false, interaction: Dictionary = {}) -> bool:
	if not is_instance_valid(target) or not (target is CharacterBody2D) or not impulse.is_finite():
		return false
	var enemy := target as CharacterBody2D
	if not enemy.is_in_group("enemies") or _read_target_health(enemy) <= 0:
		return false
	suppress_launch = suppress_launch or is_launch_suppressed()
	var action := interaction if not interaction.is_empty() else current_interaction_context()
	source_peer_id = _resolve_source_peer(source_peer_id, _should_route_enemy_damage_to_host(enemy))
	if _should_route_enemy_damage_to_host(enemy):
		var enemy_id := int(enemy.get_meta("network_enemy_id", 0))
		var scene_tree := Engine.get_main_loop() as SceneTree
		if enemy_id <= 0 or scene_tree == null or scene_tree.current_scene == null:
			return false
		scene_tree.current_scene.request_enemy_impulse_from_client(enemy_id, impulse, suppress_launch, action)
		return true
	var previous_interaction := begin_interaction_scope(action)
	if not is_displacement_immune(enemy):
		enemy.velocity += impulse
		notify_player_displacement(enemy, impulse)
	if not suppress_launch and impulse.length_squared() > 0.0001:
		_arm_launch(enemy, impulse, source_peer_id)
	end_interaction_scope(previous_interaction)
	return true


static func notify_player_displacement(target: Object, impulse: Vector2) -> void:
	if not is_instance_valid(target) or not (target is ENEMY_BASE_SCRIPT) or MultiplayerSessionManager.is_remote_replica():
		return
	(target as ENEMY_BASE_SCRIPT).on_player_displaced(impulse)


static func _find_combat_owner(source_peer_id: int) -> CharacterBody2D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var solo := not MultiplayerSessionManager.is_session_connected()
	for node in tree.get_nodes_in_group("combat_players"):
		if not (node is CharacterBody2D) or node.is_queued_for_deletion():
			continue
		var peer_id := int(node.get("player_id"))
		if peer_id == source_peer_id or (solo and peer_id == 0):
			return node as CharacterBody2D
	return null


static func _arm_primary_launch(target: Object, source_peer_id: int) -> void:
	if not (target is CharacterBody2D):
		return
	var owner := _find_combat_owner(source_peer_id)
	if owner == null:
		return
	var enemy := target as CharacterBody2D
	var direction := owner.global_position.direction_to(enemy.global_position)
	if direction.length_squared() <= 0.0001:
		direction = Vector2(owner.get("visual_facing_direction"))
	_arm_launch(enemy, direction.normalized() * 540.0, source_peer_id)


static func _arm_launch(enemy: CharacterBody2D, impulse: Vector2, source_peer_id: int) -> void:
	if MultiplayerSessionManager.is_remote_replica() or is_launch_suppressed():
		return
	var owner := _find_combat_owner(source_peer_id)
	if owner == null:
		return
	var combinations := owner.get("boss_combinations") as Node
	if combinations != null:
		combinations.launch_enemy(enemy, impulse, source_peer_id)


static func _restore_rejected_damage_credit(target: Object, health_before: int, pending_credit: Dictionary) -> void:
	if pending_credit.is_empty() or not is_instance_valid(target):
		return
	if _read_target_health(target) < health_before:
		return
	var enemy_id := int(pending_credit["enemy_id"])
	if EnemyReplicationService.killer_peer_for(enemy_id) != int(pending_credit["source_peer_id"]):
		return
	var previous_peer_id := int(pending_credit["previous_peer_id"])
	if previous_peer_id > 0:
		EnemyReplicationService.credit_damage(enemy_id, previous_peer_id)
	else:
		EnemyReplicationService.last_damage_peer_by_id.erase(enemy_id)


static func _read_target_health(target: Object) -> int:
	if not is_instance_valid(target):
		return -1
	var health_state_node := target.get("health_state") as Object
	if health_state_node != null:
		return int(health_state_node.get("current_health"))
	return -1


static func _report_enemy_damage_applied(target: Object, health_before: int, source_peer_id: int) -> void:
	if health_before < 0:
		return
	if not is_instance_valid(target) or not (target is Node):
		return
	var target_node := target as Node
	if target_node == null or not target_node.is_in_group("enemies"):
		return
	var health_after := _read_target_health(target)
	if health_after < 0:
		return
	var applied_amount := maxi(0, health_before - health_after)
	if applied_amount <= 0:
		return
	var killed_enemy := health_before > 0 and health_after <= 0
	var enemy_id := 0
	if target_node.has_meta("network_enemy_id"):
		enemy_id = int(target_node.get_meta("network_enemy_id"))
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree == null:
		return
	var world := scene_tree.current_scene
	if world == null:
		return
	if STAT_ATTRIBUTION_TRACE:
		print_debug("[StatAttribution][LocalApply] peer=%d enemy_id=%d applied=%d killed=%s" % [source_peer_id, enemy_id, applied_amount, str(killed_enemy)])
	world.record_player_damage_dealt(applied_amount, source_peer_id, killed_enemy, enemy_id)


static func _resolve_local_peer_id() -> int:
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree != null and scene_tree.get_multiplayer() != null:
		var active_peer_id := int(scene_tree.get_multiplayer().get_unique_id())
		if active_peer_id > 0:
			return active_peer_id
	if MultiplayerSessionManager != null and MultiplayerSessionManager.is_session_connected():
		return int(MultiplayerSessionManager.local_peer_id)
	return 0


static func _resolve_source_peer(explicit_peer: int, route_to_host: bool) -> int:
	if route_to_host:
		return _resolve_local_peer_id()
	if explicit_peer > 0:
		return explicit_peer
	# Only an already active scope can supply ownership for host-generated
	# descendants. Incoming damage metadata cannot select its own sender.
	if not _interaction_scope.is_empty():
		var inherited_owner := int(_interaction_scope.get("owner", 0))
		if inherited_owner > 0 and not _status_action(_interaction_scope, inherited_owner).is_empty():
			return inherited_owner
	return _resolve_local_peer_id()


static func _should_route_enemy_damage_to_host(target: Object) -> bool:
	if not MultiplayerSessionManager.is_remote_replica():
		return false
	if not (target is Node):
		return false
	var target_node := target as Node
	if target_node == null:
		return false
	if not target_node.has_meta("network_enemy_id"):
		return false
	return true


static func _route_enemy_damage_to_host(target: Object, amount: int, damage_context: Dictionary) -> void:
	if not (target is Node):
		return
	var target_node := target as Node
	if target_node == null:
		return
	if not target_node.has_meta("network_enemy_id"):
		return
	var routed_context := damage_context.duplicate(true)
	var local_peer_id := _resolve_local_peer_id()
	if local_peer_id > 0:
		routed_context["source_peer_id"] = local_peer_id
	var enemy_id := int(target_node.get_meta("network_enemy_id"))
	if enemy_id <= 0:
		return
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree == null:
		return
	var world := scene_tree.current_scene
	if world == null:
		return
	if STAT_ATTRIBUTION_TRACE:
		print_debug("[StatAttribution][RouteToHost] peer=%d enemy_id=%d amount=%d attack=%s" % [local_peer_id, enemy_id, amount, String(routed_context.get("attack_type", "unknown"))])
	world.request_enemy_damage_from_client(enemy_id, amount, routed_context)

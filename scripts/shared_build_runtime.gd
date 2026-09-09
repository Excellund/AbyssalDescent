extends Node
## Player-owned adapters for confirmed combat events. Damage and status authority
## stays in Damageable; this class supplies the existing powers' reactions.

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const REGISTRY := preload("res://scripts/shared/combat_interaction_registry.gd")
const FIELDS := preload("res://scripts/shared/owned_field_registry.gd")
var fields: RefCounted
var player: CharacterBody2D
var _attack_victims: Dictionary = {}
var _movement_events: Dictionary = {}
var _serial: int = 0
var _received_serial: int = 0
var _received_epoch: int = 0
var _received_dash_refund: float = 0.0
var _sigil_armed_origin: String = ""
var _room: String = ""

func initialize(owner_player: CharacterBody2D) -> void:
	player = owner_player
	fields = FIELDS.new()
	fields.initialize(player)
	_room = "%s:%d" % [REGISTRY.current_run(), REGISTRY.current_room()]

func cancel() -> void:
	if fields != null:
		fields.clear()
	_attack_victims.clear()
	_movement_events.clear()
	_sigil_armed_origin = ""

func _owner_id() -> int:
	return int(player.player_id) if int(player.player_id) > 0 else DAMAGEABLE._resolve_local_peer_id()

func _physics_process(_delta: float) -> void:
	var identity := "%s:%d" % [REGISTRY.current_run(), REGISTRY.current_room()]
	if identity != _room:
		_room = identity
		cancel()

func prepare_attack(target: Node2D, descriptor: Dictionary, _action: Dictionary) -> Dictionary:
	var result := descriptor.duplicate(true)
	var raw := float(result.get("raw_amount", 0.0))
	var coefficient := float(result.get("damage_coefficient", 0.0))
	var pending: Dictionary = {}
	if int(player.apex_predator_bonus_damage) > 0:
		var step := (int(player.apex_predator_combo_hits) % 4) + 1
		pending["warden_step"] = step
		pending["warden_base"] = raw
		pending["warden_coefficient"] = coefficient
		raw += maxf(1.0, round(float(player.apex_predator_bonus_damage) * (0.22 + step * 0.12)))
		if step == 4:
			raw += float(result.get("raw_amount", 0.0)) * 0.42
			coefficient *= 1.42
	if player.reward_riftpunch and float(player._riftpunch_window_left) > 0.0:
		pending["riftpunch"] = true
		raw += float(player.riftpunch_bonus_damage)
	result["raw_amount"] = raw
	result["damage_coefficient"] = coefficient
	result["pending_bonuses"] = pending
	return result

func accepted_damage(_event: Dictionary) -> void:
	player._trigger_battle_trance()
	publish_state()

func accepted_attack(event: Dictionary) -> void:
	var action: Dictionary = event.get("interaction", {})
	var target_ref: Variant = event.get("target")
	var target: Node2D = target_ref.get_ref() as Node2D if target_ref is WeakRef else null
	var hit_context: Dictionary = event.get("context", {})
	var position: Vector2 = hit_context.get("hit_position", event.get("position", player.global_position))
	if not position.is_finite():
		position = event.get("position", player.global_position)
	var target_id := int(event.get("target_id", 0))
	var raw := float(event.get("raw_amount", 0.0))
	var coefficient := float(event.get("damage_coefficient", 0.0))
	var source := String(action.get("source", "melee"))
	var pending: Dictionary = event.get("pending_bonuses", {})
	var controller: Node = player.combat_interactions
	var key := "%d:%d" % [int(action.get("epoch", 0)), int(action.get("seq", 0))]
	if not _attack_victims.has(key):
		if _attack_victims.size() >= REGISTRY.MAX_ROOTS:
			_attack_victims.erase(_attack_victims.keys().front())
		_attack_victims[key] = {}
	var victims: Dictionary = _attack_victims[key]
	if bool(event.get("first_attack_hit", false)):
		player._indomitable_attack_hit_count = 0
		player._try_apply_convergence_surge(position, int(raw), target_id)
		player._register_apex_momentum_hit()
		if player.reward_voidfire and float(player._voidfire_lockout_left) <= 0.0:
			player._voidfire_last_hit_time = Time.get_ticks_msec() / 1000.0
			player._gain_void_heat(player.voidfire_heat_per_hit)
	if int(pending.get("warden_step", 0)) > 0:
		player.apex_predator_combo_hits += 1
		player.apex_predator_combo_left = player.apex_predator_combo_window
		var step := int(pending.warden_step)
		player._show_warden_verdict_contact(position, step)
		if step == 4:
			player._trigger_apex_predator_burst(position, target_id, int(pending.get("warden_base", raw)), float(pending.get("warden_coefficient", coefficient)))
	if bool(pending.get("riftpunch", false)):
		player._consume_riftpunch_bonus(source, position, target)
	if is_instance_valid(target):
		if player.reward_hunters_snare:
			DAMAGEABLE.apply_slow(target, player.hunters_snare_slow_duration * player._global_slow_duration_mult(), player.hunters_snare_slow_mult, _owner_id(), action)
		if player.reward_wraithstep and int(player.wraithstep_stacks) >= 2 and float(event.get("pre_mark_ratio", 0.0)) > 0.0 and controller.claim_reaction(action, "wraith_burst"):
			wraith_burst(position, target_id, raw, coefficient, action)
		if player.reward_dread_resonance:
			DAMAGEABLE.apply_mark(target, "dread_resonance", player.dread_resonance_mark_bonus_ratio, player.dread_resonance_mark_duration, _owner_id(), action)
			DAMAGEABLE.add_dread_stack(target, _owner_id(), int(player.dread_resonance_max_stacks), action)
		if not player._indomitable_oath_spent_this_attack:
			player._gain_indomitable_oath_from_hit(target, source)
		var context: Dictionary = event.get("context", {})
		var attack_origin: Vector2 = context.get("attack_origin", player.global_position)
		var attack_range := float(context.get("attack_range", player.attack_range))
		if player.reward_farline_volley and source != "razor_wind" and attack_origin.distance_to(position) > attack_range * float(player.FARLINE_VOLLEY_BAND_RATIO):
			player._on_farline_volley_outer_hit(target)
	if player.reward_sigil_chain:
		if player._sigil_chain_drop_armed and key != _sigil_armed_origin and controller.claim_reaction(action, "sigil_drop"):
			player._drop_sigil_chain_zone(position)
			player._sigil_chain_drop_armed = false
		player._sigil_chain_charge += 1
		if int(player._sigil_chain_charge) >= int(player.SIGIL_CHAIN_CHARGE_THRESHOLD):
			player._sigil_chain_charge = 0
			player._sigil_chain_drop_armed = true
			_sigil_armed_origin = key
	if player.passive_sigil_burst and player.sigil_burst_ready and controller.claim_reaction(action, "sigil_burst"):
		player.sigil_burst_ready = false
		player._apply_sigil_burst(position, int(raw), coefficient)
	if player.reward_rupture_wave:
		player._apply_rupture_wave(position, int(raw), victims, 0, coefficient)
	publish_state()

func wraith_burst(origin: Vector2, primary_id: int, raw: float, coefficient: float, action: Dictionary) -> void:
	var ratio := float(player.wraithstep_mark_splash_ratio)
	var radius := float(player.wraithstep_mark_splash_radius)
	var visited: Dictionary = {primary_id: true}
	var frontier: Array[Vector2] = [origin]
	var chain_candidates: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is Node2D) or DAMAGEABLE._read_target_health(node) <= 0 or node.get_instance_id() == primary_id or node.global_position.distance_to(origin) > radius:
			continue
		visited[node.get_instance_id()] = true
		if float(DAMAGEABLE.status_snapshot(node, _owner_id()).get("mark_ratio", 0.0)) > 0.0:
			frontier.append(node.global_position)
		var context := REGISTRY.damage_context(action, "wraithstep_splash", {"raw_amount": raw * ratio, "damage_coefficient": coefficient * ratio, "attack_origin": origin})
		DAMAGEABLE.apply_damage(node, int(raw * ratio), context, _owner_id())
	if int(player.wraithstep_stacks) >= 3:
		var remaining := 3
		var chain_scale := minf(1.0, 0.72 + float(maxi(0, int(player.wraithstep_stacks) - 1)) * 0.1)
		while not frontier.is_empty() and remaining > 0:
			var from := frontier.pop_front() as Vector2
			chain_candidates.clear()
			for node in get_tree().get_nodes_in_group("enemies"):
				if node is Node2D and DAMAGEABLE._read_target_health(node) > 0 and not visited.has(node.get_instance_id()) and node.global_position.distance_to(from) <= radius and float(DAMAGEABLE.status_snapshot(node, _owner_id()).get("mark_ratio", 0.0)) > 0.0:
					chain_candidates.append(node)
			chain_candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.global_position.distance_squared_to(from) < b.global_position.distance_squared_to(from))
			for node in chain_candidates:
				if remaining <= 0:
					break
				visited[node.get_instance_id()] = true
				frontier.append(node.global_position)
				remaining -= 1
				var scale := ratio * chain_scale
				DAMAGEABLE.apply_damage(node, int(raw * scale), REGISTRY.damage_context(action, "wraithstep_chain", {"raw_amount": raw * scale, "damage_coefficient": coefficient * scale, "attack_origin": from}), _owner_id())
				if player.player_feedback != null:
					player.player_feedback.play_wraithstep_chain_echo(from, node.global_position)
	if player.player_feedback != null:
		player.player_feedback.play_world_ring(origin, radius, Color(0.72, 0.94, 1.0, 0.6), 0.18)
	player._broadcast_cue_event("world_ring", {"position": origin, "radius": radius, "color": Color(0.72, 0.94, 1.0, 0.6), "duration": 0.18})

func field_contains(target: Node2D) -> bool:
	return fields != null and fields.contains_point(target.global_position)

func register_field(source: String, identity: String, geometry: Dictionary, action: Dictionary) -> bool:
	return fields != null and fields.register_field(source, identity, geometry, action)

func publish_state() -> void:
	if not MultiplayerSessionManager.should_broadcast():
		return
	_serial += 1
	var payload := {"run": REGISTRY.current_run(), "room": REGISTRY.current_room(), "serial": _serial, "epoch": player.combat_interactions._accepted_epoch, "state": {}}
	for property in ["battle_trance_active_left", "combo_relay_stacks", "combo_relay_stack_timer", "apex_predator_combo_hits", "apex_predator_combo_left", "apex_momentum_stacks", "apex_momentum_stack_left", "convergence_surge_hit_counter", "_sigil_chain_charge", "_sigil_chain_drop_armed", "sigil_burst_ready", "_riftpunch_window_left", "void_heat", "_farline_volley_current_stacks", "indomitable_damage_bank", "_indomitable_spirit_primed", "_dash_damage_immune_left", "_shared_dash_refund_total"]:
		var value: Variant = player.get(property)
		if value != null:
			payload.state[property] = value
	PlayerReplicationService.broadcast_cue_event(_owner_id(), "shared_build_state", payload, true)

func apply_state(payload: Dictionary) -> void:
	if not MultiplayerSessionManager.is_remote_replica() or payload.get("run") != REGISTRY.current_run() or payload.get("room") != REGISTRY.current_room() or not (payload.get("state") is Dictionary):
		return
	var epoch := int(payload.get("epoch", 0))
	var controller: Node = player.combat_interactions
	if controller == null or epoch <= 0 or epoch < controller._accepted_epoch or (player._is_local_control_owner() and epoch != controller._epoch):
		return
	if epoch < _received_epoch or (epoch == _received_epoch and int(payload.get("serial", 0)) <= _received_serial):
		return
	_received_epoch = epoch
	_received_serial = int(payload.serial)
	for property in payload.state:
		if property in ["battle_trance_active_left", "combo_relay_stacks", "combo_relay_stack_timer", "apex_predator_combo_hits", "apex_predator_combo_left", "apex_momentum_stacks", "apex_momentum_stack_left", "convergence_surge_hit_counter", "_sigil_chain_charge", "_sigil_chain_drop_armed", "sigil_burst_ready", "_riftpunch_window_left", "void_heat", "_farline_volley_current_stacks", "indomitable_damage_bank", "_indomitable_spirit_primed"]:
			player.set(property, payload.state[property])
	var refund := float(payload.state.get("_shared_dash_refund_total", _received_dash_refund))
	if is_finite(refund) and refund > _received_dash_refund:
		player.dash_cooldown_left = maxf(0.0, player.dash_cooldown_left - (refund - _received_dash_refund))
		_received_dash_refund = refund
	var grace := float(payload.state.get("_dash_damage_immune_left", 0.0))
	if is_finite(grace) and grace > 0.0:
		player._dash_damage_immune_left = maxf(player._dash_damage_immune_left, minf(grace, player.riftpunch_grace_duration))

extends Node2D
## Owns movement shades and launch rewards. Echoes and impacts deliberately use
## secondary damage, so neither can create another echo, launch, or primary hit.

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const LAUNCH := preload("res://scripts/enemy_launch_state.gd")
const ENEMY_BASE := preload("res://scripts/enemy_base.gd")
const SHADE_LIFETIME := 4.0
var player: CharacterBody2D
var shade_position: Vector2 = Vector2.INF
var shade_hits: int = 0
var shade_left: float = 0.0
var dash_origin: Vector2 = Vector2.INF
var dash_contact: Vector2 = Vector2.INF
var _launch_targets: Dictionary = {} # Enemy instance ID -> unique weak reference.
var _echo_visuals: Array[Dictionary] = []
var _resolved_hit_damage: Dictionary = {}
var _cancel_generation: int = 0

func initialize(owner_player: CharacterBody2D) -> void:
	player = owner_player
	z_index = 2

func begin_direct_strike() -> void:
	_resolved_hit_damage.clear()

func record_direct_hit(enemy: Node2D, amount: int, source: String) -> void:
	var key := source
	_resolved_hit_damage[key] = maxi(amount, int(_resolved_hit_damage.get(key, 0)))
	if dash_origin.is_finite():
		dash_contact = player.global_position

func on_dash_started() -> void:
	dash_origin = player.global_position
	dash_contact = Vector2.INF

func record_dash_contact(position: Vector2) -> void:
	if dash_origin.is_finite():
		dash_contact = position

func on_dash_completed() -> void:
	if dash_origin.is_finite():
		create_shade(dash_origin, dash_contact)
	dash_origin = Vector2.INF
	dash_contact = Vector2.INF

func create_shade(origin: Vector2, last_contact: Vector2 = Vector2.INF) -> void:
	if int(player.sovereigns_double_stacks) <= 0 or not bool(player.combat_damage_enabled) or not bool(player._is_alive_state) or bool(player.encounter_input_frozen) or not bool(player._is_local_control_owner()):
		return
	shade_position = last_contact if last_contact.is_finite() else origin
	shade_hits = clampi(int(player.sovereigns_double_stacks), 1, 2)
	shade_left = SHADE_LIFETIME
	_broadcast_shade()

func repeat_strike(direction: Vector2, shapes: Array[Dictionary]) -> void:
	if shade_hits <= 0 or shade_left <= 0.0 or not shade_position.is_finite() or not bool(player.combat_damage_enabled) or bool(player.encounter_input_frozen) or not bool(player._is_local_control_owner()):
		return
	var origin := shade_position
	shade_hits -= 1
	if shade_hits == 0:
		shade_left = 0.0
	var generation := _cancel_generation
	for shape in shapes:
		var source := String(shape.get("source", "melee"))
		var baseline := int(shape.get("damage", 0))
		var amount := maxi(1, int(round(float(maxi(baseline, int(_resolved_hit_damage.get(source, 0)))) * 0.55)))
		var reach := float(shape.get("range", 0.0))
		var arc := float(shape.get("arc_degrees", 0.0))
		var inner := float(shape.get("inner_range", -1.0))
		var visual := {"position": origin, "direction": direction, "range": reach, "arc": arc, "inner_range": maxf(0.0, inner), "life": 0.20}
		show_echo(visual)
		player._broadcast_cue_event("sovereign_double_strike", visual)
		for hit in player._get_damageable_enemies_in_cone(origin, direction, reach, deg_to_rad(arc * 0.5)):
			var enemy := hit.get("enemy") as Node2D
			var hit_position: Vector2 = hit.get("hit_position", origin)
			if enemy == null or hit_position.distance_to(origin) <= inner:
				continue
			DAMAGEABLE.apply_damage(enemy, amount, {"attack_type": "sovereigns_double", "secondary": true, "is_ground_attack": true, "attack_origin": origin})
			if generation != _cancel_generation:
				return
	_broadcast_shade()

## Invoked on the host for both direct strikes and authenticated player pushes.
func launch_enemy(enemy: ENEMY_BASE, impulse: Vector2, source_peer: int) -> void:
	var stacks := clampi(int(player.ruinous_impact_stacks), 0, 2)
	if stacks == 0 or not bool(player.combat_damage_enabled) or not bool(player._is_alive_state) or DAMAGEABLE._read_target_health(enemy) <= 0:
		return
	var state: LAUNCH = enemy.get_launch_state()
	var amount := maxi(1, int(round(float(player.damage) * (1.0 + 0.4 * (stacks - 1)))))
	amount = int(player._apply_objective_mutator_damage_mult(amount))
	var radius := 70.0 + 25.0 * (stacks - 1)
	var callback := _impact.bind(amount, radius, source_peer, impulse.normalized())
	if state.arm(impulse, DAMAGEABLE.is_displacement_immune(enemy), source_peer, player.get_instance_id(), callback):
		if not state.compression:
			DAMAGEABLE.notify_player_displacement(enemy, impulse)
		_launch_targets[enemy.get_instance_id()] = weakref(enemy)
		var serial := EnemyReplicationService.broadcast_ruinous_launch(enemy, impulse, state.compression, state.remaining)
		if serial > 0:
			state.ended.connect(EnemyReplicationService.finish_ruinous_launch.bind(serial), CONNECT_ONE_SHOT)

func _impact(position: Vector2, amount: int, radius: float, source_peer: int, direction: Vector2 = Vector2.RIGHT) -> void:
	if not is_instance_valid(player) or not bool(player.combat_damage_enabled):
		return
	EnemyReplicationService.broadcast_ruinous_burst(position, radius, direction)
	var generation := _cancel_generation
	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node is Node2D) or DAMAGEABLE._read_target_health(node) <= 0:
			continue
		var enemy := node as Node2D
		if enemy.global_position.distance_to(position) > radius:
			continue
		DAMAGEABLE.apply_damage(enemy, amount, {"attack_type": "ruinous_impact", "secondary": true, "is_ground_attack": true, "attack_origin": position}, source_peer)
		if generation != _cancel_generation:
			return

func _broadcast_shade() -> void:
	if not is_instance_valid(player):
		return
	player._broadcast_cue_event("sovereign_double_shade", {"position": shade_position, "hits": shade_hits, "life": shade_left}, true)

func apply_shade_visual(payload: Dictionary) -> void:
	shade_position = Vector2(payload.get("position", Vector2.INF))
	shade_hits = clampi(int(payload.get("hits", 0)), 0, 2)
	shade_left = clampf(float(payload.get("life", 0.0)), 0.0, SHADE_LIFETIME)

func show_echo(payload: Dictionary) -> void:
	_echo_visuals.append(payload.duplicate())
	if _echo_visuals.size() > 8:
		_echo_visuals.pop_front()

func tick(delta: float) -> void:
	shade_left = maxf(0.0, shade_left - delta)
	if shade_left <= 0.0:
		shade_hits = 0
	for enemy_id in _launch_targets.keys():
		var target := (_launch_targets[enemy_id] as WeakRef).get_ref() as Node
		if not is_instance_valid(target):
			_launch_targets.erase(enemy_id)
			continue
		var state: LAUNCH = target.get_launch_state()
		if not state.active or state.owner_id != player.get_instance_id():
			_launch_targets.erase(enemy_id)

func cancel() -> void:
	_cancel_generation += 1
	shade_hits = 0
	shade_left = 0.0
	dash_origin = Vector2.INF
	dash_contact = Vector2.INF
	_echo_visuals.clear()
	_resolved_hit_damage.clear()
	for target_ref in _launch_targets.values():
		var target := target_ref.get_ref() as ENEMY_BASE
		if target != null:
			var state: LAUNCH = target.get_launch_state()
			if state.owner_id == player.get_instance_id():
				state.cancel()
	_launch_targets.clear()
	_broadcast_shade()

func _process(delta: float) -> void:
	if player != null and not bool(player._is_local_control_owner()):
		tick(delta)
	for i in range(_echo_visuals.size() - 1, -1, -1):
		_echo_visuals[i]["life"] = float(_echo_visuals[i].get("life", 0.0)) - delta
		if float(_echo_visuals[i]["life"]) <= 0.0:
			_echo_visuals.remove_at(i)
	queue_redraw()

func _draw() -> void:
	if player == null or not player.visible:
		return
	var tint := Color(0.74, 0.68, 1.0, 0.6)
	if shade_hits > 0 and shade_left > 0.0 and shade_position.is_finite():
		var point := to_local(shade_position)
		draw_circle(point, 12.0, Color(tint, 0.13))
		draw_arc(point, 15.0, 0.0, TAU, 24, tint, 1.5, true)
		for i in range(shade_hits):
			draw_circle(point + Vector2(-3.0 + 6.0 * i, -20.0), 2.0, tint)
	for effect in _echo_visuals:
		var point := to_local(Vector2(effect.get("position", global_position)))
		draw_circle(point, 12.0, Color(tint, float(effect["life"]) * 1.5))
		draw_arc(point, 15.0, 0.0, TAU, 24, Color(tint, float(effect["life"]) * 3.0), 1.5, true)
		var direction: Vector2 = effect.get("direction", Vector2.RIGHT)
		var half_arc := deg_to_rad(float(effect.get("arc", 100.0)) * 0.5)
		var reach := float(effect.get("range", 80.0))
		draw_arc(point, reach, direction.angle() - half_arc, direction.angle() + half_arc, 30, Color(tint, float(effect["life"]) * 3.0), 3.0, true)
		var inner := clampf(float(effect.get("inner_range", 0.0)), 0.0, reach)
		if inner > 0.0:
			# Razor Wind echoes damage only the outer band. Show its inner edge
			# using the same boundary carried with the repeated attack.
			var edge_color := Color(tint, float(effect["life"]) * 3.0)
			draw_arc(point, inner, direction.angle() - half_arc, direction.angle() + half_arc, 30, edge_color, 1.5, true)
			for edge_angle in [direction.angle() - half_arc, direction.angle() + half_arc]:
				var edge_direction := Vector2.RIGHT.rotated(edge_angle)
				draw_line(point + edge_direction * inner, point + edge_direction * reach, edge_color, 1.5, true)

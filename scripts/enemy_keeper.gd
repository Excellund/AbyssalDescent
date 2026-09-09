extends "res://scripts/enemy_base.gd"

const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const ENEMY_BASE_SCRIPT := preload("res://scripts/enemy_base.gd")
const MAX_WARD_TARGETS := 2
const REMOTE_WARD_LEASE := 0.50
const WARD_HEARTBEAT_INTERVAL := 0.12
const WARD_COLOR := COLOR_SHIELDER_SHIELD_OUTLINE

@export var move_speed: float = 62.0
@export var acceleration: float = 480.0
@export var deceleration: float = 640.0
@export var ward_range: float = 220.0
@export var ward_damage_multiplier: float = 0.70
@export var ward_warmup_duration: float = 0.60
@export var ward_rearm_duration: float = 1.0
@export var ward_interrupt_duration: float = 1.25
@export var ward_interrupt_impulse: float = 40.0
@export var contact_damage: int = 7
@export var attack_interval: float = 1.4
@export var contact_range: float = 48.0
@export var contact_windup_duration: float = 0.45

var ward_targets: Array[Node2D] = []
var ward_rearm_left: float = 0.0
var ward_warmup_left: float = 0.0
var _pending_ward_targets: Array[Node2D] = []
var _ward_scan_left: float = 0.0
var _ward_heartbeat_left: float = 0.0
var _ward_sync_revision: int = 0
var _ward_break_flash_left: float = 0.0
var _remote_revision: int = -1
var _remote_ward_lease_left: float = 0.0
var _remote_active_ids: PackedInt32Array = []
var _remote_pending_ids: PackedInt32Array = []
var _contact_cooldown_left: float = 0.0
var _contact_windup_left: float = 0.0
var _contact_direction: Vector2 = Vector2.LEFT
var _contact_target: Node2D


func _ready() -> void:
	max_health = 78
	crowd_separation_radius = 42.0
	crowd_separation_strength = 54.0
	super()
	add_to_group("keepers")


func _physics_process(delta: float) -> void:
	# EnemyBase skips AI during launch movement. Ward expiry must still run.
	if network_simulation_enabled:
		_update_wards(delta)
	super(delta)


func _on_health_state_died() -> void:
	_clear_wards()
	super()


func _exit_tree() -> void:
	_clear_wards()


func _clear_wards() -> void:
	ward_targets.clear()
	_pending_ward_targets.clear()
	_remote_active_ids.clear()
	_remote_pending_ids.clear()
	_remote_ward_lease_left = 0.0
	ward_warmup_left = 0.0
	_contact_windup_left = 0.0
	_contact_target = null
	_ward_sync_revision += 1
	queue_redraw()


func _can_ward() -> bool:
	return network_simulation_enabled and not MultiplayerSessionManager.is_remote_replica() \
		and is_inside_tree() and not is_queued_for_deletion() \
		and get_current_health() > 0 and not is_spawn_transporting() \
		and (_launch_state == null or not _launch_state.active)


func get_ward_damage_multiplier_for(candidate: Variant) -> float:
	return clampf(ward_damage_multiplier, 0.70, 1.0) if has_active_ward_for(candidate) else 1.0


func has_active_ward_for(candidate: Variant) -> bool:
	# Damage resolution asks again, so movement, cover and death cannot leave a
	# stale ward between the Keeper's normal physics updates.
	if not _can_ward():
		return false
	_prune_ward_targets()
	return is_instance_valid(candidate) and ward_targets.has(candidate)


func on_player_displaced(impulse: Vector2) -> void:
	if not network_simulation_enabled or MultiplayerSessionManager.is_remote_replica() or not impulse.is_finite():
		return
	if impulse.length_squared() < ward_interrupt_impulse * ward_interrupt_impulse:
		return
	_clear_wards()
	ward_rearm_left = maxf(ward_rearm_left, ward_interrupt_duration)
	_ward_break_flash_left = 0.24
	_ward_scan_left = 0.0
	_ward_sync_revision += 1
	queue_redraw()


func _update_wards(delta: float) -> void:
	if not network_simulation_enabled or MultiplayerSessionManager.is_remote_replica():
		return
	var elapsed := maxf(0.0, delta)
	ward_rearm_left = maxf(0.0, ward_rearm_left - elapsed)
	_ward_break_flash_left = maxf(0.0, _ward_break_flash_left - elapsed)
	_ward_scan_left = maxf(0.0, _ward_scan_left - elapsed)
	_ward_heartbeat_left -= elapsed
	if _ward_heartbeat_left <= 0.0:
		_ward_heartbeat_left = WARD_HEARTBEAT_INTERVAL
		_ward_sync_revision += 1
	if not _can_ward():
		if not ward_targets.is_empty() or not _pending_ward_targets.is_empty():
			_clear_wards()
		return
	_prune_ward_targets()
	if not _pending_ward_targets.is_empty():
		ward_warmup_left = maxf(0.0, ward_warmup_left - elapsed)
		if ward_warmup_left <= 0.0:
			for candidate in _pending_ward_targets:
				if ward_targets.size() < MAX_WARD_TARGETS and _valid_ward_ally(candidate, true):
					ward_targets.append(candidate)
			_pending_ward_targets.clear()
			_ward_sync_revision += 1
	if ward_rearm_left <= 0.0 and ward_targets.size() < MAX_WARD_TARGETS \
			and _pending_ward_targets.is_empty() and _ward_scan_left <= 0.0:
		_ward_scan_left = 0.20
		_pending_ward_targets = _find_ward_targets(MAX_WARD_TARGETS - ward_targets.size())
		if not _pending_ward_targets.is_empty():
			ward_warmup_left = ward_warmup_duration
			_ward_sync_revision += 1
	queue_redraw()


func _prune_ward_targets() -> void:
	var lost_link := false
	for index in range(ward_targets.size() - 1, -1, -1):
		if not _valid_ward_ally(ward_targets[index], true):
			ward_targets.remove_at(index)
			lost_link = true
	for index in range(_pending_ward_targets.size() - 1, -1, -1):
		if not _valid_ward_ally(_pending_ward_targets[index], true):
			_pending_ward_targets.remove_at(index)
			lost_link = true
	if _pending_ward_targets.is_empty():
		ward_warmup_left = 0.0
	if lost_link:
		ward_rearm_left = maxf(ward_rearm_left, ward_rearm_duration)
		_ward_break_flash_left = 0.24
		_ward_sync_revision += 1
		queue_redraw()


func _valid_ward_ally(candidate: Variant, check_geometry: bool) -> bool:
	if not is_instance_valid(candidate):
		return false
	var ally := candidate as ENEMY_BASE_SCRIPT
	if ally == null or ally == self or not ally.is_inside_tree() or ally.is_queued_for_deletion():
		return false
	if not ally.is_in_group("enemies") or ally.is_in_group("keepers") or ally.get_current_health() <= 0:
		return false
	if ally.is_spawn_transporting() or DAMAGEABLE.is_displacement_immune(ally):
		return false
	if check_geometry:
		if global_position.distance_squared_to(ally.global_position) > ward_range * ward_range:
			return false
		if not _ward_line_visible(ally):
			return false
	return true


func _ward_line_visible(ally: Node2D) -> bool:
	if not is_inside_tree() or get_world_2d() == null:
		return false
	var excluded: Array[RID] = [get_rid()]
	for group_name in ["enemies", "combat_players"]:
		for body in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(body) and body is CollisionObject2D and not body.is_queued_for_deletion():
				excluded.append((body as CollisionObject2D).get_rid())
	var query := PhysicsRayQueryParameters2D.create(global_position, ally.global_position, 1, excluded)
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _find_ward_targets(limit: int) -> Array[Node2D]:
	var candidates: Array[Node2D] = []
	for candidate in _get_shared_enemy_nodes_cache():
		if not ward_targets.has(candidate) and _valid_ward_ally(candidate, true):
			candidates.append(candidate)
	candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	if candidates.size() > limit:
		candidates.resize(limit)
	return candidates


func _process_behavior(delta: float) -> void:
	if MultiplayerSessionManager.is_remote_replica():
		return
	_update_contact_attack(delta)
	var desired := _support_velocity() * slow_speed_mult
	if _contact_windup_left > 0.0:
		desired = Vector2.ZERO
	velocity = velocity.move_toward(desired, (acceleration if desired != Vector2.ZERO else deceleration) * delta)
	move_and_slide()


func _support_velocity() -> Vector2:
	# Stand and defend when approached. The support role must not become an
	# endless chase after every other enemy in the room has died.
	if is_instance_valid(target) and global_position.distance_to(target.global_position) < 78.0:
		return Vector2.ZERO
	var center := Vector2.ZERO
	var count := 0
	for ally in ward_targets + _pending_ward_targets:
		if _valid_ward_ally(ally, false):
			center += ally.global_position
			count += 1
	if count == 0:
		# Walk toward a nearby formation after a split spawn; do not retreat to
		# a distant ally on the opposite side of the room.
		var nearest_distance := ward_range * ward_range * 4.0
		for ally in _get_shared_enemy_nodes_cache():
			if not _valid_ward_ally(ally, false):
				continue
			var distance := global_position.distance_squared_to(ally.global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				center = ally.global_position
				count = 1
	if count > 0:
		center /= float(count)
		var behind := Vector2.ZERO
		if is_instance_valid(target):
			behind = target.global_position.direction_to(center) * 72.0
		var to_support := center + behind - global_position
		return to_support.normalized() * move_speed if to_support.length() > 30.0 else Vector2.ZERO
	if is_instance_valid(target):
		var to_player := target.global_position - global_position
		return to_player.normalized() * move_speed if to_player.length() > contact_range * 0.85 else Vector2.ZERO
	return Vector2.ZERO


func _update_contact_attack(delta: float) -> void:
	_contact_cooldown_left = maxf(0.0, _contact_cooldown_left - delta)
	if _contact_windup_left > 0.0:
		_contact_windup_left = maxf(0.0, _contact_windup_left - delta)
		if _contact_windup_left <= 0.0:
			if is_instance_valid(_contact_target) and not _contact_target.is_dead():
				var to_player := _contact_target.global_position - global_position
				if to_player.length() <= contact_range and (to_player.length() < 1.0 or to_player.normalized().dot(_contact_direction) > 0.35):
					DAMAGEABLE.apply_damage(_contact_target, contact_damage, {"source": "enemy_contact", "ability": "keeper_strike"})
			_contact_target = null
			_contact_cooldown_left = attack_interval
			attack_anim_time_left = attack_anim_duration
		return
	if _contact_cooldown_left > 0.0 or not is_instance_valid(target) or target.is_dead():
		return
	if global_position.distance_to(target.global_position) > contact_range:
		return
	_contact_target = target
	_contact_direction = global_position.direction_to(target.global_position)
	if _contact_direction == Vector2.ZERO:
		_contact_direction = visual_facing_direction
	_contact_windup_left = contact_windup_duration
	_ward_sync_revision += 1


func _is_in_priority_attack_state() -> bool:
	return not ward_targets.is_empty() or not _pending_ward_targets.is_empty() \
		or _ward_break_flash_left > 0.0 or _contact_windup_left > 0.0 or _remote_ward_lease_left > 0.0


func _get_custom_network_runtime_state() -> Dictionary:
	# A heartbeat keeps a short replica lease alive without resending clocks
	# every physics tick. Empty ID arrays explicitly clear old links.
	return {
		"q": _ward_sync_revision,
		"a": _network_ids(ward_targets),
		"p": _network_ids(_pending_ward_targets),
		"w": snappedf(ward_warmup_left, 0.05),
		"r": snappedf(ward_rearm_left, 0.10),
		"b": snappedf(_ward_break_flash_left, 0.05),
		"c": snappedf(_contact_windup_left, 0.05),
		"d": _contact_direction,
	}


func _network_ids(nodes: Array[Node2D]) -> PackedInt32Array:
	var ids: PackedInt32Array = []
	for node in nodes:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			var enemy_id := int(node.get_meta("network_enemy_id", -1))
			if enemy_id > 0:
				ids.append(enemy_id)
	return ids


func _apply_custom_network_runtime_state(custom_state: Dictionary) -> void:
	if network_simulation_enabled or custom_state.is_empty() or not custom_state.has("q"):
		return
	var revision := int(custom_state["q"])
	if revision <= _remote_revision:
		return
	_remote_revision = revision
	_remote_active_ids = _read_network_ids(custom_state.get("a", []))
	_remote_pending_ids = _read_network_ids(custom_state.get("p", []))
	ward_warmup_left = clampf(float(custom_state.get("w", 0.0)), 0.0, ward_warmup_duration)
	ward_rearm_left = clampf(float(custom_state.get("r", 0.0)), 0.0, ward_interrupt_duration)
	_ward_break_flash_left = clampf(float(custom_state.get("b", 0.0)), 0.0, 0.24)
	_contact_windup_left = clampf(float(custom_state.get("c", 0.0)), 0.0, contact_windup_duration)
	var direction: Vector2 = custom_state.get("d", Vector2.LEFT)
	_contact_direction = direction.normalized() if direction.is_finite() else Vector2.LEFT
	_remote_ward_lease_left = REMOTE_WARD_LEASE
	_resolve_remote_links()
	queue_redraw()


func _read_network_ids(value: Variant) -> PackedInt32Array:
	var ids: PackedInt32Array = []
	if not (value is Array or value is PackedInt32Array or value is PackedInt64Array):
		return ids
	for raw_id in value:
		var enemy_id := int(raw_id)
		if enemy_id > 0 and not ids.has(enemy_id):
			ids.append(enemy_id)
		if ids.size() >= MAX_WARD_TARGETS:
			break
	return ids


func _resolve_remote_links() -> void:
	ward_targets.clear()
	_pending_ward_targets.clear()
	if _remote_ward_lease_left <= 0.0 or not is_inside_tree():
		return
	# IDs can arrive before the corresponding spawn. Keep them until lease
	# expiry and resolve again, without inventing a local substitute target.
	for node in get_tree().get_nodes_in_group("enemies"):
		if not _valid_ward_ally(node, false):
			continue
		var enemy_id := int(node.get_meta("network_enemy_id", -1))
		if _remote_active_ids.has(enemy_id):
			ward_targets.append(node as Node2D)
		elif _remote_pending_ids.has(enemy_id):
			_pending_ward_targets.append(node as Node2D)


func _process_network_visuals(delta: float) -> void:
	_remote_ward_lease_left = maxf(0.0, _remote_ward_lease_left - delta)
	ward_warmup_left = maxf(0.0, ward_warmup_left - delta)
	ward_rearm_left = maxf(0.0, ward_rearm_left - delta)
	_ward_break_flash_left = maxf(0.0, _ward_break_flash_left - delta)
	_contact_windup_left = maxf(0.0, _contact_windup_left - delta)
	_resolve_remote_links()
	queue_redraw()


func _draw() -> void:
	var facing := visual_facing_direction if visual_facing_direction != Vector2.ZERO else Vector2.LEFT
	if is_spawn_transporting():
		_draw_spawn_transport_fx(15.0, facing)
		return
	for ally in ward_targets:
		if _valid_ward_ally(ally, false):
			_draw_ward_link(to_local(ally.global_position), true, ally.get_current_health() == 1)
	for ally in _pending_ward_targets:
		if _valid_ward_ally(ally, false):
			_draw_ward_link(to_local(ally.global_position), false)
	_draw_common_body(15.0, COLOR_WEAVER_BODY.darkened(0.24), COLOR_ARCHER_CORE, facing)
	# Open crown, not a shield: the Keeper's own body is always vulnerable.
	var crown := PackedVector2Array([Vector2(-17.0, -9.0), Vector2(-20.0, -20.0), Vector2(-7.0, -15.0), Vector2(0.0, -23.0), Vector2(7.0, -15.0), Vector2(20.0, -20.0), Vector2(17.0, -9.0)])
	var crown_color := WARD_COLOR
	crown_color.a = 0.82 if ward_rearm_left <= 0.0 else 0.28
	draw_polyline(crown, crown_color, 1.8, true)
	if _ward_break_flash_left > 0.0:
		var progress := 1.0 - _ward_break_flash_left / 0.24
		for index in 4:
			var direction := Vector2.from_angle(float(index) * PI * 0.5 + PI * 0.25)
			var center := direction * (22.0 + progress * 18.0)
			var side := direction.orthogonal() * 4.0
			draw_line(center - side, center + side, Color(WARD_COLOR, 1.0 - progress), 2.4, true)
	if _contact_windup_left > 0.0:
		var angle := _contact_direction.angle()
		var color := COLOR_SHIELDER_SLAM_WARNING_RING
		color.a = 0.75
		draw_arc(Vector2.ZERO, contact_range, angle - 0.85, angle + 0.85, 14, color, 2.0, true)
	_draw_slow_indicator(15.0)


func _draw_ward_link(endpoint: Vector2, active: bool, sustaining: bool = false) -> void:
	var direction := endpoint.normalized()
	var start := direction * 21.0
	var end := endpoint - direction * 19.0
	var color := WARD_COLOR
	color.a = 0.95 if sustaining else (0.62 if active else 0.25)
	if active:
		draw_line(start, end, color, 2.8 if sustaining else 1.5, true)
	else:
		draw_dashed_line(start, end, color, 1.1, 7.0, true)
	if sustaining:
		# A persistent shield makes the saved ally readable even under rapid
		# damage. Health replication supplies the same cue to co-op joiners.
		var shell := PackedVector2Array([
			endpoint + Vector2(-22.0, -18.0), endpoint + Vector2(22.0, -18.0),
			endpoint + Vector2(21.0, 9.0), endpoint + Vector2(0.0, 27.0),
			endpoint + Vector2(-21.0, 9.0), endpoint + Vector2(-22.0, -18.0)])
		draw_colored_polygon(shell, Color(WARD_COLOR, 0.09))
		draw_polyline(shell, color, 2.4, true)
	var marker := endpoint + Vector2(0.0, -23.0)
	var shield := PackedVector2Array([marker + Vector2(-6.0, -3.0), marker + Vector2(6.0, -3.0), marker + Vector2(5.0, 3.0), marker + Vector2(0.0, 7.0), marker + Vector2(-5.0, 3.0), marker + Vector2(-6.0, -3.0)])
	if sustaining:
		draw_colored_polygon(shield, Color(WARD_COLOR, 0.32))
	draw_polyline(shield, color, 2.2 if sustaining else (1.6 if active else 1.0), true)

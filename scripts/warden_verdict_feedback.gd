extends Node2D
## Presentation only: a four-contact seal and the exact fourth-contact Burst.
## One cadence display per owner; short contact/impact queues remain bounded.
const REGISTRY := preload("res://scripts/shared/combat_interaction_registry.gd")
const INK := Color(0.08, 0.06, 0.04, 0.94)
const GOLD := Color(0.94, 0.72, 0.38)
const IVORY := Color(1.0, 0.94, 0.77)
const CONTACT_LIFETIME := 0.25
const BURST_LIFETIME := 0.34
const MAX_CONTACTS := 4
const MAX_BURSTS := 6

var player: Node2D
var step: int = 0
var remaining: float = 0.0
var contacts: Array[Dictionary] = []
var bursts: Array[Dictionary] = []
var _run: String = ""
var _room: int = -1
var _epoch: int = 0
var _serial: int = 0

func initialize(owner_player: Node2D) -> void:
	player = owner_player
	top_level = true
	global_position = Vector2.ZERO
	z_index = 6
	set_process(false)

func apply_cue(payload: Dictionary) -> bool:
	if not is_instance_valid(player) or player.get("_is_alive_state") == false or player.get("_combat_removed") == true:
		return false
	if payload.get("run") != REGISTRY.current_run() or payload.get("room") != REGISTRY.current_room():
		return false
	for key in ["epoch", "serial", "step"]:
		if not (payload.get(key) is int):
			return false
	var point: Variant = payload.get("position")
	var radius: Variant = payload.get("radius")
	var duration: Variant = payload.get("duration")
	if not (point is Vector2) or not point.is_finite() or not _finite_number(radius) or not _finite_number(duration):
		return false
	if int(payload.step) < 1 or int(payload.step) > 4 or float(radius) < 0.0 or float(radius) > 126.0 or float(duration) <= 0.0 or float(duration) > 3.0:
		return false
	if int(payload.step) == 4 and float(radius) < 72.0:
		return false
	var controller: Node = player.get("combat_interactions")
	if controller == null or int(payload.epoch) <= 0 or int(payload.epoch) < int(controller._accepted_epoch):
		return false
	if player._is_local_control_owner() and int(payload.epoch) != int(controller._epoch):
		return false
	if _run != String(payload.run) or _room != int(payload.room):
		clear()
		_epoch = 0
		_serial = 0
	if int(payload.epoch) < _epoch or (int(payload.epoch) == _epoch and int(payload.serial) <= _serial):
		return false
	_run = String(payload.run)
	_room = int(payload.room)
	_epoch = int(payload.epoch)
	_serial = int(payload.serial)
	step = int(payload.step)
	remaining = float(duration) if step < 4 else 0.0
	contacts.append({"position": point, "step": step, "left": CONTACT_LIFETIME})
	if contacts.size() > MAX_CONTACTS:
		contacts.pop_front()
	if step == 4:
		bursts.append({"position": point, "radius": float(radius), "left": BURST_LIFETIME})
		if bursts.size() > MAX_BURSTS:
			bursts.pop_front()
	set_process(true)
	queue_redraw()
	return true

func clear() -> void:
	step = 0
	remaining = 0.0
	contacts.clear()
	bursts.clear()
	set_process(false)
	queue_redraw()

func _process(delta: float) -> void:
	if not is_instance_valid(player) or _run != REGISTRY.current_run() or _room != REGISTRY.current_room() or player.get("_is_alive_state") == false or player.get("_combat_removed") == true or player.get("combat_damage_enabled") == false:
		clear()
		return
	# Menus pause the actor directly rather than pausing the SceneTree.
	if not player.is_physics_processing():
		return
	advance(delta)

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	remaining = maxf(0.0, remaining - delta)
	for index in range(contacts.size() - 1, -1, -1):
		contacts[index].left -= delta
		if float(contacts[index].left) <= 0.0:
			contacts.remove_at(index)
	for index in range(bursts.size() - 1, -1, -1):
		bursts[index].left -= delta
		if float(bursts[index].left) <= 0.0:
			bursts.remove_at(index)
	queue_redraw()
	if remaining <= 0.0 and contacts.is_empty() and bursts.is_empty():
		set_process(false)

func _draw() -> void:
	if is_instance_valid(player) and remaining > 0.0:
		var center := to_local(player.global_position) + Vector2(0.0, 29.0)
		var fade := minf(1.0, remaining * 5.0)
		for index in range(4):
			var rect := Rect2(center + Vector2(-16.0 + index * 9.0, -2.5), Vector2(5.0, 5.0))
			draw_rect(rect.grow(1.5), Color(INK, fade))
			if index < step:
				draw_rect(rect, Color(IVORY, fade * 0.95))
			else:
				draw_rect(rect, Color(GOLD, fade * 0.3), false, 1.0)
		if step == 3:
			# The open fourth slot is the visible ready state for the next contact.
			var tip := center + Vector2(13.5, -8.0)
			draw_polyline(PackedVector2Array([tip + Vector2(-3.0, -3.0), tip, tip + Vector2(3.0, -3.0)]), Color(IVORY, fade), 1.6, true)
	for contact: Dictionary in contacts:
		var point := to_local(contact.position)
		var fade := clampf(float(contact.left) / CONTACT_LIFETIME, 0.0, 1.0)
		var distance := 18.0 + (1.0 - fade) * 9.0
		for side in [-1.0, 1.0]:
			var points := PackedVector2Array([point + Vector2(side * (distance + 4.0), -7.0), point + Vector2(side * distance, 0.0), point + Vector2(side * (distance + 4.0), 7.0)])
			draw_polyline(points, Color(INK, fade * 0.8), 4.0, true)
			draw_polyline(points, Color(IVORY, fade), 1.8, true)
	for burst: Dictionary in bursts:
		var point := to_local(burst.position)
		var radius := float(burst.radius)
		var progress := 1.0 - float(burst.left) / BURST_LIFETIME
		var fade := pow(1.0 - progress, 1.5)
		# The outer boundary is the actual damage radius from the first frame.
		draw_arc(point, radius, 0.0, TAU, 64, Color(INK, fade * 0.85), 4.5, true)
		draw_arc(point, radius, 0.0, TAU, 64, Color(GOLD, fade * 0.82), 1.8, true)
		var seal_radius := lerpf(radius * 0.23, radius * 0.86, 1.0 - pow(1.0 - progress, 3.0))
		for index in range(4):
			var axis := Vector2.from_angle(PI * 0.25 + index * PI * 0.5)
			var tangent := axis.orthogonal()
			var tip := point + axis * seal_radius
			var edge := minf(14.0, radius * 0.18)
			var points := PackedVector2Array([tip - axis * edge - tangent * edge, tip, tip - axis * edge + tangent * edge])
			draw_polyline(points, Color(INK, fade), 6.0, true)
			draw_polyline(points, Color(IVORY, fade), 2.8, true)
		if progress < 0.28:
			var core_fade := 1.0 - progress / 0.28
			for axis in [Vector2.RIGHT, Vector2.UP]:
				draw_line(point - axis * 13.0, point + axis * 13.0, Color(IVORY, core_fade), 3.0, true)

static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

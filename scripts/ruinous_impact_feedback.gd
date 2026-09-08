extends Node2D
## Host-announced launch and impact cues. This layer never moves actors or deals
## damage; a weak target reference lets the launch cue follow replicated motion.

const ENEMY_BASE := preload("res://scripts/enemy_base.gd")
const LAUNCH := preload("res://scripts/enemy_launch_state.gd")
const AUDIO_LEVELS := preload("res://scripts/shared/audio_levels.gd")
const IMPACT_SOUND := preload("res://sounds/impactPunch_medium_002.ogg")
const MAX_LAUNCHES := 24
const MAX_BURSTS := 16
const BURST_LIFETIME := 0.26
const AMBER := Color(1.0, 0.52, 0.18)
const HOT := Color(1.0, 0.92, 0.70)

var launches: Dictionary = {}
var bursts: Array[Dictionary] = []
var _impact_sound: AudioStreamPlayer2D
var _sound_cooldown: float = 0.0

func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	z_index = 4
	_impact_sound = AudioStreamPlayer2D.new()
	_impact_sound.stream = IMPACT_SOUND
	_impact_sound.pitch_scale = 0.82
	add_child(_impact_sound)
	set_process(false)

func show_launch(serial: int, enemy: ENEMY_BASE, direction: Vector2, compression: bool, duration: float) -> void:
	if serial <= 0 or not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or not direction.is_finite() or not is_finite(duration) or duration <= 0.0:
		return
	if not launches.has(serial) and launches.size() >= MAX_LAUNCHES:
		launches.erase(launches.keys().front())
	var lifetime := clampf(duration, 0.01, 0.32)
	launches[serial] = {
		"target": weakref(enemy), "direction": direction.normalized(),
		"compression": compression, "duration": lifetime, "left": lifetime,
		"radius": LAUNCH.body_radius(enemy)
	}
	set_process(true)
	queue_redraw()

func finish_launch(serial: int) -> void:
	launches.erase(serial)
	queue_redraw()

func show_burst(position: Vector2, radius: float, direction: Vector2, sfx_volume_db: float) -> void:
	if not position.is_finite() or not direction.is_finite() or not is_finite(radius) or radius <= 0.0:
		return
	bursts.append({"position": position, "radius": clampf(radius, 1.0, 500.0), "angle": direction.angle(), "left": BURST_LIFETIME})
	if bursts.size() > MAX_BURSTS:
		bursts.pop_front()
	set_process(true)
	# A group collision should land as one impact, not a stack of loud samples.
	if _sound_cooldown <= 0.0 and is_instance_valid(_impact_sound) and is_finite(sfx_volume_db):
		_impact_sound.global_position = position
		_impact_sound.volume_db = AUDIO_LEVELS.clamp_db(sfx_volume_db - 13.0)
		_impact_sound.play()
		_sound_cooldown = 0.07
	queue_redraw()

func _process(delta: float) -> void:
	_sound_cooldown = maxf(0.0, _sound_cooldown - delta)
	for serial in launches.keys():
		var cue: Dictionary = launches[serial]
		var enemy := (cue["target"] as WeakRef).get_ref() as ENEMY_BASE
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or enemy.get_current_health() <= 0:
			launches.erase(serial)
			continue
		# Combat pause freezes the enemy's launch/compression timer as well.
		if enemy.is_physics_processing():
			cue["left"] = maxf(0.0, float(cue["left"]) - delta)
			if float(cue["left"]) <= 0.0:
				launches.erase(serial)
	for index in range(bursts.size() - 1, -1, -1):
		bursts[index]["left"] = float(bursts[index]["left"]) - delta
		if float(bursts[index]["left"]) <= 0.0:
			bursts.remove_at(index)
	# Also clear the final frame after the last cue expires, then stop polling.
	queue_redraw()
	if launches.is_empty() and bursts.is_empty() and _sound_cooldown <= 0.0:
		set_process(false)

func _draw() -> void:
	for cue: Dictionary in launches.values():
		var enemy := (cue["target"] as WeakRef).get_ref() as ENEMY_BASE
		if not is_instance_valid(enemy) or not enemy.is_visible_in_tree():
			continue
		var point := to_local(enemy.global_position)
		var progress := 1.0 - float(cue["left"]) / float(cue["duration"])
		var body_radius := float(cue["radius"])
		var fade := minf(1.0, (1.0 - progress) * 4.0)
		if bool(cue["compression"]):
			var distance := body_radius + lerpf(20.0, 2.0, progress)
			for index in range(4):
				var axis := Vector2.from_angle(PI * 0.25 + index * PI * 0.5)
				var tip := point + axis * distance
				var side := axis.orthogonal() * 4.0
				draw_polyline(PackedVector2Array([tip + axis * 6.0 + side, tip, tip + axis * 6.0 - side]), Color(HOT, fade * 0.9), 2.0, true)
		else:
			var direction: Vector2 = cue["direction"]
			var side := direction.orthogonal()
			var tail := point - direction * (body_radius + 40.0)
			for sign_value in [-1.0, 1.0]:
				var edge: Vector2 = point - direction * body_radius + side * body_radius * 0.65 * sign_value
				draw_line(tail, edge, Color(AMBER, fade * 0.22), 5.0, true)
				draw_line(tail + direction * 12.0, edge, Color(HOT, fade * 0.8), 1.5, true)
			draw_arc(point, body_radius + 3.0, direction.angle() - 1.05, direction.angle() + 1.05, 12, Color(AMBER, fade * 0.95), 2.0, true)
	for burst in bursts:
		var point := to_local(Vector2(burst["position"]))
		var radius := float(burst["radius"])
		var age := BURST_LIFETIME - float(burst["left"])
		var fade := clampf(float(burst["left"]) / BURST_LIFETIME, 0.0, 1.0)
		# The stationary contour is the real damage boundary. The short inner
		# front and six fragments provide motion without enlarging that footprint.
		draw_arc(point, radius, 0.0, TAU, 40, Color(AMBER, fade * 0.65), 1.3, true)
		var front := radius * lerpf(0.20, 1.0, clampf(age / 0.075, 0.0, 1.0))
		for index in range(6):
			var angle := float(burst["angle"]) + index * TAU / 6.0
			draw_arc(point, front, angle + 0.08, angle + TAU / 6.0 - 0.12, 8, Color(HOT, fade * 0.9), 1.0 + 2.5 * fade, true)
			var ray := Vector2.from_angle(angle)
			var distance := radius * clampf(0.2 + age * 4.0, 0.0, 1.0)
			draw_line(point + ray * maxf(0.0, distance - 12.0 * fade), point + ray * distance, Color(AMBER, fade * 0.8), 2.0, true)
		var flash := maxf(0.0, 1.0 - age / 0.065)
		draw_circle(point, minf(radius * 0.20, 12.0) * flash, Color(HOT, flash * 0.8))

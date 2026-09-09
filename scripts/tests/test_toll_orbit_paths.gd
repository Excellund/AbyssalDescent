extends "res://scripts/tests/test_live_arena_edges.gd"
## Production Orbit segments checked against an independent sampled time/space oracle.
const TOLL := preload("res://scripts/enemy_toll.gd")
const FLOW := preload("res://scripts/core/player_flow_coordinator.gd")
var toll: TOLL
var touched := 0
var missed := 0

func _fixture(position: Vector2, radius: float, directed: bool) -> void:
	_setup()
	actor.player_id = 0
	actor.global_position = position
	toll = TOLL.new()
	room.add_child(toll)
	toll.set_physics_process(false)
	toll.target = actor
	toll.target_candidates = [actor]
	toll._begin_pulse_telegraph()
	toll._begin_pulse_expand()
	toll._pulse_is_directed = directed
	toll._directed_spoke_angle = 0.19
	toll._pulse_radius = radius
	toll._pulse_phase_left = 1.1 * (1.0 - radius / 380.0)

func _sampled_hit(a: Vector2, b: Vector2, r0: float, r1: float, directed: bool) -> bool:
	for sample in range(2001):
		var t := float(sample) / 2000.0
		var x := float(a.x) + float(b.x - a.x) * t
		var y := float(a.y) + float(b.y - a.y) * t
		var r := r0 + (r1 - r0) * t
		var d := sqrt(x*x+y*y)
		if d > r or d < maxf(0.0, r - 64.0):
			continue
		if not directed:
			return true
		var angle := atan2(y,x) if d > 0.001 else 0.0
		for spoke in range(3):
			if absf(wrapf(angle - 0.19 - float(spoke)*TAU/3.0, -PI, PI)) < PI/6.0:
				return true
	return false

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	for directed in [false, true]:
		for initial_radius in [40.0, 180.0, 300.0]:
			for orientation in range(4):
				var offset := Vector2.RIGHT.rotated(float(orientation)*PI/2.0)*70.2
				_fixture(Vector2(180,0)+offset, initial_radius, directed)
				actor.apply_trial_power("razor_orbit")
				actor.apply_trial_power("razor_orbit")
				var anchor := Node2D.new()
				room.add_child(anchor)
				anchor.add_to_group("arena_columns")
				anchor.position = Vector2(180,0)
				actor.dash_direction = Vector2.RIGHT
				actor.arcana_motion.start_orbit(anchor)
				var expected := false
				for frame in range(20):
					if toll._pulse_phase == TOLL.PULSE_PHASE_NONE:
						break
					var before := actor.global_position
					var r0 := toll._pulse_radius
					var active_delta := minf(1.0/30.0, toll._pulse_phase_left)
					actor.arcana_motion.process_movement(1.0/30.0, Vector2.ZERO)
					var after := before.lerp(actor.global_position, active_delta/(1.0/30.0))
					var r1 := minf(380.0, r0 + 380.0/1.1*active_delta)
					expected = expected or _sampled_hit(before, after, r0, r1, directed)
					toll._tick_pulse(1.0/30.0)
				_check(actor.get_current_health() == (82 if expected else 100), "Actual Orbit path agrees with independent 2,001-point segment/time oracle: directed=%s radius=%s orientation=%s" % [directed,initial_radius,orientation])
				_check(actor._dash_damage_immune_left == 0.0 and not actor.dash_phasing_active, "Orbit adds no dash immunity during real band crossing")
				if expected:
					touched += 1
				else:
					missed += 1
				_clear()
				await process_frame
	for reset in [false,true]:
		_fixture(Vector2(250,0), 350.0, false)
		if reset:
			FLOW.new().reset_player_position(actor, Vector2(450,0))
		else:
			actor.position = Vector2(450,0)
		toll._tick_pulse(0.01)
		_check(actor.get_current_health() == (100 if reset else 82), "Production reset generation discards only forced reposition, retaining ordinary crossing")
		_clear()
		await process_frame
	for departed in [false,true]:
		_fixture(Vector2(50,0), 0.0, false)
		actor.set_combat_removed(departed)
		toll._tick_pulse(0.4)
		_check(actor.get_current_health() == (100 if departed else 82), "Departure removes only the absent player from active pulse")
		_check(toll._pulse_player_positions.is_empty() == departed, "Departed target history is pruned without retaining objects")
		_clear()
		await process_frame
	_check(touched > 0 and missed > 0, "Real Orbit matrix contains contacts and safe trajectories")
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Toll Orbit paths: %d checks, %d failures; %d hit paths and %d safe paths" % [checks,failures.size(),touched,missed])
	quit(0 if failures.is_empty() else 1)

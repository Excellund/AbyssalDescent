extends "res://scripts/tests/test_breakwater_runtime.gd"
## Continuous movement through the actual body/movement and accepted damage paths.

const FLOW := preload("res://scripts/core/player_flow_coordinator.gd")
var pilot_receipts: Array[Dictionary] = []

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	await _test_gate_commit_and_geometry()
	await _test_coop_openings()
	await _test_moving_crossings()
	await _test_gate_lifecycle()
	await _test_circle_pilots()
	await _test_corner_and_cover_response()
	await _test_close_range_pressure()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	FileAccess.open("res://harbor_gate_pilots.json", FileAccess.WRITE).store_string(JSON.stringify(pilot_receipts, "\t"))
	await process_frame
	print("[OK] Harbor Gate: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_gate_commit_and_geometry() -> void:
	for direction: Vector2 in SIDES:
		_setup()
		room.global_position = Vector2(81.25, -37.5)
		var bounds := EnemyReplicationService.get_current_room_bounds()
		actor.global_position = bounds.get_center() - direction * (bounds.size * 0.5 - Vector2.ONE * 40.0)
		var boss := _apex(bounds.get_center())
		await physics_frame
		boss._begin_tracking()
		boss._enter_recovery(true)
		boss._process_behavior(BREAKWATER.WALL_RECOVERY)
		boss._process_behavior(boss.attack_cooldown)
		_check(boss.phase == BREAKWATER.Phase.GATE_BRACE and boss._gate_direction == direction, "A terrain bait preserves recovery then selects the nearest committed Harbor Gate shore: %s" % direction)
		_check(boss.get_attack_callout() == "Harbor Gate / HOLD THE OPENING", "The gate uses the shared plain move-name callout")
		var gaps := boss._gate_gaps.duplicate()
		var warning := boss.get_warning_polygons()
		var origin := boss._gate_origin
		var first_health := actor.get_current_health()
		actor.global_position += direction.orthogonal() * 180.0
		boss._process_behavior(BREAKWATER.GATE_WARNING * 0.5)
		_check(boss._gate_gaps == gaps and boss._gate_origin == origin and boss.get_warning_polygons() == warning, "Moving after the tell cannot chase, move or close the opening")
		for xi in range(13):
			for yi in range(11):
				var point := bounds.position + bounds.size * Vector2(float(xi) / 12.0, float(yi) / 10.0)
				var painted := _inside_tide_polygons(warning, point)
				_check(painted == boss.gate_contains_point(point, 0.0, boss._gate_distance), "Full-floor warning and damage agree, including the boundary: %s / %s" % [direction, point])
		boss._process_behavior(BREAKWATER.GATE_WARNING * 0.5)
		_check(boss.phase == BREAKWATER.Phase.GATE and actor.get_current_health() == first_health, "Releasing a gate does not damage the whole warned floor")
		boss._process_behavior(10.0)
		_check(actor.get_current_health() == first_health - 16 and boss._hit_players.size() == 1, "A crest crossing an occupied dangerous lane hits once even on a long frame")
		_check(boss.phase == BREAKWATER.Phase.RECOVER and is_equal_approx(boss.phase_left, BREAKWATER.GATE_RECOVERY), "The spent seawall opens a full stationary punish window")
		boss._process_behavior(BREAKWATER.GATE_RECOVERY)
		boss._process_behavior(boss.attack_cooldown)
		_check(boss.phase == BREAKWATER.Phase.TRACK, "The next move returns to the ram's different response")
		_clear()

func _test_coop_openings() -> void:
	_setup()
	actor.global_position = Vector2(480.0, -300.0)
	var boss := _apex()
	var peers: Array[Probe] = []
	for index in range(3):
		var probe := Probe.new()
		probe.player_id = index + 2
		room.add_child(probe)
		probe.global_position = Vector2(480.0, -100.0 + index * 200.0)
		peers.append(probe)
	boss._begin_harbor_gate()
	_check(boss._gate_gaps.size() == 4, "Four spread participants receive four bounded openings")
	var total_gap := 0.0
	for gap in boss._gate_gaps:
		total_gap += gap.y - gap.x
	_check(is_equal_approx(total_gap, 448.0) and total_gap < room.current_room_size.y * 0.55, "A four-player spread cannot turn the ordinary arena into one calm shore")
	for player in [actor] + peers:
		_check(not boss.gate_contains_point(player.global_position, 0.0, boss._gate_distance), "Every living player can remain safely in their own committed opening")
	var runtime := boss.get_network_runtime_state()
	_check(boss._valid_gate_packet(runtime.custom.g), "The complete four-player geometry passes the replica validator")
	for probe in peers:
		probe.global_position = actor.global_position + Vector2(0.0, 15.0)
	boss._begin_harbor_gate()
	_check(boss._gate_gaps.size() == 1 and is_equal_approx(boss._gate_gaps[0].y - boss._gate_gaps[0].x, 127.0), "Overlapping party openings merge without nested hazards or expanding unrelated gaps")
	actor.set_combat_removed(true)
	peers[0].health_state.current_health = 0
	peers[1].global_position.y = 100.0
	peers[2].global_position.y = 300.0
	boss.target = peers[1]
	boss.target_candidates = [peers[1], peers[2]]
	boss._begin_harbor_gate()
	_check(boss._gate_gaps.size() == 2, "Removed and dead players do not reserve new openings")
	_clear()

func _crossing_setup(cross: float = 160.0) -> Apex:
	_setup()
	actor.global_position = Vector2(-500.0, 0.0)
	var boss := _apex(Vector2(0.0, -240.0))
	boss._begin_harbor_gate()
	actor.global_position = boss._gate_origin + boss._gate_direction * 220.0 + boss._gate_direction.orthogonal() * cross
	boss._release_harbor_gate()
	boss._gate_progress = 100.0
	return boss

func _test_moving_crossings() -> void:
	var boss := _crossing_setup()
	await physics_frame
	var initial := actor.get_current_health()
	actor.move_and_collide(-boss._gate_direction * 170.0)
	_check(not boss.gate_contains_point(actor.global_position, 100.0, 174.0), "The fast crossing ends beyond the ordinary endpoint-only test")
	boss._process_behavior(0.2)
	_check(actor.get_current_health() == initial - 16, "Opposing fast movement crosses the moving seawall in relative time and deals one accepted hit")
	boss._process_behavior(0.1)
	_check(actor.get_current_health() == initial - 16, "Repeated overlap cannot hit the same player twice per gate")
	_clear()
	boss = _crossing_setup(0.0)
	await physics_frame
	actor.move_and_collide(-boss._gate_direction * 170.0)
	boss._process_behavior(0.2)
	_check(actor.get_current_health() == 100, "The same fast crossing through an actual opening is safe")
	_clear()
	boss = _crossing_setup()
	await physics_frame
	FLOW.new().reset_player_position(actor, actor.global_position - boss._gate_direction * 170.0)
	boss._process_behavior(0.2)
	_check(actor.get_current_health() == 100, "An explicit respawn/room correction resets motion history instead of inventing a traveled hit")
	_clear()
	boss = _crossing_setup()
	await physics_frame
	await process_frame
	actor._refresh_combat_input_release()
	actor.aim = -boss._gate_direction
	actor.dash_cooldown_left = 0.0
	Input.action_press("dash")
	actor._try_start_dash(actor.aim)
	Input.action_release("dash")
	_check(actor.dash_time_left > 0.0, "Actual normal Dash starts through the input boundary: local=%s frozen=%s locked=%s pressed=%s blocked=%s" % [actor._is_local_control_owner(), actor.encounter_input_frozen, actor._is_attack_locked(), Input.is_action_just_pressed("dash"), actor._combat_actions_awaiting_release])
	actor.move_and_collide(-boss._gate_direction * 170.0)
	boss._process_behavior(0.2)
	_check(actor.get_current_health() == 100, "The accepted gate contact honors existing normal Dash immunity")
	_clear()

func _test_gate_lifecycle() -> void:
	for active in [false, true]:
		for reason in ["cancel", "bounds", "no_players", "authority", "death"]:
			_setup()
			actor.global_position = Vector2(400.0, 0.0)
			var boss := _apex()
			boss._begin_harbor_gate()
			if active:
				boss._release_harbor_gate()
			match reason:
				"cancel": boss._cancel_attack()
				"bounds":
					room.current_effective_room_size += Vector2(20.0, 0.0)
					boss._process_behavior(0.02)
				"no_players":
					actor.set_combat_removed(true)
					boss._process_behavior(0.02)
				"authority": boss.set_network_simulation_enabled(false)
				"death": boss.take_damage(99999)
			_check(boss.get_warning_polygons().is_empty() and boss._gate_gaps.is_empty() and boss._gate_player_positions.is_empty(), "%s clears the %s gate, opening and motion history" % [reason, "moving" if active else "warning"])
			_clear()

func _move_pilot(direction: Vector2, delta: float) -> float:
	var before := actor.global_position
	actor._update_ground_movement(direction, delta)
	actor.move_and_collide(actor.velocity * delta)
	var bounds := EnemyReplicationService.get_current_room_bounds()
	actor.global_position = actor.global_position.clamp(bounds.position, bounds.end)
	actor._contact_damage_grace_left = maxf(0.0, actor._contact_damage_grace_left - delta)
	return before.distance_to(actor.global_position)

func _pilot(radius: float, angle: float, speed_mult: float, mode: String, duration: float = 32.0) -> Dictionary:
	_setup()
	actor.global_position = Vector2.from_angle(angle) * radius
	actor.max_speed = 220.0 if speed_mult == 1.0 else 188.0
	actor.external_slow_left = 1000.0 if speed_mult < 1.0 else 0.0
	actor.external_slow_mult = speed_mult
	var boss := _apex(Vector2.ZERO)
	await physics_frame
	var contacts := 0
	var gate_contacts := 0
	var gates := 0
	var traveled := 0.0
	var gate_seen := -1
	var reaction := 0.0
	var elapsed := 0.0
	while elapsed < duration:
		var radial := actor.global_position.normalized()
		var direction := (radial.orthogonal() + radial * (radius - actor.global_position.length()) * 0.035).normalized()
		if mode == "legacy":
			boss._gate_next = false # The previous ram/Return Tide loop, with identical movement and damage.
		if boss.phase in [BREAKWATER.Phase.GATE_BRACE, BREAKWATER.Phase.GATE]:
			if gate_seen != boss._attack_generation:
				gate_seen = boss._attack_generation
				reaction = 0.35
				gates += 1
			if mode == "respond" and reaction <= 0.0:
				var side := boss._gate_direction.orthogonal()
				var cross := (actor.global_position - boss._gate_origin).dot(side)
				var middle := (boss._gate_gaps[0].x + boss._gate_gaps[0].y) * 0.5
				direction = side * clampf((middle - cross) / 9.0, -1.0, 1.0)
			reaction -= STEP
		var health_before := actor.get_current_health()
		traveled += _move_pilot(direction, STEP)
		var phase_before := boss.phase
		boss._process_behavior(STEP)
		if actor.get_current_health() < health_before:
			contacts += 1
			if phase_before == BREAKWATER.Phase.GATE:
				gate_contacts += 1
			actor.health_state.current_health = 100
		elapsed += STEP
	var receipt := {"mode": mode, "radius": radius, "angle": angle, "speed_mult": speed_mult, "seconds": duration, "hits": contacts, "gate_hits": gate_contacts, "gates": gates, "traveled": snappedf(traveled, 0.1)}
	pilot_receipts.append(receipt)
	print("[PILOT] " + JSON.stringify(receipt))
	_clear()
	await process_frame
	return receipt

func _test_circle_pilots() -> void:
	for speed_mult: float in [1.0, 0.45]:
		var legacy_hits := 0
		var new_hits := 0
		var reacted_gate_hits := 0
		var crossed_gates := 0
		for radius: float in [260.0, 350.0]:
			for angle: float in [0.0, 1.2, 2.7, 4.4]:
				var legacy := await _pilot(radius, angle, speed_mult, "legacy")
				var circle := await _pilot(radius, angle, speed_mult, "circle")
				var respond := await _pilot(radius, angle, speed_mult, "respond")
				legacy_hits += legacy.hits
				new_hits += circle.hits
				crossed_gates += circle.gate_hits
				reacted_gate_hits += respond.gate_hits
				_check(legacy.traveled > 900.0 and circle.traveled > 900.0 and respond.traveled > 500.0, "All comparison pilots really move through the production acceleration and collision path")
		_check(crossed_gates >= 8, "Continuous circling is repeatedly caught by committed crossings at speed%.2f: %d" % [speed_mult, crossed_gates])
		_check(new_hits > legacy_hits, "The new loop creates more actual contacts than its previous circle-safe loop at speed%.2f: %d > %d" % [speed_mult, new_hits, legacy_hits])
		_check(reacted_gate_hits == 0, "A 0.35s response followed by ground movement avoids every gate at speed%.2f: %d" % [speed_mult, reacted_gate_hits])

func _test_corner_and_cover_response() -> void:
	for size: Vector2 in [Vector2(1160.0, 860.0), Vector2(740.0, 540.0)]:
		for signs: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_setup()
			room.current_room_size = size
			room.current_effective_room_size = size
			actor.global_position = signs * (size * 0.5 - Vector2(20.0, 20.0))
			actor.max_speed = 188.0
			actor.external_slow_left = 100.0
			actor.external_slow_mult = 0.45
			_thin_cover(actor.global_position - signs * Vector2(75.0, 60.0))
			var boss := _apex()
			await physics_frame
			boss._begin_harbor_gate()
			var initial := actor.global_position
			var elapsed := 0.0
			var traveled := 0.0
			while boss.phase in [BREAKWATER.Phase.GATE_BRACE, BREAKWATER.Phase.GATE]:
				var direction := -signs.normalized() if elapsed < 0.35 else actor.global_position.direction_to(initial) * minf(1.0, actor.global_position.distance_to(initial) / 9.0)
				traveled += _move_pilot(direction, STEP)
				boss._process_behavior(STEP)
				elapsed += STEP
			_check(actor.get_current_health() == 100 and traveled > 20.0, "Slowed movement back to the committed corner opening remains safe beside real cover: %s / %s" % [size, signs])
			_clear()
			await process_frame

func _close_attack_pilot(stationary: bool, blocked: bool = false) -> Dictionary:
	_setup()
	actor.global_position = Vector2(390.0, 0.0)
	var boss := _apex(Vector2(440.0, 0.0))
	if blocked:
		# Two genuine terrain columns pin the intended lateral brace. The
		# player remains in the calm lane, without being pushed by the boss.
		_thin_cover(Vector2(440.0, 40.0))
		_thin_cover(Vector2(440.0, -40.0))
	await physics_frame
	boss._begin_harbor_gate()
	var origin := boss.global_position
	var player_origin := actor.global_position
	var attack_left := 0.0
	var elapsed := 0.0
	while boss.phase in [BREAKWATER.Phase.GATE_BRACE, BREAKWATER.Phase.GATE]:
		if stationary:
			boss._gate_brace_position = boss.global_position # Compare the stationary gate prototype.
		attack_left -= STEP
		if attack_left <= 0.0:
			actor._perform_melee_attack(actor.global_position.direction_to(boss.global_position), {"damage": 20, "range": 78.0, "arc_degrees": 130.0})
			attack_left += actor.attack_cooldown
		boss._process_behavior(STEP)
		elapsed += STEP
	var result := {"mode": "close_attack", "stationary": stationary, "blocked": blocked, "boss_damage": 900 - boss.get_current_health(), "seconds": snappedf(elapsed, 0.01), "step": snappedf(origin.distance_to(boss.global_position), 0.1), "player_damage": 100 - actor.get_current_health()}
	_check(actor.global_position == player_origin and actor.get_current_health() == 100, "The lateral brace cannot move or damage a player holding their committed opening")
	pilot_receipts.append(result)
	print("[PILOT] " + JSON.stringify(result))
	_clear()
	await process_frame
	return result

func _test_close_range_pressure() -> void:
	var stationary := await _close_attack_pilot(true)
	var final := await _close_attack_pilot(false)
	var pinned := await _close_attack_pilot(false, true)
	_check(stationary.boss_damage >= 200 and final.boss_damage <= stationary.boss_damage * 0.3 and final.step > 120.0, "The committed brace removes prolonged free melee from the calm opening: %s versus %s" % [stationary, final])
	_check(pinned.step < 40.0 and pinned.boss_damage > final.boss_damage, "Actual terrain can still earn melee access by pinning the harmless brace: %s" % pinned)

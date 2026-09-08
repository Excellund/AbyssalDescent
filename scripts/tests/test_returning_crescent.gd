extends "res://scripts/tests/test_hit_origins.gd"

const CRESCENT := preload("res://scripts/returning_crescent_controller.gd")
const CUE_QUEUE := preload("res://scripts/core/player_cue_sync_queue.gd")
var crescent: CRESCENT

func _run() -> void:
	_test_registry_contract()
	await _test_levels_and_legs()
	await _test_primary_hooks()
	await _test_return_path()
	await _test_cover_and_ricochet()
	await _test_repeated_crossings_and_thin_cover()
	await _test_shield_approach()
	await _test_hit_cancellation()
	await _test_snapshot_and_input_clear()
	await _test_remote_presentation()
	await _settle()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("[ReturningCrescent] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_registry_contract() -> void:
	_setup_crescent(0)
	_check(player.apply_power_for_test(" Returning_Crescent ") and player.returning_crescent_stacks == 1, "Named debug grants recognize Crescent and apply its first level")
	var registry := player.upgrade_system.power_registry
	var matches := registry.get_trial_power_pool().filter(func(entry: Dictionary) -> bool: return entry.id == "returning_crescent")
	_check(matches.size() == 1, "Crescent appears exactly once in the shared Arcana pool")
	_check(registry.get_power_display_name("returning_crescent") == "Returning Crescent" and registry.get_power_stack_limit("returning_crescent") == 3, "Registry exposes the correct name and structural level cap")
	_check(registry.get_damage_model("returning_crescent").get("scale_source") == "damage_stat", "Registry reports the controller's Damage stat scaling")
	var snapshot := player.build_run_snapshot()
	for property in ["reward_returning_crescent", "returning_crescent_stacks", "returning_crescent_damage_scale", "returning_crescent_reach_scale"]:
		_check(MAPPER.get_all_snapshot_properties().has(property) and snapshot.properties.has(property), "Learned %s participates in both mapper and real player snapshots" % property)
	_free_world()

func _setup_crescent(level: int = 1) -> void:
	_make_world()
	player.damage = 100
	crescent = player.returning_crescent
	crescent.set_physics_process(false)
	for index in range(level):
		player.apply_trial_power("returning_crescent")

func _advance_crescent(duration: float) -> void:
	var remaining := duration
	while remaining > 0.00001:
		var step := minf(0.01, remaining)
		crescent.tick(step)
		remaining -= step

func _test_levels_and_legs() -> void:
	for level in [1, 2, 3]:
		_setup_crescent(level)
		var enemy := _origin_enemy(Vector2(100.0, 0.0))
		await _settle()
		_check(crescent.try_launch(Vector2.RIGHT), "L%d launches its first blade" % level)
		var first := crescent.blades[0]
		_check(is_equal_approx(first.travel_left, 220.0 * (1.0 + 0.15 * (level - 1))), "L%d has the correct outbound distance" % level)
		_check(first.bounces_left == (1 if level == 3 else 0), "Wall bounce unlocks only at L3")
		_check(crescent.try_launch(Vector2.UP) == (level >= 2), "Second blade unlocks at L2")
		_check(not crescent.try_launch(Vector2.DOWN), "Active blade count stays bounded")
		_advance_crescent(1.0)
		_check(enemy.hits.size() == 2, "A target takes exactly one outgoing and one returning hit")
		if enemy.hits.size() == 2:
			var expected := int(round(45.0 * (1.0 + 0.15 * (level - 1))))
			_check(enemy.hits[0].applied == expected and enemy.hits[1].applied == expected, "Both legs use level-scaled Damage")
			_check(enemy.hits.all(func(hit: Dictionary) -> bool: return hit.attack_type == "returning_crescent" and hit.secondary), "Both legs carry secondary provenance")
		_check(crescent.blades.is_empty(), "Returned blades free their slots")
		_check(crescent.try_launch(Vector2.RIGHT), "Next deliberate attack can use a caught blade")
		_free_world()
	_setup_crescent(3)
	_check(player.upgrade_system.apply_trial_power("returning_crescent"), "Prismatic applies at L3")
	await _settle()
	crescent.try_launch(Vector2.RIGHT)
	_check(crescent.blades[0].damage == 70 and is_equal_approx(crescent.blades[0].travel_left, 343.2), "Prismatic scales each knob once without another level")
	_check(not player.upgrade_system.apply_trial_power("returning_crescent"), "A second Prismatic claim is rejected")
	var snapshot := player.build_run_snapshot()
	player.apply_run_snapshot(snapshot)
	_check(crescent.blades.is_empty() and player.returning_crescent_stacks == 3 and is_equal_approx(player.returning_crescent_damage_scale, 1.56), "Snapshot retains Prismatic progression and clears blades")
	_free_world()

func _test_primary_hooks() -> void:
	_setup_crescent(2)
	player.reward_razor_wind = true
	player.apply_upgrade("sovereigns_double")
	player.boss_combinations.create_shade(Vector2(0.0, 100.0))
	await _settle()
	player._try_execute_attack(Vector2.RIGHT)
	_check(crescent.blades.size() == 1, "Accepted melee launches once despite Razor Wind and a shade echo")
	player._try_execute_attack(Vector2.RIGHT)
	_check(crescent.blades.size() == 1, "Rejected cooldown input cannot throw another blade")
	player.perform_motion_blast(Vector2.UP, 1.0)
	_check(crescent.blades.size() == 2, "An intentional charged Blast may use the second blade")
	crescent.cancel()
	DAMAGEABLE.begin_secondary_scope()
	_check(not crescent.try_launch(Vector2.RIGHT), "Secondary proc scope cannot create a blade")
	DAMAGEABLE.end_secondary_scope()
	_check(not crescent.try_launch(Vector2.INF) and not crescent.try_launch(Vector2.ZERO), "Invalid directions never create projectiles")
	_free_world()

func _test_return_path() -> void:
	_setup_crescent()
	var direct := _origin_enemy(Vector2(100.0, 0.0))
	var diagonal := _origin_enemy(Vector2(110.0, 100.0))
	await _settle()
	crescent.try_launch(Vector2.RIGHT)
	_advance_crescent(0.355)
	_check(direct.hits.size() == 1 and diagonal.hits.is_empty(), "Outgoing blade follows its deliberate aim")
	player.position = Vector2(0.0, 200.0)
	var before_velocity := player.velocity
	player._dash_damage_immune_left = 0.17
	_advance_crescent(0.6)
	_check(diagonal.hits.size() == 1 and direct.hits.size() == 1, "Moving the owner changes the returning damage path")
	_check(player.velocity == before_velocity and player._dash_damage_immune_left == 0.17, "Blade movement never moves the player or extends dash immunity")
	_check(crescent.blades.is_empty(), "Clamped homing catches instead of overshooting")
	_free_world()
	_setup_crescent()
	var hitch_target := _origin_enemy(Vector2(100.0, 0.0))
	await _settle()
	crescent.try_launch(Vector2.RIGHT)
	crescent.tick(1.8)
	_check(hitch_target.hits.size() == 2 and crescent.blades.is_empty(), "Swept substeps preserve both legs through a large frame hitch")
	_free_world()
	_setup_crescent()
	await _settle()
	crescent.try_launch(Vector2.RIGHT)
	player.position = Vector2(-10000.0, 0.0)
	crescent.tick(2.1)
	_check(crescent.blades.is_empty(), "An unreachable owner cannot leave a permanent blade")
	_free_world()

func _test_cover_and_ricochet() -> void:
	_setup_crescent()
	_wall(Vector2(100.0, 0.0), 20.0)
	var hidden := _origin_enemy(Vector2(130.0, 0.0))
	await _settle()
	crescent.try_launch(Vector2.RIGHT)
	crescent.tick(1.0)
	_check(hidden.hits.is_empty() and crescent.blades.is_empty(), "A column turns the base blade home and protects enemies behind it")
	_free_world()
	_setup_crescent(3)
	_wall(Vector2(100.0, 15.0), 20.0)
	await _settle()
	crescent.try_launch(Vector2.RIGHT)
	var blade := crescent.blades[0]
	crescent.tick(0.15)
	_check(blade.bounces_left == 0 and not blade.returning, "L3 spends exactly one outward bounce")
	_check(blade.direction.y < -0.5, "A glancing column hit reflects using the real surface normal")
	_check(blade.travel_left < 200.0, "Ricochet spends the existing outbound budget")
	_advance_crescent(1.0)
	_check(crescent.blades.is_empty(), "A bounced blade still returns or safely expires")
	_free_world()
	_setup_crescent()
	await _settle()
	crescent.try_launch(Vector2.RIGHT)
	_advance_crescent(0.36)
	var returning := crescent.blades[0]
	_wall(Vector2.ZERO, 20.0)
	player.position = Vector2(-150.0, 0.0)
	await _settle()
	_advance_crescent(0.5)
	_check(crescent.blades.is_empty() and returning.life_left > 0.0, "Cover blocks the return leg and frees the slot immediately")
	_free_world()

func _test_shield_approach() -> void:
	_setup_crescent()
	var shield := _shield()
	shield.position = Vector2(100.0, 0.0)
	shield.shield_facing = Vector2.LEFT
	shield.target = player
	await _settle()
	crescent.try_launch(Vector2.RIGHT)
	_advance_crescent(0.30)
	var outward := 10000 - shield.get_current_health()
	_check(outward > 0 and outward < 45, "Outgoing blade is blocked on the actual shield face")
	var before_return := shield.get_current_health()
	_advance_crescent(0.5)
	_check(before_return - shield.get_current_health() == 45, "Return blade strikes the rear despite unchanged AI target")
	_check(shield.origins.size() == 2 and shield.origins[0].x < 100.0 and shield.origins[1].x > 100.0, "Each leg carries its actual approach origin")
	_free_world()

func _test_repeated_crossings_and_thin_cover() -> void:
	for large_delta in [false, true]:
		_setup_crescent(3)
		_wall(Vector2(100.0, 0.0), 20.0)
		_wall(Vector2(-160.0, 0.0), 20.0)
		var front := _origin_enemy(Vector2(40.0, 0.0))
		var back := _origin_enemy(Vector2(-70.0, 0.0))
		await _settle()
		crescent.try_launch(Vector2.RIGHT)
		var blade := crescent.blades[0]
		if large_delta:
			crescent.tick(1.8)
		else:
			_advance_crescent(1.8)
		_check(front.hits.size() == 1 and back.hits.size() == 2, "Crossing a target twice outbound never resets its hit allowance (hitch=%s)" % large_delta)
		_check(blade.bounces_left == 0 and blade.outgoing_hits.size() == 2 and blade.returning_hits.size() == 1 and crescent.blades.is_empty(), "Second wall ends the outward leg without granting a second bounce")
		_free_world()
	_setup_crescent()
	var wall := StaticBody2D.new()
	var collider := CollisionShape2D.new()
	collider.shape = RectangleShape2D.new()
	(collider.shape as RectangleShape2D).size = Vector2(1.0, 80.0)
	wall.add_child(collider)
	wall.position = Vector2(100.0, 0.0)
	world.add_child(wall)
	var hidden := _origin_enemy(Vector2(112.0, 0.0))
	await _settle()
	crescent.try_launch(Vector2.RIGHT)
	crescent.tick(1.8)
	_check(hidden.hits.is_empty(), "A one-pixel wall blocks a large-frame sweep and an overlapping target behind cover")
	_free_world()

func _test_hit_cancellation() -> void:
	_setup_crescent()
	var first := _origin_enemy(Vector2(60.0, 0.0))
	var next := _origin_enemy(Vector2(120.0, 0.0))
	await _settle()
	first.damage_received.connect(func(_amount: int, _remaining: int) -> void: player.discard_pending_combat_input())
	crescent.try_launch(Vector2.RIGHT)
	crescent.tick(0.8)
	_check(first.hits.size() == 1 and next.hits.is_empty() and crescent.blades.is_empty(), "Synchronous final-hit/modal cancellation aborts the rest of the sweep")
	_free_world()

func _test_snapshot_and_input_clear() -> void:
	_setup_crescent(2)
	await _settle()
	var learned := player.build_run_snapshot()
	for cause in ["modal", "focus", "combat", "snapshot", "death"]:
		player.combat_damage_enabled = true
		player._is_alive_state = true
		crescent.try_launch(Vector2.RIGHT)
		match cause:
			"modal": player.discard_pending_combat_input()
			"focus": player._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			"combat": player.set_combat_damage_enabled(false)
			"snapshot": player.apply_run_snapshot(learned)
			"death":
				player._is_alive_state = false
				crescent.tick(0.1)
		_check(crescent.blades.is_empty(), "%s clears transient blades" % cause)
	player.apply_run_snapshot({"properties": {}, "current_health": 100})
	_check(not player.reward_returning_crescent and player.returning_crescent_stacks == 0, "Legacy snapshot cannot retain an absent learned power on a reused player")
	_free_world()

func _test_remote_presentation() -> void:
	_setup_crescent(2)
	var enemy := _origin_enemy(Vector2(100.0, 0.0))
	await _settle()
	crescent.try_launch(Vector2.RIGHT)
	crescent.try_launch(Vector2.UP)
	var state := crescent.build_network_state()
	var queue := CUE_QUEUE.new()
	_check(queue.estimate_event_bytes("returning_crescent_state", state) <= 640, "Two blades fit the existing cue budget")
	var remote_player := ComboPlayer.new()
	_add_circle(remote_player, 14.0)
	world.add_child(remote_player)
	remote_player.player_id = 2
	remote_player.is_local_player = false
	remote_player.returning_crescent.set_physics_process(false)
	MultiplayerSessionManager.session_connected = true
	MultiplayerSessionManager.is_host_peer = true
	MultiplayerSessionManager.local_peer_id = 1
	var remote: CRESCENT = remote_player.returning_crescent
	remote.apply_network_state(state)
	_check(remote.blades.size() == 2, "Replica accepts two compact visual blades")
	_check(not remote.try_launch(Vector2.RIGHT), "Replica cannot create gameplay blades")
	remote.tick(0.2)
	_check(enemy.hits.is_empty() and world.damage_total == 0, "Replica prediction never deals damage or records stats")
	var advanced := crescent.build_network_state()
	advanced.s = state.s + 1
	advanced.b[0][1] = Vector2(150.0, 0.0)
	remote.apply_network_state(advanced)
	remote.apply_network_state(state)
	_check(remote.blades[0].position == Vector2(150.0, 0.0), "Out-of-order state cannot rewind an active blade")
	var catching := advanced.duplicate(true)
	catching.s += 1
	catching.b[0][1] = Vector2(30.0, 0.0)
	catching.b[0][3] = true
	remote.apply_network_state(catching)
	remote.tick(0.02)
	_check(remote.blades[0].presentation_finished and not remote.blades[1].presentation_finished, "A natural remote catch retires only that blade")
	advanced.s = catching.s + 1
	remote.apply_network_state(advanced)
	_check(remote.blades[0].presentation_finished and not remote.blades[1].presentation_finished, "A delayed authoritative state cannot make a caught blade reappear")
	remote.tick(0.4)
	_check(remote.blades.is_empty(), "Lost updates expire remote blades")
	advanced.s += 1
	remote.apply_network_state(advanced)
	_check(remote.blades.is_empty(), "A late state cannot resurrect an expired blade ID")
	advanced.s += 1
	advanced.n = 3
	advanced.b = [[3, Vector2(50.0, 0.0), Vector2.RIGHT, false, 170.0, 1.9, 0]]
	remote.apply_network_state(advanced)
	_check(remote.blades.size() == 1 and remote.blades[0].id == 3, "A new blade ID can start after a cleared sequence")
	var clear := {"s": advanced.s + 1, "r": 0, "n": 3, "b": []}
	remote.apply_network_state(clear)
	remote.apply_network_state(advanced)
	_check(remote.blades.is_empty(), "Reliable clear wins over older active state")
	advanced.s += 3
	advanced.r = 99
	advanced.n = 4
	advanced.b[0][0] = 4
	remote.apply_network_state(advanced)
	_check(remote.blades.is_empty(), "Old room state cannot spawn blades in another room")
	if is_instance_valid(remote_player.upgrade_system.power_registry):
		remote_player.upgrade_system.power_registry.free()
	MultiplayerSessionManager.session_connected = false
	MultiplayerSessionManager.is_host_peer = false
	_free_world()

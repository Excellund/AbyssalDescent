extends "res://scripts/tests/test_blast_feedback.gd"
## Real melee/echo damage and real player-indicator receive paths, with isolated
## profiles supplied by run_gameplay_regressions.ps1.

func _run() -> void:
	await _test_moving_melee()
	await _test_empowered_melee()
	await _test_wind_levels()
	await _test_remote_wind()
	await _test_shade_wind()
	await _test_invalid_and_expired_visuals()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Attack feedback: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _swings(actor: Node2D) -> Array[Polygon2D]:
	var result: Array[Polygon2D] = []
	for child in actor.player_feedback.get_children():
		if child is Polygon2D and not child.is_queued_for_deletion():
			result.append(child)
	return result

func _contains(swing: Polygon2D, world_point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(swing.to_local(world_point), swing.polygon)

func _outer_radius(swing: Polygon2D) -> float:
	var outer := 0.0
	for point in swing.polygon:
		outer = maxf(outer, point.length())
	return outer

func _test_moving_melee() -> void:
	_make_world()
	var victim := _enemy(Vector2(45.0, 0.0))
	var untouched := _enemy(Vector2(-85.0, 0.0))
	await physics_frame
	var origin := player.global_position
	player.arcana_motion.motion = MOTION.Motion.RECOIL
	player.arcana_motion.recoil_direction = Vector2.LEFT
	player.arcana_motion.recoil_initial_direction = Vector2.LEFT
	player.arcana_motion.recoil_left = 170.0
	player.arcana_motion.recoil_speed = 700.0
	player._try_execute_attack(Vector2.RIGHT)
	var swings := _swings(player)
	_check(swings.size() == 1 and victim.get_current_health() < 10000, "An accepted moving melee strike produces one damage shape")
	var swing := swings[0]
	_check(swing.global_position.is_equal_approx(origin) and swing.scale == Vector2.ONE, "Melee starts at full damage reach and the firing origin")
	_check(_contains(swing, victim.global_position) and not _contains(swing, untouched.global_position), "Drawn melee covers the accepted victim and excludes the untouched enemy")
	var before := victim.get_current_health()
	player.arcana_motion.process_movement(0.08, Vector2.ZERO)
	_check(player.global_position.distance_to(origin) > 50.0, "Real recoil continues during the melee strike")
	_check(swing.global_position.is_equal_approx(origin), "Recoil cannot drag the completed swing to the player's next position")
	await create_timer(0.035).timeout
	_check(is_instance_valid(swing) and swing.scale == Vector2.ONE and is_equal_approx(_outer_radius(swing), player.attack_range), "Fading melee keeps its true damage radius")
	_check(victim.get_current_health() == before and untouched.get_current_health() == 10000, "The fading strike does not apply another moving damage sweep")
	_free_world()

func _test_empowered_melee() -> void:
	_make_world()
	player._indomitable_spirit_primed = true
	player.indomitable_damage_bank = player._get_indomitable_fill_requirement()
	player.passive_iron_retort = true
	player.iron_retort_brace_ready = true
	player.reward_farline_volley = true
	player._farline_volley_current_stacks = 2
	var reach := player.attack_range * player.INDOMITABLE_OATH_PRIMED_REACH_SCALE
	var arc := player.attack_arc_degrees + 24.0 + player.farline_volley_arc_per_stack * 2.0
	var origin := player.global_position
	var extended := _enemy(Vector2(reach - 2.0, 0.0))
	var widened := _enemy(Vector2.RIGHT.rotated(deg_to_rad(arc * 0.5 - 2.0)) * reach * 0.8)
	await physics_frame
	player._try_execute_attack(Vector2.RIGHT)
	var swing := _swings(player)[0]
	_check(extended.get_current_health() < 10000 and widened.get_current_health() < 10000, "Primed reach and Retort/Farline angles still damage their extended targets")
	_check(is_equal_approx(_outer_radius(swing), reach) and _contains(swing, extended.global_position) and _contains(swing, widened.global_position), "Empowered melee draws final reach and angle before bonuses are consumed")
	_check(swing.global_position == origin, "Empowered attack effects retain the original damage position")
	_free_world()

func _test_wind_levels() -> void:
	for level in range(1, 5):
		_make_world()
		for _index in level:
			player.apply_trial_power("razor_wind")
		var origin := player.global_position
		player._try_execute_attack(Vector2.RIGHT)
		var swings := _swings(player)
		_check(swings.size() == 2, "Razor Wind L%d produces melee and wind visuals" % level)
		var wind := swings[1]
		_check(not _contains(wind, origin + Vector2(player.attack_range * 0.5, 0.0)), "Razor Wind L%d leaves the melee center out of its outer band" % level)
		_check(_contains(wind, origin + Vector2((player.attack_range + _outer_radius(wind)) * 0.5, 0.0)), "Razor Wind L%d visibly includes its actual outer band" % level)
		player.global_position += Vector2(70.0, 35.0)
		_check(wind.global_position.is_equal_approx(origin) and wind.scale == Vector2.ONE, "Razor Wind L%d retains origin and reach through player movement" % level)
		_free_world()

func _test_remote_wind() -> void:
	_make_world()
	player.local_owner = false
	player.player_id = 7
	player.global_position = Vector2(350.0, -100.0)
	var service = root.get_node("PlayerReplicationService")
	var old_nodes: Dictionary = service.player_nodes.duplicate()
	var old_local: int = service.local_peer_id
	service.local_peer_id = 1
	service.player_nodes[7] = player
	var origin := Vector2(-160.0, 80.0)
	service._sync_attack_indicator(7, Vector2.RIGHT, 150.0, 70.0, Color.WHITE, 0.14, origin, 65.0)
	var wind := _swings(player).back() as Polygon2D
	_check(wind.global_position == origin, "The production indicator receive path uses the transmitted origin, independent of interpolation")
	_check(not _contains(wind, origin + Vector2(40.0, 0.0)) and _contains(wind, origin + Vector2(100.0, 0.0)), "Remote Razor Wind retains the transmitted hollow inner boundary")
	player.global_position += Vector2(130.0, 80.0)
	_check(wind.global_position == origin and wind.scale == Vector2.ONE, "Subsequent replica movement cannot drag or resize the attack")
	service.player_nodes = old_nodes
	service.local_peer_id = old_local
	_free_world()

func _test_shade_wind() -> void:
	_make_world()
	var inner_victim := _enemy(Vector2(30.0, 0.0))
	var wind_victim := _enemy(Vector2(105.0, 0.0))
	await physics_frame
	var origin := player.global_position
	player.sovereigns_double_stacks = 2
	player.boss_combinations.create_shade(origin)
	player.boss_combinations.repeat_strike(Vector2.RIGHT, [{"source": "razor_wind", "interaction": player.new_combat_action("melee"), "damage": 20, "range": 145.0, "arc_degrees": 70.0, "inner_range": 65.0}])
	_check(inner_victim.get_current_health() == 10000 and wind_victim.get_current_health() == 9989, "Shade wind still damages only the outer band at 55% strength")
	var effect: Dictionary = player.boss_combinations._echo_visuals.back()
	var payload: Dictionary = _latest_cue("sovereign_double_strike")["payload"]
	_check(effect["position"] == origin and effect["inner_range"] == 65.0 and payload == effect, "Local and broadcast shade geometry include the same true inner boundary")
	player.boss_combinations._echo_visuals.clear()
	player.local_owner = false
	player.global_position += Vector2(-160.0, 80.0)
	player.apply_network_cue_event("sovereign_double_strike", payload)
	_check(player.boss_combinations._echo_visuals.back() == effect, "A remote shade receives the exact world-space wind band")
	_check(player.boss_combinations.shade_hits == 1, "Visual parity does not add shade charges or change repeat limits")
	_free_world()

func _test_invalid_and_expired_visuals() -> void:
	_make_world()
	var feedback := player.player_feedback
	feedback.play_attack_swing_visual(Vector2.RIGHT, NAN, 90.0)
	feedback.play_attack_swing_visual(Vector2.RIGHT, 60.0, 90.0, Color.WHITE, 0.1, 60.0)
	_check(_swings(player).is_empty(), "Malformed range and empty wind bands do not create invalid polygons")
	feedback.play_attack_swing_visual(Vector2.RIGHT, 60.0, 90.0, Color.WHITE, 0.025)
	var swing := _swings(player).back() as Polygon2D
	_check(swing.global_position == feedback.global_position, "A legacy caller safely captures the current finite origin")
	await create_timer(0.05).timeout
	await process_frame
	_check(not is_instance_valid(swing), "Completed swing visuals free after their visible lifetime")
	feedback.play_attack_swing_visual(Vector2.RIGHT, 60.0, 90.0)
	var live_effect: WeakRef = weakref(_swings(player).back())
	_free_world()
	_check(live_effect.get_ref() == null, "World-space swings remain owned by the player scene for transition cleanup")

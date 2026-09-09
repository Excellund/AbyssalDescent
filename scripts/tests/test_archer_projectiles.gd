extends "res://scripts/tests/test_live_arena_edges.gd"
const ARCHER := preload("res://scripts/enemy_archer.gd")
var shooter: ARCHER

func _spawn_archer() -> void:
	_setup()
	actor.global_position = Vector2.ZERO
	shooter = ARCHER.new()
	_circle(shooter, 12.0)
	room.add_child(shooter)
	shooter.set_physics_process(false)
	shooter.global_position = Vector2(-250.0, 0.0)
	shooter.target = actor
	shooter.target_candidates = [actor]
	shooter.arena_size = room.current_effective_room_size

func _shot(position: Vector2, direction: Vector2 = Vector2.RIGHT) -> Node2D:
	shooter.arrow_direction = direction
	shooter._fire_arrow()
	var bullet: Node2D = shooter.projectiles.back()
	bullet.global_position = position
	return bullet

func _cover(position: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(4.0, 80.0)
	collision.shape = shape
	body.add_child(collision)
	room.add_child(body)
	body.global_position = position
	return body

func _settle() -> void:
	await physics_frame
	await process_frame

func _finish_case() -> void:
	_clear()
	await process_frame

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	await _test_all_bearings()
	await _test_target_sweep()
	await _test_geometry_order()
	await _test_target_resets()
	await _test_launch_interruption()
	await _test_bounds_and_range()
	await _test_cleanup()
	await _test_replication()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Archer projectiles: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_all_bearings() -> void:
	for tier in range(4):
		for iron_volley in [false,true]:
			for covered in [false,true]:
				_spawn_archer()
				room.difficulty_provider = preload("res://scripts/core/difficulty_scaling_provider.gd").new(room)
				room._apply_difficulty_tier_bonuses(tier,false)
				var builder := preload("res://scripts/encounter_profile_builder.gd").new()
				room.add_child(builder)
				builder.set_difficulty_tier(tier)
				var spawner := preload("res://scripts/enemy_spawner.gd").new()
				room.add_child(spawner)
				spawner.scripts = {"archer":ARCHER}
				if iron_volley:
					for mutator in builder.get_hard_enemy_mutator_pool():
						if mutator.get("name") == "Iron Volley":
							spawner.current_room_enemy_mutator = builder._scale_mutator_damage(mutator)
				spawner._apply_enemy_mutator(shooter,ARCHER)
				var expected_raw: int = [18,19,19,20][tier] if iron_volley else 14
				var expected_damage: int = [15,18,19,20][tier] if iron_volley else [11,13,14,14][tier]
				_check(shooter.projectile_damage == expected_raw and shooter.projectile_speed == 280.0, "Bearing%d actual spawner resolves original Archer damage/speed (Iron Volley=%s)" % [tier,iron_volley])
				actor.global_position = Vector2(0.0,-85.0)
				actor.apply_trial_power("blast_drive")
				actor.aim = Vector2.UP
				actor.arcana_motion.tick(0.02)
				if covered:
					_cover(Vector2(-16.0,0.0))
				await _settle()
				_shot(Vector2(-28.0,0.0))
				actor.arcana_motion.release_blast(1.0)
				actor.arcana_motion.process_movement(0.2,Vector2.ZERO)
				shooter._process_projectiles(0.2)
				_check(actor.get_current_health() == 100 - (0 if covered else expected_damage) and shooter.projectiles.is_empty(), "Bearing%d fast crossing accepts resolved damage and nearer cover protects (Iron Volley=%s, covered=%s)" % [tier,iron_volley,covered])
				if not (builder.multiplayer_difficulty_config is RefCounted):
					builder.multiplayer_difficulty_config.free()
				await _finish_case()

func _test_target_sweep() -> void:
	for hitch in [false,true]:
		_spawn_archer()
		await _settle()
		_shot(Vector2(-70.0,0.0))
		if hitch:
			shooter._process_projectiles(0.4)
		else:
			for step in range(24):
				shooter._process_projectiles(1.0/60.0)
		_check(actor.get_current_health() == 86 and shooter.projectiles.is_empty(), "Normal steps and a hitch hit the same current target once for original14damage")
		await _finish_case()
	_spawn_archer()
	actor.global_position = Vector2(0.0,-85.0)
	actor.apply_trial_power("blast_drive")
	actor.aim = Vector2.UP
	actor.arcana_motion.tick(0.02)
	await _settle()
	_shot(Vector2(-28.0,0.0))
	actor.arcana_motion.release_blast(1.0)
	actor.arcana_motion.process_movement(0.2,Vector2.ZERO)
	shooter._process_projectiles(0.2)
	_check(actor.global_position.y > 80.0 and actor.get_current_health() == 86 and shooter.projectiles.is_empty(), "Real170px recoil and arrow cross at the same time and register once")
	_check(is_inf(shooter._target_contact_fraction(Vector2(50.0,0.0),Vector2(0.0,150.0))), "Parallel safe motion cannot become a false historical collision")
	_check(is_inf(shooter._target_contact_fraction(Vector2(-80.0,28.0),Vector2(160.0,0.0))), "Exact tangency preserves strict28px accepted radius")
	_check(is_inf(shooter._target_contact_fraction(Vector2(-56.0,0.0),Vector2(28.0,0.0))), "Only reaching the strict radius at the final instant cannot hit")
	_check(shooter._target_contact_fraction(Vector2(-28.0,0.0),Vector2(1.0,0.0)) == 0.0, "Starting at the boundary and moving inward still crosses inside")
	_check(shooter._target_contact_fraction(Vector2(-80.0,27.9),Vector2(160.0,0.0)) < 1.0, "A real near-tangent crossing inside28px is still detected")
	await _finish_case()
	_spawn_archer()
	actor.global_position = Vector2(0.0,20.0)
	actor._dash_damage_immune_left = 1.0
	await _settle()
	_shot(Vector2(-40.0,0.0))
	shooter._process_projectiles(0.1)
	_check(actor.get_current_health() == 86, "Existing enemy_ability category still threatens normal dash immunity")
	await _finish_case()

func _test_geometry_order() -> void:
	for target_before_cover in [false,true]:
		_spawn_archer()
		actor.global_position = Vector2(-50.0 if target_before_cover else 80.0,0.0)
		_cover(Vector2.ZERO)
		_enemy(Vector2(-75.0,0.0))
		await _settle()
		var bullet := _shot(Vector2(-120.0,0.0))
		shooter._process_projectiles(1.0)
		_check(shooter.projectiles.is_empty(), "Shot stops in one frame even with an ignored enemy before thin cover")
		_check(actor.get_current_health() == (86 if target_before_cover else 100), "Earliest target or terrain contact wins without shooting through cover")
		_check(bullet.global_position.x < 0.0, "Consumed projectile remains at its true clipped contact, not beyond cover")
		await _finish_case()
	_spawn_archer()
	actor.global_position = Vector2(120.0,0.0)
	var ally := Actor.new()
	_circle(ally,14.0)
	room.add_child(ally)
	ally.set_physics_process(false)
	ally.global_position = Vector2.ZERO
	await _settle()
	_shot(Vector2(-70.0,0.0))
	shooter._process_projectiles(0.8)
	_check(shooter.projectiles.is_empty() and actor.get_current_health() == 100 and ally.get_current_health() == 100, "Non-target body still consumes the projectile without damage")
	ally.upgrade_system.power_registry.free()
	await _finish_case()

func _test_target_resets() -> void:
	_spawn_archer()
	actor.global_position = Vector2(0.0,-80.0)
	await _settle()
	_shot(Vector2(-20.0,0.0))
	preload("res://scripts/core/player_flow_coordinator.gd").new().reset_player_position(actor,Vector2(0.0,80.0))
	shooter._process_projectiles(0.1)
	_check(actor.get_current_health() == 100 and shooter.projectiles.size() == 1, "Explicit position reset never draws a false crossing through the beam")
	actor.global_position.y = -80.0
	shooter._process_projectiles(0.1)
	_check(actor.get_current_health() == 86, "Normal subsequent movement retains its true projectile crossing")
	await _finish_case()
	_spawn_archer()
	actor.global_position = Vector2(0.0,-80.0)
	var ally := Actor.new()
	_circle(ally,14.0)
	room.add_child(ally)
	ally.set_physics_process(false)
	ally.global_position = Vector2(0.0,80.0)
	await _settle()
	_shot(Vector2(-20.0,0.0))
	shooter._set_target_node(ally)
	shooter._process_projectiles(0.1)
	_check(ally.get_current_health() == 100 and actor.get_current_health() == 100, "AI target switch never joins two players' unrelated histories")
	ally.set_combat_removed(true)
	shooter._process_projectiles(0.1)
	_check(ally.get_current_health() == 100, "Removed player cannot receive damage from a retained AI target")
	ally.upgrade_system.power_registry.free()
	await _finish_case()

func _test_launch_interruption() -> void:
	_spawn_archer()
	actor.global_position = Vector2(0.0,-70.0)
	await _settle()
	var bullet := _shot(Vector2.ZERO)
	actor.ruinous_impact_stacks = 1
	actor.boss_combinations.launch_enemy(shooter,Vector2.UP * 300.0,1)
	var frozen_packet := shooter.get_projectile_network_sync_state()
	_check(frozen_packet.p[0][1][1] == Vector2.ZERO, "Active Ruinous launch immediately reports the existing arrow freeze")
	var replica := ARCHER.new()
	room.add_child(replica)
	replica.set_physics_process(false)
	replica.set_network_simulation_enabled(false)
	replica.apply_projectile_network_sync_state(frozen_packet)
	replica._process_network_visuals(0.1)
	_check(replica.projectiles[0].global_position == Vector2.ZERO, "Replica frozen arrow remains at the exact host position")
	actor.apply_trial_power("blast_drive")
	actor.aim = Vector2.UP
	actor.arcana_motion.tick(0.02)
	actor.arcana_motion.release_blast(1.0)
	for index in range(4):
		await _settle()
		actor.arcana_motion.process_movement(0.1,Vector2.ZERO)
		shooter._physics_process(0.1)
	_check(actor.get_current_health() == 100 and bullet.global_position == Vector2.ZERO and not shooter.get_launch_state().active, "Actual recoil crosses a frozen arrow during launch without changing the existing freeze contract")
	_check(shooter.get_projectile_network_sync_state().p[0][1][1] == Vector2.ZERO, "Final skipped launch step remains visually frozen until host processing resumes")
	shooter._physics_process(1.0/60.0)
	_check(actor.get_current_health() == 100 and shooter.projectiles.size() == 1, "First resumed frame cannot damage a player from movement during the arrow freeze")
	var resumed_packet := shooter.get_projectile_network_sync_state()
	_check(resumed_packet.p[0][1][1] == Vector2.RIGHT * 280.0, "Normal arrow velocity resumes with the first actual host step")
	var state: Dictionary = shooter._projectile_states.values()[0]
	_check(state.target_position == actor.global_position and state.source_position.distance_to(shooter.global_position) < 3.0, "Resumption samples post-launch actor positions for both target and moving-source range")
	actor.global_position.y = -70.0
	shooter._process_projectiles(0.1)
	_check(actor.get_current_health() == 86 and shooter.projectiles.is_empty(), "A genuine new crossing after resumption still hits once")
	await _finish_case()
func _test_bounds_and_range() -> void:
	for side: Vector2 in SIDES:
		_spawn_archer()
		actor.global_position = Vector2(-200.0,200.0)
		room.current_effective_room_size = Vector2(600.0,600.0)
		await _settle()
		var bullet := _shot(side * 290.0,side)
		shooter._process_projectiles(0.2)
		_check(shooter.projectiles.is_empty() and bullet.global_position.is_equal_approx(side * 300.0), "Every live room side clips the shot at the visible boundary")
		await _finish_case()
	_spawn_archer()
	actor.global_position = Vector2(0.0,-80.0)
	await _settle()
	_shot(Vector2(-20.0,0.0))
	room.current_effective_room_size = Vector2(600.0,600.0)
	actor.global_position.y = 80.0
	shooter._process_projectiles(0.1)
	_check(actor.get_current_health() == 100, "Arena correction resets motion samples instead of inventing a shrink crossing")
	var outside := _shot(Vector2(400.0,0.0))
	shooter._process_projectiles(0.1)
	_check(not shooter.projectiles.has(outside) and outside.global_position.x == 400.0, "Outside-start shot cancels after shrink without an invented traveled segment")
	await _finish_case()
	for source_moves in [false,true]:
		_spawn_archer()
		room.current_effective_room_size = Vector2(4000.0,4000.0)
		actor.global_position = Vector2(0.0,500.0)
		shooter.global_position = Vector2.ZERO
		await _settle()
		var bullet := _shot(Vector2(1190.0,0.0))
		if source_moves:
			shooter.global_position.x = 100.0
		shooter._process_projectiles(0.1)
		_check(shooter.projectiles.has(bullet) == source_moves, "Original1200px range retains moving-source semantics")
		_check(is_equal_approx(bullet.global_position.x,1218.0 if source_moves else 1200.0), "Final range crossing is clipped exactly without a new lifetime rule")
		await _finish_case()

func _test_cleanup() -> void:
	for immediate_free in [false,true]:
		_spawn_archer()
		actor.global_position = Vector2(0.0,100.0)
		await _settle()
		var bullet := _shot(Vector2.ZERO)
		if immediate_free:
			bullet.free()
		else:
			bullet.queue_free()
		shooter._process_projectiles(0.1)
		_check(shooter.projectiles.is_empty() and shooter._projectile_states.is_empty() and shooter.projectile_directions.is_empty() and shooter._projectile_network_ids.is_empty(), "Queued/freed arrow clears numeric bookkeeping without accessing a freed node")
		await _finish_case()
	_spawn_archer()
	var bullet := _shot(Vector2.ZERO)
	shooter.free()
	_check(bullet.is_queued_for_deletion(), "Owner removal clears sibling projectile nodes")
	await _finish_case()

func _test_replication() -> void:
	_spawn_archer()
	actor.global_position = Vector2(0.0,100.0)
	_shot(Vector2(200.0,0.0))
	var packet := shooter.get_projectile_network_sync_state()
	var replica := ARCHER.new()
	room.add_child(replica)
	replica.set_physics_process(false)
	replica.set_network_simulation_enabled(false)
	replica.apply_projectile_network_sync_state(packet)
	_check(replica.projectiles.size() == 1 and replica.projectiles[0].global_position == Vector2(200.0,0.0), "Native world-space projectile packet reconstructs the exact host location")
	shooter._clear_all_projectiles()
	var final_packet := shooter.get_projectile_network_sync_state()
	for tick in range(60):
		replica._physics_process(1.0/60.0)
	_check(replica.projectiles.is_empty() and shooter.get_projectile_network_sync_state().is_empty(), "Lost final packet expires rather than leaving an immortal ghost")
	replica.apply_projectile_network_sync_state(packet)
	_check(replica.projectiles.is_empty(), "Equal packet cannot revive an expired projectile")
	var idle_generation: int = replica._projectile_generation
	replica._process_network_visuals(1.0)
	_check(replica._projectile_generation == idle_generation, "Idle replica does not repeatedly clear and redraw an already empty projectile set")
	replica.apply_projectile_network_sync_state(final_packet)
	replica.apply_projectile_network_sync_state(packet)
	_check(replica.projectiles.is_empty(), "Old active packet cannot overwrite a newer authoritative clear")
	_shot(Vector2(100.0,0.0))
	var fresh := shooter.get_projectile_network_sync_state()
	var malformed := fresh.duplicate(true)
	malformed.q += 1000
	malformed.p[0][1][0] = Vector2(INF,0.0)
	replica.apply_projectile_network_sync_state(malformed)
	replica.apply_projectile_network_sync_state(fresh)
	_check(replica.projectiles.size() == 1, "Malformed high sequence does not poison a following valid snapshot")
	replica._process_projectiles(1.0)
	_check(actor.get_current_health() == 100, "Replica projectile processing cannot author player damage")
	await _finish_case()
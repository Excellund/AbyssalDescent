extends "res://scripts/tests/test_character_passive_runtime.gd"
## The stable threadbinder save ID now delivers one real Attack through a fixed
## effigy. Placement, targeting and recall must not create a secondary Attack.

class ThreadAlly extends ComboPlayer:
	func _is_local_control_owner() -> bool:
		return true

class CursorKeeper extends "res://scripts/player.gd":
	var cursor := Vector2(240.0, 0.0)
	func _is_local_control_owner() -> bool:
		return true
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
	func _get_attack_aim_point() -> Vector2:
		return cursor

class PlacementBounds extends Node:
	var current_effective_room_size := Vector2(1040.0, 760.0)

func _run() -> void:
	await _test_effigy_deployment()
	await _test_effigy_strike_origin()
	await _test_effigy_cursor_aim()
	await _test_effigy_placement_geometry()
	await _test_effigy_real_boss()
	await _test_effigy_persistence_and_recall()
	await _test_effigy_attack_allowances()
	await _test_effigy_execution_boundary()
	await _test_effigy_target_conditions()
	await _test_effigy_blast()
	await _test_effigy_motion_preservation()
	await _test_effigy_restore()
	await _test_effigy_ownership()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	print("[EffigyKeeperRuntime] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _effigy_attack(direction: Vector2 = Vector2.RIGHT, owner_player: ComboPlayer = null) -> void:
	if owner_player == null:
		owner_player = player
	owner_player.attack_cooldown_left = 0.0
	owner_player.attack_lock_time_left = 0.0
	owner_player.aim = direction
	owner_player._try_execute_attack(direction)

func _test_effigy_deployment() -> void:
	_character("threadbinder")
	await _settle()
	_check(player.active_character_id == "threadbinder" and player.passive_effigy_command and not player.passive_cross_stitch, "The stable fifth-character ID enables Effigy Command and retires active Cross Stitch")
	_check(not player.effigy_deployed and player.get_attack_origin() == player.global_position, "An undeployed Keeper attacks from the body")
	var signals: Array[int] = []
	player.primary_attack_fired.connect(func(): signals.append(player.attack_combo_counter))
	_effigy_attack()
	_check(player.effigy_deployed and player.effigy_position.is_equal_approx(Vector2(180.0, 0.0)), "The first deliberate Attack plants the effigy 180px ahead even when it misses")
	_check(player.attack_combo_counter == 1 and signals.size() == 1, "Deployment consumes exactly one Attack input and ordinary cooldown")
	var placed := player.effigy_position
	player._try_execute_attack(Vector2.LEFT)
	_check(player.effigy_position == placed and player.attack_combo_counter == 1 and signals.size() == 1, "A cooldown-rejected press neither relocates the effigy nor creates an Attack")
	_free_world()

func _test_effigy_strike_origin() -> void:
	_character("threadbinder")
	var body_foe := _target(Vector2(40.0, 0.0))
	var effigy_foe := _target(Vector2(220.0, 0.0))
	await _settle()
	_effigy_attack()
	_check(_source_hits(body_foe, "melee").size() == 1 and effigy_foe.hits.is_empty(), "Deployment's single real strike remains at the body instead of also striking at the new effigy")
	if not body_foe.contexts.is_empty():
		_check(Vector2(body_foe.contexts[0].attack_origin) == Vector2.ZERO, "Deployment damage records the true body origin")
	_check(player.get_attack_origin() == player.effigy_position, "Subsequent attacks use the committed effigy origin")
	_effigy_attack()
	_check(_source_hits(body_foe, "melee").size() == 1 and _source_hits(effigy_foe, "melee").size() == 1, "The following Attack hits only at the effigy, without a second body strike")
	if not effigy_foe.contexts.is_empty():
		_check(Vector2(effigy_foe.contexts[0].attack_origin) == player.effigy_position and not bool(effigy_foe.contexts[0].get("secondary", false)), "Effigy damage is the original Attack at its actual anchor, not a secondary proc")
	_check(_source_hits(body_foe, "cross_stitch_burst").is_empty() and _source_hits(effigy_foe, "cross_stitch_burst").is_empty(), "Alternating foes no longer creates Cross Stitch Bursts")
	_check(DAMAGEABLE.status_snapshot(body_foe, 1).mark_ratio == 0.0 and DAMAGEABLE.status_snapshot(effigy_foe, 1).mark_ratio == 0.0, "Effigy placement and attacks do not retain the retired automatic Mark mechanic")
	_free_world()

func _test_effigy_persistence_and_recall() -> void:
	_character("threadbinder")
	_effigy_attack()
	var anchor := player.effigy_position
	player.position = Vector2(-160.0, 130.0)
	player._update_ground_movement(Vector2.LEFT, 0.4)
	_check(player.effigy_deployed and player.effigy_position == anchor and player.get_attack_origin() == anchor, "Ordinary walking neither follows, expires nor recalls the fixed effigy")
	var lethal := _target(anchor + Vector2(40.0, 0.0))
	lethal.health_state.current_health = 1
	await _settle()
	_effigy_attack()
	_check(lethal.get_current_health() == 0 and player.effigy_deployed and player.effigy_position == anchor, "Killing an attacked foe leaves the battlefield anchor in place")
	lethal.free()
	_check(player.effigy_deployed and player.effigy_position == anchor, "Freeing the last foe cannot leave the effigy dependent on an enemy reference")
	player.attack_lock_time_left = 0.0
	player.dash_cooldown_left = 1.0
	Input.action_press("dash")
	player._try_start_dash(Vector2.DOWN)
	Input.action_release("dash")
	_check(player.effigy_deployed, "A rejected Dash press does not recall the effigy")
	player.dash_cooldown_left = 0.0
	Input.action_press("dash")
	player._try_start_dash(Vector2.DOWN)
	Input.action_release("dash")
	_check(player._is_dash_active() and not player.effigy_deployed and player.get_attack_origin() == player.global_position, "A successful normal Dash recalls immediately and restores body-origin attacks")
	player._process_active_dash(1.0)
	_effigy_attack(Vector2.LEFT)
	_check(player.effigy_deployed and player.effigy_position.is_equal_approx(player.global_position + Vector2.LEFT * 180.0), "The next Attack after recall plants a fresh anchor from the new body position")
	_free_world()

func _test_effigy_cursor_aim() -> void:
	_character("bastion")
	var keeper := CursorKeeper.new()
	_add_circle(keeper, 14.0)
	world.add_child(keeper)
	keeper.player_id = 2
	keeper.apply_character_package(keeper.CHARACTER_REGISTRY.get_character("threadbinder"))
	keeper.arcana_motion.set_process(false)
	keeper.boss_combinations.set_process(false)
	keeper._try_execute_attack(keeper._get_mouse_attack_direction())
	keeper.position = Vector2(0.0, 170.0)
	keeper.cursor = Vector2(220.0, 0.0)
	var aimed_foe := _target(keeper.cursor)
	await _settle()
	_check(keeper._get_mouse_attack_direction().is_equal_approx(Vector2.RIGHT), "Production mouse aiming uses cursor minus fixed effigy, not the perpendicularly displaced body")
	keeper.attack_cooldown_left = 0.0
	keeper.attack_lock_time_left = 0.0
	keeper._try_execute_attack(keeper._get_mouse_attack_direction())
	_check(_source_hits(aimed_foe, "melee").size() == 1 and keeper.position == Vector2(0.0, 170.0), "The cursor-aligned effigy Attack connects while its Keeper stays at the walking position")
	if is_instance_valid(keeper.upgrade_system.power_registry):
		keeper.upgrade_system.power_registry.free()
	keeper.free()
	_free_world()

func _test_effigy_attack_allowances() -> void:
	_character("threadbinder")
	_effigy_attack()
	player.apply_trial_power("razor_wind")
	player.reward_storm_crown = true
	player.storm_crown_proc_every = 999
	var first := _target(player.effigy_position + Vector2(35.0, 0.0))
	var second := _target(player.effigy_position + Vector2(45.0, 15.0))
	var wind := _target(player.effigy_position + Vector2(130.0, 0.0))
	var body_only := _target(Vector2(35.0, 0.0))
	await _settle()
	var before := player.attack_combo_counter
	_effigy_attack()
	_check(player.attack_combo_counter == before + 1, "An effigy cleave plus Razor Wind increments Attack count once")
	_check(_source_hits(first, "melee").size() == 1 and _source_hits(second, "melee").size() == 1 and _source_hits(wind, "razor_wind").size() == 1, "The original melee cleave and outer Razor Wind band both originate at the effigy")
	_check(body_only.hits.is_empty(), "The Keeper body cannot duplicate melee or Razor Wind while the effigy is deployed")
	_check(player.storm_crown_hit_counter == 3, "Cleave and wind contacts keep exactly one Crown contribution per victim per original Attack")
	if first.contexts.size() > 0 and wind.contexts.size() > 0:
		_check(int(first.contexts[0].interaction.seq) == int(wind.contexts[0].interaction.seq), "Melee and Razor Wind retain the same original action identity")
		_check(Vector2(wind.contexts[0].attack_origin) == player.effigy_position, "Extended damage records the same effigy anchor as melee")
	var blocked := BlockedPassiveEnemy.new()
	_add_circle(blocked, 13.0)
	world.add_child(blocked)
	blocked.position = player.effigy_position + Vector2(-35.0, 0.0)
	await _settle()
	var anchor := player.effigy_position
	_effigy_attack(Vector2.LEFT)
	_check(blocked.hits.is_empty() and player.effigy_position == anchor and player.effigy_deployed, "Rejected damage preserves the anchor without inventing passive damage or a target switch")
	_free_world()

func _test_effigy_target_conditions() -> void:
	_character("threadbinder")
	_effigy_attack()
	player.first_strike_bonus_damage = 16
	player.severing_edge_bonus_damage = 14
	var healthy := _target(player.effigy_position + Vector2(35.0, 15.0))
	var wounded := _target(player.effigy_position + Vector2(40.0, -15.0))
	wounded.health_state.current_health = 4500
	await _settle()
	_effigy_attack()
	_check(healthy.hits.size() == 1 and healthy.hits[0].amount == 36, "A healthy effigy target resolves ordinary First Strike exactly once")
	_check(wounded.hits.size() == 1 and wounded.hits[0].amount == 34, "A wounded effigy target resolves its own Severing Edge without borrowed target conditions")
	if not healthy.contexts.is_empty() and not wounded.contexts.is_empty():
		_check(is_equal_approx(float(healthy.contexts[0].damage_coefficient), 1.0) and is_equal_approx(float(wounded.contexts[0].damage_coefficient), 1.0), "Effigy delivery introduces no hidden Damage multiplier")
	_free_world()

func _test_effigy_execution_boundary() -> void:
	_character("threadbinder")
	player.apply_trial_power("execution_edge")
	player.execution_every = 3
	_check(player.reward_execution_edge, "The Execution boundary uses the learned Arcana package")
	var foe := _target(Vector2(220.0, 0.0))
	await _settle()
	_effigy_attack()
	_check(player.attack_combo_counter == 1 and foe.hits.is_empty(), "Missed deployment still advances the real Execution phase once")
	_effigy_attack()
	_check(player.attack_combo_counter == 2 and foe.hits.size() == 1 and foe.hits[0].amount == 20, "The second real Attack at the effigy stays below the Execution boundary")
	_effigy_attack()
	var empowered := int(round(20.0 * player.execution_damage_mult))
	_check(player.attack_combo_counter == 3 and foe.hits.size() == 2 and foe.hits[1].amount == empowered, "The third real Attack crosses Execution exactly once without an extra effigy count")
	var state: Dictionary = player.get_effigy_network_state()
	_check(int(state.get("attacks", -1)) == 3, "Effigy synchronization carries the phase produced by the three real Attacks")
	_effigy_attack()
	_check(player.attack_combo_counter == 4 and foe.hits.size() == 3 and foe.hits[2].amount == 20, "The next real Attack leaves the proc boundary rather than replaying it")
	_free_world()

func _test_effigy_blast() -> void:
	_character("threadbinder")
	player.apply_trial_power("blast_drive")
	_effigy_attack()
	var anchor := player.effigy_position
	var at_effigy := _target(anchor + Vector2(40.0, 0.0))
	var at_body := _target(Vector2(40.0, 0.0))
	await _settle()
	player.perform_motion_blast(Vector2.RIGHT, 1.0)
	_check(player.effigy_deployed and player.effigy_position == anchor, "A charged Blast preserves the deployed anchor")
	_check(_source_hits(at_effigy, "blast_drive").size() == 1 and _source_hits(at_body, "blast_drive").is_empty(), "Charged Blast keeps its original single strike from the current attack origin")
	if not at_effigy.contexts.is_empty():
		_check(is_equal_approx(float(at_effigy.contexts[0].damage_coefficient), player.ARCANA_MOTION_SCRIPT.BLAST_DAMAGE_MULT_MAX * player.blast_drive_damage_scale), "Charged Blast retains its existing damage coefficient")
	_check(player.attack_combo_counter == 2, "Deployment Attack and deliberate charged Blast count once each")
	_free_world()

func _test_effigy_restore() -> void:
	_character("threadbinder")
	_effigy_attack()
	player.apply_trial_power("static_wake")
	var snapshot := player.build_run_snapshot()
	player.apply_run_snapshot(snapshot)
	_check(player.active_character_id == "threadbinder" and player.passive_effigy_command and player.reward_static_wake, "Run restore retains the stable character ID and learned shared powers")
	_check(not player.effigy_deployed and player.get_attack_origin() == player.global_position, "Run restore discards the previous room's temporary effigy")
	_effigy_attack()
	player.apply_character_package(player.CHARACTER_REGISTRY.get_character("bastion"))
	_check(not player.passive_effigy_command and not player.effigy_deployed, "Changing character removes the temporary effigy and its active command")
	_free_world()

func _test_effigy_placement_geometry() -> void:
	for obstacle_kind in ["wall", "cover", "overlap"]:
		_character("threadbinder")
		var obstacle := StaticBody2D.new()
		if obstacle_kind == "wall":
			var collider := CollisionShape2D.new()
			var rectangle := RectangleShape2D.new()
			rectangle.size = Vector2(16.0, 240.0)
			collider.shape = rectangle
			obstacle.add_child(collider)
			obstacle.position = Vector2(100.0, 0.0)
		else:
			_add_circle(obstacle, 30.0)
			obstacle.position = Vector2(110.0, 0.0) if obstacle_kind == "cover" else Vector2.ZERO
			obstacle.add_to_group("arena_columns")
			obstacle.set_meta("column_radius", 30.0)
		world.add_child(obstacle)
		await _settle()
		_effigy_attack()
		if obstacle_kind == "overlap":
			_check(not player.effigy_deployed and player.attack_combo_counter == 1, "An invalid overlapping placement still performs its single body Attack without planting inside solid cover")
		else:
			var maximum := 80.0 if obstacle_kind == "wall" else 68.0
			_check(player.effigy_deployed and player.effigy_position.x > 0.0 and player.effigy_position.x <= maximum + 0.1 and absf(player.effigy_position.y) < 0.1, "Actual swept placement stops its 12px footprint before solid " + obstacle_kind)
		obstacle.free()
		player._clear_effigy()
		await _settle()
		_effigy_attack()
		_check(player.effigy_deployed and player.effigy_position.is_equal_approx(Vector2(180.0, 0.0)), "Removing actual " + obstacle_kind + " restores the full placement distance")
		_free_world()
	_character("threadbinder")
	var bounds := PlacementBounds.new()
	world.add_child(bounds)
	EnemyReplicationService.bind_world(bounds)
	for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(1.0,1.0).normalized()]:
		player._clear_effigy()
		player.position = direction * Vector2(515.0, 375.0)
		_effigy_attack(direction)
		var allowed := Rect2(Vector2(-508.0,-368.0), Vector2(1016.0,736.0)).grow(0.01)
		_check(player.effigy_deployed and allowed.has_point(player.effigy_position), "Placement respects the live room boundary with the full 12px footprint: " + str(direction))
	EnemyReplicationService.unbind_world(bounds)
	_free_world()
	_character("threadbinder")
	_target(Vector2(100.0, 0.0))
	await _settle()
	_effigy_attack()
	_check(player.effigy_position.is_equal_approx(Vector2(180.0, 0.0)), "A real enemy collider along the placement path does not become solid terrain or shorten the effigy placement")
	_free_world()

func _test_effigy_real_boss() -> void:
	_character("threadbinder")
	var boss := preload("res://scripts/shared/boss_stage_registry.gd").create_boss_node(1, Vector2(220.0, 0.0), "kilnheart")
	world.add_child(boss)
	boss.set_physics_process(false)
	await _settle()
	var full_health: int = boss.get_current_health()
	_effigy_attack()
	_check(player.effigy_deployed and boss.get_current_health() == full_health, "A real Kilnheart outside body reach is not hit by deployment")
	_effigy_attack()
	_check(boss.get_current_health() == full_health - 20, "The fixed effigy's original melee Attack deals normal damage to a real alternative boss")
	player.apply_trial_power("blast_drive")
	var before_blast: int = boss.get_current_health()
	player.perform_motion_blast(Vector2.RIGHT, 1.0)
	var expected_blast := int(round(20.0 * player.ARCANA_MOTION_SCRIPT.BLAST_DAMAGE_MULT_MAX * player.blast_drive_damage_scale))
	_check(boss.get_current_health() == before_blast - expected_blast and player.effigy_deployed, "A real alternative boss accepts the effigy Blast once at its existing charged damage amount")
	_free_world()

func _test_effigy_motion_preservation() -> void:
	_character("threadbinder")
	player.apply_trial_power("blast_drive")
	_effigy_attack()
	var anchor := player.effigy_position
	player.arcana_motion.tick(0.02)
	player.arcana_motion.release_blast(1.0)
	_check(player.arcana_motion.motion == player.ARCANA_MOTION_SCRIPT.Motion.RECOIL, "The ordinary charged Blast still enters Recoil")
	player.arcana_motion.process_movement(0.2, Vector2.ZERO)
	_check(player.global_position.x < -40.0 and player.effigy_deployed and player.effigy_position == anchor, "Actual Recoil moves the Keeper body while preserving its fixed effigy")
	_free_world()
	_character("threadbinder")
	player.apply_trial_power("razor_orbit")
	_effigy_attack()
	anchor = player.effigy_position
	var orbit_target := _target(Vector2(100.0, 0.0))
	await _settle()
	player.arcana_motion.start_orbit(orbit_target)
	_check(player.arcana_motion.motion == player.ARCANA_MOTION_SCRIPT.Motion.ORBIT, "The ordinary Orbit controller accepts its real enemy anchor")
	player.arcana_motion.process_movement(0.15, Vector2.ZERO)
	_check(player.global_position.distance_to(Vector2.ZERO) > 10.0 and player.effigy_deployed and player.effigy_position == anchor, "Actual Orbit movement preserves the effigy and does not act as another normal Dash")
	_free_world()

func _test_effigy_ownership() -> void:
	_character("threadbinder")
	var teammate := ThreadAlly.new()
	_add_circle(teammate, 14.0)
	world.add_child(teammate)
	teammate.player_id = 2
	teammate.position = Vector2(0.0, 180.0)
	teammate.apply_character_package(teammate.CHARACTER_REGISTRY.get_character("threadbinder"))
	teammate.arcana_motion.set_process(false)
	teammate.boss_combinations.set_process(false)
	_effigy_attack(Vector2.RIGHT)
	_effigy_attack(Vector2.LEFT, teammate)
	var teammate_anchor := teammate.effigy_position
	_check(player.effigy_deployed and teammate.effigy_deployed and player.effigy_position != teammate_anchor, "Two Keepers retain independent fixed effigies")
	player.set_alive(false)
	_check(not player.effigy_deployed and teammate.effigy_deployed and teammate.effigy_position == teammate_anchor, "One owner's death removes only that owner's effigy")
	if is_instance_valid(teammate.upgrade_system.power_registry):
		teammate.upgrade_system.power_registry.free()
	teammate.free()
	_free_world()

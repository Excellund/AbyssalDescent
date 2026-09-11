extends "res://scripts/tests/test_pulse_hud.gd"
## Mechanical guards for body-art changes; native captures verify the pixels.

const VISUAL_DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const VISUAL_ENEMY_STATES := preload("res://scripts/shared/enemy_state_enums.gd")
const VISUAL_WARDEN := preload("res://scripts/enemy_boss.gd")
const VISUAL_ROLES := ["chaser", "archer", "charger", "shielder", "weaver", "drifter", "sentinel", "pyre"]
var visual_enemies: Dictionary = {}

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Enemy visual profile tests require disposable user data")
		quit(1)
		return
	_prepare_pulse_world()
	world.enemy_spawner.configure_room(world.current_effective_room_size, 90.0, 170.0, {})
	var report: Array[Dictionary] = world.enemy_spawner._spawn_types_immediate(VISUAL_ROLES, true)
	for entry: Dictionary in report:
		visual_enemies[entry.enemy_type] = entry.enemy
	# Exercise the unchanged boss through the same actual collision construction.
	visual_enemies["warden"] = world.enemy_spawner._spawn_enemy_in_current_room(VISUAL_WARDEN)
	check(report.size() == VISUAL_ROLES.size() and is_instance_valid(visual_enemies.warden), "The real spawner creates all seven profiled roles, Pyre, and Warden")
	if report.size() == VISUAL_ROLES.size() and is_instance_valid(visual_enemies.warden):
		await _test_collision_and_presentation_state()
		_test_shield_geometry_and_damage()
		_test_native_warning_activity()
	await _release_pulse_world()
	print("[OK] Enemy visual profiles: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _collision_radius(enemy: Node) -> float:
	for child: Node in enemy.get_children():
		if child is CollisionShape2D and child.shape is CircleShape2D:
			return child.shape.radius
	return -1.0

func _test_collision_and_presentation_state() -> void:
	for role: String in visual_enemies:
		var enemy: Node2D = visual_enemies[role]
		enemy.set_physics_process(false)
		var expected_radius := 34.0 if role == "warden" else (15.86 if role == "shielder" else 13.0)
		check(is_equal_approx(_collision_radius(enemy), expected_radius), "Production collision radius is unchanged for " + role)
		check(enemy.is_spawn_transporting(), "Actual spawn still enters its native transport state: " + role)
		enemy._update_spawn_transport(enemy.spawn_transport_duration * 0.5)
		check(enemy.is_spawn_transporting() and is_equal_approx(_collision_radius(enemy), expected_radius), "The entrance retains the role's collision geometry: " + role)
		enemy._update_spawn_transport(enemy.spawn_transport_duration)
		enemy.apply_slow(2.0, 0.5)
		var status: Node = VISUAL_DAMAGEABLE._target_status(enemy, true)
		check(status.apply_mark(1, "eclipse_mark", 0.2, 3.0), "Native target storage accepts a Mark for " + role)
		var mark_before: Dictionary = status.snapshot(1)
		for enemy_count in [1, 48]:
			enemy._visual_lod_enemy_count = enemy_count
			enemy.visual_facing_direction = Vector2.RIGHT.rotated(0.63)
			enemy.queue_redraw()
			await process_frame
			check(enemy.is_slowed() and is_equal_approx(enemy.slow_speed_mult, 0.5) and status.snapshot(1) == mark_before, "Selecting visual detail preserves native Slow and Mark state: %s/%d" % [role, enemy_count])
			check(not enemy.is_spawn_transporting() and is_equal_approx(_collision_radius(enemy), expected_radius), "Detail/facing changes cannot resize collision or restart transport: %s/%d" % [role, enemy_count])
	# The optional profile must retain the four-argument legacy call contract.
	var common_method: Dictionary = {}
	for method: Dictionary in visual_enemies.pyre.get_method_list():
		if String(method.name) == "_draw_common_body":
			common_method = method
			break
	check(common_method.get("args", []).size() == 5 and common_method.get("default_args", []).size() == 1 and String(common_method.default_args[0]).is_empty(), "Unprofiled callers retain the optional empty body profile")

func _same_polygon(left: PackedVector2Array, right: PackedVector2Array) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		if not left[index].is_equal_approx(right[index]):
			return false
	return true

func _test_shield_geometry_and_damage() -> void:
	var shield: Node2D = visual_enemies.shielder
	shield.global_position = Vector2.ZERO
	shield.shield_facing = Vector2.RIGHT
	var radius := _collision_radius(shield)
	var original: PackedVector2Array = shield._get_shield_points(radius)
	check(original.size() == 5, "The directional Shield remains its existing five-vertex polygon")
	shield.set_max_health_and_current(10000)
	for enemy_count in [1, 48]:
		shield._visual_lod_enemy_count = enemy_count
		for angle in [0.0, 0.71, 2.8]:
			shield.shield_facing = Vector2.RIGHT.rotated(angle)
			var actual: PackedVector2Array = shield._get_shield_points(radius)
			var rotated := PackedVector2Array()
			for point: Vector2 in original:
				rotated.append(point.rotated(angle))
			check(_same_polygon(actual, rotated), "Native Shield geometry rotates without resizing under status/LOD: %d/%.2f" % [enemy_count, angle])
			for side in [1.0, -1.0]:
				var before: int = shield.get_current_health()
				var origin: Vector2 = shield.global_position + shield.shield_facing * 100.0 * side
				shield.take_damage(100, {"attack_origin": origin})
				var applied: int = before - shield.get_current_health()
				check(applied > 0 and applied < 100 if side > 0.0 else applied == 100, "The actual Shield still mitigates front hits and admits rear hits: %d/%.2f/%.0f" % [enemy_count, angle, side])
	shield.shield_facing = Vector2.RIGHT
	check(_same_polygon(shield._get_shield_points(radius), original), "Returning the facing restores exactly the original Shield polygon")
	# The shield art and body silhouette must not redefine the circular slam.
	check(is_equal_approx(shield.slam_radius, 92.0), "The slam retains its existing 92-pixel damage and warning radius")
	shield.target = world.player
	world.player.set_max_health_and_current(1000)
	for distance in [91.9, 92.1]:
		world.player.global_position = shield.global_position + Vector2(distance, 0.0)
		shield.slam_hit_applied = false
		var before: int = world.player.get_current_health()
		shield._try_apply_slam_aoe_hit()
		check((world.player.get_current_health() < before) == (distance < 92.0), "Actual slam damage agrees with the unchanged circular boundary at %.1f pixels" % distance)

func _test_native_warning_activity() -> void:
	for role: String in ["charger", "archer", "shielder"]:
		var enemy: Node2D = visual_enemies[role]
		enemy.global_position = Vector2.ZERO
		enemy.target = world.player
		world.player.global_position = Vector2(120.0, 0.0)
		enemy._visual_lod_enemy_count = 48
		if role == "shielder":
			enemy._try_start_slam()
			check(enemy.slam_state == VISUAL_ENEMY_STATES.ShielderSlamState.WINDUP and enemy.slam_state_time_left > 0.0, "The Shielder still enters its native slam warning in a crowded room")
		else:
			enemy._enter_windup_state()
			if role == "charger":
				check(enemy.charger_state == VISUAL_ENEMY_STATES.ChargerState.WINDUP and enemy.charger_charge_preview_length > 0.0, "The Charger still creates its native directional charge warning")
			else:
				check(enemy.archer_state == VISUAL_ENEMY_STATES.ArcherState.WINDUP and enemy.archer_state_time_left > 0.0, "The Archer still creates its native aimed windup")
		check(enemy.should_force_network_runtime_state_sampling(), "An active warning retains authoritative sampling under crowded-room LOD: " + role)
		if role != "archer":
			enemy.set_network_simulation_enabled(false)
			check(enemy.should_process_remote_visuals_every_frame(), "A remote active warning keeps its per-frame presentation: " + role)
			enemy.set_network_simulation_enabled(true)

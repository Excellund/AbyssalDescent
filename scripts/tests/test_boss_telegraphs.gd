extends SceneTree
## Real Lacuna damage and network state, checked against its rendered geometry.

class Probe extends Node2D:
	var health := 1000
	func get_current_health() -> int:
		return health
	func take_damage(amount: int, _context: Dictionary = {}) -> void:
		health -= amount

class Lacuna extends "res://scripts/enemy_boss_3.gd":
	func _ready() -> void:
		max_health = boss_max_health
		_create_health_state()
		set_physics_process(false)
		_ensure_seam_overlay()
		_ensure_attack_overlay()

var world: Node2D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, detail: String) -> void:
	checks += 1
	if not value:
		failures.append(detail)
		push_error(detail)

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	if not OS.get_user_data_dir().begins_with(project_path) or not DirAccess.dir_exists_absolute("res://validation_fixtures"):
		push_error("Boss telegraphs require an isolated validation project")
		quit(1)
		return
	world = Node2D.new()
	world.position = Vector2(76.0, -28.0)
	root.add_child(world)
	current_scene = world
	await _test_cross_geometry()
	await _test_seam_lifecycle()
	world.free()
	await process_frame
	print("[OK] Boss telegraphs: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _boss(remote: bool = false) -> Lacuna:
	var boss := Lacuna.new()
	world.add_child(boss)
	boss.set_network_simulation_enabled(not remote)
	boss.set_physics_process(false)
	boss.global_position = Vector2(81.0, -63.0) if not remote else Vector2(-370.0, 140.0)
	boss.boss_state = boss.STATE_WINDUP
	boss.active_attack = boss.ATTACK_ECHO_CROSS
	boss.telegraph_alpha = 1.0
	return boss

func _warning_contains(boss: Lacuna, point: Vector2) -> bool:
	var overlay := boss._attack_overlay
	if not overlay.has_method("get_echo_cross_polygons"):
		return false
	var polygons: Array = overlay.call("get_echo_cross_polygons")
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(overlay.to_local(point), polygon):
			return true
	return false

func _test_cross_geometry() -> void:
	var probe := Probe.new()
	world.add_child(probe)
	# Side bands, rounded ends, outside corners and the gap between both arms.
	var samples: Array[Vector2] = [Vector2(100, 31), Vector2(100, 36), Vector2(190, 0), Vector2(205, 0), Vector2(190, 20), Vector2(196, 26), Vector2(100, 100)]
	for angle in [0.0, 0.53, 2.17]:
		var host := _boss()
		var remote := _boss(true)
		host.target = probe
		host.target_candidates = [probe]
		host._echo_cross_angle = angle
		host._sync_attack_overlay()
		remote.apply_projectile_network_sync_state(host.get_projectile_network_sync_state().duplicate(true))
		_check(remote.global_position != host.global_position, "Replica interpolation differs from the attack's transmitted origin")
		for offset in samples:
			probe.global_position = host.global_position + offset.rotated(angle)
			probe.health = 1000
			host._apply_echo_cross_hit()
			var damaged := probe.health < 1000
			_check(_warning_contains(host, probe.global_position) == damaged, "Host cross warning agrees with real damage at %s, angle %.2f" % [offset, angle])
			_check(_warning_contains(remote, probe.global_position) == damaged, "Joiner cross warning agrees with host damage at %s, angle %.2f" % [offset, angle])
		_check(host._seam_overlay.seam_zones.size() == host.seam_zones.size(), "Cross-spawned seams reach the same renderer immediately")
		host.boss_state = host.STATE_STALK
		host.seam_zones.clear()
		host._sync_attack_overlay()
		remote.apply_projectile_network_sync_state(host.get_projectile_network_sync_state().duplicate(true))
		_check(not remote._attack_overlay.telegraph_active, "An inactive authoritative state clears the joiner's warning")
		host.free()
		remote.free()
		await process_frame
	probe.free()

func _test_seam_lifecycle() -> void:
	var host := _boss()
	var remote := _boss(true)
	var probe := Probe.new()
	world.add_child(probe)
	host.target = probe
	host.target_candidates = [probe]
	var center := Vector2(200.0, 100.0)
	host._spawn_seam(center)
	remote.apply_projectile_network_sync_state(host.get_projectile_network_sync_state().duplicate(true))
	_check(host._seam_overlay.seam_zones.size() == 1 and remote._seam_overlay.seam_zones.size() == 1, "Host and joiner render each newly spawned seam")
	host._process_seam_zones(0.2)
	_check(is_equal_approx(float(host._seam_overlay.seam_zones[0]["time_left"]), host.seam_duration - 0.2), "Host overlay follows live remaining time rather than its spawn snapshot")
	# The last active tick still reaches the full radius, even during fade-out.
	host.seam_zones[0]["time_left"] = 0.21
	host.seam_zones[0]["tick_left"] = 0.01
	probe.global_position = center + Vector2(50.0, 0.0)
	probe.health = 1000
	host._process_seam_zones(0.02)
	_check(probe.health == 1000 - host.seam_tick_damage, "Late active seam ticks retain their existing full damage radius")
	var live_zone: Dictionary = host._seam_overlay.seam_zones[0]
	var visible_radius: float = host._seam_overlay.call("get_zone_draw_radius", live_zone) if host._seam_overlay.has_method("get_zone_draw_radius") else -1.0
	_check(is_equal_approx(visible_radius, host.seam_radius), "Active seam warning keeps the full radius until it stops damaging")
	host._evict_excess_seams(0)
	probe.health = 1000
	host._process_seam_zones(0.02)
	_check(probe.health == 1000 and bool(host._seam_overlay.seam_zones[0].get("evicting", false)), "Evicted seams stop damage and preserve their distinct fading state")
	remote.apply_projectile_network_sync_state(host.get_projectile_network_sync_state().duplicate(true))
	_check(bool(remote._seam_overlay.seam_zones[0].get("evicting", false)), "Joiner receives the same evicted seam state")
	host._process_seam_zones(1.0)
	_check(host.seam_zones.is_empty() and host._seam_overlay.seam_zones.is_empty(), "Expired host zones clear their warning immediately")
	remote._process_network_visuals(1.0)
	_check(remote.seam_zones.is_empty() and remote._seam_overlay.seam_zones.is_empty(), "Joiner visual expiry clears warnings without requiring a final packet")
	for boss_variant in [host, remote]:
		var boss := boss_variant as Lacuna
		boss._spawn_seam(center)
		boss._sync_attack_overlay()
		var seam_overlay := boss._seam_overlay
		var attack_overlay := boss._attack_overlay
		boss.free()
		_check(not is_instance_valid(seam_overlay) or seam_overlay.seam_zones.is_empty(), "Removing the owner clears its remaining seam warning immediately")
		_check(not is_instance_valid(attack_overlay) or not attack_overlay.telegraph_active, "Removing the owner clears its remaining attack warning immediately")
		await process_frame
		_check(not is_instance_valid(seam_overlay) and not is_instance_valid(attack_overlay), "Both sibling overlays are freed after owner removal")
	probe.free()

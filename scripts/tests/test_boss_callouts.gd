extends "res://scripts/tests/test_live_arena_edges.gd"
## Presentation follows production warning and replication lifecycles.
const CALLOUT := preload("res://scripts/shared/enemy_attack_callout.gd")
const SCRIPTS := [preload("res://scripts/enemy_boss.gd"), preload("res://scripts/enemy_boss_2.gd"), preload("res://scripts/enemy_boss_3.gd"), preload("res://scripts/enemy_seamlock.gd"), preload("res://scripts/enemy_mirrorline.gd"), preload("res://scripts/enemy_toll.gd")]
const COUNTS := [3, 6, 3, 3, 2, 3]

static func prepare(boss: Node2D, family: int, move: int) -> void:
	match family:
		0, 1, 2:
			boss.set("active_attack", mini(move, 4))
			boss.set("boss_state", 1)
			boss.set("state_time_left", 1.0)
			boss.set("telegraph_alpha", 0.55)
			boss.set("locked_direction", Vector2.RIGHT)
			if family in [0, 2] and move == 0:
				boss.call("_ensure_charge_motion")
				var motion: RefCounted = boss.get("_charge_motion")
				motion.call("prepare", 640.0, 0.58, Vector2.RIGHT)
			if family == 1:
				boss.set("_polar_shift_is_pull", move != 5)
				if move == 0: boss.call("_capture_prism_pattern")
				if move == 3: boss.call("_capture_orbital_lance_pattern")
				if move >= 4: boss.call("_capture_polar_shift_pattern")
			if family == 2: boss.call("_sync_attack_overlay")
		3:
			match move:
				0: boss.call("_enter_teleport")
				1: boss.call("_enter_band_attack")
				2: boss.call("_enter_spiral")
		4:
			boss.set("_twin_pending", move == 1)
			boss.call("_enter_telegraph")
			boss.set("_state_time_left", 0.65)
			boss.call("_advance_axis_rotation")
		5:
			if move != 1: boss.call("_begin_pulse_telegraph")
			if move != 0: boss.call("_begin_heal_channel")

static func clear_move(boss: Node2D, family: int) -> void:
	match family:
		0, 1, 2:
			boss.set("boss_state", 3)
			boss.set("state_time_left", 0.3)
		3: boss.call("_enter_recover")
		4: boss.call("_enter_cooldown")
		5:
			boss.set("_pulse_phase", 0)
			boss.set("_pulse_phase_left", 0.0)
			boss.set("_heal_channel_left", 0.0)

func _spawn(family: int, remote: bool = false) -> Node2D:
	var boss: Node2D = SCRIPTS[family].new()
	_circle(boss, 34.0)
	room.add_child(boss)
	boss.set_physics_process(false)
	boss.set("target", actor)
	boss.set("target_candidates", [actor])
	boss.call("set_network_simulation_enabled", not remote)
	boss.set_physics_process(false)
	return boss

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	root.size = Vector2i(960, 720)
	root.content_scale_size = root.size
	_setup()
	actor.position = Vector2(220, 70)
	for family in range(SCRIPTS.size()):
		for move in range(COUNTS[family]):
			var host := _spawn(family)
			var remote := _spawn(family, true)
			_check(host.call("get_attack_callout").is_empty(), "Survey and idle have no callout")
			prepare(host, family, move)
			var name: String = host.call("get_attack_callout")
			_check(not name.is_empty(), "Every committed move has a name: %d/%d" % [family, move])
			var getter := "get_projectile_network_sync_state" if family == 2 else "_get_custom_network_runtime_state"
			var receiver := "apply_projectile_network_sync_state" if family == 2 else "_apply_custom_network_runtime_state"
			var runtime: Dictionary = host.call(getter)
			remote.call(receiver, runtime.duplicate(true))
			_check(remote.call("get_attack_callout") == name, "Production runtime snapshot retains move name: " + name)
			if family == 5 and move == 2:
				_check(name.contains("Tribute Pulse") and name.contains("Healing Tithe") and name.contains("\n"), "Concurrent Toll channels both remain visible")
			for scale in [0.5, 1.0, 1.4]:
				root.canvas_transform = Transform2D(0.0, Vector2.ONE * scale, 0.0, Vector2(400, 230))
				for point in [Vector2.ZERO, Vector2(-750, -500), Vector2(750, 500)]:
					host.position = point
					var info := CALLOUT.layout(host, name, -100.0)
					_check(root.get_visible_rect().encloses(info.rect), "Callout fits after zoom/edge placement: " + name)
					_check(info.font_size >= 18, "Callout keeps readable type at arena zoom")
			if family == 3 and move == 0:
				host.call("_enter_illusion_phase", false)
				_check(host.call("get_attack_callout").is_empty(), "Illusions never reveal the real body with a label")
				remote.call(receiver, host.call(getter))
				_check(remote.call("get_attack_callout").is_empty(), "Joiners also lose the real-body label at the split")
			clear_move(host, family)
			_check(host.call("get_attack_callout").is_empty(), "Recovery removes the previous name")
			remote.call(receiver, host.call(getter))
			_check(remote.call("get_attack_callout").is_empty(), "Replicated recovery clears the joiner name")
			host.free()
			remote.free()
			await process_frame
	_clear()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Boss callouts: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

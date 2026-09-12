extends "res://scripts/tests/test_boss_callouts.gd"
## Actual secondary warning/damage transitions, rather than only preset windups.
const ALTERNATIVE := preload("res://scripts/enemy_boss_alternative.gd")
const CHARGE_TEST := preload("res://scripts/tests/test_boss_charge.gd")

static func begin_echo_chain(boss: Node2D, reposition: bool = false) -> void:
	boss.set("active_attack", 2)
	boss.set("boss_state", 1)
	boss.set("state_time_left", .01)
	boss.set("_echo_dash_reposition_only", reposition)
	boss.call("_process_windup_state", .02)

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	_setup()
	actor.position = Vector2(450, 100)
	_check_echo_chain()
	_check_polar_collapse()
	_check_null_collapse()
	_check_instant_resolution()
	_check_matching_spacing()
	_clear()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Boss callout parity: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _copy_native(host: Node2D, remote: Node2D) -> void:
	remote.call("apply_network_runtime_state", host.call("get_network_runtime_state"))
	remote.call("apply_projectile_network_sync_state", host.call("get_projectile_network_sync_state"))

func _check_echo_chain() -> void:
	var host := _spawn(1)
	var remote := _spawn(1, true)
	begin_echo_chain(host)
	for leg in range(1, 4):
		var expected := "Echo Dash / %d" % leg
		_check(host.call("get_attack_callout") == expected, "Actual contact leg stays named: " + expected)
		_copy_native(host, remote)
		_check(remote.call("get_attack_callout") == expected, "Both native state streams agree during contact: " + expected)
		host.call("_process_attack_state", float(host.get("echo_dash_duration")) + .001)
		if leg < 3:
			var next := "Echo Dash / %d" % (leg + 1)
			_check(host.get("_echo_dash_retargeting") and is_zero_approx(float(host.get("state_time_left"))), "The real next warning runs after the prior state's timer reaches zero")
			_check(host.call("get_attack_callout") == next, "Every committed retarget warning announces its next leg")
			_copy_native(host, remote)
			_check(remote.call("get_attack_callout") == next, "Retarget warning reaches the replica")
			remote.call("_process_network_visuals", float(host.get("echo_dash_retarget_pause")) * .5)
			_check(remote.call("get_attack_callout") == next, "The joiner keeps the announcement during its actual retarget timer")
			remote.call("_process_network_visuals", float(host.get("echo_dash_retarget_pause")))
			_check(remote.call("get_attack_callout").is_empty(), "Expired retarget cannot leave a stale announcement without another packet")
			_check(not remote.call("_is_attack_warning_active"), "Expired retarget clears its actual warning geometry with its name")
			host.call("_process_attack_state", float(host.get("echo_dash_retarget_pause")) + .001)
		else:
			_check(host.call("get_attack_callout").is_empty(), "The completed three-leg chain clears at recovery")
	begin_echo_chain(host, true)
	_check(host.call("get_attack_callout") == "Reposition", "The harmless movement variant has its actual identity")
	var payload: Dictionary = host.call("get_projectile_network_sync_state")
	_check(payload.get("echo_dash_reposition_only") == true, "Precise state carries the same reposition distinction as the runtime stream")
	remote.set("_echo_dash_reposition_only", false)
	remote.call("apply_projectile_network_sync_state", payload)
	_check(remote.call("get_attack_callout") == "Reposition", "Precise-only reception cannot mislabel Reposition as a contact chain")
	host.call("_process_attack_state", float(host.get("reposition_dash_duration")) + .001)
	_check(host.call("get_attack_callout").is_empty(), "Reposition clears when movement ends")
	host.free()
	remote.free()

func _check_polar_collapse() -> void:
	var host := _spawn(1)
	var remote := _spawn(1, true)
	prepare(host, 1, 4)
	host.set("_polar_shift_pull_damage_pending", true)
	host.set("_polar_shift_pull_damage_delay_left", float(host.get("polar_shift_pull_inner_delay")))
	_check(host.call("get_attack_callout") == "Polar Shift / PULL", "Pull windup keeps the root move name")
	host.call("_enter_attack_state")
	_check(host.call("get_attack_callout") == "Polar Collapse", "The delayed inner warning has its own move announcement")
	_copy_native(host, remote)
	_check(remote.call("get_attack_callout") == "Polar Collapse", "The inner warning has identical replica presentation")
	remote.call("_process_network_visuals", float(host.get("polar_shift_pull_inner_delay")) + .01)
	_check(remote.call("get_attack_callout").is_empty(), "An expired pending inner warning clears without waiting for recovery")
	host.free()
	remote.free()

func _check_null_collapse() -> void:
	var host := _spawn(2)
	var remote := _spawn(2, true)
	prepare(host, 2, 1)
	var victim := CHARGE_TEST.Probe.new()
	room.add_child(victim)
	victim.position = host.get("_locked_null_ring_center") + Vector2.RIGHT * (float(host.get("null_ring_radius")) + float(host.get("null_ring_safe_radius"))) * .5
	host.set("target_candidates", [victim])
	_check(host.get("_locked_null_ring_centers").is_empty(), "The real resolution also covers the single-center fallback")
	_check(host.call("get_attack_callout") == "Null Ring", "Null Ring names its actual initial warning")
	host.call("_enter_attack_state")
	_check(host.call("get_attack_callout") == "Null Ring / COLLAPSE", "Pending ring damage remains announced after initial windup")
	_copy_native(host, remote)
	_check(remote.call("get_attack_callout") == host.call("get_attack_callout"), "Pending collapse is identical on host and joiner")
	remote.call("_process_network_visuals", float(host.get("null_ring_pull_delay")) + .01)
	_check(float(remote.get("state_time_left")) > 0.0 and remote.call("get_attack_callout").is_empty(), "Replica clears resolved ring callout before the cosmetic ATTACK tail ends")
	_check(victim.attempts == 0, "Initial warning and remote visual expiry cannot apply the pending damage")
	host.call("_process_attack_state", float(host.get("null_ring_pull_delay")) + .01)
	_check(float(host.get("_null_ring_pull_timer")) <= 0.0 and host.call("get_attack_callout").is_empty(), "Actual ring damage resolution clears the announcement")
	_check(victim.attempts == 1 and victim.health_state.current_health == 10000 - int(host.get("null_ring_damage")), "Fallback resolution retains the exact single damage hit at the announced boundary")
	host.call("_process_attack_state", .01)
	_check(victim.attempts == 1, "Resolved ring afterglow cannot repeat its damage")
	victim.free()
	host.free()
	remote.free()

func _check_instant_resolution() -> void:
	for family in range(3):
		var host := _spawn(family)
		var move := 1 if family == 0 else (0 if family == 1 else 2)
		prepare(host, family, move)
		_check(not host.call("get_attack_callout").is_empty(), "Original instant ability announces its warning")
		host.call("_enter_attack_state")
		_check(host.call("get_attack_callout").is_empty() and float(host.get("attack_afterglow_time_left")) > 0.0, "Resolved original damage stops its callout despite remaining impact art")
		host.free()
	for id in ["kilnheart", "glassweaver", "null_archivist"]:
		var boss := ALTERNATIVE.new()
		boss.boss_id = id
		_circle(boss, 36.0)
		room.add_child(boss)
		boss.set_physics_process(false)
		boss.target = actor
		boss.target_candidates = [actor]
		boss.begin_attack(0)
		_check(not boss.get_attack_callout().is_empty(), "Newest warning is the same announcement boundary: " + id)
		boss._resolve_attack()
		_check(boss.get_attack_callout().is_empty() and boss._afterglow_left > 0.0, "Newest resolution also clears while impact art remains: " + id)
		boss.free()

func _check_matching_spacing() -> void:
	root.canvas_transform = Transform2D(0.0, Vector2(640, 380))
	for family in range(3):
		var boss := _spawn(family)
		prepare(boss, family, 0)
		for scale in [.5, 1.0, 1.4]:
			boss.scale = Vector2.ONE * scale
			var info := CALLOUT.layout(boss, boss.call("get_attack_callout"), -100.0)
			var bar: Control = boss.get("health_bar")
			var rect: Rect2 = bar.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, bar.size)
			_check(is_equal_approx(rect.position.y - (info.rect as Rect2).end.y, 8.0), "Every original boss has the same readable gap at each body scale")
		boss.free()

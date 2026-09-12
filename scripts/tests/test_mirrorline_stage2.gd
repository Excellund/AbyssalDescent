extends "res://scripts/tests/test_live_arena_edges.gd"
## Real health transitions and production attack clocks; observed spawns retain
## their actual origins, velocities and timing instead of replacing the attack.
const CHARGE_TEST := preload("res://scripts/tests/test_boss_charge.gd")
const SENDER := preload("res://scripts/core/enemy_state_sync_broadcaster.gd")
const STATUS := preload("res://scripts/shared/combat_target_status.gd")
const DAMAGE := preload("res://scripts/shared/damageable.gd")

class Mirrorline extends "res://scripts/enemy_mirrorline.gd":
	var elapsed := 0.0
	var volleys: Array[Dictionary] = []
	func _spawn_echo_from_player(axis_index: int = -1) -> void:
		var before := _active_echoes.size()
		super._spawn_echo_from_player(axis_index)
		if _active_echoes.size() > before:
			volleys.append({"at": elapsed, "axis": axis_index, "echoes": _active_echoes.slice(before).duplicate(true), "axes": _active_axes().duplicate(true)})

var victims: Array[Node2D] = []

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	_setup()
	actor.position = Vector2(500, 350)
	for point in [Vector2(220, 130), Vector2(-150, 240)]:
		var victim := CHARGE_TEST.Probe.new()
		room.add_child(victim)
		victim.position = point
		victims.append(victim)
	_check_codec()
	_check_payload_budget()
	_check_transport_fields()
	_check_threshold()
	for sundered in [false, true]:
		_check_warning(sundered)
		_check_cadence(sundered)
	_check_geometry_and_compatibility()
	_check_cancellation_and_replica()
	_clear()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Mirrorline stage two: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _boss(remote: bool = false) -> Mirrorline:
	var boss := Mirrorline.new()
	_circle(boss, 32.0)
	room.add_child(boss)
	boss.global_position = Vector2(-350, -250)
	boss.target = victims[0]
	boss.target_candidates = victims.duplicate()
	boss.set_network_simulation_enabled(not remote)
	boss.set_physics_process(false)
	boss._axis_normal = Vector2.RIGHT
	boss._axis_origin = Vector2.ZERO
	boss._axis_target_normal = Vector2.RIGHT
	boss._axis_target_origin = Vector2.ZERO
	return boss

static func cross_half_health(boss: Node2D) -> void:
	boss.call("take_damage", ceili(float(boss.call("get_max_health")) * .5))

func _step(boss: Mirrorline, duration: float, quantum: float = .01) -> void:
	var remaining := duration
	while remaining > .000001:
		var delta := minf(quantum, remaining)
		boss.elapsed += delta
		boss._process_behavior(delta)
		remaining -= delta

func _check_threshold() -> void:
	var boss := _boss()
	_check(boss.get_max_health() == 660 and boss.echo_damage == 26 and boss.seam_beam_tick_damage == 14, "Health and both damage values remain unchanged")
	boss._enter_telegraph()
	_step(boss, 1.30)
	_check(boss._state == boss.STATE_REFLECT and boss._active_axes().size() == 1, "First real windup enters single-axis reflect")
	cross_half_health(boss)
	_check(boss.get_current_health() == 330 and boss._twin_pending and not boss._twin_active, "Real half-health damage queues the twin without adding an unannounced lethal seam")
	_check(boss._active_axes().size() == 1 and is_equal_approx(boss._sundered_reduction_left, 2.0), "Existing transition protection remains while the current attack keeps one axis")
	boss._enter_cooldown()
	_step(boss, boss._state_time_left)
	boss._enter_telegraph()
	_check(boss._twin_active and not boss._twin_pending and boss._active_axes().size() == 2, "Next warning promotes the pending twin through the production transition")
	_check(is_equal_approx(boss._telegraph_total, 1.60), "First promoted twin receives its full additional settled warning")
	boss.free()

func _check_warning(sundered: bool) -> void:
	var boss := _boss()
	if sundered:
		cross_half_health(boss)
	boss._enter_telegraph()
	var duration := 1.60 if sundered else 1.30
	_check(is_equal_approx(boss._state_time_left, duration), "Expected warning duration for stage %d" % (2 if sundered else 1))
	# Ensure there is visible movement to settle, independent of random setup.
	boss._axis_prev_normal = Vector2.LEFT
	boss._axis_prev_origin = Vector2(-80, -60)
	boss._advance_axis_rotation()
	_step(boss, .70)
	_check(not boss._axis_origin.is_equal_approx(boss._axis_target_origin), "Axis is still rotating before the unchanged .715-second boundary")
	_step(boss, .015)
	var normal := boss._axis_normal
	var origin := boss._axis_origin
	_check(normal.is_equal_approx(boss._axis_target_normal) and origin.is_equal_approx(boss._axis_target_origin), "Both stages lock the real axis at .715 seconds")
	var remote := _boss(true)
	remote.apply_network_runtime_state(boss.get_network_runtime_state().duplicate(true))
	_check(remote._twin_active == sundered and is_equal_approx(remote._telegraph_total, duration), "Actual receiver retains the promoted stage and full warning duration")
	_check(is_equal_approx(remote._local_duration_for_state(remote.STATE_TELEGRAPH), duration), "Replica reconstructs the correct stage warning duration")
	_step(boss, duration - .715 - .01)
	_check(boss._state == boss.STATE_TELEGRAPH and boss._axis_normal.is_equal_approx(normal) and boss._axis_origin.is_equal_approx(origin) and boss.volleys.is_empty(), "The entire extra window is settled and harmless")
	_step(boss, .011)
	_check(boss._state == boss.STATE_REFLECT and not boss.volleys.is_empty(), "Echoes begin only after the complete warning expires")
	boss._enter_cooldown()
	_check(is_equal_approx(boss._state_time_left, 1.55 if sundered else 1.30), "Only twin-axis recovery gets the additional .25 seconds")
	remote.free()
	boss.free()

func _check_cadence(sundered: bool) -> void:
	var boss := _boss()
	if sundered:
		cross_half_health(boss)
	boss._enter_telegraph()
	boss._state_time_left = 0.0
	boss._advance_axis_rotation()
	boss.elapsed = 0.0
	boss._enter_reflect()
	_check(is_equal_approx(boss._state_time_left, 1.7), "Reflect danger duration is unchanged")
	var interval := .20 if sundered else .40
	var count := 8 if sundered else 4
	for volley in range(count):
		if volley > 0:
			_step(boss, interval - .001)
			_check(boss.volleys.size() == volley, "No early volley at stage %d / slot %d" % [2 if sundered else 1, volley])
			# Cross the exact boundary by .1ms to avoid floating subtraction residue.
			_step(boss, .0011)
		_check(boss.volleys.size() == volley + 1, "Exactly one volley arrives at each announced cadence slot")
		if boss.volleys.size() <= volley:
			continue
		var event := boss.volleys[volley]
		_check(absf(float(event.at) - float(volley) * interval) < .002, "Volley timestamp preserves the .4 stage-one / .2 stage-two cadence")
		_check(event.echoes.size() == victims.size(), "Each cadence slot fires one shot per player, without simultaneous twin pairs")
		var axis_index := volley % 2 if sundered else 0
		var axis: Dictionary = event.axes[axis_index]
		for index in range(mini(event.echoes.size(), victims.size())):
			var echo: Dictionary = event.echoes[index]
			var expected := boss._reflect_point_about(victims[index].global_position, axis.normal, axis.origin)
			_check((echo.origin as Vector2).is_equal_approx(expected), "Actual shot originates at that player's image across the expected alternating seam")
			_check(is_equal_approx((echo.velocity as Vector2).length(), 880.0) and is_equal_approx(float(echo.time_left), 2.6), "Echo speed and lifetime are preserved")
	_step(boss, .31 if sundered else .51)
	_check(boss.volleys.size() == count and boss._state == boss.STATE_COOLDOWN, "Four shots per axis finish without an extra volley at recovery")
	boss.free()

func _check_geometry_and_compatibility() -> void:
	var boss := _boss()
	cross_half_health(boss)
	boss._enter_telegraph()
	boss._axis_normal = Vector2.RIGHT
	boss._axis_origin = Vector2.ZERO
	boss._axis_target_normal = Vector2.RIGHT
	boss._axis_target_origin = Vector2.ZERO
	boss._enter_reflect()
	victims[0].position = Vector2(0, 160)
	victims[1].position = Vector2(160, 0)
	var before := [victims[0].get("attempts"), victims[1].get("attempts")]
	boss._tick_seam_beam_damage(.151)
	for index in range(2):
		_check(int(victims[index].get("attempts")) == int(before[index]) + 1, "Both perpendicular seams retain their real damage boundary")
	boss._active_echoes.clear()
	boss._spawn_echo_from_player()
	_check(boss._active_echoes.size() == 4, "Default helper call remains compatible with spawning both axes for two players")
	victims[0].position = Vector2(220, 130)
	victims[1].position = Vector2(-150, 240)
	boss.free()

func _check_cancellation_and_replica() -> void:
	var boss := _boss()
	cross_half_health(boss)
	boss._enter_telegraph()
	boss._enter_reflect()
	var remote := _boss(true)
	remote.apply_network_runtime_state(boss.get_network_runtime_state().duplicate(true))
	var next_id := remote._next_echo_id
	victims[0].position = remote._axis_origin + remote._axis_normal.orthogonal() * 160.0
	victims[1].position = remote._axis_origin + remote._axis_normal * 160.0
	if not remote._active_echoes.is_empty():
		remote._active_echoes[0].origin = victims[0].position
		remote._active_echoes[0].velocity = Vector2.ZERO
	var before_hits := int(victims[0].get("attempts")) + int(victims[1].get("attempts"))
	remote._process_network_visuals(.41)
	remote._advance_echoes(.13)
	remote._tick_reflect_cadence(.41)
	remote._spawn_echo_from_player(1)
	remote._tick_seam_beam_damage(.5)
	_check(remote._next_echo_id == next_id and remote.volleys.is_empty(), "Replica presentation cannot become a firing authority")
	_check(int(victims[0].get("attempts")) + int(victims[1].get("attempts")) == before_hits, "Replica warning/echo updates cannot deal damage")
	victims[0].position = Vector2(220, 130)
	victims[1].position = Vector2(-150, 240)
	boss._enter_cooldown()
	var count := boss.volleys.size()
	boss._tick_reflect_cadence(.5)
	_check(boss.volleys.size() == count, "Recovery cancels pending volley scheduling")
	boss._sundered_reduction_left = 0.0
	boss.take_damage(10000)
	_check(boss.is_queued_for_deletion() and boss._active_echoes.is_empty(), "Real death clears in-flight echoes immediately")
	boss._tick_reflect_cadence(.5)
	boss._spawn_echo_from_player(0)
	_check(boss._active_echoes.is_empty() and boss.volleys.size() == count, "Queued death cannot emit another scheduled or direct volley")
	remote.free()

func _check_payload_budget() -> void:
	var boss := _boss()
	cross_half_health(boss)
	boss._enter_telegraph()
	boss._enter_reflect()
	for slot in range(7):
		boss._tick_reflect_cadence(.20001)
	var sender := SENDER.new(room)
	var envelope := {"enemy_id": 974, "runtime_state_delta": {"custom": boss._get_custom_network_runtime_state()}}
	var size := sender._estimate_state_size_bytes(envelope)
	var fitted := sender._fit_state_to_size_limit(envelope, 900)
	print("[MirrorlinePayload] 16 two-player echoes: %d estimated bytes; custom retained: %s" % [size, fitted.runtime_state_delta.has("custom")])
	_check(boss._active_echoes.size() == 16 and fitted.runtime_state_delta.has("custom"), "All two-player twin volleys survive the production 900-byte state budget")
	var full := {"enemy_id": 974, "position": boss.position, "facing_angle": boss.get_network_facing_angle(), "health": boss.get_current_health(), "runtime_state_delta": boss.get_network_runtime_state()}
	var full_size := sender._estimate_state_size_bytes(full)
	print("[MirrorlinePayload] Full 16-echo runtime envelope: %d estimated bytes" % full_size)
	_check(sender._fit_state_to_size_limit(full, 900).runtime_state_delta.has("custom"), "Full runtime changes cannot push twin projectiles out of their transport budget")
	var status := seed_statuses(boss, [1], false)
	var shared_status: PackedByteArray = DAMAGE.get_status_network_packet(boss)
	_check(int(shared_status[18]) == 1 and int(shared_status[19]) == 1 and shared_status.decode_u16(16) > 0, "Ordinary status packet contains a real run identity, one Mark and one Dread owner")
	full.runtime_state_delta.shared_status = shared_status
	_check(sender._fit_state_to_size_limit(full, 900).runtime_state_delta.has("custom"), "Ordinary real Mark/Dread data retains the full generic pattern snapshot")
	print("[MirrorlinePayload] Normal status %d bytes; full envelope %d" % [shared_status.size(), sender._estimate_state_size_bytes(full)])
	status = seed_statuses(boss, [1, 2], true)
	shared_status = DAMAGE.get_status_network_packet(boss)
	_check(status.marks.size() == STATUS.MARK_SOURCES.size() * 2 and int(shared_status[18]) == 12 and int(shared_status[19]) == 2, "Dense real packet includes every supported Mark source for two owners")
	full.runtime_state_delta.shared_status = shared_status
	var dense := sender._fit_state_to_size_limit(full, 900)
	_check(not dense.runtime_state_delta.has("custom") and dense.runtime_state_delta.has("shared_status"), "Full dense status demonstrates the real generic pattern-budget gap while keeping statuses")
	var dedicated := boss.get_projectile_network_sync_state()
	_check(not dedicated.is_empty(), "Dedicated projectile snapshot remains available under dense generic status")
	var projectile_envelope := {"enemy_id": 974, "payload": dedicated}
	_check(sender._estimate_state_size_bytes(projectile_envelope) + 160 <= 1052, "Complete twin pattern stays within the separate production projectile packet budget")
	print("[MirrorlinePayload] Dense status %d bytes; full envelope %d; dedicated envelope %d" % [shared_status.size(), sender._estimate_state_size_bytes(full), sender._estimate_state_size_bytes(projectile_envelope)])
	boss.free()

func _check_codec() -> void:
	var boss := _boss()
	cross_half_health(boss)
	boss._enter_telegraph()
	boss._enter_reflect()
	for slot in range(7):
		boss._tick_reflect_cadence(.20001)
	var packet := boss._get_custom_network_runtime_state()
	_check(packet.m is PackedByteArray, "Twin phase and echoes use a bounded compact payload")
	var decoded := boss._decode_mirror_state(packet)
	var remote := _boss(true)
	remote._apply_custom_network_runtime_state(packet.duplicate(true))
	_check(remote._active_echoes.size() == 16, "Compact receiver reconstructs every two-player shot")
	for index in range(mini(16, remote._active_echoes.size())):
		var local_echo: Dictionary = boss._active_echoes[index]
		var received: Dictionary = remote._active_echoes[index]
		_check(received.id == local_echo.id and (received.origin as Vector2).distance_to(local_echo.origin) < .001 and absf((received.velocity as Vector2).x - (local_echo.velocity as Vector2).x) <= .051 and absf((received.velocity as Vector2).y - (local_echo.velocity as Vector2).y) <= .051 and absf(float(received.time_left) - float(local_echo.time_left)) < .0001, "Compact transport preserves shot ID, mirror origin, velocity and bounded lifetime")
	remote._update_echoes_visual_only(.2)
	var remaining: float = remote._active_echoes[0].time_left
	remote._apply_custom_network_runtime_state(packet.duplicate(true))
	_check(remote._active_echoes.size() == 16 and is_equal_approx(float(remote._active_echoes[0].time_left), remaining), "Repeated packet cannot duplicate echoes or reset their locally advancing lifetime")
	var legacy: Array = []
	for echo: Dictionary in boss._active_echoes:
		legacy.append({"i": echo.id, "o": echo.origin, "v": echo.velocity, "t": echo.time_left})
	var older := _boss(true)
	var previous_format := decoded.duplicate(true)
	previous_format.e = legacy
	older._apply_custom_network_runtime_state(previous_format)
	_check(older._active_echoes.size() == 16 and older._active_echoes[0].id == legacy[0].i, "Previous dictionary snapshots remain accepted by the actual receiver")
	var packed: PackedByteArray = decoded.e
	_check(boss._decode_echo_payload(packed.slice(0, packed.size() - 1)).is_empty(), "Truncated compact packets cannot create partial or misaligned shots")
	_check(boss._decode_echo_payload(17).is_empty(), "Wrong payload types cannot become echo entries")
	var invalid := packed.slice(0, boss.ECHO_WIRE_STRIDE)
	invalid.encode_u32(0, 0)
	_check(boss._decode_echo_payload(invalid).is_empty(), "A zero shot ID is rejected")
	invalid = packed.slice(0, boss.ECHO_WIRE_STRIDE)
	invalid.encode_float(4, NAN)
	_check(boss._decode_echo_payload(invalid).is_empty(), "Non-finite echo coordinates cannot reach drawing or prediction")
	invalid = packed.slice(0, boss.ECHO_WIRE_STRIDE)
	invalid.encode_float(boss.ECHO_WIRE_STRIDE - 4, -1.0)
	_check(boss._decode_echo_payload(invalid).is_empty(), "Expired or negative echo lifetimes are discarded")
	var header: PackedByteArray = packet.m
	_check(boss._decode_mirror_state({"m": header.slice(0, boss.MIRROR_WIRE_HEADER - 1)}).is_empty(), "A truncated phase header cannot change a replica state")
	_check(boss._decode_mirror_state({"m": header.slice(0, header.size() - 1)}).is_empty(), "A truncated echo tail invalidates its entire combined phase packet")
	var invalid_header := header.duplicate()
	invalid_header.encode_float(20, NAN)
	_check(boss._decode_mirror_state({"m": invalid_header}).is_empty(), "Nonfinite mirror angles cannot enter axis interpolation")
	var state_before := remote._state
	remote._apply_custom_network_runtime_state({"m": invalid_header})
	_check(remote._state == state_before and remote._active_echoes.size() == 16, "Rejected header leaves existing replica attack presentation intact")
	invalid_header = header.duplicate()
	invalid_header.encode_u8(0, 255)
	_check(boss._decode_mirror_state({"m": invalid_header}).is_empty(), "Unknown attack states are rejected before they can alter duration")
	older.free()
	remote.free()
	boss.free()

static func seed_statuses(boss: Node2D, owners: Array, dense: bool) -> Node:
	var status: Node = DAMAGE._target_status(boss, true)
	status.clear()
	for owner: int in owners:
		for source: String in (STATUS.MARK_SOURCES if dense else ["wraithstep"]):
			status.apply_mark(owner, source, .15, 4.0)
		status.add_dread(owner, 8, {"epoch": 1, "seq": 1})
	return status

func _check_transport_fields() -> void:
	var boss := _boss()
	var remote := _boss(true)
	boss.spawn_transport_time_left = 0.0
	var inactive := boss.get_network_runtime_state()
	_check(inactive.has("spawn_transport_time_left") and is_zero_approx(float(inactive.spawn_transport_time_left)) and not inactive.has("spawn_transport_duration") and not inactive.has("spawn_transport_seed"), "Inactive transport keeps its clearing timer while omitting irrelevant duration and seed")
	boss.spawn_transport_duration = 1.25
	boss.spawn_transport_seed = .625
	boss.spawn_transport_time_left = .50
	var active := boss.get_network_runtime_state()
	_check(is_equal_approx(float(active.get("spawn_transport_duration", -1.0)), 1.25) and is_equal_approx(float(active.get("spawn_transport_seed", -1.0)), .625), "An active transport includes its actual duration and seed")
	remote.apply_network_runtime_state(active)
	_check(remote.is_spawn_transporting() and is_equal_approx(remote.spawn_transport_duration, 1.25) and is_equal_approx(remote.spawn_transport_seed, .625), "Actual replica receiver reconstructs active transport")
	boss.spawn_transport_time_left = 0.0
	remote.apply_network_runtime_state(boss.get_network_runtime_state())
	_check(not remote.is_spawn_transporting(), "The omitted inactive metadata cannot leave the replica stuck in transport")
	remote.free()
	boss.free()

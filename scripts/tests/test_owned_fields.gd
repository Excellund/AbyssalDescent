extends "res://scripts/tests/test_blast_feedback.gd"

const FIELDS := preload("res://scripts/shared/owned_field_registry.gd")
var fields: RefCounted
var serial := 0

func _run() -> void:
	_make_world()
	player.apply_trial_power("static_wake")
	player.apply_trial_power("sigil_chain")
	player.apply_upgrade("lacuna_echo")
	player.apply_upgrade("null_corridor")
	player.apply_upgrade("pillar_convergence")
	fields = FIELDS.new()
	fields.initialize(player)
	_test_geometry()
	_test_expiry_and_replacement()
	_test_validation_and_lifecycle()
	_test_serial_ordering()
	_test_native_registration()
	_test_parent_child_clock_order()
	_test_remote_parent_clock_order()
	fields = null
	_free_world()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OwnedFields] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _identity(action: Dictionary) -> String:
	serial += 1
	return "%d:%d:%d" % [action.epoch, action.seq, serial]

func _register(source: String, geometry: Dictionary, kind: String = "attack") -> Dictionary:
	var action := player.new_combat_action(kind)
	var identity := _identity(action)
	_check(fields.register_field(source, identity, geometry, action), "%s native owned geometry is accepted" % source)
	return {"action": action, "identity": identity, "geometry": geometry, "source": source}

func _circle(center: Vector2, radius: float = 20.0, remaining: float = 1.0) -> Dictionary:
	return {"shape": "circle", "center": center, "radius": radius, "remaining": remaining}

func _test_geometry() -> void:
	fields.clear()
	_register("sigil_chain_zone", _circle(Vector2.ZERO))
	_check(fields.contains_point(Vector2(20.0, 0.0)), "Circle includes its exact damage boundary")
	_check(not fields.contains_point(Vector2(20.01, 0.0)), "Circle excludes outside decoration")
	fields.clear()
	_register("static_wake", {"shape": "capsules", "segments": [{"a": Vector2.ZERO, "b": Vector2(80.0, 0.0)}, {"a": Vector2(80.0, 0.0), "b": Vector2(80.0, 60.0)}], "radius": 12.0, "remaining": 1.0}, "dash")
	_check(fields.contains_point(Vector2(-12.0, 0.0)), "Wake includes its round departure cap")
	_check(fields.contains_point(Vector2(92.0, 60.0)), "Wake includes its round arrival cap")
	_check(not fields.contains_point(Vector2(-12.01, 0.0)), "Wake excludes outside radius")
	_check(not fields.contains_point(Vector2(40.0, 30.0)), "Bent Wake does not fill its bounding rectangle")
	fields.clear()
	_register("null_corridor_deflect", {"shape": "rectangle", "start": Vector2.ZERO, "end": Vector2(100.0, 0.0), "width": 20.0, "remaining": 1.0}, "dash")
	_check(fields.contains_point(Vector2(100.0, 10.0)), "Corridor includes exact square corner")
	_check(not fields.contains_point(Vector2(100.01, 0.0)), "Corridor has no invented round end cap")
	_check(not fields.contains_point(Vector2(30.0, 10.01)), "Corridor excludes beyond actual full width")
	fields.clear()
	player.global_position = Vector2(20.0, 40.0)
	_register("convergence_window", {"shape": "moving_circle", "center": player.global_position, "radius": 30.0, "remaining": 1.0})
	player.global_position = Vector2(200.0, 40.0)
	_check(fields.contains_point(Vector2(230.0, 40.0)) and not fields.contains_point(Vector2(20.0, 40.0)), "Convergence follows its owner rather than a stale pulse position")
	fields.clear()
	_register("void_echo_zone", _circle(Vector2(400.0, 0.0), 25.0, 2.4))
	_check(fields.contains_point(Vector2(400.0, 0.0)), "Lacuna Well qualifies through its own true circle")

func _test_expiry_and_replacement() -> void:
	fields.clear()
	var saved := _register("sigil_chain_zone", _circle(Vector2.ZERO))
	fields.advance(0.75)
	_check(fields.register_field(saved.source, saved.identity, saved.geometry, saved.action), "Same field may update geometry")
	fields.advance(0.251)
	_check(not fields.contains_point(Vector2.ZERO), "An update cannot restart the original expiry")
	_check(not fields.register_field(saved.source, saved.identity, saved.geometry, saved.action), "Late state cannot revive an expired field")
	fields.clear()
	var first := _register("static_wake", {"shape": "capsules", "segments": [{"a": Vector2.ZERO, "b": Vector2(10.0, 0.0)}], "radius": 5.0, "remaining": 1.0}, "dash")
	for center in [Vector2(100.0, 0.0), Vector2(200.0, 0.0)]:
		_register("static_wake", {"shape": "capsules", "segments": [{"a": center, "b": center + Vector2(10.0, 0.0)}], "radius": 5.0, "remaining": 1.0}, "dash")
	_check(not fields.contains_point(Vector2.ZERO) and fields.contains_point(Vector2(100.0, 0.0)) and fields.contains_point(Vector2(200.0, 0.0)), "Third ribbon retires only the oldest of two Wake fields")
	_check(not fields.register_field(first.source, first.identity, first.geometry, first.action), "Replaced Wake cannot reappear from an old packet")
	fields.clear()
	_register("void_echo_zone", _circle(Vector2.ZERO))
	_register("void_echo_zone", _circle(Vector2(100.0, 0.0)))
	_check(not fields.contains_point(Vector2.ZERO) and fields.contains_point(Vector2(100.0, 0.0)), "New Lacuna Well replaces old membership")
	fields.clear()
	for index in range(FIELDS.MAX_FIELDS + 3):
		_register("sigil_chain_zone", _circle(Vector2(index * 50.0, 0.0), 5.0))
	_check(fields._fields.size() == FIELDS.MAX_FIELDS, "Field storage stays bounded across repeated native placements")
	_check(not fields.contains_point(Vector2.ZERO) and fields.contains_point(Vector2((FIELDS.MAX_FIELDS + 2) * 50.0, 0.0)), "Global limit retains newest membership")

func _test_validation_and_lifecycle() -> void:
	fields.clear()
	var action := player.new_combat_action("attack")
	var identity := _identity(action)
	for malformed in [_circle(Vector2.INF), _circle(Vector2.ZERO, INF), _circle(Vector2.ZERO, -1.0), _circle(Vector2.ZERO, player.sigil_chain_radius + 1.0), _circle(Vector2.ZERO, 5.0, 1.01)]:
		_check(not fields.register_field("sigil_chain_zone", identity, malformed, action), "Invalid or overpowered geometry is rejected")
	for malformed_shape in [null, 3, [], {}]:
		var malformed := _circle(Vector2.ZERO)
		malformed.shape = malformed_shape
		_check(not fields.register_field("sigil_chain_zone", identity, malformed, action), "Malformed shape types fail without a script exception")
	_check(not fields.register_field("world_ring", identity, _circle(Vector2.ZERO), action), "Visual rings cannot register gameplay Fields")
	_check(not fields.register_field("sigil_chain_zone", "wrong:identity", _circle(Vector2.ZERO), action), "Field identity must belong to its authenticated action")
	var spoof := action.duplicate(true)
	spoof.owner = int(action.owner) + 1
	_check(not fields.register_field("sigil_chain_zone", identity, _circle(Vector2.ZERO), spoof), "Another owner's action cannot register a field")
	var stale := action.duplicate(true)
	stale.room = int(action.room) - 1
	_check(not fields.register_field("sigil_chain_zone", identity, _circle(Vector2.ZERO), stale), "Prior-room registration is rejected")
	player.reward_sigil_chain = false
	_check(not fields.register_field("sigil_chain_zone", identity, _circle(Vector2.ZERO), action), "A field cannot be registered without the learned power")
	player.reward_sigil_chain = true
	var saved := _register("sigil_chain_zone", _circle(Vector2.ZERO))
	var retire: Dictionary = saved.geometry.duplicate(true)
	retire.remaining = 0.0
	_check(fields.register_field(saved.source, saved.identity, retire, saved.action) and not fields.contains_point(Vector2.ZERO), "Explicit native removal retires membership immediately")
	_check(not fields.register_field(saved.source, saved.identity, saved.geometry, saved.action), "Explicitly removed field cannot be revived")
	_register("sigil_chain_zone", _circle(Vector2.ZERO))
	player.discard_pending_combat_input()
	_check(not fields.contains_point(Vector2.ZERO), "Actual player input cancellation invalidates prior action fields")
	_check(not fields.register_field(saved.source, saved.identity, saved.geometry, saved.action), "Cancelled epoch cannot register old field state")
	var new_field := _register("sigil_chain_zone", _circle(Vector2(200.0, 0.0)))
	fields.advance(NAN)
	_check(fields.contains_point(Vector2(200.0, 0.0)), "Non-finite delta cannot poison expiry")
	fields.advance(1000000.0)
	_check(fields._fields.is_empty(), "Long hitch retires bounded fields without per-tick iteration")
	_check(not fields.register_field(new_field.source, new_field.identity, new_field.geometry, new_field.action), "Expired field stays retired after a hitch")

func _test_serial_ordering() -> void:
	fields.clear()
	var old_action := player.new_combat_action("dash")
	var old_id := _identity(old_action)
	var newer := _register("void_echo_zone", _circle(Vector2.ZERO))
	var delayed_id := _identity(old_action)
	_check(fields.register_field("void_echo_zone", delayed_id, _circle(Vector2(200.0, 0.0)), old_action), "A delayed kill from an older action can create a genuinely new Well")
	_check(fields.contains_point(Vector2(200.0, 0.0)) and not fields.contains_point(Vector2.ZERO), "Native serial orders replacement independently from action age")
	_check(not fields.register_field("void_echo_zone", old_id, _circle(Vector2.ZERO), old_action), "An unseen stale field cannot replace the newest Well")
	_check(not fields.register_field(newer.source, newer.identity, newer.geometry, newer.action), "A replaced field cannot reappear with its original serial")
	var malformed := _circle(Vector2.ZERO, INF)
	_check(not fields.register_field("void_echo_zone", "%d:%d:999999" % [old_action.epoch, old_action.seq], malformed, old_action), "Malformed high serial is rejected before advancing the floor")
	_check(fields.register_field("void_echo_zone", _identity(old_action), _circle(Vector2(300.0, 0.0)), old_action), "Malformed serial does not poison valid later registration")
	_check(not fields.register_field("void_echo_zone", "%d:%d:999999" % [old_action.epoch, old_action.seq], {"remaining": 0.0}, old_action), "Unknown removal cannot retire a future field")
	_check(fields.register_field("void_echo_zone", _identity(old_action), _circle(Vector2(400.0, 0.0)), old_action), "Unknown removal preserves the next real field")

func _test_native_registration() -> void:
	fields = player.shared_build_runtime.fields
	fields.clear()
	var position := Vector2(500.0, 100.0)
	player._drop_sigil_chain_zone(position)
	_check(fields.contains_point(position) and not fields.contains_point(position + Vector2(player.sigil_chain_radius + 0.1, 0.0)), "Production Sigil creation registers exactly its live radius")
	fields.clear()
	player._apply_void_echo(position)
	var radius := clampf(54.0 + float(player.void_echo_damage) * 0.6, 54.0, 110.0)
	_check(fields.contains_point(position + Vector2(radius - 0.1, 0.0)) and not fields.contains_point(position + Vector2(radius + 0.1, 0.0)), "Production Lacuna creation registers its actual Field")
	fields.clear()
	player._null_corridor_dash_origin = position
	player._apply_null_corridor_segment(position, position + Vector2(100.0, 0.0))
	var width := 32.0 + player.null_corridor_strength * 14.0
	_check(fields.contains_point(position + Vector2(50.0, width * 0.5)) and not fields.contains_point(position + Vector2(100.1, 0.0)), "Production Null corridor uses its rectangular damage footprint")
	fields.clear()
	player.convergence_window_left = 0.0
	for _index in range(6):
		player._try_apply_convergence_surge(player.global_position, 20, 0)
	_check(player.convergence_window_left > 0.0 and fields.contains_point(player.global_position), "Production Convergence activation registers its moving Field")
	fields.clear()
	player.static_wake_controller.begin_dash(player.new_combat_action("dash"))
	player.static_wake_controller.append_segment(position, position + Vector2(80.0, 0.0))
	player.static_wake_controller.append_segment(position + Vector2(80.0, 0.0), position + Vector2(80.0, 60.0))
	player.static_wake_controller.end_dash()
	_check(fields.contains_point(position) and fields.contains_point(position + Vector2(80.0, 60.0)), "Production Wake append/end registers the whole traveled path")
	_check(not fields.contains_point(position + Vector2(30.0, 60.0)), "Production Wake membership leaves the bent path's empty interior untouched")
	player.static_wake_controller.cancel()
	_check(not fields.contains_point(position), "Production Wake cancel retires its owned geometry")
	fields.clear()
	player._on_cue_sigil_chain_zone({"position": position, "radius": player.sigil_chain_radius, "lifetime": 1.0, "depth": 1})
	_check(not fields.contains_point(position), "Actual replicated Sigil visual cue cannot create gameplay membership")

func _test_parent_child_clock_order() -> void:
	player.discard_pending_combat_input()
	player.shared_build_runtime._physics_process(0.0)
	fields = player.shared_build_runtime.fields
	fields.clear()
	# Player updates existing effects before accepting Dash; its child runtime
	# runs afterward in the same physics frame. The new trail has not aged yet.
	player._physics_process(0.5)
	var position := Vector2(800.0, 0.0)
	player.static_wake_controller.begin_dash(player.new_combat_action("dash"))
	player.static_wake_controller.append_segment(position, position + Vector2(60.0, 0.0))
	player.static_wake_controller.end_dash()
	player.shared_build_runtime._physics_process(0.5)
	player._physics_process(1.6)
	player.shared_build_runtime._physics_process(1.6)
	_check(player.static_wake_controller.contains_point(position), "Native Wake still has 0.4s of its mapped lifetime")
	_check(fields.contains_point(position), "Parent then child physics preserves the same live Field lifetime as its native source")

func _test_remote_parent_clock_order() -> void:
	player.discard_pending_combat_input()
	fields = player.shared_build_runtime.fields
	var action := player.new_combat_action("attack")
	player.local_owner = false
	var position := Vector2(1600.0, 0.0)
	_check(fields.register_field("sigil_chain_zone", _identity(action), _circle(position, 20.0, 1.0), action), "Host accepts authenticated geometry for its remotely owned avatar")
	player._physics_process(0.4)
	player.shared_build_runtime._physics_process(0.4)
	_check(fields.contains_point(position), "Remote host avatar's parent and child do not age one Field twice")
	player._physics_process(0.4)
	player.shared_build_runtime._physics_process(0.4)
	_check(fields.contains_point(position), "Remote host Field remains live until its actual one-second lifetime")
	player._physics_process(0.21)
	player.shared_build_runtime._physics_process(0.21)
	_check(not fields.contains_point(position), "Remote host Field expires through the ordinary Player parent update")
	player.local_owner = true

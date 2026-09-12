extends "res://scripts/tests/test_breakwater_enet.gd"

const RUNTIME := preload("res://scripts/tests/test_breakwater_runtime.gd")
var shore_probes: Array[Node2D] = []

func _run() -> void:
	await super._run()
	if is_instance_valid(deadline_timer):
		deadline_timer.start(100.0)

func snapshot() -> Dictionary:
	var result := super.snapshot()
	result["gaps"] = breakwater._gate_gaps
	result["gate_origin"] = breakwater._gate_origin
	result["gate_direction"] = breakwater._gate_direction
	result["gate_progress"] = breakwater._gate_progress
	result["sequence"] = breakwater._received_sequence
	result["status"] = DAMAGE.get_status_network_state(breakwater)
	return result

func _inspect_gate(key: String, state: Dictionary = {}) -> Dictionary:
	var actual := send_state(state)
	var sequence := int(actual.custom.q)
	world.fixture_command.rpc_id(joiner_id, "gate_packet", {"key": key, "sequence": sequence})
	check(await until(func(): return results.has(key)), "Joiner acknowledges gate state: " + key)
	return results.get(key, {})

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	await physics_frame
	check(await until(func(): return world.run_summary_recorder.run_summary_tracker._received_provenance_peers.has(client_id), 6.0), "Party handshake establishes native shared run identity")
	world.current_room_size = Vector2(1160.0, 860.0)
	world.current_effective_room_size = world.current_room_size
	local_player.position = Vector2(480.0, -300.0)
	remote_player.position = Vector2(480.0, -100.0)
	for index in range(2):
		var probe := RUNTIME.Probe.new()
		probe.player_id = 20 + index
		world.add_child(probe)
		probe.position = Vector2(480.0, 100.0 + index * 200.0)
		shore_probes.append(probe)
	breakwater._begin_harbor_gate()
	check(breakwater._gate_gaps.size() == 4, "The network stress snapshot carries all four separate openings")
	# Populate the production status serializer with every supported Mark source
	# for four owners, plus Dread and Slow. This exercises worst-party payload.
	var status := DAMAGE._target_status(breakwater, true)
	for owner in [1, client_id, 20, 21]:
		for source: String in status.MARK_SOURCES:
			status.apply_mark(owner, source, 0.25, 8.0)
		status.dread[owner] = 6
	breakwater.slow_time_left = 3.0
	breakwater.slow_speed_mult = 0.45
	var raw := breakwater.get_network_runtime_state()
	raw["shared_status"] = DAMAGE.get_status_network_packet(breakwater)
	var quantized: Dictionary = world.enemy_state_sync_broadcaster._quantize_runtime_state_for_network(raw)
	var wire := {"enemy_id": BREAKWATER_ID, "health": breakwater.get_current_health(), "position": breakwater.global_position, "facing_angle": 0.0, "runtime_state_delta": quantized}
	var estimate: int = world.enemy_state_sync_broadcaster._estimate_state_size_bytes(wire)
	var fitted: Dictionary = world.enemy_state_sync_broadcaster._fit_state_to_size_limit(wire, 900)
	results["packet_budget"] = {"estimate": estimate, "encoded_bytes": var_to_bytes(wire).size(), "marks": status.marks.size(), "openings": breakwater._gate_gaps.size()}
	check(estimate <= 900 and fitted.runtime_state_delta.has("custom"), "Four openings plus 24 Marks, four Dread owners and Slow survive the actual 900-byte runtime fitter: %d" % estimate)
	var report := await _inspect_gate("brace", quantized)
	check(report.get("warnings") == breakwater.get_warning_polygons() and report.get("gaps") == breakwater._gate_gaps and report.get("gate_origin") == breakwater._gate_origin, "Quantized host and joining process retain the same full-floor warning, shore and four committed openings")
	check(report.get("callout") == "Harbor Gate / HOLD THE OPENING" and report.get("local_damage_calls") == 0 and report.get("remote_damage_calls") == 0, "The same plain callout reaches the joiner, whose explicit simulation attempts create no damage")
	check(report.get("status", {}).get("m", []).size() == 24, "The full real status packet reaches the observer beside the gate")
	var brace_state := raw.duplicate(true)
	var openings := breakwater._gate_gaps.duplicate()
	remote_player.position = Vector2(480.0, 0.0)
	local_player.position = Vector2(480.0, -300.0)
	breakwater._process_behavior(BREAKWATER.GATE_WARNING)
	check(breakwater._gate_gaps == openings and local_player.get_current_health() == 100 and remote_player.get_current_health() == 100, "Players may reposition during the full warning without damage or retargeted openings")
	breakwater._process_behavior(0.1)
	report = await _inspect_gate("moving")
	check(report.get("warnings") == breakwater.get_warning_polygons() and report.get("callout") == "Harbor Gate", "Actual moving seawall geometry and phase agree across native ENet")
	breakwater._process_behavior(5.0)
	check(local_player.get_current_health() == 100 and remote_player.get_current_health() == 84, "The authoritative crossing preserves the host opening and damages the joiner outside its opening exactly once")
	check((remote_player as ChargePlayer).damage_contexts.size() == 1 and (remote_player as ChargePlayer).damage_contexts[0].ability == "breakwater_gate", "The real contact keeps gate attribution and has no duplicate damage call")
	report = await _inspect_gate("resolved")
	world.fixture_command.rpc_id(client_id, "inspect_health", {"key": "health", "local": 84, "remote": 100})
	check(await until(func(): return results.has("health")), "Host-owned damage reaches both joining player nodes")
	check(report.get("warnings", []).is_empty(), "Resolved gate removes all replicated danger")
	# Rejected packets must neither resurrect nor advance the ordering cursor.
	var accepted_sequence := int(report.get("sequence", -1))
	for invalid in ["old", "room", "missing", "nan", "overlap"]:
		var bad := brace_state.duplicate(true)
		if invalid != "old":
			bad.custom.q += 100
		match invalid:
			"room": bad.custom.r -= 1
			"missing": bad.custom.erase("g")
			"nan": bad.custom.g[0] = Vector2.INF
			"overlap": bad.custom.g[7] = bad.custom.g[6]
		send_state(bad)
		world.fixture_command.rpc_id(client_id, "gate_rejected", {"key": invalid})
		check(await until(func(): return results.has(invalid)), "Joiner receives deliberately invalid gate packet: " + invalid)
		var rejected: Dictionary = results.get(invalid, {})
		check(rejected.get("warnings", []).is_empty() and rejected.get("sequence", -2) == accepted_sequence, "Rejected %s cannot resurrect a gate or poison the accepted sequence" % invalid)
	# Lost release/state packets expire only the replica; no local release is invented.
	breakwater._begin_harbor_gate()
	var lease_state := send_state()
	world.fixture_command.rpc_id(client_id, "gate_expire", {"sequence": lease_state.custom.q})
	check(await until(func(): return results.has("lease")), "Joiner runs the missing-packet visual lease")
	check(results.get("lease", {}).get("warnings", []).is_empty() and results.get("lease", {}).get("gaps", []).is_empty(), "An expired gate leaves no stale shore or opening rails")
	send_state(lease_state)
	world.fixture_command.rpc_id(client_id, "gate_rejected", {"key": "expired_replay"})
	check(await until(func(): return results.has("expired_replay")), "Old start arrives after visual expiry")
	check(results.get("expired_replay", {}).get("warnings", []).is_empty(), "Replaying the expired start cannot restore its warning")
	breakwater._cancel_attack()
	report = await _inspect_gate("cancel")
	check(report.get("warnings", []).is_empty() and report.get("gaps", []).is_empty(), "Real host cancellation clears all gate presentation")
	# A departed participant's gap remains committed for this attack; the next
	# warning drops that player. Host death and authority changes cancel normally.
	remote_player.set_combat_removed(true)
	breakwater.target = local_player
	breakwater._begin_harbor_gate()
	check(breakwater._gate_gaps.size() == 3, "The next gate excludes a combat-removed participant")
	report = await _inspect_gate("after_removal")
	check(report.get("gaps") == breakwater._gate_gaps, "Observer sees the exact reduced party opening set")
	breakwater.set_network_simulation_enabled(false)
	report = await _inspect_gate("authority_cancel")
	check(report.get("warnings", []).is_empty(), "Authority retirement clears the warning across transport")
	world.fixture_command.rpc_id(client_id, "gate_finish")
	check(await until(func(): return results.has("finished")), "Joining process finishes after its final cancellation assertion")
	await finish()

func client_command(command: String, payload: Dictionary) -> void:
	match command:
		"gate_packet":
			check(await until(func(): return breakwater._received_sequence >= int(payload.sequence)), "Replica receives the expected gate ordering sequence")
			breakwater._process_behavior(10.0)
			breakwater._release_harbor_gate()
			breakwater._apply_gate_hits(0.0, breakwater._gate_distance)
			world.fixture_result.rpc_id(1, payload.key, snapshot())
		"gate_rejected": world.fixture_result.rpc_id(1, payload.key, snapshot())
		"gate_expire":
			check(await until(func(): return breakwater._received_sequence >= int(payload.sequence)), "Replica receives the gate before expiring its lease")
			breakwater._process_network_visuals(BREAKWATER.REMOTE_LEASE + 0.01)
			world.fixture_result.rpc_id(1, "lease", snapshot())
		"gate_finish":
			world.fixture_result.rpc_id(1, "finished", {})
			await create_timer(0.1).timeout
			await finish()
		_:
			await super.client_command(command, payload)

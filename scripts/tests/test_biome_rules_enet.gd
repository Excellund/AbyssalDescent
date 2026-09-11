extends "res://scripts/tests/test_brittle_cover_enet.gd"
## Two real Main scenes and mapped native actors. Fixture barriers coordinate
## inspection; only the production world RPC transports biome phase/geometry.
## test_boss_combinations_enet.ps1 -FixtureScript res://scripts/tests/test_biome_rules_enet.gd
## -ValidationProject <isolated snapshot> -FixtureTimeoutSeconds 90

const RULES := preload("res://scripts/core/biome_rule_controller.gd")
const NATIVE_ENEMY := preload("res://scripts/enemy_base.gd")
var storm_warning: Dictionary = {}
var storm_active: Dictionary = {}
var future_haunt_profile: Dictionary = {}
var future_haunt_warning: Dictionary = {}

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or args.size() != 4:
		push_error("Biome rule ENet fixture requires the isolated two-process helper")
		quit(1)
		return
	await _setup_cover_peers(args)
	PlayerReplicationService.multiplayer_session_manager = MultiplayerSessionManager
	await _storm_transport_and_damage()
	await _reject_foreign_rule_states()
	await _future_room_warning_and_haunt()
	for id: String in ["crumble", "shatterfield", "grinding_vault", "hollow", "void_breach", "the_maelstrom", "convergence_end"]:
		await _ordinary_rule_pair(id)
	await _compact_mission_entry()
	await _assistance_apex_damage()
	await _cover_free_fragment_entry()
	await _barrier("biome-rules-finished")
	await _finish_rule_fixture()

func _enter_biome_room(id: String, key: String, prepared_profile: Dictionary = {}) -> void:
	var act := int(BIOMES.get_biome(id).act)
	world.first_boss_defeated = act >= 2
	world.second_boss_defeated = act >= 3
	if role == "host":
		var roster: Array[String] = ["crumble", "grinding_vault", "void_breach"]
		roster[act - 1] = id
		world._sync_act_biomes.rpc(PackedStringArray(roster))
		world.encounter_profile_builder.set_active_biome(BIOMES.get_biome(id))
		var built_profile: Dictionary = prepared_profile if not prepared_profile.is_empty() else world.encounter_profile_builder.build_debug_encounter_profile("crossfire", 5)
		_write("rule-profile-" + key, built_profile)
	await _barrier("rule-profile-" + key)
	var profile: Dictionary = _read("rule-profile-" + key)
	await _enter_profile(profile, key)
	check(world._active_biome_rule_id == id and world._biome_rules.rule_id == id, "Actual chosen-door entry configures the room's biome rule: " + id)
	check(world._biome_rules.snapshot().get("run", "") == INTERACTIONS.current_run() and int(world._biome_rules.snapshot().get("room", -1)) == world.get_current_room_sync_id(), "Rule is bound to the actual shared run and entered room: " + id)
	for actor in world._get_multiplayer_player_nodes():
		actor.set_max_health_and_current(200, 200)
		actor.set_combat_damage_enabled(true)
		actor.position = Vector2(350, 250) if actor.player_id == client_id else Vector2(-160, -40)
		actor.external_slow_left = 0.0
		actor.external_slow_mult = 1.0
	await _barrier("rule-actors-" + key)

func _advance_network_phase(key: String, expected_phase: String) -> Dictionary:
	if role == "host":
		world._tick_biome_rules(100.0)
		_write("rule-state-" + key, world._biome_rules.snapshot())
	await _barrier("rule-state-" + key)
	var expected: Dictionary = _read("rule-state-" + key)
	check(await _until(func(): return world._biome_rules.phase == expected_phase and world._biome_rules.revision == int(expected.revision)), "Native world RPC delivers the host's " + expected_phase + " phase: " + key)
	var actual := world._biome_rules.snapshot()
	check(actual.get("shape", {}) == expected.get("shape", {}) and actual.get("event", -1) == expected.get("event", -2), "Host and joiner use identical committed geometry and event: " + key)
	check(actual.get("mode") == expected.get("mode") and actual.get("fragments") == expected.get("fragments") and actual.get("bounds_size") == expected.get("bounds_size"), "Production state keeps room mode, fragment policy and effective bounds identical: " + key)
	return expected

func _native_enemy(id: int) -> NATIVE_ENEMY:
	return EnemyReplicationService.enemy_nodes_by_id.get(id) as NATIVE_ENEMY

func _storm_transport_and_damage() -> void:
	await _enter_biome_room("storm_reach", "storm")
	if role == "host":
		var candidate := _living()[0]
		_write("storm-enemy-id", int(candidate.get_meta("network_enemy_id", 0)))
	await _barrier("storm-enemy-selected")
	var enemy_id := int(_read("storm-enemy-id"))
	check(await _until(func(): return is_instance_valid(_native_enemy(enemy_id))), "The same native enemy exists in both processes")
	var enemy := _native_enemy(enemy_id)
	if not is_instance_valid(enemy):
		return
	enemy.set_max_health_and_current(500, 500)
	var committed := Vector2(-160, -40)
	for actor in world._get_multiplayer_player_nodes():
		actor.position = committed
	enemy.position = committed
	await _barrier("storm-bait-positioned")
	storm_warning = await _advance_network_phase("storm-warning", "warning")
	check((storm_warning.shape as Dictionary).get("center", Vector2.INF) == committed, "Storm's transmitted warning locks the targeted peer's actual position")
	check(enemy.get_current_health() == 500 and world.player.get_current_health() == 200, "Visible warning does not damage the enemy or either local owner")
	world._get_player_for_peer(1).position = Vector2(370, 260)
	await _barrier("storm-target-escaped")
	storm_active = await _advance_network_phase("storm-active", "active")
	check(storm_active.shape == storm_warning.shape, "Lightning strikes the committed point after its target escapes")
	if role == "host":
		check(enemy.get_current_health() == 450, "The native environmental strike damages the baited enemy once")
		check(world._get_player_for_peer(1).get_current_health() == 200 and world._get_player_for_peer(client_id).get_current_health() < 200, "Host health authority spares the escaping player and damages the player still under lightning")
		check(world._get_player_for_peer(client_id).get_last_damage_event().get("ability", "") == "biome_storm_reach", "Native player damage retains the biome ability attribution")
		world._sync_enemy_states.rpc([{"enemy_id": enemy_id, "health": enemy.get_current_health(), "position": enemy.position}], world.active_room_enemy_count)
	await _barrier("storm-health-sent")
	check(await _until(func(): return enemy.get_current_health() == 450 and world._get_player_for_peer(client_id).get_current_health() < 200), "Native enemy/player health replication delivers the authoritative strike")
	var enemy_before := enemy.get_current_health()
	var player_before := world.player.get_current_health()
	world._tick_biome_rules(0.01)
	check(enemy.get_current_health() == enemy_before and world.player.get_current_health() == player_before, "Neither another host frame nor a client's visual tick repeats lightning damage")
	await _barrier("storm-no-repeat")
	if role == "client":
		var revision_before := world._biome_rules.revision
		world._tick_biome_rules(100.0)
		check(world._biome_rules.revision == revision_before and enemy.get_current_health() == enemy_before and world.player.get_current_health() == player_before, "A joiner cannot invent the next phase or damage native actors")
	await _barrier("storm-client-authority")

func _reject_foreign_rule_states() -> void:
	var before := world._biome_rules.snapshot()
	if role == "host":
		for key: String in ["run", "room", "id"]:
			var foreign := storm_active.duplicate(true)
			foreign["revision"] = int(storm_active.revision) + 100
			foreign[key] = int(storm_active.room) + 2 if key == "room" else "foreign-" + key
			world._sync_biome_rule_state.rpc(foreign)
		world._sync_biome_rule_state.rpc(storm_warning)
		world._sync_biome_rule_state.rpc(storm_active)
		for alteration: Dictionary in [{"mode": "invalid"}, {"mode": "assistance"}, {"fragments": true}, {"bounds_size": Vector2(NAN, 540)}, {"bounds_size": Vector2(9000, 9000)}]:
			var malformed := storm_active.duplicate(true)
			malformed.merge(alteration, true)
			malformed.revision = int(storm_active.revision) + 200
			world._sync_biome_rule_state.rpc(malformed)
	await _barrier("foreign-rule-states")
	check(world._biome_rules.snapshot() == before, "Wrong run/room/biome, stale warning and duplicate active packets cannot change live state")
	check(world._pending_biome_rule_state.is_empty(), "Rejected future-room packets do not pollute the pending room state")

func _future_room_warning_and_haunt() -> void:
	if role == "host":
		world.encounter_profile_builder.set_active_biome(BIOMES.get_biome("haunt"))
		future_haunt_profile = world.encounter_profile_builder.build_debug_encounter_profile("crossfire", 5)
		var next_room := world.get_current_room_sync_id() + 1
		var early := RULES.new()
		world.add_child(early)
		early.initialize(world)
		early.configure({"id": "haunt", "obstacles": CONTRACTS.profile_obstacle_layout(future_haunt_profile)}, CONTRACTS.profile_room_size(future_haunt_profile), INTERACTIONS.current_run(), next_room, next_room)
		early.tick(100.0, true, [], [], true)
		future_haunt_warning = early.snapshot()
		early.free()
		_write("future-haunt-warning", future_haunt_warning)
		world._sync_biome_rule_state.rpc(future_haunt_warning)
	await _barrier("future-haunt-arrived")
	future_haunt_warning = _read("future-haunt-warning")
	if role == "client":
		check(world._pending_biome_rule_state == future_haunt_warning and world._biome_rules.rule_id == "storm_reach", "A warning one room ahead waits without replacing the current room")
	if role == "host":
		for alteration: Dictionary in [{"mode": "invalid"}, {"fragments": "true"}, {"bounds_size": Vector2(-1, 540)}, {"shape": {"kind": "circle", "center": Vector2.ZERO, "radius": INF}}]:
			var malformed := future_haunt_warning.duplicate(true)
			malformed.merge(alteration, true)
			malformed.revision = int(future_haunt_warning.revision) + 200
			world._sync_biome_rule_state.rpc(malformed)
	await _barrier("malformed-future-rule")
	if role == "client":
		check(world._pending_biome_rule_state == future_haunt_warning, "Malformed newer future-room packets cannot poison an already queued valid warning")
	await _enter_biome_room("haunt", "haunt", future_haunt_profile)
	if role == "client":
		check(world._pending_biome_rule_state.is_empty() and world._biome_rules.phase == "warning" and world._biome_rules.shape == future_haunt_warning.shape, "Native room entry consumes its queued warning with the correct geometry")
	var warning := await _advance_network_phase("haunt-warning", "warning")
	var patch := _floor_point(warning.shape, true)
	for actor in world._get_multiplayer_player_nodes():
		actor.position = patch
		actor.external_slow_left = 0.0
		actor.external_slow_mult = 1.0
	await _barrier("haunt-players-in-patch")
	await _advance_network_phase("haunt-active", "active")
	world._tick_biome_rules(0.01)
	check(world.player.external_slow_left > 0.0 and is_equal_approx(world.player.external_slow_mult, 0.6), "Each process applies Haunt Slow to its own native movement owner")
	var other := world._get_player_for_peer(client_id if role == "host" else 1) as PLAYER
	check(other.external_slow_left == 0.0, "A process does not overwrite the other peer avatar's owned movement modifier")
	check(world.player.get_current_health() == 200, "Haunt's shared patch changes movement without dealing damage")
	await _barrier("haunt-owner-slow")
	if role == "client":
		world._tick_biome_rules(100.0)
		world.player._update_external_slow(0.25)
		world._tick_biome_rules(0.1)
		check(world.player.external_slow_left == 0.0 and world.player.external_slow_mult == 1.0, "A missing expiry packet cannot indefinitely reapply a joiner's Slow")
	await _barrier("haunt-local-expiry")

func _ordinary_rule_pair(id: String) -> void:
	await _enter_biome_room(id, "matrix-" + id)
	if id == "shatterfield":
		check(world._biome_rules.phase == "idle" and world._biome_rules.shape.is_empty(), "Shatterfield uses physical cover interactions without a second timed hazard")
		check(world._arena_cover.contacts_left(2) == 3 and world._arena_cover.contacts_left(3) == 3, "Native Shatterfield entry carries both breakable inner columns")
		await _barrier("matrix-shatterfield-inspected")
		return
	var warning := await _advance_network_phase(id + "-warning", "warning")
	var safe_point := _floor_point(warning.shape, false)
	for actor in world._get_multiplayer_player_nodes():
		actor.position = safe_point
	await _barrier(id + "-safe-position")
	var active := await _advance_network_phase(id + "-active", "active")
	check(active.shape == warning.shape and world.player.get_current_health() == 200, "Warning geometry remains true at activation and its safe route protects the player: " + id)
	await _barrier(id + "-active-inspected")

func _floor_point(geometry: Dictionary, affected: bool) -> Vector2:
	var layout: Array[Dictionary] = world.renderer.obstacle_layout
	var arena_bounds := Rect2(-world.current_effective_room_size * 0.5, world.current_effective_room_size).grow(-14.0)
	for x in range(-400, 401, 20):
		for y in range(-280, 281, 20):
			var point := Vector2(x, y)
			if not arena_bounds.has_point(point):
				continue
			if RULES.geometry_contains(geometry, point, 14.0) != affected:
				continue
			var clear := true
			for obstacle: Dictionary in layout:
				if point.distance_to(obstacle.pos) < float(obstacle.radius) + 14.0:
					clear = false
					break
			if clear:
				return point
	check(false, "Authored terrain leaves the requested affected/safe inspection point")
	return Vector2.ZERO

func _compact_mission_entry() -> void:
	var stale := world._biome_rules.snapshot()
	var profile: Dictionary = {}
	if role == "host":
		world.encounter_profile_builder.set_active_biome(BIOMES.get_biome("storm_reach"))
		profile = world.encounter_profile_builder.build_objective_profile(5, "pulse_window")
	await _enter_biome_room("storm_reach", "compact-pulse", profile)
	check(world._biome_rules.snapshot().mode == "compact" and world._biome_rules.shape.is_empty(), "Native Mission entry replaces the old hazard with its own compact biome rule")
	if role == "host":
		world._sync_biome_rule_state.rpc(stale)
	await _barrier("mission-stale-state")
	check(world._biome_rules.phase == "recovery" and world._biome_rules.shape.is_empty() and world._pending_biome_rule_state.is_empty(), "Late ordinary-room state cannot start an old hazard inside the new Mission")
	var warning := await _advance_network_phase("mission-warning", "warning")
	check(warning.mode == "compact" and float(warning.duration) >= 1.8 and warning.bounds_size == world.current_effective_room_size, "Mission uses its longer warning and actual current arena size on both peers")
	world.pause_menu_controller.open()
	var held := world._biome_rules.snapshot()
	world._tick_biome_rules(100.0)
	check(world._biome_rules.snapshot() == held, "Native combat pause preserves the adapted warning without advancing damage")
	world.pause_menu_controller.close()
	for actor in world._get_multiplayer_player_nodes():
		actor.set_physics_process(false)
	for enemy in _living():
		enemy.set_physics_process(false)
	world.hud.refresh(world._get_hud_state(), world.player)
	check(not String(world._get_hud_state().get("active_biome_rule_hint", "")).is_empty(), "Mission HUD retains the active biome instruction")
	await _barrier("compact-mission-inspected")

func _assistance_apex_damage() -> void:
	var profile: Dictionary = {}
	if role == "host":
		world.encounter_profile_builder.set_active_biome(BIOMES.get_biome("storm_reach"))
		profile = world.encounter_profile_builder.build_debug_encounter_profile("apex_breakwater", 8)
	await _enter_biome_room("storm_reach", "assistance-apex", profile)
	check(world._biome_rules.snapshot().mode == "assistance", "Native Apex room chooses assistance on both peers")
	if role == "host":
		_write("assistance-enemy-id", int(_living()[0].get_meta("network_enemy_id", 0)))
	await _barrier("assistance-enemy-selected")
	var enemy_id := int(_read("assistance-enemy-id"))
	var enemy := _native_enemy(enemy_id)
	check(is_instance_valid(enemy), "Both assistance peers map the actual native Apex")
	if not is_instance_valid(enemy):
		return
	enemy.set_max_health_and_current(500, 500)
	enemy.position = Vector2(-120, -40)
	for actor in world._get_multiplayer_player_nodes():
		actor.position = enemy.position
	await _barrier("assistance-overlap-positioned")
	var warning := await _advance_network_phase("assistance-warning", "warning")
	check(warning.mode == "assistance" and RULES.geometry_contains(warning.shape, enemy.position), "Assistance commits its warning over the native foe even while players overlap it")
	check(enemy.get_current_health() == 500 and world.player.get_current_health() == 200, "Assistance warning preserves normal warning-before-damage timing")
	await _advance_network_phase("assistance-active", "active")
	if role == "host":
		check(enemy.get_current_health() < 500, "Host assistance deals real damage through the native Apex health boundary")
		_write("assistance-health", enemy.get_current_health())
		world.enemy_state_sync_broadcaster.tick(1.0)
	await _barrier("assistance-health-sent")
	check(await _until(func(): return enemy.get_current_health() == int(_read("assistance-health"))), "Existing enemy runtime transport delivers the host's assistance damage")
	for actor in world._get_multiplayer_player_nodes():
		check(actor.get_current_health() == 200 and actor.external_slow_left == 0.0, "Assistance leaves both overlapping player owners unharmed and unslowed")
	var health_before := enemy.get_current_health()
	world._tick_biome_rules(0.01)
	check(enemy.get_current_health() == health_before, "Neither host continuation nor replica presentation repeats one assistance strike")
	await _barrier("assistance-authority-inspected")

func _cover_free_fragment_entry() -> void:
	var profile: Dictionary = {}
	if role == "host":
		world.encounter_profile_builder.set_active_biome(BIOMES.get_biome("shatterfield"))
		profile = world.encounter_profile_builder.build_objective_profile(5, "pulse_window")
	await _enter_biome_room("shatterfield", "fragments-pulse", profile)
	check(not world._arena_cover.has_brittle_cover() and world._biome_rules.snapshot().fragments, "Cover-free Shatterfield Mission entry enables its own fragment rule on both peers")
	var warning := await _advance_network_phase("fragments-warning", "warning")
	check(warning.fragments and warning.shape.kind == "circle" and float(warning.duration) >= 1.8, "Fragment mode transports a complete committed warning before becoming active")
	var safe := _floor_point(warning.shape, false)
	for actor in world._get_multiplayer_player_nodes():
		actor.position = safe
	await _barrier("fragments-safe-position")
	var active := await _advance_network_phase("fragments-active", "active")
	check(active.shape == warning.shape and world.player.get_current_health() == 200, "Fragment impact uses exactly its warning and leaves the shown safe floor safe")
	await _barrier("fragments-inspected")

func _finish_rule_fixture() -> void:
	MultiplayerSessionManager.session_connected = false
	PlayerReplicationService.player_nodes.clear()
	EnemyReplicationService.unbind_world(world)
	current_scene = null
	world.queue_free()
	world = null
	barrier.queue_free()
	await process_frame
	await process_frame
	transport.close()
	get_multiplayer().multiplayer_peer = null
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await audio_retirement.wait_until_retired(self), "Native audio retires after both biome-rule Main scenes")
	var report := FileAccess.open(prefix + "-" + role + ".json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"role": role, "checks": checks, "failures": failures}, "\t"))
	report.close()
	print("[ENet] %s: %d checks, %d failures" % [role, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

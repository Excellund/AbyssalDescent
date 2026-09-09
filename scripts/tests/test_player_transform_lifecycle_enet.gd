extends SceneTree
## Actual Main transitions/retries exercise inherited native transform RPCs and retired-avatar cleanup.
const MAIN := preload("res://scenes/Main.tscn")
const WORLD := preload("res://scripts/world_generator.gd")
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const PROFILE := preload("res://scripts/core/profile_persistence_store.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const BREAKWATER := preload("res://scripts/enemy_breakwater.gd")
const RETIREMENT := preload("res://scripts/tests/fixture_audio_retirement.gd")
const PLAYER := preload("res://scripts/player.gd")
class ActiveReplication extends "res://scripts/player_replication_service.gd":
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

var audio_retirement := RETIREMENT.new()
var role: String
var prefix: String
var transport: ENetMultiplayerPeer
var world: WORLD
var failures: Array[String] = []
var checks := 0
var cases := ["Queued held", "Blast held", "Orbit held"]
var prepared_cooldowns := Vector2.ZERO

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _until(predicate: Callable, seconds: float = 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false

func _write(key: String, value: Variant) -> void:
	var file := FileAccess.open(prefix + "-" + key, FileAccess.WRITE)
	file.store_var(value)
	file.close()

func _read(key: String) -> Variant:
	return FileAccess.open(prefix + "-" + key, FileAccess.READ).get_var()

func _has(key: String) -> bool:
	return FileAccess.file_exists(prefix + "-" + key)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or args.size() != 4:
		quit(1)
		return
	PlayerReplicationService.set_script(ActiveReplication)
	PlayerReplicationService.set_process(false)
	PlayerReplicationService.set_physics_process(false)
	role = args[1]
	prefix = args[3]
	ProjectSettings.set_setting("application/config/version", "dev-room-layout-enet")
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.multiplayer_session_id = ""
	RunContext.active_ascension_loadout = []
	RunContext.run_mode = ENUMS.RunMode.STANDARD
	RunContext.selected_character_id = "bastion"
	RunContext.current_difficulty_tier = 1
	RunContext.clear_resume_saved_run_request()
	RunContext.clear_active_run()
	MultiplayerSessionManager.session_connected = false
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var profiles := PROFILE.new()
	var profile := profiles.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	profiles.save_profile(profile)
	node_added.connect(audio_retirement.observe_node)
	node_added.connect(_observe_main)
	world = MAIN.instantiate() as WORLD
	world.name = "World"
	world.get_node("DebugSettings").enabled = false
	root.add_child(world)
	current_scene = world
	var ui: Node = world.reward_selection_ui
	var choice: Dictionary = ui.boon_choices.front().duplicate(true)
	ui.close_selection()
	ui.reward_selected.emit(choice, ENUMS.RewardMode.ARCANA, true)
	world.set_process(false)
	world.set_physics_process(false)
	transport = ENetMultiplayerPeer.new()
	if role == "host":
		transport.set_bind_ip("127.0.0.1")
		check(transport.create_server(int(args[2]), 1) == OK, "Host binds actual isolated loopback ENet")
	else:
		check(transport.create_client("127.0.0.1", int(args[2])) == OK, "Joiner connects on actual separate ENet process")
	get_multiplayer().multiplayer_peer = transport
	if role == "host":
		_write("ready", true)
	check(await _until(func(): return transport.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED), "ENet becomes connected")
	check(await _until(func(): return get_multiplayer().get_peers().size() == 1), "Both real peers are visible")
	MultiplayerSessionManager._multiplayer = get_multiplayer()
	MultiplayerSessionManager.session_connected = true
	MultiplayerSessionManager.is_host_peer = role == "host"
	MultiplayerSessionManager.local_peer_id = get_multiplayer().get_unique_id()
	MultiplayerSessionManager.connected_peers = {1: {}}
	for id in get_multiplayer().get_peers():
		MultiplayerSessionManager.connected_peers[id] = {}
	MultiplayerSessionManager.connected_peers[get_multiplayer().get_unique_id()] = {}
	PlayerReplicationService.player_nodes.clear()
	PlayerReplicationService.local_peer_id = get_multiplayer().get_unique_id()
	world.player.player_id = get_multiplayer().get_unique_id()
	world.player.is_local_player = true
	PlayerReplicationService.register_player(world.player.player_id, world.player)
	world.is_multiplayer = true
	world._setup_multiplayer_remote_players()
	for actor in world._get_multiplayer_player_nodes():
		actor.set_physics_process(false)
	world.encounter_profile_builder.set_use_multiplayer_difficulty_config(true)
	world.encounter_profile_builder.set_multiplayer_party_size(2)
	_write("built-" + role, true)
	check(await _until(func(): return _has("built-host") and _has("built-client")), "Both actual Main instances are initialized before profile RPCs")
	for index in cases.size():
		var key := str(index)
		await _arm_gesture(index)
		_write("armed-" + role + "-" + key, true)
		check(await _until(func(): return _has("armed-host-" + key) and _has("armed-client-" + key)), "Both real owners hold pending input before transition")
		if role == "host":
			var encounter := CONTRACTS.profile(cases[index], Vector2(1160, 860), true, 2, 0, 0, 0)
			var door := CONTRACTS.standard_encounter_door_option(encounter)
			world._choose_door(door)
			var state := world._build_progress_sync_state()
			world._sync_chosen_door.rpc(door, state)
			_write("case-" + key, {"room": world.get_current_room_sync_id(), "layout": CONTRACTS.profile_obstacle_layout(encounter), "count": CONTRACTS.profile_total_enemy_count(encounter)})
		else:
			check(await _until(func(): return _has("case-" + key)), "Host dispatches native chosen-door RPC " + key)
		var expected: Dictionary = _read("case-" + key)
		check(await _until(func(): return world.current_room_label == cases[index] and world.get_current_room_sync_id() == int(expected.room) and _living().size() == int(expected.count)), "Real room RPC and spawn replication enter " + cases[index])
		check(world.encounter_intro_grace_active and not world.choosing_next_room, "Declared encounter remains awaiting play rather than clearing before combat")
		check(world.active_room_enemy_count == int(expected.count), "World count matches the host-declared actual spawn count")
		check(world.renderer.obstacle_layout == expected.layout and world.enemy_spawner.obstacle_circles == expected.layout, "Host geometry survives actual room RPC into renderer/spawner")
		check(world._active_obstacle_nodes.size() == expected.layout.size(), "Same number of real collision bodies exists after native transition")
		for obstacle_index in expected.layout.size():
			check(world._active_obstacle_nodes[obstacle_index].global_position == expected.layout[obstacle_index].pos, "Real collision body preserves exact host world position")
		await _check_reset(index)
		await _exchange_transforms(key)
		_write("checked-" + role + "-" + key, true)
		check(await _until(func(): return _has("checked-host-" + key) and _has("checked-client-" + key)), "Both peers inspect the same room before advancing")
	await _retry_transform_check()
	await _initial_reward("first")
	await _replay_prior_run()
	_write("finished-" + role, true)
	check(await _until(func(): return _has("finished-host") and _has("finished-client")), "Both peers finish before teardown")
	MultiplayerSessionManager.session_connected = false
	PlayerReplicationService.player_nodes.clear()
	EnemyReplicationService.unbind_world(world)
	current_scene = null
	world.queue_free()
	world = null
	await process_frame
	await process_frame
	transport.close()
	get_multiplayer().multiplayer_peer = null
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await audio_retirement.wait_until_retired(self), "Native audio playback retires after scene teardown")
	var file := FileAccess.open(prefix + "-" + role + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"role": role, "checks": checks, "failures": failures}, "\t"))
	file.close()
	print("[ENet] %s: %d checks, %d failures" % [role, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _arm_gesture(index: int) -> void:
	Input.action_release("attack")
	Input.action_release("dash")
	await physics_frame
	await process_frame
	var actor: Node = world.player
	world._exit_encounter_intro_grace()
	actor.set_physics_process(false)
	actor.set_max_health_and_current(10000, 10000)
	actor.apply_trial_power("blast_drive")
	actor.apply_trial_power("razor_orbit")
	actor.apply_trial_power("sovereigns_double")
	actor._refresh_combat_input_release()
	actor.attack_cooldown_left = 0.0
	actor.attack_lock_time_left = 0.0
	actor.dash_cooldown_left = 0.0
	actor.arcana_motion.cancel()
	actor.arcana_motion.tick(0.0)
	actor._set_dash_phasing(false)
	actor.dash_remaining_distance = 0.0
	actor.dash_time_left = 0.0
	actor.dash_phase_release_left = 0.0
	if index == 0:
		Input.action_press("dash")
		actor._try_start_dash(Vector2.RIGHT)
		Input.action_press("attack")
		actor._try_attack_input()
		check(actor.queued_attack_after_dash and actor.dash_phasing_active and not actor.dash_enemy_exceptions.is_empty(), "Actual dash owns native enemy exceptions and a queued held attack before reset")
	elif index == 1:
		Input.action_press("attack")
		actor._try_attack_input()
		actor.arcana_motion.tick(0.65)
		check(actor.arcana_motion.charge_hold >= 0.65, "Actual successful held attack fully arms Blast before reset")
	else:
		Input.action_press("dash")
		var anchor := Node2D.new()
		world.add_child(anchor)
		anchor.position = actor.position + Vector2(0, 100)
		anchor.add_to_group("arena_columns")
		actor.arcana_motion.start_orbit(anchor)
		Input.action_press("attack")
		actor._try_attack_input()
		actor.arcana_motion.tick(0.35)
		check(actor.arcana_motion.owns_movement() and actor.arcana_motion.charge_hold >= 0.25, "Actual Orbit plus held Blast is armed before reset")
	prepared_cooldowns = Vector2(actor.attack_cooldown_left, actor.dash_cooldown_left)
	await physics_frame
	await process_frame

func _check_reset(index: int) -> void:
	var actor: Node = world.player
	var attacks: int = actor.attack_combo_counter
	var charges: int = actor.arcana_motion.blast_charges
	check(not actor.queued_attack_after_dash and actor.dash_remaining_distance == 0.0 and actor.dash_time_left == 0.0, "Room RPC clears queued attack and old dash on this actual owner")
	check(not actor.dash_phasing_active and actor._dash_damage_immune_left == 0.0 and actor.dash_enemy_exceptions.is_empty(), "Reset clears old dash immunity and exception registry")
	var party_exceptions: Array = actor.get_collision_exceptions()
	check(party_exceptions.size() == 1 and party_exceptions[0] is PLAYER, "Actual native exceptions preserve only the living party body")
	check(not actor.arcana_motion.owns_movement() and actor.arcana_motion.charge_hold < 0.0 and actor.arcana_motion.dash_hold < 0.0, "Old Orbit/Blast holds and anchor cannot survive room reset")
	check(actor.boss_combinations.shade_hits == 0 and not actor.boss_combinations.dash_origin.is_finite(), "Forced room reset cannot award a movement-completion shade")
	check(is_equal_approx(actor.attack_cooldown_left, prepared_cooldowns.x) and is_equal_approx(actor.dash_cooldown_left, prepared_cooldowns.y), "Room reset preserves spent Attack and Dash cooldowns")
	check(actor._combat_actions_awaiting_release.has(&"attack") and (index == 1 or actor._combat_actions_awaiting_release.has(&"dash")), "Held actions require release in new arena")
	var before: Vector2 = actor.position
	for frame in 20:
		actor._physics_process(1.0/60.0)
	check(actor.position.distance_to(before) < 0.01, "Frozen survey does not advance previous-room movement")
	world._signal_local_player_ready()
	check(await _until(func(): return not world.encounter_intro_grace_active), "Actual owner readiness uses host/all-ready flow")
	for frame in 45:
		actor._physics_process(1.0/60.0)
	check(actor.attack_combo_counter == attacks and actor.arcana_motion.blast_charges == charges and not actor.arcana_motion.owns_movement(), "Still-held buttons cannot attack, launch, hook, or spend charge after readiness")
	Input.action_release("attack")
	Input.action_release("dash")
	await physics_frame
	await process_frame
	actor._refresh_combat_input_release()
	actor.arcana_motion.tick(0.01)
	check(actor.attack_combo_counter == attacks and actor.arcana_motion.blast_charges == charges, "Eventual release cannot fire a canceled Blast")
	actor.attack_cooldown_left = 0.0
	actor.attack_lock_time_left = 0.0
	Input.action_press("attack")
	actor._try_attack_input()
	check(actor.attack_combo_counter == attacks + 1 and actor.arcana_motion.charge_hold >= 0.0, "A fresh successful Attack rearms normally after release")
	Input.action_release("attack")

func _living() -> Array[Node]:
	var out: Array[Node] = []
	for enemy in get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and not enemy.is_dead():
			out.append(enemy)
	return out

func _observe_main(node: Node) -> void:
	if node is WORLD:
		var settings := node.get_node_or_null("DebugSettings")
		if settings != null:
			settings.enabled = false

func _exchange_transforms(key: String) -> void:
	var own_id := get_multiplayer().get_unique_id()
	var other_id := int(get_multiplayer().get_peers()[0])
	var target := Vector2(250.0, 25.0) if role == "host" else Vector2(-250.0, -25.0)
	var expected := -target
	world.player.position = target
	var sequence_before := int(PlayerReplicationService._outgoing_transform_sequence)
	PlayerReplicationService._sync_all_player_positions()
	check(PlayerReplicationService._outgoing_transform_sequence > sequence_before, "Changed actual room broadcasts the owner's first transform " + key)
	_write("sent-" + role + "-" + key, true)
	check(await _until(func(): return _has("sent-host-" + key) and _has("sent-client-" + key)), "Both owners send in actual new room " + key)
	check(await _until(func():
		PlayerReplicationService._sync_all_player_positions()
		return PlayerReplicationService._remote_target_positions.get(other_id, Vector2.INF) == expected), "Actual bound room IDs accept the other owner after transition " + key)
	check(world.player.position == target, "Native call_local keeps the owner's chosen transform " + key)
	var remote: Node2D = PlayerReplicationService.player_nodes[other_id]
	PlayerReplicationService._interpolate_remote_players(1.0)
	check(remote.position.distance_to(expected) < 0.1, "Unchanged smoothing reaches the actual replicated sample " + key)
	_write("received-" + role + "-" + key, true)
	check(await _until(func():
		PlayerReplicationService._sync_all_player_positions()
		return _has("received-host-" + key) and _has("received-client-" + key)), "Both owners finish transform observation " + key)

func _retry_transform_check(key: String = "first", exchange: bool = true, tick_service: bool = true) -> void:
	Input.action_release("attack")
	Input.action_release("dash")
	RunContext.set_multiplayer_session("fixture-transform-retry", role == "host")
	MultiplayerSessionManager.session_id = "fixture-transform-retry"
	var old_id := world.get_instance_id()
	var old_sequence := int(PlayerReplicationService._outgoing_transform_sequence)
	var other_id := int(get_multiplayer().get_peers()[0])
	var old_other: WeakRef = weakref(PlayerReplicationService.player_nodes[other_id])
	_write("retry-ready-" + role + "-" + key, true)
	check(await _until(func(): return _has("retry-ready-host-" + key) and _has("retry-ready-client-" + key)), "Both peers reach actual retry barrier")
	PlayerReplicationService.multiplayer_session_manager = MultiplayerSessionManager
	PlayerReplicationService.set_process(tick_service)
	if role == "host":
		world._start_multiplayer_retry_run.rpc()
	check(await _until(func(): return is_instance_valid(current_scene) and current_scene is WORLD and current_scene.get_instance_id() != old_id and current_scene.is_node_ready()), "Actual in-session retry loads another complete Main scene")
	world = current_scene as WORLD
	PlayerReplicationService.set_process(false)
	world.set_process(false)
	world.set_physics_process(false)
	world.run_summary_recorder.initialize(false)
	for actor in world._get_multiplayer_player_nodes():
		actor.set_physics_process(false)
		var pairs: Array = actor.get_collision_exceptions()
		check(pairs.size() == 1 and is_instance_valid(pairs[0]) and pairs[0] is PLAYER and pairs[0].get_parent() == world, "Retry preserves only the live party collision exception")
	check(world.is_multiplayer and PlayerReplicationService.player_nodes.size() == 2 and old_other.get_ref() == null, "Retry replaces both avatars while retaining the two-peer session")
	check(EnemyReplicationService.world_generator == world, "Retry binds the new World for transform room identity")
	check(PlayerReplicationService._outgoing_transform_sequence >= old_sequence, "Scene reload preserves the service's monotonically increasing send sequence")
	check(is_instance_valid(PlayerReplicationService.player_nodes.get(other_id)) and PlayerReplicationService.player_nodes[other_id].get_parent() == world, "Replacement remote avatar belongs to current actual World")
	_write("retry-built-" + role + "-" + key, true)
	check(await _until(func(): return _has("retry-built-host-" + key) and _has("retry-built-client-" + key)), "Both new scenes register before sending new-run transforms")
	if exchange:
		await _exchange_transforms("retry-starting-chamber-" + key)


func _initial_reward(key: String) -> void:
	var ui: Node = world.reward_selection_ui
	check(await _until(func(): return not ui.boon_choices.is_empty() and world._is_reward_selection_active()), "Actual offered starting reward is ready " + key)
	var choice: Dictionary = ui.boon_choices.front().duplicate(true)
	ui.close_selection()
	ui.reward_selected.emit(choice, ENUMS.RewardMode.ARCANA, true)
	check(await _until(func(): return world.get_current_room_sync_id() == 1 and world.encounter_intro_grace_active and not world._is_reward_selection_active()), "Actual reward completion enters the synchronized first room " + key)
	_write("initial-room-" + role + "-" + key, true)
	check(await _until(func(): return _has("initial-room-host-" + key) and _has("initial-room-client-" + key)), "Both owners reach the same actual first room " + key)

func _replay_prior_run() -> void:
	var own_id := get_multiplayer().get_unique_id()
	var other_id := int(get_multiplayer().get_peers()[0])
	var old_room := world.get_current_room_sync_id()
	PlayerReplicationService._outgoing_transform_sequence += 1
	var delayed_sequence := int(PlayerReplicationService._outgoing_transform_sequence)
	var old_position := Vector2(420.0, 180.0) if role == "host" else Vector2(-420.0, -180.0)
	check(await _until(func(): return GameStateReplicationService.get_current_run_sync_token().length() == 32), "Actual party handshake supplies the old run token with collection disabled")
	var old_token := GameStateReplicationService.get_current_run_sync_token()
	_write("delayed-captured-" + role, {"sequence": delayed_sequence, "room": old_room, "token": old_token})
	check(await _until(func(): return _has("delayed-captured-host") and _has("delayed-captured-client")), "Both owner packets are captured before the next actual retry")
	await _retry_transform_check("late", false, false)
	await _initial_reward("late")
	check(world.get_current_room_sync_id() == old_room, "Actual retry returns to the same first-room identity as the delayed sample")
	check(await _until(func(): return GameStateReplicationService.get_current_run_sync_token().length() == 32 and GameStateReplicationService.get_current_run_sync_token() != old_token), "Actual retry creates a different run token even with collection disabled")
	var other_role := "client" if role == "host" else "host"
	var captured: Dictionary = _read("delayed-captured-" + other_role)
	check(int(captured.sequence) > int(PlayerReplicationService._last_received_transform_sequence.get(other_id, 0)), "The delayed prior-run sample is unseen and would pass sequence ordering")
	var expected: Vector2 = PlayerReplicationService._remote_target_positions[other_id]
	PlayerReplicationService._sync_player_transform.rpc(own_id, old_position, 0.5, delayed_sequence, old_room, old_token)
	_write("replayed-" + role, true)
	check(await _until(func(): return _has("replayed-host") and _has("replayed-client")), "Both delayed prior-run samples are sent before any fresh-owner update")
	await create_timer(0.15).timeout
	var observed: Vector2 = PlayerReplicationService._remote_target_positions[other_id]
	check(observed == expected, "An unseen prior-run sample cannot restore old position when retry reuses the room ID")
	_write("replay-observed-" + role, true)
	check(await _until(func(): return _has("replay-observed-host") and _has("replay-observed-client")), "Both peers inspect the delayed sample before fresh recovery")
	await _exchange_transforms("after-retry-replay")

extends SceneTree
## Two actual Main scenes. Only actor placement and the last-enemy clear are staged;
## all health/death/revive messages originate from native callbacks over loopback ENet.
const MAIN := preload("res://scenes/Main.tscn")
const WORLD := preload("res://scripts/world_generator.gd")
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const PROFILE := preload("res://scripts/core/profile_persistence_store.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const AUDIO_RETIREMENT := preload("res://scripts/tests/fixture_audio_retirement.gd")
var audio_retirement := AUDIO_RETIREMENT.new()
var role: String
var prefix: String
var transport: ENetMultiplayerPeer
var world: WORLD
var failures: Array[String] = []
var checks := 0
var client_id := 0

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
	role = args[1]
	prefix = args[3]
	node_added.connect(audio_retirement.observe_node)
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
	world.encounter_profile_builder.set_use_multiplayer_difficulty_config(true)
	world.encounter_profile_builder.set_multiplayer_party_size(2)
	_write("built-" + role, true)
	check(await _until(func(): return _has("built-host") and _has("built-client")), "Both actual Main instances are initialized before profile RPCs")
	PlayerReplicationService.multiplayer_session_manager = MultiplayerSessionManager
	world._setup_multiplayer_remote_players()
	client_id = int(get_multiplayer().get_peers()[0]) if role == "host" else get_multiplayer().get_unique_id()
	check(world._get_multiplayer_player_nodes().size() == 2, "Both real player bodies are registered on each peer")
	world.run_summary_recorder.initialize(false)
	world.run_summary_recorder.mark_run_start()
	check(await _until(func(): return GameStateReplicationService.get_current_run_sync_token().length() == 32), "Existing recorder handshake establishes the run token")
	_write("token-" + role, GameStateReplicationService.get_current_run_sync_token())
	await _barrier("tokens")
	check(_read("token-host") == _read("token-client"), "Native movement transport shares the authenticated run token")
	await _test_fall_and_clear(client_id, true, "same-frame")
	await _test_fall_and_clear(client_id, false, "joiner-falls")
	await _test_fall_and_clear(1, false, "host-falls")
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
	for _frame in range(8):
		await process_frame
	check(await audio_retirement.wait_until_retired(self), "Native scene audio retires before the ENet process exits")
	var file := FileAccess.open(prefix + "-" + role + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"role": role, "checks": checks, "failures": failures}, "\t"))
	file.close()
	print("[ENet] %s: %d checks, %d failures" % [role, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _barrier(key: String) -> void:
	_write(key + "-" + role, true)
	check(await _until(func(): return _has(key + "-host") and _has(key + "-client")), "Both peers reach " + key)

func _living() -> Array[Node]:
	var result: Array[Node] = []
	for enemy in get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and not enemy.is_dead():
			result.append(enemy)
	return result

func _settle_physics() -> void:
	await physics_frame
	await process_frame
	await physics_frame
	await process_frame

func _actor_state(actor: Node) -> Dictionary:
	var disabled_shapes: Array[bool] = []
	for shape in actor.find_children("*", "CollisionShape2D", true, false):
		disabled_shapes.append(shape.disabled)
	return {"health": actor.get_current_health(), "dead": actor.is_dead(),
		"alive": actor._is_alive_state, "removed": actor._combat_removed,
		"visible": actor.visible, "shapes_disabled": disabled_shapes}

func _check_actor_state(actor: Node, expected_dead: bool, key: String) -> void:
	var state := _actor_state(actor)
	check(state.health == (0 if expected_dead else 1), key + ": exact host health is shared")
	check(state.dead == expected_dead and state.alive == not expected_dead, key + ": health and life flag agree")
	check(state.removed == expected_dead and state.visible == not expected_dead, key + ": presence and visibility agree with life")
	var shapes: Array = state.shapes_disabled
	check(not shapes.is_empty() and shapes.all(func(value): return bool(value) == expected_dead), key + ": every actual body collider matches life after deferred updates")
	_write(key + "-state-" + role, state)
	print("[ENet] " + key + " " + role + ": " + JSON.stringify(state))

func _enter_room(key: String) -> void:
	var previous_room := world.get_current_room_sync_id()
	var label := "Revival " + key
	if role == "host":
		var profile := CONTRACTS.profile(label, Vector2(1160, 860), true, 1, 0, 0, 0)
		var option := CONTRACTS.standard_encounter_door_option(profile)
		CONTRACTS.door_option_set_position(option, Vector2(260, -220))
		world.door_options = [option]
		world.choosing_next_room = true
		world._sync_door_options.rpc(world.door_options, true, world.boss_unlocked, world._build_progress_sync_state())
	check(await _until(func():
		world.enemy_state_sync_receiver.flush_pending_door_syncs()
		return world.choosing_next_room and world.door_options.size() == 1 and CONTRACTS.profile_label(CONTRACTS.door_option_profile(world.door_options[0])) == label), key + ": both peers see the offered actual encounter")
	await _barrier("offered-" + key)
	if role == "client":
		world._request_use_door.rpc_id(1, world.door_options[0].duplicate(true))
	check(await _until(func(): return world.get_current_room_sync_id() > previous_room and world.current_room_label == label and _living().size() == 1), key + ": owner door request enters the host room and real enemy on both peers")
	world._signal_local_player_ready()
	check(await _until(func(): return not world.encounter_intro_grace_active), key + ": both owners Engage through existing ready RPCs")
	for actor in world._get_multiplayer_player_nodes():
		actor.set_physics_process(false)
	for enemy in _living():
		enemy.set_process(false)
		enemy.set_physics_process(false)
		enemy.global_position = Vector2(350, 250)
	world.enemy_spawner.set_process(false)
	await _settle_physics()
	await _barrier("engaged-" + key)

func _finish_rewards(key: String) -> void:
	check(await _until(func(): return world.reward_selection_ui.is_active()), key + ": actual room clear opens each owner's reward selection")
	world.reward_selection_ui.close_selection()
	world.reward_selection_ui.reward_skipped.emit(ENUMS.RewardMode.BOON, false)
	check(await _until(func():
		world.enemy_state_sync_receiver.flush_pending_door_syncs()
		return not world.reward_selection_ui.is_active() and world.choosing_next_room and not world.door_options.is_empty()), key + ": normal reward completion unlocks authoritative routes")
	await _barrier("reward-complete-" + key)

func _clear_final_enemy() -> void:
	_living()[0].health_state.take_damage(1000000)
	world._update_encounter_state()

func _test_fall_and_clear(fallen_id: int, same_frame: bool, key: String) -> void:
	await _enter_room(key)
	var fallen = world._get_player_for_peer(fallen_id)
	var survivor = world._get_player_for_peer(1 if fallen_id == client_id else client_id)
	if role == "host":
		for actor in world._get_multiplayer_player_nodes():
			actor.set_health(actor.get_max_health())
	check(await _until(func(): return fallen.get_current_health() == fallen.get_max_health() and survivor.get_current_health() == survivor.get_max_health()), key + ": host establishes full living party health")
	await _barrier("healthy-" + key)
	if role == "host":
		# Same-frame case deliberately places two ordinary outcomes together:
		# the joiner falls, then the final enemy dies before ENet can round-trip.
		# The client receives host HP0 and emits its native death callback;
		# there is no injected death RPC or locally repaired replica state here.
		fallen.health_state.set_health(0)
		if same_frame:
			_clear_final_enemy()
			check(not fallen.is_dead() and fallen._is_alive_state and fallen.visible, key + ": host immediately revives normally before any client reply")
			_write("cleared-" + key, true)
	if not same_frame:
		check(await _until(func(): return fallen.is_dead() and not fallen.visible), key + ": natural health/death callback reaches both peers")
		await _settle_physics()
		_check_actor_state(fallen, true, key + "-fallen")
		check(world._count_alive_players() == 1 and not world._run_outcome_coordinator.is_player_defeated(), key + ": living teammate keeps the encounter active")
		if role == "host":
			check(not _living()[0]._is_target_valid(fallen) and _living()[0]._is_target_valid(survivor), key + ": native enemy target eligibility retains only the survivor")
		await _barrier("fallen-observed-" + key)
		if role == "host":
			_clear_final_enemy()
			_write("cleared-" + key, true)
	check(await _until(func(): return _has("cleared-" + key) and not fallen.is_dead()), key + ": normal host clear and revival arrive")
	# Allow every ordinary reliable callback echo to round-trip. Check before
	# reward completion sends a build snapshot that could hide a stale life flag.
	await create_timer(0.4).timeout
	await _settle_physics()
	_check_actor_state(fallen, false, key + "-revived")
	check(world._count_alive_players() == 2 and survivor.get_current_health() == survivor.get_max_health(), key + ": revival preserves1HP rule and untouched living teammate")
	await _barrier("revived-observed-" + key)
	await _finish_rewards(key)
	await _enter_room(key + "-next")
	_check_actor_state(fallen, false, key + "-next-room")
	check(world._is_local_control_owner(world.player) and world.player.player_id == get_multiplayer().get_unique_id(), key + ": actual next-room entry retains local ownership")
	if role == "host":
		check(_living()[0]._is_target_valid(fallen) and _living()[0]._is_target_valid(survivor), key + ": both revived and surviving players are valid native enemy targets")
	await _move_revived_owner(fallen_id, key)
	if same_frame:
		await _reject_non_host_life_updates(fallen, key)
	if role == "host":
		_clear_final_enemy()
	await _finish_rewards(key + "-next")

func _reject_non_host_life_updates(fallen: Node, key: String) -> void:
	var before := _actor_state(fallen)
	if role == "client":
		# First use public production send methods as a joining owner, then
		# explicitly replay an old client's reliable death message and attempt
		# an unauthorized heal. These are separate from the natural race above.
		PlayerReplicationService.broadcast_player_died(client_id)
		PlayerReplicationService.broadcast_player_revived(client_id, 44.0)
		PlayerReplicationService._sync_player_alive_status.rpc_id(1, client_id, false)
		PlayerReplicationService._sync_player_revived.rpc_id(1, client_id, 55.0)
	await create_timer(0.2).timeout
	await _settle_physics()
	check(_actor_state(fallen) == before, key + ": joining sends and old-owner life messages cannot change authoritative revival")
	await _barrier("nonhost-rejected-" + key)

func _move_revived_owner(fallen_id: int, key: String) -> void:
	var actor = world._get_player_for_peer(fallen_id)
	if get_multiplayer().get_unique_id() == fallen_id:
		var before: Vector2 = actor.global_position
		Input.action_press("move_right")
		actor._physics_process(0.1)
		Input.action_release("move_right")
		check(actor.global_position.x > before.x and actor.velocity.x > 0, key + ": revived owner moves through actual Player physics and input")
		PlayerReplicationService._sync_all_player_positions()
		_write("moved-" + key, actor.global_position)
	check(await _until(func(): return _has("moved-" + key)), key + ": revived owner emits native transform sync")
	var expected: Vector2 = _read("moved-" + key)
	if get_multiplayer().get_unique_id() != fallen_id:
		check(await _until(func():
			PlayerReplicationService._interpolate_remote_players(0.1)
			return actor.global_position.distance_to(expected) < 1.0), key + ": normal authenticated transform reaches the other real peer")
	await _barrier("movement-observed-" + key)

extends "res://scripts/tests/test_peer_departure_enet.gd"
## Four real ENet processes; file barriers synchronize only fixture instructions.
## Game readiness, reward completion, retry and power cues use production RPCs.

class NetworkPlayer extends Player:
	func _broadcast_cue_event(event: String, payload: Dictionary, reliable: bool = false) -> void:
		if MultiplayerSessionManager.session_connected and player_id == PlayerReplicationService.local_peer_id:
			PlayerReplicationService.broadcast_cue_event(player_id, event, payload, reliable)

var party_roles := ["host", "client1", "client2", "client3"]
var roster: Dictionary = {}
var peer_refs: Dictionary = {}
var observed: Dictionary = {}
var target_enemy: Enemy
var owned_launch: RefCounted
var saved_checkpoint: Dictionary
var party_started := false

func _until(predicate: Callable) -> bool:
	# Several simultaneous Godot imports/launches can take over six seconds.
	# Only process startup gets extra time; gameplay waits keep the old limit.
	var deadline := Time.get_ticks_msec() + (6000 if party_started else 15000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await create_timer(0.02).timeout
	return false

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or args.size() != 4:
		push_error("Four-process departure fixture requires isolated profile/role/port/prefix")
		quit(1)
		return
	role = args[1]
	prefix = args[3]
	transport = ENetMultiplayerPeer.new()
	if role == "host":
		transport.set_bind_ip("127.0.0.1")
		check(transport.create_server(int(args[2]), 3) == OK, "Host opens an ephemeral loopback server for three joiners")
	else:
		check(transport.create_client("127.0.0.1", int(args[2])) == OK, "Separate joiner process opens its ENet transport")
	get_multiplayer().multiplayer_peer = transport
	if role == "host":
		_write("ready", true)
	var connected := await _until(func(): return transport.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)
	check(connected, "Actual ENet connection becomes ready")
	if not connected:
		await _finish_enet()
		return
	_write("peer-" + role, get_multiplayer().get_unique_id())
	if role == "host":
		var all_joined := await _until(func(): return get_multiplayer().get_peers().size() == 3 and _all_files("peer", party_roles))
		check(all_joined, "All three separate clients join the host")
		if not all_joined:
			await _finish_enet()
			return
		for key in party_roles:
			roster[key] = int(_read("peer-" + key))
		_write("roster", roster)
	else:
		var roster_ready := await _until(func(): return FileAccess.file_exists(prefix + "-roster"))
		check(roster_ready, "Host publishes the actual four-peer roster")
		if not roster_ready:
			await _finish_enet()
			return
		roster = _read("roster") as Dictionary
	var all_visible := await _until(func(): return get_multiplayer().get_peers().size() == 3)
	check(all_visible, "Each process observes all other live ENet peers")
	if not all_visible:
		await _finish_enet()
		return
	party_started = true
	_setup_four_party()
	await _barrier("built", party_roles)
	await _effects_and_first_departure()
	if role == "client2":
		await _close_departing_client()
		return
	var three := ["host", "client1", "client3"]
	await _verify_departure("client2", three)
	await _barrier("first_departure", three)
	await _reward_and_second_departure(three)
	if role == "client3":
		await _close_departing_client()
		return
	var two := ["host", "client1"]
	await _verify_departure("client3", two)
	check(await _until(func(): return (world as DepartureWorld).door_advances > 0 and not world.encounter_intro_grace_active), "Remaining players receive reward advance and arena-ready state over real RPCs")
	check(not world.player.encounter_input_frozen and world._reward_phase_coordinator.get_active_phase().is_empty(), "Neither reward nor arena survey remains stuck after the unready joiner leaves")
	await _barrier("ready_after_departure", two)
	for actor in actors:
		_fallen(actor)
	world._on_player_died()
	check(world._run_outcome_coordinator.is_player_defeated() and HISTORY.load_all().size() == 1, "Intentional remaining-party wipe reaches the existing outcome/history path once")
	await _barrier("defeated", two)
	world._request_multiplayer_retry_run()
	check(await _until(func(): return (world as DepartureWorld).retries == 1), "Votes from the two remaining real processes trigger exactly one coordinated retry")
	check(world._expected_retry_voter_ids().size() == 2, "Departed peer IDs cannot strand retry voting")
	check(RunContext.load_active_run() == saved_checkpoint and RunContext.consume_resume_saved_run_request(), "Co-op departures and retry preserve the isolated suspended solo save")
	await _barrier("finished", two)
	await _close_surviving_client()

func _setup_four_party() -> void:
	MultiplayerSessionManager.session_connected = false
	PlayerReplicationService.player_nodes.clear()
	HISTORY.clear_all()
	world = _create_world()
	world.name = "World"
	root.add_child(world)
	current_scene = world
	world.is_multiplayer = true
	world.combat_phase_coordinator = preload("res://scripts/core/combat_phase_coordinator.gd").new()
	world.player_flow_coordinator = preload("res://scripts/core/player_flow_coordinator.gd").new()
	world.objective_lifecycle_coordinator = preload("res://scripts/core/objective_lifecycle_coordinator.gd").new()
	world.difficulty_provider = preload("res://scripts/core/difficulty_scaling_provider.gd").new(world)
	world.hud = HUD.new()
	world.add_child(world.hud)
	MultiplayerSessionManager.peer_disconnected.connect(world._on_multiplayer_peer_disconnected)
	world.fixture_peer = get_multiplayer().get_unique_id()
	MultiplayerSessionManager._multiplayer = get_multiplayer()
	MultiplayerSessionManager.local_peer_id = world.fixture_peer
	MultiplayerSessionManager.is_host_peer = role == "host"
	MultiplayerSessionManager.connected_peers.clear()
	PlayerReplicationService.local_peer_id = world.fixture_peer
	for key in party_roles:
		var id := int(roster[key])
		MultiplayerSessionManager.connected_peers[id] = {}
		var actor := NetworkPlayer.new()
		actor.player_id = id
		actor.is_local_player = id == world.fixture_peer
		actor.name = "Player_%d" % id
		var shape := CollisionShape2D.new()
		shape.shape = CircleShape2D.new()
		shape.shape.radius = 14.0
		actor.add_child(shape)
		world.add_child(actor)
		actor.position = Vector2(float(actors.size()) * 80.0, 0.0)
		actor.returning_crescent.set_physics_process(false)
		actor.boss_combinations.set_process(false)
		actor.player_feedback._aux_sfx_player = null
		PlayerReplicationService.register_player(id, actor)
		for prior in actors:
			world._disable_player_collision_pair(prior, actor)
		actors.append(actor)
		peer_refs[id] = weakref(actor)
		if id == world.fixture_peer:
			world.player = actor
		actor.apply_upgrade("ruinous_impact")
		actor.apply_upgrade("sovereigns_double")
		actor.apply_trial_power("returning_crescent")
	MultiplayerSessionManager.peer_disconnected.connect(_observe_four_departure)
	get_multiplayer().peer_disconnected.connect(MultiplayerSessionManager._on_peer_disconnected)
	MultiplayerSessionManager.session_connected = true
	world.run_summary_recorder = RECORDER.new(world)
	world.run_summary_recorder.mark_run_start()
	world.run_summary_recorder.initialize(false)
	saved_checkpoint = {"version": 1, "marker": "suspended-solo-before-four-party-" + role, "active_ascension_loadout": []}
	check(RunContext.save_active_run(saved_checkpoint), "Each process establishes its own isolated suspended solo checkpoint")
	RunContext.request_resume_saved_run()
	world.current_room_size = Vector2(1160.0, 860.0)
	world.current_effective_room_size = world.current_room_size
	EnemyReplicationService.bind_world(world)
	target_enemy = Enemy.new()
	target_enemy.name = "Target"
	world.add_child(target_enemy)
	target_enemy.set_meta("network_enemy_id", 301)
	EnemyReplicationService.enemy_nodes_by_id[301] = target_enemy
	target_enemy.target_candidates.assign(actors)
	target_enemy.target = PlayerReplicationService.player_nodes[int(roster.client2)]
	_check_live_roster(party_roles)

func _effects_and_first_departure() -> void:
	var victim_id := int(roster.client2)
	var victim := PlayerReplicationService.player_nodes[victim_id] as Player
	if role == "client2":
		victim.boss_combinations.create_shade(victim.global_position)
		check(victim.returning_crescent.try_launch(Vector2.UP), "Departing owner launches its real Crescent")
		PlayerReplicationService._flush_pending_cue_events()
	if role == "host":
		victim.boss_combinations.launch_enemy(target_enemy, Vector2.RIGHT * 300.0, victim_id)
		owned_launch = target_enemy.get_launch_state()
		check(owned_launch.active and owned_launch.owner_id == victim.get_instance_id(), "Host arms a real Ruinous launch owned by the departing joiner")
	check(await _until(func(): return victim.boss_combinations.shade_hits == 1 and victim.returning_crescent.blades.size() == 1), "Every process receives the departing player's shade and blade through production cue RPCs")
	await _barrier("effects", party_roles)
	if role == "client2":
		_write("leaving-client2", true)
		return
	check(await _until(func(): return observed.has(victim_id)), "Real non-first joiner transport departure reaches this survivor's production world callback")
	if role == "host":
		check(not owned_launch.active, "Departing owner cancels its actual host-authoritative enemy launch")

func _reward_and_second_departure(live_roles: Array) -> void:
	world.encounter_intro_grace_active = true
	world._local_player_ready = false
	world._encounter_ready_peers.clear()
	world.player.encounter_input_frozen = true
	world._reward_phase_coordinator.begin_phase(true, false, 1, world.hud)
	await _barrier("reward_open", live_roles)
	if role != "client3":
		world._signal_local_player_ready()
		world._mark_local_reward_phase_complete(false, 1)
	await _barrier("remaining_chose", live_roles)
	if role == "host":
		check(await _until(func(): return world._reward_phase_coordinator._phase_completed_peers.size() == 2 and world._encounter_ready_peers.size() == 2), "Host receives two real reward confirmations and arena-ready RPCs")
		check((world as DepartureWorld).door_advances == 0 and world.encounter_intro_grace_active, "The third connected player's missing confirmation still blocks advance")
		_write("leave-client3", true)
	check(await _until(func(): return FileAccess.file_exists(prefix + "-leave-client3")), "Second joiner leaves only after the host establishes a pending wait")
	if role != "client3":
		check(await _until(func(): return observed.has(int(roster.client3))), "Second ENet departure reaches every remaining process")

func _observe_four_departure(peer_id: int) -> void:
	var reference := peer_refs.get(peer_id) as WeakRef
	var departed := reference.get_ref() as Player if reference != null else null
	if is_instance_valid(departed):
		check(departed.is_queued_for_deletion() and not departed.visible and not departed.combat_damage_enabled, "Production departure immediately hides/disables the registered remote avatar")
		check(departed.returning_crescent.blades.is_empty() and departed.boss_combinations.shade_hits == 0, "Production departure clears the removed owner's blades and shade before deletion")
		departed.upgrade_system.power_registry.free()
		actors.erase(departed)
	observed[peer_id] = true

func _verify_departure(departing_role: String, live_roles: Array) -> void:
	await process_frame
	await physics_frame
	var id := int(roster[departing_role])
	check(not is_instance_valid((peer_refs[id] as WeakRef).get_ref()), "Departed avatar and attached temporary effects are actually freed")
	_check_live_roster(live_roles)
	check(not PlayerReplicationService._remote_position_samples.has(id) and not PlayerReplicationService._pending_cue_events_by_peer.has(id), "Departed owner leaves no queued movement/cue state")
	check(target_enemy.target_candidates.size() == live_roles.size() and not target_enemy.target_candidates.any(func(candidate): return candidate.player_id == id), "Every survivor refreshes enemy target candidates without the departed actor")
	check(is_instance_valid(target_enemy.target) and target_enemy.target.player_id != id, "Enemy targeting never retains the departed owner")
	check(not world._run_outcome_coordinator.is_player_defeated() and HISTORY.load_all().is_empty(), "Living remaining players continue without a false defeat or terminal history")

func _check_live_roster(live_roles: Array) -> void:
	check(PlayerReplicationService.player_nodes.size() == live_roles.size() and world._get_multiplayer_player_nodes().size() == live_roles.size(), "Registered avatars match the actual remaining network party")
	for key in live_roles:
		var actor := PlayerReplicationService.player_nodes.get(int(roster[key])) as Player
		check(is_instance_valid(actor), "Remaining roster keeps " + String(key))
		if not is_instance_valid(actor):
			continue
		var handles := actor.get_collision_exceptions()
		var exact := handles.size() == live_roles.size() - 1 and not handles.has(null)
		for other in live_roles:
			if other != key and not handles.has(PlayerReplicationService.player_nodes[int(roster[other])]):
				exact = false
		check(exact, "Every remaining avatar has exactly the live party collision exceptions")

func _write(key: String, value: Variant) -> void:
	var destination := prefix + "-" + key
	var temporary := destination + ".tmp-" + role
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
	check(DirAccess.rename_absolute(temporary, destination) == OK, "Publish fixture barrier atomically")

func _read(key: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(prefix + "-" + key))

func _all_files(key: String, roles: Array) -> bool:
	for item in roles:
		if not FileAccess.file_exists(prefix + "-" + key + "-" + String(item)):
			return false
	return true

func _barrier(key: String, roles: Array) -> void:
	_write(key + "-" + role, true)
	check(await _until(func(): return _all_files(key, roles)), "Separate processes reach fixture barrier " + key)

func _close_departing_client() -> void:
	MultiplayerSessionManager.session_connected = false
	transport.close()
	await _close_world_and_report()

func _close_surviving_client() -> void:
	if get_multiplayer().peer_disconnected.is_connected(MultiplayerSessionManager._on_peer_disconnected):
		get_multiplayer().peer_disconnected.disconnect(MultiplayerSessionManager._on_peer_disconnected)
	MultiplayerSessionManager.session_connected = false
	transport.close()
	await _close_world_and_report()

func _close_world_and_report() -> void:
	EnemyReplicationService.unbind_world(world)
	await _cleanup()
	await _finish_enet()

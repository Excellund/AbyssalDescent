extends "res://scripts/tests/test_player_transform_lifecycle_enet.gd"
## Actual Main scenes, two mapped avatars per process and native gameplay RPCs.
const INTERACTIONS := preload("res://scripts/shared/combat_interaction_registry.gd")
const BIOMES := preload("res://scripts/shared/biome_registry.gd")

class Barrier extends Node:
	var received: Dictionary = {}
	@rpc("any_peer", "call_remote", "reliable")
	func mark(key: String) -> void:
		received[key] = multiplayer.get_remote_sender_id()

var barrier: Barrier
var client_id: int
var original_profile: Dictionary
var cover_origin := Vector2.ZERO
var saved_attack: Dictionary
var old_cover_state: Dictionary

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or args.size() != 4:
		quit(1)
		return
	await _setup_cover_peers(args)
	await _enter_cover_room()
	await _attack_and_reject_replays()
	await _destroy_and_release_anchor()
	await _two_owner_contacts()
	await _pulse_state_roundtrip()
	await _legacy_solid_room()
	await _barrier("finished")
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
	check(await audio_retirement.wait_until_retired(self), "Native audio retires after both Main scenes")
	var report := FileAccess.open(prefix + "-" + role + ".json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"role": role, "checks": checks, "failures": failures}, "\t"))
	report.close()
	print("[ENet] %s: %d checks, %d failures" % [role, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _setup_cover_peers(args: PackedStringArray) -> void:
	PlayerReplicationService.set_script(ActiveReplication)
	PlayerReplicationService.set_process(false)
	PlayerReplicationService.set_physics_process(false)
	role = args[1]
	prefix = args[3]
	ProjectSettings.set_setting("application/config/version", "dev-cover-pulse-enet")
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
	world = MAIN.instantiate() as WORLD
	world.name = "World"
	world.get_node("DebugSettings").enabled = false
	root.add_child(world)
	current_scene = world
	world.reward_selection_ui.close_selection()
	world.reward_selection_ui.reward_skipped.emit(ENUMS.RewardMode.ARCANA, true)
	world.set_process(false)
	world.set_physics_process(false)
	barrier = Barrier.new()
	barrier.name = "FixtureBarrier"
	root.add_child(barrier)
	transport = ENetMultiplayerPeer.new()
	if role == "host":
		transport.set_bind_ip("127.0.0.1")
		check(transport.create_server(int(args[2]), 1) == OK, "Host binds isolated loopback ENet")
	else:
		check(transport.create_client("127.0.0.1", int(args[2])) == OK, "Client opens separate native ENet connection")
	get_multiplayer().multiplayer_peer = transport
	if role == "host":
		_write("ready", true)
	check(await _until(func(): return transport.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and get_multiplayer().get_peers().size() == 1), "Two actual processes connect")
	client_id = int(get_multiplayer().get_peers()[0]) if role == "host" else get_multiplayer().get_unique_id()
	MultiplayerSessionManager._multiplayer = get_multiplayer()
	MultiplayerSessionManager.session_connected = true
	MultiplayerSessionManager.is_host_peer = role == "host"
	MultiplayerSessionManager.local_peer_id = get_multiplayer().get_unique_id()
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	PlayerReplicationService.player_nodes.clear()
	PlayerReplicationService.local_peer_id = get_multiplayer().get_unique_id()
	world.player.player_id = get_multiplayer().get_unique_id()
	world.player.is_local_player = true
	PlayerReplicationService.register_player(world.player.player_id, world.player)
	world.is_multiplayer = true
	world._setup_multiplayer_remote_players()
	world.encounter_profile_builder.set_use_multiplayer_difficulty_config(true)
	world.encounter_profile_builder.set_multiplayer_party_size(2)
	RunContext.set_multiplayer_session("cover-pulse-loopback", role == "host")
	GameStateReplicationService.initialize(world)
	await _barrier("mapped")
	check(world._get_multiplayer_player_nodes().size() == 2 and world._get_player_for_peer(1) != world._get_player_for_peer(client_id), "Both actual player bodies are mapped independently on this Main")
	world.run_summary_recorder.initialize(false)
	world.run_summary_recorder.mark_run_start()
	check(await _until(func(): return INTERACTIONS.current_run().length() == 32), "Production recorder handshake supplies the shared run token")
	_write("token-" + role, INTERACTIONS.current_run())
	await _barrier("token")
	check(_read("token-host") == _read("token-client"), "Both peers use the same authenticated run token")

func _barrier(key: String) -> void:
	barrier.mark.rpc(key)
	check(await _until(func(): return barrier.received.has(key)), "Ordered peer barrier: " + key)
	check(int(barrier.received.get(key, 0)) == (client_id if role == "host" else 1), "Barrier has the actual sender: " + key)

func _enter_profile(profile: Dictionary, key: String) -> void:
	if role == "host":
		var door := CONTRACTS.standard_encounter_door_option(profile)
		if not CONTRACTS.profile_objective_kind(profile).is_empty():
			door = CONTRACTS.objective_door_option(profile)
		world._choose_door(door)
		world._sync_chosen_door.rpc(door, world._build_progress_sync_state())
		_write("room-" + key, {"room": world.get_current_room_sync_id(), "label": world.current_room_label, "count": CONTRACTS.profile_total_enemy_count(profile)})
	else:
		check(await _until(func(): return _has("room-" + key)), "Host publishes room identity " + key)
	var expected: Dictionary = _read("room-" + key)
	check(await _until(func(): return world.get_current_room_sync_id() == int(expected.room) and world.current_room_label == String(expected.label) and _living().size() >= int(expected.count)), "Native chosen-door and spawn RPCs enter " + key)
	for actor in world._get_multiplayer_player_nodes():
		actor.set_process(false)
		actor.set_physics_process(false)
	for enemy in _living():
		enemy.set_process(false)
		enemy.set_physics_process(false)
		enemy.position = Vector2(900.0, 900.0)
	world._exit_encounter_intro_grace()
	world._set_combat_paused(false)
	await _barrier("entry-" + key)

func _enter_cover_room() -> void:
	if role == "host":
		world._sync_act_biomes.rpc(PackedStringArray(["shatterfield", "hollow", "void_breach"]))
		world.encounter_profile_builder.set_active_biome(BIOMES.get_biome("shatterfield"))
		original_profile = world.encounter_profile_builder.build_debug_encounter_profile("crossfire", 5)
		_write("profile", original_profile)
	await _barrier("profile")
	original_profile = _read("profile")
	await _enter_profile(original_profile, "brittle")
	var layout := CONTRACTS.profile_obstacle_layout(original_profile)
	check(world._arena_cover.contacts_left(2) == 3 and world._arena_cover.contacts_left(3) == 3, "Both authored inner columns begin with three contacts")
	check(world._active_obstacle_nodes.size() == 4 and world.renderer.obstacle_layout == layout, "Native room creates matching rendered and physical geometry")
	cover_origin = Vector2(layout[1].pos) - Vector2(60.0, 0.0)
	world._get_player_for_peer(client_id).position = cover_origin
	world._get_player_for_peer(1).position = Vector2(500.0, 200.0)
	await _barrier("positioned")

func _swing() -> Dictionary:
	world.player.attack_cooldown_left = 0.0
	world.player.attack_lock_time_left = 0.0
	world.player._try_execute_attack(Vector2.RIGHT)
	var action := {"run": INTERACTIONS.current_run(), "room": INTERACTIONS.current_room(), "owner": world.player.player_id, "seq": world.player.combat_interactions._next_sequence, "epoch": world.player.combat_interactions._epoch, "kind": "melee", "ancestry": 0}
	return INTERACTIONS.damage_context(action, "melee").interaction

func _attack_and_reject_replays() -> void:
	if role == "client":
		saved_attack = _swing()
		_write("first-attack", saved_attack)
	await _barrier("first-attack")
	saved_attack = _read("first-attack")
	check(await _until(func(): return world._arena_cover.contacts_left(2) == 2), "Joining player's actual Attack cracks the same column on both peers")
	if role == "host":
		check(world._get_player_for_peer(client_id).combat_interactions._accepted_epoch == int(saved_attack.epoch), "Cover contact used the joining player's authenticated epoch")
	check(world._arena_cover.revision == 1 and world._active_obstacle_nodes.size() == 4, "One attack changes one contact while preserving collision")
	if role == "client":
		world.request_brittle_cover_attack(saved_attack, cover_origin, Vector2.RIGHT)
		for bad_key in ["owner", "run", "room", "epoch", "source"]:
			# Each rejection has its own unused sequence, so deduplication cannot
			# conceal a missing ownership, provenance or source guard.
			var forged := INTERACTIONS.damage_context(world.player.new_combat_action("melee"), "melee").interaction as Dictionary
			match bad_key:
				"owner": forged[bad_key] = 1
				"run": forged[bad_key] = "retired-run"
				"room": forged[bad_key] = int(forged[bad_key]) - 1
				"epoch": forged[bad_key] = int(forged[bad_key]) - 1
				"source": forged[bad_key] = "static_wake"
			world.request_brittle_cover_attack(forged, cover_origin, Vector2.RIGHT)
		var distant_origin := INTERACTIONS.damage_context(world.player.new_combat_action("melee"), "melee").interaction as Dictionary
		world.request_brittle_cover_attack(distant_origin, cover_origin + Vector2(500, 0), Vector2.RIGHT)
	await _barrier("replays")
	check(world._arena_cover.contacts_left(2) == 2 and world._arena_cover.revision == 1, "Duplicate, wrong owner/run/room/epoch/source and remote origin cannot spend another contact")
	if role == "host":
		var wrong_run_state := world._cover_state_payload().duplicate(true)
		wrong_run_state["run"] = "retired-run"
		wrong_run_state["revision"] = 2
		wrong_run_state.columns[0]["left"] = 1
		world._sync_brittle_cover_state.rpc(wrong_run_state)
	await _barrier("stale-run-state")
	check(world._arena_cover.contacts_left(2) == 2 and world._arena_cover.revision == 1, "An otherwise valid newer snapshot from a retired run cannot damage joining cover")
	if role == "host":
		world.pause_menu_controller.open()
	await _barrier("host-paused")
	if role == "client":
		_swing()
	await _barrier("paused-attack")
	check(world._arena_cover.contacts_left(2) == 2, "Host Pause rejects an otherwise valid client Attack")
	if role == "host":
		world.pause_menu_controller.close()
	await _barrier("host-resumed")
	# Authoritative build geometry wins over additional client payload fields.
	var outside := cover_origin - Vector2(220.0, 0.0)
	world._get_player_for_peer(client_id).position = outside
	if role == "client":
		var distant := INTERACTIONS.damage_context(world.player.new_combat_action("melee"), "melee").interaction as Dictionary
		distant["range"] = 99999.0
		distant["arc_degrees"] = 360.0
		world.request_brittle_cover_attack(distant, outside, Vector2.RIGHT)
	await _barrier("canonical-range")
	check(world._arena_cover.contacts_left(2) == 2, "Host uses the mapped player's real Attack reach instead of client geometry")
	world._get_player_for_peer(client_id).position = cover_origin
	await _barrier("in-range")

func _destroy_and_release_anchor() -> void:
	if role == "client":
		_swing()
	await _barrier("second-hit")
	check(await _until(func(): return world._arena_cover.contacts_left(2) == 1), "Second distinct Attack advances the shared crack state")
	old_cover_state = world._cover_state_payload().duplicate(true)
	if role == "host":
		world.player.apply_trial_power("razor_orbit")
		world.player.position = cover_origin
		world.player.arcana_motion.start_orbit(world._arena_cover_bodies[2])
		check(world.player.arcana_motion.anchor == world._arena_cover_bodies[2], "Host input owner actually orbits the column before the final client hit")
	await _barrier("anchored")
	if role == "client":
		_swing()
	await _barrier("third-hit")
	check(await _until(func(): return world._arena_cover.contacts_left(2) == 0), "Third client Attack destroys the same column on both peers")
	await process_frame
	check(world._active_obstacle_nodes.size() == 3 and not world._arena_cover_bodies.has(2), "Destroyed collision body leaves both room maps")
	check(world.renderer.obstacle_layout == world.enemy_spawner.obstacle_circles and world.renderer.obstacle_layout.size() == 3, "Renderer and spawn exclusion agree on the opened lane")
	check(world.renderer.cover_rubble_layout.size() == 1 and get_nodes_in_group("arena_columns").size() == 3, "One nonblocking rubble mark replaces the removed Orbit anchor")
	if role == "host":
		check(world.player.arcana_motion.anchor == null and not world.player.arcana_motion.orbit_transferred, "Destroying cover releases Orbit without an enemy-death transfer")
		world._sync_brittle_cover_state.rpc(old_cover_state)
		world._sync_brittle_cover_state.rpc(world._cover_state_payload())
	await _barrier("old-state")
	check(world._arena_cover.contacts_left(2) == 0 and world._active_obstacle_nodes.size() == 3, "Older and duplicate cover snapshots cannot restore collision")

func _two_owner_contacts() -> void:
	var layout := CONTRACTS.profile_obstacle_layout(original_profile)
	var shared_origin: Vector2 = Vector2(layout[2].pos) - Vector2(60.0, 0.0)
	for actor in world._get_multiplayer_player_nodes():
		actor.position = shared_origin
	await _barrier("two-owner-positioned")
	var own_action := _swing()
	await _barrier("two-owner-attacks")
	check(await _until(func(): return world._arena_cover.contacts_left(3) == 1), "One real Attack from each owner spends exactly two contacts on the shared second column")
	check(world._arena_cover.revision == 5 and world._active_obstacle_nodes.size() == 3, "Concurrent owner actions preserve shared revision and remaining collision")
	world.request_brittle_cover_attack(own_action, shared_origin, Vector2.RIGHT)
	await _barrier("two-owner-duplicates")
	check(world._arena_cover.contacts_left(3) == 1 and world._arena_cover.revision == 5, "Replaying both owners' accepted actions cannot spend a third contact")

func _pulse_state_roundtrip() -> void:
	var profile: Dictionary = {}
	if role == "host":
		profile = world.encounter_profile_builder.build_objective_profile(5, "pulse_window")
	await _enter_profile(profile, "pulse")
	check(world.renderer.cover_rubble_layout.is_empty(), "Next room removes prior rubble")
	if role == "host":
		world.objective_runtime._fire_pulse()
		world._sync_objective_state.rpc(world.objective_manager.serialize_sync_state(), world.get_current_room_sync_id(), 100)
		_write("pulse-name", world.objective_manager.pulse_mode)
	await _barrier("active-pulse")
	check(await _until(func(): return world.objective_manager.pulse_active), "Actual objective RPC carries the host's active pulse")
	world.hud.refresh(world._get_hud_state(), world.player)
	check(world.hud._status_obj_line2.text.contains(String(_read("pulse-name"))) and world.hud._status_obj_line3.visible and not world.hud._status_obj_line3.text.is_empty(), "Both HUDs show the actual active rule and mode")
	check(is_equal_approx(world.objective_manager.pulse_active_timer, 6.0), "Joining HUD starts with the authoritative remaining time")
	if role == "client":
		world.pause_menu_controller.open()
		world._process(1.0)
		check(is_equal_approx(world.objective_manager.pulse_active_timer, 6.0), "Actual joining Pause freezes the display countdown")
		world.pause_menu_controller.close()
		world.objective_frame_coordinator.tick(world.objective_manager, null, 0.5, false)
		check(is_equal_approx(world.objective_manager.pulse_active_timer, 5.5), "Joining display advances between authoritative snapshots")
		world.objective_frame_coordinator.tick(world.objective_manager, null, 6.0, false)
		world.hud.refresh(world._get_hud_state(), world.player)
		check(not world.hud._status_obj_line3.visible, "Missing expiry packet cannot leave a stale active rule on the joining HUD")
	await _barrier("predicted-expiry")
	if role == "host":
		world.objective_manager.pulse_active = false
		world.objective_manager.pulse_active_timer = 0.0
		world._sync_objective_state.rpc(world.objective_manager.serialize_sync_state(), world.get_current_room_sync_id(), 101)
	await _barrier("expired-pulse")
	world.hud.refresh(world._get_hud_state(), world.player)
	check(not world._get_hud_state().objective_pulse_active and not world.hud._status_obj_line3.visible, "Host expiry leaves both HUDs in the next-pulse state")

func _legacy_solid_room() -> void:
	var legacy := original_profile.duplicate(true)
	for entry in legacy.obstacle_layout:
		entry.erase("break_contacts")
	await _enter_profile(legacy, "legacy-solid")
	if role == "host":
		world._sync_brittle_cover_state.rpc(old_cover_state)
	await _barrier("stale-room-cover")
	check(not world._arena_cover.has_brittle_cover() and world._active_obstacle_nodes.size() == 4, "Legacy serialized columns remain solid and reject earlier-room cover state")
	world.hud.refresh(world._get_hud_state(), world.player)
	check(world.objective_manager.active_objective_kind.is_empty() and not world.hud._status_obj_line3.visible, "Room transition removes the last objective rule")

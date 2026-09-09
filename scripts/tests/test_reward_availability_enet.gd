extends SceneTree
## Real Main room methods and existing chosen-door/enemy-spawn RPCs over loopback ENet.
const MAIN := preload("res://scenes/Main.tscn")
const WORLD := preload("res://scripts/world_generator.gd")
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const PROFILE := preload("res://scripts/core/profile_persistence_store.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const BREAKWATER := preload("res://scripts/enemy_breakwater.gd")
var role: String
var prefix: String
var transport: ENetMultiplayerPeer
var world: WORLD
var failures: Array[String] = []
var checks := 0
const AUDIO_RETIREMENT := preload("res://scripts/tests/fixture_audio_retirement.gd")
var audio_retirement := AUDIO_RETIREMENT.new()

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
	node_added.connect(audio_retirement.observe_node)
	role = args[1]
	prefix = args[3]
	ProjectSettings.set_setting("application/config/version", "dev-reward-availability-enet")
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
	# Bootstrap Main before establishing the controlled peer session. Its solo room
	# is fixture setup, not part of these reward phases.
	world._clear_all_enemies()
	await process_frame
	await process_frame
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
	for entry in world.power_registry_instance.get_trial_power_pool(world.player):
		if role == "client" and String(entry.id) == "returning_crescent":
			continue
		for _level in int(entry.stack_limit) - world.player.get_trial_power_stack_count(String(entry.id)):
			world.player.apply_trial_power(String(entry.id))
	for entry in world.power_registry_instance.get_boss_reward_pool(world.player):
		if role == "client" and String(entry.id) == "sovereigns_double":
			continue
		for _level in int(entry.stack_limit) - world.player.get_upgrade_stack_count(String(entry.id)):
			world.player.apply_upgrade(String(entry.id))
	for index in range(3):
		var key := str(index)
		var initial := index == 2
		var mode: int = ENUMS.RewardMode.BOSS if index == 1 else ENUMS.RewardMode.ARCANA
		var selected_id := "sovereigns_double" if index == 1 else "returning_crescent"
		if initial:
			# Initial rewards begin in a fresh Starting Chamber, not the previous
			# ordinary room left by this fixture's earlier phases.
			world.current_room_label = "Starting Chamber"
			world._world_multiplayer_sync_state.reset_for_new_run()
			while world.player.get_trial_power_stack_count("returning_crescent") < 3:
				world.player.apply_trial_power("returning_crescent")
			if role == "host":
				world.pending_initial_room_profile = world.encounter_profile_builder.build_debug_encounter_profile("apex_breakwater", 8)
		var before_stacks: int = world.player.get_upgrade_stack_count(selected_id) if index == 1 else world.player.get_trial_power_stack_count(selected_id)
		var before_timeline: Array = world.run_summary_recorder.run_summary_tracker.reward_timeline.duplicate(true)
		_write("prepared-" + role + "-" + key, true)
		check(await _until(func(): return _has("prepared-host-" + key) and _has("prepared-client-" + key)), "Both actual builds are prepared for reward " + key)
		if role == "host":
			world._sync_open_reward_selection.rpc("Reward", initial, mode, {}, "")
			world._open_boon_selection("Reward", initial, mode, {}, "", world.current_character_id)
		check(await _until(func(): return ui.is_active() and ui.reward_selection_mode == mode and ui.pending_initial_boon == initial), "Real reliable World reward open reaches each owner " + key)
		check(not ui.skip_button.visible and ui.boon_confirm_lock_time > 0, "Native reward opens with confirmation delay")
		ui.process_input(ui.boon_confirm_lock_time + 0.01)
		ui.process_input(0.01)
		var empty := role == "host" or initial
		check(ui.boon_choices.is_empty() == empty, "Each owner rolls availability from its own current build")
		if empty:
			check(ui.skip_button.visible and ui.skip_button.text.begins_with("Continue"), "Exhausted owner receives usable Continue")
		else:
			check(ui.boon_choices.size() == 1 and String(ui.boon_choices[0].id) == selected_id and ui.skip_button.text.begins_with("Skip"), "Eligible owner retains its actual remaining reward card and normal Skip")
		_write("offered-" + role + "-" + key, true)
		check(await _until(func(): return _has("offered-host-" + key) and _has("offered-client-" + key)), "Both peers see corresponding offers before confirmation")
		if role == "host":
			ui.skip_button.pressed.emit()
			_write("host-continued-" + key, true)
			check(await _until(func(): return _has("client-saw-wait-" + key)), "Joiner inspects host-first readiness")
			check(not world._reward_phase_coordinator.get_active_phase().is_empty() and not world.player.is_physics_processing(), "Exhausted host stays paused until joiner deliberately chooses")
			_write("release-client-" + key, true)
		else:
			check(await _until(func(): return _has("host-continued-" + key) and world._reward_phase_coordinator._phase_completed_peers.has(1)), "Host Continue uses real reliable readiness RPC")
			check(ui.is_active() and not world._reward_phase_coordinator.get_active_phase().is_empty() and not world.player.is_physics_processing(), "Other player is never auto-skipped or resumed")
			_write("client-saw-wait-" + key, true)
			check(await _until(func(): return _has("release-client-" + key)), "Host observes pending phase before joiner confirmation")
			if empty:
				ui.skip_button.pressed.emit()
			else:
				Input.action_release("attack")
				await process_frame
				await physics_frame
				await process_frame
				ui.boon_card_rects[0] = Rect2(root.get_mouse_position() - Vector2(10,10), Vector2(20,20))
				Input.action_press("attack")
				ui.process_input(0.016)
				Input.action_release("attack")
		check(await _until(func(): return world._reward_phase_coordinator.get_active_phase().is_empty()), "Actual readiness completion and phase advance reach both peers")
		check(not ui.is_active(), "Completed native reward closes on each owner")
		var after_stacks: int = world.player.get_upgrade_stack_count(selected_id) if index == 1 else world.player.get_trial_power_stack_count(selected_id)
		check(after_stacks == before_stacks + (0 if empty else 1), "Only the owner accepting a real reward gains a stack")
		check(world.run_summary_recorder.run_summary_tracker.reward_timeline.size() == before_timeline.size() + (0 if empty else 1), "Empty continuation leaves local Oath/build reward timeline unchanged")
		if initial:
			var entered := await _until(func(): return _living().size() == 1 and _living()[0].get_script() == BREAKWATER)
			check(entered, "Both empty initial choices start one real host-selected Breakwater via normal phase RPC")
		else:
			check(await _until(func(): return world.choosing_next_room and not world.door_options.is_empty()), "Completed party receives next route options")
		_write("checked-" + role + "-" + key, true)
		check(await _until(func(): return _has("checked-host-" + key) and _has("checked-client-" + key)), "Both peers verify reward before next phase")
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
	check(await audio_retirement.wait_until_retired(self), "Native audio retires after actual Main teardown")
	var file := FileAccess.open(prefix + "-" + role + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"role": role, "checks": checks, "failures": failures}, "\t"))
	file.close()
	print("[ENet] %s: %d checks, %d failures" % [role, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _living() -> Array[Node]:
	var out: Array[Node] = []
	for enemy in get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and not enemy.is_dead():
			out.append(enemy)
	return out

extends SceneTree
const AUDIO_RETIREMENT := preload("res://scripts/tests/fixture_audio_retirement.gd")
var audio_retirement := AUDIO_RETIREMENT.new()
## Exercise the production room-entry boundary, including clear and serialized layouts.
const MAIN := preload("res://scenes/Main.tscn")
const WORLD := preload("res://scripts/world_generator.gd")
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const PROFILE := preload("res://scripts/core/profile_persistence_store.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const BREAKWATER := preload("res://scripts/enemy_breakwater.gd")
var checks := 0
var failures: Array[String] = []
var world: WORLD

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	node_added.connect(audio_retirement.observe_node)
	ProjectSettings.set_setting("application/config/version", "dev-room-layout-entry")
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.multiplayer_session_id = ""
	RunContext.active_ascension_loadout = []
	RunContext.run_mode = ENUMS.RunMode.STANDARD
	RunContext.selected_character_id = "veilstrider"
	RunContext.clear_resume_saved_run_request()
	RunContext.clear_active_run()
	MultiplayerSessionManager.session_connected = false
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var store := PROFILE.new()
	var profile := store.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	store.save_profile(profile)
	for input in [{}, {"obstacle_layout": null}, {"obstacle_layout": "legacy"}, {"obstacle_layout": []}]:
		var empty := CONTRACTS.profile_obstacle_layout(input)
		check(empty.is_typed() and empty.get_typed_builtin() == TYPE_DICTIONARY and empty.is_empty(), "Missing or non-array optional layout resolves to typed empty geometry")
	var first := {"pos": Vector2(10, 20), "radius": 28.0}
	var second := {"pos": Vector2(-50, 60), "radius": 36.0, "type": "boulder"}
	var mixed := [first, null, 7, "legacy", second]
	var valid := CONTRACTS.profile_obstacle_layout({"obstacle_layout": mixed})
	check(valid == [first, second] and mixed.size() == 5, "Optional malformed entries cannot discard or mutate valid obstacle dictionaries")
	for tier in range(4):
		RunContext.current_difficulty_tier = tier
		world = MAIN.instantiate() as WORLD
		world.get_node("DebugSettings").enabled = false
		root.add_child(world)
		current_scene = world
		var ui: Node = world.reward_selection_ui
		var choice: Dictionary = ui.boon_choices.front().duplicate(true)
		ui.close_selection()
		ui.reward_selected.emit(choice, ENUMS.RewardMode.ARCANA, true)
		var apex := world.encounter_profile_builder.build_debug_encounter_profile("apex_breakwater", 8)
		_enter(apex, "Actual builder Breakwater Bearing%d" % tier)
		check(world.active_room_enemy_count == 1 and _living_enemies() == 1, "Breakwater actual spawn equals its declared one enemy on Bearing%d" % tier)
		check(world.renderer.obstacle_layout.is_empty() and world.enemy_spawner.obstacle_circles.is_empty() and world._active_obstacle_nodes.is_empty(), "Breakwater remains obstacle-free on Bearing%d" % tier)
		check(_only_breakwater_alive() and not world.choosing_next_room and not world.reward_selection_ui.is_active(), "A real live Breakwater cannot masquerade as a cleared room before its death")
		# Real binary checkpoint preserves the offered door through RunContext's codec.
		var door := CONTRACTS.standard_encounter_door_option(apex)
		check(RunContext.save_active_run({"door_options": [door]}), "Disposable real checkpoint stores offered Breakwater door")
		var loaded := RunContext.load_active_run()
		_enter(CONTRACTS.door_option_profile(loaded.door_options[0]), "Checkpoint Breakwater Bearing%d" % tier)
		check(world.active_room_enemy_count == 1 and _living_enemies() == 1, "Restored Breakwater still actually spawns once")
		check(_only_breakwater_alive() and not world.choosing_next_room, "Disk-restored room contains the real undefeated Apex")
		var ordinary := CONTRACTS.profile("Skirmish", Vector2(1160, 860), true, 2, 0, 0, 0)
		_enter(ordinary, "Legacy missing obstacle layout")
		check(world.active_room_enemy_count == 2 and _living_enemies() == 2, "Absent optional layout still spawns the declared ordinary enemies")
		ordinary["obstacle_layout"] = [{"pos": Vector2(-190, -70), "radius": 28.0}, {"pos": Vector2(200, 100), "radius": 36.0, "type": "boulder"}]
		_enter(bytes_to_var(var_to_bytes(ordinary)) as Dictionary, "Serialized untyped nonempty layout")
		check(world.renderer.obstacle_layout == ordinary.obstacle_layout and world.enemy_spawner.obstacle_circles == ordinary.obstacle_layout, "Serialized valid geometry reaches renderer and spawner exactly")
		check(world._active_obstacle_nodes.size() == 2 and world._active_obstacle_nodes[0].global_position == Vector2(-190, -70) and world._active_obstacle_nodes[1].global_position == Vector2(200, 100), "Actual column bodies retain both world positions")
		check(_living_enemies() == 2, "Serialized ordinary profile spawns its actual two enemies")
		current_scene = null
		world.queue_free()
		world = null
		await process_frame
		await process_frame
	RunContext.clear_active_run()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	var pending_audio := audio_retirement.pending_count()
	check(await audio_retirement.wait_until_retired(self), "AudioServer releases native playback from every deleted room owner")
	print("[AudioRetirement] pending before barrier=%d, after=%d" % [pending_audio, audio_retirement.pending_count()])
	print("[RoomLayoutEntry] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _enter(profile: Dictionary, label: String) -> void:
	world._clear_all_enemies()
	world.active_room_enemy_count = -1
	world.encounter_intro_grace_active = false
	world._begin_room(profile)
	check(world.encounter_intro_grace_active, label + " reaches the end of actual World._begin_room")

func _living_enemies() -> int:
	var count := 0
	for enemy in get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and not enemy.is_dead():
			count += 1
	return count

func _only_breakwater_alive() -> bool:
	if _living_enemies() != 1:
		return false
	for enemy in get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and not enemy.is_dead():
			return enemy.get_script() == BREAKWATER
	return false

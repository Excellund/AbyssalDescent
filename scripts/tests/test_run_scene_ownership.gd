extends SceneTree
## Actual scene ownership across health/death retry, menu resume and restart.
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const MENU := preload("res://scripts/menu_controller.gd")
var snapshots: Array[Dictionary] = []
const MAIN := preload("res://scenes/Main.tscn")
const WORLD := preload("res://scripts/world_generator.gd")
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")
const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const PROFILE := preload("res://scripts/core/profile_persistence_store.gd")
const HISTORY := preload("res://scripts/core/run_history_store.gd")
class BorrowWorld extends Node2D:
	var is_multiplayer := true
var failures: Array[String] = []
var checks := 0
var active_world: WORLD
var main_instances := 0
var player_fallback_registry_ids: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _disable_debug_before_ready(node: Node) -> void:
	if node.get_script() == preload("res://scripts/player.gd"):
		node.ready.connect(_record_player_fallback.bind(node), CONNECT_ONE_SHOT)
	if node is WORLD:
		var debug := node.get_node_or_null("DebugSettings")
		if debug != null:
			debug.enabled = false
		main_instances += 1

func _record_player_fallback(actor: Node) -> void:
	player_fallback_registry_ids[actor.get_instance_id()] = actor.upgrade_system.power_registry.get_instance_id()

func _wait(predicate: Callable, seconds: float = 5.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false

func _pick_reward(row: Dictionary) -> void:
	var ui: Node = active_world.reward_selection_ui
	if ui.boon_choices.is_empty():
		return
	var choice: Dictionary = ui.boon_choices.front().duplicate(true)
	var mode: int = ui.reward_selection_mode
	var initial: bool = ui.pending_initial_boon
	check(mode != ENUMS.RewardMode.MISSION, "Smoke route avoids objectives and their two-stage reward contract")
	row.rewards.append({"id": choice.get("id", ""), "mode": mode, "initial": initial, "depth": active_world.room_depth})
	ui.close_selection()
	ui.reward_selected.emit(choice, mode, initial)

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	check(HISTORY.clear_all(), "Isolated scene fixture starts with empty local history")
	ProjectSettings.set_setting("application/config/version", "dev-main-ownership-smoke")
	ProjectSettings.set_setting("application/config/update_feed_url", "")
	RunContext.telemetry_upload_enabled = false
	RunContext.telemetry_consent_asked = true
	RunContext.set_profile_name("FixturePilot", false)
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.multiplayer_session_id = ""
	RunContext.active_ascension_loadout = []
	RunContext.selected_character_id = "bastion"
	RunContext.current_difficulty_tier = 0
	RunContext.run_mode = ENUMS.RunMode.STANDARD
	RunContext.clear_resume_saved_run_request()
	RunContext.clear_active_run()
	MultiplayerSessionManager.session_connected = false
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var profiles := PROFILE.new()
	var profile := profiles.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	profiles.save_profile(profile)
	node_added.connect(_disable_debug_before_ready)
	MAPPER._get_power_registry_instance()
	var shared_id: int = MAPPER._power_registry_instance.get_instance_id()
	await _test_borrowed_helpers(shared_id)
	Engine.time_scale = 1.0
	for iteration in 2:
		active_world = MAIN.instantiate() as WORLD
		active_world.get_node("DebugSettings").enabled = false
		root.add_child(active_world)
		current_scene = active_world
		# Two real death retries in succession; never manually free the helper Nodes.
		for death_round in 2:
			var old_world_id := active_world.get_instance_id()
			var helpers := _helpers(active_world)
			var before_history := HISTORY.load_all().size()
			_pick_reward({"rewards": []})
			await process_frame
			active_world.player.take_damage(1000000, {"source": "fixture_death"})
			check(await _wait(func(): return active_world.defeat_screen.is_open()), "Native health/death callback opens real defeat UI")
			check(HISTORY.load_all().size() == before_history + 1, "Death records one summary")
			active_world.defeat_screen.retry_run_requested.emit()
			check(await _wait(func(): return current_scene is WORLD and current_scene.get_instance_id() != old_world_id), "Defeat UI retries actual Main")
			active_world = current_scene as WORLD
			_check_freed(helpers, old_world_id, "death retry")
			check(active_world.reward_selection_ui.is_active() and active_world.room_depth == 0, "Death retry restarts initial reward")
		# Save/exit from actual pause, then Continue uses the menu's production resume path.
		_pick_reward({"rewards": []})
		await _clear_first_room_to_checkpoint()
		var menu_exit_world_id := active_world.get_instance_id()
		var menu_exit_helpers := _helpers(active_world)
		active_world.pause_menu_controller.open()
		active_world.pause_menu_controller.back_to_main_menu_requested.emit()
		check(await _wait(func(): return current_scene is MENU), "Pause exit loads actual Menu")
		active_world = null
		_check_freed(menu_exit_helpers, menu_exit_world_id, "menu exit")
		check(current_scene._has_saved_run(), "Pause exit preserves checkpoint for Continue")
		check(await _wait(func(): return current_scene is MENU and current_scene.primary_run_button.is_visible_in_tree() and not current_scene.primary_run_button.disabled and current_scene.root_panel.modulate.a >= 0.99 and not current_scene._is_profile_prompt_blocked() and not current_scene.profile_name_prompt_layer.visible), "Real primary button is visible and interactive after menu intro")
		current_scene.primary_run_button.pressed.emit()
		var resumed := await _wait(func(): return current_scene is WORLD)
		check(resumed, "Actual menu Continue resumes Main")
		if not resumed:
			quit(1)
			return
		active_world = current_scene as WORLD
		check(not active_world.settings_enabled, "Menu resume uses normal gameplay")
		var resume_world_id := active_world.get_instance_id()
		var resume_helpers := _helpers(active_world)
		active_world.pause_menu_controller.open()
		active_world.pause_menu_controller.abandon_run_requested.emit()
		check(await _wait(func(): return current_scene is MENU), "Abandon loads actual Menu")
		active_world = null
		_check_freed(resume_helpers, resume_world_id, "abandon")
		check(not current_scene._has_saved_run(), "Abandon removes checkpoint")
		# Menu selectors are the actual restart action; no direct scene load here.
		check(await _wait(func(): return current_scene is MENU and current_scene.primary_run_button.is_visible_in_tree() and not current_scene.primary_run_button.disabled and current_scene.root_panel.modulate.a >= 0.99 and not current_scene._is_profile_prompt_blocked() and not current_scene.profile_name_prompt_layer.visible), "Real primary button is visible and interactive after menu intro")
		current_scene.primary_run_button.pressed.emit()
		check(await _wait(func(): return current_scene.character_selector_panel.visible and current_scene.character_selector_panel.modulate.a >= 0.99 and not current_scene.character_buttons[0].disabled), "Actual character selector is interactive")
		current_scene.character_buttons[0].pressed.emit()
		check(await _wait(func(): return current_scene.difficulty_selector_panel.visible and current_scene.difficulty_selector_panel.modulate.a >= 0.99 and not current_scene.difficulty_tier_buttons[0].disabled), "Actual Bearing selector is interactive")
		current_scene.difficulty_tier_buttons[0].pressed.emit()
		check(await _wait(func(): return current_scene is WORLD), "Actual menu character/Bearing selection starts Main again")
		active_world = current_scene as WORLD
		check(active_world.reward_selection_ui.is_active(), "New menu run offers initial Arcana")
		var final_id := active_world.get_instance_id()
		var final_helpers := _helpers(active_world)
		current_scene = null
		active_world.queue_free()
		active_world = null
		await process_frame
		await process_frame
		_check_freed(final_helpers, final_id, "final teardown")
		check(is_instance_id_valid(shared_id) and MAPPER._power_registry_instance.get_instance_id() == shared_id, "Shared mapper registry survives all scene transitions")
		var metrics := {"iteration": iteration, "orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), "objects": Performance.get_monitor(Performance.OBJECT_COUNT)}
		snapshots.append(metrics)
		print("[OwnershipCounts] " + JSON.stringify(metrics))
	check(snapshots[0].orphans == 1 and snapshots[1].orphans == 1, "Only intentional shared registry remains orphaned")
	check(snapshots[0].nodes == snapshots[1].nodes, "Post-teardown total Node count remains exact across repeated restart cycles")
	check(snapshots[0].resources == snapshots[1].resources, "Post-teardown Resource count remains exact across repeated restart cycles")
	MAPPER._power_registry_instance.free()
	MAPPER._power_registry_instance = null
	Engine.time_scale = 1.0
	FileAccess.open("res://main-helper-ownership-results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "counts": snapshots, "main_instances": main_instances}, "\t"))
	print("[MainOwnership] %d checks, %d failures, %d actual Main instances" % [checks, failures.size(), main_instances])
	call_deferred("quit", 0 if failures.is_empty() else 1)

func _helpers(world: WORLD) -> Dictionary:
	# Exercise the production lazy co-op wrapper without turning this solo lifecycle
	# fixture into a fake multiplayer session.
	world.is_multiplayer = true
	var lazy_config: Object = world.difficulty_provider.get_config_provider()
	world.is_multiplayer = false
	return {
		"world_registry": world.power_registry_instance.get_instance_id(),
		"builder_difficulty": world.encounter_profile_builder.multiplayer_difficulty_config.get_instance_id(),
		"hud_registry": world.hud.power_registry_instance.get_instance_id(),
		"build_panel_registry": world.build_detail_panel.power_registry_instance.get_instance_id(),
		"player_fallback_registry": player_fallback_registry_ids[world.player.get_instance_id()],
		"lazy_coop_difficulty": lazy_config.get_instance_id()
	}

func _clear_first_room_to_checkpoint() -> void:
	var deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		if active_world.choosing_next_room:
			return
		if active_world.encounter_intro_grace_active:
			Input.action_press("move_right")
			await process_frame
			await physics_frame
			Input.action_release("move_right")
		if active_world.reward_selection_ui.is_active():
			_pick_reward({"rewards": []})
		for actor in get_nodes_in_group("enemies"):
			if not actor.is_dead() and not actor.is_spawn_transporting():
				DAMAGEABLE.apply_damage(actor, 1000000, {"source": "fixture_room_clear", "attack_type": "ground"})
		await process_frame
	check(false, "Actual first-room clear produces saved door checkpoint")

func _check_freed(helpers: Dictionary, world_id: int, transition: String) -> void:
	check(not is_instance_id_valid(world_id), transition + ": actual World is freed")
	for kind in helpers:
		check(not is_instance_id_valid(helpers[kind]), transition + ": owned helper freed: " + kind)

func _test_borrowed_helpers(shared_id: int) -> void:
	var owner := BorrowWorld.new()
	root.add_child(owner)
	var registry := preload("res://scripts/power_registry.gd").new()
	owner.add_child(registry)
	var registry_id := registry.get_instance_id()
	for iteration in 3:
		var actor := preload("res://scripts/player.gd").new()
		owner.add_child(actor)
		actor.set_physics_process(false)
		var fallback: Node = actor.upgrade_system.power_registry
		var fallback_id := fallback.get_instance_id()
		check(fallback.get_parent() == actor, "Standalone Player owns its fallback registry")
		actor.set_power_registry(registry)
		check(actor.upgrade_system.power_registry == registry and registry.get_parent() == owner, "Borrowed registry retains its actual owner")
		actor.apply_trial_power("blast_drive")
		check(actor.reward_blast_drive and actor.blast_drive_stacks == 1, "Replaced registry still applies real Arcana")
		actor.free()
		check(not is_instance_id_valid(fallback_id), "Retired borrower frees private fallback")
		check(is_instance_id_valid(registry_id) and registry.get_parent() == owner, "Retired borrower preserves the owner's registry")
		check(is_instance_id_valid(shared_id) and MAPPER._power_registry_instance.get_instance_id() == shared_id, "Retired borrower preserves shared mapper")
	var provider := preload("res://scripts/core/difficulty_scaling_provider.gd").new(owner)
	var wrapper: Node = provider.get_config_provider()
	var wrapper_id := wrapper.get_instance_id()
	check(wrapper.get_parent() == owner and provider.get_config_provider() == wrapper, "Lazy co-op dependency belongs to owner and is reused")
	owner.free()
	check(not is_instance_id_valid(registry_id) and not is_instance_id_valid(wrapper_id), "Owner frees private registry and co-op dependency")
	check(is_instance_id_valid(shared_id), "Owner teardown preserves shared mapper")
	for script in [preload("res://scripts/world_hud.gd"), preload("res://scripts/build_detail_panel.gd"), preload("res://scripts/encounter_profile_builder.gd")]:
		var helper: Node = script.new()
		var owned: Node = helper.get_child(0)
		var owned_id := owned.get_instance_id()
		check(owned.get_parent() == helper, "Detached helper owns dependency before ready")
		helper.free()
		check(not is_instance_id_valid(owned_id), "Detached helper frees dependency without entering tree")
	await process_frame

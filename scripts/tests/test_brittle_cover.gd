extends "res://scripts/tests/test_descent_presentation.gd"

const COVER := preload("res://scripts/core/arena_cover_controller.gd")
const INTERACTIONS := preload("res://scripts/shared/combat_interaction_registry.gd")
const CHARACTERS := preload("res://scripts/character_registry.gd")

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	node_added.connect(audio_retirement.observe_node)
	ProjectSettings.set_setting("application/config/version", "dev-brittle-cover")
	RunContext.telemetry_upload_enabled = false
	RunContext.master_volume_db = -80.0
	RunContext.music_volume_db = -80.0
	RunContext.sfx_volume_db = -80.0
	RunContext.multiplayer_session_id = ""
	RunContext.active_ascension_loadout = []
	RunContext.run_mode = ENUMS.RunMode.STANDARD
	RunContext.current_difficulty_tier = 1
	RunContext.clear_resume_saved_run_request()
	RunContext.clear_active_run()
	MultiplayerSessionManager.session_connected = false
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	var store := PROFILE.new()
	var profile := store.load_or_create_profile()
	profile.first_descent_tutorial_completed = true
	store.save_profile(profile)
	_test_controller()
	for character in CHARACTERS.get_launch_character_ids():
		_setup_world(character)
		await _test_native_attacks(character)
		if character == "bastion":
			await _test_authority_and_shapes()
			_test_room_state_lifetime()
			await _test_orbit_release()
		current_scene = null
		world.queue_free()
		world = null
		await process_frame
		await process_frame
	RunContext.clear_active_run()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await audio_retirement.wait_until_retired(self), "Native cover scenes retire their audio")
	print("[OK] Brittle cover: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_controller() -> void:
	var layout: Array[Dictionary] = [{"pos": Vector2(100, 0), "radius": 28.0, "break_contacts": 3}, {"pos": Vector2(150, 0), "radius": 28.0, "break_contacts": 3}, {"pos": Vector2(350, 0), "radius": 28.0}]
	var host := COVER.new()
	host.reset(layout)
	check(host.live_layout() == layout and host.revision == 0, "Pristine runtime geometry equals its immutable authored profile")
	var copy := host.live_layout()
	copy[0].radius = 900.0
	check(host.live_layout() == layout, "Runtime geometry snapshots cannot mutate authored or controller data")
	var shapes: Array[Dictionary] = [{"range": 160.0, "arc_degrees": 20.0}, {"range": 240.0, "arc_degrees": 35.0, "inner": 120.0}]
	check(host.contact_candidates(Vector2.ZERO, Vector2.RIGHT, shapes) == [1, 2], "An overlapping cone and Wind annulus produce at most one candidate per column")
	check(host.contact_candidates(Vector2.ZERO, Vector2.LEFT, shapes).is_empty(), "Cover behind the actual attack direction is untouched")
	check(host.contact_candidates(Vector2.ZERO, Vector2.RIGHT, [{"range": 240.0, "arc_degrees": 35.0, "inner": 120.0}]) == [2], "Wind excludes the hollow inner range using existing contact sampling")
	check(not host.apply_contact(3) and not host.apply_contact(0), "Permanent and unknown cover cannot receive brittle contacts")
	for left in [2, 1, 0]:
		check(host.apply_contact(1) and host.contacts_left(1) == left, "Each distinct accepted contact removes one of the three authored marks")
	check(not host.apply_contact(1) and not host.is_present(1) and host.is_present(2), "Destroyed state is terminal and preserves other stable IDs")
	check(host.live_layout().size() == 2 and host.rubble_layout().size() == 1 and host.rubble_layout()[0].contacts_left == 0, "Rubble is separate from the live collision layout")
	var replica := COVER.new()
	replica.reset(layout)
	check(replica.apply_snapshot(host.revision, bytes_to_var(var_to_bytes(host.snapshot()))), "A full native serialized state can skip directly to destruction")
	check(replica.live_layout() == host.live_layout() and replica.rubble_layout() == host.rubble_layout(), "Host and replica resolve identical live and destroyed geometry")
	check(not replica.apply_snapshot(host.revision, host.snapshot()), "Duplicate state revisions are idempotent")
	check(not replica.apply_snapshot(4, [{"id": 1, "left": 1}, {"id": 2, "left": 1}]), "Even a newer revision cannot resurrect cover")
	check(not replica.apply_snapshot(900, host.snapshot()), "Revision must equal actual consumed contacts, not an arbitrary high number")
	check(not replica.apply_snapshot(4, [{"id": 1, "left": 0}, {"id": 1, "left": 2}]), "Malformed duplicate IDs reject the whole update")
	check(not replica.apply_snapshot(4, [{"id": 1, "left": 0}, {"id": 2, "left": -1}]), "Negative remaining contacts reject the whole update")
	check(replica.contacts_left(2) == 3, "Rejected state never partially updates another column")
	host.reset([{"pos": Vector2.ZERO}, {"pos": Vector2.ONE, "break_contacts": "3"}, {"pos": Vector2(3, 0), "break_contacts": 1}])
	check(not host.has_brittle_cover() and host.live_layout().size() == 3, "Legacy and invalid optional metadata remain permanently solid")

func _setup_world(character: String) -> void:
	# Each character is a new run; the prior codec probe saves only doorway
	# metadata, which must never be treated as a complete resume snapshot.
	RunContext.clear_active_run()
	RunContext.selected_character_id = character
	world = MAIN.instantiate() as WORLD
	world.get_node("DebugSettings").enabled = false
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.set_physics_process(false)
	world.reward_selection_ui.close_selection()
	world.reward_selection_ui.reward_skipped.emit(ENUMS.RewardMode.ARCANA, true)
	world.run_session.act_biome_ids = ["shatterfield", "grinding_vault", "void_breach"]
	world._apply_active_biome(1)
	world.player.set_physics_process(false)

func _enter_cover() -> Dictionary:
	var profile: Dictionary = world.encounter_profile_builder.build_debug_encounter_profile("crossfire", 5)
	world._clear_all_enemies()
	world._begin_room(profile)
	# Isolate environmental contact from enemy damage and ordinary room clear.
	world._clear_all_enemies()
	world.active_room_enemy_count = 1
	world.player.set_physics_process(false)
	var target_position: Vector2 = profile.obstacle_layout[1].pos
	world.player.global_position = target_position - Vector2.RIGHT * (world.player.attack_range - 10.0)
	return profile

func _attack() -> void:
	world.player.attack_cooldown_left = 0.0
	world.player.attack_lock_time_left = 0.0
	world.player._try_execute_attack(Vector2.RIGHT)

func _action(source: String = "melee") -> Dictionary:
	return INTERACTIONS.damage_context(world.player.new_combat_action(source), source).interaction

func _test_native_attacks(character: String) -> void:
	var profile := _enter_cover()
	var original := profile.duplicate(true)
	check(world.hud.room_banner_subtitle_label.text == "Attack cracked columns to open a lane", "Only the authored room explains its breakable cover during the existing survey: " + character)
	_attack()
	check(world._arena_cover.contacts_left(2) == 3, "Survey-phase contact is rejected on the authoritative boundary: " + character)
	world._exit_encounter_intro_grace()
	world.player.apply_trial_power("storm_crown")
	world.player.apply_trial_power("sigil_chain")
	world.player.iron_retort_brace_ready = true
	var body: StaticBody2D = world._arena_cover_bodies[2]
	await physics_frame
	await process_frame
	var query := PhysicsRayQueryParameters2D.create(body.global_position - Vector2(40, 0), body.global_position + Vector2(40, 0), 1)
	query.exclude = [world.player.get_rid()]
	check(world.get_world_2d().direct_space_state.intersect_ray(query).get("collider") == body, "Intact column is real projectile/terrain cover: " + character)
	for left in [2, 1, 0]:
		_attack()
		check(world._arena_cover.contacts_left(2) == left, "Actual accepted Attack advances one cover contact: %s/%d" % [character, left])
	check(not body.is_in_group("arena_columns") and body.collision_layer == 0 and body.is_queued_for_deletion(), "Broken cover is immediately unavailable to physics and anchor consumers: " + character)
	check(world._active_obstacle_nodes.size() == 3 and world.renderer.obstacle_layout.size() == 3 and world.enemy_spawner.obstacle_circles.size() == 3, "Breaking one column updates bodies, renderer and spawn exclusions together: " + character)
	check(world.player.storm_crown_hit_counter == 0 and world.player._sigil_chain_charge == 0 and world.player.iron_retort_brace_ready, "Cover does not become enemy-hit resources or consume Retort: " + character)
	check(world.run_summary_recorder.run_summary_tracker.total_damage_dealt == 0 and world.run_summary_recorder.run_summary_tracker.enemies_killed == 0, "Cover grants no damage or kill statistics: " + character)
	check(profile == original and world._arena_cover.contacts_left(3) == 3, "Contact does not alter the offered profile or the other brittle column: " + character)
	await physics_frame
	await process_frame
	check(world.get_world_2d().direct_space_state.intersect_ray(query).is_empty(), "Projectiles and world raycasts see the opened gap: " + character)
	var door := CONTRACTS.standard_encounter_door_option(profile)
	check(RunContext.save_active_run({"door_options": [door]}), "Authored cover metadata uses the existing safe checkpoint codec")
	var restored: Dictionary = RunContext.load_active_run()
	check(CONTRACTS.door_option_profile(restored.door_options[0]) == original, "Continue's saved offered profile starts untouched instead of persisting unsaved combat damage")
	var legacy := profile.duplicate(true)
	for entry in legacy.obstacle_layout:
		entry.erase("break_contacts")
	world._begin_room(legacy)
	world._clear_all_enemies()
	world.active_room_enemy_count = 1
	world._exit_encounter_intro_grace()
	_attack()
	check(not world._arena_cover.has_brittle_cover() and world._active_obstacle_nodes.size() == 4 and world._arena_cover.rubble_layout().is_empty(), "An old serialized room stays solid and clears previous rubble: " + character)

func _test_authority_and_shapes() -> void:
	_enter_cover()
	world._exit_encounter_intro_grace()
	var action := _action()
	var origin: Vector2 = world.player.global_position
	world.request_brittle_cover_attack(action, origin + Vector2(10000, 0), Vector2.RIGHT)
	world.request_brittle_cover_attack(action, origin, Vector2.INF)
	world.request_brittle_cover_attack(action, origin, Vector2.ZERO)
	check(world._arena_cover.contacts_left(2) == 3, "Distant origins and invalid aim cannot consume cover")
	world._set_combat_paused(true)
	world.request_brittle_cover_attack(action, origin, Vector2.RIGHT)
	world._set_combat_paused(false)
	check(world._arena_cover.contacts_left(2) == 3, "Paused combat cannot accept a cover contact")
	# Pausing cancels the old input epoch; the next accepted Attack has a new one.
	action = _action()
	world.request_brittle_cover_attack(action, origin, Vector2.RIGHT)
	world.request_brittle_cover_attack(action, origin, Vector2.RIGHT)
	check(world._arena_cover.contacts_left(2) == 2, "Duplicate requests for an accepted action are one contact per column")
	var stale := _action()
	world.player._cancel_interactions()
	world.request_brittle_cover_attack(stale, origin, Vector2.RIGHT)
	for source in ["sovereigns_double", "static_wake", "storm_crown", "returning_crescent", "rupture_wave", "razor_wind"]:
		world.request_brittle_cover_attack(_action(source), origin, Vector2.RIGHT)
	check(world._arena_cover.contacts_left(2) == 2, "Cancelled epochs and automatic/independent descendant requests never contact cover")
	world.request_brittle_cover_attack(_action("blast_drive"), origin, Vector2.RIGHT, 1.0)
	check(world._arena_cover.contacts_left(2) == 2, "A player without Blast cannot nominate charged Blast geometry")
	world.player.apply_trial_power("blast_drive")
	world.request_brittle_cover_attack(_action("blast_drive"), origin, Vector2.RIGHT, 1.01)
	check(world._arena_cover.contacts_left(2) == 2, "Charged Blast strength is bounded before geometry derivation")
	world.player.perform_motion_blast(Vector2.RIGHT, 1.0)
	check(world._arena_cover.contacts_left(2) == 1, "An actual charged Blast is one deliberate cover contact")
	_enter_cover()
	world._exit_encounter_intro_grace()
	world.player.apply_trial_power("razor_wind")
	var target: Node2D = world._arena_cover_bodies[2]
	world.player.global_position = target.global_position - Vector2.RIGHT * (world.player.attack_range + 40.0)
	_attack()
	check(world._arena_cover.contacts_left(2) == 2, "Actual Razor Wind reaches a column beyond the melee cone using its own annulus")
	var previous_run := _action()
	previous_run.run = "retired-run"
	world.request_brittle_cover_attack(previous_run, world.player.global_position, Vector2.RIGHT)
	check(world._arena_cover.contacts_left(2) == 2, "A previous run action cannot affect the current room")
	await process_frame

func _test_room_state_lifetime() -> void:
	_enter_cover()
	world._exit_encounter_intro_grace()
	var retired_action := _action()
	var retired_state: Dictionary = world._cover_state_payload()
	retired_state.revision = 1
	retired_state.columns = [{"id": 2, "left": 2}, {"id": 3, "left": 3}]
	_enter_cover()
	world._exit_encounter_intro_grace()
	world.request_brittle_cover_attack(retired_action, world.player.global_position, Vector2.RIGHT)
	world._apply_brittle_cover_state(retired_state)
	check(world._arena_cover.contacts_left(2) == 3, "Previous-room actions and receiver states cannot touch a new room's cover")
	var old_run: Dictionary = world._cover_state_payload()
	old_run.run = "retired-run"
	old_run.revision = 1
	old_run.columns = retired_state.columns.duplicate(true)
	world._apply_brittle_cover_state(old_run)
	check(world._arena_cover.contacts_left(2) == 3, "Previous-run receiver states cannot touch the current cover")
	world._pending_cover_state = retired_state.duplicate(true)
	_enter_cover()
	check(world._pending_cover_state.is_empty() and world._arena_cover.contacts_left(2) == 3, "Room entry discards an old-room queued state")
	old_run.room = world.get_current_room_sync_id() + 1
	world._pending_cover_state = old_run
	_enter_cover()
	check(world._pending_cover_state.is_empty() and world._arena_cover.contacts_left(2) == 3, "Room entry discards an old-run queued state even when its room number matches")
	var next_state: Dictionary = world._cover_state_payload()
	next_state.room = world.get_current_room_sync_id() + 1
	next_state.revision = 3
	next_state.columns = [{"id": 2, "left": 0}, {"id": 3, "left": 3}]
	world._pending_cover_state = next_state
	_enter_cover()
	check(world._pending_cover_state.is_empty() and world._arena_cover.contacts_left(2) == 0 and world.renderer.obstacle_layout.size() == 3, "A matching queued full state applies after geometry exists, including destruction")
	_enter_cover()
	check(world._arena_cover.revision == 0 and world._arena_cover.contacts_left(2) == 3 and world.renderer.obstacle_layout.size() == 4, "An ordinary later room creates fresh cover with no prior damage or revision")

func _test_orbit_release() -> void:
	_enter_cover()
	world._exit_encounter_intro_grace()
	world.player.apply_trial_power("razor_orbit")
	world.player.apply_trial_power("razor_orbit")
	world.player.apply_trial_power("razor_orbit")
	# The preceding state cases replace several rooms in one frame. Retire
	# their queued bodies before testing the real grapple sight query.
	await physics_frame
	await process_frame
	var body: StaticBody2D = world._arena_cover_bodies[2]
	world.player.arcana_motion.start_orbit(body)
	check(world.player.arcana_motion.anchor == body and world.player.arcana_motion.motion == world.player.ARCANA_MOTION_SCRIPT.Motion.ORBIT, "The current visible column is a live Orbit anchor before destruction")
	world.player.arcana_motion.tangent = Vector2.DOWN
	for _contact in range(3):
		world.request_brittle_cover_attack(_action(), world.player.global_position, Vector2.RIGHT)
	check(world.player.arcana_motion.anchor == null and world.player.arcana_motion.motion == world.player.ARCANA_MOTION_SCRIPT.Motion.CARRY, "Destruction of a live Orbit anchor uses the normal tangential release")
	check(not world.player.arcana_motion.orbit_transferred and not body.is_in_group("arena_columns"), "Broken terrain cannot grant an enemy-death transfer or be reacquired")
	world._enter_rest_site()
	check(world._arena_cover.rubble_layout().is_empty() and world._arena_cover_bodies.is_empty() and world.renderer.obstacle_layout.is_empty(), "Next-room entry clears every live and destroyed cover state")
	await process_frame

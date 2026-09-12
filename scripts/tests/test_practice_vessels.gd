extends "res://scripts/tests/test_warden_practice.gd"
## Actual Practice/Player/Warden with staged positions and manual normal-action
## timing. This proves base passive integration and isolation, not human balance.

const VESSELS := preload("res://scripts/character_registry.gd")

func _run() -> void:
	if not _is_isolated():
		quit(1)
		return
	_test_detached_unlocks()
	await _prepare_normal_checkpoint()
	RunContext.meta_progress_profile["character_state"] = {"selected_character_id": "hexweaver", "unlocked_character_ids": VESSELS.get_launch_character_ids()}
	RunContext.save_meta_progress()
	RunContext.unlocked_character_ids = ["bastion"] # Detect accidental cache normalization too.
	file_baseline = _file_hashes()
	context_baseline = _context_state()
	_new_arena()
	await _start_default_attempt()
	_freeze_motion()
	await _test_pending_choice()
	for id in VESSELS.get_launch_character_ids():
		await _choose(id)
		_check_base_package(id)
		await _exercise_passive(id)
		_check_preserved("Base passive " + id)
	await _test_retirement_and_terminal()
	await _test_normal_continue()
	await _cleanup_recovery_world()
	print("[OK] Practice Vessels: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _context_state() -> Dictionary:
	var state := super._context_state()
	state["unlocked_cache"] = RunContext.unlocked_character_ids.duplicate()
	return state

func _test_detached_unlocks() -> void:
	for profile in [{}, {"character_state": {}}, {"character_state": null}, {"character_state": {"unlocked_character_ids": "invalid"}}, {"character_state": {"unlocked_character_ids": [" HEXWEAVER ", "hexweaver", "unknown", "threadbinder"]}}]:
		var before: Dictionary = profile.duplicate(true)
		var options := ARENA.available_characters_for_profile(profile)
		check(profile == before, "Showing legacy/malformed unlocks never repairs its input profile")
		check(options[0].id == "bastion" and options[0].name == "Bastion", "Bastion remains available for old or incomplete unlock data")
		check(options.all(func(row: Dictionary) -> bool: return VESSELS.is_known_character_id(row.id)), "Only canonical existing Vessels appear")
	var explicit := {"character_state": {"unlocked_character_ids": ["threadbinder", "hexweaver", "hexweaver", "unknown"]}}
	var options := ARENA.available_characters_for_profile(explicit)
	check(options.map(func(row: Dictionary): return row.id) == VESSELS.get_launch_character_ids(), "The sandbox exposes every canonical Vessel regardless of normal unlocks")
	check(options.back().name == "Effigy Keeper", "Stable threadbinder ID uses its current player-facing name")
	options[0].name = "mutated"
	check(ARENA.available_characters_for_profile(explicit)[0].name == "Bastion", "Returned option dictionaries do not alias registry or profile")

func _freeze_motion() -> void:
	arena.set_process(false)
	arena.player.set_physics_process(false)
	arena.boss.set_physics_process(false)

func _test_pending_choice() -> void:
	var first := arena.player.get_instance_id()
	check(arena.current_character_id == "bastion" and arena.next_character_id == "bastion", "Every Practice entry defaults to Bastion despite normal saved selection")
	check(not arena.request_vessel("hexweaver"), "Active combat rejects a stale selector request")
	arena.request_pause()
	check(arena.request_vessel("hexweaver") and arena.next_character_id == "hexweaver", "Pause chooses an unlocked next attempt")
	check(not arena.request_vessel("missing") and not arena.request_vessel("HEXWEAVER"), "Unknown and noncanonical request IDs cannot silently fall back to Bastion")
	var view := arena.presentation()
	view.available_characters.clear()
	view.next_character_id = "riftlancer"
	check(arena.next_character_id == "hexweaver" and arena.presentation().available_characters.size() == 5, "Presentation mutations cannot alter pending choice or its options")
	arena.request_resume()
	check(arena.player.get_instance_id() == first and arena.player.active_character_id == "bastion" and arena.next_character_id == "hexweaver", "Resume keeps the current actor and the explicitly chosen next attempt")
	arena.request_pause()
	check(arena.next_character_id == "hexweaver", "Later Pause retains pending choice")
	MultiplayerSessionManager.connected_peers = {8: {}}
	check(not arena.request_vessel("riftlancer"), "An intervening party rejects new choices")
	arena.request_retry()
	check(not arena._transition_pending and arena.attempt == 1, "An intervening party rejects Retry before changing the attempt")
	MultiplayerSessionManager.connected_peers.clear()
	var original: Dictionary = RunContext.meta_progress_profile.duplicate(true)
	RunContext.meta_progress_profile.character_state.unlocked_character_ids = ["bastion"]
	check(arena.request_vessel("hexweaver"), "The full sandbox permits registered Vessels without a normal unlock")
	arena.request_retry()
	await process_frame
	await process_frame
	_freeze_motion()
	check(arena.attempt == 2 and arena.player.active_character_id == "hexweaver", "Practice creates a locked base Vessel without changing its profile")
	RunContext.meta_progress_profile = original.duplicate(true)
	arena.request_resume()
	arena.player.set_physics_process(true)
	arena.boss.set_physics_process(true)
	var active_actor := arena.player.get_instance_id()
	arena.request_retry()
	MultiplayerSessionManager.connected_peers = {8: {}}
	await process_frame
	check(arena.mode == "active" and arena.player.get_instance_id() == active_actor and arena.player.is_physics_processing() and arena.boss.is_physics_processing(), "A new party aborts deferred Retry and restores the live actor's processing")
	MultiplayerSessionManager.connected_peers.clear()
	_freeze_motion()
	_check_preserved("Pending selection and refused commits")

func _choose(id: String) -> void:
	if arena.mode == "active":
		arena.request_pause()
	check(arena.request_vessel(id), "Choose existing unlocked " + id)
	var old_actor: WeakRef = weakref(arena.player)
	var old_action := arena.player.new_combat_action("melee")
	var old_attempt := arena.attempt
	var music_id := arena.music_system.get_instance_id()
	var score: AudioStreamPlayer = arena.music_system.music_players[arena.music_system.active_music_player_index]
	var playback_id := score.get_stream_playback().get_instance_id()
	Input.action_press("attack")
	Input.action_press("dash")
	arena.request_retry()
	arena.request_retry()
	check(not arena.request_vessel("bastion"), "Queued Retry rejects later stale selection signals")
	await process_frame
	await process_frame
	_freeze_motion()
	check(arena.attempt == old_attempt + 1 and old_actor.get_ref() == null, "Retry creates exactly one fresh actor and retires the previous Vessel")
	check(arena.current_character_id == id and arena.next_character_id == id and arena.player.active_character_id == id, "Retry commits one canonical base character consistently")
	check(arena.player._combat_actions_awaiting_release.has(&"attack") and arena.player._combat_actions_awaiting_release.has(&"dash"), "Selector Retry requires held Attack and Dash to be released")
	check(INTERACTIONS.validate_action(old_action, 1).is_empty(), "Changing Vessels retires the previous attempt's combat action")
	check(arena.music_system.get_instance_id() == music_id and score.get_stream_playback().get_instance_id() == playback_id, "Changing Vessels retains the same shared music playback")
	check(get_nodes_in_group("enemies").size() == 1 and get_nodes_in_group("combat_players").size() == 1, "Exactly one real player and Warden remain after changing Vessels")
	_release_practice_controls()
	for _tick in 3:
		await process_frame
		await physics_frame
		arena.player._refresh_combat_input_release()
	check(arena.player._combat_actions_awaiting_release.is_empty(), "Released controls become available to the new actor")

func _check_base_package(id: String) -> void:
	var package := VESSELS.get_character(id)
	for key in package.stat_modifiers:
		check(is_equal_approx(float(arena.player.get(key)), float(package.stat_modifiers[key])), id + " receives its unchanged base " + String(key))
	check(arena.player.get_current_health() == int(package.stat_modifiers.max_health), id + " starts at full base health")
	check(arena.player.iron_skin_armor == (1 if id == "bastion" else 0), "Bastion armor does not carry into " + id)
	var flags := [arena.player.passive_iron_retort, arena.player.passive_sigil_burst, arena.player.passive_veilstep_rhythm, arena.player.passive_farline_focus, arena.player.passive_effigy_command]
	check(flags.count(true) == 1, id + " has exactly its one base passive")
	check(not arena.player.sigil_burst_ready and not arena.player.veilstep_rhythm_surge_ready and not arena.player.effigy_deployed and arena.player.attack_combo_counter == 0, id + " starts without another attempt's passive resources")
	check(arena.player.upgrade_system.upgrade_stacks.is_empty() and arena.player.upgrade_system.trial_power_stacks.is_empty() and is_equal_approx(arena.player.incoming_damage_taken_mult, 0.92), id + " receives no saved Catalyst, Arcana or Boon and keeps actual Delver scaling")
	check(arena.damage_dealt == 0 and arena.elapsed_seconds == 0.0 and not arena.presentation().has("damage_recap"), "Vessel Retry clears counters without a Practice damage log")
	check(arena.presentation().character_name == package.name and arena.presentation().max_health == package.stat_modifiers.max_health, "Presentation reflects actual " + id + " identity and health")

func _attack(direction: Vector2 = Vector2.RIGHT) -> void:
	arena.player._update_attack_cooldown(1.0)
	arena.player._update_attack_lock(1.0)
	var previous := arena.player.attack_combo_counter
	arena.player._try_execute_attack(direction)
	_capture_audio(root)
	check(arena.player.attack_combo_counter == previous + 1, "A production Attack creates one deliberate action")

func _dash(direction: Vector2) -> void:
	arena.player._update_attack_lock(1.0)
	arena.player._update_dash_cooldown(1.0)
	_release_practice_controls()
	for _tick in 3:
		await process_frame
		await physics_frame
		arena.player._refresh_combat_input_release()
	await process_frame # Input.action_press belongs to this idle-frame boundary.
	Input.action_press("dash")
	var before := {"local": arena.player._is_local_control_owner(), "just": arena.player.is_combat_action_just_pressed(&"dash"), "waiting": arena.player._combat_actions_awaiting_release.duplicate(), "frozen": arena.player.encounter_input_frozen, "lock": arena.player.attack_lock_time_left, "cooldown": arena.player.dash_cooldown_left}
	arena.player._try_start_dash(direction)
	Input.action_release("dash")
	check(arena.player._is_dash_active(), "The base Vessel starts an ordinary Dash: %s" % before)
	for _frame in 32:
		await physics_frame
		if arena.player._is_dash_active():
			arena.player._process_active_dash(1.0 / 60.0)
		arena.player._update_dash_phase_state(1.0 / 60.0)
	_capture_audio(root)
	check(not arena.player._is_dash_active(), "The ordinary Dash completes through production movement")

func _capture_audio(node: Node) -> void:
	# Observe each action's native playback before a later action reuses its
	# player; tree_exiting alone can only see the final playback handle.
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D:
		audio_retirement._capture_playback(node)
	for child in node.get_children():
		_capture_audio(child)

func _exercise_passive(id: String) -> void:
	arena.player.position = Vector2.ZERO
	arena.boss.position = Vector2(80, 0)
	await physics_frame
	var initial := int(arena.boss.get_current_health())
	match id:
		"bastion":
			arena.player.velocity = Vector2.ZERO
			arena.player._update_iron_retort(arena.player.iron_retort_brace_build_time)
			check(arena.player.iron_retort_brace_ready, "Holding still builds the normal Iron Retort brace")
			_attack()
			check(initial - arena.boss.get_current_health() == 70 and not arena.player.iron_retort_brace_ready and arena.player.iron_retort_guard_left > 0.0, "Actual Warden accepts the empowered Attack and Retort burst, consuming brace and granting its normal guard")
		"hexweaver":
			await _dash(Vector2.DOWN)
			check(arena.player.sigil_burst_ready, "Hexweaver's ordinary Dash primes Sigil Burst")
			arena.boss.position = arena.player.position + Vector2(70, 0)
			_attack()
			check(initial - arena.boss.get_current_health() == 48 and not arena.player.sigil_burst_ready, "The actual Warden accepts one28-Damage Attack plus20-Damage Sigil Burst")
		"veilstrider":
			await _dash(Vector2.RIGHT)
			check(arena.player.veilstep_rhythm_shards == 1, "The first real Dash through the Warden gains one Shard")
			await _dash(Vector2.LEFT)
			check(arena.player.veilstep_rhythm_shards == 2 and arena.player.veilstep_rhythm_surge_ready, "The second real touching Dash readies Surge")
			arena.boss.position = arena.player.position + Vector2(arena.player.dash_distance, 0)
			await _dash(Vector2.RIGHT)
			check(initial - arena.boss.get_current_health() == 35 and arena.player.veilstep_rhythm_shards == 0 and not arena.player.veilstep_rhythm_surge_ready, "The empowered Dash ends in one normal35-Damage wave against Warden and spends Surge")
		"riftlancer":
			arena.boss.position = Vector2(35, 0)
			_attack()
			var close_loss := initial - int(arena.boss.get_current_health())
			arena.boss.position = Vector2(125, 0)
			_attack()
			check(close_loss == 14 and initial - arena.boss.get_current_health() - close_loss == 34, "Actual Warden geometry receives Farline's existing14 close/34 precision Damage")
		"threadbinder":
			arena.boss.position = Vector2(310, 0)
			_attack()
			check(arena.player.effigy_deployed and arena.boss.get_current_health() == initial, "The missed deployment Attack places a real Effigy without inventing another hit")
			var anchor := arena.player.effigy_position
			check(EnemyReplicationService.get_current_room_bounds().grow(-16).has_point(anchor), "Effigy placement respects the Practice arena's actual bounds")
			arena.boss.position = anchor + Vector2(70, 0)
			_attack()
			check(initial - arena.boss.get_current_health() == 24, "The next original Attack reaches Warden from the fixed Effigy while the body is out of reach")
			arena.request_pause()
			arena.request_resume()
			check(arena.player.effigy_deployed and arena.player.effigy_position == anchor, "Pause and Resume preserve a deployed Effigy")
			await _dash(Vector2.DOWN)
			check(not arena.player.effigy_deployed and arena.player.get_attack_origin() == arena.player.global_position, "An accepted ordinary Dash recalls Effigy and restores the body origin")
			_attack(Vector2.LEFT)
			check(arena.player.effigy_deployed, "A subsequent deliberate Attack can place a new Effigy after recall")
	check(arena.damage_dealt == initial - arena.boss.get_current_health(), id + " accepted passive damage reaches Practice's local damage counter exactly once")

func _test_retirement_and_terminal() -> void:
	var old_keeper: WeakRef = weakref(arena.player)
	var old_effigy: WeakRef = weakref(arena.player.effigy_controller)
	await _choose("hexweaver")
	check(old_keeper.get_ref() == null and old_effigy.get_ref() == null, "Switching away retires the previous Effigy actor and controller")
	arena.request_pause()
	check(arena.request_vessel("veilstrider"), "The next attempt can be chosen before finishing the current fight")
	arena.request_resume()
	arena.player.take_damage(500, {"source": "enemy_ability", "ability": "warden_nova"})
	check(arena.mode == "defeat" and arena.next_character_id == "veilstrider" and arena.player.get_current_health() == 0, "Defeat retains pending choice after the current Hexweaver loses all75 HP")
	await _choose("veilstrider")
	check(arena.player.get_current_health() == 70 and not arena.presentation().has("damage_recap"), "Defeat Retry applies the next base Vessel and does not expose a damage log")
	arena.boss.health_state.set_health(1)
	var attack := INTERACTIONS.damage_context(arena.player.new_combat_action("melee"), "melee", {"raw_amount": 22.0, "damage_coefficient": 1.0})
	DAMAGE.apply_damage(arena.boss, 22, attack, 1)
	check(arena.mode == "victory" and arena.request_vessel("riftlancer"), "Victory also allows choosing the next attempt without awarding progress")
	_check_preserved("Vessel defeat and victory")
	arena.request_menu()
	await process_frame
	await process_frame
	check(current_scene.scene_file_path == "res://scenes/Menu.tscn", "Vessel Practice returns through the actual normal Menu")
	_check_preserved("Return after all five Vessels")
	current_scene.queue_free()
	current_scene = null
	await process_frame
	_new_arena()
	await _start_default_attempt()
	_freeze_motion()
	check(arena.current_character_id == "bastion" and arena.next_character_id == "bastion", "Leaving Practice discards its current and pending Vessel choices")
	await _choose("threadbinder")
	arena.player.position = Vector2.ZERO
	arena.boss.position = Vector2(310, 0)
	_attack()
	check(arena.player.effigy_deployed, "Direct scene-detach fixture owns a real active Effigy")
	var detached_player: WeakRef = weakref(arena.player)
	var detached_effigy: WeakRef = weakref(arena.player.effigy_controller)
	var detached_action := arena.player.new_combat_action("melee")
	current_scene = null
	arena.queue_free()
	arena = null
	await process_frame
	await process_frame
	check(detached_player.get_ref() == null and detached_effigy.get_ref() == null and get_nodes_in_group("combat_players").is_empty() and get_nodes_in_group("enemies").is_empty(), "Direct active scene teardown retires the actor, Effigy and Warden without using exited feedback")
	check(EnemyReplicationService.world_generator == null and INTERACTIONS.validate_action(detached_action, 1).is_empty(), "Direct teardown releases its owned service and invalidates the previous combat action")
	_check_preserved("Fresh entry and direct scene teardown")

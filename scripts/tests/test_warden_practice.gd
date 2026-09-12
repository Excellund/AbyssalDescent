extends "res://scripts/tests/test_relic_recovery.gd"
## Real standalone scene plus real Main checkpoint/Continue. Only terminal
## health staging and persistence seeds are fixture-controlled; no real profile.

const PRACTICE := preload("res://scenes/Practice.tscn")
const ARENA := preload("res://scripts/practice/practice_arena.gd")
const DAMAGE := preload("res://scripts/shared/damageable.gd")
const INTERACTIONS := preload("res://scripts/shared/combat_interaction_registry.gd")
const TELEMETRY_QUEUE := preload("res://scripts/telemetry_upload_queue.gd")
const LEADERBOARD_QUEUE := preload("res://scripts/leaderboard_upload_queue.gd")
const META_PROGRESS := preload("res://scripts/meta_progress_store.gd")
var arena: ARENA
var file_baseline: Dictionary = {}
var context_baseline: Dictionary = {}
var saved_snapshot: Dictionary = {}

class OtherWorld extends Node2D:
	var current_effective_room_size := Vector2(600, 400)
	var player: Node

func _run() -> void:
	if not _is_isolated():
		quit(1)
		return
	await _prepare_normal_checkpoint()
	await _test_arena_lifecycle()
	await _test_normal_continue()
	await _test_denied_party_ownership()
	await _cleanup_recovery_world()
	print("[OK] Warden Practice: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _prepare_normal_checkpoint() -> void:
	if DisplayServer.get_name() == "headless":
		# --script does not start the production main Window configuration.
		# Give camera/HUD checks an actual supported canvas and window size.
		root.content_scale_size = Vector2i(2560, 1440)
		root.size = Vector2i(1280, 720)
	_setup_recovery_world()
	# The real autoload binds this API in _ready; isolated fixtures suppress
	# that callback. Keep its native OfflineMultiplayerPeer, not a null stand-in.
	MultiplayerSessionManager._multiplayer = get_multiplayer()
	check(not MultiplayerSessionManager.has_active_session_state(), "Native offline multiplayer peer does not count as a party")
	RunContext.profile_name = "PracticeFixture"
	RunContext.profile_uuid = String(world.current_player_profile.player_id)
	RunContext.telemetry_consent_asked = true
	RunContext.set_profile_name("PracticeFixture")
	world.current_player_profile.profile_name = "PracticeFixture"
	world.profile_persistence_store.save_profile(world.current_player_profile)
	world.player.health_state.set_health(77)
	world.room_depth = 7
	world.rooms_cleared = 6
	world._save_active_run_checkpoint()
	saved_snapshot = RunContext.load_active_run().duplicate(true)
	check(not saved_snapshot.is_empty() and int(saved_snapshot.room_depth) == 7, "Actual Main establishes a resumable depth-seven descent")
	HISTORY.append({"run_id": "legitimate-prior-run", "character_id": "hexweaver", "outcome": "death", "deepest_depth": 4})
	TELEMETRY_QUEUE.enqueue({"run_id": "legitimate-pending-telemetry", "game_version": "0.3.1"})
	LEADERBOARD_QUEUE.enqueue({"run_id": "legitimate-pending-leaderboard", "game_version": "0.3.1"})
	RunContext._persist_settings()
	# Future menu setup and an already pending request must remain untouched.
	RunContext.selected_character_id = "hexweaver"
	RunContext.current_difficulty_tier = 2
	for id in ["starting_max_hp_bonus", "damage_reduction"]:
		META_PROGRESS.unlock_catalyst(RunContext.meta_progress_profile, id)
	for id in ["bastion", "hexweaver"]:
		META_PROGRESS.set_equipped_catalyst_ids(RunContext.meta_progress_profile, id, ["starting_max_hp_bonus", "damage_reduction"])
		RunContext.save_ascension_loadout(id, ["hardened_foes"])
	RunContext.restore_active_catalysts("hexweaver", ["starting_max_hp_bonus", "damage_reduction"])
	RunContext.set_active_ascension_loadout(["hardened_foes"], 4)
	RunContext._pending_run_retry = {"fixture": "untouched", "ascension_loadout": ["pressure"]}
	RunContext.request_resume_saved_run()
	world.player.discard_pending_combat_input()
	current_scene = null
	world.queue_free()
	world = null
	await process_frame
	await process_frame
	file_baseline = _file_hashes()
	context_baseline = _context_state()

func _file_hashes() -> Dictionary:
	var result := {}
	var paths: Array[String] = [
		RunContext._active_run_save_path(), RunContext._active_run_save_path() + ".bak", RunContext._active_run_save_path() + ".tmp",
		"user://meta_progress.save", "user://godot_2026_profile.json", "user://run_history.json",
		"user://run_telemetry.save", "user://telemetry_upload_queue.save", "user://leaderboard_upload_queue.save", "user://settings.cfg",
	]
	for path in paths:
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	return result

func _context_state() -> Dictionary:
	return {
		"selected": RunContext.selected_character_id, "bearing": RunContext.current_difficulty_tier,
		"meta": RunContext.meta_progress_profile.duplicate(true), "mode": RunContext.run_mode,
		"ascension": RunContext.active_ascension_loadout.duplicate(true),
		"ascension_tier": RunContext.active_ascension_tier,
		"ascension_proof": RunContext.ascension_tracking_complete,
		"last_outcome": RunContext.get_last_run_outcome(),
		"catalyst_character": RunContext._active_catalyst_character_id,
		"catalysts": RunContext._active_catalyst_ids.duplicate(),
		"retry": RunContext._pending_run_retry.duplicate(true),
		"resume": RunContext.run_resume_request_state.resume_saved_run_requested,
	}

func _check_preserved(label: String) -> void:
	var hashes := _file_hashes()
	for path in file_baseline:
		check(hashes[path] == file_baseline[path], label + ": unchanged " + String(path))
	check(_context_state() == context_baseline, label + ": selected Vessel, Bearing, loadouts, progression and launch requests unchanged")

func _new_arena() -> void:
	arena = PRACTICE.instantiate() as ARENA
	arena.menu_return_state = {"retry_action": "resume", "checkpoint_error": "Fixture retained notice", "discard_visible": false, "focus_practice": true}
	root.add_child(arena)
	current_scene = arena

func _start_default_attempt() -> void:
	check(arena.mode == "setup" and arena.attempt == 0 and arena.player == null and arena.current_config.is_empty(), "Practice begins in detached setup before creating an actor")
	arena.request_start()
	await process_frame
	await process_frame
	check(arena.mode == "active" and arena.attempt == 1, "Explicit Start creates exactly one default base attempt")

func _test_arena_lifecycle() -> void:
	_new_arena()
	await _start_default_attempt()
	await _test_camera_framing()
	check(arena.mode == "active" and arena.attempt == 1, "Actual Practice scene enters one active attempt")
	check(arena.player.active_character_id == "bastion" and arena.player.max_health == 130 and arena.player.damage == 25 and arena.player.passive_iron_retort, "Practice uses the unchanged base Bastion package despite the saved Hexweaver selection")
	check(arena.boss.get_script() == preload("res://scripts/enemy_boss.gd") and arena.boss.get_current_health() == 1100, "Practice uses the production Warden with normal health")
	check(arena.player.get_upgrade_stack_count("farshot") == 0 and is_equal_approx(arena.player.incoming_damage_taken_mult, 0.92), "Default build grants no powers and applies the real Delver incoming-damage multiplier")
	check(EnemyReplicationService.world_generator == arena and EnemyReplicationService.get_current_room_bounds().size == arena.current_effective_room_size, "Real accepted damage and room geometry bind to this arena")
	_check_preserved("Entry")
	var music_node_id := arena.music_system.get_instance_id()
	var music_player: AudioStreamPlayer = arena.music_system.music_players[arena.music_system.active_music_player_index]
	var playback_id := music_player.get_stream_playback().get_instance_id()
	var actor_id := arena.player.get_instance_id()
	var old_action := arena.player.new_combat_action("melee")
	arena.request_pause()
	var before := {"position": arena.player.position, "boss_position": arena.boss.position, "health": arena.player._get_current_health(), "time": arena.elapsed_seconds, "boss_time": arena.boss.state_time_left}
	Input.action_press("attack")
	Input.action_press("dash")
	for _frame in 12:
		await physics_frame
	check(arena.player.position == before.position and arena.boss.position == before.boss_position and arena.player._get_current_health() == before.health and arena.elapsed_seconds == before.time and arena.boss.state_time_left == before.boss_time, "Pause freezes both combat actors and elapsed attempt time")
	arena.request_resume()
	var actions := [0, 0]
	arena.player.primary_attack_fired.connect(func(): actions[0] += 1)
	arena.player.normal_dash_started.connect(func(): actions[1] += 1)
	for _frame in 4:
		await physics_frame
	check(actions == [0, 0], "Closing Pause cannot turn held confirmation input into an Attack or Dash")
	_release_practice_controls()
	_check_preserved("Pause and Resume")
	arena.request_pause()
	Input.action_press("attack")
	Input.action_press("dash")
	arena.request_retry()
	arena.request_retry()
	await process_frame
	await process_frame
	check(arena.attempt == 2 and arena.player.get_instance_id() != actor_id and arena.player._get_current_health() == 130, "Repeated Retry clicks create exactly one fresh full-health attempt")
	_check_visible_arena("Retry")
	var retry_actions := [0, 0]
	arena.player.primary_attack_fired.connect(func(): retry_actions[0] += 1)
	arena.player.normal_dash_started.connect(func(): retry_actions[1] += 1)
	for _frame in 3:
		await physics_frame
	check(retry_actions == [0, 0], "Retry from Pause requires held Attack and Dash to be released")
	_release_practice_controls()
	check(INTERACTIONS.validate_action(old_action, 1).is_empty(), "Retry invalidates the prior attempt's captured combat action")
	check(get_nodes_in_group("enemies").size() == 1 and get_nodes_in_group("combat_players").size() == 1, "Retry retires the previous boss and player groups")
	check(arena.music_system.get_instance_id() == music_node_id and music_player.get_stream_playback().get_instance_id() == playback_id, "Retry retains the same synchronized score playback")
	_check_preserved("Retry")
	# Deliberately staged terminal damage verifies wiring independently of the
	# unmodified active-enemy smoke in test_warden_practice_live_combat.gd.
	DAMAGE.apply_damage(arena.player, 10000, {"source": "enemy_ability", "ability": "fixture_terminal"})
	check(arena.mode == "defeat" and arena.player._get_current_health() == 0, "Accepted lethal damage opens Practice defeat")
	arena._finish_attempt("victory")
	check(arena.mode == "defeat", "Repeated or conflicting terminal callbacks cannot change the attempt outcome")
	_check_preserved("Defeat")
	arena.request_retry()
	await process_frame
	await process_frame
	check(arena.attempt == 3 and arena.mode == "active" and arena.player.combat_damage_enabled, "Defeat Retry resumes genuine combat without invulnerability")
	arena.boss.health_state.set_health(1)
	var context := INTERACTIONS.damage_context(arena.player.new_combat_action("melee"), "melee", {"raw_amount": 25.0, "damage_coefficient": 1.0})
	DAMAGE.apply_damage(arena.boss, 25, context, 1)
	check(arena.mode == "victory" and arena.boss.get_current_health() == 0, "Accepted final damage opens Practice victory without rewards")
	_check_preserved("Victory")
	arena.request_retry()
	await process_frame
	await process_frame
	check(arena.attempt == 4 and arena.boss.get_current_health() == 1100 and arena.music_system.get_instance_id() == music_node_id, "Victory Retry resets the boss while preserving the score")
	arena.request_menu()
	await process_frame
	await process_frame
	check(current_scene.scene_file_path == "res://scenes/Menu.tscn", "Practice returns through the actual normal Menu scene")
	check(current_scene._checkpoint_retry_action == "resume" and current_scene.checkpoint_status_label.text == "Fixture retained notice", "Menu reconstruction preserves the existing Resume retry/error presentation")
	check(EnemyReplicationService.world_generator == null and get_nodes_in_group("enemies").is_empty() and get_nodes_in_group("combat_players").is_empty(), "Return releases arena binding, combat actors and effects")
	_check_preserved("Return to Menu")
	arena = null
	current_scene.queue_free()
	current_scene = null
	await process_frame

func _test_camera_framing() -> void:
	var previous_size := root.size
	var previous_scale := root.content_scale_size
	arena.request_pause()
	root.content_scale_size = Vector2i(2560, 1440)
	for screen in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = screen
		for _frame in 6:
			await process_frame
		_check_visible_arena("Resize to %s" % screen)
		check(arena.current_effective_room_size == Vector2(1260, 900) and arena.player.get_node("Camera2D").is_physics_processing(), "Practice framing preserves the arena and actual camera processing")
	root.size = previous_size
	root.content_scale_size = previous_scale
	for _frame in 6:
		await process_frame
	arena.request_resume()
	_check_visible_arena("Resume after resize")

func _check_visible_arena(label: String) -> void:
	var room := Rect2(-arena.current_effective_room_size * 0.5, arena.current_effective_room_size)
	var projected: Rect2 = arena.get_global_transform_with_canvas() * room
	var available: Rect2 = arena.ui.get_gameplay_rect()
	check(available.size.x > 0.0 and available.size.y > 0.0 and available.grow(0.5).encloses(projected), label + ": the complete fight arena remains between the HUD and footer")

func _test_normal_continue() -> void:
	# Remove only the deliberately staged pending Retry so native Continue can
	# exercise the original checkpoint, as a real Menu Resume click would.
	RunContext._pending_run_retry.clear()
	RunContext.request_resume_saved_run()
	world = MAIN.instantiate() as WORLD
	world.get_node("DebugSettings").enabled = false
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.player.set_physics_process(false)
	check(world.room_depth == 7 and world.rooms_cleared == 6 and world.player._get_current_health() == 77, "Actual Main Continue restores original depth, clear count and health after Practice")
	check(world.current_character_id == "bastion" and EnemyReplicationService.world_generator == world, "Normal Continue restores saved character and owns its normal combat service")
	var previous := HISTORY.load_all().size()
	world._run_summary_finish_run("menu_exit")
	world._run_summary_finish_run("menu_exit")
	check(HISTORY.load_all().size() == previous + 1, "Normal run recording still appends exactly once after leaving Practice")
	current_scene = null
	world.queue_free()
	world = null
	await process_frame
	await process_frame

func _test_denied_party_ownership() -> void:
	var other := OtherWorld.new()
	root.add_child(other)
	var enemy := Node2D.new()
	other.add_child(enemy)
	enemy.add_to_group("enemies")
	enemy.set_physics_process(true)
	EnemyReplicationService.bind_world(other)
	EnemyReplicationService.enemy_nodes_by_id[77] = enemy
	# A real bound ENet host socket must still count as an active transport.
	var server := ENetMultiplayerPeer.new()
	var port := 24000 + int(Time.get_ticks_msec() % 16000)
	var error := server.create_server(port, 1)
	check(error == OK, "Party guard fixture opens an actual local ENet host")
	if error == OK:
		get_multiplayer().multiplayer_peer = server
		check(MultiplayerSessionManager.has_active_session_state(), "A genuine ENet transport still blocks solo practice")
		server.close()
		get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	MultiplayerSessionManager.connected_peers = {8: {}}
	_new_arena()
	check(arena.mode == "error" and arena.player == null and arena.music_system == null, "An existing party rejects Practice before actors, audio or combat binding are created")
	arena.request_retry()
	check(arena.attempt == 0, "Denied entry cannot bypass the party guard through Retry")
	arena.request_menu()
	check(enemy.is_physics_processing(), "Denied entry's Menu request cannot pause another world's enemy")
	await process_frame
	await process_frame
	check(EnemyReplicationService.world_generator == other and EnemyReplicationService.enemy_nodes_by_id.get(77) == enemy and enemy.is_physics_processing(), "Denied entry and return preserve another world's owned registry and processing")
	MultiplayerSessionManager.connected_peers.clear()
	EnemyReplicationService.unbind_world(other)
	other.queue_free()
	current_scene.queue_free()
	current_scene = null
	arena = null
	await process_frame

func _release_practice_controls() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down", "attack", "dash"]:
		Input.action_release(action)

extends "res://scripts/tests/test_power_snapshot.gd"
## Fifth-character access, existing profiles, real checkpoints and co-op packages.

const LOBBY := preload("res://scripts/lobby_controller.gd")
const OATHS := preload("res://scripts/progression/oaths_registry.gd")
const DEBUG_BOOTSTRAP := preload("res://scripts/debug_playtest_bootstrap.gd")
const AUDIO_RETIREMENT := preload("res://scripts/tests/fixture_audio_retirement.gd")
const OLD_ROSTER := ["bastion", "hexweaver", "veilstrider", "riftlancer"]
const NEW_CHARACTER := "threadbinder"

class DisconnectedSession extends Node:
	var session_connected := false
	func is_host() -> bool:
		return false

var retirement := AUDIO_RETIREMENT.new()

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or not DirAccess.dir_exists_absolute("res://validation_fixtures"):
		push_error("Effigy Keeper integration requires the isolated gameplay regression helper")
		quit(1)
		return
	node_added.connect(retirement.observe_node)
	_test_normal_unlocks()
	_test_existing_profiles()
	_test_lobby_selection()
	await _test_character_checkpoint()
	for mode in ["host", "joiner"]:
		await _test_coop_packages(mode)
	RunContext.clear_multiplayer_session()
	RunContext.clear_active_run()
	RunContext.clear_resume_saved_run_request()
	HISTORY.clear_all()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	check(await retirement.wait_until_retired(self), "Character fixtures retire native audio before exit")
	print("[OK] Effigy Keeper integration: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_normal_unlocks() -> void:
	var roster := CHARACTER.get_launch_character_ids()
	check(roster.size() == 5 and roster.back() == NEW_CHARACTER, "Effigy Keeper is the fifth playable character")
	check(ENUMS.Character.RIFTLANCER == 3 and ENUMS.Character.THREADBINDER == 4, "Existing serialized character enum values remain stable")
	check(DEBUG_BOOTSTRAP.PLAYTEST_CHARACTERS == roster, "Isolated debug builds expose the complete registered roster")
	RunContext.meta_progress_profile = META._get_default_profile()
	RunContext.selected_character_id = "bastion"
	RunContext.current_difficulty_tier = 0
	check(RunContext.get_unlocked_character_ids() == ["bastion"], "Normal new profiles still start with Bastion only")
	check(not RunContext.set_selected_character_id(NEW_CHARACTER), "Effigy Keeper cannot be selected before the normal unlock")
	for index in OLD_ROSTER.size():
		var cleared_id: String = OLD_ROSTER[index]
		RunContext.award_run_clear_unlocks(cleared_id, 0)
		var expected_id: String = roster[index + 1]
		check(RunContext.consume_just_unlocked_character_id() == expected_id, "Clearing %s unlocks %s once" % [cleared_id, expected_id])
		check(RunContext.consume_just_unlocked_character_id().is_empty(), "Unlock notice is consumed once for " + expected_id)
	check(RunContext.get_unlocked_character_ids() == roster, "Four ordinary clears reach the complete roster")
	RunContext.award_run_clear_unlocks("riftlancer", 0)
	check(RunContext.consume_just_unlocked_character_id().is_empty(), "Repeated Riftlancer clears do not reannounce Effigy Keeper")
	check(RunContext.set_selected_character_id(NEW_CHARACTER), "Unlocked Effigy Keeper is selectable through production RunContext")
	RunContext.meta_progress_profile = META.load_meta_progress()
	check(META.get_selected_character_id(RunContext.meta_progress_profile) == NEW_CHARACTER and META.get_unlocked_character_ids(RunContext.meta_progress_profile) == roster, "Effigy Keeper selection and access survive disk reload")
	check(META.get_character_highest_unlocked_tier(RunContext.meta_progress_profile, NEW_CHARACTER) == 0, "Effigy Keeper starts with independent Pilgrim progression")
	RunContext.award_run_clear_unlocks(NEW_CHARACTER, 0)
	check(META.get_character_highest_unlocked_tier(RunContext.meta_progress_profile, NEW_CHARACTER) == 1 and RunContext.consume_just_unlocked_character_id().is_empty(), "Effigy Keeper clears advance its own Bearing without a phantom next character")
	for bearing in ["pilgrim", "delver", "harbinger", "forsworn"]:
		check(OATHS.get_all_definitions().has("clear_threadbinder_" + bearing), "Effigy Keeper has the ordinary " + bearing + " clear Oath")

func _test_existing_profiles() -> void:
	var profile := META._get_default_profile()
	profile.character_state.unlocked_character_ids = OLD_ROSTER.duplicate()
	profile.character_state.selected_character_id = "riftlancer"
	profile.difficulty_state.per_character.erase(NEW_CHARACTER)
	META.unlock_character_tier(profile, "riftlancer", 3)
	profile.difficulty_state.per_character.erase(NEW_CHARACTER)
	profile.run_stats.total_runs = 29
	profile.milestones.first_clear = true
	check(META.save_meta_progress(profile), "Existing four-character profile writes to isolated disk")
	var loaded := META.load_meta_progress()
	check(META.get_unlocked_character_ids(loaded) == OLD_ROSTER and META.get_selected_character_id(loaded) == "riftlancer", "Loading an existing profile preserves its IDs, selection and unlocks")
	check(META.get_character_highest_unlocked_tier(loaded, NEW_CHARACTER) == 0 and META.get_character_highest_unlocked_tier(loaded, "riftlancer") == 3, "Missing fifth-character difficulty initializes without changing an existing record")
	check(loaded.run_stats.total_runs == 29 and loaded.milestones.first_clear, "Adding the character preserves run statistics and milestones")
	check(META.get_next_character_unlock_for_clear(loaded, "riftlancer") == NEW_CHARACTER, "Existing profiles receive Effigy Keeper from their next Riftlancer clear")
	var legacy := META._migrate_profile(profile, 3)
	check(META.get_unlocked_character_ids(legacy) == OLD_ROSTER and META.get_selected_character_id(legacy) == "riftlancer", "Legacy migration preserves all existing character IDs and selection")

func _test_lobby_selection() -> void:
	var lobby := LOBBY.new()
	lobby.available_characters = CHARACTER.get_launch_character_ids()
	lobby.character_selector = TabContainer.new()
	lobby.add_child(lobby.character_selector)
	lobby.status_label = Label.new()
	lobby.add_child(lobby.status_label)
	var session := DisconnectedSession.new()
	lobby.multiplayer_session_manager = session
	lobby.local_character_id = "bastion"
	lobby._populate_character_tabs()
	check(lobby.character_selector.get_tab_count() == 6 and lobby.character_selector.get_tab_title(4) == "Effigy Keeper", "Co-op lobby includes Effigy Keeper before Random Vessel")
	lobby.character_selector.current_tab = 4
	# Detached tabs do not emit UI signals; drive the production connection.
	lobby.character_selector.tab_changed.emit(4)
	check(lobby.local_character_id == NEW_CHARACTER, "Choosing the fifth lobby tab resolves Effigy Keeper")
	lobby.free()
	session.free()

func _test_character_checkpoint() -> void:
	_setup("solo")
	RunContext.clear_multiplayer_session()
	world.current_character_id = NEW_CHARACTER
	world.player.apply_character_package(CHARACTER.get_character(NEW_CHARACTER))
	world.player.apply_upgrade("heavy_blow")
	world.player.apply_trial_power("dread_resonance")
	world.player.set_health(37)
	world.player._try_execute_attack(Vector2.RIGHT)
	check(world.player.effigy_deployed, "A real deployment exists before the checkpoint is saved")
	var expected := world.player.build_run_snapshot()
	world._save_active_run_checkpoint()
	var saved := RunContext.load_active_run()
	check(String(saved.get("current_character_id", "")) == NEW_CHARACTER, "Actual checkpoint records Effigy Keeper identity")
	RunContext.selected_character_id = "bastion"
	var resumed := _replace_player(saved)
	check(world.current_character_id == NEW_CHARACTER and resumed.active_character_id == NEW_CHARACTER and bool(resumed.get("passive_effigy_command")), "Disk resume reapplies Effigy Keeper and Effigy Command despite a changed menu selection")
	check(resumed.build_run_snapshot() == expected and resumed.get_current_health() == 37, "Resume preserves Effigy Keeper health, stats and learned shared powers")
	check(not resumed.effigy_deployed and resumed.get_attack_origin() == resumed.global_position, "Checkpoint resume cannot restore a previous room's temporary effigy")
	await _cleanup()

func _test_coop_packages(mode: String) -> void:
	_setup(mode)
	RunContext.meta_progress_profile = META._get_default_profile()
	RunContext.selected_character_id = "bastion"
	RunContext.set_peer_character_selection(1, NEW_CHARACTER)
	RunContext.set_peer_character_selection(2, NEW_CHARACTER)
	world._apply_multiplayer_character_packages(RunContext)
	check(world.current_character_id == NEW_CHARACTER and world.player.active_character_id == NEW_CHARACTER, mode + ": lobby selection controls the local character even on a locked solo profile")
	check(actors[0].active_character_id == NEW_CHARACTER and actors[1].active_character_id == NEW_CHARACTER, mode + ": both duplicate-character peers receive Effigy Keeper packages")
	check(bool(actors[0].get("passive_effigy_command")) and bool(actors[1].get("passive_effigy_command")), mode + ": both peers receive Effigy Command")
	check(actors[0].player_body_color != actors[1].player_body_color and actors[0].damage == actors[1].damage, mode + ": duplicate Effigy Keepers retain distinct palettes and equal mechanics")
	check(not META.is_character_unlocked(RunContext.meta_progress_profile, NEW_CHARACTER), mode + ": lobby selection does not grant solo progression")
	await _cleanup()

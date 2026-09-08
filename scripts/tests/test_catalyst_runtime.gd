extends SceneTree

const META := preload("res://scripts/meta_progress_store.gd")
const CATALYSTS := preload("res://scripts/progression/catalyst_registry.gd")
const DIFFICULTY := preload("res://scripts/difficulty_config.gd")
const PROVIDER := preload("res://scripts/core/difficulty_scaling_provider.gd")
const PROFILE_BUILDER := preload("res://scripts/encounter_profile_builder.gd")
const REWARD_UI := preload("res://scripts/reward_selection_ui.gd")
const CHARACTER := preload("res://scripts/character_registry.gd")
const RECORDER := preload("res://scripts/core/run_summary_recorder.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")

class TestContext extends "res://scripts/run_context.gd":
	var saves := 0
	func _ready() -> void:
		pass
	func save_meta_progress() -> bool:
		saves += 1
		return true

class TestPlayer extends "res://scripts/player.gd":
	func _ready() -> void:
		set_physics_process(false)
		_create_health_state()
	func _is_local_control_owner() -> bool:
		return false

class TestHud extends Node:
	func refresh(_state: Dictionary, _player: Node) -> void:
		pass
	func show_banner(_title: String, _subtitle: String = "") -> void:
		pass

class TestSpawner extends "res://scripts/enemy_spawner.gd":
	# Keep the production wave scheduler; avoid spawning irrelevant actors.
	func _spawn_types_immediate(_types: Array, _build_report: bool) -> Array[Dictionary]:
		return []

class TestWorld extends "res://scripts/world_generator.gd":
	var context: TestContext
	var party: Array[Node2D] = []
	var build_broadcasts := 0
	var submitted: Dictionary = {}
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
	func _exit_tree() -> void:
		pass
	func _get_run_context() -> RUN_CONTEXT_SCRIPT:
		return context
	func _clear_all_enemies() -> void:
		pass
	func _reset_all_player_positions_to_slots() -> void:
		pass
	func _apply_camera_bounds_for_room(_size: Vector2) -> void:
		pass
	func _play_room_music(_boss: bool, _instant: bool = false, _fade: float = -1.0) -> void:
		pass
	func _set_combat_paused(_paused: bool) -> void:
		pass
	func _broadcast_local_player_build_snapshot() -> void:
		build_broadcasts += 1
	func _mark_local_reward_phase_complete(_initial: bool, _mode: int) -> void:
		pass
	func _resolve_local_peer_id() -> int:
		return 2
	func _enqueue_leaderboard_submission(summary: Dictionary) -> void:
		submitted = summary.duplicate(true)
	func _run_summary_finish_run(_outcome: String, _payload: Dictionary = {}) -> void:
		pass
	func _broadcast_run_outcome_if_needed(_outcome: String, _tier: int, _label: String, _depth: int) -> void:
		pass
	func _show_victory_feedback(_tier: int, _summary: Dictionary = {}) -> void:
		pass
	## Detached test-only presentation state.
	func _get_hud_state() -> Dictionary:
		return {}
	## Returns a detached party list.
	func _get_multiplayer_player_nodes() -> Array[Node2D]:
		return party.duplicate()

var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)

func _make_world(catalyst_ids: Array, tier: int = 2, coop: bool = false) -> TestWorld:
	var world := TestWorld.new()
	world.context = TestContext.new()
	world.context.meta_progress_profile = META._get_default_profile()
	for id in CATALYSTS.get_catalyst_ids():
		META.unlock_catalyst(world.context.meta_progress_profile, id)
	META.set_equipped_catalyst_ids(world.context.meta_progress_profile, "bastion", catalyst_ids)
	world.context.begin_catalyst_run("bastion")
	world.current_character_id = "bastion"
	world.current_difficulty_tier = tier
	world.is_multiplayer = coop
	root.add_child(world)
	world.player = TestPlayer.new()
	world.add_child(world.player)
	world.player.apply_character_package(CHARACTER.get_character("bastion"))
	world.player.iron_skin_armor = 0
	world.party.append(world.player)
	world.difficulty_provider = PROVIDER.new(world)
	world.enemy_spawner = TestSpawner.new()
	world.add_child(world.enemy_spawner)
	world.encounter_profile_builder = PROFILE_BUILDER.new()
	world.add_child(world.encounter_profile_builder)
	world.encounter_profile_builder.initialize(RandomNumberGenerator.new())
	world.encounter_profile_builder.set_difficulty_tier(tier)
	world.reward_selection_ui = REWARD_UI.new()
	world.add_child(world.reward_selection_ui)
	world._configure_reward_selection_loadout()
	world.hud = TestHud.new()
	world.add_child(world.hud)
	return world

func _free_world(world: TestWorld) -> void:
	if world.difficulty_provider._multiplayer_config != null:
		world.difficulty_provider._multiplayer_config.free()
	world.encounter_profile_builder.multiplayer_difficulty_config.free()
	world.context.free()
	world.free()

func _run() -> void:
	_test_frozen_loadout()
	_test_all_bearings_and_encounters()
	_test_rest_ownership()
	_test_checkpoint_round_trip()
	_test_checkpoint_clear_identity()
	_test_network_damage_modifiers()
	if _failures.is_empty():
		print("Catalyst runtime regression tests passed: %d checks" % _checks)
	quit(0 if _failures.is_empty() else 1)

func _test_frozen_loadout() -> void:
	var world := _make_world(["starting_max_hp_bonus", "damage_reduction"])
	var context := world.context
	var original := context.get_active_catalyst_ids()
	META.set_equipped_catalyst_ids(context.meta_progress_profile, "bastion", ["shop_reroll"])
	_check(context.get_active_catalyst_ids() == original, "Menu equipment changes must not alter an active run")
	original.clear()
	_check(context.get_active_catalyst_ids().size() == 2, "The active IDs getter must return a detached array")
	var payload := context.get_active_catalyst_payload()
	payload["starting_max_hp_add"] = 9999
	_check(context.get_active_catalyst_payload()["starting_max_hp_add"] == 20.0, "Payload callers must not mutate the active loadout")
	_check(context.get_active_catalyst_ids("riftlancer").is_empty(), "A different character must not inherit this run's Catalysts")
	context.begin_catalyst_run("bastion")
	_check(context.get_active_catalyst_ids() == ["shop_reroll"], "A new run must use the new saved equipment")
	context.restore_active_catalysts("bastion", ["damage_reduction", "damage_reduction", "unknown", "rest_heal_bonus", "shop_reroll"])
	_check(context.get_active_catalyst_ids() == ["damage_reduction", "rest_heal_bonus"], "Restore must reject duplicate/unknown IDs and enforce the slot limit")
	_free_world(world)

func _test_all_bearings_and_encounters() -> void:
	var encounters := ["skirmish", "crossfire", "blitz", "onslaught", "fortress", "suppression", "vanguard", "ambush", "gauntlet"]
	for coop in [false, true]:
		for tier in range(4):
			var world := _make_world(["damage_reduction", "ascension_loadout_preset"], tier, coop)
			var base := DIFFICULTY.get_tier_config(tier)
			world._apply_difficulty_tier_bonuses(tier)
			var expected_damage := float(base["player_damage_taken_mult"]) * 0.90
			var expected_contact := float(base["enemy_contact_damage_mult"]) * 0.88
			for encounter in encounters:
				var profile := world.encounter_profile_builder.build_debug_encounter_profile(encounter, 5)
				_check(not profile.is_empty(), "Missing encounter profile: %s" % encounter)
				world._apply_difficulty_tier_bonuses(tier, false)
				_check(is_equal_approx(world.player.incoming_damage_taken_mult, expected_damage), "Veil must persist without compounding across tier %d / %s" % [tier, encounter])
				_check(is_equal_approx(world.player.incoming_contact_damage_mult, expected_contact), "Aegis must persist without compounding across tier %d / %s" % [tier, encounter])
				world.player.set_max_health_and_current(1000, 1000)
				world.player.take_damage(100, {"source": "enemy_projectile"})
				_check(world.player.get_current_health() == 1000 - int(ceil(100.0 * expected_damage)), "Veil must affect actual projectile damage")
				world.player._contact_damage_grace_left = 0.0
				world.player.set_max_health_and_current(1000, 1000)
				world.player.take_damage(100, {"source": "enemy_contact"})
				var expected_hit := int(ceil(ceil(100.0 * expected_damage) * expected_contact))
				_check(world.player.get_current_health() == 1000 - expected_hit, "Aegis must multiply actual contact damage after Veil")
			_free_world(world)
			world = _make_world(["starting_max_hp_bonus", "wave_interval_bonus"], tier, coop)
			var initial_max := world.player.get_max_health()
			world._apply_difficulty_tier_bonuses(tier)
			var expected_max := initial_max + int(base["player_starting_health_bonus"]) + 20
			_check(world.player.get_max_health() == expected_max, "Iron Vigil must add 20 maximum HP at run start")
			world._apply_difficulty_tier_bonuses(tier, false)
			_check(world.player.get_max_health() == expected_max, "Refreshing difficulty must not add starting HP again")
			for encounter in encounters:
				var profile := world.encounter_profile_builder.build_debug_encounter_profile(encounter, 5)
				# Exercise the common scheduler even for an encounter whose normal
				# profile only has one wave at this tier/depth.
				profile["chaser_count"] = 12
				profile["wave_count"] = 3
				world.enemy_spawner.spawn_profile_enemies_report(profile)
				var expected_interval := float(base["wave_interval_seconds"]) * 1.12
				_check(is_equal_approx(world.enemy_spawner._wave_timer_remaining, expected_interval), "Calm must reach the %s wave scheduler on tier %d" % [encounter, tier])
			_free_world(world)

func _test_rest_ownership() -> void:
	for coop in [false, true]:
		for tier in range(4):
			var world := _make_world(["rest_heal_bonus"], tier, coop)
			world._apply_difficulty_tier_bonuses(tier)
			world.player.set_max_health_and_current(200, 10)
			var remote := TestPlayer.new()
			world.add_child(remote)
			remote.set_max_health_and_current(200, 10)
			world.party.append(remote)
			world._heal_local_player_at_rest()
			var base := DIFFICULTY.get_tier_config(tier)
			var expected := 10 + int(round(200.0 * world.rest_heal_ratio * float(base.get("rest_heal_ratio_mult", 1.0)) * 1.35))
			_check(world.player.get_current_health() == mini(200, expected), "Tonic must increase actual rest healing by 35%")
			_check(remote.get_current_health() == 10, "Rest must not also heal a remote avatar with the local Tonic")
			world.player.health_state.current_health = 0
			world._heal_local_player_at_rest()
			_check(world.player.get_current_health() == 0, "Rest healing must not revive a dead player")
			_free_world(world)

func _test_checkpoint_round_trip() -> void:
	var world := _make_world(["starting_max_hp_bonus", "reward_choice_bonus"], 2)
	world._apply_difficulty_tier_bonuses(2)
	world.player.set_max_health_and_current(world.player.get_max_health(), 37)
	var saved_max := world.player.get_max_health()
	var saved := world._build_active_run_snapshot()
	_check(saved["active_catalyst_ids"] == ["starting_max_hp_bonus", "reward_choice_bonus"], "Checkpoint must record actual run equipment")
	META.set_equipped_catalyst_ids(world.context.meta_progress_profile, "bastion", ["damage_reduction"])
	world.context.begin_catalyst_run("bastion")
	world.current_character_id = "hexweaver"
	world.player.apply_character_package(CHARACTER.get_character("hexweaver"))
	world._configure_reward_selection_loadout()
	_check(world._apply_active_run_snapshot(saved), "A Catalyst checkpoint must resume successfully")
	_check(world.context.get_active_catalyst_ids() == ["starting_max_hp_bonus", "reward_choice_bonus"], "Resume must restore the saved loadout after a menu change")
	_check(world.current_character_id == "bastion" and world.player.active_character_id == "bastion", "Resume must keep the saved character's equipment and identity together")
	_check(world.player.get_max_health() == saved_max and world.player.get_current_health() == 37, "Resume must preserve current HP without reapplying Iron Vigil")
	_check(world.reward_selection_ui.boon_choice_count == world.boon_choice_count + 1, "Resume must reconfigure the reward UI from the saved Catalyst")
	var recorder := RECORDER.new(world)
	recorder.reset_summary_tracker()
	_check(recorder.run_summary_tracker.equipped_catalyst_ids == world.context.get_active_catalyst_ids(), "Run summaries must disclose the frozen loadout")
	saved["active_catalyst_ids"] = []
	_check(world._apply_active_run_snapshot(saved), "An explicitly empty saved loadout must resume")
	_check(world.context.get_active_catalyst_ids().is_empty(), "Empty checkpoint equipment must not fall back to menu equipment")
	saved.erase("active_catalyst_ids")
	world.context.begin_catalyst_run("bastion")
	_check(world._apply_active_run_snapshot(saved), "Legacy checkpoints without Catalyst history remain playable")
	_check(world.context.get_active_catalyst_ids() == ["damage_reduction"], "Legacy checkpoints retain previous menu-based behavior")
	_free_world(world)

func _test_checkpoint_clear_identity() -> void:
	var world := _make_world(["starting_max_hp_bonus"], 2)
	var context := world.context
	META.unlock_character_tier(context.meta_progress_profile, "bastion", 2)
	world._apply_difficulty_tier_bonuses(2)
	var saved := world._build_active_run_snapshot()
	META.unlock_character(context.meta_progress_profile, "hexweaver")
	context.set_selected_character_id("hexweaver")
	context.set_difficulty_tier(0)
	world.current_character_id = "hexweaver"
	world.current_difficulty_tier = 0
	_check(world._apply_active_run_snapshot(saved), "A run must resume after changing the menu character and tier")
	world.run_summary_recorder = RECORDER.new(world)
	world.run_summary_recorder.reset_summary_tracker()
	world._finish_third_boss_clear()
	_check(META.get_character_highest_unlocked_tier(context.meta_progress_profile, "bastion") == 3, "A resumed Bastion/Harbinger clear must unlock Bastion's Forsworn tier")
	_check(META.get_character_highest_unlocked_tier(context.meta_progress_profile, "hexweaver") == 0, "A resumed clear must not advance the menu character's difficulty")
	_check(META.get_milestone(context.meta_progress_profile, "first_clear_on_veteran") and not META.get_milestone(context.meta_progress_profile, "first_clear"), "Clear milestones must use the resumed run's tier")
	_check(not META.is_character_unlocked(context.meta_progress_profile, "riftlancer"), "A resumed Bastion clear must not grant Hexweaver's character unlock")
	_check(context.get_selected_character_id() == "hexweaver" and context.current_difficulty_tier == 0, "Run clear rewards must not change the saved menu selection")
	_check(context.saves > 0, "Completed run unlocks must still persist progression")
	_free_world(world)

func _test_network_damage_modifiers() -> void:
	var world := _make_world(["damage_reduction", "ascension_loadout_preset"], 2, true)
	world._apply_difficulty_tier_bonuses(2)
	var replica := TestPlayer.new()
	world.add_child(replica)
	replica.apply_network_build_snapshot(world.player.build_network_build_snapshot())
	_check(replica.get_max_health() == world.player.get_max_health(), "Network builds must preserve the actual maximum health")
	_check(is_equal_approx(replica.incoming_damage_taken_mult, world.player.incoming_damage_taken_mult), "Network builds must preserve Veil for host-side hit detection")
	_check(is_equal_approx(replica.incoming_contact_damage_mult, world.player.incoming_contact_damage_mult), "Network builds must preserve Aegis for host-side hit detection")
	world.run_summary_recorder = RECORDER.new(world)
	world._on_reward_skipped(ENUMS.RewardMode.ARCANA, true)
	_check(world.build_broadcasts == 1, "Skipping starting Arcana must still broadcast the initial Catalyst stats")
	world.run_summary_recorder.reset_summary_tracker()
	world.run_summary_recorder._run_is_debug = true
	var host_summary := {"run_id": "catalyst-host", "outcome": "death", "equipped_catalyst_ids": ["starting_max_hp_bonus"]}
	world.run_summary_recorder.finalize_synced_run_summary_for_joiner(host_summary, "death")
	_check(world.run_summary_recorder.latest_run_summary["equipped_catalyst_ids"] == world.context.get_active_catalyst_ids(), "Joined run history must disclose that player's Catalysts instead of the host's")
	_check(world.submitted["equipped_catalyst_ids"] == world.context.get_active_catalyst_ids(), "Joined leaderboard submission must disclose the player's actual Catalysts")
	_check(host_summary["equipped_catalyst_ids"] == ["starting_max_hp_bonus"], "Joined summary overrides must not mutate the host summary")
	_free_world(world)

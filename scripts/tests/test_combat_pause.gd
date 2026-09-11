extends SceneTree

const PLAYER := preload("res://scripts/player.gd")
const ENEMY := preload("res://scripts/enemy_base.gd")
const PHASE := preload("res://scripts/core/combat_phase_coordinator.gd")
const WEB := preload("res://scripts/web_zone.gd")
const PAUSE_MENU := preload("res://scripts/pause_menu_controller.gd")
const BUILD_PANEL := preload("res://scripts/build_detail_panel.gd")
const REWARD_UI := preload("res://scripts/reward_selection_ui.gd")
const SPAWNER := preload("res://scripts/enemy_spawner.gd")
const RECORDER := preload("res://scripts/core/run_summary_recorder.gd")
const PLAYER_FLOW := preload("res://scripts/core/player_flow_coordinator.gd")
const ENEMY_SYNC := preload("res://scripts/core/enemy_state_sync_broadcaster.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")

# Keep the real modal handlers; skip only scene boot, generation and frame UI.
class World extends "res://scripts/world_generator.gd":
	func _ready() -> void:
		set_process(false)
		set_process_unhandled_input(false)
	func _refresh_frame_ui() -> void:
		pass

var checks := 0
var failures: Array[String] = []
var world: World
var player: PLAYER
var phase: PHASE

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _setup() -> void:
	world = World.new()
	root.add_child(world)
	current_scene = world
	player = PLAYER.new()
	world.add_child(player)
	world.player = player
	phase = PHASE.new()
	world.combat_phase_coordinator = phase
	world.player_flow_coordinator = PLAYER_FLOW.new()
	world.enemy_state_sync_broadcaster = ENEMY_SYNC.new(world)
	world.enemy_spawner = SPAWNER.new()
	world.add_child(world.enemy_spawner)
	world.enemy_spawner.set_process(false)
	world.run_summary_recorder = RECORDER.new(world)
	world.run_summary_recorder.run_started_at_msec = maxi(1, Time.get_ticks_msec())
	world.pause_menu_controller = PAUSE_MENU.new()
	world.add_child(world.pause_menu_controller)
	world.pause_menu_controller.pause_opened.connect(world._on_pause_menu_opened)
	world.pause_menu_controller.pause_closed.connect(world._on_pause_menu_closed)
	world.build_detail_panel = BUILD_PANEL.new()
	world.add_child(world.build_detail_panel)
	world.build_detail_panel.panel = Panel.new()
	world.build_detail_panel.add_child(world.build_detail_panel.panel)
	world.build_detail_panel.build_detail_opened.connect(world._on_build_detail_opened)
	world.build_detail_panel.build_detail_closed.connect(world._on_build_detail_closed)
	world.reward_selection_ui = REWARD_UI.new()
	world.add_child(world.reward_selection_ui)
	for audio in world.find_children("*", "AudioStreamPlayer", true, false):
		(audio as AudioStreamPlayer).stream = null
	for audio in world.find_children("*", "AudioStreamPlayer2D", true, false):
		(audio as AudioStreamPlayer2D).stream = null
	# Hurt feedback normally assigns a fresh random stream at each real hit.
	# Audio is outside this lifecycle test and can outlive forced headless exit.
	player.player_feedback._aux_sfx_player = null

func _cleanup() -> void:
	phase.set_combat_paused(player, self, false)
	player.upgrade_system.power_registry.free()
	world.build_detail_panel.power_registry_instance.free()
	current_scene = null
	world.free()
	world = null
	player = null
	phase = null

func _web() -> WEB:
	var web := WEB.new()
	world.add_child(web)
	web.initialize(player, 64.0, 3.6, 0.5, 6)
	return web

func _enemy() -> ENEMY:
	var enemy := ENEMY.new()
	world.add_child(enemy)
	enemy.position = Vector2(500.0, 0.0)
	return enemy

func _run() -> void:
	await _test_live_web_pause_and_resume()
	await _test_prior_flags_and_removed_nodes()
	await _test_nested_modal_and_transition_pause()
	await _test_combat_cleanup()
	_test_biome_rule_ownership_and_modal_pause()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Combat pause: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_live_web_pause_and_resume() -> void:
	_setup()
	var web := _web()
	var enemy := _enemy()
	var before_health := player.get_current_health()
	var before_lifetime := web.time_left
	var before_tick := web.tick_left
	world.pause_menu_controller.open()
	_check(not player.is_physics_processing() and not enemy.is_physics_processing(), "Pause freezes player and ordinary enemy simulation")
	_check(not enemy.is_processing() and not web.is_processing(), "Pause freezes enemy presentation and independent web hazards")
	await create_timer(0.8).timeout
	_check(player.get_current_health() == before_health, "A real Weaver web cannot damage the player behind Pause")
	_check(is_equal_approx(web.time_left, before_lifetime) and is_equal_approx(web.tick_left, before_tick), "Pause freezes hazard lifetime and time until next hit")
	world.pause_menu_controller.close()
	_check(player.is_physics_processing() and enemy.is_physics_processing() and web.is_processing(), "Closing the final modal restores active simulation")
	await create_timer(0.35).timeout
	_check(player.get_current_health() < before_health and web.time_left < before_lifetime, "The same web resumes its remaining lifetime and damage ticks")
	_cleanup()

func _test_prior_flags_and_removed_nodes() -> void:
	_setup()
	var idle_only := _web()
	idle_only.set_physics_process(false)
	var disabled := _web()
	disabled.set_process(false)
	disabled.set_physics_process(false)
	var disabled_enemy := _enemy()
	disabled_enemy.set_process(false)
	disabled_enemy.set_physics_process(false)
	player.set_physics_process(false)
	var queued := _web()
	var freed := _web()
	phase.set_combat_paused(player, self, true)
	phase.set_combat_paused(player, self, true)
	queued.queue_free()
	freed.free()
	phase.set_combat_paused(player, self, false)
	_check(not player.is_physics_processing(), "Resume preserves a player disabled before pause")
	_check(idle_only.is_processing() and not idle_only.is_physics_processing(), "Repeated pauses preserve distinct original idle and physics flags")
	_check(not disabled.is_processing() and not disabled.is_physics_processing(), "Resume does not activate an already-disabled hazard")
	_check(not disabled_enemy.is_processing() and not disabled_enemy.is_physics_processing(), "Resume does not activate an already-disabled enemy")
	_check(not queued.is_processing(), "A queued hazard is not reactivated before deletion")
	await process_frame
	_check(not is_instance_valid(queued) and not is_instance_valid(freed), "Freed and queued hazards can disappear during pause safely")
	phase.set_combat_paused(player, self, false)
	_check(not disabled.is_processing(), "A redundant resume does not change unrelated processing state")
	_cleanup()

func _test_nested_modal_and_transition_pause() -> void:
	_setup()
	var web := _web()
	world.build_detail_panel.open()
	world.pause_menu_controller.open()
	world.build_detail_panel.close()
	_check(not web.is_processing() and not player.is_physics_processing(), "Releasing Tab behind Pause leaves combat and hazards paused")
	_check(world.enemy_spawner.wave_timer_paused, "Releasing Tab behind Pause does not restart encounter waves")
	world.pause_menu_controller.close()
	_check(web.is_processing() and not world.enemy_spawner.wave_timer_paused, "Closing the final panel resumes hazards and wave timing")

	world.build_detail_panel.open()
	world.pause_menu_controller.open()
	world.pause_menu_controller.close()
	_check(not web.is_processing() and world.enemy_spawner.wave_timer_paused, "Closing Pause while Tab remains held preserves the build-panel pause")
	_check(world.run_summary_recorder._pause_started_at_msec > 0, "The run timer stays paused while another modal remains")
	world.build_detail_panel.close()
	_check(web.is_processing() and world.run_summary_recorder._pause_started_at_msec == 0, "Closing the remaining build panel resumes combat and the run timer")

	world.reward_selection_ui.boon_selection_active = true
	world._set_combat_paused(true)
	world.pause_menu_controller.open()
	world.pause_menu_controller.close()
	_check(not web.is_processing(), "Closing Pause cannot resume an active reward selection")
	world.reward_selection_ui.close_selection()
	world._set_combat_paused(false)
	_check(web.is_processing(), "Reward completion releases the final modal pause")

	world.pause_menu_controller.open()
	world._run_outcome_coordinator.register_player_death(false)
	world._set_combat_paused(true)
	world.pause_menu_controller.close()
	_check(not web.is_processing() and not player.is_physics_processing(), "Closing Pause during defeat transition cannot restart combat")
	_check(world.enemy_spawner.wave_timer_paused, "Defeat transition keeps encounter waves stopped")
	world._reset_for_debug_jump()
	_check(not world._run_outcome_coordinator.is_run_cleared() and player.is_physics_processing(), "Debug jump clears terminal outcome before resolving combat resume")
	_cleanup()

func _test_combat_cleanup() -> void:
	_setup()
	var web := _web()
	phase.set_combat_paused(player, self, true)
	phase.end_combat_phase(player, self)
	phase.set_combat_paused(player, self, false)
	_check(web.is_queued_for_deletion() and not web.is_processing(), "Combat completion clears a paused web without a final damage tick")
	_check(not player.combat_damage_enabled, "Resuming processing does not re-enable damage after combat completion")
	var health := player.get_current_health()
	await process_frame
	_check(not is_instance_valid(web) and player.get_current_health() == health, "A cleared paused hazard disappears without further damage")
	var stale_web := _web()
	phase.begin_combat_phase(player, self)
	_check(player.combat_damage_enabled and stale_web.is_queued_for_deletion(), "New combat enables damage and clears stale lingering hazards")
	_cleanup()

func _test_biome_rule_ownership_and_modal_pause() -> void:
	_setup()
	_check(not is_instance_valid(world._biome_rules), "A skipped-bootstrap world does not allocate an orphan biome node")
	world._ensure_biome_rules()
	var rules := world._biome_rules
	var owned_rules: WeakRef = weakref(rules)
	_check(rules.get_parent() == world, "Lazily created biome rules immediately belong to their world")
	rules.configure({"id": "storm_reach"}, Vector2(1040, 760), "modal-fixture", 1)
	rules.tick(2.5, true, [player], [], true)
	var warning: Dictionary = rules.snapshot()
	_check(warning.phase == "warning" and rules._combat_visible, "The modal fixture begins with a visible committed warning")
	world.pause_menu_controller.open()
	world._process(0.25)
	_check(not rules._combat_visible and rules.snapshot() == warning, "The real Pause frame hides the biome warning without consuming its remaining time")
	world.build_detail_panel.open()
	world.pause_menu_controller.close()
	world._process(0.25)
	_check(not rules._combat_visible and rules.snapshot() == warning, "Build Details keeps the same warning hidden after Pause closes")
	world.build_detail_panel.close()
	world.reward_selection_ui.boon_selection_active = true
	world._process(0.25)
	_check(not rules._combat_visible and rules.snapshot() == warning, "Reward selection hides a retained replica warning without advancing its event")
	world.reward_selection_ui.close_selection()
	world._active_biome_rule_id = "storm_reach"
	world.choosing_next_room = false
	world.encounter_intro_grace_active = false
	world._tick_biome_rules(0.1)
	_check(rules._combat_visible and is_equal_approx(rules.phase_left, float(warning.left) - 0.1), "Returning to combat resumes the existing warning through the world lifecycle")
	_cleanup()
	_check(owned_rules.get_ref() == null, "Freeing a skipped-bootstrap world also frees its lazily owned biome controller")

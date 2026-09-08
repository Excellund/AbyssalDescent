extends SceneTree

const PLAYER := preload("res://scripts/player.gd")
const COMBAT_PHASE := preload("res://scripts/core/combat_phase_coordinator.gd")
const POWERS := preload("res://scripts/power_registry.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")

# Exercise the real reward confirmation path without depending on mouse layout.
class FirstChoiceUI extends "res://scripts/reward_selection_ui.gd":
	func _update_boon_hover() -> void:
		boon_hovered_index = 0

var _failures: Array[String] = []
var _attacks := 0
var _selections := 0
var _skips := 0
var _player: PLAYER
var _phase = COMBAT_PHASE.new()

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	_player = PLAYER.new()
	root.add_child(_player)
	_player.set_physics_process(false)
	# This suite checks combat input, not audio. Repeated attack sounds can leave
	# mixer-thread playback references alive during headless process shutdown.
	_player.player_feedback.attack_swing_sound_player.stream = null
	_player.primary_attack_fired.connect(func(): _attacks += 1)
	var ui := FirstChoiceUI.new()
	root.add_child(ui)
	ui.initialize(1, 0.0)
	ui.reward_selected.connect(func(_choice: Dictionary, _mode: int, _initial: bool):
		_selections += 1
		_phase.set_combat_paused(_player, self, false)
		_player.set_physics_process(false))
	ui.reward_skipped.connect(func(_mode: int, _initial: bool):
		_skips += 1
		_phase.set_combat_paused(_player, self, false)
		_player.set_physics_process(false))
	var registry := POWERS.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 123

	for mode in [ENUMS.RewardMode.ARCANA, ENUMS.RewardMode.BOON, ENUMS.RewardMode.BOSS, ENUMS.RewardMode.MISSION]:
		await _release_actions()
		_phase.set_combat_paused(_player, self, true)
		ui.open_selection("Test reward", mode == ENUMS.RewardMode.ARCANA, mode, registry, _player, rng)
		ui.boon_confirm_lock_time = 0.0
		var attacks_before := _attacks
		var selections_before := _selections
		Input.action_press("attack")
		ui.process_input(0.016)
		_check(_selections == selections_before + 1, "Reward mode %d did not confirm" % mode)
		_check(not ui.is_active(), "Reward mode %d remained active" % mode)
		_player._try_attack_input()
		_check(_attacks == attacks_before, "Reward mode %d leaked a primary attack" % mode)
		_check(not _player.is_combat_action_just_pressed(&"attack"), "Reward click can skip arena survey")
		await physics_frame
		_player._refresh_combat_input_release()
		_player._try_attack_input()
		_check(_attacks == attacks_before, "Reward click leaked into next physics frame")
		await _release_actions()
		_player.attack_cooldown_left = 0.0
		_player.attack_lock_time_left = 0.0
		Input.action_press("attack")
		_player._try_attack_input()
		_check(_attacks == attacks_before + 1, "Fresh attack was blocked after reward mode %d" % mode)
		ui.close_selection()

	# Mouse skip and keyboard activation (Space) must not become combat actions.
	await _release_actions()
	_phase.set_combat_paused(_player, self, true)
	ui.open_selection("Skip", false, ENUMS.RewardMode.BOON, registry, _player, rng)
	ui.boon_confirm_lock_time = 0.0
	Input.action_press("attack")
	Input.action_press("dash")
	ui._on_skip_button_pressed()
	_check(_skips == 1, "Skip signal was not emitted")
	_player.attack_cooldown_left = 0.0
	_player.attack_lock_time_left = 0.0
	_player.dash_cooldown_left = 0.0
	var attacks_before_skip := _attacks
	_player._try_attack_input()
	_player._try_start_dash(Vector2.RIGHT)
	_check(_attacks == attacks_before_skip, "Skip leaked an attack")
	_check(_player.dash_remaining_distance == 0.0, "Skip leaked a dash")

	# A fast press/release still belongs to the UI in the confirmation tick.
	await _release_actions()
	_phase.set_combat_paused(_player, self, true)
	Input.action_press("attack")
	Input.action_release("attack")
	_phase.set_combat_paused(_player, self, false)
	_player.set_physics_process(false)
	_player._refresh_combat_input_release()
	_check(not _player.is_combat_action_just_pressed(&"attack"), "Quick click escaped suppression")

	# Pausing cancels an already-buffered attack; survey must not execute one.
	_player.queued_attack_after_dash = true
	_phase.set_combat_paused(_player, self, true)
	_check(not _player.queued_attack_after_dash, "Modal retained a buffered dash attack")
	_player.queued_attack_after_dash = true
	_player.encounter_input_frozen = true
	var attacks_before_survey := _attacks
	_player._try_consume_queued_attack()
	_check(_attacks == attacks_before_survey, "Buffered attack fired during arena survey")
	_player.queued_attack_after_dash = false
	_player.encounter_input_frozen = false

	# In co-op another player may finish much later, after our click is released.
	await _release_actions()
	_phase.set_combat_paused(_player, self, true)
	Input.action_press("attack")
	await _release_actions()
	_phase.set_combat_paused(_player, self, false)
	_player.set_physics_process(false)
	_player.attack_cooldown_left = 0.0
	_player.attack_lock_time_left = 0.0
	var attacks_before_wait := _attacks
	Input.action_press("attack")
	_player._try_attack_input()
	_check(_attacks == attacks_before_wait + 1, "Delayed party resume blocked a new attack")

	await _release_actions()
	for audio_node in root.find_children("*", "AudioStreamPlayer", true, false):
		(audio_node as AudioStreamPlayer).stop()
	for audio_node in root.find_children("*", "AudioStreamPlayer2D", true, false):
		(audio_node as AudioStreamPlayer2D).stop()
	await create_timer(0.05).timeout
	ui.free()
	registry.free()
	_player.upgrade_system.power_registry.free()
	_player.free()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	if _failures.is_empty():
		print("[OK] Reward confirmation, skip, release, buffered attack, and delayed resume regression checks")
	quit(0 if _failures.is_empty() else 1)

func _release_actions() -> void:
	Input.action_release("attack")
	Input.action_release("dash")
	await process_frame
	await physics_frame
	await process_frame
	_player._refresh_combat_input_release()

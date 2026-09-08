extends SceneTree

const REGISTRY := preload("res://scripts/power_registry.gd")
const UPGRADES := preload("res://scripts/upgrade_system.gd")
const MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const CATALYSTS := preload("res://scripts/progression/catalyst_registry.gd")
const ENUMS := preload("res://scripts/shared/enums.gd")

class RewardPlayer extends "res://scripts/player.gd":
	func _ready() -> void:
		set_physics_process(false)
		_create_health_state()
		var registry := REGISTRY.new()
		add_child(registry)
		upgrade_system = UPGRADES.new()
		add_child(upgrade_system)
		upgrade_system.initialize(self, null, registry)

class FirstChoiceUI extends "res://scripts/reward_selection_ui.gd":
	func _update_boon_hover() -> void:
		boon_hovered_index = 0

var _checks: int = 0
var _failures: Array[String] = []
var _offer_events: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)

func _has_choice(choices: Array[Dictionary], power_id: String) -> bool:
	for choice in choices:
		if String(choice.get("id", "")) == power_id:
			return true
	return false

func _check_distinct_choices(choices: Array[Dictionary], context: String) -> void:
	var seen: Dictionary = {}
	for choice in choices:
		var power_id := String(choice.get("id", ""))
		_check(not seen.has(power_id), context + " does not duplicate " + power_id)
		seen[power_id] = true

func _run() -> void:
	var player := RewardPlayer.new()
	root.add_child(player)
	var registry: REGISTRY = player.upgrade_system.power_registry
	var rng := RandomNumberGenerator.new()
	rng.seed = 521
	var regular_ui := FirstChoiceUI.new()
	root.add_child(regular_ui)
	regular_ui.initialize(3, 0.0)
	var original_layer := regular_ui.boon_layer
	var original_audio := regular_ui._sfx_player
	regular_ui.initialize(3, 0.1)
	_check(regular_ui.boon_layer == original_layer, "Repeated setup reuses reward layer when choice count is unchanged")
	_check(regular_ui._sfx_player == original_audio, "Repeated setup reuses reward audio")
	_check(regular_ui.boon_reveal_duration == 0.1, "Repeated setup updates reveal duration")
	_check(regular_ui.get_child_count() == 2, "Repeated setup leaves one reward layer and one audio player")
	regular_ui.initialize(4, 0.0)
	_check(not is_instance_valid(original_layer), "Changed loadout removes the previous reward layer")
	_check(regular_ui.get_child_count() == 2, "Changed loadout leaves one reward layer and one audio player")
	_check(regular_ui.boon_card_panels.size() == 4, "Changed loadout rebuilds the correct number of cards")
	_check(regular_ui._sfx_player == original_audio, "Changed choice count preserves reward audio")
	regular_ui.initialize(3, 0.0)
	_check(regular_ui.boon_card_panels.size() == 3, "Removing Draft Compass restores three cards")
	var compass_ui := FirstChoiceUI.new()
	root.add_child(compass_ui)
	var compass_payload := CATALYSTS.merge_payloads(["reward_choice_bonus"])
	compass_ui.initialize(3 + int(compass_payload.get("reward_choice_count_add", 0)), 0.0)
	compass_ui.reward_offers_presented.connect(func(_offers: Array[Dictionary], _mode: int, _initial: bool, _stage: int): _offer_events += 1)

	# All four real registry pools support Draft Compass, including starting Arcana.
	for mode in [ENUMS.RewardMode.BOON, ENUMS.RewardMode.ARCANA, ENUMS.RewardMode.MISSION, ENUMS.RewardMode.BOSS]:
		regular_ui.open_selection("Regular draft", false, mode, registry, player, rng)
		compass_ui.open_selection("Compass draft", false, mode, registry, player, rng)
		_check(regular_ui.boon_choices.size() == 3, "Base choice count for mode %d" % mode)
		_check(compass_ui.boon_choices.size() == 4, "Draft Compass adds a choice for mode %d" % mode)
		_check(compass_ui.boon_card_panels[3].visible, "Extra choice is rendered for mode %d" % mode)
		_check_distinct_choices(compass_ui.boon_choices, "Draft mode %d" % mode)
		regular_ui.close_selection()
		compass_ui.close_selection()
	compass_ui.open_selection("Starting Arcana", true, ENUMS.RewardMode.ARCANA, registry, player, rng)
	_check(compass_ui.boon_choices.size() == 4, "Draft Compass also adds a starting Arcana choice")
	compass_ui.close_selection()

	# Each newly opened eligible offer receives one reroll; mission's fixed bonus
	# is not a second draft and cannot consume or renew that allowance.
	var reroll_payload := CATALYSTS.merge_payloads(["shop_reroll"])
	for mode in [ENUMS.RewardMode.BOON, ENUMS.RewardMode.ARCANA, ENUMS.RewardMode.MISSION, ENUMS.RewardMode.BOSS]:
		compass_ui.configure_catalyst_payload({})
		compass_ui.open_selection("No reroll", false, mode, registry, player, rng)
		_check(not compass_ui._can_reroll_current_offer(), "Reroll requires Catalyst for mode %d" % mode)
		compass_ui.configure_catalyst_payload(reroll_payload)
		compass_ui.open_selection("Reroll draft", false, mode, registry, player, rng)
		_check(compass_ui._reward_rerolls_remaining == 1, "New offer starts with one reroll for mode %d" % mode)
		var offers_before := _offer_events
		_check(compass_ui._reroll_current_offer(), "Reroll succeeds for mode %d" % mode)
		_check(_offer_events == offers_before + 1, "Rerolled choices are recorded for mode %d" % mode)
		_check(compass_ui.boon_choices.size() == 4, "Reroll preserves Draft Compass for mode %d" % mode)
		_check_distinct_choices(compass_ui.boon_choices, "Reroll mode %d" % mode)
		_check(compass_ui._reward_rerolls_remaining == 0, "Reroll is consumed for mode %d" % mode)
		_check(not compass_ui._reroll_current_offer(), "Second reroll is blocked for mode %d" % mode)
		compass_ui.close_selection()
		compass_ui.open_selection("Next draft", false, mode, registry, player, rng)
		_check(compass_ui._can_reroll_current_offer(), "Next offer restores reroll for mode %d" % mode)
		compass_ui.close_selection()

	for mode in [ENUMS.RewardMode.BOON, ENUMS.RewardMode.ARCANA, ENUMS.RewardMode.MISSION, ENUMS.RewardMode.BOSS]:
		compass_ui.open_selection("Initial draft", true, mode, registry, player, rng)
		_check(compass_ui._can_reroll_current_offer() == (mode == ENUMS.RewardMode.ARCANA), "Only starting Arcana is an eligible initial reroll for mode %d" % mode)
		compass_ui.close_selection()

	for spend_reroll in [false, true]:
		Input.action_release("attack")
		await process_frame
		await physics_frame
		await process_frame
		var mutator := {"name": "Combo Relay", "id": "combo_relay"}
		compass_ui.open_selection("Mission", false, ENUMS.RewardMode.MISSION, registry, player, rng, mutator)
		if spend_reroll:
			_check(compass_ui._reroll_current_offer(), "Mission's first draft can be rerolled")
		compass_ui.boon_confirm_lock_time = 0.0
		compass_ui.process_input(0.016)
		Input.action_press("attack")
		compass_ui.process_input(0.016)
		Input.action_release("attack")
		await process_frame
		_check(compass_ui.mission_reward_stage == 1, "Mission selection reaches actual bonus stage")
		_check(not compass_ui.pending_mission_upgrade_choice.is_empty(), "Mission preserves selected draft reward")
		_check(compass_ui.boon_choices.size() == 1, "Draft Compass leaves fixed mission bonus as one claim")
		_check(not compass_ui.reroll_button.visible, "Mission bonus immediately hides stale reroll button")
		_check(not compass_ui._can_reroll_current_offer(), "Mission bonus cannot be rerolled")
		_check(compass_ui._reward_rerolls_remaining == (0 if spend_reroll else 1), "Mission bonus does not reset reroll allowance")
		compass_ui.close_selection()

	# The Catalyst permits one Prismatic enhancement of each maxed Arcana.
	# Ordinary stacks remain at their real cap, and every enhanced Arcana leaves
	# the offer pool after its final pick.
	var prismatic_payload := CATALYSTS.merge_payloads(["extra_arcana_slot"])
	compass_ui.configure_catalyst_payload(prismatic_payload)
	compass_ui.open_selection("Arcana", false, ENUMS.RewardMode.ARCANA, registry, player, rng)
	_check(compass_ui.boon_card_stack_labels[0].text == "◇◇◇", "Fresh Arcana shows the three actual ordinary stacks")
	compass_ui.close_selection()
	var all_arcana := registry.get_trial_power_pool(player)
	for choice in all_arcana:
		var power_id := String(choice.get("id", ""))
		var stack_limit := int(choice.get("stack_limit", 0))
		for _stack in range(stack_limit):
			_check(player.upgrade_system.apply_trial_power(power_id), "Apply ordinary stack of " + power_id)
		compass_ui.configure_catalyst_payload({})
		_check(not _has_choice(compass_ui._roll_arcana_choices(100, registry, player, rng), power_id), "Maxed " + power_id + " is excluded without Catalyst")
		compass_ui.configure_catalyst_payload(prismatic_payload)
		var available := compass_ui._roll_arcana_choices(100, registry, player, rng)
		_check(_has_choice(available, power_id), "Catalyst offers Prismatic " + power_id)
		compass_ui.open_selection("Prismatic", false, ENUMS.RewardMode.ARCANA, registry, player, rng)
		compass_ui.boon_choices = [choice]
		compass_ui._refresh_boon_ui(player)
		_check(compass_ui.boon_card_stack_labels[0].text == "Prismatic", "Card identifies Prismatic " + power_id)
		_check(compass_ui.boon_card_stack_labels[0].get_minimum_size().x <= 210.0, "Prismatic label fits its card column")
		_check(player.upgrade_system.apply_trial_power(power_id), "Apply Prismatic " + power_id)
		_check(player.has_trial_power_prismatic(power_id), "Player records Prismatic " + power_id)
		_check(player.get_trial_power_stack_count(power_id) == stack_limit, "Prismatic preserves ordinary stack cap for " + power_id)
		_check(not player.upgrade_system.apply_trial_power(power_id), "Prismatic cannot be claimed twice for " + power_id)
		_check(not _has_choice(compass_ui._roll_arcana_choices(100, registry, player, rng), power_id), "Prismatic " + power_id + " leaves reward pool")
		compass_ui.close_selection()

	compass_ui.configure_catalyst_payload(CATALYSTS.merge_payloads(["extra_arcana_slot", "shop_reroll"]))
	compass_ui.open_selection("Exhausted Arcana", false, ENUMS.RewardMode.ARCANA, registry, player, rng)
	_check(compass_ui.boon_choices.is_empty(), "Fully enhanced Arcana pool is exhausted")
	_check(not compass_ui._reroll_current_offer(), "Empty pool cannot reroll")
	_check(compass_ui._reward_rerolls_remaining == 1, "Failed empty-pool reroll preserves allowance")
	compass_ui.close_selection()

	regular_ui.free()
	compass_ui.free()
	player.free()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Catalyst reward regressions: %d checks, %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

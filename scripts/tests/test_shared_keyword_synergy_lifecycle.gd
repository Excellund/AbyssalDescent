extends "res://scripts/tests/test_shared_status_lifecycle.gd"
## Modal cancellation retires action-root flights; committed target Marks have
## their existing pause/owner/room lifetime rather than becoming new actions.

func _seed_keyword_effects() -> Dictionary:
	player.player_id = 1
	player.set_physics_process(false)
	player.apply_character_package(preload("res://scripts/character_registry.gd").get_character("bastion"))
	player.apply_trial_power("stormbrand")
	player.apply_trial_power("spark_relay")
	player.apply_upgrade("shatterwake")
	player.apply_upgrade("patient_hunter")
	player.apply_upgrade("marked_prey")
	var target := _enemy()
	target.position = Vector2(400, 0)
	target.health_state.max_health = 10000
	target.health_state.current_health = 10000
	var electric := player.new_combat_action("dash")
	DAMAGEABLE.apply_damage(target, 20, INTERACTIONS.damage_context(electric, "static_wake", {"raw_amount": 20.0, "damage_coefficient": 1.0}), 1)
	var action := player.new_combat_action("attack")
	DAMAGEABLE.apply_damage(target, 20, INTERACTIONS.damage_context(action, "rupture_wave", {"raw_amount": 20.0, "damage_coefficient": 1.0, "attack_origin": player.global_position}), 1)
	var status := DAMAGEABLE._target_status(target)
	_check(status.marks.has("1:stormbrand"), "Accepted Electric damage prepares the real Stormbrand lifecycle state")
	_check(is_instance_valid(player.spark_relay_controller) and player.spark_relay_controller.projectiles.size() == 1, "Accepted Burst prepares one live Relay before lifecycle change")
	if is_instance_valid(player.spark_relay_controller):
		player.spark_relay_controller.set_physics_process(false)
	return {"target": target, "status": status, "action": action}

func _run() -> void:
	await _test_scene_pause()
	await _test_real_modal()
	await _test_package_identity()
	await _test_legacy_restore()
	for reason in ["death", "removal", "restore", "room_end", "character_change"]:
		await _test_keyword_retirement(reason)
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[SharedKeywordLifecycle] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_package_identity() -> void:
	_setup()
	var seeded := _seed_keyword_effects()
	var relay := player.spark_relay_controller
	var first_id: int = relay.projectiles[0].id
	player.apply_character_package(preload("res://scripts/character_registry.gd").get_character("bastion"))
	_check(relay.projectiles.size() == 1 and relay.projectiles[0].id == first_id and player.combat_interactions.accepts_action(seeded.action), "Reapplying the current character retains the same learned-power flight and root")
	_check(seeded.status.marks.has("1:stormbrand"), "Reapplying a character package retains its committed Stormbrand Mark")
	var incoming := PLAYER.new()
	world.add_child(incoming)
	incoming.set_physics_process(false)
	incoming.player_id = 0
	incoming.apply_character_package(preload("res://scripts/character_registry.gd").get_character("hexweaver"))
	_check(seeded.status.marks.has("1:stormbrand") and relay.projectiles.size() == 1, "A newly created unassigned actor cannot clear the existing host's Mark or flight during its first character assignment")
	incoming.upgrade_system.power_registry.free()
	incoming.free()
	_cleanup()
	await process_frame

func _test_legacy_restore() -> void:
	_setup()
	var legacy := player.build_run_snapshot()
	# Model a checkpoint authored before any of these properties existed.
	for key: String in player.KEYWORD_SYNERGY_DEFAULTS:
		legacy.properties.erase(key)
	var seeded := _seed_keyword_effects()
	player.apply_run_snapshot(legacy)
	_check(player.patient_hunter_bonus_damage == 0 and player.marked_prey_bonus_damage == 0 and player.shatterwake_stacks == 0, "Restoring a pre-expansion checkpoint clears both conditional Boons and Shatterwake from a reused actor")
	_check(not player.reward_stormbrand and not player.reward_spark_relay and player.stormbrand_stacks == 0 and player.spark_relay_stacks == 0, "Omitted legacy Arcana remain unowned after restoration")
	_check(player.spark_relay_controller.projectiles.is_empty() and not seeded.status.marks.has("1:stormbrand"), "Legacy restoration also retires learned-power flight and target state")
	_check(player.upgrade_system.apply_power("stormbrand") and player.upgrade_system.apply_power("spark_relay") and player.stormbrand_stacks == 1 and player.spark_relay_stacks == 1, "Normal acquisition after legacy restoration begins both Arcana at level one")
	_cleanup()
	await process_frame

func _test_scene_pause() -> void:
	_setup()
	var seeded := _seed_keyword_effects()
	var relay := player.spark_relay_controller
	if not is_instance_valid(relay) or relay.projectiles.is_empty():
		_cleanup()
		return
	var before: Vector2 = relay.projectiles[0].position
	var remaining: float = relay.projectiles[0].travel_left
	paused = true
	relay.tick(.25)
	_check(relay.projectiles.size() == 1 and relay.projectiles[0].position == before and relay.projectiles[0].travel_left == remaining, "A SceneTree pause freezes both Relay travel and its remaining range")
	paused = false
	relay.tick(.1)
	_check(relay.projectiles.size() == 1 and relay.projectiles[0].position.distance_to(before) > 50.0, "The same committed Relay resumes when the SceneTree resumes")
	_check(player.combat_interactions.accepts_action(seeded.action), "SceneTree freeze alone preserves the flight's original accepted root")
	_cleanup()
	await process_frame

func _test_real_modal() -> void:
	_setup()
	var seeded := _seed_keyword_effects()
	var status: Node = seeded.status
	var before: Dictionary = status.snapshot(1)
	var left: float = status.marks["1:stormbrand"].left
	world.pause_menu_controller.open()
	_check(player.spark_relay_controller.projectiles.is_empty() and not player.combat_interactions.accepts_action(seeded.action), "Opening real Pause cancels Relay and retires its input epoch")
	status._physics_process(1.0)
	_check(status.snapshot(1) == before and is_equal_approx(float(status.marks["1:stormbrand"].left), left), "Pause retains and freezes the already committed Stormbrand Mark")
	world.build_detail_panel.open()
	world.pause_menu_controller.close()
	_check(player.spark_relay_controller.projectiles.is_empty(), "Nested Build Details cannot recreate the cancelled flight")
	world.build_detail_panel.close()
	var hp: int = seeded.target.get_current_health()
	DAMAGEABLE.apply_damage(seeded.target, 20, INTERACTIONS.damage_context(seeded.action, "rupture_wave", {"raw_amount": 20.0, "damage_coefficient": 1.0}), 1)
	_check(seeded.target.get_current_health() == hp and player.spark_relay_controller.projectiles.is_empty(), "Closing modal panels cannot replay prior-epoch damage or converters")
	_cleanup()
	await process_frame

func _test_keyword_retirement(reason: String) -> void:
	_setup()
	var seeded := _seed_keyword_effects()
	var status: Node = seeded.status
	status.apply_mark(2, "stormbrand", .14, 3.5)
	var snapshot := player.build_run_snapshot()
	match reason:
		"death": player.set_alive(false)
		"removal": player.set_combat_removed(true)
		"restore": player.apply_run_snapshot(snapshot)
		"room_end": phase.end_combat_phase(player, self)
		"character_change": player.apply_character_package(preload("res://scripts/character_registry.gd").get_character("hexweaver"))
	_check(not is_instance_valid(player.spark_relay_controller) or player.spark_relay_controller.projectiles.is_empty(), reason + ": owner transition retires all Relay flight state")
	_check(not status.marks.has("1:stormbrand") and status.marks.has("2:stormbrand"), reason + ": cleanup removes only the departing owner's Stormbrand window")
	_check(not player.combat_interactions.accepts_action(seeded.action), reason + ": old action roots cannot restart a conversion")
	if reason == "restore":
		_check(player.patient_hunter_bonus_damage == 12 and player.marked_prey_bonus_damage == 12 and player.stormbrand_stacks == 1 and player.spark_relay_stacks == 1 and player.shatterwake_stacks == 1, "Real checkpoint restore retains all five learned powers while clearing temporary flights and Marks")
	_cleanup()
	await process_frame

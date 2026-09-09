extends "res://scripts/tests/test_combat_pause.gd"
## Real modal and Player lifecycles keep target status separate from action roots.
const DAMAGEABLE := preload("res://scripts/shared/damageable.gd")
const INTERACTIONS := preload("res://scripts/shared/combat_interaction_registry.gd")

func _test_modal_statuses() -> void:
	_setup()
	player.player_id = 1
	player.apply_trial_power("dread_resonance")
	var enemy := _enemy()
	var action := INTERACTIONS.damage_context(player.new_combat_action("melee"), "melee").interaction as Dictionary
	DAMAGEABLE.apply_damage(enemy, 1, INTERACTIONS.damage_context(action, "melee", {"damage_coefficient": 0.0}), 1)
	var status := DAMAGEABLE._target_status(enemy)
	_check(status != null and status.snapshot(1).dread_stacks == 1, "Actual accepted Player attack creates Dread before pause")
	var before: Dictionary = status.snapshot(1)
	var mark_left := float(status.marks["1:dread_resonance"].left)
	Input.action_press("attack")
	Input.action_press("dash")
	player.queued_attack_after_dash = true
	player.arcana_motion.charge_hold = 0.4
	player.arcana_motion.dash_hold = 0.3
	world.pause_menu_controller.open()
	_check(status.snapshot(1) == before, "Opening actual Pause preserves Mark and Dread")
	_check(not player.queued_attack_after_dash and player.arcana_motion.charge_hold < 0.0 and player.arcana_motion.dash_hold < 0.0, "Pause still cancels queued attack and motion holds")
	_check(player._combat_actions_awaiting_release.has(&"attack") and player._combat_actions_awaiting_release.has(&"dash"), "Held actions still require release after Pause")
	_check(not player.combat_interactions.accepts_action(action), "Pause rejects cancelled-epoch damage")
	status._physics_process(1.0)
	_check(status.snapshot(1) == before and is_equal_approx(float(status.marks.get("1:dread_resonance", {}).get("left", 0.0)), mark_left), "Native status process freezes Mark time while target paused")
	world.build_detail_panel.open()
	world.pause_menu_controller.close()
	_check(status.snapshot(1) == before and not enemy.is_physics_processing(), "Nested Build details retains both status and pause")
	world.build_detail_panel.close()
	_check(status.snapshot(1) == before and enemy.is_physics_processing(), "Closing final panel preserves statuses and restores simulation")
	player._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_check(status.snapshot(1) == before, "Lost focus cancels input without erasing committed Mark/Dread")
	status._physics_process(mark_left + 0.1)
	_check(status.snapshot(1).mark_ratio == 0.0 and status.snapshot(1).dread_stacks == 1, "Resumed Mark expires normally while Dread remains on its living target")
	player._refresh_combat_input_release()
	_check(player._combat_actions_awaiting_release.has(&"attack") and player._combat_actions_awaiting_release.has(&"dash"), "Still-held actions cannot rearm after modal or focus cancellation")
	Input.action_release("attack")
	Input.action_release("dash")
	await physics_frame
	await process_frame
	player._refresh_combat_input_release()
	_check(player._combat_actions_awaiting_release.is_empty(), "An actual release observed by physics rearms both actions")
	_cleanup()

func _seed_statuses() -> Node:
	player.player_id = 1
	player.apply_trial_power("dread_resonance")
	player.apply_trial_power("sigil_chain")
	var enemy := _enemy()
	var action: Dictionary = INTERACTIONS.damage_context(player.new_combat_action("melee"), "melee").interaction
	DAMAGEABLE.apply_damage(enemy, 1, INTERACTIONS.damage_context(action, "melee", {"damage_coefficient": 0.0}), 1)
	var status := DAMAGEABLE._target_status(enemy)
	_check(status.snapshot(1).dread_stacks == 1, "Native accepted attack seeds lifecycle Dread")
	# Teammate-owned entries exercise selective cleanup in the same target storage.
	status.apply_mark(2, "eclipse_mark", 0.2, 4.0)
	status.add_dread(2, 8, {"epoch": 1, "seq": 1})
	player._drop_sigil_chain_zone(enemy.global_position)
	_check(player.shared_build_runtime.fields.contains_point(enemy.global_position), "Actual learned Sigil creates a live Field before lifecycle change")
	return status

func _test_explicit_cleanup(kind: String, remote_owner: bool = false) -> void:
	_setup()
	var status := _seed_statuses()
	var pending_action: Dictionary = INTERACTIONS.damage_context(player.new_combat_action("melee"), "melee").interaction
	player.is_local_player = not remote_owner
	var snapshot := player.build_run_snapshot()
	match kind:
		"death": player.set_alive(false)
		"removal": player.set_combat_removed(true)
		"restore": player.apply_run_snapshot(snapshot)
		"room_end": phase.end_combat_phase(player, self)
	_check(status.snapshot(1).dread_stacks == 0 and not status.marks.has("1:dread_resonance"), kind + ": explicit lifecycle clears only owner's Mark/Dread")
	_check(status.snapshot(2).dread_stacks == 1 and status.marks.has("2:eclipse_mark"), kind + ": teammate's independently owned statuses survive")
	_check(not player.shared_build_runtime.fields.contains_point(status.get_parent().global_position), kind + ": old Field membership does not survive cleanup")
	if remote_owner and kind in ["death", "removal"]:
		_check(not DAMAGEABLE.apply_mark(status.get_parent(), "dread_resonance", 0.1, 3.0, 1, pending_action), kind + ": retained remote owner cannot recreate Mark before epoch cancellation arrives")
		_check(DAMAGEABLE.add_dread_stack(status.get_parent(), 1, 8, pending_action) == 0, kind + ": retained remote owner cannot recreate Dread before epoch cancellation arrives")
	_cleanup()
	await process_frame

func _test_network_snapshot_and_epoch() -> void:
	_setup()
	var status := _seed_statuses()
	var old := INTERACTIONS.damage_context(player.new_combat_action("melee"), "melee").interaction as Dictionary
	var before: Dictionary = status.snapshot(1)
	var snapshot := player.build_network_build_snapshot()
	player.is_local_player = false
	player.apply_network_build_snapshot(snapshot)
	_check(status.snapshot(1) == before, "A remote owner's live build update preserves Mark/Dread")
	_check(player.combat_interactions.accepts_action(old), "A remote build update cannot independently advance its authenticated epoch")
	PlayerReplicationService.player_nodes[1] = player
	PlayerReplicationService._interaction_epoch_announcements[1] = {"epoch": int(old.epoch) + 1, "run": old.run, "room": old.room}
	PlayerReplicationService._apply_interaction_epoch_to_player(1)
	_check(not player.combat_interactions.accepts_action(old), "Actual replication receiver rejects old actions after the owner's new epoch")
	_check(status.snapshot(1) == before, "Authenticated epoch cancellation does not discard committed statuses")
	var health: int = status.get_parent().get_current_health()
	DAMAGEABLE.apply_damage(status.get_parent(), 10, INTERACTIONS.damage_context(old, "melee", {"damage_coefficient": 1.0}), 1)
	_check(status.get_parent().get_current_health() == health, "Late prior-epoch damage cannot apply or recreate reactions")
	PlayerReplicationService.player_nodes.erase(1)
	PlayerReplicationService._interaction_epoch_announcements.erase(1)
	player.set_alive(false)
	_check(status.snapshot(1).dread_stacks == 0 and status.snapshot(2).dread_stacks == 1, "Remote-owner death clears its statuses without touching teammates")
	_cleanup()
	await process_frame

func _run() -> void:
	await _test_modal_statuses()
	for remote_owner in [false, true]:
		for kind in ["death", "removal", "restore", "room_end"]:
			await _test_explicit_cleanup(kind, remote_owner)
	await _test_network_snapshot_and_epoch()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[SharedStatusLifecycle] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

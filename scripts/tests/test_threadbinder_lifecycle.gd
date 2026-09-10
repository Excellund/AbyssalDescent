extends "res://scripts/tests/test_shared_status_lifecycle.gd"
## Committed threads survive modal input cancellation and live build updates,
## while explicit combat lifecycle changes discard their enemy references.

func _run() -> void:
	await _test_thread_modal_preservation()
	await _test_thread_live_build_preservation()
	for remote_owner in [false, true]:
		for kind in ["death", "removal", "restore", "room_end"]:
			await _test_thread_explicit_cleanup(kind, remote_owner)
	await _test_thread_authoritative_ring_deduplication()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[ThreadbinderLifecycle] %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _setup_thread() -> void:
	_setup()
	player.player_id = 1
	player.apply_character_package(player.CHARACTER_REGISTRY.get_character("threadbinder"))

func _thread_enemy(position: Vector2 = Vector2(40.0, 0.0)) -> ENEMY:
	var enemy := _enemy()
	enemy.position = position
	return enemy

func _thread_hit(target: ENEMY, amount: int = 1) -> Dictionary:
	var action := player.new_combat_action("melee")
	DAMAGEABLE.apply_damage(target, amount, INTERACTIONS.damage_context(action, "melee", {"raw_amount": float(amount), "damage_coefficient": 0.0}), 1)
	return action

func _pending_thread() -> Node2D:
	return player.cross_stitch_target.get_ref() as Node2D if player.cross_stitch_target != null else null

func _test_thread_modal_preservation() -> void:
	_setup_thread()
	var enemy := _thread_enemy()
	var action := _thread_hit(enemy)
	var status := DAMAGEABLE._target_status(enemy)
	var before_window := player.cross_stitch_window_left
	var before_mark := float(status.marks.get("1:cross_stitch", {}).get("left", 0.0))
	_check(_pending_thread() == enemy and before_window > 0.0 and before_mark > 0.0, "Accepted damage commits a live thread and Mark before a modal opens")
	Input.action_press("attack")
	Input.action_press("dash")
	player.queued_attack_after_dash = true
	world.pause_menu_controller.open()
	_check(_pending_thread() == enemy and is_equal_approx(player.cross_stitch_window_left, before_window), "Opening actual Pause preserves the committed thread")
	_check(not player.queued_attack_after_dash and not player.combat_interactions.accepts_action(action), "Pause still discards queued Attack input and rejects its retired action epoch")
	await create_timer(0.12).timeout
	_check(_pending_thread() == enemy and is_equal_approx(player.cross_stitch_window_left, before_window) and is_equal_approx(float(status.marks.get("1:cross_stitch", {}).get("left", 0.0)), before_mark), "Actual paused frames freeze both thread and Mark duration")
	world.build_detail_panel.open()
	world.pause_menu_controller.close()
	_check(_pending_thread() == enemy and not player.is_physics_processing(), "Nested Build Details preserves the thread while the final modal remains open")
	world.build_detail_panel.close()
	_check(_pending_thread() == enemy and player.is_physics_processing() and enemy.is_physics_processing(), "Closing the final modal resumes the existing thread and enemy")
	player._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_check(_pending_thread() == enemy and is_equal_approx(player.cross_stitch_window_left, before_window), "Focus loss cancels input without discarding the committed thread")
	_check(player._combat_actions_awaiting_release.has(&"attack") and player._combat_actions_awaiting_release.has(&"dash"), "Still-held inputs require release after modal and focus cancellation")
	Input.action_release("attack")
	Input.action_release("dash")
	player._update_cross_stitch(0.5)
	status.advance(0.5)
	_check(is_equal_approx(player.cross_stitch_window_left, before_window - 0.5) and is_equal_approx(float(status.marks.get("1:cross_stitch", {}).get("left", 0.0)), before_mark - 0.5), "Resumed thread and Mark advance from their preserved remaining time")
	var next := _thread_enemy(Vector2(-80.0, 0.0))
	var previous_health := enemy.get_current_health()
	_thread_hit(next, 20)
	_check(_pending_thread() == next and enemy.get_current_health() < previous_health, "A new accepted Attack after Pause still releases the preserved previous thread")
	_cleanup()
	await process_frame

func _test_thread_live_build_preservation() -> void:
	_setup_thread()
	var enemy := _thread_enemy()
	var action := _thread_hit(enemy)
	var status := DAMAGEABLE._target_status(enemy)
	var before: Dictionary = status.snapshot(1)
	var remaining := player.cross_stitch_window_left
	var snapshot := player.build_network_build_snapshot()
	player.is_local_player = false
	player.apply_network_build_snapshot(snapshot)
	_check(_pending_thread() == enemy and is_equal_approx(player.cross_stitch_window_left, remaining) and status.snapshot(1) == before, "A remote owner's live build update preserves both its thread and committed Mark")
	_check(player.combat_interactions.accepts_action(action), "Live build synchronization does not independently advance the owner's action epoch")
	player.is_local_player = true
	var next := _thread_enemy(Vector2(-80.0, 0.0))
	var previous_health := enemy.get_current_health()
	_thread_hit(next, 20)
	_check(_pending_thread() == next and enemy.get_current_health() < previous_health, "The first new Attack after live build synchronization can release the previous thread")
	_cleanup()
	await process_frame

func _test_thread_explicit_cleanup(kind: String, remote_owner: bool) -> void:
	_setup_thread()
	var enemy := _thread_enemy()
	_thread_hit(enemy)
	var status := DAMAGEABLE._target_status(enemy)
	status.apply_mark(2, "cross_stitch", 0.12, 4.0)
	player.is_local_player = not remote_owner
	var snapshot := player.build_run_snapshot()
	match kind:
		"death": player.set_alive(false)
		"removal": player.set_combat_removed(true)
		"restore": player.apply_run_snapshot(snapshot)
		"room_end": phase.end_combat_phase(player, self)
	var label := "%s %s" % ["remote owner" if remote_owner else "local owner", kind]
	_check(_pending_thread() == null and is_zero_approx(player.cross_stitch_window_left) and player.cross_stitch_target_network_id == 0, label + " clears the pending target, visual network ID and timer")
	_check(not status.marks.has("1:cross_stitch") and status.marks.has("2:cross_stitch"), label + " clears only the departing owner's Cross Stitch Mark")
	_cleanup()
	await process_frame

func _test_thread_authoritative_ring_deduplication() -> void:
	_setup_thread()
	var before := player.player_feedback.find_children("*", "Line2D", true, false).size()
	var origin := Vector2(300.0, 0.0)
	player._apply_cross_stitch_burst(origin, 20.0, 1.0, player.new_combat_action("melee"))
	var after_local := player.player_feedback.find_children("*", "Line2D", true, false).size()
	_check(after_local == before + 1, "An authoritative Cross Stitch Burst produces one local ring")
	var payload := {"position": origin, "radius": 48.0, "color": Color.WHITE, "duration": 0.24}
	player.apply_owner_cue_event("cross_stitch_burst", payload)
	player.apply_network_cue_event("cross_stitch_burst", payload)
	_check(player.player_feedback.find_children("*", "Line2D", true, false).size() == after_local, "Authoritative owner and remote-avatar cue handlers cannot replay the already rendered host ring")
	_cleanup()
	await process_frame

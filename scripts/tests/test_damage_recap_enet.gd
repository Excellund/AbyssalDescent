extends "res://scripts/tests/test_player_revival_enet.gd"
## Real Main health callbacks, outcome RPC, per-peer override and disk histories.

const HISTORY := preload("res://scripts/core/run_history_store.gd")
const RECAP := preload("res://scripts/core/damage_recap.gd")

func _test_fall_and_clear(_fallen_id: int, _same_frame: bool, key: String) -> void:
	if key != "host-falls":
		return
	HISTORY.clear_all()
	await _enter_room("damage-recap")
	var host_actor = world._get_player_for_peer(1)
	var client_actor = world._get_player_for_peer(client_id)
	if role == "host":
		for actor in [host_actor, client_actor]:
			actor.set_health(actor.get_max_health())
			actor.iron_skin_armor = 0
			actor.incoming_damage_taken_mult = 1.0
			actor.incoming_contact_damage_mult = 1.0
			actor._dash_damage_immune_left = 0.0
			actor._contact_damage_grace_left = 0.0
	check(await _until(func(): return host_actor.get_current_health() == host_actor.get_max_health() and client_actor.get_current_health() == client_actor.get_max_health()), "Native party is healthy before accepted damage")
	await _barrier("damage-healthy")
	if role == "host":
		host_actor.take_damage(9, {"source": "enemy_ability", "ability": "archer_projectile"})
		client_actor.take_damage(100000, {"source": "enemy_ability", "ability": "pyre_death_field"})
	check(await _until(func(): return client_actor.is_dead() and not host_actor.is_dead()), "Real accepted damage downs only the joiner on both peers")
	await _barrier("damage-down")
	if role == "host":
		check(world.run_summary_recorder.run_summary_tracker.get_damage_recap(client_id).entries.back().ability == "pyre_death_field", "Authority attributes first downing to the actual joiner")
		_clear_final_enemy()
	check(await _until(func(): return not client_actor.is_dead() and client_actor.get_current_health() == 1), "Native encounter clear revives the joiner")
	await _finish_rewards("damage-recap")
	await _enter_room("damage-recap-final")
	if role == "host":
		check(not world.run_summary_recorder.run_summary_tracker.get_damage_recap(client_id).ending_on_damage, "Revival clears prior final-damage eligibility on the authority")
		client_actor.take_damage(100000, {"source": "enemy_ability", "ability": "warden_nova"})
	check(await _until(func(): return client_actor.is_dead() and not host_actor.is_dead()), "Second accepted downing retains the living host")
	await _barrier("damage-second-down")
	if role == "host":
		host_actor.take_damage(100000, {"source": "enemy_ability", "ability": "biome_storm_reach"})
	check(await _until(func(): return world.defeat_screen.is_open() and world.run_summary_recorder.latest_run_summary.get("outcome") == "death"), "Native death finalizes and shows results through the production outcome RPC")
	# Let reliable health/outcome traffic complete before reading final disk state.
	await create_timer(0.25).timeout
	var summary: Dictionary = world.run_summary_recorder.latest_run_summary
	var recap := RECAP.normalize(summary.get("damage_recap"))
	var expected := "biome_storm_reach" if role == "host" else "warden_nova"
	check(not recap.is_empty() and recap.peer_id == world.player.player_id, "Final outcome recap belongs to this exact native peer")
	if not recap.is_empty() and not recap.entries.is_empty():
		check(recap.entries.back().ability == expected and recap.entries.back().health_after == 0, "Each player sees their own accepted final damage source")
		if role == "client":
			check(recap.entries.size() == 2 and recap.entries[0].ability == "pyre_death_field", "Joining owner receives both sides of the real revival from host evidence")
			check(recap.entries.back().health_lost == 1, "Joiner overkill recap shows its one remaining HP")
		check(RECAP.presentation(summary).entries[0].is_final, "Player-facing recap identifies that peer's final accepted damage")
	var history := HISTORY.load_all()
	check(history.size() == 1, "Each process writes exactly one local terminal record")
	if not history.is_empty():
		check(RECAP.normalize(history[0].get("damage_recap")) == recap, "The actual local History preserves the same attributed recap as the outcome screen")
	await _barrier("damage-history-checked")
	var history_hash := FileAccess.get_sha256(HISTORY.STORAGE_PATH)
	if role == "host":
		world._broadcast_run_outcome_if_needed("death", -1, world.current_room_label, world.room_depth)
		world._broadcast_run_outcome_if_needed("death", -1, world.current_room_label, world.room_depth)
	await create_timer(0.25).timeout
	check(HISTORY.load_all().size() == 1 and FileAccess.get_sha256(HISTORY.STORAGE_PATH) == history_hash, "Repeated authoritative outcome RPCs do not duplicate or rewrite local history")
	await _barrier("damage-repeated-outcome")

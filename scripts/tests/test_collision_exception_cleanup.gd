extends "res://scripts/tests/test_live_arena_edges.gd"
## Inspect actual physics handles after actors leave, not only tracking maps.

const CHARGER := preload("res://scripts/enemy_charger.gd")
const RAM := preload("res://scripts/enemy_ram.gd")
const BREAKWATER := preload("res://scripts/enemy_breakwater.gd")
const ROSTER := preload("res://scripts/core/player_roster_helpers.gd")

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Collision cleanup requires isolated user data")
		quit(1)
		return
	for kind in ["charger", "ram", "breakwater"]:
		for removed in [false, true]:
			await _test_charge_cleanup(kind, removed)
	await _test_edge_target_cleanup()
	await _test_party_cleanup()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Collision exception cleanup: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_charge_cleanup(kind: String, removed: bool) -> void:
	_setup()
	var script: Script = {"charger": CHARGER, "ram": RAM, "breakwater": BREAKWATER}[kind]
	var body := script.new() as CharacterBody2D
	_circle(body, 13.0)
	room.add_child(body)
	body.set_physics_process(false)
	body.target = actor
	body.target_candidates = [actor]
	var victim := _enemy(Vector2(40.0, 0.0))
	if kind == "breakwater":
		body._begin_tracking()
		body._lock_charge()
		body._begin_charge()
	else:
		body._enter_charge_state()
	_check(body.get_collision_exceptions().has(victim), kind + " charge actually phases through its live ally")
	if removed:
		victim.take_damage(100000)
		await process_frame
		await physics_frame
		_check(not is_instance_valid(victim), kind + " ally is freed through its production death path")
		if kind == "charger":
			body._sync_charge_enemy_collision_exceptions()
			_check(body.get_collision_exceptions().is_empty(), "Charger drops freed allies during its next charge update")
		elif kind == "ram":
			body._sync_charge_exceptions()
			_check(body.get_collision_exceptions().is_empty(), "Ram drops freed allies during its next charge update")
	if kind == "breakwater":
		body._enter_recovery(false)
	else:
		body._enter_recover_state()
	_check(body.get_collision_exceptions().is_empty(), kind + " recovery removes every live or freed physics handle")
	_clear()
	await process_frame

func _test_edge_target_cleanup() -> void:
	_setup()
	var body := _enemy(Vector2.ZERO)
	var first := CharacterBody2D.new()
	var second := CharacterBody2D.new()
	room.add_child(first)
	room.add_child(second)
	body.target = first
	body._set_target_collision_ignored(true)
	_check(body.get_collision_exceptions().has(first), "Edge escape phases through its actual original target")
	body.target = second
	body._set_target_collision_ignored(true)
	var handles := body.get_collision_exceptions()
	_check(handles.size() == 1 and handles.has(second), "Retargeting moves the edge exception to the new target without leaving the old one")
	second.free()
	body._clear_edge_escape_state()
	_check(body.get_collision_exceptions().is_empty() and not body._ignoring_target_collision, "Clearing edge escape removes the actual target handle even after its Node is freed")
	body.target = first
	body._set_target_collision_ignored(true)
	body.target = null
	body._clear_edge_escape_state()
	_check(body.get_collision_exceptions().is_empty(), "Losing the target reference still clears its original edge exception")
	_clear()
	await process_frame

func _test_party_cleanup() -> void:
	_setup()
	var peers: Array[PhysicsBody2D] = [actor]
	for index in range(3):
		var peer := CharacterBody2D.new()
		_circle(peer, 14.0)
		room.add_child(peer)
		peers.append(peer)
	_pair_party(peers)
	var connection_counts: Dictionary = {}
	for peer in peers:
		connection_counts[peer.get_instance_id()] = peer.tree_exiting.get_connections().size()
	for repeat in range(3):
		_pair_party(peers)
		_pair_party(peers, true)
	for peer in peers:
		_check(peer.tree_exiting.get_connections().size() == connection_counts[peer.get_instance_id()], "Repeated and reversed setup does not accumulate departure callbacks")
	_check_party_exceptions(peers, "All four party bodies retain exactly the other three live bodies")

	# A two-player test misses static-bound-Callable deduplication: a later
	# departing peer must notify every survivor, including other remote players.
	var departing := peers[2]
	peers.remove_at(2)
	departing.free()
	_check_party_exceptions(peers, "A non-first peer departure preserves only the other live party members")
	var queued := peers[1]
	peers.remove_at(1)
	queued.queue_free()
	await process_frame
	_check_party_exceptions(peers, "A second queued departure leaves every survivor free of stale handles")

	var rejoining := peers[1]
	room.remove_child(rejoining)
	_check(actor.get_collision_exceptions().is_empty() and rejoining.get_collision_exceptions().is_empty(), "Leaving the tree clears party handles on both the remaining and departing bodies")
	room.add_child(rejoining)
	_pair_party(peers)
	_pair_party(peers, true)
	_check_party_exceptions(peers, "Adding the same body again and reapplying setup restores both live exceptions")
	var container := Node2D.new()
	room.add_child(container)
	rejoining.reparent(container)
	_check(actor.get_collision_exceptions().is_empty() and rejoining.get_collision_exceptions().is_empty(), "A live reparent clears its previous party relationship safely")
	_pair_party(peers)
	_check_party_exceptions(peers, "Pair setup after reparent rearms departure cleanup")

	var live_enemy := _enemy(Vector2(100.0, 0.0))
	actor._set_dash_phasing(true)
	rejoining.free()
	var remaining_handles := actor.get_collision_exceptions()
	_check(remaining_handles.size() == 1 and remaining_handles.has(live_enemy), "Party departure preserves the player's independently owned dash exception")
	actor._set_dash_phasing(false)
	_check(actor.get_collision_exceptions().is_empty(), "Dash cleanup subsequently removes only its own surviving enemy exception")
	_clear()
	await process_frame

func _pair_party(peers: Array[PhysicsBody2D], reverse: bool = false) -> void:
	for first in range(peers.size()):
		for second in range(first + 1, peers.size()):
			if reverse:
				ROSTER.disable_player_collision_pair(peers[second], peers[first])
			else:
				ROSTER.disable_player_collision_pair(peers[first], peers[second])

func _check_party_exceptions(peers: Array[PhysicsBody2D], label: String) -> void:
	for body in peers:
		var handles := body.get_collision_exceptions()
		var matches := handles.size() == peers.size() - 1
		for peer in peers:
			if peer != body and not handles.has(peer):
				matches = false
		_check(matches, label)

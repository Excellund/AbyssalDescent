extends "res://scripts/tests/test_boss_combinations_enet.gd"
## Native host/joiner transport exercises the production projectile receiver.

const FIXTURE := preload("res://scripts/tests/test_drifter_replication.gd")
const DRIFTER_ID := 712
var drifter: FIXTURE.TestDrifter
var victim: FIXTURE.TestTarget

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	victim = FIXTURE.TestTarget.new()
	victim.name = "RingTarget"
	world.add_child(victim)
	drifter = FIXTURE.TestDrifter.new()
	drifter.name = "Drifter"
	world.add_child(drifter)
	drifter.global_position = Vector2(80, -60)
	drifter.target = victim
	world.enemy_state_sync_broadcaster.register_enemy(drifter, DRIFTER_ID)
	world.active_room_enemy_count = 1
	check(drifter.network_simulation_enabled == (role == "host"), "Production registration assigns the Drifter's host and replica authority")
	check(drifter.get_current_health() == 88 and drifter.get_max_health() == 88, "Both processes start the Drifter with full intended health")

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	for _wave in range(2):
		drifter._emit_ring()
		drifter.rings.back()["radius"] = 120.0
		drifter.rings.back()["gap_index"] = 6
	victim.global_position = drifter._get_ring_node_world_position(drifter.rings[1], 0)
	var payload := drifter.get_projectile_network_sync_state()
	world._sync_archer_projectile_states.rpc([{"enemy_id": DRIFTER_ID, "payload": payload}], 7)
	world.fixture_command.rpc_id(client_id, "inspect", {"key": "rings", "q": payload.q, "target": victim.global_position, "step": 0.0})
	check(await until(func(): return results.has("rings")), "Joiner acknowledges the real ring packet")
	if results.has("rings"):
		var observed: Dictionary = results.rings
		check(observed.count == 2 and observed.config == [12, 176.0, 360.0, 20.0], "The production projectile channel carries both waves and their exact denser geometry")
		check((observed.first as Vector2).is_equal_approx(drifter._get_ring_node_world_position(drifter.rings[0], 0)) and (observed.second as Vector2).is_equal_approx(victim.global_position), "Stable wave IDs reproduce the alternating half-spokes exactly on the joiner")
		check(observed.gaps == [6, 6] and observed.hits == 0, "The missing spokes agree while replica collision cannot damage its target")
	drifter._process_rings(0.0)
	check(victim.hits == 1 and victim.health_state.current_health == 88, "Only the host applies the matching second-wave contact")
	world.fixture_command.rpc_id(client_id, "inspect", {"key": "advanced", "q": payload.q, "target": victim.global_position, "step": 0.25})
	check(await until(func(): return results.has("advanced")), "Joiner reports locally advanced projectile geometry")
	if results.has("advanced"):
		check(is_equal_approx(float(results.advanced.radius), 164.0) and results.advanced.hits == 0, "The joiner animates the faster waves smoothly without dealing damage")
	drifter.rings.clear()
	var clear_payload := drifter.get_projectile_network_sync_state()
	world._sync_archer_projectile_states.rpc([{"enemy_id": DRIFTER_ID, "payload": clear_payload}], 7)
	world.fixture_command.rpc_id(client_id, "inspect", {"key": "clear", "q": clear_payload.q, "target": Vector2.ZERO, "step": 0.0})
	check(await until(func(): return results.has("clear")), "Joiner acknowledges the final clear packet")
	if results.has("clear"):
		check(results.clear.count == 0 and results.clear.hits == 0, "An authoritative clear removes all remaining remote waves")
	world.fixture_command.rpc_id(client_id, "finish")
	check(await until(func(): return results.has("finished")), "Joiner acknowledges fixture completion")
	await finish()

func client_command(command: String, payload: Dictionary) -> void:
	if command != "inspect":
		await super.client_command(command, payload)
		return
	check(await until(func(): return drifter._last_remote_ring_sequence >= int(payload.q)), "The production receiver delivers the requested Drifter sequence")
	victim.global_position = payload.target
	drifter._process_network_visuals(float(payload.step))
	var count := drifter.rings.size()
	drifter._emit_ring()
	check(drifter.rings.size() == count and drifter.get_projectile_network_sync_state().is_empty(), "A replica cannot emit or broadcast its own waves")
	var gaps: Array[int] = []
	for ring in drifter.rings:
		gaps.append(int(ring.gap_index))
	world.fixture_result.rpc_id(1, payload.key, {
		"count": count, "config": [drifter.ring_node_count, drifter.ring_speed, drifter.ring_radius_max, drifter.node_hit_radius],
		"first": drifter._get_ring_node_world_position(drifter.rings[0], 0) if count > 0 else Vector2.ZERO,
		"second": drifter._get_ring_node_world_position(drifter.rings[1], 0) if count > 1 else Vector2.ZERO,
		"radius": float(drifter.rings[0].radius) if count > 0 else 0.0,
		"gaps": gaps, "hits": victim.hits
	})

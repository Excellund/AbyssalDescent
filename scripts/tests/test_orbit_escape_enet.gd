extends "res://scripts/tests/test_boss_combinations_enet.gd"
## Owner dismount input uses the existing production transform and damage RPCs.
const MOTION := preload("res://scripts/arcana_motion_controller.gd")

func _begin_reward_run() -> void:
	# Actor setup binds services; the scenario starts recorders in host/join order.
	RunContext.set_multiplayer_session("orbit-escape-loopback", role == "host")
	RunContext.meta_progress_profile = {}
	world.difficulty_provider = preload("res://scripts/core/difficulty_scaling_provider.gd").new(world)
	GameStateReplicationService.initialize(world)

func _start_fixture_run() -> void:
	world.run_summary_recorder = preload("res://scripts/core/run_summary_recorder.gd").new(world)
	world.run_summary_recorder.reset_summary_tracker()
	world.run_summary_recorder.initialize(true)
	world.run_summary_recorder.mark_run_start()

func setup_actors(client_id: int) -> void:
	super.setup_actors(client_id)
	for actor in [local_player, remote_player]:
		actor.apply_trial_power("razor_orbit")
	enemy(101).global_position = Vector2(0, 70)
	PlayerReplicationService._remote_target_positions[client_id] = Vector2.ZERO

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	_start_fixture_run()
	world.fixture_command.rpc_id(client_id, "begin")
	check(await until(func(): return results.has("bound") and world.run_summary_recorder.run_summary_tracker._received_provenance_peers.has(client_id)), "Real run handshake binds the owner before its first Orbit action")
	check(results.get("bound", {}).get("run", "") == REWARD_INTERACTIONS.current_run() and not REWARD_INTERACTIONS.current_run().is_empty(), "Both peers share the actual production run identity")
	world.fixture_command.rpc_id(client_id, "orbit")
	check(await until(func(): return enemy(101).get_current_health() == 86 and bool(remote_player.arcana_motion._visual.get("orbit", false))), "Owner's real Orbit cut and tether arrive through production RPCs")
	results["accepted_cut"] = {"health": enemy(101).get_current_health(), "damage_events": world.damage_events.duplicate(true), "visual": remote_player.arcana_motion._visual.duplicate(true)}
	check(world.damage_events.size() == 1 and world.damage_events[0].amount == 14 and world.damage_events[0].peer == client_id, "Host accepts one 35% cut with the authenticated owner's damage credit")
	check(not remote_player.arcana_motion.owns_movement() and remote_player.arcana_motion.motion == MOTION.Motion.NONE, "Observer presentation never acquires movement or cut authority")
	world.fixture_command.rpc_id(client_id, "escape")
	check(await until(func(): return results.has("escape")), "Joiner reports its input-driven quarter-second escape")
	if results.has("escape"):
		var receipt: Dictionary = results.escape
		var destination := Vector2(receipt.x, receipt.y)
		check(await until(func():
			PlayerReplicationService._sync_all_player_positions()
			return Vector2(PlayerReplicationService._remote_target_positions.get(client_id, Vector2.INF)).distance_to(destination) < 1.5
		), "Production transform channel receives the actual steered destination within its pixel quantization")
		check(absf(float(receipt.x) - (float(receipt.origin_x) - float(receipt.speed) * 0.20)) < 0.01 and absf(float(receipt.y) - (float(receipt.origin_y) - float(receipt.speed) * 0.05)) < 0.01 and bool(receipt.finished), "Owner reverses tangent, steers again, and ends the bounded escape")
		check(not bool(receipt.dash) and float(receipt.immunity) == 0.0 and not bool(receipt.phasing), "Remote escape never advertises a Dash or damage immunity")
		check(receipt.local_damage_events == 0 and receipt.local_enemy_health == 100, "Joiner does not locally apply its requested enemy damage")
	check(await until(func(): return not bool(remote_player.arcana_motion._visual.get("orbit", false))), "Production cue clears the remote tether after release")
	var hp := enemy(101).get_current_health()
	remote_player.arcana_motion.start_orbit(enemy(101))
	remote_player.arcana_motion.tick(0.1)
	remote_player.arcana_motion.process_movement(0.25, Vector2.RIGHT)
	check(not remote_player.arcana_motion.owns_movement() and enemy(101).get_current_health() == hp and world.damage_events.size() == 1, "Host replica cannot replay owner Orbit movement or duplicate cuts after the escape")
	world.fixture_command.rpc_id(client_id, "finish")
	await until(func(): return results.has("finished"))
	await finish()

func client_command(command: String, payload: Dictionary) -> void:
	match command:
		"begin":
			_start_fixture_run()
			check(await until(func(): return not REWARD_INTERACTIONS.current_run().is_empty()), "Joiner receives the host run token before issuing input")
			world.fixture_result.rpc_id(1, "bound", {"run": REWARD_INTERACTIONS.current_run()})
		"orbit":
			local_player.global_position = Vector2.ZERO
			local_player.dash_direction = Vector2.RIGHT
			local_player._dash_interaction = local_player.new_combat_action("dash")
			check(not local_player._dash_interaction.is_empty(), "The accepted owner action carries real run, room and epoch identity")
			Input.action_press("dash")
			local_player.arcana_motion.start_orbit(enemy(101))
			for frame in range(5):
				local_player.arcana_motion.process_movement(0.02, Vector2.ZERO)
			local_player.arcana_motion._publish_state()
			PlayerReplicationService._flush_pending_cue_events()
			check(local_player.arcana_motion.motion == MOTION.Motion.ORBIT, "Joiner owns the real circular movement")
			world.fixture_result.rpc_id(1, "cut_owner", {"position": local_player.position, "damage": local_player.damage, "reach": local_player.attack_range, "cooldowns": local_player.arcana_motion.contact_cooldowns.size(), "root": local_player.arcana_motion._orbit_interaction})
		"escape":
			var origin := local_player.global_position
			var speed := minf(MOTION.ORBIT_SPEED, local_player.max_speed * 1.5)
			Input.action_press("move_left")
			Input.action_release("dash")
			local_player.arcana_motion.tick(0.01)
			check(local_player.arcana_motion._orbit_hint_direction.dot(Vector2.LEFT) > 0.99, "Fresh owner movement selects the first departure cue")
			local_player.arcana_motion.process_movement(0.20, Vector2.LEFT)
			local_player.arcana_motion.process_movement(0.05, Vector2.UP)
			PlayerReplicationService._flush_pending_cue_events()
			PlayerReplicationService._sync_all_player_positions()
			Input.action_release("move_left")
			check(not local_player.arcana_motion.owns_movement(), "Owner relinquishes escape at its fixed deadline")
			world.fixture_result.rpc_id(1, "escape", {"origin_x": origin.x, "origin_y": origin.y, "speed": speed, "x": local_player.position.x, "y": local_player.position.y, "finished": not local_player.arcana_motion.owns_movement(), "dash": local_player._is_dash_active(), "immunity": local_player._dash_damage_immune_left, "phasing": local_player.dash_phasing_active, "local_damage_events": world.damage_events.size(), "local_enemy_health": enemy(101).get_current_health()})
		_:
			super.client_command(command, payload)

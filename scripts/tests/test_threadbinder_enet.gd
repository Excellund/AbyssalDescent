extends "res://scripts/tests/test_combat_interactions_enet.gd"
## Real owner inputs, authenticated Effigy origins, and late-observer recovery.

const CHARACTERS := preload("res://scripts/character_registry.gd")
const SEAMLOCK := preload("res://scripts/enemy_seamlock.gd")
var saved_start: Dictionary = {}
var last_transport_tick_usec: int = 0
var seamlock: SEAMLOCK

class EffigyFeedback extends Feedback:
	var swings: Array[Dictionary] = []
	func play_attack_swing_visual(direction: Vector2, swing_range: float, arc_degrees: float, tint: Color = Color.WHITE, lifetime: float = 0.11, inner_range: float = 0.0, attack_origin: Vector2 = Vector2.INF) -> void:
		swings.append({"origin": attack_origin if attack_origin.is_finite() else global_position, "direction": direction, "range": swing_range})
		super.play_attack_swing_visual(direction, swing_range, arc_degrees, tint, lifetime, inner_range, attack_origin)

class EffigyPlayer extends InteractionPlayer:
	var primary_actions := 0
	var attack_actions: Array[Dictionary] = []
	var shared_owner_cues: Array[Dictionary] = []
	func _ready() -> void:
		super._ready()
		primary_attack_fired.connect(func(): primary_actions += 1)
	func _notification(_what: int) -> void:
		# Both isolated peers deliberately run without an OS-focused game window.
		pass
	func _create_player_feedback() -> void:
		player_feedback = EffigyFeedback.new()
		add_child(player_feedback)
		player_feedback.setup(max_health, get_current_health())
	func new_combat_action(kind: String) -> Dictionary:
		var action := super.new_combat_action(kind)
		if kind in ["melee", "blast_drive"]:
			attack_actions.append(action.duplicate(true))
		return action
	func apply_owner_cue_event(event_name: String, payload: Dictionary) -> void:
		var was_deployed := effigy_deployed
		super.apply_owner_cue_event(event_name, payload)
		if event_name == "shared_build_state" and payload.get("effigy") is Dictionary:
			shared_owner_cues.append({"effigy": payload.effigy.duplicate(true), "serial": payload.serial,
				"accepted_serial": shared_build_runtime._received_serial, "was_deployed": was_deployed, "deployed": effigy_deployed})

class EffigyEnemy extends Enemy:
	var received_hits: Array[Dictionary] = []
	func take_damage(amount: int, context: Dictionary = {}) -> void:
		var before := get_current_health()
		super.take_damage(amount, context)
		if get_current_health() < before:
			received_hits.append(context.duplicate(true))

func _create_actor(id: int) -> EffigyPlayer:
	var actor := EffigyPlayer.new()
	actor.name = "Player_%d" % id
	actor.player_id = id
	actor.is_local_player = id == get_multiplayer().get_unique_id()
	circle(actor, 14.0)
	world.add_child(actor)
	actor.apply_character_package(CHARACTERS.get_character("threadbinder"))
	actor.damage = 100
	actor.position = Vector2(-300.0, -160.0) if id == 1 else Vector2.ZERO
	actor.arcana_motion.set_process(false)
	actor.returning_crescent.set_physics_process(false)
	actor.boss_combinations.set_process(false)
	PlayerReplicationService.register_player(id, actor)
	return actor

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	RunContext.set_multiplayer_session("effigy-loopback", role == "host")
	RunContext.meta_progress_profile = {}
	world.current_room_size = Vector2(1160.0, 860.0)
	world.current_effective_room_size = world.current_room_size
	world.difficulty_provider = preload("res://scripts/core/difficulty_scaling_provider.gd").new(world)
	GameStateReplicationService.initialize(world)
	process_frame.connect(_pump_player_transport)
	for id in [1, client_id]:
		var actor := _create_actor(id)
		if actor.is_local_player:
			local_player = actor
			world.player = actor
		else:
			remote_player = actor
	var positions := {101: Vector2(60, 0), 102: Vector2(240, 0), 103: Vector2(60, 150), 104: Vector2(180, -60), 105: Vector2(-240, -160), 106: Vector2(-60, -160), 107: Vector2(500, 0)}
	for id in positions:
		var target := EffigyEnemy.new()
		target.name = "Enemy_%d" % id
		circle(target, 13.0)
		world.add_child(target)
		target.position = positions[id]
		target.health_state.setup(100 if id == 104 else 10000, 100 if id == 104 else 10000)
		world.enemy_state_sync_broadcaster.register_enemy(target, id)
	world.active_room_enemy_count = positions.size()

func _pump_player_transport() -> void:
	if finished or not MultiplayerSessionManager.is_session_connected():
		return
	# Isolated autoloads suppress their process callbacks. Exercise the real
	# transport methods here so walking and state heartbeats run as in play.
	var now := Time.get_ticks_usec()
	var delta := 1.0 / 60.0 if last_transport_tick_usec == 0 else float(now - last_transport_tick_usec) / 1000000.0
	last_transport_tick_usec = now
	PlayerReplicationService._sync_all_player_positions()
	PlayerReplicationService._interpolate_remote_players(delta)
	PlayerReplicationService._flush_pending_cue_events()

func _state(actor: Player) -> Dictionary:
	return {"deployed": actor.effigy_deployed, "position": actor.effigy_position, "origin": actor.get_attack_origin(), "body": actor.global_position, "passive": actor.passive_effigy_command, "attack_phase": actor._effigy_attack_count}

func report(key: String) -> void:
	world.fixture_result.rpc_id(1, key, {
		"raw_owner_deployed": local_player.effigy_deployed,
		"shared_owner_cues": (local_player as EffigyPlayer).shared_owner_cues.duplicate(true),
		"bounds": world.current_effective_room_size,
		"seamlock_steps": seamlock.arena_penalty_steps if is_instance_valid(seamlock) else -1,
		"seamlock_shatters": seamlock._illusion_shatter_times.duplicate() if is_instance_valid(seamlock) else [],
		"owner": _state(local_player), "observer": _state(remote_player),
		"primary_actions": (local_player as EffigyPlayer).primary_actions,
		"attack_actions": (local_player as EffigyPlayer).attack_actions.duplicate(true),
		"swings": (local_player.player_feedback as EffigyFeedback).swings.duplicate(true),
		"observer_swings": (remote_player.player_feedback as EffigyFeedback).swings.duplicate(true),
		"damage": local_player.damage, "execution_mult": local_player.execution_damage_mult,
		"oath_primed": local_player._indomitable_spirit_primed, "oath_bank": local_player.indomitable_damage_bank,
		"damage_breakdown": local_player.last_damage_breakdown.duplicate(true),
		"damage_events": world.damage_events.size(), "scope": DAMAGE.current_interaction_context()})

func _attack(actor: Player, direction: Vector2) -> void:
	actor.attack_cooldown_left = 0.0
	actor.attack_lock_time_left = 0.0
	actor._try_execute_attack(direction)

func _dash(actor: Player) -> void:
	actor.attack_lock_time_left = 0.0
	actor.dash_cooldown_left = 0.0
	Input.action_press("dash")
	actor._try_start_dash(Vector2.DOWN)
	Input.action_release("dash")
	check(actor.dash_remaining_distance > 0.0, "Normal Dash crosses the real input boundary")
	# Inspect recall at Dash start; no fixture movement or input cancellation
	# supplies the state change that the production Dash must have performed.
	actor.dash_remaining_distance = 0.0
	actor.dash_time_left = 0.0
	actor.dash_phase_release_left = 0.0
	actor._set_dash_phasing(false)

func _hits(id: int) -> Array[Dictionary]:
	return (enemy(id) as EffigyEnemy).received_hits

func _prepare_damage_parity(actor: Player) -> void:
	actor.apply_trial_power("execution_edge")
	actor.execution_every = 1
	actor.damage = 37
	actor.indomitable_spirit_damage_reduction = 0.2
	actor.indomitable_damage_bank = actor._get_indomitable_fill_requirement()
	actor._indomitable_spirit_primed = true

func _sync_observed_state() -> void:
	world.enemy_state_sync_broadcaster.tick(0.25)
	world.enemy_state_sync_broadcaster.tick(0.25)
	PlayerReplicationService._flush_pending_cue_events()

func _create_seamlock() -> void:
	seamlock = SEAMLOCK.new()
	seamlock.name = "Seamlock_201"
	seamlock.arena_size = world.current_room_size
	world.add_child(seamlock)
	seamlock.global_position = Vector2(-430, 240)
	world.enemy_state_sync_broadcaster.register_enemy(seamlock, 201)
	seamlock.set_physics_process(false)
	world.active_room_enemy_count += 1

func _has_received_bounds_clear() -> bool:
	for cue in (local_player as EffigyPlayer).shared_owner_cues:
		var state: Dictionary = cue.effigy
		if not state.deployed and state.seq == local_player.effigy_action_seq and state.attacks == local_player._effigy_attack_count and cue.was_deployed and not cue.deployed and cue.serial == cue.accepted_serial:
			return true
	return false

func _test_remote_seamlock() -> void:
	_create_seamlock()
	await command("seamlock_prepare")
	check(await until(func(): return remote_player.global_position.distance_to(Vector2(250, -150)) < 2.0), "Native transform transport positions the owner before its Seamlock deployment")
	await command("seamlock_deploy")
	var anchor := Vector2(430, -150)
	check(remote_player.effigy_deployed and remote_player.effigy_position.is_equal_approx(anchor), "Joiner's real deployment plants the anchor near the future shrinking wall")
	await command("walk")
	check(await until(func(): return remote_player.global_position.distance_to(results.walk.owner.body) < 2.0), "Host receives the owner's ordinary body movement before the perpendicular guess")
	check(results.walk.owner.body.distance_to(Vector2(250, -150)) > 60.0 and results.walk.owner.position.is_equal_approx(anchor), "Ordinary walking preserves the native anchor used for the false-illusion guess")
	seamlock._enter_illusion_phase(false)
	# Fixed native illusion positions isolate two mutually exclusive cones:
	# the body faces a decoy; the committed anchor faces the actual wrong guess.
	seamlock._illusion_positions = [anchor + Vector2.UP * 60.0, remote_player.global_position + Vector2.UP * 60.0]
	seamlock._illusion_shatter_times = [0.0, 0.0]
	_sync_observed_state()
	await command("seamlock_guess")
	var action: Dictionary = results.seamlock_guess.attack_actions.back()
	var accepted: Dictionary = remote_player.combat_interactions.get_attack_start(action)
	check(not accepted.is_empty() and accepted.origin.is_equal_approx(anchor) and accepted.direction.is_equal_approx(Vector2.UP), "Authenticated remote Attack commits the fixed anchor and perpendicular aim in the host ledger")
	check(seamlock.arena_penalty_steps == 1 and seamlock._illusion_shatter_times[0] > 0.0 and seamlock._illusion_shatter_times[1] == 0.0, "Native host Seamlock shatters only the anchor-side false illusion and applies one wrong-guess penalty")
	check(results.seamlock_guess.primary_actions == results.seamlock_deploy.primary_actions + 1, "One remote Effigy command creates one deliberate Attack while resolving its illusion guess")
	seamlock._update_arena_penalty_lerp(10.0)
	world._refresh_effective_room_bounds_from_seamlock_penalty()
	check(world.current_effective_room_size.x < world.current_room_size.x and remote_player.get_attack_origin().is_equal_approx(anchor) and remote_player.effigy_deployed, "The real first Seamlock shrink preserves an anchor whose full footprint still fits")
	_sync_observed_state()
	await command("seamlock_first_shrink")
	check(results.seamlock_first_shrink.seamlock_steps == 1 and results.seamlock_first_shrink.seamlock_shatters[0] > 0.0 and results.seamlock_first_shrink.seamlock_shatters[1] == 0.0, "Production enemy state transport mirrors the host's exact false-illusion reaction")
	check(results.seamlock_first_shrink.bounds.is_equal_approx(world.current_effective_room_size) and results.seamlock_first_shrink.raw_owner_deployed, "Owner's native penalty lerp and World refresh preserve the same anchor after one step")
	await command("seamlock_duplicate")
	check(seamlock.arena_penalty_steps == 1 and seamlock._illusion_shatter_times[1] == 0.0, "A duplicate accepted-start request with changed aim cannot create another Seamlock guess")
	var sequence := remote_player.effigy_action_seq
	var attack_phase := remote_player._effigy_attack_count
	seamlock._apply_arena_penalty()
	seamlock._apply_arena_penalty()
	seamlock._update_arena_penalty_lerp(10.0)
	world._refresh_effective_room_bounds_from_seamlock_penalty()
	check(not EnemyReplicationService.get_current_room_bounds().has_point(anchor), "The real three-step Seamlock shrink puts the same anchor outside the arena")
	check(remote_player.get_attack_origin().is_equal_approx(remote_player.global_position) and not remote_player.effigy_deployed, "Authoritative bounds refresh recalls the remote owner's invalid anchor")
	check(remote_player.effigy_action_seq == sequence and remote_player._effigy_attack_count == attack_phase, "Bounds recall preserves the accepted action sequence and Attack phase")
	_sync_observed_state()
	await command("seamlock_final_shrink")
	check(not results.seamlock_final_shrink.raw_owner_deployed and results.seamlock_final_shrink.bounds.is_equal_approx(world.current_effective_room_size), "Real shared clear and replicated Seamlock penalty reconcile the owner to the same shrunken arena")
	var clear_received := false
	for cue in results.seamlock_final_shrink.shared_owner_cues:
		if not cue.effigy.deployed and cue.effigy.seq == sequence and cue.effigy.attacks == attack_phase and cue.was_deployed and not cue.deployed and cue.serial == cue.accepted_serial:
			clear_received = true
	check(clear_received, "A fresh accepted host shared-state cue clears the owner's live anchor without inventing another Attack or relying on its getter")

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	begin_run()
	await command("begin")
	check(await until(received), "Effigy peers complete the production run-token handshake")
	await command("miss_deploy")
	check(remote_player.effigy_deployed and remote_player.effigy_position.is_equal_approx(Vector2(0, -180)), "A real missed Attack deploys the joiner's Effigy through the reliable start request")
	check(world.damage_events.is_empty() and not local_player.effigy_deployed, "Miss deployment deals no damage and leaves the host player's Effigy untouched")
	check(results.miss_deploy.primary_actions == 1 and results.miss_deploy.attack_actions.size() == 1, "Deployment on a miss emits one deliberate Attack and creates one action root")
	await command("first_recall")
	check(not remote_player.effigy_deployed and not results.first_recall.owner.deployed, "Normal Dash recalls the first Effigy on both owner and host")
	await command("body_deploy")
	check(enemy(101).get_current_health() == 9900 and enemy(102).get_current_health() == 10000, "Deployment strike hits only the body-side target, not the newly planted Effigy-side target")
	check(remote_player.effigy_position.is_equal_approx(Vector2(180, 0)) and _hits(101).size() == 1, "Deployment stores one fixed Effigy and accepts one body-origin hit")
	if _hits(101).size() == 1:
		check(_hits(101)[0].attack_origin.is_equal_approx(Vector2.ZERO) and _hits(101)[0].source_peer_id == client_id and not _hits(101)[0].secondary, "Deployment damage retains authenticated ownership and its real primary body origin")
	await command("walk")
	check(results.walk.owner.body.distance_to(Vector2.ZERO) > 60.0 and results.walk.owner.position.is_equal_approx(Vector2(180, 0)), "Real ordinary walking moves the body while leaving the Effigy fixed")
	check(await until(func(): return remote_player.global_position.distance_to(results.walk.owner.body) < 24.0), "Production transform interpolation follows the owner before its next Attack start")
	check(remote_player.effigy_deployed and remote_player.effigy_position.is_equal_approx(Vector2(180, 0)), "Replicated body movement cannot drag or recall the authoritative Effigy")
	await command("effigy_attack")
	check(enemy(102).get_current_health() == 9900 and enemy(103).get_current_health() == 10000 and world.damage_events.size() == 2, "The next real Attack hits only from the Effigy, without a body duplicate")
	if _hits(102).size() == 1:
		var hit := _hits(102)[0]
		check(hit.attack_origin.is_equal_approx(Vector2(180, 0)) and hit.source_peer_id == client_id and not hit.secondary and hit.attack_type == "melee", "Effigy damage is the owner's one primary melee Attack at the authenticated fixed origin")
		if _hits(101).size() == 1:
			check(hit.interaction.seq != _hits(101)[0].interaction.seq, "Separate deliberate Attacks retain distinct ordinary action identities")
	else:
		check(false, "Effigy-side target receives exactly one accepted hit")
	check(results.effigy_attack.primary_actions == 3 and results.effigy_attack.attack_actions.size() == 3, "Effigy command adds no second primary event or second action root")
	var swings: Array = results.effigy_attack.swings
	check(swings.size() == 3 and swings.back().origin.is_equal_approx(Vector2(180, 0)) and swings.back().direction.is_equal_approx(Vector2.RIGHT), "Owner swing presentation uses the same Effigy origin and aim as its accepted damage")
	_sync_observed_state()
	check(await until(func(): return (remote_player.player_feedback as EffigyFeedback).swings.size() >= 3), "Host observer receives the real Attack indicator transport")
	var observed_swings := (remote_player.player_feedback as EffigyFeedback).swings
	if not observed_swings.is_empty():
		check(observed_swings.back().origin.is_equal_approx(Vector2(180, 0)) and observed_swings.back().direction.is_equal_approx(Vector2.RIGHT), "Host observer draws the same Effigy-origin strike")
	await command("kill")
	check(await until(func(): return world.kill_peers == [client_id]), "Effigy Attack kill reaches the ordinary authoritative death and owner-credit path")
	check(remote_player.effigy_deployed and remote_player.effigy_position.is_equal_approx(Vector2(180, 0)) and results.kill.owner.deployed, "Killing an enemy leaves the Effigy deployed for both owner and host")
	await command("forged_origins")
	check(enemy(107).get_current_health() == 10000 and remote_player.effigy_position.is_equal_approx(Vector2(180, 0)), "Forged origin, owner, remote deployment and stale action requests cannot create Effigy damage or placement")
	check(not local_player.effigy_deployed, "Forged owner metadata cannot deploy the host player's Effigy")
	_prepare_damage_parity(remote_player)
	await command("prepare_parity")
	check(results.prepare_parity.damage == 37 and is_equal_approx(float(results.prepare_parity.execution_mult), remote_player.execution_damage_mult) and results.prepare_parity.oath_primed, "Both peers prepare the same modified Damage, mapped Execution and primed Oath without resetting Attack counters")
	var execution_damage := int(round(37.0 * remote_player.execution_damage_mult))
	var oath_ratio := remote_player._get_indomitable_retaliation_ratio()
	var oath_damage := int(round(37.0 * oath_ratio))
	var parity_health := enemy(102).get_current_health()
	var parity_hits := _hits(102).size()
	var parity_events := world.damage_events.size()
	await command("parity_attack")
	check(parity_health - enemy(102).get_current_health() == execution_damage + oath_damage, "Real remote Effigy Attack preserves separately rounded Execution and primed Oath damage at non-default Damage")
	check(results.parity_attack.damage_breakdown.base_scaling_damage == execution_damage and results.parity_attack.damage_breakdown.oath_damage == oath_damage and results.parity_attack.damage_breakdown.final_damage == parity_health - enemy(102).get_current_health(), "Owner's actual Attack breakdown agrees with the authoritative accepted damage")
	check(_hits(102).size() == parity_hits + 1 and world.damage_events.size() == parity_events + 1 and results.parity_attack.primary_actions == results.prepare_parity.primary_actions + 1 and results.parity_attack.attack_actions.size() == results.prepare_parity.attack_actions.size() + 1, "Execution and Oath still produce one real Attack root and one accepted Effigy hit")
	if _hits(102).size() == parity_hits + 1:
		var parity_hit: Dictionary = _hits(102).back()
		check(parity_hit.attack_origin.is_equal_approx(Vector2(180, 0)) and parity_hit.source_peer_id == client_id and not parity_hit.secondary and is_equal_approx(float(parity_hit.damage_coefficient), remote_player.execution_damage_mult + oath_ratio), "Modified Effigy hit retains its authenticated origin and combined Damage coefficient")
	check(remote_player.indomitable_damage_bank == 0.0 and not remote_player._indomitable_spirit_primed and results.parity_attack.oath_bank == 0.0 and not results.parity_attack.oath_primed, "Primed Oath is spent once on both peers and the same Attack cannot refill it")
	_attack(local_player, Vector2.RIGHT)
	check(enemy(105).get_current_health() == 9900 and local_player.effigy_position.is_equal_approx(Vector2(-120, -160)), "Host deployment uses the same body-origin Attack contract")
	_attack(local_player, Vector2.RIGHT)
	check(enemy(106).get_current_health() == 9900 and _hits(106).size() == 1 and _hits(106)[0].attack_origin.is_equal_approx(Vector2(-120, -160)), "Host's later primary Attack originates at its own Effigy")
	check(remote_player.effigy_position.is_equal_approx(Vector2(180, 0)), "Host and joiner retain independent Effigy anchors")
	_sync_observed_state()
	await command("inspect_host")
	check(results.inspect_host.observer.deployed and results.inspect_host.observer.position.is_equal_approx(Vector2(-120, -160)), "Joining observer receives the host's authoritative Effigy state")
	await command("recreate_observer")
	check(not results.recreate_observer.observer.deployed, "A recreated observer starts without any remembered Effigy cue")
	local_player.broadcast_network_build_snapshot()
	await command("recover_observer")
	check(results.recover_observer.observer.deployed and results.recover_observer.observer.position.is_equal_approx(Vector2(-120, -160)), "Periodic production state recovers the existing Effigy for a late observer without another Attack")
	check(results.recover_observer.observer.attack_phase == local_player._effigy_attack_count, "Actual owner build broadcast seeds a late observer with the already advanced Attack phase")
	await command("final_recall")
	check(not remote_player.effigy_deployed and local_player.effigy_deployed, "Joiner Dash recalls only its own Effigy")
	await command("replay_deployment")
	check(not remote_player.effigy_deployed, "A delayed duplicate deployment start cannot replant an Effigy after Dash recall")
	local_player.apply_character_package(CHARACTERS.get_character("bastion"))
	local_player.broadcast_network_build_snapshot()
	_sync_observed_state()
	await command("inspect_cleanup")
	check(not local_player.effigy_deployed and not results.inspect_cleanup.observer.deployed, "Character change clears host and observer Effigy presentation")
	check(results.inspect_cleanup.damage_events == 0 and results.inspect_cleanup.scope.is_empty(), "Replica presentation and owner requests produce no client damage accounting or leaked interaction scope")
	await _test_remote_seamlock()
	await command("finish")
	await finish()

func client_command(name: String, _payload: Dictionary) -> void:
	match name:
		"begin":
			begin_run()
			check(await until(func(): return not INTERACTIONS.current_run().is_empty()), "Joiner binds the actual host run token")
		"miss_deploy":
			_attack(local_player, Vector2.UP)
			check(enemy(101).get_current_health() == 10000, "Owner prediction does not damage an enemy on a miss")
		"first_recall", "final_recall":
			_dash(local_player)
		"body_deploy":
			_attack(local_player, Vector2.RIGHT)
			check(enemy(101).get_current_health() == 10000, "Owner body strike submits damage without mutating replica health")
		"walk":
			local_player.attack_lock_time_left = 0.0
			Input.action_press("move_down")
			for step in range(32):
				local_player._physics_process(1.0 / 60.0)
				await physics_frame
			Input.action_release("move_down")
			local_player.velocity = Vector2.ZERO
			PlayerReplicationService._sync_all_player_positions()
		"effigy_attack":
			_attack(local_player, Vector2.RIGHT)
		"prepare_parity":
			_prepare_damage_parity(local_player)
			local_player.broadcast_network_build_snapshot()
		"parity_attack":
			_attack(local_player, Vector2.RIGHT)
		"kill":
			_attack(local_player, Vector2.UP)
			saved_action = (local_player as EffigyPlayer).attack_actions.back().duplicate(true)
			saved_start = {"body_origin": local_player.global_position, "direction": Vector2.UP, "blast_strength": -1.0}
			check(await until(func(): return not (local_player as EffigyPlayer).kill_interactions.is_empty()), "Owner receives the real Effigy Attack kill callback")
		"forged_origins":
			var action: Dictionary = (local_player as EffigyPlayer).attack_actions.back().duplicate(true)
			DAMAGE.apply_damage(enemy(107), 100, INTERACTIONS.damage_context(action, "melee", {"raw_amount": 100.0, "damage_coefficient": 1.0, "attack_origin": Vector2(10000, 10000)}))
			var forged_owner := action.duplicate(true)
			forged_owner.owner = 1
			world.request_shared_attack_start_from_client(INTERACTIONS.damage_context(forged_owner, "melee").interaction, {"body_origin": Vector2.ZERO, "direction": Vector2.RIGHT})
			DAMAGE.apply_damage(enemy(107), 100, INTERACTIONS.damage_context(forged_owner, "melee", {"raw_amount": 100.0, "damage_coefficient": 1.0, "attack_origin": Vector2(180, 0)}))
			var remote_start := local_player.new_combat_action("melee")
			world.request_shared_attack_start_from_client(INTERACTIONS.damage_context(remote_start, "melee").interaction, {"body_origin": Vector2(10000, 10000), "direction": Vector2.RIGHT})
			DAMAGE.apply_damage(enemy(107), 100, INTERACTIONS.damage_context(remote_start, "melee", {"raw_amount": 100.0, "damage_coefficient": 1.0, "attack_origin": Vector2(10000, 10000)}))
			for key in ["run", "room", "epoch"]:
				var stale := action.duplicate(true)
				stale[key] = "retired-effigy-run" if key == "run" else -1
				world.request_shared_attack_start_from_client(INTERACTIONS.damage_context(stale, "melee").interaction, {"body_origin": local_player.global_position, "direction": Vector2.RIGHT})
				DAMAGE.apply_damage(enemy(107), 100, INTERACTIONS.damage_context(stale, "melee", {"raw_amount": 100.0, "damage_coefficient": 1.0, "attack_origin": Vector2(180, 0)}))
		"inspect_host":
			check(await until(func(): return remote_player.effigy_deployed and remote_player.effigy_position.is_equal_approx(Vector2(-120, -160))), "Authoritative host Effigy reaches the actual joining observer")
		"recreate_observer":
			PlayerReplicationService.unregister_player(1)
			if is_instance_valid(remote_player.upgrade_system.power_registry):
				remote_player.upgrade_system.power_registry.free()
			remote_player.free()
			remote_player = _create_actor(1)
		"recover_observer":
			check(await until(func(): return remote_player.effigy_deployed and remote_player.effigy_position.is_equal_approx(Vector2(-120, -160))), "Late observer recovers the existing Effigy through periodic production state")
		"replay_deployment":
			world.request_shared_attack_start_from_client(INTERACTIONS.damage_context(saved_action, "melee").interaction, saved_start)
		"inspect_cleanup":
			check(await until(func(): return not remote_player.effigy_deployed), "Character cleanup reaches the observing joiner")
		"seamlock_prepare":
			_create_seamlock()
			local_player.global_position = Vector2(250, -150)
			PlayerReplicationService._sync_all_player_positions()
		"seamlock_deploy":
			_attack(local_player, Vector2.RIGHT)
		"seamlock_guess":
			check(await until(func(): return seamlock._illusion_positions.size() == 2, 1.5), "Joiner observes the native false illusions before issuing its perpendicular Attack")
			_attack(local_player, Vector2.UP)
			saved_action = (local_player as EffigyPlayer).attack_actions.back().duplicate(true)
			saved_start = {"body_origin": local_player.global_position, "direction": Vector2.UP, "blast_strength": -1.0}
			check(seamlock.arena_penalty_steps == 0, "Owner prediction does not guess on the native Seamlock replica")
		"seamlock_first_shrink":
			check(await until(func(): return seamlock.arena_penalty_steps == 1, 1.5), "Native enemy broadcaster delivers the accepted wrong-guess penalty")
			seamlock._update_arena_penalty_lerp(10.0)
			world._refresh_effective_room_bounds_from_seamlock_penalty()
			(local_player as EffigyPlayer).shared_owner_cues.clear()
		"seamlock_duplicate":
			var duplicate_start := saved_start.duplicate(true)
			duplicate_start.direction = Vector2.RIGHT
			world.request_shared_attack_start_from_client(INTERACTIONS.damage_context(saved_action, "melee").interaction, duplicate_start)
		"seamlock_final_shrink":
			# Keep the owner's World bounds at one step until the host clear arrives;
			# local geometry polling therefore cannot satisfy reconciliation alone.
			check(await until(_has_received_bounds_clear, 1.5) and not local_player.effigy_deployed, "Host shared-state transport clears the live owner anchor before its local bounds change")
			check(await until(func(): return seamlock.arena_penalty_steps == 3, 1.5), "Native enemy transport delivers the final Seamlock shrink")
			seamlock._update_arena_penalty_lerp(10.0)
			world._refresh_effective_room_bounds_from_seamlock_penalty()
		"finish":
			report(name)
			await create_timer(0.1).timeout
			await finish()
			return
	report(name)

extends "res://scripts/tests/test_combat_interactions_enet.gd"
## Separate real peers: host-accepted keyword reactions and observer recovery.

const BASE_DAMAGE := 37
const PATIENT_BONUS := 11
const MARKED_BONUS := 13
const REWARD_OBSERVERS := [402, 403, 404, 406, 412, 413, 414, 502, 503, 601, 602]
var transport_tick_usec: int = 0
var stale_relay_state: Dictionary = {}
var fresh_owner_build: Dictionary = {}

class KeywordPlayer extends InteractionPlayer:
	func _notification(_what: int) -> void:
		# Isolated peers have no focused OS game window.
		pass

class KeywordEnemy extends Enemy:
	var hits: Array[Dictionary] = []
	func take_damage(amount: int, context: Dictionary = {}) -> void:
		var before := get_current_health()
		var accepted_action := DAMAGE.current_interaction_context()
		super.take_damage(amount, context)
		if get_current_health() < before:
			hits.append({"amount": before - get_current_health(), "context": context.duplicate(true), "accepted_action": accepted_action})

func _create_actor(id: int) -> KeywordPlayer:
	var actor := KeywordPlayer.new()
	actor.name = "Player_%d" % id
	actor.player_id = id
	actor.is_local_player = id == get_multiplayer().get_unique_id()
	circle(actor, 14.0)
	world.add_child(actor)
	if actor.is_local_player:
		fresh_owner_build = actor.build_run_snapshot()
	actor.damage = BASE_DAMAGE
	actor.patient_hunter_bonus_damage = PATIENT_BONUS
	actor.marked_prey_bonus_damage = MARKED_BONUS
	for power in ["stormbrand", "spark_relay"]:
		actor.apply_trial_power(power)
	actor.apply_upgrade("shatterwake")
	actor.position = Vector2(-1000.0, 0.0) if id == 1 else Vector2.ZERO
	actor.arcana_motion.set_process(false)
	actor.returning_crescent.set_physics_process(false)
	actor.boss_combinations.set_process(false)
	# launch() and received snapshots enable physics themselves; disable this
	# node's automatic clock while keeping every production method intact.
	actor._ensure_spark_relay().process_mode = Node.PROCESS_MODE_DISABLED
	PlayerReplicationService.register_player(id, actor)
	return actor

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1: {}, client_id: {}}
	RunContext.set_multiplayer_session("keyword-synergies-loopback", role == "host")
	RunContext.meta_progress_profile = {}
	world.current_room_size = Vector2(3000.0, 2400.0)
	world.current_effective_room_size = world.current_room_size
	world.difficulty_provider = preload("res://scripts/core/difficulty_scaling_provider.gd").new(world)
	GameStateReplicationService.initialize(world)
	process_frame.connect(_pump_transport)
	for id in [1, client_id]:
		var actor := _create_actor(id)
		if actor.is_local_player:
			local_player = actor
			world.player = actor
		else:
			remote_player = actor
	var positions := {101: Vector2(900, 900), 102: Vector2(900, -900), 201: Vector2(160, 0), 202: Vector2(200, 45), 203: Vector2(700, 0), 301: Vector2(-840, 0), 302: Vector2(-800, 45), 303: Vector2(-300, 0)}
	positions.merge({401: Vector2(0, 700), 402: Vector2(80, 700), 403: Vector2(140, 700), 404: Vector2(170, 700), 405: Vector2(0, 950), 406: Vector2(60, 950), 407: Vector2(40, 700), 411: Vector2(-700, 700), 412: Vector2(-620, 700), 413: Vector2(-560, 700), 414: Vector2(-530, 700), 417: Vector2(-660, 700), 501: Vector2(900, -500), 502: Vector2(940, -500), 503: Vector2(1050, -500), 601: Vector2(900, -800), 602: Vector2(900, -760)})
	for id in positions:
		var target := KeywordEnemy.new()
		target.name = "Enemy_%d" % id
		circle(target, 13.0)
		world.add_child(target)
		target.position = positions[id]
		target.health_state.setup(10000, 10000)
		if id in [401, 405, 407, 411, 417, 501]:
			target.health_state.current_health = 1
		world.enemy_state_sync_broadcaster.register_enemy(target, id)
	world.active_room_enemy_count = positions.size()

func _pump_transport() -> void:
	if finished or not MultiplayerSessionManager.is_session_connected():
		return
	# Autoload fixtures suppress idle callbacks. Pump the production transports
	# while projectile time remains explicitly controlled on the host.
	var now := Time.get_ticks_usec()
	var delta := 1.0 / 60.0 if transport_tick_usec == 0 else float(now - transport_tick_usec) / 1000000.0
	transport_tick_usec = now
	PlayerReplicationService._sync_all_player_positions()
	PlayerReplicationService._interpolate_remote_players(delta)
	PlayerReplicationService._flush_pending_cue_events()
	# A crowded roster staggers runtime sampling across real physics frames.
	# Keep this production transport running while waiting for observed status.
	if role == "host":
		world.enemy_state_sync_broadcaster.tick(delta)

func _hits(id: int, source: String = "") -> Array:
	var records: Array = (enemy(id) as KeywordEnemy).hits
	return records if source.is_empty() else records.filter(func(entry: Dictionary) -> bool: return String(entry.context.get("attack_type", "")) == source)

func _state(actor: Player) -> Dictionary:
	var relay: Node = actor._ensure_spark_relay()
	return {"body": actor.global_position, "damage": actor.damage, "patient": actor.patient_hunter_bonus_damage, "marked": actor.marked_prey_bonus_damage, "relay": relay.build_network_state(), "projectiles": relay.projectiles.size()}

func report(key: String) -> void:
	var reward_targets := {}
	for id in REWARD_OBSERVERS:
		var target := enemy(id)
		reward_targets[id] = {"health": target.get_current_health(), "position": target.global_position, "velocity": target.velocity, "slow": target.is_slowed(), "slow_mult": target.slow_speed_mult, "slow_time_left": target.slow_time_left, "mark": DAMAGE.status_snapshot(target, joiner_id)}
	world.fixture_result.rpc_id(1, key, {"owner": _state(local_player), "observer": _state(remote_player), "status": DAMAGE.get_status_network_state(enemy(101)), "mark": DAMAGE.status_snapshot(enemy(101), joiner_id), "damage_events": world.damage_events.size(), "scope": DAMAGE.current_interaction_context(), "epoch": local_player.combat_interactions._epoch, "action": next_action.duplicate(true), "reward_targets": reward_targets, "kills": (local_player as InteractionPlayer).kill_interactions.duplicate(true)})

func _deal(id: int, source: String, action: Dictionary, raw: float = BASE_DAMAGE, coefficient: float = 1.0) -> void:
	DAMAGE.apply_damage(enemy(id), int(raw), INTERACTIONS.damage_context(action, source, {"raw_amount": raw, "damage_coefficient": coefficient, "secondary": not INTERACTIONS.is_attack_hit(source), "attack_origin": enemy(id).global_position + Vector2.LEFT * 40.0}), local_player.player_id)

func _publish_status() -> void:
	# Cover the expanded roster using the production bounded scan cursor.
	for _scan in range(4):
		world.enemy_state_sync_broadcaster.tick(0.25)
	PlayerReplicationService._flush_pending_cue_events()

func _conditional_scenario() -> void:
	await command("electric_first")
	check(enemy(101).get_current_health() == 10000 - BASE_DAMAGE - PATIENT_BONUS, "First Electric damage gets pre-existing Slow bonus, without its new Stormbrand Mark or Marked Prey")
	var ratio := float(DAMAGE.status_snapshot(enemy(101), joiner_id).mark_ratio)
	check(ratio > 0.0, "Accepted Electric Field damage applies authoritative Stormbrand Mark")
	var records: Array = DAMAGE.get_status_network_state(enemy(101)).m
	check(records.any(func(entry: Array) -> bool: return int(entry[0]) == joiner_id and String(entry[1]) == "stormbrand"), "Stormbrand status retains the authenticated joining owner and its registered source")
	_publish_status()
	await command("inspect_mark")
	check(is_equal_approx(float(results.inspect_mark.mark.mark_ratio), ratio), "Production status broadcaster and receiver mirror the exact host Stormbrand strength")
	check(results.inspect_mark.damage_events == 0, "Observing client applies status without simulating accepted damage")
	var before := enemy(101).get_current_health()
	await command("electric_half")
	var expected := int(round(0.5 * float(BASE_DAMAGE + PATIENT_BONUS + MARKED_BONUS) * (1.0 + ratio)))
	check(before - enemy(101).get_current_health() == expected, "Half-Damage packet distributes both conditional Boons before the existing Mark multiplier exactly once")
	var half_hits := _hits(101, "static_wake")
	check(half_hits.size() == 2 and is_equal_approx(float(half_hits.back().context.damage_coefficient), 0.5), "Accepted remote packet retains its half-Damage coefficient")

func _invalid_scenario() -> void:
	var before := enemy(102).get_current_health()
	await command("invalid_packets")
	check(enemy(102).get_current_health() == before and _hits(102).is_empty(), "Malformed, forged-owner, wrong-run and wrong-room shared packets are rejected before damage")
	check(float(DAMAGE.status_snapshot(enemy(102), joiner_id).mark_ratio) == 0.0, "Rejected Electric packets cannot create Stormbrand Mark")
	check(local_player._ensure_spark_relay().projectiles.is_empty() and remote_player._ensure_spark_relay().projectiles.size() == 1, "Joining client cannot forge the dedicated host projectile-state RPC for either owner")
	await command("cancel_stale")
	check(remote_player.combat_interactions._accepted_epoch == int(results.cancel_stale.epoch), "Owner lifecycle cancellation crosses the reliable authenticated epoch transport")
	check(enemy(102).get_current_health() == before, "Retired-root damage remains rejected after owner cancellation")
	remote_player._ensure_spark_relay().tick(0.01)
	check(remote_player._ensure_spark_relay().projectiles.is_empty(), "Host retires the joining owner's held flight when its original epoch is cancelled")
	await command("inspect_relay_clear")
	check(results.inspect_relay_clear.owner.projectiles == 0, "Cancelled joining-owner flight remains cleared after the host acknowledgement")

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	if is_instance_valid(deadline_timer):
		deadline_timer.start(40.0)
	begin_run()
	await command("begin")
	check(await until(received), "Both real ENet peers share the authoritative run token")
	await _conditional_scenario()
	await _relay_scenario()
	await _invalid_scenario()
	await _seeking_relay_scenario()
	await _stationary_reward_scenario()
	check(DAMAGE.current_interaction_context().is_empty(), "All generated reactions release the authoritative interaction scope")
	await command("finish")
	await finish()

func _stationary_reward_scenario() -> void:
	await command("edict_build", {"level": 1, "damage": 37})
	check(await until(func(): return remote_player.edict_court_push_power == 40 and remote_player.damage == 37), "Actual owner build broadcast supplies Edict level one and nondefault Damage to the host")
	await command("edict_kill", {"enemy": 401})
	check(_hits(402, "edict_court").size() == 1 and enemy(402).get_current_health() == 9970, "Accepted remote kill creates exactly one host Edict hit at 80% of Damage37")
	var first_hits := _hits(402, "edict_court")
	if not first_hits.is_empty():
		var hit: Dictionary = first_hits[0]
		check(is_equal_approx(float(hit.context.raw_amount), 29.6) and is_equal_approx(float(hit.context.damage_coefficient), 0.8), "Host Edict derives the unconditioned amount and coefficient from the accepted owner's build")
		check(int(hit.context.interaction.owner) == joiner_id and int(hit.context.interaction.seq) == int(results.edict_kill.action.seq) and int(hit.context.interaction.ancestry) == INTERACTIONS.EDICT_ANCESTRY, "Edict retains authenticated ownership and original root with its own ancestry bit")
	check(enemy(402).is_slowed() and is_equal_approx(enemy(402).slow_speed_mult, 0.75) and is_equal_approx(enemy(402).slow_time_left, 1.5) and enemy(402).velocity.is_zero_approx(), "The surviving Edict victim receives its 1.5-second Slow without Push or launch velocity")
	check(_hits(403, "edict_court").is_empty() and _hits(404, "edict_court").is_empty(), "Level-one Edict leaves victims beyond its 120-pixel radius untouched")
	await command("edict_same_root", {"enemy": 405})
	check(_hits(406, "edict_court").is_empty() and _hits(402, "edict_court").size() == 1, "A second accepted kill on the same root cannot repeat Edict, including after its descendant kill")
	_publish_status()
	if not await command("inspect_edict", {"enemy": 402}):
		return
	check(results.inspect_edict.reward_targets[402].slow and is_equal_approx(float(results.inspect_edict.reward_targets[402].slow_mult), 0.75) and results.inspect_edict.damage_events == 0, "Existing status transport mirrors Edict Slow while the joining owner records no local damage")
	var edict_kills: Array = results.inspect_edict.kills
	check(edict_kills.any(func(action: Dictionary) -> bool: return String(action.get("source", "")) == "edict_court" and int(action.ancestry) == 4), "An actual Edict descendant kill transports ancestry4 to the owning peer")
	# This target stays far from both bodies and has no Mark. Expire its real
	# native Slow clock without another hit or movement to refresh its state.
	enemy(402)._update_attack_animation(1.6)
	check(not enemy(402).is_slowed(), "The native Edict survivor Slow expires while its victim stays stationary")
	_publish_status()
	if not await command("inspect_edict_clear"):
		return
	check(not results.inspect_edict_clear.reward_targets[402].slow and is_zero_approx(float(results.inspect_edict_clear.reward_targets[402].slow_time_left)) and is_equal_approx(float(results.inspect_edict_clear.reward_targets[402].slow_mult), 1.0) and int(results.inspect_edict_clear.reward_targets[402].health) == 9970, "Far observer receives the final Slow-clear delta without another damage event")
	await command("edict_build", {"level": 2, "damage": 53})
	check(await until(func(): return remote_player.edict_court_push_power == 80 and remote_player.damage == 53), "The next real owner snapshot updates both Edict level and Damage on the host")
	await command("edict_kill", {"enemy": 411, "inherited_ancestry": true})
	check(_hits(412, "edict_court").size() == 1 and enemy(412).get_current_health() == 9936 and enemy(413).get_current_health() == 9936, "Level-two Edict uses 120% of updated Damage53 and reaches the 140-pixel annulus")
	check(_hits(414, "edict_court").is_empty() and enemy(413).velocity.is_zero_approx(), "The 160-pixel boundary excludes the outer victim and keeps the inner victim stationary")
	_publish_status()
	if not await command("inspect_edict", {"enemy": 413}):
		return
	var combined_kills: Array = results.inspect_edict.kills
	check(combined_kills.any(func(action: Dictionary) -> bool: return String(action.get("source", "")) == "edict_court" and int(action.ancestry) == 7), "Crown, Tempo and Edict ancestry7 survives a real descendant kill RPC")
	var untouched_health := enemy(414).get_current_health()
	await command("forged_edict")
	check(enemy(414).get_current_health() == untouched_health and _hits(414).is_empty(), "Directly submitted Edict damage cannot forge the host-only producer even with a valid owner/root")
	await command("unknown_ancestry")
	var sanitized := _hits(404, "melee")
	check(sanitized.size() == 2 and int(sanitized[0].accepted_action.ancestry) == 0 and int(sanitized[1].accepted_action.ancestry) == 7, "Actual accepted damage scope removes unknown ancestry16/128 while preserving the valid combined mask7")
	await _stationary_field_scenario()

func _stationary_field_scenario() -> void:
	await command("stationary_field_build")
	check(await until(func(): return remote_player.void_echo_damage > 0 and is_equal_approx(remote_player.null_corridor_strength, 0.5) and remote_player.edict_court_push_power == 0), "Actual owner replacement snapshot installs Lacuna and Null Corridor without retaining Edict")
	await command("lacuna_kill")
	await command("lacuna_native_pulse")
	# Level-one Lacuna's native 17-base pulse also receives its existing 20.3%
	# owned-Field bonus, yielding 20 damage before this contact applies Slow.
	var lacuna_hits := _hits(502, "void_echo_zone")
	check(lacuna_hits.size() == 1 and enemy(502).get_current_health() == 9980 and is_equal_approx(float(lacuna_hits[0].context.damage_coefficient), 0.13) and is_equal_approx(enemy(502).slow_speed_mult, 0.75) and is_equal_approx(enemy(502).slow_time_left, 0.45), "The owner's real Lacuna pulse retains 20 damage including its Field bonus and applies its host-accepted 0.45-second survivor Slow")
	check(enemy(502).velocity.is_zero_approx() and _hits(503, "void_echo_zone").is_empty(), "Lacuna preserves its local radius without Pulling the inside victim")
	await command("corridor_native_tick")
	check(_hits(601, "null_corridor_deflect").size() == 1 and enemy(601).get_current_health() == 9991 and is_equal_approx(float(DAMAGE.status_snapshot(enemy(601), joiner_id).mark_ratio), 0.1), "The real owner corridor tick retains 9 damage before applying the host-derived level-one Mark")
	check(enemy(601).velocity.is_zero_approx() and _hits(602, "null_corridor_deflect").is_empty(), "Corridor keeps its original strip geometry without side Push")
	var mark_wire: Dictionary = DAMAGE.get_status_network_state(enemy(601))
	check((mark_wire.m as Array).any(func(entry: Array) -> bool: return int(entry[0]) == joiner_id and String(entry[1]) == "null_corridor"), "New Corridor status keeps its registered source and authenticated owner")
	_publish_status()
	if not await command("inspect_stationary_status"):
		return
	check(is_equal_approx(float(results.inspect_stationary_status.reward_targets[601].mark.mark_ratio), 0.1) and results.inspect_stationary_status.reward_targets[502].slow and results.inspect_stationary_status.damage_events == 0, "Existing enemy-state transport delivers both new statuses without client damage simulation")
	await command("recreate_status_observer")
	# Send the production full enemy-state snapshot after replacing its local
	# target status node; this exercises late observation of the same live Mark.
	_publish_status()
	if not await command("inspect_stationary_status"):
		return
	check(is_equal_approx(float(results.inspect_stationary_status.reward_targets[601].mark.mark_ratio), 0.1), "A fresh observer recovers the active Corridor Mark through the existing snapshot")
	var outside_health := enemy(602).get_current_health()
	await command("forged_corridor_mark")
	check(enemy(602).get_current_health() == outside_health and float(DAMAGE.status_snapshot(enemy(602), joiner_id).mark_ratio) == 0.0, "A plausible client Mark RPC cannot manufacture accepted Corridor contact")
	var prior_hits := _hits(601).size()
	await command("cancel_stationary_fields")
	check(remote_player.combat_interactions._accepted_epoch == int(results.cancel_stationary_fields.epoch) and _hits(601).size() == prior_hits, "Owner cancellation crosses ENet and rejects the retained old corridor action")
	check(results.cancel_stationary_fields.scope.is_empty() and DAMAGE.current_interaction_context().is_empty(), "Stationary reward and lifecycle callbacks release both interaction scopes")

func _relay_scenario() -> void:
	await command("burst")
	var relay: Node = remote_player._ensure_spark_relay()
	check(relay.projectiles.size() == 1, "Accepted remote Burst launches one host-owned Electric Projectile")
	if relay.projectiles.size() == 1:
		var projectile: RefCounted = relay.projectiles[0]
		check(projectile.position.is_equal_approx(remote_player.global_position) and projectile.direction.is_equal_approx(Vector2.RIGHT), "Relay launches at the owning body toward the Burst target, away from the submitted Burst origin")
		check(is_equal_approx(projectile.raw_amount, 18.5) and is_equal_approx(projectile.damage_coefficient, 0.5), "Relay retains half the unconditioned Damage37 descriptor despite its already Slowed and Marked trigger victim")
		check(int(projectile.interaction.owner) == joiner_id and int(projectile.interaction.seq) == int(results.burst.action.seq), "Generated projectile keeps the authenticated original action")
	await command("inspect_relay")
	check(results.inspect_relay.owner.projectiles == 1 and results.inspect_relay.observer.projectiles == 0, "Host projectile state reaches its actual owner without attaching to the other player")
	var received: Array = results.inspect_relay.owner.relay.projectiles
	check(received.size() == 1 and Vector2(float(received[0][1]), float(received[0][2])).is_equal_approx(Vector2.ZERO), "Owner receives the exact body-origin projectile through the dedicated production transport")
	await command("burst_same")
	check(relay.projectiles.size() == 1, "Later Burst damage from the same root cannot launch a second Relay")
	relay.tick(0.4)
	check(relay.projectiles.is_empty(), "Authoritative projectile ends after its level-one accepted impact")
	var projectile_hits := _hits(201, "spark_relay_projectile")
	check(projectile_hits.size() == 1 and int(projectile_hits[0].amount) == 19, "Real projectile sweep accepts its half-Damage impact exactly once")
	check(_hits(201, "shatterwake_burst").size() == 1 and _hits(202, "shatterwake_burst").size() == 1, "One accepted Projectile releases one Shatterwake Burst across nearby victims")
	check(_hits(202, "spark_relay_projectile").is_empty(), "Off-path neighbor receives the Burst without inventing a projectile impact")
	for id in [201, 202]:
		for hit: Dictionary in _hits(id, "shatterwake_burst"):
			check(is_equal_approx(float(hit.context.raw_amount), 11.1) and is_equal_approx(float(hit.context.damage_coefficient), 0.3), "Shatterwake preserves the unconditioned descriptor and coefficient for victim%d" % id)
			check(int(hit.context.interaction.owner) == joiner_id and int(hit.context.interaction.seq) == int(results.burst.action.seq), "Burst descendant retains the same authenticated root for victim%d" % id)
	check(relay.projectiles.is_empty() and remote_player.combat_interactions.has_reaction(results.burst.action, "spark_relay") and remote_player.combat_interactions.has_reaction(results.burst.action, "shatterwake"), "Burst to Projectile to Burst spends both original-action allowances and terminates")
	check(world.damage_events.all(func(entry: Dictionary) -> bool: return int(entry.peer) == joiner_id), "Every accepted damage event in the joining-owner chain is credited to that peer")
	_publish_status()
	await command("inspect_relay_clear")
	check(results.inspect_relay_clear.owner.projectiles == 0 and results.inspect_relay_clear.damage_events == 0, "Reliable impact cleanup removes the owning client's visual without local damage")
	await _late_observer_scenario()
	# Leave one joining-owner flight active for the later lifecycle cancellation.
	await command("burst_again")
	check(relay.projectiles.size() == 1, "A later original action gets a fresh independent Relay allowance")

func _seeking_relay_scenario() -> void:
	# Move existing registered enemies so the reliable position and accepted
	# damage transports exercise a genuine off-axis lethal-trigger redirect.
	enemy(203).health_state.current_health = 1
	enemy(201).position = Vector2(0, -160)
	enemy(202).position = Vector2(160, 160)
	_publish_status()
	var relay: Node = remote_player._ensure_spark_relay()
	await command("burst_again")
	check((not is_instance_valid(enemy(203)) or enemy(203).get_current_health() <= 0) and relay.projectiles.size() == 1, "Accepted joining-owner lethal Burst still creates a useful host-owned Relay")
	if relay.projectiles.is_empty():
		return
	check(relay.projectiles[0].direction.is_equal_approx(Vector2.UP), "Host acquires the living off-axis foe instead of the dead trigger's submitted position")
	relay.tick(.06)
	_deal(201, "melee", local_player.combat_interactions.begin_action("attack"), 20000.0)
	relay.tick(.02)
	check(relay.projectiles.size() == 1 and relay.projectiles[0].direction.x > .5 and relay.projectiles[0].direction.y > .3, "Host redirects the same in-flight bolt when another player kills its acquired target")
	await command("inspect_seeking_turn")
	var observed: Array = results.inspect_seeking_turn.owner.relay.projectiles
	check(observed.size() == 1 and float(observed[0][3]) > .5 and float(observed[0][4]) > .3 and results.inspect_seeking_turn.damage_events == 0, "Authenticated direction snapshot reaches the joining owner without client targeting or local damage")
	var before := _hits(202, "spark_relay_projectile").size()
	relay.tick(1.0)
	check(relay.projectiles.is_empty() and _hits(202, "spark_relay_projectile").size() == before + 1, "Retargeted host bolt hits the surviving foe once and ends at its original level-one cap")
	var hit: Dictionary = _hits(202, "spark_relay_projectile").back()
	check(int(hit.context.interaction.owner) == joiner_id and int(hit.context.interaction.seq) == int(results.burst_again.action.seq) and is_equal_approx(float(hit.context.raw_amount), 18.5) and is_equal_approx(float(hit.context.damage_coefficient), .5), "Retargeted hit preserves the joining owner's original root and unconditioned descriptor")
	await command("inspect_relay_clear")
	check(results.inspect_relay_clear.owner.projectiles == 0, "Reliable impact clear retires the retargeted flight on its owning client")

func _late_observer_scenario() -> void:
	var action := local_player.combat_interactions.begin_action("attack")
	_deal(303, "rupture_wave", action)
	var relay: Node = local_player._ensure_spark_relay()
	check(relay.projectiles.size() == 1, "Host player can independently own an active Relay")
	await command("inspect_host_relay")
	check(results.inspect_host_relay.observer.projectiles == 1, "Joining observer receives the host player's separate projectile")
	await command("recreate_observer")
	check(results.recreate_observer.observer.projectiles == 0, "Recreated observer has no remembered flight")
	local_player.broadcast_network_build_snapshot()
	# Exercise the controller's production state publisher on the held flight.
	relay._publish_state(true)
	await command("recover_observer")
	var recovered: Array = results.recover_observer.observer.relay.projectiles
	check(recovered.size() == 1 and Vector2(float(recovered[0][1]), float(recovered[0][2])).is_equal_approx(Vector2(-1000, 0)), "Late observer recovers the existing host flight from an actual owner build and current projectile snapshot")
	stale_relay_state = relay.build_network_state().duplicate(true)
	for key in ["run", "room", "projectiles"]:
		var malformed := stale_relay_state.duplicate(true)
		malformed.serial = int(malformed.serial) + 1000
		match key:
			"run": malformed.run = "retired-relay-run"
			"room": malformed.room = 999
			"projectiles": malformed.projectiles[0][3] = NAN
		PlayerReplicationService.broadcast_spark_relay_state(1, malformed, true)
	relay.tick(0.04)
	relay._publish_state(true)
	await command("inspect_host_progress")
	var progressed: Array = results.inspect_host_progress.observer.relay.projectiles
	check(progressed.size() == 1 and float(progressed[0][1]) > -1000.0, "Malformed or wrong-identity state cannot poison the next genuine snapshot sequence")
	local_player._cancel_interactions()
	check(relay.projectiles.is_empty(), "Host lifecycle cancellation clears active projectile authority")
	stale_relay_state.serial = int(stale_relay_state.serial) + 2000
	PlayerReplicationService.broadcast_spark_relay_state(1, stale_relay_state, true)
	await command("inspect_host_clear")
	check(results.inspect_host_clear.observer.projectiles == 0, "Old-epoch flight cannot resurrect after authenticated lifecycle clear")

func _replace_reward_build(powers: Array) -> void:
	# A character package changes identity and base stats, while a genuine
	# checkpoint restore also clears the prior learned build and its effects.
	local_player.apply_run_snapshot(fresh_owner_build.duplicate(true))
	local_player.apply_character_package(local_player.CHARACTER_REGISTRY.get_character("veilstrider"))
	local_player.damage = BASE_DAMAGE
	for power: String in powers:
		local_player.apply_upgrade(power)
	local_player.broadcast_network_build_snapshot()

func client_command(name: String, payload: Dictionary) -> void:
	match name:
		"begin":
			if is_instance_valid(deadline_timer):
				deadline_timer.start(40.0)
			begin_run()
			check(await until(func(): return not INTERACTIONS.current_run().is_empty()), "Joiner binds the actual run token")
		"electric_first":
			next_action = local_player.combat_interactions.begin_action("dash")
			check(DAMAGE.apply_slow(enemy(101), 20.0, 0.5, joiner_id, next_action), "Owner sends pre-Slow through the real status request")
			_deal(101, "static_wake", next_action)
			check(not enemy(101).is_slowed(), "Owner status request leaves local state unchanged until replication")
		"electric_half":
			next_action = local_player.combat_interactions.begin_action("dash")
			_deal(101, "static_wake", next_action, float(BASE_DAMAGE) * 0.5, 0.5)
		"inspect_mark":
			check(await until(func(): return float(DAMAGE.status_snapshot(enemy(101), joiner_id).mark_ratio) > 0.0), "Actual joining owner observes Stormbrand status")
		"burst":
			next_action = local_player.combat_interactions.begin_action("attack")
			DAMAGE.apply_slow(enemy(203), 20.0, 0.5, joiner_id, next_action)
			_deal(203, "static_wake", next_action)
			_deal(203, "rupture_wave", next_action)
		"burst_same":
			_deal(203, "rupture_wave", next_action)
		"burst_again":
			next_action = local_player.combat_interactions.begin_action("attack")
			_deal(203, "rupture_wave", next_action)
		"inspect_relay":
			check(await until(func(): return local_player._ensure_spark_relay().projectiles.size() == 1), "Actual owner receives its host-generated flight")
		"inspect_seeking_turn":
			check(await until(func():
				var relay: Node = local_player._ensure_spark_relay()
				return relay.projectiles.size() == 1 and relay.projectiles[0].direction.x > .5 and relay.projectiles[0].direction.y > .3), "Actual owner receives the authoritative retargeted direction")
		"inspect_relay_clear":
			check(await until(func(): return local_player._ensure_spark_relay().projectiles.is_empty()), "Owner receives the reliable impact clear")
		"inspect_host_relay", "recover_observer":
			check(await until(func(): return remote_player._ensure_spark_relay().projectiles.size() == 1), "Observer receives the current host flight")
		"recreate_observer":
			PlayerReplicationService.unregister_player(1)
			if is_instance_valid(remote_player.upgrade_system.power_registry):
				remote_player.upgrade_system.power_registry.free()
			remote_player.free()
			remote_player = _create_actor(1)
		"inspect_host_progress":
			check(await until(func():
				var controller: Node = remote_player._ensure_spark_relay()
				return controller.projectiles.size() == 1 and float(controller.projectiles[0].position.x) > -1000.0), "Observer accepts normal progress after malformed snapshots")
		"inspect_host_clear":
			check(await until(func(): return remote_player._ensure_spark_relay().projectiles.is_empty()), "Observer receives authenticated host lifecycle cleanup")
		"edict_build":
			if int(payload.level) == 1:
				_replace_reward_build(["edict_of_the_court"])
			else:
				local_player.apply_upgrade("edict_of_the_court")
			local_player.damage = int(payload.damage)
			local_player.broadcast_network_build_snapshot()
		"edict_kill":
			next_action = local_player.combat_interactions.begin_action("attack")
			if bool(payload.get("inherited_ancestry", false)):
				# Registered descendant construction preserves both existing bits
				# before the host independently adds Edict's own bit on its kill.
				next_action = INTERACTIONS.damage_context(next_action, "apex_momentum_wave").interaction
				next_action = INTERACTIONS.damage_context(next_action, "storm_crown").interaction
			_deal(int(payload.enemy), "melee", next_action, float(local_player.damage))
		"edict_same_root":
			_deal(int(payload.enemy), "melee", next_action, float(local_player.damage))
		"inspect_edict":
			# Keep both observation waits below the command's outer deadline so
			# a failed receipt still returns diagnostics and both peer reports.
			var target := enemy(int(payload.enemy))
			var observed := await until(func(): return target.is_slowed(), 1.0)
			check(observed, "Owner receives host Edict Slow (enemy%d health=%s slow_time=%s)" % [int(payload.enemy), target.get_current_health(), target.slow_time_left])
			check(await until(func(): return (local_player as InteractionPlayer).kill_interactions.any(func(action: Dictionary) -> bool: return String(action.get("source", "")) == "edict_court"), 1.0), "Actual Edict kill callback reaches the joining owner")
		"inspect_edict_clear":
			check(await until(func(): return not enemy(402).is_slowed(), 1.0), "Owner observes Edict Slow expiry without another hit or movement")
		"forged_edict":
			var action := local_player.combat_interactions.begin_action("attack")
			# Bypass the owner's producer guard to probe the real server boundary.
			world.request_enemy_damage_from_client(414, 999, INTERACTIONS.damage_context(action, "edict_court", {"raw_amount": 999.0, "damage_coefficient": 9.0, "secondary": true}))
		"unknown_ancestry":
			for mask in [16, 128 | 7]:
				var action := local_player.combat_interactions.begin_action("attack")
				action.ancestry = mask
				world.request_enemy_damage_from_client(404, 1, INTERACTIONS.damage_context(action, "melee", {"raw_amount": 1.0, "damage_coefficient": 0.0}))
		"stationary_field_build":
			_replace_reward_build(["lacuna_echo", "null_corridor"])
		"lacuna_kill":
			next_action = local_player.combat_interactions.begin_action("attack")
			_deal(501, "melee", next_action)
		"lacuna_native_pulse":
			check(await until(func(): return not local_player.void_echo_zones.is_empty()), "Real remote kill callback starts the owner's existing Lacuna zone")
			local_player._update_void_echo_zones(0.01)
		"corridor_native_tick":
			next_action = local_player.combat_interactions.begin_action("dash")
			var previous := DAMAGE.begin_interaction_scope(next_action)
			local_player._apply_null_corridor_segment(Vector2(800, -800), Vector2(1050, -800))
			DAMAGE.end_interaction_scope(previous)
			local_player._update_null_corridor_segments(0.01)
		"inspect_stationary_status":
			check(await until(func(): return is_equal_approx(float(DAMAGE.status_snapshot(enemy(601), joiner_id).mark_ratio), 0.1) and enemy(502).is_slowed(), 1.0), "Owner observes the authoritative Corridor Mark and Lacuna Slow")
		"recreate_status_observer":
			var previous: Node = DAMAGE._target_status(enemy(601))
			if is_instance_valid(previous):
				previous.free()
			check(float(DAMAGE.status_snapshot(enemy(601), joiner_id).mark_ratio) == 0.0, "A fresh local status observer has no remembered Corridor Mark")
		"forged_corridor_mark":
			world.request_enemy_mark_from_client(602, "null_corridor", 0.99, 10.0, next_action)
		"cancel_stationary_fields":
			var retired := next_action.duplicate(true)
			local_player.clear_lingering_combat_effects()
			check(local_player.void_echo_zones.is_empty() and local_player.null_corridor_segments.is_empty(), "Actual lifecycle cleanup removes both old owner Fields")
			_deal(601, "null_corridor_deflect", retired, 9.0, 0.24)
		"invalid_packets":
			saved_action = local_player.combat_interactions.begin_action("attack")
			for key in ["owner", "run", "room", "seq"]:
				var forged := saved_action.duplicate(true)
				forged[key] = {"owner": 1, "run": "retired-keyword-run", "room": 999, "seq": "malformed"}[key]
				_deal(102, "static_wake", forged)
			var forged_state := {"run": INTERACTIONS.current_run(), "room": INTERACTIONS.current_room(), "epoch": local_player.combat_interactions._epoch, "serial": 99999, "highest": 999, "projectiles": [[999, -1100.0, 0.0, 1.0, 0.0, 400.0]]}
			for id in [1, joiner_id]:
				PlayerReplicationService._sync_spark_relay_state_reliable.rpc_id(1, id, forged_state)
		"cancel_stale":
			local_player._cancel_interactions()
			_deal(102, "static_wake", saved_action)
		"finish":
			report(name)
			await create_timer(0.1).timeout
			await finish()
			return
	report(name)

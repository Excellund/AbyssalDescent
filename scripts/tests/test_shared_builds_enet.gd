extends "res://scripts/tests/test_combat_interactions_enet.gd"
## Native authenticated World/player transports with actual mapped Player hooks.
const LOBBY := preload("res://scripts/lobby_controller.gd")

class FixtureLobby extends "res://scripts/lobby_controller.gd":
	var launches: int = 0
	func _ready() -> void:
		set_process(false)
		multiplayer_session_manager = get_node("/root/MultiplayerSessionManager")
		local_peer_id = multiplayer.get_unique_id()
		local_character_id = "bastion"
		_ensure_local_peer_state()
	func _notification(_what: int) -> void:
		pass
	func _update_player_list() -> void:
		pass
	func _apply_difficulty_selection(value: int) -> void:
		selected_difficulty_tier = value
	func _apply_ascension_loadout(value: Array) -> void:
		selected_ascension_loadout.assign(value)
	func _launch_main_game() -> void:
		launches += 1

class ClearWithoutReward extends "res://scripts/core/room_clear_outcome_coordinator.gd":
	# Keep the real World clear/phase/status/replication boundary; this fixture
	# stops before reward UI and routing, so no build snapshot repairs expiry.
	func resolve_outcome(_flow: Node, _boss: bool, _reward: int, _cleared: int, _depth: int, _encounters: int) -> Dictionary:
		return {}

class Shield extends "res://scripts/enemy_shielder.gd":
	func _ready() -> void:
		max_health = 10000
		_create_health_state()
		add_to_group("enemies")
		set_physics_process(false)

var lobby: FixtureLobby
var stale_status: PackedByteArray
var received_room_clears: int = 0

func setup_actors(client_id: int) -> void:
	super.setup_actors(client_id)
	for actor in [local_player, remote_player]:
		actor.reward_storm_crown = false
		actor.apply_trial_power("dread_resonance")
		actor.apply_trial_power("wraithstep")
		actor.apply_upgrade("battle_trance")
		actor.damage = 100
		actor.shared_build_runtime.set_physics_process(false)
		actor.position = Vector2.ZERO
	var shield := Shield.new()
	shield.name = "Enemy_111"
	world.add_child(shield)
	shield.position = Vector2(1000, 0)
	shield.shield_facing = Vector2.LEFT
	world.enemy_state_sync_broadcaster.register_enemy(shield, 111)
	var mission_target := Enemy.new()
	mission_target.name = "Enemy_114"
	world.add_child(mission_target)
	mission_target.position = Vector2(1300, 0)
	mission_target.health_state.setup(10000, 10000)
	world.enemy_state_sync_broadcaster.register_enemy(mission_target, 114)
	for id in range(116, 120):
		var isolated := Enemy.new()
		isolated.name = "Enemy_%d" % id
		world.add_child(isolated)
		isolated.position = Vector2(60.0 + float(id - 116) * 30.0, 500.0) if id < 118 else Vector2(500.0 + float(id - 118) * 400.0, 500.0)
		isolated.health_state.setup(10000, 10000)
		world.enemy_state_sync_broadcaster.register_enemy(isolated, id)
	world.active_room_enemy_count = 16
	var lobby_node: Control = load("res://scenes/Lobby.tscn").instantiate()
	lobby_node.set_script(FixtureLobby)
	lobby = lobby_node as FixtureLobby
	lobby.name = "ProtocolLobby"
	world.add_child(lobby)
	lobby.hide()
	lobby._ensure_remote_peer_state(1 if role == "client" else client_id)
	world.game_state_replication_service = GameStateReplicationService
	GameStateReplicationService.room_cleared.connect(world._on_room_cleared_synced)
	GameStateReplicationService.room_cleared.connect(func(): received_room_clears += 1)

func report(key: String) -> void:
	world.fixture_result.rpc_id(1, key, {
		"mark": DAMAGE.status_snapshot(target_node(101), joiner_id),
		"far_mark": DAMAGE.status_snapshot(target_node(109), joiner_id),
		"slow": target_node(102).is_slowed(),
		"trance": local_player.battle_trance_active_left,
		"warden": local_player.apex_predator_combo_hits,
		"host_warden": remote_player.apex_predator_combo_hits,
		"damage_events": world.damage_events.size(),
		"protocol": lobby.peer_state.duplicate(true),
		"cooldown": local_player.dash_cooldown_left,
		"refund": local_player._shared_dash_refund_total,
		"epoch": local_player.combat_interactions._epoch,
		"scope": DAMAGE.current_interaction_context(),
		"combo_relay": local_player.combo_relay_stacks,
		"farline": local_player._farline_volley_current_stacks,
		"sigil_ready": local_player.sigil_burst_ready,
		"oath_bank": local_player.indomitable_damage_bank,
		"oath_primed": local_player._indomitable_spirit_primed,
		"action": next_action.duplicate(true),
		"contact": local_player.arcana_motion.last_contact_position,
		"mission_remaining": mission_remaining(local_player),
		"mission_damage_mult": local_player.objective_mutator_damage_mult,
		"room_clears": received_room_clears,
		"target_status": DAMAGE.get_status_network_state(target_node(119))})

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	begin_run()
	await command("begin")
	check(await until(received), "Shared builds use the real common run-token handshake")
	await command("protocol_missing")
	check(not LOBBY._peer_protocol_matches(lobby.peer_state, client_id), "Missing protocol request is recorded against the authenticated joiner")
	check(not lobby._explicit_ready_peers.has(client_id), "Old client cannot set Ready through the real request RPC")
	await command("protocol_mismatch")
	check(not lobby._explicit_ready_peers.has(client_id), "Explicit incompatible client cannot set Ready")
	await command("protocol_match")
	check(LOBBY._roster_protocol_matches(lobby.peer_state, [1, client_id]), "Matching protocol announcement repairs earlier missing evidence")
	lobby.peer_state[1].is_ready = true
	lobby._explicit_ready_peers[1] = true
	await command("protocol_ready")
	check(lobby.launches == 1, "Actual all-ready boundary permits compatible peers exactly once")

	await command("mark")
	check(is_equal_approx(float(DAMAGE.status_snapshot(target_node(101), client_id).mark_ratio), 0.15), "World Mark request uses host mapped strength, not submitted claims")
	stale_status = DAMAGE.get_status_network_packet(target_node(101))
	world.enemy_state_sync_broadcaster.tick(0.25)
	world.enemy_state_sync_broadcaster.tick(0.25)
	await command("inspect_mark")
	check(is_equal_approx(float(results.inspect_mark.mark.mark_ratio), 0.15), "Actual broadcaster/World RPC/receiver preserves a 15% Mark")
	check(float(results.inspect_mark.far_mark.mark_ratio) > 0.0, "Far enemy status remains eligible through normal distance throttling")
	check(results.inspect_mark.damage_events == 0, "Client Mark and replica updates never simulate authoritative damage")
	await command("attack")
	check(target_node(101).get_current_health() == 9885, "First attack benefits from earlier Dash Mark, not its newly applied Dread stack")
	check(int(DAMAGE.status_snapshot(target_node(101), client_id).dread_stacks) == 1, "Host-confirmed attack installs the owning joiner's Dread stack")
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_trance")
	check(results.inspect_trance.trance > 0.0, "Host accepted damage refreshes the actual owning joiner's Battle Trance")
	await command("same_attack")
	check(int(DAMAGE.status_snapshot(target_node(101), client_id).dread_stacks) == 1, "Melee and Razor Wind share one stack allowance per Attack/foe")
	await command("next_attack")
	check(int(DAMAGE.status_snapshot(target_node(101), client_id).dread_stacks) == 2, "A later deliberate attack may add the next target stack")
	var host_action: Dictionary = local_player.combat_interactions.begin_action("attack")
	DAMAGE.apply_damage(target_node(101), 10, INTERACTIONS.damage_context(host_action, "melee", {"raw_amount": 10.0, "damage_coefficient": 0.1}), 1)
	check(int(DAMAGE.status_snapshot(target_node(101), 1).dread_stacks) == 1 and int(DAMAGE.status_snapshot(target_node(101), client_id).dread_stacks) == 2, "Two peers share the Mark window while retaining independent Dread stacks")
	world.enemy_state_sync_broadcaster.tick(0.25)
	await command("inspect_dread")
	check(results.inspect_dread.mark.dread_stacks == 2, "Native status snapshot carries the owner's exact stack count")

	remote_player.first_strike_bonus_damage = 16
	await command("wake")
	check(target_node(102).get_current_health() == 9948, "Two fractional Wake packets get coefficient-scaled First Strike and only the pre-Slow second-tick Snare bonus")
	check(int(DAMAGE.status_snapshot(target_node(102), client_id).dread_stacks) == 0, "Generated Field damage cannot add Attack-only Dread stacks")
	remote_player.first_strike_bonus_damage = 0
	var shield := target_node(111) as Shield
	shield.damage_blocked = true
	await command("blocked")
	check(shield.get_current_health() == 10000 and int(DAMAGE.status_snapshot(shield, client_id).dread_stacks) == 0, "Fully blocked native attack cannot spend resources or add Dread")
	shield.damage_blocked = false
	await command("shield_front")
	check(shield.get_current_health() == 10000 - int(100.0 * (1.0 - shield.shield_damage_reduction)), "Finite remote attack origin preserves the Shielder's 80% frontal reduction")
	check(int(DAMAGE.status_snapshot(shield, client_id).dread_stacks) == 1, "A positive reduced hit still counts as one accepted Attack")

	remote_player.apex_predator_bonus_damage = 17
	await command("echo")
	check(target_node(103).get_current_health() == 9894 and target_node(104).get_current_health() == 9942, "Immediate client Echo copies host-prepared raw Warden bonus at 55%, without waiting for owner acknowledgement")
	check(remote_player.apex_predator_combo_hits == 1 and int(DAMAGE.status_snapshot(target_node(104), client_id).dread_stacks) == 0, "Echo neither spends the Warden counter again nor generates an Attack-only stack")
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_warden")
	check(results.inspect_warden.warden == 1 and results.inspect_warden.host_warden == 0, "Packed host-generated state reaches its actual owner without changing the host player's counters")
	remote_player.apex_predator_bonus_damage = 0
	remote_player.apply_trial_power("rupture_wave")
	var count_before := world.damage_events.size()
	await command("rupture")
	var descendants := world.damage_events.slice(count_before)
	check(descendants.size() >= 2 and descendants.all(func(entry: Dictionary) -> bool: return int(entry.peer) == client_id), "Host-generated native Rupture descendants preserve the authenticated joiner damage owner")
	check(DAMAGE.current_interaction_context().is_empty(), "Confirmed callbacks leave no inherited global action scope")

	await command("refund_prepare")
	remote_player._refund_shared_dash(0.25)
	remote_player.shared_build_runtime.publish_state()
	remote_player.shared_build_runtime.publish_state()
	var pending: Array = PlayerReplicationService._pending_cue_events_by_peer.get(client_id, [])
	check(pending.filter(func(entry: Dictionary) -> bool: return entry.event == "shared_build_state").size() == 1, "Cumulative owner state coalesces without flooding one event per descendant")
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_refund")
	check(is_equal_approx(float(results.inspect_refund.cooldown), 0.75), "Owner receives one explicit refund without importing the host replica's stale cooldown")
	remote_player.shared_build_runtime.publish_state()
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_refund_again")
	check(is_equal_approx(float(results.inspect_refund_again.cooldown), 0.75), "A newer cumulative state cannot apply the same refund twice")
	await command("forge_state")
	check(remote_player.apex_predator_combo_hits != 9999, "Joiner cannot forge a host-confirmed shared-build state cue")
	DAMAGE.cancel_owner(client_id)
	world.enemy_state_sync_broadcaster.tick(0.25)
	world._sync_enemy_states.rpc([{"enemy_id": 101, "runtime_state_delta": {"shared_status": stale_status}}], 11)
	await command("inspect_clear")
	check(results.inspect_clear.mark.dread_stacks == 0, "Authoritative owner clear removes Dread and late older snapshots cannot resurrect it")
	check(float(results.inspect_clear.mark.mark_ratio) > 0.0, "Clearing joiner status preserves the host's independently applied Mark")
	var damage_before: int = target_node(110).get_current_health()
	await command("cancel_stale")
	check(target_node(110).get_current_health() == damage_before and DAMAGE.status_snapshot(target_node(110), client_id).mark_ratio == 0.0, "Retired epoch cannot apply either shared damage or a new Mark")
	check(results.cancel_stale.scope.is_empty(), "Client inherited scope also retires after native requests")
	PlayerReplicationService.broadcast_cue_event(client_id, "shared_build_state", {"run": INTERACTIONS.current_run(), "room": INTERACTIONS.current_room(), "serial": 999999, "epoch": int(results.cancel_stale.epoch) - 1, "state": {"apex_predator_combo_hits": 9999}}, true)
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_stale_state")
	check(results.inspect_stale_state.warden != 9999, "Even a later host packet cannot restore retired-epoch owner counters")
	await command("forged_root")
	check(target_node(110).get_current_health() == damage_before and DAMAGE.status_snapshot(target_node(110), client_id).mark_ratio == 0.0, "Authenticated sender identity rejects another owner's shared damage and Mark metadata")
	remote_player.active_objective_mutators = [{"id": "combo_relay"}]
	target_node(105).health_state.current_health = 1
	await command("mission_kill")
	check(remote_player.combo_relay_stacks == 1 and local_player.combo_relay_stacks == 0, "Actual credited joiner kill updates exactly its host-side Combo Relay counter")
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_mission")
	check(results.inspect_mission.combo_relay == 1, "Owner kill callback and cumulative acknowledgement do not double a Mission stack")
	await command("mission_damage")
	check(target_node(114).get_current_health() == 9895, "Next owned Field damage receives the authoritative 5% Combo Relay stack exactly once")
	remote_player._update_combo_relay_state(3.0)
	remote_player.shared_build_runtime.publish_state()
	PlayerReplicationService._flush_pending_cue_events()
	await command("mission_damage_after_expiry")
	check(remote_player.combo_relay_stacks == 0 and target_node(114).get_current_health() == 9795, "Expired host Mission stack no longer modifies subsequent shared damage")
	await test_native_action_boundaries(client_id)
	await test_mission_room_expiry(client_id)
	await test_input_status_lifecycle(client_id)
	await command("finish")
	await finish()

func client_command(name: String, payload: Dictionary) -> void:
	match name:
		"begin":
			begin_run()
			check(await until(func(): return not INTERACTIONS.current_run().is_empty()), "Actual host run identity arrives")
		"protocol_missing":
			lobby._request_lobby_roster.rpc_id(1)
			lobby._request_ready_state.rpc_id(1, true)
		"protocol_mismatch":
			lobby._request_lobby_roster.rpc_id(1, LOBBY.COMBAT_PROTOCOL_VERSION + 1)
			lobby._request_ready_state.rpc_id(1, true)
		"protocol_match":
			lobby._request_lobby_roster.rpc_id(1, LOBBY.COMBAT_PROTOCOL_VERSION)
		"protocol_ready":
			lobby._request_ready_state.rpc_id(1, true)
		"mark":
			saved_action = local_player.combat_interactions.begin_action("dash")
			DAMAGE.apply_mark(target_node(101), "wraithstep", 0.99, 29.0, joiner_id, saved_action)
			DAMAGE.apply_mark(target_node(109), "wraithstep", 0.99, 29.0, joiner_id, saved_action)
			check(DAMAGE.status_snapshot(target_node(101), joiner_id).mark_ratio == 0.0, "Requesting Mark never changes the joiner replica before host acknowledgement")
		"inspect_mark":
			check(await until(func(): return DAMAGE.status_snapshot(target_node(101), joiner_id).mark_ratio > 0.0 and DAMAGE.status_snapshot(target_node(109), joiner_id).mark_ratio > 0.0), "Shared status arrives through production enemy snapshot transport")
		"attack":
			next_action = local_player.combat_interactions.begin_action("attack")
			deal(101, 100.0, 1.0, "melee", next_action)
		"same_attack":
			deal(101, 10.0, 0.1, "razor_wind", next_action)
		"next_attack":
			deal(101, 100.0, 1.0)
		"inspect_trance":
			check(await until(func(): return local_player.battle_trance_active_left > 0.0), "Host-only shared state is forwarded to apply_owner_cue_event")
		"inspect_dread":
			check(await until(func(): return DAMAGE.status_snapshot(target_node(101), joiner_id).dread_stacks == 2), "Authoritative Dread mirror is exact")
		"wake":
			local_player.first_strike_bonus_damage = 16
			var action: Dictionary = local_player.combat_interactions.begin_action("dash")
			deal(102, 20.0, 0.2, "static_wake", action)
			DAMAGE.apply_slow(target_node(102), 3.0, 0.5, joiner_id, action)
			deal(102, 20.0, 0.2, "static_wake", action)
			local_player.first_strike_bonus_damage = 0
		"blocked", "shield_front":
			deal(111, 100.0, 1.0)
		"echo":
			local_player.apex_predator_bonus_damage = 17
			var action: Dictionary = local_player.combat_interactions.begin_action("attack")
			deal(103, 100.0, 1.0, "melee", action)
			var original: Dictionary = INTERACTIONS.damage_context(action, "melee").interaction
			deal(104, 55.0, 0.55, "sovereigns_double", original)
		"inspect_warden":
			check(await until(func(): return local_player.apex_predator_combo_hits == 1), "Warden resource acknowledgement reaches the joining owner")
		"rupture":
			local_player.apex_predator_bonus_damage = 0
			local_player.apply_trial_power("rupture_wave")
			deal(107, 100.0, 1.0)
		"refund_prepare":
			local_player.dash_cooldown_left = 1.0
		"forge_state":
			var fake := {"run": INTERACTIONS.current_run(), "room": INTERACTIONS.current_room(), "serial": 99999, "epoch": local_player.combat_interactions._epoch, "state": {"apex_predator_combo_hits": 9999}}
			var entry := {"event": "shared_build_state", "payload": PlayerReplicationService._pack_shared_build_state(fake)}
			var entries: Array[Dictionary] = [entry]
			PlayerReplicationService._sync_player_cue_events_reliable.rpc_id(1, joiner_id, entries)
		"inspect_clear":
			check(await until(func(): return DAMAGE.status_snapshot(target_node(101), joiner_id).dread_stacks == 0), "Ordered clear arrives and retains no stale owner stack")
		"cancel_stale":
			local_player.combat_interactions.cancel()
			DAMAGE.apply_mark(target_node(110), "wraithstep", 0.15, 2.5, joiner_id, saved_action)
			deal(110, 20.0, 0.2, "static_wake", saved_action)
		"forged_root":
			var forged: Dictionary = local_player.combat_interactions.begin_action("attack")
			forged.owner = 1
			DAMAGE.apply_mark(target_node(110), "wraithstep", 0.15, 2.5, joiner_id, forged)
			deal(110, 20.0, 0.2, "melee", forged)
		"mission_kill":
			local_player.active_objective_mutators = [{"id": "combo_relay"}]
			deal(105, 10.0, 0.1, "returning_crescent")
		"inspect_mission":
			check(await until(func(): return local_player.combo_relay_stacks == 1), "Credited kill and host Mission state reach the joiner")
		"mission_damage", "mission_damage_after_expiry":
			deal(114, 100.0, 1.0, "static_wake")
		"status_prepare":
			configure_action_fixture(local_player)
			local_player.reward_wraithstep = true
			local_player.reward_dread_resonance = true
			local_player.set_combat_damage_enabled(true)
			next_action = local_player.combat_interactions.begin_action("melee")
			deal(119, 100.0, 1.0, "melee", next_action)
			DAMAGE.apply_mark(target_node(119), "wraithstep", 0.15, 2.5, joiner_id, next_action)
		"inspect_status":
			check(await until(func(): return int(DAMAGE.status_snapshot(target_node(119), joiner_id).dread_stacks) == 1), "Authoritative target status arrives before modal input test")
		"status_discard":
			local_player.discard_pending_combat_input()
		"status_stale":
			DAMAGE.apply_mark(target_node(119), "wraithstep", 0.15, 2.5, joiner_id, next_action)
			deal(119, 10.0, 0.1, "melee", next_action)
		"status_build":
			local_player.broadcast_network_build_snapshot()
		"status_fresh":
			next_action = local_player.combat_interactions.begin_action("melee")
			deal(119, 10.0, 0.1, "melee", next_action)
		"status_dead_kill":
			deal(118, 10.0, 0.1, "returning_crescent", next_action)
		"mission_duration_prepare":
			configure_action_fixture(local_player)
			local_player.apply_objective_mutator(payload.mutator)
		"mission_duration_damage":
			deal(114, 100.0, 1.0, "static_wake")
		"mission_duration_clear":
			check(await until(func(): return received_room_clears == int(payload.clears)), "Real room-cleared signal arrives before inspecting Mission expiry")
		"dash_start":
			configure_action_fixture(local_player)
			local_player.reward_farline_volley = true
			local_player.farline_volley_stacks = 2
			local_player._farline_volley_current_stacks = 3
			local_player.passive_sigil_burst = true
			local_player.dash_cooldown_left = 0.0
			Input.action_press("dash")
			local_player._try_start_dash(Vector2.RIGHT)
			Input.action_release("dash")
			check(local_player.dash_time_left > 0.0, "Real native dash input starts before immediate cancellation")
			next_action = local_player._dash_interaction.duplicate(true)
			local_player.discard_pending_combat_input()
			local_player.dash_time_left = 0.0
			local_player.dash_remaining_distance = 0.0
			local_player._set_dash_phasing(false)
		"dash_stale":
			world.request_shared_dash_start_from_client(next_action)
		"dash_state":
			deal(119, 10.0, 0.1, "returning_crescent")
		"sigil_attack":
			local_player._perform_melee_attack(Vector2.RIGHT, {"damage": 100, "range": 120.0, "arc_degrees": 50.0, "source": "melee"})
			next_action = last_attack_action(local_player)
		"sigil_delayed":
			next_action = local_player.combat_interactions.begin_action("attack")
			deal(119, 1.0, 0.01, "returning_crescent", next_action)
		"oath_miss", "oath_attack":
			configure_action_fixture(local_player)
			prime_oath(local_player)
			local_player.first_strike_bonus_damage = 16
			local_player._perform_melee_attack(Vector2.DOWN if name == "oath_miss" else Vector2.RIGHT, {"damage": 100, "range": 120.0, "arc_degrees": 50.0, "source": "melee"})
			next_action = last_attack_action(local_player)
		"oath_replay":
			world.request_shared_attack_start_from_client(next_action)
		"oath_echo":
			deal(118, 55.0, 0.55, "sovereigns_double", next_action)
		"predict_contact":
			local_player.arcana_motion.motion = local_player.arcana_motion.Motion.RECOIL
			local_player.arcana_motion.last_contact_position = Vector2.INF
			var action: Dictionary = local_player.combat_interactions.begin_action("melee")
			var previous: Dictionary = DAMAGE.begin_interaction_scope(action)
			local_player._resolve_attack_hit(target_node(119), target_node(119).global_position, 1, "melee", {}, {}, {}, {}, 1.0, Vector2.INF, action, 0.01)
			DAMAGE.end_interaction_scope(previous)
			check(local_player.arcana_motion.last_contact_position == local_player.global_position, "Routed primary contact immediately records actual recoil position for Double placement")
			local_player.arcana_motion.motion = local_player.arcana_motion.Motion.NONE
		"finish":
			report(name)
			await create_timer(0.1).timeout
			await finish()
			return
	report(name)

func deal(id: int, raw: float, coefficient: float, source: String = "melee", action: Dictionary = {}) -> void:
	if action.is_empty():
		action = local_player.combat_interactions.begin_action("attack")
	DAMAGE.apply_damage(target_node(id), int(raw), INTERACTIONS.damage_context(action, source, {"raw_amount": raw, "damage_coefficient": coefficient, "attack_origin": target_node(id).global_position + Vector2.LEFT * 100.0, "secondary": source == "sovereigns_double"}))

func target_node(id: int) -> Node2D:
	return EnemyReplicationService.enemy_nodes_by_id.get(id) as Node2D

func configure_action_fixture(actor: Player) -> void:
	actor.position = Vector2(0.0, 500.0)
	actor.reward_dread_resonance = false
	actor.reward_wraithstep = false
	actor.reward_hunters_snare = false
	actor.reward_rupture_wave = false
	actor.reward_sigil_chain = false
	actor.reward_farline_volley = false
	actor.reward_storm_crown = false
	actor.passive_sigil_burst = false
	actor.passive_iron_retort = false
	actor.passive_farline_focus = false
	actor.active_objective_mutators.clear()
	actor.combo_relay_stacks = 0
	actor.first_strike_bonus_damage = 0
	actor.apex_predator_bonus_damage = 0
	actor.indomitable_spirit_damage_reduction = 0.0
	actor.indomitable_damage_bank = 0.0
	actor._indomitable_spirit_primed = false

func prime_oath(actor: Player) -> void:
	actor.indomitable_spirit_damage_reduction = 0.2
	actor.indomitable_damage_bank = actor._get_indomitable_fill_requirement()
	actor._indomitable_spirit_primed = true

func last_attack_action(actor: Player) -> Dictionary:
	var action := {"run": INTERACTIONS.current_run(), "room": INTERACTIONS.current_room(), "owner": actor.player_id, "seq": actor.combat_interactions._next_sequence, "epoch": actor.combat_interactions._epoch, "kind": "melee", "ancestry": 0}
	return INTERACTIONS.damage_context(action, "melee").interaction

func test_native_action_boundaries(client_id: int) -> void:
	configure_action_fixture(remote_player)
	remote_player.reward_farline_volley = true
	remote_player.farline_volley_stacks = 2
	remote_player._farline_volley_current_stacks = 3
	remote_player.passive_sigil_burst = true
	await command("dash_start")
	check(remote_player._farline_volley_current_stacks == 0, "Successful joining-owner dash resets the host Farline bank even if movement is canceled")
	check(remote_player.sigil_burst_ready, "The same authenticated dash arms Arcanist's host-side passive")
	remote_player._farline_volley_current_stacks = 2
	await command("dash_stale")
	check(remote_player._farline_volley_current_stacks == 2, "Retired dash start cannot consume later host resources")
	remote_player._farline_volley_current_stacks = 0
	await command("dash_state")
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_dash_state")
	check(results.inspect_dash_state.farline == 0 and results.inspect_dash_state.sigil_ready, "Later authoritative owner state preserves spent Farline and the newly armed passive")
	remote_player.reward_farline_volley = false
	var first_health: int = target_node(116).get_current_health()
	var second_health: int = target_node(117).get_current_health()
	await command("sigil_attack")
	check(first_health - target_node(116).get_current_health() == 170 and second_health - target_node(117).get_current_health() == 170, "One native two-target attack releases Arcanist's 70% Burst only once")
	check(not remote_player.sigil_burst_ready, "Accepted passive burst consumes the host readiness flag")
	PlayerReplicationService._flush_pending_cue_events()
	await command("inspect_sigil_consumed")
	check(not results.inspect_sigil_consumed.sigil_ready, "Consumed Arcanist readiness is mirrored to its actual owner")
	remote_player.passive_sigil_burst = false
	remote_player.apply_trial_power("sigil_chain")
	remote_player.apply_trial_power("sigil_chain")
	await command("sigil_delayed")
	var original: Dictionary = results.sigil_delayed.action
	var previous: Dictionary = DAMAGE.begin_interaction_scope(original)
	remote_player._drop_sigil_chain_zone(target_node(119).global_position)
	DAMAGE.end_interaction_scope(previous)
	check(not remote_player._sigil_chain_zones.is_empty(), "Host-confirmed owner creates a real saved-context Sigil zone")
	var count_before: int = world.damage_events.size()
	remote_player._apply_sigil_chain_zone_tick(remote_player._sigil_chain_zones.back())
	check(target_node(119).is_slowed() and DAMAGE.current_interaction_context().is_empty(), "Delayed Sigil Level 2 tick applies Slow outside the originating callback scope")
	check(world.damage_events.size() > count_before and int(world.damage_events.back().peer) == client_id, "Delayed Sigil keeps the originating joiner damage attribution")
	remote_player._sigil_chain_zones.clear()
	configure_action_fixture(remote_player)
	prime_oath(remote_player)
	remote_player.first_strike_bonus_damage = 16
	await command("oath_miss")
	check(remote_player.indomitable_damage_bank == 0.0 and not remote_player._indomitable_spirit_primed, "Actual native missed Attack spends the joining owner's primed bank on host")
	prime_oath(remote_player)
	await command("oath_replay")
	check(remote_player._indomitable_spirit_primed, "Duplicate old Attack start cannot consume a newly primed host bank")
	var ratio: float = remote_player._get_indomitable_retaliation_ratio()
	first_health = target_node(116).get_current_health()
	second_health = target_node(117).get_current_health()
	await command("oath_attack")
	var loss_one: int = first_health - target_node(116).get_current_health()
	var loss_two: int = second_health - target_node(117).get_current_health()
	var empowered := int(round(100.0 + round(100.0 * ratio) + 16.0 * (1.0 + ratio)))
	check([loss_one, loss_two].has(empowered) and loss_one + loss_two == empowered + 116, "Two-target native Attack spends Oath bonus once and carries its exact conditional Damage coefficient")
	check(remote_player.indomitable_damage_bank == 0.0 and not remote_player._indomitable_spirit_primed, "Hits from a spent Oath root cannot immediately recharge its bank")
	var echo_health: int = target_node(118).get_current_health()
	await command("oath_echo")
	check(echo_health - target_node(118).get_current_health() == int(round((100.0 + round(100.0 * ratio)) * 0.55 + 16.0 * (1.0 + ratio) * 0.55)), "Immediate Echo inherits the host accepted Oath coefficient at 55% without copying target conditions")
	check(remote_player.indomitable_damage_bank == 0.0, "Oath Echo cannot refill the Attack-only bank")
	await command("predict_contact")
	check(results.predict_contact.contact == Vector2(0.0, 500.0), "Host-routed contact prediction preserves joining-owner recoil contact feedback")

func mission_remaining(actor: Player) -> int:
	var mutators := actor.get_active_objective_mutators()
	return 0 if mutators.is_empty() else int(mutators[0].get("remaining_encounters", -1))

func test_mission_room_expiry(_client_id: int) -> void:
	configure_action_fixture(local_player)
	configure_action_fixture(remote_player)
	var builder := preload("res://scripts/encounter_profile_builder.gd").new()
	var mutator: Dictionary = builder._build_hunters_focus_mutator()
	builder.free()
	local_player.apply_objective_mutator(mutator)
	remote_player.apply_objective_mutator(mutator)
	await command("mission_duration_prepare", {"mutator": mutator})
	check(mission_remaining(local_player) == 3 and mission_remaining(remote_player) == 3 and results.mission_duration_prepare.mission_remaining == 3, "Actual Hunter's Focus starts with three encounters on host and owner")
	var flow := Node.new()
	world.add_child(flow)
	world.encounter_flow_system = flow
	world.combat_phase_coordinator = preload("res://scripts/core/combat_phase_coordinator.gd").new()
	world.room_clear_outcome_coordinator = ClearWithoutReward.new()
	for clear_index in range(3):
		var before: int = target_node(114).get_current_health()
		await command("mission_duration_damage")
		check(before - target_node(114).get_current_health() == 125, "Unexpired joining-owner Mission modifies actual Field damage by25% exactly once")
		# The last iteration is an already-unlocked boss room; duration handling
		# executes before all ordinary and boss-specific clear outcomes.
		world.in_boss_room = clear_index == 2
		world.first_boss_defeated = true
		world.room_depth = 20 + clear_index
		world.rooms_cleared = 19 + clear_index
		world._on_room_cleared()
		await command("mission_duration_clear", {"clears": clear_index + 1})
		var expected := 2 - clear_index
		check(mission_remaining(local_player) == expected and mission_remaining(remote_player) == expected, "Actual authoritative World clear ticks each registered host copy exactly once")
		check(int(results.mission_duration_clear.mission_remaining) == expected, "Native call-remote room clear ticks the local joining owner exactly once")
	var after_expiry: int = target_node(114).get_current_health()
	await command("mission_duration_damage")
	check(after_expiry - target_node(114).get_current_health() == 100 and remote_player.objective_mutator_damage_mult == 0.0, "Third clear expires host Mission Field bonus without any owner build snapshot or reward claim")
	check(local_player.objective_mutator_damage_mult == 0.0 and results.mission_duration_clear.mission_damage_mult == 0.0, "Both local and joining-owner displayed Mission totals expire at the same clear")
	world.in_boss_room = false

func test_input_status_lifecycle(client_id: int) -> void:
	configure_action_fixture(remote_player)
	remote_player.reward_wraithstep = true
	remote_player.reward_dread_resonance = true
	remote_player.set_combat_damage_enabled(true)
	local_player.reward_wraithstep = true
	local_player.set_combat_damage_enabled(true)
	await command("status_prepare")
	var other_action: Dictionary = local_player.combat_interactions.begin_action("dash")
	DAMAGE.apply_mark(target_node(119), "wraithstep", 0.15, 2.5, 1, other_action)
	var state: Node = DAMAGE._target_status(target_node(119))
	check(int(state.snapshot(client_id).dread_stacks) == 1 and state.marks.has("%d:wraithstep" % client_id), "Prepared owner Mark and Dread exist before input cancellation")
	world.enemy_state_sync_broadcaster.tick(0.25)
	world.enemy_state_sync_broadcaster.tick(0.25)
	await command("inspect_status")
	check((results.inspect_status.target_status.get("d", []) as Array).any(func(entry: Array) -> bool: return int(entry[0]) == client_id and int(entry[1]) == 1), "Owner sees real authoritative status snapshot before opening a modal")
	var prior_epoch: int = remote_player.combat_interactions._accepted_epoch
	await command("status_discard")
	check(remote_player.combat_interactions._accepted_epoch == prior_epoch + 1, "Actual owner input discard announces a new authenticated epoch")
	check(int(state.snapshot(client_id).dread_stacks) == 1 and state.marks.has("%d:wraithstep" % client_id), "Host retains established Mark and Dread across input-only epoch cancellation")
	check((results.status_discard.target_status.get("d", []) as Array).any(func(entry: Array) -> bool: return int(entry[0]) == client_id and int(entry[1]) == 1), "Owning replica also retains its displayed Dread after input discard")
	var health_before: int = target_node(119).get_current_health()
	var duration_before: float = state.marks["%d:wraithstep" % client_id].left
	await command("status_stale")
	check(target_node(119).get_current_health() == health_before and is_equal_approx(float(state.marks["%d:wraithstep" % client_id].left), duration_before), "Retired action cannot deal damage or refresh the preserved Mark window")
	await command("status_build")
	check(int(state.snapshot(client_id).dread_stacks) == 1 and state.marks.has("%d:wraithstep" % client_id) and state.marks.has("1:wraithstep"), "Actual network build snapshot preserves both owners' established target status")
	await command("status_fresh")
	check(int(state.snapshot(client_id).dread_stacks) == 2, "A new accepted action can continue Dread after modal cancellation and build sync")
	# Host learns death before the owning client's cancellation reply. Preserve
	# pre-existing in-flight damage credit but prevent any status/reaction rearm.
	remote_player.set_alive(false)
	remote_player.battle_trance_active_left = 0.0
	check(int(state.snapshot(client_id).dread_stacks) == 0 and not state.marks.has("%d:wraithstep" % client_id) and state.marks.has("1:wraithstep"), "Host death immediately removes only the fallen owner's Mark and Dread")
	var dead_epoch: int = remote_player.combat_interactions._accepted_epoch
	await command("status_stale")
	check(remote_player.combat_interactions._accepted_epoch == dead_epoch and not state.marks.has("%d:wraithstep" % client_id), "Late native Mark request cannot rearm dead-owner status before epoch acknowledgement")
	check(int(state.snapshot(client_id).dread_stacks) == 0 and remote_player.battle_trance_active_left == 0.0, "Late accepted damage cannot rearm Dread or Battle Trance for a dead owner")
	var recent_action: Dictionary = results.status_fresh.action
	var tagged: Dictionary = INTERACTIONS.damage_context(recent_action, "melee").interaction
	DAMAGE.add_dread_stack(target_node(117), client_id, 8, tagged)
	check(int(DAMAGE.status_snapshot(target_node(117), client_id).dread_stacks) == 0, "Direct shared stack boundary also rejects an explicitly dead owner")
	target_node(118).health_state.current_health = 1
	var kills_before: int = world.kill_peers.size()
	await command("status_dead_kill")
	check(world.kill_peers.size() == kills_before + 1 and int(world.kill_peers.back()) == client_id, "Existing in-flight posthumous kill retains its original joining-owner credit")

extends "res://scripts/tests/test_boss_combinations_enet.gd"
## Two-process authority and presentation tests for the original bosses' charges.
const MOTION := preload("res://scripts/arcana_motion_controller.gd")
var bosses: Array = []
var boss: Node2D
var boss_index: int = 0

class Warden extends "res://scripts/enemy_boss.gd":
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
class Lacuna extends "res://scripts/enemy_boss_3.gd":
	var seam_attempts: int = 0
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
	func _spawn_seam(position: Vector2,duration_mult: float=1.0,tick_interval_mult: float=1.0) -> void:
		seam_attempts += 1
		super._spawn_seam(position,duration_mult,tick_interval_mult)
class ChargePlayer extends Player:
	var damage_contexts: Array[Dictionary] = []
	func _ready() -> void:
		super._ready()
		damage_taken.connect(func(_raw: int,_final: int,context: Dictionary):damage_contexts.append(context.duplicate(true)))

func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1:{},client_id:{}}
	world.position = Vector2(40.0,-60.0)
	world.current_room_size = Vector2(1800.0,1100.0)
	world.current_effective_room_size = world.current_room_size
	for id in [1,client_id]:
		var actor := ChargePlayer.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		circle(actor,14.0)
		world.add_child(actor)
		actor.set_max_health_and_current(500,500)
		actor.arcana_motion.set_process(false)
		actor.returning_crescent.set_physics_process(false)
		actor.boss_combinations.set_process(false)
		PlayerReplicationService.register_player(id,actor)
		if id == get_multiplayer().get_unique_id():
			local_player = actor
			world.player = actor
		else:
			remote_player = actor
	for index in range(2):
		var enemy: Node2D = Warden.new() if index==0 else Lacuna.new()
		enemy.name = "ChargeBoss%d" % index
		circle(enemy,34.0 if index==0 else 40.0)
		world.add_child(enemy)
		enemy.position = Vector2(-750.0,350.0)
		enemy.target = local_player
		enemy.target_candidates = [local_player, local_player, remote_player]
		world.enemy_state_sync_broadcaster.register_enemy(enemy,801+index)
		bosses.append(enemy)

func _reset_players() -> void:
	for actor_variant in [local_player, remote_player]:
		var actor := actor_variant as ChargePlayer
		actor.discard_pending_combat_input()
		actor.set_max_health_and_current(500,500)
		actor.set_combat_damage_enabled(true)
		actor._dash_damage_immune_left = 0.0
		actor._contact_damage_grace_left = 0.0
		actor.damage_contexts.clear()
	local_player.position = Vector2(-110.0,0.0)
	remote_player.position = Vector2(-20.0,0.0)
	if boss_index==1:
		boss.seam_zones.clear()
		boss.seam_attempts = 0

func _prepare_charge() -> void:
	_reset_players()
	boss.position = Vector2(-200.0,0.0)
	boss.velocity = Vector2.ZERO
	boss.set_max_health_and_current(boss.max_health)
	boss.target = local_player
	if boss_index==1:
		boss._attack_cycle_step = 0
		boss._last_attack = -1
		boss._repeat_attack_streak = 0
	boss._start_next_attack(400.0,0.0)
	check(boss.active_attack==0 and boss.boss_state==1,"Boss starts its real charge telegraph")

func _send_state(packet: Dictionary={},room_id: int=7) -> Dictionary:
	var actual: Dictionary = boss.get_projectile_network_sync_state() if packet.is_empty() else packet
	world._sync_enemy_states.rpc([{"enemy_id":801+boss_index,"health":boss.get_current_health(),"position":boss.global_position,"runtime_state_delta":boss.get_network_runtime_state()}],2)
	world._sync_archer_projectile_states.rpc([{"enemy_id":801+boss_index,"payload":actual}],room_id)
	return actual

func _snapshot() -> Dictionary:
	return {"geometry":boss.get_charge_warning_geometry(),"polygons":boss.get_charge_warning_polygons(),"health":boss.get_current_health(),"local_health":local_player.get_current_health(),"remote_health":remote_player.get_current_health(),"local_calls":(local_player as ChargePlayer).damage_contexts.size(),"remote_calls":(remote_player as ChargePlayer).damage_contexts.size(),"seam_attempts":boss.seam_attempts if boss_index==1 else 0,"phase":boss.boss_state,"attack":boss.active_attack}

func _inspect(client_id: int,key: String,options: Dictionary={}) -> Dictionary:
	var payload := options.duplicate(true)
	payload["index"] = boss_index
	payload["key"] = key
	world.fixture_command.rpc_id(client_id,"inspect",payload)
	check(await until(func():return results.has(key)),key+": joiner replies")
	return results.get(key,{})

func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	await physics_frame
	await _test_packet_budget(client_id)
	for index in range(2):
		boss_index = index
		boss = bosses[index]
		var label := "Warden" if index==0 else "Lacuna"
		_prepare_charge()
		var initial_geometry: Dictionary = boss.get_charge_warning_geometry()
		var packet := _send_state()
		var remote := await _inspect(client_id,label+"_warning",{"expect_warning":true,"try_damage":true})
		if not remote.is_empty():
			check(remote.geometry==initial_geometry and remote.polygons==boss.get_charge_warning_polygons(),label+": replica warning uses exact host world geometry")
			check(remote.local_calls==0 and remote.remote_calls==0 and remote.seam_attempts==0,label+": replica attack methods cannot apply damage or create seams")
		# Deliberately let the last warning packet expire, then replay it.
		remote = await _inspect(client_id,label+"_expire",{"expire":true})
		check(remote.get("polygons",[]).is_empty(),label+": lost final packet expires the warning")
		_send_state(packet)
		remote = await _inspect(client_id,label+"_duplicate")
		check(remote.get("polygons",[]).is_empty(),label+": equal/stale charge cannot resurrect expired geometry")
		var stale_room := packet.duplicate(true)
		stale_room.cc[0] += 100
		_send_state(stale_room,6)
		remote = await _inspect(client_id,label+"_wrong_room")
		check(remote.get("polygons",[]).is_empty(),label+": prior-room projectile packet cannot restore a charge")
		for invalid_kind in ["inner_room","nonfinite"]:
			var invalid := packet.duplicate(true)
			invalid.cc[0] += 100
			if invalid.has("seq"):invalid.seq += 100
			if invalid_kind=="inner_room":invalid.cc[1] = 6
			else:invalid.cc[3] = Vector2.INF
			_send_state(invalid)
			remote = await _inspect(client_id,label+"_"+invalid_kind)
			check(remote.get("polygons",[]).is_empty(),label+": invalid "+invalid_kind+" geometry is rejected atomically")
		# Existing custom runtime may be delayed independently of projectile state.
		var stale_runtime: Dictionary = boss.get_network_runtime_state()
		world._sync_enemy_states.rpc([{"enemy_id":801+index,"runtime_state_delta":stale_runtime}],2)
		remote = await _inspect(client_id,label+"_runtime_only")
		check(remote.get("polygons",[]).is_empty(),label+": runtime-only state cannot revive expired committed geometry")
		_send_state()
		remote = await _inspect(client_id,label+"_next_valid",{"expect_warning":true})
		check(remote.get("geometry",{})==initial_geometry,label+": rejected high sequences do not suppress the next valid warning")
		var locked: Dictionary = boss.get_charge_warning_geometry()
		boss._enter_attack_state()
		boss._process_attack_state(2.0)
		var damage := int(boss.charge_damage if index==0 else boss.sever_damage)
		check(local_player.get_current_health()==500-damage and remote_player.get_current_health()==500-damage,label+": long-step swept charge hits both peers once")
		check((local_player as ChargePlayer).damage_contexts.size()==1 and (remote_player as ChargePlayer).damage_contexts.size()==1,label+": duplicated candidates never duplicate charge hits")
		for actor_variant in [local_player, remote_player]:
			var actor := actor_variant as ChargePlayer
			check(actor.damage_contexts[0].source==("enemy_contact" if index==0 else "enemy_ability") and actor.damage_contexts[0].ability==("warden_charge" if index==0 else "lacuna_sever"), label+": hit attribution and damage category stay unchanged")
		check(boss.global_position.distance_to(locked.end)<0.01,label+": movement ends at the announced finite center endpoint")
		if index==1:
			check(boss.seam_attempts==2,"Lacuna creates exactly one seam for each accepted charge attempt")
		_send_state()
		remote = await _inspect(client_id,label+"_health",{"health":500-damage})
		check(remote.get("local_calls",-1)==0 and remote.get("remote_calls",-1)==0,label+": health replication never replays local damage")
		await _test_immunity_attempts(label)
		await _test_other_attacks(client_id,label)
		boss.position = Vector2(-750.0,350.0)
	# Death uses the normal death protocol; run these after final health replication checks.
	for index in range(2):
		boss_index = index
		boss = bosses[index]
		await _test_motion_and_target_death("Warden" if index==0 else "Lacuna")
	world.fixture_command.rpc_id(client_id,"finish")
	await create_timer(0.1).timeout
	await finish()

func _test_immunity_attempts(label: String) -> void:
	_prepare_charge()
	remote_player.position = Vector2(-80.0,0.0)
	local_player._dash_damage_immune_left = 1.0
	remote_player.set_combat_damage_enabled(false)
	boss._enter_attack_state()
	boss._process_attack_state(0.12)
	local_player._dash_damage_immune_left = 0.0
	remote_player.set_combat_damage_enabled(true)
	boss._process_attack_state(2.0)
	check(local_player.get_current_health()==(500 if boss_index==0 else 500-int(boss.sever_damage)),label+": existing contact versus ability immunity rule is preserved")
	check(remote_player.get_current_health()==500,label+": a rejected first attempt is not retried later in the same charge")
	if boss_index==1:
		check(boss.seam_attempts==2,"Lacuna's existing accepted-attempt seam rule also survives rejected player damage")
	await physics_frame

func _test_motion_and_target_death(label: String) -> void:
	_prepare_charge()
	local_player.apply_trial_power("blast_drive")
	local_player.apply_trial_power("razor_orbit")
	local_player.arcana_motion.tick(0.0)
	local_player.global_position = boss.global_position+Vector2(0.0,100.0)
	var locked: Dictionary = boss.get_charge_warning_geometry()
	boss._enter_attack_state()
	local_player.arcana_motion.start_orbit(boss)
	boss._process_attack_state(0.03)
	local_player.arcana_motion.process_movement(0.03,Vector2.ZERO)
	check(local_player.arcana_motion.anchor==boss and local_player.global_position.is_finite(),label+": Orbit follows a charging boss with finite motion")
	local_player.arcana_motion.release_blast(1.0)
	check(local_player.arcana_motion.motion==MOTION.Motion.RECOIL and local_player.arcana_motion.anchor==null,label+": Blast detaches the charge anchor into normal recoil")
	local_player.arcana_motion.process_movement(0.3,Vector2.ZERO)
	check(local_player._dash_damage_immune_left<=0.0,label+": charge combinations do not extend dash immunity")
	boss.target = local_player
	local_player.set_health(0)
	remote_player.position = Vector2(-500.0,250.0)
	boss._process_attack_state(2.0)
	check(boss.global_position.distance_to(locked.end)<0.01,label+": target death and player damage cannot retarget or extend the committed charge")
	await physics_frame

func client_command(command: String,payload: Dictionary) -> void:
	match command:
		"inspect":
			boss_index = int(payload.index)
			boss = bosses[boss_index]
			if bool(payload.get("expect_warning",false)):
				check(await until(func():return not boss.get_charge_warning_polygons().is_empty()),"Joiner receives a host charge warning")
			if bool(payload.get("expire",false)):
				boss._process_network_visuals(0.4)
			if bool(payload.get("try_damage",false)):
				boss._physics_process(0.01)
				if boss_index==0:boss._apply_charge_hit()
				else:boss._apply_sever_hit()
			if payload.has("attack"):
				check(await until(func():return boss.active_attack==int(payload.attack)),"Joiner receives unchanged non-charge attack state")
			if payload.has("health"):
				check(await until(func():return local_player.get_current_health()==int(payload.health) and remote_player.get_current_health()==int(payload.health)),"Joiner receives authoritative charge health")
			world.fixture_result.rpc_id(1,payload.key,_snapshot())
		"finish":
			await create_timer(0.05).timeout
			await finish()
func _test_other_attacks(client_id: int,label: String) -> void:
	for attack in [1,2]:
		_reset_players()
		boss.position = Vector2(-200.0,0.0)
		boss.velocity = Vector2.ZERO
		boss.target = local_player
		boss.locked_direction = Vector2.RIGHT
		boss.target_candidates = [local_player,remote_player]
		boss.active_attack = attack
		local_player.global_position = boss.global_position+Vector2(120.0,0.0)
		remote_player.global_position = boss.global_position+Vector2(140.0,0.0)
		if boss_index==0:
			boss._cleave_locked_directions.clear()
			boss._cleave_locked_directions.append(Vector2.RIGHT)
		else:
			boss._locked_null_ring_center = boss.global_position
			boss._locked_null_ring_centers.clear()
			boss._locked_null_ring_centers.append(boss.global_position)
			boss._echo_cross_angle = 0.0
		boss._enter_attack_state()
		if boss_index==1 and attack==1:
			boss._process_attack_state(0.7)
		var amount: int
		if boss_index==0:
			amount = int(boss.nova_damage if attack==1 else boss.cleave_damage)
		else:
			amount = int(boss.null_ring_damage if attack==1 else boss.echo_cross_damage)
		check(local_player.get_current_health()==500-amount and remote_player.get_current_health()==500-amount,label+": other attack%d preserves both players' existing damage" % attack)
		_send_state()
		var remote := await _inspect(client_id,label+"_other%d" % attack,{"health":500-amount,"attack":attack})
		check(remote.get("attack",-1)==attack and remote.get("polygons",[]).is_empty(),label+": other attacks replicate without retaining a charge warning")
func _test_packet_budget(client_id: int) -> void:
	boss_index = 1
	boss = bosses[1]
	_prepare_charge()
	# Retain a prior four-player Null Ring, but only two seams remain active.
	for index in range(4):
		boss._locked_null_ring_centers.append(Vector2(index * 80.0, 100.0))
	boss._spawn_seam(local_player.global_position)
	boss._spawn_seam(remote_player.global_position)
	var largest: Dictionary = {}
	var largest_bytes := 0
	for sample in range(18):
		# Actual timers and seam pulses exercise fractional float encodings.
		boss._process_seam_zones(1.0 / 60.0)
		boss._process_windup_state(1.0 / 60.0)
		var packet: Dictionary = boss.get_projectile_network_sync_state().duplicate(true)
		var byte_count := var_to_bytes([{"enemy_id":802,"payload":packet}]).size() + 15
		if byte_count >= largest_bytes:
			largest_bytes = byte_count
			largest = packet
	check(largest_bytes <= 1392, "Timed two-seam warning with retained four-player centers fits an uncached ENet packet")
	check(not largest.has("locked_null_ring_centers"), "Sever omits prior Null Ring centers from its packet")
	print("CHARGE_PACKET_BUDGET warning_uncached_max=", largest_bytes)
	# This is deliberately the first projectile RPC on the World path.
	world._sync_archer_projectile_states.rpc([{"enemy_id":802,"payload":largest}],7)
	var remote := await _inspect(client_id,"packet_budget_warning",{"expect_warning":true})
	check(remote.get("geometry",{})==boss.get_charge_warning_geometry(),"Compact uncached warning preserves exact host geometry")
	local_player.position = Vector2(-500.0,300.0)
	remote_player.position = Vector2(-400.0,300.0)
	boss._enter_attack_state()
	boss._process_attack_state(0.05)
	var charge_packet: Dictionary = boss.get_projectile_network_sync_state()
	var charge_bytes := var_to_bytes([{"enemy_id":802,"payload":charge_packet}]).size() + 15
	check(charge_bytes <= 1392 and charge_packet.cc.size()==3, "Charge phase stays compact while both prior seams are active")
	print("CHARGE_PACKET_BUDGET charge_uncached=", charge_bytes)
	world._sync_archer_projectile_states.rpc([{"enemy_id":802,"payload":charge_packet}],7)
	remote = await _inspect(client_id,"packet_budget_charge")
	check(remote.get("polygons",[]).is_empty(),"Ordered compact charge phase clears the replica warning")
	boss._process_attack_state(1.0)
	boss.position = Vector2(-750.0,350.0)
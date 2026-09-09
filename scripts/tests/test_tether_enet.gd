extends "res://scripts/tests/test_boss_combinations_enet.gd"
const TETHER := preload("res://scripts/enemy_tether.gd")
const LEAD_ID := 901
var lead: Node2D
var partner: Node2D
var alternate: Node2D
var departed_registry: Node
class BeamPlayer extends Player:
	var hits: Array[Dictionary] = []
	var deliberate_direction := Vector2.UP
	func _get_mouse_attack_direction() -> Vector2:return deliberate_direction
	func _ready() -> void:
		super._ready()
		damage_taken.connect(func(_raw: int,_final: int,context: Dictionary):hits.append(context.duplicate(true)))
class Tether extends "res://scripts/enemy_tether.gd":
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
	func _beam_aim_velocity() -> Vector2:return Vector2.ZERO
	func _orbit_desired_velocity() -> Vector2:return Vector2.ZERO
	func _web_desired_velocity() -> Vector2:return Vector2.ZERO
	func _beam_crossing_support_velocity() -> Vector2:return Vector2.ZERO
func _run() -> void:
	super._run()
	get_multiplayer().peer_disconnected.connect(MultiplayerSessionManager._on_peer_disconnected)
func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1:{},client_id:{}}
	world.position = Vector2(73.0,-41.0)
	world.current_room_size = Vector2(1800,1100)
	world.current_effective_room_size = world.current_room_size
	for id in [1,client_id]:
		var actor := BeamPlayer.new()
		actor.name = "Player_%d" % id
		actor.player_id = id
		actor.is_local_player = id==get_multiplayer().get_unique_id()
		circle(actor,14.0)
		world.add_child(actor)
		actor.set_max_health_and_current(500,500)
		actor.returning_crescent.set_physics_process(false)
		PlayerReplicationService.register_player(id,actor)
		if actor.is_local_player:
			local_player = actor
			world.player = actor
		else:remote_player = actor
	var bodies: Array[Node2D] = []
	for index in range(3):
		var enemy := Tether.new()
		enemy.name = "Tether%d" % index
		circle(enemy,14.0)
		world.add_child(enemy)
		enemy.set_max_health_and_current(84)
		world.enemy_state_sync_broadcaster.register_enemy(enemy,LEAD_ID+index)
		bodies.append(enemy)
	lead = bodies[0]
	partner = bodies[1]
	alternate = bodies[2]
	lead.position = Vector2(-200.375,0.25)
	partner.position = Vector2(200.625,0.25)
	alternate.position = Vector2(240,300)
	lead.beam_partner = partner
	partner.beam_partner = lead
	lead.target = local_player
	partner.target = remote_player
	for enemy in bodies:enemy.target_candidates = [local_player,local_player,remote_player]
func _reset_players() -> void:
	for actor_variant in [local_player,remote_player]:
		var actor := actor_variant as BeamPlayer
		actor.discard_pending_combat_input()
		actor.set_max_health_and_current(500,500)
		actor.set_combat_damage_enabled(true)
		actor._dash_damage_immune_left = 0.0
		actor._contact_damage_grace_left = 0.0
		actor.dash_cooldown_left = 0.0
		actor.hits.clear()
	local_player.position = Vector2(-50,-70)
	remote_player.position = Vector2(50,70)
	PlayerReplicationService.reset_remote_player_position(remote_player.player_id,remote_player.position)
func _start_beam() -> void:
	lead._enter_recover_state()
	lead.beam_partner = partner
	partner.beam_partner = lead
	lead.target = local_player
	lead._enter_windup_state()
	lead._process_windup(lead.beam_windup_time)
	check(lead.tether_state==TETHER.STATE_BEAM,"Host enters its ordinary beam state after windup")
func _projectile(packet: Dictionary = {}, room_id: int = 7) -> Dictionary:
	var state: Dictionary = lead.get_projectile_network_sync_state() if packet.is_empty() else packet
	world._sync_archer_projectile_states.rpc([{"enemy_id":LEAD_ID,"payload":state}],room_id)
	return state
func _runtime(packet: Dictionary = {}) -> Dictionary:
	var state: Dictionary = lead.get_network_runtime_state() if packet.is_empty() else packet
	if packet.is_empty():state = world.enemy_state_sync_broadcaster._quantize_runtime_state_for_network(state)
	world._sync_enemy_states.rpc([{"enemy_id":LEAD_ID,"health":lead.get_current_health(),"position":lead.global_position,"runtime_state_delta":state}],3)
	return state
func _snapshot() -> Dictionary:
	return {"geometry":lead.get_beam_geometry(),"polygons":lead.get_beam_polygons(),"phase":lead.tether_state,"local_health":local_player.get_current_health(),"remote_health":remote_player.get_current_health(),"local_hits":(local_player as BeamPlayer).hits.size(),"remote_hits":(remote_player as BeamPlayer).hits.size()}
func _inspect(client_id: int,key: String,options: Dictionary = {}) -> Dictionary:
	var payload := options.duplicate(true)
	payload.key = key
	world.fixture_command.rpc_id(client_id,"inspect",payload)
	check(await until(func():return results.has(key)),key+": joiner replies")
	return results.get(key,{})
func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	MultiplayerSessionManager.peer_disconnected.connect(world._on_multiplayer_peer_disconnected)
	await physics_frame
	_reset_players()
	lead._enter_windup_state()
	var warning := _projectile()
	var remote := await _inspect(client_id,"warning",{"phase":TETHER.STATE_WINDUP,"try_damage":true})
	check(remote.get("geometry",{})==lead.get_beam_geometry() and remote.get("polygons",[])==lead.get_beam_polygons(),"Translated host and joiner draw the same exact rounded beam capsule")
	check(remote.get("local_hits",-1)==0 and remote.get("remote_hits",-1)==0,"Replica beam methods cannot originate player damage")
	lead._process_windup(lead.beam_windup_time)
	var active_runtime := _runtime()
	remote = await _inspect(client_id,"runtime_active",{"phase":TETHER.STATE_BEAM})
	check(remote.get("geometry",{})==lead.get_beam_geometry(),"Runtime channel preserves exact packed endpoints and beam radius")
	_projectile(warning)
	remote = await _inspect(client_id,"old_projectile")
	check(remote.get("phase",-1)==TETHER.STATE_BEAM,"Older projectile warning cannot overwrite newer runtime beam state")
	lead._enter_recover_state()
	_projectile()
	remote = await _inspect(client_id,"clear",{"clear":true})
	_runtime(active_runtime)
	remote = await _inspect(client_id,"old_runtime")
	check(remote.get("polygons",[]).is_empty(),"Older runtime beam cannot resurrect a projectile-cleared link")
	_start_beam()
	var active_packet := _projectile()
	await _inspect(client_id,"lease_active",{"phase":TETHER.STATE_BEAM})
	remote = await _inspect(client_id,"lease_expired",{"expire":true})
	check(remote.get("polygons",[]).is_empty(),"Lost final packet expires the remote beam")
	_projectile(active_packet)
	remote = await _inspect(client_id,"lease_replay")
	check(remote.get("polygons",[]).is_empty(),"Equal packet cannot resurrect an expired beam")
	for invalid_kind in ["room","nonfinite"]:
		var invalid := active_packet.duplicate(true)
		invalid.beam[0] += 100
		if invalid_kind=="room":invalid.beam[1] = 6
		else:invalid.beam[6] = PackedVector2Array([Vector2.INF,Vector2.ZERO])
		_projectile(invalid)
		remote = await _inspect(client_id,"invalid_"+invalid_kind)
		check(remote.get("polygons",[]).is_empty(),"Invalid "+invalid_kind+" geometry is rejected without reviving the beam")
	_projectile()
	remote = await _inspect(client_id,"valid_after_rejection",{"phase":TETHER.STATE_BEAM})
	check(remote.get("geometry",{})==lead.get_beam_geometry(),"Rejected higher sequences do not block the next valid beam state")
	await _test_crossing_and_ticks(client_id)
	await _test_motion_crossings(client_id)
	await _test_launch_interruptions(client_id)
	await _test_partner_and_departure(client_id)
	if is_instance_valid(departed_registry):departed_registry.free()
	await finish()
func _joiner_crossed() -> bool:
	# Validation suppresses autoload processing; use the real interpolation step.
	PlayerReplicationService._interpolate_remote_players(1.0/60.0)
	return remote_player.position.y<0.0
func _test_crossing_and_ticks(client_id: int) -> void:
	lead.beam_thickness = 1.0
	_reset_players()
	_start_beam()
	_projectile()
	var thin_remote := await _inspect(client_id,"thin_beam",{"phase":TETHER.STATE_BEAM})
	check(is_equal_approx(float(thin_remote.get("geometry",{}).get("radius",0.0)),1.0), "Thin beam radius replicates without generic runtime quantization")
	lead.target = remote_player
	lead._process_beam(0.01)
	check(local_player.get_current_health()==500 and remote_player.get_current_health()==500,"AI target handoff does not invent a crossing between different players")
	# Both owners dash across the beam between its damage samples.
	world.fixture_command.rpc_id(client_id,"dash",{"position":remote_player.position,"direction":Vector2.UP})
	Input.action_press("dash")
	local_player._try_start_dash(Vector2.DOWN)
	Input.action_release("dash")
	for index in range(12):
		await physics_frame
		local_player._process_active_dash(1.0/60.0)
	check(await until(func():return results.has("dash")),"Joiner finishes its own real dash")
	check(await until(_joiner_crossed),"Host receives the joiner's crossed position through normal transform replication")
	check(local_player.position.y>0.0,"Host's real dash crosses the beam")
	lead._process_beam(lead.beam_tick_interval)
	check(local_player.get_current_health()==491 and remote_player.get_current_health()==491,"One area tick damages both crossing players once, including dashes under the existing ability-damage rule")
	for actor_variant in [local_player,remote_player]:
		var actor := actor_variant as BeamPlayer
		check(actor.hits.size()==1 and actor.hits[0].source=="enemy_ability" and actor.hits[0].ability=="tether_beam_tick","Each crossing retains the existing damage attribution")
	partner._enter_beam_state()
	partner._process_beam(0.01)
	check(local_player.get_current_health()==491 and remote_player.get_current_health()==491,"The opposite endpoint cannot double-own pair damage")
	lead._process_beam(0.01)
	check(local_player.get_current_health()==491 and remote_player.get_current_health()==491,"An early frame does not add another damage tick")
	await _inspect(client_id,"crossing_health",{"health":491})
	# A hitch may deliver one due attempt, never a catch-up burst.
	local_player.position = Vector2(-50,0.25)
	remote_player.position = Vector2(50,0.25)
	lead._process_beam(1.0)
	check(local_player.get_current_health()==482 and remote_player.get_current_health()==482,"Long frame yields at most one due tick for each participant")
	lead.state_time_left = 0.01
	lead.beam_tick_left = 0.15
	lead._process_beam(0.5)
	check(local_player.get_current_health()==482 and remote_player.get_current_health()==482 and lead.tether_state==TETHER.STATE_RECOVER,"Expiry clips elapsed damage time and does not invent a late tick")
	_reset_players()
	local_player.position = Vector2(-50,50)
	remote_player.position = Vector2(50,50)
	_start_beam()
	lead.position.y += 100.0
	partner.position.y += 100.0
	lead._process_beam(0.01)
	check(local_player.get_current_health()==491 and remote_player.get_current_health()==491,"A moving thin beam detects stationary players crossed between endpoint samples")
	_runtime()
	var moved_remote := await _inspect(client_id,"moved_thin_beam",{"phase":TETHER.STATE_BEAM})
	check(moved_remote.get("geometry",{})==lead.get_beam_geometry(),"Runtime beam endpoints stay exact while endpoint body packets arrive separately")
func _test_motion_crossings(client_id: int) -> void:
	_reset_players()
	lead.position = Vector2(-200,0)
	partner.position = Vector2(200,0)
	remote_player.position = Vector2(120,-70)
	PlayerReplicationService.reset_remote_player_position(remote_player.player_id,remote_player.position)
	_start_beam()
	_projectile()
	world.fixture_command.rpc_id(client_id,"orbit",{"position":remote_player.position})
	local_player.reward_blast_drive = true
	local_player.blast_drive_stacks = 1
	local_player.arcana_motion._refresh_capacity()
	local_player.arcana_motion.release_blast(1.0)
	check(local_player.arcana_motion.motion==local_player.arcana_motion.Motion.RECOIL,"Blast starts its real recoil across the thin beam")
	for index in range(16):
		await physics_frame
		local_player.arcana_motion.process_movement(1.0/60.0,Vector2.ZERO)
	check(local_player.position.y>0.0,"Blast recoil crosses the beam without extending dash immunity")
	check(await until(func():return results.has("orbit")),"Joiner completes a real Orbit crossing")
	var orbit_result: Dictionary = results.get("orbit",{})
	check(bool(orbit_result.get("active",false)) and Vector2(orbit_result.get("position",Vector2.ZERO)).y>0.0,"Joiner is still orbiting the aimed endpoint after crossing")
	check(await until(func():
		PlayerReplicationService._interpolate_remote_players(1.0/60.0)
		return remote_player.position.y>0.0),"Host receives the Orbit endpoint through normal player transform replication")
	lead._process_beam(lead.beam_tick_interval)
	check(local_player.get_current_health()==491 and remote_player.get_current_health()==491,"Host area tick detects both real recoil and Orbit crossings exactly once")
	check(local_player._dash_damage_immune_left<=0.0 and not bool(orbit_result.get("immune",true)),"Recoil and Orbit preserve ordinary immunity duration")
	await _inspect(client_id,"motion_crossing_health",{"health":491})
func _test_launch_interruptions(client_id: int) -> void:
	local_player.ruinous_impact_stacks = 1
	for launched in [lead,partner]:
		for phase in [TETHER.STATE_WINDUP,TETHER.STATE_BEAM]:
			_reset_players()
			lead.position = Vector2(-200,0)
			partner.position = Vector2(200,0)
			local_player.position = Vector2(-50,0)
			remote_player.position = Vector2(50,0)
			lead._enter_recover_state()
			lead._enter_windup_state()
			if phase==TETHER.STATE_BEAM:lead._process_windup(lead.beam_windup_time)
			var case_name := "launch_%d_%d" % [launched.get_meta("network_enemy_id"),phase]
			var before_projectile := _projectile()
			var before_runtime := _runtime()
			await _inspect(client_id,case_name+"_before",{"phase":phase})
			launched.get_launch_state().cooldown_left = 0.0
			local_player.boss_combinations.launch_enemy(launched,Vector2.UP*600.0,1)
			check(launched.get_launch_state().active and not launched.get_launch_state().compression,case_name+": actual Ruinous reward starts a displacement launch")
			check(lead.get_beam_geometry().is_empty(),case_name+": launched endpoint immediately suppresses hazardous geometry")
			lead._physics_process(0.01)
			lead._process_beam(lead.beam_tick_interval)
			check(lead.tether_state==TETHER.STATE_RECOVER and local_player.get_current_health()==500 and remote_player.get_current_health()==500,case_name+": launch interrupts into existing recovery without an extra area tick")
			_projectile()
			await _inspect(client_id,case_name+"_cancel",{"clear":true})
			_runtime(before_runtime)
			_projectile(before_projectile)
			var remote := await _inspect(client_id,case_name+"_old_packets")
			check(remote.get("polygons",[]).is_empty(),case_name+": stale packets from both channels cannot revive the interrupted beam")
			launched.get_launch_state().cancel()
			lead._process_recover(lead.recover_time)
			lead._process_stalk(0.01)
			check(lead.tether_state==TETHER.STATE_STALK and lead.beam_cooldown_left>0.0,case_name+": finishing launch preserves recovery cooldown before another fresh warning")
func _test_partner_and_departure(client_id: int) -> void:
	lead.beam_thickness = 24.0
	_reset_players()
	_start_beam()
	_projectile()
	await _inspect(client_id,"before_partner_death",{"phase":TETHER.STATE_BEAM})
	partner.set_health(0)
	lead._process_behavior(0.01)
	check(lead.get_beam_geometry().is_empty() and local_player.get_current_health()==500 and remote_player.get_current_health()==500,"Pair death ends the announced beam without sweeping to a replacement")
	var remote := await _inspect(client_id,"dead_partner",{"clear":true})
	check(remote.get("polygons",[]).is_empty(),"Joiner removes beam geometry when its endpoint dies through normal enemy replication")
	partner = alternate
	lead.beam_partner = partner
	partner.beam_partner = lead
	lead.position = Vector2(-200,0)
	partner.position = Vector2(200,0)
	local_player.position = Vector2(-50,0)
	remote_player.position = Vector2(50,70)
	PlayerReplicationService.reset_remote_player_position(remote_player.player_id,remote_player.position)
	_start_beam()
	lead._process_beam(0.01)
	check(local_player.get_current_health()==491 and remote_player.get_current_health()==500,"Replacement pair begins with fresh participant histories")
	departed_registry = remote_player.upgrade_system.power_registry
	world.fixture_command.rpc_id(client_id,"disconnect")
	check(await until(func():return not MultiplayerSessionManager.connected_peers.has(client_id) and not is_instance_valid(remote_player)),"Participant leaves through actual ENet and World roster cleanup")
	lead._process_beam(lead.beam_tick_interval)
	check(local_player.get_current_health()==482,"Remaining player still receives one beam tick after the other player departs")
func client_command(command: String,payload: Dictionary) -> void:
	match command:
		"inspect":
			if payload.has("phase"):
				check(await until(func():return lead.tether_state==int(payload.phase) and not lead.get_beam_polygons().is_empty()),"Joiner receives current active beam phase")
			if bool(payload.get("clear",false)):
				check(await until(func():return lead.get_beam_polygons().is_empty()),"Joiner clears ended beam geometry")
			if bool(payload.get("expire",false)):lead._process_network_visuals(0.4)
			if bool(payload.get("try_damage",false)):
				lead._physics_process(0.01)
				lead._try_apply_beam_damage()
			if payload.has("health"):
				check(await until(func():return local_player.get_current_health()==int(payload.health) and remote_player.get_current_health()==int(payload.health)),"Joiner receives authoritative health for both crossing players")
			world.fixture_result.rpc_id(1,payload.key,_snapshot())
		"dash":
			local_player.position = payload.position
			local_player.dash_cooldown_left = 0.0
			Input.action_press("dash")
			local_player._try_start_dash(payload.direction)
			Input.action_release("dash")
			for index in range(12):
				await physics_frame
				local_player._process_active_dash(1.0/60.0)
			PlayerReplicationService._sync_all_player_positions()
			world.fixture_result.rpc_id(1,"dash",{"position":local_player.position,"immune":local_player._dash_damage_immune_left>0.0})
		"orbit":
			_reset_players()
			lead.position = Vector2(-200,0)
			partner.position = Vector2(200,0)
			local_player.position = payload.position
			local_player.reward_razor_orbit = true
			local_player.razor_orbit_stacks = 1
			local_player.dash_direction = Vector2.DOWN
			local_player.arcana_motion.start_orbit(partner)
			for index in range(16):
				await physics_frame
				local_player.arcana_motion.process_movement(1.0/60.0,Vector2.ZERO)
			PlayerReplicationService._sync_all_player_positions()
			world.fixture_result.rpc_id(1,"orbit",{"position":local_player.position,"active":local_player.arcana_motion.motion==local_player.arcana_motion.Motion.ORBIT,"immune":local_player._dash_damage_immune_left>0.0})
		"disconnect":
			world.process_mode = Node.PROCESS_MODE_DISABLED
			world.hide()
			await create_timer(0.05).timeout
			peer.disconnect_peer(1)
			await create_timer(0.2).timeout
			await finish()

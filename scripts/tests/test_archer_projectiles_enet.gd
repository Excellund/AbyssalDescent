extends "res://scripts/tests/test_boss_combinations_enet.gd"
const ARCHER := preload("res://scripts/enemy_archer.gd")
const ARCHER_ID := 940
var archer: Node2D
var anchor: Node2D
var cover: StaticBody2D
class ArrowPlayer extends Player:
	var hits: Array[Dictionary] = []
	var deliberate_direction := Vector2.UP
	func _get_mouse_attack_direction() -> Vector2:return deliberate_direction
	func _ready() -> void:
		super._ready()
		damage_taken.connect(func(_raw:int,_final:int,context:Dictionary):hits.append(context.duplicate(true)))
class Archer extends "res://scripts/enemy_archer.gd":
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
func setup_actors(client_id:int) -> void:
	MultiplayerSessionManager.connected_peers = {1:{},client_id:{}}
	world.position = Vector2(73,-41)
	world.current_room_size = Vector2(1800,1100)
	world.current_effective_room_size = world.current_room_size
	for id in [1,client_id]:
		var actor := ArrowPlayer.new()
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
	archer = Archer.new()
	archer.name = "Archer"
	circle(archer,14.0)
	world.add_child(archer)
	archer.set_max_health_and_current(1000)
	world.enemy_state_sync_broadcaster.register_enemy(archer,ARCHER_ID)
	anchor = Enemy.new()
	anchor.name = "Anchor"
	circle(anchor,14.0)
	world.add_child(anchor)
	anchor.set_max_health_and_current(1000)
	world.enemy_state_sync_broadcaster.register_enemy(anchor,ARCHER_ID+1)
	_reset_actors()
func _reset_actors() -> void:
	archer._clear_all_projectiles()
	archer.position = Vector2(-250,0)
	archer.arrow_direction = Vector2.RIGHT
	archer.target = local_player
	archer.target_candidates = [local_player,remote_player]
	anchor.position = Vector2(350,250)
	for actor in [local_player,remote_player]:
		actor.discard_pending_combat_input()
		actor.set_max_health_and_current(500,500)
		actor.set_combat_damage_enabled(true)
		actor._dash_damage_immune_left = 0.0
		actor._contact_damage_grace_left = 0.0
		actor.hits.clear()
	local_player.position = Vector2(150,0)
	remote_player.position = Vector2(150,250)
	PlayerReplicationService.reset_remote_player_position(remote_player.player_id,remote_player.position)
	if is_instance_valid(cover):
		cover.free()
	cover = null
func _wall(local_position:Vector2) -> void:
	cover = StaticBody2D.new()
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(4,300)
	cover.add_child(shape)
	world.add_child(cover)
	cover.position = local_position
func _packet(packet:Dictionary = {},room:int = 7) -> Dictionary:
	var state:Dictionary = archer.get_projectile_network_sync_state() if packet.is_empty() else packet
	world._sync_archer_projectile_states.rpc([{"enemy_id":ARCHER_ID,"payload":state}],room)
	return state
func _runtime(packet:Dictionary = {}) -> Dictionary:
	var state:Dictionary = archer.get_network_runtime_state() if packet.is_empty() else packet
	if packet.is_empty():state = world.enemy_state_sync_broadcaster._quantize_runtime_state_for_network(state)
	world._sync_enemy_states.rpc([{"enemy_id":ARCHER_ID,"health":archer.get_current_health(),"position":archer.global_position,"runtime_state_delta":state}],2)
	return state
func _snapshot() -> Dictionary:
	var positions: Array[Vector2] = []
	if is_instance_valid(archer):
		for arrow in archer.projectiles:
			if is_instance_valid(arrow):positions.append(arrow.global_position)
	return {"positions":positions,"local_health":local_player.get_current_health(),"remote_health":remote_player.get_current_health(),"local_hits":local_player.hits.size(),"remote_hits":remote_player.hits.size()}
func _inspect(client_id:int,key:String,options:Dictionary = {}) -> Dictionary:
	var payload := options.duplicate(true)
	payload.key = key
	world.fixture_command.rpc_id(client_id,"inspect",payload)
	check(await until(func():return results.has(key)),key+": joiner responds")
	return results.get(key,{})
func host_scenarios(client_id:int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	await physics_frame
	await _collision_cases(client_id)
	await _wire_cases(client_id)
	await _motion_cases(client_id)
	await _identity_and_counterplay_cases(client_id)
	await _launch_pause_case(client_id)
	await _death_case(client_id)
	world.fixture_command.rpc_id(client_id,"finish")
	await create_timer(0.08).timeout
	await finish()
func _collision_cases(client_id:int) -> void:
	_reset_actors()
	archer._fire_arrow()
	check(archer.projectiles.size()==1 and archer.projectiles[0].global_position==archer.global_position+Vector2.RIGHT*20.0,"Arrow spawns at its exact translated world origin")
	var spawn := _packet()
	var remote := await _inspect(client_id,"spawn",{"count":1,"try_damage":true})
	check(remote.get("positions",[])==_snapshot().positions,"Joiner receives the actual world-space arrow origin")
	check(remote.get("local_hits",-1)==0 and remote.get("remote_hits",-1)==0,"Replica update methods cannot originate arrow damage")
	archer._process_projectiles(1.5)
	check(local_player.get_current_health()==486 and archer.projectiles.is_empty(),"A hitch crossing the current target deals the existing14 damage once")
	check(local_player.hits.size()==1 and local_player.hits[0].source=="enemy_ability" and local_player.hits[0].ability=="archer_projectile","Arrow keeps its existing enemy-ability attribution")
	_packet()
	await _inspect(client_id,"consumed",{"count":0})
	_packet(spawn)
	remote = await _inspect(client_id,"old_spawn")
	check(remote.get("positions",[]).is_empty(),"Stale active packet cannot resurrect a consumed arrow")
	_reset_actors()
	anchor.position = Vector2(-100,0)
	_wall(Vector2(0,0))
	await physics_frame
	archer._fire_arrow()
	archer._process_projectiles(1.5)
	check(archer.projectiles.is_empty() and local_player.get_current_health()==500,"Ignored enemy bodies cannot hide the earlier cover collision")
	_reset_actors()
	local_player.position = Vector2(-50,0)
	_wall(Vector2(60,0))
	await physics_frame
	archer._fire_arrow()
	archer._process_projectiles(1.5)
	check(local_player.get_current_health()==486 and archer.projectiles.is_empty(),"Target contact before a later wall wins the time ordering")
	_reset_actors()
	remote_player.position = Vector2(-50,0)
	await physics_frame
	archer._fire_arrow()
	archer._process_projectiles(1.5)
	check(local_player.get_current_health()==500 and remote_player.get_current_health()==500 and archer.projectiles.is_empty(),"A non-target player still consumes the arrow harmlessly")
func _wire_cases(client_id:int) -> void:
	_reset_actors()
	local_player.position = Vector2(150,250)
	archer._fire_arrow()
	var active := _packet()
	await _inspect(client_id,"lease_begin",{"count":1})
	var remote := await _inspect(client_id,"lease_gap",{"advance":0.36})
	check(remote.get("positions",[]).is_empty(),"Lost final update expires remote arrows after the short lease")
	_packet(active)
	remote = await _inspect(client_id,"equal_after_gap")
	check(remote.get("positions",[]).is_empty(),"Equal packets cannot revive a lease-expired arrow")
	_runtime()
	remote = await _inspect(client_id,"runtime_after_gap")
	check(remote.get("positions",[]).is_empty(),"Generic runtime snapshots carry no stale projectile resurrection path")
	_packet()
	remote = await _inspect(client_id,"newer_after_gap",{"count":1,"advance":0.1})
	check(remote.get("positions",[])==[archer.projectiles[0].global_position+Vector2.RIGHT*28.0],"A newer live snapshot restores presentation with the original280px-per-second velocity")
	for invalid_kind in ["room","nonfinite","duplicate"]:
		var invalid: Dictionary = archer.get_projectile_network_sync_state().duplicate(true)
		invalid.q += 100
		if invalid_kind=="room":invalid.r = 6
		elif invalid_kind=="nonfinite":invalid.p[0][1] = PackedVector2Array([Vector2.INF,Vector2.RIGHT*280.0])
		else:invalid.p.append(invalid.p[0].duplicate(true))
		_packet(invalid)
		remote = await _inspect(client_id,"invalid_"+invalid_kind)
		check(remote.get("positions",[])==[archer.projectiles[0].global_position+Vector2.RIGHT*28.0],"Invalid "+invalid_kind+" snapshot is rejected atomically")
	_packet()
	remote = await _inspect(client_id,"valid_after_invalid",{"count":1})
	check(remote.get("positions",[])==[archer.projectiles[0].global_position],"Rejected high sequences do not block the next valid authoritative position")
	for index in range(5):archer._fire_arrow()
	var six := _packet()
	check(var_to_bytes([{"enemy_id":ARCHER_ID,"payload":six}]).size()+64<1392,"A two-volley snapshot stays within the existing safe per-RPC packet budget")
	await _inspect(client_id,"six_arrows",{"count":6})
	archer.projectiles.front().queue_free()
	archer._process_projectiles(0.01)
	_packet()
	await _inspect(client_id,"omitted_arrow",{"count":5})
	_packet(six)
	remote = await _inspect(client_id,"omitted_replay")
	check(remote.get("positions",[]).size()==5,"An older full snapshot cannot restore an omitted projectile ID")
func _motion_cases(client_id:int) -> void:
	_reset_actors()
	archer.position = Vector2(-48,0)
	local_player.position = Vector2(0,-85)
	archer._fire_arrow()
	local_player.reward_blast_drive = true
	local_player.blast_drive_stacks = 1
	local_player.arcana_motion._refresh_capacity()
	local_player.arcana_motion.release_blast(1.0)
	for index in range(12):
		await physics_frame
		local_player.arcana_motion.process_movement(1.0/60.0,Vector2.ZERO)
	check(local_player.position.y>70.0,"Actual Blast recoil crosses the arrow's path")
	archer._process_projectiles(0.2)
	check(local_player.get_current_health()==486 and archer.projectiles.is_empty(),"Same-time projectile sweep catches real recoil between distant endpoints")
	_reset_actors()
	archer.position = Vector2(-48,0)
	anchor.position = Vector2(100,0)
	remote_player.position = Vector2(30,-70)
	PlayerReplicationService.reset_remote_player_position(remote_player.player_id,remote_player.position)
	archer.target = remote_player
	archer._fire_arrow()
	world.fixture_command.rpc_id(client_id,"orbit",{"position":remote_player.position})
	check(await until(func():return results.has("orbit")),"Joiner finishes its own real Orbit movement")
	check(await until(func():
		PlayerReplicationService._interpolate_remote_players(1.0/60.0)
		return remote_player.position.y>0.0),"Host receives the Orbit crossing through ordinary transform replication")
	archer._process_projectiles(16.0/60.0)
	check(remote_player.get_current_health()==486 and archer.projectiles.is_empty(),"Host resolves the arrow against the moving joiner's own position history")
	await _inspect(client_id,"orbit_health",{"health":486})
func _identity_and_counterplay_cases(client_id:int) -> void:
	_reset_actors()
	archer.position = Vector2(-48,0)
	local_player.position = Vector2(0,-70)
	remote_player.position = Vector2(0,70)
	archer._fire_arrow()
	archer.target = remote_player
	archer._process_projectiles(0.2)
	check(local_player.get_current_health()==500 and remote_player.get_current_health()==500 and archer.projectiles.size()==1,"AI target handoff cannot combine different players' positions into a false swept hit")
	_reset_actors()
	archer.position = Vector2(-48,0)
	local_player.position = Vector2(0,-70)
	archer._fire_arrow()
	var flow := preload("res://scripts/core/player_flow_coordinator.gd").new()
	flow.reset_player_position(local_player,world.to_global(Vector2(0,70)))
	archer._process_projectiles(0.2)
	check(local_player.get_current_health()==500 and archer.projectiles.size()==1,"An explicit combat-position reset cannot become a phantom arrow crossing")
	_reset_actors()
	archer._fire_arrow()
	var original: Vector2 = archer.projectiles[0].global_position
	local_player.null_corridor_strength = 1.0
	local_player._null_corridor_dash_origin = world.to_global(Vector2(-250,-100))
	local_player._apply_null_corridor_segment(world.to_global(Vector2(-250,-100)),world.to_global(Vector2(-250,100)))
	local_player._update_null_corridor_segments(0.01)
	check(archer.velocity.length()>0.0,"Existing Null Corridor deflects the Archer body")
	check(archer.projectiles[0].global_position==original,"Deflecting the Archer does not drag its already spawned arrow")
	archer._process_projectiles(0.2)
	check(archer.projectiles[0].global_position==original+Vector2.RIGHT*56.0,"The existing arrow retains its own direction and280px speed after body deflection")
	_packet()
	var remote := await _inspect(client_id,"corridor_arrow",{"count":1})
	check(remote.get("positions",[])==_snapshot().positions,"Null Corridor interaction preserves authoritative world-space arrow replication")
	local_player.null_corridor_segments.clear()
	local_player.null_corridor_strength = 0.0
	world.current_effective_room_size = Vector2(100,100)
	archer._process_projectiles(0.01)
	check(archer.projectiles.is_empty() and local_player.get_current_health()==500,"A live arena shrink removes an outside arrow before any later target contact")
	_packet()
	await _inspect(client_id,"live_boundary_clear",{"count":0})
	world.current_effective_room_size = world.current_room_size
func _launch_pause_case(client_id:int) -> void:
	_reset_actors()
	local_player.position = Vector2(0,-70)
	archer._fire_arrow()
	var bullet:Node2D = archer.projectiles[0]
	bullet.global_position = world.to_global(Vector2.ZERO)
	local_player.ruinous_impact_stacks = 1
	local_player.boss_combinations.launch_enemy(archer,Vector2.UP*300.0,1)
	_packet()
	var remote := await _inspect(client_id,"launched_arrow_pause",{"count":1,"advance":0.1})
	check(remote.get("positions",[])==[world.to_global(Vector2.ZERO)],"Joiner holds the arrow still while Ruinous owns the Archer's movement")
	remote = await _inspect(client_id,"paused_lease_expiry",{"advance":0.26})
	check(remote.get("positions",[]).is_empty(),"A zero-velocity arrow still expires if its host updates stop")
	_packet()
	await _inspect(client_id,"paused_new_snapshot",{"count":1})
	local_player.arcana_motion._refresh_capacity()
	local_player.arcana_motion.blast_charges = 1
	local_player.arcana_motion.release_blast(1.0)
	for index in range(4):
		await physics_frame
		local_player.arcana_motion.process_movement(0.1,Vector2.ZERO)
		archer._physics_process(0.1)
	check(local_player.position.y>90.0 and local_player.get_current_health()==500 and bullet.global_position==world.to_global(Vector2.ZERO),"Ruinous retains the existing arrow pause while real recoil moves the player away")
	_packet()
	remote = await _inspect(client_id,"last_skipped_arrow_step",{"count":1,"advance":0.1})
	check(remote.get("positions",[])==[world.to_global(Vector2.ZERO)],"The launch's final skipped AI frame still replicates zero arrow velocity")
	archer._physics_process(1.0/60.0)
	check(local_player.get_current_health()==500 and archer.projectiles.size()==1,"Resuming the paused Archer cannot retroactively hit a crossing from its launch interruption")
	_packet()
	remote = await _inspect(client_id,"resumed_arrow",{"count":1,"advance":0.1})
	check(remote.get("positions",[])==[archer.projectiles[0].global_position+Vector2.RIGHT*28.0],"First real resumed update restores the same arrow's normal replicated speed")
	local_player.ruinous_impact_stacks = 0
func _death_case(client_id:int) -> void:
	_reset_actors()
	archer._fire_arrow()
	var live := _packet()
	await _inspect(client_id,"before_archer_death",{"count":1})
	archer.set_health(0)
	var remote := await _inspect(client_id,"archer_death",{"count":0})
	check(remote.get("positions",[]).is_empty(),"Normal replicated Archer death clears its world-parented arrows")
	_packet(live)
	remote = await _inspect(client_id,"dead_archer_replay")
	check(remote.get("positions",[]).is_empty(),"Late arrow packets cannot recreate arrows after the owning Archer dies")
func client_command(command:String,payload:Dictionary) -> void:
	match command:
		"inspect":
			if payload.has("count"):
				check(await until(func():return (archer.projectiles.size() if is_instance_valid(archer) else 0)==int(payload.count)),"Joiner receives the authoritative arrow count")
			if bool(payload.get("try_damage",false)):archer._process_projectiles(2.0)
			if payload.has("advance"):archer._process_network_visuals(float(payload.advance))
			if payload.has("health"):
				check(await until(func():return local_player.get_current_health()==int(payload.health)),"Joiner receives the authoritative arrow damage")
			world.fixture_result.rpc_id(1,payload.key,_snapshot())
		"orbit":
			_reset_actors()
			anchor.position = Vector2(100,0)
			local_player.position = payload.position
			local_player.reward_razor_orbit = true
			local_player.razor_orbit_stacks = 1
			local_player.dash_direction = Vector2.DOWN
			local_player.arcana_motion.start_orbit(anchor)
			for index in range(16):
				await physics_frame
				local_player.arcana_motion.process_movement(1.0/60.0,Vector2.ZERO)
			PlayerReplicationService._sync_all_player_positions()
			world.fixture_result.rpc_id(1,"orbit",{"position":local_player.position})
		"finish":
			await create_timer(0.03).timeout
			await finish()

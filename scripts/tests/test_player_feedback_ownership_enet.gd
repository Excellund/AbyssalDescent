extends "res://scripts/tests/test_boss_combinations_enet.gd"
class DamageFeedback extends Feedback:
	var flashes: Array[float] = []
	func play_damage_flash() -> void:
		super.play_damage_flash()
		flashes.append(damage_flash_rect.modulate.a if damage_flash_rect != null else 0.0)
class ImpactPlayer extends Player:
	func _create_player_feedback() -> void:
		player_feedback = DamageFeedback.new()
		add_child(player_feedback)
		player_feedback.setup(max_health,get_current_health())
class Warden extends "res://scripts/enemy_boss.gd":
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
class Shielder extends "res://scripts/enemy_shielder.gd":
	func _ready() -> void:
		super._ready()
		set_physics_process(false)
var warden: Warden
var shielder: Shielder
func setup_actors(client_id: int) -> void:
	MultiplayerSessionManager.connected_peers = {1:{},client_id:{}}
	for id in [1,client_id]:
		var actor := ImpactPlayer.new()
		actor.name = "Player_%d" % id
		circle(actor,14.0)
		# Exercise real setup before session identity has been assigned.
		world.add_child(actor)
		actor.player_id = id
		actor.is_local_player = id==get_multiplayer().get_unique_id()
		actor.set_max_health_and_current(500,500)
		actor.returning_crescent.set_physics_process(false)
		PlayerReplicationService.register_player(id,actor)
		if actor.is_local_player:
			local_player = actor
			world.player = actor
		else:remote_player = actor
	warden = Warden.new()
	circle(warden,34.0)
	world.add_child(warden)
	shielder = Shielder.new()
	circle(shielder,13.0)
	world.add_child(shielder)
func _snapshot() -> Dictionary:
	var local_feedback := local_player.player_feedback as DamageFeedback
	var remote_feedback := remote_player.player_feedback as DamageFeedback
	return {"local_flashes":local_feedback.flashes.duplicate(),"remote_flashes":remote_feedback.flashes.duplicate(),"local_layer":local_feedback.damage_flash_layer!=null,"remote_layer":remote_feedback.damage_flash_layer!=null,"local_health":local_player.get_current_health(),"remote_health":remote_player.get_current_health()}
func _clear_flash(actor: Player) -> void:
	var feedback := actor.player_feedback
	if feedback.damage_flash_tween != null and feedback.damage_flash_tween.is_valid():feedback.damage_flash_tween.kill()
	if feedback.damage_flash_rect != null:feedback.damage_flash_rect.modulate.a = 0.0
func _screen_alpha(actor: Player) -> float:
	return actor.player_feedback.damage_flash_rect.modulate.a if actor.player_feedback.damage_flash_rect != null else 0.0
func host_scenarios(client_id: int) -> void:
	joiner_id = client_id
	setup_actors(client_id)
	check(await until(func():return remote_player.player_feedback.damage_flash_layer==null), "Post-setup remote identity retires its provisional layer on a real frame")
	# Reassignment must also retire a flash already in progress.
	local_player.player_feedback.play_impact_heavy(local_player.global_position)
	var previous_layer: CanvasLayer = local_player.player_feedback.damage_flash_layer
	local_player.is_local_player = false
	local_player.player_feedback._process(0.0)
	check(not previous_layer.visible and local_player.player_feedback.damage_flash_layer==null, "Real player reassignment immediately retires an active screen flash")
	local_player.is_local_player = true
	local_player.player_feedback.play_impact_medium(local_player.global_position)
	check(is_equal_approx(_screen_alpha(local_player),0.495), "Reassigned real owner recovers its original medium flash strength")
	check(local_player.player_feedback.damage_flash_layer!=null and remote_player.player_feedback.damage_flash_layer==null,"Host owns exactly one screen layer")
	for label in ["warden_nova","shielder_slam","shielder_body"]:
		_clear_flash(local_player)
		_clear_flash(remote_player)
		local_player.position = Vector2(500,250)
		remote_player.position = Vector2(20,0)
		remote_player.set_max_health_and_current(500,500)
		remote_player._contact_damage_grace_left = 0.0
		var feedback := remote_player.player_feedback as DamageFeedback
		var rings_before := feedback.rings
		var expected_damage := 0
		match label:
			"warden_nova":
				warden.target = remote_player
				warden.target_candidates = [remote_player]
				warden._apply_nova_hit()
				expected_damage = warden.nova_damage
			"shielder_slam":
				shielder.target = remote_player
				shielder.slam_hit_applied = false
				shielder._try_apply_slam_aoe_hit()
				expected_damage = shielder.slam_damage
			"shielder_body":
				shielder.target = remote_player
				shielder.body_check_cooldown_left = 0.0
				shielder._try_body_check_target()
				expected_damage = shielder.body_check_damage
		check(local_player.get_current_health()==500 and remote_player.get_current_health()==500-expected_damage,label+": actual damage targets the joiner")
		check(_screen_alpha(local_player)==0.0 and _screen_alpha(remote_player)==0.0,label+": joiner impact cannot flash any host overlay")
		check(feedback.rings>rings_before,label+": observers retain the world impact ring")
		PlayerReplicationService._flush_pending_cue_events()
		world.fixture_command.rpc_id(client_id,"inspect",{"key":label,"count":results.size()+1,"health":500-expected_damage})
		check(await until(func():return results.has(label)),label+": joiner confirms owner cue")
		var snapshot: Dictionary = results.get(label,{})
		check(snapshot.get("local_layer",false) and not snapshot.get("remote_layer",true),label+": joiner also owns exactly one screen layer")
		check(snapshot.get("local_flashes",[]).all(func(alpha):return is_equal_approx(alpha,0.45)) and snapshot.get("remote_flashes",[]).is_empty(),label+": existing reliable cue flashes only its owner at ordinary strength")
	world.fixture_command.rpc_id(client_id,"finish")
	await create_timer(0.1).timeout
	await finish()
func client_command(command: String,payload: Dictionary) -> void:
	match command:
		"inspect":
			var feedback := local_player.player_feedback as DamageFeedback
			check(await until(func():return feedback.flashes.size()>=int(payload.count) and local_player.get_current_health()==int(payload.health)),"Joiner receives actual damage and existing owner-only flash cue")
			world.fixture_result.rpc_id(1,payload.key,_snapshot())
		"finish":
			await create_timer(0.05).timeout
			await finish()
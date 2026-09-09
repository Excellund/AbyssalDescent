extends "res://scripts/tests/test_drifter_replication.gd"

class Seamlock extends "res://scripts/enemy_seamlock.gd":
	func _ready() -> void:
		super._ready()
		set_physics_process(false)

func _run() -> void:
	world = Node2D.new()
	root.add_child(world)
	_test_tick_lifetime()
	_test_replica_lifetime()
	_test_packet_order()
	_test_band_boundaries_and_authority()
	world.free()
	await process_frame
	print("[OK] Seamlock bands: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _enemy(remote: bool = false) -> Seamlock:
	var enemy := Seamlock.new()
	world.add_child(enemy)
	enemy.set_network_simulation_enabled(not remote)
	return enemy

func _target() -> TestTarget:
	var player := TestTarget.new()
	world.add_child(player)
	return player

func _active_band(enemy: Seamlock, life: float, tick: float) -> void:
	enemy._enter_band_attack()
	enemy._band_windup_left = 0.0
	enemy._band_is_active = true
	enemy._band_duration_left = life
	enemy._band_tick_left = tick

func _test_tick_lifetime() -> void:
	var enemy := _enemy()
	var player := _target()
	enemy.target = player
	var cases := [
		[1.0, 0.1, 0.05, 0], [1.0, 0.1, 0.1, 1],
		[0.01, 0.1, 0.2, 0], [0.2, 0.1, 0.4, 1],
		[0.1, 0.1, 0.4, 0], [0.0, 0.0, 0.2, 0],
		[0.1, -0.1, 0.4, 1], [1.0, 0.0, 0.8, 1]
	]
	for index in cases.size():
		var sample: Array = cases[index]
		player.hits = 0
		_active_band(enemy, float(sample[0]), float(sample[1]))
		enemy._process_band_attack(float(sample[2]))
		_check(player.hits == int(sample[3]), "Band tick case %d deals damage only during its lifetime, without catch-up bursts" % index)
		_check(enemy._band_is_active == (float(sample[2]) < float(sample[0])), "Band tick case %d clears active state exactly at expiry" % index)
		if float(sample[2]) >= float(sample[0]):
			_check(enemy.seamlock_state == enemy.ENEMY_STATE_ENUMS.SeamlockState.SPIRAL and is_equal_approx(enemy._spiral_windup_left, enemy.spiral_windup), "Expired bands preserve the following spiral windup")
	player.hits = 0
	enemy._enter_band_attack()
	enemy._band_windup_left = 0.01
	enemy._process_band_attack(0.2)
	_check(player.hits == 0 and enemy._band_is_active and is_equal_approx(enemy._band_duration_left, enemy.band_attack_duration), "Windup completion preserves the existing next-frame first tick")
	player.free()
	enemy.free()

func _test_replica_lifetime() -> void:
	var host := _enemy()
	var remote := _enemy(true)
	_active_band(host, 0.1, 0.05)
	remote.apply_projectile_network_sync_state(host.get_projectile_network_sync_state())
	remote._process_network_visuals(0.04)
	_check(remote._band_is_active and is_equal_approx(remote._band_duration_left, 0.06), "A replicated active band counts down at the actual host duration")
	remote._process_network_visuals(0.06)
	_check(not remote._band_is_active and is_zero_approx(remote._band_duration_left), "Missing the final packet cannot leave active danger rings behind")
	remote._process_network_visuals(5.0)
	_check(not remote._band_is_active, "An expired replica stays visually inactive")
	host._enter_band_attack()
	host._band_windup_left = 0.05
	remote._apply_custom_network_runtime_state(host._get_custom_network_runtime_state())
	remote._process_network_visuals(0.1)
	_check(is_zero_approx(remote._band_windup_left) and not remote._band_is_active, "Expired warning clears while waiting for authoritative activation")
	_check(remote._spiral_arms.is_empty(), "Replica expiry never starts local spiral attacks")
	remote.free()
	host.free()

func _test_band_boundaries_and_authority() -> void:
	var enemy := _enemy()
	var player := _target()
	enemy.target = player
	for sample in [[77.9, 1], [78.0, 0], [168.0, 0], [168.1, 1], [327.9, 1], [328.0, 0], [418.0, 0]]:
		player.position = Vector2(float(sample[0]), 0.0)
		player.hits = 0
		_active_band(enemy, 1.0, 0.0)
		enemy._process_band_attack(0.01)
		_check(player.hits == int(sample[1]), "Danger/safe boundary %.1f retains its exact behavior" % float(sample[0]))
	player.position = Vector2.ZERO
	player.hits = 0
	enemy.set_network_simulation_enabled(false)
	_active_band(enemy, 1.0, 0.0)
	enemy._try_band_damage()
	_check(player.hits == 0, "Replica band logic cannot apply local damage")
	player.free()
	enemy.free()

func _test_packet_order() -> void:
	var host := _enemy()
	var remote := _enemy(true)
	_active_band(host, 0.3, 0.1)
	var old_projectile := host.get_projectile_network_sync_state()
	remote.apply_projectile_network_sync_state(old_projectile)
	host._process_band_attack(0.4)
	var new_custom := host._get_custom_network_runtime_state()
	remote._apply_custom_network_runtime_state(new_custom)
	remote.apply_projectile_network_sync_state(old_projectile)
	_check(not remote._band_is_active and remote.seamlock_state == host.ENEMY_STATE_ENUMS.SeamlockState.SPIRAL, "An older projectile channel cannot revive bands after newer custom spiral state")
	_active_band(host, 0.3, 0.1)
	var old_custom := host._get_custom_network_runtime_state()
	remote._apply_custom_network_runtime_state(old_custom)
	host._process_band_attack(0.4)
	var new_projectile := host.get_projectile_network_sync_state()
	remote.apply_projectile_network_sync_state(new_projectile)
	remote._apply_custom_network_runtime_state(old_custom)
	_check(not remote._band_is_active and remote.seamlock_state == host.ENEMY_STATE_ENUMS.SeamlockState.SPIRAL, "An older custom channel cannot revive bands after newer projectile spiral state")
	_active_band(host, 0.1, 0.0)
	var active := host.get_projectile_network_sync_state()
	remote.apply_projectile_network_sync_state(active)
	remote._process_network_visuals(0.2)
	remote.apply_projectile_network_sync_state(active)
	_check(not remote._band_is_active, "A duplicate active packet does not renew an expired band")
	for invalid_kind in ["room", "sequence", "duration", "windup"]:
		var invalid := active.duplicate(true)
		invalid["q"] = 1000000
		match invalid_kind:
			"room": invalid["r"] = int(active.get("r", 0)) + 1
			"sequence": invalid["q"] = "1000000"
			"duration": invalid["band_duration_left"] = NAN
			"windup": invalid["band_windup_left"] = -1.0
		remote.apply_projectile_network_sync_state(invalid)
		_check(not remote._band_is_active, "Invalid %s cannot revive a band or poison ordering" % invalid_kind)
	var fresh := host.get_projectile_network_sync_state()
	remote.apply_projectile_network_sync_state(fresh)
	_check(remote._band_is_active, "A valid newer host state still renews its actually active band after invalid packets")
	remote._process_network_visuals(0.2)
	var legacy := fresh.duplicate(true)
	legacy.erase("q")
	legacy.erase("r")
	remote.apply_projectile_network_sync_state(legacy)
	_check(not remote._band_is_active, "Unsequenced packets cannot replace an established ordered stream")
	var legacy_remote := _enemy(true)
	legacy_remote.apply_projectile_network_sync_state(legacy)
	_check(legacy_remote._band_is_active, "A fresh replica retains compatibility with older unsequenced peers")
	legacy_remote._process_network_visuals(0.2)
	_check(not legacy_remote._band_is_active, "Legacy active packets also expire locally")
	# Both channel gates preserve the host's authoritative state.
	host._apply_custom_network_runtime_state(new_custom)
	host.apply_projectile_network_sync_state(new_projectile)
	_check(host._band_is_active, "Incoming presentation state cannot alter authoritative band state")
	legacy_remote.free()
	remote.free()
	host.free()

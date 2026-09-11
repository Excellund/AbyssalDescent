extends SceneTree
## Real controller geometry, room adaptation, lifecycle and replica boundaries.
## Run only through the disposable gameplay regression helper.

const RULES := preload("res://scripts/core/biome_rule_controller.gd")
const BIOMES := preload("res://scripts/shared/biome_registry.gd")
const LAYOUTS := preload("res://scripts/shared/arena_layout_registry.gd")
const DEFINITIONS := preload("res://scripts/shared/encounter_definition_data.gd")
const ROOM_SIZE := Vector2(1040.0, 760.0)
const SAFETY_RADIUS := 14.0
const SAFETY_GRID := 32.0
const BASTION_WALK_SPEED := 188.0
const WARNING_SECONDS := 1.4
const SHAPE_KINDS := {"crumble": "circle", "haunt": "circle", "grinding_vault": "annulus", "storm_reach": "circle", "hollow": "rects", "void_breach": "rects", "the_maelstrom": "sector", "convergence_end": "rects"}

class Actor extends Node2D:
	var player_id: int = 1
	var health: int = 1000
	var body_radius: float = 12.0
	var hits: int = 0
	var slows: int = 0
	var last_context: Dictionary = {}
	var last_slow := Vector2.ZERO
	var local_owner := true

	func is_dead() -> bool:
		return health <= 0

	func take_damage(amount: int, context: Dictionary = {}) -> void:
		health -= amount
		hits += 1
		last_context = context.duplicate(true)

	func apply_external_slow(duration: float, multiplier: float) -> void:
		slows += 1
		last_slow = Vector2(duration, multiplier)

	func apply_slow(duration: float, multiplier: float) -> void:
		apply_external_slow(duration, multiplier)

	func _is_local_control_owner() -> bool:
		return local_owner

var checks := 0
var failures: Array[String] = []
var arena: Node2D

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Biome rule tests require disposable user data")
		quit(1)
		return
	arena = Node2D.new()
	root.add_child(arena)
	_test_geometry()
	_test_catalogue_lifecycle()
	_test_storm_baiting()
	_test_haunt_ownership()
	_test_snapshots()
	_test_compact_objective_clearance()
	_test_live_context_changes()
	_test_assistance_and_fragment_modes()
	_test_room_mode_snapshots()
	_test_walking_escape_matrix()
	arena.free()
	await process_frame
	print("[OK] Biome rules: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _actor(at: Vector2 = Vector2.ZERO, id: int = 1) -> Actor:
	var actor := Actor.new()
	arena.add_child(actor)
	actor.position = at
	actor.player_id = id
	return actor

func _config(id: String) -> Dictionary:
	var generator := RandomNumberGenerator.new()
	generator.seed = 421
	return {"id": id, "obstacles": LAYOUTS.pick_layout("Crossfire", ROOM_SIZE, generator, id), "warning_time": 1.4, "active_time": 0.65 if id != "haunt" else 3.0, "recovery_time": 2.5, "player_damage": 7, "enemy_damage": 31, "slow_mult": 0.6}

func _controller(id: String, room_id: int = 7, run_token: String = "fixture-biome-run") -> RULES:
	var controller := RULES.new()
	arena.add_child(controller)
	controller.initialize(arena)
	controller.configure(_config(id), ROOM_SIZE, run_token, room_id, 421)
	return controller

func _adapted_controller(id: String, mode: String = "compact", fragments: bool = false, bounds: Vector2 = Vector2(720, 540), exclusions: Array[Dictionary] = [], obstacles: Array[Dictionary] = []) -> RULES:
	var controller := RULES.new()
	arena.add_child(controller)
	controller.initialize(arena)
	var config := _config(id)
	config["mode"] = mode
	config["shatter_fragments"] = fragments
	config["obstacles"] = obstacles.duplicate(true)
	# Use the production pacing defaults for the new room modes.
	for key in ["warning_time", "active_time", "recovery_time"]:
		config.erase(key)
	controller.configure(config, bounds, "adapted-biome-run", 9, 0)
	controller.set_room_context(bounds, exclusions, true)
	return controller

func _objective_contains(exclusion: Dictionary, point: Vector2) -> bool:
	if String(exclusion.kind) == "capsule":
		return point.distance_to(Geometry2D.get_closest_point_to_segment(point, exclusion.start, exclusion.end)) <= float(exclusion.radius)
	return point.distance_to(exclusion.center) <= float(exclusion.radius)

func _affected_floor_samples(geometry: Dictionary) -> int:
	var count := 0
	for x in range(-350, 351, 10):
		for y in range(-260, 261, 10):
			if RULES.geometry_contains(geometry, Vector2(x, y)):
				count += 1
	return count

func _test_compact_objective_clearance() -> void:
	var exclusions: Array[Dictionary] = [
		{"kind": "circle", "center": Vector2(-90, 0), "radius": 24.0},
		{"kind": "capsule", "start": Vector2(50, -130), "end": Vector2(180, -130), "radius": 20.0}
	]
	var obstacles: Array[Dictionary] = [{"pos": Vector2(-250, 130), "radius": 32.0}]
	var player := _actor(Vector2(-250, 130))
	for id: String in BIOMES.BIOME_DEFINITIONS:
		var controller := _adapted_controller(id, "compact", id == "shatterfield", Vector2(720, 540), exclusions, obstacles)
		check(controller.phase_left >= 5.0, "Compact room has its slower recovery pacing: " + id)
		var warning := _advance_to(controller, "warning", [player])
		check(warning.mode == "compact" and warning.bounds_size == Vector2(720, 540), "Room with available floor keeps its compact mode and effective bounds: " + id)
		check(float(warning.duration) >= 1.8 and is_equal_approx(float(warning.left), float(warning.duration)), "A compact event starts with its complete longer warning: " + id)
		var geometry: Dictionary = warning.shape
		var protected_samples := 0
		var intrusions := 0
		var cover_intrusions := 0
		for x in range(-340, 341, 8):
			for y in range(-250, 251, 8):
				var point := Vector2(x, y)
				if point.distance_to(obstacles[0].pos) <= float(obstacles[0].radius) and RULES.geometry_contains(geometry, point, SAFETY_RADIUS):
					cover_intrusions += 1
				if not exclusions.any(func(exclusion: Dictionary) -> bool: return _objective_contains(exclusion, point)):
					continue
				protected_samples += 1
				if RULES.geometry_contains(geometry, point, SAFETY_RADIUS):
					intrusions += 1
		check(protected_samples > 100 and intrusions == 0, "Circular and capsule objective footprints protect a real player-sized body: " + id)
		check(cover_intrusions == 0, "Compact placement leaves solid cover and its body clearance outside the hazard: " + id)
		check(not geometry.is_empty() and not RULES.geometry_contains(geometry, Vector2(500, 0)), "Compact warning remains inside the smaller room: " + id)
		if id != "shatterfield":
			var ordinary := _adapted_controller(id, "ordinary")
			var ordinary_warning := _advance_to(ordinary, "warning", [player])
			var compact_samples := _affected_floor_samples(geometry)
			check(compact_samples > 0 and compact_samples < _affected_floor_samples(ordinary_warning.shape), "Compact mode affects less floor than the same biome's ordinary pattern: " + id)
			ordinary.free()
		controller.free()
	player.free()

func _test_live_context_changes() -> void:
	var player := _actor(Vector2(-240, -140))
	var enemy := _actor(player.position, 0)
	var controller := _adapted_controller("storm_reach")
	var warning := _advance_to(controller, "warning", [player], [enemy])
	controller.tick(0.8, true, [player], [enemy], true)
	controller.set_room_context(Vector2(400, 300), [], true)
	check(controller.phase == "recovery" and controller.shape.is_empty(), "Shrinking bounds cancel a warned location that no longer fits")
	check(player.hits == 0 and enemy.hits == 0, "Invalidating a warning causes no unadvertised impact")
	var replacement := _advance_to(controller, "warning", [player], [enemy])
	check(int(replacement.event) > int(warning.event) and float(replacement.left) >= 1.8 and replacement.left == replacement.duration, "A replacement after shrinking receives a new event and complete warning")
	check(replacement.bounds_size == Vector2(400, 300) and (replacement.shape as Dictionary).bounds == Rect2(-200, -150, 400, 300), "Replacement warning and collision share the live smaller bounds")
	var contact := _inside_point(replacement.shape)
	player.position = contact
	enemy.position = contact
	_advance_to(controller, "active", [player], [enemy])
	var player_hits := player.hits
	var enemy_hits := enemy.hits
	var exclusion: Array[Dictionary] = [{"kind": "circle", "center": contact, "radius": 28.0}]
	controller.set_room_context(Vector2(400, 300), exclusion, true)
	check(controller.phase == "recovery" and controller.shape.is_empty(), "A newly required objective footprint cancels an overlapping active pattern")
	controller.tick(0.1, true, [player], [enemy], true)
	check(player.hits == player_hits and enemy.hits == enemy_hits, "Cancelled active geometry cannot keep damaging its former footprint")
	var next_warning := _advance_to(controller, "warning", [player], [enemy])
	check(next_warning.left == next_warning.duration and float(next_warning.left) >= 1.8, "Replanning after an active exclusion change gives the entire warning again")
	var held := controller.snapshot()
	controller.tick(100.0, false, [player], [enemy], true)
	check(controller.snapshot() == held, "Pause or room survey holds the adapted warning and its remaining time")
	controller.reset()
	controller.tick(100.0, true, [player], [enemy], true)
	check(controller.shape.is_empty() and controller.phase == "idle", "Room or death cleanup retires the adapted rule permanently")
	controller.free()
	player.free()
	enemy.free()

func _test_assistance_and_fragment_modes() -> void:
	var player := _actor()
	var remote := _actor(Vector2.ZERO, 2)
	remote.local_owner = false
	var enemy := _actor(Vector2.ZERO, 0)
	var blocked: Array[Dictionary] = [{"kind": "circle", "center": Vector2.ZERO, "radius": 1000.0}]
	var controller := _adapted_controller("storm_reach", "compact", false, Vector2(640, 480), blocked)
	var warning := _advance_to(controller, "warning", [player, remote], [enemy])
	check(warning.mode == "assistance" and RULES.geometry_contains(warning.shape, enemy.position), "No safe hazard candidate promotes to a warned assistance event targeting a living foe")
	controller.set_room_context(Vector2(640, 480), [], true)
	check(controller.snapshot().mode == "assistance", "Removing the exclusion does not turn assistance back into player danger mid-room")
	_advance_to(controller, "active", [player, remote, player], [enemy, enemy])
	check(player.hits == 0 and remote.hits == 0 and enemy.hits == 1 and enemy.health == 969, "Assistance damages the foe once while overlapping players remain unharmed")
	check(enemy.last_context.get("ability") == "biome_storm_reach" and (enemy.last_context.get("interaction", {}) as Dictionary).is_empty(), "Assistance keeps environmental attribution without creating a player power root")
	controller.free()
	var haunt := _adapted_controller("haunt", "assistance")
	warning = _advance_to(haunt, "warning", [player, remote], [enemy])
	var patch := _inside_point(warning.shape)
	for actor: Actor in [player, remote, enemy]:
		actor.position = patch
	_advance_to(haunt, "active", [player, remote], [enemy])
	haunt.tick(0.01, true, [player, remote], [enemy], true)
	check(player.slows == 0 and remote.slows == 0 and enemy.slows > 0, "Haunt assistance affects enemy movement and neither player's movement ownership")
	var replica := _adapted_controller("haunt", "assistance")
	check(replica.apply_snapshot(haunt.snapshot()), "An assistance replica accepts the host's live patch")
	var enemy_slows := enemy.slows
	replica.tick(0.1, true, [player, remote], [enemy], false)
	check(player.slows == 0 and remote.slows == 0 and enemy.slows == enemy_slows, "Assistance replica cannot Slow a local owner or simulate enemy status")
	replica.free()
	haunt.free()
	for id: String in ["crumble", "shatterfield", "grinding_vault", "hollow", "void_breach", "the_maelstrom", "convergence_end"]:
		var assistance := _adapted_controller(id, "assistance", id == "shatterfield")
		for actor: Actor in [player, remote, enemy]:
			actor.position = Vector2.ZERO
		enemy.health = 1000
		enemy.hits = 0
		warning = _advance_to(assistance, "warning", [player, remote], [enemy])
		check(RULES.geometry_contains(warning.shape, enemy.position) and enemy.hits == 0, "Assistance aims the damaging portion of its native shape at the foe before impact: " + id)
		_advance_to(assistance, "active", [player, remote], [enemy])
		check(enemy.hits == 1 and enemy.health == 969 and player.hits == 0 and remote.hits == 0, "Native assistance geometry damages only the overlapping foe: " + id)
		assistance.free()
	var fragments := _adapted_controller("shatterfield", "ordinary", true)
	warning = _advance_to(fragments, "warning", [player], [enemy])
	check(warning.fragments and warning.shape.kind == "circle" and float(warning.shape.radius) == 60.0 and float(warning.duration) >= 1.8, "Cover-free Shatterfield entry provides its own fully warned fragment circle")
	fragments.free()
	var cover_rule := _adapted_controller("shatterfield", "ordinary", false)
	cover_rule.set_room_context(Vector2(640, 480), [], true)
	cover_rule.tick(100.0, true, [player], [enemy], true)
	check(not cover_rule.snapshot().fragments and cover_rule.phase == "idle" and cover_rule.shape.is_empty(), "Later room geometry changes cannot enable an extra hazard in a cover-driven Shatterfield")
	cover_rule.free()
	player.free()
	remote.free()
	enemy.free()

func _test_room_mode_snapshots() -> void:
	var actor := _actor(Vector2(-160, 100))
	var host := _adapted_controller("storm_reach")
	var replica := _adapted_controller("storm_reach")
	var warning := _advance_to(host, "warning", [actor])
	check(replica.apply_snapshot(warning), "A compact warning transports its mode, fragment policy and bounds")
	var accepted := replica.snapshot()
	var invalid: Array[Dictionary] = [{"mode": "unsafe"}, {"mode": "ordinary"}, {"fragments": true}, {"fragments": 1}, {"bounds_size": Vector2(721, 540)}, {"bounds_size": Vector2(100, 100)}, {"bounds_size": Vector2(NAN, 540)}, {"bounds_size": "720x540"}]
	for alteration: Dictionary in invalid:
		var candidate := warning.duplicate(true)
		candidate.merge(alteration, true)
		candidate.revision = int(warning.revision) + 100
		check(not replica.apply_snapshot(candidate) and replica.snapshot() == accepted, "Malformed or incompatible room-mode data is rejected atomically: " + str(alteration))
	var blocked: Array[Dictionary] = [{"kind": "circle", "center": Vector2.ZERO, "radius": 1000.0}]
	host.set_room_context(Vector2(720, 540), blocked, true)
	var assistance := _advance_to(host, "warning", [actor], [actor])
	check(assistance.mode == "assistance" and replica.apply_snapshot(assistance), "An authoritative compact-to-assistance promotion reaches an existing replica")
	accepted = replica.snapshot()
	var downgrade := assistance.duplicate(true)
	downgrade.mode = "compact"
	downgrade.revision = int(assistance.revision) + 1
	check(not replica.apply_snapshot(downgrade) and replica.snapshot() == accepted, "Later packets cannot downgrade safe assistance to a player hazard")
	host.free()
	replica.free()
	var ordinary := _controller("storm_reach")
	var old_replica := _controller("storm_reach")
	var legacy := _advance_to(ordinary, "warning", [actor])
	for key in ["mode", "fragments", "bounds_size"]:
		legacy.erase(key)
	check(old_replica.apply_snapshot(legacy), "Existing ordinary non-fragment snapshots remain compatible")
	ordinary.free()
	old_replica.free()
	actor.free()

func _advance_to(controller: RULES, phase: String, players: Array = [], enemies: Array = []) -> Dictionary:
	for _step in range(8):
		var current := controller.snapshot()
		if String(current.get("phase", "")) == phase:
			return current
		controller.tick(10.0, true, players, enemies, true)
	check(false, "Controller reaches " + phase + " without an unbounded wait")
	return controller.snapshot()

func _inside_point(shape: Dictionary) -> Vector2:
	for x in range(-480, 481, 20):
		for y in range(-340, 341, 20):
			var point := Vector2(x, y)
			if RULES.geometry_contains(shape, point):
				return point
	check(false, "Generated rule has a reachable affected point")
	return Vector2.ZERO

func _test_geometry() -> void:
	var bounds := Rect2(-ROOM_SIZE * 0.5, ROOM_SIZE)
	var circle := {"kind": "circle", "center": Vector2(80, -30), "radius": 50.0, "bounds": bounds}
	check(RULES.geometry_contains(circle, Vector2(80, -30)), "Circle contains its committed center")
	check(not RULES.geometry_contains(circle, Vector2(141, -30)), "Circle excludes a point beyond its radius")
	check(RULES.geometry_contains(circle, Vector2(134, -30), 5.0), "Circle considers the actor's collision radius")
	var annulus := {"kind": "annulus", "center": Vector2.ZERO, "inner": 50.0, "outer": 110.0, "bounds": bounds}
	check(not RULES.geometry_contains(annulus, Vector2(20, 0)), "Annulus leaves its center safe")
	check(RULES.geometry_contains(annulus, Vector2(80, 0)), "Annulus includes the band between its radii")
	check(not RULES.geometry_contains(annulus, Vector2(125, 0)), "Annulus leaves the exterior safe")
	check(RULES.geometry_contains(annulus, Vector2(47, 0), 5.0), "Annulus detects an actor overlapping its inner edge")
	var strips := {"kind": "rects", "rects": [Rect2(-200, -30, 160, 60), Rect2(40, -30, 160, 60)], "bounds": bounds}
	check(RULES.geometry_contains(strips, Vector2(-100, 0)) and RULES.geometry_contains(strips, Vector2(100, 0)), "Paired strips include both hazardous segments")
	check(not RULES.geometry_contains(strips, Vector2.ZERO), "Paired strips preserve their authored escape gap")
	check(not RULES.geometry_contains(strips, Vector2(100, 45), 5.0), "A body outside a strip stays safe")
	var sector := {"kind": "sector", "center": Vector2.ZERO, "inner": 40.0, "outer": 160.0, "angle": 0.0, "half_angle": PI * 0.25, "bounds": bounds}
	check(RULES.geometry_contains(sector, Vector2(90, 0)), "Sector contains its facing direction")
	check(not RULES.geometry_contains(sector, Vector2(-90, 0)), "Opposite side of the rotating sector stays safe")
	check(not RULES.geometry_contains(sector, Vector2(0, 100)), "Sector excludes angles beyond its warning wedge")
	check(not RULES.geometry_contains(sector, Vector2.ZERO), "Sector's inner pocket stays safe")
	check(not RULES.geometry_contains({}, Vector2.ZERO), "Missing geometry cannot damage an actor")

func _test_catalogue_lifecycle() -> void:
	var player := _actor(Vector2(-110, 40))
	var enemy := _actor(Vector2(140, -60), 0)
	for id: String in BIOMES.BIOME_DEFINITIONS:
		var controller := _controller(id)
		var twin := _controller(id)
		var before := controller.snapshot()
		controller.tick(10.0, false, [player], [enemy], true)
		check(controller.snapshot() == before, "Survey/paused combat does not age the rule: " + id)
		if id == "shatterfield":
			controller.tick(100.0, true, [player], [enemy], true)
			check(String(controller.snapshot().get("phase", "")) == "idle" and (controller.snapshot().get("shape", {}) as Dictionary).is_empty(), "Shatterfield uses cover interactions without a timed hazard")
		else:
			controller.tick(100.0, true, [player], [enemy], true)
			twin.tick(100.0, true, [player], [enemy], true)
			var warning := controller.snapshot()
			check(String(warning.get("phase", "")) == "warning", "A long frame reaches a visible warning without skipping it: " + id)
			check(player.hits == 0 and enemy.hits == 0 and player.slows == 0 and enemy.slows == 0, "Warnings cause no damage or Slow: " + id)
			var shape: Dictionary = warning.get("shape", {})
			check(String(shape.get("kind", "")) == String(SHAPE_KINDS[id]), "Rule uses its declared shape family: " + id)
			check(shape == twin.snapshot().get("shape", {}), "Equal configuration, seed and actors yield the same warning: " + id)
			_inside_point(shape)
			var safe_points := 0
			for point: Vector2 in [Vector2(-440, -300), Vector2(440, -300), Vector2(-440, 300), Vector2(440, 300), Vector2.ZERO]:
				if not RULES.geometry_contains(shape, point, 12.0):
					safe_points += 1
			check(safe_points > 0, "The ordinary room retains an escape position: " + id)
			controller.tick(0.2, true, [player], [enemy], false)
			check(int(controller.snapshot().get("revision", -1)) == int(warning.get("revision", -2)) and player.hits == 0 and enemy.hits == 0, "Visual replica advancement cannot create authoritative events: " + id)
		controller.reset()
		var cleared := controller.snapshot()
		check(String(cleared.get("phase", "")) == "idle" and (cleared.get("shape", {}) as Dictionary).is_empty(), "Reset removes every pending warning and active shape: " + id)
		controller.tick(100.0, true, [player], [enemy], true)
		check((controller.snapshot().get("shape", {}) as Dictionary).is_empty(), "A cleared room cannot spontaneously restart its old rule: " + id)
		controller.free()
		twin.free()
	player.free()
	enemy.free()

func _test_storm_baiting() -> void:
	var first := _actor(Vector2(-160, -40), 1)
	var second := _actor(Vector2(190, 80), 2)
	var dead := _actor(Vector2(-350, -200), 0)
	dead.health = 0
	var enemy := _actor(first.position, 0)
	var controller := _controller("storm_reach")
	# A zero seed starts the stable peer rotation at its first member.
	controller.configure(_config("storm_reach"), ROOM_SIZE, "fixture-biome-run", 7, 0)
	var warning := _advance_to(controller, "warning", [second, dead, first], [enemy])
	var shape: Dictionary = warning.get("shape", {})
	var committed: Vector2 = shape.get("center", Vector2.INF)
	check(committed.is_equal_approx(first.position), "Storm targets the first living peer in stable ID order")
	check(first.hits == 0 and enemy.hits == 0, "Baited lightning warns before dealing damage")
	first.position = Vector2(400, 300)
	var bystander := _actor(committed, 3)
	_advance_to(controller, "active", [second, dead, first, bystander, bystander], [enemy, enemy])
	controller.tick(0.01, true, [second, dead, first, bystander, bystander], [enemy, enemy], true)
	check((controller.snapshot().get("shape", {}) as Dictionary).get("center", Vector2.INF) == committed, "Lightning remains at the warned location after its target moves")
	check(first.hits == 0 and second.hits == 0 and dead.hits == 0, "Moving out of the strike escapes it and dead players are excluded")
	check(bystander.hits == 1 and enemy.hits == 1, "The committed strike hits each present player and enemy once despite duplicate references")
	check(bystander.health == 993 and enemy.health == 969, "Environmental player/enemy damage uses its explicit independent amounts")
	check((enemy.last_context.get("interaction", {}) as Dictionary).is_empty() and not enemy.last_context.has("damage_coefficient"), "Baited environmental damage does not manufacture a player power descriptor")
	for _step in range(8):
		controller.tick(0.01, true, [bystander], [enemy], true)
	check(bystander.hits == 1 and enemy.hits == 1, "Remaining in one lightning flash does not repeat its impact")
	var next_warning := _advance_to(controller, "warning", [second, first], [])
	check(int(next_warning.get("event", 0)) > int(warning.get("event", 0)), "A later storm warning has a new event identity")
	check((next_warning.get("shape", {}) as Dictionary).get("center", Vector2.INF) == second.position, "Successive storm warnings rotate between living peer IDs")
	controller.free()
	first.free()
	second.free()
	dead.free()
	enemy.free()
	bystander.free()

func _test_haunt_ownership() -> void:
	var owner := _actor()
	var remote := _actor(Vector2.ZERO, 2)
	remote.local_owner = false
	var enemy := _actor(Vector2.ZERO, 0)
	var dead := _actor(Vector2.ZERO, 3)
	dead.health = 0
	var controller := _controller("haunt")
	var warning := _advance_to(controller, "warning", [owner, remote, dead], [enemy])
	var patch := _inside_point(warning.get("shape", {}))
	for actor: Actor in [owner, remote, enemy, dead]:
		actor.position = patch
	_advance_to(controller, "active", [owner, remote, dead], [enemy])
	controller.tick(0.01, true, [owner, remote, dead], [enemy], true)
	check(owner.slows > 0 and enemy.slows > 0, "Haunt's active patch slows a local player and enemy using their native hooks")
	check(remote.slows == 0 and dead.slows == 0, "Haunt does not overwrite another peer's movement or slow dead actors")
	check(is_equal_approx(owner.last_slow.y, 0.6) and owner.last_slow.x > 0.0, "Haunt applies the authored temporary movement multiplier")
	check(owner.hits == 0 and enemy.hits == 0, "Haunt is a movement rule rather than an extra damage tick")
	var replica := _controller("haunt")
	check(replica.apply_snapshot(controller.snapshot()), "Haunt replica accepts the committed active patch")
	owner.slows = 0
	enemy.slows = 0
	replica.tick(0.01, true, [owner, remote], [enemy], false)
	check(owner.slows > 0 and remote.slows == 0 and enemy.slows == 0, "A replica applies only its own player's Slow and leaves enemy authority to the host")
	replica.tick(100.0, true, [owner], [], false)
	var expired_slows := owner.slows
	replica.tick(0.1, true, [owner], [], false)
	check(owner.slows == expired_slows, "Missing expiry packets cannot keep a replica Slow patch active forever")
	replica.free()
	controller.free()
	owner.free()
	remote.free()
	enemy.free()
	dead.free()

func _test_snapshots() -> void:
	var player := _actor(Vector2(100, -60))
	var host := _controller("storm_reach")
	var replica := _controller("storm_reach")
	var warning := _advance_to(host, "warning", [player])
	replica.apply_snapshot(warning)
	var accepted := replica.snapshot()
	check(accepted.get("shape", {}) == warning.get("shape", {}) and accepted.get("phase", "") == "warning" and accepted.get("event", -1) == warning.get("event", -2), "A replica receives the host's committed warning geometry and event")
	var defensive_copy := host.snapshot()
	(defensive_copy["shape"] as Dictionary)["radius"] = 9999.0
	check(host.snapshot().get("shape", {}) == warning.get("shape", {}), "Snapshot callers cannot mutate live hazard geometry")
	for key: String in ["run", "room", "id"]:
		var foreign := warning.duplicate(true)
		foreign["revision"] = int(warning.get("revision", 0)) + 100
		foreign[key] = 99 if key == "room" else "other-" + key
		replica.apply_snapshot(foreign)
		check(replica.snapshot() == accepted, "Replica rejects a foreign " + key + " even with a newer revision")
	for revision_offset in [0, -1]:
		var stale := warning.duplicate(true)
		stale["revision"] = int(warning.get("revision", 0)) + revision_offset
		stale["phase"] = "active"
		replica.apply_snapshot(stale)
		check(replica.snapshot() == accepted, "Duplicate or older snapshots cannot activate or rewind a warning: %d" % revision_offset)
	var previous_event := warning.duplicate(true)
	previous_event["revision"] = int(warning.get("revision", 0)) + 101
	previous_event["event"] = int(warning.get("event", 0)) - 1
	replica.apply_snapshot(previous_event)
	check(replica.snapshot() == accepted, "A newer revision cannot restore an earlier hazard event")
	var active := _advance_to(host, "active", [player])
	replica.apply_snapshot(active)
	check(replica.snapshot().get("phase", "") == "active", "New authoritative revisions advance the replica phase")
	var hits_before_visual := player.hits
	replica.tick(100.0, true, [player], [], false)
	check(player.hits == hits_before_visual, "A remote visual flash cannot deal duplicate authoritative damage")
	replica.configure(_config("storm_reach"), ROOM_SIZE, "fixture-biome-run", 8, 421)
	var next_room := replica.snapshot()
	replica.apply_snapshot(active)
	check(replica.snapshot() == next_room, "An old-room flash cannot enter a freshly configured room")
	var unconfigured := RULES.new()
	arena.add_child(unconfigured)
	unconfigured.initialize(arena)
	unconfigured.apply_snapshot(active)
	check(String(unconfigured.snapshot().get("phase", "")) == "idle" and (unconfigured.snapshot().get("shape", {}) as Dictionary).is_empty(), "Packets arriving before configuration cannot create hazards")
	host.free()
	replica.free()
	unconfigured.free()
	player.free()

func _test_walking_escape_matrix() -> void:
	# Multi-source shortest paths start at every safe grid point. Edges are
	# real straight walking segments against inflated circular cover, so a
	# path cannot use a corner cut or require a dash through an obstacle.
	var actor := _actor()
	var affected_samples := 0
	var longest_path := 0.0
	for bounds_size: Vector2 in [DEFINITIONS.INTRO_ROOM_SIZE, DEFINITIONS.POOL_ROOM_SIZE]:
		for id: String in SHAPE_KINDS:
			for orientation in range(8):
				var generator := RandomNumberGenerator.new()
				generator.seed = orientation
				var layout := LAYOUTS.pick_layout("Crossfire", bounds_size, generator, id)
				var config := _config(id)
				config["obstacles"] = layout
				var controller := RULES.new()
				arena.add_child(controller)
				controller.initialize(arena)
				controller.configure(config, bounds_size, "escape-matrix", 1, orientation)
				actor.position = Vector2.from_angle(float(orientation) * PI * 0.25) * (minf(bounds_size.x, bounds_size.y) * 0.5 - 115.0)
				controller.tick(100.0, true, [actor], [], true)
				var geometry: Dictionary = controller.snapshot().get("shape", {})
				if id == "convergence_end":
					var patches: Array = geometry.get("rects", [])
					var follows_gates := patches.size() == 2
					for index in mini(2, patches.size()):
						var post_index := (orientation % 2) * 4 + index * 2
						var gate_center: Vector2 = (layout[post_index].pos + layout[post_index + 1].pos) * 0.5
						follows_gates = follows_gates and (patches[index] as Rect2).get_center().distance_to(gate_center) <= 0.36
					check(follows_gates, "Convergence's two patches follow the actual opposite gate centers, including diagonal terrain: %s/orientation%d" % [bounds_size, orientation])
				var result := _walking_escape_result(geometry, bounds_size, layout)
				affected_samples += int(result.affected)
				longest_path = maxf(longest_path, float(result.longest))
				check(int(result.affected) > 0, "Escape matrix samples the affected floor: %s/%s/orientation%d" % [id, bounds_size, orientation])
				check((result.unreachable as Array).is_empty(), "Bastion can walk out within 1.4s at 188px/s with a 14px body and solid cover: %s/%s/orientation%d; blocked samples %s" % [id, bounds_size, orientation, result.unreachable])
				controller.free()
	actor.free()
	print("[ESCAPE] %d affected grid points; longest verified walking route %.1fpx of %.1fpx warning budget" % [affected_samples, longest_path, BASTION_WALK_SPEED * WARNING_SECONDS])

func _walking_escape_result(geometry: Dictionary, bounds_size: Vector2, layout: Array[Dictionary]) -> Dictionary:
	var half := bounds_size * 0.5 - Vector2.ONE * SAFETY_RADIUS
	var points := {}
	var distances := {}
	var affected: Array[Vector2i] = []
	var heap: Array[Vector3] = []
	for x in range(ceili(-half.x / SAFETY_GRID), floori(half.x / SAFETY_GRID) + 1):
		for y in range(ceili(-half.y / SAFETY_GRID), floori(half.y / SAFETY_GRID) + 1):
			var key := Vector2i(x, y)
			var point := Vector2(key) * SAFETY_GRID
			if not _walk_segment_clear(point, point, layout):
				continue
			points[key] = point
			if RULES.geometry_contains(geometry, point, SAFETY_RADIUS):
				affected.append(key)
				distances[key] = INF
			else:
				distances[key] = 0.0
				_heap_push(heap, Vector3(x, y, 0.0))
	var budget := BASTION_WALK_SPEED * WARNING_SECONDS
	while not heap.is_empty():
		var item := _heap_pop(heap)
		var key := Vector2i(int(item.x), int(item.y))
		if item.z > float(distances[key]) + 0.001 or item.z > budget:
			continue
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var neighbor := key + Vector2i(dx, dy)
				if not points.has(neighbor):
					continue
				var distance := float(item.z) + Vector2(dx, dy).length() * SAFETY_GRID
				if distance > budget or distance >= float(distances[neighbor]) or not _walk_segment_clear(points[key], points[neighbor], layout):
					continue
				distances[neighbor] = distance
				_heap_push(heap, Vector3(neighbor.x, neighbor.y, distance))
	var unreachable: Array[Vector2] = []
	var longest := 0.0
	for key: Vector2i in affected:
		if not is_finite(float(distances[key])):
			if unreachable.size() < 8:
				unreachable.append(points[key])
		else:
			longest = maxf(longest, float(distances[key]))
	return {"affected": affected.size(), "unreachable": unreachable, "longest": longest}

func _walk_segment_clear(first: Vector2, second: Vector2, layout: Array[Dictionary]) -> bool:
	for obstacle: Dictionary in layout:
		var nearest := Geometry2D.get_closest_point_to_segment(obstacle.pos, first, second)
		if nearest.distance_to(obstacle.pos) < float(obstacle.get("radius", 28.0)) + SAFETY_RADIUS:
			return false
	return true

func _heap_push(heap: Array[Vector3], item: Vector3) -> void:
	heap.append(item)
	var index := heap.size() - 1
	while index > 0:
		var parent_index := (index - 1) >> 1
		if heap[parent_index].z <= item.z:
			break
		heap[index] = heap[parent_index]
		index = parent_index
		heap[index] = item

func _heap_pop(heap: Array[Vector3]) -> Vector3:
	var first := heap[0]
	var last: Vector3 = heap.pop_back()
	if heap.is_empty():
		return first
	heap[0] = last
	var index := 0
	while index * 2 + 1 < heap.size():
		var child := index * 2 + 1
		if child + 1 < heap.size() and heap[child + 1].z < heap[child].z:
			child += 1
		if heap[child].z >= last.z:
			break
		heap[index] = heap[child]
		index = child
		heap[index] = last
	return first

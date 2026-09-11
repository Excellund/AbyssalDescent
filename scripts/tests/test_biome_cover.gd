extends "res://scripts/tests/test_archer_projectiles.gd"
## Native obstacle bodies must change movement and real arrow outcomes.
const BIOMES := preload("res://scripts/shared/biome_registry.gd")
const LAYOUTS := preload("res://scripts/shared/arena_layout_registry.gd")

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		quit(1)
		return
	var generator := RandomNumberGenerator.new()
	for biome_id: String in BIOMES.BIOME_DEFINITIONS:
		var labels: Array = LAYOUTS.BIOME_TERRAIN_ENCOUNTERS if biome_id == "shatterfield" else ["Crossfire"]
		for label: String in labels:
			for seed_value in [7, 31]:
				await _test_cover_case(biome_id, label, seed_value, generator)
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Biome cover: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_cover_case(biome_id: String, label: String, seed_value: int, generator: RandomNumberGenerator) -> void:
	_spawn_archer()
	generator.seed = seed_value
	var layout := LAYOUTS.pick_layout(label, Vector2(1040, 760), generator, biome_id)
	var case_name := "%s/%s/seed%d" % [biome_id, label, seed_value]
	room._spawn_room_obstacles(layout)
	if biome_id == "shatterfield":
		_check(room._arena_cover.has_brittle_cover() and room._arena_cover.contacts_left(2) == 3 and room._arena_cover.contacts_left(3) == 3, "Ordinary Shatterfield room creates both cracked columns: " + case_name)
		_check(room._arena_cover.contacts_left(1) == -1 and room._arena_cover.contacts_left(4) == -1, "Outer Shatterfield cover stays permanent: " + case_name)
	var origin: Vector2 = Vector2.ZERO if layout.is_empty() else layout[0].pos
	actor.global_position = origin + Vector2(100, 0)
	shooter.global_position = origin - Vector2(100, 0)
	await _settle()
	_shot(shooter.global_position)
	shooter._process_projectiles(1.0)
	_check(shooter.projectiles.is_empty(), "Real arrow resolves its first contact in " + case_name)
	_check(actor.get_current_health() == (86 if layout.is_empty() else 100), "Biome cover changes accepted arrow damage in " + case_name)
	if not layout.is_empty():
		var collision := actor.move_and_collide(Vector2(-160, 0))
		_check(collision != null and room._active_obstacle_nodes.has(collision.get_collider()), "Authored terrain blocks actual player movement in " + case_name)
		_check(actor.global_position.x > origin.x + float(layout[0].radius), "Player stops outside the physical cover in " + case_name)
		actor.global_position = origin + Vector2(100, 0)
		room._clear_room_obstacles()
		await _settle()
		_shot(shooter.global_position)
		shooter._process_projectiles(1.0)
		_check(actor.get_current_health() == 86, "Clearing a biome room removes its arrow cover in " + case_name)
	await _finish_case()

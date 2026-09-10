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
		for seed_value in [7, 31]:
			_spawn_archer()
			generator.seed = seed_value
			var layout := LAYOUTS.pick_layout("Crossfire", Vector2(1040, 760), generator, biome_id)
			room._spawn_room_obstacles(layout)
			var origin: Vector2 = Vector2.ZERO if layout.is_empty() else layout[0].pos
			actor.global_position = origin + Vector2(100, 0)
			shooter.global_position = origin - Vector2(100, 0)
			await _settle()
			_shot(shooter.global_position)
			shooter._process_projectiles(1.0)
			_check(shooter.projectiles.is_empty(), "Real arrow resolves its first contact in " + biome_id)
			_check(actor.get_current_health() == (86 if layout.is_empty() else 100), "Biome cover changes accepted arrow damage in " + biome_id)
			if not layout.is_empty():
				var collision := actor.move_and_collide(Vector2(-160, 0))
				_check(collision != null and room._active_obstacle_nodes.has(collision.get_collider()), "Authored terrain blocks actual player movement in " + biome_id)
				_check(actor.global_position.x > origin.x + float(layout[0].radius), "Player stops outside the physical cover in " + biome_id)
				actor.global_position = origin + Vector2(100, 0)
				room._clear_room_obstacles()
				await _settle()
				_shot(shooter.global_position)
				shooter._process_projectiles(1.0)
				_check(actor.get_current_health() == 86, "Clearing a biome room removes its arrow cover in " + biome_id)
			await _finish_case()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	print("[OK] Biome cover: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

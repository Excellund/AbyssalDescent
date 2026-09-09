extends SceneTree

const FEEDBACK := preload("res://scripts/player_feedback.gd")

var checks := 0
var failures := 0

class Owner extends Node2D:
	var local := true

	func _is_local_control_owner() -> bool:
		return local

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var actor := Owner.new()
	root.add_child(actor)
	var feedback := FEEDBACK.new()
	actor.add_child(feedback)
	feedback.setup(100, 100)
	check(feedback.damage_flash_rect != null, "Local setup creates the screen layer")
	var original_layer := feedback.damage_flash_layer
	feedback._create_damage_flash()
	check(feedback.damage_flash_layer == original_layer, "Screen layer creation is idempotent")
	feedback.play_damage_flash()
	check(is_equal_approx(feedback.damage_flash_rect.modulate.a, 0.45), "Solo light flash keeps its existing strength")
	feedback.play_impact_medium(Vector2(10, 20))
	check(is_equal_approx(feedback.damage_flash_rect.modulate.a, 0.495), "Solo medium flash keeps its existing strength")
	feedback.play_impact_heavy(Vector2(10, 20))
	check(is_equal_approx(feedback.damage_flash_rect.modulate.a, 0.585), "Solo heavy flash keeps its existing strength")
	actor.local = false
	feedback._process(0.0)
	check(feedback.damage_flash_rect == null and not original_layer.visible, "Losing ownership clears an active flash immediately on the next frame")
	feedback.play_damage_flash()
	feedback.play_impact_medium(Vector2(10, 20))
	feedback.play_impact_heavy(Vector2(10, 20))
	check(feedback.damage_flash_layer == null, "Remote impact methods cannot create a screen layer")
	check(feedback.get_children().any(func(child): return child is Line2D), "Remote impacts still create world rings")
	actor.local = true
	feedback.play_damage_flash()
	check(feedback.damage_flash_rect != null and is_equal_approx(feedback.damage_flash_rect.modulate.a, 0.45), "A reassigned local owner lazily creates its flash")
	actor.queue_free()
	await process_frame
	var remote_actor := Owner.new()
	remote_actor.local = false
	root.add_child(remote_actor)
	var remote_feedback := FEEDBACK.new()
	remote_actor.add_child(remote_feedback)
	remote_feedback.setup(100, 100)
	check(remote_feedback.damage_flash_layer == null, "Remote setup allocates no fullscreen layer")
	remote_actor.local = true
	remote_feedback.play_impact_heavy(Vector2.ZERO)
	check(remote_feedback.damage_flash_rect != null and is_equal_approx(remote_feedback.damage_flash_rect.modulate.a, 0.585), "Initially remote setup can become a local owner without repeating setup")
	remote_actor.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	print("[OK] Player feedback ownership: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

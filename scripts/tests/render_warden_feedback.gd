extends "res://scripts/tests/render_character_identity.gd"
## Actual actors, status, accepted attacks and the normal arena camera fit.
const DAMAGE := preload("res://scripts/shared/damageable.gd")
const INTERACTIONS := preload("res://scripts/shared/combat_interaction_registry.gd")

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or not DirAccess.dir_exists_absolute("res://validation_fixtures") or DisplayServer.get_name() == "headless":
		push_error("Warden GPU fixture requires an isolated real renderer")
		quit(1)
		return
	node_added.connect(retirement.observe_node)
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	output_directory = ProjectSettings.globalize_path("res://warden_feedback_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	_setup()
	party.append(actor)
	renderer = RENDERER.new()
	room.add_child(renderer)
	renderer.set_process(false)
	camera = CAMERA.new()
	room.add_child(camera)
	camera.set_static_mode(Vector2.ZERO)
	camera.set_physics_process(false)
	_set_room_size(DEFINITIONS.POOL_ROOM_SIZE)
	var layer := CanvasLayer.new()
	room.add_child(layer)
	heading = Label.new()
	heading.position = Vector2(32, 20)
	heading.add_theme_font_size_override("font_size", 23)
	layer.add_child(heading)
	caption = Label.new()
	caption.position = Vector2(32, 52)
	caption.add_theme_font_size_override("font_size", 16)
	layer.add_child(caption)
	actor.position = Vector2(-50, 100)
	actor.apply_upgrade("wardens_verdict")
	actor.apply_trial_power("static_wake")
	actor.apply_trial_power("dread_resonance")
	actor.apply_trial_power("wraithstep")
	actor.static_wake_controller.renderer.set_process(false)
	var marked := _visible_enemy(Vector2(-145, -100))
	var unmarked := _visible_enemy(Vector2(-260, -100))
	var dread := _visible_enemy(Vector2(-20, -100))
	var large := preload("res://scripts/enemy_boss.gd").new()
	_circle(large, 34)
	room.add_child(large)
	large.set_physics_process(false)
	large.position = Vector2(140, -100)
	large.target = actor
	var mark_action := actor.new_combat_action("dash")
	for target in [marked, dread, large]:
		DAMAGE.apply_mark(target, "wraithstep", .15, 3.0, 1, mark_action)
	for index in range(8):
		DAMAGE.add_dread_stack(dread, 1, 8, actor.new_combat_action("melee"))
	_label(unmarked, "UNMARKED")
	_label(marked, "MARKED")
	_label(dread, "MARKED + DREAD")
	_label(large, "BOSS MARK")
	_make_ribbon(actor, Vector2(-350, -110), Vector2(230, -110))
	_make_electric_warnings()
	await _capture("marked_targets", "MARK / SHARED VULNERABILITY", "Open violet diamonds stay outside enemy bodies. Dread strengthens the same symbol; Wake and warnings remain distinct.")
	var primary := _visible_enemy(Vector2(15, 100))
	var nearby := _visible_enemy(Vector2(75, 125))
	var outside := _visible_enemy(Vector2(155, 125))
	actor.reward_dread_resonance = false
	for step in range(1, 5):
		actor._perform_melee_attack(Vector2.RIGHT, {"damage": 20, "range": 78.0, "arc_degrees": 130.0})
		var visual: Node = actor.player_feedback.warden_verdict
		_check(visual != null and visual.step == step, "Native accepted contact creates Warden visual " + str(step))
		visual.set_process(false)
		if step == 1:
			await _capture("first_contact", "WARDEN / FIRST CONTACT", "One accepted attack hit fills the first ivory slot. Brief contact brackets locate the hit.")
		if step == 3:
			visual.advance(0.27)
			await _capture("fourth_ready", "WARDEN / FOURTH CONTACT READY", "Three filled slots and the highlighted open fourth slot announce the next contact's Burst.")
		if step == 4:
			_check(not visual.bursts.is_empty() and visual.bursts.back().radius == actor._get_apex_predator_burst_radius(), "Native Burst visual has the exact damage radius")
			_check(nearby.accepted_sources.has("apex_predator_burst") and not outside.accepted_sources.has("apex_predator_burst"), "Actual fourth-contact damage matches the visible reach")
			visual.advance(0.055)
			await _capture("fourth_impact", "WARDEN / FOURTH CONTACT BURST", "The ivory seal expands inside an amber boundary showing the actual damage radius; no screen flash.")
			visual.advance(0.11)
			await _capture("fourth_release", "WARDEN / BURST RELEASE", "The Burst clears quickly and leaves the enemy warnings and persistent Mark shapes readable.")
	actor.player_feedback.warden_verdict.advance(3.0)
	await _capture("feedback_cleared", "WARDEN / AFTER THE BURST", "Transient contact and Burst shapes expire. Mark remains tied to its existing status duration.")
	actor.discard_pending_combat_input()
	EnemyReplicationService.unbind_world(room)
	current_scene = null
	room.free()
	party.clear()
	if is_instance_valid(MAPPER._power_registry_instance):
		MAPPER._power_registry_instance.free()
		MAPPER._power_registry_instance = null
	await process_frame
	_check(await retirement.wait_until_retired(self), "Native audio retires before renderer exit")
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify({"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "failures": failures}, "\t"))
	print("[OK] Warden feedback GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _label(target: Node2D, text: String) -> void:
	var label := Label.new()
	label.position = Vector2(-75, 55)
	label.size = Vector2(150, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	target.add_child(label)

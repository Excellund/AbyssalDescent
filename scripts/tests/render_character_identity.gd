extends "res://scripts/tests/test_live_arena_edges.gd"
## Real players and camera fit. Physics is staged only to hold visual poses.

const CAMERA := preload("res://scripts/player_camera.gd")
const RENDERER := preload("res://scripts/world_renderer.gd")
const CHARACTER := preload("res://scripts/character_registry.gd")
const DEFINITIONS := preload("res://scripts/shared/encounter_definition_data.gd")
const AUDIO_RETIREMENT := preload("res://scripts/tests/fixture_audio_retirement.gd")
const WAKE := preload("res://scripts/static_wake_controller.gd")
const FRAME_SIZE := Vector2i(1280, 720)
const IDS := ["bastion", "hexweaver", "veilstrider", "riftlancer"]

class VisibleEnemy extends "res://scripts/enemy_chaser.gd":
	var accepted_sources: Array[String] = []
	func _ready() -> void:
		max_health = 10000
		super._ready()
		set_physics_process(false)
	func take_damage(amount: int, context: Dictionary = {}) -> void:
		var before := get_current_health()
		super.take_damage(amount, context)
		if before > get_current_health():
			accepted_sources.append(String(context.get("attack_type", "")))

var party: Array[Actor] = []
var camera: CAMERA
var renderer: RENDERER
var heading: Label
var caption: Label
var frames: Array[Dictionary] = []
var output_directory: String
var retirement := AUDIO_RETIREMENT.new()

func _run() -> void:
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or not DirAccess.dir_exists_absolute("res://validation_fixtures") or DisplayServer.get_name() == "headless":
		push_error("Character GPU fixture requires an isolated real renderer")
		quit(1)
		return
	node_added.connect(retirement.observe_node)
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	output_directory = ProjectSettings.globalize_path("res://character_identity_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	_setup()
	party.append(actor)
	renderer = RENDERER.new()
	room.add_child(renderer)
	renderer.set_process(false) # Freeze background only for exact pixel comparisons.
	camera = CAMERA.new()
	room.add_child(camera)
	camera.set_static_mode(Vector2.ZERO)
	camera.set_physics_process(false)
	_set_room_size(DEFINITIONS.POOL_ROOM_SIZE)
	var layer := CanvasLayer.new()
	room.add_child(layer)
	heading = Label.new()
	heading.position = Vector2(32.0, 20.0)
	heading.add_theme_font_size_override("font_size", 23)
	layer.add_child(heading)
	caption = Label.new()
	caption.position = Vector2(32.0, 52.0)
	caption.add_theme_font_size_override("font_size", 16)
	layer.add_child(caption)
	_make_party()
	await _capture("pool_idle", "CHARACTER IDENTITY / IDLE", "Bastion, Hexweaver, Veilstrider and Riftlancer at the normal arena camera fit.")
	for member in party:
		member._try_execute_attack(member.aim)
		member.attack_anim_time_left = member.attack_anim_duration * 0.75
		_check(member.attack_cooldown_left > 0.0, "Actual attack starts for " + member.active_character_id)
	await _capture("pool_attack", "CHARACTER IDENTITY / ATTACK CONTRACTION", "Decorative poses move; the original damage shapes and facing remain separate.")
	for member in party:
		member.attack_anim_time_left = member.attack_anim_duration * 0.25
	await _capture("pool_release", "CHARACTER IDENTITY / ATTACK RELEASE", "Hexweaver's glyphs release outward while the other weapons complete their attack poses.")
	_make_party()
	Input.action_press("dash")
	for index in party.size():
		var member := party[index]
		member._try_start_dash(Vector2.RIGHT.rotated(float(index) * 0.45))
		member.velocity = member.dash_direction * member.dash_speed
		_check(member._is_dash_active(), "Actual dash starts for " + member.active_character_id)
	await _capture("pool_dash", "CHARACTER IDENTITY / DASH", "Compact shield, light glyphs, fine dash trails and a slender lance.")
	Input.action_release("dash")
	for character_id: String in IDS:
		_make_party(character_id)
		await _capture("party_" + character_id, character_id.to_upper() + " / FOUR PARTY VARIANTS", "Existing duplicate-character color variants keep the same recognizable outline.")
	await _wake_footprint_frames()
	await _electric_build_frame(false)
	await _electric_build_frame(true)
	_make_party()
	_set_room_size(DEFINITIONS.TRIAL_ROOM_SIZE)
	await _combat_frame()
	for member in party:
		member.discard_pending_combat_input()
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
	print("[OK] Character identity GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _set_room_size(size: Vector2) -> void:
	room.current_room_size = size
	room.current_effective_room_size = size
	renderer.room_size = size
	renderer.queue_redraw()
	camera.set_world_bounds(Rect2(-size * 0.5, size))
	camera.global_position = Vector2.ZERO
	camera.zoom = camera.target_zoom
	camera.force_update_scroll()

func _make_party(duplicate_character: String = "") -> void:
	for member in party:
		member.discard_pending_combat_input()
		member.free()
	party.clear()
	for index in IDS.size():
		var member := Actor.new()
		_circle(member, 14.0)
		room.add_child(member)
		# Each displayed actor uses the local control path to stage its own pose;
		# duplicate palettes below are real registry variants, not network peers.
		member.player_id = 1
		var id: String = duplicate_character if not duplicate_character.is_empty() else IDS[index]
		var package := CHARACTER.get_character(id)
		if not duplicate_character.is_empty():
			package = CHARACTER.apply_duplicate_color_variant(package, index)
		member.apply_character_package(package)
		member.global_position = Vector2(-285.0 + float(index) * 190.0, 0.0)
		member.aim = Vector2.RIGHT.rotated([-0.35, 0.65, -0.65, 0.35][index])
		member.visual_facing_direction = member.aim
		member.arcana_motion.set_process(false)
		member.returning_crescent.set_physics_process(false)
		member.boss_combinations.set_process(false)
		# Freeze presentation time for deterministic footprint comparisons below.
		member.static_wake_controller.renderer.set_process(false)
		var name_label := Label.new()
		name_label.position = Vector2(-70.0, 55.0)
		name_label.size = Vector2(140.0, 30.0)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.text = id.capitalize() + (" " + str(index + 1) if not duplicate_character.is_empty() else "")
		name_label.add_theme_font_size_override("font_size", 16)
		member.add_child(name_label)
		party.append(member)
	actor = party[0]
	room.player = actor

func _make_ribbon(member: Actor, start: Vector2, finish: Vector2) -> void:
	var wake: WAKE = member.static_wake_controller
	wake.begin_dash(member.new_combat_action("dash"))
	wake.append_segment(start, finish)
	wake.end_dash()

func _pixel_at(picture: Image, world_position: Vector2) -> Color:
	var screen := root.get_canvas_transform() * world_position
	return picture.get_pixel(int(round(screen.x)), int(round(screen.y)))

func _color_distance(first: Color, second: Color) -> float:
	return maxf(absf(first.r - second.r), maxf(absf(first.g - second.g), absf(first.b - second.b)))

func _wake_footprint_frames() -> void:
	_make_party()
	_set_room_size(DEFINITIONS.POOL_ROOM_SIZE)
	for member in party:
		member.visible = member == actor
	actor.position = Vector2(-145.0, 120.0)
	actor.apply_trial_power("static_wake")
	var wake: WAKE = actor.static_wake_controller
	var radius := actor.static_wake_trail_radius
	var start := Vector2(-220.0, 120.0)
	var finish := Vector2(100.0, 120.0)
	var baseline: Image = await _capture("wake_baseline", "ELECTRIC FOOTPRINT / BASELINE", "Pixel controls use the real arena at 0.90 zoom and freeze only background animation.")
	_make_ribbon(actor, start, finish)
	var single: Image = await _capture("wake_single", "ELECTRIC FOOTPRINT / ONE RIBBON", "The thin boundary is the actual capsule; actor artwork stays above the field.")
	var expected_bounds := Rect2(start, Vector2.ZERO).expand(finish).grow(radius)
	_check(wake.renderer.get_footprint_bounds().is_equal_approx(expected_bounds), "Wake renderer bounds equal its mapped damage capsule")
	_check(wake.renderer.z_index < actor.z_index, "Wake renders below actor layer")
	_check(_color_distance(_pixel_at(single, actor.position), _pixel_at(baseline, actor.position)) < 0.008, "Opaque actor center occludes Wake pixels")
	_make_ribbon(actor, start, finish)
	var overlap: Image = await _capture("wake_overlap", "ELECTRIC FOOTPRINT / TWO IDENTICAL RIBBONS", "The same owner's overlapping damage footprint has no extra fill or bright intersection.")
	var bounds_start := root.get_canvas_transform() * expected_bounds.position
	var bounds_end := root.get_canvas_transform() * expected_bounds.end
	var actor_screen := root.get_canvas_transform() * actor.position
	var maximum_difference := 0.0
	for x in range(int(ceil(bounds_start.x)), int(floor(bounds_end.x))):
		for y in range(int(ceil(bounds_start.y)), int(floor(bounds_end.y))):
			# The player's existing clock-driven status rim is intentionally animated.
			if Vector2(x, y).distance_to(actor_screen) < 40.0:
				continue
			maximum_difference = maxf(maximum_difference, _color_distance(single.get_pixel(x, y), overlap.get_pixel(x, y)))
	_check(maximum_difference <= 1.0 / 255.0, "Duplicate ribbon footprint is pixel-identical (maximum channel delta %.5f)" % maximum_difference)
	wake.tick(actor.static_wake_lifetime - 0.175)
	var faded: Image = await _capture("wake_fade", "ELECTRIC FOOTPRINT / FINAL 0.175 SECONDS", "Opacity fades while the damage radius and round endpoints stay fixed.")
	_check(wake.renderer.get_footprint_bounds().is_equal_approx(expected_bounds), "Fading does not shrink the damage capsule")
	for offset: Vector2 in [Vector2(0.0, radius - 2.0), Vector2(0.0, -radius + 2.0), Vector2(100.0 + radius - 2.0, 0.0)]:
		var point := Vector2(0.0, 120.0) + offset
		var full_delta := _color_distance(_pixel_at(single, point), _pixel_at(baseline, point))
		var fade_delta := _color_distance(_pixel_at(faded, point), _pixel_at(baseline, point))
		_check(full_delta > 0.025 and fade_delta > 0.008 and fade_delta < full_delta * 0.75, "Fade retains visible full-radius boundary at " + str(point))
	for point: Vector2 in [Vector2(0.0, 120.0 + radius + 3.0), Vector2(100.0 + radius + 3.0, 120.0)]:
		_check(_color_distance(_pixel_at(single, point), _pixel_at(baseline, point)) < 0.008 and _color_distance(_pixel_at(faded, point), _pixel_at(baseline, point)) < 0.008, "Wake has no fill beyond exact capsule at " + str(point))
	wake.cancel()
	_make_ribbon(actor, start, finish)
	_make_ribbon(actor, Vector2(0.0, 20.0), Vector2(0.0, 220.0))
	var crossed: Image = await _capture("wake_crossing", "ELECTRIC FOOTPRINT / CROSSING UNION", "Only the outside boundary remains; crossing paths add neither damage nor internal bright borders.")
	_check(_color_distance(_pixel_at(crossed, Vector2(0.0, 120.0)), _pixel_at(single, Vector2(0.0, 120.0))) < 0.008, "Crossing union center does not brighten")
	# Choose the brightest rasterized edge pixel in the analytic boundary's
	# two-pixel AA band instead of assuming the boundary lands on a pixel center.
	var former_edge := root.get_canvas_transform() * Vector2(0.0, 120.0 + radius)
	var edge_brightness := 0.0
	var union_brightness := 0.0
	for y in range(int(round(former_edge.y)) - 2, int(round(former_edge.y)) + 2):
		var x := int(round(former_edge.x))
		var brightness := _color_distance(single.get_pixel(x, y), baseline.get_pixel(x, y))
		if brightness > edge_brightness:
			edge_brightness = brightness
			union_brightness = _color_distance(crossed.get_pixel(x, y), baseline.get_pixel(x, y))
	_check(union_brightness < edge_brightness * 0.8, "Interior ribbon boundary disappears inside the union")
	wake.cancel()
	_make_ribbon(actor, start, finish)
	var previous := single
	for index in range(2):
		# Exercise the production animation clock, independently from damage time.
		wake.renderer._process(0.13)
		var animated: Image = await _capture("wake_static_" + str(index + 1), "ELECTRIC FOOTPRINT / LOCAL STATIC", "White-yellow forks crackle inside the fixed gold footprint; overlaps share the same static.")
		var changed_pixels := 0
		var bright_sparks := 0
		var inspected_pixels := 0
		for x in range(int(ceil(bounds_start.x)), int(floor(bounds_end.x))):
			for y in range(int(ceil(bounds_start.y)), int(floor(bounds_end.y))):
				if Vector2(x, y).distance_to(actor_screen) < 40.0:
					continue
				inspected_pixels += 1
				var pixel := animated.get_pixel(x, y)
				if _color_distance(pixel, previous.get_pixel(x, y)) > 0.08:
					changed_pixels += 1
				if pixel.r > 0.55 and pixel.g > 0.52 and pixel.r > pixel.b:
					bright_sparks += 1
		_check(changed_pixels > 20 and changed_pixels < inspected_pixels * 0.28, "Static moves locally without a whole-field flash: %d pixels" % changed_pixels)
		_check(bright_sparks > 20, "Static contains visible warm-white electrical filaments")
		_check(_color_distance(_pixel_at(animated, actor.position), _pixel_at(baseline, actor.position)) < 0.008, "Animated static stays below the actor")
		_check(wake.renderer.get_footprint_bounds().is_equal_approx(expected_bounds), "Animation does not change the damage footprint")
		for point: Vector2 in [Vector2(0.0, 120.0 + radius + 3.0), Vector2(100.0 + radius + 3.0, 120.0)]:
			_check(_color_distance(_pixel_at(animated, point), _pixel_at(baseline, point)) < 0.008, "Animated static stays inside the capsule at " + str(point))
		previous = animated
	wake.cancel()
	var cleared: Image = await _capture("wake_cleared", "ELECTRIC FOOTPRINT / CLEARED", "Leaving the room or canceling a field retires its footprint and all decorative static.")
	_check(_color_distance(_pixel_at(cleared, Vector2(0.0, 120.0)), _pixel_at(baseline, Vector2(0.0, 120.0))) < 0.008, "Cancel removes the ribbon and static")

func _visible_enemy(position: Vector2) -> VisibleEnemy:
	var enemy := VisibleEnemy.new()
	_circle(enemy, 13.0)
	room.add_child(enemy)
	enemy.position = position
	return enemy

func _electric_build_frame(show_party: bool) -> void:
	_make_party()
	_set_room_size(DEFINITIONS.TRIAL_ROOM_SIZE if show_party else DEFINITIONS.POOL_ROOM_SIZE)
	for index in party.size():
		party[index].visible = show_party or index == 0
		party[index].position = [Vector2(-235.0, -90.0), Vector2(25.0, -170.0), Vector2(130.0, 115.0), Vector2(295.0, 165.0)][index]
	actor.apply_trial_power("static_wake")
	actor.apply_trial_power("storm_crown")
	actor.apply_trial_power("storm_crown")
	actor.apply_trial_power("aegis_field")
	var targets: Array[VisibleEnemy] = []
	for position: Vector2 in [Vector2(-195.0, -45.0), Vector2(-70.0, 30.0), Vector2(55.0, -40.0), Vector2(175.0, 40.0), Vector2(305.0, -30.0)]:
		targets.append(_visible_enemy(position))
	# One real earlier strike supplies the first of Crown L2's two contacts.
	actor._perform_melee_attack((targets[0].position - actor.position).normalized(), {"damage": 20})
	_check(actor.storm_crown_hit_counter == 1, "Real strike prepares the first Crown contact")
	actor._trigger_aegis_field()
	_check(targets[0].is_slowed(), "Real Aegis supplies Slow before the Wake contact")
	_make_ribbon(actor, Vector2(-360.0, -45.0), targets[0].position)
	_check(actor.static_wake_controller.ribbons.size() == 1, "Mapped Wake creates one real ribbon")
	if show_party:
		party[1].apply_trial_power("static_wake")
		_make_ribbon(party[1], Vector2(-110.0, -170.0), Vector2(110.0, -170.0))
		party[2].apply_trial_power("razor_orbit")
		var anchor := _visible_enemy(Vector2(205.0, 115.0))
		Input.action_press("dash")
		party[2].arcana_motion.start_orbit(anchor)
		_check(party[2].arcana_motion.motion == MOTION.Motion.ORBIT, "Integrated party Orbit remains live")
		_make_electric_warnings()
	actor.static_wake_controller.tick(WAKE.TICK_INTERVAL)
	_check(actor.storm_crown_hit_counter == 2, "Wake damage supplies Crown's second Hit without another attack")
	var chain_hits := 0
	for target in get_nodes_in_group("enemies"):
		if target is VisibleEnemy:
			chain_hits += target.accepted_sources.count("storm_crown")
	_check(chain_hits == actor.storm_crown_chain_targets + 1, "Aegis Slow produces exactly one additional L2 Crown hop")
	_check(targets[0].accepted_sources.has("static_wake"), "The triggering hit is real Wake damage")
	await _capture("electric_party" if show_party else "electric_solo", "ELECTRIC BUILD / " + ("PARTY AND WARNINGS" if show_party else "SOLO"), "Real Wake damage feeds Crown; Aegis Slow grants the teal final hop. " + ("Orbit and hostile warnings retain their own shapes." if show_party else "The same controls connect three powers through Hit and Slow."))
	Input.action_release("dash")
	for enemy in get_nodes_in_group("enemies"):
		enemy.free()

func _make_electric_warnings() -> void:
	var charger := preload("res://scripts/enemy_charger.gd").new()
	_circle(charger, 14.0)
	room.add_child(charger)
	charger.set_physics_process(false)
	charger.position = Vector2(-305.0, 145.0)
	charger.target = actor
	charger._enter_windup_state()
	charger.charger_charge_direction = Vector2.RIGHT
	charger.visual_facing_direction = Vector2.RIGHT
	var drifter := preload("res://scripts/enemy_drifter.gd").new()
	_circle(drifter, 16.0)
	room.add_child(drifter)
	drifter.set_physics_process(false)
	drifter.position = Vector2(330.0, -155.0)
	drifter._emit_ring()
	drifter.rings[0]["radius"] = 125.0
	drifter.rings[0]["gap_index"] = 4
	drifter.queue_redraw()

func _combat_frame() -> void:
	for index in party.size():
		party[index].global_position = [Vector2(-80.0, -80.0), Vector2(115.0, -95.0), Vector2(-140.0, 110.0), Vector2(135.0, 115.0)][index]
	var anchor := VisibleEnemy.new()
	_circle(anchor, 13.0)
	room.add_child(anchor)
	anchor.position = Vector2(-10.0, -80.0)
	actor.apply_trial_power("razor_orbit")
	Input.action_press("dash")
	actor.arcana_motion.start_orbit(anchor)
	_check(actor.arcana_motion.motion == MOTION.Motion.ORBIT, "Real Orbit starts for crowded silhouette review")
	var charger := preload("res://scripts/enemy_charger.gd").new()
	_circle(charger, 14.0)
	room.add_child(charger)
	charger.set_physics_process(false)
	charger.global_position = Vector2(-340.0, 40.0)
	charger.target = actor
	charger._enter_windup_state()
	charger.charger_charge_direction = Vector2.RIGHT
	charger.visual_facing_direction = Vector2.RIGHT
	var drifter := preload("res://scripts/enemy_drifter.gd").new()
	_circle(drifter, 16.0)
	room.add_child(drifter)
	drifter.set_physics_process(false)
	drifter.global_position = Vector2(295.0, -110.0)
	drifter._emit_ring()
	drifter.rings[0]["radius"] = 170.0
	drifter.rings[0]["gap_index"] = 4
	drifter.queue_redraw()
	party[1].sigil_burst_ready = true
	party[2].veilstep_rhythm_surge_ready = true
	party[2].veilstep_rhythm_surge_window_left = 2.0
	party[3].farline_focus_ready = true
	await _capture("trial_combat", "CHARACTER IDENTITY / POWERS AND WARNINGS", "Actual Orbit, passive indicators, Charger warning and Drifter ring at the larger-room camera fit.")
	Input.action_release("dash")

func _mechanical_state(member: Actor) -> Dictionary:
	var collider := member.find_children("*", "CollisionShape2D", false, false)[0] as CollisionShape2D
	return {
		"snapshot": member.build_run_snapshot(), "position": member.global_position,
		"velocity": member.velocity, "facing": member.visual_facing_direction,
		"collision": (collider.shape as CircleShape2D).radius,
		"dash": [member.dash_remaining_distance, member._dash_damage_immune_left],
		"passives": [member.iron_retort_brace_ready, member.sigil_burst_ready, member.veilstep_rhythm_shards, member.farline_focus_ready]
	}

func _capture(name: String, title: String, explanation: String) -> Image:
	heading.text = title
	caption.text = explanation
	var before: Array[Dictionary] = []
	for member in party:
		before.append(_mechanical_state(member))
		member.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	for index in party.size():
		_check(before[index] == _mechanical_state(party[index]), "Drawing preserves mechanics for " + name + "/" + str(index))
	var picture := root.get_texture().get_image()
	var path := output_directory.path_join(name + ".png")
	_check(picture.save_png(path) == OK, "Saved " + name)
	frames.append({"name": name, "path": path, "zoom": camera.zoom.x, "room_size": room.current_effective_room_size})
	print("[FRAME] " + path)
	return picture

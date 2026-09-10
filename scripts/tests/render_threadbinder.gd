extends "res://scripts/tests/test_live_arena_edges.gd"
## Actual fifth-character drawing at ordinary solo and party camera fits.
## Run with render_gameplay_fixture.ps1 against an isolated validation copy.

const CAMERA := preload("res://scripts/player_camera.gd")
const RENDERER := preload("res://scripts/world_renderer.gd")
const CHARACTER := preload("res://scripts/character_registry.gd")
const DEFINITIONS := preload("res://scripts/shared/encounter_definition_data.gd")
const AUDIO_RETIREMENT := preload("res://scripts/tests/fixture_audio_retirement.gd")
const FRAME_SIZE := Vector2i(1280, 720)

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
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")) or not DirAccess.dir_exists_absolute("res://validation_fixtures"):
		push_error("Threadbinder GPU fixture requires isolated user data")
		quit(1)
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_video_adapter_name().is_empty():
		push_error("Threadbinder GPU fixture requires an actual GPU")
		quit(1)
		return
	node_added.connect(retirement.observe_node)
	root.size = FRAME_SIZE
	root.content_scale_size = FRAME_SIZE
	output_directory = ProjectSettings.globalize_path("res://threadbinder_frames")
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
	_set_room_size(DEFINITIONS.POOL_ROOM_SIZE)
	_make_party(["threadbinder"])
	await _capture("solo_idle", "THREADBINDER / IDLE", "Coral body, paired ivory shuttles and a thin thread loop at ordinary arena zoom.")
	actor.velocity = actor.aim * actor.max_speed
	await _capture("solo_moving", "THREADBINDER / MOVING", "The thread trails behind movement while the short shuttles preserve the round core.")
	actor.velocity = Vector2.ZERO
	actor._try_execute_attack(actor.aim)
	actor.attack_anim_time_left = actor.attack_anim_duration * 0.75
	_check(actor.attack_cooldown_left > 0.0, "The real Threadbinder Attack starts")
	await _capture("solo_attack", "THREADBINDER / ATTACK", "One shuttle reaches forward as the other draws back during the real Attack pose.")
	actor.attack_anim_time_left = actor.attack_anim_duration * 0.2
	await _capture("solo_release", "THREADBINDER / ATTACK RELEASE", "The shuttles return through the Attack animation without changing its damage shape.")
	_make_party(["threadbinder"])
	Input.action_press("dash")
	actor._try_start_dash(Vector2(-0.65, 0.75).normalized())
	actor.velocity = actor.dash_direction * actor.dash_speed
	_check(actor._is_dash_active(), "The real Threadbinder dash starts")
	await _capture("solo_dash", "THREADBINDER / DASH", "The thread follows the actual diagonal dash while the shuttles tuck toward the core.")
	Input.action_release("dash")
	_make_party(CHARACTER.get_launch_character_ids())
	_check(party.size() == 5, "The visual roster includes all five playable characters")
	await _capture("full_roster", "PLAYABLE ROSTER / FIVE IDENTITIES", "Shield, orbiting glyphs, blade, lance and paired shuttles remain distinct at gameplay scale.")
	_make_party(["threadbinder", "threadbinder", "threadbinder", "threadbinder"], true)
	await _capture("duplicates_pool", "THREADBINDER / FOUR PARTY VARIANTS", "Actual registry color variants retain the same ivory shuttle silhouette.")
	_set_room_size(DEFINITIONS.TRIAL_ROOM_SIZE)
	for index in party.size():
		party[index].position = [Vector2(-250.0, -95.0), Vector2(230.0, -95.0), Vector2(-250.0, 130.0), Vector2(230.0, 130.0)][index]
	await _capture("duplicates_trial", "THREADBINDER / LARGE ROOM PARTY SCALE", "Four palette variants at the larger trial-room camera fit, with their normal player bodies.")
	await _passive_switch_frame()
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
	print("[OK] Threadbinder GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	print("THREADBINDER_FRAMES=" + output_directory)
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

func _make_party(ids: Array, duplicate_variants: bool = false) -> void:
	for member in party:
		member.discard_pending_combat_input()
		member.free()
	party.clear()
	for index in ids.size():
		var member := Actor.new()
		_circle(member, 14.0)
		room.add_child(member)
		# Local control stages each real actor's pose. Palettes use the registry's
		# party variants; this fixture does not claim to create network peers.
		member.player_id = 1
		var package := CHARACTER.get_character(String(ids[index]))
		if duplicate_variants:
			package = CHARACTER.apply_duplicate_color_variant(package, index)
		member.apply_character_package(package)
		_check(member.active_character_id == String(ids[index]), "The registry applies " + String(ids[index]))
		member.position = Vector2((float(index) - float(ids.size() - 1) * 0.5) * 180.0, 0.0)
		member.aim = Vector2.RIGHT.rotated(-0.4 + float(index % 3) * 0.4)
		member.visual_facing_direction = member.aim
		member.arcana_motion.set_process(false)
		member.returning_crescent.set_physics_process(false)
		member.boss_combinations.set_process(false)
		member.static_wake_controller.renderer.set_process(false)
		var label := Label.new()
		label.position = Vector2(-80.0, 48.0)
		label.size = Vector2(160.0, 30.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text = String(package.get("name", "")) + (" " + str(index + 1) if duplicate_variants else "")
		label.add_theme_font_size_override("font_size", 16)
		member.add_child(label)
		party.append(member)
	actor = party[0]
	room.player = actor

func _mechanical_state(member: Actor) -> Dictionary:
	var collider := member.find_children("*", "CollisionShape2D", false, false)[0] as CollisionShape2D
	return {
		"snapshot": member.build_run_snapshot(), "position": member.position,
		"velocity": member.velocity, "facing": member.visual_facing_direction,
		"collision": (collider.shape as CircleShape2D).radius,
		"attack": [member.attack_cooldown_left, member.attack_anim_time_left],
		"dash": [member.dash_remaining_distance, member._dash_damage_immune_left],
		"thread": [member.cross_stitch_window_left, member.cross_stitch_target_network_id, member.cross_stitch_target.get_ref().get_instance_id() if member.cross_stitch_target != null and member.cross_stitch_target.get_ref() != null else 0]
	}

func _visible_enemy(position: Vector2) -> VisibleEnemy:
	var enemy := VisibleEnemy.new()
	_circle(enemy, 13.0)
	room.add_child(enemy)
	enemy.position = position
	return enemy

func _passive_switch_frame() -> void:
	_set_room_size(DEFINITIONS.POOL_ROOM_SIZE)
	_make_party(["threadbinder"])
	var previous := _visible_enemy(Vector2(65.0, 0.0))
	var next := _visible_enemy(Vector2(-65.0, 0.0))
	var collateral := _visible_enemy(Vector2(95.0, 30.0))
	await physics_frame
	await physics_frame
	_check(actor._perform_melee_attack(Vector2.RIGHT, {"damage": actor.damage, "damage_coefficient": 1.0}), "The first real Attack connects in the render fixture")
	_check(actor.cross_stitch_target != null and actor.cross_stitch_target.get_ref() == previous, "Accepted Attack damage threads the previous foe")
	actor.aim = Vector2.LEFT
	actor._try_execute_attack(actor.aim)
	actor.attack_anim_time_left = actor.attack_anim_duration * 0.75
	_check(actor.cross_stitch_target != null and actor.cross_stitch_target.get_ref() == next, "A second real Attack transfers the thread to the next foe")
	_check(previous.accepted_sources.count("cross_stitch_burst") == 1 and collateral.accepted_sources.count("cross_stitch_burst") == 1, "The actual switch Burst damages the previous foe and nearby collateral exactly once")
	await _capture("passive_switch", "CROSS STITCH / ACCEPTED TARGET SWITCH", "The new foe receives the thread and Mark; the previous foe releases the actual nearby Burst.")
	for enemy in [previous, next, collateral]:
		enemy.free()
	actor._clear_cross_stitch()

func _capture(name: String, title: String, explanation: String) -> void:
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
	_check(picture.get_size() == FRAME_SIZE, "Frame uses the requested resolution")
	var path := output_directory.path_join(name + ".png")
	_check(picture.save_png(path) == OK, "Saved " + name)
	frames.append({"name": name, "path": path, "zoom": camera.zoom.x, "room_size": room.current_effective_room_size})
	print("[FRAME] " + path)

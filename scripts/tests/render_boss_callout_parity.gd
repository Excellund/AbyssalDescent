extends "res://scripts/tests/test_biome_room_context.gd"
## Native Main, real boss-door owner and factory-created alternative side by
## side. Only move selection/time is staged; all labels and geometry are drawn
## by the actual actors, through their production camera and HUD.

const CALLOUT := preload("res://scripts/shared/enemy_attack_callout.gd")
const CALLOUT_TEST := preload("res://scripts/tests/test_boss_callouts.gd")
const STAGES := preload("res://scripts/shared/boss_stage_registry.gd")
const ALT_IDS := ["kilnheart", "glassweaver", "null_archivist"]
const ROOT_NAMES := [
	["Iron Charge", "Judgment Nova", "Sweeping Cleave"],
	["Prism Crown", "Gravity Well", "Echo Dash / 1", "Orbital Lance", "Polar Shift / PULL", "Polar Shift / PUSH"],
	["Sever", "Null Ring", "Echo Cross"],
]
const OWNED_POWERS := ["heavy_blow", "static_wake", "stormbrand", "shatterwake"]
var frames: Array[Dictionary] = []
var output_directory := ""
var original: Node2D
var alternative: Node2D

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://")):
		push_error("Boss parity capture requires a native disposable project")
		quit(1)
		return
	output_directory = ProjectSettings.globalize_path("res://boss_callout_parity_frames")
	DirAccess.make_dir_recursive_absolute(output_directory)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	await _setup_context_world()
	for power_id: String in OWNED_POWERS:
		check(world.player.upgrade_system.apply_power(power_id), "Native ownership populates build HUD: " + power_id)
	for family in range(3):
		await _open_pair(family)
		await _fit_native_camera(Vector2i(1280, 720))
		for move in range(ROOT_NAMES[family].size()):
			_prepare_pair(family, move)
			check(original.get_attack_callout() == ROOT_NAMES[family][move], "Exact original move name: " + String(ROOT_NAMES[family][move]))
			await _capture_pair("%s_1280_root_%d" % [BOSSES.DEFAULT_IDS[family], move], true, true)
		for capture_size: Vector2i in [Vector2i(960, 720), Vector2i(1920, 1080)]:
			await _fit_native_camera(capture_size)
			_prepare_pair(family, 0)
			await _capture_pair("%s_%d_pair" % [BOSSES.DEFAULT_IDS[family], capture_size.x], true, true)
		await _fit_native_camera(Vector2i(1280, 720))
		if family == 1:
			await _echo_dash_lifecycle()
		elif family == 2:
			await _null_ring_lifecycle()
			CALLOUT_TEST.clear_move(original, family)
			original._charge_motion.cancel()
			original._sync_attack_overlay()
			alternative._cancel_attack()
			original.queue_redraw()
			await _capture_pair("lacuna_1280_recovery", false, false)
			var old_overlay: WeakRef = weakref(original._attack_overlay)
			original.queue_free()
			alternative.queue_free()
			await process_frame
			await process_frame
			check(old_overlay.get_ref() == null, "Removing Lacuna also removes its external attack overlay")
			original = null
			alternative = null
			await _capture_pair("lacuna_1280_owners_removed", false, false)
	await _dispose_context_world()
	check(frames.size() == 26, "All 26 requested native parity/lifecycle frames were captured")
	var manifest := {"gpu": RenderingServer.get_video_adapter_name(), "frames": frames, "checks": checks, "failures": failures, "scope": "Actual Main boss doors and factory-created alternative counterparts, all twelve original move names at1280, three native arena/camera sizes, Echo Dash retarget legs and exact snapshot expiry, Reposition, Null Ring pending/resolved, recovery and owner cleanup."}
	FileAccess.open(output_directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t"))
	print("[OK] Boss callout parity GPU: %d frames, %d checks, %d failures" % [frames.size(), checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _open_pair(family: int) -> void:
	original = await _enter_context_boss("crumble", BOSSES.DEFAULT_IDS[family])
	check(is_instance_valid(original), "Actual Main boss door creates " + String(BOSSES.DEFAULT_IDS[family]))
	_start_context_combat()
	alternative = STAGES.create_boss_node(family + 1, Vector2.ZERO, ALT_IDS[family])
	world.add_child(alternative)
	alternative.arena_size = world.current_effective_room_size
	alternative.target = world.player
	alternative.target_candidates = [world.player]
	alternative.set_physics_process(false)
	alternative.set_process(false)
	alternative._update_spawn_transport(float(alternative.spawn_transport_time_left) + .01)
	original._update_spawn_transport(float(original.spawn_transport_time_left) + .01)
	check(alternative.get_meta("boss_id") == ALT_IDS[family], "Factory counterpart preserves its actual boss identity")

func _fit_native_camera(capture_size: Vector2i) -> void:
	root.size = capture_size
	root.content_scale_size = capture_size
	await process_frame
	world._apply_camera_bounds_for_room(world.current_effective_room_size)
	world._update_camera_mode()
	world.player_camera.set_physics_process(false)
	world.player_camera.global_position = Vector2.ZERO
	world.player_camera.zoom = world.player_camera.target_zoom
	world.player_camera.force_update_scroll()
	world._sync_renderer()
	world.hud.refresh(world._get_hud_state(), world.player)
	await process_frame
	world.hud.refresh(world._get_hud_state(), world.player)
	await process_frame

func _position_pair() -> void:
	var screen_size := Vector2(root.size)
	original.global_position = original.get_canvas_transform().affine_inverse() * (screen_size * Vector2(.42, .47))
	alternative.global_position = alternative.get_canvas_transform().affine_inverse() * (screen_size * Vector2(.76, .47))
	world.player.global_position = world.player.get_canvas_transform().affine_inverse() * (screen_size * Vector2(.59, .69))
	world.player.velocity = Vector2.ZERO
	world.player.set_health(world.player.get_max_health())
	original.target = world.player
	original.target_candidates = [world.player]
	original.velocity = Vector2.ZERO
	alternative.velocity = Vector2.ZERO

func _prepare_pair(family: int, move: int) -> void:
	_position_pair()
	if family == 1:
		original._echo_dash_remaining = 0
		original._echo_dash_retargeting = false
		original._echo_dash_retarget_time_left = 0.0
		original._echo_dash_reposition_only = false
		original._polar_shift_pull_damage_pending = false
		original._polar_shift_pull_damage_delay_left = 0.0
	else:
		original._ensure_charge_motion()
		original._charge_motion.cancel()
	if family == 2:
		original._null_ring_pull_timer = -1.0
	CALLOUT_TEST.prepare(original, family, move)
	if family in [0, 2] and move == 0:
		original._charge_motion.update_warning(original.global_position, Vector2.RIGHT)
	if family == 1 and move == 2:
		original.state_time_left = float(original._get_windup_time(move)) * .55
		original._process_windup_state(.01)
	if family == 2:
		if move == 1:
			original._locked_null_ring_center = world.player.global_position
			original._rebuild_null_ring_centers(.0)
		original._sync_attack_overlay()
	check(float(original.telegraph_alpha) > .1, "Staged original warning has actually visible opacity")
	alternative._cancel_attack()
	alternative.begin_attack(move % 3)
	# Native progression supplies actual committed geometry/telegraph opacity;
	# Kilnheart's moving body remains at the resulting production position.
	alternative._process_behavior(float(alternative.warning_duration) * .45)
	check(not alternative.get_attack_warning_geometry().is_empty(), "Newest counterpart has real committed geometry")
	original.queue_redraw()
	alternative.queue_redraw()

func _echo_dash_lifecycle() -> void:
	_prepare_pair(1, 2)
	original._enter_attack_state()
	check(original.get_attack_callout() == "Echo Dash / 1", "First real Echo Dash leg retains its name")
	for leg in [2, 3]:
		original._process_attack_state(float(original.echo_dash_duration) + .001)
		check(is_zero_approx(float(original.state_time_left)) and original._echo_dash_retargeting and float(original._echo_dash_retarget_time_left) > 0.0, "Leg %d is the actual zero-state-timer retarget interval" % leg)
		original._process_attack_state(float(original.echo_dash_retarget_pause) * .45)
		check(original.get_attack_callout() == "Echo Dash / %d" % leg, "Actual next-leg warning remains named")
		original.queue_redraw()
		await _capture_pair("sovereign_1280_echo_retarget_%d" % leg, true, true)
		if leg == 2:
			original._process_attack_state(float(original._echo_dash_retarget_time_left) + .001)
	# Apply both precise/runtime packets to a distinct factory actor. Its timer
	# then expires with no subsequent packet or manually requested redraw.
	var host := original
	var remote := STAGES.create_boss_node(2, host.global_position, "sovereign")
	world.add_child(remote)
	remote.set_network_simulation_enabled(false)
	remote.set_physics_process(false)
	remote.set_process(false)
	remote.apply_network_runtime_state(host.get_network_runtime_state().duplicate(true))
	remote.apply_projectile_network_sync_state(host.get_projectile_network_sync_state().duplicate(true))
	remote._update_spawn_transport(float(remote.spawn_transport_time_left) + .01)
	check(remote.get_attack_callout() == "Echo Dash / 3", "Replica inherits leg 3 from actual zero-state-timer packets")
	host.hide()
	original = remote
	alternative._cancel_attack()
	check(remote._is_attack_warning_active(), "Fresh replica snapshot begins with a live retarget warning")
	await process_frame
	await RenderingServer.frame_post_draw
	remote._process_network_visuals(float(remote._echo_dash_retarget_time_left) + .01)
	check(remote.get_attack_callout().is_empty(), "Replica's own retarget countdown removes the callout without a new snapshot")
	check(not remote._is_attack_warning_active(), "Replica expiry also retires the real retarget warning geometry")
	await _capture_pair("sovereign_1280_echo_replica_expired", false, false)
	remote.queue_free()
	original = host
	host.show()
	_prepare_pair(1, 2)
	original._echo_dash_reposition_only = true
	original.state_time_left = float(original._get_windup_time(2)) * .55
	original._process_windup_state(.01)
	original.queue_redraw()
	check(float(original.telegraph_alpha) > .1, "Reposition's distinct warning lane is actually visible")
	check(original.get_attack_callout() == "Reposition", "Non-damaging reposition has a distinct name")
	await _capture_pair("sovereign_1280_reposition", true, true)

func _null_ring_lifecycle() -> void:
	_prepare_pair(2, 1)
	original._enter_attack_state()
	original._process_attack_state(float(original.null_ring_pull_delay) * .45)
	original.queue_redraw()
	check(original.get_attack_callout() == "Null Ring / COLLAPSE", "Actual pending collapse is announced after initial windup")
	await _capture_pair("lacuna_1280_null_ring_pending", true, true)
	# Resolve the actual damage timer while its short visual afterglow remains.
	original._process_attack_state(float(original._null_ring_pull_timer) + .001)
	original.queue_redraw()
	check(float(original.state_time_left) > 0.0 and original.get_attack_callout().is_empty(), "Resolved ring clears its name before afterglow ends")
	alternative._cancel_attack()
	await _capture_pair("lacuna_1280_null_ring_resolved", false, false)

func _actor_record(actor: Node2D, expected_visible: bool, frame_name: String) -> Dictionary:
	if not is_instance_valid(actor):
		check(not expected_visible, "Removed owner cannot retain a callout")
		return {"owner_removed": true}
	var text: String = actor.get_attack_callout()
	check(not text.is_empty() if expected_visible else text.is_empty(), "Expected visibility for " + frame_name + ": " + String(actor.get_meta("boss_id")))
	var result := {"boss_id": actor.get_meta("boss_id"), "callout": text, "state": int(actor.boss_state), "state_time_left": float(actor.state_time_left), "screen_position": actor.get_global_transform_with_canvas().origin}
	if not expected_visible:
		return result
	var info := CALLOUT.layout(actor, text, -100.0)
	var rectangle: Rect2 = info.rect
	var stretch := root.get_stretch_transform().get_scale().x
	var health_bar: Control = actor.health_bar
	var health_rect: Rect2 = health_bar.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, health_bar.size)
	var gap := (health_rect.position.y - rectangle.end.y) * stretch
	check(root.get_visible_rect().encloses(rectangle), "Viewport contains complete callout: " + text)
	check(float(info.font_size) * stretch >= 18.0 - .01, "Native arena camera retains 18 physical pixel text: " + text)
	check(not rectangle.intersects(health_rect), "Name clears its own actual health bar: " + text)
	check(absf(gap - 8.0) < .02, "Original/newest name stack uses the same 8px health-bar gap: " + text)
	for exclusion: Rect2 in world.hud.get_attack_callout_exclusion_rects():
		check(not rectangle.intersects(exclusion), "Name clears actual HUD surface: " + text)
	result.merge({"rect": rectangle, "font_pixels": float(info.font_size) * stretch, "health_rect": health_rect, "health_gap_pixels": gap})
	return result

func _capture_pair(frame_name: String, original_visible: bool, alternative_visible: bool) -> void:
	await process_frame
	await process_frame
	check(world.hud.is_in_group("attack_callout_hud") and world.hud.status_panel.is_visible_in_tree() and world.hud.stats_panel.is_visible_in_tree(), "Native HUD is present for " + frame_name)
	var old := _actor_record(original, original_visible, frame_name)
	var newest := _actor_record(alternative, alternative_visible, frame_name)
	if original_visible and alternative_visible:
		check(not (old.rect as Rect2).intersects(newest.rect), "Paired callouts remain separately readable")
		check(is_equal_approx(float(old.font_pixels), float(newest.font_pixels)), "Original and newest boss names use matching physical type size")
	await RenderingServer.frame_post_draw
	var path := output_directory.path_join(frame_name + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "Saved native parity image: " + frame_name)
	frames.append({"name": frame_name, "path": path, "size": root.size, "camera_zoom": world.player_camera.zoom, "original": old, "newest": newest, "hud_exclusions": world.hud.get_attack_callout_exclusion_rects()})
	print("[FRAME] " + path)

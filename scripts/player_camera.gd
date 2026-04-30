extends Camera2D

const MODE_FOLLOW := 0
const MODE_STATIC := 1

@export var velocity_lookahead_distance: float = 72.0
@export var mouse_lookahead_distance: float = 96.0
@export_range(0.0, 1.0, 0.01) var mouse_influence: float = 0.38
@export var offset_lerp_speed: float = 10.0
@export var max_offset_distance: float = 132.0
@export var position_lerp_speed: float = 8.0
@export var velocity_deadzone: float = 24.0
@export var mouse_deadzone: float = 28.0
@export var input_smoothing_speed: float = 14.0
@export var zoom_lerp_speed: float = 10.0
@export var room_fit_zoom_scale: float = 0.95
@export var min_zoom: float = 0.5
@export var max_zoom: float = 3.0
@export var visible_edge_margin: float = 10.0

var target_body: CharacterBody2D
var smoothed_velocity_offset: Vector2 = Vector2.ZERO
var smoothed_mouse_offset: Vector2 = Vector2.ZERO
var camera_mode: int = MODE_FOLLOW
var static_center_global: Vector2 = Vector2.ZERO
var target_zoom: Vector2 = Vector2.ONE
var world_bounds_rect: Rect2 = Rect2()
var has_world_bounds: bool = false
var cached_viewport_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	target_body = get_parent() as CharacterBody2D
	enabled = true
	top_level = true
	position_smoothing_enabled = false
	if is_instance_valid(target_body):
		global_position = target_body.global_position
		static_center_global = global_position
	cached_viewport_size = get_viewport_rect().size
	target_zoom = zoom
	make_current()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target_body):
		return
	_refresh_world_bounds_for_viewport_change()

	var velocity_offset_target := Vector2.ZERO
	if camera_mode == MODE_FOLLOW and target_body.velocity.length() > velocity_deadzone:
		velocity_offset_target = target_body.velocity.normalized() * velocity_lookahead_distance

	var input_blend := 1.0 - exp(-input_smoothing_speed * delta)
	smoothed_velocity_offset = smoothed_velocity_offset.lerp(velocity_offset_target, input_blend)

	var mouse_vector := get_global_mouse_position() - target_body.global_position
	var mouse_offset_target := Vector2.ZERO
	if camera_mode == MODE_FOLLOW and mouse_vector.length() > mouse_deadzone:
		var mouse_strength := minf(1.0, (mouse_vector.length() - mouse_deadzone) / mouse_lookahead_distance)
		mouse_offset_target = mouse_vector.normalized() * mouse_lookahead_distance * mouse_strength * mouse_influence
	smoothed_mouse_offset = smoothed_mouse_offset.lerp(mouse_offset_target, input_blend)

	var desired_position := target_body.global_position
	if camera_mode == MODE_FOLLOW:
		var target_offset := smoothed_velocity_offset + smoothed_mouse_offset
		if target_offset.length() > max_offset_distance:
			target_offset = target_offset.normalized() * max_offset_distance
		desired_position += target_offset
	else:
		desired_position = static_center_global

	var blend := 1.0 - exp(-position_lerp_speed * delta)
	global_position = global_position.lerp(desired_position, blend)
	var zoom_blend := 1.0 - exp(-zoom_lerp_speed * delta)
	zoom = zoom.lerp(target_zoom, zoom_blend)
	_ensure_target_visible()

func set_follow_mode() -> void:
	camera_mode = MODE_FOLLOW

func set_static_mode(center_global: Vector2) -> void:
	camera_mode = MODE_STATIC
	static_center_global = center_global

func set_world_bounds(bounds_rect: Rect2) -> void:
	world_bounds_rect = bounds_rect
	has_world_bounds = true
	_apply_zoom_and_limits_from_bounds(bounds_rect)

func set_room_fit_zoom_scale(scale: float) -> void:
	room_fit_zoom_scale = maxf(0.01, scale)
	if has_world_bounds:
		_apply_zoom_and_limits_from_bounds(world_bounds_rect)

func _refresh_world_bounds_for_viewport_change() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	if viewport_size.distance_to(cached_viewport_size) <= 0.1:
		return
	cached_viewport_size = viewport_size
	if has_world_bounds:
		_apply_zoom_and_limits_from_bounds(world_bounds_rect)

func _apply_zoom_and_limits_from_bounds(bounds_rect: Rect2) -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var fit_zoom := minf(viewport_size.x / maxf(1.0, bounds_rect.size.x), viewport_size.y / maxf(1.0, bounds_rect.size.y))
	fit_zoom *= maxf(0.01, room_fit_zoom_scale)
	fit_zoom = clampf(fit_zoom, min_zoom, max_zoom)
	target_zoom = Vector2(fit_zoom, fit_zoom)

	var half_view := Vector2(
		viewport_size.x * 0.5 / maxf(0.001, fit_zoom),
		viewport_size.y * 0.5 / maxf(0.001, fit_zoom)
	)
	var left := bounds_rect.position.x + half_view.x
	var right := bounds_rect.position.x + bounds_rect.size.x - half_view.x
	if left > right:
		var center_x := bounds_rect.position.x + bounds_rect.size.x * 0.5
		left = center_x
		right = center_x

	var top := bounds_rect.position.y + half_view.y
	var bottom := bounds_rect.position.y + bounds_rect.size.y - half_view.y
	if top > bottom:
		var center_y := bounds_rect.position.y + bounds_rect.size.y * 0.5
		top = center_y
		bottom = center_y

	limit_left = int(floor(left))
	limit_right = int(ceil(right))
	limit_top = int(floor(top))
	limit_bottom = int(ceil(bottom))

func _ensure_target_visible() -> void:
	if not is_instance_valid(target_body):
		return

	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var half_view := Vector2(
		viewport_size.x * 0.5 / maxf(0.001, zoom.x),
		viewport_size.y * 0.5 / maxf(0.001, zoom.y)
	)
	var min_visible := global_position - half_view + Vector2.ONE * visible_edge_margin
	var max_visible := global_position + half_view - Vector2.ONE * visible_edge_margin

	var changed := false
	if target_body.global_position.x < min_visible.x:
		global_position.x = target_body.global_position.x + half_view.x - visible_edge_margin
		changed = true
	elif target_body.global_position.x > max_visible.x:
		global_position.x = target_body.global_position.x - half_view.x + visible_edge_margin
		changed = true

	if target_body.global_position.y < min_visible.y:
		global_position.y = target_body.global_position.y + half_view.y - visible_edge_margin
		changed = true
	elif target_body.global_position.y > max_visible.y:
		global_position.y = target_body.global_position.y - half_view.y + visible_edge_margin
		changed = true

	if changed:
		_clamp_to_limits()

func _clamp_to_limits() -> void:
	var min_x := minf(float(limit_left), float(limit_right))
	var max_x := maxf(float(limit_left), float(limit_right))
	var min_y := minf(float(limit_top), float(limit_bottom))
	var max_y := maxf(float(limit_top), float(limit_bottom))
	global_position.x = clampf(global_position.x, min_x, max_x)
	global_position.y = clampf(global_position.y, min_y, max_y)

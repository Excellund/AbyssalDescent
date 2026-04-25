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

var target_body: CharacterBody2D
var smoothed_velocity_offset: Vector2 = Vector2.ZERO
var smoothed_mouse_offset: Vector2 = Vector2.ZERO
var camera_mode: int = MODE_FOLLOW
var static_center_global: Vector2 = Vector2.ZERO

func _ready() -> void:
	target_body = get_parent() as CharacterBody2D
	enabled = true
	top_level = true
	position_smoothing_enabled = false
	if is_instance_valid(target_body):
		global_position = target_body.global_position
		static_center_global = global_position
	make_current()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target_body):
		return

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

func set_follow_mode() -> void:
	camera_mode = MODE_FOLLOW

func set_static_mode(center_global: Vector2) -> void:
	camera_mode = MODE_STATIC
	static_center_global = center_global

func set_world_bounds(bounds_rect: Rect2) -> void:
	limit_left = int(floor(bounds_rect.position.x))
	limit_top = int(floor(bounds_rect.position.y))
	limit_right = int(ceil(bounds_rect.position.x + bounds_rect.size.x))
	limit_bottom = int(ceil(bounds_rect.position.y + bounds_rect.size.y))

extends Node2D

const ATTACK_SEVER := 0
const ATTACK_ECHO_CROSS := 2

var telegraph_active: bool = false
var active_attack: int = ATTACK_SEVER
var boss_position: Vector2 = Vector2.ZERO
var telegraph_alpha: float = 0.0
var locked_direction: Vector2 = Vector2.RIGHT
var echo_cross_angle: float = 0.0
var sever_speed: float = 760.0
var sever_duration: float = 0.2
var sever_width: float = 42.0
var echo_cross_length: float = 340.0
var echo_cross_width: float = 34.0

func _ready() -> void:
	top_level = false
	z_as_relative = false
	z_index = -1
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE

func set_telegraph_state(is_active: bool, next_attack: int, next_boss_position: Vector2, next_telegraph_alpha: float, next_locked_direction: Vector2, next_echo_cross_angle: float, next_sever_speed: float, next_sever_duration: float, next_sever_width: float, next_echo_cross_length: float, next_echo_cross_width: float) -> void:
	telegraph_active = is_active
	active_attack = next_attack
	boss_position = next_boss_position
	telegraph_alpha = next_telegraph_alpha
	locked_direction = next_locked_direction
	echo_cross_angle = next_echo_cross_angle
	sever_speed = next_sever_speed
	sever_duration = next_sever_duration
	sever_width = next_sever_width
	echo_cross_length = next_echo_cross_length
	echo_cross_width = next_echo_cross_width
	queue_redraw()

func _process(_delta: float) -> void:
	if telegraph_active:
		queue_redraw()

func _draw() -> void:
	if not telegraph_active:
		return
	var alpha := 0.2 + telegraph_alpha * 0.72
	if active_attack == ATTACK_SEVER:
		var direction := locked_direction.normalized() if locked_direction.length_squared() > 0.000001 else Vector2.RIGHT
		var start := boss_position + direction * 28.0
		var end := start + direction * (sever_speed * sever_duration * 0.7)
		draw_line(start, end, Color(0.2, 1.0, 0.82, alpha * 0.6), sever_width * 2.0)
		draw_line(start, end, Color(0.92, 1.0, 0.98, alpha), 3.6)
		var slash_side := Vector2(-direction.y, direction.x)
		draw_line(start + slash_side * (sever_width * 0.7), end + slash_side * (sever_width * 0.22), Color(0.84, 1.0, 0.95, alpha * 0.36), 1.6)
		draw_line(start - slash_side * (sever_width * 0.7), end - slash_side * (sever_width * 0.22), Color(0.84, 1.0, 0.95, alpha * 0.24), 1.2)
		return
	if active_attack == ATTACK_ECHO_CROSS:
		var primary_dir := Vector2.RIGHT.rotated(echo_cross_angle)
		var secondary_dir := primary_dir.orthogonal()
		var half_len := echo_cross_length * 0.5
		draw_line(boss_position - primary_dir * half_len, boss_position + primary_dir * half_len, Color(0.18, 1.0, 0.8, alpha * 0.7), echo_cross_width * 1.5)
		draw_line(boss_position - secondary_dir * half_len, boss_position + secondary_dir * half_len, Color(0.18, 1.0, 0.8, alpha * 0.7), echo_cross_width * 1.5)
		draw_line(boss_position - primary_dir * half_len, boss_position + primary_dir * half_len, Color(0.92, 1.0, 0.98, alpha), 2.4)
		draw_line(boss_position - secondary_dir * half_len, boss_position + secondary_dir * half_len, Color(0.92, 1.0, 0.98, alpha), 2.4)
		var echo_offset := (0.1 + telegraph_alpha * 0.18) * echo_cross_width
		draw_line(boss_position - primary_dir * half_len + secondary_dir * echo_offset, boss_position + primary_dir * half_len + secondary_dir * echo_offset, Color(0.86, 1.0, 0.96, alpha * 0.26), 1.6)
		draw_line(boss_position - secondary_dir * half_len - primary_dir * echo_offset, boss_position + secondary_dir * half_len - primary_dir * echo_offset, Color(0.86, 1.0, 0.96, alpha * 0.2), 1.4)
		var half_width := echo_cross_width * 0.5
		draw_line(boss_position - primary_dir * half_len + secondary_dir * half_width, boss_position + primary_dir * half_len + secondary_dir * half_width, Color(0.9, 1.0, 0.96, alpha * 0.54), 1.6)
		draw_line(boss_position - primary_dir * half_len - secondary_dir * half_width, boss_position + primary_dir * half_len - secondary_dir * half_width, Color(0.9, 1.0, 0.96, alpha * 0.54), 1.6)
		draw_line(boss_position - secondary_dir * half_len + primary_dir * half_width, boss_position + secondary_dir * half_len + primary_dir * half_width, Color(0.9, 1.0, 0.96, alpha * 0.46), 1.6)
		draw_line(boss_position - secondary_dir * half_len - primary_dir * half_width, boss_position + secondary_dir * half_len - primary_dir * half_width, Color(0.9, 1.0, 0.96, alpha * 0.46), 1.6)

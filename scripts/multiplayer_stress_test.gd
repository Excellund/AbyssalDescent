## Network stress test coordinator
## Incrementally spawns enemies and measures packet size/FPS impact
## Auto-scales until performance degradation detected

extends RefCounted

class StressMetrics:
	var enemy_count: int = 0
	var total_bytes_synced: int = 0
	var max_packet_size_bytes: int = 0
	var avg_packet_size_bytes: float = 0.0
	var sync_count: int = 0
	var frame_count: int = 0
	var total_frame_ms: float = 0.0
	var average_fps: float = 0.0
	var min_fps: float = 60.0
	var mtu_exceeded: bool = false
	var avg_sim_ms: float = 0.0
	var avg_ui_ms: float = 0.0
	var avg_pre_ms: float = 0.0
	var avg_sync_ms: float = 0.0
	var avg_post_ms: float = 0.0
	var avg_frame_ms: float = 0.0
	var avg_enemy_drawn: float = 0.0
	
	func get_string() -> String:
		return "Enemies:%d | Bandwidth:%d avg bytes/cycle | PerPacket:%d max | FPS:%.1f avg (min:%.1f) | Pre:%.2fms | Sync:%.2fms | Post:%.2fms | Frame:%.2fms | Sim:%.2fms | UI:%.2fms | Drawn:%.1f | Syncs:%d | Frames:%d" % [
			enemy_count,
			int(avg_packet_size_bytes),
			max_packet_size_bytes,
			average_fps,
			min_fps,
			avg_pre_ms,
			avg_sync_ms,
			avg_post_ms,
			avg_frame_ms,
			avg_sim_ms,
			avg_ui_ms,
			avg_enemy_drawn,
			sync_count,
			frame_count
		]

var world_gen: Node = null
var test_phases: Array[StressMetrics] = []
var current_phase: int = 0
var phase_frame_count: int = 0
var phase_warmup_frames: int = 20
var phase_measure_frames: int = 30
var mtu_limit: int = 1392
var fps_drop_limit_pct: float = 22.0
var fps_drop_stop_below_fps: float = 75.0
var initial_enemy_count: int = 10
var increment_enemy_count: int = 10
var max_enemy_count: int = 100

## Start stress test: initial enemy count, increment step, max enemies
func start_test(initial_count: int = 10, increment: int = 10, max_count: int = 100) -> void:
	if not is_instance_valid(world_gen):
		print_debug("[StressTest] FAIL: world_gen not set before calling start_test()")
		return
	
	initial_enemy_count = initial_count
	increment_enemy_count = increment
	max_enemy_count = max_count
	
	print_debug("[StressTest] Starting auto-scale stress test")
	print_debug("[StressTest] Initial:%d | Increment:%d | Max:%d | Warmup:%d | Measure:%d frames" % [
		initial_count, increment, max_count, phase_warmup_frames, phase_measure_frames
	])
	
	test_phases.clear()
	current_phase = 0
	phase_frame_count = 0
	world_gen._stress_test_active = true

	# Pre-create first phase with correct test enemy count
	var first_metric := StressMetrics.new()
	first_metric.enemy_count = initial_count
	test_phases.append(first_metric)

	# Spawn initial batch
	_spawn_enemy_batch(initial_count)

func _spawn_enemy_batch(count: int) -> void:
	if not is_instance_valid(world_gen):
		return
	
	print_debug("[StressTest] Spawning %d enemies for phase" % count)
	
	# Clear previous phase enemies before spawning new batch
	world_gen._clear_all_enemies()
	world_gen.active_room_enemy_count = 0
	if world_gen.has_method("_spawn_test_enemies"):
		world_gen._spawn_test_enemies(count)

func tick_frame(delta: float, last_sync_bytes: int, last_sync_count: int) -> void:
	if not world_gen._stress_test_active:
		return
	
	phase_frame_count += 1
	
	# last_sync_bytes = total bytes across ALL RPC calls in the sync cycle
	# last_sync_count = number of RPC batch calls made (batch_size controls enemies per call)
	var per_packet_bytes := int(float(last_sync_bytes) / maxf(1.0, float(last_sync_count))) + 200

	# Ignore spawn-transport burst so phase scoring reflects steady-state behavior.
	if phase_frame_count <= phase_warmup_frames:
		return

	var current_metric: StressMetrics = test_phases[-1]
	current_metric.frame_count += 1
	current_metric.total_frame_ms += delta * 1000.0
	current_metric.average_fps = 1000.0 / (current_metric.total_frame_ms / maxf(1, current_metric.frame_count))
	var instant_fps := 1.0 / maxf(0.0001, delta)
	current_metric.min_fps = minf(current_metric.min_fps, instant_fps)
	
	if last_sync_bytes > 0 and last_sync_count > 0:
		current_metric.total_bytes_synced += last_sync_bytes
		current_metric.sync_count += 1
		current_metric.avg_packet_size_bytes = float(current_metric.total_bytes_synced) / float(current_metric.sync_count)
		# Track max per-packet size (not total-per-cycle) for MTU comparison
		current_metric.max_packet_size_bytes = maxi(current_metric.max_packet_size_bytes, per_packet_bytes)
		
		if per_packet_bytes > mtu_limit:
			current_metric.mtu_exceeded = true

	if world_gen != null and world_gen.has_method("_get_perf_attribution_snapshot"):
		var perf_sample := world_gen.call("_get_perf_attribution_snapshot") as Dictionary
		if not perf_sample.is_empty():
			current_metric.avg_pre_ms = float(perf_sample.get("avg_pre_ms", current_metric.avg_pre_ms))
			current_metric.avg_sim_ms = float(perf_sample.get("avg_sim_ms", current_metric.avg_sim_ms))
			current_metric.avg_sync_ms = float(perf_sample.get("avg_sync_ms", current_metric.avg_sync_ms))
			current_metric.avg_post_ms = float(perf_sample.get("avg_post_ms", current_metric.avg_post_ms))
			current_metric.avg_frame_ms = float(perf_sample.get("avg_frame_ms", current_metric.avg_frame_ms))
			current_metric.avg_ui_ms = float(perf_sample.get("avg_ui_ms", current_metric.avg_ui_ms))
			current_metric.avg_enemy_drawn = float(perf_sample.get("avg_enemy_drawn", current_metric.avg_enemy_drawn))

	if current_metric.frame_count >= phase_measure_frames:
		var can_scale := _should_scale_to_next_phase(current_metric)
		if can_scale:
			var next_count = current_metric.enemy_count + increment_enemy_count
			if next_count <= max_enemy_count:
				_spawn_enemy_batch(next_count)
				var next_metric := StressMetrics.new()
				next_metric.enemy_count = next_count
				test_phases.append(next_metric)
				phase_frame_count = 0
			else:
				_terminate_test("Reached max enemy count limit")
				return
		else:
			_terminate_test("Performance limit reached")
			return

func _should_scale_to_next_phase(metric: StressMetrics) -> bool:
	# Stop if: MTU exceeded, FPS < 30
	if metric.mtu_exceeded or metric.average_fps < 30.0:
		return false
	
	# Check FPS drop from previous phase
	if test_phases.size() >= 2:
		var prev = test_phases[-2]
		if prev.average_fps <= 0.0001:
			return true
		var fps_drop_pct = ((prev.average_fps - metric.average_fps) / prev.average_fps) * 100.0
		var should_apply_drop_stop := metric.average_fps <= fps_drop_stop_below_fps
		if should_apply_drop_stop and fps_drop_pct > fps_drop_limit_pct:
			return false
	
	return true

func _terminate_test(reason: String = "") -> void:
	world_gen._stress_test_active = false
	print_debug("\n" + "=".repeat(100))
	print_debug("STRESS TEST RESULTS - %s" % reason)
	print_debug("=".repeat(100))
	
	for i in range(test_phases.size()):
		var phase = test_phases[i]
		var phase_info = "Phase %d: " % i
		if i > 0:
			var prev = test_phases[i - 1]
			var fps_drop_pct = ((prev.average_fps - phase.average_fps) / prev.average_fps) * 100.0
			phase_info += "(FPS drop: %.1f%%) | " % fps_drop_pct
		print_debug("  " + phase_info + phase.get_string())
	
	if test_phases.size() > 0:
		var last = test_phases[-1]
		var limit_factor = _identify_limit_factor(last)
		print_debug("\nLimiting factor: " + limit_factor)
	
	print_debug("=".repeat(100) + "\n")

func _identify_limit_factor(metric: StressMetrics) -> String:
	if metric.mtu_exceeded:
		return "MTU exceeded at %d enemies (packet size %d > %d)" % [metric.enemy_count, metric.max_packet_size_bytes, mtu_limit]
	elif metric.average_fps < 30.0:
		return "FPS dropped below 30 at %d enemies (FPS: %.1f)" % [metric.enemy_count, metric.average_fps]
	elif test_phases.size() >= 2:
		var prev = test_phases[-2]
		var fps_drop_pct = ((prev.average_fps - metric.average_fps) / prev.average_fps) * 100.0
		if metric.average_fps <= fps_drop_stop_below_fps and fps_drop_pct > fps_drop_limit_pct:
			return "FPS drop exceeded %.1f%% between phases (%.1f%%)" % [fps_drop_limit_pct, fps_drop_pct]
	return "Test completed successfully"

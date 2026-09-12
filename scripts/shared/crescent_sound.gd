extends RefCounted
## Recorded air swishes, prepared offline; no oscillators or gameplay RNG.
const OUTBOUND: Array[AudioStreamWAV] = [
	preload("res://sounds/crescent/crescent_outbound_1.wav"),
	preload("res://sounds/crescent/crescent_outbound_2.wav"),
	preload("res://sounds/crescent/crescent_outbound_3.wav"),
]
const RETURNING: Array[AudioStreamWAV] = [
	preload("res://sounds/crescent/crescent_return_1.wav"),
	preload("res://sounds/crescent/crescent_return_2.wav"),
]
const BOUNCE: Array[AudioStreamWAV] = [preload("res://sounds/crescent/crescent_bounce_1.wav")]

static func variants(kind: StringName) -> Array[AudioStreamWAV]:
	return RETURNING if kind == &"return" else BOUNCE if kind == &"bounce" else OUTBOUND

static func stream(kind: StringName, index: int = 0) -> AudioStreamWAV:
	var pool := variants(kind)
	return pool[posmod(index, pool.size())]

static func trim_db(kind: StringName) -> float:
	return -8.0 if kind == &"return" else -6.0 if kind == &"bounce" else 0.0

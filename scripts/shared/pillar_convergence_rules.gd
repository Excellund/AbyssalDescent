extends RefCounted
## Faultline Seal. Stable Pillar Convergence save ID and mapped ratio are retained.

static func charges(ratio: float) -> int:
	return 2 if ratio >= 0.4 else 3

static func radius(ratio: float) -> float:
	return 90.0 if ratio >= 0.4 else 76.0

static func duration(_ratio: float) -> float:
	return 0.8

static func cooldown(_ratio: float) -> float:
	return 0.6

static func damage_ratio(ratio: float, field_triggered: bool = false) -> float:
	return (2.4 if ratio >= 0.4 else 1.8) * (1.5 if field_triggered else 1.0)

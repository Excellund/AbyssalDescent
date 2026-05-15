extends RefCounted

# Returns a fade multiplier that holds near 1.0 for most of an ability's life,
# then drops steeply to 0.0 at the end. Useful for projectiles, lingering zones,
# and any effect that should stay clearly visible until it expires.
#
#   ratio:          progress through the ability's life — 0.0 = fresh, 1.0 = expired
#   fade_start:     fraction of life at which fading begins
#                   e.g. 0.90 = full opacity for the first 90%, then steep drop
#   fade_steepness: exponent — higher = sharper cliff at the end
#                   3.0 = moderate curve, 5.0 = near-instant cutoff
#
# Example usage (ring node traveling 0→ring_radius_max):
#   var ratio := ring_radius / ring_radius_max
#   var alpha := VISUAL_MATH.late_fade(ratio, 0.90, 3.0)
static func late_fade(ratio: float, fade_start: float = 0.88, fade_steepness: float = 3.0) -> float:
	return pow(clampf((1.0 - ratio) / (1.0 - fade_start), 0.0, 1.0), fade_steepness)

extends RefCounted
## A raw packet describes damage before target conditions and Mission effects.
## Its effective Damage coefficient distributes conditional flat Boons over
## time, projectile scale and Echo strength instead of awarding a full flat
## bonus on every tiny packet.

static func valid_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func property_number(owner: Object, property: String, fallback: float = 0.0) -> float:
	var value: Variant = owner.get(property) if is_instance_valid(owner) else null
	return float(value) if valid_number(value) else fallback

static func resolve(owner: Object, target: Object, raw_amount: float, coefficient: float, pre: Dictionary, attack_hit: bool) -> float:
	var flat := 0.0
	var target_health := float(target.get_current_health()) if target.has_method("get_current_health") else 0.0
	var target_max := float(target.get_max_health()) if target.has_method("get_max_health") else property_number(target, "max_health", 1.0)
	var target_ratio := target_health / maxf(1.0, target_max)
	if target_ratio >= 0.8:
		flat += maxf(0.0, property_number(owner, "first_strike_bonus_damage"))
	if target_ratio < 0.55:
		flat += maxf(0.0, property_number(owner, "severing_edge_bonus_damage"))
	var owner_health := float(owner.get_current_health()) if owner.has_method("get_current_health") else (float(owner._get_current_health()) if owner.has_method("_get_current_health") else property_number(owner, "max_health", 1.0))
	var owner_max := float(owner.get_max_health()) if owner.has_method("get_max_health") else property_number(owner, "max_health", 1.0)
	if owner_health / maxf(1.0, owner_max) <= 0.5:
		flat += maxf(0.0, property_number(owner, "bloodpact_bonus_damage"))
	var amount := raw_amount + coefficient * flat
	var mark_ratio := maxf(0.0, float(pre.get("mark_ratio", 0.0)))
	if mark_ratio > 0.0:
		var dread_ratio := maxf(0.0, property_number(owner, "dread_resonance_damage_ratio_per_stack")) * int(pre.get("dread_stacks", 0))
		amount *= 1.0 + mark_ratio + dread_ratio
	var snare_level := int(property_number(owner, "hunters_snare_stacks"))
	if bool(owner.get("reward_hunters_snare")) and bool(pre.get("slowed", false)) and (attack_hit or snare_level >= 2):
		amount *= 1.0 + maxf(0.0, property_number(owner, "hunters_snare_bonus_ratio"))
	var lacuna_power := property_number(owner, "void_echo_damage")
	if lacuna_power > 0.0 and owner.has_method("_shared_owned_field_contains") and owner._shared_owned_field_contains(target):
		amount *= 1.0 + 0.14 + lacuna_power * 0.0015
	if owner.has_method("_shared_mission_damage_multiplier"):
		var mission: Variant = owner._shared_mission_damage_multiplier()
		if valid_number(mission):
			amount *= maxf(0.0, float(mission))
	return amount

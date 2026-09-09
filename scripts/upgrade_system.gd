## Unified power application and stacking system
## Handles all upgrade and trial power effects + their scaling with stacks
## This is the most reusable system: can be called by player, test harness, console, etc.

extends Node

const KEYWORDS := preload("res://scripts/shared/combat_keyword_catalogue.gd")
const DESCRIPTION_CAP_GUARD := preload("res://scripts/shared/description_cap_guard.gd")
const POWER_PARAMETER_MAPPER := preload("res://scripts/power_parameter_mapper.gd")
const ARCANA_MOTION := preload("res://scripts/arcana_motion_controller.gd")
const RETURNING_CRESCENT := preload("res://scripts/returning_crescent_controller.gd")
const STATIC_WAKE := preload("res://scripts/static_wake_controller.gd")
const INDOMITABLE_OATH_FILL_REQUIREMENT: float = 52.0
const INDOMITABLE_OATH_DAMAGE_SCALE: float = 1.35

# Dependencies (injected)
var player_reference: Node = null
var game_state: Node = null  # GameStateManager instance
const POWER_REGISTRY_SCRIPT := preload("res://scripts/power_registry.gd")

var power_registry: POWER_REGISTRY_SCRIPT = null  # power_registry.gd instance
var upgrade_stacks: Dictionary = {}

# Track stacks for trial powers as backup when player_reference is unavailable
var trial_power_stacks: Dictionary = {}
var trial_power_prismatic_states: Dictionary = {}


func _ready() -> void:
	# Register as singleton or get injected
	pass


## Apply an upgrade (stat boost) to the player
func apply_upgrade(upgrade_id: String) -> bool:
	var id := upgrade_id.strip_edges().to_lower()
	if not is_instance_valid(player_reference):
		return false
	
	if not _is_upgrade_id(id):
		return false
	
	var current_stacks := get_upgrade_stack_count(id)
	var stack_limit := _get_power_stack_limit(id)
	if stack_limit > 0 and current_stacks >= stack_limit:
		return false

	var preview := _build_upgrade_preview(id)
	if preview.is_empty():
		return false

	# Track after verifying this upgrade can apply.
	if is_instance_valid(game_state):
		game_state.add_upgrade(id)
	upgrade_stacks[id] = current_stacks + 1

	match id:
		"first_strike", "heavy_blow", "wide_arc", "long_reach", "fleet_foot", "blink_dash", "battle_trance", "surge_step", "wardens_verdict", "lacuna_echo", "sovereign_tempo", "pillar_convergence", "unbroken_oath", "edict_of_the_court", "null_corridor", "ruinous_impact", "sovereigns_double":
			player_reference.set(String(preview.get("property", "")), preview.get("next", player_reference.get(String(preview.get("property", "")))))
		"heartstone":
			var next_max := int(preview.get("next", player_reference.get_max_health()))
			var current_max: int = int(player_reference.get_max_health())
			var max_gain := maxi(0, next_max - current_max)
			var next_current: int = int(player_reference.get_current_health()) + max_gain
			player_reference.set_max_health_and_current(next_max, next_current)
		"iron_skin":
			player_reference.set("iron_skin_armor", int(preview.get("next", int(player_reference.get("iron_skin_armor")))))
			player_reference.set("iron_skin_stacks", int(player_reference.get("iron_skin_stacks")) + 1)
		"bloodpact":
			player_reference.set("bloodpact_bonus_damage", int(preview.get("next", int(player_reference.get("bloodpact_bonus_damage")))))
		"severing_edge":
			player_reference.set("severing_edge_bonus_damage", int(preview.get("next", int(player_reference.get("severing_edge_bonus_damage")))))
		_:
			return false
	refresh_derived_trial_parameters(String(preview.get("property", "")))
	return true


## Refresh values derived from base stats without granting another stack or
## applying acquisition-only cooldown reductions again.
func refresh_derived_trial_parameters(changed_property: String = "") -> void:
	if not is_instance_valid(player_reference):
		return
	var derived_parameters := {}
	if changed_property.is_empty() or changed_property == "damage":
		derived_parameters["phantom_step"] = "damage"
		derived_parameters["static_wake"] = "damage"
	if changed_property.is_empty() or changed_property == "attack_arc_degrees":
		derived_parameters["razor_wind"] = "arc_degrees"
	for power_id: String in derived_parameters:
		if get_trial_power_stack_count(power_id) <= 0:
			continue
		var values := get_trial_runtime_values(power_id)
		var parameter: String = derived_parameters[power_id]
		var property_name := POWER_PARAMETER_MAPPER.get_property_name(power_id, parameter)
		if values.has(parameter) and not property_name.is_empty():
			player_reference.set(property_name, values[parameter])
	if changed_property.is_empty() or changed_property == "damage":
		reapply_derived_damage_coefficients()

## Restore analytic scaling without replaying Phantom's acquisition cooldown or
## replacing explicitly saved integer damage values.
func reapply_derived_damage_coefficients() -> void:
	if not is_instance_valid(player_reference) or not is_instance_valid(power_registry):
		return
	for power_id in ["phantom_step", "static_wake"]:
		var mapping: Dictionary = power_registry.get_trial_power_param_map(power_id)
		var level := get_trial_power_stack_count(power_id)
		if level <= 0:
			level = int(trial_power_stacks.get(power_id, 0))
		if level <= 0 and bool(player_reference.get(String(mapping.get("reward_flag", "")))):
			level = 1
		var property_name := POWER_PARAMETER_MAPPER.get_property_name(power_id, "damage_ratio")
		if level <= 0:
			player_reference.set(property_name, 0.0)
			continue
		var values := POWER_PARAMETER_MAPPER.build_trial_values(power_id, clampi(level, 1, 3), _get_power_balance_data(power_id), player_reference, has_trial_power_prismatic(power_id))
		player_reference.set(property_name, float(values.get("damage_ratio", 0.0)))


## Apply a trial power (combat ability) to the player
func apply_trial_power(power_id: String) -> bool:
	var id := power_id.strip_edges().to_lower()
	if not is_instance_valid(player_reference):
		return false
	
	if not _is_trial_power_id(id):
		return false
	var current_stack := get_trial_power_stack_count(id)
	var stack_limit := _get_power_stack_limit(id)
	var applying_prismatic := false
	var next_stack := current_stack + 1
	if stack_limit > 0 and current_stack >= stack_limit:
		if has_trial_power_prismatic(id):
			return false
		applying_prismatic = true
		next_stack = current_stack
	var next_values := POWER_PARAMETER_MAPPER.build_trial_values(id, next_stack, _get_power_balance_data(id), player_reference, applying_prismatic)
	if next_values.is_empty():
		return false
	
	# Use data-driven mapper to apply all parameter values to player
	var applied := POWER_PARAMETER_MAPPER.apply_trial_power_values(player_reference, id, next_stack, next_values)
	if not applied:
		return false
	if applying_prismatic:
		trial_power_prismatic_states[id] = true

	# Commit run-state tracking only after successful application.
	if is_instance_valid(game_state):
		game_state.add_trial_power(id)
	if not applying_prismatic:
		trial_power_stacks[id] = next_stack

	return true


## Apply any power (upgrade or trial power)
func apply_power(power_id: String) -> bool:
	var id := power_id.strip_edges().to_lower()
	
	if _is_upgrade_id(id):
		return apply_upgrade(id)
	elif _is_trial_power_id(id):
		return apply_trial_power(id)
	
	return false


## Apply multiple powers at once
func apply_powers(power_ids: Array[String]) -> Dictionary:
	var applied: Array[String] = []
	var unknown: Array[String] = []
	
	for power_id in power_ids:
		var id := power_id.strip_edges().to_lower()
		if id.is_empty():
			continue
		
		if apply_power(id):
			applied.append(id)
		else:
			unknown.append(id)
	
	return {
		"applied": applied,
		"unknown": unknown,
		"total_applied": applied.size()
	}


## Get current stack count for a trial power
func get_trial_power_stack_count(power_id: String) -> int:
	var id := power_id.strip_edges().to_lower()
	if is_instance_valid(player_reference):
		var stack_property := POWER_PARAMETER_MAPPER.get_stack_property(id)
		if not stack_property.is_empty():
			return int(player_reference.get(stack_property))
	if trial_power_stacks.has(id):
		return trial_power_stacks[id]
	return 0


func get_trial_runtime_values(power_id: String) -> Dictionary:
	var id := power_id.strip_edges().to_lower()
	if id.is_empty():
		return {}
	var stack_count := get_trial_power_stack_count(id)
	return POWER_PARAMETER_MAPPER.build_trial_values(id, stack_count, _get_power_balance_data(id), player_reference, has_trial_power_prismatic(id))


## Snapshot migration recalculates only these shared-status parameters. It never
## grants a pick, changes health or reapplies acquisition-time stat reductions.
func reapply_shared_power_parameters(power_id: String) -> bool:
	if not is_instance_valid(player_reference) or not is_instance_valid(power_registry) or power_id not in ["hunters_snare", "wraithstep", "eclipse_mark", "dread_resonance"]:
		return false
	var mapping: Dictionary = power_registry.get_trial_power_param_map(power_id)
	var level := get_trial_power_stack_count(power_id)
	if level <= 0:
		level = int(trial_power_stacks.get(power_id, 0))
	if level <= 0 and bool(player_reference.get(String(mapping.get("reward_flag", "")))):
		level = 1
	if level <= 0:
		return false
	level = clampi(level, 1, _get_power_stack_limit(power_id))
	var values := POWER_PARAMETER_MAPPER.build_trial_values(power_id, level, _get_power_balance_data(power_id), player_reference, has_trial_power_prismatic(power_id))
	return POWER_PARAMETER_MAPPER.apply_trial_power_values(player_reference, power_id, level, values)


func has_trial_power_prismatic(power_id: String) -> bool:
	var id := power_id.strip_edges().to_lower()
	return bool(trial_power_prismatic_states.get(id, false))


func can_claim_trial_power_prismatic(power_id: String) -> bool:
	var id := power_id.strip_edges().to_lower()
	if id.is_empty() or not _is_trial_power_id(id):
		return false
	if has_trial_power_prismatic(id):
		return false
	var stack_limit := _get_power_stack_limit(id)
	if stack_limit <= 0:
		return false
	return get_trial_power_stack_count(id) >= stack_limit


func _get_power_balance_data(power_id: String) -> Dictionary:
	if power_registry != null:
		return power_registry.get_power_balance(power_id) as Dictionary
	return {}


func get_power_damage_model(power_id: String) -> Dictionary:
	if power_registry != null:
		return power_registry.get_damage_model(power_id)
	return {
		"kind": "none",
		"scale_source": "none",
		"formula_note": "No direct damage"
	}


## Formats a single stat value for either the initial pick (green) or an upgrade (orange -> green).
## Use _stat("+%d", cur, nxt, is_initial) and embed the result in your description string.
func _stat(fmt: String, cur: Variant, nxt: Variant, is_initial: bool) -> String:
	if is_initial:
		return "[color=#7de882]%s[/color]" % (fmt % nxt)
	return "[color=#e8c96a]%s[/color] [color=#8899aa]->[/color] [color=#7de882]%s[/color]" % [fmt % cur, fmt % nxt]


func _initial_prefix(is_initial: bool) -> String:
	return "[color=#9ab8d8]Initial:[/color] " if is_initial else ""


func _const(value: String) -> String:
	return "[color=#7de882]%s[/color]" % value


func _current_const(value: String) -> String:
	return "[color=#e8c96a]%s[/color]" % value


func _current_stat(fmt: String, value: Variant) -> String:
	return "[color=#e8c96a]%s[/color]" % (fmt % value)


func _desc(is_initial: bool, flavor: String, template: String, args: Array = []) -> String:
	var body: String = template % args if not args.is_empty() else template
	return "%s[color=#9ab8d8]%s[/color] %s" % [_initial_prefix(is_initial), flavor, body]


func _reward_flavor_first_desc(is_initial: bool, flavor: String, body: String) -> String:
	return "[color=#9ab8d8]%s[/color]\n%s%s" % [flavor, _initial_prefix(is_initial), body]


# Player-facing terms follow docs/combat-wording.md; internal HIT is not a copy keyword.
func _power_sentence_template(power_id: String) -> String:
	match power_id:
		"first_strike":
			return "{kw:damage_stat} %s against enemies at 80%% HP or above."
		"heavy_blow":
			return "{kw:damage_stat} %s."
		"wide_arc":
			return "{kw:attack} arc %s."
		"long_reach":
			return "{kw:attack} range %s."
		"fleet_foot":
			return "Move speed %s."
		"blink_dash":
			return "{kw:dash} cooldown %s."
		"iron_skin":
			return "Armor %s."
		"battle_trance":
			return "{kw:damage|Dealing damage} grants %s move speed for %s."
		"surge_step":
			return "{kw:dash} speed %s."
		"heartstone":
			return "Max HP %s."
		"bloodpact":
			return "At 50%% HP or below, {kw:damage_stat} %s."
		"severing_edge":
			return "{kw:damage_stat} %s against enemies below 55%% HP."
		"wardens_verdict":
			return "Bonus damage %s; {kw:burst|burst} on 4th {kw:attack_hit}."
		"lacuna_echo":
			return "{kw:field} power %s, radius %s."
		"sovereign_tempo":
			return "Tempo per stack %s."
		"pillar_convergence":
			return "Every %s connected {kw:attack|attacks}; lasts %s; pulse every %s."
		"unbroken_oath":
			return "Damage reduction %s. Fill Oath at %s; next {kw:attack|attack} gains %s damage."
		"edict_of_the_court":
			return "{kw:push} force %s, scatter radius %s."
		"null_corridor":
			return "{kw:dash} {kw:field|trail}: {kw:push|push} and damage at most every 0.5s. Width %s; duration %s; {kw:damage_stat} %s."
		"ruinous_impact":
			return "Strikes {kw:launch|launch} foes; {kw:impact|impacts} {kw:burst|burst}. Bosses burst in place. {kw:damage_stat} %s; radius %s."
		"sovereigns_double":
			return "After {kw:dash|dash}/{kw:recoil|recoil}/{kw:orbit|orbit}: shade {kw:echo|echoes} next %s {kw:attack|attacks} at %s damage. Lasts %s."
		"razor_wind":
			return "Range %s, damage %s of hit, arc %s."
		"execution_edge":
			return "Every %s {kw:attack|attacks} for %s damage."
		"rupture_wave":
			return "{kw:burst} radius %s, damage %s of hit. %s"
		"aegis_field":
			return "Resist %s for %s, {kw:slow} pulse radius %s, cooldown %s."
		"hunters_snare":
			return "{kw:attack|Attacks} {kw:slow} %s at %s speed; %s damage vs {kw:slow|Slowed}. %s"
		"phantom_step":
			return "Damage %s, {kw:slow} %s."
		"riftpunch":
			return "Bonus damage %s, window %s, grace %s. %s"
		"reaper_step":
			return "Range/speed %s, {kw:kill|kill} refresh %s. %s"
		"static_wake":
			return "{kw:dash} {kw:field|trail}: %s {kw:electric} {kw:damage_stat}/s; lasts %s; radius %s. %s"
		"storm_crown":
			return "{kw:damage|Deal damage} %s times: %s lightning jumps; %s range; %s dmg. %s"
		"wraithstep":
			return "{kw:dash} {kw:mark} %s for %s; {kw:burst} %s. %s"
		"voidfire":
			return "Damage %s, detonate %s, lockout %s. %s"
		"dread_resonance":
			return "{kw:attack_hit|Attack hits} {kw:mark} 10%%/3s; +%s/stack vs {kw:mark|Marked}; cap %s."
		"bloodvow":
			return "Below %s HP, {kw:attack|attacks} deal x%s damage."
		"eclipse_mark":
			return "{kw:kill|Kills} {kw:mark} %s for %s; radius %s."
		"fracture_field":
			return "{kw:burst} length %s, damage %s, {kw:slow} %s."
		"farline_volley":
			return "Arc +%s/Volley, +%s dmg/Volley, cap %s. %s"
		"sigil_chain":
			return "{kw:field} radius %s, %s of {kw:damage_stat} per tick. %s"
		"blast_drive":
			return "Hold {kw:attack}; release: blast/{kw:recoil|recoil}. Full {kw:damage_stat} %s; reach %s. %s"
		"razor_orbit":
			return "Aim; Hold {kw:dash}: {kw:orbit|orbit} 1.4s or release. {kw:damage_stat} %s; reach %s. %s"
		"returning_crescent":
			return "{kw:attack} throws a returning {kw:projectile|blade}. {kw:damage_stat} %s each way; reach %s. %s"
		_:
			return ""


func _power_sentence(power_id: String, args: Array = [], surface: String = "") -> String:
	var template := _power_sentence_template(power_id)
	if template.is_empty():
		return ""
	var sentence: String = KEYWORDS.format_text(template % args if not args.is_empty() else template)
	if not surface.is_empty():
		return DESCRIPTION_CAP_GUARD.assert_visible_cap(sentence, power_id, surface)
	return sentence


func _flavor_detail(flavor: String, body: String) -> String:
	return "[color=#9ab8d8]%s[/color]\n    %s" % [flavor, body]


func _variant_to_number(value: Variant, fallback: float = 0.0) -> float:
	if value is float:
		return value
	if value is int:
		return value
	if value is String:
		var text := String(value).strip_edges()
		if text.is_empty():
			return fallback
		return text.to_float()
	return fallback


func _build_upgrade_preview(upgrade_id: String) -> Dictionary:
	if not is_instance_valid(player_reference):
		return {}
	var data := _get_power_balance_data(upgrade_id)
	if data.is_empty():
		return {}
	var property_name := String(data.get("property", ""))
	if property_name.is_empty():
		return {}

	var current_value: Variant = player_reference.get(property_name)
	var current_number := _variant_to_number(current_value)
	var next_value: Variant = current_value
	match String(data.get("kind", "")):
		"mul_min":
			next_value = maxf(_variant_to_number(data.get("min", 0.0)), current_number * _variant_to_number(data.get("mult", 1.0), 1.0))
		"add_int":
			next_value = floori(current_number) + floori(_variant_to_number(data.get("add", 0.0)))
		"add_float":
			next_value = current_number + _variant_to_number(data.get("add", 0.0))
		"add_clamp":
			next_value = clampf(
				current_number + _variant_to_number(data.get("add", 0.0)),
				_variant_to_number(data.get("min", -INF), -INF),
				_variant_to_number(data.get("max", INF), INF)
			)
		_:
			return {}

	return {
		"property": property_name,
		"current": current_value,
		"next": next_value,
		"data": data
	}


## Single source of truth for the flavor sentence of every power.
## Change a description here and it updates everywhere: reward cards and build detail.
func get_power_flavor_text(power_id: String) -> String:
	return KEYWORDS.format_text(_power_flavor_authored(power_id))


func _power_flavor_authored(power_id: String) -> String:
	match power_id:
		"wardens_verdict":
			return "Each consecutive {kw:attack_hit} deals more bonus damage. The fourth releases a {kw:burst} that damages nearby enemies."
		"lacuna_echo":
			return "{kw:kill|Kills} create a {kw:field} that {kw:pull|Pulls} foes and pulses damage. All your Fields gain its bonus once per target."
		"sovereign_tempo":
			return "{kw:attack_hit|Attack hits} build Tempo. Completing {kw:dash}, {kw:recoil} or {kw:orbit} releases one wave; damaged enemies refund dash cooldown."
		"pillar_convergence":
			return "Several {kw:attack_hit|attack hits} create a moving {kw:field} that pulses damage around you."
		"unbroken_oath":
			return "{kw:attack|Attacks} build Oath faster when they damage several foes. Fill the bar to empower your next Attack."
		"edict_of_the_court":
			return "{kw:kill|Kills} release a force {kw:burst} that {kw:push|Pushes} nearby enemies outward."
		"null_corridor":
			return "A {kw:dash} leaves a {kw:field}. Enemies inside take damage and are {kw:push|Pushed}, at most once every 0.5s."
		"ruinous_impact":
			return "Direct strikes {kw:launch|Launch} foes. Existing {kw:push|Pushes} and {kw:pull|Pulls} also enable {kw:impact} {kw:burst|Bursts}. Immovable foes compress in place."
		"sovereigns_double":
			return "Completing {kw:dash}, {kw:recoil} or {kw:orbit} leaves a shade that {kw:echo|Echoes} your next deliberate {kw:attack|Attacks}."
		"razor_wind":
			return "Each {kw:attack} extends a slicing arc that only strikes enemies past your normal melee reach."
		"execution_edge":
			return "Every few {kw:attack|Attacks}, an execution strike multiplies attack damage."
		"rupture_wave":
			return "{kw:attack_hit|Attack hits} send out {kw:burst|Bursts} that damage nearby enemies."
		"aegis_field":
			return "Periodically emits a pulse that applies {kw:slow} nearby and grants brief damage resistance."
		"hunters_snare":
			return "{kw:attack_hit|Attack hits} apply {kw:slow}. Already {kw:slow|Slowed} foes take more damage; level 2 extends the bonus to all your damage."
		"phantom_step":
			return "A {kw:dash} through enemies deals damage and applies {kw:slow}."
		"riftpunch":
			return "Ending a {kw:dash} primes your next {kw:attack_hit} for bonus damage and brief contact grace."
		"reaper_step":
			return "{kw:kill|Kills} fully refresh your {kw:dash}. Dash range and speed scale together."
		"static_wake":
			return "A {kw:dash} leaves an {kw:electric} {kw:field}. No {kw:attack} is needed."
		"storm_crown":
			return "{kw:damage|Dealing damage} charges {kw:electric} chain lightning. {kw:attack|Attacks}, {kw:dash} effects, {kw:projectile|Projectiles}, {kw:field|Fields} and {kw:echo|Echoes} can contribute."
		"wraithstep":
			return "A {kw:dash} applies {kw:mark}. From level 2, an {kw:attack_hit} against an already {kw:mark|Marked} foe releases one {kw:burst} per Attack; level 3 can continue through three more Marked foes."
		"voidfire":
			return "{kw:attack_hit|Attack hits} build Heat. The Danger Zone boosts Attack damage; overheating releases a {kw:burst} and briefly locks Attacks."
		"dread_resonance":
			return "{kw:attack_hit|Attack hits} apply {kw:mark} and build one resonance stack per foe per Attack. Each stack increases your damage against Marked foes. Stacks last until that enemy dies or you leave the room."
		"bloodvow":
			return "While wounded, every {kw:attack} hits harder. Lower HP, bigger windows."
		"eclipse_mark":
			return "{kw:kill|Kills} apply {kw:mark} to nearby foes. Marks amplify all player damage and expire with time, not hits."
		"fracture_field":
			return "{kw:kill|Kills} rupture fault-line {kw:burst|Bursts}, damaging and applying {kw:slow} along each line."
		"farline_volley":
			return "Direct {kw:attack_hit|attack hits} near your reach edge build Volley: wider Attacks and bonus damage. A {kw:dash} resets stacks."
		"sigil_chain":
			return "{kw:attack_hit|Attack hits} charge a sigil. Your next one places a damaging {kw:field}; chained Fields compound damage."
		"blast_drive":
			return "Hold {kw:attack}, then release a short, narrow {kw:burst} that launches you backward in {kw:recoil}. Taps still strike immediately."
		"razor_orbit":
			return "Aim at a foe, then hold {kw:dash} to {kw:orbit} and cut. Release to depart; {kw:attack} freely while orbiting."
		"returning_crescent":
			return "{kw:attack|Attacks} throw a {kw:projectile} that returns to your current position. Move to guide its return through enemies."
		_:
			return ""


## Current-state description for the build detail panel.
## Reads actual live player values — no stack approximations.
func get_power_current_description(power_id: String) -> String:
	if not is_instance_valid(player_reference):
		return ""
	var id := power_id.strip_edges().to_lower()
	var flavor := get_power_flavor_text(id)
	match id:
		"ruinous_impact":
			var stacks := clampi(int(player_reference.get("ruinous_impact_stacks")), 1, 2)
			return _power_sentence(id, [_current_stat("%.0f%%", 100.0 + 40.0 * (stacks - 1)), _current_stat("%.0f", 70.0 + 25.0 * (stacks - 1))], "build_detail")
		"sovereigns_double":
			return _power_sentence(id, [_current_stat("%d", clampi(int(player_reference.get("sovereigns_double_stacks")), 1, 2)), _current_const("55%"), _current_const("4s")], "build_detail")
		"blast_drive", "razor_orbit", "returning_crescent":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			var metrics := _motion_arcana_description_metrics(id, cur)
			return _power_sentence(id, [
				_current_stat("x%.2f" if id == "blast_drive" else "%.1f%%", metrics["damage"]),
				_current_stat("%.0f", metrics["reach"]),
				_motion_arcana_unlocks_for_stack(id, get_trial_power_stack_count(id))
			], "build_detail")
		"wardens_verdict":
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("+%d", int(player_reference.get("apex_predator_bonus_damage")))], "build_detail"))
		"lacuna_echo":
			var val := int(player_reference.get("void_echo_damage"))
			var radius := clampf(54.0 + float(val) * 0.6, 54.0, 110.0)
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%d", val), _current_stat("%.0f", radius)], "build_detail"))
		"sovereign_tempo":
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("+%.0f%%", float(player_reference.get("apex_momentum_speed_bonus")) * 100.0)], "build_detail"))
		"pillar_convergence":
			var cs_ratio := float(player_reference.get("convergence_surge_damage_ratio"))
			var cs_hits := maxi(2, 6 - int(round(cs_ratio * 8.0)))
			var cs_window := 1.2 + cs_ratio * 1.8
			var cs_pulse := maxf(0.14, 0.3 - cs_ratio * 0.25)
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%d", cs_hits), _current_stat("%.2fs", cs_window), _current_stat("%.2fs", cs_pulse)], "build_detail"))
		"unbroken_oath":
			var resist := float(player_reference.get("indomitable_spirit_damage_reduction")) * 100.0
			var fill_req := INDOMITABLE_OATH_FILL_REQUIREMENT
			var ratio := (1.8 + float(player_reference.get("indomitable_spirit_damage_reduction")) * 2.2 + fill_req * 0.009) * INDOMITABLE_OATH_DAMAGE_SCALE * 100.0
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%.0f%%", resist), _current_stat("%.0f", fill_req), _current_stat("%.0f%%", ratio)], "build_detail"))
		"edict_of_the_court":
			var edict_power := int(player_reference.get("edict_court_push_power"))
			var edict_radius := clampf(80.0 + float(edict_power) * 1.0, 80.0, 160.0)
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%.0f", float(edict_power) * 1.8 + 300.0), _current_stat("%.0f", edict_radius)], "build_detail"))
		"null_corridor":
			var nc_strength := float(player_reference.get("null_corridor_strength"))
			var nc_width := 32.0 + nc_strength * 14.0
			var nc_duration := 3.2 + nc_strength * 0.8
			var nc_bounce_ratio := 0.20 + nc_strength * 0.08
			var nc_bounce_dmg := maxi(1, int(round(float(player_reference.get("damage")) * nc_bounce_ratio)))
			return _power_sentence(id, [_current_stat("%.0f", nc_width), _current_stat("%.1fs", nc_duration), _current_stat("%d", nc_bounce_dmg)], "build_detail")
		"first_strike":
			return _power_sentence(id, [_current_stat("+%d", int(player_reference.get("first_strike_bonus_damage")))], "build_detail")
		"heavy_blow":
			return _power_sentence(id, [_current_stat("%d", int(player_reference.get("damage")))], "build_detail")
		"wide_arc":
			return _power_sentence(id, [_current_stat("%.0f deg", float(player_reference.get("attack_arc_degrees")))], "build_detail")
		"long_reach":
			return _power_sentence(id, [_current_stat("%.0f", float(player_reference.get("attack_range")))], "build_detail")
		"fleet_foot":
			return _power_sentence(id, [_current_stat("%.0f", float(player_reference.get("max_speed")))], "build_detail")
		"blink_dash":
			return _power_sentence(id, [_current_stat("%.2fs", float(player_reference.get("dash_cooldown")))], "build_detail")
		"iron_skin":
			return _power_sentence(id, [_current_stat("+%d", int(player_reference.get("iron_skin_armor")))], "build_detail")
		"battle_trance":
			var bt_duration := 1.25
			if player_reference.get("battle_trance_duration") != null:
				bt_duration = float(player_reference.get("battle_trance_duration"))
			return _power_sentence(id, [_current_stat("+%.0f%%", float(player_reference.get("battle_trance_move_speed_bonus")) * 100.0), _current_stat("%.2fs", bt_duration)], "build_detail")
		"surge_step":
			return _power_sentence(id, [_current_stat("%.0f", float(player_reference.get("dash_speed")))], "build_detail")
		"heartstone":
			return _power_sentence(id, [_current_stat("%d", int(player_reference.get("max_health")))], "build_detail")
		"bloodpact":
			return _power_sentence(id, [_current_stat("+%d", int(player_reference.get("bloodpact_bonus_damage")))], "build_detail")
		"severing_edge":
			return _power_sentence(id, [_current_stat("+%d", int(player_reference.get("severing_edge_bonus_damage")))], "build_detail")
		"razor_wind":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("x%.2f", float(cur.get("range_scale", 1.0))), _current_stat("%.0f%%", float(cur.get("damage_ratio", 0.0)) * 100.0), _current_stat("%.0f deg", float(cur.get("arc_degrees", 24.0)))], "build_detail"))
		"execution_edge":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%d", int(cur.get("every", 2))), _current_stat("x%.2f", float(cur.get("damage_mult", 1.0)))], "build_detail"))
		"rupture_wave":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			var rupture_unlocks := _rupture_wave_unlocks_for_stack(get_trial_power_stack_count(id))
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%.0f", float(cur.get("radius", 0.0))), _current_stat("%.0f%%", float(cur.get("damage_ratio", 0.0)) * 100.0), _current_const(rupture_unlocks)], "build_detail"))
		"aegis_field":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%.0f%%", float(cur.get("resist", 0.0)) * 100.0), _current_stat("%.2fs", float(cur.get("duration", 0.0))), _current_stat("%.0f", float(cur.get("radius", 0.0))), _current_stat("%.2fs", float(cur.get("cooldown", 0.0)))], "build_detail"))
		"hunters_snare":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			var hunters_unlocks := _hunters_snare_unlocks_for_stack(get_trial_power_stack_count(id))
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%.2fs", float(cur.get("slow_duration", 0.0))), _current_stat("%.0f%%", float(cur.get("slow_mult", 1.0)) * 100.0), _current_stat("+%.0f%%", float(cur.get("bonus_ratio", 0.0)) * 100.0), _current_const(hunters_unlocks)], "build_detail"))
		"phantom_step":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%d", int(cur.get("damage", 0))), _current_stat("%.2fs", float(cur.get("slow_duration", 0.0)))], "build_detail"))
		"riftpunch":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			var rp_unlocks := _riftpunch_unlocks_for_stack(get_trial_power_stack_count(id))
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("+%d", int(cur.get("bonus_damage", 0))), _current_stat("%.2fs", float(cur.get("window_duration", 0.0))), _current_stat("%.2fs", float(cur.get("grace_duration", 0.0))), _current_const(rp_unlocks)], "build_detail"))
		"reaper_step":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			var reaper_unlocks := _reaper_step_unlocks_for_stack(get_trial_power_stack_count(id))
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("x%.2f", float(cur.get("range_mult", 1.0))), _current_const("full"), _current_const(reaper_unlocks)], "build_detail"))
		"static_wake":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			var runtime_values := get_trial_runtime_values(id)
			var wake_unlocks := _static_wake_unlocks_for_stack(get_trial_power_stack_count(id))
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%.0f%%", float(runtime_values.get("damage_ratio", 0.0)) * STATIC_WAKE.DAMAGE_RATE * 100.0), _current_stat("%.2fs", float(cur.get("lifetime", 0.0))), _current_stat("%.0f", float(cur.get("trail_radius", 28.0))), _current_const(wake_unlocks)], "build_detail"))
		"storm_crown":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%d", int(cur.get("proc_every", 1))), _current_stat("%d", int(cur.get("chain_targets", 1))), _current_stat("%.0f", float(cur.get("chain_radius", 0.0))), _current_stat("%.0f%%", float(cur.get("damage_ratio", 0.0)) * 100.0), _current_const(_storm_crown_unlocks_for_stack(get_trial_power_stack_count(id)))], "build_detail"))
		"wraithstep":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			var ws_unlock := _wraithstep_unlocks_for_stack(get_trial_power_stack_count(id))
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("+%.0f%%", float(cur.get("bonus_ratio", 0.0)) * 100.0), _current_stat("%.2fs", float(cur.get("mark_duration", 0.0))), _current_stat("%.0f%%", float(cur.get("splash_ratio", 0.0)) * 100.0), ws_unlock], "build_detail"))
		"voidfire":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			var voidfire_unlocks := _voidfire_unlocks_for_stack(get_trial_power_stack_count(id))
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("+%.0f%%", float(cur.get("danger_zone_amp", 0.0)) * 100.0), _current_stat("%.0f%%", float(cur.get("detonate_ratio", 0.0)) * 100.0), _current_stat("%.2fs", float(cur.get("lockout_duration", 0.0))), _current_const(voidfire_unlocks)] , "build_detail"))
		"dread_resonance":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			var max_stacks_dr := int(player_reference.get("dread_resonance_max_stacks"))
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%.1f%%", float(cur.get("damage_ratio_per_stack", 0.0)) * 100.0), _current_const(str(max_stacks_dr))], "build_detail"))
		"bloodvow":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%.0f%%", float(cur.get("low_hp_threshold", 0.4)) * 100.0), _current_stat("%.2f", float(cur.get("damage_mult", 1.0)))], "build_detail"))
		"eclipse_mark":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			return _power_sentence(id, [_current_stat("+%.0f%%", float(cur.get("bonus_ratio", 0.0)) * 100.0), _current_stat("%.2fs", float(cur.get("mark_duration", 0.0))), _current_stat("%.0f", float(cur.get("radius", 0.0)))], "build_detail")
		"fracture_field":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%.0f", float(cur.get("radius", 0.0))), _current_stat("%.0f%%", float(cur.get("damage_ratio", 0.0)) * 100.0), _current_stat("%.2fs", float(cur.get("slow_duration", 0.0)))] , "build_detail"))
		"farline_volley":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			var fv_unlocks := _farline_volley_unlocks_for_stack(get_trial_power_stack_count(id))
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%.0f deg", float(cur.get("arc_per_stack", 0.0))), _current_stat("%d", int(cur.get("bonus_per_stack", 0))), _current_stat("%d", int(cur.get("stack_cap", 0))), _current_const(fv_unlocks)], "build_detail"))
		"sigil_chain":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			var sc_unlocks := _sigil_chain_unlocks_for_stack(get_trial_power_stack_count(id))
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%.0f", float(cur.get("radius", 0.0))), _current_stat("%.0f%%", float(cur.get("damage_ratio", 0.0)) * 100.0), _current_const(sc_unlocks)], "build_detail"))
		_:
			return ""


## Get trial power description with next stack info from the current player state.
func get_trial_power_card_description(power_id: String) -> String:
	if not is_instance_valid(player_reference):
		return "[color=#9ab8d8]Enhances this power.[/color]"
	var id := power_id.strip_edges().to_lower()
	var current_stack := get_trial_power_stack_count(id)
	var stack_limit := _get_power_stack_limit(id)
	var prismatic_preview := stack_limit > 0 and current_stack >= stack_limit and not has_trial_power_prismatic(id)
	var next_stack := current_stack if prismatic_preview else current_stack + 1
	var next_values := POWER_PARAMETER_MAPPER.build_trial_values(id, next_stack, _get_power_balance_data(id), player_reference, prismatic_preview)
	if next_values.is_empty():
		return "[color=#9ab8d8]Enhances this power.[/color]"
	var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
	var flavor := get_power_flavor_text(id)
	if prismatic_preview:
		flavor = "[color=#40C8B0]%s[/color]" % _get_trial_prismatic_blurb(id)
	var is_initial := current_stack <= 0
	match id:
		"blast_drive", "razor_orbit", "returning_crescent":
			var current_metrics := _motion_arcana_description_metrics(id, cur)
			var next_metrics := _motion_arcana_description_metrics(id, next_values)
			return _power_sentence(id, [
				_stat("x%.2f" if id == "blast_drive" else "%.1f%%", current_metrics["damage"], next_metrics["damage"], is_initial),
				_stat("%.0f", current_metrics["reach"], next_metrics["reach"], is_initial),
				_motion_arcana_unlocks_for_stack(id, next_stack)
			], "reward_card")
		"razor_wind":
			var range_stat := _stat("x%.2f", float(cur.get("range_scale", 1.0)), float(next_values.get("range_scale", 1.0)), is_initial)
			var damage_stat := _stat("%.0f%%", float(cur.get("damage_ratio", 0.0)) * 100.0, float(next_values.get("damage_ratio", 0.0)) * 100.0, is_initial)
			var arc_stat := _stat("%.0f deg", float(cur.get("arc_degrees", 24.0)), float(next_values.get("arc_degrees", 24.0)), is_initial)
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [range_stat, damage_stat, arc_stat], "reward_card"))
		"execution_edge":
			var every_stat := _stat("%d", int(cur.get("every", 2)), int(next_values.get("every", 2)), is_initial)
			var mult_stat := _stat("x%.2f", float(cur.get("damage_mult", 1.0)), float(next_values.get("damage_mult", 1.0)), is_initial)
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [every_stat, mult_stat], "reward_card"))
		"rupture_wave":
			var radius_stat := _stat("%.0f", float(cur.get("radius", 0.0)), float(next_values.get("radius", 0.0)), is_initial)
			var damage_stat := _stat("%.0f%%", float(cur.get("damage_ratio", 0.0)) * 100.0, float(next_values.get("damage_ratio", 0.0)) * 100.0, is_initial)
			var rw_unlock := _const(_rupture_wave_unlocks_for_stack(next_stack))
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [radius_stat, damage_stat, rw_unlock], "reward_card"))
		"aegis_field":
			var resist_stat := _stat("%.0f%%", float(cur.get("resist", 0.0)) * 100.0, float(next_values.get("resist", 0.0)) * 100.0, is_initial)
			var duration_stat := _stat("%.2fs", float(cur.get("duration", 0.0)), float(next_values.get("duration", 0.0)), is_initial)
			var radius_stat := _stat("%.0f", float(cur.get("radius", 0.0)), float(next_values.get("radius", 0.0)), is_initial)
			var cooldown_stat := _stat("%.2fs", float(cur.get("cooldown", 0.0)), float(next_values.get("cooldown", 0.0)), is_initial)
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [resist_stat, duration_stat, radius_stat, cooldown_stat], "reward_card"))
		"hunters_snare":
			var slow_stat := _stat("%.2fs", float(cur.get("slow_duration", 0.0)), float(next_values.get("slow_duration", 0.0)), is_initial)
			var speed_stat := _stat("%.0f%%", float(cur.get("slow_mult", 1.0)) * 100.0, float(next_values.get("slow_mult", 1.0)) * 100.0, is_initial)
			var bonus_stat := _stat("+%.0f%%", float(cur.get("bonus_ratio", 0.0)) * 100.0, float(next_values.get("bonus_ratio", 0.0)) * 100.0, is_initial)
			var hs_unlock := _const(_hunters_snare_unlocks_for_stack(next_stack))
			return _power_sentence(id, [slow_stat, speed_stat, bonus_stat, hs_unlock], "reward_card")
		"phantom_step":
			var damage_stat := _stat("%d", int(cur.get("damage", 0)), int(next_values.get("damage", 0)), is_initial)
			var slow_stat := _stat("%.2fs", float(cur.get("slow_duration", 0.0)), float(next_values.get("slow_duration", 0.0)), is_initial)
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [damage_stat, slow_stat], "reward_card"))
		"riftpunch":
			var bonus_stat := _stat("+%d", int(cur.get("bonus_damage", 0)), int(next_values.get("bonus_damage", 0)), is_initial)
			var window_stat := _stat("%.2fs", float(cur.get("window_duration", 0.0)), float(next_values.get("window_duration", 0.0)), is_initial)
			var grace_stat := _stat("%.2fs", float(cur.get("grace_duration", 0.0)), float(next_values.get("grace_duration", 0.0)), is_initial)
			var unlock_stat := _const(_riftpunch_unlocks_for_stack(next_stack))
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [bonus_stat, window_stat, grace_stat, unlock_stat], "reward_card"))
		"reaper_step":
			var range_stat := _stat("x%.2f", float(cur.get("range_mult", 1.0)), float(next_values.get("range_mult", 1.0)), is_initial)
			var rs_unlock := _const(_reaper_step_unlocks_for_stack(next_stack))
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [range_stat, _const("full"), rs_unlock], "reward_card"))
		"static_wake":
			var runtime_values := get_trial_runtime_values(id)
			var wake_damage_stat := _stat("%.0f%%", float(runtime_values.get("damage_ratio", 0.0)) * STATIC_WAKE.DAMAGE_RATE * 100.0, float(next_values.get("damage_ratio", 0.0)) * STATIC_WAKE.DAMAGE_RATE * 100.0, is_initial)
			var wake_life_stat := _stat("%.2fs", float(cur.get("lifetime", 0.0)), float(next_values.get("lifetime", 0.0)), is_initial)
			var wake_radius_stat := _stat("%.0f", float(cur.get("trail_radius", 28.0)), float(next_values.get("trail_radius", 28.0)), is_initial)
			var sw_unlock := _const(_static_wake_unlocks_for_stack(next_stack))
			return _power_sentence(id, [wake_damage_stat, wake_life_stat, wake_radius_stat, sw_unlock], "reward_card")
		"storm_crown":
			var every_stat := _stat("%d", int(cur.get("proc_every", 1)), int(next_values.get("proc_every", 1)), is_initial)
			var targets_stat := _stat("%d", int(cur.get("chain_targets", 1)), int(next_values.get("chain_targets", 1)), is_initial)
			var radius_stat := _stat("%.0f", float(cur.get("chain_radius", 0.0)), float(next_values.get("chain_radius", 0.0)), is_initial)
			var damage_stat := _stat("%.0f%%", float(cur.get("damage_ratio", 0.0)) * 100.0, float(next_values.get("damage_ratio", 0.0)) * 100.0, is_initial)
			return _power_sentence(id, [every_stat, targets_stat, radius_stat, damage_stat, _const(_storm_crown_unlocks_for_stack(next_stack))], "reward_card")
		"wraithstep":
			var mark_stat := _stat("%.2fs", float(cur.get("mark_duration", 0.0)), float(next_values.get("mark_duration", 0.0)), is_initial)
			var bonus_stat := _stat("+%.0f%%", float(cur.get("bonus_ratio", 0.0)) * 100.0, float(next_values.get("bonus_ratio", 0.0)) * 100.0, is_initial)
			var cleave_stat := _stat("%.0f%%", float(cur.get("splash_ratio", 0.0)) * 100.0, float(next_values.get("splash_ratio", 0.0)) * 100.0, is_initial)
			var unlock := _wraithstep_unlocks_for_stack(next_stack)
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [bonus_stat, mark_stat, cleave_stat, unlock], "reward_card"))
		"voidfire":
			var amp_stat := _stat("+%.0f%%", float(cur.get("danger_zone_amp", 0.0)) * 100.0, float(next_values.get("danger_zone_amp", 0.0)) * 100.0, is_initial)
			var det_stat := _stat("%.0f%%", float(cur.get("detonate_ratio", 0.0)) * 100.0, float(next_values.get("detonate_ratio", 0.0)) * 100.0, is_initial)
			var lockout_stat := _stat("%.2fs", float(cur.get("lockout_duration", 0.0)), float(next_values.get("lockout_duration", 0.0)), is_initial)
			var vf_unlock := _const(_voidfire_unlocks_for_stack(next_stack))
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [amp_stat, det_stat, lockout_stat, vf_unlock], "reward_card"))
		"dread_resonance":
			var bonus_stat := _stat("%.1f%%", float(cur.get("damage_ratio_per_stack", 0.0)) * 100.0, float(next_values.get("damage_ratio_per_stack", 0.0)) * 100.0, is_initial)
			var max_stacks_stat := _stat("%d", int(cur.get("max_stacks", int(player_reference.get("dread_resonance_max_stacks")))), int(next_values.get("max_stacks", int(player_reference.get("dread_resonance_max_stacks")))), is_initial)
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [bonus_stat, max_stacks_stat], "reward_card"))
		"bloodvow":
			var threshold_stat := _stat("%.0f%%", float(cur.get("low_hp_threshold", 0.4)) * 100.0, float(next_values.get("low_hp_threshold", 0.4)) * 100.0, is_initial)
			var mult_stat := _stat("%.2f", float(cur.get("damage_mult", 1.0)), float(next_values.get("damage_mult", 1.0)), is_initial)
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [threshold_stat, mult_stat], "reward_card"))
		"eclipse_mark":
			var radius_stat := _stat("%.0f", float(cur.get("radius", 0.0)), float(next_values.get("radius", 0.0)), is_initial)
			var dur_stat := _stat("%.2fs", float(cur.get("mark_duration", 0.0)), float(next_values.get("mark_duration", 0.0)), is_initial)
			var ratio_stat := _stat("%.0f%%", float(cur.get("bonus_ratio", 0.0)) * 100.0, float(next_values.get("bonus_ratio", 0.0)) * 100.0, is_initial)
			return _power_sentence(id, [ratio_stat, dur_stat, radius_stat], "reward_card")
		"fracture_field":
			var length_stat := _stat("%.0f", float(cur.get("radius", 0.0)), float(next_values.get("radius", 0.0)), is_initial)
			var damage_stat := _stat("%.0f%%", float(cur.get("damage_ratio", 0.0)) * 100.0, float(next_values.get("damage_ratio", 0.0)) * 100.0, is_initial)
			var slow_stat := _stat("%.2fs", float(cur.get("slow_duration", 0.0)), float(next_values.get("slow_duration", 0.0)), is_initial)
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [length_stat, damage_stat, slow_stat], "reward_card"))
		"farline_volley":
			var arc_stat := _stat("%.0f deg", float(cur.get("arc_per_stack", 0.0)), float(next_values.get("arc_per_stack", 0.0)), is_initial)
			var bonus_stat := _stat("%d", int(cur.get("bonus_per_stack", 0)), int(next_values.get("bonus_per_stack", 0)), is_initial)
			var cap_stat := _stat("%d", int(cur.get("stack_cap", 0)), int(next_values.get("stack_cap", 0)), is_initial)
			var fv_unlock := _const(_farline_volley_unlocks_for_stack(next_stack))
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [arc_stat, bonus_stat, cap_stat, fv_unlock], "reward_card"))
		"sigil_chain":
			var radius_stat := _stat("%.0f", float(cur.get("radius", 0.0)), float(next_values.get("radius", 0.0)), is_initial)
			var damage_stat := _stat("%.0f%%", float(cur.get("damage_ratio", 0.0)) * 100.0, float(next_values.get("damage_ratio", 0.0)) * 100.0, is_initial)
			var sc_unlock := _const(_sigil_chain_unlocks_for_stack(next_stack))
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [radius_stat, damage_stat, sc_unlock], "reward_card"))
		_:
			return "[color=#9ab8d8]Enhances this power.[/color]"


func get_upgrade_card_description(upgrade_id: String) -> String:
	if not is_instance_valid(player_reference):
		return "[color=#c8daf0]Upgrade your stats.[/color]"
	var id := upgrade_id.strip_edges().to_lower()
	var preview := _build_upgrade_preview(id)
	if preview.is_empty():
		return "[color=#c8daf0]Upgrade your stats.[/color]"
	var cur_val: Variant = preview.get("current")
	var next_val: Variant = preview.get("next")
	var flavor := get_power_flavor_text(id)
	match id:
		"first_strike", "bloodpact", "severing_edge", "iron_skin":
			return _power_sentence(id, [_stat("+%d", int(cur_val), int(next_val), false)], "reward_card")
		"heavy_blow", "heartstone":
			return _power_sentence(id, [_stat("%d", int(cur_val), int(next_val), false)], "reward_card")
		"wide_arc":
			return _power_sentence(id, [_stat("%.0f°", float(cur_val), float(next_val), false)], "reward_card")
		"long_reach", "fleet_foot", "surge_step":
			return _power_sentence(id, [_stat("%.0f", float(cur_val), float(next_val), false)], "reward_card")
		"blink_dash":
			return _power_sentence(id, [_stat("%.2fs", float(cur_val), float(next_val), false)], "reward_card")
		"battle_trance":
			return _power_sentence(id, [_stat("+%.0f%%", float(cur_val) * 100.0, float(next_val) * 100.0, false), _const("%.2fs" % float(player_reference.get("battle_trance_duration")))], "reward_card")
		"wardens_verdict":
			var is_initial := int(cur_val) == 0
			var stat := _stat("+%d", int(cur_val), int(next_val), is_initial)
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [stat], "reward_card"))
		"ruinous_impact":
			var is_initial := int(cur_val) == 0
			var current_stack := clampi(int(cur_val), 1, 2)
			var next_stack := clampi(int(next_val), 1, 2)
			return _power_sentence(id, [
				_stat("%.0f%%", 100.0 + 40.0 * (current_stack - 1), 100.0 + 40.0 * (next_stack - 1), is_initial),
				_stat("%.0f", 70.0 + 25.0 * (current_stack - 1), 70.0 + 25.0 * (next_stack - 1), is_initial)
			], "reward_card")
		"sovereigns_double":
			return _power_sentence(id, [_stat("%d", int(cur_val), clampi(int(next_val), 1, 2), int(cur_val) == 0), _const("55%"), _const("4s")], "reward_card")
		"lacuna_echo":
			var cur_void_echo := int(cur_val)
			var next_void_echo := int(next_val)
			var cur_echo_radius := clampf(54.0 + float(cur_void_echo) * 0.6, 54.0, 110.0)
			var next_echo_radius := clampf(54.0 + float(next_void_echo) * 0.6, 54.0, 110.0)
			var is_initial := cur_void_echo == 0
			var power_stat := _stat("+%d", cur_void_echo, next_void_echo, is_initial)
			var radius_stat := _stat("%.0f", cur_echo_radius, next_echo_radius, is_initial)
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [power_stat, radius_stat], "reward_card"))
		"sovereign_tempo":
			var cur_momentum := float(cur_val) * 100.0
			var next_momentum := float(next_val) * 100.0
			var is_initial := cur_momentum == 0.0
			var stat := _stat("+%.0f%%", cur_momentum, next_momentum, is_initial)
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [stat], "reward_card"))
		"pillar_convergence":
			var cur_ratio := float(cur_val)
			var next_ratio := float(next_val)
			var cur_hits_needed := maxi(2, 6 - int(round(cur_ratio * 8.0)))
			var next_hits_needed := maxi(2, 6 - int(round(next_ratio * 8.0)))
			var cur_window := 1.2 + cur_ratio * 1.8
			var next_window := 1.2 + next_ratio * 1.8
			var cur_pulse_every := maxf(0.14, 0.3 - cur_ratio * 0.25)
			var next_pulse_every := maxf(0.14, 0.3 - next_ratio * 0.25)
			var is_initial := cur_ratio == 0.0
			var hits_stat := _stat("%d", cur_hits_needed, next_hits_needed, is_initial)
			var window_stat := _stat("%.2fs", cur_window, next_window, is_initial)
			var pulse_stat := _stat("%.2fs", cur_pulse_every, next_pulse_every, is_initial)
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [hits_stat, window_stat, pulse_stat], "reward_card"))
		"unbroken_oath":
			var cur_resist := float(cur_val) * 100.0
			var next_resist := float(next_val) * 100.0
			var fill_req := INDOMITABLE_OATH_FILL_REQUIREMENT
			var cur_ratio := (1.8 + float(cur_val) * 2.2 + fill_req * 0.009) * INDOMITABLE_OATH_DAMAGE_SCALE * 100.0
			var next_ratio := (1.8 + float(next_val) * 2.2 + fill_req * 0.009) * INDOMITABLE_OATH_DAMAGE_SCALE * 100.0
			var is_initial := cur_resist == 0.0
			var resist_stat := _stat("%.0f%%", cur_resist, next_resist, is_initial)
			var fill_stat := _const("%.0f" % fill_req)
			var ratio_stat := _stat("%.0f%%", cur_ratio, next_ratio, is_initial)
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [resist_stat, fill_stat, ratio_stat], "reward_card"))
		"edict_of_the_court":
			var cur_edict := int(cur_val)
			var next_edict := int(next_val)
			var is_initial_edict := cur_edict == 0
			var cur_force := 300.0 + float(cur_edict) * 1.8
			var next_force := 300.0 + float(next_edict) * 1.8
			var cur_edict_radius := clampf(80.0 + float(cur_edict), 80.0, 160.0)
			var next_edict_radius := clampf(80.0 + float(next_edict), 80.0, 160.0)
			var force_stat := _stat("%.0f", cur_force, next_force, is_initial_edict)
			var radius_stat_e := _stat("%.0f", cur_edict_radius, next_edict_radius, is_initial_edict)
			return _reward_flavor_first_desc(is_initial_edict, flavor, _power_sentence(id, [force_stat, radius_stat_e], "reward_card"))
		"null_corridor":
			var cur_nc := float(cur_val)
			var next_nc := float(next_val)
			var is_initial_nc := cur_nc == 0.0
			var cur_nc_width := 32.0 + cur_nc * 14.0
			var next_nc_width := 32.0 + next_nc * 14.0
			var cur_nc_dur := 3.2 + cur_nc * 0.8
			var next_nc_dur := 3.2 + next_nc * 0.8
			var cur_nc_bounce_ratio := 0.20 + cur_nc * 0.08
			var next_nc_bounce_ratio := 0.20 + next_nc * 0.08
			var base_dmg := float(player_reference.get("damage")) if is_instance_valid(player_reference) else 20.0
			var cur_nc_dmg := maxi(1, int(round(base_dmg * cur_nc_bounce_ratio)))
			var next_nc_dmg := maxi(1, int(round(base_dmg * next_nc_bounce_ratio)))
			var width_stat := _stat("%.0f", cur_nc_width, next_nc_width, is_initial_nc)
			var dur_stat := _stat("%.1fs", cur_nc_dur, next_nc_dur, is_initial_nc)
			var dmg_stat := _stat("%d", cur_nc_dmg, next_nc_dmg, is_initial_nc)
			return _power_sentence(id, [width_stat, dur_stat, dmg_stat], "reward_card")
		_:
			return "[color=#c8daf0]Upgrade your stats.[/color]"


## Get all power IDs the player currently has
func get_player_powers() -> Dictionary:
	if is_instance_valid(game_state):
		return {
			"upgrades": game_state.upgrades_taken.duplicate(),
			"trial_powers": game_state.trial_powers_taken.duplicate()
		}
	return {
		"upgrades": [],
		"trial_powers": []
	}


## Build the final melee attack context after all applicable power rules are considered.
func build_melee_attack_context(base_damage: int, base_attack_range: float, base_attack_arc_degrees: float, execution_proc: bool, execution_damage_mult: float) -> Dictionary:
	var damage_mult := execution_damage_mult if execution_proc else 1.0
	return {
		"damage": maxi(1, int(round(float(base_damage) * damage_mult))),
		"range": base_attack_range,
		"arc_degrees": base_attack_arc_degrees,
		"damage_mult": damage_mult,
		"execution_proc": execution_proc
	}


## Build the final Razor Wind attack context from the already-resolved melee context.
func build_razor_wind_attack_context(melee_context: Dictionary, razor_wind_damage_ratio: float, razor_wind_range_scale: float, razor_wind_arc_degrees: float, fallback_damage: int, fallback_attack_range: float) -> Dictionary:
	var melee_damage := int(melee_context.get("damage", fallback_damage))
	return {
		"damage": maxi(1, int(round(float(melee_damage) * razor_wind_damage_ratio))),
		"range": float(melee_context.get("range", fallback_attack_range)) * razor_wind_range_scale,
		"arc_degrees": razor_wind_arc_degrees,
		"source_damage": melee_damage,
		"execution_proc": bool(melee_context.get("execution_proc", false))
	}


## Reset for new run
func reset() -> void:
	upgrade_stacks.clear()
	trial_power_stacks.clear()
	trial_power_prismatic_states.clear()
	
	if is_instance_valid(game_state):
		game_state.reset()


## Initialize with dependencies
func initialize(player: Node, state: Node, registry: Node) -> void:
	player_reference = player
	game_state = state
	power_registry = registry as POWER_REGISTRY_SCRIPT


func _riftpunch_unlocks_for_stack(stack_count: int) -> String:
	if stack_count >= 3:
		return "+{kw:slow|slow} +{kw:burst|shockwave}"
	if stack_count >= 2:
		return "+{kw:slow|slow}"
	return ""

func _rupture_wave_unlocks_for_stack(stack_count: int) -> String:
	if stack_count >= 3:
		return "+{kw:slow|slow} +chain"
	if stack_count >= 2:
		return "+{kw:slow|slow}"
	return ""

func _static_wake_unlocks_for_stack(stack_count: int) -> String:
	if stack_count >= 3:
		return "%d trails; {kw:slow|Slows}." % STATIC_WAKE.MAX_RIBBONS
	return "%d trails." % STATIC_WAKE.MAX_RIBBONS


func _storm_crown_unlocks_for_stack(stack_count: int) -> String:
	return "{kw:slow} +1 jump; 1/action." if stack_count >= 2 else "1/action."

func _reaper_step_unlocks_for_stack(stack_count: int) -> String:
	if stack_count >= 3:
		return "+chain +grace"
	if stack_count >= 2:
		return "+chain"
	return ""

func _hunters_snare_unlocks_for_stack(stack_count: int) -> String:
	if stack_count >= 3:
		return "All; {kw:slow} x2."
	if stack_count >= 2:
		return "All damage."
	return "{kw:attack|Attack} only."

func _voidfire_unlocks_for_stack(stack_count: int) -> String:
	if stack_count >= 3:
		return "+half lockout"
	return ""

func _farline_volley_unlocks_for_stack(stack_count: int) -> String:
	if stack_count >= 3:
		return "+{kw:slow|slow} +{kw:dash|dash} {kw:burst|burst}"
	if stack_count >= 2:
		return "+{kw:slow|slow}"
	return ""

func _sigil_chain_unlocks_for_stack(stack_count: int) -> String:
	if stack_count >= 3:
		return "+slow +chain bonus | Hexweaver: detonates burst"
	if stack_count >= 2:
		return "+slow | Hexweaver: detonates burst"
	return "Hexweaver: detonates burst"


## Describe the actual hit/anchor dimensions, not the internal level multiplier.
## Use the runtime's constants so a later tuning change reaches every UI surface.
func _motion_arcana_description_metrics(power_id: String, values: Dictionary) -> Dictionary:
	var damage_scale := float(values.get("damage_scale", 1.0))
	var reach_scale := float(values.get("reach_scale", 1.0))
	if power_id == "blast_drive":
		return {"damage": ARCANA_MOTION.BLAST_DAMAGE_MULT_MAX * damage_scale, "reach": ARCANA_MOTION.BLAST_RANGE_MAX * reach_scale}
	if power_id == "returning_crescent":
		return {"damage": RETURNING_CRESCENT.DAMAGE_RATIO * 100.0 * damage_scale, "reach": RETURNING_CRESCENT.OUTBOUND_DISTANCE * reach_scale}
	return {"damage": ARCANA_MOTION.ORBIT_CUT_DAMAGE_RATIO * 100.0 * damage_scale, "reach": ARCANA_MOTION.ORBIT_ACQUIRE_RANGE * reach_scale}


func _motion_arcana_unlocks_for_stack(power_id: String, stack_count: int) -> String:
	if power_id == "returning_crescent":
		if stack_count >= 3:
			return "2 blades; wall bounce."
		return "2 blades." if stack_count >= 2 else "1 blade."
	if power_id == "blast_drive":
		if stack_count >= 3:
			return "2 charges; steer."
		return "2 charges." if stack_count >= 2 else "1 charge."
	if stack_count >= 3:
		return "Columns; kill transfer 2.4s."
	return "Foes + columns." if stack_count >= 2 else "Aim at a foe."


func _get_trial_prismatic_blurb(power_id: String) -> String:
	match power_id:
		"razor_wind":
			return "wider arcs, harder crescents"
		"execution_edge":
			return "every attack is an execution strike"
		"rupture_wave":
			return "shockwaves hit as hard as the blow"
		"aegis_field":
			return "stronger guard, denser control"
		"hunters_snare":
			return "near-freeze slow, punishing bonus"
		"phantom_step":
			return "dash strikes hit far harder"
		"riftpunch":
			return "finisher lands with crushing force"
		"reaper_step":
			return "longer chain, deeper grace"
		"static_wake":
			return "wake fields deal heavy damage"
		"storm_crown":
			return "lightning hits harder, forks wider"
		"wraithstep":
			return "marks punish, splashes overwhelm"
		"voidfire":
			return "danger zone surges, blasts dominate"
		"dread_resonance":
			return "deeper pool, harder stacks"
		"bloodvow":
			return "frenzy activates at safer bands"
		"eclipse_mark":
			return "marks land near-double damage"
		"fracture_field":
			return "fault lines tear through enemies"
		"farline_volley":
			return "wider arc, higher stack ceiling"
		"sigil_chain":
			return "zones deal devastating tick damage"
		"blast_drive":
			return "harder blasts, farther reach"
		"razor_orbit":
			return "deeper cuts, farther anchors"
		"returning_crescent":
			return "stronger blades, longer return paths"
		_:
			return "empowered beyond mastery"

func get_upgrade_stack_count(upgrade_id: String) -> int:
	var id := upgrade_id.strip_edges().to_lower()
	if is_instance_valid(game_state):
		return int(game_state.get_upgrade_stack_count(id))
	return int(upgrade_stacks.get(id, 0))


func _get_power_stack_limit(power_id: String) -> int:
	if power_registry != null:
		return int(power_registry.get_power_stack_limit(power_id))
	return 0

func _is_upgrade_id(power_id: String) -> bool:
	if power_registry != null:
		return bool(power_registry.is_upgrade(power_id))
	return false

func _is_trial_power_id(power_id: String) -> bool:
	if power_registry != null:
		return bool(power_registry.is_trial_power(power_id))
	return false


func _wraithstep_unlocks_for_stack(stack_count: int) -> String:
	if stack_count >= 3:
		return "Chain +3."
	if stack_count >= 2:
		return "1/Attack."
	return "From L2."

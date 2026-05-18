## Unified power application and stacking system
## Handles all upgrade and trial power effects + their scaling with stacks
## This is the most reusable system: can be called by player, test harness, console, etc.

extends Node

const DESCRIPTION_CAP_GUARD := preload("res://scripts/shared/description_cap_guard.gd")
const POWER_PARAMETER_MAPPER := preload("res://scripts/power_parameter_mapper.gd")
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

	# Apply upgrade using data-driven mapper (removes hard-coded logic)
	var applied := POWER_PARAMETER_MAPPER.apply_upgrade_values(player_reference, id)
	if not applied:
		return false

	# Track after successful application
	if is_instance_valid(game_state):
		game_state.add_upgrade(id)
	upgrade_stacks[id] = current_stacks + 1

	return true


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


func _power_sentence_template(power_id: String) -> String:
	match power_id:
		"first_strike":
			return "Extra hit damage vs enemies above 80%% HP %s."
		"heavy_blow":
			return "Damage %s."
		"wide_arc":
			return "Attack arc %s."
		"long_reach":
			return "Attack range %s."
		"fleet_foot":
			return "Move speed %s."
		"blink_dash":
			return "Dash cooldown %s."
		"iron_skin":
			return "Armor %s."
		"battle_trance":
			return "On hit gain %s move speed for %s."
		"surge_step":
			return "Dash speed %s."
		"heartstone":
			return "Max HP %s."
		"bloodpact":
			return "While below 50%% HP, +%s damage on every hit."
		"severing_edge":
			return "Bonus damage on hits against enemies below 55%% HP %s."
		"wardens_verdict":
			return "Bonus damage %s; powers 4th-hit burst."
		"lacuna_echo":
			return "Zone power %s, radius %s."
		"sovereign_tempo":
			return "Tempo per stack %s."
		"pillar_convergence":
			return "Every %s hits, lasts %s, pulses every %s."
		"unbroken_oath":
			return "Damage reduction %s. Fill Oath at %s; next hit deals %s bonus damage."
		"edict_of_the_court":
			return "Push force %s, scatter radius %s."
		"null_corridor":
			return "Trail width %s, duration %s, deflect %s dmg."
		"razor_wind":
			return "Range %s, damage %s of hit, arc %s."
		"execution_edge":
			return "Every %s swings for %s damage."
		"rupture_wave":
			return "Radius %s, damage %s of hit. %s"
		"aegis_field":
			return "Resist %s for %s, pulse radius %s, cooldown %s."
		"hunters_snare":
			return "Slow %s at %s speed, extra hit damage %s. %s"
		"phantom_step":
			return "Damage %s, slow %s."
		"riftpunch":
			return "Bonus damage %s, window %s, grace %s. %s"
		"reaper_step":
			return "Range/speed %s, kill refresh %s. %s"
		"static_wake":
			return "Damage %s of dmg, lasts %s, radius %s. %s"
		"storm_crown":
			return "Every %s hits, chains to %s targets within %s, for %s damage."
		"wraithstep":
			return "Mark %s, marked-hit damage %s, cleave %s, lasts %s hits."
		"voidfire":
			return "Damage %s, detonate %s, lockout %s. %s"
		"dread_resonance":
			return "Bonus per resonance stack %s, up to %s stacks."
		"bloodvow":
			return "Below %s HP, attacks deal x%s damage."
		"eclipse_mark":
			return "Mark radius %s, duration %s, bonus %s of hit, lasts %s hits."
		"fracture_field":
			return "Length %s, damage %s, slow %s."
		"farline_volley":
			return "Arc +%s/Volley, +%s dmg/Volley, cap %s. %s"
		"sigil_chain":
			return "Radius %s, %s of hit per tick. %s"
		_:
			return ""


func _power_sentence(power_id: String, args: Array = [], surface: String = "") -> String:
	var template := _power_sentence_template(power_id)
	if template.is_empty():
		return ""
	var sentence: String = template % args if not args.is_empty() else template
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
	match power_id:
		"wardens_verdict":
			return "Each consecutive hit deals more bonus damage. The 4th hit detonates a burst that hits nearby enemies."
		"lacuna_echo":
			return "Kills create a void zone that yanks in nearby enemies and pulses damage."
		"sovereign_tempo":
			return "Hits build tempo. Ending a dash releases a wave; hits refund dash cooldown."
		"pillar_convergence":
			return "Every few damaging hits you enter Convergence, pulsing damage around you until it expires."
		"unbroken_oath":
			return "Single hits trickle Oath; multihits scale exponentially. Fill the bar, then unleash a massive sword strike."
		"edict_of_the_court":
			return "Kills detonate a force pulse at the kill position, pushing nearby enemies outward."
		"null_corridor":
			return "Dashes leave a void corridor. Enemies that enter are deflected and take damage once."
		"razor_wind":
			return "Each swing extends a slicing arc that only strikes enemies past your normal melee reach."
		"execution_edge":
			return "Every few swings, an execution strike multiplies hit damage."
		"rupture_wave":
			return "Hits send a shockwave rippling outward, damaging all nearby enemies."
		"aegis_field":
			return "Periodically emits a guard pulse that slows nearby enemies and grants brief damage resistance."
		"hunters_snare":
			return "Hits slow enemies. Striking slowed targets deals extra hit damage."
		"phantom_step":
			return "Dashing through enemies deals damage and leaves them slowed."
		"riftpunch":
			return "Ending a dash primes a finisher: your next melee hit deals bonus damage and grants brief contact grace."
		"reaper_step":
			return "Kills fully refresh your dash. Dash range and speed scale together."
		"static_wake":
			return "Dashing leaves an electrified trail that shocks any enemy who steps into it."
		"storm_crown":
			return "Every few hits discharge chain lightning from your target to nearby foes."
		"wraithstep":
			return "Dash marks enemies. Marked hits deal extra hit damage and chain-splash nearby foes."
		"voidfire":
			return "Heat attacks. Danger Zone boosts hit damage. At cap, overheat detonates and briefly locks attacks."
		"dread_resonance":
			return "Chain hits on one enemy build resonance. Swapping targets resets to 1."
		"bloodvow":
			return "While wounded, every strike hits harder. Lower HP, bigger windows."
		"eclipse_mark":
			return "Kills inflicted by hits mark nearby enemies. First hit on each deals bonus damage."
		"fracture_field":
			return "Kills inflicted by hits rupture fault lines from the slain enemy, striking enemies along each line."
		"farline_volley":
			return "Hits at the edge of your reach build Volley: wider arc and flat bonus damage. Dashing resets stacks."
		"sigil_chain":
			return "Hits charge a sigil. The next strike drops a brief zone — chain zones to compound damage."
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
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%.0f", nc_width), _current_stat("%.1fs", nc_duration), _current_stat("%d", nc_bounce_dmg)], "build_detail"))
		"first_strike":
			return _power_sentence(id, [_current_stat("+%d", int(player_reference.get("first_strike_bonus_damage")))], "build_detail")
		"heavy_blow":
			return _power_sentence(id, [_current_stat("+%d", 7 * get_upgrade_stack_count("heavy_blow"))], "build_detail")
		"wide_arc":
			return _power_sentence(id, [_current_stat("+%d deg", 28 * get_upgrade_stack_count("wide_arc"))], "build_detail")
		"long_reach":
			return _power_sentence(id, [_current_stat("+%d", 11 * get_upgrade_stack_count("long_reach"))], "build_detail")
		"fleet_foot":
			return _power_sentence(id, [_current_stat("+%d", 17 * get_upgrade_stack_count("fleet_foot"))], "build_detail")
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
			return _power_sentence(id, [_current_stat("+%d", 85 * get_upgrade_stack_count("surge_step"))], "build_detail")
		"heartstone":
			return _power_sentence(id, [_current_stat("+%d", 10 * get_upgrade_stack_count("heartstone"))], "build_detail")
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
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%.2fs", float(cur.get("slow_duration", 0.0))), _current_stat("%.0f%%", float(cur.get("slow_mult", 1.0)) * 100.0), _current_stat("+%d", int(cur.get("bonus_damage", 0))), _current_const(hunters_unlocks)], "build_detail"))
		"phantom_step":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%.0f%%", float(cur.get("damage_ratio", 0.0)) * 100.0), _current_stat("%.2fs", float(cur.get("slow_duration", 0.0)))], "build_detail"))
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
			var wake_unlocks := _static_wake_unlocks_for_stack(get_trial_power_stack_count(id))
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%.0f%%", float(cur.get("damage_ratio", 0.0)) * 100.0), _current_stat("%.2fs", float(cur.get("lifetime", 0.0))), _current_stat("%.0f", float(cur.get("trail_radius", 28.0))), _current_const(wake_unlocks)], "build_detail"))
		"storm_crown":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%d", int(cur.get("proc_every", 1))), _current_stat("%d", int(cur.get("chain_targets", 1))), _current_stat("%.0f", float(cur.get("chain_radius", 0.0))), _current_stat("%.0f%%", float(cur.get("damage_ratio", 0.0)) * 100.0)], "build_detail"))
		"wraithstep":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			var ws_hits := _wraithstep_hits_for_stack(get_trial_power_stack_count(id))
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%.2fs", float(cur.get("mark_duration", 0.0))), _current_stat("+%d", int(cur.get("bonus_damage", 0))), _current_stat("%.0f%%", float(cur.get("splash_ratio", 0.0)) * 100.0), _current_stat("%d", ws_hits)], "build_detail"))
		"voidfire":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			var voidfire_unlocks := _voidfire_unlocks_for_stack(get_trial_power_stack_count(id))
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("+%.0f%%", float(cur.get("danger_zone_amp", 0.0)) * 100.0), _current_stat("%.0f%%", float(cur.get("detonate_ratio", 0.0)) * 100.0), _current_stat("%.2fs", float(cur.get("lockout_duration", 0.0))), _current_const(voidfire_unlocks)] , "build_detail"))
		"dread_resonance":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			var max_stacks_dr := int(player_reference.get("dread_resonance_max_stacks"))
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("+%d", int(cur.get("bonus_per_stack", 0))), _current_const(str(max_stacks_dr))], "build_detail"))
		"bloodvow":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%.0f%%", float(cur.get("low_hp_threshold", 0.4)) * 100.0), _current_stat("%.2f", float(cur.get("damage_mult", 1.0)))], "build_detail"))
		"eclipse_mark":
			var cur := POWER_PARAMETER_MAPPER.get_current_values(id, player_reference)
			var em_hits := _eclipse_hits_for_stack(get_trial_power_stack_count(id))
			return _flavor_detail(flavor, _power_sentence(id, [_current_stat("%.0f", float(cur.get("radius", 0.0))), _current_stat("%.2fs", float(cur.get("mark_duration", 0.0))), _current_stat("%.0f%%", float(cur.get("bonus_ratio", 0.0)) * 100.0), _current_stat("%d", em_hits)], "build_detail"))
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
			var bonus_stat := _stat("+%d", int(cur.get("bonus_damage", 0)), int(next_values.get("bonus_damage", 0)), is_initial)
			var hs_unlock := _const(_hunters_snare_unlocks_for_stack(next_stack))
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [slow_stat, speed_stat, bonus_stat, hs_unlock], "reward_card"))
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
			var wake_data := _get_power_balance_data("static_wake")
			var wake_ratio_base := float(wake_data.get("damage_ratio_base", 0.0))
			var wake_ratio_per_stack := float(wake_data.get("damage_ratio_per_stack", 0.0))
			var wake_damage_stat := _stat("%.0f%%", (wake_ratio_base + wake_ratio_per_stack * float(current_stack)) * 100.0, (wake_ratio_base + wake_ratio_per_stack * float(next_stack)) * 100.0, is_initial)
			var wake_life_stat := _stat("%.2fs", float(cur.get("lifetime", 0.0)), float(next_values.get("lifetime", 0.0)), is_initial)
			var wake_radius_stat := _stat("%.0f", float(cur.get("trail_radius", 28.0)), float(next_values.get("trail_radius", 28.0)), is_initial)
			var sw_unlock := _const(_static_wake_unlocks_for_stack(next_stack))
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [wake_damage_stat, wake_life_stat, wake_radius_stat, sw_unlock], "reward_card"))
		"storm_crown":
			var every_stat := _stat("%d", int(cur.get("proc_every", 1)), int(next_values.get("proc_every", 1)), is_initial)
			var targets_stat := _stat("%d", int(cur.get("chain_targets", 1)), int(next_values.get("chain_targets", 1)), is_initial)
			var radius_stat := _stat("%.0f", float(cur.get("chain_radius", 0.0)), float(next_values.get("chain_radius", 0.0)), is_initial)
			var damage_stat := _stat("%.0f%%", float(cur.get("damage_ratio", 0.0)) * 100.0, float(next_values.get("damage_ratio", 0.0)) * 100.0, is_initial)
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [every_stat, targets_stat, radius_stat, damage_stat], "reward_card"))
		"wraithstep":
			var mark_stat := _stat("%.2fs", float(cur.get("mark_duration", 0.0)), float(next_values.get("mark_duration", 0.0)), is_initial)
			var bonus_stat := _stat("+%d", int(cur.get("bonus_damage", 0)), int(next_values.get("bonus_damage", 0)), is_initial)
			var cleave_stat := _stat("%.0f%%", float(cur.get("splash_ratio", 0.0)) * 100.0, float(next_values.get("splash_ratio", 0.0)) * 100.0, is_initial)
			var hits_stat := _stat("%d", _wraithstep_hits_for_stack(current_stack), _wraithstep_hits_for_stack(next_stack), is_initial)
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [mark_stat, bonus_stat, cleave_stat, hits_stat], "reward_card"))
		"voidfire":
			var amp_stat := _stat("+%.0f%%", float(cur.get("danger_zone_amp", 0.0)) * 100.0, float(next_values.get("danger_zone_amp", 0.0)) * 100.0, is_initial)
			var det_stat := _stat("%.0f%%", float(cur.get("detonate_ratio", 0.0)) * 100.0, float(next_values.get("detonate_ratio", 0.0)) * 100.0, is_initial)
			var lockout_stat := _stat("%.2fs", float(cur.get("lockout_duration", 0.0)), float(next_values.get("lockout_duration", 0.0)), is_initial)
			var vf_unlock := _const(_voidfire_unlocks_for_stack(next_stack))
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [amp_stat, det_stat, lockout_stat, vf_unlock], "reward_card"))
		"dread_resonance":
			var bonus_stat := _stat("+%d", int(cur.get("bonus_per_stack", 0)), int(next_values.get("bonus_per_stack", 0)), is_initial)
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
			var hits_stat := _stat("%d", _eclipse_hits_for_stack(current_stack), _eclipse_hits_for_stack(next_stack), is_initial)
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [radius_stat, dur_stat, ratio_stat, hits_stat], "reward_card"))
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
		"first_strike":
			return "[color=#c8daf0]Extra hit damage vs enemies above 80%% HP:[/color] [color=#e8c96a]+%d[/color] [color=#8899aa]->[/color] [color=#7de882]+%d[/color]" % [int(cur_val), int(next_val)]
		"heavy_blow":
			return "[color=#c8daf0]Damage:[/color] [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color]" % [int(cur_val), int(next_val)]
		"wide_arc":
			var cur_arc := float(cur_val)
			var next_arc := float(next_val)
			return "[color=#c8daf0]Attack arc:[/color] [color=#e8c96a]%.0f°[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f°[/color]" % [cur_arc, next_arc]
		"long_reach":
			return "[color=#c8daf0]Attack range:[/color] [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color]" % [float(cur_val), float(next_val)]
		"fleet_foot":
			return "[color=#c8daf0]Move speed:[/color] [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color]" % [float(cur_val), float(next_val)]
		"blink_dash":
			var cur_dash_cd := float(cur_val)
			var next_dash_cd := float(next_val)
			return "[color=#c8daf0]Dash cooldown:[/color] [color=#e8c96a]%.2fs[/color] [color=#8899aa]->[/color] [color=#7de882]%.2fs[/color]" % [cur_dash_cd, next_dash_cd]
		"iron_skin":
			return "[color=#c8daf0]Armor:[/color] [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color]" % [int(cur_val), int(next_val)]
		"battle_trance":
			var cur_speed_bonus := float(cur_val) * 100.0
			var next_speed_bonus := float(next_val) * 100.0
			var trance_duration := 1.25
			if player_reference.get("battle_trance_duration") != null:
				trance_duration = float(player_reference.get("battle_trance_duration"))
			return "[color=#c8daf0]On hit:[/color] gain [color=#e8c96a]+%.0f%%[/color] [color=#8899aa]->[/color] [color=#7de882]+%.0f%%[/color] move speed for [color=#7de882]%.2fs[/color]." % [cur_speed_bonus, next_speed_bonus, trance_duration]
		"surge_step":
			return "[color=#c8daf0]Dash speed:[/color] [color=#e8c96a]%.0f[/color] [color=#8899aa]->[/color] [color=#7de882]%.0f[/color]" % [float(cur_val), float(next_val)]
		"heartstone":
			var cur_max := int(cur_val)
			var next_max := int(next_val)
			return "[color=#c8daf0]Max HP:[/color] [color=#e8c96a]%d[/color] [color=#8899aa]->[/color] [color=#7de882]%d[/color]" % [cur_max, next_max]
		"bloodpact":
			return "[color=#c8daf0]Below 50%% HP, +damage on every hit:[/color] [color=#e8c96a]+%d[/color] [color=#8899aa]->[/color] [color=#7de882]+%d[/color]" % [int(cur_val), int(next_val)]
		"severing_edge":
			return "[color=#c8daf0]Bonus damage on hits against enemies below 55%% HP:[/color] [color=#e8c96a]+%d[/color] [color=#8899aa]->[/color] [color=#7de882]+%d[/color]" % [int(cur_val), int(next_val)]
		"wardens_verdict":
			var is_initial := int(cur_val) == 0
			var stat := _stat("+%d", int(cur_val), int(next_val), is_initial)
			return _reward_flavor_first_desc(is_initial, flavor, _power_sentence(id, [stat], "reward_card"))
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
			return _reward_flavor_first_desc(is_initial_nc, flavor, _power_sentence(id, [width_stat, dur_stat, dmg_stat], "reward_card"))
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


func _eclipse_hits_for_stack(stack_count: int) -> int:
	return maxi(1, stack_count)

func _wraithstep_hits_for_stack(stack_count: int) -> int:
	if stack_count >= 3:
		return 2
	return 1

func _riftpunch_unlocks_for_stack(stack_count: int) -> String:
	if stack_count >= 3:
		return "+slow +shockwave"
	if stack_count >= 2:
		return "+slow"
	return ""

func _rupture_wave_unlocks_for_stack(stack_count: int) -> String:
	if stack_count >= 3:
		return "+slow +chain"
	if stack_count >= 2:
		return "+slow"
	return ""

func _static_wake_unlocks_for_stack(stack_count: int) -> String:
	if stack_count >= 3:
		return "+slow"
	return ""

func _reaper_step_unlocks_for_stack(stack_count: int) -> String:
	if stack_count >= 3:
		return "+chain +grace"
	if stack_count >= 2:
		return "+chain"
	return ""

func _hunters_snare_unlocks_for_stack(stack_count: int) -> String:
	if stack_count >= 3:
		return "+aoe +2x slow"
	if stack_count >= 2:
		return "+aoe"
	return ""

func _voidfire_unlocks_for_stack(stack_count: int) -> String:
	if stack_count >= 3:
		return "+half lockout"
	return ""

func _farline_volley_unlocks_for_stack(stack_count: int) -> String:
	if stack_count >= 3:
		return "+slow +dash burst"
	if stack_count >= 2:
		return "+slow"
	return ""

func _sigil_chain_unlocks_for_stack(stack_count: int) -> String:
	if stack_count >= 3:
		return "+slow +chain bonus | Hexweaver: detonates burst"
	if stack_count >= 2:
		return "+slow | Hexweaver: detonates burst"
	return "Hexweaver: detonates burst"


func _get_trial_prismatic_blurb(power_id: String) -> String:
	match power_id:
		"razor_wind":
			return "wider arcs, harder crescents"
		"execution_edge":
			return "every hit lands a finisher strike"
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

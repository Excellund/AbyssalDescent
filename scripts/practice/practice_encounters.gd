extends "res://scripts/encounter_profile_builder.gd"
## Selects an existing encounter identity without touching route or debug state.
const BOSS_CATALOGUE := preload("res://scripts/shared/boss_catalogue.gd")
const BOSS_STAGES := preload("res://scripts/shared/boss_stage_registry.gd")

const GOALS := {
	"skirmish": "Clear a small opening formation of pursuing foes.",
	"apex_trial": "Read Seamlock's attack cue and choose the correct response. Wrong guesses shrink the arena.",
	"apex_mirrorline": "Read Mirrorline's marked lanes and avoid its closing attacks.",
	"apex_toll": "Read Toll's ring and move through its safe opening.",
	"apex_breakwater": "Read Breakwater's sweeping pressure and use the gaps to approach.",
	"last_stand": "Survive the pressure and reach the kill quota. Missing the quota sends the fight into overtime.",
	"cut_the_signal": "Defeat the marked target. Kill its escorts to expose it before it relocates.",
	"hold_the_line": "Stay inside the control zone and clear contesting enemies until control is secured.",
	"circuit_sweep": "Capture each signal node in sequence while surviving the pursuers.",
	"pulse_window": "Reach the kill quota while recurring pulses change the enemies' combat rules.",
	"intercept_run": "Escort the drone to the end of its route. Stay nearby and clear foes blocking its path.",
	"relic_recovery": "Carry all three relics to the receiver. Picking up a new relic awakens its defenders.",
}
var selected_trial_mutator := ""

func roll_hard_enemy_mutator() -> Dictionary:
	if not selected_trial_mutator.is_empty():
		# The ordinary Trial builder must see this before choosing its base roster
		# and converting specialists. Raw registry damage is scaled exactly once.
		return _scale_mutator_damage(build_debug_mutator(selected_trial_mutator))
	return super.roll_hard_enemy_mutator()

func build_selected(id: String, depth: int) -> Dictionary:
	selected_trial_mutator = id.trim_prefix("trial_") if id.begins_with("trial_") else ""
	if id == "empty":
		return _build_profile("Empty arena", INTRO_ROOM_SIZE, 0, 0, 0, 0)
	if BOSS_CATALOGUE.NAMES.has(id):
		var descriptor := BOSS_STAGES.get_descriptor(BOSS_CATALOGUE.stage_for_id(id), id)
		var profile := _build_profile(descriptor.room_label, descriptor.room_size, 0, 0, 0, 0)
		profile["obstacle_layout"] = []
		profile["encounter_key"] = id
		return profile
	var profile: Dictionary
	if not selected_trial_mutator.is_empty():
		profile = _build_trial_profile(depth)
	elif id == "skirmish":
		# Keep the chosen Skirmish identity at later floors; the public random
		# skirmish route builder may choose a different named formation instead.
		profile = _build_intro_profile(depth)
	else:
		profile = build_debug_encounter_profile(id, depth)
	return apply_wave_staggering(profile)

static func entries() -> Array[Dictionary]:
	var rows: Array[Dictionary] = [{"id": "empty", "name": "Empty arena", "category": "training", "description": "Move and try your build without an encounter to clear."}]
	for entry: Dictionary in ENCOUNTER_CONTRACTS.debug_encounter_entries():
		var id := String(entry.key)
		if id in ["none", "rest", "tutorial", "random_objective", "trial"] or bool(entry.get("is_boss", false)):
			continue
		var category := "mission" if bool(entry.get("is_objective", false)) else ("apex" if id.begins_with("apex_") else "encounter")
		rows.append({"id": id, "name": ENCOUNTER_CONTRACTS.debug_encounter_glossary_name(id), "category": category,
			"description": _description(id)})
	var builder := new()
	for mutator: Dictionary in builder.get_hard_enemy_mutator_pool():
		var id := String(mutator[ENCOUNTER_CONTRACTS.MUTATOR_KEY_ICON_SHAPE_ID])
		rows.append({"id": "trial_" + id, "name": "Trial: " + String(mutator[ENCOUNTER_CONTRACTS.MUTATOR_KEY_NAME]), "category": "trial",
			"description": String(mutator.get(ENCOUNTER_CONTRACTS.MUTATOR_KEY_BANNER_SUFFIX, ""))})
	builder.free()
	for id: String in BOSS_CATALOGUE.NAMES:
		rows.append({"id": id, "name": BOSS_CATALOGUE.NAMES[id], "category": "boss", "description": "Defeat the boss through its normal combat phases."})
	return rows

static func _description(id: String) -> String:
	if GOALS.has(id):
		return GOALS[id]
	# Read the canonical formation identity without returning its mutable row.
	for definition: Dictionary in ENCOUNTER_CONTRACTS._get_encounter_registry():
		if definition.get("key", "") == id:
			return String(definition.get("identity", "Clear the encounter's enemies and waves."))
	return "Clear the encounter's enemies and waves."

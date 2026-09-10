## Oaths evaluator: pure dispatcher that scores oath completion against a run summary.
##
## Stateless. Reads a run summary dict (built by run_summary_tracker.build_summary)
## and the current meta-progress profile. Returns the list of oath ids newly completed
## by this run plus the catalysts/modifiers unlocked as rewards.
##
## Call site: scripts/core/run_summary_recorder.gd at run end, before history append.
## The caller is responsible for persisting completion via meta_progress_store.

extends RefCounted

const OATHS_REGISTRY := preload("res://scripts/progression/oaths_registry.gd")
const META_PROGRESS := preload("res://scripts/meta_progress_store.gd")
const CATALYST_REGISTRY := preload("res://scripts/progression/catalyst_registry.gd")
const ASCENSION_REGISTRY := preload("res://scripts/progression/ascension_modifier_registry.gd")
const BEARING_ENUMS := preload("res://scripts/shared/bearing_enums.gd")
const RUN_SUMMARY_TRACKER := preload("res://scripts/core/run_summary_tracker.gd")

## Returns a dict:
## {
##   "completed_oath_ids":  Array[String]   newly completed this run
##   "unlocked_catalyst_ids": Array[String] catalysts to unlock
##   "unlocked_modifier_ids": Array[String] ascension modifiers to surface as unlocked
##   "labels": Array[String]                human-readable labels for the run summary
## }
static func evaluate_run(run_summary: Dictionary, profile: Dictionary) -> Dictionary:
	var newly_completed: Array[String] = []
	var unlocked_catalysts: Array[String] = []
	var unlocked_modifiers: Array[String] = []
	var labels: Array[String] = []
	var existing_catalysts := META_PROGRESS.get_unlocked_catalyst_ids(profile)
	var existing_oaths := META_PROGRESS.get_completed_oath_ids(profile)
	var defs: Dictionary = OATHS_REGISTRY.get_all_definitions()
	for oath_id_variant in defs.keys():
		var oath_id: String = String(oath_id_variant)
		if OATHS_REGISTRY.is_completed(oath_id, existing_oaths):
			continue
		var def: Dictionary = defs[oath_id] as Dictionary
		if not _meets_bearing_requirement(def, run_summary):
			continue
		var key: String = String(def.get("evaluator_key", ""))
		var params: Dictionary = def.get("params", {}) as Dictionary
		if not _evaluate(key, params, run_summary):
			continue
		newly_completed.append(oath_id)
		var label: String = String(def.get("label", oath_id))
		labels.append("Oath Complete: %s" % label)
		var catalyst_id: String = String(def.get("reward_catalyst_id", ""))
		if not catalyst_id.is_empty() and not existing_catalysts.has(catalyst_id) and not unlocked_catalysts.has(catalyst_id):
			unlocked_catalysts.append(catalyst_id)
			var catalyst := CATALYST_REGISTRY.get_definition(catalyst_id)
			labels.append("Catalyst Unlocked: %s" % String(catalyst.get("label", catalyst_id)))
		var modifier_id: String = String(def.get("reward_modifier_id", ""))
		if not modifier_id.is_empty():
			unlocked_modifiers.append(modifier_id)
	return {
		"completed_oath_ids": newly_completed,
		"unlocked_catalyst_ids": unlocked_catalysts,
		"unlocked_modifier_ids": unlocked_modifiers,
		"labels": labels
	}

## Persist completion + reward unlocks back to the meta progress profile in place.
## Returns true if anything was changed (caller should save to disk).
static func apply_results_to_profile(profile: Dictionary, results: Dictionary) -> bool:
	var changed: bool = false
	for id_variant in results.get("completed_oath_ids", []):
		if META_PROGRESS.mark_oath_completed(profile, String(id_variant)):
			changed = true
	for id_variant in results.get("unlocked_catalyst_ids", []):
		if META_PROGRESS.unlock_catalyst(profile, String(id_variant)):
			changed = true
	# Modifier unlocks are inferred at read time from the completed oath set, so we
	# don't need a separate persistent flag — but we still want a one-time claim to
	# avoid showing the same "unlocked" toast twice.
	for id_variant in results.get("completed_oath_ids", []):
		if META_PROGRESS.mark_oath_reward_claimed(profile, String(id_variant)):
			changed = true
	return changed

# --- evaluator dispatch ---------------------------------------------------------------

static func _evaluate(key: String, params: Dictionary, run_summary: Dictionary) -> bool:
	# Completed milestones remain earned if the descent later ends in defeat.
	# The remaining Oaths require a full run clear.
	if key == "boss_no_hit":
		return _eval_boss_no_hit(params, run_summary)
	if key == "hold_zone_full_control":
		return _has_true_evidence(run_summary, "hold_full_control_achieved")
	if not _is_clear(run_summary):
		return false
	if key in ["win_single_arcana", "win_no_damage_taken", "win_no_primary_attack", "win_no_rest", "win_under_time_seconds", "win_no_catalysts", "win_no_dash", "win_modifier_loadout_no_rest"] and not _has_true_evidence(run_summary, "full_run_tracking_complete"):
		return false
	match key:
		"win_with_character_at_bearing":
			return _eval_character_at_bearing(params, run_summary)
		"win_single_arcana":
			var progress := _known_build_progress(run_summary, "arcana")
			return not progress.is_empty() and int(progress.unique_count) == 1
		"win_no_catalysts":
			var catalysts: Variant = run_summary.get("equipped_catalyst_ids")
			return _has_true_evidence(run_summary, "catalyst_tracking_complete") and catalysts is Array and catalysts.is_empty() and _has_true_evidence(run_summary, "ascension_tracking_complete") and _recorded_count_at_least(run_summary.get("ascension_rank"), int(params.get("minimum_ascension_rank", 1)))
		"win_no_dash":
			return _has_true_evidence(run_summary, "dash_tracking_complete") and _recorded_count_is(run_summary.get("dashes_performed"), 0)
		"win_modifier_loadout_no_rest":
			return _has_true_evidence(run_summary, "ascension_tracking_complete") and _recorded_ids_include(run_summary.get("ascension_loadout"), params.get("modifiers", [])) and _recorded_count_is(run_summary.get("rest_count"), 0)
		"win_bosses_no_hit":
			return _recorded_ids_include(run_summary.get("boss_no_hit_ids"), params.get("boss_ids", []))
		"ascension_rank_at_least":
			return _has_true_evidence(run_summary, "ascension_tracking_complete") and ASCENSION_REGISTRY.can_record_rank(run_summary) and _recorded_count_at_least(run_summary.get("ascension_rank"), int(params.get("rank", 1)))
		"win_under_time_seconds":
			var duration: Variant = run_summary.get("duration_seconds")
			return _recorded_count_at_least(duration, 0) and float(duration) < float(params.get("seconds", 0))
		"win_no_rest":
			return _recorded_count_is(run_summary.get("rest_count"), 0)
		"win_no_damage_taken":
			var stats: Variant = run_summary.get("stats")
			return stats is Dictionary and _recorded_count_is(stats.get("damage_taken_total"), 0)
		"win_no_primary_attack":
			return _recorded_count_is(run_summary.get("primary_attacks_fired"), 0)
		_:
			return false

## Unrestricted Oaths accept any real Bearing. Restricted Oaths require evidence
## of the lowest Bearing used throughout this run, including prior checkpoints.
static func _meets_bearing_requirement(definition: Dictionary, summary: Dictionary) -> bool:
	var actual := RUN_SUMMARY_TRACKER._validated_oath_tier(summary.get("difficulty_tier"))
	var required := RUN_SUMMARY_TRACKER._validated_oath_tier(definition.get("minimum_bearing_tier"))
	if bool(summary.get("is_debug", false)) or actual < 0 or required < 0:
		return false
	if not OATHS_REGISTRY.is_bearing_eligible(definition, actual):
		return false
	if required == BEARING_ENUMS.BearingTier.PILGRIM:
		return true
	# Use the same history proof as checkpoint restoration and co-op results.
	# Only older summaries with an explicit Forsworn proof can use the fallback.
	return RUN_SUMMARY_TRACKER._oath_minimum_from_summary(summary) >= required

static func _is_clear(run_summary: Dictionary) -> bool:
	var outcome: String = String(run_summary.get("outcome", "")).to_lower()
	return outcome == "clear" or outcome == "victory" or outcome == "win"

static func _eval_character_at_bearing(params: Dictionary, run_summary: Dictionary) -> bool:
	var want_char: String = String(params.get("character_id", "")).strip_edges().to_lower()
	var want_tier: int = int(params.get("bearing_tier", -1))
	var got_char: Variant = run_summary.get("character_id")
	return got_char is String and got_char.strip_edges().to_lower() == want_char and _recorded_count_is(run_summary.get("difficulty_tier"), want_tier)

static func _eval_boss_no_hit(params: Dictionary, run_summary: Dictionary) -> bool:
	var want_id: String = String(params.get("boss_id", "")).strip_edges().to_lower()
	if want_id.is_empty():
		return false
	return _recorded_ids_include(run_summary.get("boss_no_hit_ids"), [want_id])

static func _has_true_evidence(summary: Dictionary, key: String) -> bool:
	var raw: Variant = summary.get(key)
	return raw is bool and raw

static func _recorded_count_is(raw: Variant, expected: int) -> bool:
	return _recorded_count_at_least(raw, 0) and float(raw) == float(expected)

static func _recorded_count_at_least(raw: Variant, minimum: int) -> bool:
	if not (raw is int or raw is float):
		return false
	var count := float(raw)
	return is_finite(count) and count == floor(count) and count >= float(minimum)

static func _recorded_ids_include(raw: Variant, required: Array) -> bool:
	if not (raw is Array) or required.is_empty():
		return false
	var defeated: Array[String] = []
	for id in raw:
		if not (id is String):
			return false
		defeated.append(id.strip_edges().to_lower())
	for id in required:
		if not defeated.has(String(id)):
			return false
	return true

## Build discipline needs explicit, valid evidence. An absent category must
## not become an empty build, and repeated entries must not create extra Arcana.
static func _known_build_progress(run_summary: Dictionary, category: String) -> Dictionary:
	var build: Variant = run_summary.get("build_summary")
	if not (build is Dictionary):
		return {}
	var entries: Variant = build.get(category)
	if not (entries is Array):
		return {}
	var ids: Dictionary = {}
	var highest_stack := 0
	for entry in entries:
		if not (entry is Dictionary):
			return {}
		var id: Variant = entry.get("id")
		var stacks: Variant = entry.get("stacks")
		if not (id is String) or id.strip_edges().is_empty():
			return {}
		if not (stacks is int or stacks is float):
			return {}
		if not is_finite(float(stacks)) or float(stacks) < 1.0 or float(stacks) != floor(float(stacks)):
			return {}
		ids[id.strip_edges().to_lower()] = true
		highest_stack = maxi(highest_stack, int(stacks))
	return {"unique_count": ids.size(), "highest_stack": highest_stack}

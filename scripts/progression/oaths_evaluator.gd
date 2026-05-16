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
	var defs: Dictionary = OATHS_REGISTRY.get_all_definitions()
	for oath_id_variant in defs.keys():
		var oath_id: String = String(oath_id_variant)
		if META_PROGRESS.is_oath_completed(profile, oath_id):
			continue
		var def: Dictionary = defs[oath_id] as Dictionary
		var key: String = String(def.get("evaluator_key", ""))
		var params: Dictionary = def.get("params", {}) as Dictionary
		if not _evaluate(key, params, run_summary):
			continue
		newly_completed.append(oath_id)
		var label: String = String(def.get("label", oath_id))
		labels.append("Oath fulfilled: %s" % label)
		var catalyst_id: String = String(def.get("reward_catalyst_id", ""))
		if not catalyst_id.is_empty():
			unlocked_catalysts.append(catalyst_id)
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
	if not _is_clear(run_summary):
		# All current oaths require a clear; the only exception is the "ascension_rank_at_least"
		# which gates new content and should also require clear (otherwise dying on a high-rank
		# attempt would unlock content for free).
		return false
	match key:
		"win_with_character_at_bearing":
			return _eval_character_at_bearing(params, run_summary)
		"boss_no_hit":
			return _eval_boss_no_hit(params, run_summary)
		"win_no_boons":
			return _build_count(run_summary, "boons") == 0
		"win_no_arcana":
			return _build_count(run_summary, "arcana") == 0
		"win_single_arcana":
			return _build_unique_count(run_summary, "arcana") == 1
		"hold_zone_full_control":
			return bool(run_summary.get("hold_full_control_achieved", false))
		"ascension_rank_at_least":
			return int(run_summary.get("ascension_rank", 0)) >= int(params.get("rank", 1))
		"win_under_time_seconds":
			return int(run_summary.get("duration_seconds", 99999)) < int(params.get("seconds", 0))
		"win_no_rest":
			return int(run_summary.get("rest_count", 0)) == 0
		"win_no_damage_taken":
			var stats: Dictionary = run_summary.get("stats", {}) as Dictionary
			return int(stats.get("damage_taken_total", 1)) == 0
		"win_no_primary_attack":
			return int(run_summary.get("primary_attacks_fired", 1)) == 0
		_:
			return false

static func _is_clear(run_summary: Dictionary) -> bool:
	var outcome: String = String(run_summary.get("outcome", "")).to_lower()
	return outcome == "clear" or outcome == "victory" or outcome == "win"

static func _eval_character_at_bearing(params: Dictionary, run_summary: Dictionary) -> bool:
	var want_char: String = String(params.get("character_id", "")).strip_edges().to_lower()
	var want_tier: int = int(params.get("bearing_tier", -1))
	var got_char: String = String(run_summary.get("character_id", "")).strip_edges().to_lower()
	var got_tier: int = int(run_summary.get("difficulty_tier", -1))
	return got_char == want_char and got_tier == want_tier

static func _eval_boss_no_hit(params: Dictionary, run_summary: Dictionary) -> bool:
	var want_id: String = String(params.get("boss_id", "")).strip_edges().to_lower()
	if want_id.is_empty():
		return false
	var raw: Variant = run_summary.get("boss_no_hit_ids", [])
	if not (raw is Array):
		return false
	for entry in raw:
		if String(entry).strip_edges().to_lower() == want_id:
			return true
	return false

static func _build_count(run_summary: Dictionary, category: String) -> int:
	var build: Dictionary = run_summary.get("build_summary", {}) as Dictionary
	var raw: Variant = build.get(category, [])
	if not (raw is Array):
		return 0
	var total: int = 0
	for entry in raw:
		if entry is Dictionary:
			total += maxi(1, int((entry as Dictionary).get("stacks", 1)))
	return total

static func _build_unique_count(run_summary: Dictionary, category: String) -> int:
	var build: Dictionary = run_summary.get("build_summary", {}) as Dictionary
	var raw: Variant = build.get(category, [])
	if not (raw is Array):
		return 0
	return (raw as Array).size()

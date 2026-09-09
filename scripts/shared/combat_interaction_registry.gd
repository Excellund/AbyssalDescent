extends RefCounted
## Effect properties describe interactions; legacy damage/launch flags remain separate.

const HIT := 1
const DASH := 2
const ELECTRIC := 4
const CROWN_ANCESTRY := 1
const MAX_ROOTS := 256
const MAX_TARGETS_PER_ROOT := 256
const MAX_PENDING_HITS := 256

const EFFECT_TRAITS := {
	"melee": HIT, "razor_wind": HIT, "blast_drive": HIT,
	"farline_volley_burst": HIT, "riftpunch_shockwave": HIT,
	"rupture_wave": HIT, "wraithstep_chain": HIT, "wraithstep_splash": HIT,
	"phantom_step": HIT | DASH, "static_wake": HIT | DASH | ELECTRIC,
	"storm_crown": HIT | ELECTRIC, "veilstep_rhythm_wave": HIT | DASH,
	"overcharge_discharge": HIT, "iron_retort_shockwave": HIT,
	"voidfire_detonate": HIT, "sigil_chain_zone": HIT, "apex_predator_burst": HIT,
	"apex_momentum_wave": HIT | DASH, "void_echo_zone": HIT,
	"convergence_window": HIT, "null_corridor_deflect": HIT | DASH,
	"fracture_fault_line": HIT, "sigil_burst": HIT, "sigil_chain_detonate": HIT,
	"returning_crescent": HIT, "razor_orbit": HIT | DASH, "ruinous_impact": HIT,
	"sovereigns_double": HIT,
}

static func damage_context(action: Dictionary, source: String, extra: Dictionary = {}) -> Dictionary:
	var result := extra.duplicate()
	result["attack_type"] = source
	var interaction := action.duplicate()
	interaction["source"] = source
	interaction["traits"] = int(EFFECT_TRAITS.get(source, 0))
	if source == "sovereigns_double":
		var original := String(action.get("echo_source", action.get("source", "")))
		if original.is_empty():
			original = String(action.get("source", ""))
		interaction["echo_source"] = original if original != source else ""
		interaction["traits"] |= int(EFFECT_TRAITS.get(interaction.echo_source, 0))
	if source == "storm_crown":
		interaction["ancestry"] = int(interaction.get("ancestry", 0)) | CROWN_ANCESTRY
	result["interaction"] = interaction
	return result

static func current_run() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or not is_instance_valid(tree.current_scene):
		return ""
	if MultiplayerSessionManager.is_session_connected():
		return GameStateReplicationService.get_current_run_sync_token()
	return "solo:%d" % tree.current_scene.get_instance_id()

static func current_room() -> int:
	return EnemyReplicationService._current_room_sync_id()

## Ownership and trait bits are never accepted from caller-provided metadata.
static func validate_action(raw: Variant, authenticated_owner: int) -> Dictionary:
	if not (raw is Dictionary) or authenticated_owner <= 0:
		return {}
	for key in ["room", "owner", "seq", "epoch", "ancestry"]:
		if not (raw.get(key) is int):
			return {}
	if not (raw.get("run") is String) or not (raw.get("kind") is String):
		return {}
	var active_run := current_run()
	if active_run.is_empty() or raw.run != active_run or int(raw.room) != current_room():
		return {}
	if int(raw.owner) != authenticated_owner or int(raw.seq) <= 0 or int(raw.epoch) <= 0:
		return {}
	if String(raw.kind).is_empty() or String(raw.kind).length() > 48:
		return {}
	var source: Variant = raw.get("source", "")
	if not (source is String) or String(source).length() > 64:
		return {}
	var ancestry := int(raw.ancestry) & CROWN_ANCESTRY
	if source == "storm_crown":
		ancestry |= CROWN_ANCESTRY
	var traits := int(EFFECT_TRAITS.get(source, 0))
	var echo_source := ""
	if source == "sovereigns_double" and raw.get("echo_source") is String:
		echo_source = String(raw.echo_source)
		if echo_source != "sovereigns_double":
			traits |= int(EFFECT_TRAITS.get(echo_source, 0))
		if echo_source == "storm_crown":
			ancestry |= CROWN_ANCESTRY
	return {"run": active_run, "room": int(raw.room), "owner": authenticated_owner,
		"seq": int(raw.seq), "epoch": int(raw.epoch), "kind": String(raw.kind),
		"source": String(source), "traits": traits, "ancestry": ancestry, "echo_source": echo_source}

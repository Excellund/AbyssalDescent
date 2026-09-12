extends Node2D
## Practice adapter for the same terrain, cover and accepted Attack boundaries.
const CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const LAYOUTS := preload("res://scripts/shared/arena_layout_registry.gd")
const COVER := preload("res://scripts/core/arena_cover_controller.gd")
const RULES := preload("res://scripts/core/biome_rule_controller.gd")
const ACTIONS := preload("res://scripts/shared/combat_interaction_registry.gd")

var arena: Node2D
var cover := COVER.new()
var bodies: Dictionary = {}
var rules: RULES
var room_id := 0

func configure(owner_arena: Node2D, biome_id: String, profile: Dictionary, boss_arena: bool) -> void:
	arena = owner_arena
	room_id = arena.get_current_room_sync_id()
	var bounds := CONTRACTS.profile_room_size(profile)
	var layout := CONTRACTS.profile_obstacle_layout(profile)
	cover.reset(layout)
	for index in layout.size():
		var entry := layout[index]
		var body := StaticBody2D.new()
		body.position = entry.pos
		body.add_to_group("arena_columns")
		body.set_meta("column_radius", float(entry.radius))
		var shape := CircleShape2D.new()
		shape.radius = float(entry.radius)
		body.shape_owner_add_shape(body.create_shape_owner(body), shape)
		add_child(body)
		bodies[index + 1] = body
	rules = RULES.new()
	add_child(rules)
	rules.initialize(arena)
	rules.configure({"id": biome_id, "mode": _biome_mode(profile, boss_arena), "obstacles": layout,
		"shatter_fragments": biome_id == "shatterfield" and not cover.has_brittle_cover()}, bounds, ACTIONS.current_run(), room_id, room_id)
	refresh_geometry()

func tick(delta: float, active: bool, player: Node2D, enemies: Array) -> void:
	if is_instance_valid(rules):
		rules.set_room_context(arena.current_effective_room_size, arena._get_biome_objective_exclusions(), true)
		rules.tick(delta, active, [player] if is_instance_valid(player) else [], enemies, true)

func accept_attack(raw: Dictionary, origin: Vector2, direction: Vector2, blast_strength: float = -1.0) -> void:
	if not is_instance_valid(arena) or arena.mode != "active" or arena._transition_pending or room_id != arena.get_current_room_sync_id() or not cover.has_brittle_cover():
		return
	var player: Node = arena.player
	if not is_instance_valid(player) or player.is_dead() or not player.combat_damage_enabled or player.encounter_input_frozen:
		return
	if not origin.is_finite() or not direction.is_finite() or direction.length_squared() < 0.9 or direction.length_squared() > 1.1 or not is_finite(blast_strength):
		return
	var action := ACTIONS.validate_action(raw, maxi(1, player.player_id))
	var source := String(action.get("source", ""))
	if action.is_empty() or source not in ["melee", "blast_drive"] or action.kind != source or int(action.ancestry) != 0 or not player.combat_interactions.accepts_action(action):
		return
	var shapes: Array[Dictionary] = []
	if player.passive_effigy_command:
		var accepted: Dictionary = player.combat_interactions.get_attack_start(action)
		if accepted.is_empty() or origin.distance_to(accepted.origin) > 2.0 or direction.normalized().dot(accepted.direction) < 0.999:
			return
		for shape: Dictionary in (accepted.get("shapes", {}) as Dictionary).values():
			shapes.append(shape)
	else:
		if origin.distance_to(player.global_position) > 90.0:
			return
		var reach: float = player.attack_range
		var arc: float = player.attack_arc_degrees
		if source == "blast_drive":
			if not player.reward_blast_drive or blast_strength < 0.0 or blast_strength > 1.0:
				return
			reach = player.ARCANA_MOTION_SCRIPT.blast_range(blast_strength, player.blast_drive_reach_scale)
			arc = player.ARCANA_MOTION_SCRIPT.BLAST_ARC_DEGREES
		shapes.append(player._get_melee_attack_geometry({"range": reach, "arc_degrees": arc}))
		if player.reward_razor_wind:
			shapes.append({"range": reach * player.razor_wind_range_scale, "arc_degrees": player.razor_wind_arc_degrees, "inner": player.attack_range})
	var broken: Array[Vector2] = []
	for id in cover.contact_candidates(origin, direction.normalized(), shapes):
		if player.combat_interactions.claim_reaction(action, "brittle_cover", id) and cover.apply_contact(id):
			if not cover.is_present(id) and is_instance_valid(bodies.get(id)):
				broken.append(bodies[id].global_position)
	refresh_geometry()
	for center in broken:
		if arena.mode != "active" or room_id != arena.get_current_room_sync_id():
			break
		rules.release_shards(center, arena.get_live_enemies(), true)

func refresh_geometry() -> void:
	for id: int in bodies.keys():
		if cover.is_present(id):
			continue
		var body: StaticBody2D = bodies[id]
		body.remove_from_group("arena_columns")
		body.collision_layer = 0
		body.collision_mask = 0
		if is_instance_valid(arena.player) and arena.player.arcana_motion != null and arena.player.arcana_motion.anchor == body:
			arena.player.arcana_motion.detach(true)
		body.queue_free()
		bodies.erase(id)
	var live := cover.live_layout()
	if is_instance_valid(arena.renderer):
		arena.renderer.set_obstacle_layout(live)
		arena.renderer.set_cover_rubble_layout(cover.rubble_layout())
	if is_instance_valid(arena.enemy_spawner):
		arena.enemy_spawner.set_obstacle_circles(live)

func _biome_mode(profile: Dictionary, boss_arena: bool) -> String:
	if boss_arena or CONTRACTS.profile_encounter_key(profile).begins_with("apex_") or CONTRACTS.profile_seamlock_count(profile) > 0 or CONTRACTS.profile_mirrorline_count(profile) > 0 or CONTRACTS.profile_toll_count(profile) > 0 or CONTRACTS.profile_breakwater_count(profile) > 0:
		return "assistance"
	if CONTRACTS.profile_label(profile) in LAYOUTS.BIOME_TERRAIN_ENCOUNTERS and CONTRACTS.profile_objective_kind(profile).is_empty():
		return "ordinary"
	return "compact"

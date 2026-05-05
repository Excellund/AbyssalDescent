extends Node

const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")
const DEBUG_ENUMS := preload("res://scripts/shared/debug_enums.gd")

@export_group("Debug")
@export var enabled: bool = false
@export var force_update_prompt_on_menu: bool = false

@export_group("Startup")
@export var skip_starting_boon_selection: bool = false
@export_enum("None", "Rest Site", "Skirmish", "Crossfire", "Fortress", "Onslaught", "Vanguard", "Blitz", "Ambush", "Suppression", "Gauntlet", "Convergence", "Objective - Last Stand", "Objective - Cut the Signal", "Objective - Hold the Line", "Objective - Random", "Trial", "Warden", "Sovereign", "Lacuna") var start_encounter: int = DEBUG_ENUMS.Encounter.NONE
@export var start_depth: int = 1
@export_enum("No Override:-1", "Pilgrim:0", "Delver:1", "Harbinger:2", "Forsworn:3") var start_bearing: int = -1

@export_group("Mutator")
@export_enum("None", "Blood Rush", "Flashpoint", "Siegebreak", "Iron Volley", "Killbox", "Phase Collapse", "Conflagration", "Tether Web", "Random Hard") var mutator_override: int = DEBUG_ENUMS.MutatorOverride.NONE

@export_group("Powers")
@export var apply_test_powers_on_start: bool = false
@export_enum("None", "Dasher", "Bruiser", "Marksman") var start_power_preset: int = DEBUG_ENUMS.PowerPreset.NONE
@export var start_power_ids: PackedStringArray = PackedStringArray()

@export_group("End Screen")
@export_enum("None", "Victory", "Defeat") var end_screen_preview: int = DEBUG_ENUMS.EndScreenPreview.NONE
@export_enum("No Unlock:-1", "Pilgrim:0", "Delver:1", "Harbinger:2", "Forsworn:3") var victory_unlock_tier: int = -1

@export_group("Telemetry Spike")
@export var telemetry_spike_enabled: bool = false
@export var telemetry_spike_endpoint: String = ""
@export var telemetry_spike_api_key: String = ""
@export_range(3.0, 20.0, 0.5) var telemetry_spike_timeout_seconds: float = 8.0

@export_group("Network Stress Test")
@export var stress_test_enabled: bool = false
@export_range(5, 50, 1) var stress_test_initial_enemies: int = 10
@export_range(5, 30, 1) var stress_test_increment: int = 10
@export_range(20, 200, 5) var stress_test_max_enemies: int = 100
@export_range(30.0, 144.0, 1.0) var stress_test_drop_stop_below_fps: float = 75.0

@export_group("Multiplayer Perf Diagnostics")
@export var multiplayer_perf_logging_enabled: bool = false
@export var perf_attribution_enabled: bool = false
@export_range(250.0, 5000.0, 50.0) var perf_attribution_sample_ms: float = 1000.0

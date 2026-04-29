extends Node

const ENCOUNTER_CONTRACTS := preload("res://scripts/shared/encounter_contracts.gd")

const DEBUG_MUTATOR_NONE := 0
const DEBUG_MUTATOR_BLOOD_RUSH := 1
const DEBUG_MUTATOR_FLASHPOINT := 2
const DEBUG_MUTATOR_SIEGEBREAK := 3
const DEBUG_MUTATOR_IRON_VOLLEY := 4
const DEBUG_MUTATOR_KILLBOX := 5
const DEBUG_MUTATOR_RANDOM_HARD := 6
const DEBUG_END_SCREEN_NONE := 0
const DEBUG_END_SCREEN_VICTORY := 1
const DEBUG_END_SCREEN_DEFEAT := 2
const DEBUG_POWER_PRESET_NONE := 0

@export_group("Debug")
@export var enabled: bool = false

@export_group("Startup")
@export var skip_starting_boon_selection: bool = false
@export_enum("None", "Rest Site", "Skirmish", "Crossfire", "Fortress", "Onslaught", "Vanguard", "Blitz", "Ambush", "Suppression", "Gauntlet", "Objective - Last Stand", "Objective - Cut the Signal", "Objective - Hold the Line", "Objective - Random", "Trial", "Warden", "Sovereign") var start_encounter: int = ENCOUNTER_CONTRACTS.DEBUG_ENCOUNTER_NONE
@export var start_depth: int = 1
@export_enum("No Override:-1", "Pilgrim:0", "Delver:1", "Harbinger:2", "Forsworn:3") var start_bearing: int = -1

@export_group("Mutator")
@export_enum("None", "Blood Rush", "Flashpoint", "Siegebreak", "Iron Volley", "Killbox", "Random Hard") var mutator_override: int = DEBUG_MUTATOR_NONE

@export_group("Powers")
@export var apply_test_powers_on_start: bool = false
@export_enum("None", "Dasher", "Bruiser", "Marksman") var start_power_preset: int = DEBUG_POWER_PRESET_NONE
@export var start_power_ids: PackedStringArray = PackedStringArray()

@export_group("End Screen")
@export_enum("None", "Victory", "Defeat") var end_screen_preview: int = DEBUG_END_SCREEN_NONE
@export_enum("No Unlock:-1", "Pilgrim:0", "Delver:1", "Harbinger:2", "Forsworn:3") var victory_unlock_tier: int = -1

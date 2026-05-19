extends RefCounted

class_name CharacterStatModifiers

var max_health: int = 0
var max_speed: float = 0.0
var damage: int = 0
var attack_range: float = 0.0
var attack_arc_degrees: float = 0.0
var attack_cooldown: float = 0.0
var dash_cooldown: float = 0.0
var iron_skin_armor: int = 0
# Add more fields as needed

func _init(source: Dictionary = {}):
	max_health = int(source.get("max_health", 0))
	max_speed = float(source.get("max_speed", 0.0))
	damage = int(source.get("damage", 0))
	attack_range = float(source.get("attack_range", 0.0))
	attack_arc_degrees = float(source.get("attack_arc_degrees", 0.0))
	attack_cooldown = float(source.get("attack_cooldown", 0.0))
	dash_cooldown = float(source.get("dash_cooldown", 0.0))
	iron_skin_armor = int(source.get("iron_skin_armor", 0))

func duplicate() -> CharacterStatModifiers:
	var copy = CharacterStatModifiers.new()
	copy.max_health = max_health
	copy.max_speed = max_speed
	copy.damage = damage
	copy.attack_range = attack_range
	copy.attack_arc_degrees = attack_arc_degrees
	copy.attack_cooldown = attack_cooldown
	copy.dash_cooldown = dash_cooldown
	copy.iron_skin_armor = iron_skin_armor
	return copy

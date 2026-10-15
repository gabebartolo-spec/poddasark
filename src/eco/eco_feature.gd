class_name EcoFeature
extends RefCounted
## Something on the ground: a water source, food, a burrow, litter, an invasive plant.

var id: int
## Matches the kinds named in species needs and park data, e.g. "burrow", "litter".
var kind: String
var pos: Vector2


func _init(p_id: int, p_kind: String, p_pos: Vector2) -> void:
	id = p_id
	kind = p_kind
	pos = p_pos

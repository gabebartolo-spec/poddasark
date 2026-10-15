class_name EcoAnimal
extends RefCounted
## One animal. Positions are on the ground plane (x, z), not scene nodes.

var id: int
## Name the park and phase data use to refer to this animal, e.g. "lonely".
var key: String
var display_name: String
var species: SpeciesDef
var pos: Vector2
## Centre of its home range. Needs are judged from here, so they don't flicker
## as the animal wanders.
var home: Vector2
## Hidden animals aren't in the park yet (e.g. friends still in hiding).
var hidden := false
## Land health (0 to 1) at which a hidden animal comes out.
var emerge_at_land_health := 1.0
## Key of the animal whose home this one joins when it comes out.
var join_key := ""

## Need id -> 0..1, what the needs are right now.
var need_target: Dictionary = {}
## Need id -> 0..1, eased towards need_target so the panel moves smoothly.
var need_value: Dictionary = {}
## Breakdown inside a need, e.g. "shelter" and "calm" inside safety.
var parts: Dictionary = {}

var rng: SeededRng
var wander_target: Vector2
var wait_time := 0.0


func is_present() -> bool:
	return not hidden

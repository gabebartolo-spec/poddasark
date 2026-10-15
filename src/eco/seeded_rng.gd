class_name SeededRng
extends RefCounted
## Deterministic random numbers for the ecosystem logic.
##
## Everything in src/eco/ that needs randomness takes one of these instead of
## calling the global randf()/randi(), so the same park and seed always replays
## the same way. Code in src/eco/ must not depend on scene nodes.

var seed_value: int
var _rng := RandomNumberGenerator.new()


func _init(p_seed: int) -> void:
	seed_value = p_seed
	_rng.seed = p_seed


## Float in [0, 1).
func next_float() -> float:
	return _rng.randf()


## Float in [from, to].
func range_float(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


## Integer in [from, to], inclusive.
func range_int(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


## Returns true with the given probability (0 to 1).
func chance(probability: float) -> bool:
	return _rng.randf() < probability


## Independent generator derived from this one, e.g. one per species,
## so adding a species doesn't shift the random sequence of the others.
func fork(salt: int) -> SeededRng:
	return SeededRng.new(hash([seed_value, salt]))

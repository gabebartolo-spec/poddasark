class_name EcoWorld
extends RefCounted
## The park's ecosystem: features on the ground, animals, and their needs.
##
## Pure logic. No scene nodes, so it can be tested and balanced without playing.
## The scene listens to the signals and mirrors what happens here.

signal feature_added(feature: EcoFeature)
signal feature_removed(feature: EcoFeature)
signal animal_emerged(animal: EcoAnimal)

## Kinds that count against land health: human detritus and invasive plants.
const DETRITUS_KINDS: Array[String] = ["litter", "pollutant", "invasive_plant"]
## How fast the shown need values ease towards the real ones, per second.
const NEED_EASE_RATE := 0.5
## Animals further than this from their home walk back before wandering.
const ARRIVE_DISTANCE := 0.3

var features: Array[EcoFeature] = []
var animals: Array[EcoAnimal] = []
var rng: SeededRng
## Detritus count when the park loaded, used for land health.
var initial_detritus := 0

var _next_id := 1


func _init(p_seed: int = 1) -> void:
	rng = SeededRng.new(p_seed)


## Builds a world from a park data Dictionary. species maps id -> SpeciesDef.
static func from_park(park: Dictionary, species: Dictionary, p_seed: int) -> EcoWorld:
	var world := EcoWorld.new(p_seed)
	for f in park.get("features", []):
		var fd: Dictionary = f
		world.add_feature(fd["kind"], DataFiles.to_vec2(fd["pos"]))
	for a in park.get("animals", []):
		var ad: Dictionary = a
		var animal := world.add_animal(ad["key"], species[ad["species"]], DataFiles.to_vec2(ad["pos"]))
		animal.display_name = ad.get("name", animal.species.display_name)
		if ad.has("hidden_until"):
			var until: Dictionary = ad["hidden_until"]
			animal.hidden = true
			animal.emerge_at_land_health = float(until.get("land_health", 1.0))
			animal.join_key = until.get("join", "")
	world.initial_detritus = world.count_detritus()
	world.refresh_needs()
	for animal in world.animals:
		animal.need_value = animal.need_target.duplicate()
	return world


func add_feature(kind: String, pos: Vector2) -> EcoFeature:
	var feature := EcoFeature.new(_next_id, kind, pos)
	_next_id += 1
	features.append(feature)
	feature_added.emit(feature)
	refresh_needs()
	return feature


func remove_feature(feature: EcoFeature) -> void:
	features.erase(feature)
	feature_removed.emit(feature)
	refresh_needs()


func add_animal(key: String, species: SpeciesDef, pos: Vector2) -> EcoAnimal:
	var animal := EcoAnimal.new()
	animal.id = _next_id
	_next_id += 1
	animal.key = key
	animal.display_name = species.display_name
	animal.species = species
	animal.pos = pos
	animal.home = pos
	animal.wander_target = pos
	animal.rng = rng.fork(animal.id)
	animals.append(animal)
	return animal


func find_animal(key: String) -> EcoAnimal:
	for animal in animals:
		if animal.key == key:
			return animal
	return null


## Removes the detritus feature nearest to pos, if one is within radius.
## Returns the removed feature, or null.
func clean_up_at(pos: Vector2, radius: float) -> EcoFeature:
	var best: EcoFeature = null
	var best_d := radius
	for feature in features:
		if feature.kind in DETRITUS_KINDS:
			var d := feature.pos.distance_to(pos)
			if d <= best_d:
				best = feature
				best_d = d
	if best != null:
		remove_feature(best)
	return best


func count_detritus() -> int:
	var n := 0
	for feature in features:
		if feature.kind in DETRITUS_KINDS:
			n += 1
	return n


## 0 when the park is as messy as it started, 1 when all detritus is gone.
func land_health() -> float:
	if initial_detritus == 0:
		return 1.0
	return 1.0 - float(count_detritus()) / float(initial_detritus)


func tick(delta: float) -> void:
	_emerge_hidden()
	for animal in animals:
		if animal.is_present():
			_move(animal, delta)
	refresh_needs()
	for animal in animals:
		for need_id in animal.need_target:
			var current: float = animal.need_value.get(need_id, 0.0)
			animal.need_value[need_id] = move_toward(current, animal.need_target[need_id], NEED_EASE_RATE * delta)


## Recomputes every animal's needs from the current state of the park.
func refresh_needs() -> void:
	for animal in animals:
		_evaluate(animal)


## Weighted average of the needs, 0 to 1. Uses the eased values unless target is true.
func contentedness(animal: EcoAnimal, target := false) -> float:
	var values: Dictionary = animal.need_target if target else animal.need_value
	var total := 0.0
	var weights := 0.0
	for need_id in animal.species.need_order:
		var cfg: Dictionary = animal.species.needs[need_id]
		var w := float(cfg.get("weight", 1.0))
		total += float(values.get(need_id, 0.0)) * w
		weights += w
	return total / weights if weights > 0.0 else 0.0


func _evaluate(animal: EcoAnimal) -> void:
	for need_id in animal.species.need_order:
		var cfg: Dictionary = animal.species.needs[need_id]
		var value := 0.0
		match String(cfg["type"]):
			"resource":
				value = _proximity(animal.home, cfg["feature"], float(cfg["range"]))
			"safety":
				var shelter := _proximity(animal.home, cfg["shelter"], float(cfg["range"]))
				var fear_kinds: Array = cfg.get("fear_kinds", [])
				var scary := _count_near(animal.home, fear_kinds, float(cfg["fear_radius"]))
				var calm := maxf(0.0, 1.0 - float(cfg["fear_per_item"]) * scary)
				var share := float(cfg.get("shelter_share", 0.5))
				animal.parts["shelter"] = shelter
				animal.parts["calm"] = calm
				value = shelter * share + calm * (1.0 - share)
			"company":
				var others := _count_companions(animal, float(cfg["range"]))
				value = minf(1.0, float(others) / float(cfg["wanted"]))
			_:
				push_error("Unknown need type '%s' in species %s" % [cfg["type"], animal.species.id])
		animal.need_target[need_id] = value


## 1 if a feature of this kind is within range of pos, fading to 0 at twice the range.
func _proximity(pos: Vector2, kind: String, range_m: float) -> float:
	var nearest := INF
	for feature in features:
		if feature.kind == kind:
			nearest = minf(nearest, feature.pos.distance_to(pos))
	if nearest <= range_m:
		return 1.0
	if nearest == INF:
		return 0.0
	return clampf(1.0 - (nearest - range_m) / range_m, 0.0, 1.0)


func _count_near(pos: Vector2, kinds: Array, radius: float) -> int:
	var n := 0
	for feature in features:
		if feature.kind in kinds and feature.pos.distance_to(pos) <= radius:
			n += 1
	return n


func _count_companions(animal: EcoAnimal, range_m: float) -> int:
	var n := 0
	for other in animals:
		if other != animal and other.is_present() and other.species == animal.species \
				and other.pos.distance_to(animal.home) <= range_m:
			n += 1
	return n


func _emerge_hidden() -> void:
	var health := land_health()
	for animal in animals:
		if animal.hidden and health >= animal.emerge_at_land_health:
			animal.hidden = false
			var host := find_animal(animal.join_key)
			if host != null:
				var offset := Vector2(animal.rng.range_float(-2.5, 2.5), animal.rng.range_float(-2.5, 2.5))
				animal.home = host.home + offset
			animal.wander_target = animal.home
			animal.wait_time = 0.0
			animal_emerged.emit(animal)


## Wanders around the home range, pausing between short walks.
func _move(animal: EcoAnimal, delta: float) -> void:
	if animal.pos.distance_to(animal.wander_target) <= ARRIVE_DISTANCE:
		animal.wait_time -= delta
		if animal.wait_time > 0.0:
			return
		var r := animal.species.wander_radius
		var angle := animal.rng.range_float(0.0, TAU)
		var dist := animal.rng.range_float(0.0, r)
		animal.wander_target = animal.home + Vector2(cos(angle), sin(angle)) * dist
		animal.wait_time = animal.rng.range_float(1.5, 5.0)
	animal.pos = animal.pos.move_toward(animal.wander_target, animal.species.speed * delta)

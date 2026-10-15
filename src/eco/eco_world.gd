class_name EcoWorld
extends RefCounted
## The park's ecosystem: features on the ground, animals, and their needs.
##
## Pure logic. No scene nodes, so it can be tested and balanced without playing.
## The scene listens to the signals and mirrors what happens here.

signal feature_added(feature: EcoFeature)
signal feature_removed(feature: EcoFeature)
signal animal_emerged(animal: EcoAnimal)
## A new animal joined the world after it was built (a later stage, or moving in).
signal animal_added(animal: EcoAnimal)

## Kinds that count against land health: human detritus and invasive plants.
const DETRITUS_KINDS: Array[String] = ["litter", "pollutant", "invasive_plant"]
## How fast the shown need values ease towards the real ones, per second.
const NEED_EASE_RATE := 0.5
## Animals further than this from their home walk back before wandering.
const ARRIVE_DISTANCE := 0.3

var features: Array[EcoFeature] = []
var animals: Array[EcoAnimal] = []
var rng: SeededRng
## Detritus count when the park loaded (plus any added by later stages), used for land health.
var initial_detritus := 0
## Species id -> SpeciesDef for every species the park has loaded.
var species_defs: Dictionary = {}
## Species that must all be content to pass the harmony gate.
var harmony_species: Array[String] = []
## Rules for animals that move in on their own once shelter and food exist.
var move_ins: Array[Dictionary] = []

var _next_id := 1


func _init(p_seed: int = 1) -> void:
	rng = SeededRng.new(p_seed)


## Builds a world from a park data Dictionary. species maps id -> SpeciesDef.
static func from_park(park: Dictionary, species: Dictionary, p_seed: int) -> EcoWorld:
	var world := EcoWorld.new(p_seed)
	world.add_content(park, species)
	for animal in world.animals:
		animal.need_value = animal.need_target.duplicate()
	return world


## Adds a park's or a later stage's features, animals and move-in rules.
## Detritus added here counts towards land health.
func add_content(d: Dictionary, species: Dictionary) -> void:
	species_defs.merge(species)
	var detritus_before := count_detritus()
	for f in d.get("features", []):
		var fd: Dictionary = f
		add_feature(fd["kind"], DataFiles.to_vec2(fd["pos"]))
	for a in d.get("animals", []):
		var ad: Dictionary = a
		var animal := add_animal(ad["key"], species[ad["species"]], DataFiles.to_vec2(ad["pos"]))
		animal.display_name = ad.get("name", animal.species.display_name)
		if ad.has("hidden_until"):
			var until: Dictionary = ad["hidden_until"]
			animal.hidden = true
			animal.emerge_at_land_health = float(until.get("land_health", 1.0))
			for need_id in until.get("host_needs", []):
				animal.emerge_host_needs.append(String(need_id))
			animal.join_key = until.get("join", "")
		animal_added.emit(animal)
	for m in d.get("move_ins", []):
		var rule: Dictionary = (m as Dictionary).duplicate()
		rule["species_def"] = species[rule["species"]]
		rule["arrived"] = 0
		move_ins.append(rule)
	for id in d.get("harmony_species", []):
		if not harmony_species.has(String(id)):
			harmony_species.append(String(id))
	initial_detritus += count_detritus() - detritus_before
	refresh_needs()


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
	_check_move_ins()
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
				var shelter := _proximity_any(animal.home, _kinds(cfg["shelter"]), float(cfg["range"]))
				var fear_kinds: Array = cfg.get("fear_kinds", [])
				var scary := _count_near(animal.home, fear_kinds, float(cfg.get("fear_radius", 0.0)))
				var calm := maxf(0.0, 1.0 - float(cfg.get("fear_per_item", 0.0)) * scary)
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
	return _proximity_any(pos, [kind], range_m)


## Like _proximity, for the nearest feature of any of these kinds.
func _proximity_any(pos: Vector2, kinds: Array, range_m: float) -> float:
	var nearest := INF
	for feature in features:
		if feature.kind in kinds:
			nearest = minf(nearest, feature.pos.distance_to(pos))
	if nearest <= range_m:
		return 1.0
	if nearest == INF:
		return 0.0
	return clampf(1.0 - (nearest - range_m) / range_m, 0.0, 1.0)


## A data value that may be one kind ("burrow") or a list of kinds.
static func _kinds(value: Variant) -> Array:
	return value if value is Array else [value]


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
		if animal.hidden and _ready_to_emerge(animal, health):
			animal.hidden = false
			var host := find_animal(animal.join_key)
			if host != null:
				var offset := Vector2(animal.rng.range_float(-2.5, 2.5), animal.rng.range_float(-2.5, 2.5))
				animal.home = host.home + offset
			animal.wander_target = animal.home
			animal.wait_time = 0.0
			animal_emerged.emit(animal)


## Hidden animals come out either when the land is healthy enough, or (if the data
## names host needs) when the animal they join has those needs fully met.
func _ready_to_emerge(animal: EcoAnimal, health: float) -> bool:
	if animal.emerge_host_needs.is_empty():
		return health >= animal.emerge_at_land_health
	var host := find_animal(animal.join_key)
	if host == null or not host.is_present():
		return false
	for need_id in animal.emerge_host_needs:
		if float(host.need_target.get(need_id, 0.0)) < 1.0:
			return false
	return true


## Animals move in at a shelter that has their food within range, one per shelter,
## up to the rule's limit. Shelters are taken in the order they were placed.
func _check_move_ins() -> void:
	for rule in move_ins:
		var limit := int(rule["max"])
		if int(rule["arrived"]) >= limit:
			continue
		var occupied: Array = rule.get("occupied", [])
		for feature in features:
			if int(rule["arrived"]) >= limit:
				break
			if not feature.kind in _kinds(rule["shelter"]) or feature.id in occupied:
				continue
			if _proximity(feature.pos, rule["food"], float(rule["food_range"])) < 1.0:
				continue
			occupied.append(feature.id)
			rule["arrived"] = int(rule["arrived"]) + 1
			var sp: SpeciesDef = rule["species_def"]
			var animal := add_animal("%s_%d" % [rule["species"], rule["arrived"]], sp, feature.pos)
			animal.display_name = sp.display_name
			animal_added.emit(animal)
		rule["occupied"] = occupied


## One entry per harmony species: whether it's content, and how close it is.
## A species is content when its present animals' average contentedness reaches
## the species' content level (its "mood.high" in data). Absent species count as 0.
func harmony_report() -> Array[Dictionary]:
	var report: Array[Dictionary] = []
	for id in harmony_species:
		var sp: SpeciesDef = species_defs.get(id)
		var total := 0.0
		var count := 0
		for animal in animals:
			if animal.is_present() and animal.species.id == id:
				total += contentedness(animal, true)
				count += 1
		var average := total / count if count > 0 else 0.0
		var level := sp.mood_high if sp != null else 1.0
		report.append({
			"id": id,
			"name": sp.display_name if sp != null else id,
			"count": count,
			"average": average,
			"level": level,
			"content": count > 0 and average >= level,
		})
	return report


## 0 to 1: how close the park is to the harmony gate, for the harmony meter.
func harmony_progress() -> float:
	var report := harmony_report()
	if report.is_empty():
		return 0.0
	var total := 0.0
	for entry in report:
		total += minf(1.0, float(entry["average"]) / float(entry["level"]))
	return total / report.size()


func harmony_reached() -> bool:
	var report := harmony_report()
	if report.is_empty():
		return false
	for entry in report:
		if not entry["content"]:
			return false
	return true


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

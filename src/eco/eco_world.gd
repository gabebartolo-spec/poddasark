class_name EcoWorld
extends RefCounted
## The park's ecosystem: features on the ground, animals, and their needs.
##
## Pure logic. No scene nodes, so it can be tested and balanced without playing.
## The scene listens to the signals and mirrors what happens here.

signal feature_added(feature: EcoFeature)
signal feature_removed(feature: EcoFeature)
signal animal_emerged(animal: EcoAnimal)
## A new animal joined the world after it was built (a later stage, moving in, a birth
## or an arrival from outside the park).
signal animal_added(animal: EcoAnimal)
## An animal left the world. reason is "hunted" or "relocated".
signal animal_removed(animal: EcoAnimal, reason: String)
## A predator started a hunt. hunt is the Dictionary described at start_hunt().
signal hunt_started(hunt: Dictionary)
signal hunt_ended(hunt: Dictionary)

## Kinds that count against land health: human detritus and invasive plants.
const DETRITUS_KINDS: Array[String] = ["litter", "pollutant", "invasive_plant"]
## How fast the shown need values ease towards the real ones, per second.
const NEED_EASE_RATE := 0.5
## Animals further than this from their home walk back before wandering.
const ARRIVE_DISTANCE := 0.3
## Default range for counting an animal's group, when its species has no company need.
const GROUP_RANGE := 25.0

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
## Hunts in progress.
var hunts: Array[Dictionary] = []
var hunts_finished := 0
var hunts_succeeded := 0
## Half the width of the park; arrivals from outside walk in from this edge.
var bounds_half_extent := 128.0

var _next_id := 1
## Species id -> seconds since the last birth / arrival check.
var _breed_timers: Dictionary = {}
var _arrival_timers: Dictionary = {}
## Species id -> how many animals of it have been born, moved in or arrived, for keys.
var _spawn_counts: Dictionary = {}


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
	var cam: Dictionary = d.get("camera", {})
	if cam.has("bounds_half_extent"):
		bounds_half_extent = float(cam["bounds_half_extent"])
	var detritus_before := count_detritus()
	for f in d.get("features", []):
		var fd: Dictionary = f
		add_feature(fd["kind"], DataFiles.to_vec2(fd["pos"]))
	for a in d.get("animals", []):
		var ad: Dictionary = a
		var animal := add_animal(ad["key"], species_defs[ad["species"]], DataFiles.to_vec2(ad["pos"]))
		animal.display_name = ad.get("name", animal.species.display_name)
		animal.group = ad.get("group", "")
		if ad.has("home"):
			animal.home = DataFiles.to_vec2(ad["home"])
			animal.wander_target = animal.home
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
		rule["species_def"] = species_defs[rule["species"]]
		rule["arrived"] = 0
		rule["occupied"] = []
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
	animal.hunt_cooldown = float(species.predator.get("hunt_interval", 0.0))
	animals.append(animal)
	return animal


## Takes an animal out of the park (hunted, or relocated by a ranger).
func remove_animal(animal: EcoAnimal, reason: String) -> void:
	if not animals.has(animal):
		return
	for hunt in hunts.duplicate():
		if hunt["predator"] == animal or hunt["prey"] == animal:
			_end_hunt(hunt, false)
	animals.erase(animal)
	# A shelter it moved in at is free again, so another can move in later.
	for rule in move_ins:
		if animal.moved_in_at in rule["occupied"]:
			rule["occupied"].erase(animal.moved_in_at)
			rule["arrived"] = int(rule["arrived"]) - 1
	animal_removed.emit(animal, reason)
	refresh_needs()


## Moves a dingo (or any relocatable species) to another park. Returns false if this
## species can't be relocated.
func relocate(animal: EcoAnimal) -> bool:
	if animal == null or not animal.species.relocatable or not animal.is_present():
		return false
	remove_animal(animal, "relocated")
	return true


func find_animal(key: String) -> EcoAnimal:
	for animal in animals:
		if animal.key == key:
			return animal
	return null


func present(species_id: String) -> Array[EcoAnimal]:
	var out: Array[EcoAnimal] = []
	for animal in animals:
		if animal.is_present() and animal.species.id == species_id:
			out.append(animal)
	return out


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
	_breed(delta)
	_arrive(delta)
	_start_hunts(delta)
	_advance_hunts(delta)
	for animal in animals:
		if animal.is_present() and not animal.in_hunt:
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


# --- Needs -----------------------------------------------------------------

func _evaluate(animal: EcoAnimal) -> void:
	for need_id in animal.species.need_order:
		var cfg: Dictionary = animal.species.needs[need_id]
		var value := 0.0
		match String(cfg["type"]):
			"resource":
				value = _proximity_for(animal, [cfg["feature"]], float(cfg["range"]))
			"safety":
				var shelter := _shelter(animal, cfg)
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
			"prey":
				value = _prey_supply(animal, cfg)
			_:
				push_error("Unknown need type '%s' in species %s" % [cfg["type"], animal.species.id])
		animal.need_target[need_id] = value


## A predator's food: prey within range, shared by every animal of its species hunting
## the same ground (rival packs included). 1 when there's enough for all of them.
func _prey_supply(animal: EcoAnimal, cfg: Dictionary) -> float:
	var range_m := float(cfg["range"])
	var supply := 0.0
	for other in animals:
		if other.is_present() and not other.species.prey.is_empty() \
				and other.pos.distance_to(animal.home) <= range_m:
			supply += float(other.species.prey.get("weight", 1.0))
	var sharers := 0
	for other in animals:
		if other.is_present() and other.species == animal.species \
				and other.home.distance_to(animal.home) <= range_m:
			sharers += 1
	var wanted := float(cfg.get("per_animal", 1.0)) * maxi(sharers, 1)
	return minf(1.0, supply / wanted)


## Shelter from "shelter" (kinds) or "shelter_rules" (kinds with conditions).
func _shelter(animal: EcoAnimal, cfg: Dictionary) -> float:
	var range_m := float(cfg["range"])
	if not cfg.has("shelter_rules"):
		return _proximity_for(animal, _kinds(cfg["shelter"]), range_m)
	var best := 0.0
	for r in cfg["shelter_rules"]:
		var rule: Dictionary = r
		if rule.has("max_group") and _group_size(animal) > int(rule["max_group"]):
			continue
		var kinds := [rule["kind"]]
		var filter := Callable()
		if rule.has("unoccupied_by"):
			var other_species: String = rule["unoccupied_by"]
			var occupied_range := float(rule.get("occupied_range", 6.0))
			filter = func(f: EcoFeature) -> bool: return not _lives_near(other_species, f.pos, occupied_range)
		best = maxf(best, _proximity_for(animal, kinds, range_m, filter))
	return best


## 1 if a usable feature of these kinds is within range of the animal's home, fading
## to 0 at twice the range. Territorial species can't use features in a rival's
## territory. filter, if valid, must also return true for the feature.
func _proximity_for(animal: EcoAnimal, kinds: Array, range_m: float, filter := Callable()) -> float:
	var nearest := INF
	for feature in features:
		if not feature.kind in kinds:
			continue
		if animal.species.territorial and _in_rival_territory(animal, feature.pos):
			continue
		if filter.is_valid() and not filter.call(feature):
			continue
		nearest = minf(nearest, feature.pos.distance_to(animal.home))
	return _falloff(nearest, range_m)


## Proximity from a point, ignoring territory (used for move-ins).
func _proximity(pos: Vector2, kind: String, range_m: float) -> float:
	var nearest := INF
	for feature in features:
		if feature.kind == kind:
			nearest = minf(nearest, feature.pos.distance_to(pos))
	return _falloff(nearest, range_m)


static func _falloff(nearest: float, range_m: float) -> float:
	if nearest <= range_m:
		return 1.0
	if nearest == INF:
		return 0.0
	return clampf(1.0 - (nearest - range_m) / range_m, 0.0, 1.0)


## True if a rival group of the same species lives closer to pos than this animal does.
func _in_rival_territory(animal: EcoAnimal, pos: Vector2) -> bool:
	var mine := animal.home.distance_to(pos)
	for other in animals:
		if other.is_present() and other.species == animal.species and other.group != animal.group \
				and other.home.distance_to(pos) < mine:
			return true
	return false


func _lives_near(species_id: String, pos: Vector2, radius: float) -> bool:
	for other in animals:
		if other.is_present() and other.species.id == species_id and other.home.distance_to(pos) <= radius:
			return true
	return false


## How many animals are in this one's group (pack, mob or family), itself included.
func _group_size(animal: EcoAnimal) -> int:
	var range_m := GROUP_RANGE
	for need_id in animal.species.need_order:
		var cfg: Dictionary = animal.species.needs[need_id]
		if cfg["type"] == "company":
			range_m = float(cfg["range"])
	var n := 1
	for other in animals:
		if other != animal and other.is_present() and other.species == animal.species \
				and other.group == animal.group and other.home.distance_to(animal.home) <= range_m:
			n += 1
	return n


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
				and other.group == animal.group and other.pos.distance_to(animal.home) <= range_m:
			n += 1
	return n


# --- Arriving: hidden animals, move-ins, births, arrivals -------------------

func _emerge_hidden() -> void:
	var health := land_health()
	for animal in animals:
		if animal.hidden and _ready_to_emerge(animal, health):
			animal.hidden = false
			var host := find_animal(animal.join_key)
			if host != null:
				var offset := Vector2(animal.rng.range_float(-2.5, 2.5), animal.rng.range_float(-2.5, 2.5))
				animal.home = host.home + offset
				animal.group = host.group
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
		var occupied: Array = rule["occupied"]
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
			var animal := add_animal(_spawn_key(rule["species"], ""), sp, feature.pos)
			animal.moved_in_at = feature.id
			animal_added.emit(animal)


## Content species have young over time, up to the park-wide limit in their data.
func _breed(delta: float) -> void:
	for id in species_defs:
		var sp: SpeciesDef = species_defs[id]
		if sp.breeding.is_empty():
			continue
		_breed_timers[id] = float(_breed_timers.get(id, 0.0)) + delta
		if _breed_timers[id] < float(sp.breeding["interval"]):
			continue
		_breed_timers[id] = 0.0
		var members := present(id)
		if members.is_empty() or members.size() >= int(sp.breeding["max"]):
			continue
		var parents: Array[EcoAnimal] = []
		for animal in members:
			if contentedness(animal, true) >= sp.mood_high:
				parents.append(animal)
		if parents.is_empty():
			continue
		var parent := parents[rng.range_int(0, parents.size() - 1)]
		var offset := Vector2(rng.range_float(-1.5, 1.5), rng.range_float(-1.5, 1.5))
		var young := add_animal(_spawn_key(id, "born_"), sp, parent.home + offset)
		young.group = parent.group
		animal_added.emit(young)


## When a species is down to a few animals, others wander in from outside the park
## and join the group that's left.
func _arrive(delta: float) -> void:
	for id in species_defs:
		var sp: SpeciesDef = species_defs[id]
		if sp.arrivals.is_empty():
			continue
		var members := present(id)
		if members.is_empty() or members.size() >= int(sp.arrivals["below"]):
			_arrival_timers[id] = 0.0
			continue
		_arrival_timers[id] = float(_arrival_timers.get(id, 0.0)) + delta
		if _arrival_timers[id] < float(sp.arrivals["interval"]):
			continue
		_arrival_timers[id] = 0.0
		var host := members[0]
		var edge := _edge_point(host.home)
		var animal := add_animal(_spawn_key(id, "arrived_"), sp, edge)
		animal.home = host.home + Vector2(rng.range_float(-2.5, 2.5), rng.range_float(-2.5, 2.5))
		animal.wander_target = animal.home
		animal.group = host.group
		animal_added.emit(animal)


## A unique key for a new animal, e.g. "possum_1" or "kangaroo_born_2".
func _spawn_key(species_id: String, prefix: String) -> String:
	var tag := species_id + "_" + prefix
	_spawn_counts[tag] = int(_spawn_counts.get(tag, 0)) + 1
	return "%s%d" % [tag, _spawn_counts[tag]]


## The point on the park's edge in the direction of pos from the centre.
func _edge_point(pos: Vector2) -> Vector2:
	var dir := pos.normalized() if pos.length() > 0.01 else Vector2.RIGHT
	var scale := bounds_half_extent / maxf(absf(dir.x), absf(dir.y))
	return dir * scale


# --- Hunting ---------------------------------------------------------------

## Starts a hunt. succeed: 1 forces a catch, 0 forces an escape (e.g. the story hunt
## that announces the dingo), -1 rolls the prey's catch chance. Returns the hunt:
##   {"predator", "prey", "success", "elapsed", "duration", "forced"}
func start_hunt(predator: EcoAnimal, prey: EcoAnimal, succeed := -1) -> Dictionary:
	var success := false
	if succeed == -1:
		success = rng.chance(float(prey.species.prey.get("catch_chance", 0.3)))
	else:
		success = succeed == 1
	var hunt := {
		"predator": predator,
		"prey": prey,
		"success": success,
		"elapsed": 0.0,
		"duration": float(predator.species.predator.get("chase_time", 6.0)),
		"forced": succeed != -1,
	}
	predator.in_hunt = true
	prey.in_hunt = true
	predator.hunt_cooldown = float(predator.species.predator.get("hunt_interval", 120.0))
	hunts.append(hunt)
	hunt_started.emit(hunt)
	return hunt


## The prey animal this predator would chase now, or null: prey in its hunting range,
## chosen at random weighted by how much each species counts as prey.
func choose_prey(predator: EcoAnimal) -> EcoAnimal:
	var range_m := 0.0
	for need_id in predator.species.need_order:
		var cfg: Dictionary = predator.species.needs[need_id]
		if cfg["type"] == "prey":
			range_m = float(cfg["range"])
	var options: Array[EcoAnimal] = []
	var total := 0.0
	for other in animals:
		if other.is_present() and not other.in_hunt and not other.species.prey.is_empty() \
				and other.pos.distance_to(predator.home) <= range_m:
			options.append(other)
			total += float(other.species.prey.get("weight", 1.0))
	if options.is_empty():
		return null
	var roll := rng.range_float(0.0, total)
	for other in options:
		roll -= float(other.species.prey.get("weight", 1.0))
		if roll <= 0.0:
			return other
	return options[options.size() - 1]


func _start_hunts(delta: float) -> void:
	for animal in animals.duplicate():
		if animal.species.predator.is_empty() or not animal.is_present() or animal.in_hunt:
			continue
		animal.hunt_cooldown -= delta
		if animal.hunt_cooldown > 0.0:
			continue
		var prey := choose_prey(animal)
		if prey == null:
			animal.hunt_cooldown = float(animal.species.predator.get("hunt_interval", 120.0)) * 0.25
			continue
		start_hunt(animal, prey)


## The prey runs from the predator; the predator closes in if the hunt will succeed,
## and falls behind if it won't. The outcome happens at the end of the chase.
func _advance_hunts(delta: float) -> void:
	for hunt in hunts.duplicate():
		var predator: EcoAnimal = hunt["predator"]
		var prey: EcoAnimal = hunt["prey"]
		hunt["elapsed"] = float(hunt["elapsed"]) + delta
		var away := prey.pos - predator.pos
		var dir := away.normalized() if away.length() > 0.01 else Vector2.RIGHT
		prey.pos = _clamp_to_park(prey.pos + dir * prey.species.flee_speed * delta)
		var chase_speed := float(predator.species.predator.get("chase_speed", 7.0))
		if not hunt["success"]:
			chase_speed = prey.species.flee_speed * 0.85
		predator.pos = _clamp_to_park(predator.pos.move_toward(prey.pos, chase_speed * delta))
		if float(hunt["elapsed"]) >= float(hunt["duration"]):
			_end_hunt(hunt, hunt["success"])


func _end_hunt(hunt: Dictionary, caught: bool) -> void:
	if not hunts.has(hunt):
		return
	hunts.erase(hunt)
	var predator: EcoAnimal = hunt["predator"]
	var prey: EcoAnimal = hunt["prey"]
	predator.in_hunt = false
	prey.in_hunt = false
	predator.wander_target = predator.home
	prey.wander_target = prey.home
	hunts_finished += 1
	if caught:
		hunts_succeeded += 1
	hunt["caught"] = caught
	hunt_ended.emit(hunt)
	if caught:
		remove_animal(prey, "hunted")


func _clamp_to_park(pos: Vector2) -> Vector2:
	var h := bounds_half_extent
	return Vector2(clampf(pos.x, -h, h), clampf(pos.y, -h, h))


# --- Harmony ---------------------------------------------------------------

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


## Average of a need across a species' present animals, or -1 if none are present.
func species_need(species_id: String, need_id: String) -> float:
	var members := present(species_id)
	if members.is_empty():
		return -1.0
	var total := 0.0
	for animal in members:
		total += float(animal.need_target.get(need_id, 0.0))
	return total / members.size()


# --- Movement --------------------------------------------------------------

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

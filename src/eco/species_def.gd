class_name SpeciesDef
extends RefCounted
## One species' needs and behaviour, read from data/species/<id>.json.

var id: String
var display_name: String
var scientific_name: String
## Need id -> config Dictionary, in the order the data lists them.
var needs: Dictionary = {}
var need_order: Array[String] = []
var wander_radius := 4.0
var speed := 1.0
## Contentedness below this shows the low mood icon.
var mood_low := 0.4
## Contentedness at or above this shows the high mood icon.
var mood_high := 0.75
var facts: Array[String] = []
## Placeholder body shape for the scene, e.g. {"shape": "upright", "scale": 1.3}.
var placeholder: Dictionary = {}
## If hunted: {"weight": how much it counts as prey, "catch_chance": 0 to 1}.
var prey: Dictionary = {}
## If a predator: {"hunt_interval": s, "chase_time": s, "chase_speed": m/s}.
var predator: Dictionary = {}
## Speed when fleeing a predator, in m/s.
var flee_speed := 0.0
## Births while content: {"interval": s, "max": park-wide limit}.
var breeding: Dictionary = {}
## Arrivals from outside the park when numbers are low: {"below": n, "interval": s}.
var arrivals: Dictionary = {}
## Territorial species (e.g. dingo packs) can't use dens or water that sit closer to a
## rival group's home than to their own.
var territorial := false
## Whether a ranger can relocate this species to another park.
var relocatable := false
## Text for the scene: "hunt_facts" (narration) and "hunt_success" / "hunt_fail".
var text: Dictionary = {}


static func from_dict(d: Dictionary) -> SpeciesDef:
	var s := SpeciesDef.new()
	s.id = d["id"]
	s.display_name = d["name"]
	s.scientific_name = d.get("scientific_name", "")
	var behaviour: Dictionary = d.get("behaviour", {})
	s.wander_radius = float(behaviour.get("wander_radius", s.wander_radius))
	s.speed = float(behaviour.get("speed", s.speed))
	var mood: Dictionary = d.get("mood", {})
	s.mood_low = float(mood.get("low", s.mood_low))
	s.mood_high = float(mood.get("high", s.mood_high))
	for need in d["needs"]:
		var cfg: Dictionary = need
		var need_id: String = cfg["id"]
		s.needs[need_id] = cfg
		s.need_order.append(need_id)
	s.placeholder = d.get("placeholder", {})
	s.prey = d.get("prey", {})
	s.predator = d.get("predator", {})
	s.flee_speed = float(behaviour.get("flee_speed", s.speed * 3.0))
	s.breeding = d.get("breeding", {})
	s.arrivals = d.get("arrivals", {})
	s.relocatable = bool(d.get("relocatable", false))
	s.territorial = bool(d.get("territorial", false))
	s.text = d.get("text", {})
	for fact in d.get("facts", []):
		s.facts.append(String(fact))
	return s


static func load_file(path: String) -> SpeciesDef:
	var d: Variant = DataFiles.load_json(path)
	return from_dict(d) if d is Dictionary else null

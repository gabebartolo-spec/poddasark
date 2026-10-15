class_name PhaseScript
extends RefCounted
## Runs a campaign phase's steps from data/phases/, one at a time.
## Pure logic: it reads the EcoWorld and doesn't touch scene nodes.

signal step_changed(step: Dictionary)
signal finished(finale: Dictionary)

var steps: Array[Dictionary] = []
var finale: Dictionary = {}
var index := 0
var is_finished := false


static func from_dict(d: Dictionary) -> PhaseScript:
	var script := PhaseScript.new()
	for s in d["steps"]:
		script.steps.append(s)
	script.finale = d.get("finale", {})
	return script


func current_step() -> Dictionary:
	return {} if is_finished else steps[index]


## Checks the current step and moves on when it's done. selected_key is the animal
## the player is observing, or "".
func update(world: EcoWorld, selected_key: String) -> void:
	if is_finished:
		return
	if not is_done(steps[index]["done_when"], world, selected_key):
		return
	index += 1
	if index >= steps.size():
		is_finished = true
		finished.emit(finale)
	else:
		step_changed.emit(steps[index])


static func is_done(cond: Dictionary, world: EcoWorld, selected_key: String) -> bool:
	match String(cond["type"]):
		"selected":
			return selected_key == cond["animal"]
		"need":
			var animal := world.find_animal(cond["animal"])
			return float(animal.need_target.get(cond["need"], 0.0)) >= float(cond["at_least"])
		"need_part":
			var animal := world.find_animal(cond["animal"])
			return float(animal.parts.get(cond["part"], 0.0)) >= float(cond["at_least"])
		"land_health":
			return world.land_health() >= float(cond["at_least"])
		"selected_species":
			var selected := world.find_animal(selected_key)
			return selected != null and selected.species.id == cond["species"]
		"species_content":
			for entry in world.harmony_report():
				if entry["id"] == cond["species"]:
					return entry["content"]
			return false
		"species_count":
			var n := 0
			for animal in world.animals:
				if animal.is_present() and animal.species.id == cond["species"]:
					n += 1
			return n >= int(cond["at_least"])
		"harmony":
			return world.harmony_reached()
	push_error("Unknown step condition: %s" % cond["type"])
	return false

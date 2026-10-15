extends SceneTree
## Balance tool: runs the ecosystem logic forward without playing, and reports how
## each harmony species is doing over time.
##
##   tools/godot.sh --headless --path . -s tools/simulate.gd -- \
##       --plan res://tools/plans/m2_example.json [--seconds 120] [--every 10] [--seed 7]
##
## A plan is a JSON file: a park, the stages to add, and timed player actions:
##   {"park": "res://data/parks/wombat_tutorial.json",
##    "stages": ["res://data/parks/apply_learnings.json"],
##    "actions": [{"t": 0, "place": "water", "pos": [70, -44]},
##                {"t": 5, "clean_up_all": true}]}
## Positions in actions can be relative to an animal's home: "near": "roo_lead".

const SPECIES_DIR := "res://data/species/"
const STEP := 0.1


func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	if not args.has("plan"):
		printerr("Usage: -s tools/simulate.gd -- --plan <res://path.json> [--seconds N] [--every N] [--seed N]")
		quit(2)
		return
	var plan: Dictionary = DataFiles.load_json(args["plan"])
	var park: Dictionary = DataFiles.load_json(plan["park"])
	var seed := int(args.get("seed", park.get("seed", 1)))
	var world := EcoWorld.from_park(park, _species_for(park, {}), seed)
	for path in plan.get("stages", []):
		var stage: Dictionary = DataFiles.load_json(path)
		world.add_content(stage, _species_for(stage, world.species_defs))

	var seconds := float(args.get("seconds", 120))
	var every := float(args.get("every", 10))
	var actions: Array = plan.get("actions", [])
	actions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	var next_action := 0
	var next_report := 0.0
	var t := 0.0
	print("seed %d, %d s" % [seed, int(seconds)])
	while t <= seconds + 0.001:
		while next_action < actions.size() and float(actions[next_action]["t"]) <= t:
			_apply(world, actions[next_action])
			next_action += 1
		if t >= next_report - 0.001:
			_report(world, t)
			next_report += every
		world.tick(STEP)
		t += STEP
	quit(0)


func _apply(world: EcoWorld, action: Dictionary) -> void:
	if action.get("clean_up_all", false):
		for f in world.features.duplicate():
			if f.kind in EcoWorld.DETRITUS_KINDS:
				world.remove_feature(f)
		print("  t=%5.1f  cleaned up all detritus" % float(action["t"]))
		return
	var pos := DataFiles.to_vec2(action.get("pos", [0, 0]))
	if action.has("near"):
		var animal := world.find_animal(action["near"])
		if animal == null:
			printerr("  no animal '%s' for action at t=%s" % [action["near"], action["t"]])
			return
		pos += animal.home
	world.add_feature(action["place"], pos)
	print("  t=%5.1f  placed %s at (%.0f, %.0f)" % [float(action["t"]), action["place"], pos.x, pos.y])


func _report(world: EcoWorld, t: float) -> void:
	var parts: Array[String] = []
	for entry in world.harmony_report():
		parts.append("%s %d @ %.2f%s" % [entry["id"], int(entry["count"]), float(entry["average"]),
			"*" if entry["content"] else ""])
	print("t=%5.1f  harmony %.2f%s  land %.2f  | %s" % [t, world.harmony_progress(),
		" REACHED" if world.harmony_reached() else "", world.land_health(), "  ".join(parts)])


func _species_for(d: Dictionary, have: Dictionary) -> Dictionary:
	var ids: Array = []
	for a in d.get("animals", []):
		ids.append(a["species"])
	for m in d.get("move_ins", []):
		ids.append(m["species"])
	ids.append_array(d.get("harmony_species", []))
	var out := {}
	for id in ids:
		if not out.has(id) and not have.has(id):
			out[id] = SpeciesDef.load_file(SPECIES_DIR + String(id) + ".json")
	return out


func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < raw.size():
		if raw[i].begins_with("--") and i + 1 < raw.size():
			out[raw[i].substr(2)] = raw[i + 1]
			i += 2
		else:
			i += 1
	return out

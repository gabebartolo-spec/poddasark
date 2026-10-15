extends TestCase
## Plays the wombat tutorial from the real data files, without a scene,
## to prove it can be finished in the director's step order.

const SPECIES := "res://data/species/wombat.json"
const PARK := "res://data/parks/wombat_tutorial.json"
const PHASE := "res://data/phases/wombat_tutorial.json"


func _setup() -> Array:
	var wombat := SpeciesDef.load_file(SPECIES)
	var park: Dictionary = DataFiles.load_json(PARK)
	var world := EcoWorld.from_park(park, {"wombat": wombat}, int(park["seed"]))
	var phase := PhaseScript.from_dict(DataFiles.load_json(PHASE))
	return [world, phase]


func _run(world: EcoWorld, phase: PhaseScript, selected: String, seconds := 1.0) -> void:
	var t := 0.0
	while t < seconds:
		world.tick(0.1)
		phase.update(world, selected)
		t += 0.1


func _step_id(phase: PhaseScript) -> String:
	return "finished" if phase.is_finished else String(phase.current_step()["id"])


func test_data_files_load() -> void:
	var parts := _setup()
	var world: EcoWorld = parts[0]
	assert_true(world.find_animal("lonely") != null)
	assert_eq(world.animals.size(), 5)
	assert_true(world.initial_detritus > 0)


func test_wombat_starts_with_the_four_issues() -> void:
	var world: EcoWorld = _setup()[0]
	var w := world.find_animal("lonely")
	assert_almost(w.parts["shelter"], 0.0, 0.0001, "no shelter")
	assert_true(w.parts["calm"] < 1.0, "scared")
	assert_almost(w.need_target["food"], 0.0, 0.0001, "hungry")
	assert_almost(w.need_target["company"], 0.0, 0.0001, "alone")
	assert_almost(w.need_target["water"], 1.0, 0.0001, "the pond covers water")


func test_full_playthrough_in_step_order() -> void:
	var parts := _setup()
	var world: EcoWorld = parts[0]
	var phase: PhaseScript = parts[1]
	var home := world.find_animal("lonely").home

	_run(world, phase, "")
	assert_eq(_step_id(phase), "observe")
	_run(world, phase, "lonely")
	assert_eq(_step_id(phase), "shelter")

	world.add_feature("burrow", home + Vector2(2, 1))
	_run(world, phase, "lonely")
	assert_eq(_step_id(phase), "scared")

	for f in world.features.duplicate():
		if f.kind in ["litter", "pollutant"] and f.pos.distance_to(home) <= 10.0:
			world.clean_up_at(f.pos, 0.5)
	_run(world, phase, "lonely")
	assert_eq(_step_id(phase), "hungry")

	world.add_feature("native_grass", home + Vector2(-3, 2))
	_run(world, phase, "lonely")
	assert_eq(_step_id(phase), "alone")

	for f in world.features.duplicate():
		if f.kind in EcoWorld.DETRITUS_KINDS:
			world.clean_up_at(f.pos, 0.5)
	assert_almost(world.land_health(), 1.0)
	# The friends walk in from the edges of the area.
	_run(world, phase, "lonely", 90.0)
	assert_eq(_step_id(phase), "finished")
	assert_true(world.contentedness(world.find_animal("lonely"), true) >= 0.99)


func test_steps_do_not_skip_ahead_without_the_fix() -> void:
	var parts := _setup()
	var world: EcoWorld = parts[0]
	var phase: PhaseScript = parts[1]
	_run(world, phase, "lonely", 5.0)
	assert_eq(_step_id(phase), "shelter")

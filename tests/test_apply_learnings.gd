extends TestCase
## Plays the M2 "apply learnings" stage from the real data files, without a scene:
## finishes the wombat tutorial, adds the stage to the same world (the seamless
## zoom-out), then helps the kangaroo mob and the possums to the harmony gate.

const WOMBAT_PARK := "res://data/parks/wombat_tutorial.json"
const SPECIES_DIR := "res://data/species/"


func _species(ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		out[id] = SpeciesDef.load_file(SPECIES_DIR + String(id) + ".json")
	return out


func _run(world: EcoWorld, phase: PhaseScript, selected: String, seconds := 1.0) -> void:
	var t := 0.0
	while t < seconds:
		world.tick(0.1)
		if phase != null:
			phase.update(world, selected)
		t += 0.1


func _step_id(phase: PhaseScript) -> String:
	return "finished" if phase.is_finished else String(phase.current_step()["id"])


## The wombat corner as the player leaves it at the end of M1.
func _finished_wombat_world() -> EcoWorld:
	var park: Dictionary = DataFiles.load_json(WOMBAT_PARK)
	var world := EcoWorld.from_park(park, _species(["wombat"]), int(park["seed"]))
	var home := world.find_animal("lonely").home
	world.add_feature("burrow", home + Vector2(2, 1))
	world.add_feature("native_grass", home + Vector2(-3, 2))
	for f in world.features.duplicate():
		if f.kind in EcoWorld.DETRITUS_KINDS:
			world.clean_up_at(f.pos, 0.5)
	_run(world, null, "", 90.0)
	return world


## Returns [world, phase, stage].
func _setup() -> Array:
	var world := _finished_wombat_world()
	var park: Dictionary = DataFiles.load_json(WOMBAT_PARK)
	var stage: Dictionary = DataFiles.load_json(park["next_stage"])
	world.add_content(stage, _species(["kangaroo", "possum"]))
	var phase := PhaseScript.from_dict(DataFiles.load_json(stage["phase"]))
	return [world, phase, stage]


func _present(world: EcoWorld, species_id: String) -> int:
	var n := 0
	for animal in world.animals:
		if animal.is_present() and animal.species.id == species_id:
			n += 1
	return n


func test_wombat_tutorial_links_to_the_stage() -> void:
	var park: Dictionary = DataFiles.load_json(WOMBAT_PARK)
	assert_eq(park["next_stage"], "res://data/parks/apply_learnings.json")


func test_stage_keeps_everything_from_the_wombat_corner() -> void:
	var world := _finished_wombat_world()
	var burrows_before := world.features.filter(func(f: EcoFeature) -> bool: return f.kind == "burrow").size()
	var parts := _setup()
	var after: EcoWorld = parts[0]
	assert_eq(after.features.filter(func(f: EcoFeature) -> bool: return f.kind == "burrow").size(), burrows_before)
	assert_eq(_present(after, "wombat"), 5)


func test_new_mess_counts_against_land_health() -> void:
	# Land health covers the whole park: the wombat corner's 14 pieces are cleaned,
	# the bigger area's 11 are not.
	var world: EcoWorld = _setup()[0]
	assert_eq(world.initial_detritus, 25)
	assert_almost(world.land_health(), 14.0 / 25.0, 0.0001)


func test_harmony_starts_unreached_with_wombats_content() -> void:
	var world: EcoWorld = _setup()[0]
	var report := world.harmony_report()
	assert_eq(report.size(), 3)
	assert_true(report[0]["content"], "wombats are already content")
	assert_true(not report[1]["content"], "the kangaroo mob is struggling")
	assert_eq(int(report[2]["count"]), 0, "no possums yet")
	assert_true(not world.harmony_reached())
	assert_true(world.harmony_progress() > 0.0 and world.harmony_progress() < 1.0)


func test_small_mob_starts_uneasy_thirsty_and_hungry() -> void:
	var world: EcoWorld = _setup()[0]
	var roo := world.find_animal("roo_lead")
	assert_eq(_present(world, "kangaroo"), 3)
	assert_almost(roo.need_target["water"], 0.0, 0.0001)
	assert_almost(roo.need_target["food"], 0.0, 0.0001)
	assert_true(roo.need_target["safety"] < 1.0)


func test_possums_need_both_a_nest_box_and_eucalypts() -> void:
	var world: EcoWorld = _setup()[0]
	# A nest box out on the plains, away from any eucalypt: nobody moves in.
	world.add_feature("nest_box", Vector2(30, 30))
	_run(world, null, "", 2.0)
	assert_eq(_present(world, "possum"), 0)
	# A eucalypt beside it: a possum moves in, and it's content straight away.
	world.add_feature("eucalypt", Vector2(32, 31))
	_run(world, null, "", 5.0)
	assert_eq(_present(world, "possum"), 1)
	var possum := world.find_animal("possum_1")
	assert_true(world.contentedness(possum, true) >= 0.99)


func test_full_playthrough_reaches_harmony() -> void:
	var parts := _setup()
	var world: EcoWorld = parts[0]
	var phase: PhaseScript = parts[1]
	var mob := world.find_animal("roo_lead").home

	_run(world, phase, "")
	assert_eq(_step_id(phase), "find_the_mob")
	_run(world, phase, "roo_lead")
	assert_eq(_step_id(phase), "the_mob")

	world.add_feature("water", mob + Vector2(8, 4))
	world.add_feature("native_grass", mob + Vector2(-3, 2))
	world.add_feature("native_grass", mob + Vector2(3, -2))
	# More kangaroos join the mob once it has food and water, and walk in.
	_run(world, phase, "", 60.0)
	assert_eq(_present(world, "kangaroo"), 6)
	assert_eq(_step_id(phase), "possums")

	world.add_feature("nest_box", Vector2(-60, 52))
	_run(world, phase, "", 5.0)
	assert_eq(_present(world, "possum"), 1)
	assert_eq(_step_id(phase), "finished", "every species content: harmony")
	assert_true(world.harmony_reached())
	assert_almost(world.harmony_progress(), 1.0, 0.0001)


func test_phase_waits_at_harmony_if_a_species_is_not_content() -> void:
	var parts := _setup()
	var world: EcoWorld = parts[0]
	var phase: PhaseScript = parts[1]
	_run(world, phase, "roo_lead")
	# Possums arrive first, but the mob is still struggling.
	world.add_feature("nest_box", Vector2(-60, 52))
	_run(world, phase, "", 5.0)
	assert_eq(_step_id(phase), "the_mob")
	assert_true(not world.harmony_reached())

extends TestCase
## M3, the dingo: plays the predator tutorial from the real data files, and checks
## hunting, dens, rival packs, births and relocation in the ecosystem logic.

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


## The park as the player leaves it at the end of M2: wombats, a grown kangaroo mob
## and a possum, all content.
func _m2_world() -> EcoWorld:
	var park: Dictionary = DataFiles.load_json(WOMBAT_PARK)
	var world := EcoWorld.from_park(park, _species(["wombat"]), int(park["seed"]))
	var home := world.find_animal("lonely").home
	world.add_feature("burrow", home + Vector2(2, 1))
	world.add_feature("native_grass", home + Vector2(-3, 2))
	for f in world.features.duplicate():
		if f.kind in EcoWorld.DETRITUS_KINDS:
			world.clean_up_at(f.pos, 0.5)
	_run(world, null, "", 90.0)
	var m2: Dictionary = DataFiles.load_json(park["next_stage"])
	world.add_content(m2, _species(["kangaroo", "possum"]))
	var mob := world.find_animal("roo_lead").home
	world.add_feature("water", mob + Vector2(8, 4))
	world.add_feature("native_grass", mob + Vector2(-3, 2))
	world.add_feature("nest_box", Vector2(-60, 52))
	_run(world, null, "", 60.0)
	return world


## Returns [world, phase] with the dingo stage added and its first step entered.
func _setup() -> Array:
	var world := _m2_world()
	var m2: Dictionary = DataFiles.load_json("res://data/parks/apply_learnings.json")
	var stage: Dictionary = DataFiles.load_json(m2["next_stage"])
	world.add_content(stage, _species(["dingo"]))
	var phase := PhaseScript.from_dict(DataFiles.load_json(stage["phase"]))
	phase.step_changed.connect(func(step: Dictionary) -> void: PhaseScript.run_actions(step, world))
	PhaseScript.run_actions(phase.current_step(), world)
	return [world, phase]


func test_m2_ends_in_harmony_before_the_dingo() -> void:
	var world := _m2_world()
	assert_true(world.harmony_reached())


func test_arrival_hunt_always_fails() -> void:
	# Whatever the seed, the story hunt that announces the dingo never succeeds.
	for i in 3:
		var parts := _setup()
		var world: EcoWorld = parts[0]
		var roos := world.present("kangaroo").size()
		assert_eq(world.hunts.size(), 1, "the arrival hunt starts straight away")
		assert_true(world.hunts[0]["forced"])
		_run(world, parts[1], "", 8.0)
		assert_eq(world.hunts_finished, 1)
		assert_eq(world.hunts_succeeded, 0, "the kangaroo always gets away")
		assert_true(world.present("kangaroo").size() >= roos)


func test_dingo_tutorial_in_order_and_family_joins() -> void:
	var parts := _setup()
	var world: EcoWorld = parts[0]
	var phase: PhaseScript = parts[1]
	var dingo := world.find_animal("dingo_1")

	_run(world, phase, "", 8.0)
	assert_eq(_step_id(phase), "meet")
	_run(world, phase, "dingo_1")
	assert_eq(_step_id(phase), "den")

	world.add_feature("rock_den", dingo.home + Vector2(3, 2))
	_run(world, phase, "dingo_1")
	assert_eq(_step_id(phase), "water")

	world.add_feature("water", dingo.home + Vector2(-10, 6))
	_run(world, phase, "dingo_1")
	assert_eq(_step_id(phase), "family")

	# Prey, water and a den: the family joins and walks in from the edge.
	_run(world, phase, "", 90.0)
	assert_true(world.present("dingo").size() >= 3)
	# The harmony step can pass at once if the mob has already grown enough.
	assert_true(_step_id(phase) in ["harmony", "finished"], "got " + _step_id(phase))


func test_pack_shares_prey_and_tip_appears_when_hungry() -> void:
	var parts := _setup()
	var world: EcoWorld = parts[0]
	var phase: PhaseScript = parts[1]
	var tips: Array[String] = []
	phase.tip_shown.connect(func(tip: Dictionary) -> void: tips.append(tip["id"]))
	var dingo := world.find_animal("dingo_1")
	assert_almost(dingo.need_target["food"], 1.0, 0.0001, "plenty of prey for one dingo")
	world.add_feature("rock_den", dingo.home + Vector2(3, 2))
	world.add_feature("water", dingo.home + Vector2(-10, 6))
	_run(world, phase, "dingo_1", 90.0)
	assert_true(dingo.need_target["food"] < 0.8, "three dingoes share the same prey")
	assert_true("prey_must_thrive" in tips)


func test_prey_recovers_and_the_park_reaches_harmony_with_dingoes() -> void:
	var parts := _setup()
	var world: EcoWorld = parts[0]
	var phase: PhaseScript = parts[1]
	var dingo := world.find_animal("dingo_1")
	world.add_feature("rock_den", dingo.home + Vector2(3, 2))
	world.add_feature("water", dingo.home + Vector2(-10, 6))
	_run(world, phase, "dingo_1", 8.0)
	var reached := false
	var t := 0.0
	while t < 1500.0 and not reached:
		_run(world, phase, "", 10.0)
		t += 10.0
		reached = world.harmony_reached()
	assert_true(reached, "kangaroo births outpace the pack's hunting")


func test_predators_and_prey_settle_into_a_stable_balance() -> void:
	var parts := _setup()
	var world: EcoWorld = parts[0]
	var dingo := world.find_animal("dingo_1")
	world.add_feature("rock_den", dingo.home + Vector2(3, 2))
	world.add_feature("water", dingo.home + Vector2(-10, 6))
	_run(world, null, "", 2400.0)
	assert_true(world.hunts_succeeded >= 5, "the dingoes have been hunting")
	var roos := world.present("kangaroo").size()
	assert_true(roos >= 8 and roos <= 14, "the mob holds steady, got %d" % roos)
	assert_true(world.present("dingo").size() >= 3, "the pack holds steady")
	assert_true(world.harmony_progress() > 0.95)


func test_hollow_log_only_suits_a_small_family() -> void:
	var parts := _setup()
	var world: EcoWorld = parts[0]
	var dingo := world.find_animal("dingo_1")
	world.add_feature("hollow_log", dingo.home + Vector2(3, 2))
	world.refresh_needs()
	assert_almost(dingo.parts["shelter"], 1.0, 0.0001, "a lone dingo can den in a hollow log")
	world.add_feature("water", dingo.home + Vector2(-10, 6))
	_run(world, null, "", 90.0)
	assert_true(world.present("dingo").size() >= 3)
	assert_almost(dingo.parts["shelter"], 0.0, 0.0001, "a family of three needs a bigger den")


func test_dingoes_only_take_burrows_no_wombat_is_using() -> void:
	var parts := _setup()
	var world: EcoWorld = parts[0]
	var dingo := world.find_animal("dingo_1")
	var burrow := world.add_feature("burrow", dingo.home + Vector2(3, 2))
	assert_almost(dingo.parts["shelter"], 1.0, 0.0001, "an empty burrow works as a den")
	var wombat := world.find_animal("lonely")
	wombat.home = burrow.pos
	world.refresh_needs()
	assert_almost(dingo.parts["shelter"], 0.0, 0.0001, "not a burrow a wombat lives in")


func test_rival_packs_compete_for_dens_water_and_prey() -> void:
	var world := _m2_world()
	var dingo_sp := SpeciesDef.load_file(SPECIES_DIR + "dingo.json")
	world.species_defs["dingo"] = dingo_sp
	var a := world.add_animal("a", dingo_sp, Vector2(100, -100))
	a.group = "north"
	world.add_feature("rock_den", Vector2(108, -100))
	world.add_feature("water", Vector2(110, -95))
	world.refresh_needs()
	assert_almost(a.parts["shelter"], 1.0, 0.0001)
	assert_almost(a.need_target["water"], 1.0, 0.0001)
	var food_alone := float(a.need_target["food"])

	# A rival pack settles right beside the den and the water.
	var b := world.add_animal("b", dingo_sp, Vector2(112, -98))
	b.group = "south"
	world.refresh_needs()
	assert_almost(a.parts["shelter"], 0.0, 0.0001, "the den is in the rival's territory now")
	assert_true(a.need_target["water"] < 1.0, "so is the water (only far-off water is left)")
	assert_true(float(a.need_target["food"]) < food_alone, "both packs hunt the same prey")
	assert_almost(b.parts["shelter"], 1.0, 0.0001)


func test_relocation_only_moves_relocatable_animals() -> void:
	var parts := _setup()
	var world: EcoWorld = parts[0]
	var dingo := world.find_animal("dingo_1")
	assert_true(not world.relocate(world.find_animal("lonely")), "wombats can't be relocated")
	assert_true(world.relocate(dingo))
	assert_true(world.find_animal("dingo_1") == null)


func test_kangaroos_arrive_from_outside_when_few_are_left() -> void:
	var world := _m2_world()
	var roos := world.present("kangaroo")
	while roos.size() > 2:
		world.remove_animal(roos.pop_back(), "hunted")
	_run(world, null, "", 100.0)
	assert_true(world.present("kangaroo").size() > 2)


func test_same_seed_same_story() -> void:
	var a: EcoWorld = _setup()[0]
	var b: EcoWorld = _setup()[0]
	_run(a, null, "", 300.0)
	_run(b, null, "", 300.0)
	assert_eq(a.hunts_finished, b.hunts_finished)
	assert_eq(a.present("kangaroo").size(), b.present("kangaroo").size())

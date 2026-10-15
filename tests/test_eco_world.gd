extends TestCase


func _species() -> SpeciesDef:
	return SpeciesDef.from_dict({
		"id": "testbeast",
		"name": "Test beast",
		"needs": [
			{"id": "water", "type": "resource", "feature": "water", "range": 5},
			{"id": "safety", "type": "safety", "shelter": "burrow", "range": 4,
				"shelter_share": 0.5, "fear_kinds": ["litter"], "fear_radius": 6, "fear_per_item": 0.5},
			{"id": "company", "type": "company", "range": 8, "wanted": 2},
		],
	})


func test_resource_need_met_in_range_and_fades_beyond() -> void:
	var world := EcoWorld.new()
	var a := world.add_animal("a", _species(), Vector2.ZERO)
	world.refresh_needs()
	assert_almost(a.need_target["water"], 0.0)
	var pond := world.add_feature("water", Vector2(4, 0))
	assert_almost(a.need_target["water"], 1.0)
	world.remove_feature(pond)
	world.add_feature("water", Vector2(7.5, 0))
	assert_almost(a.need_target["water"], 0.5)


func test_safety_combines_shelter_and_calm() -> void:
	var world := EcoWorld.new()
	var a := world.add_animal("a", _species(), Vector2.ZERO)
	world.add_feature("litter", Vector2(1, 0))
	assert_almost(a.parts["calm"], 0.5)
	assert_almost(a.need_target["safety"], 0.25)
	world.add_feature("burrow", Vector2(2, 0))
	assert_almost(a.need_target["safety"], 0.75)
	world.clean_up_at(Vector2(1.2, 0), 1.0)
	assert_almost(a.need_target["safety"], 1.0)


func test_clean_up_ignores_non_detritus_and_far_clicks() -> void:
	var world := EcoWorld.new()
	world.add_feature("burrow", Vector2.ZERO)
	world.add_feature("litter", Vector2(10, 0))
	assert_true(world.clean_up_at(Vector2.ZERO, 2.0) == null)
	assert_eq(world.features.size(), 2)


func test_company_counts_present_animals_only() -> void:
	var world := EcoWorld.new()
	var sp := _species()
	var a := world.add_animal("a", sp, Vector2.ZERO)
	var b := world.add_animal("b", sp, Vector2(3, 0))
	var c := world.add_animal("c", sp, Vector2(-3, 0))
	c.hidden = true
	world.refresh_needs()
	assert_almost(a.need_target["company"], 0.5)
	c.hidden = false
	world.refresh_needs()
	assert_almost(a.need_target["company"], 1.0)
	assert_true(b != null)


func test_contentedness_is_weighted_average() -> void:
	var world := EcoWorld.new()
	var a := world.add_animal("a", _species(), Vector2.ZERO)
	world.add_feature("water", Vector2(1, 0))
	# water 1, safety 0.5 (calm but no burrow), company 0
	assert_almost(world.contentedness(a, true), 0.5)


func test_land_health_and_hidden_animals_emerge() -> void:
	var sp := _species()
	var park := {
		"features": [
			{"kind": "litter", "pos": [10, 0]},
			{"kind": "invasive_plant", "pos": [-10, 0]},
		],
		"animals": [
			{"key": "host", "species": "testbeast", "pos": [0, 0]},
			{"key": "shy", "species": "testbeast", "pos": [30, 30],
				"hidden_until": {"land_health": 1.0, "join": "host"}},
		],
	}
	var world := EcoWorld.from_park(park, {"testbeast": sp}, 5)
	var shy := world.find_animal("shy")
	assert_almost(world.land_health(), 0.0)
	world.clean_up_at(Vector2(10, 0), 1.0)
	assert_almost(world.land_health(), 0.5)
	world.tick(0.1)
	assert_true(shy.hidden)
	world.clean_up_at(Vector2(-10, 0), 1.0)
	world.tick(0.1)
	assert_true(not shy.hidden)
	assert_true(shy.home.distance_to(Vector2.ZERO) < 4.0, "joins the host's home")


func test_same_seed_moves_animals_the_same_way() -> void:
	var positions := []
	for run in 2:
		var world := EcoWorld.new(77)
		var a := world.add_animal("a", _species(), Vector2.ZERO)
		for i in 300:
			world.tick(0.1)
		positions.append(a.pos)
	assert_eq(positions[0], positions[1])

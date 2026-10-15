extends TestCase


func _sequence(rng: SeededRng, count: int) -> Array:
	var values := []
	for i in count:
		values.append(rng.next_float())
	return values


func test_same_seed_gives_same_sequence() -> void:
	assert_eq(_sequence(SeededRng.new(42), 20), _sequence(SeededRng.new(42), 20))


func test_different_seeds_differ() -> void:
	assert_true(_sequence(SeededRng.new(1), 20) != _sequence(SeededRng.new(2), 20))


func test_range_int_stays_in_bounds() -> void:
	var rng := SeededRng.new(7)
	for i in 1000:
		var v := rng.range_int(3, 5)
		assert_true(v >= 3 and v <= 5, "got %d" % v)


func test_fork_is_deterministic_and_independent() -> void:
	var a := SeededRng.new(99).fork(1)
	var b := SeededRng.new(99).fork(1)
	var c := SeededRng.new(99).fork(2)
	var seq_a := _sequence(a, 10)
	assert_eq(seq_a, _sequence(b, 10))
	assert_true(seq_a != _sequence(c, 10))

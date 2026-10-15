extends TestCase


func test_distance_hits_both_ends() -> void:
	assert_almost(CameraMath.distance_for_zoom(0.0, 4.0, 260.0), 4.0)
	assert_almost(CameraMath.distance_for_zoom(1.0, 4.0, 260.0), 260.0, 0.001)


func test_distance_grows_with_zoom() -> void:
	var previous := 0.0
	for i in 11:
		var d := CameraMath.distance_for_zoom(i / 10.0, 4.0, 260.0)
		assert_true(d > previous)
		previous = d


func test_zoom_is_clamped() -> void:
	assert_almost(CameraMath.distance_for_zoom(-1.0, 4.0, 260.0), 4.0)
	assert_almost(CameraMath.distance_for_zoom(2.0, 4.0, 260.0), 260.0, 0.001)


func test_pitch_hits_both_ends() -> void:
	assert_almost(CameraMath.pitch_for_zoom(0.0, 18.0, 62.0), 18.0)
	assert_almost(CameraMath.pitch_for_zoom(1.0, 18.0, 62.0), 62.0)


func test_focus_is_clamped_to_park() -> void:
	var clamped := CameraMath.clamp_focus(Vector3(500, 3, -500), 128.0)
	assert_eq(clamped, Vector3(128, 3, -128))

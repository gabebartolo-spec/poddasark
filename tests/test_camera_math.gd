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


func test_zoom_for_distance_inverts_distance_for_zoom() -> void:
	for i in 11:
		var t := i / 10.0
		var d := CameraMath.distance_for_zoom(t, 4.0, 260.0)
		assert_almost(CameraMath.zoom_for_distance(d, 4.0, 260.0), t, 0.0001)


func test_zoom_for_distance_keeps_view_when_range_grows() -> void:
	# The wombat corner's widest view, re-expressed in the bigger park's zoom range.
	var d := CameraMath.distance_for_zoom(1.0, 4.0, 90.0)
	var t := CameraMath.zoom_for_distance(d, 4.0, 280.0)
	assert_almost(CameraMath.distance_for_zoom(t, 4.0, 280.0), d, 0.001)

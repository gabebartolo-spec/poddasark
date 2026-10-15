class_name CameraMath
extends RefCounted
## Pure helpers for the overhead camera, kept out of the node so they can be tested.


## Pitch (degrees below the horizon) for a zoom level. Close in, the camera looks
## across the ground at an animal; zoomed out, it looks down at the park like a map.
## zoom_t is 0 at the closest zoom and 1 at the widest.
static func pitch_for_zoom(zoom_t: float, close_pitch: float, wide_pitch: float) -> float:
	return lerpf(close_pitch, wide_pitch, ease(clampf(zoom_t, 0.0, 1.0), 0.6))


## Distance for a zoom level. Uses an exponential curve so each scroll step feels
## the same size whether you're looking at one wombat or the whole park.
static func distance_for_zoom(zoom_t: float, min_distance: float, max_distance: float) -> float:
	var t := clampf(zoom_t, 0.0, 1.0)
	return min_distance * pow(max_distance / min_distance, t)


## Keeps the camera's focus point inside the park's square bounds.
static func clamp_focus(focus: Vector3, half_extent: float) -> Vector3:
	return Vector3(
		clampf(focus.x, -half_extent, half_extent),
		focus.y,
		clampf(focus.z, -half_extent, half_extent))

class_name CameraRig
extends Node3D
## Free overhead camera (director decisions, M0: free rotation, zoom close to wide).
##
## Controls:
##   Pan:    WASD / arrow keys, or drag with the middle mouse button
##   Rotate: drag with the right mouse button, or Q / E
##   Zoom:   mouse wheel
##
## The rig sits on the ground at the point the camera looks at. Yaw turns the rig,
## and the camera sits behind it at a distance and pitch set by the zoom level.

@export_group("Zoom")
## Closest distance, roughly one small animal filling the view.
@export var min_distance := 4.0
## Widest distance, the whole placeholder park in view.
@export var max_distance := 260.0
## Zoom amount per mouse wheel step (fraction of the full range).
@export var zoom_step := 0.06
@export_range(0.0, 1.0) var start_zoom := 0.55

@export_group("Angle")
## Degrees below the horizon when fully zoomed in.
@export var close_pitch := 18.0
## Degrees below the horizon when fully zoomed out.
@export var wide_pitch := 62.0

@export_group("Movement")
## Pan speed in view-heights per second, so panning feels the same at every zoom.
@export var pan_speed := 0.9
## Degrees per second when rotating with Q / E.
@export var key_rotate_speed := 90.0
## Degrees per pixel when rotating with the right mouse button.
@export var mouse_rotate_speed := 0.3
## How quickly the camera catches up with input (higher is snappier).
@export var smoothing := 10.0
## Half the width of the area the camera can pan across.
@export var bounds_half_extent := 128.0

@onready var _camera: Camera3D = $Camera3D

var _focus := Vector3.ZERO
var _yaw := 0.0
var _zoom_t := 0.0

var _target_focus := Vector3.ZERO
var _target_yaw := 0.0
var _target_zoom_t := 0.0

var _rotating := false
var _panning := false


func _ready() -> void:
	_target_zoom_t = start_zoom
	_zoom_t = start_zoom
	_focus = global_position
	_target_focus = _focus
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_target_zoom_t = clampf(_target_zoom_t - zoom_step, 0.0, 1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_target_zoom_t = clampf(_target_zoom_t + zoom_step, 0.0, 1.0)
			MOUSE_BUTTON_RIGHT:
				_rotating = event.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
	elif event is InputEventMouseMotion:
		if _rotating:
			_target_yaw -= deg_to_rad(event.relative.x * mouse_rotate_speed)
		if _panning:
			var per_pixel := _view_height() / get_viewport().get_visible_rect().size.y
			_target_focus -= _ground_basis() * Vector3(event.relative.x, 0.0, event.relative.y) * per_pixel
			_target_focus = CameraMath.clamp_focus(_target_focus, bounds_half_extent)


func _process(delta: float) -> void:
	_read_keys(delta)
	var w := 1.0 - exp(-smoothing * delta)
	_focus = _focus.lerp(_target_focus, w)
	_yaw = lerpf(_yaw, _target_yaw, w)
	_zoom_t = lerpf(_zoom_t, _target_zoom_t, w)
	_apply()


func _read_keys(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		move.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if move != Vector2.ZERO:
		var step := move.normalized() * pan_speed * _view_height() * delta
		_target_focus += _ground_basis() * Vector3(step.x, 0.0, step.y)
		_target_focus = CameraMath.clamp_focus(_target_focus, bounds_half_extent)

	if Input.is_physical_key_pressed(KEY_Q):
		_target_yaw += deg_to_rad(key_rotate_speed) * delta
	if Input.is_physical_key_pressed(KEY_E):
		_target_yaw -= deg_to_rad(key_rotate_speed) * delta


func _apply() -> void:
	global_position = _focus
	rotation = Vector3(0.0, _yaw, 0.0)
	var distance := CameraMath.distance_for_zoom(_zoom_t, min_distance, max_distance)
	var pitch := deg_to_rad(CameraMath.pitch_for_zoom(_zoom_t, close_pitch, wide_pitch))
	_camera.position = Vector3(0.0, sin(pitch) * distance, cos(pitch) * distance)
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)


## Rotation that maps screen-relative movement onto the ground plane.
func _ground_basis() -> Basis:
	return Basis(Vector3.UP, _yaw)


## Rough height of the ground area in view, used to scale pan speed with zoom.
func _view_height() -> float:
	return CameraMath.distance_for_zoom(_zoom_t, min_distance, max_distance)

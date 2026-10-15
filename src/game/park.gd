class_name Park
extends Node3D
## Plays a park from data: mirrors the EcoWorld in the scene, runs the phase script,
## and turns clicks into observing, placing and cleaning up.
##
## All visuals here are neutral grey placeholders, labelled as such.

@export_file("*.json") var park_path := "res://data/parks/wombat_tutorial.json"
@export_file("*.json") var phase_path := "res://data/phases/wombat_tutorial.json"
@export var camera_rig_path: NodePath = ^"../CameraRig"
## Screen distance in pixels within which a click picks an animal.
@export var pick_radius_px := 48.0

const SPECIES_DIR := "res://data/species/"
const MOOD_ICONS := [":(", ":|", ":)"]

var world: EcoWorld
var phase: PhaseScript

var _park: Dictionary
## Path of the next campaign stage (from the current stage's "next_stage"), or "".
var _next_stage := ""
## Half the width of the area the player can currently place things in.
var _bounds := 128.0
var _rig: CameraRig
var _hud: Hud
var _tool := "observe"
var _placeables: Dictionary = {}
var _feature_nodes: Dictionary = {}
var _animal_nodes: Dictionary = {}
var _mood_labels: Dictionary = {}
var _selected: EcoAnimal = null
var _selection_ring: MeshInstance3D
var _materials: Dictionary = {}


func _ready() -> void:
	_rig = get_node(camera_rig_path)
	_park = DataFiles.load_json(park_path)
	_next_stage = _park.get("next_stage", "")
	for p in _park.get("placeables", []):
		_placeables[p["id"]] = p

	# Build from data, then mirror the finished world and listen for changes.
	world = EcoWorld.from_park(_park, _load_species(_park), int(_park.get("seed", 1)))
	world.feature_added.connect(_on_feature_added)
	world.feature_removed.connect(_on_feature_removed)
	world.animal_emerged.connect(_on_animal_emerged)
	world.animal_added.connect(_spawn_animal)
	for feature in world.features:
		_on_feature_added(feature)
	for animal in world.animals:
		_spawn_animal(animal)

	_selection_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.75
	ring.outer_radius = 0.9
	_selection_ring.mesh = ring
	_selection_ring.material_override = _grey(0.95)
	_selection_ring.visible = false
	add_child(_selection_ring)

	var cam: Dictionary = _park.get("camera", {})
	var focus := DataFiles.to_vec2(cam.get("focus", [0, 0]))
	_bounds = float(cam.get("bounds_half_extent", 128.0))
	_rig.configure(Vector3(focus.x, 0.0, focus.y), float(cam.get("start_zoom", 0.4)),
		_bounds, float(cam.get("max_distance", 260.0)))

	_hud = Hud.new()
	add_child(_hud)
	_hud.setup_tools(_placeables.values())
	_hud.tool_selected.connect(func(tool_id: String) -> void: _tool = tool_id)
	_hud.continue_pressed.connect(_advance_stage)

	_start_phase(phase_path)


## Species used by a park or stage's animals and move-ins, loaded from data/species/.
func _load_species(d: Dictionary) -> Dictionary:
	var species := {}
	var ids: Array = []
	for a in d.get("animals", []):
		ids.append(a["species"])
	for m in d.get("move_ins", []):
		ids.append(m["species"])
	ids.append_array(d.get("harmony_species", []))
	for id in ids:
		if not species.has(id) and not world_has_species(id):
			species[id] = SpeciesDef.load_file(SPECIES_DIR + String(id) + ".json")
	return species


func world_has_species(id: String) -> bool:
	return world != null and world.species_defs.has(id)


func _start_phase(path: String) -> void:
	phase = PhaseScript.from_dict(DataFiles.load_json(path))
	phase.step_changed.connect(func(_step: Dictionary) -> void: _show_current_step())
	phase.finished.connect(func(finale: Dictionary) -> void:
		_hud.show_finale(finale, _next_stage != ""))
	_show_current_step()


## The seamless zoom-out: adds the next stage to the same world, widens the park,
## pulls the camera back and starts the next phase. Everything built so far stays.
func _advance_stage() -> void:
	if _next_stage == "":
		return
	var stage: Dictionary = DataFiles.load_json(_next_stage)
	_next_stage = stage.get("next_stage", "")
	world.add_content(stage, _load_species(stage))
	for p in stage.get("placeables_add", []):
		_placeables[p["id"]] = p
	_hud.setup_tools(_placeables.values())
	_set_tool("observe")
	var cam: Dictionary = stage.get("camera", {})
	var focus := DataFiles.to_vec2(cam.get("focus", [0, 0]))
	_bounds = float(cam.get("bounds_half_extent", _bounds))
	_rig.retarget(Vector3(focus.x, 0.0, focus.y), float(cam.get("start_zoom", 0.6)),
		_bounds, float(cam.get("max_distance", 260.0)))
	_start_phase(stage["phase"])


func _process(delta: float) -> void:
	world.tick(delta)
	for animal in world.animals:
		_sync_animal(animal)
	phase.update(world, _selected.key if _selected != null else "")
	_hud.set_land_health(world.land_health())
	_hud.set_harmony(world.harmony_progress(), world.harmony_report())
	if _selected != null:
		_hud.update_animal(_selected, world)
		var node: Node3D = _animal_nodes[_selected.id]
		_selection_ring.position = Vector3(node.position.x, 0.05, node.position.z)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_click(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_set_tool("observe")
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var ids := _hud.tool_ids()
			var i: int = event.keycode - KEY_1
			if i < ids.size():
				_set_tool(ids[i])


func _set_tool(tool_id: String) -> void:
	_tool = tool_id
	_hud.set_active_tool(tool_id)


func _click(screen_pos: Vector2) -> void:
	if _tool == "observe":
		_select(_pick_animal(screen_pos))
		return
	var ground: Variant = _ground_point(screen_pos)
	if ground == null:
		return
	var pos := Vector2(ground.x, ground.z)
	if _tool == "clean_up":
		world.clean_up_at(pos, float(_park.get("clean_up_radius", 2.0)))
	elif _placeables.has(_tool):
		if absf(pos.x) <= _bounds and absf(pos.y) <= _bounds:
			world.add_feature(_placeables[_tool]["kind"], pos)


func _select(animal: EcoAnimal) -> void:
	_selected = animal
	_selection_ring.visible = animal != null
	if animal == null:
		_hud.hide_animal()
	else:
		_hud.show_animal(animal)


func _pick_animal(screen_pos: Vector2) -> EcoAnimal:
	var cam := _rig.camera()
	var best: EcoAnimal = null
	var best_d := pick_radius_px
	for animal in world.animals:
		if not animal.is_present():
			continue
		var p := Vector3(animal.pos.x, 0.4, animal.pos.y)
		if cam.is_position_behind(p):
			continue
		var d := cam.unproject_position(p).distance_to(screen_pos)
		if d < best_d:
			best = animal
			best_d = d
	return best


## Where a screen point hits the ground plane, or null.
func _ground_point(screen_pos: Vector2) -> Variant:
	var cam := _rig.camera()
	return Plane(Vector3.UP, 0.0).intersects_ray(
		cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))


func _show_current_step() -> void:
	if not phase.is_finished:
		_hud.show_step(phase.current_step(), phase.index + 1, phase.steps.size())


func _on_feature_added(feature: EcoFeature) -> void:
	if _feature_nodes.has(feature.id):
		return
	var node := _make_feature_node(feature.kind)
	node.position = Vector3(feature.pos.x, 0.0, feature.pos.y)
	add_child(node)
	_feature_nodes[feature.id] = node


func _on_feature_removed(feature: EcoFeature) -> void:
	if _feature_nodes.has(feature.id):
		_feature_nodes[feature.id].queue_free()
		_feature_nodes.erase(feature.id)


func _on_animal_emerged(animal: EcoAnimal) -> void:
	_animal_nodes[animal.id].visible = true


func _spawn_animal(animal: EcoAnimal) -> void:
	if _animal_nodes.has(animal.id):
		return
	var shape: Dictionary = animal.species.placeholder
	var scale := float(shape.get("scale", 1.0))
	var upright: bool = shape.get("shape", "low") == "upright"
	var node := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35 * scale
	capsule.height = 1.0 * scale
	body.mesh = capsule
	body.material_override = _grey(0.38)
	if upright:
		# Standing body, e.g. a kangaroo.
		body.position = Vector3(0.0, 0.5 * scale, 0.0)
	else:
		# Lie the capsule along the animal's facing direction: low and stocky.
		body.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
		body.position = Vector3(0.0, 0.35 * scale, 0.0)
	node.add_child(body)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22 * scale
	sphere.height = 0.44 * scale
	head.mesh = sphere
	head.material_override = _grey(0.3)
	head.position = Vector3(0.0, 1.05 * scale, -0.15 * scale) if upright \
		else Vector3(0.0, 0.4 * scale, -0.55 * scale)
	node.add_child(head)
	var top := (1.3 if upright else 0.75) * scale
	node.add_child(_label("placeholder: " + animal.species.display_name.to_lower(), top + 0.3, 32))
	var mood := _label("", top + 0.7, 72)
	mood.no_depth_test = true
	node.add_child(mood)
	_mood_labels[animal.id] = mood
	node.position = Vector3(animal.pos.x, 0.0, animal.pos.y)
	node.visible = animal.is_present()
	add_child(node)
	_animal_nodes[animal.id] = node


func _sync_animal(animal: EcoAnimal) -> void:
	var node: Node3D = _animal_nodes[animal.id]
	if not animal.is_present():
		return
	var target := Vector3(animal.pos.x, 0.0, animal.pos.y)
	var step := target - node.position
	if step.length() > 0.001:
		node.look_at(node.position + step, Vector3.UP)
	node.position = target
	var c := world.contentedness(animal)
	var icon: String = MOOD_ICONS[1]
	if c < animal.species.mood_low:
		icon = MOOD_ICONS[0]
	elif c >= animal.species.mood_high:
		icon = MOOD_ICONS[2]
	_mood_labels[animal.id].text = icon


func _make_feature_node(kind: String) -> Node3D:
	var node := Node3D.new()
	var mesh := MeshInstance3D.new()
	var label_height := 1.0
	match kind:
		"water":
			var m := CylinderMesh.new()
			m.top_radius = 2.2
			m.bottom_radius = 2.2
			m.height = 0.06
			mesh.mesh = m
			mesh.material_override = _grey(0.78)
			mesh.position.y = 0.03
		"native_grass":
			var m := CylinderMesh.new()
			m.top_radius = 0.0
			m.bottom_radius = 0.9
			m.height = 0.6
			mesh.mesh = m
			mesh.material_override = _grey(0.58)
			mesh.position.y = 0.3
		"burrow":
			var m := SphereMesh.new()
			m.radius = 0.9
			m.height = 0.9
			m.is_hemisphere = true
			mesh.mesh = m
			mesh.material_override = _grey(0.22)
			label_height = 1.4
		"litter":
			var m := BoxMesh.new()
			m.size = Vector3(0.35, 0.2, 0.25)
			mesh.mesh = m
			mesh.material_override = _grey(0.92)
			mesh.position.y = 0.1
			label_height = 0.6
		"pollutant":
			var m := CylinderMesh.new()
			m.top_radius = 1.0
			m.bottom_radius = 1.0
			m.height = 0.04
			mesh.mesh = m
			mesh.material_override = _grey(0.1)
			mesh.position.y = 0.02
			label_height = 0.6
		"invasive_plant":
			var m := CylinderMesh.new()
			m.top_radius = 0.0
			m.bottom_radius = 0.6
			m.height = 1.8
			mesh.mesh = m
			mesh.material_override = _grey(0.3)
			mesh.position.y = 0.9
			label_height = 2.2
		"eucalypt":
			var trunk := CylinderMesh.new()
			trunk.top_radius = 0.25
			trunk.bottom_radius = 0.35
			trunk.height = 4.0
			mesh.mesh = trunk
			mesh.material_override = _grey(0.35)
			mesh.position.y = 2.0
			var canopy := MeshInstance3D.new()
			var crown := SphereMesh.new()
			crown.radius = 2.2
			crown.height = 3.2
			canopy.mesh = crown
			canopy.material_override = _grey(0.55)
			canopy.position.y = 5.0
			node.add_child(canopy)
			label_height = 7.0
		"nest_box":
			var post := CylinderMesh.new()
			post.top_radius = 0.08
			post.bottom_radius = 0.08
			post.height = 2.0
			mesh.mesh = post
			mesh.material_override = _grey(0.35)
			mesh.position.y = 1.0
			var box := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(0.5, 0.6, 0.5)
			box.mesh = b
			box.material_override = _grey(0.6)
			box.position.y = 2.2
			node.add_child(box)
			label_height = 3.0
		_:
			var m := BoxMesh.new()
			m.size = Vector3(0.5, 0.5, 0.5)
			mesh.mesh = m
			mesh.material_override = _grey(0.5)
			mesh.position.y = 0.25
	node.add_child(mesh)
	node.add_child(_label("placeholder: " + kind.replace("_", " "), label_height, 32))
	return node


func _label(text: String, height: float, size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.12, 0.12, 0.12)
	label.outline_modulate = Color(0.85, 0.85, 0.85)
	label.position = Vector3(0.0, height, 0.0)
	return label


func _grey(v: float) -> StandardMaterial3D:
	if not _materials.has(v):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(v, v, v)
		mat.roughness = 1.0
		_materials[v] = mat
	return _materials[v]

class_name Hud
extends CanvasLayer
## On-screen UI for the wombat tutorial: build note, tutorial panel, needs panel
## and toolbar. Built in code. Placeholder styling (Godot's default theme) until the
## director sets the look in M5.

signal tool_selected(tool_id: String)

const BUILD_NOTE := "PLACEHOLDER ART - M1 wombat tutorial build\n" \
	+ "Pan: WASD / arrows or middle-drag   Rotate: right-drag or Q / E   Zoom: wheel\n" \
	+ "Tools: 1-5, Esc to go back to Observe"

var _root: Control
var _tool_buttons: Dictionary = {}
var _step_title: Label
var _step_body: Label
var _step_count: Label
var _land_label: Label
var _land_bar: ProgressBar

var _needs_panel: PanelContainer
var _animal_name: Label
var _animal_species: Label
var _mood_bar: ProgressBar
var _need_rows: VBoxContainer
var _need_bars: Dictionary = {}
var _issues: Label
var _fact: Label
var _fact_index := 0


func _ready() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_build_left_column(_root)
	_build_needs_panel(_root)


## Builds the toolbar. placeables are the park's placeable entries.
func setup_tools(placeables: Array) -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_bottom = -12
	_root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)

	var group := ButtonGroup.new()
	var tools: Array = [{"id": "observe", "label": "Observe"}]
	tools.append_array(placeables)
	tools.append({"id": "clean_up", "label": "Clean up"})
	for i in tools.size():
		var t: Dictionary = tools[i]
		var button := Button.new()
		var label: String = t["label"]
		if t.has("cost"):
			label += " (free)" if float(t["cost"]) == 0.0 else " (%d)" % int(t["cost"])
		button.text = "%d  %s" % [i + 1, label]
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(120, 40)
		var tool_id: String = t["id"]
		button.pressed.connect(func() -> void: tool_selected.emit(tool_id))
		row.add_child(button)
		_tool_buttons[tool_id] = button
	set_active_tool("observe")


func tool_ids() -> Array:
	return _tool_buttons.keys()


func set_active_tool(tool_id: String) -> void:
	if _tool_buttons.has(tool_id):
		_tool_buttons[tool_id].button_pressed = true


func show_step(step: Dictionary, number: int, total: int) -> void:
	_step_title.text = step.get("title", "")
	_step_body.text = step.get("body", "")
	_step_count.text = "Step %d of %d" % [number, total]
	var show_land: bool = step.get("show_land_health", false)
	_land_label.visible = show_land
	_land_bar.visible = show_land


func show_finale(finale: Dictionary) -> void:
	_step_title.text = finale.get("title", "")
	_step_body.text = finale.get("body", "")
	_step_count.text = "Tutorial complete"
	_land_label.visible = false
	_land_bar.visible = false


func set_land_health(value: float) -> void:
	_land_bar.value = value


## Shows the needs panel for an animal. Call once on selection, then update_animal.
func show_animal(animal: EcoAnimal) -> void:
	_needs_panel.visible = true
	_animal_name.text = animal.display_name
	var sp := animal.species
	_animal_species.text = sp.display_name + ("  (%s)" % sp.scientific_name if sp.scientific_name != "" else "")
	for child in _need_rows.get_children():
		child.queue_free()
	_need_bars.clear()
	for need_id in sp.need_order:
		var cfg: Dictionary = sp.needs[need_id]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = cfg.get("label", need_id)
		label.custom_minimum_size = Vector2(90, 0)
		row.add_child(label)
		var bar := _make_bar()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bar)
		_need_rows.add_child(row)
		_need_bars[need_id] = bar
	if sp.facts.is_empty():
		_fact.text = ""
	else:
		_fact.text = "Did you know? " + sp.facts[_fact_index % sp.facts.size()]
		_fact_index += 1


func update_animal(animal: EcoAnimal, world: EcoWorld) -> void:
	_mood_bar.value = world.contentedness(animal)
	var issues: Array[String] = []
	for need_id in animal.species.need_order:
		var cfg: Dictionary = animal.species.needs[need_id]
		if _need_bars.has(need_id):
			_need_bars[need_id].value = animal.need_value.get(need_id, 0.0)
		if cfg.has("issue_parts"):
			var issue_parts: Dictionary = cfg["issue_parts"]
			for part in issue_parts:
				if float(animal.parts.get(part, 1.0)) < 1.0:
					issues.append(issue_parts[part])
		elif cfg.has("issue") and float(animal.need_target.get(need_id, 1.0)) < 1.0:
			issues.append(cfg["issue"])
	_issues.text = "Content: needs are met" if issues.is_empty() else "\n".join(issues)


func hide_animal() -> void:
	_needs_panel.visible = false


func _build_left_column(root: Control) -> void:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.position = Vector2(16, 12)
	column.custom_minimum_size = Vector2(460, 0)
	column.add_theme_constant_override("separation", 10)
	root.add_child(column)

	var note := Label.new()
	note.text = BUILD_NOTE
	note.add_theme_font_size_override("font_size", 13)
	column.add_child(note)

	var panel := PanelContainer.new()
	column.add_child(panel)
	var box := _padded_vbox(panel)
	_step_count = Label.new()
	_step_count.add_theme_font_size_override("font_size", 13)
	box.add_child(_step_count)
	_step_title = Label.new()
	_step_title.add_theme_font_size_override("font_size", 24)
	box.add_child(_step_title)
	_step_body = _wrapping_label()
	box.add_child(_step_body)
	_land_label = Label.new()
	_land_label.text = "Land restored"
	box.add_child(_land_label)
	_land_bar = _make_bar()
	box.add_child(_land_bar)


func _build_needs_panel(root: Control) -> void:
	_needs_panel = PanelContainer.new()
	_needs_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_needs_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_needs_panel.offset_right = -16
	_needs_panel.offset_top = 12
	_needs_panel.custom_minimum_size = Vector2(340, 0)
	_needs_panel.visible = false
	root.add_child(_needs_panel)
	var box := _padded_vbox(_needs_panel)

	_animal_name = Label.new()
	_animal_name.add_theme_font_size_override("font_size", 22)
	box.add_child(_animal_name)
	_animal_species = Label.new()
	_animal_species.add_theme_font_size_override("font_size", 13)
	box.add_child(_animal_species)

	var mood_label := Label.new()
	mood_label.text = "Contentedness"
	box.add_child(mood_label)
	_mood_bar = _make_bar()
	_mood_bar.custom_minimum_size = Vector2(0, 22)
	box.add_child(_mood_bar)

	box.add_child(HSeparator.new())
	var needs_label := Label.new()
	needs_label.text = "Needs"
	box.add_child(needs_label)
	_need_rows = VBoxContainer.new()
	box.add_child(_need_rows)

	box.add_child(HSeparator.new())
	_issues = _wrapping_label()
	box.add_child(_issues)

	box.add_child(HSeparator.new())
	_fact = _wrapping_label()
	_fact.add_theme_font_size_override("font_size", 14)
	box.add_child(_fact)


func _padded_vbox(panel: PanelContainer) -> VBoxContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	return box


func _wrapping_label() -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(300, 0)
	return label


func _make_bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.01
	bar.custom_minimum_size = Vector2(0, 18)
	return bar

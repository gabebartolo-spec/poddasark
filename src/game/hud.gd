class_name Hud
extends CanvasLayer
## On-screen UI for the Australian park: build note, tutorial panel, harmony panel,
## needs panel and toolbar. Built in code. Placeholder styling (Godot's default theme) until the
## director sets the look in M5.

signal tool_selected(tool_id: String)
## The player pressed Continue on a finale that leads to another stage.
signal continue_pressed
## The player accepted the invitation to watch a hunt.
signal watch_pressed

const BUILD_NOTE := "PLACEHOLDER ART - M3 build (wombat, apply learnings, the dingo)\n" \
	+ "Pan: WASD / arrows or middle-drag   Rotate: right-drag or Q / E   Zoom: wheel\n" \
	+ "Tools: number keys, Esc to go back to Observe"

var _root: Control
var _tool_buttons: Dictionary = {}
var _step_title: Label
var _step_body: Label
var _step_count: Label
var _land_label: Label
var _land_bar: ProgressBar
var _continue_button: Button
var _toolbar: PanelContainer

var _tip_panel: PanelContainer
var _tip_title: Label
var _tip_body: Label
var _toast: Label
var _toast_time := 0.0
var _invite_panel: PanelContainer
var _invite_label: Label
var _doc_layer: Control
var _doc_caption: Label

var _harmony_panel: PanelContainer
var _harmony_bar: ProgressBar
var _checklist_button: Button
var _checklist: VBoxContainer

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
	_build_messages(_root)


## Builds (or rebuilds) the toolbar. placeables are the park's placeable entries.
## extra_tools are non-placing tools such as Relocate: {"id", "label"}.
func setup_tools(placeables: Array, extra_tools: Array = []) -> void:
	if _toolbar != null:
		_toolbar.queue_free()
		_tool_buttons.clear()
	var bar := PanelContainer.new()
	_toolbar = bar
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
	tools.append_array(extra_tools)
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
	_harmony_panel.visible = step.get("show_harmony", false)
	_continue_button.visible = false


## can_continue shows a Continue button that leads into the next stage.
func show_finale(finale: Dictionary, can_continue := false) -> void:
	_step_title.text = finale.get("title", "")
	_step_body.text = finale.get("body", "")
	_step_count.text = "Phase complete"
	_land_label.visible = false
	_land_bar.visible = false
	_continue_button.visible = can_continue


## progress is 0 to 1; report is EcoWorld.harmony_report().
func set_harmony(progress: float, report: Array) -> void:
	_harmony_bar.value = progress
	if not _checklist.visible:
		return
	while _checklist.get_child_count() < report.size():
		var row := Label.new()
		_checklist.add_child(row)
	for i in _checklist.get_child_count():
		var row: Label = _checklist.get_child(i)
		row.visible = i < report.size()
		if i < report.size():
			var entry: Dictionary = report[i]
			var state := "content"
			if int(entry["count"]) == 0:
				state = "not here yet"
			elif not entry["content"]:
				state = "needs help"
			row.text = "%s  %s (%d): %s" % ["[x]" if entry["content"] else "[  ]",
				entry["name"], int(entry["count"]), state]


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
	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.focus_mode = Control.FOCUS_NONE
	_continue_button.visible = false
	_continue_button.pressed.connect(func() -> void: continue_pressed.emit())
	box.add_child(_continue_button)

	_harmony_panel = PanelContainer.new()
	_harmony_panel.visible = false
	column.add_child(_harmony_panel)
	var hbox := _padded_vbox(_harmony_panel)
	var harmony_label := Label.new()
	harmony_label.text = "Harmony"
	harmony_label.add_theme_font_size_override("font_size", 20)
	hbox.add_child(harmony_label)
	_harmony_bar = _make_bar()
	_harmony_bar.custom_minimum_size = Vector2(0, 22)
	hbox.add_child(_harmony_bar)
	_checklist_button = Button.new()
	_checklist_button.text = "Show checklist"
	_checklist_button.focus_mode = Control.FOCUS_NONE
	_checklist_button.pressed.connect(_toggle_checklist)
	hbox.add_child(_checklist_button)
	_checklist = VBoxContainer.new()
	_checklist.visible = false
	hbox.add_child(_checklist)


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
		_toast.visible = _toast_time > 0.0


## A tip that appears the first time a situation happens in play. Stays until closed.
func show_tip(tip: Dictionary) -> void:
	_tip_title.text = tip.get("title", "")
	_tip_body.text = tip.get("body", "")
	_tip_panel.visible = true


## A short message above the toolbar that fades out.
func show_toast(text: String) -> void:
	_toast.text = text
	_toast_time = 4.0
	_toast.visible = true


func show_hunt_invite(text: String) -> void:
	_invite_label.text = text
	_invite_panel.visible = true


func hide_hunt_invite() -> void:
	_invite_panel.visible = false


## Wildlife-documentary framing for a hunt: letterbox bars and a narrated caption.
func show_documentary(caption: String) -> void:
	_doc_caption.text = caption
	_doc_layer.visible = true
	hide_hunt_invite()


func set_documentary_caption(caption: String) -> void:
	_doc_caption.text = caption


func hide_documentary() -> void:
	_doc_layer.visible = false


func _build_messages(root: Control) -> void:
	# Letterbox bars and caption for watching a hunt. Placeholder styling.
	_doc_layer = Control.new()
	_doc_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_doc_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_doc_layer.visible = false
	root.add_child(_doc_layer)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0.08, 0.08, 0.08, 0.92)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		if top:
			bar.offset_bottom = 90
		else:
			bar.offset_top = -110
		_doc_layer.add_child(bar)
	_doc_caption = Label.new()
	_doc_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_doc_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_doc_caption.add_theme_font_size_override("font_size", 22)
	_doc_caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_doc_caption.offset_top = -100
	_doc_caption.offset_bottom = -12
	_doc_caption.offset_left = 120
	_doc_caption.offset_right = -120
	_doc_layer.add_child(_doc_caption)

	_tip_panel = PanelContainer.new()
	_tip_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_tip_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tip_panel.offset_top = 12
	_tip_panel.custom_minimum_size = Vector2(420, 0)
	_tip_panel.visible = false
	root.add_child(_tip_panel)
	var box := _padded_vbox(_tip_panel)
	var tip_label := Label.new()
	tip_label.text = "Tip"
	tip_label.add_theme_font_size_override("font_size", 13)
	box.add_child(tip_label)
	_tip_title = Label.new()
	_tip_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_tip_title)
	_tip_body = _wrapping_label()
	_tip_body.custom_minimum_size = Vector2(390, 0)
	box.add_child(_tip_body)
	var ok := Button.new()
	ok.text = "Got it"
	ok.focus_mode = Control.FOCUS_NONE
	ok.pressed.connect(func() -> void: _tip_panel.visible = false)
	box.add_child(ok)

	_invite_panel = PanelContainer.new()
	_invite_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_invite_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_invite_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_invite_panel.offset_bottom = -70
	_invite_panel.visible = false
	root.add_child(_invite_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_padded_vbox(_invite_panel).add_child(row)
	_invite_label = Label.new()
	row.add_child(_invite_label)
	var watch := Button.new()
	watch.text = "Watch"
	watch.focus_mode = Control.FOCUS_NONE
	watch.pressed.connect(func() -> void: watch_pressed.emit())
	row.add_child(watch)
	var skip := Button.new()
	skip.text = "Not now"
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(hide_hunt_invite)
	row.add_child(skip)

	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.offset_bottom = -130
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.1))
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.visible = false
	root.add_child(_toast)


func _toggle_checklist() -> void:
	_checklist.visible = not _checklist.visible
	_checklist_button.text = "Hide checklist" if _checklist.visible else "Show checklist"


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

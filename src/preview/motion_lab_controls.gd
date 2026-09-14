extends RefCounted

const SESSION := preload("res://src/preview/motion_lab_session.gd")
var lab: Node3D
var system_select: OptionButton
var view_select: OptionButton
var follow_button: CheckButton
var support: Label
var input_hint: Label

func build(value: Node3D) -> void:
	lab = value
	var layer := CanvasLayer.new()
	layer.name = "LabUI"
	lab.add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 12
	panel.offset_right = -12
	panel.offset_top = 12
	var theme := Theme.new()
	theme.default_font_size = 18
	panel.theme = theme
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.10, 0.135, 0.94)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	panel.add_child(stack)
	lab.main_title = _label("WINDWARD / MANUAL CONTROLS", stack)
	lab.main_title.add_theme_font_size_override("font_size", 24)
	var row := _row(stack)
	system_select = OptionButton.new()
	system_select.focus_mode = Control.FOCUS_NONE
	for title in SESSION.SYSTEM_NAMES: system_select.add_item(title)
	system_select.item_selected.connect(lab.select_system)
	row.add_child(system_select)
	_label("Wheel down: haul / up: ease | A/D: rudder", row)
	_button("Reset trim [R]", lab.reset_action, row)
	_button("Reset setup", lab.reset_scenario, row)
	row = _row(stack)
	_label("Rudder A/D", row)
	_button("Neutral [S]", func(): lab._stop_and_set(0.0), row)
	lab.slider = _slider(-1, 1, 0.002, lab._stop_and_set, row)
	_label("Hike Z/X", row)
	lab.hike_slider = _slider(0, 1, 0.01, lab._request_hike, row)
	_button("Switch side [8]", func(): lab.set_side(-lab.actor.seat_side), row)
	row = _row(stack)
	view_select = OptionButton.new()
	view_select.focus_mode = Control.FOCUS_NONE
	for title in ["3/4 [F1]", "Front [F2]", "Top [F3]", "First person [F4]", "Sheet hand [F5]", "Tiller hand [F6]", "Upper arm [F7]"]: view_select.add_item(title)
	view_select.item_selected.connect(lab.set_view)
	row.add_child(view_select)
	follow_button = CheckButton.new()
	follow_button.focus_mode = Control.FOCUS_NONE
	follow_button.text = "Look at hands"
	follow_button.toggled.connect(lab.set_follow_work)
	row.add_child(follow_button)
	_button("Reset view", lab.reset_view, row)
	_button("Copy setup", func(): DisplayServer.clipboard_set(JSON.stringify(lab.inspection_snapshot(), "\t")), row)
	support = _label("", stack)
	lab.status = _label("", stack)
	lab.sheet_status = _label("", stack)
	for label in [support, lab.status, lab.sheet_status]: label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.mode_hint = _label("1-4: rope | A/D + S: rudder | Z/X: hike | F1-F7: views | Click: mouse look | Esc: cursor | H: panel", stack)
	lab.mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var hint_layer := CanvasLayer.new()
	hint_layer.name = "LabInputHint"
	lab.add_child(hint_layer)
	input_hint = Label.new()
	input_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	input_hint.offset_left = 24
	input_hint.offset_right = -24
	input_hint.offset_top = -70
	input_hint.offset_bottom = -10
	input_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	input_hint.add_theme_font_size_override("font_size", 20)
	input_hint.add_theme_color_override("font_color", Color("f0cf87"))
	input_hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	input_hint.add_theme_constant_override("shadow_offset_x", 2)
	input_hint.add_theme_constant_override("shadow_offset_y", 2)
	hint_layer.add_child(input_hint)

func refresh() -> void:
	var session = lab.session
	system_select.select(session.selected_system)
	view_select.select(lab.selected_view)
	follow_button.set_pressed_no_signal(lab.follow_work_area)
	lab.hike_slider.set_value_no_signal(session.requested_hike)
	lab.slider.set_value_no_signal(lab.actor.amount)
	var reason: String = session.support_reason()
	support.text = "READY" if reason.is_empty() else reason
	if not session.notice.is_empty(): support.text += " | " + session.notice
	support.add_theme_color_override("font_color", Color("a7dbbb") if reason.is_empty() else Color("efc181"))
	var input = session.wheel_pull
	var repeat_status := "distance driven" if input.motion!=null else "not ready"
	lab.sheet_status.text = "%s | Trim %.1f / target %.1f mm | Range %.0f-%.0f mm | Idle %.2fs: return hands, keep trim | Repeated handover: %s" % [input.state, input.metres * 1000, input.target_metres * 1000, input.minimum_metres*1000, input.maximum_metres*1000, input.IDLE_SECONDS,repeat_status]
	if input.length_budget!=null:
		lab.sheet_status.text += " | Total %.2fm / Rig %.2fm / Cockpit %.2fm / Ends %.2fm" % [input.length_budget.total_metres,input.length_budget.rig_metres,input.length_budget.cockpit_metres,input.length_budget.fixed_end_metres+input.length_budget.free_end_metres]
	input_hint.text = "%s | Wheel down/up: haul/ease | A/D: rudder | Z/X: hike | F4: first person | Click: look / Esc: cursor | H: panel" % SESSION.SYSTEM_NAMES[session.selected_system]
	input_hint.text += "\n%.1f mm | range %.0f-%.0f mm | %s" % [input.metres * 1000, input.minimum_metres*1000, input.maximum_metres*1000, input.state if reason.is_empty() else reason]

func _row(parent: Node) -> HBoxContainer:
	var result := HBoxContainer.new()
	result.add_theme_constant_override("separation", 8)
	parent.add_child(result)
	return result

func _label(text: String, parent: Node) -> Label:
	var result := Label.new()
	result.text = text
	parent.add_child(result)
	return result

func _button(text: String, callback: Callable, parent: Node) -> Button:
	var result := Button.new()
	result.text = text
	result.focus_mode = Control.FOCUS_NONE
	result.pressed.connect(callback)
	parent.add_child(result)
	return result

func _slider(low: float, high: float, step: float, callback: Callable, parent: Node) -> HSlider:
	var result := HSlider.new()
	result.focus_mode = Control.FOCUS_NONE
	result.min_value = low
	result.max_value = high
	result.step = step
	result.custom_minimum_size = Vector2(140, 24)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.value_changed.connect(callback)
	parent.add_child(result)
	return result

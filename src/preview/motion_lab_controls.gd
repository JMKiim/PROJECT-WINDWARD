extends RefCounted

var lab: Node3D
var system_select: OptionButton
var view_select: OptionButton
var follow_button: CheckButton
var support: Label
var input_hint: Label
var rig_column: VBoxContainer
var drawer: PanelContainer
var advanced_column: VBoxContainer
var drawer_scroll: ScrollContainer
var summary: Label
var toolbar: PanelContainer
var inspection_status: Label
var inspect_button: Button
var cancel_button: Button
var manual_button: Button
var zoom_buttons: Array[Button] = []

func build(value: Node3D) -> void:
	lab=value
	var layer := CanvasLayer.new()
	layer.name="LabUI"
	lab.add_child(layer)
	var panel := PanelContainer.new()
	toolbar=panel
	panel.name="Toolbar"
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left=12
	panel.offset_right=-12
	panel.offset_top=12
	_style(panel)
	layer.add_child(panel)
	var stack := VBoxContainer.new()
	panel.add_child(stack)
	var row := _row(stack)
	lab.main_title=_label("WINDWARD",row)
	lab.main_title.add_theme_font_size_override("font_size",20)
	system_select=OptionButton.new()
	system_select.focus_mode=Control.FOCUS_NONE
	for title in ["1 메인시트","2 붐뱅 (준비 중)","3 커닝험 (준비 중)","4 아웃홀 (준비 중)"]: system_select.add_item(title)
	system_select.item_selected.connect(lab.select_system)
	row.add_child(system_select)
	view_select=OptionButton.new()
	view_select.focus_mode=Control.FOCUS_NONE
	for title in ["사선 [F1]","정면 [F2]","위 [F3]","1인칭 [F4]","시트 손 [F5]","러더 손 [F6]","팔 [F7]","전체 리그","트래블러 블록","선미 전체"]: view_select.add_item(title)
	view_select.item_selected.connect(lab.set_view)
	row.add_child(view_select)
	zoom_buttons.append(_button("−",func(): lab.zoom_inspection(-2),row))
	zoom_buttons.append(_button("＋",func(): lab.zoom_inspection(2),row))
	for button in zoom_buttons: button.tooltip_text="외부 시점 확대/축소 · Ctrl+휠로도 조절"
	_button("시야 복원",lab.reset_view,row)
	_button("설정",func(): show_drawer("rig"),row)
	summary=_label("",row)
	summary.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	summary.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	row=_row(stack)
	inspect_button=_button("트래블러 검수 · 트림 변경",func(): lab.rig_inspection.inspect_traveller(),row)
	inspect_button.tooltip_text="한 번 클릭: 중립 조타 → 25°/5 N 기준 연결부 계산 → 블록 확대. 전체 14 m 유지, 트림 배분 변경. 좌현·앉음 전용."
	manual_button=_button("수동 조작",func(): lab.rig_inspection.clear_load(),row)
	cancel_button=_button("취소",func(): lab.rig_inspection.cancel_request(),row)
	inspection_status=_label("",row)
	inspection_status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	inspection_status.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	inspection_status.mouse_filter=Control.MOUSE_FILTER_PASS
	input_hint=_label("휠↓ 당김 / ↑ 풀기 · Ctrl+휠 확대 · 우클릭 드래그 회전 · 휠버튼 드래그 이동 · A/D 러더 · Z/X 하이크 · Esc 커서",stack)
	input_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE
	input_hint.add_theme_font_size_override("font_size",15)
	drawer=PanelContainer.new()
	drawer.name="InspectionDrawer"
	drawer.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	drawer.position=Vector2(12,104)
	drawer.size=Vector2(490,540)
	_style(drawer)
	layer.add_child(drawer)
	drawer_scroll=ScrollContainer.new()
	drawer_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	drawer.add_child(drawer_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	drawer_scroll.add_child(content)
	_button("닫기",func(): drawer.hide(),content)
	rig_column=VBoxContainer.new()
	content.add_child(rig_column)
	advanced_column=VBoxContainer.new()
	content.add_child(advanced_column)
	_label("자세 / 조작 상세",advanced_column)
	row=_row(advanced_column)
	_label("러더 A/D",row)
	lab.slider=_slider(-1,1,.002,lab._stop_and_set,row)
	_button("중립 [S]",func(): lab._stop_and_set(0.0),row)
	row=_row(advanced_column)
	_label("하이크 Z/X",row)
	lab.hike_slider=_slider(0,1,.01,lab._request_hike,row)
	_button("좌우 [8]",func(): lab.set_side(-lab.actor.seat_side),row)
	follow_button=CheckButton.new()
	follow_button.text="1인칭에서 손 쪽 보기"
	follow_button.focus_mode=Control.FOCUS_NONE
	follow_button.toggled.connect(lab.set_follow_work)
	advanced_column.add_child(follow_button)
	row=_row(advanced_column)
	_button("시야 초기화",lab.reset_view,row)
	_button("트림 리셋 [R]",lab.reset_action,row)
	_button("전체 초기화",lab.reset_scenario,row)
	_button("설정 복사",func(): DisplayServer.clipboard_set(JSON.stringify(lab.inspection_snapshot(),"\t")),row)
	support=_label("",advanced_column)
	lab.status=_label("",advanced_column)
	lab.sheet_status=_label("",advanced_column)
	lab.mode_hint=_label("번호: 줄 선택 · Shift+휠: 큰 폭 조절\n좌우 변경은 태킹이 아니라 자세 검수예요.\n시트는 현재 좌현·앉은 자세를 지원해요.",advanced_column)
	for label in [support,lab.status,lab.sheet_status,lab.mode_hint]: label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	drawer.hide()
	lab.get_viewport().size_changed.connect(_resize)
	_resize()

func _resize() -> void:
	var size: Vector2=lab.get_viewport().get_visible_rect().size
	drawer.position.y=maxf(144,toolbar.get_global_rect().end.y+12)
	drawer.size=Vector2(minf(490,size.x-24),maxf(200,minf(590,size.y-drawer.position.y-12)))

func pointer_over_ui(point: Vector2) -> bool:
	# Input callbacks run before GUI delivery. Use visible panel bounds instead
	# of relying on the previous frame's hovered control during a fast click.
	for panel in [toolbar,drawer]:
		if panel.is_visible_in_tree() and panel.get_global_rect().has_point(point): return true
	return false

func show_drawer(kind: String) -> void:
	var same := (kind=="rig" and rig_column.visible) or (kind=="advanced" and advanced_column.visible)
	if drawer.visible and same:
		drawer.hide()
		return
	rig_column.visible=kind=="rig"
	advanced_column.visible=true
	drawer_scroll.scroll_vertical=0
	drawer.show()

func refresh() -> void:
	var session=lab.session
	for button in zoom_buttons: button.disabled=lab.selected_view==3
	if lab.rig_inspection!=null:
		var inspection: Node3D=lab.rig_inspection
		var busy: bool=inspection.contact_busy() or not inspection.pending_action.is_empty()
		inspect_button.disabled=busy
		inspect_button.tooltip_text="한 번 클릭: 조타 −6° → 붐 45°/5 N 실제 접촉 계산 → 블록 확대. 약 35초, 전체 14 m 유지. 트림·조타 변경." if inspection.inspection_preset==1 else "한 번 클릭: 중립 조타 → 25°/5 N 기준 연결부 계산 → 블록 확대. 전체 14 m 유지, 트림 배분 변경. 좌현·앉음 전용."
		var preset := rig_column.get_node_or_null("TravellerCondition") as OptionButton
		if preset!=null: preset.disabled=busy
		cancel_button.visible=busy
		manual_button.visible=not busy and (not lab.complete_sheet.rig.coupled.is_empty() or inspection.deck_contact_preview or lab.complete_sheet.rig.traveller_override.is_finite())
		inspection_status.text=inspection.message.replace("\n"," · ")
		inspection_status.tooltip_text=inspection.message
	_resize()
	system_select.select(session.selected_system)
	view_select.select(lab.selected_view)
	follow_button.set_pressed_no_signal(lab.follow_work_area)
	lab.hike_slider.set_value_no_signal(session.requested_hike)
	lab.slider.set_value_no_signal(lab.actor.amount)
	var reason: String=session.support_reason()
	support.text="조작 가능" if reason.is_empty() else reason
	if not session.notice.is_empty(): support.text+="\n"+session.notice
	var input=session.wheel_pull
	var state := "대기" if input.state=="REST" else ("풀기" if "EASE" in input.state else "손 동작")
	summary.text="%s · 회수 %.2f m" % [state,input.metres]
	if not reason.is_empty(): summary.text="선택 동작 미지원 · 상세 확인"
	lab.sheet_status.text="트림 %.3f / 목표 %.3f m\n범위 %.3f~%.3f m · %s" % [input.metres,input.target_metres,input.minimum_metres,input.maximum_metres,input.state]
	if input.length_budget!=null:
		lab.sheet_status.text+="\n총 %.2f / 리그 %.2f / 콕핏 %.2f m" % [input.length_budget.total_metres,input.length_budget.rig_metres,input.length_budget.cockpit_metres]

func _style(panel: PanelContainer) -> void:
	var theme := Theme.new()
	theme.default_font_size=17
	panel.theme=theme
	var style := StyleBoxFlat.new()
	style.bg_color=Color(.04,.075,.10,.94)
	for edge in ["left","right","top","bottom"]: style.set("content_margin_"+edge,10)
	panel.add_theme_stylebox_override("panel",style)

func _row(parent: Node) -> HBoxContainer:
	var result := HBoxContainer.new()
	result.add_theme_constant_override("separation",8)
	parent.add_child(result)
	return result

func _label(text: String,parent: Node) -> Label:
	var result := Label.new()
	result.text=text
	parent.add_child(result)
	return result

func _button(text: String,callback: Callable,parent: Node) -> Button:
	var result := Button.new()
	result.text=text
	result.focus_mode=Control.FOCUS_NONE
	result.pressed.connect(callback)
	parent.add_child(result)
	return result

func _slider(low: float,high: float,step: float,callback: Callable,parent: Node) -> HSlider:
	var result := HSlider.new()
	result.focus_mode=Control.FOCUS_NONE
	result.min_value=low
	result.max_value=high
	result.step=step
	result.custom_minimum_size=Vector2(140,24)
	result.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	result.value_changed.connect(callback)
	parent.add_child(result)
	return result

extends CanvasLayer
const OPTIONS := preload("res://src/ui/graphics_options.gd")
const ROWS := [
	["화면","render_scale","3D 렌더 배율",["75%","85%","100%"],[75,85,100]],
	["화면","fps_limit","FPS 제한",["제한 없음","30","60","120"],[0,30,60,120]],
	["화면","vsync","수직동기화",["끄기","켜기"],[false,true]],
	["품질","msaa","안티앨리어싱(MSAA)",["끄기","2배","4배","8배"],[0,1,2,3]],
	["품질","shadows","그림자",["끄기","켜기"],[false,true]],
	["품질","shadow_distance","그림자 거리",["30m","60m","100m","160m"],[30,60,100,160]],
	["품질","water_detail","수면 메시 디테일",["낮음","중간","높음","매우 높음"],[128,192,256,384]],
	["품질","texture_filter","모델 텍스처 필터",["원본 설정","이방성 8배"],[0,1]],
	["품질","ambient_percent","환경광 밝기",["60%","100%","140%"],[60,100,140]]]
var scene: Node3D
var model := OPTIONS.new()
var applied := {}
var panel: PanelContainer
var status: Label
var preset: OptionButton
var controls := {}
var was_paused := false
var previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var opened := false
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS; layer=20
	model.storage_path=String(get_tree().get_meta("graphics_config_path","user://graphics.cfg"))
	model.load_config(); model.bind(scene); model.apply(get_viewport()); applied=model.values.duplicate()
	var entry := Button.new()
	entry.text="그래픽 설정 · F10"
	entry.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	entry.offset_left=20; entry.offset_top=-56; entry.offset_right=240; entry.offset_bottom=-16
	entry.pressed.connect(open_panel); add_child(entry)
	panel=PanelContainer.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left=-350; panel.offset_top=-325; panel.offset_right=350; panel.offset_bottom=325
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
	panel.add_child(margin)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation",12); margin.add_child(box)
	var title := Label.new(); title.text="그래픽 설정"; title.add_theme_font_size_override("font_size",26); box.add_child(title)
	var hint := Label.new(); hint.text="설정 중에는 항해가 멈춰요. 품질 옵션은 물리·조작 정확도를 바꾸지 않아요."
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; hint.add_theme_font_size_override("font_size",14); box.add_child(hint)
	preset=OptionButton.new()
	for label in ["낮음","중간","높음(기본)","매우 높음","사용자 설정"]: preset.add_item(label)
	preset.item_selected.connect(_preset_selected); box.add_child(preset)
	var tabs := TabContainer.new(); tabs.custom_minimum_size=Vector2(640,270); box.add_child(tabs)
	var pages := {}
	for name in ["화면","품질","향후 효과"]:
		var page := VBoxContainer.new(); page.name=name; page.add_theme_constant_override("separation",10); tabs.add_child(page); pages[name]=page
	for row in ROWS:
		var line := HBoxContainer.new(); pages[row[0]].add_child(line)
		var label := Label.new(); label.text=row[2]; label.custom_minimum_size.x=300; line.add_child(label)
		var choice := OptionButton.new(); choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		for label_text in row[3]: choice.add_item(label_text)
		choice.item_selected.connect(_value_selected.bind(row[1],row[4])); line.add_child(choice); controls[row[1]]=choice
	var unsupported := Label.new()
	unsupported.text="아래 항목은 아직 설정할 수 없어요.\n\n텍스처 해상도 단계 · 그림자 해상도/부드러움\n간접광/주변 차폐 · 수면 반사/포말 품질\n렌즈플레어 · 블룸 · 광선 · 피사계 심도 · 모션블러\n\n화면 모드/해상도 변경과 안전 복귀도 후속 연결 예정이에요.\n현재 효과 구현과 렌더러 지원을 확인한 뒤 제공할게요."
	pages["향후 효과"].add_child(unsupported)
	var device := Label.new(); device.text="렌더러: "+RenderingServer.get_current_rendering_method()+" · "+RenderingServer.get_video_adapter_name(); device.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; box.add_child(device)
	status=Label.new(); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; box.add_child(status)
	var actions := HBoxContainer.new(); box.add_child(actions)
	for item in [["기본값",_defaults],["적용·저장",apply_pending],["취소·닫기",close_panel]]:
		var button := Button.new(); button.text=item[0]; button.pressed.connect(item[1]); actions.add_child(button)
	_sync(); panel.hide()
func _sync() -> void:
	preset.select(["low","medium","high","very_high","custom"].find(model.preset_name()))
	for row in ROWS: controls[row[1]].select(row[4].find(model.values[row[1]]))
func _value_selected(index: int,key: String,choices: Array) -> void:
	model.values[key]=choices[index]; _sync(); status.text="미적용 변경사항이 있어요."
func _preset_selected(index: int) -> void:
	if index<4: model.select_preset(["low","medium","high","very_high"][index]); _sync(); status.text="프리셋은 적용·저장을 누르면 반영돼요. FPS·동기화·밝기는 유지해요."
func _defaults() -> void:
	model.values=OPTIONS.DEFAULTS.duplicate(); _sync(); status.text="기본값을 선택했어요. 적용·저장을 누르면 반영돼요."
func open_panel() -> void:
	if opened: return
	opened=true; was_paused=get_tree().paused; previous_mouse_mode=Input.mouse_mode
	var control: Node3D=scene.get_node("Boat").seated_controls
	control.deck.session.wheel_pull.pause()
	if not control.deck.tack.busy(): control.deck.session.request_hike(control.deck.actor.hike)
	for action in ["steer_port","steer_starboard","sheet_in","sheet_out","land_hike_out","land_hike_in"]: Input.action_release(action)
	get_tree().paused=true; Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	model.values=applied.duplicate(); _sync(); status.text=model.load_message; panel.show()
func apply_pending() -> void:
	model.apply(get_viewport())
	var error := model.save_config()
	if error!=OK:
		model.values=applied.duplicate(); model.apply(get_viewport()); _sync(); status.text="설정을 저장하지 못해 이전 설정으로 되돌렸어요."; return
	applied=model.values.duplicate(); status.text="적용하고 저장했어요. 품질 변경 중 잠깐 멈출 수 있어요."
func close_panel() -> void:
	if not opened: return
	model.values=applied.duplicate(); _sync(); panel.hide(); opened=false
	get_tree().paused=was_paused
	if get_window().has_focus(): Input.mouse_mode=previous_mouse_mode
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_F10:
			if opened: close_panel()
			else: open_panel()
			get_viewport().set_input_as_handled()
		elif opened and event.physical_keycode==KEY_ESCAPE: close_panel(); get_viewport().set_input_as_handled()

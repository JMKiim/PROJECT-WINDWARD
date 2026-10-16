extends "res://src/preview/land_drill/support/rudder_motion_lab.gd"
const DIRECT_ACTOR := preload("res://src/preview/land_drill_visual_actor.gd")
const DIRECT_SHEET := preload("res://src/preview/land_drill_visual_sheet.gd")
const DIRECT_CONTROLS := preload("res://src/preview/motion_lab_controls.gd")
const NECK_CLOSURE := preload("res://src/preview/land_drill_neck_closure.gd")
const COCKPIT_SHEET_DISPLAY := preload("res://src/preview/land_drill_sheet_display.gd")
const CACHED_HULL := preload("res://src/preview/land_drill_cached_hull.gd")
const DELIVERY := preload("res://src/preview/land_drill_runtime_config.gd")
const FIRST_PERSON_VIEW := preload("res://src/preview/land_drill_first_person_view.gd")
const RIG_DISPLAY := preload("res://src/preview/land_drill_rig_display.gd")
var first_person_view := FIRST_PERSON_VIEW.new()
var rig_display: RefCounted
var startup_ms := 0.0
var startup_ready := false
var startup_stages := {}
func _ready() -> void:
	var started := Time.get_ticks_usec()
	var resource_error := DELIVERY.resources_error()
	if not resource_error.is_empty():
		var warning_ui := CanvasLayer.new()
		warning_ui.name="LabUI"
		add_child(warning_ui)
		var warning_label := Label.new()
		warning_label.position=Vector2(40,40)
		warning_label.text="육상 연습을 준비할 수 없습니다.\n"+resource_error+"\n프로젝트의 실행 자료를 확인해 주세요."
		warning_label.add_theme_font_size_override("font_size",20)
		warning_ui.add_child(warning_label)
		set_process(false)
		push_error(resource_error)
		return
	wide_steering_enabled=true
	continuous_sheet_enabled=true
	complete_mainsheet_enabled=true
	extension_tube_metres=1.25
	_create_stage()
	startup_stages["stage_ms"]=(Time.get_ticks_usec()-started)/1000.0
	var part_started := Time.get_ticks_usec()
	actor=_new_actor()
	actor.name="AuthoredSailor"
	actor.extension_span=extension.tiller_extension_span()
	add_child(actor)
	startup_stages["actor_ms"]=(Time.get_ticks_usec()-part_started)/1000.0
	part_started=Time.get_ticks_usec()
	actor.seat_contact=preload("res://src/boat/animation/seated_deck_contact.gd").new()
	actor.seat_contact.setup(actor,get_node("Hull"))
	actor.sheet_study.block_anchor=to_local(ratchet.rope_anchor_global(&"sheave"))
	actor.sheet_study.floor_surface=get_node("Hull").cockpit_floor_y_at
	actor.sheet_study.deck_fitting=ratchet
	session.setup(actor)
	startup_stages["seat_ms"]=(Time.get_ticks_usec()-part_started)/1000.0
	part_started=Time.get_ticks_usec()
	complete_sheet=_new_sheet()
	complete_sheet.name="TrainingMainsheet"
	add_child(complete_sheet)
	if not complete_sheet.setup(self):
		push_error("Direct land drill resources do not match")
		set_process(false)
		return
	startup_stages["sheet_ms"]=(Time.get_ticks_usec()-part_started)/1000.0
	part_started=Time.get_ticks_usec()
	var old_cap: MeshInstance3D=actor.neck_cap
	var cap := _new_neck_closure()
	var body: MeshInstance3D=actor.skeleton.get_node("SuperHero_Male")
	body.get_parent().add_child(cap)
	if not cap.setup(body,actor.body_material.get_shader_parameter("head_bind_index"),actor.HEAD_MASK_THRESHOLD):
		push_error("Direct land drill neck closure failed")
		set_process(false)
		return
	cap.visible=old_cap.visible
	actor.neck_cap=cap
	old_cap.queue_free()
	startup_stages["cap_ms"]=(Time.get_ticks_usec()-part_started)/1000.0
	part_started=Time.get_ticks_usec()
	# Same scene, one initial connection. No re-instantiation or compare mode.
	review_options=_new_sheet_display()
	review_options.setup(self)
	# Build the same visible rig once, without a second scene or load button.
	review_options.show_held(self)
	rig_display=RIG_DISPLAY.new()
	if not rig_display.setup(self):
		push_error("Training rig display could not be fitted")
		set_process(false)
		return
	session.bilateral_sheet_enabled=true
	session.visual_port_hiking_enabled=true
	session.visual_starboard_hiking_enabled=true
	_prepare_hiking_input()
	startup_stages["rig_ms"]=(Time.get_ticks_usec()-part_started)/1000.0
	part_started=Time.get_ticks_usec()
	controls=DIRECT_CONTROLS.new()
	if not embedded_controls:
		_create_controls()
		set_view(0)
	else:
		set_process(false)
		set_process_input(false)
		set_process_unhandled_key_input(false)
	set_amount(0)
	startup_stages["ui_ms"]=(Time.get_ticks_usec()-part_started)/1000.0
	startup_ms=float(Time.get_ticks_usec()-started)/1000.0
	startup_ready=true

func _new_actor() -> Node3D: return DIRECT_ACTOR.new()

func _prepare_hiking_input() -> void:
	# Lab-only actions: the same physical X/Z bindings can be exercised
	# through the engine input path without polling the desktop keyboard.
	for binding in [[&"land_hike_out",KEY_X],[&"land_hike_in",KEY_Z]]:
		var action: StringName=binding[0]
		if InputMap.has_action(action): continue
		InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode=binding[1]
		InputMap.action_add_event(action,event)

func _process(delta: float) -> void:
	if actor==null: return
	var previous_side: int=actor.seat_side
	var follow_hand: bool=camera!=null and (selected_view==4 or selected_view==5)
	var previous_hand: Vector3=actor.palm_boat(actor.sheet_hand() if selected_view==4 else actor.tiller_hand()) if follow_hand else Vector3.ZERO
	var previous_hike: float=actor.hike
	super._process(delta)
	# The seat selector is an explicit inspection cut, not a maneuver.
	# Reframe only that cut; ordinary steering preserves the user's orbit.
	if actor.seat_side!=previous_side and selected_view!=3 and camera!=null:
		set_view(selected_view)
	elif follow_hand and maxf(previous_hike,float(actor.hike))>0:
		# Translate the inspector's entire frame with the selected hiking
		# hand, retaining the user's zoom, orbit and pan offsets.
		var shift: Vector3=actor.palm_boat(actor.sheet_hand() if selected_view==4 else actor.tiller_hand())-previous_hand
		camera.position+=shift
		inspection_target+=shift

func _new_sheet() -> Node3D: return DIRECT_SHEET.new()
func _new_neck_closure() -> MeshInstance3D: return NECK_CLOSURE.new()
func _new_sheet_display() -> RefCounted: return COCKPIT_SHEET_DISPLAY.new()

func _update_first_person_camera() -> void:
	first_person_view.update(self)

func _set_view_base(index: int,reset_look: bool) -> void:
	super._set_view_base(index,reset_look)
	if (index==4 or index==5) and actor.hike>0:
		# Hiking hands are forward of the torso. Enter the close view from
		# the bow side, not through the forearm; retain ordinary orbit/pan.
		var palm: Vector3=actor.palm_boat(actor.sheet_hand() if index==4 else actor.tiller_hand())
		var blend := smoothstep(0,.125,float(actor.hike))
		camera.position=palm+actor.from_port(Vector3(.32,.18,lerpf(.22,-.36,blend)))
		camera.look_at(to_global(palm),global_basis*Vector3.UP)
	if index==7 and rig_display!=null:
		camera.position=actor.from_port(Vector3(8,5,-6))
		camera.look_at(to_global(_view_target(index)),global_basis*Vector3.UP)
	if index==3 and reset_look:
		first_person_view.reset_follow(self)
		_update_first_person_camera()

func set_follow_work(value: bool) -> void:
	follow_work_area=value
	if value: first_person_view.reset_follow(self)
	if selected_view==3: _update_first_person_camera()
	if controls.lab!=null: controls.refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if key==KEY_F:
			if selected_view!=3: set_view(3)
			set_follow_work(not follow_work_area)
			return
	super._unhandled_key_input(event)

func supports_rig_diagnostics() -> bool: return false
func supports_rig_display() -> bool: return true

func _refresh_preview() -> void:
	super._refresh_preview()
	if rig_display!=null and not rig_display.samples.is_empty():
		if not rig_display.update():
			session.notice="리그 표시 연결을 확인해 주세요."

func _view_target(index: int) -> Vector3:
	if index==7 and rig_display!=null: return Vector3(0,3,0)
	if index==8 and rig_display!=null and rig_display.rig!=null:
		return to_local((rig_display.rig.pin_lower.global_position+rig_display.rig.pin_upper.global_position)*.5)
	return super._view_target(index)

func _create_deck() -> void:
	var hull := CACHED_HULL.new()
	hull.inspection_mast_fit=true
	hull.name="Hull"
	add_child(hull)
	ratchet=_hardware(HARDWARE.PartKind.DECK_RATCHET,HULL.RATCHET_ORIGIN,self,{"name":"RatchetBlock"})
	var details := COCKPIT_DETAILS.new()
	details.name="CockpitDetails"
	add_child(details)
	details.setup(hull,ratchet)
	_hardware(HARDWARE.PartKind.DAGGERBOARD_CASE,Vector3(0,.058,-.155),self,{"name":"DaggerboardCase"})
	for index in HARDWARE.DECK_LEAD_PREFIX_POINTS-1:
		var line := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius=GRIP.SHEET_RADIUS
		cylinder.bottom_radius=GRIP.SHEET_RADIUS
		cylinder.radial_segments=10
		line.mesh=cylinder
		var material := StandardMaterial3D.new()
		material.albedo_color=Color(.88,.82,.63)
		line.material_override=material
		add_child(line)
		block_lead_lines.append(line)
	_hardware(HARDWARE.PartKind.SELF_BAILER,Vector3.ZERO,self,{"name":"SelfBailer"})
	_hardware(HARDWARE.PartKind.COCKPIT_DRAIN_BUNG,Vector3.ZERO,self,{"name":"CockpitDrainBung"})
	rudder=Node3D.new()
	rudder.name="RudderPivot"
	rudder.position=Vector3(0,0,2.171)
	add_child(rudder)
	var tiller := _hardware(HARDWARE.PartKind.TILLER,Vector3(0,.331476,-.489529),rudder)
	tiller.rotation_degrees.x=2.512
	_hardware(HARDWARE.PartKind.RUDDER_HEAD,Vector3(0,.18,-.031),rudder)
	var stern := STERN_DETAILS.new()
	stern.name="SternDetails"
	add_child(stern)
	stern.setup(rudder)
	extension=_hardware(HARDWARE.PartKind.TILLER_EXTENSION,Vector3.ZERO,self,{"extension_tube_metres":extension_tube_metres})
	sheet=MeshInstance3D.new()
	var rope := CylinderMesh.new()
	rope.top_radius=GRIP.SHEET_RADIUS
	rope.bottom_radius=GRIP.SHEET_RADIUS
	rope.radial_segments=12
	sheet.mesh=rope
	var rope_material := StandardMaterial3D.new()
	rope_material.albedo_color=Color("d8aa55")
	rope_material.roughness=.95
	sheet.material_override=rope_material
	add_child(sheet)
	for segment in GRIP.sheet_channel().size()-1+TAIL_SEGMENTS:
		var line := MeshInstance3D.new()
		line.mesh=rope.duplicate()
		line.material_override=rope_material
		add_child(line)
		sheet_channel_lines.append(line)
	for segment in STROKE_PLAYER.ROPE_SEGMENTS:
		var line := MeshInstance3D.new()
		line.mesh=rope.duplicate()
		line.material_override=rope_material
		line.visible=false
		add_child(line)
		study_lines.append(line)

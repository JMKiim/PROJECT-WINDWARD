extends "res://src/preview/land_drill/support/rudder_motion_lab.gd"
const DIRECT_ACTOR := preload("res://src/preview/land_drill_runtime_actor.gd")
const DIRECT_SHEET := preload("res://src/preview/land_drill_runtime_sheet.gd")
const DIRECT_CONTROLS := preload("res://src/preview/motion_lab_controls.gd")
const NECK_CLOSURE := preload("res://src/preview/review_neck_closure.gd")
const CACHED_HULL := preload("res://src/preview/land_drill_cached_hull.gd")
const DELIVERY := preload("res://src/preview/land_drill_runtime_config.gd")
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
	actor=DIRECT_ACTOR.new()
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
	complete_sheet=DIRECT_SHEET.new()
	complete_sheet.name="TrainingMainsheet"
	add_child(complete_sheet)
	if not complete_sheet.setup(self):
		push_error("Direct land drill resources do not match")
		set_process(false)
		return
	startup_stages["sheet_ms"]=(Time.get_ticks_usec()-part_started)/1000.0
	part_started=Time.get_ticks_usec()
	var old_cap: MeshInstance3D=actor.neck_cap
	var cap := NECK_CLOSURE.new()
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
	review_options.active=true
	review_options.held_only=true
	review_options.tube=REVIEW_OPTIONS.VIEW.new()
	review_options.tube.name="HeldSheet"
	add_child(review_options.tube)
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

func supports_rig_diagnostics() -> bool: return false

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

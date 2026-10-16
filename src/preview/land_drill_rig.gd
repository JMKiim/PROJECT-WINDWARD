extends "res://src/boat/ilca_training_rig.gd"

## Prescribed straight-mast geometry with a captive traveller pin. This is
## display kinematics, not a force/friction/bearing-clearance simulation.
const SAIL_MOUNT := preload("res://src/preview/land_drill_rig_sail.gd")
const PIN_BLOCK := preload("res://src/boat/pinned_sheave_block.gd")
const PIN_ROUTE := preload("res://src/preview/land_drill_pin_geometry.gd")
const PIN_JOINT := preload("res://src/boat/revolute_pin_joint.gd")
const REAR_LENGTH := 1.01872327696678
const PIN_SIZE := {"bore":.002,"outer":.006,"eye_depth":.003,"ear_depth":.002,"side_gap":.0005,"pin_radius":.0016,"head_radius":.0035,"head_depth":.0015,"head_gap":.0003,"neck_length":.002}
var sail_mount: Node3D
var pin_lower: MeshInstance3D
var pin_upper: MeshInstance3D
var pin_result := {}
var geometry_valid := false
var geometry_ms := 0.0
var modern_ready := false
var slide_x := .455
var pin_geometry := PIN_ROUTE.new()
var local_fixed_end := PackedVector3Array()
var canonical_fixed_end := PackedVector3Array()
var fixed_end_side := 1

func setup(floor_mesh: MeshInstance3D,deck_block: MeshInstance3D) -> void:
	super.setup(floor_mesh,deck_block)
	sail_mount=SAIL_MOUNT.new()
	add_child(sail_mount)
	if not sail_mount.setup(self): return
	minimum_pitch=sail_mount.closed_pitch
	minimum_yaw=deg_to_rad(12)
	for small in [true,false]:
		var part := PIN_BLOCK.new()
		part.name="TravellerLower" if small else "TravellerUpper"
		part.part_kind=HARDWARE.PartKind.CONTROL_BLOCK if small else HARDWARE.PartKind.BOOM_BLOCK
		part.sheave_radius=.0125 if small else .020
		part.fork_head=small
		part.transverse_pin=small
		part.neck_extension=.066-.02642149 if small else 0
		part.fitting_size=PIN_SIZE.duplicate()
		add_child(part)
		if small: pin_lower=part
		else: pin_upper=part
	modern_ready=true
	var previous_view := traveller_view
	traveller_view=VIEW.new()
	traveller_view.radius=.003
	traveller_view.color=Color("253b49")
	add_child(traveller_view)
	previous_view.queue_free()
	var standing_back := Vector3(0,sin(fixed_lean),cos(fixed_lean))*becket_winding
	var knot_y := standing_back.cross(Vector3.RIGHT).normalized()
	var knot_frame := Basis(knot_y.cross(standing_back),knot_y,standing_back)
	knot_frame=Basis(knot_y,fixed_splay)*knot_frame*Basis(Vector3.BACK,fixed_roll)
	var knot_origin: Vector3=aft.rope_anchor_local(&"becket")+Vector3.UP*.0065
	for point in fixed_shape: local_fixed_end.append(knot_origin+knot_frame*point)
	canonical_fixed_end=local_fixed_end.duplicate()
	set_angles(minimum_yaw,minimum_pitch,false)

func set_opening(value: float,display := true) -> void:
	set_angles(lerpf(minimum_yaw,deg_to_rad(175),clampf(value,0,1))*side,minimum_pitch,display)

func set_angles(yaw: float,pitch: float,display := true) -> void:
	if not modern_ready:
		super.set_angles(yaw,pitch,false)
		return
	if not is_finite(yaw) or not is_finite(pitch): return
	var started := Time.get_ticks_usec()
	geometry_valid=false
	side=-1 if yaw<0 else 1
	# Sheave normals are axial vectors: the proper mirrored body frame
	# reverses local X. Tie the stopper on the corresponding becket face,
	# instead of carrying the port knot through the spar at wide trim.
	if fixed_end_side!=side:
		local_fixed_end=canonical_fixed_end.duplicate()
		if side<0:
			for index in local_fixed_end.size(): local_fixed_end[index].x=-local_fixed_end[index].x
		fixed_end_side=side
	opening=clampf(inverse_lerp(minimum_yaw,deg_to_rad(175),absf(yaw)),0,1)
	gooseneck.rotation.y=yaw
	boom_pivot.position=gooseneck.position+Basis(Vector3.UP,yaw)*gooseneck.rope_anchor_local()
	boom_pivot.basis=Basis(Vector3.UP,yaw)*Basis(Vector3.RIGHT,pitch)
	var datum := Vector3(LOADED_TRAVELLER_X*side,traveller_rest.y,traveller_rest.z)
	var patches := traveller_fairlead_patches(datum)
	if patches.is_empty(): return
	var boundary := {"port":patches.port[-1],"starboard":patches.starboard[-1],"tiller":traveller_tiller_frame(),"tiller_radius":.0161,"tiller_half_span":.490,"sheave_radius":.0125-minf(.0048,.009*.43*.873)+.0033}
	var mount := to_local(boom_pivot.to_global(Vector3(0,-.0255-BOOM_EYE_DROP,BOOM_LENGTH-AFT_BLOCK_FROM_END)))
	var d := to_local(guide.to_global(Vector3(0,.027,0)))
	var f := to_local(deck.rope_anchor_global())
	var forward_mount := to_local(boom_pivot.to_global(Vector3(0,-.0255-BOOM_EYE_DROP,BOOM_LENGTH-FORWARD_BLOCK_FROM_END)))
	var e := _anchor(forward_block)
	for iteration in 8:
		var up := _suspension_up(d,f,e,boom_pivot.basis.y,.020,.035)
		e=forward_mount-up*.035
		_align_block(forward_block,e,d,f,up)
	# A prescribed slide towards the loaded corner, not a tension equilibrium.
	slide_x=minf(.455,1.3*sin(absf(yaw)))
	pin_result=pin_geometry.solve(boundary,REAR_LENGTH,side*slide_x,mount,d,pin_lower.eye_frame_local(),pin_upper.eye_frame_local(),deg_to_rad(-70),deg_to_rad(70))
	if not pin_result.get("valid",false):
		geometry_ms=(Time.get_ticks_usec()-started)/1000.0
		return
	pin_lower.transform=pin_result.lower
	# Every derived sheave centre stays in the same purchase plane. A few
	# deterministic neck updates only orient bodies; they never move hands.
	var c := _anchor(aft)
	var upper_pose: Transform3D=pin_result.upper
	for iteration in 8:
		var b := upper_pose.origin
		var up := _suspension_up(b,d,c,boom_pivot.basis.y,.020,.035)
		c=mount-up*.035
		_align_block(aft,c,b,d,up)
		var a := to_local(aft.to_global(aft.rope_anchor_local(&"becket")+Vector3.UP*.0065))
		var toward: Vector3=(a+c)*.5-pin_result.pin.origin
		toward=(toward-pin_result.pin.basis.x*pin_result.pin.basis.x.dot(toward)).normalized()
		var zero_up: Vector3=pin_upper.eye_frame_local().basis.inverse().y
		var desired: Vector3=pin_result.pin.basis.transposed()*(-toward)
		var angle := atan2(zero_up.cross(desired).x,zero_up.dot(desired))
		var joint := PIN_JOINT.compose(pin_result.pin,pin_upper.eye_frame_local(),angle,deg_to_rad(-70),deg_to_rad(70))
		if not joint.valid:
			pin_result=joint
			return
		upper_pose=joint.body
	pin_upper.transform=upper_pose
	pin_result["joint"]=PIN_JOINT.measure(pin_result.pin,upper_pose,pin_upper.eye_frame_local(),deg_to_rad(-70),deg_to_rad(70))
	fixed_end=(global_transform.affine_inverse()*aft.global_transform)*local_fixed_end
	_rebuild_purchase(d)
	_rebuild_traveller(patches)
	sail_mount.synchronize(yaw)
	geometry_valid=pin_result.joint.valid and route.size()>4
	geometry_ms=(Time.get_ticks_usec()-started)/1000.0
	if display and geometry_valid: show_geometry()

func _rebuild_purchase(d: Vector3) -> void:
	var a := to_local(aft.to_global(aft.rope_anchor_local(&"becket")+Vector3.UP*.0065))
	var pin := _anchor(aft,&"becket")
	var b := _anchor(pin_upper)
	var c := _anchor(aft)
	var e := _anchor(forward_block)
	var f := to_local(deck.rope_anchor_global())
	var remote := cockpit_lead
	if remote.is_empty(): remote=PackedVector3Array([f+Vector3(-.08,.06,0),f+Vector3(-.16,.12,0)])
	var next_b := b
	var next_c := c
	var next_f := f
	var axis := global_basis.inverse()*aft.global_basis.x
	for iteration in 8:
		route=PackedVector3Array([a])
		wraps.clear()
		wraps["becket"]=_append_wrap(route,pin,.0062,a,next_b,Vector4.ZERO,becket_winding,axis)
		wraps["traveller"]=_append_wrap(route,b,_groove_radius(.020),route[-1],next_c,Vector4.ZERO,traveller_winding,axis)
		wraps["aft"]=_append_wrap(route,c,_groove_radius(.020),route[-1],d,Vector4.ZERO,aft_winding,axis)
		route.append(d)
		wraps["forward"]=_append_wrap(route,e,_groove_radius(.020),route[-1],next_f)
		wraps["deck"]=_append_wrap(route,f,_groove_radius(.0285),route[-1],remote[0])
		next_b=route[wraps.traveller.begin]
		next_c=route[wraps.aft.begin]
		next_f=route[wraps.deck.begin]
	_align_deck(wraps.deck.axle,remote[0]-f)
	_align_axis(forward_block,e,wraps.forward.axle,global_basis.inverse()*forward_block.global_basis.y)
	var start := route[-1]
	var incoming := (remote[0]-start).normalized()
	var outgoing := (remote[1]-remote[0]).normalized()
	var handle := start.distance_to(remote[0])/3.0
	for index in range(1,9):
		var t := index/8.0
		var u := 1-t
		route.append(start*u*u*u+(start+incoming*handle)*3*u*u*t+(remote[0]-outgoing*handle)*3*u*t*t+remote[0]*t*t*t)

func _rebuild_traveller(patches: Dictionary) -> void:
	var before := traveller_handle.duplicate()
	before.reverse()
	before.append_array(PackedVector3Array([traveller_cleat.position+Vector3(.040,.013,-.080),traveller_cleat.position+Vector3(0,.018,-.070),traveller_cleat.position+Vector3(0,.018,-.025),traveller_cleat.position+Vector3(0,.020,.020),traveller_cleat.position+Vector3(0,.018,.060)]))
	before.append_array(traveller_nipping)
	before.append_array(_traveller_support(traveller_nipping[-1],patches.starboard[0],true))
	before=CURVE.round_corners(before,.012)
	before.append_array(patches.starboard)
	traveller_path=before
	traveller_path.append_array(pin_result.support.path.slice(1))
	var after: PackedVector3Array=patches.port.duplicate()
	after.reverse()
	traveller_path.append_array(after.slice(1))
	traveller_path.append_array(traveller_returning)

func show_geometry() -> void:
	traveller.hide()
	traveller_lower.hide()
	traveller_link.hide()
	rope_view.show_path(route)
	fixed_view.transform=global_transform.affine_inverse()*aft.global_transform
	fixed_view.show_path(local_fixed_end)
	traveller_view.show_path(traveller_path)

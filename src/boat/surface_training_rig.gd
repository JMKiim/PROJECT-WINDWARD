extends "res://src/boat/ilca_training_rig.gd"

## A transactional static inspection layer. The inherited manual rig remains
## the measured control envelope; no new equilibrium runs in set_angles.
const PINNED := preload("res://src/boat/pinned_sheave_block.gd")
const FIELD := preload("res://src/boat/mesh_rope_obstacle.gd")
const REAR_REST_METRES := 1.01872327696678
var coupled := {}
var coupled_parts := {}
var traveller_total_metres := 0.0

func setup(floor_mesh: MeshInstance3D,deck_block: MeshInstance3D) -> void:
	super.setup(floor_mesh,deck_block)
	var size := {"bore":.002,"outer":.006,"eye_depth":.003,"ear_depth":.002,"side_gap":.0005,"pin_radius":.0016,"head_radius":.0035,"head_depth":.0015,"head_gap":.0003,"neck_length":.002}
	for small in [true,false]:
		var block := PINNED.new()
		block.name="CoupledLower" if small else "CoupledUpper"
		block.part_kind=HARDWARE.PartKind.CONTROL_BLOCK if small else HARDWARE.PartKind.BOOM_BLOCK
		block.sheave_radius=.0125 if small else .020
		block.fork_head=small
		block.transverse_pin=small
		block.neck_extension=.066-.02642149 if small else 0.0
		block.fitting_size=size.duplicate()
		block.visible=false
		add_child(block)
		coupled_parts["lower" if small else "upper"]=block
	var tails := traveller_tails()
	traveller_total_metres=STOPPER.length_of(tails.before)+REAR_REST_METRES+STOPPER.length_of(tails.after)

func traveller_tails() -> Dictionary:
	# Fixed outer material is separate from the rear support span. Rounding
	# these tails never rounds the new contact arcs or their shared endpoints.
	var patches := traveller_fairlead_patches(_anchor(traveller_lower))
	if patches.is_empty(): return {"before":PackedVector3Array(),"after":PackedVector3Array()}
	var front: Vector3=patches.starboard[0]
	var before := traveller_handle.duplicate()
	before.reverse()
	before.append_array(PackedVector3Array([traveller_cleat.position+Vector3(.040,.013,-.080),traveller_cleat.position+Vector3(0,.018,-.070),traveller_cleat.position+Vector3(0,.018,-.025),traveller_cleat.position+Vector3(0,.020,.020),traveller_cleat.position+Vector3(0,.018,.060)]))
	before.append_array(traveller_nipping)
	before.append_array(_traveller_support(traveller_nipping[-1],front,true))
	before=CURVE.round_corners(before,.012)
	before.append_array(patches.starboard)
	var after: PackedVector3Array=patches.port.duplicate()
	after.reverse()
	after.append_array(traveller_returning)
	return {"before":before,"after":after}

func purchase_snapshot(tension: float) -> Dictionary:
	var tails := traveller_tails()
	var rear := traveller_total_metres-STOPPER.length_of(tails.before)-STOPPER.length_of(tails.after)
	var body := []
	for part: Node3D in [coupled_parts.lower,coupled_parts.upper,aft]:
		body.append(_intrinsic_mesh_records(part))
	var inverse := global_transform.affine_inverse()
	var fixed_hardware := []
	for part: Node3D in [get_node("PortTravellerEye"),get_node("StarboardTravellerEye"),traveller_cleat]:
		fixed_hardware.append_array(FIELD.capture_tree(part,inverse))
	var becket: Vector3=aft.rope_anchor_local(&"becket")
	var axis := boom_pivot.basis.z
	var angles := Vector2(atan2(axis.x,axis.z),atan2(-axis.y,Vector2(axis.x,axis.z).length()))
	var purchase := {"mount":to_local(boom_pivot.to_global(Vector3(0,-.0255-BOOM_EYE_DROP,BOOM_LENGTH-AFT_BLOCK_FROM_END))),"guide":to_local(guide.to_global(Vector3(0,.027,0))),"eye":aft.rope_anchor_local(&"attachment"),"becket":becket,"anchor":becket+Vector3.UP*.0065,"becket_winding":becket_winding,"traveller_winding":0.0,"aft_winding":0.0}
	var snapshot := {"boundary":{"port":tails.after[0],"starboard":tails.before[-1],"tiller":traveller_tiller_frame(),"tiller_radius":.0161,"tiller_half_span":.490,"sheave_radius":.0125-minf(.0048,.009*.43*.873)+.0033,"lower_winding":-1.0,"purchase":purchase},"rear_metres":rear,"traveller_total_metres":traveller_total_metres,"tails":tails,"lower":traveller_lower.transform,"aft":inverse*aft.global_transform,"upper_in":wraps.traveller.incoming,"upper_out":wraps.traveller.outgoing,"lower_eye":coupled_parts.lower.eye_frame_local(),"upper_eye":coupled_parts.upper.eye_frame_local(),"bodies":body,"hull":FIELD.capture_tree(hull,inverse),"fixed_hardware":fixed_hardware,"load":{"lower_mass":.03,"upper_mass":.05,"aft_mass":.05,"lower_com":Vector3(0,.012,0),"upper_com":Vector3(0,.003,0),"aft_com":Vector3(0,.003,0),"gravity":Vector3(0,-9.81,0),"sheet_tension":tension},"path":route.duplicate(),"wraps":wraps.duplicate(true),"fixed":fixed_end.duplicate(),"angles":angles,"tiller_angle":tiller_angle}
	snapshot["fairlead"]=traveller_contact_data()
	return snapshot

static func _intrinsic_mesh_records(part: Node3D,frame := Transform3D.IDENTITY) -> Array:
	# A body pose is an unknown, not part of its intrinsic contact geometry.
	# Compose local transforms directly: inverse(global)*global introduces
	# pose-dependent float32 noise and cannot identify exact reaction reuse.
	var records := []
	if part is MeshInstance3D and part.mesh!=null:
		records.append({"faces":FIELD.TRIANGLES.faces(part.mesh),"frame":frame,"label":str(part.get_path())})
	for child in part.get_children():
		if child is Node3D: records.append_array(_intrinsic_mesh_records(child,frame*child.transform))
	return records

func traveller_contact_data() -> Dictionary:
	var prefix := traveller_handle.duplicate()
	prefix.reverse()
	var cleat := traveller_cleat.position
	prefix.append_array(PackedVector3Array([cleat+Vector3(.040,.013,-.080),cleat+Vector3(0,.018,-.070),cleat+Vector3(0,.018,-.025),cleat+Vector3(0,.020,.020),cleat+Vector3(0,.018,.060)]))
	prefix.append_array(traveller_nipping)
	return {"frames":{"port":get_node("PortTravellerEye").transform,"starboard":get_node("StarboardTravellerEye").transform},"prefix":prefix,"returning":traveller_returning.duplicate()}


func install_purchase(value: Dictionary,display := false) -> bool:
	if not value.get("accepted",false) or not value.has_all(["path","fixed","traveller_path","poses","angles"]): return false
	coupled=value.duplicate(true)
	_show_coupled(display)
	return true

func release_purchase(display := true) -> void:
	if coupled.is_empty(): return
	var q: Vector2=coupled.angles
	coupled.clear()
	coupled_parts.lower.visible=false
	coupled_parts.upper.visible=false
	traveller.visible=true
	traveller_lower.visible=true
	traveller_link.visible=true
	traveller_rope_key=Vector4(INF,INF,INF,INF)
	super.set_angles(q.x,q.y,display)

func _show_coupled(display: bool) -> void:
	for key in ["lower","upper"]:
		coupled_parts[key].transform=coupled.poses[key]
		coupled_parts[key].visible=true
	aft.transform=boom_pivot.transform.affine_inverse()*coupled.poses.aft
	traveller.visible=false
	traveller_lower.visible=false
	traveller_link.visible=false
	route=coupled.path
	fixed_end=coupled.fixed
	traveller_path=coupled.traveller_path
	if display:
		rope_view.show_path(route)
		fixed_view.show_path(fixed_end)
		traveller_view.show_path(traveller_path)

func set_angles(yaw: float,pitch: float,display := true) -> void:
	if not coupled.is_empty():
		if Vector2(yaw,pitch).distance_to(coupled.angles)<.000001 and absf(tiller_angle-coupled.tiller_angle)<.000001:
			_show_coupled(display)
			return
		release_purchase(false)
	super.set_angles(yaw,pitch,display)

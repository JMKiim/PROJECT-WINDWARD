extends "res://src/boat/training_sheave_block.gd"

## Provisional finite-pin traveller candidate. This is deliberately a
## separate construction: the active rig and its authored length envelope
## still use training_sheave_block until joint/rope coupling is validated.
const FITTING := preload("res://src/boat/finite_pin_fitting.gd")
var fork_head := true
var fitting_size := {}
var transverse_pin := false
var neck_extension := 0.0

func rope_anchor_local(anchor_name: StringName = &"sheave") -> Vector3:
	if anchor_name==&"attachment": return Vector3(0,_mount_top()+fitting_size.get("outer",.006)+fitting_size.get("neck_length",.002),0)
	return super.rope_anchor_local(anchor_name)

func _mount_top() -> float:
	# The real tube, not only its centreline, must pass below the bridge.
	# Candidate sizing clearance, not a claimed measured product dimension.
	var small := part_kind==PartKind.CONTROL_BLOCK
	var width := .009 if small else BLOCK_SHEAVE_WIDTH
	var rope_radius := .003 if small else .004
	var groove_bottom := sheave_radius-minf(BLOCK_GROOVE_DEPTH,width*.43*.873)
	return groove_bottom+2*rope_radius+.0003+.001+.002+neck_extension

func eye_frame_local() -> Transform3D:
	var clocking := Basis(Vector3.UP,PI*.5) if transverse_pin else Basis.IDENTITY
	return Transform3D(clocking*(Basis.IDENTITY if fork_head else Basis(Vector3.BACK,PI)),rope_anchor_local(&"attachment"))

func _ready() -> void:
	mesh=null
	_build_block(sheave_radius,false)
	# Retain the shared wheel, cheeks and axle, replacing the entire old head
	# assembly. Its solid strop centre is not a hole in this construction.
	for child in get_children():
		var label := String(child.name)
		if label in ["AttachmentStrop","HeadBridge"] or label.begins_with("PortNeck") or label.begins_with("StarboardNeck"):
			remove_child(child)
			child.free()
	var fitting := FITTING.build(fitting_size)
	assert(fitting.valid,"Finite head requires explicit fitting dimensions")
	if not fitting.valid: return
	var eye := eye_frame_local()
	for part: Dictionary in fitting.fixed if fork_head else fitting.moving:
		# One full-width mounting bridge replaces the coupon's narrow bridge;
		# overlapping coplanar boxes would flicker in the close-up renderer.
		if part.label=="ForkBridge": continue
		var instance := MeshInstance3D.new()
		instance.name=part.label
		var shape := ArrayMesh.new()
		shape.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,part.arrays)
		instance.mesh=shape
		instance.transform=eye*part.transform
		instance.material_override=_stainless
		add_child(instance)
	var small := part_kind==PartKind.CONTROL_BLOCK
	var width := .009 if small else BLOCK_SHEAVE_WIDTH
	var thickness := .0025 if small else BLOCK_CHEEK_THICKNESS
	var offset := width*.5+BLOCK_CHEEK_CLEARANCE+thickness*.5
	var bridge_y: float=rope_anchor_local(&"attachment").y-fitting_size.outer-fitting_size.neck_length
	# A transverse bridge above the rotating sheave attaches the new head to
	# two side rails. Neither a rail nor the bridge fills the pin's bore.
	var outside := offset+thickness*.5
	var inside := offset-thickness*.5
	var bottom := sheave_radius*.65
	var outline := PackedVector2Array([Vector2(-outside,bottom),Vector2(-inside,bottom),Vector2(-inside,bridge_y-.002),Vector2(inside,bridge_y-.002),Vector2(inside,bottom),Vector2(outside,bottom),Vector2(outside,bridge_y),Vector2(-outside,bridge_y)])
	var depth: float=fitting_size.outer*1.2
	if transverse_pin:
		# The clocked fork stems sit fore/aft, not across the cheeks. The
		# bridge must reach their entire thickness, without filling the bore.
		depth=maxf(depth,fitting_size.eye_depth+2*(fitting_size.side_gap+fitting_size.ear_depth))
	var mount := _add_profile_part("PinHeadMountFrame",outline,depth,Vector3.ZERO,_black)
	mount.rotation.y=PI*.5

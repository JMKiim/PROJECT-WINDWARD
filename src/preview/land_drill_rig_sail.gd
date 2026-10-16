extends Node3D

## Straight-mast presentation. The fitted eye is a mounting datum, not a
## force solution; neither the sailor nor the material ledger is written.
const SAIL := preload("res://src/boat/ilca_sail.gd")
const CONTRACT := preload("res://src/boat/rigging_contract.gd")
const BOOM_RADIUS := .0255
const BAND_INNER := BOOM_RADIUS+.0005
const BAND_OUTER := BAND_INNER+.002
const BAND_WIDTH := .030
const EYE_HEIGHT := BAND_OUTER+.011
var rig: Node3D
var cloth: MeshInstance3D
var strap: Node3D
var eye: MeshInstance3D
var closed_pitch := 0.0
var reference_leech := 0.0
var cloth_revision := 0
var last_local_clew := Vector3(INF,INF,INF)

func setup(value: Node3D) -> bool:
	rig=value
	strap=Node3D.new()
	strap.name="ClewStrap"
	strap.position=Vector3(0,0,CONTRACT.CLEW_LOCAL.z)
	rig.boom_pivot.add_child(strap)
	var band := MeshInstance3D.new()
	band.name="BoomWebbing"
	band.mesh=_band_mesh()
	var webbing := StandardMaterial3D.new()
	webbing.albedo_color=Color("252b2e")
	webbing.roughness=.9
	band.material_override=webbing
	strap.add_child(band)
	eye=MeshInstance3D.new()
	eye.name="ClewEye"
	eye.position=Vector3(0,EYE_HEIGHT,0)
	eye.rotation.z=PI*.5
	var ring := TorusMesh.new()
	ring.inner_radius=.005
	ring.outer_radius=.011
	ring.rings=32
	ring.ring_segments=8
	eye.mesh=ring
	var metal := StandardMaterial3D.new()
	metal.albedo_color=Color("aab2b6")
	metal.metallic=.8
	metal.roughness=.3
	eye.material_override=metal
	strap.add_child(eye)
	var reader := SAIL.new()
	reference_leech=reader.boundary_arc_length(&"leech")
	var low := deg_to_rad(-15)
	var high := 0.0
	for iteration in 30:
		var pitch: float=(low+high)*.5
		var boom_frame: Transform3D=CONTRACT.boom_transform(0,pitch)
		var frame := sail_frame(0,reader.luff_boundary_point(1))
		reader._clew_target_local=frame.affine_inverse()*(boom_frame*Vector3(0,EYE_HEIGHT,strap.position.z))
		if reader.boundary_arc_length(&"leech")>reference_leech: high=pitch
		else: low=pitch
	closed_pitch=low
	reader.free()
	cloth=SAIL.new()
	cloth.name="TrainingSail"
	cloth.set_process(false)
	add_child(cloth)
	cloth.set_process(false)
	return is_finite(closed_pitch) and closed_pitch>=deg_to_rad(-15) and closed_pitch<0

static func sail_frame(yaw: float,local_head: Vector3) -> Transform3D:
	var turn := Basis(Vector3.UP,yaw)
	return Transform3D(turn,CONTRACT.SAIL_HEAD-turn*local_head)

func synchronize(yaw: float) -> void:
	if cloth==null: return
	cloth.transform=sail_frame(yaw,cloth.luff_boundary_point(1))
	var point: Vector3=cloth.to_local(eye.global_position)
	# At fixed pitch the sail only turns around the mast. Do not rebuild the
	# same cloth/pockets/three battens for float-noise in a yaw round trip.
	if point.distance_to(last_local_clew)>.000002:
		cloth.set_clew_target_local(point)
		last_local_clew=point
		cloth_revision+=1

func edges() -> Dictionary:
	return {"luff":cloth.boundary_arc_length(&"luff"),"foot":cloth.boundary_arc_length(&"foot"),"leech":cloth.boundary_arc_length(&"leech"),"eye_error":cloth.to_global(cloth.clew_target_local()).distance_to(eye.global_position),"head_error":cloth.to_global(cloth.luff_boundary_point(1)).distance_to(rig.to_global(CONTRACT.SAIL_HEAD))}

static func _band_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in 48:
		var a := TAU*index/48.0
		var b := TAU*(index+1)/48.0
		var ra := Vector3(cos(a),sin(a),0)
		var rb := Vector3(cos(b),sin(b),0)
		for radius: float in [BAND_INNER,BAND_OUTER]:
			_quad(surface,ra*radius+Vector3.FORWARD*BAND_WIDTH*.5,rb*radius+Vector3.FORWARD*BAND_WIDTH*.5,rb*radius+Vector3.BACK*BAND_WIDTH*.5,ra*radius+Vector3.BACK*BAND_WIDTH*.5,(ra+rb).normalized()*(-1 if radius==BAND_INNER else 1))
		for sign_z: float in [-1.0,1.0]:
			var shift := Vector3.BACK*BAND_WIDTH*.5*sign_z
			_quad(surface,ra*BAND_INNER+shift,rb*BAND_INNER+shift,rb*BAND_OUTER+shift,ra*BAND_OUTER+shift,Vector3.BACK*sign_z)
	surface.index()
	return surface.commit()

static func _quad(surface: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,d: Vector3,normal: Vector3) -> void:
	var points := [a,b,c,a,c,d] if (b-a).cross(c-a).dot(normal)<0 else [a,c,b,a,d,c]
	for point: Vector3 in points:
		surface.set_normal(normal)
		surface.add_vertex(point)

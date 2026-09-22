extends Node3D

## Fixed transom fittings and the common steering-axis assembly.
const HARDWARE := preload("res://src/boat/ilca_hardware_part.gd")
const FOIL := preload("res://src/boat/ilca_foil.gd")
const CUT := preload("res://src/boat/ilca_mesh_cut.gd")
const ROPE := preload("res://src/boat/rope_tube_view.gd")
const STOPPER := preload("res://src/boat/mainsheet_stopper.gd")
const CURVE := preload("res://src/boat/rope_path_curve.gd")
const PIN_AXIS_Z := 2.171
const BLADE_PIVOT := Vector3(0,.155,.065)
var bearings: Array[Node3D] = []
var blade_pivot: Node3D
var downhaul_path := PackedVector3Array()
var downhaul_hole := Vector2(.120,-.065)

func setup(rudder: Node3D) -> void:
	for y: float in [.225,.105]:
		var fitting := HARDWARE.new()
		fitting.name = "UpperRudderGudgeon" if y>.2 else "LowerRudderGudgeon"
		fitting.part_kind = HARDWARE.PartKind.RUDDER_GUDGEON
		fitting.position = Vector3(0,y,PIN_AXIS_Z-.052)
		add_child(fitting)
		bearings.append(fitting)
	var builder := bearings[0]
	var clip_profile := PackedVector2Array([
		Vector2(0,.203),Vector2(.0012,.203),Vector2(.0012,.177),
		Vector2(.043,.153),Vector2(.0424,.152),Vector2(0,.176),
	])
	var clip: Node3D = builder._add_profile_part("RudderRetainingClip",clip_profile,.014,Vector3(0,0,2.124),builder._stainless)
	clip.reparent(self,false)
	for y: float in [.195,.183]:
		var screw: Node3D = builder._add_cylinder("ClipScrew",.002,.0035,Vector3(0,y,2.127),builder._stainless,Vector3(PI*.5,0,0))
		screw.reparent(self,false)
	var flange: Node3D = builder._add_cylinder("TransomDrainFlange",.004,.020,Vector3(.105,.091,2.125),builder._black,Vector3(PI*.5,0,0))
	flange.reparent(self,false)
	var plug: Node3D = builder._add_cylinder("ClosedDrainPlug",.007,.012,Vector3(.105,.091,2.130),builder._soft_black,Vector3(PI*.5,0,0))
	plug.reparent(self,false)
	var grip: Node3D = builder._add_box("DrainPlugGrip",Vector3(.020,.004,.005),Vector3(.105,.091,2.135),builder._black)
	grip.reparent(self,false)
	for x: float in [.084,.126]:
		var screw: Node3D = builder._add_cylinder("DrainScrew",.002,.003,Vector3(x,.091,2.128),builder._stainless,Vector3(PI*.5,0,0))
		screw.reparent(self,false)
	blade_pivot = Node3D.new()
	blade_pivot.name = "RudderBladePivot"
	blade_pivot.position = BLADE_PIVOT
	blade_pivot.rotation_degrees.x = -12
	rudder.add_child(blade_pivot)
	var blade := FOIL.new()
	blade.name = "RudderBlade"
	blade.foil_kind = FOIL.FoilKind.RUDDER
	# Keep material above the bolt; the previous root almost ended at its axis.
	# Exact mould offsets remain provisional, distinct from the fixed hand datum.
	blade.position = Vector3(0,-.250,.032)
	blade.span = .635
	blade.root_chord = .203
	blade.tip_chord = .066
	blade.maximum_thickness = .020
	blade.aft_sweep = .015
	blade_pivot.add_child(blade)
	for part in rudder.get_children():
		if part.has_node("RudderDownhaulCleatBase"):
			_add_downhaul(blade,part,rudder)
			break

func _add_downhaul(blade: MeshInstance3D,tiller: Node3D,rudder: Node3D) -> void:
	# Representative fixed-down rigging. The bore/cleat locations are modelling
	# estimates; lifting and cleat-release controls are a separate interaction.
	_cut_blade_bore(blade,Vector2(.250,-.032),.00495,"PivotBore")
	_cut_blade_bore(blade,downhaul_hole,.0035,"DownhaulBore")
	var bore := Vector3(0,downhaul_hole.x,downhaul_hole.y)
	var right: Vector3=rudder.to_local(blade.to_global(bore+Vector3(.012,0,0)))
	var left: Vector3=rudder.to_local(blade.to_global(bore-Vector3(.012,0,0)))
	var knot := STOPPER.points(.040,.020)
	for index in knot.size(): knot[index]*=.375
	downhaul_path=STOPPER.placed(knot,right,Vector3.RIGHT)
	downhaul_path.reverse()
	# The working leg rises through the open pintle bridges, not down the
	# exposed working blade or through solid metal at the steering axis.
	var lip: Vector3=rudder.to_local(blade.to_global(Vector3(-.013,downhaul_hole.x,-.115)))
	downhaul_path.append_array(PackedVector3Array([left,lip,Vector3(-.010,.040,.005),Vector3(-.010,.085,.012),Vector3(-.010,.123,.020),Vector3(-.010,.263,.020),Vector3(-.010,.277,-.012),Vector3(-.026,.294,-.018),Vector3(-.026,.302,-.028)]))
	for z: float in [.363,.335,.295]:
		downhaul_path.append(rudder.to_local(tiller.to_global(Vector3(-.023,0,z))))
	downhaul_path=CURVE.round_corners(downhaul_path,.004)
	var rope := ROPE.new()
	rope.name="RudderDownhaul"
	rope.radius=.0015
	rope.color=Color("96324c")
	rudder.add_child(rope)
	rope.show_path(downhaul_path)

func _cut_blade_bore(blade: MeshInstance3D,location: Vector2,radius: float,label: String) -> void:
	var outline := CUT.circle(location,radius,24)
	var frame := Transform3D(Basis(Vector3.UP,Vector3.LEFT,Vector3.BACK),Vector3.ZERO)
	blade.mesh=CUT.apply(blade.mesh,{0:[outline]},frame)
	var liner := SurfaceTool.new()
	liner.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in outline.size():
		var edge := []
		for point: Vector2 in [outline[index],outline[(index+1)%outline.size()]]:
			var fraction: float=.5-point.x/blade.span
			var chord: Vector2=blade._side_outline(fraction)
			var ratio := inverse_lerp(chord.x,chord.y,point.y)
			var half: float=blade.effective_maximum_thickness()*blade._naca_half_thickness_shape(ratio)*blade._span_thickness_factor(fraction)
			edge.append(Vector3(half,point.x,point.y))
			edge.append(Vector3(-half,point.x,point.y))
		for corner in [0,2,3,0,3,1]: liner.add_vertex(edge[corner])
	liner.generate_normals()
	var wall := MeshInstance3D.new()
	wall.name=label
	wall.mesh=liner.commit()
	wall.material_override=blade.mesh.surface_get_material(0)
	blade.add_child(wall)

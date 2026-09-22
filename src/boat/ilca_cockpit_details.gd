extends Node3D

## Shared static cockpit fittings. Locations follow the moulded support
## surface; rope tension and hiking deformation are separate controls.
const EYE_SPACING := .048
const EYE_DROP := .100
const STRAP_FRONT := .119
const STRAP_END := .888
const PAD_START := .194
const PAD_END := .816
const PAD_CENTRE_Y := .137
const PAD_WIDTH := .080
const PAD_THICKNESS := .012
var hull: MeshInstance3D
var rail_mounts := PackedVector3Array()
var eye_mounts := PackedVector3Array()
var eye_centres := PackedVector3Array()
var support_path := PackedVector3Array()
var strap_loop := Vector3(0,.144,.888)
var _plastic := _material(Color("555d62"),.64)
var _rubber := _material(Color("25282a"),.87)
var _steel := _material(Color("a2a9ad"),.27,.85)
var _dark := _material(Color("121719"),.78)

func setup(floor_mesh: MeshInstance3D, ratchet: MeshInstance3D) -> void:
	hull = floor_mesh
	_build_rails()
	_build_strap(ratchet)
	_build_support()
	_build_bow_eye()

func _build_rails() -> void:
	# The inside-wall rail is a low moulding, not a bar on the seating deck.
	# Three sections and five countersunk fasteners follow the builder photos.
	for side: float in [-1.0,1.0]:
		var prefix := "Port" if side<0 else "Starboard"
		for section in 3:
			var z0 := .335 + section * .320
			var z1 := z0 + .317
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			var previous := PackedVector3Array()
			for index in 25:
				var z := lerpf(z0,z1,index/24.0)
				var y: float = hull.deck_y_at(0,z)-.047
				var taper := lerpf(.30,1.0,minf(smoothstep(z0,z0+.009,z),1-smoothstep(z1-.009,z1,z)))
				var top := _wall_point(side,y+.012*taper,z)
				var bottom := _wall_point(side,y-.012*taper,z)
				var normal: Vector3 = hull._surface_normal(bottom.x,bottom.z,2)
				var ring := PackedVector3Array([top,top+normal*.006,bottom+normal*.009,bottom])
				if not previous.is_empty():
					for edge in 4:
						var next := (edge+1)%4
						_quad(surface,previous[edge],ring[edge],ring[next],previous[next],Vector3(-side,0,0) if edge==1 else (Vector3.UP if edge==0 else Vector3.DOWN))
				if index==0: _quad(surface,ring[0],ring[1],ring[2],ring[3],Vector3.FORWARD)
				if index==24: _quad(surface,ring[3],ring[2],ring[1],ring[0],Vector3.BACK)
				previous = ring
			_mesh(prefix+"GrabRail%d"%section,surface,_plastic)
		for index in 5:
			var z := lerpf(.370,1.255,index/4.0)
			var point := _wall_point(side,hull.deck_y_at(0,z)-.047,z)
			var normal: Vector3 = hull._surface_normal(point.x,z,2)
			rail_mounts.append(point)
			_screw(prefix+"RailScrew%d"%index,point+normal*.009,normal)

func _wall_point(side: float,y: float,z: float) -> Vector3:
	var lo := 0.0
	var hi: float = hull._cockpit_half_width_at(z)
	for index in 32:
		var x := (lo+hi)*.5
		if hull.cockpit_floor_y_at(x,z)<y: lo=x
		else: hi=x
	var x := side*(lo+hi)*.5
	return Vector3(x,hull.cockpit_floor_y_at(x,z),z)

func _aft_point(x: float,y: float) -> Vector3:
	var lo := 1.340
	var hi := 1.415
	for index in 32:
		var z := (lo+hi)*.5
		if hull.cockpit_floor_y_at(x,z)<y: lo=z
		else: hi=z
	var z := (lo+hi)*.5
	return Vector3(x,hull.cockpit_floor_y_at(x,z),z)

func _build_strap(ratchet: MeshInstance3D) -> void:
	# The webbing is clamped under the mainsheet mounting plate, not on a
	# separate unsupported plate aft of it. Preserve the sheave/hand datum.
	var base: MeshInstance3D = ratchet.get_node("EyeStrapBase")
	base.position.y += .004
	for child in ratchet.get_children():
		if str(child.name).begins_with("MountScrew"): child.position.y += .004
	_box("StrapPressurePlate",Vector3(.062,.002,.037),Vector3(0,.243,.140),_dark)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var previous := PackedVector3Array()
	for index in 97:
		var z := lerpf(STRAP_FRONT,STRAP_END,index/96.0)
		var cross := strap_section(z)
		var ring := PackedVector3Array()
		for edge in 24:
			var a := TAU*edge/24.0
			var x := signf(cos(a))*pow(absf(cos(a)),.32)*cross.y*.5
			var y := cross.x+signf(sin(a))*pow(absf(sin(a)),.56)*cross.z*.5
			ring.append(Vector3(x,y,z))
		if not previous.is_empty():
			for edge in 24:
				var next := (edge+1)%24
				_quad(surface,previous[edge],ring[edge],ring[next],previous[next],Vector3(ring[edge].x,ring[edge].y-cross.x,0))
		if index in [0,96]:
			for edge in 24: _triangle(surface,Vector3(0,cross.x,z),ring[edge],ring[(edge+1)%24],Vector3.FORWARD if index==0 else Vector3.BACK)
		previous = ring
	_mesh("PaddedStrap",surface,_rubber)
	# Flat webbing return forms a real closed sewn loop at the aft support.
	var loop_surface := SurfaceTool.new()
	loop_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prior := PackedVector3Array()
	for index in 49:
		var angle := TAU*index/48.0
		var centre := strap_loop+Vector3(0,sin(angle)*.006,cos(angle)*.014)
		var normal := Vector3(0,sin(angle)/.006,cos(angle)/.014).normalized()
		var ring := PackedVector3Array([centre-Vector3.RIGHT*.025+normal*.00075,centre+Vector3.RIGHT*.025+normal*.00075,centre+Vector3.RIGHT*.025-normal*.00075,centre-Vector3.RIGHT*.025-normal*.00075])
		if not prior.is_empty():
			for edge in 4:
				var next := (edge+1)%4
				var outward := normal if edge==0 else (-normal if edge==2 else (Vector3.RIGHT if edge==1 else Vector3.LEFT))
				_quad(loop_surface,prior[edge],ring[edge],ring[next],prior[next],outward)
		prior = ring
	_mesh("AftSewnLoop",loop_surface,_rubber)
	var stitches := SurfaceTool.new()
	stitches.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0,1.0]:
		for index in 118:
			var z := lerpf(PAD_START+.010,PAD_END-.010,index/117.0)
			_stitch(stitches,Vector2(side*.033,z),Vector2(side*.033,z+.0022))
	# Bound padding ends and a visible box/X seam on the folded aft webbing.
	for z: float in [PAD_START+.008,PAD_END-.008,.843,.870]:
		var half_width := minf(.031,strap_section(z).y*.5-.004)
		for index in 15:
			var x := lerpf(-half_width,half_width-.002,index/14.0)
			_stitch(stitches,Vector2(x,z),Vector2(x+.002,z))
	for side: float in [-1.0,1.0]:
		for index in 12:
			var t := index/12.0
			_stitch(stitches,Vector2(lerpf(-.021,.021,t)*side,lerpf(.843,.870,t)),Vector2(lerpf(-.021,.021,t+.045)*side,lerpf(.843,.870,t+.045)))
	_mesh("StrapStitching",stitches,_material(Color("626360"),.95))
	for z: float in [PAD_START+.002,PAD_END-.002]:
		var edge := PackedVector3Array()
		for index in 25:
			var x := lerpf(-.036,.036,index/24.0)
			edge.append(Vector3(x,_strap_top(x,z)+.0002,z))
		_line("PadBinding",edge,.00065,Color("303538"))

func _stitch(surface: SurfaceTool,a: Vector2,b: Vector2) -> void:
	var axis := (b-a).orthogonal().normalized()*.00026
	var points := PackedVector3Array()
	for p: Vector2 in [a-axis,a+axis,b+axis,b-axis]: points.append(Vector3(p.x,_strap_top(p.x,p.y)+.00035,p.y))
	_quad(surface,points[0],points[1],points[2],points[3],Vector3.UP)

static func _strap_top(x: float,z: float) -> float:
	var section := strap_section(z)
	var fraction := clampf(absf(x)/(section.y*.5),0,1)
	return section.x+section.z*.5*pow(maxf(0,1-pow(fraction,6.25)),.28)

static func strap_section(z: float) -> Vector3:
	# y, width, thickness. Separate webbing width, foam termination and bend:
	# the cover ends in a short bound seam, not a long rubber-like taper.
	var bend := smoothstep(.250,.435,z)
	var rear := smoothstep(PAD_END,STRAP_END,z)
	var padded := smoothstep(PAD_START-.006,PAD_START+.006,z)*(1-smoothstep(PAD_END-.006,PAD_END+.006,z))
	return Vector3(lerpf(lerpf(.241+.006*padded,PAD_CENTRE_Y,bend),.144,rear),lerpf(lerpf(.050,PAD_WIDTH,smoothstep(.164,.194,z)),.050,rear),lerpf(.0025,PAD_THICKNESS,padded))

func _build_support() -> void:
	for side: float in [-1.0,1.0]:
		var x := side*EYE_SPACING*.5
		var point := _aft_point(x,hull.deck_y_at(x,1.415)-EYE_DROP)
		var normal: Vector3 = hull._surface_normal(point.x,point.z,2)
		var along := Vector3.RIGHT.cross(normal).normalized()
		eye_mounts.append(point)
		var centre := point+normal*.0075
		eye_centres.append(centre)
		var arch := PackedVector3Array()
		for index in 25:
			var a := PI*index/24.0
			arch.append(point+along*(cos(a)*.014)+normal*(sin(a)*.015+.0015))
		_line("AftEyestrap",arch,.0022,Color("a2a9ad"))
		for sign_y: float in [-1.0,1.0]:
			var foot := point+along*(sign_y*.014)
			_screw("AftEyeScrew",foot+normal*.0015,normal)
	# Fixed, tied support is a supported configuration; an adjustable tackle
	# and hiking-load response have not been represented by a decorative cleat.
	var left := eye_centres[0]
	var right := eye_centres[1]
	support_path = PackedVector3Array([left,strap_loop+Vector3(-.017,0,0),strap_loop+Vector3(0,-.003,0),strap_loop+Vector3(.017,0,0),right])
	_line("StrapSupport",support_path,.0025,Color("b3b4aa"))
	for eye in eye_centres:
		var knot := PackedVector3Array()
		for index in 41:
			var a := TAU*2*index/40.0
			knot.append(eye+Vector3(cos(a)*.005,sin(a)*.005,(index/40.0-.5)*.012))
		_line("SupportLashing",knot,.002,Color("b3b4aa"))

func _build_bow_eye() -> void:
	# Replacement-guide fore-aft interval; this midpoint is not a mould survey.
	var z := 2.123-3.905
	var y: float = hull.deck_y_at(0,z)
	var eye := PackedVector3Array()
	for index in 25:
		var a := PI*index/24.0
		eye.append(Vector3(0,y+.002+sin(a)*.011,z+cos(a)*.018))
	_line("BowEye",eye,.003,Color("454b4e"))
	for sign_z: float in [-1.0,1.0]:
		var foot_z := z+sign_z*.022
		_box("BowEyeFoot",Vector3(.010,.0015,.014),Vector3(0,hull.deck_y_at(0,foot_z)+.00075,foot_z),_steel)
		_screw("BowScrew",Vector3(0,hull.deck_y_at(0,z+sign_z*.024)+.0015,z+sign_z*.024),Vector3.UP)

func _mesh(label: String,surface: SurfaceTool,material: Material) -> MeshInstance3D:
	surface.index()
	var value := MeshInstance3D.new()
	value.name = label
	value.mesh = surface.commit()
	value.material_override = material
	add_child(value)
	return value

func _box(label: String,size: Vector3,point: Vector3,material: Material) -> MeshInstance3D:
	var value := MeshInstance3D.new()
	value.name = label
	var box := BoxMesh.new()
	box.size = size
	value.mesh = box
	value.position = point
	value.material_override = material
	add_child(value)
	return value

func _screw(label: String,point: Vector3,normal: Vector3) -> void:
	var value := MeshInstance3D.new()
	value.name = label
	var head := CylinderMesh.new()
	head.top_radius = .0041
	head.bottom_radius = .0032
	head.height = .0013
	head.radial_segments = 20
	value.mesh = head
	value.material_override = _steel
	value.transform = Transform3D(Basis(Quaternion(Vector3.UP,normal)),point)
	add_child(value)
	for turn in 2:
		var slot := _box("CrossRecess",Vector3(.0048,.0001,.0007),Vector3.ZERO,_dark)
		slot.transform = value.transform*Transform3D(Basis(Vector3.UP,turn*PI*.5),Vector3(0,.00068,0))

func _line(label: String,points: PackedVector3Array,radius: float,color: Color) -> void:
	# Fixed tubing is one closed surface, not hundreds of moving rope instances.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var previous := PackedVector3Array()
	var frame_u := Vector3.ZERO
	for index in points.size():
		var tangent := (points[mini(index+1,points.size()-1)]-points[maxi(index-1,0)]).normalized()
		# Transport the section frame through bends without flipping reference
		# axes at an upright tangent and twisting a short metal tube segment.
		var projected := frame_u-tangent*frame_u.dot(tangent)
		if projected.length_squared()<.000001:
			var reference := Vector3.UP if absf(tangent.y)<.95 else Vector3.RIGHT
			projected = tangent.cross(reference)
		frame_u = projected.normalized()
		var u := frame_u
		var v := tangent.cross(u).normalized()
		var ring := PackedVector3Array()
		for edge in 12:
			var angle := TAU*edge/12.0
			ring.append(points[index]+radius*(u*cos(angle)+v*sin(angle)))
		if not previous.is_empty():
			for edge in 12:
				var next := (edge+1)%12
				_quad(surface,previous[edge],ring[edge],ring[next],previous[next],ring[edge]-points[index])
		if index==0 or index==points.size()-1:
			for edge in 12: _triangle(surface,points[index],ring[edge],ring[(edge+1)%12],-tangent if index==0 else tangent)
		previous = ring
	var metal := "Eye" in label
	_mesh(label,surface,_material(color,.28 if metal else .95,.8 if metal else 0.0))

static func _material(color: Color,roughness: float,metallic := 0.0) -> StandardMaterial3D:
	var value := StandardMaterial3D.new()
	value.albedo_color = color
	value.roughness = roughness
	value.metallic = metallic
	value.cull_mode = BaseMaterial3D.CULL_DISABLED
	return value

static func _triangle(surface: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,outward: Vector3) -> void:
	var normal := (b-a).cross(c-a)
	if normal.length_squared()<1e-18: return
	normal = normal.normalized()
	if normal.dot(outward)<0: normal = -normal
	var points := [a,c,b] if (b-a).cross(c-a).dot(normal)>0 else [a,b,c]
	for point in points:
		surface.set_normal(normal)
		surface.add_vertex(point)

static func _quad(surface: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,d: Vector3,outward: Vector3) -> void:
	_triangle(surface,a,b,c,outward)
	_triangle(surface,a,c,d,outward)

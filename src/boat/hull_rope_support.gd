extends RefCounted

## Finite-radius support against actual hull triangles in a gravity frame.
## Geometry only: reactions, friction and moving blocks are not solved here.
const CELL := .06
const CONTACT_PAD := .00004
var frame := Basis.IDENTITY
var cell_size := CELL
var radius := .004
var triangles := []
var cells := {}
var height_cache := {}
var valid := false
var last_clearance := {}

func setup(mesh: Mesh,transform: Transform3D,gravity: Vector3,rope_radius: float,grid_size := CELL) -> bool:
	return setup_faces(mesh.get_faces() if mesh!=null else PackedVector3Array(),transform,gravity,rope_radius,grid_size)

func setup_faces(faces: PackedVector3Array,transform: Transform3D,gravity: Vector3,rope_radius: float,grid_size := CELL) -> bool:
	# Detached numerical input: workers never fetch a live mesh or scene node.
	valid=false
	triangles.clear()
	cells.clear()
	height_cache.clear()
	if faces.is_empty() or faces.size()%3!=0 or not gravity.is_finite() or gravity.length()<.0001 or not is_finite(rope_radius) or rope_radius<=0 or not is_finite(grid_size) or grid_size<=0: return false
	cell_size=grid_size
	var up := -gravity.normalized()
	var right := Vector3.RIGHT-up*up.x
	if right.length()<.1: right=Vector3.FORWARD+up*up.z
	right=right.normalized()
	frame=Basis(right,up,right.cross(up)).orthonormalized()
	radius=rope_radius+CONTACT_PAD
	for index in range(0,faces.size(),3):
		var a := frame.transposed()*(transform*faces[index])
		var b := frame.transposed()*(transform*faces[index+1])
		var c := frame.transposed()*(transform*faces[index+2])
		var normal := (b-a).cross(c-a)
		if normal.length_squared()<1e-18: continue
		normal=normal.normalized()
		if normal.y<0: normal=-normal
		var lower := Vector2(minf(a.x,minf(b.x,c.x))-radius,minf(a.z,minf(b.z,c.z))-radius)
		var upper := Vector2(maxf(a.x,maxf(b.x,c.x))+radius,maxf(a.z,maxf(b.z,c.z))+radius)
		var item := {"a":a,"b":b,"c":c,"n":normal,"d":normal.dot(a)+radius,"lo":lower,"hi":upper}
		var orientation := float(b.x-a.x)*(c.z-a.z)-float(b.z-a.z)*(c.x-a.x)
		var clip := PackedVector3Array()
		if absf(orientation)>1e-14:
			for edge in [[a,b],[b,c],[c,a]]:
				var direction: Vector3=edge[1]-edge[0]
				var inward := Vector2(-direction.z,direction.x)*signf(orientation)
				clip.append(Vector3(inward.x,inward.y,inward.dot(Vector2(edge[0].x,edge[0].z))-radius*inward.length()))
		item["clip"]=clip
		var slot := triangles.size()
		triangles.append(item)
		for x in range(floori(lower.x/cell_size),floori(upper.x/cell_size)+1):
			for z in range(floori(lower.y/cell_size),floori(upper.y/cell_size)+1):
				var key := Vector2i(x,z)
				if not cells.has(key): cells[key]=PackedInt32Array()
				cells[key].append(slot)
	valid=not triangles.is_empty()
	return valid

func height_at(point: Vector3) -> float:
	if height_cache.size()>65536: height_cache.clear()
	var local := frame.transposed()*point
	var xz := Vector2(local.x,local.z)
	if height_cache.has(xz): return height_cache[xz]
	var highest := -INF
	for index: int in cells.get(Vector2i(floori(xz.x/cell_size),floori(xz.y/cell_size)),PackedInt32Array()):
		var item: Dictionary=triangles[index]
		if xz.x<item.lo.x or xz.x>item.hi.x or xz.y<item.lo.y or xz.y>item.hi.y: continue
		if not projected_overlap(item,xz,xz): continue
		var n: Vector3=item.n
		var ceiling := maxf(item.a.y,maxf(item.b.y,item.c.y))+radius
		if ceiling<=highest: continue
		if n.y>.000001:
			var y: float=(item.d-n.x*xz.x-n.z*xz.y)/n.y
			# The offset face plane bounds its entire rounded triangle. Once
			# a face witness attains that bound, no edge can lie above it.
			if y<=highest: continue
			var contact := Vector3(xz.x,y,xz.y)-n*radius
			if _inside(contact,item.a,item.b,item.c):
				highest=maxf(highest,y)
				continue
		for edge in [[item.a,item.b],[item.b,item.c],[item.c,item.a]]:
			highest=maxf(highest,_edge_height(xz,edge[0],edge[1]))
	height_cache[xz]=highest
	return highest

static func projected_overlap(triangle: Dictionary,lower: Vector2,upper: Vector2) -> bool:
	# Separating edge half-planes of the projected triangle, expanded by the
	# physical radius. The rounded triangle is contained by all three planes.
	for plane: Vector3 in triangle.clip:
		var x := upper.x if plane.x>=0 else lower.x
		var z := upper.y if plane.y>=0 else lower.y
		if plane.x*x+plane.y*z<plane.z-1e-9: return false
	return true

func _edge_height(xz: Vector2,a: Vector3,b: Vector3) -> float:
	var result := maxf(_vertex_height(xz,a),_vertex_height(xz,b))
	# Scalar precision avoids subtracting nearly equal float-vector squares
	# at almost vertical edges. Their silhouette must not invent tall spikes.
	var ex := float(b.x)-a.x
	var ey := float(b.y)-a.y
	var ez := float(b.z)-a.z
	var qx := float(xz.x)-a.x
	var qz := float(xz.y)-a.z
	var horizontal := ex*ex+ez*ez
	if horizontal<1e-20: return result
	var dot_flat := qx*ex+qz*ez
	var cross_flat := qx*ez-qz*ex
	var remaining := radius*radius-cross_flat*cross_flat/horizontal
	if remaining<0: return result
	var squared := horizontal+ey*ey
	var y := a.y+ey*dot_flat/horizontal+sqrt(remaining*squared/horizontal)
	var t := (dot_flat+(y-a.y)*ey)/squared
	if t>=0 and t<=1: result=maxf(result,y)
	return result

func _vertex_height(xz: Vector2,point: Vector3) -> float:
	var dx := float(xz.x)-point.x
	var dz := float(xz.y)-point.z
	var remaining := radius*radius-dx*dx-dz*dz
	return point.y+sqrt(remaining) if remaining>=0 else -INF

static func _inside(point: Vector3,a: Vector3,b: Vector3,c: Vector3) -> bool:
	var v0 := b-a
	var v1 := c-a
	var v2 := point-a
	var determinant := float(v0.x)*v1.z-float(v0.z)*v1.x
	if absf(determinant)<1e-16: return false
	var u := (float(v2.x)*v1.z-float(v2.z)*v1.x)/determinant
	var v := (float(v0.x)*v2.z-float(v0.z)*v2.x)/determinant
	return u>=-.0000001 and v>=-.0000001 and u+v<=1.0000001

func clearance(path: PackedVector3Array) -> float:
	var minimum := INF
	last_clearance={}
	for index in path.size()-1:
		var a := path[index]
		var b := path[index+1]
		var flat := b-a-frame.y*(b-a).dot(frame.y)
		var samples := maxi(1,ceili(flat.length()/.0005))
		for sample in samples+1:
			var point := a.lerp(b,sample/float(samples))
			var height := height_at(point)
			if is_finite(height):
				var gap := point.dot(frame.y)-height+CONTACT_PAD
				if gap<minimum:
					minimum=gap
					last_clearance={"segment":index,"point":str(point),"height":height,"gap":gap}
	return minimum

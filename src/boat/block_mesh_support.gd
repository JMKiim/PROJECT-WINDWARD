extends RefCounted

## Surface samples of one rigid block against actual upward hull/fitting
## envelopes and the existing finite tiller tube. Cached static inspection;
## undercuts, interlocking joints and general rigid-body collision are excluded.
const SURFACE := preload("res://src/boat/hull_rope_support.gd")
var points := PackedVector3Array()
var supports := []
var up := Vector3.UP
var tiller_inverse := Transform3D.IDENTITY
var tiller_enabled := false
var queries := 0
var exact_queries := 0
var corners := PackedVector3Array()
var tree := []
var witness_index := -1

func set_body(body: Node3D) -> void:
	set_body_faces(body_faces(body))

static func body_faces(body: Node3D) -> PackedVector3Array:
	var faces := PackedVector3Array()
	_collect_faces(body,body.global_transform.affine_inverse(),faces)
	return faces

static func _collect_faces(node: Node3D,inverse: Transform3D,faces: PackedVector3Array) -> void:
	if node is MeshInstance3D and node.mesh!=null:
		var frame := inverse*node.global_transform
		for point in node.mesh.get_faces(): faces.append(frame*point)
	for child in node.get_children():
		if child is Node3D: _collect_faces(child,inverse,faces)

func set_body_faces(faces: PackedVector3Array,cancelled := Callable()) -> void:
	points.clear()
	tree.clear()
	corners.clear()
	witness_index=-1
	if faces.size()%3!=0: return
	var seen := {}
	for index in range(0,faces.size(),3):
		if index%192==0 and cancelled.is_valid() and cancelled.call():
			points.clear()
			return
		for edge in [[faces[index],faces[index+1]],[faces[index+1],faces[index+2]],[faces[index+2],faces[index]]]:
			var count := maxi(1,ceili(edge[0].distance_to(edge[1])/.003))
			for sample in count:
				var point: Vector3=edge[0].lerp(edge[1],sample/float(count))
				var key := Vector3i(roundi(point.x*1000000),roundi(point.y*1000000),roundi(point.z*1000000))
				if not seen.has(key):
					seen[key]=true
					points.append(point)
	tree.clear()
	if not points.is_empty():
		var indices := []
		for index in points.size(): indices.append(index)
		if _build_tree(indices,cancelled)<0:
			points.clear()
			tree.clear()
			return
	witness_index=-1
	corners.clear()
	if not points.is_empty():
		var box := AABB(points[0],Vector3.ZERO)
		for point in points: box=box.expand(point)
		for x in [box.position.x,box.end.x]:
			for y in [box.position.y,box.end.y]:
				for z in [box.position.z,box.end.z]: corners.append(Vector3(x,y,z))

func add_surface(mesh: Mesh,frame: Transform3D,gravity: Vector3,label: String,cell_size := SURFACE.CELL) -> bool:
	return add_surface_faces(mesh.get_faces() if mesh!=null else PackedVector3Array(),frame,gravity,label,cell_size)

func add_surface_faces(faces: PackedVector3Array,frame: Transform3D,gravity: Vector3,label: String,cell_size := SURFACE.CELL) -> bool:
	if not supports.is_empty() and up.distance_to(-gravity.normalized())>.000001: return false
	var support := SURFACE.new()
	if not support.setup_faces(faces,frame,gravity,.000001,cell_size): return false
	up=-gravity.normalized()
	var ceilings := {}
	for key: Vector2i in support.cells:
		var ceiling := -INF
		for index: int in support.cells[key]:
			var triangle: Dictionary=support.triangles[index]
			var height: float=maxf(triangle.a.y,maxf(triangle.b.y,triangle.c.y))+support.radius
			if cell_size<.01:
				var lower := Vector2(key)*cell_size
				var upper := lower+Vector2.ONE*cell_size
				if not SURFACE.projected_overlap(triangle,lower,upper): continue
				var n: Vector3=triangle.n
				if n.y>.000001:
					var x := lower.x if n.x>=0 else upper.x
					var z := lower.y if n.z>=0 else upper.y
					height=minf(height,(triangle.d-n.x*x-n.z*z)/n.y)
			ceiling=maxf(ceiling,height)
		ceilings[key]=ceiling
	supports.append({"surface":support,"label":label,"ceilings":ceilings})
	return true

func _bounds(frame: Transform3D) -> AABB:
	var box := AABB(frame*corners[0],Vector3.ZERO)
	for corner in corners: box=box.expand(frame*corner)
	return box

func _build_tree(indices: Array,cancelled := Callable()) -> int:
	if cancelled.is_valid() and cancelled.call(): return -1
	var box := AABB(points[indices[0]],Vector3.ZERO)
	for index: int in indices: box=box.expand(points[index])
	var slot := tree.size()
	tree.append({"box":box,"indices":[],"left":-1,"right":-1})
	if indices.size()<=12:
		tree[slot].indices=indices
	else:
		var axis := box.size.max_axis_index()
		indices.sort_custom(func(a: int,b: int) -> bool: return points[a][axis]<points[b][axis])
		var middle := indices.size()/2
		tree[slot].left=_build_tree(indices.slice(0,middle),cancelled)
		if tree[slot].left<0: return -1
		tree[slot].right=_build_tree(indices.slice(middle),cancelled)
		if tree[slot].right<0: return -1
	return slot

static func _transformed_box(box: AABB,pose: Transform3D) -> AABB:
	var center := pose*box.get_center()
	var half := box.size*.5
	var extent := pose.basis.x.abs()*half.x+pose.basis.y.abs()*half.y+pose.basis.z.abs()*half.z
	return AABB(center-extent,extent*2)

func _lower_bound(box: AABB,pose: Transform3D) -> float:
	var result := INF
	for entry: Dictionary in supports:
		var surface: RefCounted=entry.surface
		var frame := Transform3D(surface.frame.transposed(),Vector3.ZERO)*pose
		var world := _transformed_box(box,frame)
		if surface.cell_size<.01:
			# Small fittings use fine precomputed cell ceilings. Enumerating
			# every triangle again at each tree node defeats their spatial grid.
			var ceiling := -INF
			for x in range(floori(world.position.x/surface.cell_size),floori(world.end.x/surface.cell_size)+1):
				for z in range(floori(world.position.z/surface.cell_size),floori(world.end.z/surface.cell_size)+1):
					ceiling=maxf(ceiling,entry.ceilings.get(Vector2i(x,z),-INF))
			result=minf(result,world.position.y-ceiling)
			continue
		var center := frame*box.get_center()
		var half := box.size*.5
		var seen := {}
		for x in range(floori(world.position.x/surface.cell_size),floori(world.end.x/surface.cell_size)+1):
			for z in range(floori(world.position.z/surface.cell_size),floori(world.end.z/surface.cell_size)+1):
				for index: int in surface.cells.get(Vector2i(x,z),PackedInt32Array()):
					if seen.has(index): continue
					seen[index]=true
					var triangle: Dictionary=surface.triangles[index]
					if world.end.x<triangle.lo.x or world.position.x>triangle.hi.x or world.end.z<triangle.lo.y or world.position.z>triangle.hi.y: continue
					if not SURFACE.projected_overlap(triangle,Vector2(world.position.x,world.position.z),Vector2(world.end.x,world.end.z)): continue
					var gap: float=world.position.y-maxf(triangle.a.y,maxf(triangle.b.y,triangle.c.y))-surface.radius
					var n: Vector3=triangle.n
					if n.y>.000001:
						# Project the original oriented body box onto the plane:
						# world axis bounds lose x/y correlation on a heeled deck.
						var local_normal := frame.basis.transposed()*n
						gap=maxf(gap,(n.dot(center)-local_normal.abs().dot(half)-triangle.d)/n.y)
					result=minf(result,gap)
	if tiller_enabled:
		var world := _transformed_box(box,tiller_inverse*pose)
		var x := maxf(0,maxf(world.position.x,-world.end.x))
		var y := maxf(0,maxf(world.position.y,-world.end.y))
		var z := maxf(0,maxf(world.position.z-.490,-.490-world.end.z))
		result=minf(result,Vector3(x,y,z).length()-.0128)
	return result

func _point_gap(point: Vector3,limit: float) -> Dictionary:
	var gap := limit
	var name := ""
	for entry: Dictionary in supports:
		var position: Vector3=entry.surface.frame.transposed()*point
		var key := Vector2i(floori(position.x/entry.surface.cell_size),floori(position.z/entry.surface.cell_size))
		if position.y-entry.ceilings.get(key,-INF)+SURFACE.CONTACT_PAD>=gap: continue
		var height: float=entry.surface.height_at(point)
		if not is_finite(height): continue
		var distance := point.dot(up)-height+SURFACE.CONTACT_PAD
		if distance<gap:
			gap=distance
			name=entry.label
	if tiller_enabled:
		var p := tiller_inverse*point
		var distance := p.distance_to(Vector3(0,0,clampf(p.z,-.490,.490)))-.0128
		if distance<gap:
			gap=distance
			name="tiller"
	return {"gap":gap,"surface":name,"point":point}

func interval_clear(rest: Transform3D,pivot: Vector3,axis: Vector3,first: float,last: float,guard: float) -> bool:
	# Exact coordinate extrema of the rotating body box bound the whole arc,
	# so the swivel can skip empty space without increasing its contact step.
	var low := minf(first,last)
	var high := maxf(first,last)
	var lower := Vector3(INF,INF,INF)
	var upper := -lower
	for corner in corners:
		var offset := rest*corner-pivot
		var center := pivot+axis*axis.dot(offset)
		var cosine := offset-axis*axis.dot(offset)
		var sine := axis.cross(offset)
		for coordinate in 3:
			var values := [center[coordinate]+cosine[coordinate]*cos(low)+sine[coordinate]*sin(low),center[coordinate]+cosine[coordinate]*cos(high)+sine[coordinate]*sin(high)]
			var peak := atan2(sine[coordinate],cosine[coordinate])
			for k in range(-2,3):
				var angle := peak+k*PI
				if angle>=low and angle<=high: values.append(center[coordinate]+cosine[coordinate]*cos(angle)+sine[coordinate]*sin(angle))
			for value: float in values:
				lower[coordinate]=minf(lower[coordinate],value)
				upper[coordinate]=maxf(upper[coordinate],value)
	return _lower_bound(AABB(lower,upper-lower).grow(.0000003),Transform3D.IDENTITY)>=guard

func query(pose: Transform3D,precise := false) -> Dictionary:
	queries+=1
	if tree.is_empty() or supports.is_empty(): return {"valid":false,"gap":NAN}
	var bound := _lower_bound(tree[0].box,pose)
	if not precise and bound>.003:
		return {"valid":true,"gap":bound if is_finite(bound) else 1000.0,"broad_phase_only":true}
	exact_queries+=1
	var result := {"valid":true,"gap":INF,"point":Vector3.ZERO,"surface":""}
	if witness_index>=0: result.merge(_point_gap(pose*points[witness_index],INF),true)
	var pending := [0]
	while not pending.is_empty():
		var node: Dictionary=tree[pending.pop_back()]
		# Keep every original surface sample; reject only subtrees whose
		# conservative bounds cannot improve the already measured witness.
		if _lower_bound(node.box,pose)>=result.gap: continue
		if node.left<0:
			for index: int in node.indices:
				var measured := _point_gap(pose*points[index],result.gap)
				if measured.gap<result.gap:
					result.merge(measured,true)
					witness_index=index
		else:
			var a := _lower_bound(tree[node.left].box,pose)
			var b := _lower_bound(tree[node.right].box,pose)
			pending.append(node.right if a<b else node.left)
			pending.append(node.left if a<b else node.right)
	if not is_finite(result.gap): result.gap=1000.0
	return result

func contact_constraints(pose: Transform3D,pivot: Vector3,maximum_gap: float) -> Array:
	# Preserve distinct witnesses: differentiating only the minimum gap mixes
	# normals when several cheek/edge points touch at the same time.
	var result := []
	if tree.is_empty(): return result
	var pending := [0]
	while not pending.is_empty():
		var node: Dictionary=tree[pending.pop_back()]
		if _lower_bound(node.box,pose)>maximum_gap: continue
		if node.left>=0:
			pending.append(node.left)
			pending.append(node.right)
			continue
		for index: int in node.indices:
			var point := pose*points[index]
			var contact := _point_gap(point,INF)
			if contact.gap>maximum_gap: continue
			var normal := Vector3.ZERO
			for coordinate in 3:
				var offset := Vector3.ZERO
				offset[coordinate]=.00001
				var before := _point_gap(point-offset,INF)
				var after := _point_gap(point+offset,INF)
				if is_finite(before.gap) and is_finite(after.gap): normal[coordinate]=(after.gap-before.gap)/.00002
			var gradient := (point-pivot).cross(normal)
			if not gradient.is_finite() or gradient.length_squared()<1e-12: continue
			result.append({"gap":contact.gap,"gradient":gradient,"normal":normal,"point":point,"surface":contact.surface})
	return result

func reference_query(pose: Transform3D,precise := false) -> Dictionary:
	queries+=1
	if points.is_empty() or supports.is_empty(): return {"valid":false,"gap":NAN}
	var candidates := []
	var bound := INF
	for entry: Dictionary in supports:
		var surface: RefCounted=entry.surface
		var box := _bounds(Transform3D(surface.frame.transposed(),Vector3.ZERO)*pose)
		var ceiling := -INF
		for x in range(floori(box.position.x/surface.cell_size),floori(box.end.x/surface.cell_size)+1):
			for z in range(floori(box.position.z/surface.cell_size),floori(box.end.z/surface.cell_size)+1):
				ceiling=maxf(ceiling,entry.ceilings.get(Vector2i(x,z),-INF))
		var gap_bound: float=box.position.y-ceiling
		bound=minf(bound,gap_bound)
		if precise or gap_bound<=.003: candidates.append(entry)
	var near_tiller := false
	if tiller_enabled:
		var box := _bounds(tiller_inverse*pose)
		var x := maxf(0,maxf(box.position.x,-box.end.x))
		var y := maxf(0,maxf(box.position.y,-box.end.y))
		var z := maxf(0,maxf(box.position.z-.490,-.490-box.end.z))
		var gap_bound := Vector3(x,y,z).length()-.0128
		bound=minf(bound,gap_bound)
		near_tiller=precise or gap_bound<=.003
	if candidates.is_empty() and not near_tiller:
		return {"valid":true,"gap":bound if is_finite(bound) else 1000.0,"broad_phase_only":true}
	exact_queries+=1
	var gap := INF
	var closest := Vector3.ZERO
	var name := ""
	for local in points:
		var point := pose*local
		for entry: Dictionary in candidates:
			var position: Vector3=entry.surface.frame.transposed()*point
			var key := Vector2i(floori(position.x/entry.surface.cell_size),floori(position.z/entry.surface.cell_size))
			var ceiling: float=entry.ceilings.get(key,-INF)
			# A sample above this cell's highest triangle cannot beat the
			# current minimum. This is a lower bound, not a contact shortcut.
			if position.y-ceiling+SURFACE.CONTACT_PAD>=gap: continue
			var height: float=entry.surface.height_at(point)
			if not is_finite(height): continue
			var distance := point.dot(up)-height+SURFACE.CONTACT_PAD
			if distance<gap:
				gap=distance
				closest=point
				name=entry.label
		if near_tiller:
			var p := tiller_inverse*point
			var distance := p.distance_to(Vector3(0,0,clampf(p.z,-.490,.490)))-.0128
			if distance<gap:
				gap=distance
				closest=point
				name="tiller"
	# An entirely outboard block has no floor underneath, not an invalid gap.
	return {"valid":true,"gap":gap if is_finite(gap) else 1000.0,"point":closest,"surface":name}

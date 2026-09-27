extends RefCounted

## Detached finite-radius contact field for the static deck inspection.
const TRIANGLES := preload("res://src/boat/mesh_triangle_source.gd")
var entries := []
var capsules := []
var capsule_tree := []
var capsule_radius := 0.0
var valid := true
var revision := 0

## Entry geometry is read-only after construction. Move through these atomic
## APIs so contact caches observe a revision even when counts stay unchanged.
## Restricted fields keep the previous numeric snapshot, not a live view.
func move_entries(frames: Array) -> bool:
	if not valid or frames.size()!=entries.size(): return false
	for frame in frames:
		if not frame is Transform3D or not frame.is_finite() or absf(frame.basis.determinant()-1)>.00001 or not (frame.basis.transposed()*frame.basis).is_equal_approx(Basis.IDENTITY): return false
	var changed := false
	for index in frames.size(): changed=changed or frames[index]!=entries[index].frame
	if not changed: return true
	var moved := []
	for index in frames.size():
		var entry: Dictionary=entries[index].duplicate()
		entry.frame=frames[index]
		entry.inverse=frames[index].affine_inverse()
		moved.append(entry)
	entries=moved
	revision+=1
	return true

func move_capsule(index: int,first: Vector3,last: Vector3) -> bool:
	if not valid or index<0 or index>=capsules.size() or not first.is_finite() or not last.is_finite(): return false
	if capsules[index].a==first and capsules[index].b==last: return true
	var moved: Dictionary=capsules[index].duplicate()
	moved.a=first
	moved.b=last
	moved.box=AABB(first,Vector3.ZERO).expand(last)
	capsules[index]=moved
	_index_capsules()
	revision+=1
	return true

## Capture on the main thread; the returned arrays contain no scene objects.
static func capture_tree(node: Node3D,rig_inverse: Transform3D) -> Array:
	var records := []
	if node is MeshInstance3D and node.mesh!=null:
		records.append({"faces":TRIANGLES.faces(node.mesh),"frame":rig_inverse*node.global_transform,"label":str(node.get_path())})
	for child in node.get_children():
		if child is Node3D: records.append_array(capture_tree(child,rig_inverse))
	return records

func add_records(records: Array,cancelled := Callable()) -> bool:
	for record: Dictionary in records:
		if cancelled.is_valid() and cancelled.call():
			valid=false
			return false
		if not record.has_all(["faces","frame","label"]):
			valid=false
			return false
		add_faces(record.faces,record.frame,record.label,cancelled)
		if not valid: return false
	return valid

func restricted(region: AABB) -> RefCounted:
	var subset: RefCounted=get_script().new()
	subset.valid=valid
	subset.revision=revision
	for entry: Dictionary in entries:
		if region.intersects(entry.frame*entry.box): subset.entries.append(entry)
	for capsule: Dictionary in capsules:
		if region.intersects(capsule.box.grow(capsule.radius)): subset.capsules.append(capsule)
	subset._index_capsules()
	return subset

func add_capsules(points: PackedVector3Array,own_radius: float,label: String) -> void:
	if not is_finite(own_radius) or own_radius<=0:
		valid=false
		return
	for point in points:
		if not point.is_finite():
			valid=false
			return
	for index in points.size()-1:
		capsules.append({"a":points[index],"b":points[index+1],"radius":own_radius,"box":AABB(points[index],Vector3.ZERO).expand(points[index+1]),"label":label})
	_index_capsules()
	revision+=1

func _index_capsules() -> void:
	capsule_tree.clear()
	capsule_radius=0
	var indices := []
	for index in capsules.size():
		indices.append(index)
		capsule_radius=maxf(capsule_radius,capsules[index].radius)
	if not indices.is_empty(): _build(capsule_tree,capsules,indices)

func _near_capsules(point: Vector3,distance: float) -> Array:
	var result := []
	if capsule_tree.is_empty(): return result
	var pending := [0]
	var squared := distance*distance
	while not pending.is_empty():
		var node: Dictionary=capsule_tree[pending.pop_back()]
		if _box_distance_squared(node.box,point)>squared: continue
		if node.left>=0:
			pending.append(node.left)
			pending.append(node.right)
		else: result.append_array(node.indices)
	return result

func add_tree(node: Node3D,rig_inverse: Transform3D) -> void:
	add_records(capture_tree(node,rig_inverse))

func add_faces(faces: PackedVector3Array,frame: Transform3D,label: String,cancelled := Callable()) -> void:
	if faces.is_empty() or faces.size()%3!=0 or not frame.is_finite() or absf(frame.basis.determinant())<1e-12:
		valid=false
		return
	for point in faces:
		if not point.is_finite():
			valid=false
			return
	# Euclidean distances are only invariant under rigid transforms. Bake
	# scale/shear into the numeric vertices instead of scaling the rope radius.
	if not (frame.basis.transposed()*frame.basis).is_equal_approx(Basis.IDENTITY):
		faces=frame*faces
		frame=Transform3D.IDENTITY
	var triangles := []
	var volume := 0.0
	var box := AABB(faces[0],Vector3.ZERO)
	for index in range(0,faces.size(),3):
		if index%192==0 and cancelled.is_valid() and cancelled.call():
			valid=false
			return
		var a := faces[index]
		var b := faces[index+1]
		var c := faces[index+2]
		var normal := (b-a).cross(c-a)
		volume+=a.dot(b.cross(c))
		box=box.expand(a).expand(b).expand(c)
		if normal.length_squared()<1e-24: continue
		triangles.append({"a":a,"b":b,"c":c,"normal":normal.normalized(),"box":AABB(a,Vector3.ZERO).expand(b).expand(c)})
	var nodes := []
	var indices := []
	if triangles.is_empty():
		valid=false
		return
	for index in triangles.size(): indices.append(index)
	if _build(nodes,triangles,indices,cancelled)<0:
		valid=false
		return
	entries.append({"triangles":triangles,"tree":nodes,"frame":frame,"inverse":frame.affine_inverse(),"box":box,"winding":signf(volume),"label":label})
	revision+=1

static func _build(nodes: Array,triangles: Array,indices: Array,cancelled := Callable()) -> int:
	if cancelled.is_valid() and cancelled.call(): return -1
	var box: AABB=triangles[indices[0]].box
	var centres := AABB(box.get_center(),Vector3.ZERO)
	for index: int in indices:
		var bounds: AABB=triangles[index].box
		box=box.merge(bounds)
		centres=centres.expand(bounds.get_center())
	var slot := nodes.size()
	nodes.append({"box":box,"left":-1,"right":-1,"indices":[]})
	if indices.size()<=12:
		nodes[slot].indices=indices
	else:
		# A spatial midpoint partition is linear at each level. Sorting every
		# subtree through a script comparator was dominating snapshot setup.
		# Both children still bound every original triangle exactly.
		var axis := centres.size.max_axis_index()
		var split: float=centres.get_center()[axis]
		var first := []
		var last := []
		for index: int in indices:
			if triangles[index].box.get_center()[axis]<split: first.append(index)
			else: last.append(index)
		if first.size()<indices.size()/16 or last.size()<indices.size()/16 or first.is_empty() or last.is_empty():
			var middle := indices.size()/2
			first=indices.slice(0,middle)
			last=indices.slice(middle)
		nodes[slot].left=_build(nodes,triangles,first,cancelled)
		if nodes[slot].left<0: return -1
		nodes[slot].right=_build(nodes,triangles,last,cancelled)
		if nodes[slot].right<0: return -1
	return slot

static func _box_distance_squared(box: AABB,point: Vector3) -> float:
	var delta := Vector3(maxf(0,maxf(box.position.x-point.x,point.x-box.end.x)),maxf(0,maxf(box.position.y-point.y,point.y-box.end.y)),maxf(0,maxf(box.position.z-point.z,point.z-box.end.z)))
	return delta.length_squared()

func query(point: Vector3,radius: float,limit := .02) -> Dictionary:
	var result := {"gap":limit,"point":point,"normal":Vector3.ZERO,"mesh":""}
	for capsule_index: int in _near_capsules(point,radius+capsule_radius+maxf(0,limit)):
		var capsule: Dictionary=capsules[capsule_index]
		if _box_distance_squared(capsule.box,point)>pow(radius+capsule.radius+maxf(0,result.gap),2): continue
		var nearest := Geometry3D.get_closest_point_to_segment(point,capsule.a,capsule.b)
		var delta := point-nearest
		var gap: float=delta.length()-radius-capsule.radius
		if gap<result.gap:
			var normal := delta.normalized()
			if normal.is_zero_approx():
				var axis: Vector3=(capsule.b-capsule.a).normalized()
				normal=axis.cross(Vector3.UP if absf(axis.y)<.9 else Vector3.RIGHT).normalized()
				if normal.is_zero_approx(): normal=Vector3.RIGHT
			result={"gap":gap,"point":nearest+normal*capsule.radius,"normal":normal,"mesh":capsule.label}
	for entry: Dictionary in entries:
		var p: Vector3=entry.inverse*point
		if _box_distance_squared(entry.box,p)>pow(radius+maxf(0,result.gap),2): continue
		# Exterior queries only need a surface closer than the requested cap.
		# An interior point still needs its exact nearest surface/depth. Never
		# infer inside/outside from a nearest face at an acute corner.
		var side := -1.0 if _inside(entry,p) else 1.0
		var squared := INF if side<0 else pow(radius+maxf(0,result.gap),2)
		var found := false
		var nearest := Vector3.ZERO
		var normal := Vector3.ZERO
		var pending := [0]
		while not pending.is_empty():
			var node: Dictionary=entry.tree[pending.pop_back()]
			if _box_distance_squared(node.box,p)>squared: continue
			if node.left>=0:
				var a := _box_distance_squared(entry.tree[node.left].box,p)
				var b := _box_distance_squared(entry.tree[node.right].box,p)
				pending.append(node.right if a<b else node.left)
				pending.append(node.left if a<b else node.right)
				continue
			for index: int in node.indices:
				var triangle: Dictionary=entry.triangles[index]
				if _box_distance_squared(triangle.box,p)>squared: continue
				var q := _triangle_point(p,triangle.a,triangle.b,triangle.c)
				var distance := p.distance_squared_to(q)
				if distance<squared:
					found=true
					squared=distance
					nearest=q
					normal=triangle.normal*entry.winding
		# A single incident face normal is not an inside test at a sharp
		# corner. At a narrow neck it can mark points centimetres outside as
		# interior. Use solid ray parity, with exact shared-edge hit merging.
		if not found: continue
		var gap := sqrt(squared)*side-radius
		if gap>=result.gap: continue
		if squared>1e-18: normal=(p-nearest).normalized()*side
		result={"gap":gap,"point":entry.frame*nearest,"normal":entry.frame.basis*normal,"mesh":entry.label}
	return result

static func _ray_box(box: AABB,point: Vector3,direction: Vector3,length: float) -> bool:
	var low := 0.0
	var high := length
	for axis in 3:
		var a: float=(box.position[axis]-point[axis])/direction[axis]
		var b: float=(box.end[axis]-point[axis])/direction[axis]
		low=maxf(low,minf(a,b))
		high=minf(high,maxf(a,b))
		if low>high+.0000001: return false
	return true

static func _inside(entry: Dictionary,point: Vector3) -> bool:
	if not entry.box.has_point(point): return false
	var direction := Vector3(1,.137,.071).normalized()
	var length: float=entry.box.size.length()*4+.001
	var hits := []
	var pending := [0]
	while not pending.is_empty():
		var node: Dictionary=entry.tree[pending.pop_back()]
		if not _ray_box(node.box,point,direction,length): continue
		if node.left>=0:
			pending.append(node.left)
			pending.append(node.right)
			continue
		for index: int in node.indices:
			var triangle: Dictionary=entry.triangles[index]
			var hit: Variant=Geometry3D.segment_intersects_triangle(Vector3.ZERO,direction*length*1000,(triangle.a-point)*1000,(triangle.b-point)*1000,(triangle.c-point)*1000)
			if hit!=null: hits.append(hit.length()*.001)
	hits.sort()
	var crossings := 0
	var previous := -INF
	for distance: float in hits:
		if distance-previous>.00000005:
			crossings+=1
			previous=distance
	return crossings%2==1

func project(point: Vector3,radius: float) -> Dictionary:
	for iteration in 12:
		var contact := query(point,radius,.00006)
		if contact.gap>=.00004: return {"valid":true,"point":point}
		point+=contact.normal*(.00005-contact.gap)
	return {"valid":false,"point":point,"contact":query(point,radius)}

static func _triangle_point(point: Vector3,a: Vector3,b: Vector3,c: Vector3) -> Vector3:
	var ab := b-a
	var ac := c-a
	var ap := point-a
	# The region determinants have units m^4. An absolute 1e-20 cutoff
	# incorrectly reduced small/thin valid triangles to their first vertex.
	# Scalar products use double intermediates before the Vector3 result.
	var d1 := _dot64(ab,ap)
	var d2 := _dot64(ac,ap)
	if d1<=0 and d2<=0: return a
	var bp := point-b
	var d3 := _dot64(ab,bp)
	var d4 := _dot64(ac,bp)
	if d3>=0 and d4<=d3: return b
	var vc := d1*d4-d3*d2
	if vc<=0 and d1>=0 and d3<=0: return a+ab*(d1/(d1-d3)) if d1>d3 else a
	var cp := point-c
	var d5 := _dot64(ab,cp)
	var d6 := _dot64(ac,cp)
	if d6>=0 and d5<=d6: return c
	var vb := d5*d2-d1*d6
	if vb<=0 and d2>=0 and d6<=0: return a+ac*(d2/(d2-d6)) if d2>d6 else a
	var va := d3*d6-d5*d4
	if va<=0 and d4-d3>=0 and d5-d6>=0: return b+(c-b)*(d4-d3)/(d4-d3+d5-d6)
	var total := va+vb+vc
	if total<=0:
		var closest := a
		var squared := point.distance_squared_to(a)
		for edge in [[a,b],[b,c],[c,a]]:
			var candidate := Geometry3D.get_closest_point_to_segment(point,edge[0],edge[1])
			if point.distance_squared_to(candidate)<squared:
				closest=candidate
				squared=point.distance_squared_to(candidate)
		return closest
	return a+ab*(vb/total)+ac*(vc/total)

static func _dot64(a: Vector3,b: Vector3) -> float:
	return a.x*b.x+a.y*b.y+a.z*b.z

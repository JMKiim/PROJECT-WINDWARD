extends RefCounted
const FIELD := preload("res://src/boat/mesh_rope_obstacle.gd")
const GEOMETRY := preload("res://src/boat/triangle_contact_geometry.gd")
var body := {}
var exact_pairs := 0
var cache_pose := Transform3D.IDENTITY
var cache_limit := -1.0
var cache := []
var cache_field: RefCounted
var cache_counts := Vector2i.ZERO
var cache_revision := -1

func setup(faces: PackedVector3Array,cancelled := Callable()) -> bool:
	var source := FIELD.new()
	source.add_faces(faces,Transform3D.IDENTITY,"body",cancelled)
	if not source.valid or source.entries.is_empty(): return false
	body=source.entries[0]
	cache_limit=-1
	return true

func contacts(pose: Transform3D,obstacles: RefCounted,limit: float) -> Array:
	var counts := Vector2i(obstacles.entries.size(),obstacles.capsules.size())
	if obstacles==cache_field and obstacles.revision==cache_revision and counts==cache_counts and pose==cache_pose and cache_limit>=limit:
		return cache.filter(func(row: Dictionary) -> bool: return row.gap<=limit)
	var result := []
	for entry: Dictionary in obstacles.entries:
		var frame: Transform3D=entry.inverse*pose
		var boxes := {}
		if GEOMETRY.box_distance_squared(frame*body.box,entry.box)>pow(limit+.0000002,2): continue
		var pending := [Vector2i(0,0)]
		while not pending.is_empty():
			var pair: Vector2i=pending.pop_back()
			var left: Dictionary=body.tree[pair.x]
			var right: Dictionary=entry.tree[pair.y]
			if not boxes.has(pair.x): boxes[pair.x]=frame*left.box
			var box: AABB=boxes[pair.x]
			if GEOMETRY.box_distance_squared(box,right.box)>pow(limit+.0000002,2): continue
			if left.left<0 and right.left<0:
				for first: int in left.indices:
					var triangle: Dictionary=body.triangles[first]
					var a: Vector3=frame*triangle.a
					var b: Vector3=frame*triangle.b
					var c: Vector3=frame*triangle.c
					var bounds := AABB(a,Vector3.ZERO).expand(b).expand(c)
					for last: int in right.indices:
						var other: Dictionary=entry.triangles[last]
						if GEOMETRY.box_distance_squared(bounds,other.box)>pow(limit+.0000002,2): continue
						exact_pairs+=1
						var witnesses := GEOMETRY.triangles(a,b,c,other.a,other.b,other.c)
						var delta := witnesses[0]-witnesses[1]
						var distance := delta.length()
						if distance>limit: continue
						var normal: Vector3=delta/distance if distance>1e-9 else other.normal*entry.winding
						result.append({"gap":distance,"point":entry.frame*witnesses[0],"normal":entry.frame.basis*normal,"surface":entry.label,"body_triangle":first,"obstacle_triangle":last})
			elif right.left<0 or (left.left>=0 and box.size.length_squared()>=right.box.size.length_squared()):
				pending.append(Vector2i(left.left,pair.y))
				pending.append(Vector2i(left.right,pair.y))
			else:
				pending.append(Vector2i(pair.x,right.left))
				pending.append(Vector2i(pair.x,right.right))
	for capsule: Dictionary in obstacles.capsules:
		var inverse := pose.affine_inverse()
		var a: Vector3=inverse*capsule.a
		var b: Vector3=inverse*capsule.b
		var box := AABB(a,Vector3.ZERO).expand(b).grow(capsule.radius)
		var pending := [0]
		while not pending.is_empty():
			var node: Dictionary=body.tree[pending.pop_back()]
			if GEOMETRY.box_distance_squared(node.box,box)>pow(limit+.0000002,2): continue
			if node.left>=0:
				pending.append(node.left)
				pending.append(node.right)
				continue
			for index: int in node.indices:
				var triangle: Dictionary=body.triangles[index]
				if GEOMETRY.box_distance_squared(triangle.box,box)>pow(limit+.0000002,2): continue
				exact_pairs+=1
				var witnesses := GEOMETRY.segment_triangle(a,b,triangle.a,triangle.b,triangle.c)
				var delta := witnesses[1]-witnesses[0]
				var gap: float=delta.length()-capsule.radius
				if gap>limit: continue
				result.append({"gap":gap,"point":pose*witnesses[1],"normal":pose.basis*delta.normalized(),"surface":capsule.label,"body_triangle":index})
	cache_pose=pose
	cache_limit=limit
	cache_field=obstacles
	cache_counts=counts
	cache_revision=obstacles.revision
	cache=result
	return result

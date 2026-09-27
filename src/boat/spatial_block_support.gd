extends RefCounted

## Surface witnesses against a finite 3D triangle/capsule contact field.
## This is not a certified triangle/triangle continuous collision solver.
const SAMPLES := preload("res://src/boat/block_mesh_support.gd")
var body := SAMPLES.new()
var field: RefCounted
var witness := -1
var queries := 0
var point_queries := 0
var bound_queries := 0
var distance_cache := {}
var cache_hits := 0
var field_revision := -1
var coherent_cache_enabled := false
var coherent_cache := {}
var coherent_hits := 0
const COHERENT_CELL := .003

func setup(faces: PackedVector3Array,obstacles: RefCounted,cancelled := Callable()) -> bool:
	body.set_body_faces(faces,cancelled)
	field=obstacles
	witness=-1
	distance_cache.clear()
	coherent_cache.clear()
	field_revision=-1
	return not body.points.is_empty() and field!=null and field.valid

func _synchronize_field() -> void:
	if field!=null and field_revision!=field.revision:
		distance_cache.clear()
		coherent_cache.clear()
		witness=-1
		field_revision=field.revision

func _distance(point: Vector3,limit: float) -> Dictionary:
	if distance_cache.has(point):
		var cached: Dictionary=distance_cache[point]
		if cached.gap<cached.limit or limit<=cached.limit:
			cache_hits+=1
			return _returned_distance(cached,point,limit)
	var cell := Vector3i.ZERO
	if coherent_cache_enabled:
		cell=Vector3i(floori(point.x/COHERENT_CELL),floori(point.y/COHERENT_CELL),floori(point.z/COHERENT_CELL))
		for sample: Dictionary in coherent_cache.get(cell,[]):
			# Every stored capped distance is a LOWER bound. The signed union
			# field is 1-Lipschitz: subtracting spatial displacement remains a
			# lower bound at this new point. The extra 2um only makes rejection
			# more conservative; near/inside witnesses still use exact geometry.
			if sample.gap-point.distance_to(sample.position)>limit+.000002:
				coherent_hits+=1
				return {"gap":limit,"point":point,"normal":Vector3.ZERO,"mesh":"","limit":limit}
	var queried_limit := limit+(.002 if coherent_cache_enabled else 0.0)
	var value: Dictionary=field.query(point,0,queried_limit)
	value["limit"]=queried_limit
	if coherent_cache_enabled:
		if coherent_cache.size()>4096: coherent_cache.clear()
		var samples: Array=coherent_cache.get(cell,[])
		if samples.size()>=4: samples.pop_front()
		samples.append({"position":point,"gap":value.gap})
		coherent_cache[cell]=samples
	if distance_cache.size()>65536: distance_cache.clear()
	distance_cache[point]=value
	return _returned_distance(value,point,limit)

func _returned_distance(value: Dictionary,point: Vector3,limit: float) -> Dictionary:
	# A padded but truncated search is still only a bound, not an exact
	# witness beyond the caller's cap. Keep the original capped API contract.
	if coherent_cache_enabled and value.gap>=value.limit and value.gap>limit:
		return {"gap":limit,"point":point,"normal":Vector3.ZERO,"mesh":"","limit":limit}
	return value

func _bound(box: AABB,pose: Transform3D,limit: float) -> float:
	bound_queries+=1
	var radius := box.size.length()*.5
	# Signed distance is 1-Lipschitz for the accepted solid field. A sphere
	# enclosing this rigid point node bounds every one of its witnesses.
	# A capped query must be ABOVE the rejection threshold after subtracting
	# the safety margin, otherwise every empty node survives the broad phase.
	return _distance(pose*box.get_center(),limit+radius+.000001).gap-radius-.0000005

func query(pose: Transform3D,maximum_gap := 1.0) -> Dictionary:
	_synchronize_field()
	queries+=1
	if body.tree.is_empty() or field==null or not field.valid or not is_finite(maximum_gap) or maximum_gap<=0: return {"valid":false,"gap":NAN}
	# An explicit finite band returns that cap when nothing is nearer. Signed
	# containment remains uncapped, so a far interior witness cannot be missed.
	var best := {"valid":true,"gap":maximum_gap,"point":Vector3.ZERO,"normal":Vector3.ZERO,"surface":""}
	if witness>=0: best.merge(_point(pose*body.points[witness],maximum_gap),true)
	var pending := [0]
	while not pending.is_empty():
		var node: Dictionary=body.tree[pending.pop_back()]
		if _bound(node.box,pose,best.gap)>best.gap: continue
		if node.left<0:
			for index: int in node.indices:
				var measured := _point(pose*body.points[index],best.gap)
				if measured.gap<best.gap:
					best.merge(measured,true)
					witness=index
		else:
			var a := _bound(body.tree[node.left].box,pose,best.gap)
			var b := _bound(body.tree[node.right].box,pose,best.gap)
			pending.append(node.right if a<b else node.left)
			pending.append(node.left if a<b else node.right)
	return best

func _point(point: Vector3,limit: float) -> Dictionary:
	point_queries+=1
	var value: Dictionary=_distance(point,limit)
	return {"gap":value.gap,"point":point,"normal":value.normal,"surface":value.mesh}

func contact_constraints(pose: Transform3D,pivot: Vector3,maximum_gap: float) -> Array:
	_synchronize_field()
	var result := []
	var pending := [0]
	while not pending.is_empty():
		var node: Dictionary=body.tree[pending.pop_back()]
		if _bound(node.box,pose,maximum_gap)>maximum_gap: continue
		if node.left>=0:
			pending.append(node.left)
			pending.append(node.right)
			continue
		for index: int in node.indices:
			var point: Vector3=pose*body.points[index]
			var contact := _point(point,maximum_gap+.000001)
			if contact.gap>maximum_gap or contact.normal.is_zero_approx(): continue
			contact["gradient"]=(point-pivot).cross(contact.normal)
			result.append(contact)
	return result

func reference_query(pose: Transform3D) -> Dictionary:
	var best := {"valid":true,"gap":1.0}
	for local: Vector3 in body.points:
		var measured: Dictionary=field.query(pose*local,0,best.gap)
		if measured.gap<best.gap: best.merge(measured,true)
	return best

extends RefCounted
## Exact elbow-circle partition against a finite torso capsule. All possible
## closest-pair boundary families are quartics in tan(angle/2); each selected
## interval is independently checked with the actual finite segment distance.
const POLY := preload("res://src/preview/tack/polynomial.gd")
static func guide(s: Vector3,w: Vector3,a: float,b: float,pole: Vector3,direction: Vector3,hips: Vector3,chest: Vector3,clearance := .1905,drop := .085,wrist_degrees := 44.5) -> Dictionary:
	var distance := s.distance_to(w)
	if distance>=a+b or distance<=absf(a-b): return {"valid":false,"reason":"exact elbow reach"}
	var axis := (w-s)/distance
	var along := (a*a-b*b+distance*distance)/(2*distance)
	var centre := s+axis*along
	var radius := sqrt(maxf(0,a*a-along*along))
	var u := pole-centre
	u=(u-axis*u.dot(axis)).normalized()
	if u.is_zero_approx(): return {"valid":false,"reason":"exact elbow guide singular"}
	var v := axis.cross(u)
	if _valid(centre+radius*u,s,w,direction,hips,chest,clearance,drop,wrist_degrees): return {"valid":true,"point":centre+radius*u,"exact_capsule":true}
	var cuts := PackedFloat64Array([0,TAU])
	for sign_ in [1.0,-1.0]:
		var ru: Vector3=radius*u*sign_
		var rv: Vector3=radius*v*sign_
		var offset_angle := 0.0 if sign_>0 else PI
		var elbow := [centre+ru,2*rv,centre-ru]
		# Elbow drop and the original wrist cone are linear support planes.
		for plane in [{"normal":Vector3.UP,"bound":s.y-drop},{"normal":direction,"bound":w.dot(direction)-b*cos(deg_to_rad(wrist_degrees))}]:
			var normal: Vector3=plane.normal
			var bound: float=plane.bound
			_add_cuts(cuts,PackedFloat64Array([normal.dot(elbow[0])-bound,normal.dot(elbow[1]),normal.dot(elbow[2])-bound]),offset_angle)
		var fore := [elbow[0]-w,elbow[1],elbow[2]-w]
		var body_axis := chest-hips
		for endpoint in [hips,chest]:
			var delta := [elbow[0]-endpoint,elbow[1],elbow[2]-endpoint]
			# Elbow/end sphere and elbow/interior body-line boundaries.
			_add_cuts(cuts,_subtract(_squared(delta),PackedFloat64Array([1,0,2,0,1]),clearance*clearance),offset_angle)
			if body_axis.length_squared()>.00000001:
				var line := []
				for vector: Vector3 in delta: line.append(vector.cross(body_axis))
				_add_cuts(cuts,_subtract(_squared(line),PackedFloat64Array([1,0,2,0,1]),clearance*clearance*body_axis.length_squared()),offset_angle)
			# Each body endpoint tangent to the finite forearm's supporting line.
			var point := []
			for vector: Vector3 in fore: point.append((endpoint-w).cross(vector))
			_add_cuts(cuts,_subtract(_squared(point),_squared(fore),clearance*clearance),offset_angle)
		# Interior/interior closest-pair boundary of the two supporting lines.
		if body_axis.length_squared()>.00000001:
			var normal_line := []
			var scalar := PackedFloat64Array()
			for vector: Vector3 in fore:
				var n := vector.cross(body_axis)
				normal_line.append(n)
				scalar.append((hips-w).dot(n))
			_add_cuts(cuts,_subtract(_scalar_squared(scalar),_squared(normal_line),clearance*clearance),offset_angle)
	cuts.sort()
	var selected := INF
	for index in cuts.size()-1:
		var low := cuts[index]
		var high := cuts[index+1]
		if high-low<.00000001: continue
		var middle := (low+high)*.5
		if not _valid(centre+radius*(u*cos(middle)+v*sin(middle)),s,w,direction,hips,chest,clearance,drop,wrist_degrees): continue
		var padding := minf(.0001,(high-low)*.1)
		var near := low+padding if low<TAU-high else high-padding
		if not _valid(centre+radius*(u*cos(near)+v*sin(near)),s,w,direction,hips,chest,clearance,drop,wrist_degrees):
			# Polynomial boundaries use double coefficients assembled from
			# float32 vectors. Refine INSIDE this known-valid interval against
			# the unchanged finite predicate; never relax its clearance/drop.
			var outside := near
			var inside := middle
			for refinement in 24:
				var candidate := (outside+inside)*.5
				if _valid(centre+radius*(u*cos(candidate)+v*sin(candidate)),s,w,direction,hips,chest,clearance,drop,wrist_degrees): inside=candidate
				else: outside=candidate
			near=inside+(middle-inside)*.001
		var angle := near if near<=PI else near-TAU
		if absf(angle)<absf(selected): selected=angle
	if not is_finite(selected): return {"valid":false,"reason":"exact finite torso/elbow intervals empty"}
	var point := centre+radius*(u*cos(selected)+v*sin(selected))
	if not _valid(point,s,w,direction,hips,chest,clearance,drop,wrist_degrees): return {"valid":false,"reason":"exact interval boundary residual"}
	return {"valid":true,"point":point,"exact_capsule":true,"angle":selected}
static func _valid(e: Vector3,s: Vector3,w: Vector3,direction: Vector3,a: Vector3,b: Vector3,clearance: float,drop := .085,wrist_degrees := 44.5) -> bool:
	if s.y-e.y<drop-.00000001: return false
	if (w-e).normalized().dot(direction)<cos(deg_to_rad(wrist_degrees))-.00000001: return false
	var pair := Geometry3D.get_closest_points_between_segments(e,w,a,b)
	return pair[0].distance_to(pair[1])>=clearance-.00000001
static func _squared(vectors: Array) -> PackedFloat64Array:
	var result := PackedFloat64Array([0,0,0,0,0])
	for i in 3:
		for j in 3:
			var a: Vector3=vectors[i]
			var b: Vector3=vectors[j]
			result[i+j]+=a.dot(b)
	return result
static func _scalar_squared(values: PackedFloat64Array) -> PackedFloat64Array:
	var result := PackedFloat64Array([0,0,0,0,0])
	for i in 3:
		for j in 3: result[i+j]+=values[i]*values[j]
	return result
static func _subtract(a: PackedFloat64Array,b: PackedFloat64Array,scale: float) -> PackedFloat64Array:
	var result := a.duplicate()
	for index in b.size(): result[index]-=b[index]*scale
	return result
static func _add_cuts(cuts: PackedFloat64Array,coefficients: PackedFloat64Array,offset: float) -> void:
	for root in POLY.roots(coefficients,-1,1): cuts.append(fposmod(offset+2*atan(root),TAU))

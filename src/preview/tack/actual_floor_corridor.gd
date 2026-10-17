extends RefCounted
## Conservative exterior boundary plus actual-height visibility. Empty
## spaces inside its convex shadow are navigable,not solid obstacles.
const SURFACE := preload("res://src/preview/tack/floor_corridor.gd")
var hull: MeshInstance3D
var caps := []
var polygon := PackedVector2Array()
var perimeter := PackedFloat64Array()
var cap_bounds := []
var cached_a := Vector3(INF,INF,INF)
var visible_a := []
var unresolved := 0
var reference_goal := Vector3.ZERO
var reference_a := Vector3(INF,INF,INF)
var reference_route := PackedVector2Array()
var reference_path := PackedVector3Array()
var last_route := PackedVector2Array()
var reference_unresolved := 0
var fixed_path := PackedVector3Array()
var fixed_length := 0.0
var fixed_clear := false
var vertices := PackedVector3Array()
func setup(value: MeshInstance3D,obstacles: Array,outline: PackedVector2Array,goal: Vector3) -> void:
	hull=value; caps=obstacles; polygon=outline
	reference_goal=goal; reference_a=Vector3(INF,INF,INF)
	perimeter=PackedFloat64Array([0.0])
	vertices=PackedVector3Array()
	for i in polygon.size():
		perimeter.append(perimeter[-1]+polygon[i].distance_to(polygon[(i+1)%polygon.size()]))
		vertices.append(Vector3(polygon[i].x,hull.cockpit_floor_y_at(polygon[i].x,polygon[i].y)+.006,polygon[i].y))
	cap_bounds=[]
	for cap in caps:
		var pad := Vector3.ONE*(float(cap[2])+.002)
		cap_bounds.append([cap[0].min(cap[1])-pad,cap[0].max(cap[1])+pad])
	cached_a=Vector3(INF,INF,INF)
	visible_a=[]
func _line(a: Vector3,b: Vector3,coarse := false) -> PackedVector3Array:
	if not coarse: return SURFACE.surface_points(a,b,PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z)]),hull)
	var points := PackedVector3Array([a])
	var count := maxi(2,ceili(a.distance_to(b)/.04))
	for i in range(1,count+1):
		var p := a.lerp(b,i/float(count))
		p.y=maxf(p.y,hull.cockpit_floor_y_at(p.x,p.z)+.006)
		points.append(p)
	return points
func _clear(points: PackedVector3Array) -> bool:
	for i in points.size()-1:
		var low := points[i].min(points[i+1])
		var high := points[i].max(points[i+1])
		for j in caps.size():
			var box: Array=cap_bounds[j]
			if low.x>box[1].x or high.x<box[0].x or low.y>box[1].y or high.y<box[0].y or low.z>box[1].z or high.z<box[0].z: continue
			var pair := Geometry3D.get_closest_points_between_segments(points[i],points[i+1],caps[j][0],caps[j][1])
			if pair[0].distance_to(pair[1])<float(caps[j][2])+.002: return false
	return true
func _vertex(i: int) -> Vector3:
	return vertices[i]
func _chain(a: Vector3,b: Vector3,route: PackedVector2Array) -> PackedVector3Array:
	var result := PackedVector3Array([a])
	for i in range(1,route.size()):
		var target := b if i==route.size()-1 else Vector3(route[i].x,hull.cockpit_floor_y_at(route[i].x,route[i].y)+.006,route[i].y)
		result.append_array(_line(result[-1],target).slice(1))
	return result
func path(a: Vector3,b: Vector3) -> PackedVector3Array:
	var measured := _cached_tail(a,b)
	if not measured.is_empty():
		var result := fixed_path.duplicate()
		result.append_array(measured.path.slice(1))
		unresolved=0
		return result
	return _exact_path(a,b)
func measure(a: Vector3,b: Vector3) -> Dictionary:
	var measured := _cached_tail(a,b)
	if not measured.is_empty():
		unresolved=0
		return {"length":fixed_length+measured.length,"end":measured.path[-1]}
	var result := _exact_path(a,b)
	return {"length":_length(result),"end":result[-1]}
func _length(points: PackedVector3Array) -> float:
	var result := 0.0
	for index in points.size()-1: result+=points[index].distance_to(points[index+1])
	return result
func _cached_tail(a: Vector3,b: Vector3) -> Dictionary:
	if a!=reference_a:
		reference_path=_exact_path(a,reference_goal)
		reference_route=last_route.duplicate()
		reference_unresolved=unresolved
		reference_a=a
		fixed_path=reference_path.duplicate()
		fixed_length=_length(fixed_path)
		fixed_clear=reference_unresolved==0 and _clear(fixed_path)
	# A single visible boundary chain belongs to the whole fixed pile.
	# Keep it during the length inverse instead of changing path topology
	# and rebuilding an all-vertex visibility solve at every scalar trial.
	if fixed_clear:
		var tail := _line(fixed_path[-1],b)
		if _clear(tail): return {"path":tail,"length":_length(tail)}
	return {}
func _exact_path(a: Vector3,b: Vector3) -> PackedVector3Array:
	unresolved=0
	last_route=PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z)])
	var direct := _line(a,b)
	if _clear(direct): return direct
	if a!=cached_a:
		visible_a=[]
		for i in polygon.size():
			if absf(polygon[i].x)>.68: continue
			if _clear(_line(a,_vertex(i),true)): visible_a.append(i)
		cached_a=a
	var visible_b := []
	for i in polygon.size():
		if absf(polygon[i].x)>.68: continue
		if _clear(_line(b,_vertex(i),true)): visible_b.append(i)
	var best := INF
	var selected := PackedInt32Array()
	for first: int in visible_a:
		for last: int in visible_b:
			for direction in [-1,1]:
				var length: float=perimeter[last]-perimeter[first] if direction==1 else perimeter[first]-perimeter[last]
				if length<0: length+=perimeter[-1]
				var cost: float=a.distance_to(_vertex(first))+length+b.distance_to(_vertex(last))
				if cost>=best: continue
				var safe := true
				var cursor := first
				while cursor!=last:
					cursor=posmod(cursor+direction,polygon.size())
					if absf(polygon[cursor].x)>.68: safe=false; break
				if safe: best=cost; selected=PackedInt32Array([first,last,direction])
	if selected.is_empty(): unresolved=1; return direct
	var route := PackedVector2Array([Vector2(a.x,a.z),polygon[selected[0]]])
	var cursor := selected[0]
	while cursor!=selected[1]:
		cursor=posmod(cursor+selected[2],polygon.size())
		route.append(polygon[cursor])
	route.append(Vector2(b.x,b.z))
	last_route=route
	var result := _chain(a,b,route)
	if not _clear(result): unresolved=1
	return result

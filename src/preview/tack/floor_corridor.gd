extends RefCounted
## Floor-only convex contact corridor. The same continuous obstacle path
## is used by the displayed curve and its material inverse.
static func outline(caps: Array,hull: MeshInstance3D,near_only := true) -> PackedVector2Array:
	var points := PackedVector2Array()
	for cap in caps:
		var a: Vector3=cap[0]
		var b: Vector3=cap[1]
		var r: float=cap[2]
		var outer: float=r/cos(PI/16)+.002
		# Only the capsule-axis portion near the actual moulded floor casts
		# an obstacle here. Projecting a high knee filled the empty rope pile.
		for step in 9:
			var centre: Vector3=a.lerp(b,step/8.0)
			if near_only:
				var maximum_floor := -INF
				for index in 16:
					var angle: float=TAU*index/16.0
					var xz := Vector2(centre.x,centre.z)+Vector2(cos(angle),sin(angle))*outer
					maximum_floor=maxf(maximum_floor,hull.cockpit_floor_y_at(xz.x,xz.y))
				if centre.y-maximum_floor>r+.015: continue
			for index in 16:
				var angle: float=TAU*index/16.0
				points.append(Vector2(centre.x,centre.z)+Vector2(cos(angle),sin(angle))*outer)
	if points.size()<3: return PackedVector2Array()
	var polygon := Geometry2D.convex_hull(points)
	if polygon[-1].distance_to(polygon[0])<.000001: polygon.resize(polygon.size()-1)
	return polygon
static func _orientation(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for i in polygon.size(): area+=polygon[i].cross(polygon[(i+1)%polygon.size()])
	return 1.0 if area>=0 else -1.0
static func _inside(p: Vector2,polygon: PackedVector2Array) -> bool:
	if polygon.size()<3: return false
	var sign_ := _orientation(polygon)
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i+1)%polygon.size()]
		if sign_*(b-a).cross(p-a)<-.00000001: return false
	return true
static func outside(p: Vector2,polygon: PackedVector2Array) -> Vector2:
	if not _inside(p,polygon): return p
	var sign_ := _orientation(polygon)
	var selected := p
	var best := INF
	for i in polygon.size():
		var a := polygon[i]
		var edge := polygon[(i+1)%polygon.size()]-a
		var q: Vector2=a+edge*clampf((p-a).dot(edge)/maxf(.00000001,edge.length_squared()),0,1)
		var normal: Vector2=(q-p).normalized()
		if normal.length()<.000001: normal=Vector2(edge.y,-edge.x).normalized()*sign_
		q+=normal*.003
		if absf(q.x)>.61 or q.y<.25 or q.y>1.33: continue
		if q.distance_squared_to(p)<best: best=q.distance_squared_to(p); selected=q
	return selected
static func _blocked(a: Vector2,b: Vector2,polygon: PackedVector2Array,sign_ := 0.0) -> bool:
	if polygon.size()<3: return false
	var low := 0.0
	var high := 1.0
	if is_zero_approx(sign_): sign_=_orientation(polygon)
	for i in polygon.size():
		var vertex := polygon[i]
		var edge := polygon[(i+1)%polygon.size()]-vertex
		var start: float=sign_*edge.cross(a-vertex)
		var delta: float=sign_*edge.cross(b-a)
		if absf(delta)<.0000000001:
			if start<=.000000001: return false
		elif delta>0: low=maxf(low,(.000000001-start)/delta)
		else: high=minf(high,(.000000001-start)/delta)
		if low>=high-.00000001: return false
	return high>0 and low<1 and high-low>.00000001
static func path(a: Vector2,b: Vector2,polygon: PackedVector2Array,wanted := 0) -> Dictionary:
	var sign_: float=_orientation(polygon) if polygon.size()>=3 else 1.0
	if polygon.size()<3 or not _blocked(a,b,polygon,sign_): return {"points":PackedVector2Array([a,b]),"winding":wanted}
	var visible_a := []
	var visible_b := []
	var perimeter := PackedFloat64Array([0.0])
	var unsafe_vertices := false
	for i in polygon.size():
		if not _blocked(a,polygon[i],polygon,sign_): visible_a.append(i)
		if not _blocked(b,polygon[i],polygon,sign_): visible_b.append(i)
		perimeter.append(perimeter[-1]+polygon[i].distance_to(polygon[(i+1)%polygon.size()]))
		if absf(polygon[i].x)>.68: unsafe_vertices=true
	var best := INF
	var selected := PackedInt32Array()
	for first: int in visible_a:
		for last: int in visible_b:
			for direction in [-1,1]:
				if wanted!=0 and direction!=wanted: continue
				var boundary: float=perimeter[last]-perimeter[first] if direction==1 else perimeter[first]-perimeter[last]
				if boundary<0: boundary+=perimeter[-1]
				var cost: float=a.distance_to(polygon[first])+boundary+polygon[last].distance_to(b)
				if cost>=best: continue
				var safe := true
				if unsafe_vertices:
					var cursor := first
					while cursor!=last:
						cursor=posmod(cursor+direction,polygon.size())
						if absf(polygon[cursor].x)>.68: safe=false; break
				if safe: best=cost; selected=PackedInt32Array([first,last,direction])
	if selected.is_empty():
		if wanted!=0: return path(a,b,polygon,0)
		return {"points":PackedVector2Array([a,b]),"winding":wanted}
	var result := PackedVector2Array([a,polygon[selected[0]]])
	var cursor := selected[0]
	while cursor!=selected[1]:
		cursor=posmod(cursor+selected[2],polygon.size())
		result.append(polygon[cursor])
	result.append(b)
	return {"points":result,"winding":selected[2]}
static func surface(a: Vector3,b: Vector3,polygon: PackedVector2Array,winding: int,hull: MeshInstance3D) -> PackedVector3Array:
	var routed: PackedVector2Array=path(Vector2(a.x,a.z),Vector2(b.x,b.z),polygon,winding).points
	return surface_points(a,b,routed,hull)
static func surface_points(a: Vector3,b: Vector3,routed: PackedVector2Array,hull: MeshInstance3D) -> PackedVector3Array:
	var total := 0.0
	for i in routed.size()-1: total+=routed[i].distance_to(routed[i+1])
	var travelled := 0.0
	var result := PackedVector3Array([a])
	for i in routed.size()-1:
		var distance: float=routed[i].distance_to(routed[i+1])
		var count := maxi(1,ceili(distance/.008))
		for part in range(1,count+1):
			var t: float=part/float(count)
			var xz: Vector2=routed[i].lerp(routed[i+1],t)
			var y: float=lerpf(a.y,b.y,(travelled+distance*t)/maxf(.000001,total))
			var point := Vector3(xz.x,maxf(y,hull.cockpit_floor_y_at(xz.x,xz.y)+.006),xz.y)
			_supported_edge(result,result[-1],point,hull,0)
		travelled+=distance
	return result
static func _supported_edge(result: PackedVector3Array,a: Vector3,b: Vector3,hull: MeshInstance3D,depth: int) -> void:
	var middle := a.lerp(b,.5)
	var surface: float=hull.cockpit_floor_y_at(middle.x,middle.z)
	if depth<6 and middle.y<surface+.005:
		middle.y=maxf(middle.y,surface+.006)
		_supported_edge(result,a,middle,hull,depth+1)
		_supported_edge(result,middle,b,hull,depth+1)
	else: result.append(b)

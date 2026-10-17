extends RefCounted
const CABLE := preload("res://src/boat/cylinder_cable_route.gd")
static func _patch(a: Vector3,b: Vector3,joint: Vector3,axis: Vector3,span: float,preferred := Vector3.DOWN) -> Dictionary:
	var y := (Vector3.UP-axis*axis.y).normalized()
	if y.length()<.000001: y=(Vector3.RIGHT-axis*axis.x).normalized()
	var frame := Transform3D(Basis(axis,y,axis.cross(y)),joint+axis*span*.5)
	var result := CABLE.route(frame,.020,a,b,false,false,preferred,span*.5)
	if result.valid: return result
	for cap in [0.0,span]:
		var centre: Vector3=joint+axis*cap
		var normal: Vector3=(a-centre).cross(b-centre).normalized()
		if normal.length()<.000001: continue
		var radial: Vector3=(a-centre).normalized()
		var sphere := Transform3D(Basis(normal,radial,normal.cross(radial)),centre)
		var candidate := CABLE.route(sphere,.020,a,b,true,false,axis*(-1 if cap==0 else 1))
		if not candidate.valid: continue
		var clear := true
		for i in candidate.path.size()-1:
			var pair := Geometry3D.get_closest_points_between_segments(candidate.path[i],candidate.path[i+1],joint,joint+axis*span)
			if pair[0].distance_to(pair[1])<.01999: clear=false; break
		if clear: return candidate
	return result
static func _body_clear(path: PackedVector3Array,caps: Array) -> bool:
	for i in path.size()-1:
		for cap in caps:
			var pair := Geometry3D.get_closest_points_between_segments(path[i],path[i+1],cap[0],cap[1])
			if pair[0].distance_to(pair[1])<float(cap[2])+.006: return false
	return true
static func route(path: PackedVector3Array,joint: Vector3,axis: Vector3,span: float,caps: Array=[],free_inside_vertices := false) -> Dictionary:
	if path.size()<2: return {"path":path,"unresolved":[]}
	var output := PackedVector3Array([path[0]])
	var unresolved := []
	var i := 0
	while i<path.size()-1:
		var a: Vector3=path[i]
		var next := i+1
		if free_inside_vertices:
			while next<path.size()-1:
				var nearest: Vector3=Geometry3D.get_closest_point_to_segment(path[next],joint,joint+axis*span)
				if path[next].distance_to(nearest)>=.02001: break
				next+=1
		var b: Vector3=path[next]
		var pair := Geometry3D.get_closest_points_between_segments(a,b,joint,joint+axis*span)
		if pair[0].distance_to(pair[1])>=.020: output.append(b); i=next; continue
		var patch := _patch(a,b,joint,axis,span)
		if patch.valid and not _body_clear(patch.path,caps): patch={"valid":false,"reason":"rod wrap body contact"}
		if not patch.valid:
			var alternate := _patch(a,b,joint,axis,span,Vector3.UP)
			if alternate.valid and _body_clear(alternate.path,caps): patch=alternate
		if patch.valid: output.append_array(patch.path.slice(1))
		else:
			# A fixed boundary inside the rod cannot be silently moved. Keep
			# its original evidence for the independent contact acceptance.
			unresolved.append({"segment":i,"reason":patch.reason,"a":a,"b":b})
			output.append_array(path.slice(i+1,next+1))
		i=next
	return {"path":output,"unresolved":unresolved}

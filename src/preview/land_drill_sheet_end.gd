extends RefCounted
const STOPPER := preload("res://src/boat/mainsheet_stopper.gd")
const RADIUS := .004
static func cut(path: PackedVector3Array,metres: float) -> PackedVector3Array:
	var result := PackedVector3Array([path[0]])
	var remaining := maxf(0,metres)
	for index in path.size()-1:
		var length := path[index].distance_to(path[index+1])
		if remaining<=length:
			result.append(path[index].lerp(path[index+1],remaining/maxf(.000001,length)))
			return result
		result.append(path[index+1])
		remaining-=length
	return result
static func place(endpoint: Vector3,hull: MeshInstance3D,actor: Node3D=null) -> PackedVector3Array:
	var shape := STOPPER.grounded_points()
	var ground := Basis(Vector3.UP,-PI*.5)
	var tangent := (ground*(shape[1]-shape[0])).normalized()
	var contact := 0.0
	var obstacle := INF
	var lateral := Vector3.FORWARD
	var capsules := []
	for cap in ([] if actor==null else [["Hips","UpperChest",.156],["LeftUpperLeg","LeftLowerLeg",.096],["RightUpperLeg","RightLowerLeg",.096],["LeftLowerLeg","LeftFoot",.068],["RightLowerLeg","RightFoot",.068],["LeftFoot","LeftToes",.055],["RightFoot","RightToes",.055]]):
		var a: Vector3=actor.bone_pose_boat(cap[0]).origin
		var b: Vector3=actor.bone_pose_boat(cap[1]).origin
		capsules.append([a,b,float(cap[2])+.006])
		var pair: PackedVector3Array=Geometry3D.get_closest_points_between_segments(endpoint,endpoint+Vector3.DOWN*.15,a,b)
		contact=maxf(contact,1-smoothstep(float(cap[2])+.025,float(cap[2])+.065,pair[0].distance_to(pair[1])))
		var score: float=pair[0].distance_to(pair[1])-float(cap[2])
		if score<obstacle:
			obstacle=score
			var delta := pair[0]-pair[1]
			delta.y=0
			lateral=delta.normalized() if delta.length()>.0001 else Vector3.FORWARD
	var axis: Vector3=Vector3.DOWN.lerp(lateral,contact).normalized()
	var hanging := Basis(Quaternion(tangent,axis))*ground
	var height: float=endpoint.y-hull.cockpit_floor_y_at(endpoint.x,endpoint.z)-RADIUS-.001
	var frame := ground.slerp(hanging,smoothstep(.02,.18,height))
	for iteration in 4:
		var deepest := 0.0
		var arm := Vector3.ZERO
		var goal := Vector3.ZERO
		for point in shape:
			var placed: Vector3=endpoint+frame*point
			for cap in capsules:
				var nearest := Geometry3D.get_closest_point_to_segment(placed,cap[0],cap[1])
				var delta := placed-nearest
				var depth: float=float(cap[2])-delta.length()
				if depth<=deepest or point.length()<.015: continue
				deepest=depth
				arm=placed-endpoint
				goal=nearest+delta.normalized()*(float(cap[2])+.008)-endpoint
		if deepest<=0 or arm.length()<.0001 or goal.length()<.0001: break
		frame=Basis(Quaternion(arm.normalized(),goal.normalized()))*frame
	var result := PackedVector3Array()
	for point in shape:
		var placed: Vector3=endpoint+frame*point
		placed.y=maxf(placed.y,hull.cockpit_floor_y_at(placed.x,placed.z)+RADIUS+.001)
		result.append(placed)
	return result

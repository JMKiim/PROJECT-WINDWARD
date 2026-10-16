extends RefCounted
## Finite sliding grip with an elbow-circle wrist cone. A seated pose uses
## a particular 44-degree forearm; hiking may use any angle inside that cone.
const ELBOW := preload("res://src/preview/land_drill_visual_elbow.gd")
static func _wrist_tangent(wrist: Vector3,hips: Vector3,chest: Vector3,first: Vector3,last: Vector3,radius: float) -> Vector3:
	var sweep := first.angle_to(last)
	var tangent := last-first*first.dot(last)
	if tangent.is_zero_approx(): return Vector3.ZERO
	tangent=tangent.normalized()
	var low := 0.0
	var high := sweep
	# Intersect the two exact support arcs. This finds the nearest body
	# tangent that contains the fixed wrist, not an angular pose search.
	for endpoint in [hips,chest]:
		var delta: Vector3=wrist-endpoint
		var a := delta.dot(first)
		var b := delta.dot(tangent)
		var magnitude := sqrt(a*a+b*b)
		if magnitude<radius+.000002: return Vector3.ZERO
		var middle := atan2(b,a)
		var half := acos(clampf((radius+.000002)/magnitude,-1,1))
		low=maxf(low,middle-half)
		high=minf(high,middle+half)
	if low>high: return Vector3.ZERO
	var angle := minf(high,low+.00001)
	return first*cos(angle)+tangent*sin(angle)
static func plan(actor: Node3D,s: Vector3,e: Vector3,w: Vector3,joint: Vector3,axis: Vector3,frame: Basis,scale: Vector3,offset: Vector3,fore: Vector3,half: float,discriminant: float) -> Dictionary:
	var a := s.distance_to(e)
	var b := e.distance_to(w)
	var centre := (s+offset-joint).dot(axis)
	var radial := joint-offset+axis*centre-s
	var room := (a+b-.002)*(a+b-.002)-radial.length_squared()
	if room<=0: return {"valid":false,"reason":"hiking shaft outside two-link reach"}
	var low := maxf(.25,centre-sqrt(room))
	var high := minf(actor.extension_span-.045,centre+sqrt(room))
	if low>high: return {"valid":false,"reason":"hiking finite grip interval empty"}
	# Continue the seated branch when it exists; otherwise its quadratic
	# centre is a preference, not a forced forearm or an altered limb length.
	var preferred := -half-sqrt(maxf(0,discriminant))
	var grip := clampf(preferred,low,high)
	var palm := joint+axis*grip
	var wrist := palm-offset
	# The hiking bank's elbow is a stable bend-side guide. Rotating a
	# fixed44-degree forearm with the fist made a tiny grip stroke sweep
	# an unnecessarily large arc near the wrist-cone boundary.
	var pole := (wrist-b*fore).lerp(e,smoothstep(0,.7,actor.hike))
	var hips: Vector3=actor.bone_pose_boat("Hips").origin
	var chest: Vector3=actor.bone_pose_boat("UpperChest").origin
	var direction := offset.normalized()
	var cone := {"normal":direction,"maximum":wrist.dot(direction)-b*cos(deg_to_rad(44.5))}
	var free := ELBOW.guide(s,wrist,a,b,pole,Vector3.ZERO,0,[cone])
	if not free.valid: return free
	var pair := Geometry3D.get_closest_points_between_segments(free.point,wrist,hips,chest)
	var near := Geometry3D.get_closest_point_to_segment(wrist,hips,chest)
	# The unchanged independent forearm guard is185mm+5mm. Keep0.5mm
	# construction reserve; do not reject an actually safe8mm gap solely
	# because the initial key-authoring preference had10mm reserve.
	var clearance := .1905
	var solved := free if pair[0].distance_to(pair[1])>=clearance else {"valid":false,"reason":"hiking body tangent infeasible"}
	if not solved.valid:
		var closest := INF
		var first := (pair[0]-pair[1]).normalized()
		var last := (wrist-near).normalized()
		var tangent := _wrist_tangent(wrist,hips,chest,first,last,clearance)
		for normal: Vector3 in [first,tangent,last]:
			if normal.is_zero_approx(): continue
			var support := maxf(hips.dot(normal),chest.dot(normal))+clearance
			var candidate := ELBOW.guide(s,wrist,a,b,pole,normal,support,[cone])
			if not candidate.valid: continue
			var difference: float=candidate.point.distance_squared_to(free.point)
			if difference<closest:
				closest=difference
				solved=candidate
	if not solved.valid:
		solved["grip_m"]=grip
		solved["wrist"]=wrist
		solved["palm"]=palm
		solved["free_gap_m"]=pair[0].distance_to(pair[1])-.185
		return solved
	return {"valid":true,"palm":palm,"wrist":wrist,"elbow":solved.point,"frame":frame,"scale":scale,"grip_metres":grip,"grip_interval":Vector2(low,high),"wrist_cone":true}

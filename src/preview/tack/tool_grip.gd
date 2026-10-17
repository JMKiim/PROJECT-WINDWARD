extends RefCounted
## Offline contact authoring: a specified finite shaft and grip, not an
## independently interpolated palm. No changes to the anatomical guards.
const CONTACT := preload("res://src/preview/land_drill/support/land_drill_grip_profile.gd")
const ELBOW := preload("res://src/preview/land_drill_visual_elbow.gd")
const FINITE := preload("res://src/preview/land_drill_hiking_grip.gd")
const POLY := preload("res://src/preview/tack/polynomial.gd")
const EXACT_ELBOW := preload("res://src/preview/tack/elbow_exact.gd")
const TOOL_SURFACE := preload("res://src/preview/tack/tool_surface.gd")
static var author_reserve := 0.0
static func solve(actor: Node3D,side: String,axis: Vector3,grip: float,reference: Basis,roll_delta := 0.0,pole_hint := Vector3(INF,INF,INF)) -> Dictionary:
	var joint: Vector3=actor.joint_boat()
	if grip<.25 or grip>actor.extension_span-.045: return {"valid":false,"reason":"finite grip"}
	var s: Vector3=actor.bone_pose_boat(side+"UpperArm").origin
	var e: Vector3=actor.bone_pose_boat(side+"LowerArm").origin
	var w: Vector3=actor.bone_pose_boat(side+"Hand").origin
	var scale: Vector3=actor.bone_pose_boat(side+"Hand").basis.get_scale()
	var a := s.distance_to(e)
	var b := e.distance_to(w)
	var frame := Basis(Quaternion((reference*CONTACT.tiller_axis(side)).normalized(),axis))*reference
	var offset: Vector3=frame*(CONTACT.TILLER_OFFSET*scale)
	var radial := offset-axis*offset.dot(axis)
	var toward := s-joint-axis*(s-joint).dot(axis)
	var roll := atan2((-toward).dot(axis.cross(radial)),(-toward).dot(radial))+roll_delta
	frame=Basis(axis,roll)*frame
	var result := _fixed_frame(actor,side,axis,grip,frame,pole_hint)
	result["roll"]=roll
	result["frame"]=frame
	return result
static func from_frame(actor: Node3D,side: String,axis: Vector3,grip: float,reference: Basis,pole_hint := Vector3(INF,INF,INF)) -> Dictionary:
	var selected := _fixed_frame(actor,side,axis,grip,reference,pole_hint)
	if selected.valid: return selected
	# Between authored keys, a fixed grip can leave the wrist-cone domain.
	# Intersect the shaft analytically with the upper-arm sphere at the
	# preferred forearm and four cone-boundary directions (two roots each).
	# This is a fixed-size contact construction, not angular pose sampling.
	var joint: Vector3=actor.joint_boat()
	var s: Vector3=actor.bone_pose_boat(side+"UpperArm").origin
	var e: Vector3=actor.bone_pose_boat(side+"LowerArm").origin
	var w: Vector3=actor.bone_pose_boat(side+"Hand").origin
	var a := s.distance_to(e)
	var b := e.distance_to(w)
	var frame := Basis(Quaternion((reference*CONTACT.tiller_axis(side)).normalized(),axis))*reference
	var scale: Vector3=actor.bone_pose_boat(side+"Hand").basis.get_scale()
	var offset: Vector3=frame*(CONTACT.TILLER_OFFSET*scale)
	var wrist := joint+axis*grip-offset
	var normal := offset.normalized()
	var preferred: Vector3=(wrist-(pole_hint if pole_hint.is_finite() else e)).normalized()
	var tangent := preferred-normal*preferred.dot(normal)
	if tangent.is_zero_approx(): tangent=axis-normal*axis.dot(normal)
	tangent=tangent.normalized()
	var other := normal.cross(tangent).normalized()
	var directions := [normal]
	for radial: Vector3 in [tangent,-tangent,other,-other]: directions.append(normal*cos(deg_to_rad(44))+radial*sin(deg_to_rad(44)))
	var best := INF
	for fore: Vector3 in directions:
		var shift := joint-offset-b*fore-s
		var half := shift.dot(axis)
		var discriminant := half*half-shift.length_squared()+a*a
		if discriminant<0: continue
		for distance in [-half-sqrt(discriminant),-half+sqrt(discriminant)]:
			if distance<.25 or distance>actor.extension_span-.045: continue
			var elbow: Vector3=joint+axis*distance-offset-b*fore
			var candidate := _fixed_frame(actor,side,axis,distance,frame,elbow)
			if not candidate.valid: continue
			var score: float=absf(distance-grip)+(candidate.elbow-(pole_hint if pole_hint.is_finite() else e)).length()
			if score<best:
				best=score
				selected=candidate
				selected["analytic_grip_adaptation"]=distance-grip
	if not selected.valid: return _rolled_contact(actor,side,axis,grip,frame,pole_hint)
	return selected
static func _rolled_contact(actor: Node3D,side: String,axis: Vector3,grip: float,reference: Basis,pole_hint: Vector3) -> Dictionary:
	# The grip roll is a physical freedom, not a fixed orientation sample.
	# For neutral/+44/-44 wrist, the elbow lies on a cone around the shaft.
	# Cone/upper-arm-sphere intersections give two exact roll roots and two
	# closed-form grip intervals. No runtime angular or body-pose search.
	var joint: Vector3=actor.joint_boat()
	var s: Vector3=actor.bone_pose_boat(side+"UpperArm").origin
	var e: Vector3=actor.bone_pose_boat(side+"LowerArm").origin
	var w: Vector3=actor.bone_pose_boat(side+"Hand").origin
	var a := s.distance_to(e)
	var b := e.distance_to(w)
	var scale: Vector3=actor.bone_pose_boat(side+"Hand").basis.get_scale()
	var offset: Vector3=reference*(CONTACT.TILLER_OFFSET*scale)
	var length := offset.length()
	var k := offset.normalized().dot(axis)
	var r := sqrt(maxf(0,1-k*k))
	var along := (s-joint).dot(axis)
	var radial := joint-s-axis*(joint-s).dot(axis)
	var radius := radial.length()
	if r<.00001 or radius<.00001: return {"valid":false,"reason":"singular roll contact cone"}
	var old_normal := (offset.normalized()-axis*k)/r
	var selected := {"valid":false,"reason":"no finite cone/sphere roll root"}
	var best := INF
	for degrees in [0.0,44.0,-44.0]:
		var angle := deg_to_rad(degrees)
		var shift := b*sin(angle)/r
		var c := length+b*(cos(angle)-k*sin(angle)/r)
		if c<=.00001: continue
		var radial_c := c*r
		var high_square := a*a-pow(radius-radial_c,2)
		if high_square<0: continue
		var low_square := maxf(0,a*a-pow(radius+radial_c,2))
		var centre := shift+along+c*k
		for interval: Vector2 in [Vector2(centre-sqrt(high_square),centre-sqrt(low_square)),Vector2(centre+sqrt(low_square),centre+sqrt(high_square))]:
			var low := maxf(.25,interval.x)+.00001
			var high := minf(actor.extension_span-.045,interval.y)-.00001
			if low>high: continue
			var distances := PackedFloat64Array([clampf(grip,low,high),(low+high)*.5])
			# Plane/cone/sphere intersections add the actual elbow-height and
			# body-support boundaries, not guessed grip subdivisions.
			var base := joint+axis*along
			var first := radial/radius
			var second := axis.cross(first).normalized()
			var planes := [{"normal":Vector3.UP,"bound":s.y-.086}]
			if pole_hint.is_finite(): planes.append({"normal":Vector3.UP,"bound":minf(s.y-.086,pole_hint.y)})
			var hips: Vector3=actor.bone_pose_boat("Hips").origin
			var chest: Vector3=actor.bone_pose_boat("UpperChest").origin
			var hint: Vector3=pole_hint if pole_hint.is_finite() else e
			var normal_body := (hint-Geometry3D.get_closest_point_to_segment(hint,hips,chest)).normalized()
			planes.append({"normal":normal_body,"bound":maxf(hips.dot(normal_body),chest.dot(normal_body))+.191})
			var denominator := 2*radial_c*radius
			var d := radius*radius+radial_c*radial_c-a*a
			for plane in planes:
				var normal: Vector3=plane.normal
				var h: float=normal.dot(base)-plane.bound
				var aa := normal.dot(axis)
				var bb := radial_c*normal.dot(first)
				var cc := radial_c*normal.dot(second)
				var p2 := -bb
				var p1 := denominator*aa
				var p0 := denominator*h-bb*d
				var polynomial := PackedFloat64Array([p0*p0+cc*cc*(d*d-denominator*denominator),2*p1*p0,p1*p1+2*p2*p0+2*cc*cc*d,2*p2*p1,p2*p2+cc*cc])
				for root in POLY.roots(polynomial,low-centre,high-centre): distances.append(centre+root)
			for distance: float in distances:
				var z := distance-centre
				var cosine := clampf((z*z+radius*radius+radial_c*radial_c-a*a)/(2*radial_c*radius),-1,1)
				for sign_value in [-1.0,1.0]:
					var normal: Vector3=first*cosine+second*sign_value*sqrt(maxf(0,1-cosine*cosine))
					var direction := axis*k+normal*r
					var roll := atan2(axis.dot(old_normal.cross(normal)),old_normal.dot(normal))
					var frame := Basis(axis,roll)*reference
					var fore := direction*(cos(angle)-k*sin(angle)/r)+axis*sin(angle)/r
					var elbow := joint+axis*distance-direction*length-fore*b
					var candidate := _fixed_frame(actor,side,axis,distance,frame,elbow)
					if not candidate.valid: continue
					var score: float=absf(distance-grip)+(candidate.elbow-(pole_hint if pole_hint.is_finite() else e)).length()+.15*absf(roll)
					if score<best:
						best=score
						selected=candidate
						selected["analytic_grip_adaptation"]=distance-grip
						selected["analytic_roll_adaptation"]=roll
	return selected
static func _fixed_frame(actor: Node3D,side: String,axis: Vector3,grip: float,reference: Basis,pole_hint := Vector3(INF,INF,INF)) -> Dictionary:
	var joint: Vector3=actor.joint_boat()
	if grip<.25 or grip>actor.extension_span-.045: return {"valid":false,"reason":"finite grip"}
	var s: Vector3=actor.bone_pose_boat(side+"UpperArm").origin
	var e: Vector3=actor.bone_pose_boat(side+"LowerArm").origin
	var w: Vector3=actor.bone_pose_boat(side+"Hand").origin
	var scale: Vector3=actor.bone_pose_boat(side+"Hand").basis.get_scale()
	var a := s.distance_to(e)
	var b := e.distance_to(w)
	var frame := Basis(Quaternion((reference*CONTACT.tiller_axis(side)).normalized(),axis))*reference
	var contact_offset: Vector3=TOOL_SURFACE.offset(grip)
	var offset: Vector3=frame*(contact_offset*scale)
	var palm := joint+axis*grip
	var wrist := palm-offset
	var reach_reserve: float=.010*author_reserve
	if author_reserve>0 and (wrist.distance_to(s)>a+b-reach_reserve or wrist.distance_to(s)<absf(a-b)+reach_reserve):
		return {"valid":false,"reason":"positive reach construction reserve"}
	var direction: Vector3=(frame*(CONTACT.TILLER_OFFSET*scale)).normalized()
	var drop := .085+.015*author_reserve
	var wrist_degrees := 44.5-4.5*author_reserve
	var cone := {"normal":direction,"maximum":wrist.dot(direction)-b*cos(deg_to_rad(wrist_degrees))}
	var hips: Vector3=actor.bone_pose_boat("Hips").origin
	var chest: Vector3=actor.bone_pose_boat("UpperChest").origin
	var pole: Vector3=pole_hint if pole_hint.is_finite() else s+Vector3(0,-.28,.28)
	var free := ELBOW.guide(s,wrist,a,b,pole,Vector3.ZERO,0,[cone,{"normal":Vector3.UP,"maximum":s.y-drop}])
	if not free.valid: return free
	var pair := Geometry3D.get_closest_points_between_segments(free.point,wrist,hips,chest)
	var clearance := .1905+.0065*author_reserve
	var solved := free if pair[0].distance_to(pair[1])>=clearance else {"valid":false,"reason":"body support"}
	if not solved.valid:
		# A merely feasible supporting half-space may select the opposite
		# side of the elbow circle. Use the nearest actual finite-capsule
		# interval, so the continued guide does not jump between surrogates.
		solved=EXACT_ELBOW.guide(s,wrist,a,b,pole,direction,hips,chest,clearance,drop,wrist_degrees)
	if not solved.valid: return solved
	return {"valid":true,"palm":palm,"wrist":wrist,"elbow":solved.point,"frame":frame,"scale":scale,"grip":grip,"offset":contact_offset,"wrist_offset":CONTACT.TILLER_OFFSET,"drop":s.y-solved.point.y,"wrist_deg":rad_to_deg((wrist-solved.point).angle_to(direction)),"body_gap":Geometry3D.get_closest_points_between_segments(solved.point,wrist,hips,chest)[0].distance_to(Geometry3D.get_closest_points_between_segments(solved.point,wrist,hips,chest)[1])-.185}

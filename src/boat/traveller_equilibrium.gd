extends RefCounted

## Slow-boundary stick/slip equilibrium on the geometric locked-line surface.
## The two exact line constraints are solved together with boom/mast loads.
## Coefficients and linked-block mass are provisional, not measured hardware.
const LINE := preload("res://src/boat/traveller_line_constraint.gd")
const FORCE_TOLERANCE := .12
const BLOCK_MASS := .18
var coupled: RefCounted
var line: RefCounted
var trace := []
var last := {}

func _init(value: RefCounted) -> void:
	coupled=value
	line=LINE.new(coupled.constraint.rig)

func _at(x: float,azimuth: float,target: float) -> Dictionary:
	var pose: Dictionary=line.fit(x,azimuth)
	if not pose.valid: return pose
	var load: Dictionary=coupled.solve(target)
	if not load.valid: return load
	if load.get("branch","")!="taut" or load.sheet_tension_n<=0:
		return {"valid":false,"reason":"unloaded traveller needs deck/support contact"}
	var frame: Dictionary=line.frame_at(x,azimuth)
	if not frame.valid: return {"valid":false,"reason":"traveller tangent outside supported geometry"}
	var force: Vector3=line.sheet_force(load.sheet_tension_n)+BLOCK_MASS*coupled.model.effective_gravity()
	var normal_load: float=force.dot(frame.normal)
	var drive: float=force.dot(frame.slide)
	var swivel: float=force.dot(frame.dp.normalized())
	return {"valid":true,"x":x,"azimuth":azimuth,"pose":pose,"load":load,"force":force,"normal_n":normal_load,"drive_n":drive,"swivel_n":swivel,"frame":frame}

func _align(x: float,azimuth: float,target: float) -> Dictionary:
	var result := {}
	var previous_angle := NAN
	var previous_residual := NAN
	var swivel_trace := []
	for iteration in 20:
		result=_at(x,azimuth,target)
		if not result.valid: return result
		swivel_trace.append({"angle":azimuth,"residual":result.swivel_n,"normal":result.normal_n,"sheet":result.load.sheet_tension_n})
		if absf(result.swivel_n)<=FORCE_TOLERANCE:
			if result.normal_n<=0: return {"valid":false,"reason":"traveller support would require a pushing rope"}
			return result
		# Rotation around the traveller span has no imposed dry-friction brake.
		# A bounded relaxed load-direction step avoids a full pose search.
		var force: Vector3=result.force
		var correction: float=result.swivel_n/maxf(1,Vector2(force.y,force.z).length())
		var step := correction*.7
		# Use the measured coupled swivel slope after the first step. The old
		# relaxed direction iteration oscillated when boom load changed rapidly
		# with swivel, even for ordinary trim. Keep the same force tolerance.
		if is_finite(previous_angle) and absf(azimuth-previous_angle)>.00001:
			var slope: float=(result.swivel_n-previous_residual)/(azimuth-previous_angle)
			if slope<-.05: step=-result.swivel_n/slope
		previous_angle=azimuth
		previous_residual=result.swivel_n
		azimuth+=clampf(step,-.15,.15)
		if absf(azimuth)>deg_to_rad(70): return {"valid":false,"reason":"loaded traveller swivel reaches domain boundary"}
	return {"valid":false,"reason":"traveller swivel residual did not converge","residual":result.get("swivel_n",INF),"swivel_trace":swivel_trace}

func solve(target: float,static_friction: float) -> Dictionary:
	if not is_finite(target) or target<=0 or not is_finite(static_friction) or static_friction<0 or static_friction>1:
		return {"valid":false,"reason":"invalid traveller load boundary"}
	var rig: Node3D=line.rig
	var prior_override: Vector3=rig.traveller_override
	var prior_angles: Vector2=coupled.constraint.angles()
	var prior_path: PackedVector3Array=rig.route.duplicate()
	var prior_mast: Vector2=coupled.model.mast_tip
	var prior_loads: Dictionary=coupled.model.last.duplicate(true)
	var prior_solve: Dictionary=coupled.last.duplicate(true)
	var start: Vector3=rig.traveller_lower.position
	trace=[]
	var result := _solve_once(target,static_friction,start)
	if result.valid:
		var reaction: Vector3=-result.frame.normal*result.normal_n+result.frame.slide*(result.friction_n-signf(result.x)*result.get("boundary_reaction_n",0.0))
		result["balance_n"]=(result.force+reaction).length()
		if result.balance_n>FORCE_TOLERANCE:
			result["valid"]=false
			result["reason"]="traveller force residual exceeds tolerance"
	if result.valid:
		var contact: Dictionary=line.contact_check()
		result["contact"]=contact
		if not contact.valid:
			result["valid"]=false
			result["reason"]=contact.reason
	if not result.valid:
		rig.traveller_override=prior_override
		rig.set_angles(prior_angles.x,prior_angles.y,false)
		rig.route=prior_path
		coupled.model.yaw=prior_angles.x
		coupled.model.pitch=prior_angles.y
		coupled.model.mast_tip=prior_mast
		coupled.model.last=prior_loads
		coupled.last=prior_solve
	result["trace"]=trace.duplicate(true)
	result["start"]=start
	result["rest_length"]=line.rest_length
	last=result
	return result

func _solve_once(target: float,mu: float,start: Vector3) -> Dictionary:
	var initial_angle := atan2(start.z-line.origin.z,start.y-line.origin.y)
	# Node positions use 32-bit components; canonicalize an endpoint that was
	# already constrained before feeding it back to the 64-bit scalar domain.
	var initial_x := clampf(start.x,-LINE.MAX_X,LINE.MAX_X)
	var current := _align(initial_x,initial_angle,target)
	if not current.valid: return current
	trace.append(_compact(current))
	var limit: float=mu*current.normal_n
	if absf(current.drive_n)<=limit+FORCE_TOLERANCE:
		current["state"]="stick"
		current["friction_n"]=-current.drive_n
		return current
	var direction: float=signf(current.drive_n)
	var boundary: float=LINE.MAX_X*direction
	if absf(boundary-start.x)<.0001:
		current["state"]="stop"
		current["friction_n"]=-direction*minf(absf(current.drive_n),limit)
		current["boundary_reaction_n"]=maxf(0,absf(current.drive_n)-limit)
		return current
	var mu_slide := mu*.8
	var before := current
	var reached := false
	for step in 24:
		var x: float=move_toward(before.x,boundary,.04)
		current=_align(x,before.azimuth,target)
		if not current.valid: return current
		trace.append(_compact(current))
		var residual: float=current.drive_n*direction-mu_slide*current.normal_n
		if residual<=0:
			reached=true
			break
		if absf(x-boundary)<.00001:
			current["state"]="stop"
			current["friction_n"]=-direction*minf(absf(current.drive_n),mu*current.normal_n)
			current["boundary_reaction_n"]=maxf(0,absf(current.drive_n)-mu*current.normal_n)
			return current
		before=current
	if not reached: return {"valid":false,"reason":"traveller displacement budget exhausted"}
	# The moving state settles inside the static cone. No elapsed movement
	# time or inertial transient is invented by this quasi-static calculation.
	var left: float=before.x
	var right: float=current.x
	for iteration in 16:
		var candidate := _align((left+right)*.5,current.azimuth,target)
		if not candidate.valid: return candidate
		current=candidate
		var residual: float=current.drive_n*direction-mu_slide*current.normal_n
		if absf(residual)<=FORCE_TOLERANCE: break
		if residual>0: left=current.x
		else: right=current.x
	if absf(current.drive_n*direction-mu_slide*current.normal_n)>FORCE_TOLERANCE:
		return {"valid":false,"reason":"traveller slip residual did not converge"}
	current["state"]="slip settled"
	current["friction_n"]=-current.drive_n
	return current

func _compact(result: Dictionary) -> Dictionary:
	return {"x":result.x,"azimuth":result.azimuth,"normal_n":result.normal_n,"drive_n":result.drive_n,"swivel_n":result.swivel_n,"sheet_tension_n":result.load.sheet_tension_n}

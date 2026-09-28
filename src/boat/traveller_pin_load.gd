extends RefCounted

## Frictionless taut-rope loads on a free pinned assembly. Masses, centres
## of mass and gravity are explicit caller data, not product measurements.
const FREE := preload("res://src/boat/free_pinned_block.gd")
const CABLE := preload("res://src/boat/cylinder_cable_route.gd")
const CONE := preload("res://src/boat/articulated_contact_cone.gd")
const FORCE_TOLERANCE := .00001
const MOMENT_TOLERANCE := .00001

static func valid_load(load: Dictionary) -> bool:
	for key in ["lower_mass","upper_mass","sheet_tension","traveller_tension"]:
		if not (load.get(key) is float or load.get(key) is int) or not is_finite(load[key]) or load[key]<0: return false
	for key in ["gravity","lower_com","upper_com"]:
		if not load.get(key) is Vector3 or not load[key].is_finite(): return false
	return true

static func _rope(frame: Transform3D,route: Dictionary,tension: float) -> Array:
	var inverse := frame.affine_inverse()
	return [{"point":inverse*route.entry,"force":route.entry_force_per_n*tension},{"point":inverse*route.exit,"force":route.exit_force_per_n*tension}]

static func _valid_route(route: Dictionary) -> bool:
	if route.get("valid")!=true or route.get("wrapped")!=true: return false
	for key in ["entry","exit","entry_force_per_n","exit_force_per_n"]:
		if not route.get(key) is Vector3 or not route[key].is_finite(): return false
	for key in ["entry_force_per_n","exit_force_per_n"]:
		if absf(route[key].length()-1)>.00001: return false
	return true

static func _matches(frame: Transform3D,route: Dictionary) -> bool:
	var inverse := frame.affine_inverse()
	var entry: Vector3=inverse*route.entry
	var exit_point: Vector3=inverse*route.exit
	if maxf(absf(entry.x),absf(exit_point.x))>CABLE.PLANE_TOLERANCE or minf(entry.length(),exit_point.length())<1e-6 or absf(entry.length()-exit_point.length())>CABLE.PLANE_TOLERANCE: return false
	for pair in [[entry,route.entry_force_per_n],[exit_point,route.exit_force_per_n]]:
		var force: Vector3=frame.basis.transposed()*pair[1]
		if absf(force.x)>.0001 or absf(force.dot(pair[0].normalized()))>.0001: return false
	return true

static func evaluate(state: Dictionary,lower_route: Dictionary,upper_route: Dictionary,load: Dictionary) -> Dictionary:
	if not FREE.valid(state) or not valid_load(load) or not _valid_route(lower_route) or not _valid_route(upper_route): return {"valid":false,"reason":"invalid taut assembly load boundary"}
	if not _matches(state.lower,lower_route) or not _matches(state.upper,upper_route): return {"valid":false,"reason":"rope forces do not match rigid groove tangencies"}
	var lower := _rope(state.lower,lower_route,load.traveller_tension)
	var upper := _rope(state.upper,upper_route,load.sheet_tension)
	lower.append({"point":load.lower_com,"force":load.gravity*load.lower_mass})
	upper.append({"point":load.upper_com,"force":load.gravity*load.upper_mass})
	var result := FREE.evaluate(state,lower,upper,state.lower.origin)
	result["lower_loads"]=lower
	result["upper_loads"]=upper
	# No x-boundary support, groove-plane constraint force or hidden pivot.
	result["equilibrium"]=result.force_n.length()<=FORCE_TOLERANCE and result.moment_nm.length()<=MOMENT_TOLERANCE and absf(result.hinge_nm)<=MOMENT_TOLERANCE
	result["scope"]="prescribed taut tensions and explicit masses; full seven-coordinate residual, no contact reactions or slack cable"
	return result

static func best_force_tension(state: Dictionary,lower_route: Dictionary,upper_route: Dictionary,load: Dictionary) -> Dictionary:
	# Least-squares translational balance is a diagnostic, NOT an equilibrium
	# solve. Rotational residuals remain visible and negative tension is refused.
	if not valid_load(load): return {"valid":false,"reason":"invalid prescribed load"}
	var copy := load.duplicate(true)
	copy.traveller_tension=0.0
	var unloaded := evaluate(state,lower_route,upper_route,copy)
	if not unloaded.valid: return unloaded
	var direction: Vector3=lower_route.entry_force_per_n+lower_route.exit_force_per_n
	if direction.length_squared()<1e-12: return {"valid":false,"reason":"traveller has no resultant support direction"}
	var tension: float=-unloaded.force_n.dot(direction)/direction.length_squared()
	if tension<0: return {"valid":false,"reason":"compressive traveller demand requires another support or slack regime","unconstrained_tension_n":tension}
	copy.traveller_tension=tension
	var result := evaluate(state,lower_route,upper_route,copy)
	result["traveller_tension_n"]=tension
	return result

static func balance_contacts(state: Dictionary,lower_route: Dictionary,upper_route: Dictionary,load: Dictionary,contacts: Array) -> Dictionary:
	# Contact witnesses must come from a separate solid-geometry query. This
	# verifies their wrench, not whether the caller supplied every solid face.
	var result := evaluate(state,lower_route,upper_route,load)
	if not result.valid: return result
	var active := []
	for row in contacts:
		if not row is Dictionary or not row.has_all(["kind","point","normal","gap"]) or not row.kind is int or not row.point is Vector3 or not row.normal is Vector3 or not (row.gap is float or row.gap is int): return {"valid":false,"reason":"invalid contact witness"}
		var other: Variant=row.get("other",Vector3(NAN,NAN,NAN))
		if not other is Vector3: return {"valid":false,"reason":"invalid mutual witness"}
		var rebuilt := FREE.contact(state,row.kind,row.point,row.normal,row.gap,other)
		if not rebuilt.valid or row.gap< -.000002: return {"valid":false,"reason":"invalid or penetrating contact witness"}
		if row.gap<=.000002: active.append(rebuilt)
	for stop: Dictionary in FREE.stops(state):
		if stop.gap<=.00000001: active.append(stop)
	# Scale moment coordinates only for conditioning. Reaction coefficients
	# retain N (surface) / Nm (stop); certify unscaled physical residuals.
	var drive: PackedFloat64Array=result.drive.duplicate()
	for i in range(3,7): drive[i]/=.1
	for row: Dictionary in active:
		row["physical_gradient"]=row.gradient.duplicate()
		for i in range(3,7): row.gradient[i]/=.1
	var solved := CONE.solve(drive,active)
	if not solved.valid: return solved
	var residual: PackedFloat64Array=result.drive.duplicate()
	for reaction: Dictionary in solved.reactions:
		for i in 7: residual[i]+=reaction.normal_force_n*reaction.physical_gradient[i]
	var force := Vector3(residual[0],residual[1],residual[2])
	var moment := Vector3(residual[3],residual[4],residual[5])
	# Do not present the pre-contact pin wrench as a post-contact bearing load.
	return {"valid":true,"equilibrium":force.length()<=FORCE_TOLERANCE and moment.length()<=MOMENT_TOLERANCE and absf(residual[6])<=MOMENT_TOLERANCE,"residual_force_n":force,"residual_moment_nm":moment,"residual_hinge_nm":residual[6],"reactions":solved.reactions,"loads_before_contact":result,"scope":"full free wrench with supplied touching witnesses and configured hinge stops; geometry completeness, final bearing reactions and position solve not certified"}

static func _pin_components(state: Dictionary,point: Vector3) -> PackedFloat64Array:
	var result := PackedFloat64Array([0,0,0])
	for i in 3:
		for j in 3: result[i]+=float(state.pin.basis[i][j])*(float(point[j])-float(state.pin.origin[j]))
	return result

static func _potential(state: Dictionary,angle: float,a: Vector3,b: Vector3,radius: float,direction: float,load: Dictionary) -> float:
	# Scalar hinge coordinates retain double precision. Taking differences of
	# float32 Vector lengths of metre-long legs loses sub-millimetre work.
	var c := cos(angle)
	var s := sin(angle)
	var ends := []
	var eye: Transform3D=state.boundary.upper_eye
	for endpoint in [a,b]:
		var p := _pin_components(state,endpoint)
		var rotated := PackedFloat64Array([p[0],c*p[1]+s*p[2],-s*p[1]+c*p[2]])
		var local := PackedFloat64Array([eye.origin.x,eye.origin.y,eye.origin.z])
		for i in 3:
			for j in 3: local[i]+=float(eye.basis[j][i])*rotated[j]
		ends.append(local)
	var ra := sqrt(ends[0][1]*ends[0][1]+ends[0][2]*ends[0][2])
	var rb := sqrt(ends[1][1]*ends[1][1]+ends[1][2]*ends[1][2])
	var first := atan2(ends[0][2],ends[0][1])+direction*acos(radius/ra)
	var last := atan2(ends[1][2],ends[1][1])-direction*acos(radius/rb)
	var length := sqrt(ra*ra-radius*radius)+sqrt(rb*rb-radius*radius)+radius*fposmod((last-first)*direction,TAU)
	var centre: Vector3=eye.affine_inverse()*load.upper_com
	var moved := PackedFloat64Array([centre.x,c*centre.y-s*centre.z,s*centre.y+c*centre.z])
	var energy: float=load.sheet_tension*length
	for i in 3:
		for j in 3: energy-=float(state.pin.basis[j][i])*moved[j]*float(load.gravity[i])*load.upper_mass
	return energy

static func upper_trial(state: Dictionary,angle: float,a: Vector3,b: Vector3,radius: float,load: Dictionary) -> Dictionary:
	if not FREE.valid(state) or not valid_load(load): return {"valid":false,"reason":"invalid upper equilibrium boundary"}
	var posed := FREE.compose(state.boundary,state.lower,angle)
	if not posed.valid: return posed
	# Rebuild about the pin before routing. Rotating a centimetre-size part
	# at the rig's distant origin quantizes its energy derivative.
	var datum: Vector3=state.pin.origin
	var local_lower := Transform3D(state.lower.basis,-(state.lower.basis*state.boundary.lower_eye.origin))
	var local := FREE.compose(state.boundary,local_lower,angle)
	var cable := CABLE.route(local.upper,radius,a-datum,b-datum,true,true,Vector3.ZERO,INF,.0085)
	if not cable.valid: return cable
	var loads := _rope(local.upper,cable,load.sheet_tension)
	loads.append({"point":load.upper_com,"force":load.gravity*load.upper_mass})
	var wrench := FREE.evaluate(local,[],loads,Vector3.ZERO)
	# Only gravity is conservative as a frozen point force. T*length is the
	# correct potential for the recomputed constant-tension endpoint route.
	var potential := _potential(state,angle,a,b,radius,signf(cable.sweep),load)
	for key in ["entry","exit"]: cable[key]+=datum
	for key in ["path","arc_path"]: cable[key]=Transform3D(Basis.IDENTITY,datum)*cable[key]
	return {"valid":true,"state":posed,"route":cable,"drive_nm":wrench.hinge_nm,"potential_j":potential}

static func settle_upper(state: Dictionary,a: Vector3,b: Vector3,radius: float,load: Dictionary,maximum_msec := 1000,cancelled := Callable()) -> Dictionary:
	if not FREE.valid(state) or not valid_load(load) or maximum_msec<=0: return {"valid":false,"reason":"invalid upper equilibrium request"}
	var start := Time.get_ticks_usec()
	var previous := {}
	var candidates := []
	for sample in 33:
		if cancelled.is_valid() and cancelled.call(): return {"valid":false,"reason":"cancelled"}
		if Time.get_ticks_usec()-start>maximum_msec*1000: return {"valid":false,"reason":"upper equilibrium budget exhausted"}
		var angle := lerpf(state.boundary.minimum,state.boundary.maximum,sample/32.0)
		var trial := upper_trial(state,angle,a,b,radius,load)
		if not trial.valid:
			previous={}
			continue
		if (sample==0 and trial.drive_nm<=0) or (sample==32 and trial.drive_nm>=0):
			trial["stop_moment_nm"]=-trial.drive_nm
			candidates.append(trial)
		elif absf(trial.drive_nm)<MOMENT_TOLERANCE*.1:
			trial["stop_moment_nm"]=0.0
			candidates.append(trial)
		if not previous.is_empty() and previous.drive_nm>0 and trial.drive_nm<0:
			var low := previous
			var high := trial
			var best: Dictionary=low if absf(low.drive_nm)<absf(high.drive_nm) else high
			for iteration in 30:
				if cancelled.is_valid() and cancelled.call(): return {"valid":false,"reason":"cancelled"}
				if Time.get_ticks_usec()-start>maximum_msec*1000: return {"valid":false,"reason":"upper equilibrium budget exhausted"}
				var middle := upper_trial(state,(low.state.angle+high.state.angle)*.5,a,b,radius,load)
				if not middle.valid: return {"valid":false,"reason":"invalid interior upper route"}
				if absf(middle.drive_nm)<absf(best.drive_nm): best=middle
				if absf(best.drive_nm)<MOMENT_TOLERANCE*.1: break
				if middle.drive_nm>0: low=middle
				else: high=middle
			if absf(best.drive_nm)>MOMENT_TOLERANCE: return {"valid":false,"reason":"upper torque tolerance not reached"}
			best["stop_moment_nm"]=0.0
			candidates.append(best)
		previous=trial
	if candidates.is_empty(): return {"valid":false,"reason":"no supported upper angular equilibrium"}
	var selected: Dictionary=candidates[0]
	for candidate: Dictionary in candidates:
		if candidate.potential_j<selected.potential_j: selected=candidate
	selected["residual_nm"]=absf(selected.drive_nm+selected.stop_moment_nm)
	selected["elapsed_msec"]=(Time.get_ticks_usec()-start)/1000.0
	selected["scope"]="upper hinge only with lower body frozen; not whole assembly equilibrium or finite contact certification"
	return selected

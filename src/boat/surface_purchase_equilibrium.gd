extends RefCounted

## Free traveller pair plus a spherical aft attachment, taut frictionless
## ropes and specified gravity. A stationary point is NOT a hardware,
## stability, complete material-ledger, or runtime-adoption certificate.
## Supply a local coordinate frame near the lower block, not large world
## coordinates: single-precision transforms otherwise quantize short legs.
const ROUTE := preload("res://src/boat/surface_purchase_route.gd")
const FREE := preload("res://src/boat/free_pinned_block.gd")
const LOAD := preload("res://src/boat/traveller_pin_load.gd")
const LINEAR := preload("res://src/boat/grooved_cable_route.gd")
const FORCE_TOLERANCE := .00001
const MOMENT_TOLERANCE := .00001
const LENGTH_TOLERANCE := .0000002
const SOLVE_MARGIN := .5

static func _stopped(deadline: int,cancelled: Callable) -> bool:
	return Time.get_ticks_usec()>=deadline or (cancelled.is_valid() and cancelled.call())

static func _load_valid(load: Dictionary) -> bool:
	for key in ["lower_mass","upper_mass","aft_mass","sheet_tension"]:
		if not (load.get(key) is float or load.get(key) is int) or not is_finite(load[key]) or load[key]<0: return false
	for key in ["lower_com","upper_com","aft_com","gravity"]:
		if not load.get(key) is Vector3 or not load[key].is_finite(): return false
	return load.sheet_tension>0

static func _evaluate(state: Dictionary,tension: float,boundary: Dictionary,load: Dictionary,length: float,count: int,deadline: int,cancelled: Callable) -> Dictionary:
	if _stopped(deadline,cancelled): return {"valid":false,"reason":"cancelled or equilibrium budget exhausted"}
	if not FREE.valid(state) or not is_finite(tension) or tension<=0: return {"valid":false,"reason":"invalid state or nonpositive support tension"}
	var stop := func(): return _stopped(deadline,cancelled)
	var profiles: Dictionary=state.get("profiles",{})
	var remaining := maxi(1,int((deadline-Time.get_ticks_usec())/1000))
	var lower := ROUTE.lower_route(boundary,state.lower,count,remaining,stop,profiles.get("lower",PackedFloat64Array()))
	if not lower.valid: return lower
	remaining=maxi(1,int((deadline-Time.get_ticks_usec())/1000))
	var purchase := ROUTE.route(boundary.purchase,state.aft,state.upper,count,remaining,stop,profiles)
	if not purchase.valid: return purchase
	var lower_loads := LOAD._rope(state.lower,lower.sheave,tension)
	var upper_loads := LOAD._rope(state.upper,purchase.traveller,load.sheet_tension)
	lower_loads.append({"point":load.lower_com,"force":load.gravity*load.lower_mass})
	upper_loads.append({"point":load.upper_com,"force":load.gravity*load.upper_mass})
	var wrench := FREE.evaluate(state,lower_loads,upper_loads)
	if not wrench.valid: return wrench
	var inverse: Transform3D=state.aft.affine_inverse()
	var aft_loads := LOAD._rope(state.aft,purchase.aft,load.sheet_tension)
	# Fixed rope end and its incoming becket traction are internal to this
	# same body. Their combined external wrench is the outgoing traction.
	aft_loads.append({"point":inverse*purchase.becket.exit,"force":purchase.becket.exit_force_per_n*load.sheet_tension})
	aft_loads.append({"point":load.aft_com,"force":load.gravity*load.aft_mass})
	var aft_force := Vector3.ZERO
	var aft_moment := Vector3.ZERO
	for item: Dictionary in aft_loads:
		aft_force+=item.force
		aft_moment+=(state.aft*item.point-boundary.purchase.mount).cross(item.force)
	var residual: PackedFloat64Array=wrench.drive.duplicate()
	for i in range(3,7): residual[i]/=.1
	residual.append((lower.length-length)*10000)
	for i in 3: residual.append(aft_moment[i]/.1)
	var cost := 0.0
	for value in residual: cost+=value*value
	var saved := state.duplicate(true)
	saved["profiles"]={"lower":lower.sheave.profile,"traveller":purchase.traveller.profile,"aft":purchase.aft.profile}
	return {"valid":true,"state":saved,"tension":tension,"lower":lower,"purchase":purchase,"wrench":wrench,"aft_force":aft_force,"aft_moment":aft_moment,"length_error_m":lower.length-length,"residual":residual,"cost":cost}

static func _move(state: Dictionary,tension: float,step: PackedFloat64Array,scale: float,boundary: Dictionary) -> Dictionary:
	var lower: Transform3D=state.lower
	lower.origin+=Vector3(step[0],step[1],step[2])*scale*.1
	var rotation := Vector3(step[3],step[4],step[5])*scale
	if rotation.length()>1e-10: lower.basis=(Basis(rotation.normalized(),rotation.length())*lower.basis).orthonormalized()
	var moved := FREE.compose(state.boundary,lower,state.angle+step[6]*scale)
	var basis: Basis=state.aft.basis
	var spin := Vector3(step[8],step[9],step[10])*scale
	if spin.length()>1e-10: basis=(Basis(spin.normalized(),spin.length())*basis).orthonormalized()
	moved["aft"]=Transform3D(basis,boundary.purchase.mount-basis*boundary.purchase.eye)
	moved["profiles"]=state.get("profiles",{}).duplicate(true)
	return {"state":moved,"tension":tension+step[7]*scale*10}

static func _converged(result: Dictionary) -> bool:
	# Leave half the unchanged acceptance limits for independent refinement
	# and finite-transform roundoff, instead of stopping on their boundary.
	return result.get("valid",false) and result.wrench.force_n.length()<FORCE_TOLERANCE*SOLVE_MARGIN and result.wrench.moment_nm.length()<MOMENT_TOLERANCE*SOLVE_MARGIN and absf(result.wrench.hinge_nm)<MOMENT_TOLERANCE*SOLVE_MARGIN and result.aft_moment.length()<MOMENT_TOLERANCE*SOLVE_MARGIN and absf(result.length_error_m)<LENGTH_TOLERANCE*SOLVE_MARGIN

static func solve(boundary: Dictionary,initial: Dictionary,load: Dictionary,length: float,starting_tension := 8.0,maximum_msec := 15000,cancelled := Callable(),count := 25) -> Dictionary:
	var began := Time.get_ticks_usec()
	var rejected := {"valid":false,"converged":false,"usable":false,"geometry_certified":false,"reason":"invalid equilibrium request"}
	if not FREE.valid(initial) or not initial.get("aft") is Transform3D or not ROUTE.PIN.rigid(initial.aft) or not _load_valid(load) or not is_finite(length) or length<=0 or not is_finite(starting_tension) or starting_tension<=0 or maximum_msec<=0 or count<9 or count>129: return rejected
	if not boundary.get("purchase") is Dictionary or not boundary.purchase.has_all(["mount","eye"]): return rejected
	for key in ["becket_winding","traveller_winding","aft_winding"]:
		if not (boundary.purchase.get(key) is int or boundary.purchase.get(key) is float) or boundary.purchase[key] not in [-1.0,1.0]:
			rejected.reason="explicit installed purchase windings required"
			return rejected
	if not initial.get("profiles",{}) is Dictionary: return rejected
	for key in ["lower","traveller","aft"]:
		if initial.get("profiles",{}).has(key) and not initial.profiles[key] is PackedFloat64Array: return rejected
	var deadline := began+maximum_msec*1000
	var current := _evaluate(initial,starting_tension,boundary,load,length,count,deadline,cancelled)
	if not current.valid:
		rejected.reason=current.reason
		return rejected
	var trace := []
	var reason := "iteration limit"
	for iteration in 180:
		if _stopped(deadline,cancelled):
			reason="cancelled or equilibrium budget exhausted"
			break
		trace.append({"cost":current.cost,"force_n":current.wrench.force_n.length(),"moment_nm":current.wrench.moment_nm.length(),"aft_moment_nm":current.aft_moment.length(),"hinge_nm":current.wrench.hinge_nm,"length_error_m":current.length_error_m,"tension_n":current.tension})
		if _converged(current):
			reason="force and length stationary point; independent certification required"
			break
		var jacobian := []
		var good := true
		for coordinate in 11:
			var step := PackedFloat64Array()
			step.resize(11)
			var h := .0001
			var before := {}
			var after := {}
			for refinement in 7:
				step[coordinate]=h
				var left := _move(current.state,current.tension,step,-1,boundary)
				var right := _move(current.state,current.tension,step,1,boundary)
				before=_evaluate(left.state,left.tension,boundary,load,length,count,deadline,cancelled)
				after=_evaluate(right.state,right.tension,boundary,load,length,count,deadline,cancelled)
				if before.valid and after.valid: break
				if _stopped(deadline,cancelled): break
				h*=.5
			if not before.valid or not after.valid:
				good=false
				reason="derivative domain %d: %s / %s" % [coordinate,before.get("reason","ok"),after.get("reason","ok")]
				break
			var column := PackedFloat64Array()
			for i in 11: column.append((after.residual[i]-before.residual[i])/(2*h))
			# At a stationary contact route, virtual work gives its exact
			# length derivative; it avoids subtracting metre-scale float sums.
			if coordinate<3: column[7]=-current.lower.sheave.support_force_per_n[coordinate]*1000
			elif coordinate<6: column[7]=-current.lower.sheave.moment_per_n[coordinate-3]*10000
			else: column[7]=0
			jacobian.append(column)
		if not good: break
		var matrix := []
		var rhs := PackedFloat64Array()
		for i in 11:
			var row := PackedFloat64Array()
			var value := 0.0
			for k in 11: value-=jacobian[i][k]*current.residual[k]
			rhs.append(value)
			for j in 11:
				var cell := .00001 if i==j else 0.0
				for k in 11: cell+=jacobian[i][k]*jacobian[j][k]
				row.append(cell)
			matrix.append(row)
		var step := LINEAR._linear(matrix,rhs)
		if step.is_empty():
			reason="singular derivative"
			break
		var scale := minf(1,.1/maxf(LINEAR._maximum(step),.000001))
		var accepted := false
		for backtrack in 16:
			if _stopped(deadline,cancelled): break
			var proposed := _move(current.state,current.tension,step,scale,boundary)
			var trial := _evaluate(proposed.state,proposed.tension,boundary,load,length,count,deadline,cancelled)
			# Each physical criterion still applies separately. A fully passing
			# trial must not be rejected merely for a larger sub-tolerance sum.
			if trial.valid and (_converged(trial) or trial.cost<current.cost):
				current=trial
				accepted=true
				break
			scale*=.5
		if not accepted:
			reason="no descent"
			break
	var stopped := _stopped(deadline,cancelled)
	current["converged"]=_converged(current) and not stopped
	current["reason"]="cancelled or equilibrium budget exhausted" if stopped else reason
	current["usable"]=false
	current["geometry_certified"]=false
	current["stability_certified"]=false
	current["discretization_certified"]=false
	current["trace"]=trace
	current["elapsed_msec"]=(Time.get_ticks_usec()-began)/1000.0
	return current

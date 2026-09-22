extends RefCounted

## Quasi-static taut/slack branches. Exact wrapped-sheet geometry constrains
## the taut rig; the unloaded branch retains excess cable as gravity sag.
## This is deliberately not the production frame-by-frame sailing integrator.
const CONSTRAINT := preload("res://src/boat/rig_sheet_constraint.gd")
const LOAD := preload("res://src/boat/rig_load_state.gd")
const FORCE_TOLERANCE := .12
const PITCH_STEP := .0006
const MAST_STEP := .0006
var constraint: RefCounted
var model := LOAD.new()
var target := 0.0
var evaluations := 0
var last := {}
var yaw_chart := false

func _init(rig: Node3D) -> void:
	constraint=CONSTRAINT.new(rig)
	model.external_sheet_constraint=true
	var q: Vector2=constraint.angles()
	model.yaw=q.x
	model.pitch=q.y
	var key := LOAD.CONTRACT.boom_transform(q.x,q.y)*LOAD.CONTRACT.VANG_KEY_LOCAL
	model.vang_tail=LOAD.VANG.tail_for_span(key.distance_to(LOAD.CONTRACT.VANG_BASE_LOCAL))
	model.target_vang=model.vang_tail
	model.initial_vang_tail=model.vang_tail

func _residual(x: Vector3) -> Dictionary:
	evaluations+=1
	var low: float=constraint.minimum_yaw() if yaw_chart else CONSTRAINT.MIN_PITCH
	var high: float=CONSTRAINT.MAX_YAW if yaw_chart else CONSTRAINT.MAX_PITCH
	if not x.is_finite() or x.x<low or x.x>high or Vector2(x.y,x.z).length()>LOAD.MAST.MAX_DISPLACEMENT:
		return {"valid":false,"reason":"outside reduced mast or pitch domain"}
	var fit: Dictionary=constraint.fit_pitch(target,x.x,false,.000003) if yaw_chart else constraint.fit(target,x.x,false,.000003)
	if not fit.valid: return fit
	var derivative: Dictionary=constraint.jacobian(1 if yaw_chart else 0)
	if not derivative.valid: return {"valid":false,"reason":"singular sheet constraint"}
	model.yaw=fit.yaw
	model.pitch=fit.pitch
	model.mast_tip=Vector2(x.y,x.z)
	model.angular_velocity=Vector2.ZERO
	model.mast_velocity=Vector2.ZERO
	var force: Dictionary=model.forces()
	if not force.valid: return force
	var slope: float=derivative.dyaw_dpitch
	var residual := Vector3(force.moment.y+slope*force.moment.x,force.mast_force.x,force.mast_force.y)
	if yaw_chart: residual.x=force.moment.x+derivative.dpitch_dyaw*force.moment.y
	var gradient: Vector2=derivative.gradient
	var tension: float=force.moment.dot(gradient)/gradient.length_squared()
	return {"valid":residual.is_finite(),"residual":residual,"norm":maxf(absf(residual.x),maxf(absf(residual.y),absf(residual.z))),"sheet_tension_n":tension,"sheet_gradient":gradient,"fit":fit,"loads":force}

func solve(length_metres: float,display := false) -> Dictionary:
	var original: Vector2=constraint.angles()
	var original_path: PackedVector3Array=constraint.rig.route.duplicate()
	var original_mast: Vector2=model.mast_tip
	var original_loads: Dictionary=model.last.duplicate(true)
	var requested_frame: Basis=model.boat_frame
	var requested_acceleration: Vector3=model.boat_acceleration_world
	var prefer_yaw: bool=length_metres<4.0 and original.x>=constraint.minimum_yaw() and original.x-constraint.minimum_yaw()<.03
	var result := _solve_once(length_metres,false,false,prefer_yaw)
	var chart_failure := {}
	var alternate_failure := {}
	if not result.valid and result.get("reason","") in ["equilibrium residual did not decrease","equilibrium derivative leaves geometric domain","singular sheet constraint","singular equilibrium tangent","equilibrium iteration budget exhausted"]:
		var failed_chart := {"reason":result.get("reason",""),"norm":result.get("norm",INF),"trace":result.get("trace",[])}
		if prefer_yaw: alternate_failure=failed_chart
		else: chart_failure=failed_chart
		# Both coordinates describe the same constrained rig. A failed solve
		# rolls back before trying the other chart; force limits never change.
		result=_solve_once(length_metres,false,false,not prefer_yaw)
		if not result.valid:
			if prefer_yaw: chart_failure=result.duplicate(true)
			else: alternate_failure=result.duplicate(true)
	var continuation := []
	if not result.valid and result.get("reason","")=="equilibrium residual did not decrease":
		# Load continuation crosses the nonsmooth tension onset without changing
		# the requested final boundary or accepting a negative sheet reaction.
		# Intermediate algebraic roots are never displayed or called physical.
		for fraction in [0.0,.25,.5,.75,1.0]:
			model.boat_frame=Basis.IDENTITY.slerp(requested_frame,fraction)
			model.boat_acceleration_world=requested_acceleration*fraction
			result=_solve_once(length_metres,false,true)
			continuation.append({"fraction":fraction,"valid":result.valid,"norm":result.get("norm",INF),"tension":result.get("sheet_tension_n",0),"reason":result.get("reason","")})
			if not result.valid: break
		if result.valid and result.sheet_tension_n<0:
			result["valid"]=false
			result["reason"]="slack-sheet branch requires a hanging rig path"
	model.boat_frame=requested_frame
	model.boat_acceleration_world=requested_acceleration
	if not result.valid and result.get("reason","")=="slack-sheet branch requires a hanging rig path":
		var seed: Vector4=result.get("state",Vector4(original.x,original.y,original_mast.x,original_mast.y))
		result=_solve_free(length_metres,seed)
	if result.valid and result.get("branch","")=="slack":
		var hanging: Dictionary=constraint.drape(length_metres,model.yaw,model.pitch,model.effective_gravity(),display)
		if not hanging.valid: result=hanging
	if not result.valid:
		constraint.rig.set_angles(original.x,original.y,display)
		constraint.rig.route=original_path
		if display: constraint.rig.rope_view.show_path(original_path)
		model.yaw=original.x
		model.pitch=original.y
		model.mast_tip=original_mast
		model.last=original_loads
	elif display and result.get("branch","")!="slack": constraint.rig.set_angles(model.yaw,model.pitch,true)
	result["continuation"]=continuation
	result["pitch_chart_failure"]=chart_failure
	result["yaw_chart_failure"]=alternate_failure
	last=result
	return result

func _solve_once(length_metres: float,display := false,algebraic_only := false,use_yaw_chart := false) -> Dictionary:
	yaw_chart=use_yaw_chart
	if not is_finite(length_metres) or length_metres<=0 or not model.wind_world.is_finite() or not model.boat_acceleration_world.is_finite() or not model.boat_frame.is_finite() or not model.boat_frame.is_equal_approx(model.boat_frame.orthonormalized()) or absf(model.boat_frame.determinant()-1)>.001:
		return {"valid":false,"reason":"invalid equilibrium boundary"}
	var previous: Vector2=constraint.angles()
	var previous_mast: Vector2=model.mast_tip
	target=length_metres
	evaluations=0
	var x := Vector3(previous.x if yaw_chart else previous.y,previous_mast.x,previous_mast.y)
	var result := _residual(x)
	if result.valid and previous_mast.length()<.000001 and result.loads.leech_tension_n>1000:
		# Cold starts with a straight, highly compressed mast can lie on an
		# indefinite Newton tangent. Lower its fixed-boom potential first;
		# this is only a seed and never bypasses the full force acceptance.
		var seed := _relax_mast_seed()
		x.y=seed.x
		x.z=seed.y
		result=_residual(x)
	var iterations := 0
	var trace := []
	for iteration in 48:
		iterations=iteration+1
		trace.append({"x":x,"norm":result.get("norm",INF),"tension":result.get("sheet_tension_n",0)})
		if not result.valid or result.norm<=FORCE_TOLERANCE*.5: break
		var columns: Array[Vector3]=[]
		for axis in 3:
			var h := PITCH_STEP if axis==0 else MAST_STEP
			# Resolve the cable slack/taut kink locally once near equilibrium.
			if result.norm<10: h*=.1
			var probe := x
			probe[axis]+=h
			var forward := _residual(probe)
			probe[axis]-=2*h
			var backward := _residual(probe)
			if forward.valid and backward.valid:
				columns.append((forward.residual-backward.residual)/(2*h))
			elif forward.valid:
				columns.append((forward.residual-result.residual)/h)
			elif backward.valid:
				columns.append((result.residual-backward.residual)/h)
			else: break
		if columns.size()!=3:
			result={"valid":false,"reason":"equilibrium derivative leaves geometric domain"}
			break
		var jacobian := Basis(columns[0],columns[1],columns[2])
		if not jacobian.is_finite() or absf(jacobian.determinant())<.00001:
			result={"valid":false,"reason":"singular equilibrium tangent"}
			break
		var step: Vector3=-(jacobian.inverse()*result.residual)
		var factor := minf(1,minf(deg_to_rad(3)/maxf(absf(step.x),.000001),.15/maxf(Vector2(step.y,step.z).length(),.000001)))
		var accepted := false
		for search in 8:
			var candidate := x+step*factor
			var trial := _residual(candidate)
			if trial.valid and trial.norm<result.norm:
				x=candidate
				result=trial
				accepted=true
				break
			factor*=.5
		if not accepted:
			result["valid"]=false
			result["reason"]="equilibrium residual did not decrease"
			break
	if result.valid:
		result=_residual(x)
		if result.norm>FORCE_TOLERANCE:
			result["valid"]=false
			result["reason"]="equilibrium iteration budget exhausted"
		elif result.sheet_tension_n<0 and not algebraic_only:
			result["valid"]=false
			result["reason"]="slack-sheet branch requires a hanging rig path"
	result["iterations"]=iterations
	result["coordinate"]="yaw" if yaw_chart else "pitch"
	result["evaluations"]=evaluations
	result["trace"]=trace
	result["state"]=Vector4(model.yaw,model.pitch,model.mast_tip.x,model.mast_tip.y)
	if result.valid:
		result["branch"]="taut"
		result["slack_metres"]=0.0
	if not result.valid:
		constraint.rig.set_angles(previous.x,previous.y,display)
		model.yaw=previous.x
		model.pitch=previous.y
		model.mast_tip=previous_mast
	else:
		constraint.rig.set_angles(model.yaw,model.pitch,display)
		model.last=result.loads
	last=result
	return result

func _relax_mast_seed() -> Vector2:
	var current: Vector2=model.mast_tip
	for iteration in 24:
		model.mast_tip=current
		var loads: Dictionary=model.forces()
		if not loads.valid or loads.mast_force.length()<1.0: break
		var energy: float=loads.elastic_energy_j-.55*loads.aerodynamic_force.dot(loads.head)
		var direction: Vector2=loads.mast_force.normalized()
		var distance := .15
		var accepted := false
		for search in 12:
			var candidate := current+direction*distance
			model.mast_tip=candidate
			var trial: Dictionary=model.forces()
			if trial.valid and trial.elastic_energy_j-.55*trial.aerodynamic_force.dot(trial.head)<energy:
				current=candidate
				accepted=true
				break
			distance*=.5
		if not accepted: break
	model.mast_tip=current
	return current

func _free_residual(x: Vector4) -> Dictionary:
	if not x.is_finite() or x.x<constraint.rig.minimum_yaw or x.x>CONSTRAINT.MAX_YAW or x.y<CONSTRAINT.MIN_PITCH or x.y>CONSTRAINT.MAX_PITCH or Vector2(x.z,x.w).length()>LOAD.MAST.MAX_DISPLACEMENT:
		return {"valid":false,"reason":"outside free rig domain"}
	model.yaw=x.x
	model.pitch=x.y
	model.mast_tip=Vector2(x.z,x.w)
	model.angular_velocity=Vector2.ZERO
	model.mast_velocity=Vector2.ZERO
	var loads: Dictionary=model.forces()
	if not loads.valid: return loads
	var residual := Vector4(loads.moment.x,loads.moment.y,loads.mast_force.x,loads.mast_force.y)
	return {"valid":residual.is_finite(),"residual":residual,"norm":maxf(maxf(absf(residual.x),absf(residual.y)),maxf(absf(residual.z),absf(residual.w))),"loads":loads}

func _solve_free(length_metres: float,seed: Vector4) -> Dictionary:
	# Release the unilateral sheet constraint instead of letting a cable push.
	# This is a button-time equilibrium calculation, never a frame integrator.
	var x := seed
	var result := _free_residual(x)
	var trace := []
	for iteration in 28:
		trace.append({"state":x,"norm":result.get("norm",INF)})
		if not result.valid or result.norm<=FORCE_TOLERANCE: break
		var columns: Array[Vector4]=[]
		for axis in 4:
			var h := .00006
			var probe := x
			probe[axis]+=h
			var a := _free_residual(probe)
			probe[axis]-=2*h
			var b := _free_residual(probe)
			if not a.valid or not b.valid: break
			columns.append((a.residual-b.residual)/(2*h))
		if columns.size()!=4: return {"valid":false,"reason":"free rig derivative outside domain","trace":trace}
		var matrix := Projection(columns[0],columns[1],columns[2],columns[3])
		if absf(matrix.determinant())<.00001: return {"valid":false,"reason":"singular free rig derivative","trace":trace}
		var step: Vector4=matrix.inverse()*(-result.residual)
		var factor := minf(1,minf(deg_to_rad(6)/maxf(absf(step.x),.000001),minf(deg_to_rad(3)/maxf(absf(step.y),.000001),.15/maxf(Vector2(step.z,step.w).length(),.000001))))
		var accepted := false
		for search in 12:
			var candidate := x+step*factor
			var trial := _free_residual(candidate)
			if trial.valid and trial.norm<result.norm:
				x=candidate
				result=trial
				accepted=true
				break
			factor*=.5
		if not accepted: return {"valid":false,"reason":"free rig residual did not decrease","trace":trace}
	result=_free_residual(x)
	if not result.valid or result.norm>FORCE_TOLERANCE: return {"valid":false,"reason":"free rig did not converge","trace":trace}
	constraint.rig.set_angles(x.x,x.y,false)
	var direct_length: float=constraint.rig.length_metres()
	if direct_length>length_metres+CONSTRAINT.LENGTH_TOLERANCE: return {"valid":false,"reason":"free equilibrium would overextend sheet","trace":trace}
	result["branch"]="slack"
	result["sheet_tension_n"]=0.0
	result["slack_metres"]=maxf(0,length_metres-direct_length)
	result["state"]=x
	result["trace"]=trace
	model.last=result.loads
	return result

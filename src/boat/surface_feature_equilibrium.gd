extends RefCounted
## Frozen-feature contact equilibrium. It never authorizes a
## runtime commit: finite feature membership and whole mesh must be checked.
const MODEL := preload("res://src/boat/surface_purchase_equilibrium.gd")
static func valid_contact(contact: Dictionary) -> bool:
	if contact.get("body") not in [0,1]: return false
	for key in ["local","normal","surface"]:
		if not contact.get(key) is Vector3 or not contact[key].is_finite(): return false
	if absf(contact.normal.length()-1)>.00001: return false
	return (contact.get("clearance") is float or contact.get("clearance") is int) and is_finite(contact.clearance) and contact.clearance>=0 and contact.clearance<=.001
static func evaluate(state: Dictionary,tension: float,reaction: float,boundary: Dictionary,load: Dictionary,length: float,contact: Dictionary,count: int,deadline: int,stop: Callable) -> Dictionary:
	if not valid_contact(contact) or not is_finite(reaction): return {"valid":false,"reason":"invalid finite contact request"}
	var result := MODEL._evaluate(state,tension,boundary,load,length,count,deadline,stop)
	if not result.valid: return result
	var frame: Transform3D=state.lower if contact.body==0 else state.upper
	var point: Vector3=frame*contact.local
	var force: Vector3=contact.normal*reaction
	var total: Dictionary=result.wrench.duplicate(true)
	total.force_n+=force
	total.moment_nm+=(point-state.lower.origin).cross(force)
	if contact.body==1: total.hinge_nm+=(point-state.pin.origin).cross(force).dot(state.pin.basis.x)
	total.drive=PackedFloat64Array([total.force_n.x,total.force_n.y,total.force_n.z,total.moment_nm.x,total.moment_nm.y,total.moment_nm.z,total.hinge_nm])
	total.bodies[contact.body].force_n+=force
	total.bodies[contact.body].pin_moment_nm+=(point-state.pin.origin).cross(force)
	total.upper_pin_force_n=-total.bodies[1].force_n
	total.lower_pin_force_n=-total.upper_pin_force_n
	total.upper_pin_moment_nm=-(total.bodies[1].pin_moment_nm-state.pin.basis.x*total.hinge_nm)
	total.lower_pin_moment_nm=-total.upper_pin_moment_nm
	total.erase("energy_j")
	total.scope="free assembly plus one frozen actual contact feature; finite membership and stability unverified"
	var gap: float=(point-contact.surface).dot(contact.normal)-contact.clearance
	var residual := PackedFloat64Array([total.force_n.x,total.force_n.y,total.force_n.z,total.moment_nm.x/.1,total.moment_nm.y/.1,total.moment_nm.z/.1,total.hinge_nm/.1,result.length_error_m*10000,result.aft_moment.x/.1,result.aft_moment.y/.1,result.aft_moment.z/.1,gap*10000])
	var cost := 0.0
	for value in residual: cost+=value*value
	result["contact_wrench"]=total
	result["reaction_n"]=reaction
	result["contact_gap_error_m"]=gap
	result["contact_point"]=point
	result["residual"]=residual
	result["cost"]=cost
	return result
static func moved(state: Dictionary,tension: float,reaction: float,step: PackedFloat64Array,scale: float,boundary: Dictionary) -> Dictionary:
	var result := MODEL._move(state,tension,step.slice(0,11),scale,boundary)
	result["reaction"]=reaction+step[11]*scale*10
	return result
static func converged(result: Dictionary) -> bool:
	if not result.get("valid",false) or result.reaction_n<0: return false
	var wrench: Dictionary=result.contact_wrench
	return wrench.force_n.length()<MODEL.FORCE_TOLERANCE*.5 and wrench.moment_nm.length()<MODEL.MOMENT_TOLERANCE*.5 and absf(wrench.hinge_nm)<MODEL.MOMENT_TOLERANCE*.5 and result.aft_moment.length()<MODEL.MOMENT_TOLERANCE*.5 and absf(result.length_error_m)<MODEL.LENGTH_TOLERANCE*.5 and absf(result.contact_gap_error_m)<MODEL.LENGTH_TOLERANCE*.5
static func merit(result: Dictionary,weight: float) -> float:
	var cost := 0.0
	for i in result.residual.size(): cost+=pow(result.residual[i]*(weight if i in [7,11] else 1.0),2)
	return cost
static func load_column(current: Dictionary,contact: Dictionary,coordinate: int) -> PackedFloat64Array:
	var force: Vector3=current.lower.sheave.support_force_per_n if coordinate==7 else contact.normal
	var moment: Vector3=current.lower.sheave.moment_per_n if coordinate==7 else (current.contact_point-current.state.lower.origin).cross(contact.normal)
	var hinge := 0.0
	if coordinate==11 and contact.body==1: hinge=(current.contact_point-current.state.pin.origin).cross(contact.normal).dot(current.state.pin.basis.x)
	return PackedFloat64Array([force.x*10,force.y*10,force.z*10,moment.x*100,moment.y*100,moment.z*100,hinge*100,0,0,0,0,0])
static func solve(boundary: Dictionary,initial: Dictionary,load: Dictionary,length: float,tension: float,contact: Dictionary,maximum_msec := 16000,stop := Callable(),starting_reaction := .1) -> Dictionary:
	if not valid_contact(contact) or not MODEL.FREE.valid(initial) or not initial.get("aft") is Transform3D or not MODEL.ROUTE.PIN.rigid(initial.aft) or not MODEL._load_valid(load) or not is_finite(length) or length<=0 or not is_finite(tension) or tension<=0 or maximum_msec<=0:
		return {"valid":false,"converged":false,"reason":"invalid finite contact solve"}
	if not boundary.get("purchase") is Dictionary or not boundary.purchase.has_all(["mount","eye"]): return {"valid":false,"converged":false,"reason":"invalid finite purchase boundary"}
	if not is_finite(starting_reaction) or starting_reaction<0: return {"valid":false,"converged":false,"reason":"invalid initial contact reaction"}
	var began := Time.get_ticks_usec()
	var deadline := began+maximum_msec*1000
	var halted := func(): return Time.get_ticks_usec()>deadline or (stop.is_valid() and stop.call())
	var state := initial.duplicate(true)
	for key in state.get("profiles",{}):
		if state.profiles[key].size()!=25:
			state.erase("profiles")
			break
	var current := evaluate(state,tension,starting_reaction,boundary,load,length,contact,25,deadline,halted)
	if not current.valid: return current
	var trace := []
	var reason := "iteration limit"
	for iteration in 80:
		if halted.call():
			reason="contact diagnostic budget exhausted"
			break
		trace.append({"iteration":iteration,"cost":current.cost,"reaction":current.reaction_n,"force":current.contact_wrench.force_n.length(),"gap_error":current.contact_gap_error_m,"length_error":current.length_error_m})
		if converged(current):
			reason="frozen actual feature force and length stationary; membership unverified"
			break
		# Once both geometric constraints are much tighter than acceptance,
		# balance their merit units with force instead of letting nanometre
		# float32 noise dominate a still-unacceptable force residual. The
		# physical stopping limits are unchanged, and trial points must stay
		# inside those strict geometric limits while this filter is active.
		var weight := .005 if maxf(absf(current.length_error_m),absf(current.contact_gap_error_m))<MODEL.LENGTH_TOLERANCE*.25 else 1.0
		var search_cost := merit(current,weight)
		var jacobian := []
		var valid := true
		for coordinate in 12:
			if coordinate in [7,11]:
				# At fixed geometry these two amplitudes enter the wrench
				# exactly linearly. Re-solving every rope twice adds no data.
				jacobian.append(load_column(current,contact,coordinate))
				continue
			var step := PackedFloat64Array()
			step.resize(12)
			var h := .0001
			var a := {}
			var b := {}
			for refinement in 6:
				step[coordinate]=h
				var left := moved(current.state,current.tension,current.reaction_n,step,-1,boundary)
				var right := moved(current.state,current.tension,current.reaction_n,step,1,boundary)
				a=evaluate(left.state,left.tension,left.reaction,boundary,load,length,contact,25,deadline,halted)
				b=evaluate(right.state,right.tension,right.reaction,boundary,load,length,contact,25,deadline,halted)
				if a.valid and b.valid: break
				h*=.5
			if not a.valid or not b.valid:
				valid=false
				reason="contact derivative: "+a.get("reason","")+" / "+b.get("reason","")
				break
			var column := PackedFloat64Array()
			for i in 12: column.append((b.residual[i]-a.residual[i])/(2*h))
			if coordinate<3: column[7]=-current.lower.sheave.support_force_per_n[coordinate]*1000
			elif coordinate<6: column[7]=-current.lower.sheave.moment_per_n[coordinate-3]*10000
			else: column[7]=0
			jacobian.append(column)
		if not valid: break
		var matrix := []
		var rhs := PackedFloat64Array()
		for i in 12:
			var row := PackedFloat64Array()
			var value := 0.0
			for k in 12: value-=jacobian[i][k]*current.residual[k]*(weight*weight if k in [7,11] else 1.0)
			rhs.append(value)
			for j in 12:
				var cell := .00001 if i==j else 0.0
				for k in 12: cell+=jacobian[i][k]*jacobian[j][k]*(weight*weight if k in [7,11] else 1.0)
				row.append(cell)
			matrix.append(row)
		var step := MODEL.LINEAR._linear(matrix,rhs)
		if step.is_empty():
			reason="singular contact derivative"
			break
		var scale := minf(1,.1/maxf(MODEL.LINEAR._maximum(step),.000001))
		var accepted := false
		for backtrack in 16:
			var next := moved(current.state,current.tension,current.reaction_n,step,scale,boundary)
			var candidate := evaluate(next.state,next.tension,next.reaction,boundary,load,length,contact,25,deadline,halted)
			var feasible: bool=candidate.valid and (weight==1.0 or maxf(absf(candidate.length_error_m),absf(candidate.contact_gap_error_m))<MODEL.LENGTH_TOLERANCE*.5)
			if feasible and (converged(candidate) or merit(candidate,weight)<search_cost):
				current=candidate
				accepted=true
				break
			if halted.call(): break
			scale*=.5
		if not accepted:
			reason="no contact descent"
			break
	current["converged"]=converged(current)
	current["reason"]=reason
	current["trace"]=trace
	current["elapsed_ms"]=(Time.get_ticks_usec()-began)/1000.0
	current["geometry_certified"]=false
	current["stability_certified"]=false
	return current

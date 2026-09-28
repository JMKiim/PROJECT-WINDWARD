extends RefCounted

## Seven physical coordinates: translation, common rotation, and one hinge.
## No fixed pivot reaction is supplied or silently removed from the residual.
const PIN := preload("res://src/boat/revolute_pin_joint.gd")

static func compose(boundary: Dictionary,lower: Transform3D,angle: float) -> Dictionary:
	if not boundary.has_all(["lower_eye","upper_eye","minimum","maximum"]) or not PIN.rigid(lower): return {"valid":false,"reason":"invalid free assembly boundary"}
	for key in ["lower_eye","upper_eye"]:
		if not boundary[key] is Transform3D or not PIN.rigid(boundary[key]): return {"valid":false,"reason":"invalid eye"}
	for key in ["minimum","maximum"]:
		if not (boundary[key] is float or boundary[key] is int) or not is_finite(boundary[key]): return {"valid":false,"reason":"invalid stops"}
	var pin: Transform3D=lower*boundary.lower_eye
	var joint := PIN.compose(pin,boundary.upper_eye,angle,boundary.minimum,boundary.maximum)
	if not joint.valid: return joint
	return {"valid":true,"lower":lower,"upper":joint.body,"pin":pin,"angle":angle,"boundary":boundary.duplicate(true)}

static func valid(state: Dictionary) -> bool:
	if state.get("valid")!=true or not state.has_all(["lower","upper","pin","angle","boundary"]): return false
	if not state.boundary is Dictionary or not (state.angle is float or state.angle is int): return false
	for key in ["lower","upper","pin"]:
		if not state[key] is Transform3D or not PIN.rigid(state[key]): return false
	var rebuilt := compose(state.boundary,state.lower,state.angle)
	if not rebuilt.valid: return false
	for key in ["upper","pin"]:
		if rebuilt[key].origin.distance_to(state[key].origin)>.0000003 or not rebuilt[key].basis.is_equal_approx(state[key].basis): return false
	return true

static func perturb(state: Dictionary,coordinate: int,amount: float) -> Dictionary:
	if not valid(state) or coordinate<0 or coordinate>6 or not is_finite(amount): return {"valid":false,"reason":"invalid free assembly perturbation"}
	var lower: Transform3D=state.lower
	var angle: float=state.angle
	if coordinate<3: lower.origin[coordinate]+=amount
	elif coordinate<6:
		var axis := Vector3.ZERO
		axis[coordinate-3]=1
		lower.basis=(Basis(axis,amount)*lower.basis).orthonormalized()
	else: angle+=amount
	return compose(state.boundary,lower,angle)

static func evaluate(state: Dictionary,lower_loads: Array,upper_loads: Array,datum := Vector3.ZERO) -> Dictionary:
	if not valid(state) or not datum.is_finite(): return {"valid":false,"reason":"invalid free assembly load state"}
	var force := Vector3.ZERO
	var moment := Vector3.ZERO
	var hinge := 0.0
	var energy := 0.0
	var bodies := []
	for group in [[state.lower,lower_loads,false],[state.upper,upper_loads,true]]:
		var body_force := Vector3.ZERO
		var pin_moment := Vector3.ZERO
		for item in group[1]:
			if not item is Dictionary or not item.has_all(["point","force"]) or not item.point is Vector3 or not item.force is Vector3 or not item.point.is_finite() or not item.force.is_finite(): return {"valid":false,"reason":"invalid free assembly load"}
			var point: Vector3=group[0]*item.point
			body_force+=item.force
			pin_moment+=(point-state.pin.origin).cross(item.force)
			moment+=(point-state.lower.origin).cross(item.force)
			for axis in 3: energy-=(float(point[axis])-float(datum[axis]))*float(item.force[axis])
		force+=body_force
		if group[2]: hinge=pin_moment.dot(state.pin.basis.x)
		bodies.append({"force_n":body_force,"pin_moment_nm":pin_moment})
	# Bearing transmits force and two moments; it cannot absorb hinge-axis drive.
	var reaction: Vector3=-bodies[1].force_n
	var bearing: Vector3=-(bodies[1].pin_moment_nm-state.pin.basis.x*hinge)
	return {"valid":true,"force_n":force,"moment_nm":moment,"hinge_nm":hinge,"drive":PackedFloat64Array([force.x,force.y,force.z,moment.x,moment.y,moment.z,hinge]),"energy_j":energy,"bodies":bodies,"upper_pin_force_n":reaction,"lower_pin_force_n":-reaction,"upper_pin_moment_nm":bearing,"lower_pin_moment_nm":-bearing,"scope":"free assembly wrench; not a contact or equilibrium certificate"}

static func contact(state: Dictionary,kind: int,point: Vector3,normal: Vector3,gap: float,other := Vector3(NAN,NAN,NAN)) -> Dictionary:
	# Same equal/opposite pair acts on all seven coordinates. Mutual contact
	# must never produce an external translational support force.
	if not valid(state) or kind<0 or kind>2 or not point.is_finite() or not normal.is_finite() or normal.length()<1e-9 or not is_finite(gap) or (kind==2 and not other.is_finite()): return {"valid":false,"reason":"invalid free assembly contact"}
	var n := normal.normalized()
	var linear := Vector3.ZERO if kind==2 else n
	var moment: Vector3=(point-(other if kind==2 else state.lower.origin)).cross(n)
	var hinge: float=0 if kind==0 else (point-state.pin.origin).cross(n).dot(state.pin.basis.x)
	return {"valid":true,"kind":kind,"gap":gap,"normal":n,"point":point,"other":other,"gradient":PackedFloat64Array([linear.x,linear.y,linear.z,moment.x,moment.y,moment.z,hinge]),"multiplier_units":"N"}

static func stops(state: Dictionary) -> Array:
	if not valid(state): return []
	return [{"valid":true,"kind":"lower_stop","gap":state.angle-state.boundary.minimum,"gradient":PackedFloat64Array([0,0,0,0,0,0,1]),"gap_units":"radians","multiplier_units":"Nm"},{"valid":true,"kind":"upper_stop","gap":state.boundary.maximum-state.angle,"gradient":PackedFloat64Array([0,0,0,0,0,0,-1]),"gap_units":"radians","multiplier_units":"Nm"}]

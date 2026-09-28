extends RefCounted

## Provisional twisted-neck assembly: pin parallel to the upper sheave,
## perpendicular to the lower. Actual product dimensions remain unmeasured.
## Fixed material geometry only, not a coupled tension/contact equilibrium.
const SUPPORT := preload("res://src/boat/traveller_supported_route.gd")
const PIN := preload("res://src/boat/revolute_pin_joint.gd")
const CABLE := preload("res://src/boat/cylinder_cable_route.gd")

static func _trial(boundary: Dictionary,length: float,x: float,azimuth: float,a: Vector3,b: Vector3) -> Dictionary:
	var support := SUPPORT.fit(boundary,length,x,azimuth)
	if not support.valid: return support
	var axis: Vector3=(a-support.center).cross(b-a)
	if axis.length_squared()<1e-14: return {"valid":false,"reason":"indeterminate upper plane"}
	axis=axis.normalized()
	return {"valid":true,"support":support,"axis":axis,"error":axis.dot(support.frame.basis.x),"azimuth":azimuth}

static func _shift_cable(cable: Dictionary,offset: Vector3) -> void:
	for key in ["entry","exit"]:
		if cable.has(key): cable[key]+=offset
	for key in ["path","arc_path"]:
		if cable.has(key): cable[key]=Transform3D(Basis.IDENTITY,offset)*cable[key]

static func solve(boundary: Dictionary,length: float,x: float,a: Vector3,b: Vector3,lower_eye: Transform3D,upper_eye: Transform3D,radius: float,minimum: float,maximum: float) -> Dictionary:
	if not SUPPORT._valid(boundary): return {"valid":false,"reason":"invalid orthogonal support boundary"}
	# The sheave is centimetres across, while the rig origin is metres away.
	# Root finding must not quantize the centre at the far origin each step.
	var datum: Vector3=(boundary.port+boundary.starboard)*.5
	var local := boundary.duplicate(true)
	local.port-=datum
	local.starboard-=datum
	local.tiller.origin-=datum
	var result := _solve_local(local,length,x,a-datum,b-datum,lower_eye,upper_eye,radius,minimum,maximum)
	if not result.valid: return result
	for key in ["lower","upper","pin"]: result[key].origin+=datum
	result.support.center+=datum
	result.support.frame.origin+=datum
	result.support.path=Transform3D(Basis.IDENTITY,datum)*result.support.path
	for key in ["approach","departure","sheave"]: _shift_cable(result.support[key],datum)
	_shift_cable(result.upper_route,datum)
	var measured := PIN.measure(result.pin,result.upper,upper_eye,minimum,maximum)
	var inverse: Transform3D=result.upper.affine_inverse()
	result.plane_error_m=maxf(absf((inverse*a).x),absf((inverse*b).x))
	if not measured.valid or result.plane_error_m>CABLE.PLANE_TOLERANCE:
		return {"valid":false,"reason":"translated pin or groove tolerance not reached","joint":measured,"plane_error_m":result.plane_error_m}
	result.joint=measured
	return result

static func _solve_local(boundary: Dictionary,length: float,x: float,a: Vector3,b: Vector3,lower_eye: Transform3D,upper_eye: Transform3D,radius: float,minimum: float,maximum: float) -> Dictionary:
	if not is_finite(length) or length<=0 or not is_finite(x) or not is_finite(radius) or radius<=0 or not is_finite(minimum) or not is_finite(maximum) or minimum>=maximum or minimum< -PI or maximum>PI:
		return {"valid":false,"reason":"invalid orthogonal route dimensions or limits"}
	if not a.is_finite() or not b.is_finite() or not PIN.rigid(lower_eye) or not PIN.rigid(upper_eye) or not lower_eye.basis.is_equal_approx(Basis(Vector3.UP,PI*.5)) or not upper_eye.basis.is_equal_approx(Basis(Vector3.BACK,PI)) or lower_eye.origin.y<=0 or upper_eye.origin.y<=0 or Vector2(lower_eye.origin.x,lower_eye.origin.z).length()>1e-9 or Vector2(upper_eye.origin.x,upper_eye.origin.z).length()>1e-9:
		return {"valid":false,"reason":"invalid orthogonal head contract"}
	var previous := {}
	var root := {}
	var low := {}
	var high := {}
	# Bracket only the supported connected interval. A failure clears the
	# bracket; no root is interpolated across an invalid contact topology.
	for degree in range(-75,76,5):
		var trial := _trial(boundary,length,x,deg_to_rad(degree),a,b)
		if not trial.valid:
			previous={}
			continue
		if absf(trial.error)<.0000002:
			root=trial
			break
		if not previous.is_empty() and previous.error*trial.error<0:
			low=previous
			high=trial
			break
		previous=trial
	if root.is_empty() and low.is_empty(): return {"valid":false,"reason":"no orthogonal-plane root in supported interval"}
	if root.is_empty():
		root=low if absf(low.error)<absf(high.error) else high
		for iteration in 28:
			var trial := _trial(boundary,length,x,(low.azimuth+high.azimuth)*.5,a,b)
			if not trial.valid: return {"valid":false,"reason":"unsupported interior contact topology"}
			if absf(trial.error)<absf(root.error): root=trial
			if absf(root.error)<.0000002: break
			if low.error*trial.error<0: high=trial
			else: low=trial
	if absf(root.error)>.000001: return {"valid":false,"reason":"orthogonal-plane tolerance not reached","axis_error":root.error}
	var normal: Vector3=root.support.frame.basis.x
	# Remove only the certified sub-microradian root roundoff. The actual
	# endpoints are checked against the resulting rigid groove below.
	var pin_axis: Vector3=(root.axis-normal*normal.dot(root.axis)).normalized()
	var up := normal.cross(pin_axis).normalized()
	if up.dot(root.support.frame.basis.y)<0:
		up=-up
		pin_axis=-pin_axis
	var lower := Transform3D(Basis(normal,up,normal.cross(up)),root.support.center)
	var pin := lower*lower_eye
	var toward := (a+b)*.5-pin.origin
	toward=(toward-pin.basis.x*pin.basis.x.dot(toward)).normalized()
	if toward.is_zero_approx(): return {"valid":false,"reason":"indeterminate upper head direction"}
	var zero_up := upper_eye.basis.inverse().y
	var desired := pin.basis.transposed()*(-toward)
	var angle := atan2(zero_up.cross(desired).x,zero_up.dot(desired))
	var joint := PIN.compose(pin,upper_eye,angle,minimum,maximum)
	if not joint.valid: return joint
	var cable := CABLE.route(joint.body,radius,a,b,true,true,Vector3.ZERO,INF,.0085)
	if not cable.valid: return cable
	var measured := PIN.measure(pin,joint.body,upper_eye,minimum,maximum)
	if not measured.valid: return {"valid":false,"reason":"composed joint measurement failed"}
	var inverse: Transform3D=joint.body.affine_inverse()
	return {"valid":true,"lower":lower,"upper":joint.body,"pin":pin,"angle":angle,"roll":root.support.frame.basis.y.signed_angle_to(up,normal),"support":root.support,"upper_route":cable,"joint":measured,"plane_error_m":maxf(absf((inverse*a).x),absf((inverse*b).x)),"orthogonal_error":absf(root.error),"azimuth":root.azimuth,"scope":"fixed-span plane closure with prescribed slide and bisector head direction; not force equilibrium, motion path or product measurement"}

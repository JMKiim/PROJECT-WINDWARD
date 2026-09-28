extends RefCounted

## Rigid, captive revolute datum. The eye rotates about a finite pin's X
## axis, never around an unconstrained point in solid metal. Geometry and
## stop angles must be supplied and independently checked by the caller.
static func rigid(frame: Transform3D) -> bool:
	return frame.is_finite() and absf(frame.basis.determinant()-1)<.00001 and (frame.basis.transposed()*frame.basis).is_equal_approx(Basis.IDENTITY)

static func compose(pin_frame: Transform3D,body_eye: Transform3D,angle: float,minimum: float,maximum: float) -> Dictionary:
	if not rigid(pin_frame) or not rigid(body_eye) or not is_finite(angle) or not is_finite(minimum) or not is_finite(maximum) or minimum>=maximum or minimum< -PI or maximum>PI:
		return {"valid":false,"reason":"invalid revolute pin boundary"}
	if angle<minimum or angle>maximum:
		return {"valid":false,"reason":"revolute pin outside configured stops"}
	var eye := pin_frame*Transform3D(Basis(Vector3.RIGHT,angle),Vector3.ZERO)
	return {"valid":true,"body":eye*body_eye.affine_inverse(),"eye":eye,"pin":pin_frame,"angle":angle,"axis":pin_frame.basis.x,"lower_gap_radians":angle-minimum,"upper_gap_radians":maximum-angle}

static func measure(pin_frame: Transform3D,body_frame: Transform3D,body_eye: Transform3D,minimum: float,maximum: float) -> Dictionary:
	if not rigid(pin_frame) or not rigid(body_frame) or not rigid(body_eye): return {"valid":false,"reason":"nonrigid pin measurement"}
	var eye := body_frame*body_eye
	var relative := pin_frame.affine_inverse()*eye
	var angle := atan2(relative.basis.y.z,relative.basis.y.y)
	# atan2 roundoff at a stop must not invalidate compose's exact endpoint.
	# Compare the reconstructed rotation, rather than silently accepting an
	# arbitrary out-of-range angle by clamping it.
	var bounded := clampf(angle,minimum,maximum)
	var posed := compose(pin_frame,body_eye,bounded,minimum,maximum)
	if not posed.valid: return posed
	var centre_error := relative.origin.length()
	var axis_error := relative.basis.x.distance_to(Vector3.RIGHT)
	var stop_error := relative.basis.y.distance_to(Basis(Vector3.RIGHT,bounded).y)
	return {"valid":centre_error<=.0000003 and axis_error<=.00001 and stop_error<=.0000003,"centre_error_metres":centre_error,"axis_error":axis_error,"stop_rotation_error":stop_error,"angle":bounded,"lower_gap_radians":bounded-minimum,"upper_gap_radians":maximum-bounded}

static func wrench(state: Dictionary,loads: Array) -> Dictionary:
	if state.get("valid")!=true or not state.has_all(["body","pin","axis"]) or not state.body is Transform3D or not state.pin is Transform3D or not state.axis is Vector3 or not rigid(state.body) or not rigid(state.pin) or state.axis.distance_to(state.pin.basis.x)>.00001:
		return {"valid":false,"reason":"invalid pin load state"}
	var torque := Vector3.ZERO
	var total_force := Vector3.ZERO
	var energy := 0.0
	for item in loads:
		if not item is Dictionary or not item.has_all(["point","force"]) or not item.point is Vector3 or not item.force is Vector3 or not item.point.is_finite() or not item.force.is_finite(): return {"valid":false,"reason":"invalid pin load"}
		var point: Vector3=state.body*item.point
		total_force+=item.force
		torque+=(point-state.pin.origin).cross(item.force)
		energy-=point.dot(item.force)
	var driving: float=torque.dot(state.axis)
	return {"valid":true,"energy_j":energy,"driving_torque_nm":driving,"bearing_force_n":-total_force,"bearing_moment_nm":-(torque-state.axis*driving),"scope":"prescribed-load kinematics; axial drive is not an equilibrium solution"}

static func free_equilibrium(pin_frame: Transform3D,body_eye: Transform3D,loads: Array,minimum: float,maximum: float) -> Dictionary:
	# Analytic bounded single-axis equilibrium under frozen external loads.
	# Configured stops supply a moment, not fictitious bearing-axis friction.
	# Neither geometry contact, a collision-free travel path, nor forces from
	# a coupled cable are certified by this calculation.
	var initial := compose(pin_frame,body_eye,clampf(0,minimum,maximum),minimum,maximum)
	if not initial.valid: return initial
	var initial_load := wrench(initial,loads)
	if not initial_load.valid: return initial_load
	var cosine := 0.0
	var sine := 0.0
	for item: Dictionary in loads:
		var radius: Vector3=body_eye.affine_inverse()*item.point
		var force: Vector3=pin_frame.basis.transposed()*item.force
		cosine+=force.y*radius.y+force.z*radius.z
		sine+=force.z*radius.y-force.y*radius.z
	if Vector2(cosine,sine).length()<1e-10:
		return {"valid":false,"reason":"single-axis orientation is indeterminate under these loads"}
	var candidates := [minimum,maximum]
	var stationary := atan2(sine,cosine)
	for period in [-1,0,1]:
		var angle: float=stationary+period*TAU
		if angle>=minimum and angle<=maximum: candidates.append(angle)
	var selected := minimum
	var best := INF
	for angle: float in candidates:
		var energy := -cosine*cos(angle)-sine*sin(angle)
		if energy<best:
			selected=angle
			best=energy
	var state := compose(pin_frame,body_eye,selected,minimum,maximum)
	var measured := wrench(state,loads)
	var drive: float=measured.driving_torque_nm
	var stop := 0.0
	var status := "suspended"
	if selected==minimum and drive<0:
		stop=-drive
		status="lower_stop"
	elif selected==maximum and drive>0:
		stop=-drive
		status="upper_stop"
	return {"valid":absf(drive+stop)<.000001,"joint":state,"loads":measured,"state":status,"stop_moment_nm":stop,"residual_nm":absf(drive+stop),"angular_potential_j":best,"scope":"prescribed-load ideal pin and configured stops only; finite surface contact and cable feedback not solved"}

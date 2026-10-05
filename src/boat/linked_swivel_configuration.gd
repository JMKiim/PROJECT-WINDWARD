extends RefCounted

## Detached two-body kinematics around a fixed lower support datum, joined
## by a fixed-length spherical connector. This does not constrain a finite
## metal ring, solve traveller cable support, or resolve contact dynamics.
const ROTATION := preload("res://src/boat/swivel_block_equilibrium.gd")

static func rigid(frame: Transform3D) -> bool:
	return frame.is_finite() and absf(frame.basis.determinant()-1)<.00001 and (frame.basis.transposed()*frame.basis).is_equal_approx(Basis.IDENTITY)

static func valid_configuration(configuration: Dictionary) -> bool:
	if configuration.get("valid")!=true or not configuration.has_all(["lower","upper","first","last","direction","centre","pivot"]): return false
	for key in ["lower","upper"]:
		if not configuration[key] is Transform3D or not rigid(configuration[key]): return false
	for key in ["first","last","direction","centre","pivot"]:
		if not configuration[key] is Vector3 or not configuration[key].is_finite(): return false
	var chord: Vector3=configuration.last-configuration.first
	if chord.length()<.000001 or absf(configuration.direction.length()-1)>.00001: return false
	return chord.normalized().distance_to(configuration.direction)<.0001 and configuration.centre.distance_to((configuration.first+configuration.last)*.5)<.0000003

static func matches_boundary(boundary: Dictionary,configuration: Dictionary) -> bool:
	if not valid_configuration(configuration): return false
	var expected := compose(boundary,configuration.lower.basis,configuration.direction,configuration.upper.basis)
	if not expected.valid: return false
	for key in ["first","last","pivot"]:
		if expected[key].distance_to(configuration[key])>.0000003: return false
	return expected.lower.origin.distance_to(configuration.lower.origin)<.0000003 and expected.upper.origin.distance_to(configuration.upper.origin)<.0000003

static func compose(boundary: Dictionary,lower_basis: Basis,link_direction: Vector3,upper_basis: Basis) -> Dictionary:
	if not boundary.has_all(["pivot","lower_support","lower_eye","upper_eye","link_metres"]):
		return {"valid":false,"reason":"incomplete linked swivel boundary"}
	for key in ["pivot","lower_support","lower_eye","upper_eye"]:
		if not boundary[key] is Vector3 or not boundary[key].is_finite(): return {"valid":false,"reason":"nonfinite linked swivel datum"}
	if not (boundary.link_metres is float or boundary.link_metres is int) or not is_finite(boundary.link_metres) or boundary.link_metres<=0 or not link_direction.is_finite() or link_direction.length()<.000001:
		return {"valid":false,"reason":"invalid fixed connector"}
	if not rigid(Transform3D(lower_basis,Vector3.ZERO)) or not rigid(Transform3D(upper_basis,Vector3.ZERO)):
		return {"valid":false,"reason":"linked swivel bases must remain rigid and right handed"}
	var lower := Transform3D(lower_basis,boundary.pivot-lower_basis*boundary.lower_support)
	var first: Vector3=lower*boundary.lower_eye
	var direction := link_direction.normalized()
	var last: Vector3=first+direction*boundary.link_metres
	var upper := Transform3D(upper_basis,last-upper_basis*boundary.upper_eye)
	return {"valid":true,"lower":lower,"upper":upper,"first":first,"last":last,"direction":direction,"centre":(first+last)*.5,"pivot":boundary.pivot,"link_error_metres":absf(first.distance_to(last)-boundary.link_metres),"lower_support_error_metres":(lower*boundary.lower_support).distance_to(boundary.pivot),"upper_eye_error_metres":(upper*boundary.upper_eye).distance_to(last)}

static func evaluate(configuration: Dictionary,lower_loads: Array,upper_loads: Array,link_force := Vector3.ZERO) -> Dictionary:
	if not valid_configuration(configuration) or not link_force.is_finite(): return {"valid":false,"reason":"invalid linked load configuration"}
	var lower_force := Vector3.ZERO
	var upper_force := Vector3.ZERO
	var lower_moment := Vector3.ZERO
	var upper_moment := Vector3.ZERO
	var energy := 0.0
	var groups := [[lower_loads,configuration.lower,configuration.pivot],[upper_loads,configuration.upper,configuration.last]]
	for group_index in groups.size():
		var pair: Array=groups[group_index]
		for load in pair[0]:
			if not load is Dictionary or not load.has_all(["point","force"]) or not load.point is Vector3 or not load.force is Vector3 or not load.point.is_finite() or not load.force.is_finite():
				return {"valid":false,"reason":"invalid linked prescribed load"}
			var world: Vector3=pair[1]*load.point
			if group_index==0:
				lower_force+=load.force
				lower_moment+=(world-configuration.pivot).cross(load.force)
			else:
				upper_force+=load.force
				upper_moment+=(world-configuration.last).cross(load.force)
			energy-=_potential(pair[1],load.point,load.force)
	# With world upper orientation and link direction held fixed, rotating
	# the lower body translates every upper load and the connector centre by
	# the same lower-eye displacement. The transmitted moment is essential.
	lower_moment+=(configuration.first-configuration.pivot).cross(upper_force+link_force)
	var link_moment: Vector3=(configuration.last-configuration.first).cross(upper_force+link_force*.5)
	energy-=configuration.centre.dot(link_force)
	return {"valid":true,"energy_j":energy,"lower_torque_nm":lower_moment,"link_torque_nm":link_moment,"upper_torque_nm":upper_moment,"lower_force_n":lower_force,"upper_force_n":upper_force,"fixed_support_force_n":-lower_force-upper_force-link_force,"scope":"fixed support and prescribed forces; no finite ring or cable/contact equilibrium"}

static func _potential(pose: Transform3D,point: Vector3,force: Vector3) -> float:
	var value := 0.0
	for index in 3: value+=force[index]*(pose.origin[index]+pose.basis.x[index]*point.x+pose.basis.y[index]*point.y+pose.basis.z[index]*point.z)
	return value

static func contact(configuration: Dictionary,kind: int,point: Vector3,normal: Vector3,gap: float,other_point := Vector3(NAN,NAN,NAN)) -> Dictionary:
	# kind 0: lower/static, 1: upper/static, 2: upper/lower. For a mutual
	# contact the one multiplier applies equal/opposite forces to both bodies.
	if not valid_configuration(configuration) or kind<0 or kind>2 or not point.is_finite() or not normal.is_finite() or normal.length()<.000001 or not is_finite(gap) or (kind==2 and not other_point.is_finite()):
		return {"valid":false,"reason":"invalid linked contact witness"}
	var direction := normal.normalized()
	var lower := Vector3.ZERO
	var link := Vector3.ZERO
	var upper := Vector3.ZERO
	if kind==0:
		lower=(point-configuration.pivot).cross(direction)
	else:
		lower=(configuration.first-(other_point if kind==2 else configuration.pivot)).cross(direction)
		link=(configuration.last-configuration.first).cross(direction)
		upper=(point-configuration.last).cross(direction)
	return {"valid":true,"kind":kind,"point":point,"other_point":other_point,"normal":direction,"gap":gap,"gradient":PackedFloat64Array([lower.x,lower.y,lower.z,link.x,link.y,link.z,upper.x,upper.y,upper.z])}

static func generalized(state: Dictionary) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for key in ["lower_torque_nm","link_torque_nm","upper_torque_nm"]:
		var moment: Vector3=state[key]
		result.append_array(PackedFloat64Array([moment.x,moment.y,moment.z]))
	return result

static func rotation_delta(first: Dictionary,last: Dictionary) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	var lower := ROTATION.rotation_vector(first.lower.basis,last.lower.basis)
	var crossed: Vector3=first.direction.cross(last.direction)
	var link := crossed.normalized()*atan2(crossed.length(),clampf(first.direction.dot(last.direction),-1,1)) if crossed.length()>1e-12 else Vector3.ZERO
	var upper := ROTATION.rotation_vector(first.upper.basis,last.upper.basis)
	for value in [lower,link,upper]: result.append_array(PackedFloat64Array([value.x,value.y,value.z]))
	return result

static func perturb(boundary: Dictionary,configuration: Dictionary,body: int,axis: Vector3,angle: float) -> Dictionary:
	if not valid_configuration(configuration) or body<0 or body>2 or not axis.is_finite() or axis.length()<.000001 or not is_finite(angle):
		return {"valid":false,"reason":"invalid linked rotation"}
	var rotation := Basis(axis.normalized(),angle)
	var lower: Basis=configuration.lower.basis
	var upper: Basis=configuration.upper.basis
	var direction: Vector3=configuration.direction
	if body==0: lower=(rotation*lower).orthonormalized()
	elif body==1: direction=rotation*direction
	else: upper=(rotation*upper).orthonormalized()
	return compose(boundary,lower,direction,upper)

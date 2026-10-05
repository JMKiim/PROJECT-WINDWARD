extends RefCounted

## Two rigid blocks share ONE revolute pin. Three lower-support rotations
## carry both bodies; the fourth coordinate rotates only the upper body.
## The lower support is fixed here, not solved from the traveller rope.
const PIN := preload("res://src/boat/revolute_pin_joint.gd")

static func compose(boundary: Dictionary,lower_basis: Basis,angle: float) -> Dictionary:
	if not boundary.has_all(["pivot","lower_support","lower_eye","upper_eye","minimum","maximum"]): return {"valid":false,"reason":"incomplete pinned-block boundary"}
	for key in ["pivot","lower_support"]:
		if not boundary[key] is Vector3 or not boundary[key].is_finite(): return {"valid":false,"reason":"invalid pinned-block support"}
	for key in ["lower_eye","upper_eye"]:
		if not boundary[key] is Transform3D or not PIN.rigid(boundary[key]): return {"valid":false,"reason":"invalid rigid eye frame"}
	for key in ["minimum","maximum"]:
		if not (boundary[key] is float or boundary[key] is int) or not is_finite(boundary[key]): return {"valid":false,"reason":"invalid pin stop"}
	if not PIN.rigid(Transform3D(lower_basis,Vector3.ZERO)): return {"valid":false,"reason":"nonrigid lower-block basis"}
	var lower := Transform3D(lower_basis,boundary.pivot-lower_basis*boundary.lower_support)
	var pin: Transform3D=lower*boundary.lower_eye
	var joint := PIN.compose(pin,boundary.upper_eye,angle,boundary.minimum,boundary.maximum)
	if not joint.valid: return joint
	return {"valid":true,"lower":lower,"upper":joint.body,"pin":pin,"angle":angle,"pivot":boundary.pivot,"boundary":boundary.duplicate(true),"joint":joint}

static func valid(configuration: Dictionary) -> bool:
	if configuration.get("valid")!=true or not configuration.has_all(["lower","upper","pin","angle","pivot","boundary"]): return false
	for key in ["lower","upper","pin"]:
		if not configuration[key] is Transform3D or not PIN.rigid(configuration[key]): return false
	if not configuration.pivot is Vector3 or not configuration.boundary is Dictionary or not (configuration.angle is float or configuration.angle is int): return false
	var rebuilt := compose(configuration.boundary,configuration.lower.basis,configuration.angle)
	if not rebuilt.valid: return false
	for key in ["lower","upper","pin"]:
		var expected: Transform3D=rebuilt[key]
		var measured: Transform3D=configuration[key]
		if expected.origin.distance_to(measured.origin)>.0000003 or not expected.basis.is_equal_approx(measured.basis): return false
	return rebuilt.pivot.distance_to(configuration.pivot)<.0000003

static func perturb(configuration: Dictionary,coordinate: int,amount: float) -> Dictionary:
	if not valid(configuration) or coordinate<0 or coordinate>3 or not is_finite(amount): return {"valid":false,"reason":"invalid pinned-block perturbation"}
	var lower: Basis=configuration.lower.basis
	var angle: float=configuration.angle
	if coordinate<3:
		var axis := Vector3.ZERO
		axis[coordinate]=1
		lower=(Basis(axis,amount)*lower).orthonormalized()
	else: angle+=amount
	return compose(configuration.boundary,lower,angle)

static func evaluate(configuration: Dictionary,lower_loads: Array,upper_loads: Array) -> Dictionary:
	if not valid(configuration): return {"valid":false,"reason":"invalid pinned-block load state"}
	var base_moment := Vector3.ZERO
	var hinge_moment := 0.0
	var total_force := Vector3.ZERO
	var energy := 0.0
	for group in [[configuration.lower,lower_loads,false],[configuration.upper,upper_loads,true]]:
		for item in group[1]:
			if not item is Dictionary or not item.has_all(["point","force"]) or not item.point is Vector3 or not item.force is Vector3 or not item.point.is_finite() or not item.force.is_finite(): return {"valid":false,"reason":"invalid pinned-block load"}
			var point: Vector3=group[0]*item.point
			base_moment+=(point-configuration.pivot).cross(item.force)
			if group[2]: hinge_moment+=(point-configuration.pin.origin).cross(item.force).dot(configuration.pin.basis.x)
			total_force+=item.force
			# A fixed support contributes only a constant potential. Subtract it
			# before accumulating in scalar precision; a world-space Vector3 dot
			# otherwise loses small contact-descent energies to float rounding.
			for axis in 3: energy-=(float(point[axis])-float(configuration.pivot[axis]))*float(item.force[axis])
	return {"valid":true,"energy_j":energy,"gradient":PackedFloat64Array([base_moment.x,base_moment.y,base_moment.z,hinge_moment]),"support_force_n":-total_force,"scope":"four-coordinate prescribed-load model; geometry contact and traveller-cable support still external"}

static func contact(configuration: Dictionary,kind: int,point: Vector3,normal: Vector3,gap: float,other := Vector3(NAN,NAN,NAN)) -> Dictionary:
	# 0 lower/static, 1 upper/static, 2 upper/lower: one equal/opposite
	# reaction acts on every affected coordinate, never two unrelated forces.
	if not valid(configuration) or kind<0 or kind>2 or not point.is_finite() or not normal.is_finite() or normal.length()<1e-9 or not is_finite(gap) or (kind==2 and not other.is_finite()): return {"valid":false,"reason":"invalid pinned-block contact"}
	var n := normal.normalized()
	var moment: Vector3=(point-(other if kind==2 else configuration.pivot)).cross(n)
	var hinge: float=0 if kind==0 else (point-configuration.pin.origin).cross(n).dot(configuration.pin.basis.x)
	return {"valid":true,"kind":kind,"gap":gap,"point":point,"other":other,"normal":n,"gradient":PackedFloat64Array([moment.x,moment.y,moment.z,hinge]),"multiplier_units":"N"}

static func stops(configuration: Dictionary) -> Array:
	if not valid(configuration): return []
	return [{"valid":true,"kind":"lower_stop","gap":configuration.angle-configuration.boundary.minimum,"gradient":PackedFloat64Array([0,0,0,1]),"gap_units":"radians","multiplier_units":"Nm"},{"valid":true,"kind":"upper_stop","gap":configuration.boundary.maximum-configuration.angle,"gradient":PackedFloat64Array([0,0,0,-1]),"gap_units":"radians","multiplier_units":"Nm"}]

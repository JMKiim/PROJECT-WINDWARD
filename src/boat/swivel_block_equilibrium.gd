extends RefCounted

## Fixed spherical attachment, prescribed world-space loads and unilateral
## support. Rotation is optimized on SO(3), not by changing a body's scale or
## searching authored sailor poses. Cable feedback belongs to the caller.
const CONTACT_GAP := .00005
const GAP_TOLERANCE := .000002
const TORQUE_TOLERANCE := .00001
const ANGLE_LIMIT := PI/90.0
const DIFFERENCE_STEP := .0005
const MAX_ITERATIONS := 240
const CONE := preload("res://src/boat/contact_cone_projection.gd")

static func solve(rest: Transform3D,attachment: Vector3,centre_of_mass: Vector3,mass: float,gravity: Vector3,loads: Array,clearance: Callable,constraints := Callable(),maximum_msec := 20000,cancelled := Callable(),torque_tolerance := TORQUE_TOLERANCE) -> Dictionary:
	var started := Time.get_ticks_usec()
	if not is_finite(torque_tolerance) or torque_tolerance<=0 or torque_tolerance>TORQUE_TOLERANCE:
		return {"valid":false,"reason":"swivel tolerance may only tighten the standard balance contract"}
	if not rest.is_finite() or not attachment.is_finite() or not centre_of_mass.is_finite() or not gravity.is_finite() or not is_finite(mass) or mass<=0 or gravity.length()<.0001 or not clearance.is_valid():
		return {"valid":false,"reason":"invalid spherical swivel boundary"}
	if absf(rest.basis.determinant()-1)>.00001 or not (rest.basis.transposed()*rest.basis).is_equal_approx(Basis.IDENTITY):
		return {"valid":false,"reason":"swivel rest frame must be rigid and right handed"}
	var forces := [{"point":centre_of_mass,"force":mass*gravity}]
	for load in loads:
		if not load is Dictionary or not load.has_all(["point","force"]) or not load.point is Vector3 or not load.force is Vector3 or not load.point.is_finite() or not load.force.is_finite():
			return {"valid":false,"reason":"invalid prescribed swivel load"}
		forces.append(load)
	# Evaluate potential and torque from body-space attachment radii. Taking
	# the difference of two float world positions loses the tiny final work.
	for index in forces.size():
		forces[index]={"point":forces[index].point-attachment,"force":forces[index].force}
	var pivot := rest*attachment
	var pose := rest
	var contact: Dictionary=clearance.call(pose)
	if not _valid_contact(contact) or contact.gap<CONTACT_GAP-GAP_TOLERANCE:
		return {"valid":false,"reason":"initial spherical swivel penetrates guard","contact":contact}
	var initial_energy := _energy(pose,pivot,forces)
	var trace := []
	var reaction := 0.0
	var gradient := Vector3.ZERO
	var residual := INF
	var previous_direction := Vector3.ZERO
	var reactions := []
	var contact_step := ANGLE_LIMIT*.125
	var previous_surface := ""
	for iteration in MAX_ITERATIONS:
		if cancelled.is_valid() and cancelled.call(): return {"valid":false,"cancelled":true,"reason":"swivel work cancelled"}
		if Time.get_ticks_usec()-started>maximum_msec*1000:
			return {"valid":false,"reason":"spherical swivel work budget exceeded","pose":pose,"contact":contact,"balance_nm":residual,"trace":trace}
		var torque := _torque(pose,pivot,forces)
		var direction := torque
		var contacts := _contacts(pose,pivot,clearance,constraints,.00015,attachment)
		reaction=0
		gradient=Vector3.ZERO
		if constraints.is_valid():
			var active := []
			for witness: Dictionary in contacts:
				if witness.gap<=CONTACT_GAP+GAP_TOLERANCE:
					var item := witness.duplicate()
					item["actual_gap"]=witness.gap
					item.gap=CONTACT_GAP
					active.append(item)
			var projected := projection(torque,active)
			direction=projected.value
			reactions=projected.reactions
		elif contact.gap<CONTACT_GAP+.00002:
			gradient=_gradient(pose,pivot,clearance,attachment)
			if not gradient.is_finite(): return {"valid":false,"reason":"invalid swivel contact derivative"}
			if gradient.length_squared()>1e-12:
				reaction=maxf(0,-torque.dot(gradient)/gradient.length_squared())
				direction+=gradient*reaction
		residual=direction.length()
		trace.append({"iteration":iteration,"energy":_energy(pose,pivot,forces),"gap":contact.gap,"residual_nm":residual,"witnesses":contacts.size(),"reactions":reactions.size()})
		if residual<torque_tolerance:
			# A zero first derivative at an inverted pendulum is not a stable
			# equilibrium. Verify nearby feasible orientations independently.
			var escape := _escape(pose,pivot,forces,clearance,attachment)
			if escape.is_zero_approx():
				return {"valid":true,"pose":pose,"pivot":pivot,"pivot_error":(pose*attachment).distance_to(pivot),"state":"contact" if reaction>0 or (direction-torque).length()>TORQUE_TOLERANCE else "suspended","contact":contact,"torque_nm":torque,"contact_generalized_force_n":reaction,"contact_torque_nm":direction-torque,"reactions":reactions,"gap_gradient_m":gradient,"balance_nm":residual,"energy_change_j":_energy(pose,pivot,forces)-initial_energy,"iterations":iteration+1,"trace":trace}
			direction=escape
		var scale := 0.0
		for force: Dictionary in forces: scale+=force.point.length()*force.force.length()
		var angle := minf(ANGLE_LIMIT,maxf(.00001,direction.length()/maxf(scale,1e-8)))
		# Begin cautiously at a new contact, then increase only after an actual
		# feasible energy-decreasing step. Geometry guards are unchanged.
		var surface: String=contact.get("surface","")
		if surface!=previous_surface: contact_step=ANGLE_LIMIT*.125
		previous_surface=surface
		if not contacts.is_empty(): angle=minf(angle,contact_step)
		var axis := direction.normalized()
		if axis.dot(previous_direction)<-.5: angle*=.5
		previous_direction=axis
		var energy := _energy(pose,pivot,forces)
		var accepted := false
		var line_search := []
		for backtrack in 18:
			var step := project(axis*angle,contacts)
			if not step.is_finite() or step.length()<1e-9:
				angle*=.5
				continue
			var candidate := rotated(pose,pivot,step.normalized(),step.length(),attachment)
			var repaired := _feasible(candidate,pivot,clearance,constraints,attachment,.000000001 if torque_tolerance<TORQUE_TOLERANCE and residual<TORQUE_TOLERANCE*5 else .0000001)
			var microscopic := false
			var attempt := {"angle":step.length(),"feasible":repaired.valid}
			if repaired.valid and torque_tolerance<TORQUE_TOLERANCE and _energy(repaired.pose,pivot,forces)>=energy-1e-13 and step.length()<.001:
				# The tighter inner solve may reach the float32 basis energy
				# resolution before its torque target. Only accept an independently
				# smaller constrained moment, positive mechanical work, and an
				# energy difference within the rigid-coordinate rounding bound.
				var next_torque := _torque(repaired.pose,pivot,forces)
				var next_contacts := _contacts(repaired.pose,pivot,clearance,constraints,.00015,attachment)
				var next_active := []
				for witness: Dictionary in next_contacts:
					if witness.gap<=CONTACT_GAP+GAP_TOLERANCE:
						var copy := witness.duplicate()
						copy.gap=CONTACT_GAP
						next_active.append(copy)
				var next_residual: float=projection(next_torque,next_active).value.length()
				var actual := rotation_vector(pose.basis,repaired.pose.basis)
				var work: float=(torque+next_torque).dot(actual)*.5
				attempt.merge({"gap":repaired.contact.gap,"next_residual":next_residual,"work":work,"energy_change":_energy(repaired.pose,pivot,forces)-energy,"resolution":8*5.960464477539063e-8*scale})
				microscopic=actual.length()<.001 and work>1e-15 and next_residual<residual-maxf(1e-8,residual*.01) and _energy(repaired.pose,pivot,forces)-energy<=8*5.960464477539063e-8*scale
			if torque_tolerance<TORQUE_TOLERANCE: line_search.append(attempt)
			if repaired.valid and (_energy(repaired.pose,pivot,forces)<energy-1e-13 or microscopic):
				pose=repaired.pose
				contact=repaired.contact
				accepted=true
				if not contacts.is_empty():
					contact_step=clampf(contact_step*(1.3 if backtrack==0 and repaired.get("corrections",0)<=1 else .65),.0005,ANGLE_LIMIT)
				break
			angle*=.5
		if not accepted:
			return {"valid":false,"reason":"spherical swivel descent stalled","pose":pose,"contact":contact,"balance_nm":residual,"trace":trace,"line_search":line_search}
	return {"valid":false,"reason":"spherical swivel iteration limit","pose":pose,"contact":contact,"balance_nm":residual,"trace":trace}

static func rotation_vector(first: Basis,last: Basis) -> Vector3:
	var turn := last.get_rotation_quaternion()*first.get_rotation_quaternion().inverse()
	if turn.w<0: turn=-turn
	var imaginary := Vector3(turn.x,turn.y,turn.z)
	return imaginary.normalized()*(2*atan2(imaginary.length(),turn.w)) if imaginary.length()>1e-12 else Vector3.ZERO

static func _valid_contact(value: Dictionary) -> bool:
	return value.get("valid",false) and is_finite(value.get("gap",NAN))

static func rotated(pose: Transform3D,pivot: Vector3,axis: Vector3,angle: float,attachment := Vector3(NAN,NAN,NAN)) -> Transform3D:
	var turn := Basis(axis,angle)
	var basis := (turn*pose.basis).orthonormalized()
	# Reconstruct from the original body-space eye on every internal step.
	# Repeatedly rotating a rounded world offset accumulates pivot drift.
	var origin := pivot-basis*attachment if attachment.is_finite() else pivot+turn*(pose.origin-pivot)
	return Transform3D(basis,origin)

static func _energy(pose: Transform3D,pivot: Vector3,forces: Array) -> float:
	var result := 0.0
	for load: Dictionary in forces:
		# Scalar products retain double precision between small SO(3) steps;
		# Vector3 intermediate rounding otherwise hides the last energy drop.
		for index in 3:
			result-=load.force[index]*(pose.basis.x[index]*load.point.x+pose.basis.y[index]*load.point.y+pose.basis.z[index]*load.point.z)
	return result

static func _torque(pose: Transform3D,pivot: Vector3,forces: Array) -> Vector3:
	var result := Vector3.ZERO
	for load: Dictionary in forces: result+=(pose.basis*load.point).cross(load.force)
	return result

static func _gradient(pose: Transform3D,pivot: Vector3,clearance: Callable,attachment := Vector3(NAN,NAN,NAN)) -> Vector3:
	var result := Vector3.ZERO
	for index in 3:
		var axis := Vector3.ZERO
		axis[index]=1
		var before: Dictionary=clearance.call(rotated(pose,pivot,axis,-DIFFERENCE_STEP,attachment))
		var after: Dictionary=clearance.call(rotated(pose,pivot,axis,DIFFERENCE_STEP,attachment))
		if not _valid_contact(before) or not _valid_contact(after): return Vector3(NAN,NAN,NAN)
		result[index]=(after.gap-before.gap)/(2*DIFFERENCE_STEP)
	return result

static func _contacts(pose: Transform3D,pivot: Vector3,clearance: Callable,constraints: Callable,band: float,attachment := Vector3(NAN,NAN,NAN)) -> Array:
	if constraints.is_valid(): return constraints.call(pose,pivot,CONTACT_GAP+band)
	var contact: Dictionary=clearance.call(pose)
	if not _valid_contact(contact) or contact.gap>CONTACT_GAP+band: return []
	return [{"gap":contact.gap,"gradient":_gradient(pose,pivot,clearance,attachment)}]

static func project(desired: Vector3,contacts: Array) -> Vector3:
	return projection(desired,contacts).value

static func projection(desired: Vector3,contacts: Array) -> Dictionary:
	return CONE.solve(desired,contacts,CONTACT_GAP)

static func projection_iterative(desired: Vector3,contacts: Array) -> Dictionary:
	# Dykstra projection onto the intersection of linearized unilateral
	# rotation constraints. Each witness retains its own correction.
	var normals := []
	var bounds := []
	var witnesses := []
	for contact: Dictionary in contacts:
		var gradient: Vector3=contact.gradient
		var length := gradient.length()
		if not gradient.is_finite() or length<.000001: continue
		var normal := gradient/length
		var bound: float=(CONTACT_GAP-contact.gap)/length
		var duplicate := false
		for index in normals.size():
			if normal.dot(normals[index])>.999999:
				if bound>bounds[index]:
					bounds[index]=bound
					witnesses[index]=contact
				duplicate=true
				break
		if not duplicate:
			normals.append(normal)
			bounds.append(bound)
			witnesses.append(contact)
	var corrections := PackedVector3Array()
	corrections.resize(normals.size())
	var result := desired
	for iteration in 128:
		var change := 0.0
		for index in normals.size():
			var candidate := result+corrections[index]
			var next: Vector3=candidate+normals[index]*maxf(0,bounds[index]-normals[index].dot(candidate))
			corrections[index]=candidate-next
			change=maxf(change,result.distance_to(next))
			result=next
		if change<1e-9: break
	var reactions := []
	for index in witnesses.size():
		var contact: Dictionary=witnesses[index]
		var coefficient: float=maxf(0,-corrections[index].dot(normals[index])/contact.gradient.length())
		if coefficient<=1e-12: continue
		var row := {"generalized_n":coefficient,"torque_nm":contact.gradient*coefficient,"gap":contact.get("actual_gap",contact.gap),"gradient":contact.gradient}
		if contact.has_all(["normal","point"]):
			row["force_n"]=contact.normal*coefficient
			row["point"]=contact.point
			reactions.append(row)
		else: reactions.append(row)
	return {"value":result,"reactions":reactions}

static func _feasible(pose: Transform3D,pivot: Vector3,clearance: Callable,constraints: Callable,attachment := Vector3(NAN,NAN,NAN),repair_padding := .0000001) -> Dictionary:
	for iteration in 8:
		var contact: Dictionary=clearance.call(pose)
		if not _valid_contact(contact): return {"valid":false}
		if contact.gap>=CONTACT_GAP: return {"valid":true,"pose":pose,"contact":contact,"corrections":iteration}
		var witnesses := _contacts(pose,pivot,clearance,constraints,.00003,attachment)
		for witness: Dictionary in witnesses: witness.gap-=repair_padding
		var correction := project(Vector3.ZERO,witnesses)
		if not correction.is_finite() or correction.length()<1e-9 or correction.length()>ANGLE_LIMIT: return {"valid":false}
		pose=rotated(pose,pivot,correction.normalized(),correction.length(),attachment)
	return {"valid":false}

static func _escape(pose: Transform3D,pivot: Vector3,forces: Array,clearance: Callable,attachment := Vector3(NAN,NAN,NAN)) -> Vector3:
	var energy := _energy(pose,pivot,forces)
	for axis in [pose.basis.x,pose.basis.y,pose.basis.z]:
		for sign in [-1.0,1.0]:
			var candidate := rotated(pose,pivot,axis,sign*.005,attachment)
			var contact: Dictionary=clearance.call(candidate)
			if _valid_contact(contact) and contact.gap>=CONTACT_GAP and _energy(candidate,pivot,forces)<energy-1e-8:
				return axis*sign*.005
	return Vector3.ZERO

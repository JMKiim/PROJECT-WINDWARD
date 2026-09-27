extends RefCounted

## Quasi-static one-axis block swivel about a fixed physical attachment.
## Loads are prescribed in world space; cable forces and the lower attachment
## must be solved by the caller. This is not a free linked-block assembly.
const ANGLE_STEP := PI/360.0
const CONTACT_GAP := .00005
const GAP_TOLERANCE := .000002
const TORQUE_TOLERANCE := .000001
const MAX_STEPS := 400

static func solve(rest: Transform3D,attachment: Vector3,axis: Vector3,centre_of_mass: Vector3,mass: float,gravity: Vector3,loads: Array,clearance: Callable,release_side := 1.0,interval_clearance := Callable()) -> Dictionary:
	if not rest.is_finite() or not attachment.is_finite() or not centre_of_mass.is_finite() or not axis.is_finite() or axis.length()<.0001 or not gravity.is_finite() or not is_finite(mass) or mass<=0 or gravity.length()<.0001 or not clearance.is_valid() or not is_finite(release_side) or release_side==0:
		return {"valid":false,"reason":"invalid hinged block boundary"}
	if absf(rest.basis.determinant()-1)>.00001 or not (rest.basis.transposed()*rest.basis).is_equal_approx(Basis.IDENTITY):
		return {"valid":false,"reason":"block rest frame must be rigid and right handed"}
	axis=axis.normalized()
	var pivot := rest*attachment
	var forces := [{"point":centre_of_mass,"force":mass*gravity}]
	for load in loads:
		if not load is Dictionary or not load.has_all(["point","force"]) or not load.point is Vector3 or not load.force is Vector3 or not load.point.is_finite() or not load.force.is_finite():
			return {"valid":false,"reason":"invalid prescribed block load"}
		forces.append(load)
	var cosine := 0.0
	var sine := 0.0
	for load: Dictionary in forces:
		var radius: Vector3=rest.basis*(load.point-attachment)
		cosine+=load.force.dot(radius-axis*radius.dot(axis))
		sine+=load.force.dot(axis.cross(radius))
	var drive := Vector2(cosine,sine).length()
	if drive<TORQUE_TOLERANCE:
		return {"valid":false,"reason":"swivel orientation is indeterminate at zero projected torque"}
	var target := atan2(sine,cosine)
	# A vertical unstable pose has two equally valid release directions. Keep
	# the caller's chosen branch instead of letting float noise flip the side.
	if absf(absf(target)-PI)<.00001: target=PI*signf(release_side)
	var initial: Dictionary=clearance.call(rest)
	if not initial.get("valid",false) or not is_finite(initial.get("gap",NAN)):
		return {"valid":false,"reason":"invalid initial contact query"}
	if initial.gap<CONTACT_GAP-GAP_TOLERANCE:
		return {"valid":false,"reason":"initial block already touches or penetrates the swivel guard","contact":initial}
	var angle := 0.0
	var contact := initial
	var stopped := false
	var steps := mini(MAX_STEPS,maxi(1,ceili(absf(target)/ANGLE_STEP)))
	var step := 0
	while step<steps:
		var next_step := step+1
		if interval_clearance.is_valid():
			next_step=mini(steps,step+32)
			while next_step>step+1:
				if interval_clearance.call(rest,pivot,axis,angle,target*next_step/float(steps),CONTACT_GAP): break
				next_step=step+maxi(1,(next_step-step)/2)
		var next := target*next_step/float(steps)
		var query: Dictionary=clearance.call(_pose(rest,pivot,axis,next))
		if not query.get("valid",false) or not is_finite(query.get("gap",NAN)):
			return {"valid":false,"reason":"invalid contact query during swivel"}
		if query.gap<CONTACT_GAP:
			var low := angle
			var high := next
			for refinement in 30:
				var middle := (low+high)*.5
				query=clearance.call(_pose(rest,pivot,axis,middle))
				if not query.get("valid",false) or not is_finite(query.get("gap",NAN)):
					return {"valid":false,"reason":"invalid refined contact query"}
				if query.gap>=CONTACT_GAP: low=middle
				else: high=middle
			angle=low
			contact=clearance.call(_pose(rest,pivot,axis,angle))
			stopped=true
			break
		angle=next
		contact=query
		step=next_step
	var pose := _pose(rest,pivot,axis,angle)
	var torque := -cosine*sin(angle)+sine*cos(angle)
	var reaction := 0.0
	var derivative := 0.0
	if stopped:
		var h := .0001
		var before: Dictionary=clearance.call(_pose(rest,pivot,axis,angle-h))
		var after: Dictionary=clearance.call(_pose(rest,pivot,axis,angle+h))
		if not before.get("valid",false) or not after.get("valid",false): return {"valid":false,"reason":"contact derivative unavailable"}
		derivative=(after.gap-before.gap)/(2*h)
		if not is_finite(derivative) or absf(derivative)<.000001: return {"valid":false,"reason":"degenerate swivel contact reaction"}
		reaction=-torque/derivative
		if not is_finite(reaction) or reaction<0: return {"valid":false,"reason":"contact would have to pull the block"}
	var balance := absf(torque+reaction*derivative)
	return {"valid":balance<=TORQUE_TOLERANCE and contact.gap>=CONTACT_GAP-GAP_TOLERANCE,"pose":pose,"angle":angle,"free_angle":target,"pivot":pivot,"pivot_error":(pose*attachment).distance_to(pivot),"state":"contact" if stopped else "suspended","contact":contact,"applied_torque_nm":torque,"contact_generalized_force_n":reaction,"gap_derivative_m":derivative,"balance_nm":balance,"energy_change_j":cosine-(cosine*cos(angle)+sine*sin(angle)),"steps":steps}

static func _pose(rest: Transform3D,pivot: Vector3,axis: Vector3,angle: float) -> Transform3D:
	var turn := Basis(axis,angle)
	return Transform3D(turn*rest.basis,pivot+turn*(rest.origin-pivot))

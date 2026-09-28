extends RefCounted

## Coupled finite round-groove contacts at prescribed rigid body frames.
## Whole-solid clearance, material allocation and equilibrium are separate.
const GROOVE := preload("res://src/boat/grooved_cable_route.gd")
const CABLE := preload("res://src/boat/cylinder_cable_route.gd")
const SUPPORT := preload("res://src/boat/traveller_supported_route.gd")
const PIN := preload("res://src/boat/revolute_pin_joint.gd")
const ENDPOINT_TOLERANCE := .0000005

static func _distance(a: Vector3,b: Vector3) -> float:
	return sqrt(pow(float(a.x)-float(b.x),2)+pow(float(a.y)-float(b.y),2)+pow(float(a.z)-float(b.z),2))

static func _stopped(deadline: int,cancelled: Callable) -> bool:
	return Time.get_ticks_usec()>=deadline or (cancelled.is_valid() and cancelled.call())

static func _groove(frame: Transform3D,small: bool,a: Vector3,b: Vector3,winding: float,count: int,deadline: int,cancelled: Callable,initial := PackedFloat64Array()) -> Dictionary:
	if _stopped(deadline,cancelled): return {"valid":false,"reason":"surface route cancelled or budget exhausted"}
	var remaining := maxi(1,int((deadline-Time.get_ticks_usec())/1000))
	return GROOVE.route(frame,.0125 if small else .02,.009 if small else .013,.003 if small else .004,a,b,winding,count,remaining,func(): return _stopped(deadline,cancelled),initial)

static func route(boundary: Dictionary,aft: Transform3D,upper: Transform3D,count := 25,maximum_msec := 2000,cancelled := Callable(),profiles := {}) -> Dictionary:
	var began := Time.get_ticks_usec()
	if not PIN.rigid(aft) or not PIN.rigid(upper) or count<9 or count>129 or maximum_msec<=0: return {"valid":false,"reason":"invalid surface purchase request"}
	for key in ["mount","eye","anchor","becket","guide"]:
		if not boundary.get(key) is Vector3 or not boundary[key].is_finite(): return {"valid":false,"reason":"invalid surface purchase datum"}
	for key in ["becket_winding","traveller_winding","aft_winding"]:
		if not (boundary.get(key) is int or boundary.get(key) is float) or boundary[key] not in [-1.0,0.0,1.0]: return {"valid":false,"reason":"invalid surface purchase winding"}
	for key in ["traveller","aft"]:
		if profiles.has(key) and not profiles[key] is PackedFloat64Array: return {"valid":false,"reason":"invalid surface purchase initial profile"}
	if (aft*boundary.eye).distance_to(boundary.mount)>.000002: return {"valid":false,"reason":"aft attachment displaced"}
	var deadline := began+maximum_msec*1000
	var becket_frame := Transform3D(aft.basis,aft*boundary.becket)
	var anchor: Vector3=aft*boundary.anchor
	var entry: Vector3=upper.origin
	var returning: Vector3=aft.origin
	var previous := {}
	var upper_profile: PackedFloat64Array=profiles.get("traveller",PackedFloat64Array())
	var aft_profile: PackedFloat64Array=profiles.get("aft",PackedFloat64Array())
	for iteration in 64:
		if _stopped(deadline,cancelled): return {"valid":false,"reason":"surface route cancelled or budget exhausted"}
		# Actual authored becket: 2 mm pin radius, 8 mm half span. Allow
		# the 4 mm rope radius plus 0.3 mm guard at each finite pin end.
		var becket := CABLE.route(becket_frame,.0063,anchor,entry,false,true,Vector3.ZERO,.0037,0,boundary.becket_winding)
		if not becket.valid: return {"valid":false,"reason":"becket: "+becket.reason}
		var traveller := _groove(upper,false,becket.exit,returning,boundary.traveller_winding,count,deadline,cancelled,upper_profile)
		if not traveller.valid: return {"valid":false,"reason":"traveller: "+traveller.reason,"detail":traveller}
		var boom := _groove(aft,false,traveller.exit,boundary.guide,boundary.aft_winding,count,deadline,cancelled,aft_profile)
		if not boom.valid: return {"valid":false,"reason":"aft: "+boom.reason,"detail":boom}
		upper_profile=traveller.profile
		aft_profile=boom.profile
		var error := maxf(entry.distance_to(traveller.entry),returning.distance_to(boom.entry))
		if not previous.is_empty():
			for key in ["entry","exit"]:
				for pair in [[previous.becket,becket],[previous.traveller,traveller],[previous.aft,boom]]: error=maxf(error,pair[0][key].distance_to(pair[1][key]))
		entry=traveller.entry
		returning=boom.entry
		previous={"becket":becket,"traveller":traveller,"aft":boom}
		if error>ENDPOINT_TOLERANCE: continue
		var first: Vector3=(traveller.entry-becket.exit).normalized()
		var last: Vector3=(boom.entry-traveller.exit).normalized()
		var tangent_error := maxf(first.distance_to(becket.exit_force_per_n),first.distance_to(-traveller.entry_force_per_n))
		tangent_error=maxf(tangent_error,maxf(last.distance_to(traveller.exit_force_per_n),last.distance_to(-boom.entry_force_per_n)))
		if tangent_error>.0001: continue
		var path: PackedVector3Array=becket.path.duplicate()
		# The previous iterate supplied the becket's outgoing endpoint. The
		# material ledger must instead join the final shared contacts once.
		path[-1]=traveller.entry
		for i in range(1,traveller.arc_path.size()): path.append(traveller.arc_path[i])
		for i in range(1,boom.path.size()): path.append(boom.path[i])
		var length: float=_distance(anchor,becket.entry)+becket.arc_length+_distance(becket.exit,traveller.entry)+traveller.arc_length+_distance(traveller.exit,boom.entry)+boom.arc_length+_distance(boom.exit,boundary.guide)
		return {"valid":true,"geometry_certified":false,"equilibrium_certified":false,"becket":becket,"traveller":traveller,"aft":boom,"path":path,"length":length,"anchor":anchor,"iterations":iteration+1,"endpoint_error_m":error,"tangent_error":tangent_error,"elapsed_msec":(Time.get_ticks_usec()-began)/1000.0}
	return {"valid":false,"reason":"coupled surface purchase contacts did not converge"}

static func lower_route(boundary: Dictionary,frame: Transform3D,count := 25,maximum_msec := 2000,cancelled := Callable(),initial := PackedFloat64Array()) -> Dictionary:
	var began := Time.get_ticks_usec()
	if not SUPPORT._valid(boundary) or not PIN.rigid(frame) or count<9 or count>129 or maximum_msec<=0: return {"valid":false,"reason":"invalid lower surface request"}
	# Installed reeving is a boundary condition. Choosing the shortest side
	# again after a displacement can silently pass the rope through the wheel.
	if not (boundary.get("lower_winding") is int or boundary.get("lower_winding") is float) or boundary.lower_winding not in [-1.0,1.0]: return {"valid":false,"reason":"explicit installed lower winding required"}
	if absf(boundary.sheave_radius-(.0125-minf(.0048,.009*.43*.873)+.0033))>.0000002: return {"valid":false,"reason":"lower groove geometry mismatch"}
	var deadline := began+maximum_msec*1000
	var approach := SUPPORT._leg(boundary,boundary.starboard,frame.origin)
	var departure := SUPPORT._leg(boundary,frame.origin,boundary.port)
	if not approach.valid or not departure.valid: return {"valid":false,"reason":"initial tiller route"}
	var entry: Vector3=frame.origin
	var exit_point: Vector3=frame.origin
	var profile := initial.duplicate()
	for iteration in 64:
		var incoming := SUPPORT._near(approach,true)
		var outgoing := SUPPORT._near(departure,false)
		var roller := _groove(frame,true,incoming,outgoing,boundary.lower_winding,count,deadline,cancelled,profile)
		if not roller.valid: return {"valid":false,"reason":"lower groove: "+roller.reason,"detail":roller,"iteration":iteration,"incoming":incoming,"outgoing":outgoing}
		profile=roller.profile
		var next_a := SUPPORT._leg(boundary,boundary.starboard,roller.entry)
		var next_b := SUPPORT._leg(boundary,roller.exit,boundary.port)
		if not next_a.valid or not next_b.valid: return {"valid":false,"reason":"finite tiller route"}
		var error := maxf(entry.distance_to(roller.entry),exit_point.distance_to(roller.exit))
		error=maxf(error,maxf(incoming.distance_to(SUPPORT._near(next_a,true)),outgoing.distance_to(SUPPORT._near(next_b,false))))
		approach=next_a
		departure=next_b
		entry=roller.entry
		exit_point=roller.exit
		if error>ENDPOINT_TOLERANCE: continue
		var first := (SUPPORT._near(approach,true)-entry).normalized()
		var last := (SUPPORT._near(departure,false)-exit_point).normalized()
		var tangent_error := maxf(first.distance_to(roller.entry_force_per_n),last.distance_to(roller.exit_force_per_n))
		if tangent_error>.0001: continue
		var path: PackedVector3Array=approach.path.duplicate()
		for i in range(1,roller.arc_path.size()): path.append(roller.arc_path[i])
		for i in range(1,departure.path.size()): path.append(departure.path[i])
		return {"valid":true,"geometry_certified":false,"equilibrium_certified":false,"sheave":roller,"path":path,"length":approach.length+roller.arc_length+departure.length,"approach":approach,"departure":departure,"iterations":iteration+1,"endpoint_error_m":error,"tangent_error":tangent_error,"elapsed_msec":(Time.get_ticks_usec()-began)/1000.0}
	return {"valid":false,"reason":"lower surface contacts did not converge"}

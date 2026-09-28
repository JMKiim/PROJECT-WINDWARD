extends RefCounted

## Detached geometric support of the loaded aft traveller span only.
## The rope selects a candidate sheave plane; a connector must independently
## admit that plane. This is not a free-body equilibrium or a full line ledger.
const CABLE := preload("res://src/boat/cylinder_cable_route.gd")
const ENDPOINT_TOLERANCE := .0000005
const LENGTH_TOLERANCE := .0000002
const MAX_X := .455

static func _leg(boundary: Dictionary, start: Vector3, finish: Vector3) -> Dictionary:
	var source: Transform3D=boundary.tiller
	# Existing tiller axis is local Z; the circle primitive uses local X.
	var frame := Transform3D(Basis(source.basis.z,source.basis.y,-source.basis.x),source.origin)
	return CABLE.route(frame,boundary.tiller_radius,start,finish,false,false,source.basis.y,boundary.tiller_half_span)

static func _near(leg: Dictionary, at_end: bool) -> Vector3:
	if leg.wrapped: return leg.exit if at_end else leg.entry
	return leg.path[0] if at_end else leg.path[-1]

static func _valid(boundary: Dictionary) -> bool:
	for key in ["port","starboard"]:
		if not boundary.get(key) is Vector3 or not boundary[key].is_finite(): return false
	if not boundary.get("tiller") is Transform3D: return false
	for key in ["tiller_radius","tiller_half_span","sheave_radius"]:
		if not boundary.get(key) is float and not boundary.get(key) is int: return false
		if not is_finite(boundary[key]) or boundary[key]<=0: return false
	return true

static func route(boundary: Dictionary, center: Vector3) -> Dictionary:
	if not _valid(boundary) or not center.is_finite(): return {"valid":false,"reason":"invalid traveller support boundary"}
	var approach := _leg(boundary,boundary.starboard,center)
	var departure := _leg(boundary,center,boundary.port)
	if not approach.valid or not departure.valid: return {"valid":false,"reason":"initial leg has unsupported cylinder contact"}
	var entry := center
	var exit_point := center
	for iteration in 64:
		var incoming := _near(approach,true)
		var outgoing := _near(departure,false)
		var axle := (incoming-center).cross(outgoing-center)
		if axle.length_squared()<1e-14: return {"valid":false,"reason":"degenerate sheave plane"}
		axle=axle.normalized()
		var up := Vector3.UP-axle*axle.dot(Vector3.UP)
		if up.length_squared()<1e-8: up=Vector3.BACK-axle*axle.dot(Vector3.BACK)
		up=up.normalized()
		var frame := Transform3D(Basis(axle,up,axle.cross(up)),center)
		var roller := CABLE.route(frame,boundary.sheave_radius,incoming,outgoing)
		if not roller.valid: return {"valid":false,"reason":"sheave: "+roller.reason}
		var next_approach := _leg(boundary,boundary.starboard,roller.entry)
		var next_departure := _leg(boundary,roller.exit,boundary.port)
		if not next_approach.valid or not next_departure.valid: return {"valid":false,"reason":"finite cylinder tangent unsupported"}
		var error := maxf(entry.distance_to(roller.entry),exit_point.distance_to(roller.exit))
		error=maxf(error,maxf(incoming.distance_to(_near(next_approach,true)),outgoing.distance_to(_near(next_departure,false))))
		entry=roller.entry
		exit_point=roller.exit
		approach=next_approach
		departure=next_departure
		if error>ENDPOINT_TOLERANCE: continue
		var entry_force := (_near(approach,true)-entry).normalized()
		var exit_force := (_near(departure,false)-exit_point).normalized()
		var tangent_error := maxf(entry_force.distance_to(roller.entry_force_per_n),exit_force.distance_to(roller.exit_force_per_n))
		if tangent_error>.0001: continue
		var path: PackedVector3Array=approach.path.duplicate()
		for index in range(1,roller.arc_path.size()): path.append(roller.arc_path[index])
		for index in range(1,departure.path.size()): path.append(departure.path[index])
		return {"valid":true,"center":center,"frame":frame,"path":path,"length":approach.length+roller.arc_length+departure.length,"sheave":roller,"approach":approach,"departure":departure,"iterations":iteration+1,"tangent_error":tangent_error,"endpoint_error_m":error,"force_per_n":entry_force+exit_force,"moment_per_n":(entry-center).cross(entry_force)+(exit_point-center).cross(exit_force),"scope":"aft loaded span only; connector and full material ledger not solved"}
	return {"valid":false,"reason":"coupled tiller/sheave tangents did not converge"}

static func fit(boundary: Dictionary, target_length: float, x: float, azimuth: float) -> Dictionary:
	# A Node3D/Vector coordinate rounds the declared endpoint to float32.
	# Accept that representation, without widening physical/contact tolerances.
	var representable_end := float(Vector3(MAX_X,0,0).x)
	if not _valid(boundary) or not is_finite(target_length) or target_length<=0 or not is_finite(x) or not is_finite(azimuth) or absf(x)>maxf(MAX_X,representable_end) or absf(azimuth)>deg_to_rad(75):
		return {"valid":false,"reason":"invalid fixed material fit request"}
	var origin: Vector3=(boundary.port+boundary.starboard)*.5
	var base := origin+Vector3.RIGHT*x
	var axis := Vector3(0,cos(azimuth),sin(azimuth))
	var high := .35
	var low := .008
	var above := route(boundary,base+axis*high)
	if not above.valid or above.length<target_length: return {"valid":false,"reason":"target exceeds supported radial domain"}
	var bracket := false
	for sample in range(1,65):
		low=lerpf(.35,.008,sample/64.0)
		var below := route(boundary,base+axis*low)
		# Never bisect across an invalid/contact-topology hole.
		if not below.valid: return {"valid":false,"reason":"target not bracketed before contact domain boundary"}
		if below.length<=target_length:
			bracket=true
			break
		high=low
	if not bracket: return {"valid":false,"reason":"target shorter than supported radial domain"}
	var best := {}
	var best_error := INF
	for iteration in 27:
		var radius := (low+high)*.5
		var candidate := route(boundary,base+axis*radius)
		if not candidate.valid: return {"valid":false,"reason":"invalid interior tangent topology"}
		var error: float=candidate.length-target_length
		if absf(error)<best_error:
			best=candidate
			best["radius"]=radius
			best["material_error_m"]=error
			best_error=absf(error)
		if best_error<=LENGTH_TOLERANCE*.25: break
		if error<0: low=radius
		else: high=radius
	if best_error>LENGTH_TOLERANCE: return {"valid":false,"reason":"fixed material length tolerance not reached","error_m":best_error}
	best["target_length"]=target_length
	return best

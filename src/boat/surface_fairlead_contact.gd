extends RefCounted

## Detached conditional contact solve. The finite lower-body reaction is
## physical; fairlead string patches remain geometric boundary conditions.
## This is not a frictionless whole-fairlead or dynamic certificate.
const MODEL := preload("res://src/boat/surface_purchase_equilibrium.gd")
const FEATURE := preload("res://src/boat/surface_feature_equilibrium.gd")
const ADAPTIVE := preload("res://src/boat/fairlead_adaptive_route.gd")
const ROUTE := preload("res://src/boat/fairlead_cable_route.gd")
const GUARD := preload("res://src/boat/surface_purchase_guard.gd")
const CURVE := preload("res://src/boat/rope_path_curve.gd")

static func geometry_key(input: Dictionary) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes([input.get("bodies",[]),input.get("fixed_hardware",[])]))
	return hash.finish().hex_encode()

static func valid_data(input: Dictionary) -> bool:
	if not input.get("fairlead") is Dictionary: return false
	var data: Dictionary=input.fairlead
	if not data.get("frames") is Dictionary: return false
	for side in ["port","starboard"]:
		if not data.frames.get(side) is Transform3D or not MODEL.ROUTE.PIN.rigid(data.frames[side]): return false
	for key in ["prefix","returning"]:
		if not data.get(key) is PackedVector3Array or data[key].size()<2: return false
		for point in data[key]:
			if not point.is_finite(): return false
	return input.get("bodies") is Array and input.bodies.size()==3 and input.get("fixed_hardware") is Array

static func effective_input(input: Dictionary,numeric: Dictionary) -> Dictionary:
	var result := input.duplicate(true)
	var data: Dictionary=numeric.get("surface_contact",{})
	if data.is_empty(): return result
	result.tails=data.tails.duplicate(true)
	result.rear_metres=data.rear_metres
	result.boundary.port=data.port
	result.boundary.starboard=data.starboard
	return result

static func _below(boundary: Dictionary,start: Vector3,finish: Vector3) -> PackedVector3Array:
	# Preserve the existing authored front support route; do not introduce
	# a new knot, material shortcut or free-space corner in this adapter.
	var frame: Transform3D=boundary.tiller
	var a := frame.affine_inverse()*start
	var b := frame.affine_inverse()*finish
	var ra := Vector2(a.x,a.y)
	var rb := Vector2(b.x,b.y)
	var radius: float=boundary.tiller_radius
	var result := PackedVector3Array()
	if Geometry2D.get_closest_point_to_segment(Vector2.ZERO,ra,rb).length()>=radius: return result
	if minf(a.z,b.z)>boundary.tiller_half_span or maxf(a.z,b.z)<-boundary.tiller_half_span: return result
	var angles := []
	for radial in [ra,rb]: angles.append(radial.angle()-signf(radial.x)*acos(clampf(radius/radial.length(),-1,1)))
	var arc: float=absf(angle_difference(angles[0],angles[1]))*radius
	var lead := sqrt(maxf(0,ra.length_squared()-radius*radius))
	var last := sqrt(maxf(0,rb.length_squared()-radius*radius))
	for i in 9:
		var angle: float=lerp_angle(angles[0],angles[1],i/8.0)
		result.append(frame*Vector3(cos(angle)*radius,sin(angle)*radius,lerpf(a.z,b.z,(lead+arc*i/8.0)/(lead+arc+last))))
	return result

static func _tails(input: Dictionary,source: Dictionary,datum: Vector3,stop: Callable) -> Dictionary:
	var patches := {}
	var change := 0.0
	var diagnostics := {}
	for side in ["port","starboard"]:
		var frame: Transform3D=input.fairlead.frames[side]
		var front: Vector3=input.fairlead.returning[0] if side=="port" else input.fairlead.prefix[-1]
		var leg: Dictionary=source.lower.departure if side=="port" else source.lower.approach
		var finish: Vector3=MODEL.ROUTE.SUPPORT._near(leg,side=="port")+datum
		var candidate := ADAPTIVE.solve(frame.affine_inverse()*front,frame.affine_inverse()*finish,.0003,80,stop)
		if not candidate.get("valid",false): return {"valid":false,"reason":candidate.get("reason","adaptive fairlead clearance failed")}
		var patch := ROUTE.contact_patch(candidate,frame)
		if patch.is_empty(): return {"valid":false,"reason":"no finite fairlead patch"}
		patches[side]=patch
		change=maxf(change,patch[-1].distance_to(input.boundary[side]))
		diagnostics[side]={"gap":candidate.minimum_gap,"residual_per_n":candidate.residual_per_n,"iterations":candidate.iterations}
	var before: PackedVector3Array=input.fairlead.prefix.duplicate()
	before.append_array(_below(input.boundary,before[-1],patches.starboard[0]))
	before=CURVE.round_corners(before,.012)
	before.append_array(patches.starboard)
	var after: PackedVector3Array=patches.port.duplicate()
	after.reverse()
	after.append_array(input.fairlead.returning)
	input.tails={"before":before,"after":after}
	input.boundary.port=after[0]
	input.boundary.starboard=before[-1]
	input.rear_metres=input.traveller_total_metres-GUARD.STOPPER.length_of(before)-GUARD.STOPPER.length_of(after)
	return {"valid":input.rear_metres>0,"reason":"coupled fairlead material","movement_m":change,"patches":diagnostics}

static func _feature(entry: Dictionary,index: int) -> Dictionary:
	var triangle: Dictionary=entry.triangles[index]
	return {"a":entry.frame*triangle.a,"b":entry.frame*triangle.b,"c":entry.frame*triangle.c,"normal":entry.frame.basis*triangle.normal*entry.winding}

static func _retarget(field: RefCounted,body: Dictionary,source: Dictionary,datum: Vector3,contact: Dictionary,witness := {},actual_witness := false) -> Dictionary:
	var feature := {}
	if not witness.is_empty():
		for entry: Dictionary in field.entries:
			if entry.label==witness.surface and witness.obstacle_triangle>=0 and witness.obstacle_triangle<entry.triangles.size(): feature=_feature(entry,witness.obstacle_triangle)
		if feature.is_empty() or witness.body_triangle<0 or witness.body_triangle>=body.triangles.size(): return {}
		if not witness.get("point") is Vector3 or not witness.point.is_finite(): return {}
		var triangle: Dictionary=body.triangles[witness.body_triangle]
		if actual_witness:
			var frame: Transform3D=source.state.lower
			frame.origin+=datum
			# Continue an already checked finite contact on its actual face.
			# A closest point need not be a mesh vertex; a remote extreme
			# vertex can move support outside this finite fitting.
			var local: Vector3=frame.affine_inverse()*witness.point
			contact.local=GUARD.FIELD._triangle_point(local,triangle.a,triangle.b,triangle.c)
		else:
			# Preserve the cold active-set initialization. Its unverified
			# intersecting pose is not an accepted near-contact witness.
			var minimum := INF
			for vertex: Vector3 in [triangle.a,triangle.b,triangle.c]:
				var gap: float=(source.state.lower*vertex+datum-feature.a).dot(feature.normal)
				if gap<minimum:
					minimum=gap
					contact.local=vertex
	else:
		var point: Vector3=source.contact_point+datum
		var best := INF
		for entry: Dictionary in field.entries:
			var p: Vector3=entry.inverse*point
			for i in entry.triangles.size():
				var t: Dictionary=entry.triangles[i]
				var distance := p.distance_to(GUARD.FIELD._triangle_point(p,t.a,t.b,t.c))
				if distance<best:
					best=distance
					feature=_feature(entry,i)
	if feature.is_empty(): return {}
	contact.normal=feature.normal
	contact.surface=feature.a-datum
	return feature

static func membership(source: Dictionary,datum: Vector3,contact: Dictionary,feature: Dictionary) -> float:
	if contact.is_empty(): return 0.0
	var point: Vector3=source.contact_point+datum-contact.normal*contact.clearance
	return point.distance_to(GUARD.FIELD._triangle_point(point,feature.a,feature.b,feature.c))

static func body_membership(body: Dictionary,contact: Dictionary) -> float:
	if contact.is_empty(): return 0.0
	if not contact.get("local") is Vector3 or not contact.local.is_finite(): return INF
	var distance := INF
	for triangle: Dictionary in body.triangles:
		distance=minf(distance,contact.local.distance_to(GUARD.FIELD._triangle_point(contact.local,triangle.a,triangle.b,triangle.c)))
	return distance

static func _refine(input: Dictionary,source: Dictionary,datum: Vector3,boundary: Dictionary,contact: Dictionary,deadline: int,stop: Callable) -> Dictionary:
	var initial: Dictionary=source.state.duplicate(true)
	for key in initial.get("profiles",{}):
		if initial.profiles[key].size()!=25:
			initial.erase("profiles")
			break
	var remaining := mini(6000,maxi(1,int((deadline-Time.get_ticks_usec())/1000)))
	var solved := MODEL.solve(boundary,initial,input.load,input.rear_metres,source.tension,remaining,stop) if contact.is_empty() else FEATURE.solve(boundary,initial,input.load,input.rear_metres,source.tension,contact,remaining,stop,source.get("reaction_n",.1))
	if not solved.get("converged",false): return {"valid":false,"reason":solved.get("reason","contact force not converged")}
	# Intermediate fixed-point iterates are not certificates. Preserve their
	# matching 25-node contact profiles, then independently reconstruct 129
	# nodes exactly once at final acceptance (and recheck the shared exits).
	return solved

static func _certify(input: Dictionary,source: Dictionary,boundary: Dictionary,contact: Dictionary,deadline: int,stop: Callable) -> Dictionary:
	var state: Dictionary=source.state.duplicate(true)
	state.erase("profiles")
	var refined := MODEL._evaluate(state,source.tension,boundary,input.load,input.rear_metres,129,deadline,stop) if contact.is_empty() else FEATURE.evaluate(state,source.tension,source.reaction_n,boundary,input.load,input.rear_metres,contact,129,deadline,stop)
	if not refined.get("valid",false): return refined
	if not (MODEL._converged(refined) if contact.is_empty() else FEATURE.converged(refined)): return {"valid":false,"reason":"independent finite-contact force refinement rejected"}
	return refined

static func solve(input: Dictionary,numeric: Dictionary,deadline: int,stop: Callable,accepted_contact_seed := false) -> Dictionary:
	if not valid_data(input) or not numeric.get("valid",false): return {"valid":false,"reason":"finite contact boundary unavailable"}
	if accepted_contact_seed and (not numeric.has("surface_contact") or numeric.surface_contact.geometry_key!=geometry_key(input)):
		return {"valid":false,"reason":"finite geometry: accepted contact seed geometry changed"}
	# Reuse a checked contact only as the starting active set. Every new
	# requested load still recomputes forces, exits, finite membership,
	# 129-node refinement and the caller's complete mesh/material guard.
	var working := effective_input(input,numeric) if accepted_contact_seed else input.duplicate(true)
	var source: Dictionary=numeric.refined.duplicate(true)
	var datum: Vector3=numeric.datum
	var field := GUARD.FIELD.new()
	if not field.add_records(working.fixed_hardware,stop): return {"valid":false,"reason":"fixed contact mesh unavailable"}
	var pair := GUARD.PAIR.new()
	if not pair.setup(GUARD._faces(working.bodies[0]),stop): return {"valid":false,"reason":"lower contact mesh unavailable"}
	var contact: Dictionary=numeric.surface_contact.contact.duplicate(true) if accepted_contact_seed else {}
	var feature: Dictionary=numeric.surface_contact.feature.duplicate(true) if accepted_contact_seed else {}
	var trace := []
	var windings := Vector2(signf(source.purchase.traveller.sweep),signf(source.purchase.aft.sweep))
	for outer in 16:
		if stop.call() or Time.get_ticks_usec()>=deadline: return {"valid":false,"reason":"finite contact cancelled or budget exhausted","trace":trace}
		var began := Time.get_ticks_usec()
		var routing := _tails(working,source,datum,stop)
		if not routing.valid: return routing
		var route_ms := (Time.get_ticks_usec()-began)/1000.0
		var boundary: Dictionary=working.boundary.duplicate(true)
		for key in ["port","starboard"]: boundary[key]-=datum
		boundary.tiller.origin-=datum
		for key in ["mount","guide"]: boundary.purchase[key]-=datum
		boundary.purchase.traveller_winding=windings.x
		boundary.purchase.aft_winding=windings.y
		var good := false
		for inner in 8:
			began=Time.get_ticks_usec()
			var refined := _refine(working,source,datum,boundary,contact,deadline,stop)
			if not refined.valid: return {"valid":false,"reason":refined.reason,"trace":trace}
			source=refined
			var force_ms := (Time.get_ticks_usec()-began)/1000.0
			var frame: Transform3D=source.state.lower
			frame.origin+=datum
			began=Time.get_ticks_usec()
			var contacts: Array=pair.contacts(frame,field,.000048)
			var distance := membership(source,datum,contact,feature)
			var body_distance := body_membership(pair.body,contact)
			trace.append({"outer":outer,"inner":inner,"movement_m":routing.movement_m,"route_ms":route_ms,"force_ms":force_ms,"mesh_ms":(Time.get_ticks_usec()-began)/1000.0,"membership_m":distance,"body_membership_m":body_distance,"reaction_n":source.get("reaction_n",0),"contacts":contacts.size()})
			if contacts.is_empty() and distance<.000002 and body_distance<.000002:
				good=true
				break
			if contact.is_empty(): contact={"body":0,"local":Vector3.ZERO,"normal":Vector3.UP,"surface":Vector3.ZERO,"clearance":.00005}
			var witness: Dictionary=contacts[0] if not contacts.is_empty() else {}
			if witness.is_empty() and accepted_contact_seed:
				# A prior supporting facet can end while the bodies remain
				# separated by the safety skin. Only query actual nearby
				# triangle pairs; never extend that old face as an infinite plane.
				var nearby: Array=pair.contacts(frame,field,.002)
				nearby.sort_custom(func(a:Dictionary,b:Dictionary):return a.gap<b.gap)
				if not nearby.is_empty(): witness=nearby[0]
			feature=_retarget(field,pair.body,source,datum,contact,witness,accepted_contact_seed)
			if feature.is_empty(): return {"valid":false,"reason":"finite contact feature unavailable","trace":trace}
		if not good: return {"valid":false,"reason":"finite contact feature iteration limit","trace":trace}
		if routing.movement_m>=.0000005: continue
		var refined := _certify(working,source,boundary,contact,deadline,stop)
		if not refined.valid: return refined
		if membership(refined,datum,contact,feature)>=.000002 or body_membership(pair.body,contact)>=.000002:
			return {"valid":false,"reason":"independent refinement left the finite contact facet","trace":trace}
		var independent := working.duplicate(true)
		var shared := _tails(independent,refined,datum,stop)
		if not shared.valid: return shared
		if shared.movement_m>=.0000005:
			source=refined
			continue
		source=refined
		routing["independent_shared_error_m"]=shared.movement_m
		return {"valid":true,"refined":source,"datum":datum,"initialization":"finite fairlead and lower contact; forces independently refined","surface_contact":{"tails":working.tails,"rear_metres":working.rear_metres,"port":working.boundary.port,"starboard":working.boundary.starboard,"contact":contact,"feature":feature,"geometry_key":geometry_key(input),"routing":routing},"trace":trace}
	return {"valid":false,"reason":"fairlead/contact fixed point did not converge","trace":trace}

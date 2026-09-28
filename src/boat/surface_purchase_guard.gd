extends RefCounted

const FIELD := preload("res://src/boat/mesh_rope_obstacle.gd")
const PAIR := preload("res://src/boat/mesh_pair_contact.gd")
const STOPPER := preload("res://src/boat/mainsheet_stopper.gd")

static func assemble(input: Dictionary,solved: Dictionary,datum: Vector3) -> Dictionary:
	var poses := {}
	for key in ["lower","upper","aft"]:
		poses[key]=solved.state[key]
		poses[key].origin+=datum
	var shift := Transform3D(Basis.IDENTITY,datum)
	var path: PackedVector3Array=shift*solved.purchase.path
	var guide_index: int=input.wraps.aft.end+1
	if guide_index>=input.path.size() or path[-1].distance_to(input.path[guide_index])>.000002:
		return {"valid":false,"reason":"downstream guide boundary changed"}
	path.append_array(input.path.slice(guide_index+1))
	# The standing leg exits normal to the open becket plane. Carrying the
	# old decorative lean into the new body tips it into the 2 mm cross-pin.
	# Rigidly orient the same authored knot: no scale or material is changed.
	var fixed := STOPPER.placed(STOPPER.points(.025,.020),path[0],poses.aft.basis*Vector3.FORWARD)
	var traveller: PackedVector3Array=input.tails.before.duplicate()
	traveller.append_array((shift*solved.lower.path).slice(1))
	traveller.append_array(input.tails.after.slice(1))
	var material: float=STOPPER.length_of(input.tails.before)+solved.lower.length+STOPPER.length_of(input.tails.after)
	var render_error: float=STOPPER.length_of(traveller)-input.traveller_total_metres
	if absf(material-input.traveller_total_metres)>.0000002 or absf(render_error)>.00005:
		return {"valid":false,"reason":"complete traveller material rejected","error_m":render_error}
	return {"valid":true,"path":path,"fixed":fixed,"traveller_path":traveller,"poses":poses,"angles":input.angles,"tiller_angle":input.tiller_angle,"traveller_material_metres":material,"traveller_render_error_m":render_error,"rig_metres":STOPPER.length_of(path)}

static func _faces(records: Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for record: Dictionary in records: faces.append_array(record.frame*record.faces)
	return faces

static func _tube(path: PackedVector3Array,radius: float,frames: Array,fields: Array,extents: Array,tiller: Transform3D,cancelled: Callable) -> Dictionary:
	var gap := INF
	var tiller_gap := INF
	var inverses := []
	for frame: Transform3D in frames: inverses.append(frame.affine_inverse())
	var inverse := tiller.affine_inverse()
	var worst := {}
	for i in path.size()-1:
		if cancelled.call(): return {"valid":false,"reason":"geometry cancelled or budget exhausted"}
		var count := maxi(2,ceili(path[i].distance_to(path[i+1])/.0004))
		for j in count+1:
			var p := path[i].lerp(path[i+1],j/float(count))
			for body in 3:
				var local: Vector3=inverses[body]*p
				if local.length()>extents[body]+radius+.02: continue
				var contact: Dictionary=fields[body].query(local,radius,.02)
				if contact.gap<gap:
					gap=contact.gap
					worst={"body":body,"point":local,"contact":contact,"index":i,"world":p}
			var local := inverse*p
			tiller_gap=minf(tiller_gap,Vector3(local.x,local.y,local.z-clampf(local.z,-.490,.490)).length()-.0128-radius)
	return {"valid":gap>=.00025 and tiller_gap>=.00025,"reason":"tube/body or tiller clearance","gap":gap,"tiller_gap":tiller_gap,"worst":worst}

static func _rope_pair(a: PackedVector3Array,b: PackedVector3Array,separation: float,cancelled: Callable) -> float:
	var gap := INF
	for i in a.size()-1:
		if cancelled.call(): return -INF
		var box := AABB(a[i],Vector3.ZERO).expand(a[i+1]).grow(separation+.001)
		for j in b.size()-1:
			if not box.intersects(AABB(b[j],Vector3.ZERO).expand(b[j+1]).grow(.0000001)): continue
			var pair := Geometry3D.get_closest_points_between_segments(a[i],a[i+1],b[j],b[j+1])
			gap=minf(gap,pair[0].distance_to(pair[1])-separation)
	return gap

static func _fixed_tube(path: PackedVector3Array,radius: float,fittings: RefCounted,hull: RefCounted,cancelled: Callable) -> Dictionary:
	if path.size()<2 or not is_finite(radius) or radius<=0 or fittings==null or hull==null or not fittings.valid or not hull.valid:
		return {"valid":false,"reason":"invalid fixed contact boundary"}
	for point in path:
		if not point.is_finite(): return {"valid":false,"reason":"nonfinite fixed contact material"}
	var fitting_gap := INF
	var hull_gap := INF
	var worst := {}
	for i in path.size()-1:
		if cancelled.call(): return {"valid":false,"reason":"fixed contact check cancelled"}
		var count := maxi(2,ceili(path[i].distance_to(path[i+1])/.0004))
		for j in count+1:
			var point := path[i].lerp(path[i+1],j/float(count))
			var fitting: Dictionary=fittings.query(point,radius,.005)
			var support: Dictionary=hull.query(point,radius,.001)
			if fitting.gap<fitting_gap:
				fitting_gap=fitting.gap
				worst={"index":i,"point":point,"contact":fitting}
			hull_gap=minf(hull_gap,support.gap)
	return {"valid":fitting_gap>=.00025 and hull_gap>=.00025,"reason":"whole traveller/fixed fitting or hull clearance","fitting_gap":fitting_gap,"hull_gap":hull_gap,"worst":worst}

static func check_geometry(input: Dictionary,solved: Dictionary,datum: Vector3,result: Dictionary,cancelled: Callable) -> Dictionary:
	var fields := []
	var faces := []
	var extents := []
	var frames := []
	for key in ["lower","upper","aft"]: frames.append(result.poses[key])
	for records: Array in input.bodies:
		var field := FIELD.new()
		if not field.add_records(records,cancelled): return {"valid":false,"reason":"invalid body records"}
		fields.append(field)
		var geometry := _faces(records)
		faces.append(geometry)
		var extent := 0.0
		for p in geometry: extent=maxf(extent,p.length())
		extents.append(extent)
	var hull := FIELD.new()
	if not hull.add_records(input.hull,cancelled): return {"valid":false,"reason":"invalid hull records"}
	var fixed_hardware := FIELD.new()
	if not fixed_hardware.add_records(input.fixed_hardware,cancelled): return {"valid":false,"reason":"invalid fixed hardware records"}
	for i in 3:
		if cancelled.call(): return {"valid":false,"reason":"geometry cancelled"}
		var pair := PAIR.new()
		if not pair.setup(faces[i],cancelled): return {"valid":false,"reason":"invalid body faces"}
		for contact: Dictionary in pair.contacts(frames[i],hull,.000048):
			if contact.gap<.000048: return {"valid":false,"reason":"body/hull contact requires another equilibrium","contact":contact}
		if i<2:
			for contact: Dictionary in pair.contacts(frames[i],fixed_hardware,.000048):
				if contact.gap<.000048: return {"valid":false,"reason":"actual fairlead contact requires another equilibrium","contact":contact}
	var pair := PAIR.new()
	pair.setup(faces[1],cancelled)
	for contact: Dictionary in pair.contacts(frames[0].affine_inverse()*frames[1],fields[0],.00039):
		if contact.gap<=.00039: return {"valid":false,"reason":"finite shared pin clearance","contact":contact}
	var tiller: Transform3D=input.boundary.tiller
	# The earlier body guard covered blocks against fittings, but not the
	# complete rope against those same real aperture/lip/cleat surfaces.
	var fixed_contact := _fixed_tube(result.traveller_path,.003,fixed_hardware,hull,cancelled)
	if not fixed_contact.valid: return {"valid":false,"reason":fixed_contact.reason,"detail":fixed_contact}
	var low := _tube(result.traveller_path,.003,frames,fields,extents,tiller,cancelled)
	if not low.valid: return {"valid":false,"reason":"traveller "+low.reason,"detail":low}
	var high := _tube(result.path,.004,frames,fields,extents,tiller,cancelled)
	if not high.valid: return {"valid":false,"reason":"mainsheet "+high.reason,"detail":high}
	var knot := _tube(result.fixed,.004,frames,fields,extents,tiller,cancelled)
	if not knot.valid: return {"valid":false,"reason":"fixed knot "+knot.reason,"detail":knot}
	var cross_gap := _rope_pair(result.traveller_path,result.path,.007,cancelled)
	cross_gap=minf(cross_gap,_rope_pair(result.traveller_path,result.fixed,.007,cancelled))
	if cross_gap<.00025: return {"valid":false,"reason":"two material paths intersect","gap":cross_gap}
	# The adjoining first 30 mm is the same material at the becket, not a
	# collision between two independent rope portions.
	var first := 0
	var distance := 0.0
	while first<result.fixed.size()-2 and distance<.030:
		distance+=result.fixed[first].distance_to(result.fixed[first+1])
		first+=1
	var knot_gap := _rope_pair(result.path,result.fixed.slice(first),.008,cancelled)
	if knot_gap<.00025: return {"valid":false,"reason":"fixed stopper intersects loaded sheet","gap":knot_gap}
	return {"valid":not cancelled.call(),"reason":"finite static assembly checked","lower":low,"upper":high,"knot":knot,"fixed_contact":fixed_contact,"rope_gap":cross_gap,"knot_gap":knot_gap,"datum":datum,"length_error_m":solved.length_error_m}

extends RefCounted

## Detached actual triangle contacts for a fixed-support articulated pair.
## Both containment directions are checked. The connector itself and its
## traveller cable are deliberately absent from this foundation.
const FIELD := preload("res://src/boat/mesh_rope_obstacle.gd")
const BODY := preload("res://src/boat/mesh_block_support.gd")
const SIGNED := preload("res://src/boat/spatial_block_support.gd")
const KIN := preload("res://src/boat/linked_swivel_configuration.gd")
var static_field := FIELD.new()
var lower_field := FIELD.new()
var upper_field := FIELD.new()
var lower_static := BODY.new()
var upper_static := BODY.new()
var upper_lower := BODY.new()
var lower_upper := SIGNED.new()
var valid := false
var queries := 0
var query_usec := 0
var cache_key := []
var cached := {}
var lower_frames := []
var upper_frames := []
var profile := {"milliseconds":[0.0,0.0,0.0,0.0],"maximum_rows":0}

func setup(lower_faces: PackedVector3Array,upper_faces: PackedVector3Array,records: Array,lines: Array,cancelled := Callable(),lower_parts: Array=[],upper_parts: Array=[]) -> bool:
	valid=false
	static_field=FIELD.new()
	lower_field=FIELD.new()
	upper_field=FIELD.new()
	lower_frames=[]
	upper_frames=[]
	queries=0
	query_usec=0
	profile={"milliseconds":[0.0,0.0,0.0,0.0],"maximum_rows":0}
	if not static_field.add_records(records,cancelled): return false
	for line: Dictionary in lines: static_field.add_capsules(line.path,line.radius,line.label)
	# A rendered block is a UNION of separate solids. Flattening overlapping
	# components into one ray-parity shell would create false interior holes.
	if lower_parts.is_empty(): lower_field.add_faces(lower_faces,Transform3D.IDENTITY,"lower body",cancelled)
	else: lower_field.add_records(lower_parts,cancelled)
	if upper_parts.is_empty(): upper_field.add_faces(upper_faces,Transform3D.IDENTITY,"upper body",cancelled)
	else: upper_field.add_records(upper_parts,cancelled)
	for entry: Dictionary in lower_field.entries: lower_frames.append(entry.frame)
	for entry: Dictionary in upper_field.entries: upper_frames.append(entry.frame)
	valid=static_field.valid and lower_field.valid and upper_field.valid and lower_static.setup(lower_faces,static_field,cancelled) and upper_static.setup(upper_faces,static_field,cancelled) and upper_lower.setup(upper_faces,lower_field,cancelled) and lower_upper.setup(lower_faces,upper_field,cancelled)
	# Only static boundaries retain a useful geometric lower-bound cache.
	# Dynamic pair fields invalidate it on every obstacle revision.
	lower_static.coherent_cache_enabled=true
	upper_static.coherent_cache_enabled=true
	cache_key=[]
	cached={}
	return valid

func query(configuration: Dictionary) -> Dictionary:
	if not valid or not _valid_configuration(configuration): return {"valid":false,"reason":"invalid linked mesh field"}
	var key := _configuration_key(configuration)
	if key==cache_key: return cached
	var moving_lower := []
	var moving_upper := []
	for frame: Transform3D in lower_frames: moving_lower.append(configuration.lower*frame)
	for frame: Transform3D in upper_frames: moving_upper.append(configuration.upper*frame)
	if not lower_field.move_entries(moving_lower) or not upper_field.move_entries(moving_upper): return {"valid":false,"reason":"invalid moving rigid mesh"}
	var started := Time.get_ticks_usec()
	queries+=1
	var rows := []
	var gaps := []
	var models := [lower_static,upper_static,upper_lower,lower_upper]
	for kind in 4:
		var phase := Time.get_ticks_usec()
		var model: RefCounted=models[kind]
		var frame: Transform3D=configuration.lower if kind in [0,3] else configuration.upper
		# The full band traversal already contains EVERY point witness inside
		# the band, every negative signed witness, and every exact near triangle
		# pair. Repeating a nearest-point traversal first duplicated most work.
		# Do not drop witnesses, quantize positions, or relax the contact band.
		if model.body.tree.is_empty() or not model.field.valid: return {"valid":false,"reason":"invalid articulated mesh clearance"}
		var witnesses: Array=model.contact_constraints(frame,Vector3.ZERO,.00020)
		var minimum_gap := .00020
		for witness: Dictionary in witnesses:
			minimum_gap=minf(minimum_gap,witness.gap)
			var row := {}
			if kind<2: row=_contact(configuration,kind,witness.point,witness.normal,witness.gap)
			elif kind==2: row=_contact(configuration,2,witness.point,witness.normal,witness.gap,witness.point-witness.normal*witness.gap)
			else: row=_contact(configuration,2,witness.point-witness.normal*witness.gap,-witness.normal,witness.gap,witness.point)
			if not row.valid: return row
			row["surface"]=witness.get("surface","")
			rows.append(row)
		gaps.append(minimum_gap)
		profile.milliseconds[kind]+=(Time.get_ticks_usec()-phase)/1000.0
	profile.maximum_rows=maxi(profile.maximum_rows,rows.size())
	query_usec+=Time.get_ticks_usec()-started
	cache_key=key
	cached={"valid":true,"rows":rows,"minimum_gaps":gaps}
	return cached

func _valid_configuration(configuration: Dictionary) -> bool:
	return KIN.valid_configuration(configuration)

func _configuration_key(configuration: Dictionary) -> Array:
	return [configuration.lower,configuration.upper,configuration.first,configuration.last,static_field.revision]

func _contact(configuration: Dictionary,kind: int,point: Vector3,normal: Vector3,gap: float,other := Vector3(NAN,NAN,NAN)) -> Dictionary:
	return KIN.contact(configuration,kind,point,normal,gap,other)

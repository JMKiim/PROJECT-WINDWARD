extends RefCounted

## Closed annular bearing about local X. Dimensions belong to the caller;
## this numeric primitive is not a certified fitting or a spherical joint.
static func valid(inner: float,outer: float,depth: float,segments: int) -> bool:
	return is_finite(inner) and is_finite(outer) and is_finite(depth) and inner>0 and outer>inner and depth>0 and segments>=12 and segments<=256

static func distance(point: Vector3,inner: float,outer: float,depth: float) -> float:
	if not point.is_finite() or not valid(inner,outer,depth,32): return NAN
	var axial := absf(point.x)-depth*.5
	var radial := Vector2(point.y,point.z).length()
	var wall := maxf(inner-radial,radial-outer)
	return Vector2(maxf(axial,0),maxf(wall,0)).length()+minf(maxf(axial,wall),0)

static func arrays(inner: float,outer: float,depth: float,segments := 48) -> Array:
	if not valid(inner,outer,depth,segments): return []
	var angles := PackedFloat64Array()
	var radii := PackedFloat64Array()
	for index in segments:
		angles.append(TAU*index/segments)
		radii.append(outer)
	return _profile_arrays(inner,depth,angles,radii)

static func stemmed_arrays(inner: float,outer: float,depth: float,stem_end: float,stem_width: float,segments := 48) -> Array:
	if not valid(inner,outer,depth,segments) or not is_finite(stem_end) or not is_finite(stem_width) or stem_end<=outer or stem_width<=0 or stem_width>=outer*2: return []
	# One closed extruded profile joins the round eye to its positive-Y stem.
	# Separate overlapping boxes would create coplanar faces and flicker.
	var angles := PackedFloat64Array()
	for index in segments: angles.append(TAU*index/segments)
	for angle in [asin(stem_width*.5/outer),atan2(stem_width*.5,stem_end)]:
		angles.append(angle)
		angles.append(TAU-angle)
	angles.sort()
	var unique := PackedFloat64Array()
	for angle in angles:
		if unique.is_empty() or angle-unique[-1]>1e-10: unique.append(angle)
	var radii := PackedFloat64Array()
	for angle in unique:
		var radius := outer
		if cos(angle)>0:
			var edge := minf(stem_end/cos(angle),stem_width*.5/maxf(absf(sin(angle)),1e-12))
			radius=maxf(radius,edge)
		radii.append(radius)
	return _profile_arrays(inner,depth,unique,radii)

static func _profile_arrays(inner: float,depth: float,angles: PackedFloat64Array,radii: PackedFloat64Array) -> Array:
	var segments := angles.size()
	var outline := PackedVector3Array()
	for index in segments: outline.append(Vector3(0,cos(angles[index]),sin(angles[index]))*radii[index])
	var outer_normals := PackedVector3Array()
	for index in segments:
		var a := (outline[index]-outline[(index-1+segments)%segments]).normalized()
		var b := (outline[(index+1)%segments]-outline[index]).normalized()
		outer_normals.append(Vector3(0,a.z+b.z,-a.y-b.y).normalized())
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	# Four independently shaded walls, sharing geometric edge positions.
	# The inner wall is a real through-bore; no disc fills its opening.
	for wall in 4:
		var start := points.size()
		for ring in 2:
			var x := depth*(ring-.5) if wall<2 else depth*(-.5 if wall==2 else .5)
			for index in segments:
				var radius: float=(radii[index] if wall==0 else inner) if wall<2 else (inner if ring==0 else radii[index])
				var angle := angles[index]
				var radial := Vector3(0,cos(angle),sin(angle))
				points.append(Vector3(x,0,0)+radial*radius)
				normals.append((outer_normals[index] if wall==0 else -radial) if wall<2 else Vector3.LEFT if wall==2 else Vector3.RIGHT)
		for index in segments:
			var a := start+index
			var b := start+(index+1)%segments
			var c := b+segments
			var d := a+segments
			_triangle(indices,points,normals,a,b,c)
			_triangle(indices,points,normals,a,c,d)
	var result := []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX]=points
	result[Mesh.ARRAY_NORMAL]=normals
	result[Mesh.ARRAY_INDEX]=indices
	return result

static func _triangle(indices: PackedInt32Array,points: PackedVector3Array,normals: PackedVector3Array,a: int,b: int,c: int) -> void:
	# Godot front faces use clockwise winding.
	if (points[b]-points[a]).cross(points[c]-points[a]).dot(normals[a])>0:
		indices.append_array(PackedInt32Array([a,c,b]))
	else: indices.append_array(PackedInt32Array([a,b,c]))

static func faces(data: Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	if data.size()!=Mesh.ARRAY_MAX or not data[Mesh.ARRAY_VERTEX] is PackedVector3Array or not data[Mesh.ARRAY_INDEX] is PackedInt32Array: return result
	var points: PackedVector3Array=data[Mesh.ARRAY_VERTEX]
	if data[Mesh.ARRAY_INDEX].is_empty() or data[Mesh.ARRAY_INDEX].size()%3!=0: return result
	for index: int in data[Mesh.ARRAY_INDEX]:
		if index<0 or index>=points.size(): return PackedVector3Array()
		if not points[index].is_finite(): return PackedVector3Array()
		result.append(points[index])
	return result

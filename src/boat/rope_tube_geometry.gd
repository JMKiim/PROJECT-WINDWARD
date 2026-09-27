extends RefCounted

## Pure numeric swept skin. No Mesh, Node or rendering-server access here.
static func build(points: PackedVector3Array,radius: float,sides := 16) -> Array:
	if points.size()<2 or not is_finite(radius) or radius<=0 or sides<3: return []
	for point in points:
		if not point.is_finite(): return []
	if points.size()>=4 and points[0].distance_squared_to(points[-1])<1e-16:
		return _closed(points,radius,sides)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.resize(points.size()*sides+2)
	normals.resize(vertices.size())
	indices.resize(points.size()*sides*6)
	var cursor := 0
	var u := Vector3.ZERO
	var angles := []
	for side in sides: angles.append(Vector2(cos(TAU*side/sides),sin(TAU*side/sides)))
	for index in points.size():
		var tangent := (points[mini(index+1,points.size()-1)]-points[maxi(0,index-1)]).normalized()
		u-=tangent*u.dot(tangent)
		if u.length_squared()<.000001: u=tangent.cross(Vector3.UP if absf(tangent.y)<.9 else Vector3.RIGHT)
		u=u.normalized()
		var v := tangent.cross(u).normalized()
		for side in sides:
			var normal: Vector3=u*angles[side].x+v*angles[side].y
			vertices[index*sides+side]=points[index]+normal*radius
			normals[index*sides+side]=normal
			if index==0: continue
			var a := (index-1)*sides+side
			var b := (index-1)*sides+(side+1)%sides
			var c := index*sides+(side+1)%sides
			var d := index*sides+side
			indices[cursor]=a
			indices[cursor+1]=c
			indices[cursor+2]=b
			indices[cursor+3]=a
			indices[cursor+4]=d
			indices[cursor+5]=c
			cursor+=6
	for end in 2:
		var ring: int=0 if end==0 else points.size()-1
		var normal := (points[0]-points[1]).normalized() if end==0 else (points[-1]-points[-2]).normalized()
		var centre := points.size()*sides+end
		vertices[centre]=points[ring]
		normals[centre]=normal
		for side in sides:
			var a: int=ring*sides+side
			var b: int=ring*sides+(side+1)%sides
			indices[cursor]=centre
			indices[cursor+1]=a if end==0 else b
			indices[cursor+2]=b if end==0 else a
			cursor+=3
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_INDEX]=indices
	return arrays

static func _closed(points: PackedVector3Array,radius: float,sides: int) -> Array:
	# A repeated endpoint denotes a closed ring, not two capped open ends.
	# Share the first ring's indices at the seam and spread frame holonomy
	# around the loop rather than leaving one abrupt cross-section twist.
	var count := points.size()-1
	var tangents := PackedVector3Array()
	var frames := PackedVector3Array()
	var distances := PackedFloat64Array([0.0])
	var total := 0.0
	var u := Vector3.ZERO
	for index in count:
		if not points[index].is_finite(): return []
		var tangent := (points[(index+1)%count]-points[(index+count-1)%count]).normalized()
		if tangent.is_zero_approx(): return []
		u-=tangent*u.dot(tangent)
		if u.length_squared()<.000001: u=tangent.cross(Vector3.UP if absf(tangent.y)<.9 else Vector3.RIGHT)
		u=u.normalized()
		tangents.append(tangent)
		frames.append(u)
		total+=points[index].distance_to(points[(index+1)%count])
		distances.append(total)
	if total<.000001: return []
	var wrapped := (u-tangents[0]*u.dot(tangents[0])).normalized()
	if wrapped.is_zero_approx(): return []
	var correction := atan2(tangents[0].dot(wrapped.cross(frames[0])),wrapped.dot(frames[0]))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.resize(count*sides)
	normals.resize(count*sides)
	indices.resize(count*sides*6)
	for index in count:
		u=Basis(tangents[index],correction*distances[index]/total)*frames[index]
		var v := tangents[index].cross(u).normalized()
		for side in sides:
			var angle := TAU*side/sides
			var normal := u*cos(angle)+v*sin(angle)
			vertices[index*sides+side]=points[index]+normal*radius
			normals[index*sides+side]=normal
			var a := index*sides+side
			var b := index*sides+(side+1)%sides
			var c := ((index+1)%count)*sides+(side+1)%sides
			var d := ((index+1)%count)*sides+side
			var cursor := (index*sides+side)*6
			indices[cursor]=a
			indices[cursor+1]=c
			indices[cursor+2]=b
			indices[cursor+3]=a
			indices[cursor+4]=d
			indices[cursor+5]=c
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_INDEX]=indices
	return arrays

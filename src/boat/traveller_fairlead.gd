extends RefCounted

## Open-base fitting. Main dimensions follow the A.282 reference drawing;
## screw centres follow the current product table. Crown/seat detail is a
## bounded reconstruction, not a manufacturing surface or load certificate.
const LENGTH := .041
const DEPTH := .0145
const HEIGHT := .018
const OPENING := .010
const OPENING_HEIGHT := .013
const SCREW_CENTRES := .0235
const SCREW_BORE := .005
const SEAT_RADIUS := .0041
const SEAT_Y := .0045
const THROAT_Y := .0065
const HALF := OPENING*.5
const ARCH_Y := OPENING_HEIGHT-HALF
const END_CENTRE := (LENGTH-DEPTH)*.5
const HALF_DEPTH := DEPTH*.5
static var cached: ArrayMesh

static func roof(x: float) -> float:
	var a := absf(x)
	return .008+sqrt(.0001-a*a) if a<=.006 else .016-(a-.006)*.75

static func _outer(direction: Vector2) -> Vector2:
	var origin := Vector2(SCREW_CENTRES*.5,0)
	var candidates := []
	if direction.x<0:
		var t := (HALF-origin.x)/direction.x
		if absf(t*direction.y)<=HALF_DEPTH+1e-9: candidates.append(t)
	if absf(direction.y)>1e-10:
		var t := HALF_DEPTH/absf(direction.y)
		var x := origin.x+t*direction.x
		if x>=HALF-1e-9 and x<=END_CENTRE+1e-9: candidates.append(t)
	var offset := origin-Vector2(END_CENTRE,0)
	var dot := offset.dot(direction)
	var t := -dot+sqrt(maxf(0,dot*dot-offset.length_squared()+HALF_DEPTH*HALF_DEPTH))
	if origin.x+t*direction.x>=END_CENTRE-1e-9: candidates.append(t)
	candidates.sort()
	var result: Vector2=origin+direction*candidates[0]
	if absf(result.x-HALF)<1e-8: result.x=HALF
	if absf(absf(result.y)-HALF_DEPTH)<1e-8: result.y=signf(result.y)*HALF_DEPTH
	return result

static func _triangle(data: Dictionary,a: Vector3,b: Vector3,c: Vector3,normal: Vector3) -> void:
	a=a.snapped(Vector3.ONE*.00000001)
	b=b.snapped(Vector3.ONE*.00000001)
	c=c.snapped(Vector3.ONE*.00000001)
	var cross := (b-a).cross(c-a)
	if cross.length_squared()<1e-24: return
	var first: int=data.vertices.size()
	data.vertices.append_array(PackedVector3Array([a,b,c]))
	var n := normal.normalized()
	data.normals.append_array(PackedVector3Array([n,n,n]))
	data.indices.append_array(PackedInt32Array([first,first+2,first+1]) if cross.dot(n)>0 else PackedInt32Array([first,first+1,first+2]))

static func _quad(data: Dictionary,a: Vector3,b: Vector3,c: Vector3,d: Vector3,normal: Vector3) -> void:
	_triangle(data,a,b,c,normal)
	_triangle(data,a,c,d,normal)

static func _point(p: Vector2,y: float,side: float) -> Vector3: return Vector3(side*p.x,y,p.y)

static func arrays(segments := 64) -> Array:
	if segments<16 or segments>128 or segments%4!=0: return []
	var angles := PackedFloat64Array()
	for i in segments: angles.append(TAU*i/segments)
	for x in [HALF,END_CENTRE]:
		for z in [-HALF_DEPTH,HALF_DEPTH]: angles.append(fposmod(atan2(z,x-SCREW_CENTRES*.5),TAU))
	angles.sort()
	var unique := PackedFloat64Array()
	for angle in angles:
		if unique.is_empty() or angle-unique[-1]>1e-8: unique.append(angle)
	var outer := PackedVector2Array()
	var directions := PackedVector2Array()
	var z_values := PackedFloat32Array([-HALF_DEPTH,HALF_DEPTH])
	for angle in unique:
		var direction := Vector2(cos(angle),sin(angle))
		var end := _outer(direction)
		directions.append(direction)
		outer.append(end)
		if absf(end.x-HALF)<1e-8: z_values.append(end.y)
	z_values.sort()
	var bridge_z := PackedFloat32Array()
	for z in z_values:
		if bridge_z.is_empty() or z-bridge_z[-1]>.00000001: bridge_z.append(z)
	var data := {"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"indices":PackedInt32Array()}
	for side in [-1.0,1.0]:
		var origin := Vector2(SCREW_CENTRES*.5,0)
		var rings := []
		for layer in 7:
			var ring := PackedVector2Array()
			for i in unique.size():
				var start := origin+directions[i]*SEAT_RADIUS
				ring.append(origin+directions[i]*SCREW_BORE*.5 if layer==0 else start if layer<=2 else start.lerp(outer[i],(layer-2)/4.0))
			rings.append(ring)
		for i in unique.size():
			var j := (i+1)%unique.size()
			for layer in 6:
				var a: Vector2=rings[layer][i]
				var b: Vector2=rings[layer][j]
				var c: Vector2=rings[layer+1][j]
				var d: Vector2=rings[layer+1][i]
				var ya := SEAT_Y if layer<=1 else roof(a.x)
				var yb := SEAT_Y if layer<=1 else roof(b.x)
				var yc := SEAT_Y if layer==0 else roof(c.x)
				var yd := SEAT_Y if layer==0 else roof(d.x)
				var n := Vector3.UP if layer!=1 else Vector3(-side*(directions[i].x+directions[j].x),0,-directions[i].y-directions[j].y)
				if layer>1: n=Vector3(side*.75,1,0)
				_quad(data,_point(a,ya,side),_point(b,yb,side),_point(c,yc,side),_point(d,yd,side),n)
				if layer!=1: _quad(data,_point(a,0,side),_point(b,0,side),_point(c,0,side),_point(d,0,side),Vector3.DOWN)
			var a: Vector2=rings[0][i]
			var b: Vector2=rings[0][j]
			_quad(data,_point(a,0,side),_point(b,0,side),_point(b,SEAT_Y,side),_point(a,SEAT_Y,side),Vector3(-side*(directions[i].x+directions[j].x),0,-directions[i].y-directions[j].y))
			a=outer[i]
			b=outer[j]
			var inner := absf(a.x-HALF)<1e-8 and absf(b.x-HALF)<1e-8
			var midpoint := (a+b)*.5
			var outward := Vector3(-side,0,0) if inner else Vector3(side*maxf(0,midpoint.x-END_CENTRE),0,midpoint.y)
			if inner:
				_quad(data,_point(a,0,side),_point(b,0,side),_point(b,ARCH_Y,side),_point(a,ARCH_Y,side),outward)
			else:
				# Split the side edge where the open arch meets the foot. The
				# neighbouring underside must share edges, not end in a T-joint.
				var border := PackedVector3Array([_point(a,0,side),_point(b,0,side)])
				if absf(b.x-HALF)<1e-8: border.append(_point(b,ARCH_Y,side))
				border.append(_point(b,roof(b.x),side))
				border.append(_point(a,roof(a.x),side))
				if absf(a.x-HALF)<1e-8: border.append(_point(a,ARCH_Y,side))
				var centre := Vector3.ZERO
				for p in border: centre+=p
				centre/=border.size()
				for k in border.size(): _triangle(data,centre,border[k],border[(k+1)%border.size()],outward)
	for i in segments/2:
		var angle0 := PI*i/(segments/2.0)
		var angle1 := PI*(i+1)/(segments/2.0)
		var x0 := HALF*cos(angle0)
		var x1 := HALF*cos(angle1)
		var y0 := ARCH_Y+HALF*sin(angle0)
		var y1 := ARCH_Y+HALF*sin(angle1)
		for j in bridge_z.size()-1:
			var z0 := bridge_z[j]
			var z1 := bridge_z[j+1]
			_quad(data,Vector3(x0,roof(x0),z0),Vector3(x1,roof(x1),z0),Vector3(x1,roof(x1),z1),Vector3(x0,roof(x0),z1),Vector3(0,1,0))
			_quad(data,Vector3(x0,y0,z0),Vector3(x1,y1,z0),Vector3(x1,y1,z1),Vector3(x0,y0,z1),Vector3(-cos((angle0+angle1)*.5),-sin((angle0+angle1)*.5),0))
		for z in [-HALF_DEPTH,HALF_DEPTH]:
			_quad(data,Vector3(x0,y0,z),Vector3(x1,y1,z),Vector3(x1,roof(x1),z),Vector3(x0,roof(x0),z),Vector3(0,0,signf(z)))
	var result := []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX]=data.vertices
	result[Mesh.ARRAY_NORMAL]=data.normals
	result[Mesh.ARRAY_INDEX]=data.indices
	return result

static func mesh() -> ArrayMesh:
	if cached==null:
		cached=ArrayMesh.new()
		cached.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays())
	return cached

extends RefCounted

## Intersection of finite fitting/line clearance and the existing sampled
## hull support envelope. Hull projection is vertical in the gravity frame;
## it is a geometric constraint, not a surface-force equilibrium.
var fittings: RefCounted
var hull: RefCounted
var up := Vector3.UP
var valid := false
var ceilings := {}

func setup(obstacles: RefCounted,support: RefCounted) -> void:
	fittings=obstacles
	hull=support
	ceilings.clear()
	valid=fittings!=null and hull!=null and fittings.valid and hull.valid
	if valid: up=hull.frame.y

func restricted(region: AABB) -> RefCounted:
	var result: RefCounted=get_script().new()
	result.setup(fittings.restricted(region),hull)
	result.ceilings=ceilings
	return result

func query(point: Vector3,radius: float,limit := .02) -> Dictionary:
	var result: Dictionary=fittings.query(point,radius,limit)
	# Rounded triangles cannot exceed their highest vertex plus rope radius.
	# Skip detailed hull edges when even that conservative cell-wide ceiling
	# is farther than the current fitting result. No clearance is approximated.
	if point.dot(up)-height_ceiling(point)>=result.gap: return result
	var height: float=hull.height_at(point)
	if not is_finite(height): return result
	var gap := point.dot(up)-height
	if gap<result.gap: return {"gap":gap,"point":point-up*gap,"normal":up,"mesh":"hull support"}
	return result

func height_ceiling(point: Vector3) -> float:
	var local: Vector3=hull.frame.transposed()*point
	var key := Vector2i(floori(local.x/hull.cell_size),floori(local.z/hull.cell_size))
	if ceilings.has(key): return ceilings[key]
	var highest := -INF
	for index: int in hull.cells.get(key,PackedInt32Array()):
		var triangle: Dictionary=hull.triangles[index]
		highest=maxf(highest,maxf(triangle.a.y,maxf(triangle.b.y,triangle.c.y))+hull.radius)
	ceilings[key]=highest
	return highest

func project(point: Vector3,radius: float) -> Dictionary:
	for iteration in 12:
		var contact := query(point,radius,.00006)
		if contact.gap>=.00004: return {"valid":true,"point":point}
		point+=contact.normal*(.00005-contact.gap)
	return {"valid":false,"point":point,"contact":query(point,radius)}

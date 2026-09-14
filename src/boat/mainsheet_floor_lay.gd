extends RefCounted

## Authored flat folds: their material length grows monotonically with width.
## The inlet and end remain fixed; no moving splice sweeps across other turns.
const ROWS := 22
const TURN_RADIUS := .009
const INLET := Vector3(-.210,0,.850)
const MAX_WIDTH := .540
var hull: MeshInstance3D
var minimum_path := PackedVector3Array()
var minimum_length := 0.0
var maximum_length := 0.0
var poses: Array[PackedVector3Array] = []
var lengths := PackedFloat64Array()

func setup(value: MeshInstance3D) -> void:
	hull = value
	for index in 65:
		var path := _path(MAX_WIDTH*pow(index/64.0,2))
		poses.append(path)
		lengths.append(_length(path))
	minimum_path = poses[0]
	minimum_length = lengths[0]
	maximum_length = lengths[-1]

func _floor(point: Vector3) -> Vector3:
	# A shared smooth plan-view warp bends adjacent strands together without
	# introducing crossings. Individual folds do not form a rectangular mat.
	point.z += .045*sin(PI*(point.x-INLET.x)/MAX_WIDTH)
	point.y = hull.cockpit_floor_y_at(point.x,point.z)+.006
	return point

func _row_edges(row: int,value: float) -> Vector2:
	var fold := row/2
	var threshold := .64*fold/(ROWS/2-1)
	var deployed := smoothstep(threshold,threshold+.36,value/MAX_WIDTH)
	var variation := .88+.12*sin(fold*1.71+.6)
	var left := INLET.x+.008*sin(fold*.83)*deployed
	if fold==0 or fold==ROWS/2-1: left = INLET.x
	return Vector2(left,left+MAX_WIDTH*variation*deployed)

func _path(value: float) -> PackedVector3Array:
	var result := PackedVector3Array([_floor(INLET)])
	for row in ROWS:
		var direction := 1.0 if row%2==0 else -1.0
		var z := INLET.z+row*TURN_RADIUS*2
		var edges := _row_edges(row,value)
		for part in range(1,25):
			var fraction := float(part)/24
			var x := lerpf(edges.x,edges.y,fraction if direction>0 else 1-fraction)
			var wave := .0025*sin(PI*fraction)*sin(row*.7)*smoothstep(0,.05,edges.y-edges.x)
			result.append(_floor(Vector3(x,0,z+wave)))
		if row==ROWS-1: break
		var next := _row_edges(row+1,value)
		var edge := edges.y if direction>0 else edges.x
		var next_edge := next.y if direction>0 else next.x
		var bulge := smoothstep(0,.036,maxf(edges.y-edges.x,next.y-next.x))
		for part in range(1,17):
			var angle := PI*part/16.0
			result.append(_floor(Vector3(lerpf(edge,next_edge,(1-cos(angle))*.5)+direction*TURN_RADIUS*sin(angle)*bulge,0,z+TURN_RADIUS*(1-cos(angle)))))
	# A broad final quarter turn lets the free end face aft, clear of the lay.
	var last := Vector3(INLET.x,0,INLET.z+(ROWS-1)*TURN_RADIUS*2)
	for part in range(1,17):
		var angle := PI*.5*part/16.0
		result.append(_floor(last+Vector3(-sin(angle)*.018,0,(1-cos(angle))*.018)))
	return result

func build(metres: float) -> PackedVector3Array:
	if metres<0 or metres>maximum_length: return PackedVector3Array()
	if metres<=minimum_length: return _prefix(minimum_path,metres)
	var low := 0
	var high := lengths.size()-1
	while high-low>1:
		var mid := (low+high)/2
		if lengths[mid]<metres: low = mid
		else: high = mid
	var fraction := (metres-lengths[low])/(lengths[high]-lengths[low])
	var result := PackedVector3Array()
	for iteration in 4:
		result.clear()
		for index in poses[low].size(): result.append(poses[low][index].lerp(poses[high][index],fraction))
		var error := _length(result)-metres
		if absf(error)<.000025: break
		fraction = clampf(fraction-error/(lengths[high]-lengths[low]),0,1)
	return result

static func _length(path: PackedVector3Array) -> float:
	var result := 0.0
	for index in path.size()-1: result += path[index].distance_to(path[index+1])
	return result

static func _prefix(path: PackedVector3Array,metres: float) -> PackedVector3Array:
	var result := PackedVector3Array([path[0]])
	for index in range(1,path.size()):
		var length := path[index-1].distance_to(path[index])
		if metres<=length:
			result.append(path[index-1].move_toward(path[index],metres))
			return result
		result.append(path[index])
		metres -= length
	return result

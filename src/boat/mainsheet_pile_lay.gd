extends RefCounted

## Fixed, length-driven loop shapes. Contact settling is precomputed during
## setup; no random motion or rope simulation runs in the frame loop.
const BASE := preload("res://src/boat/mainsheet_floor_lay.gd")
const BANK := preload("res://src/boat/animation/mainsheet_pile_bank.gd")
const LOOPS := 20
const STEPS := 96
const ENTRY_STEPS := 16
const INLET := Vector3(.140,0,.345)
const OUTLET := Vector3(.165,0,.795)
const CLEARANCE := .014
var hull: MeshInstance3D
var minimum_path := PackedVector3Array()
var minimum_length := 0.0
var maximum_length := 0.0
var poses: Array[PackedVector3Array] = []
var lengths := PackedFloat64Array()

func load_bank(value: MeshInstance3D) -> bool:
	var path := "res://src/boat/animation/mainsheet_pile_bank.res"
	if not ResourceLoader.exists(path): return false
	var bank: Resource = load(path)
	if not bank is BANK or not bank.valid(): return false
	hull = value
	poses.assign(bank.poses)
	lengths = bank.lengths
	minimum_path = poses[0]
	minimum_length = lengths[0]
	maximum_length = lengths[-1]
	return true

func setup(value: MeshInstance3D) -> void:
	hull = value
	poses.clear()
	lengths.clear()
	for index in 257:
		var path := _path(index / 256.0)
		poses.append(path)
		lengths.append(BASE._length(path))
	minimum_path = poses[0]
	minimum_length = lengths[0]
	maximum_length = lengths[-1]

func _ground(point: Vector3) -> Vector3:
	# A smooth plan-view map confines all loops to the toe's outside edge.
	point.x = .140+.170*(.5+.5*tanh((point.x-.205)/.085))
	point.z = .310+.580*(.5+.5*tanh((point.z-.555)/.250))
	point.y = hull.cockpit_floor_y_at(point.x,point.z)+.006
	return point

func _path(amount: float) -> PackedVector3Array:
	var first := _ground(INLET)
	var entry := Vector3(.100,0,.330)
	entry.y = hull.cockpit_floor_y_at(entry.x,entry.z)+.006
	var result := PackedVector3Array([entry])
	# Keep the vertical incoming span outside the growing loops. Its grounded
	# entry is deposited first, so later turns can rest above it, never through it.
	for part in range(1,ENTRY_STEPS+1):
		var point := entry.lerp(first,part/float(ENTRY_STEPS))
		point.y = hull.cockpit_floor_y_at(point.x,point.z)+.006
		result.append(point)
	# Each loop grows from a short edge run. Asymmetric centres, radii and
	# lobes are fixed authored values, shared by forward and reverse input.
	for loop in LOOPS:
		var order := loop / float(LOOPS-1)
		var deployed := smoothstep(order*.72, order*.72+.28, amount)
		for sample in range(1,STEPS+1):
			var t := sample / float(STEPS)
			var phase := TAU*t
			var baseline := INLET.lerp(OUTLET,(loop+t)/LOOPS)
			var width := .100 + .027*sin(loop*1.71+.8)
			var longitudinal := .130 + .034*sin(loop*2.31+.4)
			var angle := .85*sin(loop*1.63+.4)+.30*cos(loop*2.4)
			var oval := Vector2(width*(1-cos(phase))*.5,longitudinal*sin(phase)).rotated(angle)
			var x := baseline.x + deployed*oval.x
			var z := baseline.z + deployed*oval.y
			z += deployed*(.545-baseline.z)*(1-cos(phase))*.5
			x += deployed*.011*sin(phase)*sin(loop*.93)
			z += deployed*.023*sin(phase*2+.4)*sin(PI*t)
			result.append(_ground(Vector3(x,0,z)))
	_settle_heights(result)
	return result

func _settle_heights(path: PackedVector3Array) -> void:
	var material := PackedFloat32Array([0.0])
	for index in range(1,path.size()):
		material.append(material[-1]+path[index].distance_to(path[index-1]))
	var cells := {}
	var contacts := []
	for index in path.size():
		var flat_point := Vector2(path[index].x,path[index].z)
		var key := Vector2i(floori(flat_point.x/.020),floori(flat_point.y/.020))
		var nearby := []
		for dx in range(-1,2):
			for dz in range(-1,2):
				for previous: int in cells.get(key+Vector2i(dx,dz),[]):
					if previous+1>=index or material[index]-material[previous+1]<.030: continue
					var a := Vector2(path[previous].x,path[previous].z)
					var b := Vector2(path[previous+1].x,path[previous+1].z)
					var along := clampf((flat_point-a).dot(b-a)/maxf((b-a).length_squared(),.0000000001),0,1)
					var gap := flat_point.distance_squared_to(a.lerp(b,along))
					if gap<CLEARANCE*CLEARANCE:
						nearby.append([previous,along,sqrt(CLEARANCE*CLEARANCE-gap)])
		contacts.append(nearby)
		if not cells.has(key): cells[key] = []
		cells[key].append(index)
	# Finalize each deposited loop before stacking the next one. A later
	# smoothing pass must not lift a lower strand into an already placed one.
	for loop in LOOPS:
		var start := ENTRY_STEPS+loop*STEPS+1
		var finish := mini(ENTRY_STEPS+(loop+1)*STEPS,path.size()-1)
		for sweep in 8:
			for index in range(start,finish+1):
				for contact in contacts[index]:
					var previous: int = contact[0]
					path[index].y = maxf(path[index].y,lerpf(path[previous].y,path[previous+1].y,contact[1])+contact[2])
			for index in range(finish-1,start-1,-1):
				var span := Vector2(path[index].x-path[index+1].x,path[index].z-path[index+1].z).length()
				path[index].y = maxf(path[index].y,path[index+1].y-.6*span)
			for index in range(start,finish+1):
				var span := Vector2(path[index].x-path[index-1].x,path[index].z-path[index-1].z).length()
				path[index].y = maxf(path[index].y,path[index-1].y-.6*span)

func build(metres: float) -> PackedVector3Array:
	if metres<0 or metres>maximum_length: return PackedVector3Array()
	if metres<=minimum_length: return BASE._prefix(minimum_path,metres)
	var low := 0
	var high := lengths.size()-1
	while high-low>1:
		var mid := (low+high)/2
		if lengths[mid]<metres: low = mid
		else: high = mid
	var fraction := (metres-lengths[low])/(lengths[high]-lengths[low])
	var result := PackedVector3Array()
	for iteration in 5:
		result.clear()
		for index in poses[low].size(): result.append(poses[low][index].lerp(poses[high][index],fraction))
		var error := BASE._length(result)-metres
		if absf(error)<.000025: break
		fraction = clampf(fraction-error/(lengths[high]-lengths[low]),0,1)
	return result

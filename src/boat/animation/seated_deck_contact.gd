extends RefCounted

## Small support correction over authored poses. Limb lengths, palm frames
## and feet stay fixed; no runtime pose search or action replacement.
var actor: Node3D
var hull: MeshInstance3D
var body: MeshInstance3D
var support := []
var bind_bones := PackedInt32Array()
var bind_poses: Array[Transform3D] = []
var support_binds := PackedInt32Array()
var cache_bones := PackedInt32Array()
var cached_input := []
var cached_output := {}
var displacement := 0.0
var support_gap := INF
const CLEARANCE := .001

func setup(value: Node3D, surface: MeshInstance3D) -> void:
	actor=value
	hull=surface
	body=actor.skeleton.get_node("SuperHero_Male")
	for bind in body.skin.get_bind_count():
		bind_bones.append(actor.skeleton.find_bone(body.skin.get_bind_name(bind)))
		bind_poses.append(body.skin.get_bind_pose(bind))
	var arrays := body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
	var matrices := _matrices()
	var candidates := []
	var minimum := INF
	for i in vertices.size():
		var sample := {"vertex":vertices[i],"bones":bones.slice(i*4,i*4+4),"weights":weights.slice(i*4,i*4+4)}
		var p := _point(sample,matrices)
		if absf(p.x)<.38 or absf(p.x)>.66 or p.z<.42 or p.z>.82: continue
		var gap: float=p.y-hull.deck_y_at(p.x,p.z)
		minimum=minf(minimum,gap)
		candidates.append({"sample":sample,"gap":gap})
	for candidate in candidates:
		if candidate.gap<=minimum+.008: support.append(candidate.sample)
	for sample in support:
		for bind in sample.bones:
			if bind not in support_binds: support_binds.append(bind)
	for name in ["Hips","Spine","Chest","UpperChest"]:
		cache_bones.append(actor.skeleton.find_bone(name))
	for side in ["Left","Right"]:
		for suffix in ["Shoulder","UpperArm","LowerArm","Hand","UpperLeg","LowerLeg","Foot"]:
			cache_bones.append(actor.skeleton.find_bone(side+suffix))

func _matrices() -> Array[Transform3D]:
	var result: Array[Transform3D]=[]
	result.resize(bind_bones.size())
	var local: Transform3D=actor.global_transform.affine_inverse()*actor.skeleton.global_transform
	var required = range(bind_bones.size()) if support_binds.is_empty() else support_binds
	for i in required: result[i]=local*actor.skeleton.get_bone_global_pose(bind_bones[i])*bind_poses[i]
	return result

func _point(sample: Dictionary, matrices: Array[Transform3D]) -> Vector3:
	var result := Vector3.ZERO
	for slot in 4: result+=matrices[sample.bones[slot]]*sample.vertex*sample.weights[slot]
	return result

func gap() -> float:
	var result := INF
	var matrices := _matrices()
	for sample in support:
		var p := _point(sample,matrices)
		result=minf(result,p.y-hull.deck_y_at(p.x,p.z))
	return result

func apply() -> void:
	if support.is_empty() or actor.hike>=.16: return
	var weight := 1.0-smoothstep(.0,.16,actor.hike)
	var skeleton: Skeleton3D=actor.skeleton
	var key := [actor.hike,actor.seat_side]
	for bone in cache_bones: key.append(skeleton.get_bone_pose(bone))
	if key==cached_input:
		for bone in cached_output:
			var pose: Transform3D=cached_output[bone]
			skeleton.set_bone_pose_position(bone,pose.origin)
			skeleton.set_bone_pose_rotation(bone,pose.basis.get_rotation_quaternion())
		return
	displacement=0.0
	var hips: int=skeleton.find_bone("Hips")
	var original := skeleton.get_bone_pose_position(hips)
	var arms := []
	var legs := []
	var restore := {}
	for side in ["Left","Right"]:
		var arm := []
		var leg := []
		for suffix in ["UpperArm","LowerArm","Hand"]: arm.append(skeleton.get_bone_global_pose(skeleton.find_bone(side+suffix)))
		for suffix in ["UpperLeg","LowerLeg","Foot"]: leg.append(skeleton.get_bone_global_pose(skeleton.find_bone(side+suffix)))
		for suffix in ["Shoulder","UpperArm","LowerArm","Hand","UpperLeg","LowerLeg","Foot"]:
			var index := skeleton.find_bone(side+suffix)
			restore[index]=skeleton.get_bone_pose(index)
		arms.append(arm)
		legs.append(leg)
	var parent := skeleton.get_bone_parent(hips)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent>=0 else Basis.IDENTITY
	var down: Vector3=parent_basis.inverse()*skeleton.global_basis.inverse()*actor.global_basis*Vector3.DOWN
	var initial_gap := gap()
	for pass_index in 2:
		var error := initial_gap-CLEARANCE if pass_index==0 else gap()-lerpf(initial_gap,CLEARANCE,weight)
		displacement=clampf(displacement+error*(weight if pass_index==0 else 1.0),0,.075)
		for index in restore:
			var pose: Transform3D=restore[index]
			skeleton.set_bone_pose_position(index,pose.origin)
			skeleton.set_bone_pose_rotation(index,pose.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_position(hips,original+down*displacement)
		for i in 2:
			var side := "Left" if i==0 else "Right"
			_solve_leg(side,legs[i])
			var guide: Vector3=arms[i][1].origin+skeleton.global_basis.inverse()*actor.global_basis*Vector3.DOWN*displacement
			_seat_arm(side,arms[i],guide)
	support_gap=gap()
	cached_input=key
	cached_output.clear()
	for bone in restore: cached_output[bone]=skeleton.get_bone_pose(bone)
	cached_output[hips]=skeleton.get_bone_pose(hips)

func _seat_arm(side: String, poses: Array, guide: Vector3) -> void:
	var skeleton: Skeleton3D=actor.skeleton
	var up: Vector3=skeleton.global_basis.inverse()*actor.global_basis*Vector3.UP
	var scale := up.length()
	up=up.normalized()
	for attempt in 2:
		actor.look_pose._follow_shoulder(skeleton,side,poses,actor.tiller_hand(),guide)
		var shoulder := skeleton.get_bone_global_pose(skeleton.find_bone(side+"UpperArm")).origin
		var elbow := skeleton.get_bone_global_pose(skeleton.find_bone(side+"LowerArm")).origin
		var missing := .082*scale-(shoulder-elbow).dot(up)
		if missing<=0.0: break
		# Seating lowers the chest, but a high fixed grip may need the
		# clavicle to counter-rotate. Never lift above its authored height.
		var rise := minf(missing,(poses[0].origin-shoulder).dot(up))
		if rise<=.00001: break
		var bone := skeleton.find_bone(side+"Shoulder")
		var start := skeleton.get_bone_global_pose(bone)
		var arm := shoulder-start.origin
		var radius := arm.length()
		var height := minf(radius-.00001,arm.dot(up)+rise)
		var radial := (arm-up*arm.dot(up)).normalized()
		var target := up*height+radial*sqrt(maxf(0,radius*radius-height*height))
		actor.look_pose._set_basis(skeleton,bone,Basis(Quaternion(arm.normalized(),target.normalized()))*start.basis)
	# Refit after the final bounded clavicle construction.
	actor.look_pose._follow_shoulder(skeleton,side,poses,actor.tiller_hand(),guide)

func _solve_leg(side: String, poses: Array) -> void:
	var skeleton: Skeleton3D=actor.skeleton
	var upper := skeleton.find_bone(side+"UpperLeg")
	var lower := skeleton.find_bone(side+"LowerLeg")
	var foot := skeleton.find_bone(side+"Foot")
	var start := skeleton.get_bone_global_pose(upper).origin
	var end: Vector3=poses[2].origin
	var a: float=poses[0].origin.distance_to(poses[1].origin)
	var b: float=poses[1].origin.distance_to(end)
	var distance := clampf(start.distance_to(end),absf(a-b)+.00001,a+b-.00001)
	var axis := (end-start).normalized()
	var along := (a*a-b*b+distance*distance)/(2*distance)
	var center := start+axis*along
	var pole: Vector3=poses[1].origin-center
	pole-=axis*pole.dot(axis)
	var knee := center+pole.normalized()*sqrt(maxf(0,a*a-along*along))
	var turn := Basis(Quaternion((poses[1].origin-poses[0].origin).normalized(),(knee-start).normalized()))
	actor.look_pose._set_basis(skeleton,upper,turn*poses[0].basis)
	var actual := skeleton.get_bone_global_pose(lower).origin
	turn=Basis(Quaternion((end-poses[1].origin).normalized(),(end-actual).normalized()))
	actor.look_pose._set_basis(skeleton,lower,turn*poses[1].basis)
	actor.look_pose._set_basis(skeleton,foot,poses[2].basis)

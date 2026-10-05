extends "res://src/preview/land_drill/support/seated_look_pose.gd"

var body_basis := {}
var body_compensation := Basis.IDENTITY
var upper_chest := -1
var neck_bones := PackedInt32Array()
const BODY_TURN_SHARE := .625

func apply(skeleton: Skeleton3D,tiller_hand := "Right",helper_weight := 0.0) -> void:
	body_basis.clear()
	body_compensation=Basis.IDENTITY
	upper_chest=skeleton.find_bone("UpperChest")
	neck_bones=PackedInt32Array([skeleton.find_bone("Neck"),skeleton.find_bone("Head")])
	for name in ["Spine","Chest","UpperChest"]:
		var bone := skeleton.find_bone(name)
		body_basis[bone]=skeleton.get_bone_global_pose(bone).basis
	# A held extension bounds the trunk contribution to five degrees. The
	# original head/eye construction still reaches the complete requested
	# view angle; a constrained grip does not reduce the camera's look range.
	super.apply(skeleton,tiller_hand,helper_weight)
	torso_yaw*=BODY_TURN_SHARE
	body_basis.clear()

func _set_basis(skeleton: Skeleton3D,bone: int,basis: Basis) -> void:
	if body_basis.has(bone):
		var full_turn := basis
		basis=(body_basis[bone] as Basis).slerp(full_turn,BODY_TURN_SHARE)
		if bone==upper_chest: body_compensation=basis*full_turn.inverse()
	elif not body_basis.is_empty() and bone in neck_bones:
		# Do not charge the missing trunk angle to the neck. Preserve the
		# parent's bounded neck rotation; its eye layer supplies the remainder.
		basis=body_compensation*basis
	super._set_basis(skeleton,bone,basis)

## Keep a glance inside the authored elbow-height and wrist constraints.
## This intersects two analytic arcs on the fixed two-link elbow circle;
## it never searches action poses or moves an authored hand contact.
func _follow_shoulder(skeleton: Skeleton3D,side: String,original: Array,tiller_hand: String,elbow_guide := Vector3(INF,INF,INF)) -> void:
	super._follow_shoulder(skeleton,side,original,tiller_hand,elbow_guide)
	var upper := skeleton.find_bone(side+"UpperArm")
	var lower := skeleton.find_bone(side+"LowerArm")
	var hand := skeleton.find_bone(side+"Hand")
	var a := skeleton.get_bone_global_pose(upper)
	var b := skeleton.get_bone_global_pose(lower)
	var c := skeleton.get_bone_global_pose(hand)
	var up := skeleton.get_bone_global_pose(skeleton.find_bone("Spine")).basis.y.normalized()
	var minimum := .0805/skeleton.global_basis.x.length()
	if (a.origin-b.origin).dot(up)>=minimum: return
	var first := a.origin.distance_to(b.origin)
	var second := b.origin.distance_to(c.origin)
	var distance := a.origin.distance_to(c.origin)
	var axis := (c.origin-a.origin)/distance
	var along := (first*first-second*second+distance*distance)/(2*distance)
	var center := a.origin+axis*along
	var radius := sqrt(maxf(0,first*first-along*along))
	if radius<.000001: return
	var x := (b.origin-center).normalized()
	var y := axis.cross(x).normalized()
	var palm: Vector3=(c.basis*authored_grip.palm_offset(side,tiller_hand)).normalized()
	var arcs: Array[Vector2]=[Vector2(-PI,PI)]
	arcs=_intersect_arc(arcs,-up,(minimum+along*axis.dot(up))/radius,x,y)
	var wrist_bound := (second*cos(deg_to_rad(WRIST_CONE_DEGREES))-palm.dot(axis)*(distance-along))/radius
	arcs=_intersect_arc(arcs,-palm,wrist_bound,x,y)
	if arcs.is_empty(): return
	var angle := INF
	for arc in arcs:
		var candidate := clampf(0,arc.x,arc.y)
		if absf(candidate)<absf(angle): angle=candidate
	var elbow := center+(x*cos(angle)+y*sin(angle))*radius
	_set_basis(skeleton,upper,Basis(Quaternion((b.origin-a.origin).normalized(),(elbow-a.origin).normalized()))*a.basis)
	var actual := skeleton.get_bone_global_pose(lower).origin
	_set_basis(skeleton,lower,Basis(Quaternion((c.origin-b.origin).normalized(),(c.origin-actual).normalized()))*b.basis)
	var forearm := (c.origin-actual).normalized()
	var lower_basis := skeleton.get_bone_global_pose(lower).basis
	var neutral := (lower_basis*skeleton.get_bone_rest(hand).basis).z
	var desired := c.basis.z
	neutral=(neutral-forearm*neutral.dot(forearm)).normalized()
	desired=(desired-forearm*desired.dot(forearm)).normalized()
	_set_basis(skeleton,lower,Basis(forearm,neutral.signed_angle_to(desired,forearm))*lower_basis)
	_set_basis(skeleton,hand,c.basis)

func _intersect_arc(arcs: Array[Vector2],normal: Vector3,bound: float,x: Vector3,y: Vector3) -> Array[Vector2]:
	var result: Array[Vector2]=[]
	var nx := normal.dot(x)
	var ny := normal.dot(y)
	var magnitude := Vector2(nx,ny).length()
	if magnitude<.000001: return arcs if bound<=0 else result
	var ratio := bound/magnitude
	if ratio>1: return result
	if ratio<=-1: return arcs
	var center := atan2(ny,nx)
	var half_width := acos(ratio)
	for shift in [-TAU,0.0,TAU]:
		for arc in arcs:
			var low := maxf(arc.x,center+shift-half_width)
			var high := minf(arc.y,center+shift+half_width)
			if low<=high: result.append(Vector2(low,high))
	return result

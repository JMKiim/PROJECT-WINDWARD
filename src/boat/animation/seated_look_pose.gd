extends RefCounted

## A bounded look layer over the authored pose. Hand targets and fingers stay
## authored; a closed-form two-link adjustment follows the moving shoulders.
const MAX_YAW := deg_to_rad(110.0)
const MAX_TORSO_YAW := deg_to_rad(20.0)
var yaw := 0.0
var pitch := 0.0
var eye_pitch := 0.0
var eye_basis := Basis.IDENTITY
var torso_yaw := 0.0
var shoulder_follow_weight := 0.0
var maximum_reach_error := 0.0

func set_target(horizontal: float, vertical: float) -> void:
	if not is_finite(horizontal) or not is_finite(vertical): return
	yaw = clampf(horizontal,-MAX_YAW,MAX_YAW)
	pitch = clampf(vertical,deg_to_rad(-60),deg_to_rad(85))

func apply(skeleton: Skeleton3D, tiller_hand := "Right", helper_weight := 0.0) -> void:
	maximum_reach_error = 0.0
	var head_index := skeleton.find_bone("Head")
	var original_head := skeleton.get_bone_global_pose(head_index)
	var up := original_head.basis.y.normalized()
	var right := original_head.basis.x.normalized()
	var arms := []
	var body := {}
	for name in ["Spine","Chest","UpperChest","Neck","Head"]:
		body[name] = skeleton.get_bone_global_pose(skeleton.find_bone(name)).basis
	for side in ["Left","Right"]:
		var poses := []
		for name in ["UpperArm","LowerArm","Hand"]:
			poses.append(skeleton.get_bone_global_pose(skeleton.find_bone(side+name)))
		arms.append(poses)
	# Both hands supporting the sheet constrain the trunk. The eyes can finish
	# the glance while the neck stays bounded and the grips remain authored.
	torso_yaw = signf(yaw)*MAX_TORSO_YAW*lerpf(1.0,.4,helper_weight)*smoothstep(deg_to_rad(35),MAX_YAW,absf(yaw))
	var torso_pitch := signf(pitch)*deg_to_rad(10)*smoothstep(deg_to_rad(50),deg_to_rad(85),absf(pitch))
	shoulder_follow_weight = smoothstep(0.0,deg_to_rad(12),absf(torso_yaw)+absf(torso_pitch))
	# A downward glance also uses the eyes; folding the full view angle into
	# the neck drives the eye point through the shoulder at diagonal extremes.
	var neck_pitch := clampf(pitch-torso_pitch,deg_to_rad(-35),deg_to_rad(35))
	eye_pitch = pitch-torso_pitch-neck_pitch
	var neck_yaw := clampf(yaw-torso_yaw,deg_to_rad(-85),deg_to_rad(85))
	var cumulative := 0.0
	for item in [["Spine",.2],["Chest",.4],["UpperChest",.4]]:
		cumulative += item[1]
		_set_basis(skeleton,skeleton.find_bone(item[0]),Basis(up,torso_yaw*cumulative)*Basis(right,torso_pitch*cumulative)*body[item[0]])
	cumulative = 0.0
	for item in [["Neck",.4],["Head",.6]]:
		cumulative += item[1]
		_set_basis(skeleton,skeleton.find_bone(item[0]),Basis(up,torso_yaw+neck_yaw*cumulative)*Basis(right,torso_pitch+neck_pitch*cumulative)*body[item[0]])
	eye_basis = skeleton.get_bone_global_pose(head_index).basis.inverse()*Basis(up,yaw)*Basis(right,pitch)*original_head.basis
	for index in 2:
		_follow_shoulder(skeleton,"Left" if index==0 else "Right",arms[index],tiller_hand)

func _set_basis(skeleton: Skeleton3D, bone: int, basis: Basis) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var local_basis := skeleton.get_bone_global_pose(parent).basis.inverse()*basis
	skeleton.set_bone_pose_rotation(bone,local_basis.orthonormalized().get_rotation_quaternion())

func _follow_shoulder(skeleton: Skeleton3D, side: String, original: Array, tiller_hand: String) -> void:
	var upper := skeleton.find_bone(side+"UpperArm")
	var lower := skeleton.find_bone(side+"LowerArm")
	var hand := skeleton.find_bone(side+"Hand")
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	var old_upper: Transform3D = original[0]
	var old_lower: Transform3D = original[1]
	var held: Transform3D = original[2]
	var a := old_upper.origin.distance_to(old_lower.origin)
	var b := old_lower.origin.distance_to(held.origin)
	if shoulder.distance_squared_to(old_upper.origin)<.000000000001: return
	# The actual palm axis comes from the same authored grip definition.
	var grip := preload("res://src/boat/animation/authored_grip_profile.gd")
	var palm_direction: Vector3 = (held.basis*grip.palm_offset(side,tiller_hand)).normalized()
	if shoulder.distance_to(held.origin)>a+b-.005:
		_move_shoulder(skeleton,side,held.origin,a+b-.005)
		shoulder = skeleton.get_bone_global_pose(upper).origin
	# If a taut arm cannot retain the wrist cone, the clavicle follows the
	# turn as well. This is one geometric construction, not a pose search.
	var ideal_elbow := held.origin-palm_direction*b
	if not _wrist_feasible(shoulder,held.origin,palm_direction,a,b):
		_move_shoulder(skeleton,side,ideal_elbow,a)
		shoulder = skeleton.get_bone_global_pose(upper).origin
	var offset := held.origin-shoulder
	var distance := clampf(offset.length(),absf(a-b)+.0001,a+b-.0001)
	maximum_reach_error = maxf(maximum_reach_error,absf(offset.length()-distance))
	var axis := offset.normalized()
	var along := (a*a-b*b+distance*distance)/(2*distance)
	var center := shoulder+axis*along
	var shoulder_basis := skeleton.get_bone_global_pose(upper).basis
	var followed_elbow := shoulder+shoulder_basis*old_upper.basis.inverse()*(old_lower.origin-old_upper.origin)
	var pole := followed_elbow-center
	pole -= axis*pole.dot(axis)
	if pole.length_squared()<.000001: pole = axis.cross(Vector3.UP)
	pole = pole.normalized()
	# Bias the elbow away from the rotated chest, within the same wrist cone.
	var hips := skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).origin
	var chest := skeleton.get_bone_global_pose(skeleton.find_bone("UpperChest")).origin
	var outside := center-Geometry3D.get_closest_point_to_segment(center,hips,chest)
	outside -= axis*outside.dot(axis)
	if outside.length_squared()>.000001: pole = pole.lerp(outside.normalized(),.5*shoulder_follow_weight).normalized()
	var radius := sqrt(maxf(0,a*a-along*along))
	var preferred := -palm_direction+axis*palm_direction.dot(axis)
	if radius*preferred.length()>.000001:
		var required := (b*cos(deg_to_rad(44.5))-palm_direction.dot(axis)*(distance-along))/(radius*preferred.length())
		var allowed := acos(clampf(required,-1,1))
		preferred = preferred.normalized()
		var angle := preferred.signed_angle_to(pole,axis)
		pole = preferred.rotated(axis,clampf(angle,-allowed,allowed))
	var elbow := center+pole*radius
	var upper_turn := Basis(Quaternion((old_lower.origin-old_upper.origin).normalized(),(elbow-shoulder).normalized()))
	_set_basis(skeleton,upper,upper_turn*old_upper.basis)
	var actual_elbow := skeleton.get_bone_global_pose(lower).origin
	var lower_turn := Basis(Quaternion((held.origin-old_lower.origin).normalized(),(held.origin-actual_elbow).normalized()))
	_set_basis(skeleton,lower,lower_turn*old_lower.basis)
	var forearm_axis := (held.origin-actual_elbow).normalized()
	var lower_basis := skeleton.get_bone_global_pose(lower).basis
	var neutral_palm := (lower_basis*skeleton.get_bone_rest(hand).basis).z
	var desired_palm := held.basis.z
	neutral_palm = (neutral_palm-forearm_axis*neutral_palm.dot(forearm_axis)).normalized()
	desired_palm = (desired_palm-forearm_axis*desired_palm.dot(forearm_axis)).normalized()
	_set_basis(skeleton,lower,Basis(forearm_axis,neutral_palm.signed_angle_to(desired_palm,forearm_axis))*lower_basis)
	_set_basis(skeleton,hand,held.basis)

func _wrist_feasible(shoulder: Vector3, hand: Vector3, palm: Vector3, a: float, b: float) -> bool:
	var offset := hand-shoulder
	var distance := maxf(offset.length(),.0001)
	var axis := offset/distance
	var along := (a*a-b*b+distance*distance)/(2*distance)
	var radius := sqrt(maxf(0,a*a-along*along))
	var projected := palm-axis*palm.dot(axis)
	return (palm.dot(axis)*(distance-along)+radius*projected.length())/b>=cos(deg_to_rad(44.0))

func _move_shoulder(skeleton: Skeleton3D, side: String, target: Vector3, reach: float) -> void:
	var bone := skeleton.find_bone(side+"Shoulder")
	var start := skeleton.get_bone_global_pose(bone)
	var upper := skeleton.get_bone_global_pose(skeleton.find_bone(side+"UpperArm")).origin
	var radius := upper.distance_to(start.origin)
	var separation := target-start.origin
	var distance := maxf(separation.length(),.0001)
	var axis := separation/distance
	var along := clampf((radius*radius-reach*reach+distance*distance)/(2*distance),-radius,radius)
	var center := start.origin+axis*along
	var radial := upper-center
	radial -= axis*radial.dot(axis)
	if radial.length_squared()<.000001: radial = axis.cross(Vector3.UP)
	var goal := center+radial.normalized()*sqrt(maxf(0,radius*radius-along*along))
	var turn := Basis(Quaternion((upper-start.origin).normalized(),(goal-start.origin).normalized()))
	_set_basis(skeleton,bone,turn*start.basis)

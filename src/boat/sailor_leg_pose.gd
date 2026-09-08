extends RefCounted

const LENGTH_EPSILON := 0.00001
const DIRECTION_EPSILON_SQUARED := 0.0000000001


static func solve(
	skeleton: Skeleton3D,
	upper: int,
	lower: int,
	foot: int,
	target_skeleton: Vector3,
	pole_skeleton: Vector3
) -> void:
	if (
		not is_instance_valid(skeleton)
		or upper < 0
		or lower < 0
		or foot < 0
		or upper >= skeleton.get_bone_count()
		or lower >= skeleton.get_bone_count()
		or foot >= skeleton.get_bone_count()
	):
		return
	var upper_pose := skeleton.get_bone_global_pose(upper)
	var lower_pose := skeleton.get_bone_global_pose(lower)
	var foot_pose := skeleton.get_bone_global_pose(foot)
	var source_upper := lower_pose.origin - upper_pose.origin
	var source_lower := foot_pose.origin - lower_pose.origin
	var upper_length := source_upper.length()
	var lower_length := source_lower.length()
	if upper_length <= LENGTH_EPSILON or lower_length <= LENGTH_EPSILON:
		return

	var source_normal := source_upper.cross(source_lower)
	if source_normal.length_squared() <= DIRECTION_EPSILON_SQUARED:
		source_normal = _perpendicular(upper_pose.basis.x, source_upper.normalized())
	source_normal = source_normal.normalized()
	var hip_to_target := target_skeleton - upper_pose.origin
	var target_distance := hip_to_target.length()
	var target_axis := hip_to_target.normalized()
	if target_distance <= LENGTH_EPSILON:
		target_axis = (foot_pose.origin - upper_pose.origin).normalized()
		if target_axis.length_squared() <= DIRECTION_EPSILON_SQUARED:
			target_axis = source_upper.normalized()
	var solved_distance := clampf(
		target_distance,
		absf(upper_length - lower_length) + LENGTH_EPSILON,
		upper_length + lower_length - LENGTH_EPSILON
	)
	var circle_distance := (
		solved_distance * solved_distance
		+ upper_length * upper_length
		- lower_length * lower_length
	) / (2.0 * solved_distance)
	var circle_center := upper_pose.origin + target_axis * circle_distance
	var circle_radius := sqrt(maxf(
		upper_length * upper_length - circle_distance * circle_distance,
		0.0
	))
	var bend := pole_skeleton - circle_center
	bend -= target_axis * bend.dot(target_axis)
	if bend.length_squared() <= DIRECTION_EPSILON_SQUARED:
		# Retain the source knee side when the pole lies on the hip-to-ankle axis.
		bend = lower_pose.origin - circle_center
		bend -= target_axis * bend.dot(target_axis)
	if bend.length_squared() <= DIRECTION_EPSILON_SQUARED:
		bend = _perpendicular(source_normal.cross(target_axis), target_axis)
	bend = bend.normalized()
	var solved_knee := circle_center + bend * circle_radius
	var solved_foot := upper_pose.origin + target_axis * solved_distance
	var solved_upper := (solved_knee - upper_pose.origin).normalized()
	var solved_lower := (solved_foot - solved_knee).normalized()
	var solved_normal := bend.cross(target_axis).normalized()

	# Mapping complete bend frames preserves the imported roll around each bone.
	# A shortest-arc direction quaternion alone has no stable roll at 180 degrees.
	var upper_rotation := (
		_bend_frame(solved_upper, solved_normal)
		* _bend_frame(source_upper.normalized(), source_normal).transposed()
	)
	var lower_rotation := (
		_bend_frame(solved_lower, solved_normal)
		* _bend_frame(source_lower.normalized(), source_normal).transposed()
	)
	skeleton.set_bone_global_pose(upper, Transform3D(
		upper_rotation * upper_pose.basis,
		upper_pose.origin
	))
	skeleton.force_update_bone_child_transform(upper)
	# Keep the propagated child origin. Only joint rotations change, so authored
	# segment lengths and local attachment positions remain intact.
	var propagated_lower := skeleton.get_bone_global_pose(lower)
	skeleton.set_bone_global_pose(lower, Transform3D(
		lower_rotation * lower_pose.basis,
		propagated_lower.origin
	))
	skeleton.force_update_bone_child_transform(lower)


static func _bend_frame(direction: Vector3, plane_normal: Vector3) -> Basis:
	var normal := _perpendicular(plane_normal, direction).normalized()
	return Basis(normal, direction, normal.cross(direction)).orthonormalized()


static func _perpendicular(candidate: Vector3, axis: Vector3) -> Vector3:
	var perpendicular := candidate - axis * candidate.dot(axis)
	if perpendicular.length_squared() > DIRECTION_EPSILON_SQUARED:
		return perpendicular
	var reference := Vector3.UP
	if absf(axis.dot(reference)) > 0.8:
		reference = Vector3.RIGHT
	return reference - axis * reference.dot(axis)

class_name WindwardSailor
extends Node3D

const SAILOR_RIG := preload("res://src/boat/assets/sailor_rig_base.tscn")
const SITTING_IDLE := preload("res://src/boat/assets/sailor_sitting_idle.res")
const CROUCH_IDLE := preload("res://src/boat/assets/sailor_crouch_idle.res")

const BODY_HEIGHT_METERS := 1.75
const FIRST_PERSON_BODY_LAYER := 4
const EXTERIOR_RENDER_LAYER := 2
const SHARED_BODY_LAYERS := FIRST_PERSON_BODY_LAYER | EXTERIOR_RENDER_LAYER

# The imported seated animation places the hips 0.36 m behind the rig origin.
# These offsets put the pelvis on the side deck while the feet remain inboard.
const POSE_LATERAL_CENTER := 0.34
const POSE_AFT_CENTER := 0.22
const BODY_FORWARD_CORRECTION := PI
const BODY_SEAT_YAW := deg_to_rad(42.0)
const TACK_CROSSING_RATE := 1.65
const TACK_CENTER_RISE := 0.10
const SAILOR_PROCESS_PRIORITY := -10

# Hard anatomical neck limits. First-person horizontal look has a wider limit:
# large turns are shared between the spine and neck instead of breaking either.
const MIN_NECK_YAW := deg_to_rad(-68.0)
const MAX_NECK_YAW := deg_to_rad(68.0)
const MIN_NECK_PITCH := deg_to_rad(-50.0)
const MAX_NECK_PITCH := deg_to_rad(45.0)
const MIN_TOTAL_LOOK_YAW := deg_to_rad(-110.0)
const MAX_TOTAL_LOOK_YAW := deg_to_rad(110.0)
const MIN_TOTAL_LOOK_PITCH := deg_to_rad(-80.0)
const MAX_TOTAL_LOOK_PITCH := MAX_NECK_PITCH
const TORSO_TWIST_START_YAW := deg_to_rad(45.0)
const MAX_TORSO_TWIST_YAW := deg_to_rad(42.0)
const TORSO_FLEX_START_PITCH := deg_to_rad(-35.0)
const MAX_TORSO_FLEX_PITCH := deg_to_rad(30.0)

# Control-hand geometry. A Laser/ILCA sailor pushes and pulls the tiller
# extension through a visible fore/aft arc. During a tack both hands meet at
# the extension behind the sailor before their sheet/tiller roles exchange.
const TILLER_TARGET_LATERAL := 0.48
const TILLER_TARGET_HEIGHT := 0.61
const TILLER_TARGET_AFT := 0.48
const TILLER_PUSH_PULL_TRAVEL := 0.16
const HANDOVER_START_SIDE := 0.10
const HANDOVER_END_SIDE := 0.88
const HANDOVER_BEHIND_BODY := Vector3(-0.20, 0.90, -0.34)

const MAIN_SHEET_BLOCK_POSITION := Vector3(0.0, 0.16, 0.24)
const LEFT_HAND_TARGET := Vector3(0.24, 0.70, -0.14)
const RIGHT_HAND_TARGET := Vector3(-0.24, 0.70, -0.14)
const LEFT_ELBOW_POLE := Vector3(0.40, 0.78, -0.42)
const RIGHT_ELBOW_POLE := Vector3(-0.40, 0.78, -0.42)

# Continuous crossing state: -1 port, +1 starboard.
var seat_side := -1.0

var _boat: WindwardBoat
var _pose_root: Node3D
var _rig_root: Node3D
var _skeleton: Skeleton3D
var _animation_player: AnimationPlayer
var _eye_anchor: Node3D
var _left_hand_anchor: Node3D
var _right_hand_anchor: Node3D
var _left_foot_anchor: Node3D
var _right_foot_anchor: Node3D
var _sheet_hand_anchor: Node3D
var _tiller_hand_anchor: Node3D
var _rudder_pivot: Node3D
var _tiller_extension_pivot: Node3D
var _tiller_grip: Node3D
var _held_mainsheet: MeshInstance3D
var _left_hand_target: Node3D
var _right_hand_target: Node3D

var _spine_bone := -1
var _chest_bone := -1
var _neck_bone := -1
var _head_bone := -1
var _upper_chest_bone := -1
var _base_head_from_chest := Basis.IDENTITY
var _base_upper_chest_basis_in_pose := Basis.IDENTITY
var _stable_neutral_head_basis_in_pose := Basis.IDENTITY
var _animation_torso_rotations: Dictionary = {}
var _requested_look_yaw := 0.0
var _requested_look_pitch := 0.0
var _applied_torso_yaw := 0.0
var _applied_torso_pitch := 0.0
var _applied_neck_yaw := 0.0
var _applied_neck_pitch := 0.0
var _pose_animation := &"Seated"
var _tiller_is_left := false
var _last_hand_exchange_side := -1.0
var _hand_exchange_direction := 0.0
var _hand_exchange_amount := 0.0
var _finger_base_rotations: Dictionary = {}


func _enter_tree() -> void:
	# Evaluate the animation and anatomical anchors before the camera consumes
	# them. Lower process priorities run earlier in an idle frame.
	process_priority = SAILOR_PROCESS_PRIORITY


func _ready() -> void:
	_boat = get_parent() as WindwardBoat
	_rudder_pivot = _boat.get_node("RudderPivot") as Node3D
	_tiller_extension_pivot = _rudder_pivot.get_node("TillerExtensionPivot") as Node3D
	_tiller_grip = _tiller_extension_pivot.get_node("TillerGrip") as Node3D

	_pose_root = Node3D.new()
	_pose_root.name = "SailorPose"
	add_child(_pose_root)

	_rig_root = SAILOR_RIG.instantiate() as Node3D
	_rig_root.name = "SailorRig"
	_pose_root.add_child(_rig_root)
	_skeleton = _rig_root.get_node("Armature/GeneralSkeleton") as Skeleton3D
	_animation_player = _rig_root.get_node("AnimationPlayer") as AnimationPlayer
	_install_seated_pose()

	_spine_bone = _skeleton.find_bone("Spine")
	_chest_bone = _skeleton.find_bone("Chest")
	_neck_bone = _skeleton.find_bone("Neck")
	_head_bone = _skeleton.find_bone("Head")
	_upper_chest_bone = _skeleton.find_bone("UpperChest")

	_configure_render_layers()
	_configure_arm_ik()
	_create_anatomical_anchors()
	_capture_finger_base_pose()
	_create_sailing_clothing()
	_create_held_mainsheet()
	_apply_pose_side_transform()
	_animation_player.advance(0.0)
	_capture_animation_torso_pose()
	_capture_base_head_from_chest()
	_capture_stable_gaze_basis()
	_resolve_control_hands()
	_update_control_ik_targets()
	_apply_control_grip_pose()
	_update_held_mainsheet()
	set_head_look(0.0, deg_to_rad(-12.0))


func _process(delta: float) -> void:
	var boom_side := signf(_boat.get_sailing_state().boom_angle_radians)
	if is_zero_approx(boom_side):
		boom_side = 1.0
	seat_side = move_toward(seat_side, -boom_side, TACK_CROSSING_RATE * delta)
	_apply_pose_side_transform()
	# Manual playback makes the order deterministic: animation, procedural head,
	# anatomical anchors, then the later-priority camera.
	# Restore the previous pure animation sample before advancing. Spine has no
	# track in the imported idle clips, so without this step its procedural
	# twist/flex would become the next frame's animation base and accumulate.
	_restore_animation_torso_pose()
	_animation_player.advance(delta)
	_capture_animation_torso_pose()
	_apply_head_pose()
	_resolve_control_hands()
	_update_control_ik_targets()
	_apply_control_grip_pose()
	_update_held_mainsheet()


func _install_seated_pose() -> void:
	var library := AnimationLibrary.new()
	library.add_animation("Seated", SITTING_IDLE)
	library.add_animation("Crouch", CROUCH_IDLE)
	_animation_player.add_animation_library("sailor", library)
	# The camera owns the visible gaze. Imported clips still drive the spine and
	# limbs, but must not write over the procedural Neck/Head chain.
	_disable_gaze_tracks(SITTING_IDLE)
	_disable_gaze_tracks(CROUCH_IDLE)
	_animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_animation_player.play("sailor/Seated")
	_animation_player.seek(0.5, true)


func _disable_gaze_tracks(animation: Animation) -> void:
	for track_index in animation.get_track_count():
		var path_text := String(animation.track_get_path(track_index))
		if path_text.contains("Neck") or path_text.contains("Head"):
			animation.track_set_enabled(track_index, false)


func _capture_base_head_from_chest() -> void:
	var chest_basis := _skeleton.get_bone_global_pose(_upper_chest_bone).basis.orthonormalized()
	var head_basis := _skeleton.get_bone_global_pose(_head_bone).basis.orthonormalized()
	_base_head_from_chest = (chest_basis.inverse() * head_basis).orthonormalized()


func _capture_stable_gaze_basis() -> void:
	# Imported idle clips contain almost three degrees of looping Chest and
	# UpperChest sway. The sailor may breathe, but an unstimulated vestibular
	# view must not inherit that motion. Capture a level head reference in the
	# continuous tack pose and drive the rendered head toward it every frame.
	var upper_chest_world_basis := (
		_skeleton.global_basis
		* _skeleton.get_bone_global_pose(_upper_chest_bone).basis
	).orthonormalized()
	var pose_basis := _pose_root.global_basis.orthonormalized()
	_base_upper_chest_basis_in_pose = (
		pose_basis.inverse() * upper_chest_world_basis
	).orthonormalized()
	# Calibrate the imported model's neutral face tilt once. Afterwards a 0°
	# request is genuinely level in the sailor pose, not the clip's +14° bias.
	var neutral_head_in_pose := (
		_base_upper_chest_basis_in_pose * _base_head_from_chest
	).orthonormalized()
	var neutral_forward := neutral_head_in_pose.z.normalized()
	var neutral_pitch := atan2(
		neutral_forward.y,
		Vector2(neutral_forward.x, neutral_forward.z).length()
	)
	_base_head_from_chest = (
		_base_head_from_chest * Basis(Vector3.RIGHT, neutral_pitch)
	).orthonormalized()
	_stable_neutral_head_basis_in_pose = (
		_base_upper_chest_basis_in_pose * _base_head_from_chest
	).orthonormalized()


func _apply_pose_side_transform() -> void:
	var clamped_side := clampf(seat_side, -1.0, 1.0)
	var crossing_amount := 1.0 - absf(clamped_side)
	_pose_root.position = Vector3(
		clamped_side * POSE_LATERAL_CENTER,
		sin(crossing_amount * PI * 0.5) * TACK_CENTER_RISE,
		POSE_AFT_CENTER
	)
	_pose_root.rotation = Vector3(
		0.0,
		BODY_FORWARD_CORRECTION + BODY_SEAT_YAW * clamped_side,
		0.0
	)
	_pose_root.scale = Vector3.ONE
	_update_pose_animation(crossing_amount)


func _update_pose_animation(crossing_amount: float) -> void:
	var desired := &"Crouch" if crossing_amount > 0.14 else &"Seated"
	if desired == _pose_animation:
		return
	_pose_animation = desired
	# A half-second blend keeps the pelvis/eye velocity and body heading smooth
	# as the sailor ducks under the boom and settles on the opposite side.
	_animation_player.play("sailor/" + String(desired), 0.50, 0.72)


func set_head_look(yaw: float, pitch: float) -> Vector2:
	_requested_look_yaw = clampf(yaw, MIN_TOTAL_LOOK_YAW, MAX_TOTAL_LOOK_YAW)
	_requested_look_pitch = clampf(
		pitch,
		MIN_TOTAL_LOOK_PITCH,
		MAX_TOTAL_LOOK_PITCH
	)
	var yaw_sign := signf(_requested_look_yaw)
	var yaw_magnitude := absf(_requested_look_yaw)
	var torso_magnitude := clampf(
		(yaw_magnitude - TORSO_TWIST_START_YAW) * 0.74,
		0.0,
		MAX_TORSO_TWIST_YAW
	)
	# Reserve enough of an extreme look for the torso to keep the neck at its
	# real joint limit. At moderate angles the neck still leads naturally.
	torso_magnitude = maxf(torso_magnitude, yaw_magnitude - MAX_NECK_YAW)
	_applied_torso_yaw = yaw_sign * minf(torso_magnitude, MAX_TORSO_TWIST_YAW)
	_applied_neck_yaw = clampf(
		_requested_look_yaw - _applied_torso_yaw,
		MIN_NECK_YAW,
		MAX_NECK_YAW
	)
	var downward_magnitude := maxf(0.0, -_requested_look_pitch)
	var natural_flex := maxf(
		0.0,
		(downward_magnitude + TORSO_FLEX_START_PITCH) * 0.67
	)
	var required_flex := maxf(0.0, downward_magnitude + MIN_NECK_PITCH)
	_applied_torso_pitch = -minf(
		maxf(natural_flex, required_flex),
		MAX_TORSO_FLEX_PITCH
	)
	_applied_neck_pitch = clampf(
		_requested_look_pitch - _applied_torso_pitch,
		MIN_NECK_PITCH,
		MAX_NECK_PITCH
	)
	_apply_head_pose()
	return Vector2(_requested_look_yaw, _requested_look_pitch)


func _capture_animation_torso_pose() -> void:
	if not is_instance_valid(_skeleton):
		return
	for bone_index in [_spine_bone, _chest_bone, _upper_chest_bone]:
		if bone_index >= 0:
			_animation_torso_rotations[bone_index] = _skeleton.get_bone_pose_rotation(bone_index)


func _restore_animation_torso_pose() -> void:
	if not is_instance_valid(_skeleton):
		return
	for bone_index in [_spine_bone, _chest_bone, _upper_chest_bone]:
		if bone_index >= 0 and _animation_torso_rotations.has(bone_index):
			_skeleton.set_bone_pose_rotation(
				bone_index,
				_animation_torso_rotations[bone_index]
			)
	if _spine_bone >= 0:
		_skeleton.force_update_bone_child_transform(_spine_bone)


func _apply_torso_pose() -> void:
	if not is_instance_valid(_skeleton):
		return
	var torso_chain := [
		[_spine_bone, 0.24],
		[_chest_bone, 0.34],
		[_upper_chest_bone, 0.42],
	]
	# Restore the current animation sample first; camera synchronization can call
	# this more than once in one frame and must never accumulate extra twist.
	_restore_animation_torso_pose()

	for entry in torso_chain:
		var bone_index: int = entry[0]
		if bone_index < 0:
			continue
		var twist_share := _applied_torso_yaw * float(entry[1])
		var flex_share := _applied_torso_pitch * float(entry[1])
		var current_basis := _skeleton.get_bone_global_pose(bone_index).basis.orthonormalized()
		var desired_basis := (
			Basis(Vector3.UP, -twist_share)
			* Basis(current_basis.x.normalized(), -flex_share)
			* current_basis
		).orthonormalized()
		var parent_index := _skeleton.get_bone_parent(bone_index)
		var parent_basis := Basis.IDENTITY
		if parent_index >= 0:
			parent_basis = _skeleton.get_bone_global_pose(parent_index).basis.orthonormalized()
		var rest_basis := _skeleton.get_bone_rest(bone_index).basis.orthonormalized()
		var local_pose_basis := (
			(parent_basis * rest_basis).inverse() * desired_basis
		).orthonormalized()
		_skeleton.set_bone_pose_rotation(
			bone_index,
			local_pose_basis.get_rotation_quaternion()
		)
		_skeleton.force_update_bone_child_transform(bone_index)


func _apply_head_pose() -> void:
	if not is_instance_valid(_skeleton) or _head_bone < 0:
		return
	_apply_torso_pose()
	# Compose the final gaze once from the stable neutral head and the total
	# request. Sequential torso + neck multiplication changes pitch into roll at
	# combined extremes (for example yaw 110°, pitch -80° looked only -37° down).
	# Torso/neck shares still drive and bound the visible anatomy, but cannot
	# redefine the player's canonical spherical gaze direction.
	var total_yaw_delta := Quaternion(Vector3.UP, -_requested_look_yaw)
	var total_pitch_delta := Quaternion(Vector3.RIGHT, -_requested_look_pitch)
	var desired_head_world_basis := (
		_pose_root.global_basis.orthonormalized()
		* _stable_neutral_head_basis_in_pose
		* Basis((total_yaw_delta * total_pitch_delta).normalized())
	).orthonormalized()
	var desired_head_basis := (
		_skeleton.global_basis.inverse()
		* desired_head_world_basis
	).orthonormalized()
	var head_parent := _skeleton.get_bone_parent(_head_bone)
	var parent_basis := _skeleton.get_bone_global_pose(head_parent).basis.orthonormalized()
	var head_rest_basis := _skeleton.get_bone_rest(_head_bone).basis.orthonormalized()
	var local_pose_basis := (
		(parent_basis * head_rest_basis).inverse()
		* desired_head_basis
	).orthonormalized()
	_skeleton.set_bone_pose_rotation(_head_bone, local_pose_basis.get_rotation_quaternion())
	_skeleton.force_update_bone_child_transform(_head_bone)
	_update_eye_anchor()


func eye_global_position() -> Vector3:
	return _eye_anchor.global_position


func gaze_global_transform() -> Transform3D:
	var eye_transform := _eye_anchor.global_transform
	# EyeAnchor already carries the canonical orthonormal head basis. Returning
	# it directly avoids a near-vertical cross-product reconstruction and keeps
	# camera forward exactly atomic with the rendered Head bone.
	return Transform3D(eye_transform.basis.orthonormalized(), eye_transform.origin)


func gaze_forward() -> Vector3:
	return -gaze_global_transform().basis.z


func body_forward() -> Vector3:
	return _pose_root.global_basis.z.normalized()


func visible_head_forward() -> Vector3:
	var head_basis := _skeleton.get_bone_global_pose(_head_bone).basis.orthonormalized()
	return (_skeleton.global_basis * head_basis.z).normalized()


func applied_neck_yaw() -> float:
	return _applied_neck_yaw


func applied_torso_yaw() -> float:
	return _applied_torso_yaw


func applied_torso_pitch() -> float:
	return _applied_torso_pitch


func applied_total_look_yaw() -> float:
	return _requested_look_yaw


func applied_total_look_pitch() -> float:
	return _requested_look_pitch


func applied_neck_pitch() -> float:
	return _applied_neck_pitch


func actual_neck_angles() -> Vector2:
	if not is_instance_valid(_skeleton) or _head_bone < 0 or _upper_chest_bone < 0:
		return Vector2.ZERO
	# This is the synthetic neck-share contract used by camera/animation logic.
	# Physical UpperChest-to-Head integrity is tested separately from the raw
	# rendered bone quaternions so a corrupt chain cannot hide behind this value.
	var delta := Basis((
		Quaternion(Vector3.UP, -_applied_neck_yaw)
		* Quaternion(Vector3.RIGHT, -_applied_neck_pitch)
	).normalized())
	var forward := delta.z.normalized()
	return Vector2(
		atan2(-forward.x, forward.z),
		asin(clampf(forward.y, -1.0, 1.0))
	)


func skeleton_node() -> Skeleton3D:
	return _skeleton


func head_bone_index() -> int:
	return _head_bone


func mainsheet_hand_global_position() -> Vector3:
	_resolve_control_hands()
	return _sheet_hand_anchor.global_position


func tiller_hand_global_position() -> Vector3:
	_resolve_control_hands()
	return _tiller_hand_anchor.global_position


func tiller_hand_boat_position() -> Vector3:
	return _boat.to_local(tiller_hand_global_position())


func tiller_grip_global_position() -> Vector3:
	return _tiller_grip.global_position


func left_foot_global_position() -> Vector3:
	return _left_foot_anchor.global_position


func right_foot_global_position() -> Vector3:
	return _right_foot_anchor.global_position


func hands_are_swapped() -> bool:
	_resolve_control_hands()
	return _tiller_hand_anchor == _left_hand_anchor


func _configure_render_layers() -> void:
	var eyebrows := _skeleton.get_node("Eyebrows") as MeshInstance3D
	var eyes := _skeleton.get_node("Eyes") as MeshInstance3D
	var exterior_body := _skeleton.get_node("SuperHero_Male") as MeshInstance3D
	eyebrows.layers = EXTERIOR_RENDER_LAYER
	eyes.layers = EXTERIOR_RENDER_LAYER
	exterior_body.layers = EXTERIOR_RENDER_LAYER

	# A second skinned instance is used only by the first-person camera. Its
	# shader clips the head in animated model space, preventing the camera from
	# looking through face polygons while preserving the connected torso/limbs.
	var first_person_body := MeshInstance3D.new()
	first_person_body.name = "FirstPersonBody"
	first_person_body.mesh = exterior_body.mesh
	first_person_body.skin = exterior_body.skin
	first_person_body.skeleton = NodePath("..")
	first_person_body.layers = FIRST_PERSON_BODY_LAYER
	first_person_body.material_override = _create_headless_body_material(exterior_body)
	_skeleton.add_child(first_person_body)


func _create_headless_body_material(source_body: MeshInstance3D) -> ShaderMaterial:
	var source := source_body.mesh.surface_get_material(0) as StandardMaterial3D
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_texture : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float head_cut_height = 1.14;
varying float sailor_model_y;
varying vec3 sailor_world_position;

void vertex() {
	sailor_model_y = VERTEX.y;
	sailor_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (sailor_model_y > head_cut_height || distance(sailor_world_position, CAMERA_POSITION_WORLD) < 0.30) {
		discard;
	}
	ALBEDO = texture(albedo_texture, UV).rgb;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	ROUGHNESS = texture(roughness_texture, UV).r;
}
"""
	var result := ShaderMaterial.new()
	result.shader = shader
	if source:
		result.set_shader_parameter("albedo_texture", source.albedo_texture)
		result.set_shader_parameter("normal_texture", source.normal_texture)
		result.set_shader_parameter("roughness_texture", source.roughness_texture)
	return result


func _configure_arm_ik() -> void:
	_left_hand_target = _rig_root.get_node("L_Hand_target") as Node3D
	_right_hand_target = _rig_root.get_node("R_Hand_target") as Node3D
	var left_pole := _rig_root.get_node("L_Hand_pole") as Node3D
	var right_pole := _rig_root.get_node("R_Hand_pole") as Node3D
	_left_hand_target.position = LEFT_HAND_TARGET
	_right_hand_target.position = RIGHT_HAND_TARGET
	left_pole.position = LEFT_ELBOW_POLE
	right_pole.position = RIGHT_ELBOW_POLE
	(_skeleton.get_node("L_ArmIK3D") as Node).set("influence", 1.0)
	(_skeleton.get_node("R_ArmIK3D") as Node).set("influence", 1.0)
	(_skeleton.get_node("L_LegIK3D") as Node).set("influence", 0.0)
	(_skeleton.get_node("R_LegIK3D") as Node).set("influence", 0.0)


func _create_anatomical_anchors() -> void:
	_left_hand_anchor = _create_bone_anchor("LeftHandAnchor", "LeftHand")
	_right_hand_anchor = _create_bone_anchor("RightHandAnchor", "RightHand")
	# Hand bone origins are wrists. These mirrored offsets put the gameplay
	# contact at the centre of each palm, where a real tiller extension sits.
	_left_hand_anchor.position = Vector3(0.015, 0.046, 0.033)
	_right_hand_anchor.position = Vector3(-0.015, 0.046, 0.033)
	_left_foot_anchor = _create_bone_anchor("LeftFootAnchor", "LeftFoot")
	_right_foot_anchor = _create_bone_anchor("RightFootAnchor", "RightFoot")
	_eye_anchor = Node3D.new()
	_eye_anchor.name = "EyeAnchor"
	_skeleton.add_child(_eye_anchor)
	_update_eye_anchor()


func _capture_finger_base_pose() -> void:
	for side in ["Left", "Right"]:
		for digit in ["Index", "Middle", "Ring", "Little"]:
			for segment in ["Proximal", "Intermediate", "Distal"]:
				var bone_name: String = String(side) + String(digit) + String(segment)
				var bone_index := _skeleton.find_bone(bone_name)
				if bone_index >= 0:
					_finger_base_rotations[bone_name] = _skeleton.get_bone_pose_rotation(bone_index)
		for thumb_segment in ["Metacarpal", "Proximal", "Distal"]:
			var thumb_name: String = String(side) + "Thumb" + String(thumb_segment)
			var thumb_index := _skeleton.find_bone(thumb_name)
			if thumb_index >= 0:
				_finger_base_rotations[thumb_name] = _skeleton.get_bone_pose_rotation(thumb_index)


func _apply_control_grip_pose() -> void:
	# Curl only the hand that currently holds the extension; during the overlap
	# phase both anatomical hands close around adjacent sections of the grip.
	var left_grip := _tiller_is_left or _hand_exchange_amount > 0.05
	var right_grip := not _tiller_is_left or _hand_exchange_amount > 0.05
	_apply_hand_grip_pose("Left", left_grip)
	_apply_hand_grip_pose("Right", right_grip)


func _apply_hand_grip_pose(side: String, gripping: bool) -> void:
	var amount := 1.0 if gripping else 0.0
	var finger_angles := {
		"Proximal": deg_to_rad(54.0),
		"Intermediate": deg_to_rad(72.0),
		"Distal": deg_to_rad(38.0),
	}
	for digit in ["Index", "Middle", "Ring", "Little"]:
		for segment in ["Proximal", "Intermediate", "Distal"]:
			var bone_name: String = side + String(digit) + String(segment)
			_apply_finger_delta(bone_name, Vector3.RIGHT, float(finger_angles[segment]) * amount)
	_apply_finger_delta(side + "ThumbMetacarpal", Vector3.FORWARD, deg_to_rad(-25.0) * amount)
	_apply_finger_delta(side + "ThumbProximal", Vector3.RIGHT, deg_to_rad(32.0) * amount)
	_apply_finger_delta(side + "ThumbDistal", Vector3.RIGHT, deg_to_rad(24.0) * amount)


func _apply_finger_delta(bone_name: String, axis: Vector3, angle: float) -> void:
	var bone_index := _skeleton.find_bone(bone_name)
	if bone_index < 0 or not _finger_base_rotations.has(bone_name):
		return
	var base_rotation: Quaternion = _finger_base_rotations[bone_name]
	_skeleton.set_bone_pose_rotation(
		bone_index,
		(base_rotation * Quaternion(axis, angle)).normalized()
	)


func _update_eye_anchor() -> void:
	if not is_instance_valid(_eye_anchor) or _head_bone < 0:
		return
	# BoneAttachment3D refreshes on the next skeleton notification, which leaves
	# a one-frame camera/head mismatch after mouse input. Build the eye transform
	# directly from the current Head bone pose so camera and mesh are atomic.
	var head_pose := _skeleton.get_bone_global_pose(_head_bone)
	_eye_anchor.transform = head_pose * Transform3D(
		Basis(Vector3.UP, PI),
		Vector3(0.0, 0.115, 0.145)
	)


func _create_bone_anchor(anchor_name: String, bone_name: String) -> Node3D:
	var attachment := _create_bone_attachment(anchor_name + "Attachment", bone_name)
	var anchor := Node3D.new()
	anchor.name = anchor_name
	attachment.add_child(anchor)
	return anchor


func _create_bone_attachment(attachment_name: String, bone_name: String) -> BoneAttachment3D:
	var attachment := BoneAttachment3D.new()
	attachment.name = attachment_name
	attachment.bone_name = StringName(bone_name)
	_skeleton.add_child(attachment)
	return attachment


func _create_sailing_clothing() -> void:
	# The buoyancy aid is an original, unbranded interpretation of the Zhik P3
	# race-cut construction: a close-fitting tapered shell, broad arm/neck
	# openings, bevelled foam panels, side entry and one low-profile cargo pocket.
	# Keeping those functional cues in separate named parts also gives visual QA
	# a stable contract without copying the manufacturer's logo artwork.
	var vest_material := StandardMaterial3D.new()
	vest_material.albedo_color = Color(0.180, 0.215, 0.235)
	vest_material.metallic = 0.0
	vest_material.roughness = 0.88
	vest_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pocket_material := StandardMaterial3D.new()
	pocket_material.albedo_color = Color(0.060, 0.075, 0.086)
	pocket_material.metallic = 0.0
	pocket_material.roughness = 0.92
	pocket_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var side_material := StandardMaterial3D.new()
	side_material.albedo_color = Color(0.025, 0.034, 0.041)
	side_material.metallic = 0.0
	side_material.roughness = 0.94
	side_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var strap_material := StandardMaterial3D.new()
	strap_material.albedo_color = Color(0.012, 0.017, 0.021)
	strap_material.roughness = 0.96
	var cap_material := StandardMaterial3D.new()
	cap_material.albedo_color = Color(0.025, 0.08, 0.11)
	cap_material.roughness = 0.76

	var chest := _create_bone_attachment("BuoyancyAidAttachment", "UpperChest")
	_make_extruded_panel(
		"PfdFrontLower",
		PackedVector2Array([
			Vector2(-0.135, -0.195), Vector2(0.135, -0.195),
			Vector2(0.174, -0.158), Vector2(0.185, -0.020),
			Vector2(0.152, 0.095), Vector2(0.085, 0.122),
			Vector2(-0.085, 0.122), Vector2(-0.152, 0.095),
			Vector2(-0.185, -0.020), Vector2(-0.174, -0.158),
		]),
		0.120,
		0.022,
		chest,
		vest_material,
		SHARED_BODY_LAYERS
	)
	_make_extruded_panel(
		"PfdFrontLeftShoulder",
		PackedVector2Array([
			Vector2(0.018, 0.080), Vector2(0.145, 0.075),
			Vector2(0.176, 0.112), Vector2(0.140, 0.190),
			Vector2(0.082, 0.205), Vector2(0.043, 0.142),
		]),
		0.115,
		0.022,
		chest,
		vest_material,
		SHARED_BODY_LAYERS
	)
	_make_extruded_panel(
		"PfdFrontRightShoulder",
		PackedVector2Array([
			Vector2(-0.145, 0.075), Vector2(-0.018, 0.080),
			Vector2(-0.043, 0.142), Vector2(-0.082, 0.205),
			Vector2(-0.140, 0.190), Vector2(-0.176, 0.112),
		]),
		0.115,
		0.022,
		chest,
		vest_material,
		SHARED_BODY_LAYERS
	)
	_make_extruded_panel(
		"PfdBackPanel",
		PackedVector2Array([
			Vector2(-0.120, -0.190), Vector2(0.120, -0.190),
			Vector2(0.172, -0.135), Vector2(0.180, -0.055),
			Vector2(0.145, 0.105), Vector2(0.090, 0.172),
			Vector2(-0.090, 0.172), Vector2(-0.145, 0.105),
			Vector2(-0.180, -0.055), Vector2(-0.172, -0.135),
		]),
		-0.112,
		0.022,
		chest,
		vest_material,
		SHARED_BODY_LAYERS
	)
	# Flexible dark side gussets and shoulder bridges join the foam into one
	# garment while leaving the armholes visibly open.
	_make_box("PfdLeftSideGusset", Vector3(0.180, -0.055, 0.0), Vector3(0.018, 0.200, 0.220), chest, side_material, SHARED_BODY_LAYERS)
	_make_box("PfdRightSideGusset", Vector3(-0.180, -0.055, 0.0), Vector3(0.018, 0.200, 0.220), chest, side_material, SHARED_BODY_LAYERS)
	_make_box("PfdLeftNeopreneShoulder", Vector3(0.106, 0.180, 0.0), Vector3(0.050, 0.055, 0.210), chest, side_material, SHARED_BODY_LAYERS)
	_make_box("PfdRightNeopreneShoulder", Vector3(-0.106, 0.180, 0.0), Vector3(0.050, 0.055, 0.210), chest, side_material, SHARED_BODY_LAYERS)

	# The large laser-drained cargo pocket is intentionally plain and carries no
	# third-party wordmark. Its shallow projection preserves the P3-like clean
	# silhouette rather than becoming another flotation pad.
	_make_extruded_panel(
		"PfdFrontPocket",
		PackedVector2Array([
			Vector2(-0.140, -0.145), Vector2(0.140, -0.145),
			Vector2(0.148, -0.115), Vector2(0.140, -0.025),
			Vector2(-0.140, -0.025), Vector2(-0.148, -0.115),
		]),
		0.135,
		0.007,
		chest,
		pocket_material,
		SHARED_BODY_LAYERS
	)
	_make_box("PfdPocketFlap", Vector3(0.0, -0.023, 0.141), Vector3(0.275, 0.008, 0.005), chest, strap_material, SHARED_BODY_LAYERS)
	_make_box("PfdConcealedWaist", Vector3(0.0, -0.172, 0.135), Vector3(0.285, 0.016, 0.006), chest, strap_material, SHARED_BODY_LAYERS)
	# Side-entry zipper: deliberately offset instead of the unrealistic central
	# zipper used by the placeholder vest.
	_make_box("PfdSideZipper", Vector3(-0.184, -0.035, 0.112), Vector3(0.008, 0.180, 0.007), chest, strap_material, SHARED_BODY_LAYERS)

	var head := _create_bone_attachment("SailingCapAttachment", "Head")
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 0.12
	crown_mesh.height = 0.22
	crown_mesh.radial_segments = 24
	crown_mesh.rings = 12
	var crown := MeshInstance3D.new()
	crown.name = "SailingCap"
	crown.mesh = crown_mesh
	crown.position = Vector3(0.0, 0.16, 0.0)
	crown.scale = Vector3(1.0, 0.55, 1.0)
	crown.material_override = cap_material
	crown.layers = EXTERIOR_RENDER_LAYER
	head.add_child(crown)
	_make_box("CapVisor", Vector3(0.0, 0.16, 0.105), Vector3(0.17, 0.016, 0.09), head, cap_material, EXTERIOR_RENDER_LAYER)


func _make_extruded_panel(
	part_name: String,
	profile: PackedVector2Array,
	center_z: float,
	depth: float,
	parent: Node3D,
	material: Material,
	layers: int
) -> MeshInstance3D:
	# All PFD profiles are convex and counter-clockwise. A recessed outer ring
	# creates the bevel instead of relying on rounded primitive capsules.
	var profile_center := Vector2.ZERO
	for point in profile:
		profile_center += point
	profile_center /= float(profile.size())
	var inner := PackedVector2Array()
	for point in profile:
		inner.append(profile_center + (point - profile_center) * 0.92)

	var half_depth := depth * 0.5
	var bevel_depth := minf(depth * 0.28, 0.010)
	var front_z := center_z + half_depth
	var front_outer_z := front_z - bevel_depth
	var back_z := center_z - half_depth
	var back_outer_z := back_z + bevel_depth
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Flat front and rear faces.
	for index in range(1, profile.size() - 1):
		_add_panel_triangle(surface, inner[0], front_z, inner[index], front_z, inner[index + 1], front_z)
		_add_panel_triangle(surface, inner[0], back_z, inner[index + 1], back_z, inner[index], back_z)

	# Chamfer rings and the narrow outside wall.
	for index in profile.size():
		var next := (index + 1) % profile.size()
		_add_panel_quad(surface, inner[index], front_z, profile[index], front_outer_z, profile[next], front_outer_z, inner[next], front_z)
		_add_panel_quad(surface, profile[index], front_outer_z, profile[index], back_outer_z, profile[next], back_outer_z, profile[next], front_outer_z)
		_add_panel_quad(surface, inner[next], back_z, profile[next], back_outer_z, profile[index], back_outer_z, inner[index], back_z)

	surface.generate_normals()
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = surface.commit()
	part.material_override = material
	part.layers = layers
	parent.add_child(part)
	return part


func _add_panel_triangle(
	surface: SurfaceTool,
	a: Vector2,
	a_z: float,
	b: Vector2,
	b_z: float,
	c: Vector2,
	c_z: float
) -> void:
	surface.set_uv(Vector2(a.x, a.y))
	surface.add_vertex(Vector3(a.x, a.y, a_z))
	surface.set_uv(Vector2(b.x, b.y))
	surface.add_vertex(Vector3(b.x, b.y, b_z))
	surface.set_uv(Vector2(c.x, c.y))
	surface.add_vertex(Vector3(c.x, c.y, c_z))


func _add_panel_quad(
	surface: SurfaceTool,
	a: Vector2,
	a_z: float,
	b: Vector2,
	b_z: float,
	c: Vector2,
	c_z: float,
	d: Vector2,
	d_z: float
) -> void:
	_add_panel_triangle(surface, a, a_z, b, b_z, c, c_z)
	_add_panel_triangle(surface, a, a_z, c, c_z, d, d_z)


func _make_box(
	part_name: String,
	part_position: Vector3,
	size: Vector3,
	parent: Node3D,
	material: Material,
	layers: int
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.position = part_position
	part.material_override = material
	part.layers = layers
	parent.add_child(part)
	return part


func _resolve_control_hands() -> void:
	_update_hand_exchange_state()
	# Anatomical hands remain continuous. Their control roles switch only while
	# both hands overlap on the extension at the behind-the-back handover point.
	if _tiller_is_left:
		_tiller_hand_anchor = _left_hand_anchor
		_sheet_hand_anchor = _right_hand_anchor
	else:
		_tiller_hand_anchor = _right_hand_anchor
		_sheet_hand_anchor = _left_hand_anchor


func _update_hand_exchange_state() -> void:
	var side_delta := seat_side - _last_hand_exchange_side
	if absf(side_delta) > 0.0001:
		_hand_exchange_direction = signf(side_delta)
	_last_hand_exchange_side = seat_side

	var exchange_progress := 0.0
	if _hand_exchange_direction > 0.0:
		exchange_progress = smoothstep(HANDOVER_START_SIDE, HANDOVER_END_SIDE, seat_side)
	elif _hand_exchange_direction < 0.0:
		exchange_progress = smoothstep(HANDOVER_START_SIDE, HANDOVER_END_SIDE, -seat_side)

	_hand_exchange_amount = sin(exchange_progress * PI)
	if exchange_progress >= 0.5:
		_tiller_is_left = _hand_exchange_direction > 0.0
	elif absf(seat_side) >= HANDOVER_END_SIDE and is_zero_approx(_hand_exchange_amount):
		_tiller_is_left = seat_side > 0.0


func tiller_control_target_boat_position(rudder_input: float) -> Vector3:
	_update_hand_exchange_state()
	var side := clampf(seat_side, -1.0, 1.0)
	var steering_side := signf(side)
	if is_zero_approx(steering_side):
		steering_side = 1.0 if _hand_exchange_direction > 0.0 else -1.0
	var target_lateral := (
		side * TILLER_TARGET_LATERAL
		+ minf(rudder_input, 0.0) * 0.08
		- maxf(rudder_input, 0.0) * 0.20
	)
	var target_height := TILLER_TARGET_HEIGHT + maxf(rudder_input, 0.0) * 0.20
	var normal_target := Vector3(
		target_lateral,
		target_height,
		TILLER_TARGET_AFT + rudder_input * steering_side * TILLER_PUSH_PULL_TRAVEL
	)
	var handover_side := _hand_exchange_direction
	if is_zero_approx(handover_side):
		handover_side = steering_side
	var mirrored_handover := Vector3(
		HANDOVER_BEHIND_BODY.x * handover_side,
		HANDOVER_BEHIND_BODY.y,
		HANDOVER_BEHIND_BODY.z
	)
	var behind_back_target := _boat.to_local(
		_pose_root.to_global(mirrored_handover)
	)
	return normal_target.lerp(behind_back_target, _hand_exchange_amount)


func _update_control_ik_targets() -> void:
	if not is_instance_valid(_left_hand_target) or not is_instance_valid(_right_hand_target):
		return
	_resolve_control_hands()
	var grip_position := _tiller_grip.global_position
	var left_default := _rig_root.to_global(LEFT_HAND_TARGET)
	var right_default := _rig_root.to_global(RIGHT_HAND_TARGET)
	var left_goal := grip_position if _tiller_is_left else left_default
	var right_goal := right_default if _tiller_is_left else grip_position
	# The incoming sheet hand reaches the same physical extension before the role
	# flag changes. At the midpoint both targets are coincident, so neither arm
	# teleports when the new hand assumes the tiller.
	left_goal = left_goal.lerp(grip_position, _hand_exchange_amount)
	right_goal = right_goal.lerp(grip_position, _hand_exchange_amount)
	if _hand_exchange_amount > 0.95:
		# Two hands cannot occupy an identical palm centre. Offset them a few
		# centimetres along the extension, exactly as a real behind-the-back
		# handover overlaps adjacent grips before the old hand releases.
		var grip_axis := -_tiller_extension_pivot.global_basis.z.normalized()
		left_goal += grip_axis * 0.026
		right_goal -= grip_axis * 0.026
	_left_hand_target.global_position = left_goal
	_right_hand_target.global_position = right_goal


func hand_exchange_amount() -> float:
	return _hand_exchange_amount


func _create_held_mainsheet() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.005
	mesh.bottom_radius = 0.005
	mesh.height = 0.2
	mesh.radial_segments = 10
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.86, 0.77, 0.55)
	material.roughness = 0.72
	_held_mainsheet = MeshInstance3D.new()
	_held_mainsheet.name = "HeldMainsheet"
	_held_mainsheet.mesh = mesh
	_held_mainsheet.material_override = material
	_held_mainsheet.layers = 1
	add_child(_held_mainsheet)


func _update_held_mainsheet() -> void:
	if not _sheet_hand_anchor:
		return
	var from := MAIN_SHEET_BLOCK_POSITION
	var to := to_local(_sheet_hand_anchor.global_position)
	_orient_cylinder(_held_mainsheet, from, to)


func _orient_cylinder(part: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.0001:
		return
	var mesh := part.mesh as CylinderMesh
	mesh.height = length
	var axis := (to - from) / length
	var reference := Vector3.FORWARD
	if absf(axis.dot(reference)) > 0.94:
		reference = Vector3.RIGHT
	var x_axis := axis.cross(reference).normalized()
	var z_axis := x_axis.cross(axis).normalized()
	part.position = (from + to) * 0.5
	part.basis = Basis(x_axis, axis, z_axis)

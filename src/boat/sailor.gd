class_name WindwardSailor
extends Node3D

const SAILOR_RIG := preload("res://src/boat/assets/sailor_rig_base.tscn")
const SITTING_IDLE := preload("res://src/boat/assets/sailor_sitting_idle.res")
const CROUCH_IDLE := preload("res://src/boat/assets/sailor_crouch_idle.res")
const SAILOR_CONTACT_MODIFIER := preload("res://src/boat/sailor_contact_modifier.gd")
const LEG_POSE := preload("res://src/boat/sailor_leg_pose.gd")
const CONTROL_POSE := preload("res://src/boat/sailor_control_pose.gd")

const BODY_HEIGHT_METERS := 1.75
const SOURCE_BODY_HEIGHT_METERS := 1.819586
const BODY_UNIFORM_SCALE := BODY_HEIGHT_METERS / SOURCE_BODY_HEIGHT_METERS
const FIRST_PERSON_BODY_LAYER := 4
const EXTERIOR_RENDER_LAYER := 2
const SHARED_BODY_LAYERS := FIRST_PERSON_BODY_LAYER | EXTERIOR_RENDER_LAYER

# Temporary presentation switches. The generated gear remains intact so each
# item can be restored independently after the underlying sailor fit is fixed.
const SHOW_SAILING_CAP := false
const SHOW_PFD := false
const SHOW_SAILING_SHOES := false

enum PfdColorPreset {
	BLACK,
	BLUE,
	GREY,
	RED,
}

enum SheetMotionPhase {
	IDLE,
	HOLD,
	PULL,
	ASSIST_OVERLAP,
	PRIMARY_RELEASE_REACH,
	REGRIP,
	ASSIST_RELEASE,
	EASE,
}

@export_enum("Black", "Blue", "Grey", "Red") var pfd_color_preset: int = PfdColorPreset.BLUE

# The imported clip is a generic chair pose. Retarget its anatomical seat
# contact to the ILCA side deck instead of placing the whole rig by an eye or
# camera offset.
const SEAT_CONTACT_LATERAL := 0.56
const SEAT_CONTACT_AFT := 0.62
const SEAT_CONTACT_BELOW_HIPS := 0.10
const BODY_FORWARD_CORRECTION := PI
# The settled pelvis and chest face directly inboard: transverse to the boat's
# forward axis, as in the standard ILCA hiking posture. Gaze-driven torso twist
# still opens toward the bow when the sailor actually looks or works there.
const BODY_SEAT_YAW := deg_to_rad(90.0)
const NEUTRAL_UPPER_TORSO_YAW := 0.0
const TACK_CROSSING_RATE := 1.65
const TACK_MAX_SEAT_STEP := 0.008
const TACK_ENTRY_MAX_SEAT_STEP := 0.004
const TACK_CENTRAL_MAX_SEAT_STEP := 0.005
const TACK_ENTRY_RELEASE_PROGRESS := 0.001
const TACK_ENTRY_CROUCH_SETTLE_TIME := 0.52
const TACK_ENTRY_CROUCH_MAX_STEP := 1.0 / 120.0
const TACK_SEATED_RETURN_SETTLE_TIME := 0.52
const TACK_SEATED_RETURN_MAX_STEP := 1.0 / 120.0
const TACK_EXIT_CROSSING_RATE := 0.60
# The exit pair has only a few millimetres of verified capsule clearance in the
# centre of a tack.  Let the controller re-solve after each small body move
# instead of allowing one low-FPS render delta to move the torso through that
# clearance before the fixed shaft can follow.
const TACK_EXIT_MAX_SEAT_STEP := 0.003
const TACK_CENTER_RISE := 0.10
const MANEUVER_CROUCH_SECONDS := 0.20
const MANEUVER_CROSS_SECONDS := 0.62
const MANEUVER_PIVOT_SECONDS := 0.54
const MANEUVER_SIT_SECONDS := 0.24
const MANEUVER_DURATION := MANEUVER_CROUCH_SECONDS + MANEUVER_CROSS_SECONDS + MANEUVER_PIVOT_SECONDS + MANEUVER_SIT_SECONDS
# Each interval checks its midpoint as well as its endpoint: at most 1/60 s
# between collision samples without rebuilding the entire rig four times at 120 Hz.
const MANEUVER_SUBSTEP := 1.0 / 30.0
const MANEUVER_MIN_SUBSTEP := 1.0 / 240.0
const MANEUVER_FORWARD_SHIFT := 0.24
const MANEUVER_CONTROL_LATERAL := 0.15
const MANEUVER_CONTROL_HEIGHT := 0.80
const MANEUVER_CONTROL_AFT := 0.74
const SAILOR_PROCESS_PRIORITY := -10

# A single Skeleton3D-X rotation preserves every Spine descendant's segment
# length. Distributing the same correction through three joints shortened the
# seated Hips-to-Eye chain from an adult 0.69 m to 0.62 m.
const NEUTRAL_SPINE_PITCH := deg_to_rad(-15.0)

# The padded hiking strap spans x +/-0.060 m and z 0.335..1.235 m. Both ankles
# stay on the seated sailor's side of centreline while each foot extends
# inboard under the strap. The stagger is centred on the pelvis at z=0.62 m.
const FOOT_TARGET_OUTBOARD_X := 0.105
const FOOT_TARGET_FORWARD_Z := 0.50
const FOOT_TARGET_AFT_Z := 0.74
const FOOT_ANKLE_HEIGHT := 0.120
const FOOT_POLE_OUTBOARD_X := 0.30
const FOOT_POLE_HEIGHT := 0.37
const FOOT_RENDERED_LENGTH := 0.22
const FOOT_INSTEP_FRACTION := 0.45
const FOOT_TIP_HEIGHT := 0.045
const SHOULDER_CAPSULE_RADIUS := 0.131
const CALF_CAPSULE_RADIUS := 0.060

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
# Keep both controls below the first-person sightline and in distinct guard
# lanes: the sheet hand stays forward while the tiller hand stays aft.
const SHEET_TARGET_LATERAL := 0.30
const SHEET_TARGET_HEIGHT := 0.68
const SHEET_TARGET_AFT := 0.50
const CONTROL_ARM_SCALE := 1.11
const CONTROL_ELBOW_POLE_DISTANCE := 0.45
const CONTROL_ELBOW_SEARCH_STEPS := 48
const CONTROL_FOREARM_RADIUS := 0.025
const CONTROL_ELBOW_SAFETY_BUFFER := 0.005
# Begin transporting the commanded elbow branch before either its clearance or
# the measured rendered clearance exhausts the hard five-millimetre tier.
const CONTROL_ELBOW_TRANSPORT_MARGIN := 0.020
const CONTROL_ELBOW_TRANSPORT_RELEASE_MARGIN := 0.025
const CONTROL_ELBOW_TRANSPORT_RELEASE_GENERATIONS := 2
const CONTROL_ELBOW_TRANSPORT_RELEASE_ANGLE := deg_to_rad(1.0)
const CONTROL_ELBOW_HEIGHT_RATIO := 0.18
const CONTROL_ELBOW_SETTLED_SHOULDER_DROP := 0.04
const CONTROL_ELBOW_SETTLED_HEIGHT_ALLOWANCE := 0.08
const CONTROL_ELBOW_HEIGHT_LATCH_RELEASE_MARGIN := 0.025
const CONTROL_ELBOW_HEIGHT_RELAX_MAX_POLE_STEP := 0.0025
const CONTROL_ELBOW_REST_WEIGHT := 0.005
const CONTROL_ELBOW_CONTINUITY_WEIGHT := 0.035
const CONTROL_ELBOW_MAX_ANGULAR_SPEED := deg_to_rad(180.0)
const CONTROL_ELBOW_MAX_FRAME_ROTATION := deg_to_rad(6.0)
const CONTROL_ELBOW_INCIDENCE_RELEASE_MARGIN := -0.003
const CONTROL_HAND_MAX_FRAME_ROTATION := deg_to_rad(4.0)
const CONTROL_HAND_TRANSPORT_MAX_FRAME_ROTATION := deg_to_rad(1.0)
const CONTROL_WRIST_REACH_MIN := 0.20
const CONTROL_WRIST_REACH_MAX := 0.50
const CONTROL_WRIST_REACH_GUARD := 0.010
# Keep the flexible sheet hand farther inside the annulus than the rigid tiller
# preview. At the former exact 210 mm floor, the hand-basis limiter and elbow
# circle could settle into an equal-and-opposite two-frame cycle while the rope
# target remained otherwise static.
const CONTROL_SHEET_WRIST_REACH_GUARD := 0.020
# The semantic sheet target already advances at a 20 mm modifier cadence. Carry
# the last safe wrist by that authored motion, but do not let the continuity
# reference itself jump farther before it is projected back onto the complete
# shoulder-annulus/body-clearance feasible set.
const CONTROL_SHEET_WRIST_PROJECTION_MAX_REFERENCE_STEP := 0.020
const CONTROL_SHEET_WRIST_PROJECTION_RELAX_STEP := 0.006
const CONTROL_SHEET_WRIST_PROJECTION_OUTLIER_STEP := 0.040
const CONTROL_SHEET_ENTRY_READY_DISTANCE := 0.002
const CONTROL_SHEET_ENTRY_READY_GENERATIONS := 2
const CONTROL_SHEET_PROJECTION_DEFECT_EPSILON := 0.00005
const CONTROL_SHEET_PROJECTION_HANDOFF_WEIGHT := 0.05
const CONTROL_TILLER_CONTACT_WEIGHT_EPSILON := 0.001
const CONTROL_ELBOW_RELAXED_FLARE := -0.015
const CONTROL_ELBOW_MAX_INWARD_FLARE := 0.055
const CONTROL_ELBOW_MAX_OUTWARD_FLARE := 0.05
const CONTROL_ELBOW_FLARE_PENALTY := 1.5
const CONTROL_TILLER_FOREARM_SHAFT_MAX_DOT := 0.50
const CONTROL_TILLER_FOREARM_SHAFT_PENALTY := 0.80
const TILLER_NORMAL_GRIP_DIRECTION := Vector3(0.406, 0.608, -0.682)
const HANDOVER_START_SIDE := 0.10
const HANDOVER_END_SIDE := 0.88
const CROUCH_ANIMATION_ENTRY_AMOUNT := 0.14
const SEATED_ANIMATION_RETURN_SIDE := 0.99
const HANDOVER_CLEARANCE_LATERAL := 0.26
const HANDOVER_CLEARANCE_HEIGHT := 0.73
const HANDOVER_CLEARANCE_AFT := 0.90
const HANDOVER_BEHIND_LATERAL := 0.0
const HANDOVER_BEHIND_HEIGHT := 0.73
const HANDOVER_BEHIND_AFT := 0.90
const HANDOVER_INCOMING_ACQUIRE_START := 0.28
const HANDOVER_INCOMING_ACQUIRE_END := 0.46
const HANDOVER_OUTGOING_RELEASE_START := 0.54
const HANDOVER_OUTGOING_RELEASE_END := 0.68

const MAIN_SHEET_BLOCK_POSITION := Vector3(0.0, 0.16, 0.24)
const SHEET_REACH_LATERAL := 0.20
const SHEET_REACH_HEIGHT := 0.60
const SHEET_REACH_AFT := 0.40
const SHEET_MOTION_RESPONSE := 8.0
const SHEET_PULL_DURATION := 0.55
const SHEET_ASSIST_ACQUIRE_DURATION := 0.10
const SHEET_PRIMARY_REACH_DURATION := 0.42
const SHEET_REGRIP_DURATION := 0.10
const SHEET_ASSIST_RELEASE_DURATION := 0.18
const SHEET_TRANSFER_LATERAL := 0.23
const SHEET_TRANSFER_HEIGHT := 0.63
const SHEET_TRANSFER_AFT := 0.65
const SHEET_EASE_GRIP := 0.52
const SHEET_RELEASED_GRIP := 0.12
const HELD_SHEET_RADIUS := 0.005
const HELD_SHEET_SIDES := 8
const HELD_SHEET_CURVE_STEPS := 18
const HELD_SHEET_BODY_GAP := 0.005
const HELD_SHEET_ROUTE_POINT_MAX_STEP := 0.020
const HELD_SHEET_LOADED_SAG := 0.010
const HELD_SHEET_TAIL_SAG_MAX := 0.100
const HELD_SHEET_TAIL_SAG_SPAN_RATIO := 0.30
const CONTROL_SHEET_TARGET_MAX_STEP := 0.020

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
var _left_sheet_grip_anchor: Node3D
var _right_sheet_grip_anchor: Node3D
var _left_foot_anchor: Node3D
var _right_foot_anchor: Node3D
var _left_toe_anchor: Node3D
var _right_toe_anchor: Node3D
var _left_foot_visual: MeshInstance3D
var _right_foot_visual: MeshInstance3D
var _foot_visuals_ready := false
var _seat_contact_anchor: Node3D
var _left_instep_anchor: Node3D
var _right_instep_anchor: Node3D
var _left_sole_anchor: Node3D
var _right_sole_anchor: Node3D
var _sheet_hand_anchor: Node3D
var _sheet_grip_anchor: Node3D
var _tiller_hand_anchor: Node3D
var _rudder_pivot: Node3D
var _tiller_extension_pivot: Node3D
var _tiller_grip: Node3D
var _held_mainsheet: MeshInstance3D
var _held_mainsheet_material: StandardMaterial3D
var _held_mainsheet_route_boat := PackedVector3Array()
var _held_mainsheet_route_candidate_index := -1
var _held_mainsheet_route_generation := -1
var _held_mainsheet_loaded_leg := PackedVector3Array()
var _held_mainsheet_tail_leg := PackedVector3Array()
var _left_hand_target: Node3D
var _right_hand_target: Node3D
var _left_hand_pole: Node3D
var _right_hand_pole: Node3D
var _left_foot_target: Node3D
var _right_foot_target: Node3D
var _left_foot_pole: Node3D
var _right_foot_pole: Node3D
var _left_leg_ik: SkeletonModifier3D
var _right_leg_ik: SkeletonModifier3D
var _left_arm_ik: SkeletonModifier3D
var _right_arm_ik: SkeletonModifier3D
var _contact_modifier: SkeletonModifier3D

var _hips_bone := -1
var _spine_bone := -1
var _chest_bone := -1
var _neck_bone := -1
var _head_bone := -1
var _upper_chest_bone := -1
var _left_upper_leg_bone := -1
var _left_lower_leg_bone := -1
var _right_upper_leg_bone := -1
var _right_lower_leg_bone := -1
var _left_foot_bone := -1
var _right_foot_bone := -1
var _left_foot_tip_bone := -1
var _right_foot_tip_bone := -1
var _left_lower_arm_bone := -1
var _right_lower_arm_bone := -1
var _left_upper_arm_bone := -1
var _right_upper_arm_bone := -1
var _left_hand_bone := -1
var _right_hand_bone := -1
var _left_desired_hand_basis := Basis.IDENTITY
var _right_desired_hand_basis := Basis.IDENTITY
var _left_hand_basis_override := false
var _right_hand_basis_override := false
var _left_elbow_bend_boat := Vector3.ZERO
var _right_elbow_bend_boat := Vector3.ZERO
var _left_expected_elbow_boat := Vector3.ZERO
var _right_expected_elbow_boat := Vector3.ZERO
var _left_elbow_transport_active := false
var _right_elbow_transport_active := false
var _left_elbow_transport_target_boat := Vector3.ZERO
var _right_elbow_transport_target_boat := Vector3.ZERO
var _left_elbow_transport_release_generations := 0
var _right_elbow_transport_release_generations := 0
var _left_elbow_height_relaxed := false
var _right_elbow_height_relaxed := false
var _base_head_from_chest := Basis.IDENTITY
var _base_upper_chest_basis_in_pose := Basis.IDENTITY
var _stable_neutral_head_basis_in_pose := Basis.IDENTITY
var _current_neutral_head_from_chest := Basis.IDENTITY
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
var _maneuver_active := false
var _maneuver_elapsed := 0.0
var _maneuver_start_side := -1.0
var _maneuver_target_side := -1.0
var _maneuver_kind: StringName = &"tack"
var _maneuver_phase: StringName = &"seated"
var _maneuver_crossing := 0.0
var _maneuver_duck := 0.0
var _maneuver_heading := 0.0
var _maneuver_wait_seconds := 0.0
var _animation_leg_rotations: Dictionary = {}
var _animation_arm_rotations: Dictionary = {}
var _hand_exchange_direction := 0.0
var _hand_exchange_amount := 0.0
var _hand_exchange_progress := 0.0
var _tack_entry_preposition_active := false
var _tack_entry_crouch_elapsed := 0.0
var _tack_seated_return_active := false
var _tack_seated_return_elapsed := 0.0
var _finger_base_rotations: Dictionary = {}
var _last_resolved_body_capsules: Array = []
var _left_final_palm_offset_in_skeleton := Vector3.ZERO
var _right_final_palm_offset_in_skeleton := Vector3.ZERO
var _final_palm_offsets_valid := false
var _left_palm_goal_global := Vector3.ZERO
var _right_palm_goal_global := Vector3.ZERO
var _left_sheet_projection_raw_wrist_boat := Vector3.ZERO
var _right_sheet_projection_raw_wrist_boat := Vector3.ZERO
var _left_sheet_projection_wrist_boat := Vector3.ZERO
var _right_sheet_projection_wrist_boat := Vector3.ZERO
var _left_sheet_projection_destination_wrist_boat := Vector3.ZERO
var _right_sheet_projection_destination_wrist_boat := Vector3.ZERO
var _left_sheet_projection_generation := -1
var _right_sheet_projection_generation := -1
var _left_sheet_projection_active := false
var _right_sheet_projection_active := false
var _left_sheet_projection_ready_generations := 0
var _right_sheet_projection_ready_generations := 0
var _final_modified_bone_poses: Dictionary = {}
var _final_skeleton_transform_boat := Transform3D.IDENTITY
var _atomic_control_pose_enabled := true
var _atomic_control_failures := 0
var maneuver_profile := {"body_us": 0, "pose_us": 0, "arm_us": 0, "body_calls": 0, "pose_calls": 0, "arm_calls": 0}
var _control_frame_delta := 1.0 / 60.0
var _completed_extension_delta := 0.0
var _atomic_control_history_valid := false
var _last_validated_atomic_control_pose: Dictionary = {}
var _atomic_control_frame_held := false
var _atomic_control_rejected_trials := 0
var _atomic_preview_debug_inputs: Dictionary = {}
var _atomic_stage_debug_count := 0
var _atomic_stage_debug_generation := -1
var _maneuver_frame_start_time := 0.0
var _maneuver_frame_pair_state: Dictionary = {}
var _pending_extension_delta := 0.0
var _pending_extension_immediate := true
var _extension_resolve_pending := false
var _extension_pose_generation := 0
var _control_pose_immediate := false
var _anatomical_controls_ready := false
var _inside_leg_modifier_callback := false
var _sheet_motion_weight := 0.0
var _sheet_stroke_amount := 0.0
var _sheet_hand_grip_amount := 1.0
var _sheet_assist_grip_amount := 0.0
var _sheet_motion_phase: int = SheetMotionPhase.IDLE
var _sheet_phase_progress := 0.0
var _sheet_pending_mode := 0
var _sheet_effective_motion_fraction := 0.0
var _sheet_hand_target_boat := Vector3.ZERO
var _sheet_phase_start_target_boat := Vector3.ZERO
var _sheet_phase_end_target_boat := Vector3.ZERO
var _rendered_sheet_target_boat := Vector3.ZERO
var _rendered_sheet_target_initialized := false
var _rendered_sheet_target_generation := -1
var _sheet_transfer_latched_length := -1.0
var _sheet_tack_interlock_requested := false
var _last_sheet_position := 0.45


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
	_rig_root.scale = Vector3.ONE * BODY_UNIFORM_SCALE
	_pose_root.add_child(_rig_root)
	_skeleton = _rig_root.get_node("Armature/GeneralSkeleton") as Skeleton3D
	_animation_player = _rig_root.get_node("AnimationPlayer") as AnimationPlayer
	_install_seated_pose()

	_hips_bone = _skeleton.find_bone("Hips")
	_spine_bone = _skeleton.find_bone("Spine")
	_chest_bone = _skeleton.find_bone("Chest")
	_neck_bone = _skeleton.find_bone("Neck")
	_head_bone = _skeleton.find_bone("Head")
	_upper_chest_bone = _skeleton.find_bone("UpperChest")
	_left_upper_leg_bone = _skeleton.find_bone("LeftUpperLeg")
	_left_lower_leg_bone = _skeleton.find_bone("LeftLowerLeg")
	_right_upper_leg_bone = _skeleton.find_bone("RightUpperLeg")
	_right_lower_leg_bone = _skeleton.find_bone("RightLowerLeg")
	_left_foot_bone = _skeleton.find_bone("LeftFoot")
	_right_foot_bone = _skeleton.find_bone("RightFoot")
	_left_foot_tip_bone = _skeleton.find_bone("ball_leaf_l")
	_right_foot_tip_bone = _skeleton.find_bone("ball_leaf_r")
	_left_lower_arm_bone = _skeleton.find_bone("LeftLowerArm")
	_right_lower_arm_bone = _skeleton.find_bone("RightLowerArm")
	_left_upper_arm_bone = _skeleton.find_bone("LeftUpperArm")
	_right_upper_arm_bone = _skeleton.find_bone("RightUpperArm")
	_left_hand_bone = _skeleton.find_bone("LeftHand")
	_right_hand_bone = _skeleton.find_bone("RightHand")

	_configure_render_layers()
	_configure_arm_ik()
	_configure_leg_ik()
	_configure_contact_modifier()
	_create_anatomical_anchors()
	_capture_finger_base_pose()
	_create_sailing_clothing()
	_create_held_mainsheet()
	_last_sheet_position = _boat.get_sailing_state().sheet_position
	_sheet_hand_target_boat = _sheet_power_target_boat()
	_sheet_phase_start_target_boat = _sheet_hand_target_boat
	_sheet_phase_end_target_boat = _sheet_hand_target_boat
	_apply_pose_side_transform()
	_animation_player.advance(0.0)
	_capture_animation_torso_pose()
	_capture_base_head_from_chest()
	_capture_stable_gaze_basis()
	_apply_head_pose()
	_update_leg_ik_targets()
	_resolve_control_hands()
	_update_control_ik_targets()
	_apply_control_grip_pose()
	_update_held_mainsheet()
	_anatomical_controls_ready = true
	queue_tiller_extension_resolve(0.0, true)
	set_head_look(0.0, deg_to_rad(-12.0))


func _process(delta: float) -> void:
	CONTROL_POSE.clear_cache()
	_control_frame_delta = clampf(delta, 0.0, 0.10)
	_boat.prepare_tiller_extension_body_pose_frame()
	var boom_angle := _boat.get_sailing_state().boom_angle_radians
	var requested_side := -signf(boom_angle)
	if (
		not _maneuver_active
		and absf(boom_angle) > deg_to_rad(1.0)
		and requested_side * seat_side < -0.95
	):
		_begin_maneuver(requested_side)
	_maneuver_frame_pair_state.clear()
	if _maneuver_active:
		_maneuver_frame_start_time = _maneuver_elapsed
		_maneuver_frame_pair_state = _boat.capture_tiller_extension_body_pose_pair_state()
		_sheet_tack_interlock_requested = true
		if _sheet_motion_is_safe_for_tack():
			_advance_maneuver(maxf(delta, 0.0))
		else:
			_maneuver_wait_seconds += maxf(delta, 0.0)
	else:
		_apply_pose_side_transform()
		_restore_animation_torso_pose()
		_animation_player.advance(delta)
		_capture_animation_torso_pose()
		_apply_head_pose()
		_update_leg_ik_targets()
		_update_hand_exchange_state()
	_resolve_control_hands(false)
	queue_tiller_extension_resolve(delta)
	_apply_control_grip_pose()


func _begin_maneuver(target_side: float) -> void:
	_maneuver_active = true
	_maneuver_elapsed = 0.0
	_maneuver_start_side = signf(seat_side)
	_maneuver_target_side = target_side
	_maneuver_wait_seconds = 0.0
	_hand_exchange_direction = target_side
	_tack_entry_preposition_active = false
	_tack_seated_return_active = false
	_sheet_tack_interlock_requested = true
	_pose_animation = &"Seated"
	_animation_player.play("sailor/Seated")
	_animation_player.seek(0.5, true)
	_capture_animation_torso_pose()
	var state := _boat.get_sailing_state()
	var wind: Vector3 = state.apparent_wind_velocity()
	var forward := -_boat.global_basis.z.normalized()
	_maneuver_kind = &"gybe" if forward.dot(-wind.normalized()) < 0.0 else &"tack"
	_apply_maneuver_sample(0.0)


func maneuver_active() -> bool:
	return _maneuver_active


func maneuver_progress() -> float:
	return _maneuver_crossing


func maneuver_phase_name() -> StringName:
	return _maneuver_phase


func maneuver_kind_name() -> StringName:
	return _maneuver_kind


func _advance_maneuver(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_advance_maneuver_impl(delta)
	maneuver_profile["body_us"] += Time.get_ticks_usec() - started
	maneuver_profile["body_calls"] += 1


func _advance_maneuver_impl(delta: float) -> void:
	# Limit catch-up work after a slow frame. Maneuver time advances only for
	# accepted intervals; no unsafe intermediate body pose is skipped.
	var remaining := minf(delta, MANEUVER_SUBSTEP)
	var trial_step := MANEUVER_SUBSTEP
	var searches := 0
	while remaining > 0.000001 and _maneuver_elapsed < MANEUVER_DURATION:
		var step := minf(remaining, trial_step)
		var previous_time := _maneuver_elapsed
		var next_time := minf(previous_time + step, MANEUVER_DURATION)
		_apply_maneuver_sample(next_time)
		var next_capsules := _sample_post_leg_body_capsules_boat()
		var side := _maneuver_target_side if _maneuver_crossing >= 0.5 else _maneuver_start_side
		var accepted := _boat.tiller_extension_pair_accepts_body_pose(
			next_capsules, side, true
		)
		var wait_reason := "future_pair"
		var proposal: Dictionary = {}
		if not accepted:
			# First try moving the body and shaft together over the full interval.
			# Testing only a stationary shaft before subdivision reduced every
			# successful coupled step to the minimum probe duration.
			if searches >= 2 or (searches > 0 and step > MANEUVER_MIN_SUBSTEP + 0.000001):
				_apply_maneuver_sample(previous_time)
				if step > MANEUVER_MIN_SUBSTEP + 0.000001:
					trial_step = maxf(step * 0.5, MANEUVER_MIN_SUBSTEP)
					continue
				break
			searches += 1
			# Body subdivision is a geometric safety probe, not a shorter render
			# frame. Let the shaft prepare within this frame's remaining physical
			# motion budget; committing only the probe duration starves both paths.
			proposal = _boat.preview_tiller_extension_pair_for_body_pose(
				next_capsules, side, true, remaining, 1
			)
			accepted = not proposal.is_empty()
		if accepted:
			wait_reason = "swept_pair"
			var sweep_fractions := [0.5] if proposal.is_empty() else [0.25, 0.5, 0.75]
			for fraction in sweep_fractions:
				_apply_maneuver_sample(lerpf(previous_time, next_time, float(fraction)))
				var swept_pair: Dictionary = {}
				if not proposal.is_empty():
					var from_direction: Vector3 = proposal["from_direction"]
					swept_pair = {"direction": from_direction.slerp(proposal["direction"], float(fraction)),
						"distance": lerpf(float(proposal["from_distance"]), float(proposal["distance"]), float(fraction))}
				accepted = _boat.tiller_extension_pair_accepts_body_pose(
					_sample_post_leg_body_capsules_boat(), side, true, swept_pair)
				if not accepted:
					break
		if not accepted:
			if not proposal.is_empty():
				_boat.reject_tiller_extension_body_pose_pair(proposal)
			if OS.get_environment("WINDWARD_MANEUVER_DEBUG") == "1" and _maneuver_wait_seconds < 0.1:
				var axis := _boat.tiller_extension_direction_boat()
				var joint: Vector3 = _boat.rudder_pivot.transform * _tiller_extension_pivot.position
				var contact := joint + axis * _boat.tiller_extension_hand_distance()
				print("MANEUVER_ARM_WAIT ", preview_tiller_extension_pair_wrist_guard(contact, axis, true))
			_apply_maneuver_sample(previous_time)
			if step > MANEUVER_MIN_SUBSTEP + 0.000001:
				trial_step = maxf(step * 0.5, MANEUVER_MIN_SUBSTEP)
				continue
			if OS.has_environment("WINDWARD_MANEUVER_DEBUG") and _maneuver_wait_seconds < 0.1:
				print("MANEUVER_WAIT phase=%s time=%.4f reason=%s proposal=%s" % [_maneuver_phase, previous_time, wait_reason, not proposal.is_empty()])
			_maneuver_wait_seconds += remaining
			break
		_apply_maneuver_sample(next_time)
		if not proposal.is_empty():
			if not _boat.commit_tiller_extension_body_pose_pair(proposal):
				_apply_maneuver_sample(previous_time)
				_maneuver_wait_seconds += remaining
				break
			# A committed proposal has consumed this frame's remaining shaft time.
			searches = 2
		remaining -= step
		trial_step = MANEUVER_SUBSTEP if not proposal.is_empty() else step
	if _maneuver_elapsed >= MANEUVER_DURATION:
		var pair := _boat.tiller_extension_driven_pair()
		if (
			not _boat.tiller_extension_is_blocked()
			and not _boat.tiller_extension_handover_route_active()
			and int(pair.get("mode", -1)) == WindwardBoat.TillerExtensionPairMode.NORMAL
		):
			_maneuver_active = false
			# Releasing the maneuver also changes the ordinary sheet target rules.
			# Validate that state before exposing it to the final arm modifier.
			if not _boat.tiller_extension_pair_accepts_body_pose(
				_last_resolved_body_capsules, _maneuver_target_side, false
			):
				_maneuver_active = true
				return
			_maneuver_phase = &"seated"
			_maneuver_duck = 0.0
			seat_side = _maneuver_target_side
			_last_hand_exchange_side = seat_side
			_sheet_tack_interlock_requested = false


func _apply_maneuver_sample(elapsed: float) -> void:
	var started := Time.get_ticks_usec()
	_apply_maneuver_sample_impl(elapsed)
	maneuver_profile["pose_us"] += Time.get_ticks_usec() - started
	maneuver_profile["pose_calls"] += 1


func _apply_maneuver_sample_impl(elapsed: float) -> void:
	_maneuver_elapsed = elapsed
	var cross_end := MANEUVER_CROUCH_SECONDS + MANEUVER_CROSS_SECONDS
	var pivot_end := cross_end + MANEUVER_PIVOT_SECONDS
	if elapsed < MANEUVER_CROUCH_SECONDS:
		_maneuver_phase = &"crouch"
		_maneuver_crossing = 0.0
		_maneuver_duck = smoothstep(0.0, MANEUVER_CROUCH_SECONDS, elapsed)
	elif elapsed < cross_end:
		_maneuver_phase = &"cross"
		_maneuver_crossing = 0.52 * smoothstep(MANEUVER_CROUCH_SECONDS, cross_end, elapsed)
		_maneuver_duck = 1.0
	elif elapsed < pivot_end:
		_maneuver_phase = &"pivot"
		_maneuver_crossing = lerpf(0.52, 1.0, smoothstep(cross_end, pivot_end, elapsed))
		_maneuver_duck = 1.0
	else:
		_maneuver_phase = &"sit"
		_maneuver_crossing = 1.0
		_maneuver_duck = 1.0 - smoothstep(pivot_end, MANEUVER_DURATION, elapsed)
	seat_side = lerpf(_maneuver_start_side, _maneuver_target_side, _maneuver_crossing)
	# Tacking crosses through the bow-facing half turn. Preserve the unwrapped
	# angle so the two seated endpoints cannot choose the stern-facing shortcut.
	var turn_progress := smoothstep(0.06, 0.94, _maneuver_crossing)
	var turn_sign := -1.0 if _maneuver_kind == &"tack" else 1.0
	_maneuver_heading = -_maneuver_start_side * PI * 0.5 + turn_sign * _maneuver_start_side * PI * turn_progress
	_hand_exchange_progress = _maneuver_crossing
	_hand_exchange_amount = sin(_maneuver_crossing * PI)
	_tiller_is_left = (
		_maneuver_target_side > 0.0
		if _maneuver_crossing >= 0.5
		else _maneuver_start_side > 0.0
	)
	_last_hand_exchange_side = seat_side
	_restore_animation_torso_pose()
	for bone in _animation_arm_rotations:
		_skeleton.set_bone_pose_rotation(int(bone), _animation_arm_rotations[bone])
	_apply_pose_side_transform()
	_apply_head_pose()
	_update_leg_ik_targets()
	_solve_maneuver_legs()
	_last_resolved_body_capsules = _sample_post_leg_body_capsules_boat()


func _solve_maneuver_legs() -> void:
	for bone in _animation_leg_rotations:
		_skeleton.set_bone_pose_rotation(int(bone), _animation_leg_rotations[bone])
	_skeleton.force_update_bone_child_transform(_hips_bone)
	for entry in [
		[_left_upper_leg_bone, _left_lower_leg_bone, _left_foot_bone, _left_foot_target, _left_foot_pole],
		[_right_upper_leg_bone, _right_lower_leg_bone, _right_foot_bone, _right_foot_target, _right_foot_pole],
	]:
		var target: Node3D = entry[3]
		var pole: Node3D = entry[4]
		LEG_POSE.solve(
			_skeleton, int(entry[0]), int(entry[1]), int(entry[2]),
			_skeleton.to_local(target.global_position),
			_skeleton.to_local(pole.global_position)
		)


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
	# The cumulative Head rest/bind basis uses +Z forward and +Y up. Normalize
	# every imported neutral head rotation, including yaw and roll, below.
	# Calibrate the imported model's neutral face tilt once. Afterwards a 0°
	# request is genuinely level in the sailor pose, not the clip's +14° bias.
	# Pose space defines the canonical face frame (+Y up, +Z forward). Removing
	# the source yaw and roll as well as pitch keeps the 14.5 cm EyeAnchor on the
	# centreline and makes the two transverse seated poses mirror exactly.
	_stable_neutral_head_basis_in_pose = Basis.IDENTITY
	_base_head_from_chest = (
		_base_upper_chest_basis_in_pose.inverse()
		* _stable_neutral_head_basis_in_pose
	).orthonormalized()


func _capture_current_neutral_head_from_chest() -> void:
	# Capture the actual animation-neutral UpperChest relation after the rigid
	# ILCA spine correction but before gaze-driven torso twist/flex. Recomputing
	# it from the current pure animation sample preserves the small breathing sway
	# without letting that sway become an unbounded neck rotation.
	var upper_chest_world_basis := (
		_skeleton.global_basis
		* _skeleton.get_bone_global_pose(_upper_chest_bone).basis
	).orthonormalized()
	var neutral_head_world_basis := (
		_pose_root.global_basis.orthonormalized()
		* Basis(Vector3.UP, _neutral_upper_torso_yaw())
		* _stable_neutral_head_basis_in_pose
	).orthonormalized()
	_current_neutral_head_from_chest = (
		upper_chest_world_basis.inverse()
		* neutral_head_world_basis
	).orthonormalized()


func _apply_pose_side_transform() -> void:
	# Spine has no source animation track. Remove the previous procedural pose
	# before a tack/seek so the neutral Spine correction cannot accumulate.
	_restore_animation_torso_pose()
	var clamped_side := clampf(seat_side, -1.0, 1.0)
	var crossing_amount := 1.0 - absf(clamped_side)
	_pose_root.rotation = Vector3(
		0.0,
		_maneuver_heading if _maneuver_active else BODY_FORWARD_CORRECTION + BODY_SEAT_YAW * clamped_side,
		0.0
	)
	_pose_root.scale = Vector3.ONE
	_update_pose_animation(crossing_amount)


func _update_pose_animation(crossing_amount: float) -> void:
	if _maneuver_active:
		return
	# Duck before the body leaves the old side. Starting the half-second Crouch
	# blend at |side| ~= .86 moved the tiller shoulder through an entry pair that
	# had been solved against Seated, turning a safe 98 cm foam contact into a
	# 20 mm shoulder penetration. Entry preposition now owns that preparation and
	# keeps the crouch latched until the handover has actually reached the new side.
	var seated_return_amount := 1.0 - SEATED_ANIMATION_RETURN_SIDE
	var tack_pose_active := (
		_tack_entry_preposition_active
		or (
			_hand_exchange_progress > 0.0001
			and _hand_exchange_progress < 0.999
		)
	)
	var driven_pair := _boat.tiller_extension_driven_pair()
	var seated_return_ready := (
		not tack_pose_active
		and absf(seat_side) >= 0.999
		and not _boat.tiller_extension_handover_route_active()
		and int(driven_pair.get("mode", -1))
		== WindwardBoat.TillerExtensionPairMode.NORMAL
	)
	var desired := _pose_animation
	if _pose_animation == &"Seated":
		if tack_pose_active or crossing_amount > CROUCH_ANIMATION_ENTRY_AMOUNT:
			desired = &"Crouch"
	elif seated_return_ready and crossing_amount <= seated_return_amount:
		desired = &"Seated"
	if desired == _pose_animation:
		return
	_pose_animation = desired
	if desired == &"Seated":
		_tack_seated_return_active = true
		_tack_seated_return_elapsed = 0.0
	else:
		_tack_seated_return_active = false
		_tack_seated_return_elapsed = 0.0
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
	for bone in [_left_upper_leg_bone, _left_lower_leg_bone, _left_foot_bone, _right_upper_leg_bone, _right_lower_leg_bone, _right_foot_bone]:
		if bone >= 0:
			_animation_leg_rotations[bone] = _skeleton.get_bone_pose_rotation(bone)
	for bone in [_left_upper_arm_bone, _left_lower_arm_bone, _right_upper_arm_bone, _right_lower_arm_bone]:
		if bone >= 0:
			_animation_arm_rotations[bone] = _skeleton.get_bone_pose_rotation(bone)
	for bone_index in [_spine_bone, _chest_bone, _upper_chest_bone]:
		if bone_index >= 0:
			# Sitting/Crouch have no Spine track. Retain its first pure source
			# sample instead of recapturing the previous procedural correction.
			if bone_index == _spine_bone and _animation_torso_rotations.has(bone_index):
				continue
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
		[_chest_bone, 0.42],
		[_upper_chest_bone, 0.58],
	]
	# Restore the current animation sample first; camera synchronization can call
	# this more than once in one frame and must never accumulate extra twist.
	_restore_animation_torso_pose()
	# Rotate the whole Spine descendant subtree rigidly in Skeleton3D space.
	# Chest and UpperChest keep the imported animation; only later gaze deltas
	# are distributed between them.
	var spine_basis := _skeleton.get_bone_global_pose(_spine_bone).basis.orthonormalized()
	_set_bone_global_basis(
		_spine_bone,
		(
			Basis(Vector3.UP, _neutral_upper_torso_yaw())
			* Basis(Vector3.RIGHT, NEUTRAL_SPINE_PITCH + _maneuver_duck * deg_to_rad(12.0))
			* spine_basis
		).orthonormalized()
	)
	_capture_current_neutral_head_from_chest()

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
		_set_bone_global_basis(bone_index, desired_basis)


func _neutral_upper_torso_yaw() -> float:
	return -NEUTRAL_UPPER_TORSO_YAW * sin(
		clampf(seat_side, -1.0, 1.0) * PI * 0.5
	)


func _set_bone_global_basis(bone_index: int, desired_basis: Basis) -> void:
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
	if not is_instance_valid(_skeleton) or _head_bone < 0 or _upper_chest_bone < 0:
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
		# The pelvis faces directly inboard while the resting chest and head open
		# toward the bow together. Keeping this neutral yaw in the canonical gaze
		# prevents the new upright pelvis from becoming a permanent neck twist.
		_pose_root.global_basis.orthonormalized()
		* Basis(Vector3.UP, _neutral_upper_torso_yaw())
		* _stable_neutral_head_basis_in_pose
		* Basis((total_yaw_delta * total_pitch_delta).normalized())
	).orthonormalized()
	# Keep the canonical spherical Head basis above, while making the rendered
	# UpperChest-to-Head delta equal the bounded neck share. Factoring the desired
	# Head basis this way prevents Head from cancelling the torso assist at deep
	# pitch or rearward yaw, yet preserves the exact first-person gaze direction.
	var neck_delta := Basis((
		Quaternion(Vector3.UP, -_applied_neck_yaw)
		* Quaternion(Vector3.RIGHT, -_applied_neck_pitch)
	).normalized())
	var desired_head_from_chest := (
		_current_neutral_head_from_chest * neck_delta
	).orthonormalized()
	var desired_upper_chest_world_basis := (
		desired_head_world_basis * desired_head_from_chest.inverse()
	).orthonormalized()
	var desired_upper_chest_basis := (
		_skeleton.global_basis.inverse()
		* desired_upper_chest_world_basis
	).orthonormalized()
	_set_bone_global_basis(_upper_chest_bone, desired_upper_chest_basis)
	var desired_head_basis := (
		_skeleton.global_basis.inverse()
		* desired_head_world_basis
	).orthonormalized()
	_set_bone_global_basis(_head_bone, desired_head_basis)
	_update_eye_anchor()
	# Position is solved only after animation, neutral Spine, and final Head have
	# been evaluated. Hand/leg targets are updated later in the same frame.
	_update_seat_contact_anchor()
	_solve_seat_contact()


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


func mainsheet_grip_global_position() -> Vector3:
	_resolve_control_hands()
	return _sheet_grip_anchor.global_position


func tiller_hand_global_position() -> Vector3:
	_resolve_control_hands()
	return _tiller_hand_anchor.global_position


func tiller_hand_boat_position() -> Vector3:
	return _boat.to_local(tiller_hand_global_position())


func tiller_grip_global_position() -> Vector3:
	return _tiller_grip.global_position


func tiller_extension_body_capsules_boat() -> Array:
	# Only expose the snapshot captured inside the post-leg-IK callback. Reading
	# get_bone_global_pose() later in _process returns the pre-modifier pose after
	# Godot has applied the temporary modifier result to the skin and rolled back.
	return _last_resolved_body_capsules.duplicate(true)


func _sample_post_leg_body_capsules_boat() -> Array:
	# Store anatomical body radii only. Each consumer adds its own geometry:
	# shaft radius/air gap in Boat, palm radius in tests, and forearm radius in
	# tests. The previous combined values double-counted those margins and made
	# every chest-front extension direction geometrically impossible.
	var capsules: Array = []
	_append_bone_capsule(
		capsules,
		_hips_bone,
		_upper_chest_bone,
		0.152,
		&"torso"
	)
	_append_bone_capsule(
		capsules,
		_left_upper_leg_bone,
		_left_lower_leg_bone,
		0.092,
		&"left_thigh"
	)
	_append_bone_capsule(
		capsules,
		_right_upper_leg_bone,
		_right_lower_leg_bone,
		0.092,
		&"right_thigh"
	)
	_append_bone_capsule(
		capsules,
		_left_upper_arm_bone,
		_left_upper_arm_bone,
		SHOULDER_CAPSULE_RADIUS,
		&"left_shoulder"
	)
	_append_bone_capsule(
		capsules,
		_right_upper_arm_bone,
		_right_upper_arm_bone,
		SHOULDER_CAPSULE_RADIUS,
		&"right_shoulder"
	)
	_append_bone_capsule(
		capsules,
		_left_lower_leg_bone,
		_left_foot_bone,
		CALF_CAPSULE_RADIUS,
		&"left_calf"
	)
	_append_bone_capsule(
		capsules,
		_right_lower_leg_bone,
		_right_foot_bone,
		CALF_CAPSULE_RADIUS,
		&"right_calf"
	)
	return capsules


func queue_tiller_extension_resolve(delta: float, immediate: bool = false) -> void:
	_pending_extension_delta = clampf(delta, 0.0, 0.10)
	_pending_extension_immediate = _pending_extension_immediate or immediate
	_extension_resolve_pending = true


func tiller_extension_pose_generation() -> int:
	return _extension_pose_generation


func tiller_extension_pose_delta() -> float:
	# Delta belongs to the completed modifier generation, not the next idle frame.
	return _completed_extension_delta


func _on_leg_ik_modification_processed() -> void:
	if (
		not _anatomical_controls_ready
		or _inside_leg_modifier_callback
		or not _extension_resolve_pending
	):
		return
	_inside_leg_modifier_callback = true
	_solve_maneuver_legs()
	var body_capsules := _sample_post_leg_body_capsules_boat()
	if body_capsules.size() >= 3:
		_last_resolved_body_capsules = body_capsules.duplicate(true)
		var resolve_immediate := _pending_extension_immediate
		_boat.resolve_tiller_extension(
			_pending_extension_delta,
			body_capsules,
			resolve_immediate
		)
		_control_pose_immediate = resolve_immediate
		var staged_pose := _stage_atomic_control_pose_for_next_generation()
		var rejected_final_arms := not bool(staged_pose["safe"])
		if rejected_final_arms:
			_atomic_control_rejected_trials += 1
		if (
			(_boat.tiller_extension_is_blocked() or rejected_final_arms)
			and not _maneuver_frame_pair_state.is_empty()
		):
			# Either final participant can reject a trial. Restore the prepared
			# frame's body and shaft before staging both hands again; never rewind
			# the actual rudder input or accept one hand from the rejected posture.
			_maneuver_active = true
			_apply_maneuver_sample(_maneuver_frame_start_time)
			var restored_capsules := _sample_post_leg_body_capsules_boat()
			var restored_side := _maneuver_target_side if _maneuver_crossing >= 0.5 else _maneuver_start_side
			_last_resolved_body_capsules = restored_capsules
			_sheet_tack_interlock_requested = true
			_maneuver_wait_seconds += _pending_extension_delta
			_resolve_control_hands(false)
			if _boat.restore_tiller_extension_body_pose_pair_state(
				_maneuver_frame_pair_state, restored_capsules, restored_side, true
			):
				staged_pose = _stage_atomic_control_pose_for_next_generation()
			else:
				# The prepared shaft may itself be infeasible after a real joint
				# movement. Keep the restored body, report the hold, and do not
				# manufacture a successful contact or revive the rejected pose.
				staged_pose["safe"] = false
			_apply_control_grip_pose()
		_pending_extension_immediate = false
		_extension_resolve_pending = false
		_extension_pose_generation += 1
		_completed_extension_delta = _pending_extension_delta
		# Modifier sibling order is legs first, arms second. These targets are thus
		# consumed by both arm solvers in this same rendered skeleton cycle. Commit
		# the exact staged solution; re-reading the sheet here would advance its
		# generation independently and could invalidate the final preflight.
		if bool(staged_pose["safe"]):
			_rendered_sheet_target_boat = staged_pose["sheet_target"]
			_rendered_sheet_target_initialized = true
			_rendered_sheet_target_generation = _extension_pose_generation
			_apply_atomic_control_targets(staged_pose)
		elif _atomic_control_history_valid:
			_hold_validated_atomic_control_targets(staged_pose)
		else:
			# Initial placement precedes the first validated physical grip.
			_update_control_ik_targets()
		_control_pose_immediate = false
	_inside_leg_modifier_callback = false


func _apply_terminal_contact_pose() -> void:
	_solve_control_arm_poses()
	# This runs inside the final SkeletonModifier3D, after both leg and arm IK
	# solvers. IK remains authoritative for knee/elbow placement; this pass fixes
	# terminal roll and the few-millimetre palm offset introduced by that roll.
	_align_bare_foot_to_strap(
		_left_foot_bone,
		_left_foot_tip_bone,
		-1.0
	)
	_align_bare_foot_to_strap(
		_right_foot_bone,
		_right_foot_tip_bone,
		1.0
	)
	if _left_hand_basis_override:
		_apply_hand_contact_basis(
			_left_hand_bone,
			_left_hand_anchor,
			_left_desired_hand_basis,
			_left_palm_goal_global
		)
	if _right_hand_basis_override:
		_apply_hand_contact_basis(
			_right_hand_bone,
			_right_hand_anchor,
			_right_desired_hand_basis,
			_right_palm_goal_global
		)
	_capture_terminal_contact_bone_poses()


func _solve_control_arm_poses() -> void:
	for bone in _animation_arm_rotations:
		_skeleton.set_bone_pose_rotation(int(bone), _animation_arm_rotations[bone])
	_skeleton.force_update_bone_child_transform(_upper_chest_bone)
	for entry in [
		[_left_upper_arm_bone, _left_lower_arm_bone, _left_hand_bone, _left_hand_target, _left_hand_pole],
		[_right_upper_arm_bone, _right_lower_arm_bone, _right_hand_bone, _right_hand_target, _right_hand_pole],
	]:
		var target: Node3D = entry[3]
		var pole: Node3D = entry[4]
		LEG_POSE.solve(
			_skeleton, int(entry[0]), int(entry[1]), int(entry[2]),
			_skeleton.to_local(target.global_position),
			_skeleton.to_local(pole.global_position)
		)


func _post_ik_blended_control_hand_basis(
	hand_bone: int,
	lower_arm_bone: int,
	palm_goal_global: Vector3,
	tiller_weight: float
) -> Basis:
	var weight := smoothstep(0.0, 1.0, clampf(tiller_weight, 0.0, 1.0))
	var sheet_basis := _post_ik_control_hand_basis(
		hand_bone,
		lower_arm_bone,
		false,
		palm_goal_global
	)
	if weight <= 0.0001:
		return sheet_basis
	var tiller_basis := _post_ik_control_hand_basis(
		hand_bone,
		lower_arm_bone,
		true,
		palm_goal_global
	)
	if weight >= 0.9999:
		return tiller_basis
	return Basis(
		sheet_basis.get_rotation_quaternion().slerp(
			tiller_basis.get_rotation_quaternion(),
			weight
		).normalized()
	).orthonormalized()


func _post_ik_control_hand_basis(
	hand_bone: int,
	lower_arm_bone: int,
	uses_tiller: bool,
	palm_goal_global: Vector3
) -> Basis:
	# IK has now chosen the current elbow. Rebuild the wrist roll from that live
	# forearm instead of applying the one-cycle-old basis used to predict the IK
	# wrist target. This prevents a tucked elbow from leaving the hand twisted
	# ninety degrees across the extension.
	var hand_pose := _skeleton.get_bone_global_pose(hand_bone)
	var lower_arm_pose := _skeleton.get_bone_global_pose(lower_arm_bone)
	var forearm_direction := hand_pose.origin - lower_arm_pose.origin
	var grip_axis_world := (
		-_tiller_extension_pivot.global_basis.z.normalized()
		if uses_tiller
		else _sheet_grip_axis_world(palm_goal_global)
	)
	var grip_axis := (
		_skeleton.global_basis.inverse() * grip_axis_world
	).normalized()
	if hand_bone == _left_hand_bone:
		grip_axis = -grip_axis
	return _grip_basis_from_forearm(
		grip_axis,
		forearm_direction,
		hand_pose.basis.orthonormalized()
	)


func _sheet_grip_axis_world(palm_goal_global: Vector3) -> Vector3:
	# The flexible rope follows the hand; it must not drive the wrist from the
	# previous rendered rope mesh. That old feedback loop was:
	# previous tangent -> wrist basis -> new palm -> new tangent, and oscillated
	# whenever a route candidate or trim phase changed. Use one deterministic
	# working-line guide instead. The rendered rope still terminates at the final
	# palm contact after the modifier stack has completed.
	# The hand crosses the old local guide during every pull. At that instant the
	# guide-to-palm vector approached zero and its normalized direction flipped,
	# producing a one-frame wrist/elbow snap. The loaded line always originates at
	# the ratchet, so block-to-palm is both physically meaningful and non-singular
	# throughout the authored working stroke.
	var axis := palm_goal_global - _boat.to_global(MAIN_SHEET_BLOCK_POSITION)
	if axis.length_squared() <= 0.000001:
		axis = _boat.global_basis * Vector3.UP
	return axis.normalized()


func _capture_terminal_contact_bone_poses() -> void:
	# Skeleton3D restores source poses after the modifier stack. Cache terminal
	# contacts here, while the rendered hand basis and its finger descendants are
	# still live, so diagnostics never compare a final wrist with rolled-back
	# finger joints from a different pose.
	for bone_entry in [
		[_left_lower_arm_bone, &"LeftLowerArm"],
		[_right_lower_arm_bone, &"RightLowerArm"],
		[_left_hand_bone, &"LeftHand"],
		[_right_hand_bone, &"RightHand"],
	]:
		var bone_index: int = bone_entry[0]
		var bone_key: StringName = bone_entry[1]
		_capture_final_modified_bone_pose(bone_index, bone_key)
	for side in ["Left", "Right"]:
		for digit in ["Index", "Middle", "Ring", "Little"]:
			for segment in ["Proximal", "Intermediate", "Distal"]:
				var bone_name: String = side + digit + segment
				_capture_final_modified_bone_pose(
					_skeleton.find_bone(bone_name),
					StringName(bone_name)
				)
		for thumb_segment in ["Metacarpal", "Proximal", "Distal"]:
			var thumb_name: String = side + "Thumb" + thumb_segment
			_capture_final_modified_bone_pose(
				_skeleton.find_bone(thumb_name),
				StringName(thumb_name)
			)


func _align_bare_foot_to_strap(
	foot_bone: int,
	foot_tip_bone: int,
	foot_side: float
) -> void:
	if foot_bone < 0 or foot_tip_bone < 0:
		return
	var foot_pose := _skeleton.get_bone_global_pose(foot_bone)
	var tip_pose := _skeleton.get_bone_global_pose(foot_tip_bone)
	var current_vector := tip_pose.origin - foot_pose.origin
	if current_vector.length_squared() <= 0.000001:
		return
	var foot_world := (_skeleton.global_transform * foot_pose).origin
	var tip_world := (_skeleton.global_transform * tip_pose).origin
	var rendered_length := foot_world.distance_to(tip_world)
	var foot_boat := _boat.to_local(foot_world)
	var vertical_drop := clampf(
		foot_boat.y - FOOT_TIP_HEIGHT,
		0.0,
		rendered_length * 0.70
	)
	var horizontal_length := sqrt(maxf(
		rendered_length * rendered_length - vertical_drop * vertical_drop,
		0.000001
	))
	var clamped_side := clampf(seat_side, -1.0, 1.0)
	var crossing_amount := 1.0 - absf(clamped_side)
	var horizontal_direction := Vector3(-clamped_side, 0.0, -crossing_amount)
	if _maneuver_active:
		horizontal_direction = Basis(Vector3.UP, _maneuver_heading).z
	if horizontal_direction.length_squared() <= 0.000001:
		horizontal_direction = Vector3(-foot_side, 0.0, 0.0)
	horizontal_direction = horizontal_direction.normalized()
	var desired_vector_boat := (
		horizontal_direction * horizontal_length
		+ Vector3.DOWN * vertical_drop
	)
	var desired_vector_world := _boat.global_basis * desired_vector_boat
	var desired_vector_skeleton := (
		_skeleton.global_basis.inverse() * desired_vector_world
	).normalized()
	var current_direction := current_vector.normalized()
	var correction := Quaternion(current_direction, desired_vector_skeleton)
	# Resolve the remaining roll around the toe axis. The imported foot may point
	# at the right endpoint while leaving its sole sideways, which still exposes
	# the instep above the strap. In the imported rig local +Z is dorsal/up, so
	# local -Z is the sole-facing axis that must remain toward boat-down.
	var corrected_sole := (
		Basis(correction) * -foot_pose.basis.z.normalized()
	)
	corrected_sole -= desired_vector_skeleton * corrected_sole.dot(
		desired_vector_skeleton
	)
	var desired_down_skeleton := (
		_skeleton.global_basis.inverse()
		* (_boat.global_basis * Vector3.DOWN)
	).normalized()
	desired_down_skeleton -= desired_vector_skeleton * desired_down_skeleton.dot(
		desired_vector_skeleton
	)
	var twist := Quaternion.IDENTITY
	if (
		corrected_sole.length_squared() > 0.000001
		and desired_down_skeleton.length_squared() > 0.000001
	):
		corrected_sole = corrected_sole.normalized()
		desired_down_skeleton = desired_down_skeleton.normalized()
		var twist_angle := atan2(
			desired_vector_skeleton.dot(corrected_sole.cross(desired_down_skeleton)),
			clampf(corrected_sole.dot(desired_down_skeleton), -1.0, 1.0)
		)
		twist = Quaternion(desired_vector_skeleton, twist_angle)
	var desired_basis := (
		Basis(twist * correction) * foot_pose.basis.orthonormalized()
	).orthonormalized()
	_skeleton.set_bone_global_pose(
		foot_bone,
		Transform3D(desired_basis, foot_pose.origin)
	)
	_skeleton.force_update_bone_child_transform(foot_bone)


func _apply_hand_contact_basis(
	hand_bone: int,
	hand_anchor: Node3D,
	desired_basis: Basis,
	_palm_goal_global: Vector3
) -> void:
	if hand_bone < 0 or not is_instance_valid(hand_anchor):
		return
	var final_basis := desired_basis.orthonormalized()
	# The IK target was compensated with this exact final basis. Rotate only:
	# moving the Hand origin after TwoBoneIK would shorten the forearm merely to
	# manufacture a perfect contact point.
	var hand_pose := _skeleton.get_bone_global_pose(hand_bone)
	_skeleton.set_bone_global_pose(
		hand_bone,
		Transform3D(final_basis, hand_pose.origin)
	)
	_skeleton.force_update_bone_child_transform(hand_bone)


func _on_arm_ik_modification_processed() -> void:
	if not _anatomical_controls_ready:
		return
	# Cache the final palm vectors rather than integrating a positional error.
	# The next modifier cycle can subtract these one-frame-old, smoothly varying
	# orientation vectors from its palm goals without feedback wind-up.
	_left_final_palm_offset_in_skeleton = _final_palm_offset_in_skeleton(
		_left_hand_bone,
		_left_hand_anchor
	)
	_right_final_palm_offset_in_skeleton = _final_palm_offset_in_skeleton(
		_right_hand_bone,
		_right_hand_anchor
	)
	_final_palm_offsets_valid = true
	_final_skeleton_transform_boat = _boat.global_transform.affine_inverse() * _skeleton.global_transform
	_capture_final_modified_bone_pose(_hips_bone, &"Hips")
	_capture_final_modified_bone_pose(_upper_chest_bone, &"UpperChest")
	_capture_final_modified_bone_pose(_head_bone, &"Head")
	_capture_final_modified_bone_pose(_left_lower_leg_bone, &"LeftLowerLeg")
	_capture_final_modified_bone_pose(_right_lower_leg_bone, &"RightLowerLeg")
	_capture_final_modified_bone_pose(_left_foot_bone, &"LeftFoot")
	_capture_final_modified_bone_pose(_right_foot_bone, &"RightFoot")
	_capture_final_modified_bone_pose(_left_foot_tip_bone, &"LeftFootTip")
	_capture_final_modified_bone_pose(_right_foot_tip_bone, &"RightFootTip")
	_capture_final_modified_bone_pose(_left_lower_arm_bone, &"LeftLowerArm")
	_capture_final_modified_bone_pose(_right_lower_arm_bone, &"RightLowerArm")
	_capture_final_modified_bone_pose(_left_upper_arm_bone, &"LeftUpperArm")
	_capture_final_modified_bone_pose(_right_upper_arm_bone, &"RightUpperArm")
	_capture_final_modified_bone_pose(_left_hand_bone, &"LeftHand")
	_capture_final_modified_bone_pose(_right_hand_bone, &"RightHand")


func _final_palm_offset_in_skeleton(hand_bone: int, hand_anchor: Node3D) -> Vector3:
	if hand_bone < 0 or not is_instance_valid(hand_anchor):
		return Vector3.ZERO
	return _skeleton.get_bone_global_pose(hand_bone).basis * hand_anchor.position


func _capture_final_modified_bone_pose(bone_index: int, key: StringName) -> void:
	if bone_index < 0:
		return
	_final_modified_bone_poses[key] = _skeleton.get_bone_global_pose(bone_index)


func final_modified_bone_pose(bone_name: StringName) -> Transform3D:
	# Diagnostic/test API: direct bone reads outside modification_processed see
	# Godot's rolled-back source pose, not the rendered IK result.
	return _final_modified_bone_poses.get(bone_name, Transform3D.IDENTITY)


func _previous_control_pose_in_skeleton(bone_name: StringName) -> Transform3D:
	# History belongs to the boat frame in which it was rendered. Reusing old
	# skeleton coordinates after a body turn rotates the remembered arm twice.
	return (
		_skeleton.global_transform.affine_inverse() * _boat.global_transform
		* _final_skeleton_transform_boat * _final_modified_bone_poses[bone_name]
	)


func _append_bone_capsule(
	capsules: Array,
	from_bone: int,
	to_bone: int,
	clearance: float,
	label: StringName
) -> void:
	if not is_instance_valid(_skeleton) or from_bone < 0 or to_bone < 0:
		return
	var from_global := (
		_skeleton.global_transform
		* _skeleton.get_bone_global_pose(from_bone)
	).origin
	var to_global := (
		_skeleton.global_transform
		* _skeleton.get_bone_global_pose(to_bone)
	).origin
	capsules.append({
		"from": _boat.to_local(from_global),
		"to": _boat.to_local(to_global),
		"clearance": clearance,
		"label": label,
	})


func left_foot_global_position() -> Vector3:
	return _left_foot_anchor.global_position


func right_foot_global_position() -> Vector3:
	return _right_foot_anchor.global_position


func left_toe_global_position() -> Vector3:
	return _left_toe_anchor.global_position if is_instance_valid(_left_toe_anchor) else Vector3.ZERO


func right_toe_global_position() -> Vector3:
	return _right_toe_anchor.global_position if is_instance_valid(_right_toe_anchor) else Vector3.ZERO


func seat_contact_global_position() -> Vector3:
	return _seat_contact_anchor.global_position


func left_instep_global_position() -> Vector3:
	return _left_instep_anchor.global_position


func right_instep_global_position() -> Vector3:
	return _right_instep_anchor.global_position


func left_sole_global_position() -> Vector3:
	return _left_sole_anchor.global_position


func right_sole_global_position() -> Vector3:
	return _right_sole_anchor.global_position


func hands_are_swapped() -> bool:
	_resolve_control_hands()
	return _tiller_hand_anchor == _left_hand_anchor


func _configure_render_layers() -> void:
	var eyebrows := _skeleton.get_node("Eyebrows") as MeshInstance3D
	var eyes := _skeleton.get_node("Eyes") as MeshInstance3D
	var exterior_body := _skeleton.get_node("SuperHero_Male") as MeshInstance3D
	eyebrows.layers = EXTERIOR_RENDER_LAYER
	eyes.layers = EXTERIOR_RENDER_LAYER
	_configure_face_detail_materials(eyebrows, eyes)
	exterior_body.layers = EXTERIOR_RENDER_LAYER
	exterior_body.material_override = _create_sailor_body_material(exterior_body, false)

	# A second skinned instance is used only by the first-person camera. Its
	# shader removes vertices weighted to the Head bone instead of cutting all
	# geometry above a height plane or inside a camera radius. Raised hands and
	# nearby arms therefore remain visible without rendering the face shell.
	var first_person_body := MeshInstance3D.new()
	first_person_body.name = "FirstPersonBody"
	first_person_body.mesh = exterior_body.mesh
	first_person_body.skin = exterior_body.skin
	first_person_body.skeleton = NodePath("..")
	first_person_body.layers = FIRST_PERSON_BODY_LAYER
	first_person_body.material_override = _create_sailor_body_material(exterior_body, true)
	_skeleton.add_child(first_person_body)


func _configure_face_detail_materials(
	eyebrows: MeshInstance3D,
	eyes: MeshInstance3D
) -> void:
	# The vendor brow atlas is intentionally silver-grey. Tint only this instance
	# instead of mutating the imported shared material used by other assets.
	var brow_source := eyebrows.mesh.surface_get_material(0) as StandardMaterial3D
	if brow_source:
		var brow_material := brow_source.duplicate() as StandardMaterial3D
		brow_material.albedo_color = Color(0.16, 0.075, 0.040, 1.0)
		brow_material.roughness = 0.88
		eyebrows.material_override = brow_material

	# Iris and pupil are baked together in the eye atlas. A centred UV zoom makes
	# both readable without scaling the eyeball mesh through the eyelids.
	var eye_source := eyes.mesh.surface_get_material(0) as StandardMaterial3D
	if eye_source:
		var eye_material := eye_source.duplicate() as StandardMaterial3D
		eye_material.uv1_scale = Vector3(0.84, 0.84, 1.0)
		eye_material.uv1_offset = Vector3(0.08, 0.08, 0.0)
		eyes.material_override = eye_material


func _create_sailor_body_material(
	source_body: MeshInstance3D,
	hide_head: bool
) -> ShaderMaterial:
	var source := source_body.mesh.surface_get_material(0) as StandardMaterial3D
	var head_bind_index := _find_skin_bind_index(source_body.skin, &"Head")
	var left_foot_bind_index := _find_skin_bind_index(source_body.skin, &"LeftFoot")
	var left_toes_bind_index := _find_skin_bind_index(source_body.skin, &"LeftToes")
	var right_foot_bind_index := _find_skin_bind_index(source_body.skin, &"RightFoot")
	var right_toes_bind_index := _find_skin_bind_index(source_body.skin, &"RightToes")
	if SHOW_SAILING_SHOES and (
		left_foot_bind_index < 0
		or left_toes_bind_index < 0
		or right_foot_bind_index < 0
		or right_toes_bind_index < 0
	):
		push_error("Sailor boots require resolvable Foot and Toes skin binds")
		return _create_hidden_first_person_material()
	if hide_head and head_bind_index < 0:
		push_error("First-person sailor requires a resolvable Head skin bind")
		return _create_hidden_first_person_material()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_texture : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform int head_bind_index = -1;
uniform int left_foot_bind_index = -1;
uniform int left_toes_bind_index = -1;
uniform int right_foot_bind_index = -1;
uniform int right_toes_bind_index = -1;
uniform float head_weight_cutoff = 0.35;
uniform float shoe_weight_cutoff = 0.35;
uniform bool hide_head = false;
uniform bool head_mask_ready = false;
uniform bool mask_feet_for_shoes = false;
varying float sailor_head_weight;
varying float sailor_shoe_weight;

void vertex() {
	sailor_head_weight = 0.0;
	sailor_shoe_weight = 0.0;
	for (int influence = 0; influence < 4; influence++) {
		if (int(BONE_INDICES[influence]) == head_bind_index) {
			sailor_head_weight += BONE_WEIGHTS[influence];
		}
		int bone_index = int(BONE_INDICES[influence]);
		if (
			bone_index == left_foot_bind_index
			|| bone_index == left_toes_bind_index
			|| bone_index == right_foot_bind_index
			|| bone_index == right_toes_bind_index
		) {
			sailor_shoe_weight += BONE_WEIGHTS[influence];
		}
	}
}

void fragment() {
	if (
		!head_mask_ready
		|| (hide_head && sailor_head_weight >= head_weight_cutoff)
		|| (mask_feet_for_shoes && sailor_shoe_weight >= shoe_weight_cutoff)
	) {
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
	result.set_shader_parameter(
		"head_bind_index",
		head_bind_index if hide_head else -1
	)
	result.set_shader_parameter("left_foot_bind_index", left_foot_bind_index)
	result.set_shader_parameter("left_toes_bind_index", left_toes_bind_index)
	result.set_shader_parameter("right_foot_bind_index", right_foot_bind_index)
	result.set_shader_parameter("right_toes_bind_index", right_toes_bind_index)
	result.set_shader_parameter("hide_head", hide_head)
	result.set_shader_parameter("head_mask_ready", true)
	result.set_shader_parameter("mask_feet_for_shoes", SHOW_SAILING_SHOES)
	return result


func _create_hidden_first_person_material() -> ShaderMaterial:
	# A renamed or malformed Skin must never fail open by rendering the face shell
	# around the lens in an exported build. Keep the error visible in logs while
	# hiding this instance until the asset's Head bind is repaired.
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
void fragment() {
	discard;
}
"""
	var result := ShaderMaterial.new()
	result.shader = shader
	return result


func _find_skin_bind_index(skin: Skin, bind_name: StringName) -> int:
	if not skin:
		return -1
	for bind_index in range(skin.get_bind_count()):
		if skin.get_bind_name(bind_index) == bind_name:
			return bind_index
	# Some importers preserve only numeric Skeleton3D links. Fall back to the
	# actual skeleton bone index so a harmless bind-name change remains robust.
	var skeleton_bone_index := _skeleton.find_bone(String(bind_name)) if _skeleton else -1
	if skeleton_bone_index >= 0:
		for bind_index in range(skin.get_bind_count()):
			if skin.get_bind_bone(bind_index) == skeleton_bone_index:
				return bind_index
	return -1


func _configure_arm_ik() -> void:
	_left_hand_target = _rig_root.get_node("L_Hand_target") as Node3D
	_right_hand_target = _rig_root.get_node("R_Hand_target") as Node3D
	_left_hand_pole = _rig_root.get_node("L_Hand_pole") as Node3D
	_right_hand_pole = _rig_root.get_node("R_Hand_pole") as Node3D
	_left_arm_ik = _skeleton.get_node("L_ArmIK3D") as SkeletonModifier3D
	_right_arm_ik = _skeleton.get_node("R_ArmIK3D") as SkeletonModifier3D
	_scale_control_arm_chain(_left_upper_arm_bone, _left_lower_arm_bone)
	_scale_control_arm_chain(_right_upper_arm_bone, _right_lower_arm_bone)
	_left_arm_ik.influence = 1.0
	_right_arm_ik.influence = 1.0


func _configure_contact_modifier() -> void:
	# Append one terminal-bone pass after both arm IK siblings. TwoBoneIK3D only
	# solves an end position; this pass supplies the missing hand roll and bare-
	# foot pitch before the final skin is uploaded.
	_contact_modifier = SAILOR_CONTACT_MODIFIER.new() as SkeletonModifier3D
	_contact_modifier.name = "SailorContactModifier"
	_contact_modifier.set("sailor", self)
	_skeleton.add_child(_contact_modifier)
	if not _contact_modifier.modification_processed.is_connected(
		_on_arm_ik_modification_processed
	):
		_contact_modifier.modification_processed.connect(
			_on_arm_ik_modification_processed
		)


func _scale_control_arm_chain(upper_arm_bone: int, lower_arm_bone: int) -> void:
	if upper_arm_bone < 0 or lower_arm_bone < 0:
		return
	_skeleton.set_bone_pose_position(
		lower_arm_bone,
		_skeleton.get_bone_pose_position(lower_arm_bone) * CONTROL_ARM_SCALE
	)
	var hand_bone := (
		_left_hand_bone if upper_arm_bone == _left_upper_arm_bone else _right_hand_bone
	)
	if hand_bone >= 0:
		_skeleton.set_bone_pose_position(
			hand_bone,
			_skeleton.get_bone_pose_position(hand_bone) * CONTROL_ARM_SCALE
		)


func _configure_leg_ik() -> void:
	_left_foot_target = _rig_root.get_node("L_foot_target") as Node3D
	_right_foot_target = _rig_root.get_node("R_foot_target") as Node3D
	_left_foot_pole = _rig_root.get_node("L_foot_pole") as Node3D
	_right_foot_pole = _rig_root.get_node("R_foot_pole") as Node3D
	_left_leg_ik = _skeleton.get_node("L_LegIK3D") as SkeletonModifier3D
	_right_leg_ik = _skeleton.get_node("R_LegIK3D") as SkeletonModifier3D
	_left_leg_ik.influence = 1.0
	_right_leg_ik.influence = 1.0
	_skeleton.modifier_callback_mode_process = (
		Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
	)
	if not _left_leg_ik.modification_processed.is_connected(
		_on_leg_ik_modification_processed
	):
		_left_leg_ik.modification_processed.connect(
			_on_leg_ik_modification_processed
		)


func _create_anatomical_anchors() -> void:
	_left_hand_anchor = _create_bone_anchor("LeftHandAnchor", "LeftHand")
	_right_hand_anchor = _create_bone_anchor("RightHandAnchor", "RightHand")
	# Hand bone origins are wrists. Put the control contact along the palm's grip
	# channel, between the curled fingers and thumb, rather than on the heel.
	# The source palm channel lies closer to the finger bases than the wrist-side
	# placeholder used during the first IK pass. This contact keeps all four final
	# finger chains around the 22 mm extension instead of hovering outside it.
	_left_hand_anchor.position = Vector3(0.0, 0.09433, 0.04843)
	_right_hand_anchor.position = Vector3(0.0, 0.09433, 0.04843)
	# A tiller is centred in the palm, while a 10 mm mainsheet sits between the
	# thumb and curled fingers. Keep the semantic palm anchors authoritative for
	# arm IK, and attach only the rendered rope to these hand-local grip channels.
	# Reusing each existing BoneAttachment avoids a second skeleton notification
	# path and keeps the role switch atomic with the final hand transform.
	_left_sheet_grip_anchor = Node3D.new()
	_left_sheet_grip_anchor.name = "LeftSheetGripAnchor"
	_left_hand_anchor.get_parent().add_child(_left_sheet_grip_anchor)
	_left_sheet_grip_anchor.position = Vector3(-0.040, 0.095, 0.060)
	_right_sheet_grip_anchor = Node3D.new()
	_right_sheet_grip_anchor.name = "RightSheetGripAnchor"
	_right_hand_anchor.get_parent().add_child(_right_sheet_grip_anchor)
	_right_sheet_grip_anchor.position = Vector3(0.040, 0.095, 0.060)
	_left_foot_anchor = _create_bone_anchor("LeftFootAnchor", "LeftFoot")
	_right_foot_anchor = _create_bone_anchor("RightFootAnchor", "RightFoot")
	_left_toe_anchor = _create_bone_anchor("LeftToeAnchor", "ball_leaf_l")
	_right_toe_anchor = _create_bone_anchor("RightToeAnchor", "ball_leaf_r")
	_seat_contact_anchor = Node3D.new()
	_seat_contact_anchor.name = "SeatContactAnchor"
	_skeleton.add_child(_seat_contact_anchor)
	_left_instep_anchor = Node3D.new()
	_left_instep_anchor.name = "LeftInstepContactAnchor"
	_skeleton.add_child(_left_instep_anchor)
	_right_instep_anchor = Node3D.new()
	_right_instep_anchor.name = "RightInstepContactAnchor"
	_skeleton.add_child(_right_instep_anchor)
	_left_sole_anchor = Node3D.new()
	_left_sole_anchor.name = "LeftSoleAnchor"
	_skeleton.add_child(_left_sole_anchor)
	_right_sole_anchor = Node3D.new()
	_right_sole_anchor.name = "RightSoleAnchor"
	_skeleton.add_child(_right_sole_anchor)
	_left_foot_visual = _create_sailing_boot("LeftSailingBoot")
	_right_foot_visual = _create_sailing_boot("RightSailingBoot")
	_foot_visuals_ready = true
	_eye_anchor = Node3D.new()
	_eye_anchor.name = "EyeAnchor"
	_skeleton.add_child(_eye_anchor)
	_update_eye_anchor()
	_update_seat_contact_anchor()
	_update_foot_contact_anchors()
	# BoneAttachment3D updates at skeleton_updated after TwoBoneIK. These
	# semantic contacts therefore sample final modified feet, not pre-IK bones.
	_skeleton.skeleton_updated.connect(_update_final_skeleton_attachments)


func _update_final_skeleton_attachments() -> void:
	_update_foot_contact_anchors()
	_update_held_mainsheet()


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
	# In a settled sailing stance one hand encloses the extension and the other
	# encloses the mainsheet. Both remain closed through the adjacent-grip tack
	# exchange instead of leaving the sheet hand visibly open.
	var tiller_grip := 1.0
	var left_grip := tiller_grip if _tiller_is_left else _sheet_hand_grip_amount
	var right_grip := _sheet_hand_grip_amount if _tiller_is_left else tiller_grip
	var left_assist := _sheet_assist_grip_amount if _tiller_is_left else 0.0
	var right_assist := _sheet_assist_grip_amount if not _tiller_is_left else 0.0
	if _hand_exchange_amount > 0.05:
		left_grip = 1.0
		right_grip = 1.0
		left_assist = 0.0
		right_assist = 0.0
	_apply_hand_grip_pose(
		"Left",
		left_grip,
		left_assist,
		_control_hand_tiller_weight(_left_hand_bone)
	)
	_apply_hand_grip_pose(
		"Right",
		right_grip,
		right_assist,
		_control_hand_tiller_weight(_right_hand_bone)
	)


func _apply_hand_grip_pose(
	side: String,
	grip_amount: float,
	assist_amount: float = 0.0,
	tiller_weight: float = 1.0
) -> void:
	var amount := clampf(grip_amount, 0.0, 1.0)
	var assist := clampf(assist_amount, 0.0, 1.0)
	var tiller_profile := smoothstep(0.0, 1.0, clampf(tiller_weight, 0.0, 1.0))
	# The imported fingers already carry roughly 77 degrees of PIP flexion.
	# Adding another 88 degrees curled the index through a full loop and back out
	# through the dorsum. Apply only the missing flexion and use a small natural
	# cascade from index to little finger instead of forcing four identical fists.
	var tiller_finger_angles := {
		"Index": Vector3(deg_to_rad(62.0), deg_to_rad(2.0), deg_to_rad(26.0)),
		"Middle": Vector3(deg_to_rad(66.0), deg_to_rad(4.0), deg_to_rad(30.0)),
		"Ring": Vector3(deg_to_rad(69.0), deg_to_rad(6.0), deg_to_rad(33.0)),
		"Little": Vector3(deg_to_rad(72.0), deg_to_rad(8.0), deg_to_rad(36.0)),
	}
	# The flexible sheet lies diagonally through the index/thumb channel rather
	# than across the full palm like the extension. A dedicated cascade closes
	# around that 10 mm line while retaining the imported PIP flexion.
	var sheet_finger_angles := {
		"Index": Vector3(deg_to_rad(62.0), deg_to_rad(2.0), deg_to_rad(26.0)),
		"Middle": Vector3(deg_to_rad(54.0), deg_to_rad(6.0), deg_to_rad(34.0)),
		"Ring": Vector3(deg_to_rad(50.0), deg_to_rad(8.0), deg_to_rad(36.0)),
		"Little": Vector3(deg_to_rad(48.0), deg_to_rad(10.0), deg_to_rad(38.0)),
	}
	for digit in ["Index", "Middle", "Ring", "Little"]:
		var sheet_angles: Vector3 = sheet_finger_angles[digit]
		var tiller_angles: Vector3 = tiller_finger_angles[digit]
		var digit_angles := sheet_angles.lerp(tiller_angles, tiller_profile)
		if digit == "Ring":
			digit_angles += Vector3(
				deg_to_rad(5.0),
				deg_to_rad(4.0),
				deg_to_rad(6.0)
			) * assist
		elif digit == "Little":
			digit_angles += Vector3(
				deg_to_rad(7.0),
				deg_to_rad(5.0),
				deg_to_rad(8.0)
			) * assist
		for segment_index in 3:
			var segment: String = ["Proximal", "Intermediate", "Distal"][segment_index]
			var bone_name: String = side + String(digit) + String(segment)
			_apply_finger_delta(
				bone_name,
				Vector3.RIGHT,
				float(digit_angles[segment_index]) * amount
			)
	var mirrored_sign := -1.0 if side == "Left" else 1.0
	var thumb_metacarpal := lerpf(
		mirrored_sign * deg_to_rad(40.0),
		mirrored_sign * deg_to_rad(35.0),
		tiller_profile
	)
	var thumb_proximal := lerpf(deg_to_rad(50.0), deg_to_rad(45.0), tiller_profile)
	var thumb_distal := lerpf(deg_to_rad(38.0), deg_to_rad(32.0), tiller_profile)
	_apply_finger_delta(
		side + "ThumbMetacarpal",
		Vector3.FORWARD,
		thumb_metacarpal * amount
	)
	_apply_finger_delta(
		side + "ThumbProximal",
		Vector3.RIGHT,
		(thumb_proximal + deg_to_rad(4.0) * assist) * amount
	)
	_apply_finger_delta(
		side + "ThumbDistal",
		Vector3.RIGHT,
		thumb_distal * amount
	)


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


func _update_seat_contact_anchor() -> void:
	if not is_instance_valid(_seat_contact_anchor) or _hips_bone < 0:
		return
	var hips_pose := _skeleton.get_bone_global_pose(_hips_bone)
	var source_contact_in_skeleton := hips_pose.origin
	var contact_world := _skeleton.to_global(source_contact_in_skeleton)
	var contact_boat := _boat.to_local(contact_world)
	contact_boat.y -= SEAT_CONTACT_BELOW_HIPS
	_seat_contact_anchor.global_position = _boat.to_global(contact_boat)


func _solve_seat_contact() -> void:
	if not is_instance_valid(_seat_contact_anchor):
		return
	var side := clampf(seat_side, -1.0, 1.0)
	var crossing_amount := 1.0 - absf(side)
	var hull := _boat.get_node_or_null("Hull") as IlcaHull
	var deck_sample_x := signf(side) * SEAT_CONTACT_LATERAL
	if is_zero_approx(deck_sample_x):
		deck_sample_x = SEAT_CONTACT_LATERAL
	var target_y := (
		hull.deck_y_at(deck_sample_x, SEAT_CONTACT_AFT)
		if is_instance_valid(hull)
		else 0.32
	)
	target_y += sin(crossing_amount * PI * 0.5) * TACK_CENTER_RISE
	var target_global := _boat.to_global(Vector3(
		side * SEAT_CONTACT_LATERAL,
		target_y,
		SEAT_CONTACT_AFT - (sin(_maneuver_crossing * PI) * MANEUVER_FORWARD_SHIFT if _maneuver_active else 0.0)
	))
	_pose_root.global_position += target_global - _seat_contact_anchor.global_position
	_update_seat_contact_anchor()


func _update_foot_contact_anchors() -> void:
	_update_foot_contact_anchor_pair(
		_left_foot_anchor,
		_left_toe_anchor,
		-1.0,
		_left_instep_anchor,
		_left_sole_anchor
	)
	_update_foot_contact_anchor_pair(
		_right_foot_anchor,
		_right_toe_anchor,
		1.0,
		_right_instep_anchor,
		_right_sole_anchor
	)


func _update_foot_contact_anchor_pair(
	foot_anchor: Node3D,
	toe_anchor: Node3D,
	foot_side: float,
	instep_anchor: Node3D,
	sole_anchor: Node3D
) -> void:
	if (
		not is_instance_valid(foot_anchor)
		or not is_instance_valid(toe_anchor)
		or not is_instance_valid(instep_anchor)
		or not is_instance_valid(sole_anchor)
	):
		return
	# The final contact modifier rotates the actual Foot/Toes subtree. Derive every
	# semantic contact from those rendered bones; a fabricated level shoe axis can
	# pass tests while the visible bare foot still sits above the strap.
	var ankle := foot_anchor.global_position
	var toe := toe_anchor.global_position
	var mid_foot := ankle.lerp(toe, FOOT_INSTEP_FRACTION)
	instep_anchor.global_position = mid_foot
	var sole_y := 0.045
	var sole_boat := _boat.to_local(mid_foot)
	sole_boat.y = sole_y
	sole_anchor.global_position = _boat.to_global(sole_boat)
	if not _foot_visuals_ready:
		return
	var boot := _left_foot_visual if foot_anchor == _left_foot_anchor else _right_foot_visual
	if is_instance_valid(boot):
		var boot_center := ankle.lerp(toe, 0.50)
		var boot_axis := toe - ankle
		var up := _boat.global_basis.y.normalized()
		boot.global_transform = Transform3D(
			Basis.looking_at(boot_axis.normalized(), up).orthonormalized(),
			boot_center
		)


func _create_sailing_boot(part_name: String) -> MeshInstance3D:
	var boot := MeshInstance3D.new()
	boot.name = part_name
	boot.mesh = _make_sailing_shoe_mesh()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.045, 0.055, 0.060)
	material.roughness = 0.94
	boot.material_override = material
	boot.layers = SHARED_BODY_LAYERS
	boot.visible = SHOW_SAILING_SHOES
	_skeleton.add_child(boot)
	return boot


func _make_sailing_shoe_mesh() -> ArrayMesh:
	# Five rounded stations create a low-profile neoprene sailing shoe instead
	# of a subdivided box. Local -Z runs heel-to-toe after Basis.looking_at().
	var stations := [
		[0.0, 0.034, 0.022],
		[0.18, 0.041, 0.019],
		[0.48, 0.045, 0.017],
		[0.78, 0.044, 0.015],
		[1.0, 0.032, 0.011],
	]
	var ring_segments := 10
	var rings: Array = []
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for station in stations:
		var amount := float(station[0])
		var half_width := float(station[1])
		var half_height := float(station[2])
		var ring := PackedVector3Array()
		for segment in ring_segments:
			var theta := TAU * float(segment) / float(ring_segments)
			ring.append(Vector3(
				cos(theta) * half_width,
				sin(theta) * half_height,
				lerpf(FOOT_RENDERED_LENGTH * 0.5, -FOOT_RENDERED_LENGTH * 0.5, amount)
			))
		rings.append(ring)

	for station_index in range(stations.size() - 1):
		var heelward: PackedVector3Array = rings[station_index]
		var toeward: PackedVector3Array = rings[station_index + 1]
		for segment in ring_segments:
			var next := (segment + 1) % ring_segments
			var outward := heelward[segment] + heelward[next] + toeward[next] + toeward[segment]
			outward.z = 0.0
			_add_clockwise_quad(
				surface,
				heelward[segment], heelward[next], toeward[next], toeward[segment],
				outward.normalized()
			)
	_append_shoe_cap(surface, rings[0], Vector3.BACK)
	_append_shoe_cap(surface, rings[rings.size() - 1], Vector3.FORWARD)
	surface.generate_normals()
	return surface.commit()


func _append_shoe_cap(
	surface: SurfaceTool,
	ring: PackedVector3Array,
	outward: Vector3
) -> void:
	var center := Vector3.ZERO
	for point in ring:
		center += point
	center /= float(ring.size())
	for segment in ring.size():
		var next := (segment + 1) % ring.size()
		_add_clockwise_triangle(surface, center, ring[segment], ring[next], outward)


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
	# This is an original, unbranded racing PFD. The reference is only the
	# contemporary low-volume silhouette: one smooth wrap, generous openings and
	# a shallow useful pocket. Product-specific panel lines and fittings are not
	# reproduced.
	var palette := _get_pfd_palette()
	var shell_color: Color = palette["shell"]
	var pocket_color: Color = palette["pocket"]
	var trim_color: Color = palette["trim"]
	var shell_material := _make_sailing_fabric_material(shell_color, 0.90)
	var pocket_material := _make_sailing_fabric_material(pocket_color, 0.93)
	var trim_material := _make_sailing_fabric_material(trim_color, 0.86)
	var cap_material := _make_sailing_fabric_material(Color(0.035, 0.060, 0.072), 0.82)

	var chest := _create_bone_attachment("BuoyancyAidAttachment", "UpperChest")
	chest.visible = SHOW_PFD
	_make_pfd_shell(chest, shell_material, SHARED_BODY_LAYERS)
	_make_pfd_front_patch(
		"PfdFrontPocket",
		chest,
		pocket_material,
		SHARED_BODY_LAYERS,
		-0.145,
		-0.045,
		0.122,
		0.137,
		0.006
	)
	_make_pfd_front_patch(
		"PfdPocketOpening",
		chest,
		trim_material,
		SHARED_BODY_LAYERS,
		-0.052,
		-0.038,
		0.132,
		0.132,
		0.008
	)

	var head := _create_bone_attachment("SailingCapAttachment", "Head")
	head.visible = SHOW_SAILING_CAP
	# The camera sits inside the head/cap volume; keep headwear exterior-only so
	# the first-person lens cannot render the underside of the crown or visor.
	_make_sailing_cap_crown(head, cap_material, EXTERIOR_RENDER_LAYER)
	_make_curved_cap_visor(head, cap_material, EXTERIOR_RENDER_LAYER)


func _get_pfd_palette() -> Dictionary:
	match pfd_color_preset:
		PfdColorPreset.BLACK:
			return {
				"shell": Color(0.035, 0.043, 0.048),
				"pocket": Color(0.105, 0.118, 0.122),
				"trim": Color(0.58, 0.69, 0.70),
			}
		PfdColorPreset.GREY:
			return {
				"shell": Color(0.335, 0.365, 0.372),
				"pocket": Color(0.115, 0.132, 0.138),
				"trim": Color(0.78, 0.82, 0.80),
			}
		PfdColorPreset.RED:
			return {
				"shell": Color(0.50, 0.060, 0.050),
				"pocket": Color(0.145, 0.025, 0.025),
				"trim": Color(0.92, 0.42, 0.27),
			}
		PfdColorPreset.BLUE:
			return {
				"shell": Color(0.035, 0.185, 0.305),
				"pocket": Color(0.025, 0.070, 0.105),
				"trim": Color(0.50, 0.76, 0.82),
			}
		_:
			return {
				"shell": Color(0.035, 0.185, 0.305),
				"pocket": Color(0.025, 0.070, 0.105),
				"trim": Color(0.50, 0.76, 0.82),
			}


func _make_sailing_fabric_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.0
	material.roughness = roughness
	material.cull_mode = BaseMaterial3D.CULL_BACK
	return material


func apply_pfd_color_preset(preset: int) -> void:
	pfd_color_preset = clampi(preset, PfdColorPreset.BLACK, PfdColorPreset.RED)
	if not is_instance_valid(_skeleton):
		return
	var attachment := _skeleton.get_node_or_null("BuoyancyAidAttachment")
	if not is_instance_valid(attachment):
		return
	var palette := _get_pfd_palette()
	for entry in [
		["PfdShell", "shell"],
		["PfdFrontPocket", "pocket"],
		["PfdPocketOpening", "trim"],
	]:
		var part := attachment.get_node_or_null(entry[0]) as MeshInstance3D
		if is_instance_valid(part) and part.material_override is StandardMaterial3D:
			(part.material_override as StandardMaterial3D).albedo_color = palette[entry[1]]


func _make_pfd_shell(parent: Node3D, material: Material, layers: int) -> MeshInstance3D:
	# Super-elliptic rings sit close to the existing torso and avoid the swollen
	# look of stacked foam boxes. Both shoulder bridges are committed into this
	# same mesh, so front, back and sides read as one garment.
	var levels := PackedFloat32Array([-0.195, -0.150, -0.045, 0.055, 0.100])
	var widths := PackedFloat32Array([0.135, 0.158, 0.177, 0.169, 0.145])
	var front_depths := PackedFloat32Array([0.105, 0.116, 0.124, 0.118, 0.108])
	var back_depths := PackedFloat32Array([0.092, 0.103, 0.110, 0.103, 0.094])
	var rings: Array = []
	var ring_segments := 28
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	for level_index in levels.size():
		var ring := PackedVector3Array()
		for segment in ring_segments:
			var theta := TAU * float(segment) / float(ring_segments)
			ring.append(_pfd_ring_point(
				theta,
				levels[level_index],
				widths[level_index],
				front_depths[level_index],
				back_depths[level_index]
			))
		rings.append(ring)

	for level_index in range(levels.size() - 1):
		var lower: PackedVector3Array = rings[level_index]
		var upper: PackedVector3Array = rings[level_index + 1]
		for segment in ring_segments:
			var next := (segment + 1) % ring_segments
			var outward := lower[segment] + lower[next] + upper[next] + upper[segment]
			outward.y = 0.0
			_add_clockwise_quad(
				surface,
				lower[segment], lower[next], upper[next], upper[segment],
				outward.normalized()
			)

	_append_pfd_edge_band(surface, rings[0], Vector3.DOWN)
	_append_pfd_edge_band(surface, rings[rings.size() - 1], Vector3.UP)
	_append_pfd_shoulder_bridge(surface, -0.098)
	_append_pfd_shoulder_bridge(surface, 0.098)

	surface.generate_normals()
	var shell := MeshInstance3D.new()
	shell.name = "PfdShell"
	shell.mesh = surface.commit()
	shell.material_override = material
	shell.layers = layers
	parent.add_child(shell)
	return shell


func _pfd_ring_point(
	theta: float,
	y: float,
	half_width: float,
	front_depth: float,
	back_depth: float
) -> Vector3:
	var side := sin(theta)
	var fore_aft := cos(theta)
	var exponent := 2.0 / 3.0
	var depth := front_depth if fore_aft >= 0.0 else back_depth
	return Vector3(
		half_width * signf(side) * pow(absf(side), exponent),
		y,
		depth * signf(fore_aft) * pow(absf(fore_aft), exponent)
	)


func _append_pfd_edge_band(
	surface: SurfaceTool,
	outer_ring: PackedVector3Array,
	outward: Vector3
) -> void:
	var inner_ring := PackedVector3Array()
	for point in outer_ring:
		inner_ring.append(Vector3(point.x * 0.93, point.y - outward.y * 0.004, point.z * 0.93))
	for segment in outer_ring.size():
		var next := (segment + 1) % outer_ring.size()
		_add_clockwise_quad(
			surface,
			outer_ring[segment], outer_ring[next], inner_ring[next], inner_ring[segment],
			outward
		)


func _append_pfd_shoulder_bridge(surface: SurfaceTool, x_center: float) -> void:
	var segment_count := 8
	var half_width := 0.036
	var half_thickness := 0.006
	var upper_left := PackedVector3Array()
	var upper_right := PackedVector3Array()
	var lower_left := PackedVector3Array()
	var lower_right := PackedVector3Array()
	var normals := PackedVector3Array()

	for segment in range(segment_count + 1):
		var amount := float(segment) / float(segment_count)
		var center := Vector3(
			x_center,
			0.078 + sin(amount * PI) * 0.130,
			lerpf(0.105, -0.095, amount)
		)
		var tangent := Vector3(
			0.0,
			cos(amount * PI) * PI * 0.130,
			-0.200
		).normalized()
		var normal := Vector3(0.0, -tangent.z, tangent.y).normalized()
		var thickness_offset := normal * half_thickness
		var left_offset := Vector3.LEFT * half_width
		var right_offset := Vector3.RIGHT * half_width
		upper_left.append(center + left_offset + thickness_offset)
		upper_right.append(center + right_offset + thickness_offset)
		lower_left.append(center + left_offset - thickness_offset)
		lower_right.append(center + right_offset - thickness_offset)
		normals.append(normal)

	for segment in segment_count:
		var next := segment + 1
		var top_normal := (normals[segment] + normals[next]).normalized()
		_add_clockwise_quad(
			surface,
			upper_left[segment], upper_left[next], upper_right[next], upper_right[segment],
			top_normal
		)
		_add_clockwise_quad(
			surface,
			lower_right[segment], lower_right[next], lower_left[next], lower_left[segment],
			-top_normal
		)
		_add_clockwise_quad(
			surface,
			lower_left[segment], lower_left[next], upper_left[next], upper_left[segment],
			Vector3.LEFT
		)
		_add_clockwise_quad(
			surface,
			upper_right[segment], upper_right[next], lower_right[next], lower_right[segment],
			Vector3.RIGHT
		)


func _make_pfd_front_patch(
	part_name: String,
	parent: Node3D,
	material: Material,
	layers: int,
	bottom_y: float,
	top_y: float,
	bottom_half_width: float,
	top_half_width: float,
	projection: float
) -> MeshInstance3D:
	var columns := 10
	var rows := 3
	var grid: Array = []
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row_index in range(rows + 1):
		var vertical_amount := float(row_index) / float(rows)
		var y := lerpf(bottom_y, top_y, vertical_amount)
		var half_width := lerpf(bottom_half_width, top_half_width, vertical_amount)
		var row := PackedVector3Array()
		for column in range(columns + 1):
			var x := lerpf(-half_width, half_width, float(column) / float(columns))
			row.append(Vector3(x, y, _pfd_front_surface_z(x, y) + projection))
		grid.append(row)

	for row_index in rows:
		var lower: PackedVector3Array = grid[row_index]
		var upper: PackedVector3Array = grid[row_index + 1]
		for column in columns:
			_add_clockwise_quad(
				surface,
				lower[column], lower[column + 1], upper[column + 1], upper[column],
				Vector3.BACK
			)

	surface.generate_normals()
	var patch := MeshInstance3D.new()
	patch.name = part_name
	patch.mesh = surface.commit()
	patch.material_override = material
	patch.layers = layers
	parent.add_child(patch)
	return patch


func _pfd_front_surface_z(x: float, y: float) -> float:
	var torso_amount := clampf(inverse_lerp(-0.150, -0.045, y), 0.0, 1.0)
	var upper_amount := clampf(inverse_lerp(-0.045, 0.100, y), 0.0, 1.0)
	var half_width := lerpf(0.158, 0.177, torso_amount)
	var depth := lerpf(0.116, 0.124, torso_amount)
	if y > -0.045:
		half_width = lerpf(0.177, 0.145, upper_amount)
		depth = lerpf(0.124, 0.108, upper_amount)
	var lateral := clampf(absf(x) / half_width, 0.0, 1.0)
	return depth * pow(maxf(0.0, 1.0 - pow(lateral, 3.0)), 1.0 / 3.0)


func _make_sailing_cap_crown(
	parent: Node3D,
	material: Material,
	layers: int
) -> MeshInstance3D:
	var radial_segments := 28
	var ring_count := 7
	var crown_base_y := 0.105
	var crown_height := 0.130
	var rings: Array = []
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	for ring_index in range(1, ring_count + 1):
		var polar := float(ring_index) / float(ring_count) * PI * 0.5
		var radius_amount := sin(polar)
		var y := crown_base_y + cos(polar) * crown_height
		var ring := PackedVector3Array()
		for segment in radial_segments:
			var theta := TAU * float(segment) / float(radial_segments)
			ring.append(Vector3(
				cos(theta) * 0.122 * radius_amount,
				y,
				sin(theta) * 0.114 * radius_amount
			))
		rings.append(ring)

	var top := Vector3(0.0, crown_base_y + crown_height, 0.0)
	var first_ring: PackedVector3Array = rings[0]
	for segment in radial_segments:
		var next := (segment + 1) % radial_segments
		var outward := (top + first_ring[segment] + first_ring[next]) / 3.0
		outward.y -= crown_base_y
		_add_clockwise_triangle(surface, top, first_ring[segment], first_ring[next], outward.normalized())

	for ring_index in range(rings.size() - 1):
		var upper: PackedVector3Array = rings[ring_index]
		var lower: PackedVector3Array = rings[ring_index + 1]
		for segment in radial_segments:
			var next := (segment + 1) % radial_segments
			var outward := upper[segment] + upper[next] + lower[next] + lower[segment]
			outward.y -= crown_base_y * 4.0
			_add_clockwise_quad(
				surface,
				upper[segment], upper[next], lower[next], lower[segment],
				outward.normalized()
			)

	var bottom_ring: PackedVector3Array = rings[rings.size() - 1]
	_append_cap_hem(surface, bottom_ring)
	surface.generate_normals()
	var crown := MeshInstance3D.new()
	crown.name = "SailingCap"
	crown.mesh = surface.commit()
	crown.material_override = material
	crown.layers = layers
	parent.add_child(crown)
	return crown


func _append_cap_hem(surface: SurfaceTool, outer_ring: PackedVector3Array) -> void:
	var inner_ring := PackedVector3Array()
	for point in outer_ring:
		inner_ring.append(Vector3(point.x * 0.94, point.y + 0.004, point.z * 0.94))
	for segment in outer_ring.size():
		var next := (segment + 1) % outer_ring.size()
		_add_clockwise_quad(
			surface,
			outer_ring[segment], outer_ring[next], inner_ring[next], inner_ring[segment],
			Vector3.DOWN
		)


func _make_curved_cap_visor(
	parent: Node3D,
	material: Material,
	layers: int
) -> MeshInstance3D:
	var length_segments := 6
	var width_segments := 12
	var top_rows: Array = []
	var bottom_rows: Array = []
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	for length_index in range(length_segments + 1):
		var length_amount := float(length_index) / float(length_segments)
		var half_width := lerpf(0.096, 0.080, length_amount)
		var top_row := PackedVector3Array()
		var bottom_row := PackedVector3Array()
		for width_index in range(width_segments + 1):
			var lateral := lerpf(-1.0, 1.0, float(width_index) / float(width_segments))
			var x := lateral * half_width
			var z := lerpf(0.065, 0.205, length_amount)
			z += 0.010 * length_amount * (1.0 - lateral * lateral)
			var y := 0.116 - 0.020 * length_amount
			y += sin(length_amount * PI) * 0.005 - lateral * lateral * 0.014
			var top_point := Vector3(x, y, z)
			top_row.append(top_point)
			bottom_row.append(top_point + Vector3.DOWN * 0.007)
		top_rows.append(top_row)
		bottom_rows.append(bottom_row)

	for length_index in length_segments:
		var next_length := length_index + 1
		var top_near: PackedVector3Array = top_rows[length_index]
		var top_far: PackedVector3Array = top_rows[next_length]
		var bottom_near: PackedVector3Array = bottom_rows[length_index]
		var bottom_far: PackedVector3Array = bottom_rows[next_length]
		for width_index in width_segments:
			var next_width := width_index + 1
			_add_clockwise_quad(
				surface,
				top_near[width_index], top_far[width_index],
				top_far[next_width], top_near[next_width],
				Vector3.UP
			)
			_add_clockwise_quad(
				surface,
				bottom_near[next_width], bottom_far[next_width],
				bottom_far[width_index], bottom_near[width_index],
				Vector3.DOWN
			)

	for length_index in length_segments:
		var next_length := length_index + 1
		var top_near: PackedVector3Array = top_rows[length_index]
		var top_far: PackedVector3Array = top_rows[next_length]
		var bottom_near: PackedVector3Array = bottom_rows[length_index]
		var bottom_far: PackedVector3Array = bottom_rows[next_length]
		_add_clockwise_quad(
			surface,
			top_near[0], bottom_near[0], bottom_far[0], top_far[0],
			Vector3.LEFT
		)
		_add_clockwise_quad(
			surface,
			top_far[width_segments], bottom_far[width_segments],
			bottom_near[width_segments], top_near[width_segments],
			Vector3.RIGHT
		)

	var top_front: PackedVector3Array = top_rows[length_segments]
	var bottom_front: PackedVector3Array = bottom_rows[length_segments]
	for width_index in width_segments:
		var next_width := width_index + 1
		_add_clockwise_quad(
			surface,
			top_front[width_index], bottom_front[width_index],
			bottom_front[next_width], top_front[next_width],
			Vector3.BACK
		)

	surface.generate_normals()
	var visor := MeshInstance3D.new()
	visor.name = "CapVisor"
	visor.mesh = surface.commit()
	visor.material_override = material
	visor.layers = layers
	parent.add_child(visor)
	return visor


func _add_clockwise_quad(
	surface: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	outward: Vector3
) -> void:
	_add_clockwise_triangle(surface, a, b, c, outward)
	_add_clockwise_triangle(surface, a, c, d, outward)


func _add_clockwise_triangle(
	surface: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	outward: Vector3
) -> void:
	# Godot's front face uses clockwise winding. Reverse a conventional
	# outward-normal triangle when necessary before SurfaceTool generates normals.
	if (b - a).cross(c - a).dot(outward) > 0.0:
		surface.add_vertex(a)
		surface.add_vertex(c)
		surface.add_vertex(b)
	else:
		surface.add_vertex(a)
		surface.add_vertex(b)
		surface.add_vertex(c)


func _resolve_control_hands(update_exchange_state: bool = true) -> void:
	# Runtime passes false because _process owns the one authoritative state
	# advance. The default keeps manual pose tools/tests deterministic when they
	# set seat_side without running a frame.
	if update_exchange_state:
		_update_hand_exchange_state()
	# Anatomical hands remain continuous. Their control roles switch only while
	# both hands overlap on the extension at the handover point.
	if _tiller_is_left:
		_tiller_hand_anchor = _left_hand_anchor
		_sheet_hand_anchor = _right_hand_anchor
		_sheet_grip_anchor = _right_sheet_grip_anchor
	else:
		_tiller_hand_anchor = _right_hand_anchor
		_sheet_hand_anchor = _left_hand_anchor
		_sheet_grip_anchor = _left_sheet_grip_anchor


func _control_hand_tiller_weight(hand_bone: int) -> float:
	# Acquisition and release are deliberately asymmetric in route progress. The
	# previous sin(progress*PI) envelope kept both hands at full tiller ownership
	# until progress 0.886, but EXIT_ALIGN gates the body at 0.72. If the outgoing
	# shoulder could not reach the new-side grip, it therefore had to move before it
	# could release while movement itself waited for that release: a hard deadlock.
	# The incoming hand is fully attached before the midpoint role switch; the
	# outgoing hand is fully released before exit alignment begins. The same weight
	# continues to own palm position, wrist orientation, fingers and elbow scoring.
	var progress := clampf(_hand_exchange_progress, 0.0, 1.0)
	var auxiliary_weight := 0.0
	if progress <= 0.5:
		auxiliary_weight = smoothstep(
			0.18 if _maneuver_active else HANDOVER_INCOMING_ACQUIRE_START,
			HANDOVER_INCOMING_ACQUIRE_END,
			progress
		)
	else:
		auxiliary_weight = 1.0 - smoothstep(
			HANDOVER_OUTGOING_RELEASE_START,
			0.80 if _maneuver_active else HANDOVER_OUTGOING_RELEASE_END,
			progress
		)
	if hand_bone == _left_hand_bone:
		return 1.0 if _tiller_is_left else auxiliary_weight
	if hand_bone == _right_hand_bone:
		return auxiliary_weight if _tiller_is_left else 1.0
	return 0.0


func _update_leg_ik_targets() -> void:
	if (
		not is_instance_valid(_left_foot_target)
		or not is_instance_valid(_right_foot_target)
		or not is_instance_valid(_left_foot_pole)
		or not is_instance_valid(_right_foot_pole)
	):
		return
	var side_ratio := clampf((seat_side + 1.0) * 0.5, 0.0, 1.0)
	if _maneuver_active:
		_update_maneuver_foot_targets()
		return
	var left_target_z := lerpf(FOOT_TARGET_FORWARD_Z, FOOT_TARGET_AFT_Z, side_ratio)
	var right_target_z := lerpf(FOOT_TARGET_AFT_Z, FOOT_TARGET_FORWARD_Z, side_ratio)
	var clamped_side := clampf(seat_side, -1.0, 1.0)
	var crossing_amount := 1.0 - absf(clamped_side)
	# Multiplying by the continuous side keeps both targets on the seated side
	# while letting them meet at x=0 through the tack; signf() would jump 11 cm.
	var ankle_x := clamped_side * lerpf(
		FOOT_TARGET_OUTBOARD_X,
		0.055,
		crossing_amount
	)
	var pole_x := clamped_side * lerpf(
		FOOT_POLE_OUTBOARD_X,
		0.12,
		crossing_amount
	)
	# Keep the feet anatomically distinct during the crouched centre crossing.
	# They exchange their stagger without ever occupying the same IK endpoint.
	var left_ankle_x := ankle_x - 0.045 * crossing_amount
	var right_ankle_x := ankle_x + 0.045 * crossing_amount
	var left_pole_x := pole_x - 0.075 * crossing_amount
	var right_pole_x := pole_x + 0.075 * crossing_amount
	_left_foot_target.global_position = _boat.to_global(Vector3(
		left_ankle_x,
		FOOT_ANKLE_HEIGHT,
		left_target_z
	))
	_right_foot_target.global_position = _boat.to_global(Vector3(
		right_ankle_x,
		FOOT_ANKLE_HEIGHT,
		right_target_z
	))
	_left_foot_pole.global_position = _boat.to_global(Vector3(
		left_pole_x,
		FOOT_POLE_HEIGHT,
		left_target_z
	))
	_right_foot_pole.global_position = _boat.to_global(Vector3(
		right_pole_x,
		FOOT_POLE_HEIGHT,
		right_target_z
	))


func _update_maneuver_foot_targets() -> void:
	var body_basis := Basis(Vector3.UP, _maneuver_heading)
	for is_left in [true, false]:
		var foot_sign := -1.0 if is_left else 1.0
		var lead: bool = bool(is_left) == (_maneuver_start_side < 0.0)
		var step_start := 0.04 if lead else 0.34
		var step_end := 0.64 if lead else 0.96
		var step_progress := smoothstep(step_start, step_end, _maneuver_crossing)
		var foot_side := lerpf(_maneuver_start_side, _maneuver_target_side, step_progress)
		var stagger := (foot_side + 1.0) * 0.5
		var target_z := lerpf(
			FOOT_TARGET_FORWARD_Z if is_left else FOOT_TARGET_AFT_Z,
			FOOT_TARGET_AFT_Z if is_left else FOOT_TARGET_FORWARD_Z,
			stagger
		)
		var swing := sin(step_progress * PI)
		var ankle := Vector3(
			foot_side * FOOT_TARGET_OUTBOARD_X + body_basis.x.x * foot_sign * 0.065 * swing,
			FOOT_ANKLE_HEIGHT + 0.045 * swing,
			target_z - MANEUVER_FORWARD_SHIFT * 0.65 * swing
		)
		var target := _left_foot_target if is_left else _right_foot_target
		var pole := _left_foot_pole if is_left else _right_foot_pole
		target.global_position = _boat.to_global(ankle)
		var hip_index := _left_upper_leg_bone if is_left else _right_upper_leg_bone
		var hip := _boat.to_local((_skeleton.global_transform * _skeleton.get_bone_global_pose(hip_index)).origin)
		var axis := (ankle - hip).normalized()
		var bend := body_basis.z + body_basis.x * foot_sign * 0.12
		bend = (bend - axis * bend.dot(axis)).normalized()
		var moving_pole := hip.lerp(ankle, 0.5) + bend * 0.45
		var seated_pole := Vector3(foot_side * FOOT_POLE_OUTBOARD_X, FOOT_POLE_HEIGHT, target_z)
		pole.global_position = _boat.to_global(seated_pole.lerp(moving_pole, _maneuver_duck))


func _update_hand_exchange_state() -> void:
	if _maneuver_active:
		return
	var side_delta := seat_side - _last_hand_exchange_side
	var exchange_requested := absf(side_delta) > 0.0001
	if exchange_requested and not _sheet_motion_is_safe_for_tack():
		_sheet_tack_interlock_requested = true
		_hand_exchange_progress = 0.0
		_hand_exchange_amount = 0.0
		return
	if absf(side_delta) > 0.0001:
		_hand_exchange_direction = signf(side_delta)
	_last_hand_exchange_side = seat_side

	var exchange_progress := 0.0
	if not is_zero_approx(_hand_exchange_direction):
		# The authored route phases below already use smoothstep easing. Applying a
		# second smoothstep here left the extension almost stationary while the torso
		# had begun crossing, so the tiller shoulder passed over the grip and folded
		# the arm. Keep the state progress linear and let each physical route segment
		# own its easing exactly once.
		exchange_progress = clampf(
			inverse_lerp(
				-HANDOVER_END_SIDE,
				HANDOVER_END_SIDE,
				seat_side * _hand_exchange_direction
			),
			0.0,
			1.0
		)

	_hand_exchange_progress = exchange_progress
	_hand_exchange_amount = sin(exchange_progress * PI)
	if exchange_progress >= 0.5:
		_tiller_is_left = _hand_exchange_direction > 0.0
	elif absf(seat_side) >= HANDOVER_END_SIDE and is_zero_approx(_hand_exchange_amount):
		_tiller_is_left = seat_side > 0.0


func tiller_control_target_boat_position(rudder_input: float) -> Vector3:
	var side := clampf(seat_side, -1.0, 1.0)
	var steering_side := signf(side)
	if is_zero_approx(steering_side):
		steering_side = 1.0 if _hand_exchange_direction > 0.0 else -1.0
	# Steering displacement is expressed in the seated sailor's mirrored frame.
	# This keeps (port,+rudder) and (starboard,-rudder) anatomically symmetric.
	# The ILCA extension contact stays on the same reachable, collision-free
	# working vector. Rudder input still rotates the connected tiller/rudder; a
	# later art pass can add a smaller measured wrist arc without changing shaft
	# hemisphere or breaking contact.
	var extension_joint := _boat.to_local(_tiller_extension_pivot.global_position)
	var normal_direction := TILLER_NORMAL_GRIP_DIRECTION
	normal_direction.x *= steering_side
	normal_direction = normal_direction.normalized()
	# A seated, non-hiking sailor holds close to the universal joint because the
	# cockpit is narrow. Rudder input rotates the tiller itself; it must not also
	# force the hand toward the far end of the extension. A later hiking-state
	# signal can interpolate toward NORMAL_FAR_HAND_DISTANCE explicitly.
	var hand_distance := _boat.TILLER_EXTENSION_UPRIGHT_HAND_DISTANCE
	if absf(rudder_input) >= 0.0001:
		# The visible rudder itself already rotates the universal-joint mount. Keep
		# the sailor's working grip in the same forward/chest hemisphere instead of
		# sending one extreme behind the torso, which forces the forearm through it.
		var steering_direction := Vector3(
			steering_side * TILLER_NORMAL_GRIP_DIRECTION.x,
			TILLER_NORMAL_GRIP_DIRECTION.y,
			TILLER_NORMAL_GRIP_DIRECTION.z
		).normalized()
		normal_direction = steering_direction
	var normal_target := (
		extension_joint
		+ normal_direction * hand_distance
	)
	if _maneuver_active:
		var transfer_target := Vector3(
			seat_side * MANEUVER_CONTROL_LATERAL,
			MANEUVER_CONTROL_HEIGHT,
			MANEUVER_CONTROL_AFT
		)
		return normal_target.lerp(transfer_target, _maneuver_duck)
	var new_side := _hand_exchange_direction
	if is_zero_approx(new_side):
		new_side = steering_side
	# Enter the aft clearance route on the side that currently owns the
	# extension. Using `new_side` here sent the target across the entire cockpit
	# as soon as handover progress became non-zero, before either the sailor or
	# the rubber joint had time to move.
	var entry_side := steering_side
	var entry_clearance_target := Vector3(
		entry_side * HANDOVER_CLEARANCE_LATERAL,
		HANDOVER_CLEARANCE_HEIGHT,
		HANDOVER_CLEARANCE_AFT
	)
	var new_clearance_target := Vector3(
		new_side * HANDOVER_CLEARANCE_LATERAL,
		HANDOVER_CLEARANCE_HEIGHT,
		HANDOVER_CLEARANCE_AFT
	)
	var behind_back_target := Vector3(
		new_side * HANDOVER_BEHIND_LATERAL,
		HANDOVER_BEHIND_HEIGHT,
		HANDOVER_BEHIND_AFT
	)
	var progress := clampf(_hand_exchange_progress, 0.0, 1.0)
	if _tack_entry_preposition_active:
		return entry_clearance_target
	if progress <= 0.0 or _hand_exchange_amount <= 0.0:
		return normal_target
	# Move the fixed 1.10 m shaft around the aft/upper hemisphere in distinct
	# phases. A single front-side Bezier chord cuts straight through the sailor.
	if progress < 0.28:
		# Entry was pre-positioned while the body was still seated. Hold that safe
		# pair through the first body movement instead of reversing toward normal.
		return entry_clearance_target
	if progress < 0.50:
		return entry_clearance_target.lerp(
			behind_back_target,
			smoothstep(0.28, 0.50, progress)
		)
	if progress < 0.72:
		return behind_back_target.lerp(
			new_clearance_target,
			smoothstep(0.50, 0.72, progress)
		)
	return new_clearance_target.lerp(
		normal_target,
		smoothstep(0.72, 1.0, progress)
	)


func normalized_rudder_input() -> float:
	return clampf(_boat.sailing_command.rudder, -1.0, 1.0)


func tiller_handover_entry_preposition_requested() -> bool:
	return _tack_entry_preposition_active


func advance_sheet_handling(delta: float) -> void:
	_update_sheet_hand_motion(delta)


func _update_sheet_hand_motion(delta: float) -> void:
	var state := _boat.get_sailing_state()
	var sheet_position := state.sheet_position
	var sheet_delta := _boat.sailing_command.sheet_delta
	var can_sheet_in := sheet_delta < -0.01 and sheet_position > 0.0001
	var can_sheet_out := sheet_delta > 0.01 and sheet_position < 0.9999
	var requested_mode := 0
	if _hand_exchange_amount <= 0.05 and not _sheet_tack_interlock_requested:
		if can_sheet_in:
			requested_mode = -1
		elif can_sheet_out:
			requested_mode = 1
	_update_sheet_motion_phase(clampf(delta, 0.0, 0.10), requested_mode)
	var motion_active := _sheet_motion_phase != SheetMotionPhase.IDLE
	var target_weight := 1.0 if motion_active else 0.0
	_sheet_motion_weight = move_toward(
		_sheet_motion_weight,
		target_weight,
		SHEET_MOTION_RESPONSE * clampf(delta, 0.0, 0.10)
	)
	_update_sheet_contact_weights(clampf(delta, 0.0, 0.10))
	_last_sheet_position = sheet_position


func _update_sheet_motion_phase(delta: float, requested_mode: int) -> void:
	# Sheet-in is a five-stage hand-over-hand cycle. Once the extension hand has
	# accepted load, finish the hand-back even if W is released or reversed;
	# otherwise both hands could let go at the same time. Sheet-out is deliberately
	# not the reverse animation: the primary hand stays on the line and meters a
	# controlled slip against the ratchet block.
	var remaining := delta
	_sheet_effective_motion_fraction = 0.0
	_sheet_pending_mode = requested_mode
	for _transition_guard in 8:
		match _sheet_motion_phase:
			SheetMotionPhase.IDLE:
				if requested_mode < 0:
					_enter_sheet_motion_phase(SheetMotionPhase.PULL)
					continue
				if requested_mode > 0:
					_enter_sheet_motion_phase(SheetMotionPhase.EASE)
					continue
				remaining = 0.0
			SheetMotionPhase.HOLD:
				if requested_mode < 0:
					_enter_sheet_motion_phase(SheetMotionPhase.PULL)
					continue
				if requested_mode > 0:
					_enter_sheet_motion_phase(SheetMotionPhase.EASE)
					continue
				remaining = 0.0
			SheetMotionPhase.PULL:
				if requested_mode >= 0:
					_enter_sheet_motion_phase(
						SheetMotionPhase.EASE
						if requested_mode > 0
						else SheetMotionPhase.HOLD
					)
					continue
				var before_pull := remaining
				remaining = _consume_sheet_phase_time(remaining, SHEET_PULL_DURATION)
				if delta > 0.000001:
					_sheet_effective_motion_fraction += (before_pull - remaining) / delta
				if _sheet_phase_progress >= 1.0:
					_enter_sheet_motion_phase(SheetMotionPhase.ASSIST_OVERLAP)
					continue
			SheetMotionPhase.ASSIST_OVERLAP:
				# Before the extension hand has fully accepted the line, the primary
				# hand is still closed and may safely cancel or reverse. Only the
				# committed release/reach phases must complete their hand-back.
				if requested_mode >= 0:
					_enter_sheet_motion_phase(
						SheetMotionPhase.EASE
						if requested_mode > 0
						else SheetMotionPhase.HOLD
					)
					continue
				remaining = _consume_sheet_phase_time(
					remaining,
					SHEET_ASSIST_ACQUIRE_DURATION
				)
				if _sheet_phase_progress >= 1.0:
					_enter_sheet_motion_phase(SheetMotionPhase.PRIMARY_RELEASE_REACH)
					continue
			SheetMotionPhase.PRIMARY_RELEASE_REACH:
				remaining = _consume_sheet_phase_time(
					remaining,
					SHEET_PRIMARY_REACH_DURATION
				)
				if _sheet_phase_progress >= 1.0:
					_enter_sheet_motion_phase(SheetMotionPhase.REGRIP)
					continue
			SheetMotionPhase.REGRIP:
				remaining = _consume_sheet_phase_time(remaining, SHEET_REGRIP_DURATION)
				if _sheet_phase_progress >= 1.0:
					_enter_sheet_motion_phase(SheetMotionPhase.ASSIST_RELEASE)
					continue
			SheetMotionPhase.ASSIST_RELEASE:
				remaining = _consume_sheet_phase_time(
					remaining,
					SHEET_ASSIST_RELEASE_DURATION
				)
				if _sheet_phase_progress >= 1.0:
					if _sheet_pending_mode < 0 and requested_mode < 0:
						_enter_sheet_motion_phase(SheetMotionPhase.PULL)
					elif _sheet_pending_mode > 0 or requested_mode > 0:
						_enter_sheet_motion_phase(SheetMotionPhase.EASE)
					else:
						_enter_sheet_motion_phase(SheetMotionPhase.HOLD)
					continue
			SheetMotionPhase.EASE:
				if requested_mode < 0:
					_enter_sheet_motion_phase(SheetMotionPhase.PULL)
					continue
				if requested_mode == 0:
					_enter_sheet_motion_phase(SheetMotionPhase.HOLD)
					continue
				_sheet_phase_progress = minf(
					1.0,
					_sheet_phase_progress + remaining / 0.16
				)
				if delta > 0.000001:
					_sheet_effective_motion_fraction += remaining / delta
				remaining = 0.0
		if remaining <= 0.000001:
			break
	_sheet_stroke_amount = _sheet_phase_progress
	_update_sheet_hand_target_for_phase()


func _enter_sheet_motion_phase(phase: int) -> void:
	_update_sheet_hand_target_for_phase()
	_sheet_motion_phase = phase
	_sheet_phase_progress = 0.0
	# Start from the currently rendered/rebased target. In particular, a new W/S
	# cycle after a tack must not inherit the previous side's frozen HOLD X value.
	_sheet_phase_start_target_boat = sheet_control_target_boat_position()
	match phase:
		SheetMotionPhase.PULL, SheetMotionPhase.ASSIST_OVERLAP:
			_sheet_phase_end_target_boat = _sheet_transfer_target_boat()
		SheetMotionPhase.PRIMARY_RELEASE_REACH, SheetMotionPhase.REGRIP:
			_sheet_phase_end_target_boat = _sheet_reach_target_boat()
		SheetMotionPhase.ASSIST_RELEASE:
			# Once the primary has regripped, return it to the relaxed chest-front
			# working point while the extension hand lets go. Freezing HOLD at the
			# extreme reach left the next tack with an almost straight arm.
			_sheet_phase_end_target_boat = _sheet_power_target_boat()
		SheetMotionPhase.EASE:
			# Easing is controlled slip through a partially relaxed hand, not the
			# pull/regrip animation in reverse. Keep the current hand position so
			# repeated S taps neither jump across the cockpit nor creep block-ward.
			_sheet_phase_end_target_boat = _sheet_hand_target_boat
		SheetMotionPhase.IDLE:
			_sheet_phase_end_target_boat = _sheet_power_target_boat()
		_:
			_sheet_phase_end_target_boat = _sheet_hand_target_boat
	if phase == SheetMotionPhase.ASSIST_OVERLAP:
		_sheet_transfer_latched_length = maxf(0.0, held_mainsheet_loaded_length())
	elif phase in [
		SheetMotionPhase.PULL,
		SheetMotionPhase.IDLE,
	] or (
		phase in [SheetMotionPhase.EASE, SheetMotionPhase.HOLD]
		and _sheet_assist_grip_amount <= 0.001
	):
		_sheet_transfer_latched_length = -1.0
	if phase == SheetMotionPhase.HOLD or phase == SheetMotionPhase.IDLE:
		_sheet_pending_mode = 0


func _update_sheet_hand_target_for_phase() -> void:
	if _sheet_motion_phase == SheetMotionPhase.IDLE:
		_sheet_hand_target_boat = _sheet_power_target_boat()
		return
	if _sheet_motion_phase == SheetMotionPhase.HOLD:
		return
	var progress := smoothstep(0.0, 1.0, _sheet_phase_progress)
	_sheet_hand_target_boat = _sheet_phase_start_target_boat.lerp(
		_sheet_phase_end_target_boat,
		progress
	)


func _consume_sheet_phase_time(available: float, duration: float) -> float:
	if available <= 0.0:
		return 0.0
	var safe_duration := maxf(duration, 0.001)
	var required := (1.0 - _sheet_phase_progress) * safe_duration
	var consumed := minf(available, required)
	_sheet_phase_progress = minf(1.0, _sheet_phase_progress + consumed / safe_duration)
	return maxf(0.0, available - consumed)


func _update_sheet_contact_weights(delta: float) -> void:
	var progress := smoothstep(0.0, 1.0, _sheet_phase_progress)
	match _sheet_motion_phase:
		SheetMotionPhase.ASSIST_OVERLAP:
			_sheet_hand_grip_amount = 1.0
			_sheet_assist_grip_amount = progress
		SheetMotionPhase.PRIMARY_RELEASE_REACH:
			_sheet_hand_grip_amount = lerpf(1.0, SHEET_RELEASED_GRIP, progress)
			_sheet_assist_grip_amount = 1.0
		SheetMotionPhase.REGRIP:
			_sheet_hand_grip_amount = lerpf(SHEET_RELEASED_GRIP, 1.0, progress)
			_sheet_assist_grip_amount = 1.0
		SheetMotionPhase.ASSIST_RELEASE:
			_sheet_hand_grip_amount = 1.0
			_sheet_assist_grip_amount = 1.0 - progress
		SheetMotionPhase.EASE:
			_sheet_hand_grip_amount = lerpf(1.0, SHEET_EASE_GRIP, progress)
			# If W is reversed late in assist acquisition, the primary hand is still
			# securely closed. Let the extension hand relax over several frames rather
			# than teleporting the rope endpoint up to ten centimetres in one frame.
			_sheet_assist_grip_amount = move_toward(
				_sheet_assist_grip_amount,
				0.0,
				1.5 * delta
			)
		SheetMotionPhase.IDLE, SheetMotionPhase.HOLD:
			_sheet_hand_grip_amount = move_toward(
				_sheet_hand_grip_amount,
				1.0,
				6.0 * delta
			)
			_sheet_assist_grip_amount = move_toward(
				_sheet_assist_grip_amount,
				0.0,
				1.5 * delta
			)
		_:
			_sheet_hand_grip_amount = 1.0
			_sheet_assist_grip_amount = 0.0


func effective_sheet_delta(raw_sheet_delta: float) -> float:
	if _hand_exchange_amount > 0.05 or _sheet_tack_interlock_requested:
		return 0.0
	if raw_sheet_delta < -0.01:
		return raw_sheet_delta * clampf(_sheet_effective_motion_fraction, 0.0, 1.0)
	if raw_sheet_delta > 0.01:
		return raw_sheet_delta * clampf(_sheet_effective_motion_fraction, 0.0, 1.0)
	return 0.0


func _sheet_motion_is_safe_for_tack() -> bool:
	return _sheet_motion_phase in [
		SheetMotionPhase.IDLE,
		SheetMotionPhase.HOLD,
	]


func sheet_tack_interlock_active() -> bool:
	return _sheet_tack_interlock_requested


func sheet_control_target_boat_position() -> Vector3:
	var power_target := _sheet_power_target_boat()
	var motion_target := _sheet_hand_target_boat
	motion_target.x = _sheet_target_side() * absf(motion_target.x)
	var ordinary_target := power_target.lerp(motion_target, _sheet_motion_weight)
	if _maneuver_active:
		var body_basis := Basis(Vector3.UP, _maneuver_heading)
		var sheet_lateral := 0.20 if _tiller_is_left else -0.20
		var working_target := Vector3(
			seat_side * SEAT_CONTACT_LATERAL, SHEET_TARGET_HEIGHT,
			SEAT_CONTACT_AFT - sin(_maneuver_crossing * PI) * MANEUVER_FORWARD_SHIFT
		) + body_basis.z * 0.30 + body_basis.x * sheet_lateral
		return ordinary_target.lerp(working_target, _maneuver_duck)
	# Motion targets are stored as a positive lateral magnitude. Reapply the
	# current continuous seat side at read time so HOLD cannot retain the old
	# tack's absolute X coordinate and fold the sheet arm across the body.
	return ordinary_target


func _sheet_target_side() -> float:
	# Crossing through x=0 is physically continuous. The previous +/-0.15 floor
	# jumped the sheet target about nine centimetres as the tack crossed centre.
	return clampf(seat_side, -1.0, 1.0)


func _sheet_power_target_boat() -> Vector3:
	return Vector3(
		_sheet_target_side() * SHEET_TARGET_LATERAL,
		SHEET_TARGET_HEIGHT,
		SHEET_TARGET_AFT
	)


func _sheet_reach_target_boat() -> Vector3:
	return Vector3(
		_sheet_target_side() * SHEET_REACH_LATERAL,
		SHEET_REACH_HEIGHT,
		SHEET_REACH_AFT
	)


func _sheet_transfer_target_boat() -> Vector3:
	return Vector3(
		_sheet_target_side() * SHEET_TRANSFER_LATERAL,
		SHEET_TRANSFER_HEIGHT,
		SHEET_TRANSFER_AFT
	)


func _compose_control_palm_goals_global(
	grip_global: Vector3,
	shaft_axis_world: Vector3,
	sheet_palm_global: Vector3
) -> Dictionary:
	var axis := shaft_axis_world.normalized()
	if axis.length_squared() <= 0.000001:
		axis = Vector3.FORWARD
	var left_tiller_weight := _control_hand_tiller_weight(_left_hand_bone)
	var right_tiller_weight := _control_hand_tiller_weight(_right_hand_bone)
	var overlap_spacing := smoothstep(
		0.85,
		1.0,
		clampf(minf(left_tiller_weight, right_tiller_weight), 0.0, 1.0)
	)
	# Two hands cannot occupy an identical palm centre. Offset them a few
	# centimetres along the extension at the overlap peak.
	var left_tiller_palm := grip_global + axis * 0.026 * overlap_spacing
	var right_tiller_palm := grip_global - axis * 0.026 * overlap_spacing
	var left_palm := (
		left_tiller_palm
		if _tiller_is_left
		else sheet_palm_global.lerp(left_tiller_palm, left_tiller_weight)
	)
	var right_palm := (
		sheet_palm_global.lerp(right_tiller_palm, right_tiller_weight)
		if _tiller_is_left
		else right_tiller_palm
	)
	return {
		"left_tiller_palm": left_tiller_palm,
		"right_tiller_palm": right_tiller_palm,
		"left_tiller_weight": left_tiller_weight,
		"right_tiller_weight": right_tiller_weight,
		"left_palm": left_palm,
		"right_palm": right_palm,
	}


func _peek_rendered_sheet_target_boat_for_next_pose() -> Vector3:
	if _maneuver_active:
		return sheet_control_target_boat_position()
	var desired := sheet_control_target_boat_position()
	if _pending_extension_immediate or not _rendered_sheet_target_initialized:
		return desired
	var next_generation := _extension_pose_generation + 1
	if _rendered_sheet_target_generation == next_generation:
		return _rendered_sheet_target_boat
	return _rendered_sheet_target_boat.move_toward(
		desired,
		CONTROL_SHEET_TARGET_MAX_STEP
	)


func preview_tiller_extension_pair_wrist_guard(
	contact_boat: Vector3,
	direction_boat: Vector3,
	validate_arm: bool = false
) -> Dictionary:
	# Boat evaluates many direction/distance pairs before publishing one. Predict
	# only from stable, rendered state; never move targets, poles or hand history
	# while inspecting a rejected candidate.
	if (
		not is_instance_valid(_boat)
		or not is_instance_valid(_skeleton)
		or not contact_boat.is_finite()
		or not direction_boat.is_finite()
		or direction_boat.length_squared() <= 0.000001
	):
		return {"safe": false, "violation_m": INF}
	var contact_global := _boat.to_global(contact_boat)
	var axis_world := (
		_boat.global_basis * direction_boat.normalized()
	).normalized()
	var sheet_global := _boat.to_global(
		_peek_rendered_sheet_target_boat_for_next_pose()
	)
	var goals := _compose_control_palm_goals_global(
		contact_global,
		axis_world,
		sheet_global
	)
	var left_guard := _preview_control_wrist_guard_for_hand(
		&"LeftHand",
		_left_hand_bone,
		_left_upper_arm_bone,
		_left_hand_anchor,
		goals["left_palm"],
		float(goals["left_tiller_weight"]), direction_boat if validate_arm else Vector3.ZERO, goals["left_tiller_palm"]
	)
	var right_guard: Dictionary = {
		"safe": false, "relevant": false, "reach": 0.0,
		"violation_m": 0.0, "reserve_m": INF, "comfort_cost": 0.0,
	}
	# A strict pair cannot pass after one arm rejects it. Broad scoring still
	# evaluates both wrists; only the expensive boolean certification short-cuts.
	if not validate_arm or bool(left_guard["safe"]):
		right_guard = _preview_control_wrist_guard_for_hand(
			&"RightHand",
			_right_hand_bone,
			_right_upper_arm_bone,
			_right_hand_anchor,
			goals["right_palm"],
			float(goals["right_tiller_weight"]), direction_boat if validate_arm else Vector3.ZERO, goals["right_tiller_palm"]
		)
	return {
		"safe": bool(left_guard["safe"]) and bool(right_guard["safe"]),
		"left": left_guard,
		"right": right_guard,
		"left_reach": float(left_guard["reach"]),
		"right_reach": float(right_guard["reach"]),
		"left_relevant": bool(left_guard["relevant"]),
		"right_relevant": bool(right_guard["relevant"]),
		"violation_m": maxf(
			float(left_guard["violation_m"]),
			float(right_guard["violation_m"])
		),
		"reserve_m": minf(
			(
				float(left_guard["reserve_m"])
				if bool(left_guard["relevant"])
				else INF
			),
			(
				float(right_guard["reserve_m"])
				if bool(right_guard["relevant"])
				else INF
			)
		),
		"comfort_cost": (
			float(left_guard["comfort_cost"])
			+ float(right_guard["comfort_cost"])
		),
	}


func _preview_control_wrist_guard_for_hand(
	bone_key: StringName,
	hand_bone: int,
	upper_arm_bone: int,
	hand_anchor: Node3D,
	palm_goal_global: Vector3,
	tiller_weight: float,
	direction_boat: Vector3 = Vector3.ZERO,
	rigid_palm_global: Vector3 = Vector3.INF
) -> Dictionary:
	var relevant := not direction_boat.is_zero_approx() or _maneuver_active or tiller_weight > CONTROL_TILLER_CONTACT_WEIGHT_EPSILON
	if _maneuver_active and direction_boat.is_zero_approx() and tiller_weight < 0.999:
		relevant = false
	if (
		not relevant
		or hand_bone < 0
		or upper_arm_bone < 0
		or not is_instance_valid(hand_anchor)
	):
		return {
			"safe": true,
			"relevant": false,
			"reach": 0.0,
			"violation_m": 0.0,
			"reserve_m": INF,
			"comfort_cost": 0.0,
		}
	if not direction_boat.is_zero_approx():
		var arm := _atomic_control_solution(hand_bone == _left_hand_bone, palm_goal_global, direction_boat, tiller_weight, _atomic_control_history_valid, rigid_palm_global)
		if bool(arm["safe"]) and arm.has("debug_inputs"):
			_atomic_preview_debug_inputs["left" if hand_bone == _left_hand_bone else "right"] = {
				"inputs": arm["debug_inputs"], "generation": _extension_pose_generation,
				"progress": _maneuver_crossing,
			}
		var arm_reach := float(arm["reach"])
		return {"safe": bool(arm["safe"]), "relevant": true, "reach": arm_reach,
			"solution": arm,
			"violation_m": 0.0 if bool(arm["safe"]) else 0.01,
			"reserve_m": minf(arm_reach - CONTROL_WRIST_REACH_MIN, CONTROL_WRIST_REACH_MAX - arm_reach),
			"comfort_cost": absf(arm_reach - 0.35)}
	var previous_basis := _skeleton.get_bone_global_pose(hand_bone).basis.orthonormalized()
	if _final_modified_bone_poses.has(bone_key):
		var previous_pose := _previous_control_pose_in_skeleton(bone_key)
		previous_basis = previous_pose.basis.orthonormalized()
	var offset_world := (
		_skeleton.global_basis * (previous_basis * hand_anchor.position)
	)
	var nominal_wrist_global := palm_goal_global - offset_world
	var shoulder_global := (
		_skeleton.global_transform
		* _skeleton.get_bone_global_pose(upper_arm_bone)
	).origin
	if _maneuver_active and tiller_weight < 0.999:
		var nominal_boat := _boat.to_local(nominal_wrist_global)
		var shoulder_boat := _boat.to_local(shoulder_global)
		var offset := nominal_boat - shoulder_boat
		if offset.length_squared() > 0.000001:
			var projected := shoulder_boat + offset.normalized() * clampf(offset.length(),
				CONTROL_WRIST_REACH_MIN + CONTROL_SHEET_WRIST_REACH_GUARD,
				CONTROL_WRIST_REACH_MAX - CONTROL_SHEET_WRIST_REACH_GUARD)
			if tiller_weight <= CONTROL_SHEET_PROJECTION_HANDOFF_WEIGHT:
				projected = _project_sheet_wrist_outside_body_capsules_boat(projected, shoulder_boat, upper_arm_bone)
			nominal_wrist_global = _boat.to_global(nominal_boat.lerp(projected, 1.0 - smoothstep(0.0, 1.0, tiller_weight)))
	var reach := shoulder_global.distance_to(nominal_wrist_global)
	var transport_active := (
		_left_elbow_transport_active
		if hand_bone == _left_hand_bone
		else _right_elbow_transport_active
	) and _hand_exchange_amount > 0.05
	var maximum_rotation := (
		CONTROL_HAND_TRANSPORT_MAX_FRAME_ROTATION
		if transport_active
		else CONTROL_HAND_MAX_FRAME_ROTATION
	)
	var maximum_drift := (
		2.0 * hand_anchor.position.length() * sin(maximum_rotation * 0.5)
		+ CONTROL_WRIST_REACH_GUARD
	)
	var minimum_reach := CONTROL_WRIST_REACH_MIN + maximum_drift
	var maximum_reach := CONTROL_WRIST_REACH_MAX - maximum_drift
	if _maneuver_active:
		# Broad search only culls palms no wrist orientation can reach. The
		# selected body/shaft transaction then validates the complete arm solution.
		reach = shoulder_global.distance_to(palm_goal_global)
		var palm_radius := hand_anchor.position.length() * BODY_UNIFORM_SCALE
		minimum_reach = CONTROL_WRIST_REACH_MIN - palm_radius
		maximum_reach = CONTROL_WRIST_REACH_MAX + palm_radius
	var violation := maxf(
		maxf(minimum_reach - reach, reach - maximum_reach),
		0.0
	)
	return {
		"safe": violation <= 0.0,
		"relevant": true,
		"reach": reach,
		"violation_m": violation,
		"reserve_m": minf(
			reach - minimum_reach,
			maximum_reach - reach
		),
		"comfort_cost": absf(reach - 0.35),
	}


func sheet_motion_phase_name() -> StringName:
	return [
		&"idle",
		&"hold",
		&"pull",
		&"assist_overlap",
		&"primary_release_reach",
		&"regrip",
		&"assist_release",
		&"ease",
	][_sheet_motion_phase]


func sheet_primary_grip_amount() -> float:
	return _sheet_hand_grip_amount


func sheet_assist_grip_amount() -> float:
	return _sheet_assist_grip_amount


func sheet_primary_contact_active() -> bool:
	return _sheet_hand_grip_amount >= 0.20


func sheet_assist_contact_active() -> bool:
	return _sheet_assist_grip_amount >= 0.20


func _update_control_ik_targets() -> void:
	if not is_instance_valid(_left_hand_target) or not is_instance_valid(_right_hand_target):
		return
	_resolve_control_hands(false)
	var grip_position := _tiller_grip.global_position
	var sheet_palm_goal := _boat.to_global(
		_rendered_sheet_control_target_boat_position()
	)
	var control_goals := _compose_control_palm_goals_global(
		grip_position,
		-_tiller_extension_pivot.global_basis.z.normalized(),
		sheet_palm_goal
	)
	if _maneuver_active:
		_atomic_control_pose_enabled = true
	if _atomic_control_pose_enabled or _atomic_control_history_valid:
		if _update_atomic_control_targets(control_goals):
			return
		if _atomic_control_history_valid:
			# An initialized control pose may be held explicitly, but a rejected
			# coupled solve must never fall through to unverified legacy targets.
			return
	var left_palm_goal: Vector3 = control_goals["left_tiller_palm"]
	var right_palm_goal: Vector3 = control_goals["right_tiller_palm"]
	var left_tiller_weight: float = control_goals["left_tiller_weight"]
	var right_tiller_weight: float = control_goals["right_tiller_weight"]
	var left_tiller_basis := _desired_control_hand_basis_skeleton(
		_left_hand_bone,
		_left_upper_arm_bone,
		_left_lower_arm_bone,
		left_palm_goal,
		true
	)
	var right_tiller_basis := _desired_control_hand_basis_skeleton(
		_right_hand_bone,
		_right_upper_arm_bone,
		_right_lower_arm_bone,
		right_palm_goal,
		true
	)
	var left_sheet_basis := _desired_control_hand_basis_skeleton(
		_left_hand_bone,
		_left_upper_arm_bone,
		_left_lower_arm_bone,
		sheet_palm_goal,
		false
	)
	var right_sheet_basis := _desired_control_hand_basis_skeleton(
		_right_hand_bone,
		_right_upper_arm_bone,
		_right_lower_arm_bone,
		sheet_palm_goal,
		false
	)
	_left_hand_basis_override = true
	_right_hand_basis_override = true
	_left_desired_hand_basis = _blend_control_hand_basis(
		left_sheet_basis,
		left_tiller_basis,
		left_tiller_weight
	)
	_right_desired_hand_basis = _blend_control_hand_basis(
		right_sheet_basis,
		right_tiller_basis,
		right_tiller_weight
	)
	# Resolve each hand's semantic contact first, then compensate the wrist using
	# the exact same blended basis that the terminal modifier will render. Using
	# one basis for the IK target and recalculating another after IK created a
	# moving fixed point and made the palms miss by centimetres.
	_left_palm_goal_global = control_goals["left_palm"]
	_right_palm_goal_global = control_goals["right_palm"]
	var left_goal := _ik_target_for_palm_with_basis(
		_left_hand_anchor,
		_left_hand_bone,
		_left_palm_goal_global,
		_left_desired_hand_basis
	)
	var right_goal := _ik_target_for_palm_with_basis(
		_right_hand_anchor,
		_right_hand_bone,
		_right_palm_goal_global,
		_right_desired_hand_basis
	)
	_left_hand_target.global_position = left_goal
	_right_hand_target.global_position = right_goal
	if (
		_control_pose_immediate
		or _left_expected_elbow_boat.is_zero_approx()
		or _right_expected_elbow_boat.is_zero_approx()
	):
		_update_control_elbow_poles(left_goal, right_goal)
	# The elbow solver now has an exact candidate on each arm's two-bone circle.
	# Refine the wrist basis against that same-frame forearm instead of a cached
	# pose. Keep that elbow branch fixed while the palm offset converges, update
	# the circle once, then perform one final basis pass. Re-searching the discrete
	# elbow circle on every inner pass made the two solves alternate.
	for _refinement in 4:
		var left_forearm := _expected_control_forearm_skeleton(
			left_goal,
			_left_expected_elbow_boat
		)
		var right_forearm := _expected_control_forearm_skeleton(
			right_goal,
			_right_expected_elbow_boat
		)
		left_tiller_basis = _desired_control_hand_basis_skeleton(
			_left_hand_bone,
			_left_upper_arm_bone,
			_left_lower_arm_bone,
			left_palm_goal,
			true,
			left_forearm
		)
		right_tiller_basis = _desired_control_hand_basis_skeleton(
			_right_hand_bone,
			_right_upper_arm_bone,
			_right_lower_arm_bone,
			right_palm_goal,
			true,
			right_forearm
		)
		left_sheet_basis = _desired_control_hand_basis_skeleton(
			_left_hand_bone,
			_left_upper_arm_bone,
			_left_lower_arm_bone,
			sheet_palm_goal,
			false,
			left_forearm
		)
		right_sheet_basis = _desired_control_hand_basis_skeleton(
			_right_hand_bone,
			_right_upper_arm_bone,
			_right_lower_arm_bone,
			sheet_palm_goal,
			false,
			right_forearm
		)
		_left_desired_hand_basis = _blend_control_hand_basis(
			left_sheet_basis,
			left_tiller_basis,
			left_tiller_weight
		)
		_right_desired_hand_basis = _blend_control_hand_basis(
			right_sheet_basis,
			right_tiller_basis,
			right_tiller_weight
		)
		left_goal = _ik_target_for_palm_with_basis(
			_left_hand_anchor,
			_left_hand_bone,
			_left_palm_goal_global,
			_left_desired_hand_basis
		)
		right_goal = _ik_target_for_palm_with_basis(
			_right_hand_anchor,
			_right_hand_bone,
			_right_palm_goal_global,
			_right_desired_hand_basis
		)
		_left_hand_target.global_position = left_goal
		_right_hand_target.global_position = right_goal
	# Keep the prior rendered branch as the forearm predictor for this final basis
	# pass. The persistent pole is committed only after the 4-degree hand-basis
	# limiter has produced the wrist targets that the arm IK will actually consume.
	var final_left_forearm := _expected_control_forearm_skeleton(
		left_goal,
		_left_expected_elbow_boat
	)
	var final_right_forearm := _expected_control_forearm_skeleton(
		right_goal,
		_right_expected_elbow_boat
	)
	left_tiller_basis = _desired_control_hand_basis_skeleton(
		_left_hand_bone,
		_left_upper_arm_bone,
		_left_lower_arm_bone,
		left_palm_goal,
		true,
		final_left_forearm
	)
	right_tiller_basis = _desired_control_hand_basis_skeleton(
		_right_hand_bone,
		_right_upper_arm_bone,
		_right_lower_arm_bone,
		right_palm_goal,
		true,
		final_right_forearm
	)
	left_sheet_basis = _desired_control_hand_basis_skeleton(
		_left_hand_bone,
		_left_upper_arm_bone,
		_left_lower_arm_bone,
		sheet_palm_goal,
		false,
		final_left_forearm
	)
	right_sheet_basis = _desired_control_hand_basis_skeleton(
		_right_hand_bone,
		_right_upper_arm_bone,
		_right_lower_arm_bone,
		sheet_palm_goal,
		false,
		final_right_forearm
	)
	_left_desired_hand_basis = _blend_control_hand_basis(
		left_sheet_basis,
		left_tiller_basis,
		left_tiller_weight
	)
	_right_desired_hand_basis = _blend_control_hand_basis(
		right_sheet_basis,
		right_tiller_basis,
		right_tiller_weight
	)
	left_goal = _ik_target_for_palm_with_basis(
		_left_hand_anchor,
		_left_hand_bone,
		_left_palm_goal_global,
		_left_desired_hand_basis
	)
	right_goal = _ik_target_for_palm_with_basis(
		_right_hand_anchor,
		_right_hand_bone,
		_right_palm_goal_global,
		_right_desired_hand_basis
	)
	_left_hand_target.global_position = left_goal
	_right_hand_target.global_position = right_goal
	if not _control_pose_immediate:
		_left_desired_hand_basis = _limit_control_hand_basis_frame(
			&"LeftHand",
			_left_desired_hand_basis
		)
		_right_desired_hand_basis = _limit_control_hand_basis_frame(
			&"RightHand",
			_right_desired_hand_basis
		)
	# The sheet is flexible, so its semantic palm contact may follow the hand to
	# keep the two-bone arm away from both the folded and fully stretched
	# singularities. Move the palm goal, not the wrist target: the final contact
	# modifier and SheetGripAnchor then remain attached to the rendered rope.
	# A hand that fully owns the rigid extension is excluded; Boat must choose a
	# reachable point on the foam for that contact instead.
	var route_projection_active := _boat.tiller_extension_handover_route_active()
	var left_requires_route_projection := (
		route_projection_active
		and left_tiller_weight <= CONTROL_SHEET_PROJECTION_HANDOFF_WEIGHT
	)
	var right_requires_route_projection := (
		route_projection_active
		and right_tiller_weight <= CONTROL_SHEET_PROJECTION_HANDOFF_WEIGHT
	)
	var left_is_flexible_sheet_hand := (
		left_tiller_weight <= CONTROL_TILLER_CONTACT_WEIGHT_EPSILON
	)
	var right_is_flexible_sheet_hand := (
		right_tiller_weight <= CONTROL_TILLER_CONTACT_WEIGHT_EPSILON
	)
	if _maneuver_active:
		if left_tiller_weight >= 0.999:
			_reset_sheet_wrist_projection_state(_left_hand_bone)
		if right_tiller_weight >= 0.999:
			_reset_sheet_wrist_projection_state(_right_hand_bone)
	# Carry each projected sheet contact through the first few percent of the
	# tiller handoff. Dropping the correction at weight 0.001 moved the palm and
	# rope by 19 cm in one generation; the existing 20 mm release path can hand
	# authority back to the rigid contact continuously instead. A fully flexible
	# sheet hand must still take the ordinary annulus-only path after the route;
	# otherwise resetting the route state also bypasses its 220 mm fold guard.
	if (
		left_is_flexible_sheet_hand
		or left_requires_route_projection
		or _left_sheet_projection_active
	):
		_left_palm_goal_global = _project_sheet_palm_goal_to_wrist_annulus(
			_left_palm_goal_global,
			_left_desired_hand_basis,
			_left_hand_anchor,
			_left_hand_bone,
			_left_upper_arm_bone,
			left_requires_route_projection
		)
	else:
		_reset_sheet_wrist_projection_state(_left_hand_bone)
	if (
		right_is_flexible_sheet_hand
		or right_requires_route_projection
		or _right_sheet_projection_active
	):
		_right_palm_goal_global = _project_sheet_palm_goal_to_wrist_annulus(
			_right_palm_goal_global,
			_right_desired_hand_basis,
			_right_hand_anchor,
			_right_hand_bone,
			_right_upper_arm_bone,
			right_requires_route_projection
		)
	else:
		_reset_sheet_wrist_projection_state(_right_hand_bone)
	left_goal = _ik_target_for_palm_with_basis(
		_left_hand_anchor,
		_left_hand_bone,
		_left_palm_goal_global,
		_left_desired_hand_basis
	)
	right_goal = _ik_target_for_palm_with_basis(
		_right_hand_anchor,
		_right_hand_bone,
		_right_palm_goal_global,
		_right_desired_hand_basis
	)
	_left_hand_target.global_position = left_goal
	_right_hand_target.global_position = right_goal
	# Commit exactly once in an ordinary runtime modifier generation, against the
	# final limited wrist goals. Committing before the hand limiter made the pole
	# chase a different two-bone circle and produced a capped-hand/pole oscillation
	# after one tack direction.
	_update_control_elbow_poles(left_goal, right_goal)
	# Route projection can move a flexible sheet palm after the ordinary basis
	# refinement, and the collision solver can then choose a different final elbow
	# on that new two-bone circle. Close the sheet wrist once against that committed
	# forearm. The pole is deliberately not searched again: the resulting wrist
	# offset remains under the existing per-generation hand-basis cap, while a
	# second pole solve would recreate the old same-frame feedback loop.
	if (
		left_is_flexible_sheet_hand
		and (route_projection_active or _left_sheet_projection_active)
	):
		var committed_left_forearm := _expected_control_forearm_skeleton(
			left_goal,
			_left_expected_elbow_boat
		)
		var closed_left_basis := _desired_control_hand_basis_skeleton(
			_left_hand_bone,
			_left_upper_arm_bone,
			_left_lower_arm_bone,
			_left_palm_goal_global,
			false,
			committed_left_forearm,
			false
		)
		if not _control_pose_immediate:
			closed_left_basis = _limit_control_hand_basis_frame(
				&"LeftHand",
				closed_left_basis
			)
		var closed_left_goal := _ik_target_for_palm_with_basis(
			_left_hand_anchor,
			_left_hand_bone,
			_left_palm_goal_global,
			closed_left_basis
		)
		var closed_left_wrist_boat := _boat.to_local(closed_left_goal)
		var closed_left_shoulder_boat := _bone_origin_boat(_left_upper_arm_bone)
		if (
			_sheet_wrist_projection_is_valid_boat(
				closed_left_wrist_boat,
				closed_left_shoulder_boat,
				CONTROL_WRIST_REACH_MIN + CONTROL_SHEET_WRIST_REACH_GUARD,
				CONTROL_WRIST_REACH_MAX - CONTROL_SHEET_WRIST_REACH_GUARD
			)
			and _control_forearm_clearance_margin_boat(
				_left_expected_elbow_boat,
				closed_left_wrist_boat
			) >= CONTROL_ELBOW_SAFETY_BUFFER
		):
			_left_desired_hand_basis = closed_left_basis
			left_goal = closed_left_goal
			_left_hand_target.global_position = left_goal
	if (
		right_is_flexible_sheet_hand
		and (route_projection_active or _right_sheet_projection_active)
	):
		var committed_right_forearm := _expected_control_forearm_skeleton(
			right_goal,
			_right_expected_elbow_boat
		)
		var closed_right_basis := _desired_control_hand_basis_skeleton(
			_right_hand_bone,
			_right_upper_arm_bone,
			_right_lower_arm_bone,
			_right_palm_goal_global,
			false,
			committed_right_forearm,
			false
		)
		if not _control_pose_immediate:
			closed_right_basis = _limit_control_hand_basis_frame(
				&"RightHand",
				closed_right_basis
			)
		var closed_right_goal := _ik_target_for_palm_with_basis(
			_right_hand_anchor,
			_right_hand_bone,
			_right_palm_goal_global,
			closed_right_basis
		)
		var closed_right_wrist_boat := _boat.to_local(closed_right_goal)
		var closed_right_shoulder_boat := _bone_origin_boat(_right_upper_arm_bone)
		if (
			_sheet_wrist_projection_is_valid_boat(
				closed_right_wrist_boat,
				closed_right_shoulder_boat,
				CONTROL_WRIST_REACH_MIN + CONTROL_SHEET_WRIST_REACH_GUARD,
				CONTROL_WRIST_REACH_MAX - CONTROL_SHEET_WRIST_REACH_GUARD
			)
			and _control_forearm_clearance_margin_boat(
				_right_expected_elbow_boat,
				closed_right_wrist_boat
			) >= CONTROL_ELBOW_SAFETY_BUFFER
		):
			_right_desired_hand_basis = closed_right_basis
			right_goal = closed_right_goal
			_right_hand_target.global_position = right_goal


func _atomic_control_solution(is_left: bool, palm_global: Vector3, axis_boat: Vector3, weight: float, first_safe: bool = false, rigid_palm_global: Vector3 = Vector3.INF) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result := _calculate_atomic_control_solution(is_left, palm_global, axis_boat, weight, first_safe, rigid_palm_global)
	maneuver_profile["arm_us"] += Time.get_ticks_usec() - started
	maneuver_profile["arm_calls"] += 1
	return result


func _calculate_atomic_control_solution(is_left: bool, palm_global: Vector3, axis_boat: Vector3, weight: float, first_safe: bool, rigid_palm_global: Vector3) -> Dictionary:
	var upper := _left_upper_arm_bone if is_left else _right_upper_arm_bone
	var lower := _left_lower_arm_bone if is_left else _right_lower_arm_bone
	var hand := _left_hand_bone if is_left else _right_hand_bone
	var anchor := _left_hand_anchor if is_left else _right_hand_anchor
	var shoulder := _bone_origin_boat(upper)
	var elbow := _bone_origin_boat(lower)
	var wrist := _bone_origin_boat(hand)
	var preferred := elbow
	var key: StringName = &"LeftLowerArm" if is_left else &"RightLowerArm"
	var hand_key: StringName = &"LeftHand" if is_left else &"RightHand"
	var previous_hand: Dictionary = {}
	if _final_modified_bone_poses.has(key):
		preferred = (_final_skeleton_transform_boat * _final_modified_bone_poses[key]).origin
	if _final_modified_bone_poses.has(hand_key):
		var hand_pose: Transform3D = _final_skeleton_transform_boat * _final_modified_bone_poses[hand_key]
		# The anatomical history stays separate from the preferred working pose.
		# Preview and rendering share this frame budget, including body substeps.
		previous_hand = {"basis": hand_pose.basis.orthonormalized()}
		if _atomic_control_history_valid:
			previous_hand["elbow"] = preferred
			previous_hand["wrist"] = hand_pose.origin
			previous_hand["max_elbow_step_m"] = 0.06 * _control_frame_delta * 60.0 + 0.002
			previous_hand["max_wrist_step_m"] = 0.06 * _control_frame_delta * 60.0 + 0.002
			previous_hand["max_hand_rotation_rad"] = deg_to_rad(20.0) * _control_frame_delta * 60.0 + deg_to_rad(0.5)
	if _atomic_control_frame_held and not _last_validated_atomic_control_pose.is_empty():
		var validated_hand: Dictionary = _last_validated_atomic_control_pose["left" if is_left else "right"]
		preferred = validated_hand["elbow"]
		previous_hand["basis"] = validated_hand["hand_basis"]
		previous_hand["elbow"] = validated_hand["elbow"]
		previous_hand["wrist"] = validated_hand["wrist"]
	var scale_boat := (_boat.global_basis.inverse() * _skeleton.global_basis).get_scale().x
	var palm := _boat.to_local(palm_global)
	var signed_axis := axis_boat if is_left else -axis_boat
	var outward := (shoulder - (_bone_origin_boat(_left_upper_arm_bone) + _bone_origin_boat(_right_upper_arm_bone)) * 0.5).normalized()
	var forward := Basis(Vector3.UP, _maneuver_heading if _maneuver_active else -seat_side * PI * 0.5).z
	if weight >= 0.999:
		var working_elbow := shoulder + forward * 0.16 + outward * 0.16 + Vector3.DOWN * 0.10
		var seated_bias := 1.0 - _maneuver_duck if _maneuver_active else 1.0
		preferred = preferred.lerp(working_elbow, seated_bias * 0.85)
	if _maneuver_active and weight < 0.999:
		var relaxed := shoulder + forward * 0.32 + outward * 0.16 + Vector3.DOWN * 0.20
		var soft_palm := _peek_rendered_sheet_target_boat_for_next_pose().lerp(relaxed, _maneuver_duck)
		if rigid_palm_global.is_finite():
			palm = soft_palm.lerp(_boat.to_local(rigid_palm_global), weight)
			palm += outward * 0.24 * sin(weight * PI) * _maneuver_duck
		# A free hand approaching the shaft must go around the shoulder's inner
		# reach sphere, not through it. Project the continuous target before the
		# arm search; changing elbow branches cannot make a too-close palm work.
		var palm_vector := palm - shoulder
		var minimum_palm_radius := CONTROL_WRIST_REACH_MIN + anchor.position.length() * scale_boat + 0.015
		if palm_vector.length() < minimum_palm_radius:
			var approach_direction := palm_vector.normalized() if palm_vector.length() > 0.00001 else forward
			var projected_palm := shoulder + approach_direction * minimum_palm_radius
			palm = palm.lerp(projected_palm, 1.0 - smoothstep(0.80, 1.0, weight))
	var result := CONTROL_POSE.solve(shoulder, shoulder.distance_to(elbow), elbow.distance_to(wrist),
		palm, signed_axis, anchor.position * scale_boat, preferred,
		_last_resolved_body_capsules, weight > 0.0, previous_hand, weight, first_safe)
	var requested_result := result
	var solved_palm := palm
	if not bool(result["safe"]) and weight < 0.999 and not _maneuver_active:
		# A flexible contact can move with the hand; the rigid owner's contact
		# must stay on the extension and is never projected into apparent reach.
		for offset in [0.0, 0.08, 0.16]:
			var relaxed: Vector3 = shoulder + forward * 0.28 + outward * (0.10 + float(offset)) + Vector3.DOWN * 0.20
			var adjusted: Vector3 = relaxed.lerp(_boat.to_local(rigid_palm_global), weight) if _maneuver_active and rigid_palm_global.is_finite() else relaxed.lerp(palm, weight)
			result = CONTROL_POSE.solve(shoulder, shoulder.distance_to(elbow), elbow.distance_to(wrist),
				adjusted, signed_axis, anchor.position * scale_boat, preferred,
				_last_resolved_body_capsules, weight > 0.0, previous_hand, weight, first_safe)
			if bool(result["safe"]):
				palm = adjusted
				solved_palm = adjusted
				break
	if not bool(result["safe"]):
		result = requested_result
	result["palm"] = palm
	if OS.get_environment("WINDWARD_MANEUVER_DEBUG") == "1":
		result["debug_inputs"] = {
			"shoulder": shoulder, "upper_length": shoulder.distance_to(elbow),
			"lower_length": elbow.distance_to(wrist), "palm": solved_palm,
			"axis": signed_axis, "palm_offset": anchor.position * scale_boat,
			"preferred": preferred, "capsules": _last_resolved_body_capsules.duplicate(true),
			"history": previous_hand.duplicate(true), "weight": weight, "first_safe": first_safe,
		}
	return result


func _update_atomic_control_targets(goals: Dictionary) -> bool:
	var pose := _solve_atomic_control_targets(goals)
	if not bool(pose["safe"]):
		_hold_validated_atomic_control_targets(pose)
		return false
	_apply_atomic_control_targets(pose)
	return true


func _solve_atomic_control_targets(goals: Dictionary) -> Dictionary:
	# Solve both hands without publishing either one. Callers commit this exact
	# pair only after the final body, shaft and sheet generation are accepted.
	var axis := (_boat.global_basis.inverse() * -_tiller_extension_pivot.global_basis.z).normalized()
	var left := _atomic_control_solution(true, goals["left_palm"], axis, float(goals["left_tiller_weight"]), _atomic_control_history_valid, goals["left_tiller_palm"])
	var right := _atomic_control_solution(false, goals["right_palm"], axis, float(goals["right_tiller_weight"]), _atomic_control_history_valid, goals["right_tiller_palm"])
	return {"safe": bool(left["safe"]) and bool(right["safe"]), "left": left, "right": right}


func _stage_atomic_control_pose_for_next_generation() -> Dictionary:
	_resolve_control_hands(false)
	var sheet_target := _peek_rendered_sheet_target_boat_for_next_pose()
	var goals := _compose_control_palm_goals_global(
		_tiller_grip.global_position,
		-_tiller_extension_pivot.global_basis.z.normalized(),
		_boat.to_global(sheet_target)
	)
	var pose := _solve_atomic_control_targets(goals)
	pose["sheet_target"] = sheet_target
	if (
		not bool(pose["safe"]) and _maneuver_active
		and OS.get_environment("WINDWARD_MANEUVER_DEBUG") == "1"
		and _atomic_stage_debug_count < 8
		and _atomic_stage_debug_generation != _extension_pose_generation
	):
		_atomic_stage_debug_count += 1
		_atomic_stage_debug_generation = _extension_pose_generation
		for side in ["left", "right"]:
			var hand: Dictionary = pose[side]
			if bool(hand["safe"]):
				continue
			var final_inputs: Dictionary = hand.get("debug_inputs", {})
			var witness: Dictionary = _atomic_preview_debug_inputs.get(side, {})
			var preview_inputs: Dictionary = witness.get("inputs", {})
			var difference := _atomic_control_input_difference(preview_inputs, final_inputs)
			print("ARM_STAGE_MISMATCH generation=", _extension_pose_generation, " p=", _maneuver_crossing,
				" hand=", side, " preview_generation=", witness.get("generation", -1),
				" preview_p=", witness.get("progress", -1.0), " differences=", difference,
				" final_rejection=", hand.get("rejection", {}))
	return pose


func _atomic_control_input_difference(previous: Dictionary, current: Dictionary) -> Dictionary:
	if previous.is_empty() or current.is_empty():
		return {"missing_inputs": true}
	var differences := {}
	for key in ["shoulder", "palm", "palm_offset", "preferred"]:
		var before: Vector3 = previous[key]
		var after: Vector3 = current[key]
		differences[key + "_delta_m"] = before.distance_to(after)
	for key in ["upper_length", "lower_length", "weight"]:
		differences[key + "_delta"] = float(current[key]) - float(previous[key])
	var previous_axis: Vector3 = previous["axis"]
	var current_axis: Vector3 = current["axis"]
	differences["axis_delta_deg"] = rad_to_deg(previous_axis.angle_to(current_axis))
	differences["capsules_equal"] = previous["capsules"] == current["capsules"]
	differences["history_equal"] = previous["history"] == current["history"]
	differences["first_safe_equal"] = previous["first_safe"] == current["first_safe"]
	if previous["history"] != current["history"]:
		differences["previous_history"] = previous["history"]
		differences["current_history"] = current["history"]
	return differences


func _apply_atomic_control_targets(pose: Dictionary, remember: bool = true) -> void:
	var left: Dictionary = pose["left"]
	var right: Dictionary = pose["right"]
	var boat_to_skeleton := _skeleton.global_transform.affine_inverse() * _boat.global_transform
	_left_hand_target.global_position = _boat.to_global(left["wrist"])
	_right_hand_target.global_position = _boat.to_global(right["wrist"])
	_left_hand_pole.global_position = _boat.to_global(left["elbow"])
	_right_hand_pole.global_position = _boat.to_global(right["elbow"])
	_left_expected_elbow_boat = left["elbow"]
	_right_expected_elbow_boat = right["elbow"]
	_left_desired_hand_basis = (boat_to_skeleton.basis * left["hand_basis"]).orthonormalized()
	_right_desired_hand_basis = (boat_to_skeleton.basis * right["hand_basis"]).orthonormalized()
	_left_palm_goal_global = _boat.to_global(left["palm"])
	_right_palm_goal_global = _boat.to_global(right["palm"])
	_left_hand_basis_override = true
	_right_hand_basis_override = true
	_reset_sheet_wrist_projection_state(_left_hand_bone)
	_reset_sheet_wrist_projection_state(_right_hand_bone)
	if remember:
		_last_validated_atomic_control_pose = pose.duplicate(true)
		_atomic_control_history_valid = true
		_atomic_control_frame_held = false


func _hold_validated_atomic_control_targets(rejected_pose: Dictionary) -> void:
	_atomic_control_failures += 1
	_atomic_control_frame_held = _atomic_control_history_valid
	if _atomic_control_history_valid and not _last_validated_atomic_control_pose.is_empty():
		# Targets are stored in boat space, so a hold cannot retain yesterday's
		# world coordinates while the boat keeps moving. This is not a newly
		# validated physical grip and must remain visibly reported as blocked.
		_apply_atomic_control_targets(_last_validated_atomic_control_pose, false)
		_boat.mark_tiller_extension_control_pose_blocked()
	if _atomic_control_failures <= 15:
		var left: Dictionary = rejected_pose.get("left", {})
		var right: Dictionary = rejected_pose.get("right", {})
		print("ARM_POSE_BLOCKED phase=", maneuver_phase_name(), " p=", _maneuver_crossing,
			" held=", _atomic_control_frame_held,
			" left=", left.get("reason", "unsafe"), " right=", right.get("reason", "unsafe"))


func _project_sheet_palm_goal_to_wrist_annulus(
	palm_goal_global: Vector3,
	desired_basis_skeleton: Basis,
	hand_anchor: Node3D,
	hand_bone: int,
	upper_arm_bone: int,
	route_clearance_required: bool
) -> Vector3:
	if (
		not is_instance_valid(_skeleton)
		or not is_instance_valid(hand_anchor)
		or hand_bone < 0
		or upper_arm_bone < 0
	):
		return palm_goal_global
	var wrist_goal_global := _ik_target_for_palm_with_basis(
		hand_anchor,
		hand_bone,
		palm_goal_global,
		desired_basis_skeleton
	)
	var original_wrist_goal_global := wrist_goal_global
	var shoulder_global := (
		_skeleton.global_transform
		* _skeleton.get_bone_global_pose(upper_arm_bone)
	).origin
	var shoulder_to_wrist := wrist_goal_global - shoulder_global
	var wrist_reach := shoulder_to_wrist.length()
	if wrist_reach <= 0.000001 or not is_finite(wrist_reach):
		return palm_goal_global
	var safe_reach := clampf(
		wrist_reach,
		CONTROL_WRIST_REACH_MIN + CONTROL_SHEET_WRIST_REACH_GUARD,
		CONTROL_WRIST_REACH_MAX - CONTROL_SHEET_WRIST_REACH_GUARD
	)
	wrist_goal_global += (
		shoulder_to_wrist / wrist_reach * (safe_reach - wrist_reach)
	)
	if _maneuver_active:
		var tiller_weight := _control_hand_tiller_weight(hand_bone)
		_reset_sheet_wrist_projection_state(hand_bone)
		if tiller_weight >= 0.999:
			return palm_goal_global
		if route_clearance_required:
			wrist_goal_global = _boat.to_global(_project_sheet_wrist_outside_body_capsules_boat(
				_boat.to_local(wrist_goal_global), _boat.to_local(shoulder_global), upper_arm_bone
			))
		return palm_goal_global + (wrist_goal_global - original_wrist_goal_global) * (1.0 - smoothstep(0.0, 1.0, tiller_weight))
	var projection_state_active := (
		_left_sheet_projection_active
		if hand_bone == _left_hand_bone
		else _right_sheet_projection_active
	)
	if route_clearance_required or projection_state_active:
		# An annulus-safe point can still lie deep inside the torso. The sheet is
		# flexible, so move its palm/rope contact by the exact wrist correction rather
		# than asking an impossible elbow circle to hide the body penetration. Keep
		# the route-only correction alive briefly after release so returning to the
		# ordinary W/S target cannot create the inverse one-frame snap.
		var raw_wrist_boat := _boat.to_local(wrist_goal_global)
		var shoulder_boat := _boat.to_local(shoulder_global)
		var projected_wrist_boat := raw_wrist_boat
		if _control_pose_immediate:
			# Focused pose samples are independent; never carry a runtime branch into
			# an immediate solve.
			_reset_sheet_wrist_projection_state(hand_bone)
			if route_clearance_required:
				projected_wrist_boat = (
					_project_sheet_wrist_outside_body_capsules_boat(
						raw_wrist_boat,
						shoulder_boat,
						upper_arm_bone
					)
				)
		else:
			projected_wrist_boat = _continuous_sheet_wrist_projection_boat(
				raw_wrist_boat,
				shoulder_boat,
				hand_bone,
				upper_arm_bone,
				route_clearance_required
			)
		wrist_goal_global = _boat.to_global(
			projected_wrist_boat
		)
	else:
		# Keep ordinary W/S trim on its existing stateless annulus path.
		_reset_sheet_wrist_projection_state(hand_bone)
	return palm_goal_global + wrist_goal_global - original_wrist_goal_global


func _continuous_sheet_wrist_projection_boat(
	raw_wrist_boat: Vector3,
	shoulder_boat: Vector3,
	hand_bone: int,
	upper_arm_bone: int,
	route_clearance_required: bool
) -> Vector3:
	var is_left := hand_bone == _left_hand_bone
	var state_active := (
		_left_sheet_projection_active
		if is_left
		else _right_sheet_projection_active
	)
	var state_generation := (
		_left_sheet_projection_generation
		if is_left
		else _right_sheet_projection_generation
	)
	var previous_raw := (
		_left_sheet_projection_raw_wrist_boat
		if is_left
		else _right_sheet_projection_raw_wrist_boat
	)
	var previous_projected := (
		_left_sheet_projection_wrist_boat
		if is_left
		else _right_sheet_projection_wrist_boat
	)
	var previous_destination := (
		_left_sheet_projection_destination_wrist_boat
		if is_left
		else _right_sheet_projection_destination_wrist_boat
	)
	var minimum_reach := (
		CONTROL_WRIST_REACH_MIN + CONTROL_SHEET_WRIST_REACH_GUARD
	)
	var maximum_reach := (
		CONTROL_WRIST_REACH_MAX - CONTROL_SHEET_WRIST_REACH_GUARD
	)

	# Skeleton callbacks can ask for the same targets more than once. An entry
	# recovery may intentionally remain inside the old capsule for a few bounded
	# generations, so reuse the cached result even before it is fully valid.
	if state_active and state_generation == _extension_pose_generation:
		return previous_projected

	var continues_previous_generation := (
		state_active
		and state_generation == _extension_pose_generation - 1
	)
	var recovery_origin := raw_wrist_boat
	if continues_previous_generation:
		recovery_origin = previous_projected

	if not route_clearance_required:
		# The ordinary W/S target remains authoritative after the route. Remove only
		# the procedural correction, at the same 20 mm cadence used by the visible
		# sheet target, instead of dropping it on the route-release edge.
		var released := _advance_sheet_wrist_projection_recovery_boat(
			recovery_origin,
			raw_wrist_boat,
			shoulder_boat,
			minimum_reach,
			maximum_reach,
			false
		)
		if (
			released.distance_to(raw_wrist_boat)
			<= CONTROL_SHEET_ENTRY_READY_DISTANCE
			and _sheet_wrist_annulus_violation_boat(
				released,
				shoulder_boat,
				minimum_reach,
				maximum_reach
			) <= CONTROL_SHEET_PROJECTION_DEFECT_EPSILON
		):
			_reset_sheet_wrist_projection_state(hand_bone)
			return raw_wrist_boat
		_store_sheet_wrist_projection_state(
			hand_bone,
			raw_wrist_boat,
			released,
			raw_wrist_boat,
			0
		)
		return released

	var raw_is_valid := _sheet_wrist_projection_is_valid_boat(
		raw_wrist_boat,
		shoulder_boat,
		minimum_reach,
		maximum_reach
	)
	var destination := raw_wrist_boat
	var destination_is_valid := raw_is_valid
	if not raw_is_valid:
		# Keep one certified exterior branch while it remains valid. Re-solving the
		# symmetric capsule roots every generation was the source of the A/B target
		# identity flip; a moving recovery point should not also move its destination.
		if (
			continues_previous_generation
			and _sheet_wrist_projection_is_valid_boat(
				previous_destination,
				shoulder_boat,
				minimum_reach,
				maximum_reach
			)
		):
			destination = previous_destination
			destination_is_valid = true
		else:
			var reference_boat := _clamp_sheet_wrist_reference_to_annulus_boat(
				recovery_origin,
				shoulder_boat,
				minimum_reach,
				maximum_reach,
				raw_wrist_boat
			)
			destination = _project_sheet_wrist_outside_body_capsules_boat(
				reference_boat,
				shoulder_boat,
				upper_arm_bone
			)
			destination_is_valid = _sheet_wrist_projection_is_valid_boat(
				destination,
				shoulder_boat,
				minimum_reach,
				maximum_reach
			)
			if not destination_is_valid:
				destination = _project_sheet_wrist_outside_body_capsules_boat(
					raw_wrist_boat,
					shoulder_boat,
					upper_arm_bone
				)
				destination_is_valid = _sheet_wrist_projection_is_valid_boat(
					destination,
					shoulder_boat,
					minimum_reach,
					maximum_reach
				)

	if not destination_is_valid:
		# Keep the body/animation handshake closed and retry against the next live
		# capsule sample. Returning the authored point is continuous; it is not ready.
		_store_sheet_wrist_projection_state(
			hand_bone,
			raw_wrist_boat,
			recovery_origin,
			recovery_origin,
			0
		)
		return recovery_origin

	var recovered := _advance_sheet_wrist_projection_recovery_boat(
		recovery_origin,
		destination,
		shoulder_boat,
		minimum_reach,
		maximum_reach,
		true
	)
	var recovered_is_valid := _sheet_wrist_projection_is_valid_boat(
		recovered,
		shoulder_boat,
		minimum_reach,
		maximum_reach
	)
	var ready_generations := 0
	var previous_ready_generations := (
		_left_sheet_projection_ready_generations
		if is_left
		else _right_sheet_projection_ready_generations
	)
	if (
		_tack_entry_preposition_active
		and recovered_is_valid
	):
		# Once the sheet has reached a fully safe entry branch, keep the handshake
		# open while each bounded Crouch tick remains fully valid. Requiring the hand
		# to re-converge to a moving capsule-boundary destination after every 2 mm
		# shoulder step doubled the half-second crouch into a visible two-second wait.
		if previous_ready_generations >= CONTROL_SHEET_ENTRY_READY_GENERATIONS:
			ready_generations = previous_ready_generations
		elif (
			recovered.distance_to(destination)
			<= CONTROL_SHEET_ENTRY_READY_DISTANCE
		):
			ready_generations = previous_ready_generations + 1
	_store_sheet_wrist_projection_state(
		hand_bone,
		raw_wrist_boat,
		recovered,
		destination,
		ready_generations
	)
	return recovered


func _advance_sheet_wrist_projection_recovery_boat(
	current_boat: Vector3,
	destination_boat: Vector3,
	shoulder_boat: Vector3,
	minimum_reach: float,
	maximum_reach: float,
	require_capsule_nonworsening: bool
) -> Vector3:
	if current_boat.distance_to(destination_boat) <= 0.000001:
		return destination_boat
	var current_offset := current_boat - shoulder_boat
	var destination_offset := destination_boat - shoulder_boat
	if (
		current_offset.length_squared() <= 0.000001
		or destination_offset.length_squared() <= 0.000001
	):
		return current_boat
	var maximum_t := 1.0
	if current_boat.distance_to(destination_boat) > CONTROL_SHEET_TARGET_MAX_STEP:
		var safe_t := 0.0
		var unsafe_t := 1.0
		for _step_search in 12:
			var middle_t := (safe_t + unsafe_t) * 0.5
			var middle := _sheet_wrist_annulus_path_point_boat(
				current_boat,
				destination_boat,
				shoulder_boat,
				middle_t
			)
			if current_boat.distance_to(middle) <= CONTROL_SHEET_TARGET_MAX_STEP:
				safe_t = middle_t
			else:
				unsafe_t = middle_t
		maximum_t = safe_t
	var current_annulus_violation := _sheet_wrist_annulus_violation_boat(
		current_boat,
		shoulder_boat,
		minimum_reach,
		maximum_reach
	)
	var current_capsule_defect := 0.0
	if require_capsule_nonworsening:
		current_capsule_defect = _sheet_wrist_capsule_defect_boat(current_boat)
	var candidate_t := maximum_t
	for _defect_guard in 14:
		var candidate := _sheet_wrist_annulus_path_point_boat(
			current_boat,
			destination_boat,
			shoulder_boat,
			candidate_t
		)
		var annulus_nonworsening := (
			_sheet_wrist_annulus_violation_boat(
				candidate,
				shoulder_boat,
				minimum_reach,
				maximum_reach
			) <= current_annulus_violation + CONTROL_SHEET_PROJECTION_DEFECT_EPSILON
		)
		var capsule_nonworsening := true
		if require_capsule_nonworsening:
			capsule_nonworsening = (
				_sheet_wrist_capsule_defect_boat(candidate)
				<= current_capsule_defect + CONTROL_SHEET_PROJECTION_DEFECT_EPSILON
			)
		if annulus_nonworsening and capsule_nonworsening:
			return candidate
		candidate_t *= 0.5
	return current_boat


func _sheet_wrist_annulus_path_point_boat(
	current_boat: Vector3,
	destination_boat: Vector3,
	shoulder_boat: Vector3,
	progress: float
) -> Vector3:
	var current_offset := current_boat - shoulder_boat
	var destination_offset := destination_boat - shoulder_boat
	var current_reach := current_offset.length()
	var destination_reach := destination_offset.length()
	if current_reach <= 0.000001 or destination_reach <= 0.000001:
		return current_boat.lerp(destination_boat, clampf(progress, 0.0, 1.0))
	var path_direction := current_offset.normalized().slerp(
		destination_offset.normalized(),
		clampf(progress, 0.0, 1.0)
	)
	if path_direction.length_squared() <= 0.000001:
		return current_boat
	return shoulder_boat + path_direction.normalized() * lerpf(
		current_reach,
		destination_reach,
		clampf(progress, 0.0, 1.0)
	)


func _sheet_wrist_annulus_violation_boat(
	candidate_boat: Vector3,
	shoulder_boat: Vector3,
	minimum_reach: float,
	maximum_reach: float
) -> float:
	var reach := shoulder_boat.distance_to(candidate_boat)
	if not is_finite(reach):
		return INF
	return maxf(maxf(minimum_reach - reach, reach - maximum_reach), 0.0)


func _sheet_wrist_capsule_defect_boat(candidate_boat: Vector3) -> float:
	var maximum_defect := 0.0
	for capsule_variant in _last_resolved_body_capsules:
		var capsule: Dictionary = capsule_variant
		if not _capsule_constrains_control_forearm(capsule):
			continue
		var capsule_from: Vector3 = capsule.get("from", Vector3.ZERO)
		var capsule_to: Vector3 = capsule.get("to", capsule_from)
		var required_distance := (
			float(capsule.get("clearance", 0.0))
			+ CONTROL_FOREARM_RADIUS
			+ CONTROL_ELBOW_TRANSPORT_MARGIN
		)
		maximum_defect = maxf(
			maximum_defect,
			required_distance - candidate_boat.distance_to(
				_closest_point_on_segment(candidate_boat, capsule_from, capsule_to)
			)
		)
	return maximum_defect


func _store_sheet_wrist_projection_state(
	hand_bone: int,
	raw_wrist_boat: Vector3,
	projected_wrist_boat: Vector3,
	destination_wrist_boat: Vector3,
	ready_generations: int
) -> void:
	if hand_bone == _left_hand_bone:
		_left_sheet_projection_raw_wrist_boat = raw_wrist_boat
		_left_sheet_projection_wrist_boat = projected_wrist_boat
		_left_sheet_projection_destination_wrist_boat = destination_wrist_boat
		_left_sheet_projection_generation = _extension_pose_generation
		_left_sheet_projection_active = true
		_left_sheet_projection_ready_generations = ready_generations
	elif hand_bone == _right_hand_bone:
		_right_sheet_projection_raw_wrist_boat = raw_wrist_boat
		_right_sheet_projection_wrist_boat = projected_wrist_boat
		_right_sheet_projection_destination_wrist_boat = destination_wrist_boat
		_right_sheet_projection_generation = _extension_pose_generation
		_right_sheet_projection_active = true
		_right_sheet_projection_ready_generations = ready_generations


func _sheet_entry_preposition_is_ready() -> bool:
	if not _tack_entry_preposition_active:
		return true
	var ready_generations := (
		_right_sheet_projection_ready_generations
		if _tiller_is_left
		else _left_sheet_projection_ready_generations
	)
	return ready_generations >= CONTROL_SHEET_ENTRY_READY_GENERATIONS


func _reset_sheet_entry_preposition_readiness() -> void:
	_left_sheet_projection_ready_generations = 0
	_right_sheet_projection_ready_generations = 0


func _clamp_sheet_wrist_reference_to_annulus_boat(
	reference_boat: Vector3,
	shoulder_boat: Vector3,
	minimum_reach: float,
	maximum_reach: float,
	fallback_boat: Vector3
) -> Vector3:
	var shoulder_to_reference := reference_boat - shoulder_boat
	var reach := shoulder_to_reference.length()
	if (
		reach <= 0.000001
		or not is_finite(reach)
		or not is_finite(reference_boat.x)
		or not is_finite(reference_boat.y)
		or not is_finite(reference_boat.z)
	):
		return fallback_boat
	return shoulder_boat + shoulder_to_reference / reach * clampf(
		reach,
		minimum_reach,
		maximum_reach
	)


func _reset_sheet_wrist_projection_state(hand_bone: int) -> void:
	if hand_bone == _left_hand_bone:
		_left_sheet_projection_active = false
		_left_sheet_projection_generation = -1
		_left_sheet_projection_destination_wrist_boat = Vector3.ZERO
		_left_sheet_projection_ready_generations = 0
	elif hand_bone == _right_hand_bone:
		_right_sheet_projection_active = false
		_right_sheet_projection_generation = -1
		_right_sheet_projection_destination_wrist_boat = Vector3.ZERO
		_right_sheet_projection_ready_generations = 0


func _project_sheet_wrist_outside_body_capsules_boat(
	wrist_boat: Vector3,
	shoulder_boat: Vector3,
	upper_arm_bone: int
) -> Vector3:
	var projected := wrist_boat
	var minimum_reach := (
		CONTROL_WRIST_REACH_MIN + CONTROL_SHEET_WRIST_REACH_GUARD
	)
	var maximum_reach := (
		CONTROL_WRIST_REACH_MAX - CONTROL_SHEET_WRIST_REACH_GUARD
	)
	# Resolve the deepest overlap first so adjoining torso/thigh capsules cannot
	# push the point back and forth according to iteration order.
	for _projection_pass in 8:
		var deepest_penetration := 0.0
		var deepest_capsule_from := Vector3.ZERO
		var deepest_capsule_to := Vector3.ZERO
		var deepest_required_distance := 0.0
		for capsule_variant in _last_resolved_body_capsules:
			var capsule: Dictionary = capsule_variant
			if not _capsule_constrains_control_forearm(capsule):
				continue
			var capsule_from: Vector3 = capsule.get("from", Vector3.ZERO)
			var capsule_to: Vector3 = capsule.get("to", capsule_from)
			var closest := _closest_point_on_segment(
				projected,
				capsule_from,
				capsule_to
			)
			var radial := projected - closest
			var radial_distance := radial.length()
			var required_distance := (
				float(capsule.get("clearance", 0.0))
				+ CONTROL_FOREARM_RADIUS
				+ CONTROL_ELBOW_TRANSPORT_MARGIN
			)
			var penetration := required_distance - radial_distance
			if penetration > deepest_penetration:
				deepest_penetration = penetration
				deepest_capsule_from = capsule_from
				deepest_capsule_to = capsule_to
				deepest_required_distance = required_distance
		if deepest_penetration <= 0.00005:
			break
		var boundary_result := _sheet_wrist_capsule_boundary_candidate_boat(
			projected,
			shoulder_boat,
			deepest_capsule_from,
			deepest_capsule_to,
			deepest_required_distance,
			upper_arm_bone,
			minimum_reach,
			maximum_reach
		)
		if not bool(boundary_result.get("found", false)):
			break
		var boundary_point: Vector3 = boundary_result.get("point", projected)
		projected = boundary_point
	if _sheet_wrist_projection_is_valid_boat(
		projected,
		shoulder_boat,
		minimum_reach,
		maximum_reach
	):
		return projected
	# A cylinder ring can be unreachable from the shoulder, and overlapping
	# capsule projections can form a short cycle. Search the annulus itself only
	# in that exceptional case, then accept a point only after validating every
	# torso/thigh capsule. This keeps the ordinary route analytic and continuous.
	var fallback_result := _find_safe_sheet_wrist_in_annulus_boat(
		wrist_boat,
		shoulder_boat,
		upper_arm_bone,
		minimum_reach,
		maximum_reach
	)
	if bool(fallback_result.get("found", false)):
		var fallback_point: Vector3 = fallback_result.get("point", projected)
		return fallback_point
	# No point can satisfy mutually inconsistent geometry. Preserve the already
	# enforced arm annulus rather than returning a folded or hyperextended wrist.
	return wrist_boat


func _sheet_wrist_capsule_boundary_candidate_boat(
	reference_boat: Vector3,
	shoulder_boat: Vector3,
	capsule_from: Vector3,
	capsule_to: Vector3,
	required_distance: float,
	upper_arm_bone: int,
	minimum_reach: float,
	maximum_reach: float
) -> Dictionary:
	var side_sign := -1.0 if upper_arm_bone == _left_upper_arm_bone else 1.0
	var segment := capsule_to - capsule_from
	var segment_length := segment.length()
	var capsule_axis := Vector3.UP
	var closest_parameter := 0.0
	if segment_length > 0.000001:
		capsule_axis = segment / segment_length
		closest_parameter = clampf(
			(reference_boat - capsule_from).dot(capsule_axis) / segment_length,
			0.0,
			1.0
		)
	var closest := capsule_from + segment * closest_parameter
	var is_open_cylinder := (
		segment_length > 0.000001
		and closest_parameter > 0.0001
		and closest_parameter < 0.9999
	)
	if not is_open_cylinder:
		var endpoint := capsule_from
		var outward_axis := Vector3.ZERO
		if segment_length > 0.000001:
			if closest_parameter >= 0.5:
				endpoint = capsule_to
				outward_axis = capsule_axis
			else:
				outward_axis = -capsule_axis
		return _sheet_wrist_endcap_boundary_candidate_boat(
			reference_boat,
			shoulder_boat,
			endpoint,
			outward_axis,
			capsule_from,
			capsule_to,
			required_distance,
			side_sign,
			minimum_reach,
			maximum_reach
		)

	# On the open cylinder the radial direction must be perpendicular to the
	# capsule axis. Build a deterministic anatomical fallback for the exact-axis
	# case instead of normalizing a near-zero, frame-dependent vector.
	var radial_direction := reference_boat - closest
	radial_direction -= capsule_axis * radial_direction.dot(capsule_axis)
	if radial_direction.length_squared() <= 0.000001:
		radial_direction = Vector3(side_sign, 0.0, 0.0)
		radial_direction -= capsule_axis * radial_direction.dot(capsule_axis)
	if radial_direction.length_squared() <= 0.000001:
		radial_direction = Vector3.UP
		radial_direction -= capsule_axis * radial_direction.dot(capsule_axis)
	if radial_direction.length_squared() <= 0.000001:
		radial_direction = Vector3.FORWARD
		radial_direction -= capsule_axis * radial_direction.dot(capsule_axis)
	if radial_direction.length_squared() <= 0.000001:
		return {"found": false}
	radial_direction = radial_direction.normalized()
	var boundary_candidate := closest + radial_direction * required_distance
	var boundary_reach := shoulder_boat.distance_to(boundary_candidate)
	if (
		boundary_reach >= minimum_reach
		and boundary_reach <= maximum_reach
		and _sheet_wrist_meets_capsule_boundary_boat(
			boundary_candidate,
			capsule_from,
			capsule_to,
			required_distance
		)
	):
		return {"found": true, "point": boundary_candidate}

	# Rodrigues keeps the complete axial component. It is normally zero on the
	# open cylinder, but retaining it makes the formula well-defined for fallback
	# directions and avoids silently shortening the rotated vector.
	var axial_component := capsule_axis * radial_direction.dot(capsule_axis)
	var perpendicular_component := radial_direction - axial_component
	var tangent_component := capsule_axis.cross(radial_direction)
	var fixed_offset := closest - shoulder_boat + required_distance * axial_component
	var reach_base_squared := (
		fixed_offset.length_squared()
		+ required_distance
		* required_distance
		* perpendicular_component.length_squared()
	)
	var coefficient_a := fixed_offset.dot(perpendicular_component)
	var coefficient_b := fixed_offset.dot(tangent_component)
	var coefficient_radius := sqrt(
		coefficient_a * coefficient_a + coefficient_b * coefficient_b
	)
	if coefficient_radius <= 0.000001:
		return {"found": false}
	var reach_amplitude := 2.0 * required_distance * coefficient_radius
	var attainable_minimum := sqrt(maxf(reach_base_squared - reach_amplitude, 0.0))
	var attainable_maximum := sqrt(maxf(reach_base_squared + reach_amplitude, 0.0))
	var reachable_minimum := maxf(minimum_reach, attainable_minimum)
	var reachable_maximum := minf(maximum_reach, attainable_maximum)
	if reachable_minimum > reachable_maximum + 0.000001:
		return {"found": false}
	var target_reach := clampf(
		boundary_reach,
		reachable_minimum,
		reachable_maximum
	)
	var raw_target_cosine := (
		(target_reach * target_reach - reach_base_squared) / reach_amplitude
	)
	if raw_target_cosine < -1.00001 or raw_target_cosine > 1.00001:
		return {"found": false}
	var target_cosine := clampf(raw_target_cosine, -1.0, 1.0)
	var phase := atan2(coefficient_b, coefficient_a)
	var phase_offset := acos(target_cosine)
	var angle_one := wrapf(phase + phase_offset, -PI, PI)
	var angle_two := wrapf(phase - phase_offset, -PI, PI)
	var candidate_one := closest + required_distance * (
		radial_direction * cos(angle_one)
		+ capsule_axis.cross(radial_direction) * sin(angle_one)
		+ capsule_axis
		* capsule_axis.dot(radial_direction)
		* (1.0 - cos(angle_one))
	)
	var candidate_two := closest + required_distance * (
		radial_direction * cos(angle_two)
		+ capsule_axis.cross(radial_direction) * sin(angle_two)
		+ capsule_axis
		* capsule_axis.dot(radial_direction)
		* (1.0 - cos(angle_two))
	)
	var one_valid := (
		_sheet_wrist_reach_is_valid_boat(
			candidate_one,
			shoulder_boat,
			minimum_reach,
			maximum_reach
		)
		and _sheet_wrist_meets_capsule_boundary_boat(
			candidate_one,
			capsule_from,
			capsule_to,
			required_distance
		)
	)
	var two_valid := (
		_sheet_wrist_reach_is_valid_boat(
			candidate_two,
			shoulder_boat,
			minimum_reach,
			maximum_reach
		)
		and _sheet_wrist_meets_capsule_boundary_boat(
			candidate_two,
			capsule_from,
			capsule_to,
			required_distance
		)
	)
	if not one_valid and not two_valid:
		return {"found": false}
	if one_valid and not two_valid:
		return {"found": true, "point": candidate_one}
	if two_valid and not one_valid:
		return {"found": true, "point": candidate_two}
	return {
		"found": true,
		"point": _prefer_sheet_wrist_projection_candidate_boat(
			candidate_one,
			candidate_two,
			reference_boat,
			shoulder_boat,
			side_sign,
			minimum_reach,
			maximum_reach
		),
	}


func _sheet_wrist_endcap_boundary_candidate_boat(
	reference_boat: Vector3,
	shoulder_boat: Vector3,
	endcap_center: Vector3,
	outward_axis: Vector3,
	capsule_from: Vector3,
	capsule_to: Vector3,
	required_distance: float,
	side_sign: float,
	minimum_reach: float,
	maximum_reach: float
) -> Dictionary:
	var initial_direction := reference_boat - endcap_center
	if initial_direction.length_squared() <= 0.000001:
		initial_direction = Vector3(side_sign, 0.0, 0.0)
	if initial_direction.length_squared() <= 0.000001:
		initial_direction = Vector3.UP
	initial_direction = initial_direction.normalized()
	var boundary_candidate := endcap_center + initial_direction * required_distance
	var boundary_reach := shoulder_boat.distance_to(boundary_candidate)
	if (
		boundary_reach >= minimum_reach
		and boundary_reach <= maximum_reach
		and _sheet_wrist_meets_capsule_boundary_boat(
			boundary_candidate,
			capsule_from,
			capsule_to,
			required_distance
		)
	):
		return {"found": true, "point": boundary_candidate}

	var center_to_shoulder := shoulder_boat - endcap_center
	var center_distance := center_to_shoulder.length()
	if center_distance <= 0.000001:
		if required_distance < minimum_reach or required_distance > maximum_reach:
			return {"found": false}
		if (
			outward_axis.length_squared() > 0.000001
			and initial_direction.dot(outward_axis) < 0.0
		):
			initial_direction = (
				initial_direction
				- 2.0 * outward_axis * initial_direction.dot(outward_axis)
			).normalized()
		var concentric_candidate := (
			endcap_center + initial_direction * required_distance
		)
		if _sheet_wrist_meets_capsule_boundary_boat(
			concentric_candidate,
			capsule_from,
			capsule_to,
			required_distance
		):
			return {"found": true, "point": concentric_candidate}
		return {"found": false}

	# Intersect the expanded spherical endcap with the shoulder annulus. Unlike
	# rotating about the capsule axis, this remains correct at a segment endpoint.
	var attainable_minimum := absf(center_distance - required_distance)
	var attainable_maximum := center_distance + required_distance
	var reachable_minimum := maxf(minimum_reach, attainable_minimum)
	var reachable_maximum := minf(maximum_reach, attainable_maximum)
	if reachable_minimum > reachable_maximum + 0.000001:
		return {"found": false}
	var target_reach := clampf(
		boundary_reach,
		reachable_minimum,
		reachable_maximum
	)
	var shoulder_axis := center_to_shoulder / center_distance
	var plane_offset := (
		center_distance * center_distance
		+ required_distance * required_distance
		- target_reach * target_reach
	) / (2.0 * center_distance)
	var circle_radius_squared := (
		required_distance * required_distance - plane_offset * plane_offset
	)
	if circle_radius_squared < -0.00001:
		return {"found": false}
	var circle_radius := sqrt(maxf(circle_radius_squared, 0.0))
	var circle_center := endcap_center + shoulder_axis * plane_offset
	if circle_radius <= 0.000001:
		if _sheet_wrist_meets_capsule_boundary_boat(
			circle_center,
			capsule_from,
			capsule_to,
			required_distance
		):
			return {"found": true, "point": circle_center}
		return {"found": false}

	var circle_axis_a := reference_boat - circle_center
	circle_axis_a -= shoulder_axis * circle_axis_a.dot(shoulder_axis)
	if circle_axis_a.length_squared() <= 0.000001:
		circle_axis_a = Vector3(side_sign, 0.0, 0.0)
		circle_axis_a -= shoulder_axis * circle_axis_a.dot(shoulder_axis)
	if circle_axis_a.length_squared() <= 0.000001:
		circle_axis_a = Vector3.UP
		circle_axis_a -= shoulder_axis * circle_axis_a.dot(shoulder_axis)
	if circle_axis_a.length_squared() <= 0.000001:
		return {"found": false}
	circle_axis_a = circle_axis_a.normalized()
	var circle_axis_b := shoulder_axis.cross(circle_axis_a).normalized()
	var circle_candidate := circle_center + circle_axis_a * circle_radius
	if _sheet_wrist_meets_capsule_boundary_boat(
		circle_candidate,
		capsule_from,
		capsule_to,
		required_distance
	):
		return {"found": true, "point": circle_candidate}
	if outward_axis.length_squared() <= 0.000001:
		return {"found": false}

	# The nearest point on the sphere-intersection circle can lie on the cylinder
	# side of an endcap. Move only to the closest hemisphere seam; this is an exact
	# solution, including the q ~= 0 case where the whole circle is inadmissible.
	var hemisphere_constant := (circle_center - endcap_center).dot(outward_axis)
	var hemisphere_a := circle_radius * circle_axis_a.dot(outward_axis)
	var hemisphere_b := circle_radius * circle_axis_b.dot(outward_axis)
	var hemisphere_radius := sqrt(
		hemisphere_a * hemisphere_a + hemisphere_b * hemisphere_b
	)
	if hemisphere_radius <= 0.000001:
		return {"found": false}
	var seam_cosine_raw := -hemisphere_constant / hemisphere_radius
	if seam_cosine_raw < -1.00001 or seam_cosine_raw > 1.00001:
		return {"found": false}
	var seam_phase := atan2(hemisphere_b, hemisphere_a)
	var seam_offset := acos(clampf(seam_cosine_raw, -1.0, 1.0))
	var seam_angle_one := wrapf(seam_phase + seam_offset, -PI, PI)
	var seam_angle_two := wrapf(seam_phase - seam_offset, -PI, PI)
	var seam_candidate_one := circle_center + circle_radius * (
		circle_axis_a * cos(seam_angle_one)
		+ circle_axis_b * sin(seam_angle_one)
	)
	var seam_candidate_two := circle_center + circle_radius * (
		circle_axis_a * cos(seam_angle_two)
		+ circle_axis_b * sin(seam_angle_two)
	)
	var one_valid := _sheet_wrist_meets_capsule_boundary_boat(
		seam_candidate_one,
		capsule_from,
		capsule_to,
		required_distance
	)
	var two_valid := _sheet_wrist_meets_capsule_boundary_boat(
		seam_candidate_two,
		capsule_from,
		capsule_to,
		required_distance
	)
	if not one_valid and not two_valid:
		return {"found": false}
	if one_valid and not two_valid:
		return {"found": true, "point": seam_candidate_one}
	if two_valid and not one_valid:
		return {"found": true, "point": seam_candidate_two}
	return {
		"found": true,
		"point": _prefer_sheet_wrist_projection_candidate_boat(
			seam_candidate_one,
			seam_candidate_two,
			reference_boat,
			shoulder_boat,
			side_sign,
			minimum_reach,
			maximum_reach
		),
	}


func _prefer_sheet_wrist_projection_candidate_boat(
	candidate_one: Vector3,
	candidate_two: Vector3,
	reference_boat: Vector3,
	shoulder_boat: Vector3,
	side_sign: float,
	minimum_reach: float,
	maximum_reach: float
) -> Vector3:
	var one_globally_safe := _sheet_wrist_projection_is_valid_boat(
		candidate_one,
		shoulder_boat,
		minimum_reach,
		maximum_reach
	)
	var two_globally_safe := _sheet_wrist_projection_is_valid_boat(
		candidate_two,
		shoulder_boat,
		minimum_reach,
		maximum_reach
	)
	if one_globally_safe != two_globally_safe:
		return candidate_one if one_globally_safe else candidate_two
	var one_distance := reference_boat.distance_squared_to(candidate_one)
	var two_distance := reference_boat.distance_squared_to(candidate_two)
	if one_distance < two_distance - 0.0000001:
		return candidate_one
	if two_distance < one_distance - 0.0000001:
		return candidate_two
	# Exact +/- roots otherwise change identity when atan2 crosses its wrap seam.
	# Prefer the hand's anatomical side, then a fixed lexicographic order.
	var one_lateral := candidate_one.x * side_sign
	var two_lateral := candidate_two.x * side_sign
	if one_lateral > two_lateral + 0.000001:
		return candidate_one
	if two_lateral > one_lateral + 0.000001:
		return candidate_two
	if candidate_one.y > candidate_two.y + 0.000001:
		return candidate_one
	if candidate_two.y > candidate_one.y + 0.000001:
		return candidate_two
	return candidate_one if candidate_one.z <= candidate_two.z else candidate_two


func _sheet_wrist_reach_is_valid_boat(
	candidate_boat: Vector3,
	shoulder_boat: Vector3,
	minimum_reach: float,
	maximum_reach: float
) -> bool:
	if (
		not is_finite(candidate_boat.x)
		or not is_finite(candidate_boat.y)
		or not is_finite(candidate_boat.z)
	):
		return false
	var reach := shoulder_boat.distance_to(candidate_boat)
	return reach >= minimum_reach - 0.00005 and reach <= maximum_reach + 0.00005


func _sheet_wrist_meets_capsule_boundary_boat(
	candidate_boat: Vector3,
	capsule_from: Vector3,
	capsule_to: Vector3,
	required_distance: float
) -> bool:
	return candidate_boat.distance_to(
		_closest_point_on_segment(candidate_boat, capsule_from, capsule_to)
	) >= required_distance - 0.00005


func _sheet_wrist_projection_is_valid_boat(
	candidate_boat: Vector3,
	shoulder_boat: Vector3,
	minimum_reach: float,
	maximum_reach: float
) -> bool:
	if not _sheet_wrist_reach_is_valid_boat(
		candidate_boat,
		shoulder_boat,
		minimum_reach,
		maximum_reach
	):
		return false
	for capsule_variant in _last_resolved_body_capsules:
		var capsule: Dictionary = capsule_variant
		if not _capsule_constrains_control_forearm(capsule):
			continue
		var capsule_from: Vector3 = capsule.get("from", Vector3.ZERO)
		var capsule_to: Vector3 = capsule.get("to", capsule_from)
		var required_distance := (
			float(capsule.get("clearance", 0.0))
			+ CONTROL_FOREARM_RADIUS
			+ CONTROL_ELBOW_TRANSPORT_MARGIN
		)
		if not _sheet_wrist_meets_capsule_boundary_boat(
			candidate_boat,
			capsule_from,
			capsule_to,
			required_distance
		):
			return false
	return true


func _find_safe_sheet_wrist_in_annulus_boat(
	reference_boat: Vector3,
	shoulder_boat: Vector3,
	upper_arm_bone: int,
	minimum_reach: float,
	maximum_reach: float
) -> Dictionary:
	var preferred_direction := reference_boat - shoulder_boat
	if preferred_direction.length_squared() <= 0.000001:
		preferred_direction = Vector3(
			-1.0 if upper_arm_bone == _left_upper_arm_bone else 1.0,
			0.0,
			0.0
		)
	preferred_direction = preferred_direction.normalized()
	var ring_axis_a := preferred_direction.cross(Vector3.UP)
	if ring_axis_a.length_squared() <= 0.000001:
		ring_axis_a = preferred_direction.cross(Vector3.RIGHT)
	if ring_axis_a.length_squared() <= 0.000001:
		return {"found": false}
	ring_axis_a = ring_axis_a.normalized()
	var ring_axis_b := preferred_direction.cross(ring_axis_a).normalized()
	var side_sign := -1.0 if upper_arm_bone == _left_upper_arm_bone else 1.0
	var best_candidate := reference_boat
	var best_score := INF
	var best_lateral := -INF
	var found_candidate := false
	# Five-degree polar rings and 7.5-degree azimuths are only used after exact
	# cylinder/endcap projection fails. Each sampled ray tests its closest annulus
	# reach plus both hard bounds, and every accepted point passes all capsules.
	for polar_step in 37:
		var polar_angle := PI * float(polar_step) / 36.0
		var azimuth_count := 1 if polar_step == 0 or polar_step == 36 else 48
		for azimuth_step in azimuth_count:
			var azimuth := TAU * float(azimuth_step) / float(azimuth_count)
			var direction := (
				preferred_direction * cos(polar_angle)
				+ (
					ring_axis_a * cos(azimuth)
					+ ring_axis_b * sin(azimuth)
				) * sin(polar_angle)
			).normalized()
			var closest_reach := clampf(
				(reference_boat - shoulder_boat).dot(direction),
				minimum_reach,
				maximum_reach
			)
			var candidate_reaches := [
				closest_reach,
				minimum_reach,
				maximum_reach,
			]
			for reach_variant in candidate_reaches:
				var candidate := (
					shoulder_boat + direction * float(reach_variant)
				)
				if not _sheet_wrist_projection_is_valid_boat(
					candidate,
					shoulder_boat,
					minimum_reach,
					maximum_reach
				):
					continue
				var score := reference_boat.distance_squared_to(candidate)
				var lateral := candidate.x * side_sign
				if (
					not found_candidate
					or score < best_score - 0.0000001
					or (
						absf(score - best_score) <= 0.0000001
						and lateral > best_lateral
					)
				):
					found_candidate = true
					best_candidate = candidate
					best_score = score
					best_lateral = lateral
	return {"found": found_candidate, "point": best_candidate}


func _limit_control_hand_basis_frame(
	bone_key: StringName,
	target_basis: Basis
) -> Basis:
	if not _final_modified_bone_poses.has(bone_key):
		return target_basis.orthonormalized()
	var previous_pose := _previous_control_pose_in_skeleton(bone_key)
	var previous_quaternion := previous_pose.basis.orthonormalized().get_rotation_quaternion()
	var target_quaternion := target_basis.orthonormalized().get_rotation_quaternion()
	var angle := previous_quaternion.angle_to(target_quaternion)
	var hand_bone := _left_hand_bone if bone_key == &"LeftHand" else _right_hand_bone
	var hand_still_uses_tiller := (
		_control_hand_tiller_weight(hand_bone)
		> CONTROL_TILLER_CONTACT_WEIGHT_EPSILON
	)
	var transport_active := (
		_left_elbow_transport_active
		if bone_key == &"LeftHand"
		else _right_elbow_transport_active
	) and _hand_exchange_amount > 0.05 and hand_still_uses_tiller
	var max_frame_rotation := (
		CONTROL_HAND_TRANSPORT_MAX_FRAME_ROTATION
		if transport_active
		else CONTROL_HAND_MAX_FRAME_ROTATION
	)
	if angle <= max_frame_rotation or angle <= 0.000001:
		return Basis(target_quaternion).orthonormalized()
	return Basis(previous_quaternion.slerp(
		target_quaternion,
		max_frame_rotation / angle
	).normalized()).orthonormalized()


func _expected_control_forearm_skeleton(
	wrist_goal_global: Vector3,
	expected_elbow_boat: Vector3
) -> Vector3:
	var wrist_goal := (
		_skeleton.global_transform.affine_inverse() * wrist_goal_global
	)
	var expected_elbow := (
		_skeleton.global_transform.affine_inverse()
		* _boat.to_global(expected_elbow_boat)
	)
	var is_left := expected_elbow_boat == _left_expected_elbow_boat
	var upper := _left_upper_arm_bone if is_left else _right_upper_arm_bone
	var lower := _left_lower_arm_bone if is_left else _right_lower_arm_bone
	var hand := _left_hand_bone if is_left else _right_hand_bone
	var shoulder := _skeleton.get_bone_global_pose(upper).origin
	var source_elbow := _skeleton.get_bone_global_pose(lower).origin
	var source_wrist := _skeleton.get_bone_global_pose(hand).origin
	var upper_length := shoulder.distance_to(source_elbow)
	var lower_length := source_elbow.distance_to(source_wrist)
	var offset := wrist_goal - shoulder
	var distance := clampf(offset.length(), absf(upper_length - lower_length) + 0.002, upper_length + lower_length - 0.002)
	if offset.length_squared() > 0.000001:
		var axis := offset.normalized()
		var along := (distance * distance + upper_length * upper_length - lower_length * lower_length) / (2.0 * distance)
		var center := shoulder + axis * along
		var bend := expected_elbow - center
		bend -= axis * bend.dot(axis)
		if bend.length_squared() > 0.000001:
			expected_elbow = center + bend.normalized() * sqrt(maxf(upper_length * upper_length - along * along, 0.0))
	return wrist_goal - expected_elbow


func _blend_control_hand_basis(
	sheet_basis: Basis,
	tiller_basis: Basis,
	tiller_weight: float
) -> Basis:
	var weight := smoothstep(0.0, 1.0, clampf(tiller_weight, 0.0, 1.0))
	return Basis(
		sheet_basis.get_rotation_quaternion().slerp(
			tiller_basis.get_rotation_quaternion(),
			weight
		).normalized()
	).orthonormalized()


func _rendered_sheet_control_target_boat_position() -> Vector3:
	var desired := sheet_control_target_boat_position()
	if _maneuver_active:
		# The maneuver is already advanced through a checked temporal sweep. Its
		# body-relative control path must follow that same step, including at 30 Hz.
		_rendered_sheet_target_boat = desired
		_rendered_sheet_target_initialized = true
		_rendered_sheet_target_generation = _extension_pose_generation
		return desired
	if _control_pose_immediate or not _rendered_sheet_target_initialized:
		_rendered_sheet_target_boat = desired
		_rendered_sheet_target_initialized = true
		_rendered_sheet_target_generation = _extension_pose_generation
	elif _rendered_sheet_target_generation != _extension_pose_generation:
		# Physics may advance several fixed sheet phases before one expensive
		# modifier/render generation. Consume that authored motion in the same
		# 20 mm spatial cadence as the visible 37-point rope so hand and line stay
		# attached without a low-FPS endpoint jump.
		_rendered_sheet_target_boat = _rendered_sheet_target_boat.move_toward(
			desired,
			CONTROL_SHEET_TARGET_MAX_STEP
		)
		_rendered_sheet_target_generation = _extension_pose_generation
	return _rendered_sheet_target_boat


func _desired_control_hand_basis_skeleton(
	hand_bone: int,
	upper_arm_bone: int,
	lower_arm_bone: int,
	palm_goal_global: Vector3,
	uses_tiller: bool,
	forearm_override_skeleton: Vector3 = Vector3.INF,
	allow_rendered_sheet_forearm: bool = true
) -> Basis:
	var current_basis := _skeleton.get_bone_global_pose(hand_bone).basis.orthonormalized()
	var bone_key := &"LeftHand" if hand_bone == _left_hand_bone else &"RightHand"
	if _final_modified_bone_poses.has(bone_key):
		var previous_pose := _previous_control_pose_in_skeleton(bone_key)
		current_basis = previous_pose.basis.orthonormalized()
	var grip_axis_world := (
		-_tiller_extension_pivot.global_basis.z.normalized()
		if uses_tiller
		else _sheet_grip_axis_world(palm_goal_global)
	)
	var grip_axis := (
		_skeleton.global_basis.inverse() * grip_axis_world
	).normalized()
	var shoulder := _skeleton.get_bone_global_pose(upper_arm_bone).origin
	var palm_goal := _skeleton.global_transform.affine_inverse() * palm_goal_global
	# The previous implementation aligned only Hand local-X to the shaft, then
	# aimed local-Y from shoulder to palm. That put the contact point on the rod
	# but folded the visible wrist back by roughly 104 degrees. Use the rendered
	# elbow-to-wrist continuation as the palm direction instead: a boxing-guard
	# arm may bend at the elbow, but its wrist must remain nearly straight.
	var palm_direction := palm_goal - shoulder
	var lower_key := (
		&"LeftLowerArm"
		if lower_arm_bone == _left_lower_arm_bone
		else &"RightLowerArm"
	)
	var elbow_transport_active := (
		_left_elbow_transport_active
		if hand_bone == _left_hand_bone
		else _right_elbow_transport_active
	)
	var use_rendered_sheet_forearm := (
		allow_rendered_sheet_forearm
		and not uses_tiller
		and not _control_pose_immediate
		and _boat.tiller_extension_handover_route_active()
		and _control_hand_tiller_weight(hand_bone)
		<= CONTROL_TILLER_CONTACT_WEIGHT_EPSILON
		and elbow_transport_active
		and _final_modified_bone_poses.has(lower_key)
		and _final_modified_bone_poses.has(bone_key)
	)
	if not use_rendered_sheet_forearm and forearm_override_skeleton.is_finite() and (
		forearm_override_skeleton.length_squared() > 0.000001
	):
		palm_direction = forearm_override_skeleton
	elif (
		_final_modified_bone_poses.has(lower_key)
		and _final_modified_bone_poses.has(bone_key)
	):
		var previous_elbow := _previous_control_pose_in_skeleton(lower_key)
		var previous_wrist := _previous_control_pose_in_skeleton(bone_key)
		palm_direction = previous_wrist.origin - previous_elbow.origin
	# A cylinder is visually symmetric under an axis flip, but a human hand is
	# not. Fix the anatomical branch instead of selecting it from prior-frame
	# history: right +X follows joint-to-tip, left +X opposes it.
	if hand_bone == _left_hand_bone:
		grip_axis = -grip_axis
	if not uses_tiller:
		return _sheet_hand_basis_from_forearm(
			grip_axis,
			palm_direction,
			current_basis
		)
	return _grip_basis_from_forearm(
		grip_axis,
		palm_direction,
		current_basis
	)


func _sheet_hand_basis_from_forearm(
	line_axis: Vector3,
	forearm_direction: Vector3,
	fallback_basis: Basis
) -> Basis:
	# A flexible sheet does not require the whole knuckle axis to be collinear
	# with the rope. Forcing that rigid-cylinder constraint made the wrist bend
	# 80-116 degrees whenever the forearm had a component along the line. Keep the
	# palm continuation aligned with the forearm and use only the line component
	# perpendicular to the arm to choose a stable grip roll.
	var palm_direction := forearm_direction.normalized()
	if palm_direction.length_squared() <= 0.000001:
		palm_direction = fallback_basis.y.normalized()
	# Parallel-transport the previous knuckle axis onto the new forearm plane.
	# Selecting the line projection directly has two equivalent +/- branches; it
	# flipped by 67 degrees when the sheet stroke crossed that branch boundary.
	var hand_x := fallback_basis.x - palm_direction * fallback_basis.x.dot(
		palm_direction
	)
	var line_x := line_axis - palm_direction * line_axis.dot(palm_direction)
	if hand_x.length_squared() > 0.000001:
		hand_x = hand_x.normalized()
		if line_x.length_squared() > 0.000001:
			line_x = line_x.normalized()
			if line_x.dot(hand_x) < 0.0:
				line_x = -line_x
			hand_x = (hand_x * 0.80 + line_x * 0.20).normalized()
	else:
		hand_x = line_x
	if hand_x.length_squared() <= 0.000001:
		var reference := Vector3.UP
		if absf(reference.dot(palm_direction)) > 0.90:
			reference = Vector3.RIGHT
		hand_x = reference - palm_direction * reference.dot(palm_direction)
	hand_x = hand_x.normalized()
	var palm_offset := _left_hand_anchor.position
	var local_offset_angle := atan2(palm_offset.z, palm_offset.y)
	var hand_y := (
		Quaternion(hand_x, -local_offset_angle) * palm_direction
	).normalized()
	var hand_z := hand_x.cross(hand_y).normalized()
	hand_y = hand_z.cross(hand_x).normalized()
	return Basis(hand_x, hand_y, hand_z).orthonormalized()


func _grip_basis_from_forearm(
	shaft_axis: Vector3,
	forearm_direction: Vector3,
	fallback_basis: Basis
) -> Basis:
	var palm_direction := forearm_direction
	palm_direction -= shaft_axis * palm_direction.dot(shaft_axis)
	if palm_direction.length_squared() <= 0.000001:
		palm_direction = fallback_basis.y
		palm_direction -= shaft_axis * palm_direction.dot(shaft_axis)
	if palm_direction.length_squared() <= 0.000001:
		var reference_axis := Vector3.UP
		if absf(shaft_axis.dot(reference_axis)) > 0.82:
			reference_axis = Vector3.RIGHT
		if absf(shaft_axis.dot(reference_axis)) > 0.82:
			reference_axis = Vector3.FORWARD
		palm_direction = (
			reference_axis
			- shaft_axis * reference_axis.dot(shaft_axis)
		)
	palm_direction = palm_direction.normalized()
	# The semantic palm contact is Hand-local (0, .09433, .04843), not exactly +Y.
	# Undo that 27.2-degree local offset so the actual wrist-to-palm vector, rather
	# than merely the bone axis, continues the forearm toward the grip.
	var palm_offset := _left_hand_anchor.position
	var local_offset_angle := atan2(palm_offset.z, palm_offset.y)
	var hand_y := (
		Quaternion(shaft_axis, -local_offset_angle) * palm_direction
	).normalized()
	var hand_z := shaft_axis.cross(hand_y).normalized()
	hand_y = hand_z.cross(shaft_axis).normalized()
	return Basis(shaft_axis, hand_y, hand_z).orthonormalized()


func _update_control_elbow_poles(
	left_wrist_goal_global: Vector3,
	right_wrist_goal_global: Vector3
) -> void:
	if not is_instance_valid(_left_hand_pole) or not is_instance_valid(_right_hand_pole):
		return
	# Godot's TwoBoneIK chooses the elbow solution closest to the pole. The old
	# fixed markers were above the shoulders, so they pulled both elbows into a
	# raised guard pose. Search the live elbow circle for a safe bend first, then
	# choose the lowest natural solution instead of rewarding useless clearance.
	_left_hand_pole.global_position = _boat.to_global(_control_elbow_pole_boat(
		_left_upper_arm_bone,
		_left_lower_arm_bone,
		_left_hand_bone,
		left_wrist_goal_global
	))
	_right_hand_pole.global_position = _boat.to_global(_control_elbow_pole_boat(
		_right_upper_arm_bone,
		_right_lower_arm_bone,
		_right_hand_bone,
		right_wrist_goal_global
	))


func _control_elbow_pole_boat(
	upper_arm_bone: int,
	lower_arm_bone: int,
	hand_bone: int,
	wrist_goal_global: Vector3
) -> Vector3:
	var fallback_side := -1.0 if upper_arm_bone == _left_upper_arm_bone else 1.0
	var fallback := Vector3(fallback_side * 0.25, 0.72, 0.55)
	if (
		upper_arm_bone < 0
		or lower_arm_bone < 0
		or hand_bone < 0
		or not is_instance_valid(_skeleton)
	):
		return fallback

	var shoulder := _bone_origin_boat(upper_arm_bone)
	var source_elbow := _bone_origin_boat(lower_arm_bone)
	var source_wrist := _bone_origin_boat(hand_bone)
	var wrist_goal := _boat.to_local(wrist_goal_global)
	var upper_length := shoulder.distance_to(source_elbow)
	var lower_length := source_elbow.distance_to(source_wrist)
	var shoulder_to_goal := wrist_goal - shoulder
	var raw_distance := shoulder_to_goal.length()
	if upper_length < 0.001 or lower_length < 0.001 or raw_distance < 0.001:
		return fallback

	var direction := shoulder_to_goal / raw_distance
	var solved_distance := clampf(
		raw_distance,
		absf(upper_length - lower_length) + 0.002,
		upper_length + lower_length - 0.002
	)
	var circle_distance := (
		solved_distance * solved_distance
		+ upper_length * upper_length
		- lower_length * lower_length
	) / (2.0 * solved_distance)
	var circle_center := shoulder + direction * circle_distance
	var circle_radius_squared := maxf(
		upper_length * upper_length - circle_distance * circle_distance,
		0.0
	)
	if circle_radius_squared < 0.000001:
		return circle_center + Vector3(fallback_side, 0.0, 0.0) * CONTROL_ELBOW_POLE_DISTANCE
	var reference_axis := Vector3.UP
	if absf(direction.dot(reference_axis)) > 0.92:
		reference_axis = Vector3.FORWARD
	var circle_axis_a := direction.cross(reference_axis).normalized()
	var circle_axis_b := direction.cross(circle_axis_a).normalized()
	var circle_radius := sqrt(circle_radius_squared)
	var solved_wrist := shoulder + direction * solved_distance
	var source_bend := source_elbow - circle_center
	source_bend -= direction * source_bend.dot(direction)
	if source_bend.length_squared() > 0.000001:
		source_bend = source_bend.normalized()
	else:
		source_bend = circle_axis_a
	var desired_elbow_height := lerpf(
		solved_wrist.y,
		shoulder.y,
		CONTROL_ELBOW_HEIGHT_RATIO
	)
	# Prefer a relaxed lower guard with the upper arm close to the ribs. The
	# generic chair clip bends both elbows away from the body; preserving that
	# source hemisphere produced a high, wide boxing pose even though every
	# collision capsule passed. Keep a narrow signed band beside the ribs. For the
	# tiller arm, also reject forearms that approach parallel to the shaft—the pose
	# that previously forced all remaining rotation into the wrist.
	var shoulder_mid := (
		_bone_origin_boat(_left_upper_arm_bone)
		+ _bone_origin_boat(_right_upper_arm_bone)
	) * 0.5
	var outward_axis := shoulder - shoulder_mid
	if outward_axis.length_squared() <= 0.000001:
		outward_axis = Vector3(fallback_side, 0.0, 0.0)
	outward_axis = outward_axis.normalized()
	var tiller_weight := _control_hand_tiller_weight(hand_bone)
	var shaft_direction_boat := (
		_boat.global_basis.inverse()
		* -_tiller_extension_pivot.global_basis.z.normalized()
	).normalized()
	var rendered_bend := Vector3.ZERO
	var lower_arm_key := (
		&"LeftLowerArm"
		if lower_arm_bone == _left_lower_arm_bone
		else &"RightLowerArm"
	)
	var hand_key := &"LeftHand" if hand_bone == _left_hand_bone else &"RightHand"
	var has_previous_final_elbow := false
	var previous_final_elbow := Vector3.ZERO
	# Reproject the last terminal-modifier elbow onto this frame's two-bone circle
	# so continuity follows the pose that was actually rendered.
	if _final_modified_bone_poses.has(lower_arm_key):
		var previous_final_pose := _previous_control_pose_in_skeleton(lower_arm_key)
		previous_final_elbow = _boat.to_local(
			(_skeleton.global_transform * previous_final_pose).origin
		)
		has_previous_final_elbow = true
		rendered_bend = previous_final_elbow - circle_center
		rendered_bend -= direction * rendered_bend.dot(direction)
	# An abrupt wrist-axis change can pass almost exactly through the seeded elbow,
	# making point projection ill-conditioned. Transport the previous rendered arm
	# plane in that rare case; this still derives the branch from final bones, not
	# from the solver's previous expected elbow.
	if (
		has_previous_final_elbow
		and rendered_bend.length_squared() <= 0.000001
		and _final_modified_bone_poses.has(hand_key)
	):
		var previous_final_hand_pose := _previous_control_pose_in_skeleton(hand_key)
		var previous_final_wrist := _boat.to_local(
			(_skeleton.global_transform * previous_final_hand_pose).origin
		)
		var previous_arm_plane_normal := (
			(previous_final_elbow - shoulder).cross(
				previous_final_wrist - previous_final_elbow
			)
		)
		if previous_arm_plane_normal.length_squared() > 0.000001:
			rendered_bend = direction.cross(previous_arm_plane_normal).normalized()
	# Before the first terminal modifier pass (or for a fully degenerate rendered
	# arm plane) there is no reliable historical branch. Use the authored source
	# bend rather than reviving an unrendered expected solution.
	if rendered_bend.length_squared() <= 0.000001:
		rendered_bend = source_bend
	if rendered_bend.length_squared() > 0.000001:
		rendered_bend = rendered_bend.normalized()
	else:
		rendered_bend = source_bend
	var rendered_elbow := circle_center + rendered_bend * circle_radius
	var rendered_margin := 1000000.0
	for capsule_variant in _last_resolved_body_capsules:
		var capsule: Dictionary = capsule_variant
		if not _capsule_constrains_control_forearm(capsule):
			continue
		rendered_margin = minf(
			rendered_margin,
			_segment_segment_distance(
				rendered_elbow,
				solved_wrist,
				capsule.get("from", Vector3.ZERO),
				capsule.get("to", Vector3.ZERO)
			) - float(capsule.get("clearance", 0.0)) - CONTROL_FOREARM_RADIUS
		)
	var transport_active := (
		_left_elbow_transport_active
		if hand_bone == _left_hand_bone
		else _right_elbow_transport_active
	)
	var transport_target_boat := (
		_left_elbow_transport_target_boat
		if hand_bone == _left_hand_bone
		else _right_elbow_transport_target_boat
	)
	var transport_release_generations := (
		_left_elbow_transport_release_generations
		if hand_bone == _left_hand_bone
		else _right_elbow_transport_release_generations
	)
	var height_relaxed := (
		_left_elbow_height_relaxed
		if hand_bone == _left_hand_bone
		else _right_elbow_height_relaxed
	)
	var commanded_bend_boat := (
		_left_elbow_bend_boat
		if hand_bone == _left_hand_bone
		else _right_elbow_bend_boat
	)
	var commanded_elbow_boat := (
		_left_expected_elbow_boat
		if hand_bone == _left_hand_bone
		else _right_expected_elbow_boat
	)
	# Preserve the last commanded elbow point and choose the closest point on this
	# generation's moving circle. A unit bend direction is only a degeneracy
	# fallback: reusing it as the primary state made small wrist/circle-axis changes
	# alternate the visible elbow around a guarded transport latch.
	var fallback_commanded_bend := (
		commanded_bend_boat - direction * commanded_bend_boat.dot(direction)
	)
	var commanded_bend := fallback_commanded_bend
	if not commanded_elbow_boat.is_zero_approx():
		commanded_bend = commanded_elbow_boat - circle_center
	commanded_bend -= direction * commanded_bend.dot(direction)
	if commanded_bend.length_squared() > 0.000001:
		commanded_bend = commanded_bend.normalized()
	elif fallback_commanded_bend.length_squared() > 0.000001:
		commanded_bend = fallback_commanded_bend.normalized()
	else:
		commanded_bend = source_bend
	var commanded_elbow := circle_center + commanded_bend * circle_radius
	var commanded_margin := _control_forearm_clearance_margin_boat(
		commanded_elbow,
		solved_wrist
	)
	var projected_transport_target := Vector3.ZERO
	if transport_active and not transport_target_boat.is_zero_approx():
		var transport_target_offset := transport_target_boat - circle_center
		projected_transport_target = (
			transport_target_offset
			- direction * transport_target_offset.dot(direction)
		)
		if projected_transport_target.length_squared() > 0.000001:
			projected_transport_target = projected_transport_target.normalized()
	var transport_reference := commanded_bend
	if projected_transport_target.length_squared() > 0.000001:
		transport_reference = projected_transport_target
	var continuity_bend := source_bend if _control_pose_immediate else commanded_bend
	var allowed_shaft_dot := lerpf(
		1.0,
		CONTROL_TILLER_FOREARM_SHAFT_MAX_DOT,
		tiller_weight
	)
	# Start carrying the incumbent toward its closest safe neighbour while a full
	# transition runway remains. Waiting until the five-millimetre hard tier is
	# exhausted lets a fixed-palm wrist rotation invalidate the branch in one frame.
	var transport_entry_required := (
		rendered_margin < CONTROL_ELBOW_TRANSPORT_MARGIN
		or commanded_margin < CONTROL_ELBOW_TRANSPORT_MARGIN
	)
	var best_safe_direction := circle_axis_a
	var best_safe_natural_score := -1000000.0
	var closest_transport_safe_direction := circle_axis_a
	var closest_transport_safe_dot := -2.0
	var closest_transport_safe_natural_score := -1000000.0
	var closest_transport_guarded_direction := circle_axis_a
	var closest_transport_guarded_dot := -2.0
	var closest_transport_guarded_natural_score := -1000000.0
	var found_transport_guarded_candidate := false
	var best_unsafe_direction := circle_axis_a
	var best_unsafe_margin := -1000000.0
	var best_unsafe_natural_score := -1000000.0
	var found_safe_candidate := false
	for step in CONTROL_ELBOW_SEARCH_STEPS:
		var angle := TAU * float(step) / float(CONTROL_ELBOW_SEARCH_STEPS)
		var bend_direction := (
			circle_axis_a * cos(angle) + circle_axis_b * sin(angle)
		).normalized()
		var elbow := circle_center + bend_direction * circle_radius
		var minimum_margin := 1000000.0
		for capsule_variant in _last_resolved_body_capsules:
			var capsule: Dictionary = capsule_variant
			if not _capsule_constrains_control_forearm(capsule):
				continue
			minimum_margin = minf(
				minimum_margin,
				_segment_segment_distance(
					elbow,
					solved_wrist,
					capsule.get("from", Vector3.ZERO),
					capsule.get("to", Vector3.ZERO)
				) - float(capsule.get("clearance", 0.0)) - CONTROL_FOREARM_RADIUS
			)
		var is_safe := minimum_margin >= CONTROL_ELBOW_SAFETY_BUFFER
		var signed_flare := (elbow - shoulder).dot(outward_axis)
		var forearm_direction := (solved_wrist - elbow).normalized()
		var forearm_shaft_dot := absf(forearm_direction.dot(shaft_direction_boat))
		var flare_overrun := (
			maxf(-CONTROL_ELBOW_MAX_INWARD_FLARE - signed_flare, 0.0)
			+ maxf(signed_flare - CONTROL_ELBOW_MAX_OUTWARD_FLARE, 0.0)
		)
		var shaft_overrun := maxf(forearm_shaft_dot - allowed_shaft_dot, 0.0)
		var natural_score := (
			-absf(elbow.y - desired_elbow_height)
			+ CONTROL_ELBOW_REST_WEIGHT * bend_direction.dot(source_bend)
			+ CONTROL_ELBOW_CONTINUITY_WEIGHT * bend_direction.dot(continuity_bend)
			- CONTROL_ELBOW_FLARE_PENALTY
			* (absf(signed_flare - CONTROL_ELBOW_RELAXED_FLARE) + flare_overrun)
			- CONTROL_TILLER_FOREARM_SHAFT_PENALTY
			* tiller_weight * (forearm_shaft_dot + shaft_overrun)
		)
		if is_safe:
			if not found_safe_candidate or natural_score > best_safe_natural_score:
				best_safe_natural_score = natural_score
				best_safe_direction = bend_direction
			var transport_dot := bend_direction.dot(transport_reference)
			if (
				transport_dot > closest_transport_safe_dot + 0.00001
				or (
					absf(transport_dot - closest_transport_safe_dot) <= 0.00001
					and natural_score > closest_transport_safe_natural_score
				)
			):
				closest_transport_safe_dot = transport_dot
				closest_transport_safe_natural_score = natural_score
				closest_transport_safe_direction = bend_direction
			if minimum_margin >= CONTROL_ELBOW_TRANSPORT_MARGIN and (
				not found_transport_guarded_candidate
				or transport_dot > closest_transport_guarded_dot + 0.00001
				or (
					absf(transport_dot - closest_transport_guarded_dot) <= 0.00001
					and natural_score > closest_transport_guarded_natural_score
				)
			):
				found_transport_guarded_candidate = true
				closest_transport_guarded_dot = transport_dot
				closest_transport_guarded_natural_score = natural_score
				closest_transport_guarded_direction = bend_direction
			found_safe_candidate = true
		elif (
			minimum_margin > best_unsafe_margin + 0.00001
			or (
				absf(minimum_margin - best_unsafe_margin) <= 0.00001
				and natural_score > best_unsafe_natural_score
			)
		):
			best_unsafe_margin = minimum_margin
			best_unsafe_natural_score = natural_score
			best_unsafe_direction = bend_direction

	# The persisted command owns every ordinary runtime branch decision. The final
	# rendered elbow is sampled only as independent clearance evidence, so hand-roll
	# compensation cannot feed back into the next pole selector.
	var selected_target := best_unsafe_direction
	var height_relaxation_active := false
	var settled_height_limit := minf(
		shoulder.y - CONTROL_ELBOW_SETTLED_SHOULDER_DROP,
		desired_elbow_height + CONTROL_ELBOW_SETTLED_HEIGHT_ALLOWANCE
	)
	var driven_pair := _boat.tiller_extension_driven_pair()
	var settled_normal_tiller := (
		tiller_weight >= 0.999
		and _hand_exchange_amount <= 0.02
		and not _boat.tiller_extension_is_blocked()
		and not _boat.tiller_extension_handover_route_active()
		and _pending_extension_delta > 0.000001
		and int(driven_pair.get("mode", -1))
		== WindwardBoat.TillerExtensionPairMode.NORMAL
	)
	if _control_pose_immediate:
		height_relaxed = false
		# Focused pose tools request independent samples. Do not carry a bend
		# branch from the previously sampled runtime state into this one.
		if found_safe_candidate:
			selected_target = best_safe_direction
	else:
		var transport_candidate := best_unsafe_direction
		if found_safe_candidate:
			transport_candidate = (
				closest_transport_guarded_direction
				if found_transport_guarded_candidate
				else closest_transport_safe_direction
			)
		var transport_target_is_safe := false
		if transport_active and projected_transport_target.length_squared() > 0.000001:
			# Reproject the persistent boat-space latch onto the current arm circle.
			var projected_transport_elbow := (
				circle_center + projected_transport_target * circle_radius
			)
			var transport_target_retain_margin := CONTROL_ELBOW_SAFETY_BUFFER
			if tiller_weight <= CONTROL_TILLER_CONTACT_WEIGHT_EPSILON:
				# A flexible sheet hand can keep its existing collision-escape branch
				# through the same tiny incidence band used by the bounded pole step.
				# Retargeting the 48-point lattice at +5 mm made a static sheet arm
				# alternate between adjacent branches while the rigid tiller stayed still.
				transport_target_retain_margin = (
					CONTROL_ELBOW_INCIDENCE_RELEASE_MARGIN
				)
			transport_target_is_safe = (
				_control_forearm_clearance_margin_boat(
					projected_transport_elbow,
					solved_wrist
				) >= transport_target_retain_margin
			)
		if transport_active and not transport_target_is_safe:
			# Prefer a 20 mm interior candidate relative to the latched command;
			# retain the five-millimetre tier when no guarded sample exists.
			projected_transport_target = transport_candidate
			transport_target_boat = (
				circle_center + transport_candidate * circle_radius
			)
			transport_release_generations = 0
		elif not transport_active and transport_entry_required:
			transport_active = true
			projected_transport_target = transport_candidate
			transport_target_boat = (
				circle_center + transport_candidate * circle_radius
			)
			transport_release_generations = 0
		if transport_active:
			# A pure sheet hand may finish a collision escape after the extension route
			# has already released. Once both the rendered and commanded forearms have
			# the full release reserve, re-anchor the persistent target to the current
			# command. The existing two-generation release remains authoritative, while
			# a stale boat-space target can no longer keep a safe settled arm oscillating.
			if (
				tiller_weight <= CONTROL_TILLER_CONTACT_WEIGHT_EPSILON
				and rendered_margin >= CONTROL_ELBOW_TRANSPORT_RELEASE_MARGIN
				and commanded_margin >= CONTROL_ELBOW_TRANSPORT_RELEASE_MARGIN
			):
				projected_transport_target = commanded_bend
				transport_target_boat = commanded_elbow
			var commanded_to_target_angle := INF
			if projected_transport_target.length_squared() > 0.000001:
				commanded_to_target_angle = commanded_bend.angle_to(
					projected_transport_target
				)
			var transport_release_ready := (
				rendered_margin >= CONTROL_ELBOW_TRANSPORT_RELEASE_MARGIN
				and commanded_margin >= CONTROL_ELBOW_TRANSPORT_RELEASE_MARGIN
				and commanded_to_target_angle
				<= CONTROL_ELBOW_TRANSPORT_RELEASE_ANGLE
			)
			if transport_release_ready:
				transport_release_generations += 1
			else:
				transport_release_generations = 0
			if (
				transport_release_generations
				>= CONTROL_ELBOW_TRANSPORT_RELEASE_GENERATIONS
			):
				transport_active = false
				transport_target_boat = Vector3.ZERO
				transport_release_generations = 0
				# Keep the commanded incumbent on the release generation; switching to
				# a measured render here would reintroduce a one-frame pole jump.
				selected_target = commanded_bend
			else:
				selected_target = projected_transport_target
			height_relaxed = false
		else:
			selected_target = commanded_bend
			if not settled_normal_tiller:
				height_relaxed = false
			else:
				# Ordinary runtime deliberately preserves its commanded branch for
				# continuity. The authored source branch can nevertheless be a safe but
				# visibly raised boxing guard, so relax only that absolute height defect.
				# Once inside the band, latch the incumbent again; the release margin
				# prevents breathing or small steering changes from restarting a search.
				if height_relaxed and (
					commanded_elbow.y
					> settled_height_limit
					+ CONTROL_ELBOW_HEIGHT_LATCH_RELEASE_MARGIN
				):
					height_relaxed = false
				elif not height_relaxed and commanded_elbow.y <= settled_height_limit:
					height_relaxed = true
				if not height_relaxed and found_safe_candidate:
					var natural_elbow := (
						circle_center + best_safe_direction * circle_radius
					)
					if natural_elbow.y < commanded_elbow.y - 0.0001:
						selected_target = best_safe_direction
						height_relaxation_active = true
	# During a tack the flexible sheet arm can already have a usable rendered and
	# commanded bend while an older collision-escape latch remains active. Chasing
	# that boat-space latch around the moving elbow circle feeds hand-roll changes
	# back into the pole and makes the elbow alternate every frame. Preserve the
	# actual incumbent inside the existing incidence band; if either pose becomes
	# unsafe, the guarded transport and emergency arc below still take authority.
	var incumbent_shaft_dot := absf((solved_wrist - commanded_elbow).normalized().dot(shaft_direction_boat))
	if tiller_weight > 0.95 and incumbent_shaft_dot > CONTROL_TILLER_FOREARM_SHAFT_MAX_DOT and found_safe_candidate:
		var natural_elbow := circle_center + best_safe_direction * circle_radius
		var natural_shaft_dot := absf((solved_wrist - natural_elbow).normalized().dot(shaft_direction_boat))
		if natural_shaft_dot < incumbent_shaft_dot - 0.01:
			selected_target = best_safe_direction
			height_relaxation_active = false
	var tack_sheet_incumbent_is_usable := (
		transport_active
		and tiller_weight <= CONTROL_TILLER_CONTACT_WEIGHT_EPSILON
		and _boat.tiller_extension_handover_route_active()
		and rendered_margin >= CONTROL_ELBOW_INCIDENCE_RELEASE_MARGIN
		and commanded_margin >= CONTROL_ELBOW_INCIDENCE_RELEASE_MARGIN
	)
	if tack_sheet_incumbent_is_usable:
		selected_target = commanded_bend
	var selected_direction := selected_target
	# Every ordinary runtime step advances from the last command sent to TwoBoneIK.
	var rate_limit_incumbent := commanded_bend
	var rate_limit_incumbent_is_safe := (
		rendered_margin >= CONTROL_ELBOW_INCIDENCE_RELEASE_MARGIN
		and commanded_margin >= CONTROL_ELBOW_INCIDENCE_RELEASE_MARGIN
	)
	var step_delta := clampf(_pending_extension_delta, 0.0, 0.10)
	if (
		not _control_pose_immediate
		and step_delta > 0.000001
		and rate_limit_incumbent.length_squared() > 0.000001
	):
		var bend_angle := rate_limit_incumbent.angle_to(selected_target)
		# A long render frame must not spend an arbitrarily large angular budget in
		# one visible pose. The per-frame cap also protects the no-safe fallback below
		# from ever selecting an antipodal elbow branch in a single modifier cycle.
		var max_bend_step := minf(
			CONTROL_ELBOW_MAX_ANGULAR_SPEED * step_delta,
			CONTROL_ELBOW_MAX_FRAME_ROTATION
		)
		if height_relaxation_active:
			# Height relaxation is a settled-pose correction. Bound the visible pole
			# arc in metres as well as by the ordinary six-degree cap; the pole radius
			# is larger than the elbow circle and is therefore the stricter continuity
			# contract at any arm reach or render cadence.
			max_bend_step = minf(
				max_bend_step,
				CONTROL_ELBOW_HEIGHT_RELAX_MAX_POLE_STEP / CONTROL_ELBOW_POLE_DISTANCE
			)
		if bend_angle > max_bend_step and max_bend_step > 0.000001:
			var limited_direction := rate_limit_incumbent.slerp(
				selected_target,
				max_bend_step / bend_angle
			).normalized()
			var limited_elbow := circle_center + limited_direction * circle_radius
			var limited_margin := INF
			for capsule_variant in _last_resolved_body_capsules:
				var capsule: Dictionary = capsule_variant
				if not _capsule_constrains_control_forearm(capsule):
					continue
				limited_margin = minf(
					limited_margin,
					_segment_segment_distance(
						limited_elbow,
						solved_wrist,
						capsule.get("from", Vector3.ZERO),
						capsule.get("to", Vector3.ZERO)
					) - float(capsule.get("clearance", 0.0)) - CONTROL_FOREARM_RADIUS
				)
			if limited_margin >= CONTROL_ELBOW_INCIDENCE_RELEASE_MARGIN:
				selected_direction = limited_direction
			elif rate_limit_incumbent_is_safe:
				# Never snap across an unsafe arc while the current branch remains
				# feasible. Retaining it is both continuous and collision-safe.
				selected_direction = rate_limit_incumbent
			elif found_safe_candidate:
				# The incumbent is already unsafe, so retaining it would violate the
				# body-clearance contract. Find the first safe point along the
				# shortest correction arc instead of jumping to the distant lattice
				# sample in one frame.
				var unsafe_t := 0.0
				var safe_t := 1.0
				var found_safe_arc_point := false
				for arc_step in 16:
					var arc_t := float(arc_step + 1) / 16.0
					var arc_direction := rate_limit_incumbent.slerp(
						selected_target,
						arc_t
					).normalized()
					var arc_elbow := circle_center + arc_direction * circle_radius
					var arc_margin := 1000000.0
					for capsule_variant in _last_resolved_body_capsules:
						var capsule: Dictionary = capsule_variant
						if not _capsule_constrains_control_forearm(capsule):
							continue
						arc_margin = minf(
							arc_margin,
							_segment_segment_distance(
								arc_elbow,
								solved_wrist,
								capsule.get("from", Vector3.ZERO),
								capsule.get("to", Vector3.ZERO)
							) - float(capsule.get("clearance", 0.0)) - CONTROL_FOREARM_RADIUS
						)
					if arc_margin >= CONTROL_ELBOW_SAFETY_BUFFER:
						safe_t = arc_t
						found_safe_arc_point = true
						break
					unsafe_t = arc_t
				if found_safe_arc_point:
					for _refinement_step in 8:
						var middle_t := (unsafe_t + safe_t) * 0.5
						var middle_direction := rate_limit_incumbent.slerp(
							selected_target,
							middle_t
						).normalized()
						var middle_elbow := circle_center + middle_direction * circle_radius
						var middle_margin := 1000000.0
						for capsule_variant in _last_resolved_body_capsules:
							var capsule: Dictionary = capsule_variant
							if not _capsule_constrains_control_forearm(capsule):
								continue
							middle_margin = minf(
								middle_margin,
								_segment_segment_distance(
									middle_elbow,
									solved_wrist,
									capsule.get("from", Vector3.ZERO),
									capsule.get("to", Vector3.ZERO)
								) - float(capsule.get("clearance", 0.0)) - CONTROL_FOREARM_RADIUS
							)
						if middle_margin >= CONTROL_ELBOW_SAFETY_BUFFER:
							safe_t = middle_t
						else:
							unsafe_t = middle_t
					# The first fully safe point may be tens of degrees away after an
					# external body/target change. Never bypass the visible elbow budget
					# to reach it; the proactive transport above normally prevents this
					# fallback, and a genuine emergency continues over later generations.
					var bounded_safe_t := minf(
						safe_t,
						max_bend_step / maxf(bend_angle, 0.000001)
					)
					selected_direction = rate_limit_incumbent.slerp(
						selected_target,
						bounded_safe_t
					).normalized()
			else:
				# If every sampled bend is marginally unsafe, there is no collision-free
				# branch to teleport to. Move toward the least-bad bend at the same visible
				# angular limit while the semantic hand target/extension solver recovers.
				selected_direction = limited_direction
	if height_relaxation_active:
		var relaxed_elbow := circle_center + selected_direction * circle_radius
		# Never trade the visible boxing defect for an upward detour around the
		# circle. A temporarily unsuitable shortest arc simply keeps the incumbent.
		if relaxed_elbow.y > commanded_elbow.y + 0.000001:
			selected_direction = commanded_bend
		else:
			height_relaxed = relaxed_elbow.y <= settled_height_limit
	if not _control_pose_immediate:
		if hand_bone == _left_hand_bone:
			_left_elbow_transport_active = transport_active
			_left_elbow_transport_target_boat = transport_target_boat
			_left_elbow_transport_release_generations = (
				transport_release_generations
			)
			_left_elbow_height_relaxed = height_relaxed
		else:
			_right_elbow_transport_active = transport_active
			_right_elbow_transport_target_boat = transport_target_boat
			_right_elbow_transport_release_generations = (
				transport_release_generations
			)
			_right_elbow_height_relaxed = height_relaxed
	if hand_bone == _left_hand_bone:
		_left_elbow_bend_boat = selected_direction
		_left_expected_elbow_boat = circle_center + selected_direction * circle_radius
	else:
		_right_elbow_bend_boat = selected_direction
		_right_expected_elbow_boat = circle_center + selected_direction * circle_radius
	return circle_center + selected_direction * CONTROL_ELBOW_POLE_DISTANCE


func _control_forearm_clearance_margin_boat(
	elbow_boat: Vector3,
	wrist_boat: Vector3
) -> float:
	var minimum_margin := 1000000.0
	for capsule_variant in _last_resolved_body_capsules:
		var capsule: Dictionary = capsule_variant
		if not _capsule_constrains_control_forearm(capsule):
			continue
		minimum_margin = minf(
			minimum_margin,
			_segment_segment_distance(
				elbow_boat,
				wrist_boat,
				capsule.get("from", Vector3.ZERO),
				capsule.get("to", Vector3.ZERO)
			) - float(capsule.get("clearance", 0.0)) - CONTROL_FOREARM_RADIUS
		)
	return minimum_margin


func _capsule_constrains_control_forearm(capsule: Dictionary) -> bool:
	# Shoulder points are present so the extension can choose a comfortable grip,
	# and calf points protect the full shaft. Treating either as an obstacle for
	# the forearm itself made the elbow solver reject its own anatomical branch and
	# alternate between antipodal solutions. Arm clearance is intentionally
	# enforced against the torso and thighs; those are the actual self-intersection
	# risks for the seated and handover poses.
	var label := StringName(capsule.get("label", &""))
	return label == &"torso" or String(label).ends_with("thigh")


func _bone_origin_boat(bone_index: int) -> Vector3:
	if bone_index < 0 or not is_instance_valid(_skeleton):
		return Vector3.ZERO
	return _boat.to_local(
		(_skeleton.global_transform * _skeleton.get_bone_global_pose(bone_index)).origin
	)


func _closest_point_on_segment(point: Vector3, from: Vector3, to: Vector3) -> Vector3:
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared < 0.000001:
		return from
	return from + segment * clampf((point - from).dot(segment) / length_squared, 0.0, 1.0)


func _segment_segment_distance(
	p1: Vector3,
	q1: Vector3,
	p2: Vector3,
	q2: Vector3
) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var epsilon := 0.000001
	var s := 0.0
	var t := 0.0
	if a <= epsilon and e <= epsilon:
		return p1.distance_to(p2)
	if a <= epsilon:
		t = clampf(d2.dot(r) / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= epsilon:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denominator := a * e - b * b
			if not is_zero_approx(denominator):
				s = clampf((b * d2.dot(r) - c * e) / denominator, 0.0, 1.0)
			t = (b * s + d2.dot(r)) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)


func control_elbow_pole_boat(side: float, tiller: bool) -> Vector3:
	var pole := _left_hand_pole if (tiller == _tiller_is_left) else _right_hand_pole
	if not is_instance_valid(pole):
		return Vector3.ZERO
	return _boat.to_local(pole.global_position)
func _ik_target_for_palm(
	hand_anchor: Node3D,
	hand_bone: int,
	palm_goal: Vector3
) -> Vector3:
	if not is_instance_valid(hand_anchor) or hand_bone < 0:
		return palm_goal
	# BoneAttachment transforms are refreshed only after the full modifier cycle.
	# Reuse the previous final arm orientation captured at the last arm modifier;
	# this converges the visible palm to the goal without accumulating error.
	var offset_in_skeleton := (
		_left_final_palm_offset_in_skeleton
		if hand_bone == _left_hand_bone
		else _right_final_palm_offset_in_skeleton
	)
	if not _final_palm_offsets_valid:
		offset_in_skeleton = (
			_skeleton.get_bone_global_pose(hand_bone).basis
			* hand_anchor.position
		)
	var offset_world := _skeleton.global_basis * offset_in_skeleton
	return palm_goal - offset_world


func _ik_target_for_palm_with_basis(
	hand_anchor: Node3D,
	hand_bone: int,
	palm_goal: Vector3,
	desired_basis_skeleton: Basis
) -> Vector3:
	if not is_instance_valid(hand_anchor) or hand_bone < 0:
		return palm_goal
	var offset_in_skeleton := desired_basis_skeleton * hand_anchor.position
	var offset_world := _skeleton.global_basis * offset_in_skeleton
	return palm_goal - offset_world


func hand_exchange_amount() -> float:
	return _hand_exchange_amount


func hand_exchange_progress() -> float:
	return _hand_exchange_progress


func _create_held_mainsheet() -> void:
	_held_mainsheet_material = StandardMaterial3D.new()
	_held_mainsheet_material.albedo_color = Color(0.86, 0.77, 0.55)
	_held_mainsheet_material.roughness = 0.72
	_held_mainsheet_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_held_mainsheet = MeshInstance3D.new()
	_held_mainsheet.name = "HeldMainsheet"
	_held_mainsheet.mesh = ImmediateMesh.new()
	_held_mainsheet.layers = 1
	_held_mainsheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_held_mainsheet)


func _update_held_mainsheet() -> void:
	if not _sheet_grip_anchor:
		return
	var ratchet := _boat.get_node_or_null("RatchetBlock") as IlcaHardwarePart
	var start_boat := (
		_boat.to_local(ratchet.rope_anchor_global(&"sheave"))
		if ratchet
		else MAIN_SHEET_BLOCK_POSITION
	)
	var hand_boat := _boat.to_local(_sheet_grip_anchor.global_position)
	# Keep the route guide continuous through the tack centre. signf(hand.x)
	# mirrored every control point in one frame and produced a 25 cm rope pop.
	var route_side := clampf(
		hand_boat.x / maxf(SHEET_TARGET_LATERAL, 0.01),
		-1.0,
		1.0
	)
	var assist_weight := smoothstep(0.0, 1.0, _sheet_assist_grip_amount)
	var tension_holder := hand_boat
	if assist_weight > 0.001 and is_instance_valid(_tiller_hand_anchor):
		# The assist contact is expressed in the rendered hand frame: just off
		# the extension channel under the ring/little fingers. The loaded line
		# therefore reaches a real hand instead of a boat-space phantom point.
		var assist_contact_global := (
			_tiller_hand_anchor.global_position
			+ _tiller_hand_anchor.global_basis
			* Vector3(0.0, -0.006, 0.020)
		)
		var assist_contact := _boat.to_local(assist_contact_global)
		# During acquisition this waypoint moves continuously off the primary
		# contact. The rope still continues to the primary hand until the assist
		# grip is complete, so no frame is visually or physically unheld.
		tension_holder = hand_boat.lerp(assist_contact, assist_weight)
	var desired_loaded_leg := _choose_held_mainsheet_route(
		start_boat,
		tension_holder,
		route_side
	)
	# Always keep the same 37-point topology: 19 points from the ratchet to the
	# tension holder plus 18 new points to the primary hand. When assist reaches
	# zero the second span collapses onto the hand instead of disappearing in one
	# frame, so downstream route indices retain the same physical meaning.
	var desired_tail_leg := _choose_held_mainsheet_tail_route(
		tension_holder,
		hand_boat,
		route_side,
		assist_weight
	)
	var desired_route := desired_loaded_leg.duplicate()
	for tail_index in range(1, desired_tail_leg.size()):
		desired_route.append(desired_tail_leg[tail_index])
	_held_mainsheet_route_boat = _stabilize_held_mainsheet_route(desired_route)
	_held_mainsheet_loaded_leg = PackedVector3Array()
	_held_mainsheet_tail_leg = PackedVector3Array()
	for loaded_index in range(HELD_SHEET_CURVE_STEPS + 1):
		_held_mainsheet_loaded_leg.append(_held_mainsheet_route_boat[loaded_index])
	for tail_index in range(HELD_SHEET_CURVE_STEPS, _held_mainsheet_route_boat.size()):
		_held_mainsheet_tail_leg.append(_held_mainsheet_route_boat[tail_index])
	_build_held_mainsheet_tube()


func _stabilize_held_mainsheet_route(
	desired_route: PackedVector3Array
) -> PackedVector3Array:
	if _held_mainsheet_route_boat.size() != desired_route.size():
		_held_mainsheet_route_generation = _extension_pose_generation
		return desired_route
	var stabilized := _held_mainsheet_route_boat.duplicate()
	# The ratchet and primary SheetGripAnchor are fixed physical endpoints. The
	# shared index 18 moves continuously from the primary hand to the assist hand;
	# rate-limit that transferring contact with the other interior points so a
	# low-FPS assist-weight update cannot pull 7 cm of rope in one generation.
	stabilized[0] = desired_route[0]
	stabilized[stabilized.size() - 1] = desired_route[desired_route.size() - 1]
	if _held_mainsheet_route_generation == _extension_pose_generation:
		return stabilized
	_held_mainsheet_route_generation = _extension_pose_generation
	for point_index in range(1, desired_route.size() - 1):
		stabilized[point_index] = stabilized[point_index].move_toward(
			desired_route[point_index],
			HELD_SHEET_ROUTE_POINT_MAX_STEP
		)
	# A moving join and exact primary-hand endpoint can change the tail chord even
	# when every individual point obeys the 20 mm budget. Correct the tail's
	# chord-relative gravity component within that same budget; otherwise the
	# pointwise lag briefly looks like an upward arch at overlap/regrip boundaries.
	var gravity_boat := _held_mainsheet_gravity_direction_boat()
	for point_index in range(
		HELD_SHEET_CURVE_STEPS + 1,
		desired_route.size() - 1
	):
		var tail_ratio := (
			float(point_index - HELD_SHEET_CURVE_STEPS)
			/ float(HELD_SHEET_CURVE_STEPS)
		)
		var desired_chord_point := desired_route[HELD_SHEET_CURVE_STEPS].lerp(
			desired_route[desired_route.size() - 1],
			tail_ratio
		)
		var desired_gravity_deviation := (
			desired_route[point_index] - desired_chord_point
		).dot(gravity_boat)
		var stabilized_chord_point := stabilized[HELD_SHEET_CURVE_STEPS].lerp(
			stabilized[stabilized.size() - 1],
			tail_ratio
		)
		var stabilized_gravity_deviation := (
			stabilized[point_index] - stabilized_chord_point
		).dot(gravity_boat)
		var gravity_corrected_point := (
			stabilized[point_index]
			+ gravity_boat * (
				desired_gravity_deviation - stabilized_gravity_deviation
			)
		)
		stabilized[point_index] = _held_mainsheet_route_boat[point_index].move_toward(
			gravity_corrected_point,
			HELD_SHEET_ROUTE_POINT_MAX_STEP
		)
	return stabilized


func _choose_held_mainsheet_route(
	start_boat: Vector3,
	hand_boat: Vector3,
	route_side: float
) -> PackedVector3Array:
	# This is the loaded block-to-hand span. It should be almost taut, not held up
	# by absolute cockpit-height guides. Start from the endpoint chord with only a
	# subtle gravity sag, then add the smallest collision detour required by the
	# live post-leg capsules.
	var candidate_routes: Array[PackedVector3Array] = []
	var candidate_margins: Array[float] = []
	var best_route := PackedVector3Array()
	var best_margin := -INF
	var shortest_safe_index := -1
	var shortest_safe_length := INF
	var gravity_offset := (
		_held_mainsheet_gravity_direction_boat()
		* HELD_SHEET_LOADED_SAG
	)
	for height_offset in [0.0, 0.05, 0.10, 0.15, 0.20, 0.25]:
		for lateral_offset in [0.0, 0.06, 0.12, 0.18]:
			var midpoint_offset: Vector3 = (
				gravity_offset
				+ Vector3(route_side * lateral_offset, height_offset, 0.0)
			)
			var candidate := _sample_held_mainsheet_parabolic_span(
				start_boat,
				hand_boat,
				midpoint_offset
			)
			# The endpoints already move continuously between the two real hand
			# contacts. Forcing a latched spline length changed the curve topology when
			# ASSIST_RELEASE returned to PULL and produced a 20 cm one-frame rope pop.
			var margin := _held_mainsheet_leg_margin(candidate)
			candidate_routes.append(candidate)
			candidate_margins.append(margin)
			if margin > best_margin:
				best_margin = margin
				best_route = candidate
			if margin >= 0.004:
				var candidate_length := _held_sheet_route_length(candidate)
				if candidate_length < shortest_safe_length:
					shortest_safe_length = candidate_length
					shortest_safe_index = candidate_routes.size() - 1
	# Keep the current guide topology while it remains collision-free. Without
	# this hysteresis, the complete rope snapped 5-12 cm between neighbouring
	# candidates as the W/S hand crossed a discrete margin boundary.
	if (
		_held_mainsheet_route_candidate_index >= 0
		and _held_mainsheet_route_candidate_index < candidate_routes.size()
		and candidate_margins[_held_mainsheet_route_candidate_index] >= -0.010
	):
		return candidate_routes[_held_mainsheet_route_candidate_index]
	if shortest_safe_index >= 0:
		_held_mainsheet_route_candidate_index = shortest_safe_index
		return candidate_routes[shortest_safe_index]
	_held_mainsheet_route_candidate_index = candidate_margins.find(best_margin)
	return best_route


func _fit_held_sheet_route_length(
	route: PackedVector3Array,
	target_length: float
) -> PackedVector3Array:
	# The primary and extension hands are roughly ten centimetres apart. Moving
	# the loaded endpoint directly between them changed the visible tensioned line
	# by 6-9 cm even though sheet trim was frozen. Preserve the physical working
	# length by scaling the curve's deviation from its endpoint chord; endpoints
	# still remain exactly on the ratchet and the hand carrying the load.
	if route.size() < 3:
		return route
	var start := route[0]
	var finish := route[route.size() - 1]
	var direct_length := start.distance_to(finish)
	var desired := maxf(target_length, direct_length + 0.0001)
	var current_length := _held_sheet_route_length(route)
	if absf(current_length - desired) <= 0.00025:
		return route
	var low_factor := 0.0
	var high_factor := 1.0
	if current_length < desired:
		low_factor = 1.0
		for _expand_guard in 8:
			high_factor *= 1.75
			if _held_sheet_route_length(
				_scale_held_sheet_route_deviation(route, high_factor)
			) >= desired:
				break
	for _refine_step in 14:
		var factor := (low_factor + high_factor) * 0.5
		var candidate := _scale_held_sheet_route_deviation(route, factor)
		if _held_sheet_route_length(candidate) < desired:
			low_factor = factor
		else:
			high_factor = factor
	return _scale_held_sheet_route_deviation(
		route,
		(low_factor + high_factor) * 0.5
	)


func _scale_held_sheet_route_deviation(
	route: PackedVector3Array,
	factor: float
) -> PackedVector3Array:
	var scaled := PackedVector3Array()
	var start := route[0]
	var finish := route[route.size() - 1]
	for point_index in route.size():
		var t := float(point_index) / float(route.size() - 1)
		var chord_point := start.lerp(finish, t)
		scaled.append(chord_point + (route[point_index] - chord_point) * factor)
	return scaled


func _sample_held_mainsheet_parabolic_span(
	start_boat: Vector3,
	finish_boat: Vector3,
	midpoint_offset_boat: Vector3
) -> PackedVector3Array:
	var route := PackedVector3Array()
	for step in range(HELD_SHEET_CURVE_STEPS + 1):
		var t := float(step) / float(HELD_SHEET_CURVE_STEPS)
		route.append(
			start_boat.lerp(finish_boat, t)
			+ midpoint_offset_boat * (4.0 * t * (1.0 - t))
		)
	return route


func _choose_held_mainsheet_tail_route(
	start_boat: Vector3,
	hand_boat: Vector3,
	route_side: float,
	assist_weight: float
) -> PackedVector3Array:
	# The hand-to-hand span is slack only while the assist hand carries the load
	# and the primary hand is actually releasing. Overlap and regrip remain taut;
	# the existing point-rate limiter makes the transition continuous. Gravity is
	# converted into boat space so future heel/pitch does not make the rope sag in
	# an authored local-Y direction.
	var primary_release_weight := clampf(
		(1.0 - _sheet_hand_grip_amount) / maxf(1.0 - SHEET_RELEASED_GRIP, 0.001),
		0.0,
		1.0
	)
	var release_phase_weight := (
		1.0
		if _sheet_motion_phase == SheetMotionPhase.PRIMARY_RELEASE_REACH
		else 0.0
	)
	var slack_weight := (
		clampf(assist_weight, 0.0, 1.0)
		* smoothstep(0.0, 1.0, primary_release_weight)
		* release_phase_weight
	)
	var span := start_boat.distance_to(hand_boat)
	var sag := minf(
		HELD_SHEET_TAIL_SAG_MAX,
		span * HELD_SHEET_TAIL_SAG_SPAN_RATIO
	) * slack_weight
	var gravity_sag_offset := _held_mainsheet_gravity_direction_boat() * sag
	var best_route := PackedVector3Array()
	var best_margin := -INF
	# Prefer the complete gravity sag. If it reaches a live leg capsule, first
	# route it outboard, then reduce the sag only as much as collision clearance
	# requires. This stays deterministic and never resurrects the old upward arch.
	for sag_scale in [1.0, 0.75, 0.50, 0.25, 0.0]:
		var shortest_safe_route := PackedVector3Array()
		var shortest_safe_length := INF
		for lateral_offset in [0.0, 0.04, 0.08, 0.12, 0.18]:
			var midpoint_offset: Vector3 = (
				gravity_sag_offset * sag_scale
				+ Vector3(
					route_side * lateral_offset * clampf(assist_weight, 0.0, 1.0),
					0.0,
					0.0
				)
			)
			var candidate := _sample_held_mainsheet_parabolic_span(
				start_boat,
				hand_boat,
				midpoint_offset
			)
			var margin := _held_mainsheet_leg_margin(candidate)
			if margin > best_margin:
				best_margin = margin
				best_route = candidate
			if margin >= 0.004:
				var candidate_length := _held_sheet_route_length(candidate)
				if candidate_length < shortest_safe_length:
					shortest_safe_length = candidate_length
					shortest_safe_route = candidate
		if not shortest_safe_route.is_empty():
			return shortest_safe_route
	return best_route


func _held_mainsheet_gravity_direction_boat() -> Vector3:
	var gravity_boat := (
		_boat.global_basis.orthonormalized().inverse()
		* Vector3.DOWN
	)
	if gravity_boat.length_squared() <= 0.000001:
		return Vector3.DOWN
	return gravity_boat.normalized()


func _held_mainsheet_leg_margin(route: PackedVector3Array) -> float:
	if route.size() < 2:
		return -INF
	var minimum_margin := INF
	var found_leg := false
	for capsule_variant in _last_resolved_body_capsules:
		var capsule: Dictionary = capsule_variant
		var label := String(capsule.get("label", ""))
		if not (label.ends_with("thigh") or label.ends_with("calf")):
			continue
		found_leg = true
		var required_distance := (
			float(capsule.get("clearance", 0.0))
			+ HELD_SHEET_RADIUS
			+ HELD_SHEET_BODY_GAP
		)
		for route_index in range(route.size() - 1):
			minimum_margin = minf(
				minimum_margin,
				_segment_segment_distance(
					route[route_index],
					route[route_index + 1],
					capsule["from"],
					capsule["to"]
				) - required_distance
			)
	return minimum_margin if found_leg else INF


func held_mainsheet_route_boat_positions() -> PackedVector3Array:
	return _held_mainsheet_route_boat.duplicate()


func held_mainsheet_working_length() -> float:
	var length := 0.0
	for route_index in range(_held_mainsheet_route_boat.size() - 1):
		length += _held_mainsheet_route_boat[route_index].distance_to(
			_held_mainsheet_route_boat[route_index + 1]
		)
	return length


func sheet_transfer_latched_length() -> float:
	return _sheet_transfer_latched_length


func held_mainsheet_primary_leg_boat_positions() -> PackedVector3Array:
	return _held_mainsheet_loaded_leg.duplicate()


func held_mainsheet_assist_leg_boat_positions() -> PackedVector3Array:
	return _held_mainsheet_tail_leg.duplicate()


func held_mainsheet_loaded_length() -> float:
	return _held_sheet_route_length(_held_mainsheet_loaded_leg)


func held_mainsheet_rendered_loaded_length() -> float:
	return _held_sheet_route_length(_held_mainsheet_loaded_leg)


func _sheet_transfer_owns_loaded_length() -> bool:
	return _sheet_motion_phase in [
		SheetMotionPhase.ASSIST_OVERLAP,
		SheetMotionPhase.PRIMARY_RELEASE_REACH,
		SheetMotionPhase.REGRIP,
		SheetMotionPhase.ASSIST_RELEASE,
	] or (
		_sheet_motion_phase in [SheetMotionPhase.EASE, SheetMotionPhase.HOLD]
		and _sheet_assist_grip_amount > 0.001
	)


func held_mainsheet_tail_length() -> float:
	return _held_sheet_route_length(_held_mainsheet_tail_leg)


func _held_sheet_route_length(route: PackedVector3Array) -> float:
	var length := 0.0
	for route_index in range(route.size() - 1):
		length += route[route_index].distance_to(route[route_index + 1])
	return length


func _build_held_mainsheet_tube() -> void:
	var mesh := _held_mainsheet.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if _held_mainsheet_route_boat.size() < 2:
		return
	var points := PackedVector3Array()
	for point_boat in _held_mainsheet_route_boat:
		var local_point := to_local(_boat.to_global(point_boat))
		if (
			points.is_empty()
			or points[points.size() - 1].distance_squared_to(local_point) > 0.00000001
		):
			points.append(local_point)
	if points.size() < 2:
		return
	var ring_normals: Array[Vector3] = []
	var ring_binormals: Array[Vector3] = []
	var previous_normal := Vector3.ZERO
	for point_index in points.size():
		var tangent := Vector3.ZERO
		if point_index == 0:
			tangent = points[1] - points[0]
		elif point_index == points.size() - 1:
			tangent = points[-1] - points[-2]
		else:
			tangent = points[point_index + 1] - points[point_index - 1]
		tangent = tangent.normalized()
		var normal := previous_normal - tangent * previous_normal.dot(tangent)
		if normal.length_squared() <= 0.000001:
			var reference := Vector3.UP
			if absf(tangent.dot(reference)) > 0.92:
				reference = Vector3.RIGHT
			normal = tangent.cross(reference)
		normal = normal.normalized()
		var binormal := tangent.cross(normal).normalized()
		ring_normals.append(normal)
		ring_binormals.append(binormal)
		previous_normal = normal
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _held_mainsheet_material)
	for point_index in range(points.size() - 1):
		for side_index in HELD_SHEET_SIDES:
			var next_side := (side_index + 1) % HELD_SHEET_SIDES
			var angle_a := TAU * float(side_index) / float(HELD_SHEET_SIDES)
			var angle_b := TAU * float(next_side) / float(HELD_SHEET_SIDES)
			var radial_a := (
				ring_normals[point_index] * cos(angle_a)
				+ ring_binormals[point_index] * sin(angle_a)
			).normalized()
			var radial_b := (
				ring_normals[point_index] * cos(angle_b)
				+ ring_binormals[point_index] * sin(angle_b)
			).normalized()
			var radial_c := (
				ring_normals[point_index + 1] * cos(angle_a)
				+ ring_binormals[point_index + 1] * sin(angle_a)
			).normalized()
			var radial_d := (
				ring_normals[point_index + 1] * cos(angle_b)
				+ ring_binormals[point_index + 1] * sin(angle_b)
			).normalized()
			var a := points[point_index] + radial_a * HELD_SHEET_RADIUS
			var b := points[point_index] + radial_b * HELD_SHEET_RADIUS
			var c := points[point_index + 1] + radial_c * HELD_SHEET_RADIUS
			var d := points[point_index + 1] + radial_d * HELD_SHEET_RADIUS
			_add_held_sheet_vertex(mesh, a, radial_a)
			_add_held_sheet_vertex(mesh, c, radial_c)
			_add_held_sheet_vertex(mesh, b, radial_b)
			_add_held_sheet_vertex(mesh, b, radial_b)
			_add_held_sheet_vertex(mesh, c, radial_c)
			_add_held_sheet_vertex(mesh, d, radial_d)
	mesh.surface_end()


func _add_held_sheet_vertex(
	mesh: ImmediateMesh,
	position: Vector3,
	normal: Vector3
) -> void:
	mesh.surface_set_normal(normal)
	mesh.surface_add_vertex(position)

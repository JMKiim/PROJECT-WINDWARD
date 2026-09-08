extends Node3D

## Isolated authored-clip actor. It never instantiates the production sailor or
## its control solver. Runtime blends authored local bone tracks; no limb IK.
const RIG := preload("res://src/boat/assets/sailor_rig_base.tscn")
const LAYOUT := preload("res://src/boat/animation/rudder_layer_layout.gd")
const GRIP := preload("res://src/boat/animation/authored_grip_profile.gd")
const HIKE := preload("res://src/boat/animation/hiking_port_source.tres")
const SHEET_STUDY := preload("res://src/boat/animation/sheet_stroke_player.gd")
const BODY_SCALE := 1.75 / 1.819586
const INSPECTION_BODY := preload("res://src/boat/animation/rudder_inspection_body.gdshader")

var skeleton: Skeleton3D
var players: Dictionary = {}
var trees: Dictionary = {}
var seat_side := LAYOUT.PORT
var amount := 0.0
var hike := 0.0
var hike_target := 0.0
var grip_phase := "HOLD"
var grip_loosen := 0.0
const GRIP_SECONDS := 0.18
const HIKE_RATE := 0.35
var body_material: ShaderMaterial
var sheet_study: Node


func _ready() -> void:
	var pose := Node3D.new()
	pose.name = "Pose"
	pose.rotation.y = PI * 0.5
	add_child(pose)
	var rig := RIG.instantiate() as Node3D
	rig.name = "Rig"
	rig.scale = Vector3.ONE * BODY_SCALE
	_disable_modifiers(rig)
	pose.add_child(rig)
	skeleton = rig.get_node("Armature/GeneralSkeleton")
	(rig.get_node("AnimationPlayer") as AnimationPlayer).active = false
	for layer in LAYOUT.LAYERS:
		var player := AnimationPlayer.new()
		player.name = "Rudder_" + String(layer)
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		add_child(player)
		var library := AnimationLibrary.new()
		for side in [LAYOUT.PORT, LAYOUT.STARBOARD]:
			for level in HIKE.LEVELS:
				var clip := load(LAYOUT.path(side, layer, level)) as Animation
				if clip == null:
					push_error("Missing authored layer; use the safe launcher to bake rudder/hiking layers")
					return
				library.add_animation(StringName(_clip_name(side, level)), clip)
		player.add_animation_library(&"rudder", library)
		player.play("rudder/" + LAYOUT.side_name(seat_side))
		players[layer] = player
		var tree := AnimationTree.new()
		tree.name = "Blend_" + String(layer)
		tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var graph := AnimationNodeBlendTree.new()
		for branch in ["lo", "hi"]:
			graph.add_node(branch, AnimationNodeAnimation.new())
			graph.add_node(branch + "_seek", AnimationNodeTimeSeek.new())
			graph.connect_node(branch + "_seek", 0, branch)
		graph.add_node("mix", AnimationNodeBlend2.new())
		graph.connect_node("mix", 0, "lo_seek")
		graph.connect_node("mix", 1, "hi_seek")
		graph.connect_node("output", 0, "mix")
		tree.tree_root = graph
		add_child(tree)
		tree.anim_player = tree.get_path_to(player)
		tree.active = true
		trees[layer] = tree
	_tint_face()
	_configure_body_material()
	sheet_study = SHEET_STUDY.new()
	add_child(sheet_study)
	sheet_study.setup(self)
	set_amount(0.0)


func set_amount(value: float) -> void:
	if not is_finite(value) or players.size() != LAYOUT.LAYERS.size():
		return
	amount = clampf(value, -1.0, 1.0)
	if sheet_study != null and sheet_study.enabled:
		amount = 0.0
	var coordinate := hike * (HIKE.LEVELS - 1)
	var low := mini(int(coordinate), HIKE.LEVELS - 2)
	for layer in LAYOUT.LAYERS:
		var tree: AnimationTree = trees[layer]
		var graph := tree.tree_root as AnimationNodeBlendTree
		(graph.get_node("lo") as AnimationNodeAnimation).animation = "rudder/" + _clip_name(seat_side, low)
		(graph.get_node("hi") as AnimationNodeAnimation).animation = "rudder/" + _clip_name(seat_side, low + 1)
		tree.set("parameters/lo_seek/seek_request", amount + 1.0)
		tree.set("parameters/hi_seek/seek_request", amount + 1.0)
		tree.set("parameters/mix/blend_amount", coordinate - low)
		tree.advance(0.0)
	if sheet_study != null and sheet_study.enabled:
		sheet_study.sample()
	# A guided grip loosens slightly before sliding, and closes before HOLD.
	# Reapply from the sampled clip, never accumulate rotations. Thumb stays on.
	if grip_loosen > 0.0:
		for digit in ["Index", "Middle", "Ring", "Little"]:
			for segment in ["Proximal", "Intermediate", "Distal"]:
				var bone := skeleton.find_bone(tiller_hand() + digit + segment)
				var held := skeleton.get_bone_pose_rotation(bone)
				var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
				skeleton.set_bone_pose_rotation(bone, held.slerp(rest, 0.10 * grip_loosen))


func _clip_name(side: int, level: int) -> String:
	return LAYOUT.side_name(side) + ("" if level == 0 else "_hike%d" % level)


func set_hike(value: float) -> void:
	# Explicit inspection seek; interactive controls use request_hike instead.
	if not is_finite(value) or (sheet_study != null and sheet_study.enabled):
		return
	hike = clampf(value, 0.0, 1.0)
	hike_target = hike
	grip_phase = "HOLD"
	grip_loosen = 0.0
	set_amount(amount)


func request_hike(value: float) -> void:
	if not is_finite(value) or (sheet_study != null and sheet_study.enabled):
		return
	hike_target = clampf(value, 0.0, 1.0)
	if not is_equal_approx(hike_target, hike) and grip_phase in ["HOLD", "CLOSE"]:
		grip_phase = "LOOSEN"


func advance_hike(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or grip_phase == "HOLD":
		return
	var remaining := delta
	# Consume phase boundaries exactly, including low frame rates and reversals.
	for boundary in 4:
		if remaining <= 0.0 or grip_phase == "HOLD":
			break
		if grip_phase == "LOOSEN":
			var duration := (1.0 - grip_loosen) * GRIP_SECONDS
			var step := minf(remaining, duration)
			grip_loosen = minf(1.0, grip_loosen + step / GRIP_SECONDS)
			remaining -= step
			if step >= duration:
				grip_phase = "SLIDE"
		elif grip_phase == "SLIDE":
			var duration := absf(hike_target - hike) / HIKE_RATE
			var step := minf(remaining, duration)
			hike = move_toward(hike, hike_target, step * HIKE_RATE)
			remaining -= step
			if step >= duration:
				hike = hike_target
				grip_phase = "CLOSE"
		elif grip_phase == "CLOSE":
			var duration := grip_loosen * GRIP_SECONDS
			var step := minf(remaining, duration)
			grip_loosen = maxf(0.0, grip_loosen - step / GRIP_SECONDS)
			remaining -= step
			if step >= duration:
				grip_loosen = 0.0
				grip_phase = "HOLD"
	set_amount(amount)


func set_side(value: int) -> void:
	if sheet_study != null and sheet_study.enabled:
		return
	if value not in [LAYOUT.PORT, LAYOUT.STARBOARD] or value == seat_side:
		return
	seat_side = value
	set_hike(hike)
	for player in players.values():
		player.play("rudder/" + LAYOUT.side_name(seat_side))
	set_amount(amount)


func tiller_hand() -> String:
	return "Right" if seat_side == LAYOUT.PORT else "Left"


func sheet_hand() -> String:
	return "Left" if seat_side == LAYOUT.PORT else "Right"


func rudder_angle() -> float:
	return -float(seat_side) * amount * deg_to_rad(12.0)


func from_port(point: Vector3) -> Vector3:
	return point * Vector3(-seat_side, 1, 1)


func bone_pose_boat(name: String) -> Transform3D:
	return global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(name))


func palm_boat(prefix: String = "") -> Vector3:
	var hand := tiller_hand() if prefix.is_empty() else prefix
	return bone_pose_boat(hand + "Hand") * GRIP.palm_offset(hand, tiller_hand())


func sheet_channel_boat() -> PackedVector3Array:
	var result := PackedVector3Array()
	var hand := bone_pose_boat(sheet_hand() + "Hand")
	for point in GRIP.sheet_channel(sheet_hand()):
		result.append(hand * point)
	return result


func joint_boat() -> Vector3:
	return Vector3(0, 0, 2.171) + Basis(Vector3.UP, rudder_angle()) * Vector3(0, 0.352952, -0.979058)


func eye_boat() -> Vector3:
	return bone_pose_boat("Head") * Vector3(0, 0.115, 0.145)


func set_first_person(enabled: bool) -> void:
	body_material.set_shader_parameter("hide_head", enabled)
	skeleton.get_node("Eyebrows").visible = not enabled
	skeleton.get_node("Eyes").visible = not enabled


func _configure_body_material() -> void:
	# Reuse the production head-weight masking principle without loading its actor.
	var body := skeleton.get_node("SuperHero_Male") as MeshInstance3D
	var source := body.mesh.surface_get_material(0) as StandardMaterial3D
	body_material = ShaderMaterial.new()
	body_material.shader = INSPECTION_BODY
	for channel in ["albedo", "normal", "roughness"]:
		body_material.set_shader_parameter(channel + "_texture", source.get(channel + "_texture"))
	for index in body.skin.get_bind_count():
		if body.skin.get_bind_name(index) == &"Head":
			body_material.set_shader_parameter("head_bind_index", index)
			break
	body.material_override = body_material


func _disable_modifiers(node: Node) -> void:
	if node is SkeletonModifier3D:
		(node as SkeletonModifier3D).active = false
	for child in node.get_children():
		_disable_modifiers(child)


func _tint_face() -> void:
	var brows := skeleton.get_node("Eyebrows") as MeshInstance3D
	var eyes := skeleton.get_node("Eyes") as MeshInstance3D
	var brow_material := brows.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	brow_material.albedo_color = Color(0.16, 0.075, 0.04)
	brows.material_override = brow_material
	var eye_material := eyes.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	eye_material.uv1_scale = Vector3(0.84, 0.84, 1.0)
	eye_material.uv1_offset = Vector3(0.08, 0.08, 0.0)
	eyes.material_override = eye_material

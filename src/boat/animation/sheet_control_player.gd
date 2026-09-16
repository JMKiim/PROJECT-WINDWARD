extends Node

const SOURCE := preload("res://src/boat/animation/sheet_control_source.gd")
const REGRIP := preload("res://src/boat/animation/sheet_regrip_player.gd")
var actor: Node3D
var work := 0.5
var weight := 0.0
var slip := 0.0
var player: AnimationPlayer
var tree: AnimationTree
var bones := PackedInt32Array()
var regrip: Node
# Negative means ordinary manual work. Only contact tests enable the bridge
# until the complete rig allocation and distance-driven handover are joined.
var regrip_time := -1.0
var continuous_relay := false

func use_continuous_relay() -> void:
	if continuous_relay: return
	var candidate := load("res://src/boat/animation/sheet_relay_player.gd").new() as Node
	add_child(candidate)
	candidate.setup(actor)
	candidate.prepare()
	regrip.queue_free()
	regrip = candidate
	continuous_relay = true

func setup(value: Node3D) -> void:
	actor = value
	player = AnimationPlayer.new()
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	add_child(player)
	player.root_node = player.get_path_to(actor)
	var library := AnimationLibrary.new()
	for index in SOURCE.STEERING_SAMPLES:
		library.add_animation(str(index), load(SOURCE.path(index)) as Animation)
	player.add_animation_library("work", library)
	player.play("work/8")
	tree = AnimationTree.new()
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
	var clip: Animation = library.get_animation("8")
	for track in clip.get_track_count():
		var path := clip.track_get_path(track)
		if path.get_subname_count() > 0:
			var bone: int = actor.skeleton.find_bone(path.get_subname(0))
			if bone >= 0 and bone not in bones: bones.append(bone)
	regrip = REGRIP.new()
	add_child(regrip)
	regrip.setup(actor)

func sample() -> void:
	if weight <= 0.0: return
	if continuous_relay:
		if regrip_time>=0: regrip.sample(regrip_time,weight)
		else: regrip.sample_entry(work,weight)
		_sliding_sheet_fingers(actor.sheet_hand())
		_sliding_bone(actor.tiller_hand()+"ThumbDistal",.035)
		return
	if regrip_time >= 0.0:
		regrip.sample(regrip_time,weight)
		# A fixed trim during a hand return requires sliding contact, not an
		# additional closed-hand haul. The extension fingers stay wrapped;
		# only its sheet-pin thumb tip reduces pressure.
		if REGRIP.SOURCE.sheet_holds(regrip_time): _sliding_sheet_fingers(actor.sheet_hand())
		if REGRIP.SOURCE.helper_holds(regrip_time): _sliding_bone(actor.tiller_hand()+"ThumbDistal",0.035)
		return
	if actor.hiking_sheet_grid!=null:
		if not actor.hiking_sheet_grid.sample(work,-1.0,weight): push_error("Authored hiking sheet grid is unavailable for this posture")
		_sliding_sheet_fingers(actor.sheet_hand())
		return
	var previous: Dictionary = actor.pose_mirror.capture(bones,actor.seat_side)
	var coordinate: float = (actor.amount + 1.0) * 0.5 * (SOURCE.STEERING_SAMPLES - 1)
	var low := mini(int(coordinate), SOURCE.STEERING_SAMPLES - 2)
	var graph := tree.tree_root as AnimationNodeBlendTree
	(graph.get_node("lo") as AnimationNodeAnimation).animation = "work/" + str(low)
	(graph.get_node("hi") as AnimationNodeAnimation).animation = "work/" + str(low + 1)
	tree.set("parameters/lo_seek/seek_request", work)
	tree.set("parameters/hi_seek/seek_request", work)
	tree.set("parameters/mix/blend_amount", coordinate - low)
	tree.advance(0.0)
	actor.pose_mirror.apply_sample(bones,previous,actor.seat_side,weight)
	_sliding_sheet_fingers(actor.sheet_hand())

func _sliding_sheet_fingers(hand: String) -> void:
	# Controlled friction slip, never a fully released hand.
	for digit in ["Index", "Middle", "Ring", "Little"]:
		for segment in ["Proximal", "Intermediate", "Distal"]:
			_sliding_bone(hand+digit+segment,0.035)

func _sliding_bone(name: String, amount: float) -> void:
	var bone: int = actor.skeleton.find_bone(name)
	var held: Quaternion = actor.skeleton.get_bone_pose_rotation(bone)
	var rest: Quaternion = actor.skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	actor.skeleton.set_bone_pose_rotation(bone,held.slerp(rest,amount*slip*weight))

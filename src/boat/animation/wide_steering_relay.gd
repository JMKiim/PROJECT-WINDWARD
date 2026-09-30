extends "res://src/boat/animation/sheet_relay_player.gd"
const CONFIG := preload("res://src/boat/animation/wide_steering_config.gd")

func prepare() -> void:
	if not trees.is_empty(): return
	super.prepare()
	var bank := load(CONFIG.BANK) as AnimationLibrary
	var player := get_child(0) as AnimationPlayer
	var library := AnimationLibrary.new()
	for section in ["entry","cycle"]:
		for index in CONFIG.STEERING_SAMPLES:
			library.add_animation(section+str(index),bank.get_animation(CONFIG.relay_name(section,index)))
	player.remove_animation_library("relay")
	player.add_animation_library("relay",library)
	player.play("relay/entry32")

func _sample(weight: float) -> void:
	if weight<=0: return
	prepare()
	var previous: Dictionary=actor.pose_mirror.capture(bones,actor.seat_side)
	var coordinate: float=(actor.amount+1)*.5*(CONFIG.STEERING_SAMPLES-1)
	var low := mini(int(coordinate),CONFIG.STEERING_SAMPLES-2)
	var tree := trees[0]
	var graph := tree.tree_root as AnimationNodeBlendTree
	(graph.get_node("lo") as AnimationNodeAnimation).animation="relay/"+clip_section+str(low)
	(graph.get_node("hi") as AnimationNodeAnimation).animation="relay/"+clip_section+str(low+1)
	tree.set("parameters/lo_seek/seek_request",clip_time)
	tree.set("parameters/hi_seek/seek_request",clip_time)
	tree.set("parameters/mix/blend_amount",coordinate-low)
	tree.advance(0)
	actor.pose_mirror.apply_sample(bones,previous,actor.seat_side,weight)

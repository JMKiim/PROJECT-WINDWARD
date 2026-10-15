extends "res://src/preview/land_drill/support/wide_steering_actor.gd"
const DELIVERY := preload("res://src/preview/land_drill_runtime_config.gd")
const DIRECT_CONTROL := preload("res://src/preview/land_drill_runtime_control.gd")
func _ready() -> void:
	authored_grip=CONTACT
	look_pose=LAND_LOOK.new()
	look_pose.authored_grip=CONTACT
	var pose := Node3D.new()
	pose.name="Pose"
	pose.rotation.y=PI*.5
	add_child(pose)
	var rig: Node3D=RIG.instantiate()
	rig.name="Rig"
	rig.scale=Vector3.ONE*BODY_SCALE
	_disable_modifiers(rig)
	pose.add_child(rig)
	skeleton=rig.get_node("Armature/GeneralSkeleton")
	pose_mirror.setup(skeleton)
	(rig.get_node("AnimationPlayer") as AnimationPlayer).active=false
	# The common side API retains its manual players, but authored sampling
	# goes directly to the single bank. No legacy clip libraries are loaded.
	for layer in LAYOUT.LAYERS:
		var player := AnimationPlayer.new()
		player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		add_child(player)
		var library := AnimationLibrary.new()
		for side in [-1,1]: library.add_animation(LAYOUT.side_name(side),Animation.new())
		player.add_animation_library("rudder",library)
		players[layer]=player
	authored_bank=load(DELIVERY.BASE)
	track_sampler.configure(skeleton,get_node("Pose"))
	wide_bank_ready=true
	_tint_face()
	_configure_body_material()
	sheet_study=LAND_SHEET.new()
	add_child(sheet_study)
	sheet_study.setup(self)
	sheet_control=_new_sheet_control()
	add_child(sheet_control)
	sheet_control.setup(self)
	set_amount(0)

func _new_sheet_control() -> Node: return DIRECT_CONTROL.new()

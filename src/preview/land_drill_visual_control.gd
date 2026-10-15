extends Node
const PLAYER := preload("res://src/preview/land_drill_visual_player.gd")
var actor: Node3D
var work := .5
var weight := 0.0
var slip := 0.0
var regrip_time := -1.0
var continuous_relay := true
var regrip: Node
var motion: RefCounted
var ease_relaxation := 0.0
var feedback_revision := -1
func setup(value: Node3D) -> void:
	actor=value
	actor._sample_steering_pose()
	regrip=_new_player()
	add_child(regrip)
	regrip.setup(actor)
func _new_player() -> Node: return PLAYER.new()
func sample() -> void:
	_update_easing_feedback()
	set_display_weight(weight)
	if weight<=0: return
	regrip.ease_relaxation=ease_relaxation
	if regrip_time>=0: regrip.sample(regrip_time,weight)
	else: regrip.sample_entry(work,weight)
func _update_easing_feedback() -> void:
	# The completed simulation step owns feed. Re-sampling a camera or pose
	# must not advance the grip response or amplify a small wheel packet.
	var revision: int=actor.sheet_study.manual_revision
	if motion==null or revision==feedback_revision: return
	feedback_revision=revision
	var delta: float=actor.sheet_study.manual_delta
	if not is_finite(delta) or delta<=0: return
	var rate: float=maxf(0,-motion.last_feed/delta)
	var target := .18*smoothstep(0,3.6,rate)
	var response := .04 if target>ease_relaxation else .07
	ease_relaxation=lerpf(ease_relaxation,target,1-exp(-delta/response))
	if ease_relaxation<.000001: ease_relaxation=0
func set_display_weight(value: float) -> void:
	regrip.active_weight=value
	if motion!=null: motion.presentation_weight=value
	if value<=0:
		# The authored idle hand owns the sheet after the working pose leaves.
		# Do not keep a frozen helper clock in the rendered unsupported pose.
		regrip.time=-1
		regrip.clip_section="entry"
		regrip.clip_time=work
func use_continuous_relay() -> void: pass

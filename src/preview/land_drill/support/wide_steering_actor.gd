extends "res://src/preview/land_drill/support/rudder_clip_actor.gd"

const CONFIG := preload("res://src/preview/land_drill/support/wide_steering_config.gd")
const RELAY_PLAYER := preload("res://src/preview/land_drill/support/wide_steering_relay.gd")
const CONTACT := preload("res://src/preview/land_drill/support/land_drill_grip_profile.gd")
const TRACK_SAMPLER := preload("res://src/boat/animation/authored_track_sampler.gd")
const LAND_LOOK := preload("res://src/preview/land_drill/support/land_drill_look_pose.gd")
const LAND_SHEET := preload("res://src/preview/land_drill/support/land_drill_sheet_study.gd")
var authored_bank: AnimationLibrary
var track_sampler := TRACK_SAMPLER.new()
var wide_bank_ready := false
var steering_target := 0.0
var steering_phase := "HOLD"
var steering_release := 0.0
const STEERING_RELEASE_SECONDS := .14
const STEERING_RATE := 1.5

func _ready() -> void:
	authored_grip=CONTACT
	look_pose=LAND_LOOK.new()
	look_pose.authored_grip=CONTACT
	super._ready()
	var prior_study := sheet_study
	sheet_study=LAND_SHEET.new()
	add_child(sheet_study)
	sheet_study.setup(self)
	prior_study.queue_free()
	var bank := load(CONFIG.BANK) as AnimationLibrary
	if bank==null or extension_span<CONFIG.TUBE_METRES+CONFIG.JOINT_METRES-.000001:
		push_error("Wide steering requires its authored bank and matching extension")
		return
	for layer in LAYOUT.LAYERS:
		var player: AnimationPlayer=players[layer]
		var library := AnimationLibrary.new()
		for side in [-1,1]:
			for level in CONFIG.HIKE_LEVELS:
				library.add_animation(_clip_name(side,level),bank.get_animation(CONFIG.base_name(side,layer,level)))
		player.remove_animation_library("rudder")
		player.add_animation_library("rudder",library)
		player.play("rudder/"+LAYOUT.side_name(seat_side))
	authored_bank=bank
	track_sampler.configure(skeleton,get_node("Pose"))
	wide_bank_ready=true
	var relay := RELAY_PLAYER.new()
	sheet_control.add_child(relay)
	relay.setup(self)
	relay.prepare()
	sheet_control.regrip.queue_free()
	sheet_control.regrip=relay
	sheet_control.continuous_relay=true
	set_amount(0)

func rudder_angle() -> float:
	return -float(seat_side)*amount*deg_to_rad(CONFIG.DEGREES)

func _sample_steering_pose() -> void:
	if not wide_bank_ready:
		super._sample_steering_pose()
		return
	var coordinate := hike*(CONFIG.HIKE_LEVELS-1)
	var low := mini(int(coordinate),CONFIG.HIKE_LEVELS-2)
	for layer in LAYOUT.LAYERS:
		track_sampler.sample_pair(authored_bank.get_animation(CONFIG.base_name(seat_side,layer,low)),authored_bank.get_animation(CONFIG.base_name(seat_side,layer,low+1)),amount+1,coordinate-low)

func _hike_playback_levels() -> int:
	return CONFIG.HIKE_LEVELS if wide_bank_ready else HIKE.LEVELS

func _grip_release_for_segment(segment: String) -> float:
	# The measured closed finger pose keeps its PIP guard while releasing.
	return .075 if segment=="Intermediate" else .10

func grip_status() -> String:
	return "STEER_"+steering_phase if steering_phase!="HOLD" else grip_phase

func set_amount(value: float) -> void:
	if not is_finite(value): return
	if steering_phase=="HOLD": steering_target=clampf(value,-1,1)
	var hike_release := grip_loosen
	grip_loosen=maxf(hike_release,steering_release)
	super.set_amount(value)
	grip_loosen=hike_release

func set_hike(value: float) -> void:
	if not is_finite(value): return
	steering_target=amount
	steering_phase="HOLD"
	steering_release=0
	super.set_hike(value)

func request_amount(value: float) -> void:
	if not is_finite(value): return
	steering_target=clampf(value,-1,1)
	if not is_equal_approx(steering_target,amount) and steering_phase in ["HOLD","CLOSE"]:
		steering_phase="LOOSEN"

func advance_steering(delta: float, resample := true) -> void:
	if not is_finite(delta) or delta<=0 or steering_phase=="HOLD": return
	var remaining := delta
	for boundary in 4:
		if remaining<=0 or steering_phase=="HOLD": break
		if steering_phase=="LOOSEN":
			var duration := (1-steering_release)*STEERING_RELEASE_SECONDS
			var step := minf(remaining,duration)
			steering_release=minf(1,steering_release+step/STEERING_RELEASE_SECONDS)
			remaining-=step
			if step>=duration: steering_phase="SLIDE"
		elif steering_phase=="SLIDE":
			var duration := absf(steering_target-amount)/STEERING_RATE
			var step := minf(remaining,duration)
			amount=move_toward(amount,steering_target,step*STEERING_RATE)
			remaining-=step
			if step>=duration:
				amount=steering_target
				steering_phase="CLOSE"
		elif steering_phase=="CLOSE":
			var duration := steering_release*STEERING_RELEASE_SECONDS
			var step := minf(remaining,duration)
			steering_release=maxf(0,steering_release-step/STEERING_RELEASE_SECONDS)
			remaining-=step
			if step>=duration:
				steering_release=0
				steering_phase="HOLD"
	if resample: set_amount(amount)

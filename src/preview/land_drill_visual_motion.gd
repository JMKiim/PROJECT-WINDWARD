extends "res://src/boat/animation/sheet_relay_motion.gd"
const GESTURE := preload("res://src/preview/land_drill/support/land_drill_wheel_gesture.gd")
const PROFILE_MODEL := preload("res://src/preview/land_drill_visual_profile.gd")
var presentation_weight := 1.0
var hiking_blend := 0.0
func set_posture(hike: float) -> void:
	# Short hiking strokes use a lower display cadence for the same metered
	# input. This is an animation calibration, not1:1 physical hand/rope work.
	# The short-stroke lane is established in the first eighth of hiking;
	# its cadence calibration must follow that gesture morph, not wait for
	# full body extension while small-hike fingers race through the return.
	hiking_blend=smoothstep(0,.125,hike)
	profile.presentation_gain=lerpf(1,2.5,hiking_blend)
func configure_visual() -> bool: return configure(PROFILE_MODEL.new())
func contact_state() -> Dictionary:
	if presentation_weight<=0:
		return {"sheet_holds":true,"helper_holds":false,"sheet_contact":"grip","helper_contact":"open","phase":"POSTURE HOLD"}
	var contacts := super.contact_state()
	if bridge_time>=1 and bridge_time<1.1:
		# The sheet hand retains pressure while the helper closes its pinch.
		contacts.helper_holds=false
		contacts.helper_contact="open"
		contacts.phase="TRANSFER"
	if bridge_time>=1:
		var progress := bridge_time-1
		contacts.sheet_holds=progress<=.12 or progress>=.9
		contacts.sheet_contact="grip" if contacts.sheet_holds else "open"
	# Returning a hand with retained trim is not an easing operation.
	var held_role := "friction" if last_feed<-.0000001 else "grip"
	if contacts.sheet_holds: contacts.sheet_contact=held_role
	if contacts.helper_holds: contacts.helper_contact=held_role
	return contacts
func advance(input: RefCounted,delta: float,steering: float) -> void:
	if not input.wheel_gesture is GESTURE:
		var gesture := GESTURE.new()
		gesture.adopt(input.wheel_gesture)
		input.wheel_gesture=gesture
	var prior: float=input.wheel_gesture.rate
	input.wheel_gesture.rate=input.wheel_gesture.onset_rate()
	super.advance(input,delta,steering)
	input.wheel_gesture.rate=prior
func _speed_proxy(section: String,role: String,steering: float,progress: float) -> Vector3:
	var original: Vector3=profile.palm_at(section,role,steering,progress)
	if role!="left" or hiking_blend<=0: return original
	# Match the actual hiking hand's phase windows. The legacy smoothstep
	# over the entire helper clip missed the faster12..85% regrasp lane.
	var u := smoothstep(0,1,progress)
	if section=="helper": u=1-smoothstep(.12,.85,progress)
	elif section=="work": u=.45*smoothstep(0,.5,progress) if progress<.5 else .45+.55*smoothstep(.5,1,progress)
	var point: Vector3=profile.LOW.lerp(profile.HIGH,u)+Vector3(0,0,-.12)*sin(PI*u)
	return original.lerp(point,hiking_blend)
func _proxy_distance(section: String,role: String,steering: float,a: float,b: float) -> float:
	var distance := _speed_proxy(section,role,steering,a).distance_to(_speed_proxy(section,role,steering,b))
	if role=="left" and section=="helper":
		# Bound the released digits as well as the palm. This is a speed
		# envelope, never a displayed rope length or material measurement.
		distance+=hiking_blend*.072*absf(sin(PI*smoothstep(0,1,b))-sin(PI*smoothstep(0,1,a)))
	return distance
func _continue_remaining(input: RefCounted,delta: float,steering: float,section: String,previous: float,current: float,rate: float) -> void:
	if hiking_blend<=0:
		super._continue_remaining(input,delta,steering,section,previous,current,rate)
		return
	var held := "right" if section=="helper" else "left"
	var free := "left" if held=="right" else "right"
	var reserve := lerpf(.8,.65,hiking_blend)
	var held_speed := MAX_HAND_SPEED*(reserve if held=="left" else 1.0)
	var free_speed := RETURN_PATH_SPEED*(reserve if free=="left" else 1.0)
	var elapsed := maxf(absf(last_feed)/rate,maxf(_proxy_distance(section,held,steering,previous,current)/held_speed,_proxy_distance(section,free,steering,previous,current)/free_speed))
	var remaining := delta-elapsed
	if remaining<=.0000001: return
	var consumed := last_feed
	input.since_input-=remaining
	advance(input,remaining,steering)
	last_feed+=consumed
func _bounded(section: String,steering: float,current: float,target: float,delta: float,held_speed: float,free_speed: float) -> float:
	# Bounds apply to authored hand travel; visual rope arc is never an input.
	var held := "right" if section=="helper" else "left"
	var free := "left" if held=="right" else "right"
	# Reserve hand-frame/finger travel as well as palm translation. The
	# closed-form grip changes forearm orientation during the short return.
	var hand_frame_reserve := lerpf(.8,.65,hiking_blend)
	if held=="left": held_speed*=hand_frame_reserve
	if free=="left": free_speed*=hand_frame_reserve
	var low := 0.0
	var high := 1.0
	for iteration in 11:
		var fraction := 1.0 if iteration==0 else (low+high)*.5
		var next := lerpf(current,target,fraction)
		if _proxy_distance(section,held,steering,current,next)<=held_speed*delta and _proxy_distance(section,free,steering,current,next)<=free_speed*delta:
			if iteration==0: return target
			low=fraction
		else: high=fraction
	return lerpf(current,target,low)

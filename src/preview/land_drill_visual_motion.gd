extends "res://src/boat/animation/sheet_relay_motion.gd"
const GESTURE := preload("res://src/preview/land_drill/support/land_drill_wheel_gesture.gd")
const PROFILE_MODEL := preload("res://src/preview/land_drill_visual_profile.gd")
var presentation_weight := 1.0
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
func _bounded(section: String,steering: float,current: float,target: float,delta: float,held_speed: float,free_speed: float) -> float:
	# Bounds apply to authored hand travel; visual rope arc is never an input.
	var held := "right" if section=="helper" else "left"
	var free := "left" if held=="right" else "right"
	# Reserve hand-frame/finger travel as well as palm translation. The
	# closed-form grip changes forearm orientation during the short return.
	if held=="left": held_speed*=.8
	if free=="left": free_speed*=.8
	var a: Vector3=profile.palm_at(section,held,steering,current)
	var b: Vector3=profile.palm_at(section,free,steering,current)
	var low := 0.0
	var high := 1.0
	for iteration in 11:
		var fraction := 1.0 if iteration==0 else (low+high)*.5
		var next := lerpf(current,target,fraction)
		if a.distance_to(profile.palm_at(section,held,steering,next))<=held_speed*delta and b.distance_to(profile.palm_at(section,free,steering,next))<=free_speed*delta:
			if iteration==0: return target
			low=fraction
		else: high=fraction
	return lerpf(current,target,low)

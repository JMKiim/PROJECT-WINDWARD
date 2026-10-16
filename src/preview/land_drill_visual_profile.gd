extends "res://src/boat/animation/sheet_relay_profile.gd"
## Logical haul distances and authored reach guides, not measured rope arc.
const READY := Vector3(-.23,.57,.34)
const LOW := Vector3(-.23,.52,.38)
const HIGH := Vector3(-.14,.76,.50)
const HELPER_START := Vector3(-.18,.94,.40)
const HELPER_END := Vector3(-.10,.91,.54)
const HELPER_LOGICAL_STROKE := .21354
var presentation_gain := 1.0
func valid() -> bool: return true
func length_at(section: String,_steering: float,progress: float) -> float:
	# Authored hand travel is the logical stroke calibration, not display arc.
	if section=="work":
		if progress<.5: return presentation_gain*LOW.distance_to(READY)*smoothstep(0,.5,progress)
		return presentation_gain*(LOW.distance_to(READY)+READY.distance_to(HIGH)*smoothstep(.5,1,progress))
	# Animation-to-trim calibration is independent of the shortened visual
	# grip travel; keeping the fingers smooth must not slow the trim system.
	return presentation_gain*(HELPER_LOGICAL_STROKE if section=="helper" else LOW.distance_to(HIGH))*smoothstep(0,1,progress)
func advance_distance(section: String,steering: float,progress: float,distance: float) -> float:
	var goal := clampf(length_at(section,steering,progress)+distance,0,length_at(section,steering,1))
	if goal<=0: return 0
	if goal>=length_at(section,steering,1): return 1
	var low := 0.0
	var high := 1.0
	for step in (22 if presentation_gain!=1 else 20):
		var middle := (low+high)*.5
		if length_at(section,steering,middle)<goal: low=middle
		else: high=middle
	return (low+high)*.5
func palm_at(section: String,hand: String,steering: float,progress: float) -> Vector3:
	var u := smoothstep(0,1,progress)
	var end := HELPER_END+Vector3(0,0,.08*smoothstep(0,1,steering))
	var right := HELPER_START.lerp(end,u) if section=="helper" else end.lerp(HELPER_START,u)
	var left := HIGH.lerp(LOW,u)+Vector3(-.065,0,-.06)*sin(PI*u) if section=="helper" else LOW.lerp(HIGH,u)
	if section=="work":
		left=LOW.lerp(READY,smoothstep(0,.5,progress)) if progress<.5 else READY.lerp(HIGH,smoothstep(.5,1,progress))
		right=HELPER_START
	# Whole-range steering shifts the working space, not the input limits.
	var point := left if hand=="left" else right
	return point+Vector3(-steering*.025,0,steering*.025)

extends RefCounted

## Authored high-haul to low-regrip bridge. No live playback or rope feed here.
const CONTROL := preload("res://src/boat/animation/sheet_control_source.gd")
const GRIP := preload("res://src/boat/animation/authored_grip_profile.gd")
const DURATION := 2.9
const STEERING_SAMPLES := 33
const HELPER_START := .8
const HELPER_FINISH := 1.75
const CATCH_FRACTION := 0.64
const REGRIP_FRACTION := 0.65
const HELPER_LIFT := Vector3(0.0, 0.055, 0.025)
const ASSIST_LOCAL := Vector3(0.049508149, 0.056987157, 0.075087968)
const CONTACT_AXIS := Vector3(0.193030993, -0.849499969, -0.491007982)
const PIN_HALF_LENGTH := .006

static func helper_channel(hand: Transform3D) -> PackedVector3Array:
	# The support is the measured thumb contact, not the middle of a long
	# virtual channel. Its tangent stays on the actual skin-side contact line.
	var tangent := (hand.basis*CONTACT_AXIS).normalized()
	# Seated port inlet stays on the lower side of this grip. Choosing its
	# sign by incoming-line angle flips the channel near full pull steering.
	if tangent.y < 0.0: tangent = -tangent
	var center := hand*ASSIST_LOCAL
	return PackedVector3Array([center-tangent*PIN_HALF_LENGTH,center,center+tangent*PIN_HALF_LENGTH])

static func phase(t: float) -> String:
	if t < .6: return "APPROACH"
	if t < .8: return "PIN"
	if t < 1.0: return "RELEASE"
	if t < 1.75: return "LIFT / REACH"
	if t < 2.0: return "REGRIP"
	if t < 2.2: return "TRANSFER"
	return "RECOVER"

static func helper_weight(t: float) -> float:
	return smoothstep(0.0,.6,t) * (1.0-smoothstep(2.2,DURATION,t))

static func helper_target(t: float, neutral: Vector3, catch: Vector3) -> Vector3:
	# Once the thumb owns the line, its haul overlaps the other hand opening.
	# The sheet palm stays high until clear; it does not drag a closed grip down.
	var goal := catch + HELPER_LIFT*smoothstep(HELPER_START,HELPER_FINISH,t)
	var result := neutral.lerp(goal,helper_weight(t))
	if t < .6: result += Vector3(.08,0,-.02)*sin(PI*smoothstep(0.0,.6,t))
	return result

static func sheet_open(t: float) -> float:
	return smoothstep(.8,1.0,t)*(1.0-smoothstep(1.75,2.0,t))

static func sheet_holds(t: float) -> bool:
	return t <= .8 or t >= 2.0

static func helper_holds(t: float) -> bool:
	return t >= .8 and t <= 2.2

static func palm(t: float, low_regrip: Vector3) -> Vector3:
	if t <= 1.0: return CONTROL.HIGH
	if t < 1.75:
		var u := smoothstep(1.0,1.75,t)
		return CONTROL.HIGH.lerp(low_regrip,u)+Vector3(-.08,0,-.12)*sin(PI*u)
	if t < 2.2: return low_regrip
	return low_regrip.lerp(CONTROL.READY,smoothstep(2.2,DURATION,t))

static func elbow(t: float) -> Vector3:
	var u := smoothstep(1.0,1.75,t)
	return CONTROL.ELBOW+Vector3(-.45,0,-.12)*sin(PI*u)

static func path(index: int, layer: String) -> String:
	return "res://src/boat/animation/sheet_regrip_%s_%d.tres" % [layer,index]

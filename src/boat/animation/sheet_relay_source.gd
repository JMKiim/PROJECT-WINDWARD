extends RefCounted

## Two continuous authored strokes. The returning hand travels during the
## other hand's haul; neutral chest pose is only an entry/idle pose.
const STEERING_SAMPLES := 33
const READY := Vector3(-.23,.78,.53)
const HIGH := Vector3(-.30,1.30,.53)
const LOW := Vector3(-.20,.48,.28)
const ELBOW := Vector3(-.45,.35,.05)
const HIGH_ELBOW := Vector3(-.72,1.02,.22)
const HELPER_ELBOW := Vector3(-.30,1.40,1.30)
const HELPER_LIFT := Vector3(0,.35,.35)
const CATCH_FRACTION := .55
const REGRIP_FRACTION := .35
const CONTACT := preload("res://src/boat/animation/sheet_regrip_source.gd")

static func entry_palm(work: float) -> Vector3:
	if work<.5: return LOW.lerp(READY,smoothstep(0,.5,work))
	return READY.lerp(HIGH,smoothstep(.5,1,work))

static func entry_elbow(work: float) -> Vector3:
	return ELBOW.lerp(HIGH_ELBOW,smoothstep(.5,1,work))

static func entry_helper(work: float) -> float:
	return .8*smoothstep(.5,1,work)

static func left_palm(progress: float,regrip: Vector3) -> Vector3:
	if progress<.4: return regrip.lerp(READY,smoothstep(0,.4,progress))
	return READY.lerp(HIGH,smoothstep(.4,1,progress))

static func left_elbow(progress: float) -> Vector3:
	return ELBOW.lerp(HIGH_ELBOW,smoothstep(.4,1,progress))

static func returning_left(progress: float,regrip: Vector3) -> Vector3:
	var u := smoothstep(.12,.85,progress)
	return HIGH.lerp(regrip,u)+Vector3(-.18,0,-.24)*sin(PI*u)

static func returning_elbow(progress: float) -> Vector3:
	var u := smoothstep(.12,.85,progress)
	return HIGH_ELBOW.lerp(ELBOW,u)+Vector3(-.45,0,-.12)*sin(PI*u)

static func left_open(progress: float) -> float:
	return smoothstep(0,.12,progress)*(1-smoothstep(.85,1,progress))

static func helper_return(progress: float) -> float:
	return 1-smoothstep(0,.85,progress)

static func helper_open(progress: float) -> float:
	return smoothstep(0,.15,progress)*(1-smoothstep(.80,1,progress))

static func contact_time(clock: float) -> float:
	if clock>=1:
		var p := clock-1
		if p<.12: return lerpf(.8,1,p/.12)
		if p<.85: return lerpf(1,1.75,(p-.12)/.73)
		return lerpf(1.75,2,(p-.85)/.15)
	if clock<.15: return lerpf(2,2.2,clock/.15)
	if clock<.80: return lerpf(2.2,2.9,(clock-.15)/.65)
	return .8*(clock-.80)/.20

static func path(index: int,section: String) -> String:
	return "res://src/boat/animation/sheet_relay_%s_%d.tres" % [section,index]

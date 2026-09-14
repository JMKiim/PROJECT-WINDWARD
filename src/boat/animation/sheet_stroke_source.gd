extends RefCounted

## One authored seated/port inspection stroke, not sail or rope dynamics.
const SEATED := preload("res://src/boat/animation/rudder_port_source.tres")
const DURATION := 5.2
const BLOCK := Vector3(0, 0.39, 0.14)
const ASSIST_LOCAL := Vector3(0.005, 0.110, 0.040)
const PULLED := Vector3(-0.34, 0.72, 0.49)
# Authored catch lies on the incoming sheet after the first pull.
const CATCH := Vector3(-0.290715, 0.607927, 0.424747)
const HELPER_LIFT := Vector3(0, 0.09, 0.025)
const REGRIP := Vector3(-0.202276, 0.625564, 0.376592)

static func phase(t: float) -> String:
	if t < 1.1: return "PULL"
	if t < 2.0: return "HELPER APPROACH"
	if t < 2.25: return "ASSIST PIN"
	if t < 2.5: return "RELEASE SHEET HAND"
	if t < 3.35: return "HELPER LIFT / REACH FORWARD"
	if t < 3.65: return "REGRIP"
	if t < 3.9: return "TRANSFER LOAD"
	if t < 4.8: return "RECOVER"
	return "HOLD / COMPLETE"

static func blend(t: float, start: float, end: float) -> float:
	return smoothstep(start, end, t)

static func sheet_open(t: float) -> float:
	return blend(t, 2.25, 2.5) * (1.0 - blend(t, 3.35, 3.65))

static func assist_weight(t: float) -> float:
	return blend(t, 2.0, 2.25) * (1.0 - blend(t, 3.65, 3.9))

static func helper_owns_load(t: float) -> bool:
	return t >= 2.25 and t <= 3.9

static func sheet_owns_load(t: float) -> bool:
	return t <= 2.25 or t >= 3.65

static func palm(t: float, helper: Vector3) -> Vector3:
	var ready: Vector3 = SEATED.sheet_palm
	var forward := REGRIP
	if t < 1.1: return ready.lerp(PULLED, blend(t, 0, 1.1))
	if t < 2.5: return PULLED
	if t < 3.35:
		var u := blend(t, 2.5, 3.35)
		# Lift away from the held line before reaching forward; don't drag a
		# closed fist along it while the other hand carries the load.
		return PULLED.lerp(forward, u) + Vector3(-0.09, 0, -0.20) * sin(u * PI)
	if t < 3.9: return forward
	return forward.lerp(ready, blend(t, 3.9, 4.8))

static func helper_work(t: float) -> float:
	return blend(t, 1.1, 2.0) * (1.0 - blend(t, 3.9, 4.8))

static func helper_target(t: float, neutral: Vector3) -> Vector3:
	var lifted := CATCH + HELPER_LIFT * blend(t, 2.5, 3.35)
	var target := neutral.lerp(lifted, helper_work(t))
	if t < 2.0:
		target += Vector3(0.12, 0, -0.02) * sin(PI * blend(t, 1.1, 2.0))
	return target

static func sheet_elbow(t: float) -> Vector3:
	var reach := blend(t, 2.5, 2.65) * (1.0 - blend(t, 3.9, 4.8))
	return SEATED.sheet_elbow_guide.lerp(Vector3(-1.0, 0.35, -0.1), reach)

static func pulled_metres(t: float) -> float:
	# Inspection feed coordinate. It never unwinds during release/regrip.
	# Not a mainsheet purchase ratio, sail angle, force or full rope simulation.
	return 0.16 * blend(t, 0, 1.1) + 0.07 * blend(t, 2.5, 3.35) + 0.03 * blend(t, 3.9, 4.8)

extends RefCounted

## One authored seated/port inspection stroke, not sail or rope dynamics.
const SEATED := preload("res://src/boat/animation/rudder_port_source.tres")
const DURATION := 5.2
const BLOCK := Vector3(0, 0.39, 0.14)
const ASSIST_LOCAL := Vector3(0.005, 0.110, 0.040)
const PULLED := Vector3(-0.34, 0.72, 0.49)

static func phase(t: float) -> String:
	if t < 1.1: return "PULL"
	if t < 2.0: return "OFFER"
	if t < 2.25: return "ASSIST PIN"
	if t < 2.5: return "RELEASE SHEET HAND"
	if t < 3.35: return "REACH FORWARD"
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
	var offer := helper + Vector3(-0.13, 0.08, -0.065)
	var forward := BLOCK.lerp(helper, 0.55)
	if t < 1.1: return ready.lerp(PULLED, blend(t, 0, 1.1))
	if t < 2.0: return PULLED.lerp(offer, blend(t, 1.1, 2.0))
	if t < 2.5: return offer
	if t < 3.35:
		var u := blend(t, 2.5, 3.35)
		# Lift away from the held line before reaching forward; don't drag a
		# closed fist along it while the other hand carries the load.
		return offer.lerp(forward, u) + Vector3(-0.10, 0.05, 0) * sin(u * PI)
	if t < 3.9: return forward
	return forward.lerp(ready, blend(t, 3.9, 4.8))

static func pulled_metres(t: float) -> float:
	# Inspection feed coordinate. It never unwinds during release/regrip.
	# Not a mainsheet purchase ratio, sail angle, force or full rope simulation.
	return 0.16 * blend(t, 0, 1.1) + 0.07 * blend(t, 1.1, 2.0) + 0.03 * blend(t, 3.9, 4.8)

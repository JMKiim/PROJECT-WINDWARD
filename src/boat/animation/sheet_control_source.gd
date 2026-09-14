extends RefCounted

## Seated port work lane. Steering samples share the existing body layers.
const STEERING_SAMPLES := 17
const READY := Vector3(-0.23, 0.78, 0.53)
const HIGH := Vector3(-0.30, 1.05, 0.53)
const LOW := Vector3(-0.20, 0.48, 0.28)
const ELBOW := Vector3(-0.45, 0.35, 0.05)

static func palm(work: float) -> Vector3:
	if work < 0.5: return LOW.lerp(READY, smoothstep(0.0, 0.5, work))
	return READY.lerp(HIGH, smoothstep(0.5, 1.0, work))

static func path(index: int) -> String:
	return "res://src/boat/animation/sheet_control_%d.tres" % index

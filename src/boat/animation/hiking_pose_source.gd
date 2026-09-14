extends Resource

## This is the bounded authoring range of the inspection lab, not sailing
## physics or an assertion that 1.0 covers every possible hiking posture.
const SEATED := preload("res://src/boat/animation/rudder_port_source.tres")
const LEVELS := 33
@export var hips_offset := Vector3(-0.28, 0.02, 0)
@export var torso_lean_degrees := 35.0
@export var grip_travel := 0.28
@export var palm_guide_offset := Vector3(-0.44, -0.10, 0.02)
@export var palm_steering_offset := Vector3.ZERO
@export var tiller_elbow_offset := Vector3(0.64, -0.40, 0)
@export var sheet_palm_offset := Vector3(-0.42, 0.02, -0.02)
@export var sheet_elbow_offset := Vector3(-0.50, 0, 0)
@export var shoulder_reach_degrees := Vector2(0, 28)

func grip_at(hike: float) -> float:
	return SEATED.grip_distance + clampf(hike, 0, 1) * grip_travel

func palm_at(amount: float, hike: float) -> Vector3:
	var h := clampf(hike, 0, 1)
	var joint := Vector3(0, 0, 2.171) + Basis(Vector3.UP, clampf(amount, -1, 1) * deg_to_rad(12)) * Vector3(0, 0.352952, -0.979058)
	var guide: Vector3 = SEATED.palm_at(amount, seated_work_weight(h)) + (palm_guide_offset + palm_steering_offset * clampf(amount, -1, 1)) * h
	return joint + (guide - joint).normalized() * grip_at(h)

func seated_work_weight(hike: float) -> float:
	var seated := 1.0 - clampf(hike, 0.0, 1.0)
	return seated * seated

func pitch_at(amount: float, hike: float) -> float:
	var h := clampf(hike, 0, 1)
	return SEATED.pitch_at(amount) * (1.0 - h * 0.7) - deg_to_rad(torso_lean_degrees) * h

func sheet_at(hike: float) -> Vector3:
	return SEATED.sheet_palm + sheet_palm_offset * clampf(hike, 0, 1)

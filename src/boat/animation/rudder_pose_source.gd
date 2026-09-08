extends Resource

## Hand-authored port-side working poses in the boat's metre-based frame.
## These guides are used by the offline baker, never by the playback loop.
@export var palm_keys := PackedVector3Array([
	Vector3(0.0, 0.78, 0.70),
	Vector3(-0.025, 0.78, 0.70),
	Vector3(-0.05, 0.78, 0.70),
	Vector3(-0.075, 0.78, 0.70),
	Vector3(-0.10, 0.78, 0.70),
])
# A pole defines the bend plane, not the elbow's final position. Keep the
# working upper arm on the aft side of the ribcage without moving its grip.
@export var tiller_elbow_guide := Vector3(-0.30, 0.45, 1.60)
@export var tiller_elbow_push_guide := Vector3(-0.30, 0.45, 1.60)
@export var sheet_palm := Vector3(-0.27, 0.70, 0.30)
@export var sheet_elbow_guide := Vector3(-0.45, 0.35, 0.05)
@export var shoulder_protraction_degrees := Vector2(10.0, 12.0)
@export var torso_pitch_degrees := PackedFloat32Array([6.0, 3.0, 0.0, -1.5, -3.0])
@export var grip_distance := 0.72
@export var torso_yaw_degrees := PackedFloat32Array([0, 0, 0, 0, 0])


func palm_at(amount: float) -> Vector3:
	var coordinate := (clampf(amount, -1.0, 1.0) + 1.0) * 2.0
	var index := mini(int(coordinate), 3)
	var guide := palm_keys[index].lerp(palm_keys[index + 1], coordinate - float(index))
	var joint := Vector3(0, 0, 2.171) + Basis(Vector3.UP, clampf(amount, -1.0, 1.0) * deg_to_rad(12.0)) * Vector3(0, 0.352952, -0.979058)
	# This stroke never releases the extension: preserve its material grip point.
	return joint + (guide - joint).normalized() * grip_distance


func pitch_at(amount: float) -> float:
	var coordinate := (clampf(amount, -1.0, 1.0) + 1.0) * 2.0
	var index := mini(int(coordinate), 3)
	return deg_to_rad(lerpf(torso_pitch_degrees[index], torso_pitch_degrees[index + 1], coordinate - float(index)))


func elbow_at(amount: float) -> Vector3:
	return tiller_elbow_push_guide.lerp(tiller_elbow_guide, (clampf(amount, -1.0, 1.0) + 1.0) * 0.5)


func yaw_at(amount: float) -> float:
	var coordinate := (clampf(amount, -1.0, 1.0) + 1.0) * 2.0
	var index := mini(int(coordinate), 3)
	return deg_to_rad(lerpf(torso_yaw_degrees[index], torso_yaw_degrees[index + 1], coordinate - float(index)))

extends RefCounted

## Local hand coordinates: +Y toward knuckles, +Z into the closing fingers.
## The two tools have different diameters and therefore different grip centres.
const TILLER_OFFSET := Vector3(0, 0.088, 0.035)
const TILLER_AXIS := Vector3(0.972387302, 0.233372952, 0)
const SHEET_OFFSET := Vector3(0, 0.096, 0.026)
const SHEET_RADIUS := 0.004


static func palm_offset(prefix: String, tiller_hand: String = "Right") -> Vector3:
	return TILLER_OFFSET if prefix == tiller_hand else SHEET_OFFSET


static func tiller_axis(prefix: String = "Right") -> Vector3:
	return TILLER_AXIS if prefix == "Right" else TILLER_AXIS * Vector3(-1, 1, 1)


static func sheet_channel(prefix: String = "Left") -> PackedVector3Array:
	# Follow the diagonal knuckle row; a straight transverse line cuts the pinky.
	var result := PackedVector3Array([
		Vector3(0.058, 0.08324, 0.026),
		Vector3(0.030, 0.08940, 0.026),
		SHEET_OFFSET,
		Vector3(-0.030, 0.10260, 0.026),
		Vector3(-0.058, 0.10876, 0.026),
	])
	if prefix == "Right":
		for i in result.size():
			result[i].x = -result[i].x
	return result

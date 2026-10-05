extends RefCounted

## Contact centres measured against the rendered hand, including rope radius.
## This profile belongs to the separate land-drill bank, not legacy clips.
const TILLER_OFFSET := Vector3(0,.096,.043)
const TILLER_AXIS := Vector3(.972387302,.233372952,0)
const SHEET_OFFSET := Vector3(0,.096,.031)
const SHEET_RADIUS := .004
const ASSIST_LOCAL := Vector3(.049508149,.052987157,.071087968)
const CONTACT_AXIS := Vector3(.193030993,-.849499969,-.491007982)
const PIN_HALF_LENGTH := .006
const SHEET_FINGER_RELEASE := Vector3(.25,.15,.25)
const TILLER_FINGER_RELEASE := Vector3(.4,.15,.4)

static func palm_offset(prefix: String,tiller_hand: String="Right") -> Vector3:
	return TILLER_OFFSET if prefix==tiller_hand else SHEET_OFFSET

static func tiller_axis(prefix: String="Right") -> Vector3:
	return TILLER_AXIS if prefix=="Right" else TILLER_AXIS*Vector3(-1,1,1)

static func sheet_channel(prefix: String="Left") -> PackedVector3Array:
	var result := PackedVector3Array([Vector3(.058,.08324,.031),Vector3(.030,.08940,.031),SHEET_OFFSET,Vector3(-.030,.10260,.031),Vector3(-.058,.10876,.031)])
	if prefix=="Right":
		for i in result.size(): result[i].x=-result[i].x
	return result

static func helper_channel(hand: Transform3D) -> PackedVector3Array:
	# Inlet/outlet identity belongs to the authored thumb, not world height.
	# Flipping at tangent.y == 0 teleports each endpoint by 12 mm and breaks
	# both steering interpolation and the sheet hand's low regrasp path.
	# Positive local direction follows the incoming block-to-thumb strand.
	# The opposite direction doubled the short channel back over that strand.
	var tangent := (hand.basis*CONTACT_AXIS).normalized()
	var center := hand*ASSIST_LOCAL
	return PackedVector3Array([center-tangent*PIN_HALF_LENGTH,center,center+tangent*PIN_HALF_LENGTH])

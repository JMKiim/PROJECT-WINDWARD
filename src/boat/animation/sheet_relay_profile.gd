extends "res://src/boat/animation/sheet_feed_profile.gd"

## Authored palm trajectories accompany the measured material distances.
@export var work_left := PackedVector3Array()
@export var work_right := PackedVector3Array()
@export var helper_left := PackedVector3Array()
@export var helper_right := PackedVector3Array()
@export var recovery_left := PackedVector3Array()
@export var recovery_right := PackedVector3Array()

func valid() -> bool:
	if not super.valid(): return false
	var count := steering_samples*phase_samples
	for values in [work_left,work_right,helper_left,helper_right,recovery_left,recovery_right]:
		if values.size()!=count: return false
	return true

func palm_at(section: String,hand: String,steering: float,progress: float) -> Vector3:
	var values: PackedVector3Array = get(section+"_"+hand)
	var sx := clampf((steering+1)*.5,0,1)*(steering_samples-1)
	var px := clampf(progress,0,1)*(phase_samples-1)
	var s := mini(int(sx),steering_samples-2)
	var p := mini(int(px),phase_samples-2)
	var a := values[s*phase_samples+p].lerp(values[s*phase_samples+p+1],px-p)
	var b := values[(s+1)*phase_samples+p].lerp(values[(s+1)*phase_samples+p+1],px-p)
	return a.lerp(b,sx-s)

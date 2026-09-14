extends "res://src/boat/animation/sheet_feed_profile.gd"
const BANK := preload("res://src/boat/animation/hiking_sheet_bank.gd")
const MEASURED := preload("res://src/boat/animation/sheet_feed_profile.gd")
@export var levels: Array[Resource] = []
var hike := 0.0

func valid() -> bool:
	if levels.size()!=BANK.LEVELS: return false
	for profile: Resource in levels:
		if not profile is MEASURED or not profile.valid() or profile.boundary!=&"remote_100mm": return false
		if profile.steering_samples!=steering_samples or profile.phase_samples!=phase_samples: return false
		for values: PackedFloat32Array in [profile.work_lengths,profile.helper_lengths,profile.recovery_lengths]:
			for steering in steering_samples:
				var start := steering*phase_samples
				for phase in phase_samples:
					var value := values[start+phase]
					if not is_finite(value) or value<0: return false
					if phase>0 and value<=values[start+phase-1]: return false
	return true

func length_at(section: String,steering: float,progress: float) -> float:
	var coordinate := clampf(hike,0,1)*(levels.size()-1)
	var low := mini(int(coordinate),levels.size()-2)
	return lerpf(levels[low].length_at(section,steering,progress),levels[low+1].length_at(section,steering,progress),coordinate-low)

func load_levels() -> bool:
	levels.clear()
	for level in BANK.LEVELS:
		if not ResourceLoader.exists(BANK.feed_path(level)):
			levels.clear()
			return false
		levels.append(load(BANK.feed_path(level)))
	boundary = &"remote_100mm"
	if valid(): return true
	levels.clear()
	return false

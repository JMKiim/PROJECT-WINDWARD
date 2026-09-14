extends Resource

## Measured block-to-grip travel of the authored seated-port arm layers.
@export var steering_samples := 33
@export var phase_samples := 129
@export var work_lengths := PackedFloat32Array()
@export var helper_lengths := PackedFloat32Array()
@export var recovery_lengths := PackedFloat32Array()
@export var source_signatures := {}
@export var boundary: StringName = &"deck_wrap"

func valid() -> bool:
	var count := steering_samples*phase_samples
	return steering_samples>=2 and phase_samples>=2 and work_lengths.size()==count and helper_lengths.size()==count and recovery_lengths.size()==count

func length_at(section: String, steering: float, progress: float) -> float:
	var values := work_lengths
	if section=="helper": values = helper_lengths
	elif section=="recovery": values = recovery_lengths
	var sx := clampf((steering+1)*.5,0,1)*(steering_samples-1)
	var px := clampf(progress,0,1)*(phase_samples-1)
	var s := mini(int(sx),steering_samples-2)
	var p := mini(int(px),phase_samples-2)
	var a := lerpf(values[s*phase_samples+p],values[s*phase_samples+p+1],px-p)
	var b := lerpf(values[(s+1)*phase_samples+p],values[(s+1)*phase_samples+p+1],px-p)
	return lerpf(a,b,sx-s)

func advance_distance(section: String, steering: float, progress: float, distance: float) -> float:
	var target := length_at(section,steering,progress)+distance
	if target<=length_at(section,steering,0): return 0.0
	if target>=length_at(section,steering,1): return 1.0
	# The table is piecewise linear. Locate its segment, then invert that
	# segment exactly; a finite pose bisection strands sub-micrometre input.
	var low := 0
	var high := phase_samples-1
	while high-low>1:
		var middle := (low+high)/2
		if length_at(section,steering,float(middle)/(phase_samples-1))<target: low = middle
		else: high = middle
	var first := length_at(section,steering,float(low)/(phase_samples-1))
	var last := length_at(section,steering,float(high)/(phase_samples-1))
	return (low+(target-first)/(last-first))/(phase_samples-1)

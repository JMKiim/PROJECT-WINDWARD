extends Resource

## Precomputed supported shapes; runtime uses only neighbouring shape blends.
@export var poses: Array[PackedVector3Array] = []
@export var lengths := PackedFloat64Array()
@export var source_signatures := {}

func valid() -> bool:
	if poses.size()!=lengths.size() or poses.size()<2: return false
	var count := poses[0].size()
	if count<2: return false
	for index in poses.size():
		if poses[index].size()!=count or not is_finite(lengths[index]) or lengths[index]<=0: return false
		if index>0 and lengths[index]<=lengths[index-1]: return false
		for point in poses[index]:
			if not point.is_finite(): return false
	return true

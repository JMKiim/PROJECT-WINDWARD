extends Resource
@export var steering_keys := PackedFloat32Array()
@export var frame_count := 401
@export var frames := PackedFloat32Array()
@export var tool_field_sha256 := ""
func error() -> String:
	if steering_keys.size()<2 or frame_count<2 or frames.size()!=steering_keys.size()*frame_count*8: return "hand frame dimensions"
	if steering_keys[0]>-1 or steering_keys[-1]<1: return "hand frame steering coverage"
	for i in steering_keys.size()-1:
		if steering_keys[i]>=steering_keys[i+1]: return "hand frame steering order"
	for i in range(0,frames.size(),4):
		var q := Quaternion(frames[i],frames[i+1],frames[i+2],frames[i+3])
		if not q.is_finite() or absf(q.length()-1)>.001: return "hand frame quaternion"
	return ""
func _at(s: int,index: int,side: String) -> Quaternion:
	var at: int=(s*frame_count+index)*8+(0 if side=="Left" else 4)
	return Quaternion(frames[at],frames[at+1],frames[at+2],frames[at+3]).normalized()
func sample(steering: float,u: float,side: String) -> Basis:
	var high := 1
	while high<steering_keys.size()-1 and steering_keys[high]<steering: high+=1
	var low := high-1
	var s: float=clampf(inverse_lerp(steering_keys[low],steering_keys[high],steering),0,1)
	var coordinate: float=clampf(u,0,1)*(frame_count-1)
	var index := mini(int(coordinate),frame_count-2)
	var t: float=coordinate-index
	return Basis(_at(low,index,side).slerp(_at(low,index+1,side),t).slerp(_at(high,index,side).slerp(_at(high,index+1,side),t),s))

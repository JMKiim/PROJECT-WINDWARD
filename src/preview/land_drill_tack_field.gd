extends Resource
## Offline-authored grip/roll/elbow guides. Runtime performs only bounded
## interpolation; the finite contact constructor owns the final pose.
@export var steering_keys := PackedFloat32Array()
@export var frame_count := 101
@export var values := PackedFloat32Array()
@export var uses_frames := false
@export var uses_relative_guides := false
@export var body_offsets := PackedFloat32Array()
@export var elbow_swivels := PackedFloat32Array()
const STRIDE := 10
func error() -> String:
	if frame_count<2 or frame_count>1001 or steering_keys.size()<2: return "invalid tack field dimensions"
	var stride := 16 if uses_frames else STRIDE
	if values.size()!=steering_keys.size()*frame_count*stride: return "incomplete tack field"
	if not body_offsets.is_empty() and body_offsets.size()!=steering_keys.size()*frame_count*3: return "incomplete tack body field"
	if not elbow_swivels.is_empty() and elbow_swivels.size()!=steering_keys.size()*frame_count*2: return "incomplete tack elbow field"
	for angle in elbow_swivels:
		if not is_finite(angle): return "nonfinite tack elbow field"
	for component in body_offsets:
		if not is_finite(component) or absf(component)>.100001: return "invalid tack body field"
	for index in steering_keys.size():
		if not is_finite(steering_keys[index]) or index>0 and steering_keys[index]<=steering_keys[index-1]: return "invalid tack steering keys"
	for index in values.size():
		if not is_finite(values[index]): return "nonfinite tack field"
		if index%(8 if uses_frames else 5)==0 and (values[index]<.25 or values[index]>1.235001): return "tack grip outside finite shaft"
	return ""
func sample(steering: float,u: float,side: String) -> Dictionary:
	var low := 0
	for index in steering_keys.size()-1:
		low=index
		if steering<=steering_keys[index+1]: break
	var s := clampf(inverse_lerp(steering_keys[low],steering_keys[low+1],steering),0,1)
	var coordinate := clampf(u,0,1)*(frame_count-1)
	var at := mini(int(coordinate),frame_count-2)
	var t := coordinate-at
	if uses_frames: return _frame_sample(low,at,s,t,side)
	var offset := 0 if side=="Right" else 5
	var row := PackedFloat32Array()
	for component in 5:
		var a := lerpf(values[(low*frame_count+at)*STRIDE+offset+component],values[(low*frame_count+at+1)*STRIDE+offset+component],t)
		var b := lerpf(values[((low+1)*frame_count+at)*STRIDE+offset+component],values[((low+1)*frame_count+at+1)*STRIDE+offset+component],t)
		row.append(lerpf(a,b,s))
	return {"grip":row[0],"roll_delta":row[1],"elbow":Vector3(row[2],row[3],row[4])}
func _frame_sample(low: int,at: int,s: float,t: float,side: String) -> Dictionary:
	var rows := []
	for seat in [low,low+1]:
		var frames := []
		for index in [at,at+1]:
			var offset: int=(seat*frame_count+index)*16+(0 if side=="Right" else 8)
			frames.append({"grip":values[offset],"rotation":Quaternion(values[offset+1],values[offset+2],values[offset+3],values[offset+4]).normalized(),"elbow":Vector3(values[offset+5],values[offset+6],values[offset+7])})
		rows.append({"grip":lerpf(frames[0].grip,frames[1].grip,t),"rotation":(frames[0].rotation as Quaternion).slerp(frames[1].rotation,t),"elbow":(frames[0].elbow as Vector3).lerp(frames[1].elbow,t)})
	var result := {"grip":lerpf(rows[0].grip,rows[1].grip,s),"frame":Basis((rows[0].rotation as Quaternion).slerp(rows[1].rotation,s)),"elbow":(rows[0].elbow as Vector3).lerp(rows[1].elbow,s)}
	if not elbow_swivels.is_empty():
		var hand := 0 if side=="Right" else 1
		var a: float=lerpf(elbow_swivels[(low*frame_count+at)*2+hand],elbow_swivels[(low*frame_count+at+1)*2+hand],t)
		var b: float=lerpf(elbow_swivels[((low+1)*frame_count+at)*2+hand],elbow_swivels[((low+1)*frame_count+at+1)*2+hand],t)
		result.swivel=lerpf(a,b,s)
	return result
func sample_body(steering: float,u: float) -> Vector3:
	if body_offsets.is_empty(): return Vector3.ZERO
	var low := 0
	for index in steering_keys.size()-1:
		low=index
		if steering<=steering_keys[index+1]: break
	var s := clampf(inverse_lerp(steering_keys[low],steering_keys[low+1],steering),0,1)
	var coordinate := clampf(u,0,1)*(frame_count-1)
	var at := mini(int(coordinate),frame_count-2)
	var t := coordinate-at
	var result := Vector3.ZERO
	for component in 3:
		var a := lerpf(body_offsets[(low*frame_count+at)*3+component],body_offsets[(low*frame_count+at+1)*3+component],t)
		var b := lerpf(body_offsets[((low+1)*frame_count+at)*3+component],body_offsets[((low+1)*frame_count+at+1)*3+component],t)
		result[component]=lerpf(a,b,s)
	return result

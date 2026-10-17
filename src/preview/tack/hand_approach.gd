extends Resource
@export var steering_keys := PackedFloat32Array()
@export var left_values := PackedFloat32Array()
@export var right_values := PackedFloat32Array()
@export var count := 49
@export var phase_keys := PackedFloat32Array()
@export var tool_field_sha256 := ""
const STRIDE := 10
func active(u: float,side: String) -> bool:
	return u>=.38 and u<=.50 if side=="Left" else u>=.52 and u<=.64
func error() -> String:
	if count<2 or steering_keys.size()<2: return "open hand patch dimensions"
	if not phase_keys.is_empty():
		if phase_keys.size()!=count or absf(phase_keys[0])>.000001 or absf(phase_keys[-1]-.12)>.000001: return "open hand phase coverage"
		for index in count-1:
			if not is_finite(phase_keys[index]) or phase_keys[index]>=phase_keys[index+1]: return "open hand phase order"
	if steering_keys[0]>-1 or steering_keys[-1]<1: return "open hand patch steering coverage"
	for index in steering_keys.size()-1:
		if steering_keys[index]>=steering_keys[index+1]: return "open hand patch steering order"
	for values in [left_values,right_values]:
		if values.size()!=steering_keys.size()*count*STRIDE: return "open hand patch incomplete"
		for value in values:
			if not is_finite(value): return "open hand patch nonfinite"
	return ""
func _at(s: int,i: int,side: String) -> Dictionary:
	var values: PackedFloat32Array=left_values if side=="Left" else right_values
	var at: int=(s*count+i)*STRIDE
	return {"wrist":Vector3(values[at],values[at+1],values[at+2]),"rotation":Quaternion(values[at+3],values[at+4],values[at+5],values[at+6]).normalized(),"elbow":Vector3(values[at+7],values[at+8],values[at+9])}
func sample(s: float,u: float,side: String) -> Dictionary:
	var high := 1
	while high<steering_keys.size()-1 and steering_keys[high]<s: high+=1
	var low := high-1
	var t: float=clampf(inverse_lerp(steering_keys[low],steering_keys[high],s),0,1)
	var coordinate: float=clampf(inverse_lerp(.38 if side=="Left" else .52,.50 if side=="Left" else .64,u),0,1)*(count-1)
	var index := mini(int(coordinate),count-2)
	var phase: float=coordinate-index
	if not phase_keys.is_empty():
		var local: float=u-(.38 if side=="Left" else .52)
		index=0
		while index<count-2 and phase_keys[index+1]<local: index+=1
		phase=clampf(inverse_lerp(phase_keys[index],phase_keys[index+1],local),0,1)
	var rows := []
	for steer in [low,high]:
		var a := _at(steer,index,side)
		var b := _at(steer,index+1,side)
		rows.append({"wrist":(a.wrist as Vector3).lerp(b.wrist,phase),"elbow":(a.elbow as Vector3).lerp(b.elbow,phase),"rotation":(a.rotation as Quaternion).slerp(b.rotation,phase)})
	return {"wrist":(rows[0].wrist as Vector3).lerp(rows[1].wrist,t),"elbow":(rows[0].elbow as Vector3).lerp(rows[1].elbow,t),"frame":Basis((rows[0].rotation as Quaternion).slerp(rows[1].rotation,t))}

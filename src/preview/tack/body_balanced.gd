extends "res://src/preview/tack/body_staged.gd"
func coordinates_at(u: float) -> Vector2:
	if u>.5:
		var old := coordinates_at(1-u)
		return Vector2(1-old.x,1-old.y)
	if u<.28: return Vector2(.1875*smoothstep(.1,.18,u),0)
	var t := smoothstep(.28,.46,u)
	return Vector2(.1875+.3125*t,.5*t)
func contact_offset(u: float) -> Vector3:
	var t := u if u<=.5 else 1-u
	return Vector3(0,0,.025)*smoothstep(.05,.1,t)*(1-smoothstep(.3,.4,t))
func lean_at(u: float) -> float:
	var t := u if u<=.5 else 1-u
	return deg_to_rad(12)*smoothstep(.1,.18,t)*(1-smoothstep(.28,.4,t))
func foot_step(side: String,u: float) -> float:
	return smoothstep(.28,.50,u) if side=="Left" else 1-smoothstep(.28,.50,1-u)

extends "res://src/preview/tack/body_base.gd"
func coordinates_at(u: float) -> Vector2:
	if u<.28: return Vector2(.1875*smoothstep(.1,.18,u),0)
	if u<=.5:
		var t := smoothstep(.28,.46,u)
		return Vector2(.1875+.3125*t,.5*t)
	if u<.74:
		var t := smoothstep(.56,.74,u)
		return Vector2(.5+.3125*t,.5+.5*t)
	return Vector2(.8125+.1875*smoothstep(.74,.86,u),1)
func hips_at(cross: float,u: float) -> Vector3:
	var hips := super.hips_at(cross,u)
	# Lower only after the pelvis has left the deck edge. The endpoint seat
	# remains untouched; this is a ducked step, not a translated seated spin.
	hips.y-=.05*smoothstep(.5,.35,absf(hips.x))
	return hips+contact_offset(u)
func contact_offset(u: float) -> Vector3:
	# Small fore/aft weight transfer measured at the remaining contact
	# witnesses. Feet are still solved to the unchanged floor step targets.
	var entry := smoothstep(.05,.1,u)*(1-smoothstep(.3,.4,u))
	var exit := smoothstep(.7,.8,u)*(1-smoothstep(.95,1,u))
	return Vector3(0,0,.025)*(entry+exit)
func lean_at(u: float) -> float:
	var entry := smoothstep(.1,.18,u)*(1-smoothstep(.28,.4,u))
	var exit := smoothstep(.64,.74,u)*(1-smoothstep(.74,.86,u))
	return deg_to_rad(12)*(entry+exit)
func foot_step(side: String,u: float) -> float:
	return smoothstep(.28,.50,u) if side=="Left" else smoothstep(.5,.78,u)

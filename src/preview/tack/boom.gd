extends RefCounted
## A prescribed spar crossing: approach a small opening first, cross it
## briskly, then settle on the new side. No human pose is moved by the rig.
static func yaw(initial: float,final: float,u: float) -> float:
	var gate := deg_to_rad(12)
	if u<.44: return lerpf(initial,gate,smoothstep(0,.44,u))
	if u<=.56: return lerpf(gate,-gate,smoothstep(.44,.56,u))
	return lerpf(-gate,final,smoothstep(.56,.96,u))

extends RefCounted
## Prescribed land drill,not a sail-pressure solver. The boom passes before
## the central hand exchange; the normal sheet inputs prepare and ease it.
static func yaw(initial: float,final: float,travel: float) -> float:
	var sign: float=1 if initial>=0 else -1
	var gate: float=deg_to_rad(12)*sign
	if travel<.30: return lerpf(initial,gate,smoothstep(.08,.30,travel))
	if travel<=.46: return lerpf(gate,-gate,smoothstep(.30,.46,travel))
	return lerpf(-gate,final,smoothstep(.56,.96,travel))

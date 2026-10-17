extends RefCounted
## The spatial path is unchanged. Redistribute a small part of the same
##5.25s across the measured finite free-hand rotation peak,not a pause or
## a longer whole maneuver. Ordinary sheet input never reads this clock.
const START := .125
const STOP := .190
const WEIGHT := .012
const CLOSURE_START := .475
const CLOSURE_STOP := .515
const CLOSURE_WEIGHT := .0075
const TOOL_START := .674
const TOOL_STOP := .684
const TOOL_WEIGHT := .005
static func clock(u: float) -> float:
	return (1-WEIGHT-CLOSURE_WEIGHT-TOOL_WEIGHT)*u+WEIGHT*smoothstep(START,STOP,u)+CLOSURE_WEIGHT*smoothstep(CLOSURE_START,CLOSURE_STOP,u)+TOOL_WEIGHT*smoothstep(TOOL_START,TOOL_STOP,u)
static func phase(p: float) -> float:
	if p<=clock(START): return p/(1-WEIGHT-CLOSURE_WEIGHT-TOOL_WEIGHT)
	if p>=clock(TOOL_STOP): return (p-WEIGHT-CLOSURE_WEIGHT-TOOL_WEIGHT)/(1-WEIGHT-CLOSURE_WEIGHT-TOOL_WEIGHT)
	var u := p
	for iteration in 8:
		var derivative: float=1-WEIGHT-CLOSURE_WEIGHT-TOOL_WEIGHT
		for pulse: Vector3 in [Vector3(START,STOP,WEIGHT),Vector3(CLOSURE_START,CLOSURE_STOP,CLOSURE_WEIGHT),Vector3(TOOL_START,TOOL_STOP,TOOL_WEIGHT)]:
			var x: float=clampf((u-pulse.x)/(pulse.y-pulse.x),0,1)
			derivative+=pulse.z*6*x*(1-x)/(pulse.y-pulse.x)
		u=clampf(u-(clock(u)-p)/derivative,0,1)
	return u

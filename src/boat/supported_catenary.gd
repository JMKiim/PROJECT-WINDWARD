extends RefCounted

## A planar cable above a sampled obstacle, at a prescribed horizontal
## tension/weight ratio. Contacts form an upper support chain; between them
## the cable is a catenary, not independently clamped height samples.
static func height(width: float,rise: float,x: float,curvature: float) -> float:
	if width<=.0000001: return rise
	if curvature*width<.005:
		var t := x/width
		return rise*t-curvature*width*width*t*(1-t)*.5*sqrt(1+rise*rise/(width*width))
	var a := 1.0/curvature
	var ratio := rise/(2*a*sinh(width/(2*a)))
	var offset := width*.5-a*log(ratio+sqrt(ratio*ratio+1))
	# Difference-of-cosh identity avoids cancellation near a contact point.
	return 2*a*sinh(x/(2*a))*sinh((x-2*offset)/(2*a))

static func solve(parameters: PackedFloat64Array,floor: PackedFloat64Array,width: float,first: float,last: float,curvature: float) -> Dictionary:
	var count := parameters.size()
	if count<2 or count!=floor.size() or not is_finite(width) or width<=.0000001 or not is_finite(first) or not is_finite(last) or not is_finite(curvature) or curvature<0 or curvature*width>16.000001:
		return {"valid":false,"reason":"invalid support chain"}
	if parameters[0]!=0.0 or parameters[-1]!=1.0: return {"valid":false,"reason":"missing fixed endpoints"}
	var chain := PackedInt32Array()
	var levels := floor.duplicate()
	levels[0]=first
	levels[-1]=last
	for index in count:
		if not is_finite(parameters[index]) or is_nan(levels[index]) or levels[index]==INF: return {"valid":false,"reason":"nonfinite support sample"}
		if index>0 and parameters[index]<=parameters[index-1]: return {"valid":false,"reason":"unordered support samples"}
		if not is_finite(levels[index]): continue
		chain.append(index)
		while chain.size()>=3:
			var a := chain[-3]
			var b := chain[-2]
			var c := chain[-1]
			var y := levels[a]+height((parameters[c]-parameters[a])*width,levels[c]-levels[a],(parameters[b]-parameters[a])*width,curvature)
			if y<levels[b]-1e-10: break
			chain.remove_at(chain.size()-2)
	var result := PackedFloat64Array()
	result.resize(count)
	for segment in chain.size()-1:
		var a := chain[segment]
		var b := chain[segment+1]
		for index in range(a,b+1):
			result[index]=levels[a]+height((parameters[b]-parameters[a])*width,levels[b]-levels[a],(parameters[index]-parameters[a])*width,curvature)
	return {"valid":true,"heights":result,"contacts":chain}

static func slope(width: float,rise: float,x: float,curvature: float) -> float:
	if curvature*width<.005:
		return rise/width-curvature*width*(1-2*x/width)*.5*sqrt(1+rise*rise/(width*width))
	var a := 1.0/curvature
	var ratio := rise/(2*a*sinh(width/(2*a)))
	var offset := width*.5-a*log(ratio+sqrt(ratio*ratio+1))
	return sinh((x-offset)/a)

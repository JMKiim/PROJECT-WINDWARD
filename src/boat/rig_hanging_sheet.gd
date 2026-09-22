extends RefCounted

## Gravity-shaped free spans between finite, already fitted rope guides.
## Guide contact arcs and the hand lead are retained. Short mouth blends keep
## their tangents continuous; this is not a friction or rope-weight load solver.
const SAMPLES := 48
const LENGTH_EPS := .000015

static func length_of(path: PackedVector3Array) -> float:
	var result := 0.0
	for index in path.size()-1: result+=path[index].distance_to(path[index+1])
	return result

static func build(path: PackedVector3Array,wraps: Dictionary,target: float,gravity: Vector3) -> Dictionary:
	if path.size()<6: return {"valid":false,"reason":"incomplete hanging route"}
	for point in path:
		if not point.is_finite(): return {"valid":false,"reason":"nonfinite hanging route"}
	for name in ["becket","traveller","aft","forward","deck"]:
		if not wraps.has(name) or not wraps[name].has_all(["begin","end"]):
			return {"valid":false,"reason":"missing hanging guide"}
	var direct := length_of(path)
	if not is_finite(target) or not gravity.is_finite() or target<direct-.00005:
		return {"valid":false,"reason":"hanging path cannot shorten its supports"}
	if target<=direct+LENGTH_EPS:
		return {"valid":true,"path":path.duplicate(),"slack_metres":0.0,"error_metres":direct-target,"curvature":0.0}
	if gravity.length()<.0001: return {"valid":false,"reason":"no effective gravity for hanging path"}
	var spans := {}
	for pair in [["becket","traveller"],["traveller","aft"],["aft","guide"],["guide","forward"],["forward","deck"]]:
		var begin: int=wraps.aft.end+1 if pair[0]=="guide" else wraps[pair[0]].end
		var end: int=wraps.aft.end+1 if pair[1]=="guide" else wraps[pair[1]].begin
		if end!=begin+1 or begin<0 or end>=path.size(): return {"valid":false,"reason":"unexpected free span topology"}
		spans[begin]=end
	var up := -gravity.normalized()
	var low := 0.0
	var high := .5
	var candidate := _path(path,spans,up,high)
	for bracket in 12:
		if length_of(candidate)>=target: break
		high*=2
		candidate=_path(path,spans,up,high)
	if length_of(candidate)<target: return {"valid":false,"reason":"hanging span allocation out of range"}
	var curve := high
	for iteration in 28:
		curve=(low+high)*.5
		candidate=_path(path,spans,up,curve)
		var measured := length_of(candidate)
		if absf(measured-target)<LENGTH_EPS*.5: break
		if measured<target: low=curve
		else: high=curve
	var error := length_of(candidate)-target
	return {"valid":absf(error)<=LENGTH_EPS,"path":candidate,"slack_metres":target-direct,"error_metres":error,"curvature":curve}

static func _path(path: PackedVector3Array,spans: Dictionary,up: Vector3,curve: float) -> PackedVector3Array:
	var result := PackedVector3Array([path[0]])
	for index in path.size()-1:
		if not spans.has(index):
			result.append(path[index+1])
			continue
		var first := path[index]
		var last := path[index+1]
		var delta := last-first
		var rise := delta.dot(up)
		var flat := delta-up*rise
		var width := flat.length()
		var mouth := minf(.18,.060/maxf(delta.length(),.001))
		var blend := minf(.12,.035/maxf(delta.length(),.001))
		for sample in range(1,SAMPLES+1):
			var t := sample/float(SAMPLES)
			var drop := 0.0
			if width>.0001 and curve>0:
				var k := minf(curve,16.0/width)
				if k*width<.005:
					drop=k*width*width*t*(1-t)*.5*sqrt(1+rise*rise/(width*width))
				else:
					var a := 1.0/k
					var ratio := rise/(2*a*sinh(width/(2*a)))
					var offset := width*.5-a*log(ratio+sqrt(ratio*ratio+1))
					var y := a*(cosh((width*t-offset)/a)-cosh(offset/a))
					drop=maxf(0,rise*t-y)
				drop*=smoothstep(mouth,mouth+blend,t)*smoothstep(mouth,mouth+blend,1-t)
			result.append(first.lerp(last,t)-up*drop)
	return result

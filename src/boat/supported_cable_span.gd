extends RefCounted

## A single heavy cable over a flat support normal to effective gravity.
## Endpoints and material length are prescribed; touching cable is not clipped.
## No friction, folds, fittings, rigid blocks or curved hull are modeled here.
const LENGTH_TOLERANCE := .00005
const SHAPE_TOLERANCE := .000008

static func solve(first: Vector3,last: Vector3,metres: float,plane_point: Vector3,plane_normal: Vector3,gravity: Vector3,radius: float,kg_per_metre: float,sample_path := true) -> Dictionary:
	if not first.is_finite() or not last.is_finite() or not plane_point.is_finite() or not plane_normal.is_finite() or not gravity.is_finite() or not is_finite(metres) or not is_finite(radius) or not is_finite(kg_per_metre) or metres<=0 or radius<0 or kg_per_metre<=0 or gravity.length()<.0001 or plane_normal.length()<.0001:
		return {"valid":false,"reason":"invalid supported cable boundary"}
	var up := -gravity.normalized()
	if plane_normal.normalized().distance_to(up)>.00001:
		return {"valid":false,"reason":"inclined support requires tangential contact forces"}
	var h0 := (first-plane_point).dot(up)-radius
	var h1 := (last-plane_point).dot(up)-radius
	if minf(h0,h1)<-.000001:
		return {"valid":false,"reason":"cable endpoint penetrates support"}
	h0=maxf(0,h0)
	h1=maxf(0,h1)
	var flat := last-first-up*(h1-h0)
	var width := flat.length()
	if width<.0001:
		return {"valid":false,"reason":"coincident support projections require a folded path"}
	var direct := first.distance_to(last)
	if metres<direct-.000001:
		return {"valid":false,"reason":"cable shorter than endpoint distance"}
	if metres>width+h0+h1+.000001:
		return {"valid":false,"reason":"excess material requires supported folds"}
	var shape := {"first":first,"last":last,"origin":first-up*h0,"up":up,"axis":flat/width,"width":width,"h0":h0,"h1":h1,"metres":metres,"a":0.0,"contact":0.0,"left_length":0.0,"right_length":0.0,"left_run":0.0,"branch":"supported"}
	if absf(metres-(width+h0+h1))<=.000001:
		# Limit of vanishing horizontal tension: vertical drops and supported run.
		shape.contact=width
		shape.left_length=h0
		shape.right_length=h1
	elif metres<=direct+.000001:
		return {"valid":false,"reason":"straight suspended cable needs an external tension boundary"}
	else:
		# Free catenary first; release only when its minimum reaches the support.
		var reduced := sqrt(maxf(0,metres*metres-(h1-h0)*(h1-h0)))
		var low := .000001
		var high := 40.0
		for iteration in 64:
			var q := (low+high)*.5
			if sinh(q)/q>reduced/width: high=q
			else: low=q
		shape.a=width/(low+high)
		var a: float=shape.a
		var xc := width*.5-a*_asinh((h1-h0)/reduced)
		var s0 := -a*sinh(xc/a)
		var at_min := clampf(xc,0,width)
		var lowest := h0+a*(cosh((at_min-xc)/a)-cosh(xc/a))
		shape["s0"]=s0
		shape.branch="suspended"
		if lowest<0:
			shape.branch="supported"
			low=0
			high=maxf(1,a)
			for bracket in 40:
				if _supported_length(high,width,h0,h1)<=metres: break
				high*=2
			for iteration in 64:
				var candidate := (low+high)*.5
				if _supported_length(candidate,width,h0,h1)>metres: low=candidate
				else: high=candidate
			shape.a=(low+high)*.5
			shape.left_length=sqrt(h0*(h0+2*shape.a))
			shape.right_length=sqrt(h1*(h1+2*shape.a))
			shape.left_run=_run(shape.a,h0)
			shape.contact=width-shape.left_run-_run(shape.a,h1)
			if shape.contact<-.000001:
				return {"valid":false,"reason":"support contact boundary did not converge"}
			shape.contact=maxf(0,shape.contact)
	var path := PackedVector3Array()
	var breaks := [0.0,metres]
	if shape.branch=="supported": breaks=[0.0,shape.left_length,shape.left_length+shape.contact,metres]
	var measured := metres
	var gap := 0.0
	if shape.branch=="suspended":
		var s: float=clampf(-shape.s0,0,metres)
		gap=_coordinates(shape,s)[1]
	if sample_path:
		path.append(first)
		for index in breaks.size()-1:
			if breaks[index+1]-breaks[index]>.0000001:
				_append_span(path,shape,breaks[index],breaks[index+1],0)
		path[-1]=last
		measured=0.0
		gap=INF
		for index in path.size():
			gap=minf(gap,(path[index]-plane_point).dot(up)-radius)
			if index>0: measured+=path[index-1].distance_to(path[index])
	var weight := kg_per_metre*gravity.length()
	var horizontal: float=weight*shape.a
	var first_vertical: float=shape.s0*weight if shape.branch=="suspended" else -shape.left_length*weight
	var last_vertical: float=-(shape.s0+metres)*weight if shape.branch=="suspended" else -shape.right_length*weight
	var first_force: Vector3=shape.axis*horizontal+up*first_vertical
	var last_force: Vector3=-shape.axis*horizontal+up*last_vertical
	var support: Vector3=up*(weight*shape.contact)
	var cable_weight := gravity*(kg_per_metre*metres)
	var residual: float=(-first_force-last_force+support+cable_weight).length()
	var energy: float=weight*(shape.origin.dot(up)*metres+_height_integral(shape))
	# -dE/dL at fixed endpoints: the invariant T - w*y. Comparing only H
	# between two differently oriented spans does not conserve pulley work.
	var tension_potential := sqrt(horizontal*horizontal+first_vertical*first_vertical)-weight*first.dot(up)
	return {"valid":absf(measured-metres)<=LENGTH_TOLERANCE and gap>=-.000001 and residual<.0001,"reason":"single flat-support span only","path":path,"branch":shape.branch,"a":shape.a,"contact_metres":shape.contact,"left_suspended_metres":shape.left_length,"right_suspended_metres":shape.right_length,"length_error_metres":measured-metres,"minimum_gap_metres":gap,"first_force_n":first_force,"last_force_n":last_force,"support_force_n":support,"weight_force_n":cable_weight,"balance_n":residual,"horizontal_tension_n":horizontal,"energy_j":energy,"tension_potential_n":tension_potential,"shape":shape,"sampled":sample_path}

static func _height_primitive(a: float,t: float) -> float:
	if a==0: return t*absf(t)*.5
	return .5*(t*sqrt(a*a+t*t)+a*a*_asinh(t/a))

static func _height_integral(shape: Dictionary) -> float:
	var a: float=shape.a
	if shape.branch=="suspended":
		return (shape.h0-sqrt(a*a+shape.s0*shape.s0))*shape.metres+_height_primitive(a,shape.s0+shape.metres)-_height_primitive(a,shape.s0)
	return _height_primitive(a,shape.left_length)-a*shape.left_length+_height_primitive(a,shape.right_length)-a*shape.right_length

static func _asinh(value: float) -> float:
	return signf(value)*log(absf(value)+sqrt(value*value+1))

static func _run(a: float,height: float) -> float:
	return a*_asinh(sqrt(height*(height+2*a))/a)

static func _supported_length(a: float,width: float,h0: float,h1: float) -> float:
	return width+sqrt(h0*(h0+2*a))-_run(a,h0)+sqrt(h1*(h1+2*a))-_run(a,h1)

static func _coordinates(shape: Dictionary,s: float) -> Array:
	if s<=0: return [0.0,shape.h0]
	if s>=shape.metres: return [shape.width,shape.h1]
	var a: float=shape.a
	var x := 0.0
	var y := 0.0
	if shape.branch=="suspended":
		var t: float=shape.s0+s
		x=a*(_asinh(t/a)-_asinh(shape.s0/a))
		y=shape.h0+sqrt(a*a+t*t)-sqrt(a*a+shape.s0*shape.s0)
	elif a==0:
		x=clampf(s-shape.h0,0,shape.width)
		y=maxf(0,shape.h0-s)+maxf(0,s-shape.h0-shape.width)
	elif s<shape.left_length:
		var t: float=shape.left_length-s
		x=shape.left_run-a*_asinh(t/a)
		y=sqrt(a*a+t*t)-a
	elif s<=shape.left_length+shape.contact:
		x=shape.left_run+s-shape.left_length
	else:
		var t: float=s-shape.left_length-shape.contact
		x=shape.left_run+shape.contact+a*_asinh(t/a)
		y=sqrt(a*a+t*t)-a
	return [x,y]

static func _point(shape: Dictionary,s: float) -> Vector3:
	var xy := _coordinates(shape,s)
	return shape.origin+shape.axis*xy[0]+shape.up*xy[1]

static func _append_span(path: PackedVector3Array,shape: Dictionary,begin: float,end: float,depth: int) -> void:
	var first := _coordinates(shape,begin)
	var last := _coordinates(shape,end)
	var length := end-begin
	# Compute the error in scalar precision; float vertex quantization must not
	# recursively subdivide an already accurate curve into thousands of points.
	var dx: float=last[0]-first[0]
	var dy: float=last[1]-first[1]
	var chord := sqrt(dx*dx+dy*dy)
	# Bound polygonal length loss in material coordinates, not by clamping y.
	if depth<16 and (length>.05 or length-chord>SHAPE_TOLERANCE*length/shape.metres):
		var middle := (begin+end)*.5
		_append_span(path,shape,begin,middle,depth+1)
		_append_span(path,shape,middle,end,depth+1)
	else: path.append(_point(shape,end))

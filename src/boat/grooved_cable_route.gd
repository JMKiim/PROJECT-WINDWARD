extends RefCounted

## Stationary finite-rope curve on the inward offset of a round sheave
## groove, with exact endpoint surface tangency and integrated arc metric.
## Independent full-mesh / rope-pair clearance remains a caller obligation.
const CIRCLE := preload("res://src/boat/cylinder_cable_route.gd")
const PIN := preload("res://src/boat/revolute_pin_joint.gd")
const QUADRATURE := [[.046910077030668, .118463442528095],[.230765344947158,.239314335249683],[.5,.284444444444444],[.769234655052842,.239314335249683],[.953089922969332,.118463442528095]]
static var _samples := _make_samples()

static func _make_samples() -> Array:
	var result := []
	for span in [1,2,3]:
		var row := []
		for sample in QUADRATURE:
			var basis := _shape(sample[0],span)
			row.append([sample[1],basis[0],basis[1]])
		result.append(row)
	return result

static func _shape(t: float,span: int) -> Array:
	if span==1: return [PackedFloat64Array([1-t,t]),PackedFloat64Array([-1,1])]
	if span==3:
		return [PackedFloat64Array([1-5.5*t+9*t*t-4.5*t*t*t,9*t-22.5*t*t+13.5*t*t*t,-4.5*t+18*t*t-13.5*t*t*t,t-4.5*t*t+4.5*t*t*t]),PackedFloat64Array([-5.5+18*t-13.5*t*t,9-45*t+40.5*t*t,-4.5+36*t-40.5*t*t,1-9*t+13.5*t*t])]
	return [PackedFloat64Array([2*t*t-3*t+1,4*t*(1-t),2*t*t-t]),PackedFloat64Array([4*t-3,4-8*t,4*t-1])]

static func _element(q: PackedFloat64Array,i: int,span: int,t: float) -> Dictionary:
	var basis := _shape(t,span)
	var alpha := 0.0
	var slope := 0.0
	for j in span+1:
		alpha+=basis[0][j]*q[i+j]
		slope+=basis[1][j]*q[i+j]
	return {"alpha":alpha,"slope":slope,"weights":basis[0],"derivatives":basis[1]}

static func _bounded(q: PackedFloat64Array,i: int,span: int,limit: float) -> bool:
	var a := 0.0
	var b := 0.0
	var c := 0.0
	if span==3:
		a=3*(-4.5*q[i]+13.5*q[i+1]-13.5*q[i+2]+4.5*q[i+3])
		b=2*(9*q[i]-22.5*q[i+1]+18*q[i+2]-4.5*q[i+3])
		c=-5.5*q[i]+9*q[i+1]-4.5*q[i+2]+q[i+3]
	elif span==2:
		b=2*(2*q[i]-4*q[i+1]+2*q[i+2])
		c=-3*q[i]+4*q[i+1]-q[i+2]
	var roots := PackedFloat64Array()
	if absf(a)<1e-15:
		if absf(b)>1e-15: roots.append(-c/b)
	else:
		var discriminant := b*b-4*a*c
		if discriminant>=0:
			roots.append((-b+sqrt(discriminant))/(2*a))
			roots.append((-b-sqrt(discriminant))/(2*a))
	for t in roots:
		if t>0 and t<1 and absf(_element(q,i,span,t).alpha)>limit: return false
	return true

static func _dot(a: PackedFloat64Array,b: PackedFloat64Array) -> float:
	var result := 0.0
	for i in a.size(): result+=a[i]*b[i]
	return result

static func _sum(values: PackedFloat64Array) -> float:
	var total := 0.0
	var correction := 0.0
	for value in values:
		var adjusted := value-correction
		var next := total+adjusted
		correction=(next-total)-adjusted
		total=next
	return total

static func _maximum(a: PackedFloat64Array) -> float:
	var result := 0.0
	for value in a: result=maxf(result,absf(value))
	return result

static func _linear(matrix: Array,rhs: PackedFloat64Array) -> PackedFloat64Array:
	for column in rhs.size():
		var pivot := column
		for row in range(column+1,rhs.size()):
			if absf(matrix[row][column])>absf(matrix[pivot][column]): pivot=row
		if absf(matrix[pivot][column])<1e-16: return PackedFloat64Array()
		var saved: PackedFloat64Array=matrix[column]
		matrix[column]=matrix[pivot]
		matrix[pivot]=saved
		var value := rhs[column]
		rhs[column]=rhs[pivot]
		rhs[pivot]=value
		for row in range(column+1,rhs.size()):
			var factor: float=matrix[row][column]/matrix[column][column]
			for index in range(column,rhs.size()): matrix[row][index]-=factor*matrix[column][index]
			rhs[row]-=factor*rhs[column]
	var answer := rhs.duplicate()
	for reverse in rhs.size():
		var row := rhs.size()-1-reverse
		for index in range(row+1,rhs.size()): answer[row]-=matrix[row][index]*answer[index]
		answer[row]/=matrix[row][row]
	return answer

static func _hessian(q: PackedFloat64Array,context: Dictionary) -> Array:
	var matrix := []
	for i in q.size():
		var row := PackedFloat64Array()
		row.resize(q.size())
		matrix.append(row)
	var entrance := _contact_theta(context.a,q[0],context,context.first)
	var departure := _contact_theta(context.b,q[-1],context,context.last)
	if not entrance.valid or not departure.valid: return []
	for i in range(0,q.size()-1,3):
		var span := mini(3,q.size()-1-i)
		var theta: float=(departure.theta-entrance.theta)*span/float(q.size()-1)
		for sample in _samples[span-1]:
			var weights: PackedFloat64Array=sample[1]
			var signs: PackedFloat64Array=sample[2]
			var alpha := 0.0
			var delta := 0.0
			for j in span+1:
				alpha+=weights[j]*q[i+j]
				delta+=signs[j]*q[i+j]
			var radius: float=context.major-context.minor*cos(alpha)
			var radial_first: float=context.minor*sin(alpha)
			var radial_second: float=context.minor*cos(alpha)
			var speed := sqrt(pow(context.minor*delta,2)+pow(radius*theta,2))
			for a in span+1:
				for b in span+1:
					var na: float=radius*radial_first*theta*theta*weights[a]+context.minor*context.minor*delta*signs[a]
					var nb: float=radius*radial_first*theta*theta*weights[b]+context.minor*context.minor*delta*signs[b]
					var curvature: float=((radial_first*radial_first+radius*radial_second)*theta*theta*weights[a]*weights[b]+context.minor*context.minor*signs[a]*signs[b])/speed-na*nb/(speed*speed*speed)
					matrix[i+a][i+b]+=sample[0]*curvature
	# Only the two endpoint variables move the theta interval. Their columns
	# include the exact tangent-boundary chain rule via a centred derivative.
	for column in [0,q.size()-1]:
		var a := q.duplicate()
		var b := q.duplicate()
		a[column]-=.0001
		b[column]+=.0001
		var before := _energy(a,context)
		var after := _energy(b,context)
		if not before.valid or not after.valid: return []
		for row in q.size(): matrix[row][column]=(after.gradient[row]-before.gradient[row])/.0002
	for row in range(1,q.size()-1):
		matrix[0][row]=matrix[row][0]
		matrix[-1][row]=matrix[row][-1]
	var cross_term: float=(matrix[0][-1]+matrix[-1][0])*.5
	matrix[0][-1]=cross_term
	matrix[-1][0]=cross_term
	return matrix

static func _polish(q: PackedFloat64Array,context: Dictionary,current: Dictionary,deadline: int,cancelled: Callable) -> Dictionary:
	if Time.get_ticks_usec()>=deadline or (cancelled.is_valid() and cancelled.call()): return {"valid":false}
	var matrix := _hessian(q,context)
	if matrix.is_empty(): return {"valid":false}
	var rhs: PackedFloat64Array=current.gradient.duplicate()
	for i in rhs.size(): rhs[i]=-rhs[i]
	var step := _linear(matrix,rhs)
	if step.is_empty() or _maximum(step)>.01: return {"valid":false,"reason":"correction too large","step":_maximum(step)}
	var next := q.duplicate()
	for i in q.size(): next[i]+=step[i]
	var trial := _energy(next,context)
	if not trial.valid: return {"valid":false,"reason":"correction domain"}
	if trial.length>current.length+2e-15*maxf(1,current.length) or _maximum(trial.gradient)>=_maximum(current.gradient)*.5: return {"valid":false,"reason":"correction did not reduce residual within energy uncertainty","energy_change":trial.length-current.length,"gradient_ratio":_maximum(trial.gradient)/_maximum(current.gradient)}
	return {"valid":true,"q":next,"energy":trial}

static func _contact_theta(endpoint: PackedFloat64Array,alpha: float,context: Dictionary,seed: float) -> Dictionary:
	var ca := cos(alpha)
	if ca<=.001: return {"valid":false}
	var radius := sqrt(endpoint[1]*endpoint[1]+endpoint[2]*endpoint[2])
	var level: float=context.major-context.minor/ca+endpoint[0]*tan(alpha)
	if radius<=absf(level)+1e-10: return {"valid":false}
	var offset := acos(level/radius)
	var centre := atan2(endpoint[2],endpoint[1])
	var left := seed+wrapf(centre-offset-seed,-PI,PI)
	var right := seed+wrapf(centre+offset-seed,-PI,PI)
	var theta := left if absf(left-seed)<absf(right-seed) else right
	var derivative: float=(-context.minor*sin(alpha)/(ca*ca)+endpoint[0]/(ca*ca))/(-endpoint[1]*sin(theta)+endpoint[2]*cos(theta))
	return {"valid":true,"theta":theta,"derivative":derivative}

static func _energy(q: PackedFloat64Array,context: Dictionary) -> Dictionary:
	var count: int=q.size()
	var entrance := _contact_theta(context.a,q[0],context,context.first)
	var departure := _contact_theta(context.b,q[-1],context,context.last)
	if not entrance.valid or not departure.valid: return {"valid":false}
	var first: float=entrance.theta
	var last: float=departure.theta
	if (last-first)*context.direction<=.001 or absf(last-first)>TAU-.001: return {"valid":false}
	var points := []
	var alpha_derivatives := []
	var theta_derivatives := []
	for i in count:
		var alpha := q[i]
		if absf(alpha)>context.alpha_max: return {"valid":false}
		var theta := lerpf(first,last,i/float(count-1))
		var ca := cos(alpha)
		var sa := sin(alpha)
		var ct := cos(theta)
		var st := sin(theta)
		var radius: float=context.major-context.minor*ca
		points.append(PackedFloat64Array([context.minor*sa,radius*ct,radius*st]))
		alpha_derivatives.append(PackedFloat64Array([context.minor*ca,context.minor*sa*ct,context.minor*sa*st]))
		theta_derivatives.append(PackedFloat64Array([0,-radius*st,radius*ct]))
	var units := []
	var length_terms := PackedFloat64Array()
	var gradient := PackedFloat64Array()
	gradient.resize(q.size())
	var angle_gradient := PackedFloat64Array([0,0])
	for end in 2:
		var index := 0 if end==0 else count-1
		var source: PackedFloat64Array=context.a if end==0 else points[-1]
		var target: PackedFloat64Array=points[0] if end==0 else context.b
		var delta := PackedFloat64Array()
		for j in 3: delta.append(target[j]-source[j])
		var distance := sqrt(_dot(delta,delta))
		if distance<1e-10: return {"valid":false}
		length_terms.append(distance)
		for j in 3: delta[j]/=distance
		units.append(delta)
		var sign_value := 1.0 if end==0 else -1.0
		gradient[index]+=sign_value*_dot(delta,alpha_derivatives[index])
		angle_gradient[end]+=sign_value*_dot(delta,theta_derivatives[index])
	# Integrate the surface metric, not chords through the sheave. Theta is
	# the independent parameter; all cross-groove samples are variational.
	var minimum_normal := INF
	for i in range(0,count-1,3):
		var span := mini(3,count-1-i)
		var delta_theta := (last-first)*span/float(count-1)
		# Bound the full polynomial, including interior extrema between nodes.
		if not _bounded(q,i,span,context.alpha_max): return {"valid":false}
		for sample in _samples[span-1]:
			var weight: float=sample[0]
			var weights: PackedFloat64Array=sample[1]
			var derivatives: PackedFloat64Array=sample[2]
			var alpha := 0.0
			var delta_alpha := 0.0
			for j in span+1:
				alpha+=weights[j]*q[i+j]
				delta_alpha+=derivatives[j]*q[i+j]
			var radius: float=context.major-context.minor*cos(alpha)
			var speed := sqrt(pow(context.minor*delta_alpha,2)+pow(radius*delta_theta,2))
			if speed<1e-12: return {"valid":false}
			length_terms.append(weight*speed)
			var cross_slope: float=weight*context.minor*context.minor*delta_alpha/speed
			var radial_slope: float=weight*radius*context.minor*sin(alpha)*delta_theta*delta_theta/speed
			for j in span+1: gradient[i+j]+=radial_slope*weights[j]+cross_slope*derivatives[j]
			var theta_slope: float=weight*radius*radius*delta_theta/speed*span/float(count-1)
			angle_gradient[0]-=theta_slope
			angle_gradient[1]+=theta_slope
			var normal_curvature: float=(cos(alpha)/radius*pow(radius*delta_theta,2)-context.minor*delta_alpha*delta_alpha)/(speed*speed)
			minimum_normal=minf(minimum_normal,normal_curvature)
	gradient[0]+=angle_gradient[0]*entrance.derivative
	gradient[-1]+=angle_gradient[1]*departure.derivative
	return {"valid":true,"length":_sum(length_terms),"gradient":gradient,"points":points,"units":units,"minimum_normal":minimum_normal,"first":first,"last":last}

static func route(frame: Transform3D,outer_radius: float,width: float,rope_radius: float,start: Vector3,finish: Vector3,winding := 0.0,count := 25,maximum_msec := 1000,cancelled := Callable(),initial := PackedFloat64Array()) -> Dictionary:
	var began := Time.get_ticks_usec()
	if cancelled.is_valid() and cancelled.call(): return {"valid":false,"reason":"cancelled"}
	if not PIN.rigid(frame) or not start.is_finite() or not finish.is_finite() or not is_finite(outer_radius) or outer_radius<=0 or not is_finite(width) or width<=0 or not is_finite(rope_radius) or rope_radius<=0 or winding not in [-1.0,0.0,1.0] or count<9 or count>129 or maximum_msec<=0: return {"valid":false,"reason":"invalid groove request"}
	var half := minf(.0055,width*.43)
	var depth := minf(.0048,half*.873)
	var minor := half-rope_radius-.0003
	if minor<=0: return {"valid":false,"reason":"rope does not fit round groove"}
	var major := outer_radius-depth+half
	var radius := major-minor
	var a := frame.affine_inverse()*start
	var b := frame.affine_inverse()*finish
	var seed := CIRCLE.route(Transform3D.IDENTITY,radius,Vector3(0,a.y,a.z),Vector3(0,b.y,b.z),true,true,Vector3.ZERO,INF,0,winding)
	if not seed.valid: return seed
	var first := atan2(seed.entry.z,seed.entry.y)
	var context := {"major":major,"minor":minor,"scale":minor/radius,"alpha_max":acos((half-depth)/half)-.01,"first":first,"last":first+seed.sweep,"direction":signf(seed.sweep),"a":PackedFloat64Array([a.x,a.y,a.z]),"b":PackedFloat64Array([b.x,b.y,b.z])}
	var q := PackedFloat64Array()
	q.resize(count)
	var current := _energy(q,context)
	if not current.get("valid",false): return {"valid":false,"reason":"no finite groove contact interval","seed_sweep":seed.sweep,"first":first,"entrance":_contact_theta(context.a,0,context,context.first),"departure":_contact_theta(context.b,0,context,context.last),"start_local":a,"finish_local":b}
	if not initial.is_empty():
		if initial.size()!=count: return {"valid":false,"reason":"invalid groove initial profile"}
		for value in initial:
			if not is_finite(value): return {"valid":false,"reason":"invalid groove initial profile"}
		var proposed := _energy(initial,context)
		if proposed.valid and proposed.length<=current.length:
			q=initial.duplicate()
			current=proposed
	var inverse := []
	for i in q.size():
		var row := PackedFloat64Array()
		row.resize(q.size())
		row[i]=1/minor
		inverse.append(row)
	var maximum_gradient := INF
	var used := 0
	var polished := 0
	for iteration in 600:
		used=iteration
		if cancelled.is_valid() and cancelled.call(): return {"valid":false,"reason":"cancelled"}
		if Time.get_ticks_usec()-began>maximum_msec*1000: return {"valid":false,"reason":"groove route budget exhausted"}
		maximum_gradient=_maximum(current.gradient)
		if maximum_gradient<minor*1e-7: break
		if maximum_gradient<minor*.0001 and polished<4:
			polished+=1
			var precise := _polish(q,context,current,began+maximum_msec*1000,cancelled)
			if precise.valid:
				q=precise.q
				current=precise.energy
				continue
		var step := PackedFloat64Array()
		for i in q.size(): step.append(-_dot(inverse[i],current.gradient))
		# Safeguarded Newton direction reduces repeated warm-contact work.
		# It uses the same energy line search and domain/normal criteria.
		if iteration%4==0:
			var matrix := _hessian(q,context)
			if not matrix.is_empty():
				var rhs: PackedFloat64Array=current.gradient.duplicate()
				for i in rhs.size(): rhs[i]=-rhs[i]
				var direction := _linear(matrix,rhs)
				if not direction.is_empty() and _dot(direction,current.gradient)<0: step=direction
		var slope := _dot(step,current.gradient)
		if slope>=0: return {"valid":false,"reason":"groove descent direction lost"}
		var largest := 0.0
		for value in step: largest=maxf(largest,absf(value))
		var scale := minf(1,.15/maxf(largest,.000001))
		var trial := {}
		var next := q.duplicate()
		var accepted := false
		for attempt in 30:
			for i in q.size(): next[i]=q[i]+step[i]*scale
			trial=_energy(next,context)
			if trial.valid:
				var decreased: bool=trial.length<=current.length+.0001*scale*slope
				# Sub-ulp energy changes cannot resolve the last correction.
				# Require a halved residual as well as bounded energy uncertainty;
				# the final stationarity threshold itself is unchanged.
				var roundoff: bool=trial.length<=current.length+2e-15*maxf(1,current.length) and _maximum(trial.gradient)<maximum_gradient*.5
				if decreased or roundoff:
					accepted=true
					break
			scale*=.5
		if not accepted:
			# A high-order profile can exhaust its early corrections before
			# the final energy change becomes unresolvable. One direct residual
			# correction still has to halve the gradient and bound energy error.
			var precise := _polish(q,context,current,began+maximum_msec*1000,cancelled)
			if precise.valid:
				q=precise.q
				current=precise.energy
				continue
			return {"valid":false,"reason":"groove line search stalled","gradient":maximum_gradient/minor,"iterations":used,"correction":precise,"profile":q}
		var displacement := PackedFloat64Array()
		var change := PackedFloat64Array()
		for i in q.size():
			displacement.append(next[i]-q[i])
			change.append(trial.gradient[i]-current.gradient[i])
		var curvature := _dot(displacement,change)
		if curvature>1e-20:
			var product := PackedFloat64Array()
			for i in q.size(): product.append(_dot(inverse[i],change))
			var coefficient := (curvature+_dot(change,product))/(curvature*curvature)
			for i in q.size():
				for j in q.size(): inverse[i][j]+=coefficient*displacement[i]*displacement[j]-(product[i]*displacement[j]+displacement[i]*product[j])/curvature
		q=next
		current=trial
	maximum_gradient=_maximum(current.gradient)
	if maximum_gradient>=minor*1e-7 or current.minimum_normal< -1e-7: return {"valid":false,"reason":"groove stationarity or unilateral normal not reached","gradient":maximum_gradient/minor,"normal":current.minimum_normal,"iterations":used}
	var arc := PackedVector3Array()
	for point: PackedFloat64Array in current.points: arc.append(frame*Vector3(point[0],point[1],point[2]))
	var path := PackedVector3Array([start])
	path.append_array(arc)
	path.append(finish)
	var ua: PackedFloat64Array=current.units[0]
	var ub: PackedFloat64Array=current.units[-1]
	var entry_force := -(frame.basis*Vector3(ua[0],ua[1],ua[2]))
	var exit_force := frame.basis*Vector3(ub[0],ub[1],ub[2])
	var entry: Vector3=arc[0]
	var exit_point: Vector3=arc[-1]
	var lead := sqrt(pow(current.points[0][0]-a.x,2)+pow(current.points[0][1]-a.y,2)+pow(current.points[0][2]-a.z,2))
	var tail := sqrt(pow(current.points[-1][0]-b.x,2)+pow(current.points[-1][1]-b.y,2)+pow(current.points[-1][2]-b.z,2))
	return {"valid":true,"geometry_certified":false,"discretization_certified":false,"profile":q.duplicate(),"wrapped":true,"path":path,"arc_path":arc,"entry":entry,"exit":exit_point,"length":current.length,"arc_length":current.length-lead-tail,"sweep":current.last-current.first,"entry_force_per_n":entry_force,"exit_force_per_n":exit_force,"support_force_per_n":entry_force+exit_force,"moment_per_n":(entry-frame.origin).cross(entry_force)+(exit_point-frame.origin).cross(exit_force),"iterations":used,"stationarity":maximum_gradient/minor,"minimum_normal":current.minimum_normal,"elapsed_msec":(Time.get_ticks_usec()-began)/1000.0,"scope":"stationary round-groove surface curve; discretization, full finite hardware and rope-pair clearance require independent certification"}

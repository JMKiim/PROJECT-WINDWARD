extends RefCounted

## A bounded geometric string through the open-base fairlead. The centreline
## passes convex aperture sections of the rope-inflated solid; no elastic
## handle, invisible peg, or renderer-only corner is inserted. A numerical
## path is not by itself a complete rig equilibrium certificate.
const FITTING := preload("res://src/boat/traveller_fairlead.gd")
const FIELD := preload("res://src/boat/fairlead_profile_field.gd")
const RADIUS := .003
const GUARD := .0003

static func _project(x: float,y: float,r: float) -> Vector2:
	var floor_y := RADIUS+GUARD
	y=maxf(y,floor_y)
	if y<=FITTING.ARCH_Y: return Vector2(clampf(x,-r,r),y)
	var dy := y-FITTING.ARCH_Y
	var distance := sqrt(x*x+dy*dy)
	if distance>r: return Vector2(x*r/distance,FITTING.ARCH_Y+dy*r/distance)
	return Vector2(x,y)

static func _length(x: PackedFloat64Array,y: PackedFloat64Array,z: PackedFloat64Array) -> float:
	var result := 0.0
	for i in x.size()-1: result+=sqrt(pow(x[i+1]-x[i],2)+pow(y[i+1]-y[i],2)+pow(z[i+1]-z[i],2))
	return result

static func route(frame: Transform3D,start: Vector3,finish: Vector3,sections := 12,initial := PackedVector3Array(),maximum_sweeps := 500) -> Dictionary:
	var began := Time.get_ticks_usec()
	if not start.is_finite() or not finish.is_finite() or sections<4 or sections>128 or maximum_sweeps<1: return {"valid":false,"reason":"invalid fairlead route"}
	var inverse := frame.affine_inverse()
	var a := inverse*start
	var b := inverse*finish
	var offset := RADIUS+GUARD
	var half := FITTING.HALF_DEPTH
	# Installed material always enters the front and leaves the aft face.
	# Far endpoints may return in front of the fitting after wrapping its lip.
	var z := PackedFloat64Array([a.z])
	var allowed := PackedFloat64Array([0])
	for i in range(sections,-1,-1):
		var angle := PI*.5*i/sections
		z.append(-half-offset*sin(angle))
		allowed.append(FITTING.HALF-offset*cos(angle))
	for i in range(0,sections+1):
		var angle := PI*.5*i/sections
		z.append(half+offset*sin(angle))
		allowed.append(FITTING.HALF-offset*cos(angle))
	z.append(b.z)
	var x := PackedFloat64Array()
	var y := PackedFloat64Array()
	x.resize(z.size())
	y.resize(z.size())
	x[0]=a.x
	y[0]=a.y
	x[-1]=b.x
	y[-1]=b.y
	var warm := initial.size()==z.size()-2
	for i in range(1,z.size()-1):
		var alpha := i/float(z.size()-1)
		var guess: Vector3=initial[i-1] if warm else a.lerp(b,alpha)
		var p := _project(guess.x,guess.y,allowed[i])
		x[i]=p.x
		y[i]=p.y
	var iterations := 0
	var movement := INF
	for sweep in maximum_sweeps:
		movement=0.0
		for order in 2:
			for j in range(1,z.size()-1):
				var i := j if order==0 else z.size()-1-j
				# Each one-vertex problem is convex. An inverse-distance metric
				# gives a safe projected step, including the vertical aperture.
				for refinement in 5:
					var left := sqrt(pow(x[i]-x[i-1],2)+pow(y[i]-y[i-1],2)+pow(z[i]-z[i-1],2))
					var right := sqrt(pow(x[i]-x[i+1],2)+pow(y[i]-y[i+1],2)+pow(z[i]-z[i+1],2))
					left=maxf(left,1e-12)
					right=maxf(right,1e-12)
					var scale := 1.0/left+1.0/right
					var next := _project((x[i-1]/left+x[i+1]/right)/scale,(y[i-1]/left+y[i+1]/right)/scale,allowed[i])
					var step := maxf(absf(next.x-x[i]),absf(next.y-y[i]))
					movement=maxf(movement,step)
					x[i]=next.x
					y[i]=next.y
					if step<1e-10: break
		iterations=sweep+1
		if movement<1e-10: break
	var profile := PackedVector3Array()
	var path := PackedVector3Array([start])
	for i in range(1,z.size()-1):
		var p := Vector3(x[i],y[i],z[i])
		profile.append(p)
		path.append(frame*p)
	path.append(finish)
	return {"valid":true,"stationary":movement<1e-9,"geometry_certified":false,"profile":profile,"path":path,"length":_length(x,y,z),"entry":path[1],"exit":path[-2],"entry_force_per_n":(start-path[1]).normalized(),"exit_force_per_n":(finish-path[-2]).normalized(),"movement_m":movement,"sweeps":iterations,"elapsed_ms":(Time.get_ticks_usec()-began)/1000.0}

static func _refine(source: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array([source[0]])
	for i in source.size()-1:
		var a := source[i]
		var b := source[i+1]
		var near := Geometry3D.get_closest_point_to_segment(Vector3(0,.010,0),a,b).distance_to(Vector3(0,.010,0))<.028
		var count := maxi(1,ceili(a.distance_to(b)/.0005)) if near else 1
		for j in range(1,count):
			var p := a.lerp(b,j/float(count))
			if p.distance_to(Vector3(0,.010,0))<.030: result.append(p)
		result.append(b)
	return result

static func settled(frame: Transform3D,start: Vector3,finish: Vector3,warm := PackedVector3Array(),maximum_sweeps := 160) -> Dictionary:
	var began := Time.get_ticks_usec()
	var inverse := frame.affine_inverse()
	var a := inverse*start
	var b := inverse*finish
	var path := warm.duplicate()
	if path.is_empty():
		var seed := route(Transform3D.IDENTITY,a,b,8,PackedVector3Array(),80)
		if not seed.valid: return seed
		path=_refine(seed.path)
	path[0]=a
	path[-1]=b
	var movement := INF
	var sweeps := 0
	for iteration in maximum_sweeps:
		movement=0
		if iteration>=12 or not warm.is_empty():
			var polished := _newton(path)
			if polished.valid:
				path=polished.path
				movement=polished.movement
				sweeps=iteration+1
				if movement<1e-9: break
				continue
		for order in 2:
			for j in range(1,path.size()-1):
				var i := j if order==0 else path.size()-1-j
				var left := maxf(path[i].distance_to(path[i-1]),1e-9)
				var right := maxf(path[i].distance_to(path[i+1]),1e-9)
				var target := (path[i-1]/left+path[i+1]/right)/(1/left+1/right)
				var proposed := path[i]+(target-path[i]).limit_length(.0005)
				var next := FIELD.project(proposed,RADIUS+GUARD)
				next.y=maxf(next.y,RADIUS+GUARD)
				movement=maxf(movement,next.distance_to(path[i]))
				path[i]=next
		if iteration%16==15: path=_refine(path)
		sweeps=iteration+1
		if movement<1e-8: break
	var gap := INF
	var length := 0.0
	for i in path.size()-1:
		length+=path[i].distance_to(path[i+1])
		var count := maxi(2,ceili(path[i].distance_to(path[i+1])/.0002))
		for j in count+1:
			var p := path[i].lerp(path[i+1],j/float(count))
			if p.length()<.04: gap=minf(gap,FIELD.query(p).distance-RADIUS)
	var residual := _residual(path)
	return {"valid":gap>.0002,"geometry_certified":false,"stationary":residual<.00001,"residual_per_n":residual,"profile":path,"path":frame*path,"length":_energy(path),"entry":frame*path[1],"exit":frame*path[-2],"minimum_gap":gap,"sweeps":sweeps,"movement_m":movement,"elapsed_ms":(Time.get_ticks_usec()-began)/1000.0}

static func contact_patch(result: Dictionary,frame: Transform3D) -> PackedVector3Array:
	if not result.get("valid",false): return PackedVector3Array()
	var local: PackedVector3Array=result.profile
	var first := -1
	var last := -1
	for i in range(1,local.size()-1):
		if FIELD.query(local[i]).distance<RADIUS+GUARD+.000001:
			if first<0: first=i
			last=i
	return frame*local.slice(first,last+1) if first>=0 and last>first else PackedVector3Array()

static func _residual(path: PackedVector3Array) -> float:
	var residual := 0.0
	for i in range(1,path.size()-1):
		var force := (path[i]-path[i-1]).normalized()+(path[i]-path[i+1]).normalized()
		var contact := FIELD.query(path[i])
		var multiplier := force.dot(contact.normal)
		if contact.distance<RADIUS+GUARD+1e-7 and multiplier>0: force-=contact.normal*multiplier
		residual=maxf(residual,force.length())
	return residual

static func _energy(path: PackedVector3Array) -> float:
	var length := 0.0
	for i in path.size()-1:
		var a := path[i]
		var b := path[i+1]
		length+=sqrt(pow(float(a.x)-float(b.x),2)+pow(float(a.y)-float(b.y),2)+pow(float(a.z)-float(b.z),2))
	return length

static func _inverse(a: PackedFloat64Array) -> PackedFloat64Array:
	var determinant := a[0]*a[3]-a[1]*a[2]
	if absf(determinant)<1e-14: return PackedFloat64Array()
	return PackedFloat64Array([a[3]/determinant,-a[1]/determinant,-a[2]/determinant,a[0]/determinant])

static func _product(a: PackedFloat64Array,b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[0]*b[0]+a[1]*b[2],a[0]*b[1]+a[1]*b[3],a[2]*b[0]+a[3]*b[2],a[2]*b[1]+a[3]*b[3]])

static func _vector(a: PackedFloat64Array,b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[0]*b[0]+a[1]*b[1],a[2]*b[0]+a[3]*b[1]])

static func _newton(path: PackedVector3Array) -> Dictionary:
	var count := path.size()-2
	var basis := []
	var diagonals := []
	var upper := []
	var rhs := []
	for j in count:
		var i := j+1
		var left := path[i]-path[i-1]
		var right := path[i+1]-path[i]
		var la := maxf(left.length(),1e-9)
		var lb := maxf(right.length(),1e-9)
		var gradient := left/la-right/lb
		var tangent := (left/la+right/lb).normalized()
		var contact := FIELD.query(path[i])
		var multiplier := gradient.dot(contact.normal)
		var active: bool=contact.distance<RADIUS+GUARD+1e-7 and multiplier>0
		var first := tangent.cross(contact.normal if active else (Vector3.UP if absf(tangent.y)<.8 else Vector3.RIGHT)).normalized()
		if first.length_squared()<.5: return {"valid":false}
		var second := Vector3.ZERO if active else tangent.cross(first).normalized()
		basis.append([first,second])
		rhs.append(PackedFloat64Array([-gradient.dot(first),-gradient.dot(second)]))
		var diagonal := PackedFloat64Array([.0001,0,0,1.0 if active else .0001])
		for row in 2:
			for column in 2:
				var a: Vector3=basis[j][row]
				var b: Vector3=basis[j][column]
				diagonal[row*2+column]+=(a.dot(b)-a.dot(left/la)*b.dot(left/la))/la+(a.dot(b)-a.dot(right/lb)*b.dot(right/lb))/lb
		if active:
			var before := FIELD.query(path[i]-first*.000002)
			var after := FIELD.query(path[i]+first*.000002)
			diagonal[0]-=multiplier*first.dot(after.normal-before.normal)/.000004
		diagonals.append(diagonal)
	for j in count-1:
		var delta := path[j+2]-path[j+1]
		var length := maxf(delta.length(),1e-9)
		var direction := delta/length
		var off := PackedFloat64Array()
		for row in 2:
			for column in 2:
				var a: Vector3=basis[j][row]
				var b: Vector3=basis[j+1][column]
				off.append(-(a.dot(b)-a.dot(direction)*b.dot(direction))/length)
		upper.append(off)
	var factored := []
	var values := []
	for j in count:
		var diagonal: PackedFloat64Array=diagonals[j].duplicate()
		var value: PackedFloat64Array=rhs[j].duplicate()
		if j>0:
			var previous: PackedFloat64Array=upper[j-1]
			var lower := PackedFloat64Array([previous[0],previous[2],previous[1],previous[3]])
			var correction := _product(lower,factored[-1])
			var change := _vector(lower,values[-1])
			for k in 4: diagonal[k]-=correction[k]
			for k in 2: value[k]-=change[k]
		var inverse := _inverse(diagonal)
		if inverse.is_empty(): return {"valid":false}
		factored.append(_product(inverse,upper[j]) if j<count-1 else PackedFloat64Array([0,0,0,0]))
		values.append(_vector(inverse,value))
	var step := PackedVector3Array()
	step.resize(path.size())
	var solution := PackedFloat64Array([0,0])
	var maximum := 0.0
	var descent := 0.0
	for reverse in count:
		var j := count-1-reverse
		var change := _vector(factored[j],solution)
		solution=values[j].duplicate()
		for k in 2: solution[k]-=change[k]
		step[j+1]=basis[j][0]*solution[0]+basis[j][1]*solution[1]
		maximum=maxf(maximum,step[j+1].length())
		descent-=rhs[j][0]*solution[0]+rhs[j][1]*solution[1]
	if descent>=0: return {"valid":false}
	var scale := minf(1,.001/maxf(maximum,1e-12))
	var old := _energy(path)
	for backtrack in 12:
		var next := path.duplicate()
		for i in range(1,path.size()-1): next[i]=FIELD.project(path[i]+step[i]*scale,RADIUS+GUARD)
		if _energy(next)<old+1e-13:
			return {"valid":true,"path":next,"movement":maximum*scale}
		scale*=.5
	return {"valid":false}

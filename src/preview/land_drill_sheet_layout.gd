extends RefCounted
static func generate(hull: MeshInstance3D) -> PackedVector3Array:
	var random := RandomNumberGenerator.new()
	random.seed=20261014
	var folds := [[-.018,.365,.095,.026,1.0,0]]
	for index in 27:
		folds.append([random.randf_range(-.035,.08),random.randf_range(.35,.365),random.randf_range(.085,.18),random.randf_range(.017,.036),1.0 if random.randf()>.5 else -1.0,(index+1)%6])
	var result := PackedVector3Array()
	for index in folds.size():
		var fold: Array=folds[index]
		var start := Vector3(float(fold[0])+float(fold[2]),0,float(fold[1]))
		start.y=hull.cockpit_floor_y_at(start.x,start.z)+.006+float(fold[5])*.009
		if not result.is_empty():
			var from := result[-1]
			var before: Array=folds[index-1]
			var control_a := from+Vector3(0,0,float(before[4])*.016)
			var control_b := start-Vector3(0,0,float(fold[4])*.016)
			for sample in range(1,9):
				var u := sample/8.0
				var v := 1-u
				var point := from*v*v*v+control_a*3*v*v*u+control_b*3*v*u*u+start*u*u*u
				point.y=maxf(point.y,hull.cockpit_floor_y_at(point.x,point.z)+.006)
				result.append(point)
		for sample in 65:
			var angle: float=sample/64.0*TAU*float(fold[4])
			var variation := 1+.065*sin(3*angle+index*.71)
			var x: float=float(fold[0])+float(fold[2])*cos(angle)*variation
			var z: float=float(fold[1])+float(fold[3])*sin(angle)
			# Both ends of each fold meet their connector exactly.
			if sample==0 or sample==64: x=start.x; z=start.z
			var point := Vector3(x,hull.cockpit_floor_y_at(x,z)+.006+float(fold[5])*.009,z)
			result.append(point)
	return result

extends RefCounted

## Projection onto a homogeneous active-contact cone in several generalized
## rotation coordinates. No penetration repair, inertia, friction or authored
## pose search. Positive multipliers are physical normal reactions after
## undoing each input gradient's normalization.
const MAX_ITERATIONS := 256

static func solve(desired: PackedFloat64Array,contacts: Array,required := PackedFloat64Array()) -> Dictionary:
	if desired.is_empty() or desired.size()>12: return {"valid":false,"reason":"invalid articulated dimension"}
	if not required.is_empty() and required.size()!=contacts.size(): return {"valid":false,"reason":"invalid contact bound count"}
	for value in desired:
		if not is_finite(value): return {"valid":false,"reason":"nonfinite generalized force"}
	var normals := []
	var scales := PackedFloat64Array()
	var sources := []
	var bounds := PackedFloat64Array()
	for row_index in contacts.size():
		var row: Variant=contacts[row_index]
		if not row is Dictionary or not row.has("gradient") or not row.gradient is PackedFloat64Array or row.gradient.size()!=desired.size():
			return {"valid":false,"reason":"invalid articulated contact gradient"}
		var gradient: PackedFloat64Array=row.gradient
		for value in gradient:
			if not is_finite(value): return {"valid":false,"reason":"nonfinite contact gradient"}
		var length := sqrt(dot(gradient,gradient))
		var bound: float=0 if required.is_empty() else required[row_index]
		if not is_finite(bound): return {"valid":false,"reason":"nonfinite contact bound"}
		if length<1e-14:
			if bound>1e-12: return {"valid":false,"reason":"immobile penetrating constraint"}
			continue
		bound/=length
		var normalized := gradient.duplicate()
		for index in normalized.size(): normalized[index]/=length
		var duplicate := false
		for previous in normals.size():
			if normals[previous]==normalized:
				if bound>bounds[previous]:
					bounds[previous]=bound
					scales[previous]=length
					sources[previous]=row
				duplicate=true
				break
		if duplicate: continue
		normals.append(normalized)
		scales.append(length)
		sources.append(row)
		bounds.append(bound)
	var multipliers := PackedFloat64Array()
	multipliers.resize(normals.size())
	var passive := []
	var value := desired.duplicate()
	var tolerance := maxf(1e-11,sqrt(dot(desired,desired))*1e-9)
	for iteration in MAX_ITERATIONS:
		var entering := -1
		var worst := -tolerance
		for index in normals.size():
			if index in passive: continue
			var violation := dot(normals[index],value)-bounds[index]
			if violation<worst:
				worst=violation
				entering=index
		if entering<0:
			return _certify(desired,value,normals,bounds,scales,sources,multipliers,tolerance,iteration)
		passive.append(entering)
		var adjusted := false
		for inner in MAX_ITERATIONS:
			var least := _least_squares(normals,passive,desired,bounds)
			if not least.valid:
				# A newly active normal may lie in the span of the old set.
				# Transfer multipliers along that exact null direction until a
				# previous constraint leaves, preserving the primal value. The
				# final KKT certification remains mandatory for redundant faces.
				if not least.has("dependence") or least.column!=passive.size()-1: return {"valid":false,"reason":"dependent active contact set","iterations":iteration,"value":value}
				var amount := INF
				for index in least.column:
					if least.dependence[index]>1e-14: amount=minf(amount,multipliers[passive[index]]/least.dependence[index])
				if not is_finite(amount): return {"valid":false,"reason":"incompatible dependent contact bounds","value":value}
				for index in least.column: multipliers[passive[index]]-=amount*least.dependence[index]
				multipliers[passive[-1]]+=amount
				var reduced := []
				for index: int in passive:
					if multipliers[index]>1e-14: reduced.append(index)
					else: multipliers[index]=0
				if reduced==passive: return {"valid":false,"reason":"dependent contact made no dual progress","value":value}
				passive=reduced
				continue
			var proposal := PackedFloat64Array()
			proposal.resize(normals.size())
			for index in passive.size(): proposal[passive[index]]=least.coefficients[index]
			var positive := true
			for index: int in passive:
				if proposal[index]<=0: positive=false
			if positive:
				multipliers=proposal
				adjusted=true
				break
			var alpha := 1.0
			for index: int in passive:
				if proposal[index]<=0:
					var denominator := multipliers[index]-proposal[index]
					alpha=minf(alpha,multipliers[index]/denominator if denominator>0 else 0)
			for index in multipliers.size(): multipliers[index]+=alpha*(proposal[index]-multipliers[index])
			var kept := []
			for index: int in passive:
				if multipliers[index]>1e-14: kept.append(index)
				else: multipliers[index]=0
			if kept==passive: return {"valid":false,"reason":"contact active set made no progress"}
			passive=kept
		if not adjusted: return {"valid":false,"reason":"contact multiplier iteration limit"}
		value=desired.duplicate()
		for index: int in passive:
			for coordinate in value.size(): value[coordinate]+=multipliers[index]*normals[index][coordinate]
	return {"valid":false,"reason":"articulated cone iteration limit","value":value}

static func dot(first: PackedFloat64Array,last: PackedFloat64Array) -> float:
	var value := 0.0
	for index in first.size(): value+=first[index]*last[index]
	return value

static func _least_squares(normals: Array,passive: Array,desired: PackedFloat64Array,bounds: PackedFloat64Array) -> Dictionary:
	# Reorthogonalized QR avoids squaring the condition number in a Gram
	# system when two actual contact normals are almost parallel/opposed.
	var columns := []
	var triangular := []
	for index in passive.size():
		var row := PackedFloat64Array()
		row.resize(passive.size())
		triangular.append(row)
	for column in passive.size():
		var vector: PackedFloat64Array=normals[passive[column]].duplicate()
		for reorthogonalize in 2:
			for previous in column:
				var coefficient := dot(columns[previous],vector)
				triangular[previous][column]+=coefficient
				for index in vector.size(): vector[index]-=coefficient*columns[previous][index]
		var length := sqrt(dot(vector,vector))
		if length<1e-12:
			var dependence := PackedFloat64Array()
			dependence.resize(column)
			for reverse in column:
				var row := column-1-reverse
				var value: float=triangular[row][column]
				for next in range(row+1,column): value-=triangular[row][next]*dependence[next]
				dependence[row]=value/triangular[row][row]
			return {"valid":false,"column":column,"dependence":dependence}
		triangular[column][column]=length
		for index in vector.size(): vector[index]/=length
		columns.append(vector)
	var solution := PackedFloat64Array()
	solution.resize(passive.size())
	# For nonzero separation bounds, R^T y = b - A^T desired and R lambda=y.
	# The same QR factor avoids explicitly forming the normal-equation matrix.
	var target := PackedFloat64Array()
	target.resize(passive.size())
	for row in passive.size():
		var value := bounds[passive[row]]-dot(normals[passive[row]],desired)
		for column in row: value-=triangular[column][row]*target[column]
		target[row]=value/triangular[row][row]
	for reverse in passive.size():
		var row := passive.size()-1-reverse
		var value := target[row]
		for column in range(row+1,passive.size()): value-=triangular[row][column]*solution[column]
		solution[row]=value/triangular[row][row]
	return {"valid":true,"coefficients":solution}

static func _certify(desired: PackedFloat64Array,value: PackedFloat64Array,normals: Array,bounds: PackedFloat64Array,scales: PackedFloat64Array,sources: Array,multipliers: PackedFloat64Array,tolerance: float,iterations: int) -> Dictionary:
	for coordinate in value:
		if not is_finite(coordinate): return {"valid":false,"reason":"nonfinite cone projection"}
	var reactions := []
	var reconstruction := desired.duplicate()
	var largest_violation := 0.0
	var largest_complementarity := 0.0
	for index in normals.size():
		if not is_finite(multipliers[index]) or multipliers[index]<0: return {"valid":false,"reason":"invalid cone reaction"}
		for coordinate in value.size(): reconstruction[coordinate]+=normals[index][coordinate]*multipliers[index]
		var slack := dot(normals[index],value)-bounds[index]
		largest_violation=maxf(largest_violation,maxf(0,-slack))
		largest_complementarity=maxf(largest_complementarity,absf(slack*multipliers[index]))
		if multipliers[index]>0:
			var coefficient: float=multipliers[index]/scales[index]
			var reaction: Dictionary=sources[index].duplicate()
			reaction["normal_force_n"]=coefficient
			reactions.append(reaction)
	var complementarity_tolerance := tolerance*maxf(1,sqrt(dot(desired,desired)))
	var reconstruction_error := 0.0
	for coordinate in value.size(): reconstruction_error=maxf(reconstruction_error,absf(reconstruction[coordinate]-value[coordinate]))
	var valid := largest_violation<=tolerance*4 and largest_complementarity<=complementarity_tolerance*4 and reconstruction_error<=tolerance*4
	return {"valid":valid,"reason":"active cone KKT" if valid else "contact cone failed independent KKT bounds","value":value,"reactions":reactions,"maximum_violation":largest_violation,"maximum_complementarity":largest_complementarity,"iterations":iterations}

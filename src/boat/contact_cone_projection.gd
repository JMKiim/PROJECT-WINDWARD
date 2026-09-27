extends RefCounted

## Exact active-set candidates for the three rotational coordinates.
## A Euclidean projection in R3 needs no more than three independent active
## halfspaces. Enumerate their KKT solutions rather than alternating almost
## parallel contacts a fixed number of times.
static func dot(a: Vector3,b: Vector3) -> float:
	return float(a.x)*b.x+float(a.y)*b.y+float(a.z)*b.z

static func solve(desired: Vector3,contacts: Array,guard: float) -> Dictionary:
	var normals := []
	var bounds := []
	var witnesses := []
	for contact: Dictionary in contacts:
		var gradient: Vector3=contact.gradient
		var length := gradient.length()
		if not gradient.is_finite() or length<.000001: continue
		var normal := gradient/length
		var bound: float=(guard-contact.gap)/length
		var duplicate := false
		for index in normals.size():
			if normal==normals[index]:
				if bound>bounds[index]:
					bounds[index]=bound
					witnesses[index]=contact
				duplicate=true
				break
		if not duplicate:
			normals.append(normal)
			bounds.append(bound)
			witnesses.append(contact)
	if _feasible(desired,normals,bounds): return {"value":desired,"reactions":[],"valid":true}
	var best := {"distance":INF,"value":Vector3(NAN,NAN,NAN),"indices":[],"multipliers":[]}
	for first in normals.size():
		_consider(desired,normals,bounds,[first],best)
		if best.value.is_finite(): break
	# Any feasible candidate with nonnegative KKT multipliers is already the
	# unique projection. There is no need to enumerate the remaining subsets.
	if not best.value.is_finite():
		for first in normals.size():
			for second in range(first+1,normals.size()):
				_consider(desired,normals,bounds,[first,second],best)
				if best.value.is_finite(): break
			if best.value.is_finite(): break
	if not best.value.is_finite():
		for first in normals.size():
			for second in range(first+1,normals.size()):
				for third in range(second+1,normals.size()):
					_consider(desired,normals,bounds,[first,second,third],best)
					if best.value.is_finite(): break
				if best.value.is_finite(): break
			if best.value.is_finite(): break
	if not best.value.is_finite(): return {"value":best.value,"reactions":[],"valid":false}
	var reactions := []
	for index in best.indices.size():
		var contact: Dictionary=witnesses[best.indices[index]]
		var coefficient: float=best.multipliers[index]/contact.gradient.length()
		if coefficient<=1e-12: continue
		var row := {"generalized_n":coefficient,"torque_nm":contact.gradient*coefficient,"gap":contact.get("actual_gap",contact.gap),"gradient":contact.gradient}
		if contact.has_all(["normal","point"]):
			row["force_n"]=contact.normal*coefficient
			row["point"]=contact.point
		reactions.append(row)
	return {"value":best.value,"reactions":reactions,"valid":true}

static func _feasible(value: Vector3,normals: Array,bounds: Array) -> bool:
	for index in normals.size():
		if dot(normals[index],value)<bounds[index]-1e-9: return false
	return true

static func _consider(desired: Vector3,normals: Array,bounds: Array,indices: Array,best: Dictionary) -> void:
	var count := indices.size()
	var rows := []
	for first: int in indices:
		var row := PackedFloat64Array()
		for second: int in indices: row.append(dot(normals[first],normals[second]))
		row.append(bounds[first]-dot(normals[first],desired))
		rows.append(row)
	# Pivoted elimination in scalar precision; Matrix/Basis storage would
	# round the small difference between nearly parallel normal equations.
	for column in count:
		var pivot := column
		for row in range(column+1,count):
			if absf(rows[row][column])>absf(rows[pivot][column]): pivot=row
		if absf(rows[pivot][column])<1e-14: return
		var swap: PackedFloat64Array=rows[column]
		rows[column]=rows[pivot]
		rows[pivot]=swap
		var divisor: float=rows[column][column]
		for entry in range(column,count+1): rows[column][entry]/=divisor
		for row in count:
			if row==column: continue
			var multiplier: float=rows[row][column]
			for entry in range(column,count+1): rows[row][entry]-=rows[column][entry]*multiplier
	var multipliers := []
	for row in count:
		if rows[row][count]<-1e-10: return
		multipliers.append(maxf(0,rows[row][count]))
	var value := Vector3.ZERO
	for coordinate in 3:
		var scalar: float=desired[coordinate]
		for index in count: scalar+=normals[indices[index]][coordinate]*multipliers[index]
		value[coordinate]=scalar
	if not _feasible(value,normals,bounds): return
	var distance := value.distance_squared_to(desired)
	if distance>=best.distance: return
	best.merge({"value":value,"distance":distance,"indices":indices,"multipliers":multipliers},true)

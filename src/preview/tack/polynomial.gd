extends RefCounted
## Degree <=4 real-root isolation by derivative critical points. Solves
## contact equations; it does not sample body poses or angular directions.
static func value(coefficients: PackedFloat64Array,x: float) -> float:
	var result := 0.0
	for index in range(coefficients.size()-1,-1,-1): result=result*x+coefficients[index]
	return result
static func roots(input: PackedFloat64Array,low: float,high: float) -> PackedFloat64Array:
	var coefficients := input.duplicate()
	var magnitude := 0.0
	for coefficient in coefficients: magnitude=maxf(magnitude,absf(coefficient))
	if magnitude<=1e-30: return PackedFloat64Array()
	for index in coefficients.size(): coefficients[index]/=magnitude
	while coefficients.size()>1 and absf(coefficients[-1])<1e-13: coefficients.resize(coefficients.size()-1)
	if coefficients.size()==1: return PackedFloat64Array()
	if coefficients.size()==2:
		var root := -coefficients[0]/coefficients[1]
		return PackedFloat64Array([root]) if root>=low and root<=high else PackedFloat64Array()
	var derivative := PackedFloat64Array()
	for index in range(1,coefficients.size()): derivative.append(index*coefficients[index])
	var divisions := PackedFloat64Array([low])
	divisions.append_array(roots(derivative,low,high))
	divisions.append(high)
	var result := PackedFloat64Array()
	for boundary in divisions:
		if absf(value(coefficients,boundary))<=1e-11: _append(result,boundary)
	for index in divisions.size()-1:
		var a := divisions[index]
		var b := divisions[index+1]
		var fa := value(coefficients,a)
		var fb := value(coefficients,b)
		if fa*fb>=0: continue
		for iteration in 40:
			var middle := (a+b)*.5
			var fm := value(coefficients,middle)
			if fa*fm<=0:
				b=middle
			else:
				a=middle
				fa=fm
		_append(result,(a+b)*.5)
	result.sort()
	return result
static func _append(values: PackedFloat64Array,value_: float) -> void:
	for existing in values:
		if absf(existing-value_)<.00000001: return
	values.append(value_)

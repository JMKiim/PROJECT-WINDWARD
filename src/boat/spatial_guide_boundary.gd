extends RefCounted

## Carry a fixed guide arc with its rigid body. The surrounding free spans
## are solved separately; contact-angle sliding is not inferred here.
static func move(path: PackedVector3Array,wraps: Dictionary,name: String,rest: Transform3D,pose: Transform3D) -> Dictionary:
	if not wraps.has(name) or not wraps[name].has_all(["begin","end","center","axle"]) or not rest.is_finite() or not pose.is_finite():
		return {"valid":false,"reason":"invalid moving guide boundary"}
	var guide: Dictionary=wraps[name]
	for frame in [rest,pose]:
		if absf(frame.basis.determinant()-1)>.00001 or not (frame.basis.transposed()*frame.basis).is_equal_approx(Basis.IDENTITY):
			return {"valid":false,"reason":"moving guide requires rigid frames"}
	var first: int=guide.begin
	var last: int=guide.end
	if first<1 or last<first or last>=path.size()-1: return {"valid":false,"reason":"moving guide range outside material"}
	var delta := pose*rest.affine_inverse()
	var moved := path.duplicate()
	for index in range(first,last+1): moved[index]=delta*path[index]
	var result := wraps.duplicate(true)
	result[name].center=delta*guide.center
	result[name].axle=(delta.basis*guide.axle).normalized()
	for key in result:
		var item: Dictionary=result[key]
		if item.has_all(["begin","end"]):
			if item.begin>0: item.incoming=moved[item.begin-1]
			if item.end<moved.size()-1: item.outgoing=moved[item.end+1]
	return {"valid":true,"path":moved,"wraps":result,"transform":delta}

extends RefCounted

## Uniform side-planform centroid,not a measured center of pressure.
## Cache silhouette panels once;clip only these small convex quads at runtime.
const STRIPS := 32
var panels: Array[PackedVector3Array] = []
func setup(foil: MeshInstance3D) -> void:
	panels.clear()
	for index in STRIPS:
		var a := float(index)/STRIPS
		var b := float(index+1)/STRIPS
		var top: Vector2=foil._side_outline(a)
		var bottom: Vector2=foil._side_outline(b)
		var y0: float=foil.span*(.5-a)
		var y1: float=foil.span*(.5-b)
		panels.append(PackedVector3Array([Vector3(0,y0,top.x),Vector3(0,y0,top.y),Vector3(0,y1,bottom.y),Vector3(0,y1,bottom.x)]))

func sample(frame: Transform3D,body_basis: Basis,water_point: Vector3,normal_world := Vector3.UP) -> Dictionary:
	var area := 0.0
	var weighted := Vector3.ZERO
	for panel in panels:
		var polygon := PackedVector3Array()
		var previous: Vector3=frame*panel[-1]
		var before: float=normal_world.dot(body_basis*previous-water_point)
		for local in panel:
			var current: Vector3=frame*local
			var after: float=normal_world.dot(body_basis*current-water_point)
			if (before<0)!=(after<0): polygon.append(previous.lerp(current,before/(before-after)))
			if after<=0: polygon.append(current)
			previous=current; before=after
		for index in range(1,polygon.size()-1):
			var a := polygon[0]; var b := polygon[index]; var c := polygon[index+1]
			var triangle := (b-a).cross(c-a).length()*.5
			area+=triangle; weighted+=(a+b+c)*(triangle/3)
	return {"area_m2":area,"center":weighted/area if area>.000000001 else Vector3.ZERO}

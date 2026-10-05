extends "res://src/boat/animation/first_person_neck_cap.gd"
## Same deformed mask boundary and triangulation; appearance only. A UV
## average may fall on the mouth's texture island. Interpolate sampled skin
## COLOURS instead, without opening the neck or changing an authored pose.
var skin_image: Image
func setup(body: MeshInstance3D,head_bind: int,threshold := .05) -> bool:
	if not super.setup(body,head_bind,threshold): return false
	var source: StandardMaterial3D=body.mesh.surface_get_material(0)
	if source.albedo_texture==null: return false
	skin_image=source.albedo_texture.get_image()
	if skin_image==null or skin_image.is_empty(): return false
	if skin_image.is_compressed() and skin_image.decompress()!=OK: return false
	var material: StandardMaterial3D=material_override
	material.albedo_texture=null
	material.normal_enabled=false
	material.roughness_texture=null
	material.roughness=.85
	material.vertex_color_use_as_albedo=true
	material.vertex_color_is_srgb=false
	update_pose()
	return true
func _skin_colour(uv: Vector2) -> Color:
	var x := posmod(int(floor(uv.x*skin_image.get_width())),skin_image.get_width())
	var y := posmod(int(floor(uv.y*skin_image.get_height())),skin_image.get_height())
	return skin_image.get_pixel(x,y).srgb_to_linear()
func update_pose() -> void:
	super.update_pose()
	if skin_image==null: return
	var colours := PackedColorArray()
	for group: Array in groups:
		var center := Color(0,0,0,1)
		for segment: Array in group:
			for corner: Dictionary in segment:
				var colour := _skin_colour(corner.uv)
				center.r+=colour.r/(group.size()*2.0)
				center.g+=colour.g/(group.size()*2.0)
				center.b+=colour.b/(group.size()*2.0)
		for segment: Array in group:
			colours.append(center)
			colours.append(_skin_colour(segment[0].uv))
			colours.append(_skin_colour(segment[1].uv))
	var arrays := mesh.surface_get_arrays(0)
	arrays[Mesh.ARRAY_COLOR]=colours
	# Re-encode each original triangle normal once, not an already packed
	# octahedral normal a second time. The exact same deformed vertices and
	# original cross-product order recover the original surface normals.
	var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals := PackedVector3Array()
	for index in range(0,points.size(),3):
		var normal := (points[index+1]-points[index]).cross(points[index+2]-points[index]).normalized()
		for corner in 3: normals.append(normal)
	arrays[Mesh.ARRAY_NORMAL]=normals
	var surface := mesh as ArrayMesh
	surface.clear_surfaces()
	surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)

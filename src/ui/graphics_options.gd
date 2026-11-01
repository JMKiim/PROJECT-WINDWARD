extends RefCounted
## Presentation-only settings. Never writes sailing state,clocks or contacts.
const DEFAULTS := {"render_scale":100,"msaa":2,"shadows":true,"shadow_distance":100,"water_detail":256,"texture_filter":0,"ambient_percent":100,"fps_limit":0,"vsync":true}
const ALLOWED := {"render_scale":[75,85,100],"msaa":[0,1,2,3],"shadows":[false,true],"shadow_distance":[30,60,100,160],"water_detail":[128,192,256,384],"texture_filter":[0,1],"ambient_percent":[60,100,140],"fps_limit":[0,30,60,120],"vsync":[false,true]}
const PRESETS := {
	"low":{"render_scale":75,"msaa":0,"shadows":false,"shadow_distance":30,"water_detail":128,"texture_filter":0},
	"medium":{"render_scale":100,"msaa":1,"shadows":true,"shadow_distance":60,"water_detail":192,"texture_filter":0},
	"high":{"render_scale":100,"msaa":2,"shadows":true,"shadow_distance":100,"water_detail":256,"texture_filter":0},
	"very_high":{"render_scale":100,"msaa":3,"shadows":true,"shadow_distance":160,"water_detail":384,"texture_filter":1}}
var values := DEFAULTS.duplicate()
var storage_path := "user://graphics.cfg"
var load_message := ""
var materials := []
var material_copies := {}
var scanned_surfaces := {}
var bound_scene: Node3D
var ocean_plane: PlaneMesh
var original_plane: PlaneMesh
var ocean_node: MeshInstance3D
var environment: Environment
var base_ambient := 0.56
func sanitize(candidate: Dictionary) -> Dictionary:
	var clean := DEFAULTS.duplicate()
	for key in DEFAULTS:
		if candidate.has(key) and typeof(candidate[key])==typeof(DEFAULTS[key]) and candidate[key] in ALLOWED[key]: clean[key]=candidate[key]
	return clean
func load_config() -> void:
	var config := ConfigFile.new()
	var result := config.load(storage_path)
	if result==ERR_FILE_NOT_FOUND: return
	if result!=OK or config.get_value("meta","version",0)!=1:
		load_message="설정 파일을 읽지 못해 기본값을 사용해요."; return
	var candidate := {}
	for key in DEFAULTS: candidate[key]=config.get_value("graphics",key,DEFAULTS[key])
	values=sanitize(candidate)
func save_config() -> Error:
	var config := ConfigFile.new()
	config.set_value("meta","version",1)
	for key in DEFAULTS: config.set_value("graphics",key,values[key])
	return config.save(storage_path)
func preset_name() -> String:
	for preset in PRESETS:
		var matches := true
		for key in PRESETS[preset]:
			if values[key]!=PRESETS[preset][key]: matches=false; break
		if matches: return preset
	return "custom"
func select_preset(preset: String) -> void:
	if not PRESETS.has(preset): return
	for key in PRESETS[preset]: values[key]=PRESETS[preset][key]
func bind(scene: Node3D) -> void:
	bound_scene=scene
	ocean_node=scene.get_node("Ocean")
	original_plane=ocean_node.mesh as PlaneMesh
	ocean_plane=original_plane
	var world: WorldEnvironment=scene.get_node("WorldEnvironment")
	environment=world.environment.duplicate() as Environment
	world.environment=environment; base_ambient=environment.ambient_light_energy
	if values.texture_filter==1: refresh_materials()
func refresh_materials() -> void:
	# Clone only textured materials,once per resource and scene. Do not edit
	# imported resources or the materials of the hidden legacy boat.
	for node in bound_scene.find_children("*","MeshInstance3D",true,false):
		var mesh_instance: MeshInstance3D=node
		if not mesh_instance.is_visible_in_tree() or mesh_instance.mesh==null: continue
		var overridden := mesh_instance.material_override!=null
		for surface in (1 if overridden else mesh_instance.mesh.get_surface_count()):
			var key := str(mesh_instance.get_instance_id())+(":override" if overridden else ":"+str(surface))
			var material: Material=mesh_instance.get_active_material(surface)
			if scanned_surfaces.get(key)==material: continue
			if not material is BaseMaterial3D: continue
			var base: BaseMaterial3D=material
			if base.albedo_texture==null and base.normal_texture==null: continue
			var identity := base.get_instance_id()
			if not material_copies.has(identity):
				var copy: BaseMaterial3D=base.duplicate()
				material_copies[identity]=copy
				materials.append({"material":copy,"original_filter":base.texture_filter})
			if overridden: mesh_instance.material_override=material_copies[identity]
			else: mesh_instance.set_surface_override_material(surface,material_copies[identity])
			scanned_surfaces[key]=material_copies[identity]
func apply(viewport: Viewport) -> void:
	values=sanitize(values)
	viewport.scaling_3d_scale=values.render_scale/100.0
	viewport.msaa_3d=values.msaa
	viewport.anisotropic_filtering_level=Viewport.ANISOTROPY_8X
	var sun: DirectionalLight3D=bound_scene.get_node("Sun")
	sun.shadow_enabled=values.shadows
	sun.directional_shadow_max_distance=float(values.shadow_distance)
	if ocean_plane.subdivide_width!=values.water_detail:
		if values.water_detail==original_plane.subdivide_width:
			ocean_plane=original_plane
		else:
			if ocean_plane==original_plane: ocean_plane=original_plane.duplicate() as PlaneMesh
			ocean_plane.subdivide_width=values.water_detail; ocean_plane.subdivide_depth=values.water_detail
		ocean_node.mesh=ocean_plane
	environment.ambient_light_energy=base_ambient*values.ambient_percent/100.0
	if values.texture_filter==1: refresh_materials()
	for item in materials:
		item.material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC if values.texture_filter==1 else item.original_filter
	Engine.max_fps=values.fps_limit
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values.vsync else DisplayServer.VSYNC_DISABLED)

extends "res://src/boat/ilca_hull.gd"
const CACHE := "res://src/boat/assets/inspection_hull.res"
const FLOOR_SOURCE_SHA256 := "43ac686d4b4d10722a10ca2630e8326564c763c82bd548be2f3ee2483a53bf18"
var exact_floor_shortcut := FileAccess.get_sha256("res://src/boat/ilca_hull.gd")==FLOOR_SOURCE_SHA256
func cockpit_floor_y_at(x_position: float,z_position: float) -> float:
	if not exact_floor_shortcut: return super.cockpit_floor_y_at(x_position,z_position)
	# The original floor/base implementation does not consume half_width.
	return _cockpit_floor_y(x_position,0,z_position)
func _cockpit_base_y(x_position: float, _half_width: float, z_position: float) -> float:
	if not exact_floor_shortcut: return super._cockpit_base_y(x_position,_half_width,z_position)
	# Evaluate the original mould exactly, but do not construct a deck
	# profile where its blend weight is zero. Rope support queries mostly
	# lie in this low well; no height grid or interpolated proxy is used.
	var z := clampf(z_position,float(_cockpit_z_positions.front()),float(_cockpit_z_positions.back()))
	var width := _cockpit_half_width_at(z)
	var core := maxf(.020,width-.100)
	var dish := .004*smoothstep(0,core,absf(x_position))
	var floor_y := .041+dish-.002*smoothstep(.45,1.20,z)
	var foreland := 1-smoothstep(FORELAND_STEP_START,FORELAND_STEP_END,z)
	var side := clampf((absf(x_position)-core)/maxf(width-core,.001),0,1)
	var side_round := smoothstep(0,1,pow(side,1.6))
	var aft_round := smoothstep(1.340,1.415,z)
	var wall := 1-(1-side_round)*(1-aft_round)
	if foreland==0 and wall==0: return floor_y
	var deck := deck_y_at(x_position,z)
	if foreland!=0:
		var landing := lerpf(deck,FORELAND_HEIGHT,smoothstep(-.390,-.080,z))
		floor_y=lerpf(floor_y,landing,foreland)
	return lerpf(floor_y,deck,wall)
func _build_hull_mesh() -> ArrayMesh:
	var prepared: ArrayMesh=load(CACHE)
	if prepared==null or prepared.get_meta("source_sha256","")!=FileAccess.get_sha256("res://src/boat/ilca_hull.gd") or prepared.get_meta("cut_sha256","")!=FileAccess.get_sha256("res://src/boat/ilca_mesh_cut.gd"):
		push_warning("Inspection hull cache is missing or stale; using original construction")
		return super._build_hull_mesh()
	for key: String in ["drain_frame","drain_outlet","drain_inlet_ring","drain_outlet_ring","_drain_seat","_drain_seat_center"]:
		set(key,prepared.get_meta(key))
	return prepared

extends "res://src/boat/ilca_hull.gd"
const CACHE := "res://src/boat/assets/inspection_hull.res"
func _build_hull_mesh() -> ArrayMesh:
	var prepared: ArrayMesh=load(CACHE)
	if prepared==null or prepared.get_meta("source_sha256","")!=FileAccess.get_sha256("res://src/boat/ilca_hull.gd") or prepared.get_meta("cut_sha256","")!=FileAccess.get_sha256("res://src/boat/ilca_mesh_cut.gd"):
		push_warning("Inspection hull cache is missing or stale; using original construction")
		return super._build_hull_mesh()
	for key: String in ["drain_frame","drain_outlet","drain_inlet_ring","drain_outlet_ring","_drain_seat","_drain_seat_center"]:
		set(key,prepared.get_meta(key))
	return prepared

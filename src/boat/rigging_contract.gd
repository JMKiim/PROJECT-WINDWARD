extends RefCounted

## Shared semantic datums. A measured limit is not a mounting centre.
## Values marked provisional must be calibrated before the seated rig adopts them.
const HULL := preload("res://src/boat/ilca_hull.gd")
const MAST_BASE := Vector3(0,.005,HULL.MAST_CENTER_Z)
const GOOSE := Vector3(0,.950,HULL.MAST_CENTER_Z)
const GOOSE_PIN_OFFSET := Vector3(0,0,.105)
const BOOM_LENGTH := 2.740
const VANG_KEY_LOCAL := Vector3(0,-.075,.445)
const VANG_BASE_LOCAL := Vector3(0,.530,HULL.MAST_CENTER_Z+.045)
const CLEW_LOCAL := Vector3(0,.060,2.620)
const SAIL_HEAD := Vector3(0,6.115,HULL.MAST_CENTER_Z)
const FORWARD_BLOCK_LOCAL := Vector3(0,-.0605,BOOM_LENGTH-1.653)
const AFT_BLOCK_LOCAL := Vector3(0,-.0605,BOOM_LENGTH-.071)
const TRAVELLER := Vector3(.455,.37,HULL.HULL_LENGTH_METERS*.5-.2625)
const DECK_BLOCK := HULL.RATCHET_ORIGIN

static func systems() -> Dictionary:
	return {
		"mainsheet": {"live":true,"control_lines":1,"diameter_m":.008,"total_m":14.0,
			"route":["aft_becket","traveller_upper","aft_sheave","boom_guide","forward_sheave","deck_ratchet","hands","free_stopper"],
			"purchase":"derive from route Jacobian; not one constant boom-angle multiplier",
			"hold":"hand/helper; no new automatic cleat assumed"},
		"vang": {"live":false,"control_lines":2,"primary_total_m":1.5,"tail_total_m":5.0,
			"primary_diameter_m":.003,"tail_diameter_m":.004,"nominal_purchase":15.0,
			"primary_route":["key_fixed_end","base_turn","key_sheave","floating_double_attachment"],
			"tail_route":["floating_becket","base_turn_a","floating_sheave_a","base_turn_b","floating_sheave_b","swivel_cleat","free_tail"],
			"layout":"EX2195 reference; 3:1 primary times 5:1 control, ideal axial approximation",
			"hold":"base cleat; hand reach and release gesture not yet authored"},
		"cunningham": {"live":false,"route":["mast_attachment","sail_cringle","purchase_pending","port_deck_block","port_cam","free_tail"],
			"purchase":0,"status":"route family known; selected purchase and travel unmeasured"},
		"outhaul": {"live":false,"route":["boom_end_attachment","clew","boom_end_fairlead","purchase_pending","gooseneck_turn","starboard_deck_block","starboard_cam","free_tail"],
			"purchase":0,"status":"route family known; selected purchase and travel unmeasured"},
		"traveller": {"live":false,"control_lines":1,"diameter_m":.006,
			"route":["closed_loop","starboard_eye","traveller_lower","port_eye","traveller_cleat","handle"],
			"status":"current visual assembly; exact tying and adjustable pretension pending"}
	}

static func datums() -> Dictionary:
	return {
		"lower_mast_max_m":2.865,"upper_mast_max_m":3.600,"insertion_m":.305,
		"gooseneck_from_base_m":.945,"gooseneck_tolerance_m":.005,
		"vang_tang_lowest_min_m":.445,"vang_key_aft_edge_max_m":.482,
		"boom_max_m":2.740,"aft_block_from_end_m":.071,"forward_block_from_end_m":1.653,
		"provisional":["pin fore-aft offset","tang/base sheave centre","vang key sheave centre","traveller sheave height","line dead allowances","elastic stiffness","boom mass/inertia","leech stiffness/rest length","upper-mast mode/stiffness/mass","aerodynamic pressure and support split"]
	}

static func boom_transform(yaw: float,pitch: float) -> Transform3D:
	var turn := Basis(Vector3.UP,yaw)
	return Transform3D(turn*Basis(Vector3.RIGHT,pitch),GOOSE+turn*GOOSE_PIN_OFFSET)

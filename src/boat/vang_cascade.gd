extends RefCounted

## Two separate elastic, tension-only lines. Ideal axial 3:1 x 5:1 cascade.
## This is a reduced mechanical model, not measured block friction or hardware contact.
const PRIMARY_TOTAL := 1.5
const CONTROL_TOTAL := 5.0
const PRIMARY_DEAD := .10
const CONTROL_DEAD := .20
const PRIMARY_WORKING := PRIMARY_TOTAL-PRIMARY_DEAD
const PRIMARY_STIFFNESS := 18000.0
const CONTROL_STIFFNESS := 900.0
const PRIMARY_LEGS := 3.0
const CONTROL_LEGS := 5.0
const NOMINAL_PURCHASE := PRIMARY_LEGS*CONTROL_LEGS
const MIN_CARRIAGE := .070
const BLOCK_CLEARANCE := .040

static func tail_for_span(span: float) -> float:
	return CONTROL_TOTAL-CONTROL_DEAD-CONTROL_LEGS*(PRIMARY_LEGS*span-PRIMARY_WORKING)

static func evaluate(span: float,tail: float) -> Dictionary:
	if not is_finite(span) or not is_finite(tail) or span<=BLOCK_CLEARANCE+MIN_CARRIAGE or tail<0 or tail>CONTROL_TOTAL-CONTROL_DEAD:
		return {"valid":false,"reason":"invalid cascade span or material allocation"}
	var available := CONTROL_TOTAL-CONTROL_DEAD-tail
	var free_carriage := available/CONTROL_LEGS
	var demanded_carriage := PRIMARY_LEGS*span-PRIMARY_WORKING
	var carriage := free_carriage
	if demanded_carriage>free_carriage:
		carriage = (PRIMARY_STIFFNESS*demanded_carriage+CONTROL_LEGS*CONTROL_STIFFNESS*available)/(PRIMARY_STIFFNESS+CONTROL_LEGS*CONTROL_LEGS*CONTROL_STIFFNESS)
	# Travel stops constrain the carriage, never the material allocation.
	# Excess line is slack; a loaded stop contributes its energy gradient.
	var travel_stop := carriage<MIN_CARRIAGE or carriage>span-BLOCK_CLEARANCE
	var upper_stop := carriage>span-BLOCK_CLEARANCE
	carriage = clampf(carriage,MIN_CARRIAGE,span-BLOCK_CLEARANCE)
	var primary_route := PRIMARY_LEGS*span-carriage
	var control_route := CONTROL_LEGS*carriage
	var primary_extension := maxf(0,primary_route-PRIMARY_WORKING)
	var control_extension := maxf(0,control_route-available)
	var primary_slack := maxf(0,PRIMARY_WORKING-primary_route)
	var control_slack := maxf(0,available-control_route)
	var primary_force := primary_extension*PRIMARY_STIFFNESS
	var tail_force := control_extension*CONTROL_STIFFNESS
	var carriage_residual := primary_force-CONTROL_LEGS*tail_force
	var output_force := PRIMARY_LEGS*primary_force-carriage_residual if upper_stop else PRIMARY_LEGS*primary_force
	return {"valid":true,"travel_stop":travel_stop,"span_m":span,"carriage_m":carriage,
		"primary_route_m":primary_route,"control_route_m":control_route,"tail_m":tail,
		"primary_extension_m":primary_extension,"control_extension_m":control_extension,
		"primary_slack_m":primary_slack,"control_slack_m":control_slack,
		"primary_tension_n":primary_force,"tail_tension_n":tail_force,
		"boom_tension_n":output_force,"stop_reaction_n":absf(carriage_residual) if travel_stop else 0.0,
		"carriage_residual_n":carriage_residual,
		"primary_material_m":primary_route+PRIMARY_DEAD+primary_slack-primary_extension,
		"control_material_m":control_route+CONTROL_DEAD+tail+control_slack-control_extension,
		"elastic_energy_j":.5*PRIMARY_STIFFNESS*primary_extension*primary_extension+.5*CONTROL_STIFFNESS*control_extension*control_extension}

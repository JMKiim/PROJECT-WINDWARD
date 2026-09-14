extends RefCounted

## Material ledger, independent of pose progress and rendering. Geometry owns
## the rig minimum, hand reserve and measured end assemblies (knot + end tail).
const DEFAULT_TOTAL_METRES := 14.0
const END_STYLE := &"figure_eight"
const EPSILON := 0.0000001

var total_metres := DEFAULT_TOTAL_METRES
var rig_metres := 0.0
var cockpit_metres := 0.0
var fixed_end_metres := 0.0
var free_end_metres := 0.0
var minimum_rig_metres := 0.0
var minimum_cockpit_metres := 0.0
var configured := false

func configure(rig_minimum: float, initial_rig: float, cockpit_minimum: float,
		fixed_end: float, free_end: float, total: float = DEFAULT_TOTAL_METRES) -> bool:
	# Invalid geometry leaves an existing allocation intact. Do not manufacture
	# length by clamping impossible spans or using a guessed knot allowance.
	for value in [rig_minimum, initial_rig, cockpit_minimum, fixed_end, free_end, total]:
		if not is_finite(value): return false
	if rig_minimum <= 0.0 or cockpit_minimum < 0.0 or fixed_end <= 0.0 or free_end <= 0.0 or total <= 0.0:
		return false
	var available := total - fixed_end - free_end
	if initial_rig < rig_minimum or initial_rig > available - cockpit_minimum:
		return false
	total_metres = total
	fixed_end_metres = fixed_end
	free_end_metres = free_end
	minimum_rig_metres = rig_minimum
	minimum_cockpit_metres = cockpit_minimum
	rig_metres = initial_rig
	cockpit_metres = available - rig_metres
	configured = true
	return true

func available_haul() -> float:
	var remaining := rig_metres - minimum_rig_metres
	return remaining if configured and remaining > EPSILON else 0.0

func available_ease() -> float:
	var remaining := cockpit_metres - minimum_cockpit_metres
	return remaining if configured and remaining > EPSILON else 0.0

func transferable(requested: float) -> float:
	if not configured or not is_finite(requested): return 0.0
	return clampf(requested, -available_ease(), available_haul())

func transfer(requested: float) -> float:
	# Positive means haul: material leaves the rig and enters the cockpit.
	var accepted := transferable(requested)
	if accepted == 0.0: return 0.0
	rig_metres -= accepted
	cockpit_metres = total_metres - fixed_end_metres - free_end_metres - rig_metres
	return accepted

func set_cockpit_minimum(required: float) -> bool:
	if not configured or not is_finite(required) or required < 0.0 or required > cockpit_metres:
		return false
	# A hand/posture change may reserve existing material, never feed the rig.
	minimum_cockpit_metres = required
	return true

func partition(held_metres: float, suspended_metres: float) -> Dictionary:
	if not configured or not is_finite(held_metres) or not is_finite(suspended_metres):
		return {"valid":false}
	if held_metres < 0.0 or suspended_metres < 0.0 or held_metres + suspended_metres > cockpit_metres + EPSILON:
		return {"valid":false}
	return {"valid":true, "rig":rig_metres, "held":held_metres,
		"suspended":suspended_metres, "floor":maxf(0.0, cockpit_metres-held_metres-suspended_metres),
		"fixed_end":fixed_end_metres, "free_end":free_end_metres, "total":total_metres}

func snapshot() -> Dictionary:
	return {"configured":configured, "total_metres":total_metres,
		"rig_metres":rig_metres, "cockpit_metres":cockpit_metres,
		"fixed_end_metres":fixed_end_metres, "free_end_metres":free_end_metres,
		"fixed_end_style":END_STYLE, "free_end_style":END_STYLE,
		"available_haul_metres":available_haul(), "available_ease_metres":available_ease()}

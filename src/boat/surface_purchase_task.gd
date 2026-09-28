extends RefCounted

## Detached numeric work with an owned cancellable thread. Scene access and
## the all-or-nothing material/display commit belong to the caller.
const CONTROL := preload("res://src/boat/contact_work_control.gd")
const MODEL := preload("res://src/boat/surface_purchase_equilibrium.gd")
const SEED := preload("res://src/boat/orthogonal_pin_route.gd")
const FREE := preload("res://src/boat/free_pinned_block.gd")
const GUARD := preload("res://src/boat/surface_purchase_guard.gd")
const FINITE := preload("res://src/boat/surface_fairlead_contact.gd")
const STEERING_SEED_MAX_DELTA := 7.0*PI/180.0
const BOOM_SEED_MAX_DELTA := 4.0*PI/180.0
var worker: Thread
var control: RefCounted
var cache_input := {}
var cache_result := {}
var accepted_states := []
var pending := {}
var key_changes := []

func start(input: Dictionary) -> Error:
	if worker!=null: return ERR_BUSY
	control=CONTROL.new()
	pending=_core_key(input)
	key_changes.clear()
	if not cache_input.is_empty():
		for key in pending:
			if not cache_input.has(key) or pending[key]!=cache_input[key]: key_changes.append(key)
	worker=Thread.new()
	var reuse := cache_result.duplicate(true) if pending==cache_input else _retained_numeric(pending)
	var load_seed: bool=reuse.is_empty() and _load_seed_compatible(pending,cache_input)
	var steering_seed: bool=reuse.is_empty() and not load_seed and cache_result.has("surface_contact") and _steering_seed_compatible(pending,cache_input)
	var boundary_seed: bool=reuse.is_empty() and not load_seed and not steering_seed and cache_result.has("surface_contact") and _boundary_seed_compatible(pending,cache_input)
	var seed: Dictionary=_transport_attachment(cache_result,input) if boundary_seed else cache_result.duplicate(true) if load_seed or steering_seed else {}
	if not seed.is_empty() and steering_seed: seed["_seed_kind"]="steering"
	if not seed.is_empty() and boundary_seed: seed["_seed_kind"]="boundary"
	var job := calculate.bind(input.duplicate(true),control.cancelled,reuse,seed)
	var error := worker.start(job,Thread.PRIORITY_LOW)
	if error!=OK: worker=null
	return error

func cancel() -> void:
	if control!=null: control.cancel()

func ready() -> bool: return worker!=null and not worker.is_alive()

func take() -> Dictionary:
	if not ready(): return {}
	var result: Dictionary=worker.wait_to_finish()
	worker=null
	result["cache_key_changes"]=key_changes.duplicate()
	if control.cancelled(): return {"valid":false,"cancelled":true,"reason":"purchase request cancelled"}
	if result.get("accepted",false):
		cache_input=pending
		cache_result=result.numeric.duplicate(true)
		_remember_accepted()
	pending={}
	return result

func finish() -> void:
	cancel()
	if worker!=null:
		worker.wait_to_finish()
		worker=null
	cache_input.clear()
	cache_result.clear()
	accepted_states.clear()
	pending.clear()

func _retained_numeric(key: Dictionary) -> Dictionary:
	# Two exact boundaries are sufficient for the two inspection presets.
	# This is not a pose search or an interpolated force certificate. The
	# worker still rebuilds downstream geometry and checks every real mesh.
	for entry: Dictionary in accepted_states:
		if entry.key==key: return entry.numeric.duplicate(true)
	return {}

func _remember_accepted() -> void:
	# Called only after successful whole geometry/material acceptance in
	# take(). Cancelled or rejected jobs cannot replace or reorder entries.
	for index in range(accepted_states.size()-1,-1,-1):
		if accepted_states[index].key==cache_input: accepted_states.remove_at(index)
	accepted_states.append({"key":cache_input.duplicate(true),"numeric":cache_result.duplicate(true)})
	while accepted_states.size()>2: accepted_states.pop_front()

static func _core_key(input: Dictionary) -> Dictionary:
	# Downstream paths and collision meshes do not enter the contact-free
	# force key. A finite contact additionally requires its exact geometry key.
	# ALWAYS rebuild all mesh fields and validate the complete assembly before
	# acceptance, including a reused force solution. Never round the force key.
	var result := input.duplicate(true)
	for key in ["path","wraps","fixed","bodies"]: result.erase(key)
	return result

static func _load_seed_compatible(current: Dictionary,previous: Dictionary) -> bool:
	# A changed load may reuse a POSE only. Never reuse its force solution.
	# This gate changes only one scalar load. The separate steering gate
	# can seed an accepted finite contact, never reuse its old forces.
	if current.is_empty() or previous.is_empty(): return false
	if current.get("tiller_angle")!=previous.get("tiller_angle"): return false
	var a := current.duplicate(true)
	var b := previous.duplicate(true)
	if not a.get("load") is Dictionary or not b.get("load") is Dictionary: return false
	a.load.erase("sheet_tension")
	b.load.erase("sheet_tension")
	return a==b

static func _steering_seed_compatible(current: Dictionary,previous: Dictionary) -> bool:
	# This permits a starting POSE, not a force certificate. Preserve every
	# load, boom/guide attachment, material, fixed shape and winding exactly.
	# Only small tiller motion and the manual rig's initial guesses may vary.
	if current.is_empty() or previous.is_empty(): return false
	if current.get("load")!=previous.get("load") or current.get("angles")!=previous.get("angles"): return false
	for item: Dictionary in [current,previous]:
		if not (item.get("tiller_angle") is float or item.get("tiller_angle") is int) or not is_finite(item.tiller_angle): return false
		if not item.get("boundary") is Dictionary or not item.boundary.get("tiller") is Transform3D: return false
		if not MODEL.ROUTE.PIN.rigid(item.boundary.tiller): return false
	if absf(current.tiller_angle-previous.tiller_angle)>STEERING_SEED_MAX_DELTA+1e-9: return false
	var first: Transform3D=current.boundary.tiller
	var last: Transform3D=previous.boundary.tiller
	if first.origin.distance_to(last.origin)>.07: return false
	if first.basis.get_rotation_quaternion().angle_to(last.basis.get_rotation_quaternion())>STEERING_SEED_MAX_DELTA+.00001: return false
	var a := current.duplicate(true)
	var b := previous.duplicate(true)
	for item: Dictionary in [a,b]:
		for key in ["tiller_angle","lower","aft","upper_in","upper_out"]: item.erase(key)
		item.boundary.erase("tiller")
	return a==b

static func _boundary_seed_compatible(current: Dictionary,previous: Dictionary) -> bool:
	# A small manual return can change boom pitch as well as steering.
	# This is still only an initialization gate: the exact force key is
	# untouched and all requested anchors enter a completely new solve.
	if current.is_empty() or previous.is_empty() or current.get("load")!=previous.get("load"): return false
	for item: Dictionary in [current,previous]:
		if not item.get("angles") is Vector2 or not item.angles.is_finite(): return false
		if not item.get("boundary") is Dictionary or not item.boundary.get("purchase") is Dictionary: return false
		for key in ["mount","guide"]:
			if not item.boundary.purchase.get(key) is Vector3 or not item.boundary.purchase[key].is_finite(): return false
	if current.angles.x*previous.angles.x<=0: return false
	if absf(current.angles.x-previous.angles.x)>BOOM_SEED_MAX_DELTA or absf(current.angles.y-previous.angles.y)>BOOM_SEED_MAX_DELTA: return false
	# The actual forward guide moves 91.6 mm in the measured 3.1-degree
	# manual-return pitch change. This bound selects a starting pose only;
	# the requested mount/guide still enter every force and geometry check.
	if current.boundary.purchase.mount.distance_to(previous.boundary.purchase.mount)>.30 or current.boundary.purchase.guide.distance_to(previous.boundary.purchase.guide)>.13: return false
	var a := current.duplicate(true)
	var b := previous.duplicate(true)
	# Compare all other physical inputs exactly; this local comparison copy
	# never changes the requested input, cache key, geometry or material.
	a.angles=b.angles
	a.boundary.purchase.mount=b.boundary.purchase.mount
	a.boundary.purchase.guide=b.boundary.purchase.guide
	return _steering_seed_compatible(a,b)

static func _transport_attachment(numeric: Dictionary,input: Dictionary) -> Dictionary:
	if not numeric.get("refined") is Dictionary or not numeric.refined.get("state") is Dictionary or not numeric.get("datum") is Vector3: return {}
	if not numeric.refined.state.get("aft") is Transform3D: return {}
	if not input.get("boundary") is Dictionary or not input.boundary.get("purchase") is Dictionary: return {}
	for key in ["mount","eye"]:
		if not input.boundary.purchase.get(key) is Vector3 or not input.boundary.purchase[key].is_finite(): return {}
	var result := numeric.duplicate(true)
	var frame: Transform3D=result.refined.state.aft
	# Preserve orientation only as a guess. Attach its eye to the actual
	# newly requested mount before Newton evaluates any force or derivative.
	frame.origin=input.boundary.purchase.mount-result.datum-frame.basis*input.boundary.purchase.eye
	result.refined.state.aft=frame
	return result

static func calculate(input: Dictionary,cancelled := Callable(),reused := {},seed := {}) -> Dictionary:
	var began := Time.get_ticks_usec()
	var stop := func(): return Time.get_ticks_usec()-began>45000000 or (cancelled.is_valid() and cancelled.call())
	if stop.call(): return {"valid":false,"reason":"purchase request cancelled"}
	if reused.has("surface_contact") and reused.surface_contact.geometry_key!=FINITE.geometry_key(input):
		return {"valid":false,"reason":"finite geometry: cached contact geometry changed"}
	var numeric: Dictionary=_equilibrium(input,began,stop,seed) if reused.is_empty() else reused
	if not numeric.get("valid",false): return numeric
	var refined: Dictionary=numeric.refined
	var datum: Vector3=numeric.datum
	var working := FINITE.effective_input(input,numeric)
	var result := GUARD.assemble(working,refined,datum)
	if not result.valid: return result
	var guard := GUARD.check_geometry(working,refined,datum,result,stop)
	# A real fitting collision may select a new reaction/exit solve. It is
	# never repaired visually, and a changed cached mesh cannot trigger this
	# branch under stale forces. All independent guards run again afterwards.
	if not guard.valid and reused.is_empty() and FINITE.valid_data(input) and _needs_fairlead_contact(guard):
		var initialization: String=numeric.get("initialization","cold")
		numeric=FINITE.solve(input,numeric,began+45000000,stop)
		if not numeric.get("valid",false): return numeric
		# Keep the actual starting path (including a rejected warm seed)
		# when adding finite contact; do not overwrite recovery evidence.
		numeric["initialization"]=initialization+"; finite fairlead and lower contact independently refined"
		refined=numeric.refined
		datum=numeric.datum
		working=FINITE.effective_input(input,numeric)
		result=GUARD.assemble(working,refined,datum)
		if not result.valid: return result
		guard=GUARD.check_geometry(working,refined,datum,result,stop)
	if not guard.valid: return {"valid":false,"reason":"finite geometry: "+guard.reason,"detail":guard,"candidate":result,"solved":refined}
	result["accepted"]=true
	result["numeric"]=numeric
	result["reused"]=not reused.is_empty()
	result["initialization"]=numeric.get("initialization","exact cached equilibrium") if reused.is_empty() else "exact cached equilibrium"
	result["force"]=refined.get("contact_wrench",refined.wrench)
	result["lower_contact_n"]=refined.get("reaction_n",0.0)
	result["aft_moment"]=refined.aft_moment
	result["support_tension"]=refined.tension
	result["sheet_tension"]=input.load.sheet_tension
	result["guard"]=guard
	result["elapsed_ms"]=(Time.get_ticks_usec()-began)/1000.0
	result["stability_certified"]=false
	result["fairlead_force_certified"]=false
	result["force_scope"]="lower/upper/aft bodies, rear support span and finite lower contact where active; fairlead patches are geometric boundaries, not solved frictionless reactions"
	return result

static func _needs_fairlead_contact(guard: Dictionary) -> bool:
	if guard.get("reason","")=="actual fairlead contact requires another equilibrium": return true
	return guard.get("reason","")=="whole traveller/fixed fitting or hull clearance" and guard.get("detail",{}).get("fitting_gap",INF)<.00025

static func _equilibrium(input: Dictionary,began: int,stop: Callable,seed := {}) -> Dictionary:
	var warm_reason := ""
	if not seed.is_empty():
		var warm := FINITE.solve(input,seed,mini(began+45000000,Time.get_ticks_usec()+20000000),stop,true) if seed.has("surface_contact") else _warm_load(input,seed,began,stop)
		if warm.get("valid",false) and seed.has("surface_contact"):
			warm["initialization"]="previous accepted finite contact; new "+seed.get("_seed_kind","load")+" forces and exits independently recomputed"
		if warm.get("valid",false): return warm
		warm_reason=warm.get("reason","invalid warm pose")
		if stop.call(): return warm
	var boundary: Dictionary=input.boundary.duplicate(true)
	var initial := SEED.solve(boundary,input.rear_metres,input.lower.origin.x,input.upper_in,input.upper_out,input.lower_eye,input.upper_eye,.0195,deg_to_rad(-70),deg_to_rad(70))
	if not initial.valid: return {"valid":false,"reason":"initial joint: "+initial.reason}
	var datum: Vector3=initial.lower.origin
	for key in ["port","starboard"]: boundary[key]-=datum
	boundary.tiller.origin-=datum
	for key in ["mount","guide"]: boundary.purchase[key]-=datum
	var lower: Transform3D=initial.lower
	lower.origin-=datum
	var joint := {"lower_eye":input.lower_eye,"upper_eye":input.upper_eye,"minimum":deg_to_rad(-70),"maximum":deg_to_rad(70)}
	initial=FREE.compose(joint,lower,initial.angle)
	initial["aft"]=input.aft
	initial.aft.origin-=datum
	# Select the installed winding once at the assembled seed, then hold it
	# fixed through all derivatives, solving and independent refinement.
	var installed := MODEL.ROUTE.route(boundary.purchase,initial.aft,initial.upper,25,2000,stop)
	if not installed.valid: return {"valid":false,"reason":"installed route: "+installed.reason}
	boundary.purchase.traveller_winding=signf(installed.traveller.sweep)
	boundary.purchase.aft_winding=signf(installed.aft.sweep)
	# Scale only the starting guess with the requested load. A fixed 8 N
	# seed was far outside the low-load basin; all forces are still solved
	# and independently certified under the unchanged physical criteria.
	var solved := MODEL.solve(boundary,initial,input.load,input.rear_metres,input.load.sheet_tension*1.6,15000,stop)
	var result := _certify(solved,boundary,input,began,stop,datum)
	result["initialization"]="cold" if warm_reason.is_empty() else "cold after rejected "+seed.get("_seed_kind","load")+" seed: "+warm_reason
	return result

static func _warm_load(input: Dictionary,seed: Dictionary,began: int,stop: Callable) -> Dictionary:
	if not seed.get("valid",false) or not seed.get("refined") is Dictionary or not seed.get("datum") is Vector3:
		return {"valid":false,"reason":"invalid accepted load seed"}
	var source: Dictionary=seed.refined
	var initial: Dictionary=source.state.duplicate(true)
	initial.erase("profiles")
	var datum: Vector3=seed.datum
	var boundary: Dictionary=input.boundary.duplicate(true)
	for key in ["port","starboard"]: boundary[key]-=datum
	boundary.tiller.origin-=datum
	for key in ["mount","guide"]: boundary.purchase[key]-=datum
	boundary.purchase.traveller_winding=signf(source.purchase.traveller.sweep)
	boundary.purchase.aft_winding=signf(source.purchase.aft.sweep)
	var solved := MODEL.solve(boundary,initial,input.load,input.rear_metres,source.tension,6000,stop)
	var result := _certify(solved,boundary,input,began,stop,datum)
	result["initialization"]="previous accepted load pose; forces recomputed"
	return result

static func _certify(solved: Dictionary,boundary: Dictionary,input: Dictionary,began: int,stop: Callable,datum: Vector3) -> Dictionary:
	if not solved.get("converged",false):
		solved["valid"]=false
		return solved
	var state: Dictionary=solved.state.duplicate(true)
	state.erase("profiles")
	var refined := MODEL._evaluate(state,solved.tension,boundary,input.load,input.rear_metres,129,began+45000000,stop)
	if not refined.get("valid",false) or refined.wrench.force_n.length()>=MODEL.FORCE_TOLERANCE or refined.wrench.moment_nm.length()>=MODEL.MOMENT_TOLERANCE or absf(refined.wrench.hinge_nm)>=MODEL.MOMENT_TOLERANCE or refined.aft_moment.length()>=MODEL.MOMENT_TOLERANCE or absf(refined.length_error_m)>=MODEL.LENGTH_TOLERANCE:
		return {"valid":false,"reason":"independent surface refinement rejected","detail":refined}
	return {"valid":true,"refined":refined,"datum":datum}

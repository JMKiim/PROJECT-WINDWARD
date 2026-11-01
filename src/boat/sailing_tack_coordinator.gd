extends RefCounted
## Coordinates an explicit crew maneuver with the existing rudder-driven hull.
## Never writes heading, velocity, trim, bones or a second animation clock.
const TIMELINE := preload("res://src/preview/tack/timeline.gd")
const AFT_LIMIT := deg_to_rad(165)
const REQUEST_LIMIT := deg_to_rad(65)
const ARRIVAL_COURSE := deg_to_rad(35)
var control: Node3D
var entry_course := ARRIVAL_COURSE
var course_limited := false
var observed := false
var last_signed := 0.0
var unwrapped_course := 0.0
var normal_side := 0
var normal_origin := 0.0
var gybe_center := 0.0

func setup(value: Node3D) -> void: control=value

func signed_course() -> float:
	var state: RefCounted=control.boat.sailing_state
	if state.true_wind_velocity.length_squared()<.0001: return 0.0
	return state.forward_vector().signed_angle_to(-state.true_wind_velocity.normalized(),Vector3.UP)

func observe_course() -> void:
	if control.boat.sailing_state.true_wind_velocity.length_squared()<.0001: return
	var course := signed_course()
	if not observed:
		unwrapped_course=course
		observed=true
	else: unwrapped_course+=wrapf(course-last_signed,-PI,PI)
	last_signed=course
	# CROSS temporarily uses the canonical port actor. Only committed normal
	# seats may rebase the bow interval, never that implementation convention.
	if control.deck.tack.phase not in ["ENTRY","CROSS","EXIT"] and normal_side!=control.deck.actor.seat_side:
		normal_side=control.deck.actor.seat_side
		normal_origin=floorf(-normal_side*unwrapped_course/TAU)*TAU

func current_unwrapped() -> float:
	return unwrapped_course+wrapf(signed_course()-last_signed,-PI,PI) if observed else signed_course()

func owned_course() -> float:
	return -normal_side*current_unwrapped()-normal_origin if normal_side!=0 else -control.deck.actor.seat_side*signed_course()

func gybe_course() -> float:
	return PI-control.deck.tack.source_side*(current_unwrapped()-gybe_center)

func request() -> bool:
	var tack: RefCounted=control.deck.tack
	if tack.busy(): return false
	var course: float=signed_course()*-control.deck.actor.seat_side
	if control.boat.sailing_state.true_wind_velocity.length_squared()<.0001 or course<-.000001 or course>REQUEST_LIMIT:
		control.deck.session.notice="T 태킹은 현재 현의 풍각 0–65°에서 준비해 주세요. A/D로 먼저 바람 쪽으로 올라가세요."
		return false
	entry_course=maxf(ARRIVAL_COURSE,course)
	return tack.request()

func request_gybe() -> bool:
	var tack: RefCounted=control.deck.tack
	if tack.manual_trim_stage():
		if tack.phase=="TRIM" and (control.boat.sailing_state.true_wind_velocity.length_squared()<.0001 or gybe_course()<deg_to_rad(120) or gybe_course()>deg_to_rad(240)):
			control.deck.session.notice="G 전환은 기존 붐 측 기준 풍하 120–240°에서 확정해 주세요."
			return false
		return tack.request_gybe()
	if tack.busy(): return false
	observe_course()
	var course := fposmod(-control.deck.actor.seat_side*signed_course(),TAU)
	if control.boat.sailing_state.true_wind_velocity.length_squared()<.0001 or course<deg_to_rad(120) or course>deg_to_rad(240):
		control.deck.session.notice="G 자이빙은 풍하에서 준비해 주세요(기존 붐 측 기준 120–240°)."
		return false
	if not tack.request_gybe(): return false
	gybe_center=current_unwrapped()-tack.source_side*(PI-course)
	return true

func prepare_tick() -> void:
	var tack: RefCounted=control.deck.tack
	tack.clock_limit=NAN
	if not tack.busy(): return
	if control.boat.sailing_state.true_wind_velocity.length_squared()<.0001:
		tack.clock_limit=tack.clock_progress
		return
	if tack.is_gybe():
		# The explicit G owns boom transfer; crossing180 alone does nothing.
		# Preserve the stern branch through atan2's wrap in both directions.
		var fraction := clampf((gybe_course()-deg_to_rad(150))/deg_to_rad(60),0,1)
		tack.clock_limit=TIMELINE.time_for(fraction if tack.source_side==-1 else 1-fraction)
		return
	var course: float=signed_course()*-tack.source_side
	# Meet the middle of the authored body path at head-to-wind. Passing
	# through that course is necessary, not sufficient: the original minimum
	# travel speed and finite handoff pauses still own the animation time.
	var fraction: float=.5*(1-course/entry_course) if course>=0 else .5+.5*(-course/ARRIVAL_COURSE)
	fraction=clampf(fraction,0,1)
	tack.clock_limit=TIMELINE.time_for(fraction if tack.source_side==-1 else 1-fraction)

func limit_rudder(command: float,delta: float) -> float:
	course_limited=false
	if delta<=0: return command
	var state: RefCounted=control.boat.sailing_state
	if state.true_wind_velocity.length_squared()<.0001: return command
	var authority: float=state.rudder_authority()
	var turn: float=state.MAX_TURN_RATE*absf(authority)*delta
	if turn<=.000000001: return command
	var tack: RefCounted=control.deck.tack
	var crossing: bool=tack.phase in ["ENTRY","CROSS","EXIT","POST"]
	var low := -AFT_LIMIT
	var high := AFT_LIMIT
	var course := signed_course()
	var direction := 1.0
	if tack.busy() and tack.is_gybe():
		low=deg_to_rad(90); high=deg_to_rad(270)
		course=gybe_course(); direction=-tack.source_side
	elif not crossing:
		# The committed boom/seat owns a complete stern crossing. Only its
		# bow endpoints remain gated for explicit T; there is no165deg fence.
		low=0; high=TAU
		course=owned_course(); direction=-control.deck.actor.seat_side
	direction*=signf(authority)
	# Bound the physical command before SailingState integrates it. If a
	# wind shift put us outside the supported sector, permit recovery only;
	# never teleport the hull back into the sector after integration.
	var minimum := minf(0,(low-course)/turn)
	var maximum := maxf(0,(high-course)/turn)
	var permitted := clampf(command*direction,minimum,maximum)*direction
	course_limited=absf(permitted-command)>.000001
	return permitted

func cancel_preparation() -> bool:
	if control.deck.tack.manual_trim_stage():
		control.deck.tack.leave_trim_stage()
		return true
	if control.deck.tack.phase!="PREP": return false
	control.deck.tack.cancel()
	control.deck.session.notice="태킹 준비 종료 · 현재 현과 트림을 유지해요."
	return true

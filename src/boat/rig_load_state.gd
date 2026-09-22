extends RefCounted

## Isolated boom/mast mechanical bench. Not the production sailing solver.
## World loads enter through a shared frame; crew weight belongs to hull balance.
const CONTRACT := preload("res://src/boat/rigging_contract.gd")
const VANG := preload("res://src/boat/vang_cascade.gd")
const WHEEL := preload("res://src/boat/animation/sheet_wheel_gesture.gd")
const MAST := preload("res://src/boat/rig_mast_curve.gd")
const STEP := 1.0/480.0
const INERTIA := Vector2(30,12)
const DAMPING := Vector2(32,18)
const SHEET_STIFFNESS := 1800.0
const LEECH_STIFFNESS := 20000.0
const LEECH_REST := 5.555
const MAST_TIP_STIFFNESS := 550.0
const MAST_TIP_MASS := 1.2
const MAST_TIP_DAMPING := 28.0
const BOOM_MASS := 7.0
const AREA := 7.06
var yaw := deg_to_rad(40)
var pitch := deg_to_rad(-5)
var angular_velocity := Vector2.ZERO
var mast_tip := Vector2.ZERO
var mast_velocity := Vector2.ZERO
var wind_world := Vector3(5,0,-2)
var boat_velocity_world := Vector3.ZERO
var boat_angular_velocity_world := Vector3.ZERO
var boat_acceleration_world := Vector3.ZERO
var boat_frame := Basis.IDENTITY
var extra_moment := Vector2.ZERO
var sheet_rest := 0.0
var initial_sheet_rest := 0.0
var vang_tail := 0.0
var initial_vang_tail := 0.0
var selected := 1
var target_sheet := 0.0
var target_vang := 0.0
var accumulator := 0.0
var rejected_time := 0.0
var elapsed := 0.0
var command_rate := 0.0
var wheel := WHEEL.new()
var last := {}
var valid := true
var external_sheet_constraint := false

func _init() -> void:
	reset()

func reset() -> void:
	yaw = deg_to_rad(40)
	pitch = deg_to_rad(-5)
	angular_velocity = Vector2.ZERO
	mast_tip = Vector2.ZERO
	mast_velocity = Vector2.ZERO
	initial_sheet_rest = sheet_geometry().length
	sheet_rest = initial_sheet_rest
	var boom := CONTRACT.boom_transform(yaw,pitch)
	initial_vang_tail = VANG.tail_for_span((boom*CONTRACT.VANG_KEY_LOCAL).distance_to(CONTRACT.VANG_BASE_LOCAL))
	vang_tail = initial_vang_tail
	target_sheet = sheet_rest
	target_vang = vang_tail
	accumulator = 0
	rejected_time = 0
	elapsed = 0
	command_rate = 0
	wheel.reset()
	valid = true
	last = forces()

func select_system(index: int) -> bool:
	if index not in [0,1]: return false
	cancel_input()
	selected = index
	return true

func cancel_input() -> void:
	target_sheet = sheet_rest
	target_vang = vang_tail
	command_rate = 0
	wheel.reset()

func request_wheel(notches: float) -> float:
	if not is_finite(notches) or is_zero_approx(notches): return 0
	var distance := clampf(notches,-8,8)*.020
	wheel.push(distance)
	distance *= wheel.trim_gain()
	if selected==0:
		if (sheet_rest-target_sheet)*distance<0: target_sheet = sheet_rest
		var previous := target_sheet
		target_sheet = clampf(target_sheet-distance,maxf(2.8,sheet_rest-.16),minf(10.0,sheet_rest+.16))
		return previous-target_sheet
	if (target_vang-vang_tail)*distance<0: target_vang = vang_tail
	var previous := target_vang
	target_vang = clampf(target_vang+distance,maxf(.3,vang_tail-.16),minf(4.2,vang_tail+.16))
	return target_vang-previous

func advance(delta: float) -> bool:
	if not valid or not is_finite(delta) or delta<=0: return false
	if not wind_world.is_finite() or not boat_velocity_world.is_finite() or not boat_angular_velocity_world.is_finite() or not boat_acceleration_world.is_finite() or not extra_moment.is_finite(): return false
	if not boat_frame.is_finite() or absf(boat_frame.determinant()-1)>.001 or not boat_frame.is_equal_approx(boat_frame.orthonormalized()): return false
	var accepted := minf(delta,.25)
	rejected_time += maxf(0,delta-accepted)
	accumulator += accepted
	while accumulator>=STEP-1e-10:
		wheel.advance(STEP)
		var rate := clampf(wheel.rate*wheel.trim_gain(),.08,1.6)
		command_rate = move_toward(command_rate,rate,4*STEP)
		sheet_rest = move_toward(sheet_rest,target_sheet,command_rate*STEP)
		vang_tail = move_toward(vang_tail,target_vang,command_rate*STEP)
		last = forces()
		if not last.valid:
			valid = false
			return false
		var moment: Vector2 = last.moment
		angular_velocity = (angular_velocity+moment/INERTIA*(STEP*.5))/(Vector2.ONE+DAMPING/INERTIA*(STEP*.5))
		mast_velocity = (mast_velocity+last.mast_force/MAST_TIP_MASS*(STEP*.5))/(1+MAST_TIP_DAMPING/MAST_TIP_MASS*(STEP*.5))
		mast_tip += mast_velocity*STEP
		if not mast_tip.is_finite() or mast_tip.length()>MAST.MAX_DISPLACEMENT:
			valid = false
			last = {"valid":false,"reason":"outside inextensible mast model range"}
			return false
		yaw += angular_velocity.x*STEP
		pitch += angular_velocity.y*STEP
		# Explicit test-bench stops, not a tack/gybe decision.
		var limited_yaw := clampf(yaw,deg_to_rad(5),deg_to_rad(165))
		var limited_pitch := clampf(pitch,deg_to_rad(-15),deg_to_rad(18))
		if limited_yaw!=yaw: angular_velocity.x = 0
		if limited_pitch!=pitch: angular_velocity.y = 0
		yaw = limited_yaw
		pitch = limited_pitch
		var next_load := forces()
		if not next_load.valid:
			valid = false
			last = next_load
			return false
		angular_velocity = (angular_velocity+next_load.moment/INERTIA*(STEP*.5))/(Vector2.ONE+DAMPING/INERTIA*(STEP*.5))
		mast_velocity = (mast_velocity+next_load.mast_force/MAST_TIP_MASS*(STEP*.5))/(1+MAST_TIP_DAMPING/MAST_TIP_MASS*(STEP*.5))
		elapsed += STEP
		accumulator -= STEP
	last = forces()
	return last.valid

func apparent_wind_at(point_boat: Vector3) -> Vector3:
	var world_offset := boat_frame*point_boat
	return boat_frame.inverse()*(wind_world-boat_velocity_world-boat_angular_velocity_world.cross(world_offset))

func effective_gravity() -> Vector3:
	return boat_frame.inverse()*(Vector3(0,-9.81,0)-boat_acceleration_world)

func sheet_geometry() -> Dictionary:
	var frame := CONTRACT.boom_transform(yaw,pitch)
	var aft := frame*CONTRACT.AFT_BLOCK_LOCAL
	var forward := frame*CONTRACT.FORWARD_BLOCK_LOCAL
	var aft_leg := aft-CONTRACT.TRAVELLER
	var fore_leg := forward-CONTRACT.DECK_BLOCK
	return {"length":2*aft_leg.length()+fore_leg.length()+CONTRACT.AFT_BLOCK_LOCAL.distance_to(CONTRACT.FORWARD_BLOCK_LOCAL),
		"aft":aft,"forward":forward,"aft_leg":aft_leg,"fore_leg":fore_leg}

func _moment_at(point: Vector3,force: Vector3) -> Vector2:
	var frame := CONTRACT.boom_transform(yaw,pitch)
	return Vector2((point-CONTRACT.GOOSE).cross(force).y,(point-frame.origin).cross(force).dot(Basis(Vector3.UP,yaw)*Vector3.RIGHT))

func forces() -> Dictionary:
	var frame := CONTRACT.boom_transform(yaw,pitch)
	var key := frame*CONTRACT.VANG_KEY_LOCAL
	var vang_vector := key-CONTRACT.VANG_BASE_LOCAL
	var cascade := VANG.evaluate(vang_vector.length(),vang_tail)
	if not cascade.valid: return {"valid":false,"reason":"cascade material bounds"}
	var sheet := sheet_geometry()
	var sheet_extension := maxf(0,sheet.length-sheet_rest)
	var sheet_force := 0.0 if external_sheet_constraint else sheet_extension*SHEET_STIFFNESS
	if external_sheet_constraint: sheet_extension=0.0
	var aft_force: Vector3 = -sheet.aft_leg.normalized()*sheet_force*2
	var forward_force: Vector3 = -sheet.fore_leg.normalized()*sheet_force
	var vang_force: Vector3 = -vang_vector.normalized()*cascade.boom_tension_n
	var clew := frame*CONTRACT.CLEW_LOCAL
	var bending: Dictionary=MAST.evaluate(mast_tip)
	if not bending.valid: return bending
	var head: Vector3=bending.point
	var leech := clew-head
	var leech_extension := maxf(0,leech.length()-LEECH_REST)
	var leech_force := -leech.normalized()*leech_extension*LEECH_STIFFNESS
	var center := frame*Vector3(0,1.5,1.15)
	var apparent := apparent_wind_at(center)
	var rig_velocity := Vector3.UP.cross(center-CONTRACT.GOOSE)*angular_velocity.x+(Basis(Vector3.UP,yaw)*Vector3.RIGHT).cross(center-frame.origin)*angular_velocity.y
	apparent -= rig_velocity
	var normal := Basis(Vector3.UP,yaw)*Vector3.RIGHT
	# Normal-pressure plate approximation; not an ILCA polar or cloth solver.
	var normal_speed := apparent.dot(normal)
	var aerodynamic := normal*(.5*1.225*AREA*normal_speed*absf(normal_speed))
	var center_mass := frame*Vector3(0,0,CONTRACT.BOOM_LENGTH*.5)
	var gravity_force := effective_gravity()*BOOM_MASS
	# A provisional two-support load split keeps total pressure force single.
	# Tip bending and leech tension solve together; trim never sets bend directly.
	var tip_force := -leech_force+aerodynamic*.55
	# The vertical tip load does work through geometric shortening as well.
	var mast_force: Vector2=Vector2(tip_force.x,tip_force.z)+bending.vertical_gradient*tip_force.y-MAST_TIP_STIFFNESS*mast_tip
	var moment := _moment_at(sheet.aft,aft_force)+_moment_at(sheet.forward,forward_force)+_moment_at(key,vang_force)+_moment_at(clew,leech_force)+_moment_at(center,aerodynamic*.45)+_moment_at(center_mass,gravity_force)+extra_moment
	return {"valid":moment.is_finite(),"moment":moment,"cascade":cascade,
		"sheet_tension_n":sheet_force,"sheet_slack_m":maxf(0,sheet_rest-sheet.length),"sheet_route_m":sheet.length,
		"leech_tension_n":leech_extension*LEECH_STIFFNESS,"leech_length_m":leech.length(),
		"apparent_wind":apparent,"gravity_boat":effective_gravity(),"aerodynamic_force":aerodynamic,
		"mast_force":mast_force,"head":head,"clew":clew,"key":key,
		"mast_spring_reaction":Vector3(mast_tip.x,0,mast_tip.y)*MAST_TIP_STIFFNESS,
		"elastic_energy_j":cascade.elastic_energy_j+.5*SHEET_STIFFNESS*sheet_extension*sheet_extension+.5*LEECH_STIFFNESS*leech_extension*leech_extension+.5*MAST_TIP_STIFFNESS*mast_tip.length_squared(),
		"kinetic_energy_j":.5*(INERTIA*angular_velocity*angular_velocity).dot(Vector2.ONE)+.5*MAST_TIP_MASS*mast_velocity.length_squared()}

static func crew_gravity_moment(mass_kg: float,center_of_mass: Vector3,gravity_boat: Vector3) -> Vector3:
	# Return this to the hull solver; do not add it as a direct vang torque.
	if not is_finite(mass_kg) or mass_kg<0 or not center_of_mass.is_finite() or not gravity_boat.is_finite(): return Vector3.ZERO
	return center_of_mass.cross(gravity_boat*mass_kg)

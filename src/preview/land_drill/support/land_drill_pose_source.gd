extends Resource

const LEGACY_HIKE := preload("res://src/boat/animation/hiking_port_source.tres")

## Boat-frame guides for offline land-drill authoring. Playback uses tracks.
@export var seated_drop := .052369
@export var hips_offset := Vector3(-.30,.063,0)
@export var torso_lean_degrees := 55.0
@export var seated_palm_guide := Vector3(-.30,.80,.74)
@export var hiking_palm_guide := Vector3(-.78,.875,.74)
@export var grip_range := Vector2(.65,1.215)
@export var seated_elbow := Vector3(-.20,.80,1.80)
@export var hiking_elbow := Vector3(-.80,.70,1.50)
@export var sheet_ready := Vector3(-.23,.78,.47)
@export var hiking_sheet := Vector3(-.87,.66,.49)
@export var foot_x := -.105
@export var foot_y := Vector2(.146,.170)
@export var sheet_low_elbow := Vector3(.05,-.20,-.10)
@export var sheet_high := Vector3(-.25,.99,.82)
@export var sheet_high_steering_offset := Vector3(.11,.018,-.045)
@export var sheet_high_elbow := Vector3(-.10,.50,.05)
@export var sheet_shoulder_degrees := -25.0
@export var sheet_regrip_elbow := Vector3(-.45,.50,-.45)
@export var helper_lift := Vector3(.02,.046,.116)
@export var regrip_fraction := .66
@export var return_reach_window := Vector2(.12,.97)
@export var return_close_window := Vector2(.90,1.0)
@export var return_normal_lane := .18
@export var return_side_lane := .14
@export var helper_elbow := Vector3(-.30,1.40,1.30)
@export var catch_fraction := .83

func palm_at(amount: float,hike: float) -> Vector3:
	var h := clampf(hike,0,1)
	var joint := joint_at(amount)
	var seated := seated_palm_guide+Vector3(0,0,.02)*clampf(amount,-2,2)
	seated.y-=.095*smoothstep(1,2,amount)
	var hiked := hiking_palm_guide+Vector3(0,-.035,.04)*clampf(amount,0,2)
	var guide := seated.lerp(hiked,h)
	guide.y+=.035*sin(PI*h)
	var seated_radius := clampf((seated-joint).length(),grip_range.x,grip_range.y)
	var hiked_radius := clampf((hiked-joint).length(),grip_range.x,grip_range.y)
	var radial := lerpf(seated_radius,hiked_radius,h)
	return joint+(guide-joint).normalized()*radial

func _seated_guide(amount: float) -> Vector3:
	var edge := clampf(amount,-1,1)
	var palm: Vector3=LEGACY_HIKE.palm_at(edge,0)
	if absf(amount)<=1: return palm
	var direction := palm+Vector3(0,-.060,0)*clampf(amount-1,0,1)-joint_at(amount)
	return joint_at(amount)+direction.normalized()*grip_range.x

func elbow_at(amount: float,hike: float) -> Vector3:
	return seated_elbow.lerp(hiking_elbow,clampf(hike,0,1))+Vector3(-.06,0,.06)*clampf(amount,-2,2)

func sheet_at(hike: float) -> Vector3:
	return sheet_ready.lerp(hiking_sheet,clampf(hike,0,1))

func sheet_high_at(amount: float) -> Vector3:
	return sheet_high+sheet_high_steering_offset*smoothstep(1,2,amount)

func foot_at(side: String,hike: float) -> Vector3:
	return Vector3(foot_x,lerpf(foot_y.x,foot_y.y,smoothstep(.05,.42,clampf(hike,0,1))),.50 if side=="Left" else .74)

func pitch_at(amount: float,hike: float) -> float:
	var reach_lean := torso_lean_degrees-24*smoothstep(-.3,-2,amount)
	return deg_to_rad(lerpf(-3.0*clampf(amount,-2,2),-reach_lean,clampf(hike,0,1)))

static func joint_at(amount: float) -> Vector3:
	return Vector3(0,0,2.171)+Basis(Vector3.UP,amount*deg_to_rad(12))*Vector3(0,.352952,-.979058)

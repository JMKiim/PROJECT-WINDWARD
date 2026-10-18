extends "res://src/preview/tack/controller.gd"
const GYBE_BOOM := preload("res://src/preview/gybe/boom.gd")
const PRACTICE_PULL_METRES := .30
var gybing := false
var trim_low := 0.0
var trim_at_cross := 0.0
func is_gybe() -> bool: return gybing
func action_name() -> String: return "자이빙" if gybing else "태킹"
func manual_trim_stage() -> bool: return phase in ["TRIM","EASE"]
func request() -> bool:
	if busy(): return false
	gybing=false
	return super.request()
func request_gybe() -> bool:
	if phase=="TRIM":
		if lab.session.wheel_pull.metres-trim_low<PRACTICE_PULL_METRES-.000001:
			lab.session.notice="자이빙 준비 · W/휠↓로 약30cm 당긴 뒤 G로 붐을 넘겨 주세요. 필요하면 S로 먼저 풀 수 있어요."
			return false
		phase="IDLE"
		if not super.request(): phase="TRIM"; return false
		trim_at_cross=retained_trim
		lab.session.notice="자이빙 · 당긴 트림을 지지하며 몸과 붐을 넘길 준비를 해요."
		return true
	if phase=="EASE":
		if trim_at_cross-lab.session.wheel_pull.metres<PRACTICE_PULL_METRES-.000001:
			lab.session.notice="새 현에서 S/휠↑로 약30cm 풀고 G로 연습을 마쳐 주세요."
			return false
		lab.session.wheel_pull.pause()
		cancel()
		lab.session.notice="자이빙 연습 완료 · 현재 트림을 유지하며 자유 조작할 수 있어요."
		return true
	if busy(): return false
	if lab.session.reference_fixture or lab.session.selected_system!=0:
		lab.session.notice="메인시트 수동 조작 상태에서 시작해 주세요."
		return false
	gybing=true
	source_side=actor.seat_side
	phase="TRIM"
	trim_low=lab.session.wheel_pull.metres
	gaze_weight=1
	lab.session.wheel_pull.pause()
	lab.session.request_hike(0)
	_trim_notice()
	return true
func advance(delta: float) -> void:
	if not is_finite(delta) or delta<=0: return
	if manual_trim_stage():
		trim_low=minf(trim_low,float(lab.session.wheel_pull.metres))
		_trim_notice()
		return
	var previous: String=phase
	super.advance(delta)
	if not gybing: return
	if previous=="POST" and phase=="IDLE":
		phase="EASE"
		gaze_weight=1
		_trim_notice()
	else: lab.session.notice=lab.session.notice.replace("태킹","자이빙")
func _trim_notice() -> void:
	var metres: float=lab.session.wheel_pull.metres
	if phase=="TRIM":
		var pull: float=maxf(0,metres-trim_low)
		lab.session.notice="자이빙 준비 · 당김 %.0fcm (최소30cm) · W/S·휠 조절 · G 붐 넘기기 · Backspace 취소"%(pull*100)
	else:
		var eased: float=maxf(0,trim_at_cross-metres)
		lab.session.notice="자이빙 도착 · 풀기 %.0fcm (최소30cm) · S/휠↑ 조절 · G 완료 · Backspace 종료"%(eased*100)
func _prescribed_yaw() -> float:
	if not gybing: return super._prescribed_yaw()
	var travel: float=completion_fraction()
	var start: float=initial_yaw if source_side==-1 else end_yaw
	var target: float=end_yaw if source_side==-1 else initial_yaw
	return GYBE_BOOM.yaw(start,target,travel)
func leave_trim_stage() -> void:
	if not manual_trim_stage(): return
	lab.session.wheel_pull.pause()
	cancel()
	lab.session.notice="자이빙 연습 종료 · 현재 현과 트림은 그대로예요."
func cancel() -> void:
	super.cancel()
	gybing=false
	trim_low=0
	trim_at_cross=0

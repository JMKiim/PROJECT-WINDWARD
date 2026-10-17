extends RefCounted
const CLOCK := preload("res://src/preview/tack/clock.gd")
const MOVE_SECONDS := 5.25
const GRIP_SECONDS := .12
const RELEASE_SECONDS := .12
const DURATION := MOVE_SECONDS+GRIP_SECONDS+RELEASE_SECONDS
static func time_for(u: float) -> float:
	return (MOVE_SECONDS*CLOCK.clock(u)+(GRIP_SECONDS+RELEASE_SECONDS if u>=.5 else 0.0))/DURATION
static func state(t: float) -> Dictionary:
	var seconds: float=clampf(t,0,1)*DURATION
	var grip_at: float=MOVE_SECONDS*CLOCK.clock(.5)
	var release_at: float=grip_at+GRIP_SECONDS
	if seconds<grip_at:
		return {"u":CLOCK.phase(seconds/MOVE_SECONDS),"left_open":0.0,"right_open":0.0,"stage":"MOVE","released":false}
	if seconds<grip_at+GRIP_SECONDS:
		return {"u":.5,"left_open":.85*(1-smoothstep(0,GRIP_SECONDS,seconds-grip_at)),"right_open":0.0,"stage":"GRIP","released":false}
	if seconds<release_at:
		return {"u":.5,"left_open":0.0,"right_open":0.0,"stage":"MOVE","released":false}
	if seconds<release_at+RELEASE_SECONDS:
		return {"u":.5,"left_open":0.0,"right_open":.85*smoothstep(0,RELEASE_SECONDS,seconds-release_at),"stage":"RELEASE","released":true}
	return {"u":CLOCK.phase((seconds-GRIP_SECONDS-RELEASE_SECONDS)/MOVE_SECONDS),"left_open":0.0,"right_open":.85,"stage":"MOVE","released":true}

extends RefCounted

## An inextensible planar bending mode above the gooseneck. Horizontal shape
## is prescribed by the modal displacement; vertical shortening follows arc
## length, rather than keeping the sail head at its unloaded height.
## Stiffness remains the provisional reduced-rig material, not a measured spar.
const CONTRACT := preload("res://src/boat/rigging_contract.gd")
const LENGTH := CONTRACT.SAIL_HEAD.y-CONTRACT.GOOSE.y
# Modal slope stays below 0.75 here; this is a model domain, not a joint stop.
const MAX_DISPLACEMENT := LENGTH*.5
const PANELS := 32

static func evaluate(displacement: Vector2,fraction := 1.0) -> Dictionary:
	# Compare in the same component precision as the stored modal coordinate.
	var component_limit := Vector2(MAX_DISPLACEMENT,0).x
	if not displacement.is_finite() or displacement.length()>component_limit or not is_finite(fraction) or fraction<0 or fraction>1:
		return {"valid":false,"reason":"outside inextensible mast mode"}
	var rise := 0.0
	var derivative := 0.0
	var step: float=fraction/PANELS
	var radius_squared := displacement.length_squared()/(LENGTH*LENGTH)
	for index in PANELS+1:
		var t := index*step
		var slope := 3*t-1.5*t*t
		var vertical := sqrt(maxf(0,1-radius_squared*slope*slope))
		var weight := 1.0 if index==0 or index==PANELS else (4.0 if index%2==1 else 2.0)
		rise+=weight*vertical
		derivative+=weight*slope*slope/vertical
	rise*=LENGTH*step/3.0
	var shape := fraction*fraction*(1.5-.5*fraction)
	return {"valid":true,"point":Vector3(displacement.x*shape,CONTRACT.GOOSE.y+rise,CONTRACT.MAST_BASE.z+displacement.y*shape),"vertical_gradient":-displacement*(step/(3*LENGTH))*derivative,"shape":shape}

static func point_at(displacement: Vector2,height: float) -> Vector3:
	if height<=CONTRACT.GOOSE.y: return Vector3(0,height,CONTRACT.MAST_BASE.z)
	var fraction := clampf((height-CONTRACT.GOOSE.y)/LENGTH,0,1)
	var value := evaluate(displacement,fraction)
	if not value.valid: return Vector3(NAN,NAN,NAN)
	return value.point+Vector3.UP*maxf(0,height-CONTRACT.SAIL_HEAD.y)

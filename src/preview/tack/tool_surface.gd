extends RefCounted
## Surface-calibrated contact datum for the actual11mm carbon,14mm foam
## and15mm grip ribs. The anatomical wrist-cone direction is NOT changed.
const G := [.565,.570,.575,.580,.605,.610,.615]
const Z := [.03925,.03975,.04175,.04250,.04250,.04275,.04300]
static func offset(grip: float) -> Vector3:
	if grip<=G[0]: return Vector3(0,.096,Z[0])
	for index in G.size()-1:
		if grip<=G[index+1]:
			return Vector3(0,.096,lerpf(Z[index],Z[index+1],inverse_lerp(G[index],G[index+1],grip)))
	return Vector3(0,.096,.043)

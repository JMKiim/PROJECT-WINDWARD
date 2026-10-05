extends "res://src/boat/animation/sheet_stroke_player.gd"

## Palm support is separate from the finger-bone supports. A loose strand
## must not return through the palm after leaving the authored grip channel.
func palm_supports() -> Array:
	var supports := []
	for side in [actor.sheet_hand(),actor.tiller_hand()]:
		var hand: Transform3D=actor.bone_pose_boat(side+"Hand")
		var scale := hand.basis.x.length()
		for row in [.035,.065]:
			supports.append([hand*Vector3(-.025,row,.004),hand*Vector3(.025,row,.004),.028*scale+GRIP.SHEET_RADIUS+.001])
		# The wrist is narrower than the palm: the former 60 mm segment plus
		# 31 mm caps made a 122 mm-wide obstacle around a roughly 70 mm wrist.
		# Use the mirrored short wrist section measured on the actual skin.
		# Rope radius and contact clearance remain unchanged; mesh tests guard
		# the boundary independently of this runtime collision approximation.
		var handed := -1.0 if side=="Left" else 1.0
		supports.append([hand*Vector3(0,-.016,.003),hand*Vector3(.029*handed,.010,.005),.026*scale+GRIP.SHEET_RADIUS+.001])
	return supports

func _tail_supports() -> Array:
	var result := super._tail_supports()
	result.append_array(palm_supports())
	# A free strand remains outside the combined palm/folded-finger shell.
	# The loaded channel is deliberately NOT projected against this shell:
	# it lies inside the real grip, whereas the free outlet is outside it.
	for side in [actor.sheet_hand(),actor.tiller_hand()]:
		var hand: Transform3D=actor.bone_pose_boat(side+"Hand")
		result.append([hand*Vector3(0,.012,.030),hand*Vector3(0,.080,.030),.0585*hand.basis.x.length()+GRIP.SHEET_RADIUS+.001])
	return result

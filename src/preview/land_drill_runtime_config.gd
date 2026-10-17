extends RefCounted
## Authored training resources with pinned publication identities.
const BANK := "res://src/boat/animation/land_drill/pose_bank.res"
const BASE := "res://src/boat/animation/land_drill/base_pose_bank.res"
const FEED := "res://src/boat/animation/land_drill/remote_feed.res"
const ENVELOPE := "res://src/boat/animation/land_drill/calibrated_length_envelope.tres"
const TACK := "res://src/boat/animation/land_drill/tack_contact.res"
const TACK_HAND_FRAMES := "res://src/boat/animation/land_drill/tack_hand_frames.res"
const TACK_HAND_APPROACH := "res://src/boat/animation/land_drill/tack_hand_approach.res"
const SIGNATURES := {
	BANK:"6589aa47252a2762725c97d4bf8fd9011a2673bd32e52b803c5844bf8d5e2ae4",
	BASE:"96b95e3e64d4da63e33deac35015032dc9891c60fa6e0eba0816f31a089dfb24",
	FEED:"511787b3cf31483eb2836e755bb6caab8d57692a21d5d90ef164bfd7a39faf51",
	ENVELOPE:"c9e9b842674a1ee57ddc82096b7a2d0c9bdea78a754f5149a000e670cb458f2b",
	TACK:"f3ad00a612bf4c4184a99e54e19f65b5d9bc0b820bb477ed97b9593685280351",
	TACK_HAND_FRAMES:"e184d87fb974689df8d5d1db10debde8ec0e3b254c07c1172553138d3d6fc12c",
	TACK_HAND_APPROACH:"c5105887c2af2acfb4538103d705c8c5becf9921189c46fe5d618a3d76e30dbd",
}
static func resources_error(expected: Dictionary=SIGNATURES) -> String:
	for path: String in expected:
		if not FileAccess.file_exists(path): return "필요한 자료가 없습니다: "+path.get_file()
		if FileAccess.get_sha256(path)!=expected[path]: return "자료가 기록된 버전과 다릅니다: "+path.get_file()
	return ""

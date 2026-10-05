extends RefCounted
## Authored training resources with pinned publication identities.
const BANK := "res://src/boat/animation/land_drill/pose_bank.res"
const BASE := "res://src/boat/animation/land_drill/base_pose_bank.res"
const FEED := "res://src/boat/animation/land_drill/remote_feed.res"
const ENVELOPE := "res://src/boat/animation/land_drill/length_envelope.tres"
const SIGNATURES := {
	BANK:"6589aa47252a2762725c97d4bf8fd9011a2673bd32e52b803c5844bf8d5e2ae4",
	BASE:"96b95e3e64d4da63e33deac35015032dc9891c60fa6e0eba0816f31a089dfb24",
	FEED:"511787b3cf31483eb2836e755bb6caab8d57692a21d5d90ef164bfd7a39faf51",
	ENVELOPE:"9d3a7329e05d0b53bf3a05f2660de5600fea7ca07585eaf7ce4fb5c2a7a97693",
}
static func resources_error(expected: Dictionary=SIGNATURES) -> String:
	for path: String in expected:
		if not FileAccess.file_exists(path): return "필요한 자료가 없습니다: "+path.get_file()
		if FileAccess.get_sha256(path)!=expected[path]: return "자료가 기록된 버전과 다릅니다: "+path.get_file()
	return ""

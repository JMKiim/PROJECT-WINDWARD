extends RefCounted

## Separate elevated handover bank; original seated and first hike candidates remain untouched.
const LEVELS := 9
const EXTENSION_TUBE_METRES := 1.25
const EXTENSION_JOINT_METRES := .030
const EXTENSION_SPAN := EXTENSION_TUBE_METRES+EXTENSION_JOINT_METRES
const END_HAND_MARGIN := .060

static func path(level: int) -> String:
	return "res://src/boat/animation/hiking_sheet_lifted_%02d.res" % level

static func feed_path(level: int) -> String:
	return "res://src/boat/animation/hiking_sheet_feed_%02d.tres" % level

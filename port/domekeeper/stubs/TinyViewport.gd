extends SubViewport
## Put by PortTweaks on BundleResourceTracker's viewport, which its script sizes to the whole map
## although only the Assessor keeper uses it. Every size the game sets is kept at 2x2 instead, so
## the map sized render target is never allocated; PortTweaks gives it the map size (with
## _applying set) when an Assessor is in the run.

var _applying := false

func _set(property: StringName, value: Variant) -> bool:
	if _applying or property != &"size" or not (value is Vector2i or value is Vector2):
		return false
	_applying = true
	size = Vector2i(2, 2)
	_applying = false
	return true

extends SubViewport
## Put on the map's effect layers by PortTweaks. When the game sets the layer's size (Map.gd sizes
## them to the map), half that size is applied instead, so the render target is never allocated at
## full size: Godot allocates it on every size change, and the Mali vendor driver keeps memory it
## once allocated. Each axis separately, since Map.gd sets only the width of ViewportTopEffects.
## PortTweaks scales the canvas and the sprites that show the layer. For a layer that already has
## a script of the game's, PortTweaks makes a subclass of that script with this code.

var _applying := false

func _set(property: StringName, value: Variant) -> bool:
	if _applying or property != &"size" or not (value is Vector2i or value is Vector2):
		return false
	var wanted := Vector2i(value)  # Map.gd passes a Vector2
	var full: Vector2i = get_meta("port_full", size)
	var half: Vector2i = get_meta("port_half", Vector2i(-1, -1))
	if wanted.x != half.x:
		full.x = wanted.x
	if wanted.y != half.y:
		full.y = wanted.y
	half = (full + Vector2i.ONE) / 2 if full.x >= 64 else full
	set_meta("port_full", full)
	set_meta("port_half", half)
	_applying = true
	size = half
	_applying = false
	return true

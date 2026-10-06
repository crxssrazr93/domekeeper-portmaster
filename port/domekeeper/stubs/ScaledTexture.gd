extends ImageTexture
## A texture stored at reduced resolution that reports its original size, so sprite
## regions, frame grids and tile atlases (all in original pixel units) keep working.
## Godot does not save ImageTexture's size override, so it is reapplied from display_size.

@export var display_size := Vector2i.ZERO:
	set(value):
		display_size = value
		_apply()

func _apply() -> void:
	if display_size != Vector2i.ZERO and get_width() > 0:
		set_size_override(display_size)

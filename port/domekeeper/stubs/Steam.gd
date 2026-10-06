extends Node
## Compile-time stand-in for the GodotSteam singleton. Dome Keeper only enables its Steam
## code when Engine.has_singleton("Steam") is true, which stays false with this autoload,
## so these members exist purely so the scripts that mention them compile.

const OVERLAY_TO_STORE_FLAG_NONE := 0

func setItemPreview(_update_handle, _preview_path) -> bool: return false

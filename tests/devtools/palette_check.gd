extends SceneTree
# Scaled index-art textures may only use colours that exist in the original image.
func _colors(img: Image) -> Dictionary:
	var d := {}
	img = img.duplicate(); if img.is_compressed(): img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.a > 0.99: d[c.to_rgba32()] = 1
	return d
func _init():
	var bad := 0; var checked := 0
	for p in ["res://content/monster/scarab/sheet.png", "res://content/monster/driller/largesheet.png", "res://content/monster/worm/sheet.png", "res://content/keeper/keeper2/player4_supersheet.png", "res://content/monster/stag/sheet.png", "res://content/gadgets/drillbot/drillbot-Sheet.png", "res://content/monster/bolter/sheet.png"]:
		var scaled: Texture2D = load(p)
		var orig_path: String = ""
		for l in FileAccess.get_file_as_string("res://devtools/orig_paths.txt").split("\n"):
			if l.begins_with(p + " "): orig_path = l.get_slice(" ", 1)
		var orig: Texture2D = ResourceLoader.load(orig_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var oc := _colors(orig.get_image()); var sc := _colors(scaled.get_image())
		var extra := 0
		for c in sc: if not oc.has(c): extra += 1
		checked += 1; if extra: bad += 1
		print("PAL %s orig=%dx%d scaled=%dx%d colors=%d new_colors=%d" % [p.get_file(), orig.get_width(), orig.get_height(), scaled.get_image().get_width(), scaled.get_image().get_height(), oc.size(), extra])
	print("PAL checked=%d with_new_colors=%d" % [checked, bad])
	quit()

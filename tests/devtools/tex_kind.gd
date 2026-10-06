extends SceneTree
func _init():
	for p in ["res://content/monster/scarab/sheet.png", "res://content/keeper/keeper2/player4_supersheet.png", "res://content/worlds/world1/BG3.png", "res://stages/title/titlescreen.png", "res://content/map/tiles.png", "res://content/gadgets/drillbot/drillbot-Sheet.png", "res://content/shared/explosions/explosions-Sheet_rough.png"]:
		var img: Image = (ResourceLoader.load(p.replace("res://", "res://"), "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D).get_image()
		if img.is_compressed(): img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var colors := {}; var g_nonzero := 0; var opaque := 0; var on_grid := 0
		var step := maxi(1, img.get_width() * img.get_height() / 200000)
		var i := 0
		for y in img.get_height():
			for x in img.get_width():
				i += 1
				if i % step: continue
				var c := img.get_pixel(x, y)
				if c.a < 0.5: continue
				opaque += 1
				colors[c.to_rgba32()] = 1
				if c.g8 != 0: g_nonzero += 1
				var r := c.r * 32.0; var b := c.b * 12.0
				if absf(r - roundf(r)) < 0.06 and absf(b - roundf(b)) < 0.06: on_grid += 1
		print("KIND %s colors=%d opaque=%d g_nonzero=%.2f r/b_on_palette_grid=%.2f" % [p.get_file(), colors.size(), opaque, float(g_nonzero) / maxi(1, opaque), float(on_grid) / maxi(1, opaque)])
	quit()

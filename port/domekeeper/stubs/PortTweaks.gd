extends Node
## PortMaster tweaks for small handheld screens and 1 GB devices. Added as an autoload by
## setup/port_setup.gd. Environment overrides: DK_UI_SCALE and DK_WORLD_ZOOM (numbers, 0 =
## automatic).

## The title screen keeps hidden patch notes and credits panels whose labels hold the full
## changelog and credits. Hidden, the panels are ~0 px wide, so every character wraps onto its
## own line and Godot keeps shaping data for each one. setup/port_setup.gd moves that text into
## "port_text" metadata in the saved scene; it is put back only while a panel is shown. Labels
## the setup could not reach are emptied here as they enter the tree.
const DEFERRED_TEXT_PANELS := ["PatchNotesPanel", "CreditsPanel"]

## Intro stage backgrounds that must cover the whole screen (see _cover_intro_background)
const INTRO_BACKGROUNDS := ["Background", "Background2"]

## CJK fonts (about 36 MB of font data) are preloaded by the game's scripts for every language.
## setup/port_setup.gd points them at small stand-ins that remember the real file; when the
## language needs them, the real data is loaded into the same objects, so every reference the
## game already holds picks it up.
const CJK_FONTS := [
	"res://gui/fonts/ja/Noto Sans Mono CJK JP Regular.otf",
	"res://gui/fonts/simplified chinese/NotoSansSC-Regular.otf",
	"res://gui/fonts/traditional chinese/NotoSansTC-Regular.otf",
	"res://gui/fonts/noto/NotoSansTC-Regular.otf",
	"res://gui/fonts/korean/NotoSansKR-Regular.otf",
	"res://gui/fonts/ja/Makinas-4-Flat.otf",
	"res://gui/fonts/ja/Makinas-4-Square.otf",
	"res://gui/fonts/ja/Senobi-Gothic-Regular.ttf",
	"res://gui/fonts/ja/Senobi-Gothic-Medium.ttf",
	"res://gui/fonts/ja/Senobi-Gothic-Bold.ttf",
]
const CJK_LOCALES := ["ja", "ko", "zh"]
var _cjk_loaded := false

## Every map carries a map-sized render target (7 MB on a small map, ~22 MB on a huge one) for
## the Assessor's bundle effect. It stays 2x2 unless an Assessor (keeper2) is playing.
const BUNDLE_TRACKER := "BundleResourceTracker"
const BUNDLE_KEEPER := "keeper2"
var _bundle_trackers: Array[Node] = []

## The map renders its rock paint, crack impacts, lights, background alpha and top effects into
## map-sized render targets at one pixel per world unit (3024x936 in the singleplayer lobby). The
## screen shows the world at a third of that on 640x480, so they are rendered at half size.
## HalfViewport.gd (put on each layer as it enters the tree) applies half of the sizes the game
## sets through untyped access, so those render targets are never allocated at full size; the
## others are halved right before the frame that would first draw them. On Mali a render target
## costs about 4.5 times its colour pixels and the vendor driver keeps memory it once allocated. Once a layer
## has its map size, its canvas is scaled by 1/2, so everything drawn into it keeps its world
## coordinates, and the sprites that show it are scaled by 2. Shaders read them by UV, which does
## not change. Map.addSpriteToBGAlpha places sprites in the background alpha layer at an offset of
## size.x / 2, which with the halved size is a quarter of the full width short; the canvas
## transform adds that back (full width / 8 after scaling), and sprites placed while the layer was
## still full size are moved to the same convention.
const HALF_RES_LAYERS := {
	"ViewportRocks": ["BackgroundRender/BackgroundSprite", "TileRender/MainStones"],
	"ViewportCrackImpact": [],
	"ViewportLights": ["LightSprite"],
	"ViewportBackgroundAlpha": [],
	"ViewportTopEffects": ["PixelatedEffects"],
}
var _layers: Array[SubViewport] = []
const HALF_VIEWPORT: GDScript = preload("res://stubs/HalfViewport.gd")
const TINY_VIEWPORT: GDScript = preload("res://stubs/TinyViewport.gd")
var _sub_scripts := {}  # [game script, port script] -> subclass of the game's with the port's code

## The port's viewport script for a node without a script; for one with a script of the game's
## (ViewportRocks, MapLights), a subclass of that script with the same code, so the game's code
## keeps working
func _viewport_script(current: Script, code: GDScript) -> Script:
	if current == null:
		return code
	if current == code or _sub_scripts.values().has(current):
		return current
	var key := [current, code]
	if not _sub_scripts.has(key):
		var sub := GDScript.new()
		sub.source_code = 'extends "%s"\n' % current.resource_path + code.source_code.substr(code.source_code.find("\n"))
		_sub_scripts[key] = sub if sub.reload() == OK else null
	return _sub_scripts[key] if _sub_scripts[key] else current

## The map's rock and cave background layers are drawn by two big per-pixel shaders, and the
## single core Mali G31 of h700 devices spends most of a frame on them (mine at 640x480: about
## 20 fps). Their code is patched here as it is loaded; the game files are not changed, and a
## patch whose expected code is missing (another game version) is skipped. Measured on an
## RG35XX H in the mine of a small map: 19-22 fps before, 28-30 after while mining (33 standing).
##
## map_main_stones_new (rock):
## * noise() builds two value noises per pixel from eight sin() hashes each. The lattice values
##   never change, so they are computed once into a 256x256 tile (_noise_tile), and noise()
##   reads it at the smoothstep-shifted position, where the hardware bilinear filter does the
##   same smoothstep interpolation. The tile repeats every 256 lattice cells (about 1900 world
##   units), invisible in the edge jitter it drives.
## * Unrevealed rock (rock falloff at or below the game's own 0.01 threshold) only shows the depth
##   gradient: no stone paint, and outlines and damage only occur next to tunnels, which are
##   always revealed. The falloff, cutout and gradient are computed first and the outline and
##   damage work (about 20 texture reads) is skipped there.
## map_background_edges (cave background): visible only where the tunnel mask is open, so its
## alpha is computed first and the rest skipped where it is 0 (exact: such pixels are not blended).
const STONES_SHADER := "res://content/map/shaders/map_main_stones_new.gdshader"
const EDGES_SHADER := "res://content/map/shaders/map_background_edges.gdshader"
const NOISE_TILE := 256
const NOISE_ORIGINAL := "753.5453123*sin(n + vec4(0., 1., 157., 158.))"
const NOISE_PATCHED := """uniform sampler2D port_noise : repeat_enable, filter_linear;
float noise(vec2 x) {
	vec2 p = floor(x);
	vec2 f = fract(x);
	f = f*f*(3.-2.*f);
	return texture(port_noise, (p + f + 0.5) / 256.0).r;
}"""
const STONES_FALLOFF := ["\t// Main big noise", "\t// The color of the Lightedge"]
const STONES_CUTOUT := ["\t// Tunnel cutout is used", "\t// Generate the \"shadow\" fadeout"]
const STONES_GRADIENT := ["\t// Background Gradient", "\tCOLOR.rgb = mix(grad_color"]
const STONES_OUTLINES := "\t// Light Catcher outline"
const STONES_EARLY_OUT := """	if (mixed_falloff <= 0.01) {
		COLOR = vec4(grad_color, tunnel_cutout);
	} else {
"""
const EDGES_ALPHA := "COLOR.a = max(abs(1.0-step(texture(mask_map, UV).r, alpha_edge_pos)) - step(0.99, alpha_px), 0.0);"
const EDGES_ALPHA_PX := "float alpha_px = texture(bg_alpha_map, UV).r;"
const EDGES_EARLY_OUT := """	float port_alpha = max(abs(1.0-step(texture(mask_map, UV).r, alpha_edge_pos)) - step(0.99, texture(bg_alpha_map, UV).r), 0.0);
	if (port_alpha <= 0.0) {
		COLOR = vec4(0.0);
	} else {
"""
const FRAGMENT_HEAD := "void fragment() {\n"
var _patched_shaders: Array[Shader] = []  # held so the patched shaders stay in the resource cache

func _patch_map_shaders() -> void:
	for path in [STONES_SHADER, EDGES_SHADER]:
		if not ResourceLoader.exists(path):
			continue
		var shader: Shader = load(path)
		var code := patch_stones_code(shader.code) if path == STONES_SHADER else patch_edges_code(shader.code)
		if code == "":
			continue
		shader.code = code
		if path == STONES_SHADER:
			shader.set_default_texture_parameter("port_noise", _noise_tile())
		_patched_shaders.append(shader)

## The patched rock shader, or "" when the code is not the one these patches were written for.
static func patch_stones_code(code: String) -> String:
	var start := code.find("float noise(vec2 x) {")
	var end := code.find("\n}\n", start)
	if start < 0 or end < 0 or not NOISE_ORIGINAL in code.substr(start, end - start):
		return ""
	code = code.substr(0, start) + NOISE_PATCHED + code.substr(end + 2)
	# early-out: needs every block exactly once, in the original order
	var blocks := []
	for markers in [STONES_FALLOFF, STONES_CUTOUT, STONES_GRADIENT]:
		var from := code.find(markers[0])
		var to := code.find(markers[1], from)
		if from < 0 or to < 0 or code.count(markers[0]) != 1:
			return code
		blocks.append([from, to])
	var outlines := code.find(STONES_OUTLINES)
	if outlines < 0 or not (outlines < blocks[0][0] and blocks[0][1] <= blocks[1][0] and blocks[1][1] <= blocks[2][0]):
		return code
	var moved := ""
	for i in range(blocks.size() - 1, -1, -1):  # cut from the back so earlier offsets stay valid
		moved = code.substr(blocks[i][0], blocks[i][1] - blocks[i][0]) + moved
		code = code.substr(0, blocks[i][0]) + code.substr(blocks[i][1])
	code = code.insert(outlines, moved + STONES_EARLY_OUT)
	var last := code.rfind("}")
	return code.substr(0, last) + "\t}\n" + code.substr(last)

## The patched cave background shader, or "" when the code is not the expected one.
static func patch_edges_code(code: String) -> String:
	var start := code.find(FRAGMENT_HEAD)
	if start < 0 or code.count(FRAGMENT_HEAD) != 1 or not EDGES_ALPHA in code or not EDGES_ALPHA_PX in code:
		return ""
	start += FRAGMENT_HEAD.length()
	var end := code.rfind("}")
	return code.substr(0, start) + EDGES_EARLY_OUT + code.substr(start, end - start) + "\t}\n" + code.substr(end)

## Lattice value of the original noise() at n = x + 157 y + 113: the mean of
## fract(753.5453123 sin(n)) and the same at n + 113.
func _noise_tile() -> ImageTexture:
	var data := PackedByteArray()
	data.resize(NOISE_TILE * NOISE_TILE)
	for y in NOISE_TILE:
		for x in NOISE_TILE:
			var n := float(x + 157 * y + 113)
			var a := 753.5453123 * sin(n)
			var b := 753.5453123 * sin(n + 113.0)
			data[y * NOISE_TILE + x] = int(round(((a - floor(a)) + (b - floor(b))) * 127.5))
	return ImageTexture.create_from_image(Image.create_from_data(NOISE_TILE, NOISE_TILE, false, Image.FORMAT_L8, data))

func _needs_cjk(locale: String) -> bool:
	return locale.get_slice("_", 0) in CJK_LOCALES

func _process(_delta: float) -> void:
	if Engine.get_process_frames() % 30 != 0:
		return
	if not _cjk_loaded and _needs_cjk(TranslationServer.get_locale()):
		_load_cjk_fonts()
	_update_bundle_trackers()

func _update_bundle_trackers() -> void:
	_bundle_trackers = _bundle_trackers.filter(func(t): return is_instance_valid(t))
	if _bundle_trackers.is_empty():
		return
	var needed := _assessor_playing()
	for tracker in _bundle_trackers:
		var viewport: SubViewport = tracker.get_node_or_null("SubViewport")
		var map = tracker.owner
		if viewport == null or map == null or not ("tilemap_size" in map) or not map.isMapReady():
			continue
		var full := Vector2i(map.tilemap_size * 24)  # GameWorld.TILE_SIZE
		if full.x < 8:
			continue
		var target := full if needed else Vector2i(2, 2)
		if viewport.size != target and (viewport.size == full or viewport.size == Vector2i(2, 2)):
			viewport.set("_applying", true)  # past TinyViewport's 2x2
			viewport.size = target
			viewport.set("_applying", false)

func _halve_map_layers() -> void:
	if _layers.is_empty():
		return
	_layers = _layers.filter(func(v): return is_instance_valid(v))
	for viewport in _layers:
		# Map.gd sets most layers through typed references, which HalfViewport's _set does not
		# see; those are halved here, before the frame that would first draw them. Each axis
		# separately, since only the width of ViewportTopEffects is set again.
		var half: Vector2i = viewport.get_meta("port_half", Vector2i(-1, -1))
		var full: Vector2i = viewport.get_meta("port_full", viewport.size)
		if viewport.size != half and viewport.size.x >= 64:
			if viewport.size.x != half.x:
				full.x = viewport.size.x
			if viewport.size.y != half.y:
				full.y = viewport.size.y
			half = (full + Vector2i.ONE) / 2
			viewport.set_meta("port_full", full)
			viewport.set_meta("port_half", half)
			viewport.set("_applying", true)
			viewport.size = half
			viewport.set("_applying", false)
			if viewport.name == "ViewportBackgroundAlpha" and not viewport.has_meta("port_scaled"):
				# sprites the map added while the layer was full size used the full-width offset
				var images := viewport.get_node_or_null("AlphaImages")
				for sprite in images.get_children() if images else []:
					if sprite is Node2D:
						sprite.position.x -= full.x / 4.0
		if full.x < 64 or viewport.size != half:
			continue
		if viewport.has_meta("port_scaled"):
			continue
		viewport.set_meta("port_scaled", true)
		var shrink := Transform2D().scaled(Vector2(0.5, 0.5))
		if viewport.name == "ViewportBackgroundAlpha":
			shrink.origin.x = full.x / 8.0
		viewport.canvas_transform = shrink * viewport.canvas_transform
		var map := viewport.get_parent()
		for path in HALF_RES_LAYERS[str(viewport.name)]:
			var shown := map.get_node_or_null(path)
			if shown is Node2D or shown is Control:
				shown.scale *= 2.0

func _assessor_playing() -> bool:
	var level := get_node_or_null("/root/Level")
	if level == null or not ("loadout" in level) or level.loadout == null:
		return true  # unknown: keep the effect
	for keeper in level.loadout.keepers:
		if keeper != null and "keeperId" in keeper and keeper.keeperId == BUNDLE_KEEPER:
			return true
	return false

func _load_cjk_fonts() -> void:
	_cjk_loaded = true
	for path in CJK_FONTS:
		if not ResourceLoader.exists(path):
			continue
		var font: FontFile = load(path)
		if not font.has_meta("port_real_path"):
			continue
		var real: FontFile = ResourceLoader.load(font.get_meta("port_real_path"), "", ResourceLoader.CACHE_MODE_IGNORE)
		if real == null:
			continue
		for prop in real.get_property_list():
			if prop.usage & PROPERTY_USAGE_STORAGE and not prop.name.begins_with("resource_"):
				font.set(prop.name, real.get(prop.name))
		font.remove_meta("port_real_path")

func _enter_tree() -> void:
	_patch_map_shaders()
	get_tree().node_added.connect(_on_node_added)
	RenderingServer.frame_pre_draw.connect(_halve_map_layers)
	_apply_ui_scale()
	get_tree().root.size_changed.connect(_apply_ui_scale)

## The game lays out its UI for 1920x1080 and canvas_items stretch shrinks it to fit, so on a
## 640x480 screen text is drawn at a third of its design size. Grow the UI so text is drawn at
## least at half its design size, as long as the screen still shows 1280x1080 design units (the
## options panel with its Cancel and Apply row is about 1040 units tall), and never below the
## game's own scale. Examples: 640x480 1.33, 480x320 1.19, 720x720 1.33, 16:9 screens 1.0.
## The level is drawn in its own SubViewport sized to the window, so the camera view is unchanged.
const DESIGN_SIZE := Vector2(1920, 1080)
const MIN_VISIBLE := Vector2(1280, 1080)
const TARGET_TEXT_SCALE := 0.5

func _apply_ui_scale() -> void:
	var win := get_tree().root
	var size := Vector2(win.size)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var base := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	var wanted := minf(TARGET_TEXT_SCALE, minf(size.x / MIN_VISIBLE.x, size.y / MIN_VISIBLE.y))
	var s := maxf(1.0, wanted / base)
	var env := OS.get_environment("DK_UI_SCALE")
	if env.is_valid_float() and env.to_float() > 0.0:
		s = env.to_float()
	if not is_equal_approx(win.content_scale_factor, s):
		win.content_scale_factor = s

## The world (lobby, mine, dome) and each player's HUD are drawn in the SubViewports of
## systems/camera/ViewportContainer.gd, whose size_2d_override holds the 1920x1080 design view;
## at 640x480 a world pixel at the game's camera zoom of 4 covers 1.33 screen pixels and the
## lobby's in world text is hard to read. After the game sizes them, divide the override (as the
## game itself does for split screen) so the design is drawn at least at half its size, by at
## most MAX_WORLD_ZOOM: 1.5 at 640x480 and 1.33 at 720x720 (2 screen pixels per world pixel),
## 1.0 on 16:9 screens. The lobby (the loadout stage) is zoomed further, to 7/3 screen pixels per
## world pixel (1.75 at 640x480, 1.56 at 720x720, chosen on the device): its game mode, loadout
## and keeper panels are text drawn in the world. The render target size stays the same; less of the world is in view.
## DK_WORLD_ZOOM and DK_LOBBY_ZOOM override the factors (1 = the game's view).
const VIEWPORT_CONTAINER := "res://systems/camera/ViewportContainer.gd"
const MAX_WORLD_ZOOM := 1.5
const LOBBY_TEXT_SCALE := 7.0 / 12.0
const MAX_LOBBY_ZOOM := 1.75
const LOBBY_SCRIPT := "res://stages/loadout/MultiplayerloadoutStage.gd"

func _zoom_world(container: Node) -> void:
	var world: SubViewport = container.get("_worldSubviewport")
	var ui: SubViewport = container.get("_uiSubviewport")
	if not world or world.size_2d_override.x <= 0 or world.size_2d_override.y <= 0:
		return
	# the signal is also emitted when only the camera zoom changed: zoom only an override the
	# game has just set, not the one zoomed here before
	if world.size_2d_override == world.get_meta("port_zoomed", Vector2i.ZERO):
		return
	var shown := Vector2(world.size) / Vector2(world.size_2d_override)
	var lobby := _in_lobby(container)
	var f := clampf((LOBBY_TEXT_SCALE if lobby else TARGET_TEXT_SCALE) / minf(shown.x, shown.y), 1.0,
			MAX_LOBBY_ZOOM if lobby else MAX_WORLD_ZOOM)
	var env := OS.get_environment("DK_LOBBY_ZOOM" if lobby else "DK_WORLD_ZOOM")
	if env.is_valid_float() and env.to_float() > 0.0:
		f = env.to_float()
	if is_equal_approx(f, 1.0):
		return
	world.size_2d_override = Vector2i((Vector2(world.size_2d_override) / f).round())
	world.set_meta("port_zoomed", world.size_2d_override)
	if ui:
		ui.size_2d_override = Vector2i((Vector2(ui.size_2d_override) / f).round())

func _in_lobby(node: Node) -> bool:
	while node:
		var sc: Script = node.get_script()
		if sc and sc.resource_path == LOBBY_SCRIPT:
			return true
		node = node.get_parent()
	return false

## The title's menus (New Game, Options, Quit with their popups; Updates and Credits) are short
## enough to be drawn larger than the rest of the UI. Scale them so they look as on a 1280x720
## screen (2/3 of design size), MainMenu around the bottom centre of its panel and AdditionalMenu
## around the bottom left of its own, by at most what keeps the two panels apart and on screen.
## 640x480 1.5, 720x720 1.33, 16:9 screens 1.0.
const TITLE_MENU_TEXT_SCALE := 2.0 / 3.0
const TITLE_MENU_MAX := 1.5
const TITLE_MENU_GAP := 16.0

func _scale_title_menus(main: Control, extra: Control) -> void:
	if not is_instance_valid(main) or not is_instance_valid(extra):
		return
	var mp: Control = main.get_node_or_null("Panel")
	var ap: Control = extra.get_node_or_null("Panel")
	var view := main.get_viewport_rect().size
	if not mp or not ap or mp.size.x <= 0.0 or view.x <= 0.0:
		return
	var shown := float(get_tree().root.size.x) / view.x  # screen pixels per design unit
	var s := clampf(TITLE_MENU_TEXT_SCALE / shown, 1.0, TITLE_MENU_MAX)
	# rects in the canvas, unscaled (scale and pivot do not move the layout rect)
	var m_left := main.position.x + mp.position.x
	var centre := m_left + mp.size.x * 0.5
	var a_left := extra.position.x + ap.position.x
	# both panels side by side, with a gap between them and at the right edge
	s = minf(s, (view.x - a_left - 2.0 * TITLE_MENU_GAP) / (ap.size.x + mp.size.x))
	s = maxf(s, 1.0)
	extra.pivot_offset = ap.position + Vector2(0.0, ap.size.y)
	# MainMenu stays centred if that clears AdditionalMenu, else its left edge goes right after it.
	# Scaling around pivot x moves the panel's left edge to X + px + s * (L - px), so the pivot
	# picks where it lands without touching the position the game lays out and animates.
	var want_left := centre - mp.size.x * s * 0.5
	var min_left := a_left + ap.size.x * s + TITLE_MENU_GAP
	var px := mp.position.x + mp.size.x * 0.5
	if want_left < min_left and s > 1.0:
		px = (min_left - main.position.x - s * mp.position.x) / (1.0 - s)
	main.pivot_offset = Vector2(px, mp.position.y + mp.size.y)
	main.scale = Vector2.ONE * s
	extra.scale = Vector2.ONE * s

func _on_title_menu_added(main: Control) -> void:
	var extra := main.get_parent().get_node_or_null("AdditionalMenu") as Control
	if not extra:
		return
	var rescale := func() -> void: _scale_title_menus.call_deferred(main, extra)
	main.resized.connect(rescale)
	extra.resized.connect(rescale)
	get_tree().root.size_changed.connect(rescale)
	main.tree_exiting.connect(func() -> void: get_tree().root.size_changed.disconnect(rescale))
	rescale.call()

## The landing screen's text (centre) and "Press anything to continue" hint (bottom right) get
## the title menu's scale as well, about the point each is anchored to, limited to what fits.
const LANDING_SCENE := "res://stages/landing/LandingStage.tscn"
const OVERLAY_PIVOTS := {
	LANDING_SCENE: {"LandingLabel": Vector2(0.5, 0.5), "MarginContainer": Vector2.ONE},
}

func _overlay_scale(c: Control) -> float:
	var view := c.get_viewport_rect().size
	var content := c.get_combined_minimum_size()  # a full width label: the text, not the rect
	if view.x <= 0.0 or view.y <= 0.0 or content.x <= 0.0 or content.y <= 0.0:
		return 1.0
	var shown := float(get_tree().root.size.x) / view.x
	var s := clampf(TITLE_MENU_TEXT_SCALE / shown, 1.0, TITLE_MENU_MAX)
	return maxf(1.0, minf(s, minf(view.x / content.x, view.y / content.y) * FIT_MARGIN))

func _scale_overlay(c: Control, pivot: Vector2) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	c.pivot_offset = c.size * pivot
	c.scale = Vector2.ONE * _overlay_scale(c)

func _on_overlay_added(c: Control, pivot: Vector2) -> void:
	var rescale := func() -> void: _scale_overlay.call_deferred(c, pivot)
	c.resized.connect(rescale)
	get_tree().root.size_changed.connect(rescale)
	c.tree_exiting.connect(func() -> void: get_tree().root.size_changed.disconnect(rescale))
	rescale.call()

## The pause menu animates its panel's scale from 0 to 1 and slides the corner boxes (controls,
## version, logos) in by position, so neither can carry a scale of their own. The whole
## CanvasLayer is scaled about the screen centre instead, by the title menu's factor (1.5 at
## 640x480), and each corner box is moved back to its corner at its old size through its
## anchors. That happens as the boxes enter the tree: the menu's _ready already starts the slide
## in, from and to the positions the boxes have then. The controls box (top left) is enlarged
## as far as it stays clear of the menu. The restart and quit confirmations open to the right of
## the menu and are kept on screen.
const PAUSE_SCENE := "res://content/pause/PauseMenu.tscn"
const PAUSE_POPUPS := ["ReallyRestartPopup", "ReallyQuitToTitlePopup"]

func _pause_scale(layer: CanvasLayer) -> float:
	var view := layer.get_viewport().get_visible_rect().size
	if view.x <= 0.0:
		return 1.0
	var shown := float(get_tree().root.size.x) / view.x
	return clampf(TITLE_MENU_TEXT_SCALE / shown, 1.0, TITLE_MENU_MAX)

func _is_pause_box(node: Node) -> bool:
	# the corner boxes: not the menu, not the full screen backdrop
	return node is Control and node.name != "MenuPanel" and not (node.anchor_left == 0.0 and node.anchor_right == 1.0)

func _place_pause_box(box: Control, s: float) -> void:
	# the anchor a lands at centre + s * (a' * view - centre), so a' = 0.5 + (a - 0.5) / s
	var a: Vector2 = box.get_meta("port_anchor", Vector2(box.anchor_left, box.anchor_top))
	if not box.has_meta("port_anchor"):
		box.set_meta("port_anchor", a)
		box.resized.connect(func() -> void: box.pivot_offset = box.size * a)
	var a2 := Vector2(0.5, 0.5) + (a - Vector2(0.5, 0.5)) / s
	box.set_anchor(SIDE_LEFT, a2.x, true)
	box.set_anchor(SIDE_RIGHT, a2.x, true)
	box.set_anchor(SIDE_TOP, a2.y, true)
	box.set_anchor(SIDE_BOTTOM, a2.y, true)
	box.pivot_offset = box.size * a
	box.scale = Vector2.ONE / s

func _scale_pause(layer: CanvasLayer) -> void:
	if not is_instance_valid(layer) or not layer.is_inside_tree():
		return
	var s := _pause_scale(layer)
	var centre := layer.get_viewport().get_visible_rect().size * 0.5
	layer.transform = Transform2D(0.0, Vector2.ONE * s, 0.0, centre * (1.0 - s))
	layer.set_meta("port_scale", s)
	for box in layer.get_children():
		if _is_pause_box(box):
			_place_pause_box(box, s)
	_scale_support_box(layer)

func _scale_support_box(layer: CanvasLayer) -> void:
	if not is_instance_valid(layer) or not layer.is_inside_tree():
		return
	var box := layer.get_node_or_null("SupportBox") as Control
	var menu := layer.get_node_or_null("MenuPanel") as Control
	if not box or not menu or box.size.x <= 0.0:
		return
	var s: float = layer.get_meta("port_scale", 1.0)
	var centre := layer.get_viewport().get_visible_rect().size.x * 0.5
	# on screen the box starts at the left edge and is k * its width wide
	var menu_left := centre + s * (menu.position.x - centre)
	var k := clampf((menu_left - TITLE_MENU_GAP) / box.size.x, 1.0, s)
	box.scale = Vector2.ONE * k / s

func _unscale_pause_child(c: Control, layer: CanvasLayer) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	var s: float = layer.get_meta("port_scale", 1.0)
	# with the layer's scale s about the centre C, the inverse scale about C - position cancels it
	c.pivot_offset = layer.get_viewport().get_visible_rect().size * 0.5 - c.position
	c.scale = Vector2.ONE / s

func _keep_pause_popup_on_screen(popup: Control) -> void:
	if not is_instance_valid(popup) or not popup.visible or not popup.is_inside_tree():
		return
	var layer := popup.get_canvas_layer_node()
	if not layer:
		return
	var view := popup.get_viewport_rect().size
	var right := (layer.transform * (popup.global_position + Vector2(popup.size.x, 0.0))).x
	if right > view.x - TITLE_MENU_GAP:
		popup.position.x -= (right - view.x + TITLE_MENU_GAP) / layer.transform.get_scale().x

func _on_pause_menu_added(layer: CanvasLayer) -> void:
	_scale_pause(layer)
	var rescale := func() -> void: _scale_pause.call_deferred(layer)
	get_tree().root.size_changed.connect(rescale)
	layer.tree_exiting.connect(func() -> void: get_tree().root.size_changed.disconnect(rescale))
	layer.ready.connect(func() -> void:
		layer.set_meta("port_ready", true)
		var refit := func() -> void: _scale_support_box.call_deferred(layer)
		for name in ["SupportBox", "MenuPanel"]:
			var c := layer.get_node_or_null(name) as Control
			if c:
				c.resized.connect(refit)
		refit.call()
		for name in PAUSE_POPUPS:
			var popup := layer.find_child(name) as Control
			if popup:
				popup.visibility_changed.connect(func() -> void: _keep_pause_popup_on_screen.call_deferred(popup)),
		CONNECT_ONE_SHOT)

## The game's popups are a full screen CenterContainer holding a PanelContainer laid out at its
## minimum size, which can be wider than a 4:3 or square screen shows with the UI scale (Key
## Bindings is cut off at 640x480). A panel larger than the screen is scaled down and centred to
## fit, with a small margin; smaller panels are left alone. Container layout
## resets the scale, so the fit runs again after each sort of the CenterContainer.
const FIT_MARGIN := 0.98

func _fit_panel(panel: Control) -> void:
	if not is_instance_valid(panel) or not panel.is_inside_tree() or not panel.get_parent() is Control:
		return
	# the CenterContainer grows to the panel's minimum size, so compare with what the screen shows
	var view := panel.get_viewport_rect().size
	if panel.size.x <= 0.0 or panel.size.y <= 0.0 or view.x <= 0.0 or view.y <= 0.0:
		return
	var s := minf(1.0, minf(view.x / panel.size.x, view.y / panel.size.y) * FIT_MARGIN)
	if s > FIT_MARGIN - 0.001:
		s = 1.0  # fits already (or within the margin)
	# the oversized CenterContainer puts the panel off centre; pick the pivot so the scaled panel
	# is centred on the screen: its corner lands at origin + pivot * (1 - s)
	# on screen (a pause menu popup sits in a scaled CanvasLayer under an inverse scale, so the net
	# scale of the parent is 1 but its canvas position is not the screen position)
	var origin := (panel.get_parent() as Control).get_global_transform_with_canvas().origin + panel.position
	if s < 1.0:
		panel.pivot_offset = ((view - panel.size * s) * 0.5 - origin) / (1.0 - s)
	else:
		panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2.ONE * s

func _on_node_added(node: Node) -> void:
	if node is PanelContainer and node.get_parent() is CenterContainer:
		# Container layout resets a child's scale to 1, so fit again after every sort
		node.get_parent().sort_children.connect(_fit_panel.bind(node))
		_fit_panel.call_deferred(node)
	if node.name == "MainMenu" and node is Control and node.get_parent() and node.get_parent().name == "Canvas":
		_on_title_menu_added.call_deferred(node)
	if node is CanvasLayer and node.scene_file_path == PAUSE_SCENE:
		_on_pause_menu_added(node)
	elif node.get_parent() is CanvasLayer and node.get_parent().scene_file_path == PAUSE_SCENE and node is Control:
		var layer: CanvasLayer = node.get_parent()
		if layer.has_meta("port_ready"):  # a popup the menu opened
			node.item_rect_changed.connect(func() -> void: _unscale_pause_child.call_deferred(node, layer))
			_unscale_pause_child(node, layer)
		elif _is_pause_box(node):
			_place_pause_box(node, layer.get_meta("port_scale", 1.0))
	if node is Control and node.get_parent() is CanvasLayer:
		var scene := node.owner.scene_file_path if node.owner else ""
		if OVERLAY_PIVOTS.has(scene) and OVERLAY_PIVOTS[scene].has(str(node.name)):
			_on_overlay_added.call_deferred(node, OVERLAY_PIVOTS[scene][str(node.name)])
	var script: Script = node.get_script()
	if script and script.resource_path == VIEWPORT_CONTAINER and node.has_signal("logic_size_changed"):
		# connected before the game's own listeners, so they see the zoomed size
		node.logic_size_changed.connect(_zoom_world.bind(node))
	if node.name == BUNDLE_TRACKER:
		_bundle_trackers.append(node)
	elif node is SubViewport and node.get_parent() and node.get_parent().name == BUNDLE_TRACKER:
		node.set_script(_viewport_script(node.get_script(), TINY_VIEWPORT))
	elif node is SubViewport and str(node.name) in HALF_RES_LAYERS:
		node.set_script(_viewport_script(node.get_script(), HALF_VIEWPORT))
		_layers.append(node)
	elif node is TextureRect and str(node.name) in INTRO_BACKGROUNDS and node.owner and node.owner.name == "Intro":
		node.resized.connect(_cover_intro_background.bind(node))
		_cover_intro_background.call_deferred(node)
	if node is Label and not node.has_meta("port_text") and node.text != "" and _in_deferred_panel(node):
		node.set_meta("port_text", node.text)
		node.text = ""
	elif node.name in DEFERRED_TEXT_PANELS and node is CanvasItem:
		node.visibility_changed.connect(_on_deferred_panel_visibility.bind(node))

## The intro's gradient backgrounds are turned 270 degrees and laid out for 16:9. On a 4:3
## screen they end short of the top edge, and the map the intro draws behind them (to compile
## its shaders early) shows through as a blue strip. They are lengthened to reach the top.
func _cover_intro_background(rect: TextureRect) -> void:
	if not is_equal_approx(rect.rotation_degrees, 270.0):
		return
	var top := rect.position.y - rect.size.x  # turned 270 degrees, the width runs upwards
	if top > 0.0:
		rect.size.x += top

func _in_deferred_panel(node: Node) -> bool:
	var p := node.get_parent()
	while p:
		if p.name in DEFERRED_TEXT_PANELS:
			return true
		p = p.get_parent()
	return false

func _on_deferred_panel_visibility(panel: CanvasItem) -> void:
	var shown := panel.is_visible_in_tree()
	for label in panel.find_children("*", "Label", true, false):
		if not label.has_meta("port_text"):
			continue
		if shown and label.text == "":
			label.text = label.get_meta("port_text")
		elif not shown:
			# keep whatever the game set meanwhile, then release the shaped text
			if label.text != "":
				label.set_meta("port_text", label.text)
			label.text = ""

extends Node
# Test-only autoload: with --autorun=<regular-small|regular-medium|regular-large|regular-huge|lobby>,
# start a run from the loadout stage as soon as it is up.
var size := ""
var done := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autorun="):
			size = arg.trim_prefix("--autorun=")

var title_done := false

func _process(_d: float) -> void:
	if size == "" or done or Engine.get_process_frames() % 60 != 0:
		return
	if not title_done and not "--autorun-notitle" in OS.get_cmdline_user_args():
		for t in get_tree().root.find_children("TitleStage", "", true, false):
			if t.has_method("_on_singleplayer_button_pressed") and t.is_node_ready():
				title_done = true
				if size == "options":
					done = true
					_options_shots(t)
					return
				if size == "popups":
					done = true
					_popup_shots()
					return
				await get_tree().create_timer(3.0).timeout
				if t.has_method("disableOnlineServices") and not Options.onlineMultiplayerDecided:
					Options.onlineMultiplayerDecided = true
					Options.allowOnlineMultiplayer = false
				t._on_singleplayer_button_pressed()
				return
	var stage = null
	for n in get_tree().root.find_children("MultiplayerLoadoutStage", "", true, false):
		if n.has_method("startRun") and n.is_node_ready():
			stage = n
	if stage == null:
		return
	done = true
	if size == "lobby":
		return  # --autorun=lobby: walk into the singleplayer lobby and stay there
	await get_tree().create_timer(6.0).timeout
	stage.gameModeSelected("relichunt")
	await get_tree().create_timer(2.0).timeout
	var dome = Data.loadoutDomes[0]
	var gadget = Data.loadoutGadgets[0]
	stage.domeSelected(dome, "team1")
	stage.primaryGadgetSelected(gadget, "team1")
	stage.mapSizeSelected(size)
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(stage._startRunChoice):
		stage._startRunChoice.set_enabled(true)
	_log("autorun: mode=relichunt dome=%s gadget=%s map=%s" % [dome, gadget, size])
	stage.startRun()
	if OS.has_environment("RELIC_AT"):
		await get_tree().create_timer(float(OS.get_environment("RELIC_AT"))).timeout
		_deliver_relic()


# RELIC_AT=<s>: that long after the run starts, open a chamber for the keeper (the game's own
# chamber code hands over its drop), then bring the keeper into the dome, and CHAMBER=relic floats
# the relic into the dome. CHAMBER=gadget (default) opens the gadget choice as a delivered gadget does.
func _deliver_relic() -> void:
	var kind := OS.get_environment("CHAMBER") if OS.has_environment("CHAMBER") else "gadget"
	var by_script := func(suffix: String) -> Array:
		return get_tree().root.find_children("*", "", true, false).filter(
			func(n): return n.get_script() and n.get_script().resource_path.ends_with(suffix))
	var chambers: Array = by_script.call("/RelicChamber.gd" if kind == "relic" else "/GadgetChamber.gd")
	var points: Array = by_script.call("RelicDropPoint.gd")
	var keeper = Keepers.getAll()[0]
	printerr("autorun: %s chambers=%d droppoints=%d" % [kind, chambers.size(), points.size()])
	if chambers.is_empty() or points.is_empty():
		return
	var point: Node2D = points[0]
	if kind == "gadget":
		# what the dome does when a carried gadget arrives (Drop.deactivate)
		Level.stage.queueChoice("gadget", "team1", keeper.playerId)
	else:
		chambers[0].registerHit(keeper.playerId)
		await get_tree().create_timer(2.0).timeout
		keeper.global_position = point.global_position + Vector2(0, 40)
	if kind == "relic":
		var relics := get_tree().get_nodes_in_group("relic")
		if relics.is_empty():
			return
		relics[0].global_position = point.global_position + Vector2(0, 40)
		await get_tree().physics_frame
		relics[0].floatToDropTarget(point)
	printerr("autorun: keeper in the dome")
	for i in 20:
		await get_tree().create_timer(1.0, true).timeout
		var popups := get_tree().root.find_children("*", "", true, false).filter(
			func(n): return n.get_script() and n.get_script().resource_path.ends_with("GadgetChoicePopup.gd"))
		var info := "-"
		if not popups.is_empty():
			var p: Control = popups[0]
			info = "%s vis=%s pos=%s size=%s scale=%s parent=%s/%s" % [p.name, p.is_visible_in_tree(), p.global_position, p.size, p.scale, p.get_parent().name, p.get_parent().get_class()]
		printerr("autorun: t+%d paused=%s popup=%s" % [i, get_tree().paused, info])
		if i == 3 and not popups.is_empty():
			var n: Node = popups[0]
			while n:
				var extra := ""
				if n is CanvasItem:
					extra = "vis=%s mod=%s self=%s z=%d clip=%s" % [n.visible, n.modulate, n.self_modulate, n.z_index, n.clip_children]
				if n is Control:
					extra += " pos=%s size=%s scale=%s clipc=%s" % [n.position, n.size, n.scale, n.clip_contents]
				if n is CanvasLayer:
					extra = "layer=%d vis=%s xf=%s" % [n.layer, n.visible, n.transform]
				if n is SubViewport:
					extra = "size=%s upd=%d" % [n.size, n.render_target_update_mode]
				printerr("autorun:   %s [%s] %s" % [n.name, n.get_class(), extra])
				n = n.get_parent()
			var pc: Control = popups[0].find_children("*", "PanelContainer", false, false)[0]
			var vp := pc.get_viewport() as SubViewport
			for f in 8:
				printerr("autorun:   frame%d panel scale=%s pivot=%s pos=%s gpos=%s vprect=%s override=%s" % [f, pc.scale, pc.pivot_offset, pc.position, pc.get_global_transform_with_canvas().origin, pc.get_viewport_rect().size, vp.size_2d_override if vp else "-"])
				await get_tree().process_frame
			for c in popups[0].find_children("*", "Control", true, false).slice(0, 3):
				printerr("autorun:   child %s [%s] vis=%s mod=%s pos=%s size=%s" % [c.name, c.get_class(), c.visible, c.modulate, c.position, c.size])


func _log(msg: String) -> void:
	var f := FileAccess.open(OS.get_environment("AUTORUN_LOG") if OS.has_environment("AUTORUN_LOG") else "user://autorun.log", FileAccess.WRITE)
	if f: f.store_line(msg)


# --autorun=options: open Options from the title, save a screenshot of every category and of the
# input popups into $SHOT_DIR (opt_<name>.png), then quit.
func _shot(name: String) -> void:
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	var dir := OS.get_environment("SHOT_DIR") if OS.has_environment("SHOT_DIR") else "/tmp"
	get_viewport().get_texture().get_image().save_png("%s/opt_%s.png" % [dir, name])
	_log("shot " + name)

func _options_shots(t: Node) -> void:
	await get_tree().create_timer(4.0).timeout
	if t.has_method("disableOnlineServices") and not Options.onlineMultiplayerDecided:
		Options.onlineMultiplayerDecided = true
		Options.allowOnlineMultiplayer = false
	await _shot("title")
	t._on_OptionsButton_pressed()
	await get_tree().create_timer(1.0).timeout
	var panels := get_tree().root.find_children("*", "", true, false).filter(func(n): return n.has_method("showCategory") and "categories" in n)
	if panels.is_empty():
		_log("no options panel")
		OS.kill(OS.get_process_id())  # Godot segfaults while shutting down this game; SIGKILL leaves no core dump
		return
	var panel = panels[0]
	for cat in panel.categories:
		panel.showCategory(cat)
		await _shot(cat)
	for popup in [["gamepadkeeper", false], ["mousekeeper", true]]:
		panel.showCategory("Gamepad")
		panel._on_open_keeper_input_settings_button_pressed(popup[1])
		await _shot(popup[0])
		for p in panel.get_parent().get_children():
			if p.has_method("showCategory") and p != panel:
				for c in p.get("categories") if "categories" in p else []:
					p.showCategory(c)
					await _shot(popup[0] + "_" + str(c))
				p.queue_free()
	panel._on_KeybindingsButton_pressed()
	await _shot("keybindings")
	for pc in get_tree().root.find_children("*", "PanelContainer", true, false):
		if pc.get_parent() is CenterContainer and pc.is_visible_in_tree():
			_log2("panel %s parent %s size %s scale %s pivot %s view %s pos %s" % [pc.get_path(), pc.get_parent().size, pc.size, pc.scale, pc.pivot_offset, pc.get_viewport_rect().size, pc.global_position])
	OS.kill(OS.get_process_id())  # Godot segfaults while shutting down this game; SIGKILL leaves no core dump


# --autorun=popups: show every scene listed in $POPUPS_LIST (one res:// path per line) on its own
# CanvasLayer over the title, save opt_popup_<name>.png into $SHOT_DIR, free it, then quit.
func _popup_shots() -> void:
	await get_tree().create_timer(4.0).timeout
	Options.onlineMultiplayerDecided = true
	for path in FileAccess.get_file_as_string(OS.get_environment("POPUPS_LIST")).split("\n", false):
		var packed = load(path)
		if not packed:
			_log("cannot load " + path)
			continue
		var layer := CanvasLayer.new()
		layer.layer = 90
		get_tree().root.add_child(layer)
		var node = packed.instantiate()
		layer.add_child(node)
		if node is CanvasItem:
			node.visible = true
		await _shot("popup_" + path.get_file().get_basename())
		# $POPUP_CALL=<method>: call it on the scene (e.g. open Options from the pause menu), shoot again
		var method := OS.get_environment("POPUP_CALL")
		if method != "" and node.has_method(method):
			node.call(method)
			await _shot("popup_" + path.get_file().get_basename() + "_" + method)
		layer.queue_free()
	OS.kill(OS.get_process_id())  # Godot segfaults while shutting down this game; SIGKILL leaves no core dump

func _log2(msg: String) -> void:
	var f := FileAccess.open(OS.get_environment("SHOT_DIR") + "/panels.txt", FileAccess.READ_WRITE if FileAccess.file_exists(OS.get_environment("SHOT_DIR") + "/panels.txt") else FileAccess.WRITE)
	f.seek_end()
	f.store_line(msg)

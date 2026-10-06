extends SceneTree
func _count(ps: PackedScene) -> Array:
	var st := ps.get_state()
	var scripts := 0; var conns := st.get_connection_count(); var groups := 0
	for i in st.get_node_count():
		groups += st.get_node_groups(i).size()
		for p in st.get_node_property_count(i):
			if st.get_node_property_name(i, p) == "script": scripts += 1
	return [st.get_node_count(), scripts, conns, groups]
func _init():
	var orig: PackedScene = ResourceLoader.load("res://.godot/exported/133200997/export-96d3b7e9358e8eb16afca1bbe92e14d6-TitleStage.scn", "", ResourceLoader.CACHE_MODE_IGNORE)
	var new: PackedScene = ResourceLoader.load("res://cache/scenes/export-96d3b7e9358e8eb16afca1bbe92e14d6-TitleStage.scn", "", ResourceLoader.CACHE_MODE_IGNORE)
	print("CMP orig nodes,scripts,conns,groups=", _count(orig))
	print("CMP new  nodes,scripts,conns,groups=", _count(new))
	quit()

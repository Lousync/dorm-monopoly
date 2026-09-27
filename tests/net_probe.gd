extends SceneTree

func _initialize() -> void:
	var node := Node.new()
	node.set_script(load("res://tests/net_probe_node.gd"))
	root.add_child(node)

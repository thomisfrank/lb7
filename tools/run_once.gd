extends Node

# Tracing helper: watch node_added during scene instantiation and report any node
# that implements input handlers (_input, _unhandled_input, _gui_input)
var _t = 0.0

func _report_node(n: Node) -> void:
	if not is_instance_valid(n):
		return
	var has_input = n.has_method("_input")
	var has_unhandled = n.has_method("_unhandled_input")
	var has_gui = n.has_method("_gui_input")
	if has_input or has_unhandled or has_gui:
		print("TRACE: node added ->", n.get_path(), "inside_tree=", n.is_inside_tree(), "_input=", has_input, "_unhandled=", has_unhandled, "_gui=", has_gui)

func _on_node_added(node: Node) -> void:
	_report_node(node)

func _ready():
	print("run_once: tracer ready")
	# Connect to node_added to trace as scenes are instanced
	get_tree().connect("node_added", Callable(self, "_on_node_added"))

	# Also scan current nodes (just in case)
	for n in get_tree().get_root().get_children():
		_report_node(n)

	# Now change to main scene (if present)
	if ResourceLoader.exists("res://Scenes/main.tscn"):
		print("run_once: loading main scene")
		get_tree().change_scene_to_file("res://Scenes/main.tscn")
	else:
		print("run_once: main scene not found")

func _process(delta):
	_t += delta
	# run for a few seconds to allow instantiation and logging
	if _t > 4.0:
		print("run_once: done, quitting")
		get_tree().quit()

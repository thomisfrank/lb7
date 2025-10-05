extends Node

var LOG = null

func _report_node(n: Node) -> void:
    if not is_instance_valid(n):
        return
    var has_input = n.has_method("_input")
    var has_unhandled = n.has_method("_unhandled_input")
    var has_gui = n.has_method("_gui_input")
    if has_input or has_unhandled or has_gui:
        var s = "DEV-TRACER: node='" + str(n.get_path()) + "' inside_tree=" + str(n.is_inside_tree()) + " _input=" + str(has_input) + " _unhandled=" + str(has_unhandled) + " _gui=" + str(has_gui)
        if LOG:
            LOG.log(s)
        else:
            print(s)

func _on_node_added(node: Node) -> void:
    _report_node(node)

func _ready() -> void:
    # Connect to node_added to trace nodes as scenes are instanced
    var tree = get_tree()
    if tree:
        tree.connect("node_added", Callable(self, "_on_node_added"))
        # report existing nodes under root
        for n in tree.get_root().get_children():
            _report_node(n)
    # lazy logger acquisition
    if ResourceLoader.exists("res://Scripts/logger.gd"):
        var l = preload("res://Scripts/logger.gd")
        LOG = l

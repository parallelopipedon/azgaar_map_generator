@tool
extends EditorPlugin

var dock_scene: PackedScene = preload("res://addons/map_generator/ui/map_generator_dock.tscn")
var dock_instance: Control

func _enter_tree() -> void:
	dock_instance = dock_scene.instantiate()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, dock_instance)

func _exit_tree() -> void:
	if dock_instance:
		remove_control_from_docks(dock_instance)
		dock_instance.free()

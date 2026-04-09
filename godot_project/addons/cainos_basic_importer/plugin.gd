@tool
extends EditorPlugin

const ImporterDock := preload("res://addons/cainos_basic_importer/importer_dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = ImporterDock.new()
	_dock.name = "Cainos Importer"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	if _dock.has_method("setup"):
		_dock.setup(get_editor_interface())


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


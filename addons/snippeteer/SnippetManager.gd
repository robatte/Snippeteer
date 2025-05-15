@tool
class_name SnippetManager
extends Node

const SNIPPET_PANEL_SCENE_PATH: String = "res://addons/snippeteer/ui/snippets_panel.tscn"
const SNIPPET_DATA_FILE_PATH: String = "res://addons/snippeteer/snippets.json"

var snippet_list: Array[Dictionary] = []

var _panel_scene: PackedScene = null
var _panel_instance: Control = null

const ERROR_PREFIX_SM: String = "[color=red][b]ERROR (SnippetManager):[/b][/color] "
const WARN_PREFIX_SM: String = "[color=yellow][b]WARN (SnippetManager):[/b][/color] "
const DEBUG_PREFIX_SM: String = "[color=lightblue]DEBUG (SnippetManager):[/color] "


func initialize() -> void:
	print_rich(DEBUG_PREFIX_SM + "Initializing...")
	_panel_scene = load(SNIPPET_PANEL_SCENE_PATH) as PackedScene
	if not is_instance_valid(_panel_scene):
		print_rich(ERROR_PREFIX_SM + "Failed to load Snippet Panel Scene from: " + SNIPPET_PANEL_SCENE_PATH)
		return
	load_snippets_from_file()


func cleanup() -> void:
	print_rich(DEBUG_PREFIX_SM + "Cleaning up...")
	if is_instance_valid(_panel_instance):
		if _panel_instance.get_parent():
			_panel_instance.get_parent().remove_child(_panel_instance)
		_panel_instance.queue_free()
		_panel_instance = null


func load_snippets_from_file() -> void:
	if FileAccess.file_exists(SNIPPET_DATA_FILE_PATH):
		var file: FileAccess = FileAccess.open(SNIPPET_DATA_FILE_PATH, FileAccess.READ)
		if not is_instance_valid(file):
			print_rich(ERROR_PREFIX_SM + "Failed to open snippet file for reading: " + SNIPPET_DATA_FILE_PATH)
			snippet_list = []
			return

		var json_parser: JSON = JSON.new()
		var content: String = file.get_as_text()
		file.close()

		var error_code: Error = json_parser.parse(content)
		if error_code == OK:
			if typeof(json_parser.data) == TYPE_ARRAY:
				var validated_array: Array[Dictionary] = []
				for item in json_parser.data:
					if typeof(item) == TYPE_DICTIONARY and item.has("keyword") and item.has("snippet"):
						validated_array.append(item)
					else:
						print_rich(WARN_PREFIX_SM + "Invalid item in snippet file (missing keyword/snippet or not a Dictionary): " + str(item))
				snippet_list = validated_array
				print_rich(DEBUG_PREFIX_SM + "Loaded " + str(snippet_list.size()) + " snippets.")
			else:
				print_rich(ERROR_PREFIX_SM + "Invalid JSON format in snippet file (not an array).")
				snippet_list = []
		else:
			print_rich(ERROR_PREFIX_SM + "JSON Parse Error in snippet file: " + json_parser.get_error_message() + " at line " + str(json_parser.get_error_line()))
			snippet_list = []
	else:
		print_rich(DEBUG_PREFIX_SM + "Snippet data file not found. Creating default empty list: " + SNIPPET_DATA_FILE_PATH)
		snippet_list = []
		save_snippets_to_file()


func save_snippets_to_file() -> void:
	var dir_path: String = SNIPPET_DATA_FILE_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var err: Error = DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			print_rich(ERROR_PREFIX_SM + "Could not create directory " + dir_path + ". Error: " + str(err))
			return

	var file: FileAccess = FileAccess.open(SNIPPET_DATA_FILE_PATH, FileAccess.WRITE)
	if not is_instance_valid(file):
		print_rich(ERROR_PREFIX_SM + "Failed to open snippet file for writing: " + SNIPPET_DATA_FILE_PATH)
		return

	var json_string: String = JSON.stringify(snippet_list, "\t", true)
	file.store_string(json_string)
	file.close()
	print_rich(DEBUG_PREFIX_SM + "Snippets saved to " + SNIPPET_DATA_FILE_PATH)


func show_management_panel() -> void:
	if not is_instance_valid(_panel_scene):
		print_rich(ERROR_PREFIX_SM + "Snippet Panel Scene is not loaded. Cannot show panel.")
		return

	if not is_instance_valid(_panel_instance):
		_panel_instance = _panel_scene.instantiate() as Control
		if not is_instance_valid(_panel_instance):
			print_rich(ERROR_PREFIX_SM + "Failed to instantiate Snippet Panel Scene.")
			return

		_connect_panel_signals()

		var inspector: EditorInspector = EditorInterface.get_inspector()
		if is_instance_valid(inspector) and is_instance_valid(inspector.get_parent()):
			var inspector_parent: Control = inspector.get_parent()
			if is_instance_valid(inspector_parent.get_parent()) and inspector_parent.get_parent() is TabContainer:
				var tabs: TabContainer = inspector_parent.get_parent() as TabContainer
				_panel_instance.name = "Snippets"
				tabs.add_child(_panel_instance)
				tabs.current_tab = tabs.get_tab_count() - 1
				print_rich(DEBUG_PREFIX_SM + "Snippet Panel added as Inspector tab.")
			else:
				# Fallback: as floating window
				print_rich(DEBUG_PREFIX_SM + "Inspector TabContainer not found. Adding panel as popup.")
				EditorInterface.get_editor_main_screen().add_child(_panel_instance)
				_panel_instance.popup_centered_ratio(0.7)
		else:
			# Fallback: as floating window
			print_rich(DEBUG_PREFIX_SM + "Inspector not found. Adding panel as popup.")
			EditorInterface.get_editor_main_screen().add_child(_panel_instance)
			_panel_instance.popup_centered_ratio(0.7)

	_panel_instance.visible = true
	_populate_item_list_in_panel()

	# if it is a popup, re-popup it to bring it to foreground
	if not _panel_instance.get_parent() is TabContainer:
		if _panel_instance.has_method("popup"):
			_panel_instance.call("popup")
		elif _panel_instance.get_parent() != EditorInterface.get_editor_main_screen():
			EditorInterface.get_editor_main_screen().add_child(_panel_instance)
			_panel_instance.popup_centered_ratio(0.7)


func _connect_panel_signals() -> void:
	if not is_instance_valid(_panel_instance):
		print_rich(ERROR_PREFIX_SM + "Panel-instance invalid")
		return
	print_rich(DEBUG_PREFIX_SM + "Panel-instance valid")

	var item_list_node: ItemList = _panel_instance.get_node_or_null("MainSplit/SnippetDisplayList") as ItemList
	if is_instance_valid(item_list_node):
		item_list_node.item_selected.connect(_on_panel_snippet_selected)
	else: print_rich(ERROR_PREFIX_SM + "Node not found: MainSplit/SnippetDisplayList")

	var new_button_node: Button = _panel_instance.get_node_or_null("MainSplit/EditArea/ButtonBox/NewButton") as Button
	if is_instance_valid(new_button_node):
		new_button_node.pressed.connect(_on_panel_new_button_pressed)
	else: print_rich(ERROR_PREFIX_SM + "Node not found: MainSplit/EditArea/ButtonBox/NewButton")

	var save_button_node: Button = _panel_instance.get_node_or_null("MainSplit/EditArea/ButtonBox/SaveButton") as Button
	if is_instance_valid(save_button_node):
		save_button_node.pressed.connect(_on_panel_save_button_pressed)
	else: print_rich(ERROR_PREFIX_SM + "Node not found: MainSplit/EditArea/ButtonBox/SaveButton")

	var delete_button_node: Button = _panel_instance.get_node_or_null("MainSplit/EditArea/ButtonBox/DeleteButton") as Button
	if is_instance_valid(delete_button_node):
		delete_button_node.pressed.connect(_on_panel_delete_button_pressed)
	else: print_rich(ERROR_PREFIX_SM + "Node not found: MainSplit/EditArea/ButtonBox/DeleteButton")


func _populate_item_list_in_panel() -> void:
	if not is_instance_valid(_panel_instance): return
	var item_list_node: ItemList = _panel_instance.get_node_or_null("MainSplit/SnippetDisplayList") as ItemList
	if not is_instance_valid(item_list_node): return

	item_list_node.clear()
	var current_keyword_in_edit: String = ""
	var keyword_edit_node: LineEdit = _panel_instance.get_node_or_null("MainSplit/EditArea/KeywordEdit") as LineEdit
	if is_instance_valid(keyword_edit_node):
		current_keyword_in_edit = keyword_edit_node.text

	var select_idx: int = -1
	for i in snippet_list.size():
		var snippet_dict: Dictionary = snippet_list[i]
		item_list_node.add_item(snippet_dict["keyword"])
		if snippet_dict["keyword"] == current_keyword_in_edit and not current_keyword_in_edit.is_empty():
			select_idx = i # only select if keyword matches and is not empty

	if select_idx != -1:
		item_list_node.select(select_idx)
	elif item_list_node.item_count > 0:
		pass # automatically select the first?


func _on_panel_snippet_selected(index: int) -> void:
	if not is_instance_valid(_panel_instance): return
	if index < 0 or index >= snippet_list.size():
		print_rich(ERROR_PREFIX_SM + "Invalid index from ItemList: " + str(index))
		_clear_panel_edit_fields()
		return

	var snippet_dict: Dictionary = snippet_list[index]
	var keyword_edit_node: LineEdit = _panel_instance.get_node_or_null("MainSplit/EditArea/KeywordEdit") as LineEdit
	var body_edit_node: TextEdit = _panel_instance.get_node_or_null("MainSplit/EditArea/BodyTextEdit") as TextEdit

	if is_instance_valid(keyword_edit_node): keyword_edit_node.text = snippet_dict["keyword"]
	if is_instance_valid(body_edit_node): body_edit_node.text = snippet_dict["snippet"]


func _clear_panel_edit_fields() -> void:
	if not is_instance_valid(_panel_instance): return
	var keyword_edit_node: LineEdit = _panel_instance.get_node_or_null("MainSplit/EditArea/KeywordEdit") as LineEdit
	var body_edit_node: TextEdit = _panel_instance.get_node_or_null("MainSplit/EditArea/BodyTextEdit") as TextEdit
	if is_instance_valid(keyword_edit_node): keyword_edit_node.text = ""
	if is_instance_valid(body_edit_node): body_edit_node.text = ""


func _on_panel_new_button_pressed() -> void:
	if not is_instance_valid(_panel_instance): return
	_clear_panel_edit_fields()
	var item_list_node: ItemList = _panel_instance.get_node_or_null("MainSplit/SnippetDisplayList") as ItemList
	if is_instance_valid(item_list_node): item_list_node.deselect_all()
	var keyword_edit_node: LineEdit = _panel_instance.get_node_or_null("MainSplit/EditArea/KeywordEdit") as LineEdit
	if is_instance_valid(keyword_edit_node): keyword_edit_node.grab_focus()
	print_rich(DEBUG_PREFIX_SM + "New snippet fields cleared.")


func _on_panel_save_button_pressed() -> void:
	if not is_instance_valid(_panel_instance): return

	var keyword_edit_node: LineEdit = _panel_instance.get_node_or_null("MainSplit/EditArea/KeywordEdit") as LineEdit
	var body_edit_node: TextEdit = _panel_instance.get_node_or_null("MainSplit/EditArea/BodyTextEdit") as TextEdit

	if not (is_instance_valid(keyword_edit_node) and is_instance_valid(body_edit_node)):
		print_rich(ERROR_PREFIX_SM + "KeywordEdit or BodyTextEdit node not found for saving.")
		return

	var keyword_text: String = keyword_edit_node.text.strip_edges()
	var body_text: String = body_edit_node.text

	if keyword_text.is_empty():
		print_rich(WARN_PREFIX_SM + "Keyword cannot be empty. Snippet not saved.")
		return

	var updated_existing: bool = false
	for i in snippet_list.size():
		if snippet_list[i]["keyword"] == keyword_text:
			snippet_list[i]["snippet"] = body_text
			updated_existing = true
			print_rich(DEBUG_PREFIX_SM + "Updated existing snippet: " + keyword_text)
			break

	if not updated_existing:
		snippet_list.append({"keyword": keyword_text, "snippet": body_text})
		print_rich(DEBUG_PREFIX_SM + "Added new snippet: " + keyword_text)

	save_snippets_to_file()
	_populate_item_list_in_panel()


func _on_panel_delete_button_pressed() -> void:
	if not is_instance_valid(_panel_instance): return

	var item_list_node: ItemList = _panel_instance.get_node_or_null("MainSplit/SnippetDisplayList") as ItemList
	if not is_instance_valid(item_list_node): return

	var selected_items_indices: Array[int] = item_list_node.get_selected_items()
	if selected_items_indices.is_empty():
		print_rich(DEBUG_PREFIX_SM + "No snippet selected for deletion.")
		return


	selected_items_indices.sort() # make sure it is sorted for pop_at
	selected_items_indices.reverse()

	for index_to_delete in selected_items_indices:
		if index_to_delete >= 0 and index_to_delete < snippet_list.size():
			var removed_snippet: Dictionary = snippet_list.pop_at(index_to_delete)
			print_rich(DEBUG_PREFIX_SM + "Deleted snippet: " + removed_snippet["keyword"])
		else:
			print_rich(ERROR_PREFIX_SM + "Invalid index selected for deletion: " + str(index_to_delete))

	save_snippets_to_file()
	_clear_panel_edit_fields()
	_populate_item_list_in_panel()

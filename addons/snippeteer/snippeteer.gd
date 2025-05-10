@tool
extends EditorPlugin

const SNIPPET_FILE_PATH: String = "res://addons/snippeteer/snippets.json"

var button_insert_snippet: Button = null
var panel: VBoxContainer = null
var snippet_list: Array[Dictionary] = []
var current_placeholders: Array[Dictionary] = []
var placeholder_index: int = 0
var text_editor: TextEdit = null

func _enter_tree() -> void:
	print("load Snippeteer...")
	add_tool_menu_item("Snippet", _show_snippet_panel)

	load_snippets()

	panel = create_snippet_panel()
	#get_editor_interface().get_base_control().add_child(panel)
	#add_control_to_dock(DOCK_SLOT_RIGHT_UR, panel)
	var inspector_dock := get_editor_interface().get_inspector().get_parent()
	if inspector_dock and inspector_dock.get_parent() is TabContainer:
		var tabs := inspector_dock.get_parent() as TabContainer
		panel.name = "Snippets"
		tabs.add_child(panel)
		tabs.move_child(panel, tabs.get_child_count() - 1)
	
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_right = -20
	panel.offset_top = 40
	panel.custom_minimum_size = Vector2(300, 300)

	_connect_editor_input.call_deferred()

func _connect_editor_input() -> void:
	var current_editor := EditorInterface.get_script_editor().get_current_editor()
	if current_editor and current_editor.is_class("ScriptTextEditor"):
		text_editor = current_editor.get_base_editor() as CodeEdit
		if text_editor and not text_editor.gui_input.is_connected(_on_editor_input):
			text_editor.gui_input.connect(_on_editor_input)

func _exit_tree() -> void:
	remove_tool_menu_item("Snippet")	
	if panel and panel.get_parent():
		panel.get_parent().remove_child(panel)
		panel.queue_free()
	if button_insert_snippet:
		button_insert_snippet.queue_free()
	if text_editor and text_editor.gui_input.is_connected(_on_editor_input):
		text_editor.gui_input.disconnect(_on_editor_input)

func load_snippets() -> void:
	if FileAccess.file_exists(SNIPPET_FILE_PATH):
		var file := FileAccess.open(SNIPPET_FILE_PATH, FileAccess.READ)
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		file.close()

		if err == OK and typeof(json.data) == TYPE_ARRAY:
			var validated_array: Array[Dictionary] = []
			for item in json.data:
				if typeof(item) == TYPE_DICTIONARY:
					validated_array.append(item)
			snippet_list = validated_array
		else:
			push_error("Invalid JSON format in snippet file.")
			snippet_list = []
	else:
		# Create empty snippet file
		snippet_list = []
		save_snippets()  # Write empty list to file



func save_snippets() -> void:
	var file: FileAccess = FileAccess.open(SNIPPET_FILE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(snippet_list, "\t"))
	file.close()

func _show_snippet_panel() -> void:
	if panel:
		panel.visible = not panel.visible

func create_snippet_panel() -> VBoxContainer:
	var container: VBoxContainer = VBoxContainer.new()
	container.name = "Snippet Panel"
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	container.custom_minimum_size = Vector2(300, 300)
	container.position = Vector2(100, 100)

	var label: Label = Label.new()
	label.text = "Snippet Library"
	container.add_child(label)

	var list: ItemList = ItemList.new()
	list.name = "SnippetList"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for snippet in snippet_list:
		list.add_item(snippet["trigger"])
	list.item_selected.connect(_on_snippet_selected)
	container.add_child(list)

	var edit_trigger: LineEdit = LineEdit.new()
	edit_trigger.name = "TriggerEdit"
	edit_trigger.placeholder_text = "Trigger keyword"
	container.add_child(edit_trigger)

	var edit_body: TextEdit = TextEdit.new()
	edit_body.name = "BodyEdit"
	edit_body.placeholder_text = "Snippet body (use [1], [2]...)"
	edit_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit_body.custom_minimum_size = Vector2(0, 100)
	container.add_child(edit_body)

	var save_button: Button = Button.new()
	save_button.text = "Save Snippet"
	save_button.pressed.connect(_on_save_snippet)
	container.add_child(save_button)

	return container

func _on_snippet_selected(index: int) -> void:
	var snippet: Dictionary = snippet_list[index]
	if panel:
		panel.get_node("TriggerEdit").text = snippet["trigger"]
		var body_lines := snippet["body"] as Array
		panel.get_node("BodyEdit").text = "\n".join(body_lines) if (typeof(body_lines) == TYPE_ARRAY) else ""

		panel.get_node("BodyEdit").text = "\n".join(snippet["body"])

func _on_save_snippet() -> void:
	if not panel:
		return
	var trigger: String = panel.get_node("TriggerEdit").text
	var body: Array = panel.get_node("BodyEdit").text.split("\n").duplicate()
	var updated: bool = false
	for i in snippet_list.size():
		if snippet_list[i]["trigger"] == trigger:
			snippet_list[i]["body"] = body
			updated = true
			break
	if not updated:
		snippet_list.append({"trigger": trigger, "body": body})

	panel.get_node("SnippetList").clear()
	for snippet in snippet_list:
		panel.get_node("SnippetList").add_item(snippet["trigger"])

	save_snippets()

func get_current_word() -> String:
	if not text_editor:
		return ""
	var column: int = text_editor.get_caret_column()
	var line: int = text_editor.get_caret_line()
	var line_text: String = text_editor.get_line(line)
	#print("word: %s" % line_text)
	var words: PackedStringArray = line_text.substr(0, column).split(" ")
	return words[-1] if words.size() > 0 else ""
	
func insert_snippet(lines: Array) -> void:
	var insert_text := "\n".join(lines)
	
	# Entferne das Triggerwort vor dem Cursor
	var cursor_line := text_editor.get_caret_line()
	var cursor_column := text_editor.get_caret_column()
	var line_text := text_editor.get_line(cursor_line)
	var word_start := line_text.left(cursor_column).rfind(" ")
	if word_start == -1:
		word_start = 0
	else:
		word_start += 1  # nach dem Leerzeichen starten

	# Baue die neue Zeile
	var new_line := line_text.left(word_start) + insert_text + line_text.substr(cursor_column)
	text_editor.set_line(cursor_line, new_line)
	
	# Positioniere Caret direkt nach dem eingefügten Text (oder später durch Placeholder ersetzt)
	text_editor.set_caret_column(word_start + insert_text.length())
	
	# Suche nach Platzhaltern und springe
	find_placeholders()
	if current_placeholders.size() > 0:
		jump_to_next_placeholder()
	else:
		# Suche nach dem Sonderzeichen "|" für Cursor-Position
		var caret_pos := insert_text.find("|")
		if caret_pos >= 0:
			insert_text = insert_text.replace("|", "")
			text_editor.set_line(cursor_line, line_text.left(word_start) + insert_text + line_text.substr(cursor_column))
			text_editor.set_caret_column(word_start + caret_pos)



func find_placeholders(text: String, base_line: int) -> void:
	current_placeholders.clear()
	var regex := RegEx.new()
	regex.compile("\\$(\\d+)")
	var lines := text.split("\n")
	for line_offset in lines.size():
		var line := lines[line_offset]
		for result in regex.search_all(line):
			var index := int(result.get_string(1))
			if current_placeholders.size() < index:
				current_placeholders.resize(index)
			if current_placeholders[index - 1] == null:
				current_placeholders[index - 1] = {"positions": []}
			current_placeholders[index - 1]["positions"].append({
				"line": base_line + line_offset,
				"column": result.get_start()
			})
	placeholder_index = 0

func jump_to_placeholder(index: int) -> void:
	if not text_editor:
		return

	text_editor.remove_secondary_carets()
	if index >= current_placeholders.size():
		return

	var ph := current_placeholders[index]
	for i in range(ph["positions"].size()):
		var pos := ph["positions"][i]
		if i == 0:
			text_editor.set_caret_line(pos["line"])
			text_editor.set_caret_column(pos["column"])
		else:
			text_editor.add_caret(pos["line"], pos["column"])
	placeholder_index += 1

func _on_editor_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		if current_placeholders.size() > 0:
			jump_to_placeholder(placeholder_index)
		else:
			var word := get_current_word()
			for snippet in snippet_list:
				if word == snippet["trigger"]:
					insert_snippet(snippet["body"], word)
					break

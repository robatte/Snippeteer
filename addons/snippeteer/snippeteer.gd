@tool
extends EditorPlugin

## List of snippet definitions.
## Each dictionary should have "keyword" and "snippet" keys.
## Snippet format:
## - Placeholders: $1, $2, ... (up to $9)
## - Final cursor position after parameter editing: | (optional)

## Instance of SnippetManager class to manage configuration-gui, loading and saving of snippet library
var _snippet_manager_instance: SnippetManager = null

# --- State variables for active snippet ---
## True if a snippet is currently being edited by the user.
var _is_snippet_active: bool = false
## The CodeEdit node where the snippet is currently active.
var _active_code_edit: CodeEdit = null
## The original template string of the currently active snippet (e.g., "for i...$1...").
var _active_snippet_template: String = ""
## The line number (0-indexed) in the CodeEdit where the snippet content begins.
var _snippet_start_line: int = -1
## The column number (0-indexed) in the `_snippet_start_line` where the snippet content begins.
var _snippet_start_col: int = -1
## The current parameter number being targeted (1 for $1, 2 for $2, etc.).
var _current_param_num: int = 1
## Stores the counts of each parameter placeholder (e.g., {"$1": 2, "$2": 1}) found in the `_active_snippet_template`.
var _param_counts_in_template: Dictionary = {}
## True if the `_active_snippet_template` contained the `FINAL_CURSOR_MARKER` ('|').
var _template_has_final_cursor_marker: bool = false

## The character used to mark the final cursor position in a snippet template.
const FINAL_CURSOR_MARKER: String = "|"
## Tracks the CodeEdit node to which the `gui_input` signal is currently connected.
var _currently_connected_code_edit: CodeEdit = null

# --- Constants for debug messages (can be silenced by commenting out print_rich calls) ---
## Prefix for error messages in the output.
const ERROR_PREFIX: String = "[color=red][b]ERROR (SnippetPlugin):[/b][/color] "
## Prefix for warning messages in the output.
const WARN_PREFIX: String = "[color=yellow][b]WARNING (SnippetPlugin):[/b][/color] "
## Prefix for debug messages in the output.
const DEBUG_PREFIX: String = "[color=lightblue]DEBUG (SnippetPlugin):[/b][/color] "
## Global switch to enable/disable most debug messages. Set to false to silence.
var _debug_mode: bool = true


#region Godot EditorPlugin Lifecycle & Editor Connection
# =======================================================

## Called when the plugin is enabled. Sets up connections to the script editor.
func _enter_tree() -> void:
	_print_debug("_enter_tree called.")
	if EditorInterface == null: # EditorInterface is a global singleton
		_print_error("Global EditorInterface not found. Plugin will not function.")
		return

	var script_editor_main: ScriptEditor = EditorInterface.get_script_editor()
	if script_editor_main == null:
		_print_error("ScriptEditor (main) not found. Plugin will not function.")
		return

	script_editor_main.editor_script_changed.connect(_on_editor_script_changed)

	# Initial connection attempt for any script active when the plugin loads
	var current_script: Script = script_editor_main.get_current_script()
	if current_script != null:
		_on_editor_script_changed(current_script) # Pass the script to the handler
	else:
		_print_debug("No script initially active in editor.")

	# initialize script-manager
	_snippet_manager_instance = SnippetManager.new()
	_snippet_manager_instance.name = "GlobalSnippetManager"
	add_child(_snippet_manager_instance)
	_snippet_manager_instance.initialize()

	add_tool_menu_item("Snippets", Callable(self, "_on_show_snippet_manager_pressed"))
	_on_show_snippet_manager_pressed()

## Called when the plugin is disabled. Cleans up connections and state.
func _exit_tree() -> void:
	_print_debug("_exit_tree called.")
	if EditorInterface == null:
		return

	remove_tool_menu_item("Snippets")

	var script_editor_main: ScriptEditor = EditorInterface.get_script_editor()
	if script_editor_main != null and \
		script_editor_main.is_connected("editor_script_changed", Callable(self, "_on_editor_script_changed")):
		script_editor_main.editor_script_changed.disconnect(Callable(self, "_on_editor_script_changed"))

	_disconnect_from_gui_input(_currently_connected_code_edit)
	_reset_snippet_state()

	if is_instance_valid(_snippet_manager_instance):
		_snippet_manager_instance.cleanup()
	_snippet_manager_instance = null

## Disconnects the `gui_input` signal from the given CodeEdit node.
## Also clears the `_currently_connected_code_edit` tracker if it was this node.
## [param p_code_edit]: The CodeEdit node to disconnect from.
func _disconnect_from_gui_input(p_code_edit: CodeEdit) -> void:
	if is_instance_valid(p_code_edit):
		var callable_to_disconnect = Callable(self, "_on_code_edit_gui_input").bind(p_code_edit)
		if p_code_edit.gui_input.is_connected(callable_to_disconnect): # Check with bound callable
			p_code_edit.gui_input.disconnect(callable_to_disconnect)
			_print_debug("Disconnected gui_input from: " + str(p_code_edit))
	if _currently_connected_code_edit == p_code_edit:
		_currently_connected_code_edit = null


## Called when [Project -> Tools -> Snippets] menu-item is pressed
## will toggle snippet-manager visibility in inspector-dock
func _on_show_snippet_manager_pressed() -> void:
	if is_instance_valid(_snippet_manager_instance):
		_snippet_manager_instance.show_management_panel()
	else:
		print_rich(ERROR_PREFIX + "SnippetManager instance not available.")


## Called when the active script in the editor changes (e.g., tab switch, script open/close).
## Handles connecting to the CodeEdit of the newly active script.
## [param _script_resource_or_null]: The Script resource that became active.
##                                  This parameter is used to confirm the context if needed,
##                                  but primarily we get the current editor directly.
func _on_editor_script_changed(_script_resource_or_null: Script) -> void:
	_print_debug("_on_editor_script_changed")
	_disconnect_from_gui_input(_currently_connected_code_edit) # Disconnect from previous

	if EditorInterface == null: return
	var script_editor_main: ScriptEditor = EditorInterface.get_script_editor()
	if script_editor_main == null: return

	var current_script_editor_base: ScriptEditorBase = script_editor_main.get_current_editor()
	if current_script_editor_base == null:
		_print_debug("No current ScriptEditorBase found.")
		return

	if current_script_editor_base.has_method("get_base_editor"): # Check if it's a text-based editor
		var code_edit_instance: CodeEdit = current_script_editor_base.get_base_editor() as CodeEdit
		if code_edit_instance != null:
			_connect_to_gui_input(code_edit_instance) # Connect to the new one
		# else: _print_warn("get_base_editor() returned null.") # Reduced verbosity
	# else: _print_debug(str(current_script_editor_base.get_class()) + " does not have get_base_editor.") # Reduced

	if _is_snippet_active and _active_code_edit != _currently_connected_code_edit:
		_print_debug("Active CodeEdit changed while a snippet was active. Resetting.")
		_reset_snippet_state()

## Connects the `gui_input` signal of the given CodeEdit node to our handler `_on_code_edit_gui_input`.
## [param p_code_edit]: The CodeEdit node to connect to.
func _connect_to_gui_input(p_code_edit: CodeEdit) -> void:
	if not is_instance_valid(p_code_edit):
		_print_warn("Attempted to connect to an invalid CodeEdit instance.")
		return

	_currently_connected_code_edit = p_code_edit
	var callable_to_connect = Callable(self, "_on_code_edit_gui_input").bind(p_code_edit)

	if not p_code_edit.gui_input.is_connected(callable_to_connect): # Godot 4 style check
		var err_code = p_code_edit.gui_input.connect(callable_to_connect)
		if err_code == OK:
			_print_debug("Successfully connected gui_input for CE: " + str(p_code_edit))
		else:
			_print_error("Failed to connect gui_input for CE: " + str(p_code_edit) + ". Error: " + str(err_code))
	# else: _print_debug("gui_input already connected for CE: " + str(p_code_edit)) # Reduced verbosity

#endregion


#region GUI Input Handling & Snippet Activation Trigger
# =====================================================

## Handles GUI input events for the connected CodeEdit node.
## This is the main entry point for reacting to Tab and Escape key presses
## to trigger snippet activation or navigate within an active snippet.
## [param event]: The InputEvent received.
## [param p_code_edit_node]: The CodeEdit node that emitted the signal (passed via `Callable.bind`).
func _on_code_edit_gui_input(event: InputEvent, p_code_edit_node: CodeEdit) -> void:
	if not is_instance_valid(p_code_edit_node) or not p_code_edit_node.is_inside_tree():
		if _currently_connected_code_edit == p_code_edit_node: _disconnect_from_gui_input(p_code_edit_node)
		if _active_code_edit == p_code_edit_node: _reset_snippet_state()
		return
	if not p_code_edit_node.has_focus():
		return

	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.is_echo():
			var keycode: Key = key_event.keycode

			if keycode == KEY_TAB:
				if _is_snippet_active:
					if _active_code_edit == p_code_edit_node: # Correct editor for active snippet
						_handle_next_parameter_jump()
						p_code_edit_node.accept_event() # Consume Tab
					else: # Snippet active, but in a different editor instance
						_reset_snippet_state() # Reset old snippet state
						if _try_activate_snippet(p_code_edit_node): # Try new one in current editor
							p_code_edit_node.accept_event()
						# else: Tab passes through
				else: # No snippet active
					if _try_activate_snippet(p_code_edit_node):
						p_code_edit_node.accept_event()
					# else: Tab passes through

			elif keycode == KEY_ESCAPE:
				if _is_snippet_active and _active_code_edit == p_code_edit_node:
					_print_debug("Escape key pressed, cancelling active snippet.")
					_handle_snippet_completion_or_cancel(true) # true for cancel
					p_code_edit_node.accept_event() # Consume Escape

#endregion


#region Snippet Activation and Logic
# ===================================

## Attempts to activate a snippet based on the keyword found immediately to the left of the caret.
## If a matching keyword is found in `_snippet_list`, it initializes the snippet state,
## replaces the keyword in the CodeEdit with the snippet text, and calls `_handle_next_parameter_jump`
## to move the caret to the first parameter placeholder.
## [param p_code_edit]: The CodeEdit node where the snippet activation is attempted.
## [return]: `true` if a snippet was successfully activated, `false` otherwise.
func _try_activate_snippet(p_code_edit: CodeEdit) -> bool:
	if not is_instance_valid(p_code_edit):
		return false
	if not is_instance_valid(_snippet_manager_instance):
		print_rich(ERROR_PREFIX + "SnippetManager not available to get snippets.")
		return false

	var keyword_to_replace: String = _get_keyword_before_caret_workaround(p_code_edit)
	if keyword_to_replace.is_empty():
		return false

	for snippet_def in _snippet_manager_instance.snippet_list:
		if snippet_def["keyword"] == keyword_to_replace:
			_print_debug("TAS: Keyword matched: '" + snippet_def["keyword"] + "'") # TAS = TryActivateSnippet
			if not is_instance_valid(p_code_edit): return false

			_is_snippet_active = true
			_active_code_edit = p_code_edit
			_current_param_num = 1
			_active_snippet_template = snippet_def["snippet"]
			_template_has_final_cursor_marker = _active_snippet_template.contains(FINAL_CURSOR_MARKER)
			_count_placeholders_in_template()

			_print_debug("TAS: Placeholder counts: " + str(_param_counts_in_template) +
				", Has '|': " + str(_template_has_final_cursor_marker))

			p_code_edit.begin_complex_operation()
			_delete_keyword_and_set_snippet_start(p_code_edit, keyword_to_replace)
			p_code_edit.insert_text_at_caret(_active_snippet_template)
			_print_debug("TAS: Snippet text inserted.")
			p_code_edit.end_complex_operation()

			_handle_next_parameter_jump()
			return true

	return false

## Retrieves the "word" immediately to the left of the caret using a workaround.
## It temporarily moves the caret one position to the left, calls `CodeEdit.get_word_at_cursor()`,
## and then restores the caret's original position.
## [param p_code_edit]: The CodeEdit node to inspect.
## [return]: The identified keyword string, or an empty string if no word is found.
func _get_keyword_before_caret_workaround(p_code_edit: CodeEdit) -> String:
	var original_caret_column: int = p_code_edit.get_caret_column()
	var keyword: String = ""
	if original_caret_column > 0:
		p_code_edit.set_caret_column(original_caret_column - 1, false) # Temporarily move caret left
		keyword = p_code_edit.get_word_under_caret()
		p_code_edit.set_caret_column(original_caret_column, false) # Restore original caret position
	return keyword

## Analyzes the `_active_snippet_template` to count occurrences of each parameter placeholder ($1-$9).
## The results are stored in the `_param_counts_in_template` dictionary.
func _count_placeholders_in_template() -> void:
	_param_counts_in_template.clear()
	if _active_snippet_template.is_empty(): return

	for i in range(1, 10): # Iterate for $1 through $9
		var placeholder_str: String = "$" + str(i)
		# `String.count()` is suitable here as placeholders are distinct (e.g., "$1" won't overlap with "$2")
		var count: int = _active_snippet_template.count(placeholder_str)
		if count > 0:
			_param_counts_in_template[placeholder_str] = count

## Helper function called within `_try_activate_snippet`.
## It selects and deletes the `keyword` at the current caret position (assuming caret is after keyword)
## and then records the new caret position as the logical start (`_snippet_start_line`, `_snippet_start_col`)
## of the snippet content that will be inserted.
## [param p_code_edit]: The CodeEdit node.
## [param keyword]: The keyword string to delete.
func _delete_keyword_and_set_snippet_start(p_code_edit: CodeEdit, keyword: String) -> void:
	var line: int = p_code_edit.get_caret_line()
	var col: int = p_code_edit.get_caret_column() # Caret is currently positioned after the keyword

	# Select the keyword by moving backwards by its length
	p_code_edit.select(line, col - keyword.length(), line, col)
	p_code_edit.delete_selection()

	# After deletion, the caret is at the start of where the snippet will be inserted.
	# Record this position.
	_snippet_start_line = p_code_edit.get_caret_line()
	_snippet_start_col = p_code_edit.get_caret_column()
	_print_debug("TAS: Snippet content will start at L" + str(_snippet_start_line) + " C" + str(_snippet_start_col))

## Finds all occurrences of a given `placeholder_str` (e.g., "$1", "|") within the `p_code_edit`'s text.
## The search is restricted to the area at or after the logical start of the currently active snippet
## (`_snippet_start_line`, `_snippet_start_col`).
## [param p_code_edit]: The CodeEdit node to search within.
## [param placeholder_str]: The string to search for (e.g., "$1").
## [return]: An Array of Dictionaries, where each dictionary is `{"line": int, "col": int}`
##           representing a found occurrence.
func _find_all_placeholder_occurrences(p_code_edit: CodeEdit, placeholder_str: String) -> Array[Dictionary]:
	var occurrences: Array[Dictionary] = []
	if not is_instance_valid(p_code_edit) or placeholder_str.is_empty():
		return occurrences

	var line_count: int = p_code_edit.get_line_count()
	for current_line_idx in range(_snippet_start_line, line_count):
		var line_text: String = p_code_edit.get_line(current_line_idx)
		var search_col_in_line: int = 0

		if current_line_idx == _snippet_start_line: # For the first line of the snippet area
			search_col_in_line = _snippet_start_col # Start searching from the snippet's start column

		var scan_col_in_line: int = search_col_in_line
		while true:
			var found_col: int = line_text.find(placeholder_str, scan_col_in_line)
			if found_col == -1: # Not found in the rest of this line
				break

			# No Anti-$10 logic needed due to exact string find and param limit to $9
			occurrences.append({ "line": current_line_idx, "col": found_col })

			scan_col_in_line = found_col + placeholder_str.length() # Continue search in same line
			if scan_col_in_line >= line_text.length(): # Optimization: if scan starts at/beyond line end
				break
	return occurrences

#endregion


#region Parameter Navigation & Snippet Completion
# ===============================================

## Handles moving to the next parameter placeholder (e.g., $1, then $2) in an active snippet.
## Finds all occurrences of the current parameter, sets up primary and secondary carets,
## and selects the placeholder text at each caret. If no more parameters are found,
## it calls `_handle_snippet_completion_or_cancel`.
func _handle_next_parameter_jump() -> void:
	if not _is_snippet_active or not is_instance_valid(_active_code_edit):
		_reset_snippet_state()
		return

	if _current_param_num > 9: # Max 9 parameters ($1 to $9)
		_print_debug("HNPJ: Max parameter number (9) reached. Completing.") # HNPJ = HandleNextParameterJump
		_handle_snippet_completion_or_cancel(false) # false = normal completion
		return

	var placeholder_to_find: String = "$" + str(_current_param_num)
	_print_debug("HNPJ: Searching for parameter: " + placeholder_to_find)

	var all_found_positions: Array[Dictionary] = _find_all_placeholder_occurrences(_active_code_edit, placeholder_to_find)
	var expected_count: int = _param_counts_in_template.get(placeholder_to_find, 0)

	var positions_to_use: Array[Dictionary] = []
	if expected_count > 0 and not all_found_positions.is_empty():
		all_found_positions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a.line < b.line: return true; if a.line > b.line: return false
			return a.col < b.col )
		positions_to_use = all_found_positions.slice(0, expected_count)

	_print_debug("HNPJ: Found " + str(all_found_positions.size()) + " potential. Using " + str(positions_to_use.size()) +
		" (expected: " + str(expected_count) + ") for '" + placeholder_to_find + "'")

	if not is_instance_valid(_active_code_edit): _reset_snippet_state(); return

	_active_code_edit.begin_complex_operation()
	_active_code_edit.deselect()
	_clear_secondary_carets()

	if not positions_to_use.is_empty():
		_setup_carets_for_parameter(positions_to_use, placeholder_to_find)
		_current_param_num += 1
		_print_debug("HNPJ: Prepared for next parameter: $" + str(_current_param_num))
	else:
		_print_debug("HNPJ: No (more) valid occurrences of '" + placeholder_to_find + "'. Proceeding to completion.")
		_handle_snippet_completion_or_cancel(false)

	if is_instance_valid(_active_code_edit): _active_code_edit.end_complex_operation()
	# else: _print_error("HNPJ: Active CodeEdit became invalid.") # Already reset if invalid

## Helper for `_handle_next_parameter_jump`. Removes all but the primary caret.
func _clear_secondary_carets() -> void:
	if is_instance_valid(_active_code_edit):
		while _active_code_edit.get_caret_count() > 1:
			_active_code_edit.remove_caret(_active_code_edit.get_caret_count() - 1)

## Helper for `_handle_next_parameter_jump`.
## Sets up primary and secondary carets at the given `positions`
## and selects the `placeholder_text` at each caret.
## [param positions]: Array of `{"line": int, "col": int}` dictionaries.
## [param placeholder_text]: The string of the placeholder (e.g., "$1").
func _setup_carets_for_parameter(positions: Array[Dictionary], placeholder_text: String) -> void:
	if not is_instance_valid(_active_code_edit) or positions.is_empty():
		return

	var first_caret_set: bool = false
	# Assumes positions are sorted if multi-caret behavior needs to be top-to-bottom.
	# The `_find_all_placeholder_occurrences` combined with sort in `_handle_next_parameter_jump` ensures this.
	for pos_info in positions:
		var target_line: int = pos_info.line
		var target_col: int = pos_info.col
		if not first_caret_set:
			_active_code_edit.set_caret_line(target_line, true, false, -1, 0)
			_active_code_edit.set_caret_column(target_col, false, 0) # keep_selection=false
			first_caret_set = true
		else:
			_active_code_edit.add_caret(target_line, target_col)

	# Select the placeholder text at each caret position
	for i in range(_active_code_edit.get_caret_count()):
		var c_line: int = _active_code_edit.get_caret_line(i)
		var c_col: int = _active_code_edit.get_caret_column(i)
		_active_code_edit.select(c_line, c_col, c_line, c_col + placeholder_text.length(), i)

## Called when all parameters have been processed or when the snippet is cancelled.
## Moves the caret to the `FINAL_CURSOR_MARKER` ('|') if present in the original template
## and found in the current text. Otherwise, the caret remains at its current position.
## [param is_cancel]: `true` if the completion is due to a cancellation (e.g., Escape key).
func _handle_snippet_completion_or_cancel(is_cancel: bool) -> void:
	if not _is_snippet_active or not is_instance_valid(_active_code_edit):
		_reset_snippet_state()
		return

	var mode_text: String = "CANCEL" if is_cancel else "COMPLETE"
	_print_debug("HSCC: Handling snippet " + mode_text) # HSCC = HandleSnippetCompleteCancel

	if not is_instance_valid(_active_code_edit): _reset_snippet_state(); return

	_active_code_edit.begin_complex_operation()
	_active_code_edit.deselect()
	_clear_secondary_carets()

	if not is_cancel and _template_has_final_cursor_marker:
		_print_debug("HSCC: Template had final cursor marker ('|'). Searching for it...")
		var marker_positions: Array[Dictionary] = _find_all_placeholder_occurrences(_active_code_edit, FINAL_CURSOR_MARKER)

		if not marker_positions.is_empty():
			marker_positions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				if a.line < b.line: return true; if a.line > b.line: return false
				return a.col < b.col )
			var marker_info: Dictionary = marker_positions[0]
			var target_line: int = marker_info.line
			var target_col: int = marker_info.col

			_print_debug("HSCC: Final marker '|' found at L" + str(target_line) + " C" + str(target_col))
			_active_code_edit.set_caret_line(target_line, true, false, -1, 0)
			_active_code_edit.set_caret_column(target_col, false, 0)

			_active_code_edit.select(target_line, target_col, target_line, target_col + FINAL_CURSOR_MARKER.length())
			_active_code_edit.delete_selection()
			_print_debug("HSCC: Moved to final marker position and deleted the marker.")
		else:
			_print_debug("HSCC: Template had '|', but marker not found. Cursor remains.")
	elif is_cancel:
		_print_debug("HSCC: Snippet cancelled. Cursor remains where it was.")
	else: # Normal completion, no '|' in template
		_print_debug("HSCC: Template had no final cursor marker. Cursor remains (end of last edit).")

	if is_instance_valid(_active_code_edit):
		_active_code_edit.end_complex_operation()

	_reset_snippet_state()

#endregion


#region State Management & Utilities
# ==================================

## Resets all state variables related to an active snippet.
## Called when a snippet is completed, cancelled, or when context changes (e.g., editor switch).
## Also cleans up any remaining secondary carets in the previously active CodeEdit.
func _reset_snippet_state() -> void:
	var was_active_and_editor_valid: bool = _is_snippet_active and is_instance_valid(_active_code_edit)
	var editor_to_clean_up: CodeEdit = _active_code_edit

	_is_snippet_active = false
	_active_code_edit = null
	_active_snippet_template = ""
	_snippet_start_line = -1
	_snippet_start_col = -1
	_current_param_num = 1
	_param_counts_in_template.clear()
	_template_has_final_cursor_marker = false

	if was_active_and_editor_valid:
		editor_to_clean_up.deselect() # Deselect first
		# Then remove carets. Calling deselect might affect caret count or indices.
		while editor_to_clean_up.get_caret_count() > 1:
			editor_to_clean_up.remove_caret(editor_to_clean_up.get_caret_count() - 1)
	_print_debug("Snippet state reset.")

## Utility function for printing debug messages if `_debug_mode` is true.
## [param message]: The string message to print.
func _print_debug(message: String) -> void:
	if _debug_mode:
		print_rich(DEBUG_PREFIX + message)

## Utility function for printing warning messages, respecting `_debug_mode`.
## [param message]: The string message to print.
func _print_warn(message: String) -> void:
	if _debug_mode: # Or consider always printing warnings: `print_rich(WARN_PREFIX + message)`
		print_rich(WARN_PREFIX + message)

## Utility function for printing error messages. Errors are always printed.
## [param message]: The string message to print.
func _print_error(message: String) -> void:
	print_rich(ERROR_PREFIX + message) # Errors are generally always important

#endregion

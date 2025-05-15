# PlaceholderHighlighter.gd
@tool
extends SyntaxHighlighter

const BASE_PLACEHOLDER_COLOR: Color = Color.RED
# Maximum placeholder number to apply distinct lightening.
const MAX_PLACEHOLDER_NUM_FOR_SHADE: int = 9

# How much to lighten the color for each increment in placeholder number.
const LIGHTEN_STEP: float = +0.07

var placeholder_regex: RegEx

func _init() -> void:
	placeholder_regex = RegEx.new()
	var err: Error = placeholder_regex.compile("\\$(\\d+)")
	if err != OK:
		# Use printerr for plain error messages to console
		printerr("ERROR (PlaceholderHighlighter): Failed to compile RegEx. Error code: " + str(err))


func _get_line_syntax_highlighting(line_index: int) -> Dictionary: # Parameter umbenannt für Klarheit
	var result: Dictionary = {}
	var text_edit = get_text_edit()
	var line_text: String = text_edit.get_line(line_index)

	if line_text.is_empty():
		return result

	var default_font_color: Color = text_edit.get_theme_color(&"font_color")

	var matches: Array[RegExMatch] = placeholder_regex.search_all(line_text)
	var color_changes: Dictionary = {}

	for match in matches:
		var placeholder_full_match_start_col: int = match.get_start(0) # Start of "$N"
		var placeholder_full_match_end_col: int = match.get_end(0)     # End of "$N"

		# Get the captured number string (e.g., "1", "9", "12")
		var number_str: String = match.get_string(1)
		var placeholder_num: int = number_str.to_int() # Convert to integer

		var current_placeholder_color: Color = BASE_PLACEHOLDER_COLOR

		# Apply lightening based on the placeholder number
		if placeholder_num > 0 and placeholder_num <= MAX_PLACEHOLDER_NUM_FOR_SHADE:
			if placeholder_num > 1: # $1 uses base color
				print("hue: ", BASE_PLACEHOLDER_COLOR.h)
				current_placeholder_color = BASE_PLACEHOLDER_COLOR #.lightened(LIGHTEN_STEP * (placeholder_num - 1))
				current_placeholder_color.h += LIGHTEN_STEP * (placeholder_num - 1)
		elif placeholder_num > MAX_PLACEHOLDER_NUM_FOR_SHADE:
			# For placeholders beyond MAX_PLACEHOLDER_NUM_FOR_SHADE (e.g., $10, $11),
			# use the color of MAX_PLACEHOLDER_NUM_FOR_SHADE or a fixed fallback.
			current_placeholder_color = BASE_PLACEHOLDER_COLOR.lightened(LIGHTEN_STEP * (MAX_PLACEHOLDER_NUM_FOR_SHADE -1))

		color_changes[placeholder_full_match_start_col] = current_placeholder_color
		color_changes[placeholder_full_match_end_col] = default_font_color

	var sorted_columns: Array = color_changes.keys()
	sorted_columns.sort()

	for col in sorted_columns:
		result[col] = {"color": color_changes[col]}

	return result

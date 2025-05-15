@tool
extends TextEdit

const PLACEHOLDER_HIGHLIGHTER_SCRIPT_PATH: String = "res://addons/snippeteer/ui/placeholder_highlighter.gd"

func _ready() -> void:
	var highlighter_script: Script = load(PLACEHOLDER_HIGHLIGHTER_SCRIPT_PATH) as Script
	if Engine.is_editor_hint():
		if is_instance_valid(highlighter_script):
			var highlighter_instance: SyntaxHighlighter = highlighter_script.new() as SyntaxHighlighter
			self.syntax_highlighter = highlighter_instance
		else:
			print("ERROR (HighlightingTextEdit): PlaceholderHighlighter script FAILED to load from " + PLACEHOLDER_HIGHLIGHTER_SCRIPT_PATH)
